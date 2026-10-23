# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
raise 'Wrong user model' unless model.path.tr('\\', '/') == 'E:/MAC/OneDrive/Desktop/Untitled1.skp'
root = app::Settings::ROOT
plan = model.find_entity_by_persistent_id(456025)
raise 'User plan changed' unless app::Model.container?(plan) && plan.parent == model
load File.join(root, 'jobs.rb')
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
read = app::Settings.method(:read)
settings = read.call(model)
sha = Digest::SHA256.file(model.path).hexdigest
qa_root = File.join(root, 'outputs/qau')
rows = []
queue = nil
queue = lambda do |combined|
  app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| read.call(m).merge('library' => qa_root) }
  begin
    model.selection.clear; model.selection.add(plan)
    geometry = app::SelectionSource.capture(model, include_views: combined)
    model.selection.clear; model.selection.add(selection.select(&:valid?))
    values = app::SelectionSource.build_request(geometry).merge('build_elevation' => combined)
    app::Jobs.start('geometry', values) do |result, job|
      begin
        p = result.dig('analyses', 0, 'products', 0)
        raise result['error'].to_s unless result['ok'] && p && p['status'] == 'ready'
        raise 'L partition changed' unless p['modules'].length == 7 && p['trim_parts'].length == 4
        raise 'Changed source position' unless p.dig('placement', 'origin_mm') == [0, 0]
        raise 'Invented measured heights' unless p['modules'].all? { |part| part['size'][2] == 1600 }
        app::SelectionSource.validate_watch(p['source_watch'], model)
        if combined
          raise 'Missing explicit pending-height reason' unless p['elevation_pending'] && !p.dig('geometry_pipeline', 'horizontal', 'issues').empty?
          methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
          methods[:start_operation][0].call('CAD2Module: Kiểm Tra Quét L Hai Chế Độ', true)
          begin
            methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
            built = app::Model.build(p, qa_root, job[:id], model)
            raise 'Native provisional output not solid' unless built.members.length == 11 && built.members.all?(&:manifold?)
            raise 'Changed volume' unless (built.members.sum { |part| part.volume * 25.4**3 } - 4_877_824_000).abs < 1
          ensure
            methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
            methods[:abort_operation][0].call
            model.selection.clear; model.selection.add(selection.select(&:valid?))
          end
          app::Storage.write_json(File.join(root, 'outputs/scan-elevation-user-plan.json'), p)
        end
        rows << { combined: combined, edges: geometry['lines'].length, capture_seconds: geometry['capture_seconds'],
                  worker: result['worker'], modules: 7, auxiliary: 4, provisional_height_mm: 1600,
                  scan_capture: p['scan_capture'], processing: p['processing_times'] }
        if !combined
          queue.call(true)
        else
          raise 'Geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
          raise 'Registry/settings changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && settings == read.call(model)
          raise 'File changed' unless sha == Digest::SHA256.file(model.path).hexdigest
          app::Storage.write_json(File.join(root, 'outputs/scan-elevation-user-result.json'), passed: true, jobs: rows, actual_native_solids: true,
                                 user_geometry_selection_settings_registry_file_preserved: true)
        end
      rescue StandardError => error
        app::Storage.write_json(File.join(root, 'outputs/scan-elevation-user-result.json'), passed: false, jobs: rows, error: error.message)
      end
    end
  ensure
    app::Settings.define_singleton_method(:read, read)
    model.selection.clear; model.selection.add(selection.select(&:valid?))
  end
end
queue.call(false)
puts 'Actual Untitled1 plan-only/combined regression queued; no persistent test build.'
