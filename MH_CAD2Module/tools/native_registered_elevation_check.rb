# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'registered_elevation.rb')
load File.join(root, 'placement.rb')
source = model.find_entity_by_persistent_id(483528)
raise 'Wrong source' unless model.path.tr('\\', '/') == 'E:/MAC/OneDrive/Desktop/Untitled1.skp' && app::Model.container?(source) && source.parent == model
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
read = app::Settings.method(:read); settings = read.call(model)
sha = Digest::SHA256.file(model.path).hexdigest
qa_root = File.join(root, 'outputs/qar')
context = JSON.parse(File.read(File.join(root, 'outputs/registered-source-context.json'), encoding: 'UTF-8'))
app::Storage.write_json(File.join(qa_root, 'source_context', context['source_signature'] + '.json'), context)
app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| read.call(m).merge('library' => qa_root) }
begin
  model.selection.clear; model.selection.add(source)
  geometry = app::SelectionSource.capture(model, include_views: true)
  values = app::SelectionSource.build_request(geometry).merge('build_elevation' => true)
  app::Storage.write_json(File.join(root, 'outputs/registered-native-request.json'), values)
  app::Jobs.start('geometry', values) do |result, job|
    begin
      p = result.dig('analyses', 0, 'products', 0)
      raise result['error'].to_s unless result['ok'] && p && p['status'] == 'ready' && !p['envelope_preview']
      raise 'Wrong measured registered tiers' unless p['modules'].map { |m| m['size'] } == [[970, 520, 642], [970, 520, 2008], [485, 520, 642], [485, 520, 2008]] && p['trim_parts'].length == 3 && p['elevation_pending'] == false
      raise 'Wrong measured levels' unless p['modules'].map { |m| m['origin'][2] } == [50, 692, 50, 692]
      trim = p['trim_parts'].last
      raise 'Missing confirmed single trim' unless trim['size'].last(2) == [50, 30] && trim.dig('elevation_evidence', 'section_parts').length == 2
      app::SelectionSource.validate_watch(p['source_watch'], model)
      methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
      methods[:start_operation][0].call('CAD2Module: Kiểm Tra Ghép Mặt Đứng Thực', true)
      rows = []
      begin
        methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
        [true, false].each do |auxiliary|
          app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| read.call(m).merge('build_auxiliary' => auxiliary) }
          data = JSON.parse(JSON.generate(p)); data['code'] = "QA-REGISTERED-#{auxiliary}"; data['activity_id'] = app::Ids.uuid
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          built = app::Model.build(data, qa_root, job[:id], model)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          raise 'Not solid' unless built.members.length == (auxiliary ? 7 : 4) && built.members.all?(&:manifold?)
          expected = 1455 * 520 * 2650 + (auxiliary ? 2 * 18 * 600 * 2700 + 1491 * 50 * 30 : 0)
          volume = built.members.sum { |part| part.volume * 25.4**3 }
          raise 'Wrong native volume/depth' unless (volume - expected).abs < 1
          rows << { auxiliary: auxiliary, modules: 4, auxiliary_parts: auxiliary ? 3 : 0, seconds: elapsed, volume_mm3: volume }
        end
      ensure
        app::Settings.define_singleton_method(:read, read)
        methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
        methods[:abort_operation][0].call
        model.selection.clear; model.selection.add(selection.select(&:valid?))
      end
      raise 'Model changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
      raise 'Registry/settings changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && settings == read.call(model)
      raise 'File changed' unless sha == Digest::SHA256.file(model.path).hexdigest
      app::Storage.write_json(File.join(root, 'outputs/registered-native-product.json'), p)
      app::Storage.write_json(File.join(root, 'outputs/registered-native-result.json'), passed: true, path: model.path, source_entity: source.persistent_id,
                             edges: geometry['lines'].length, capture_seconds: geometry['capture_seconds'], worker: result['worker'],
                             native: rows, source_placement: p['placement'], user_geometry_selection_registry_settings_file_preserved: true)
    rescue StandardError => error
      app::Storage.write_json(File.join(root, 'outputs/registered-native-result.json'), passed: false, error: error.message)
    end
  end
ensure
  app::Settings.define_singleton_method(:read, read)
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
puts 'Actual current CAD source queued; temporary native builds will be aborted.'
