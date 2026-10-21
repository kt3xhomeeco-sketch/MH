# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong source model' unless model.path.tr('\\', '/') == 'E:/MAC/OneDrive/Desktop/Untitled1.skp'
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'jobs.rb')
plan = model.find_entity_by_persistent_id(456025)
raise 'Copied plan changed' unless app::Model.container?(plan) && plan.parent == model && plan.bounds.depth.to_mm.abs < 0.1
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest
settings_read = app::Settings.method(:read)
settings = settings_read.call(model)
qa_root = File.join(root, 'outputs/qa1')
app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| settings_read.call(m).merge('library' => qa_root) }
begin
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  model.selection.clear
  model.selection.add(plan)
  geometry = app::SelectionSource.capture(model)
  capture_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
ensure
  app::Settings.define_singleton_method(:read, settings_read)
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'Expected XY plan' unless geometry['plane'] == 'XY'
values = app::SelectionSource.build_request(geometry).merge('code' => 'SCAN-QA-UNTITLED1', 'build_plan' => true, 'build_elevation' => false)
app::Storage.write_json(File.join(root, 'outputs/untitled1-plan-request.json'), values)
rows = []
queue = nil
queue = lambda do |index|
  app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| settings_read.call(m).merge('library' => qa_root) }
  begin
    app::Jobs.start('geometry', values) do |result, job|
      begin
        product = result.dig('analyses', 0, 'products', 0)
        raise result['error'].to_s unless result['ok'] && product && product['status'] == 'ready'
        raise 'Wrong recovered parts' unless product['modules'].length == 7 && product['trim_parts'].length == 4
        app::SelectionSource.validate_watch(product['source_watch'], model)
        rows << { worker: result['worker'], processing: product['processing_times'], modules: 7, auxiliary: 4 }
        if index.zero?
          queue.call(1)
        else
          raise 'Worker PID changed' unless rows.map { |r| r[:worker]['pid'] }.uniq.length == 1
          app::Storage.write_json(File.join(root, 'outputs/untitled1-plan-product.json'), product)
          native = []
          methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
          methods[:start_operation][0].call('CAD2Module: Kiểm Tra Mặt Bằng Untitled1', true)
          begin
            methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
            [true, false].each do |auxiliary|
              app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| settings_read.call(m).merge('build_auxiliary' => auxiliary) }
              data = JSON.parse(JSON.generate(product))
              data['code'] = "QA-U1-#{auxiliary}"
              data['activity_id'] = app::Ids.uuid
              start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              built = app::Model.build(data, qa_root, job[:id], model)
              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
              state = app::Model.state(built)
              raise 'Wrong native module/trim count' unless state['modules'].length == 7 && state['trim_parts'].length == (auxiliary ? 4 : 0)
              raise 'Non-solid output' unless built.members.all?(&:manifold?)
              saved = JSON.parse(built.get_attribute(app::Model::DICT, 'analysis'))
              raise 'Native measured source preflight failed' unless saved.dig('geometry_check', 'passed')
              expected = (3_005_548 + (auxiliary ? 43_092 : 0)) * 1600
              volume = built.members.sum { |part| part.volume * 25.4**3 }
              raise 'Filled empty L or changed measured dimensions' unless (volume - expected).abs < expected * 0.00001
              native << { auxiliary: auxiliary, modules: 7, trims: auxiliary ? 4 : 0, seconds: elapsed, volume_mm3: volume, source_preflight: true }
            end
          ensure
            app::Settings.define_singleton_method(:read, settings_read)
            methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
            methods[:abort_operation][0].call
            model.selection.clear
            model.selection.add(selection.select(&:valid?))
          end
          raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
          raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
          raise 'Settings changed' unless settings == settings_read.call(model)
          raise 'Source file changed' unless sha == Digest::SHA256.file(model.path).hexdigest
          receipt = { passed: true, path: model.path, source_entity: plan.persistent_id, edges: geometry['lines'].length,
                      source_hash: geometry['hash'], source_file_sha256: sha, capture_seconds: capture_seconds,
                      jobs: rows, native: native, file_geometry_selection_registry_settings_preserved: true,
                      unsaved_copied_plan_preserved: true, source_watch_validated: true }
          app::Storage.write_json(File.join(root, 'outputs/untitled1-plan-result.json'), receipt)
        end
      rescue StandardError => error
        app::Storage.write_json(File.join(root, 'outputs/untitled1-plan-result.json'), passed: false, jobs: rows, error: error.message)
      end
    end
  ensure
    app::Settings.define_singleton_method(:read, settings_read)
  end
end
queue.call(0)
puts JSON.generate({ queued: true, model: model.path, plan_entity: plan.persistent_id, edges: geometry['lines'].length, capture_seconds: capture_seconds })
