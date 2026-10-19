# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'placement.rb')
app.instance_variable_get(:@manager)&.close
dialog = app.make_dialog('MH CAD2Module — Quản lý', 'manager.html', 1100, 780, 'manager')
dialog.add_action_callback('qa_search_ui') do |_context, text|
  app::Storage.write_json(File.join(root, 'outputs', 'ai-search-live-ui.json'), JSON.parse(text))
end
app.instance_variable_set(:@manager, dialog)
dialog.show
read = app::Settings.method(:read)
settings = read.call
qa_root = 'E:/MH_CAD2Module_QA/AI/tests/search-v2-smoke'
app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa_root) }
begin
  values = JSON.parse(File.read(File.join(root, 'outputs', 'ai-search-job-fixture.json'), encoding: 'UTF-8'))
  app::Jobs.start('geometry', values) do |result, job|
    analysis = result.dig('analyses', 0, 'products', 0)
    receipt = { 'ok' => result['ok'], 'error' => result['error'], 'status' => analysis && analysis['status'],
      'local_ai' => analysis && analysis['local_ai'], 'sizes' => analysis && analysis['modules'].map { |p| p['size'] },
      'progress_seen' => job[:progress_seen], 'worker_seconds' => Time.now - job[:started] }
    begin
      unless result['ok'] && analysis['status'] == 'ready' && analysis.dig('local_ai', 'status') == 'choose'
        raise 'AI worker did not complete both search and decision'
      end
      baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
      registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
      selection = model.selection.to_a
      originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
      originals[:start_operation][0].call('CAD2Module: Kiểm Tra Quét AI Qua Worker', true)
      begin
        originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
        product = app::Model.build(analysis, qa_root, app::Ids.uuid, model)
        raise 'Expected two independent solids' unless product.members.length == 2 && product.members.all? { |g| g.is_a?(Sketchup::Group) && g.manifold? }
        state = app::Model.state(product)['modules'].sort_by { |p| p['origin'][0] }
        state.zip([[1110, 705, 1600], [450, 705, 1600]]).each do |part, expected|
          raise 'Native sizes changed' unless part['size'].zip(expected).all? { |a, b| (a - b).abs < 0.01 }
        end
        first = product.members.min_by { |g| g.bounds.min.x }
        raise 'Native source placement changed' unless first.bounds.min.to_a.map(&:to_mm).zip([30_000, 40_000, 73]).all? { |a, b| (a - b).abs < 0.01 }
        receipt['native_preflight'] = analysis.dig('local_ai', 'native_preflight')
      ensure
        originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
        originals[:abort_operation][0].call
        model.selection.clear; model.selection.add(selection.select(&:valid?))
      end
      raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
      raise 'Temporary metadata leaked' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
      receipt['native_passed'] = true
      receipt['user_geometry_unchanged'] = true
      app.publish('Đã kiểm tra AI tìm mẫu → app đánh giá → AI quyết định → dựng. Sẵn sàng Quét chọn.')
    rescue StandardError => error
      receipt['error'] = error.message
      app.publish("Kiểm tra AI chưa qua: #{error.message}")
    ensure
      app::Storage.write_json(File.join(root, 'outputs', 'ai-search-native-job.json'), receipt)
      dialog.execute_script("window.sketchup.qa_search_ui(JSON.stringify({enabled:document.querySelector('#ai-enabled').checked,label:document.querySelector('#ai-enabled').parentElement.textContent,status:document.querySelector('#status').textContent,rows:document.querySelectorAll('.activity-row').length,overflow:document.body.scrollWidth>innerWidth+1}));")
    end
  end
ensure
  app::Settings.define_singleton_method(:read, read)
end
puts 'Native AI search/decision/construction worker test queued; live settings restored.'
