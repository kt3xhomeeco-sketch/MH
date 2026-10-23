# frozen_string_literal: true

# Measure real CEF opening/painting and state reads; no user model writes.
app = MH::CAD2Module
raise 'App busy/correcting' if app::Jobs.busy? || app::Corrections.active?
raise 'Close entry before QA' if app.instance_variable_get(:@entry)
originals = %i[make_dialog public_state entry_state].to_h { |name| [name, app.method(name)] }
owned = app.singleton_class.instance_methods(false)
dialogs = []
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
results = { 'manager_reads' => 0, 'entry_reads' => 0, 'events' => [] }
opened = {}
restored = false
restore = lambda do
  next if restored
  restored = true
  originals.each { |name, method| owned.include?(name) ? app.define_singleton_method(name, method) : app.singleton_class.send(:remove_method, name) }
  dialogs.each { |dialog| dialog.singleton_class.send(:remove_method, :execute_script) }
end
app.define_singleton_method(:public_state) do
  started = clock.call
  results['manager_reads'] += 1
  state = originals[:public_state].call
  results['manager_state_seconds'] = clock.call - started
  state
end
app.define_singleton_method(:entry_state) do
  results['entry_reads'] += 1
  originals[:entry_state].call
end
app.define_singleton_method(:make_dialog) do |*args|
  dialog = originals[:make_dialog].call(*args)
  dialogs << dialog
  key = args.last
  execute = dialog.method(:execute_script)
  dialog.define_singleton_method(:execute_script) do |script|
    execute.call("(()=>{const t=performance.now();#{script};requestAnimationFrame(()=>requestAnimationFrame(()=>window.sketchup.qa_open(JSON.stringify({render_ms:performance.now()-t,rows:document.querySelectorAll('.activity-row').length,message:document.querySelector('#message')?.textContent,overflow:document.body.scrollWidth>innerWidth+1}))));})();")
  end
  dialog.add_action_callback('qa_open') do |_context, raw|
    next if results['events'].any? { |item| item['dialog'] == key }
    results['events'] << JSON.parse(raw).merge('dialog' => key, 'open_to_paint_seconds' => clock.call - opened.fetch(key))
    if key == 'manager'
      opened['entry'] = clock.call
      app.entry
    else
      dialog.close
      restore.call
      results['passed'] = results['manager_reads'] == 1 && results['entry_reads'] == 1 && results['events'].none? { |e| e['overflow'] }
      app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs/dialog-open-native-result.json'), results)
      puts JSON.generate(results)
    end
  end
  dialog
end
app.instance_variable_get(:@manager)&.close
opened['manager'] = clock.call
app.manager
UI.start_timer(15, false) do
  unless restored
    restore.call
    results['error'] = 'Dialog QA timed out'
    app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs/dialog-open-native-result.json'), results)
  end
end
puts 'Opening manager and entry; receipt follows after native paint.'
