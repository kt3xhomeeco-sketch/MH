# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
%w[cad_views.rb plan_reference.rb].each { |name| load File.join(root, name) }
app.send(:remove_const, :VERSION); app.const_set(:VERSION, '0.20.1')
app::Jobs.stop_worker
app.entry
dialog = app.instance_variable_get(:@entry)
receive_result = lambda do |text|
  result = JSON.parse(text)
  result['user_geometry_registry_preserved'] = baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
  result['version'] = app::VERSION
  app::Storage.write_json(File.join(root, 'outputs/sp20-entry-live-result.json'), result)
end
reload_entry = lambda do |text|
  values = JSON.parse(text)
  dialog.set_file(File.join(root, 'ui/entry.html'))
  UI.start_timer(0.7, false) do
    state = JSON.generate(app.entry_state)
    dialog.execute_script(<<~JS)
      (() => {
        const bridge = window.sketchup.request, sent = [], state = #{state}, saved = #{JSON.generate(values)};
        const start = document.getElementById('product-input'), end = document.getElementById('product-end');
        const result = {passed:false};
        window.sketchup.request = raw => sent.push(JSON.parse(raw));
        try {
          receive({...state,busy:false,correction:null}); start.value='20';end.value='';
          start.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true}));
          if (sent.length !== 1 || sent[0].action !== 'build' || sent[0].products !== 'SP20') throw Error('Native Enter did not build');
          receive({...state,busy:true,correction:null});
          end.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true}));
          receive({...state,busy:false,correction:{manual:true,id:'QA'}});
          document.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true}));
          receive({...state,busy:false,correction:null});
          document.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',repeat:true,bubbles:true,cancelable:true}));
          if(sent.length !== 1) throw Error('Native Enter sent blocked/repeated build');
          result.passed=true;result.enter_builds=true;result.blocked_builds_rejected=true;result.build_requests_dispatched_to_worker=0;
        } catch(error) {result.error=error.message;}
        finally {receive(state);start.value=saved.start;end.value=saved.end;window.sketchup.request=bridge;}
        window.sketchup.request(JSON.stringify({action:'qa_entry_keys_result',result}));
      })();
    JS
  end
end
normal = lambda do
  dialog.add_action_callback('request') do |_context, raw|
    packet = JSON.parse(raw)
    packet['action'] == 'ready' ? app.publish(nil, target: dialog) : app.dispatch(packet)
  rescue StandardError => error
    app.report_error(error.message, activity_key: packet && packet['activity_key'])
  end
end
dialog.add_action_callback('request') do |_context, raw|
  packet = JSON.parse(raw)
  case packet['action']
  when 'qa_entry_reload' then reload_entry.call(JSON.generate(packet['values']))
  when 'qa_entry_keys_result'
    receive_result.call(JSON.generate(packet['result'])); normal.call
  when 'ready' then app.publish(nil, target: dialog)
  else app.dispatch(packet)
  end
end
dialog.execute_script("window.sketchup.request(JSON.stringify({action:'qa_entry_reload',values:{start:document.getElementById('product-input').value,end:document.getElementById('product-end').value}}));")
manager = app.instance_variable_get(:@manager)
manager.set_file(File.join(root, 'ui/manager.html')) if manager&.visible?
puts '0.20.1 loaded; native Enter check queued without dispatching a build.'
