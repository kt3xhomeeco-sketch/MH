# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
receipts = []
[['deep', 598, true], ['shallow', 370, true], ['deep', 598, false]].each do |name, depth, auxiliary|
  analysis = JSON.parse(File.read(File.join(root, 'outputs', "recessed-trim-#{name}-response.json"), encoding: 'UTF-8')).dig('analyses', 0, 'products', 0)
  raise analysis['error'].to_s unless analysis['status'] == 'ready'
  app::SelectionSource.validate_watch(analysis['source_watch'], model) if analysis['source_watch']
  originals = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
  read = app::Settings.method(:read)
  settings = read.call
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('build_auxiliary' => auxiliary) }
  originals[:start_operation][0].call('CAD2Module: Kiểm Tra Nẹp Lùi Sau Cánh', true)
  begin
    originals.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
    assembly = app::Model.build(analysis, 'E:/MH_CAD2Module_QA/AI/tests/recessed-trims-native', app::Ids.uuid, model)
    groups = assembly.members
    raise 'Wrong independent solid group count' unless groups.length == (auxiliary ? 5 : 3) && groups.all? { |g| g.parent == model && g.is_a?(Sketchup::Group) && g.manifold? }
    actual = app::Model.state(assembly)
    raise 'Wrong module dimensions' unless actual['modules'].map { |p| p['size'].map { |v| v.round(3) } } == [800, 385, 700].map { |w| [w, depth, 1600] }
    if auxiliary
      raise 'Wrong return width or depth' unless actual['trim_parts'].all? { |p| p['size'].zip([50, depth, 1600]).all? { |a, b| (a - b).abs < 0.01 } }
    end
    first = groups.min_by { |g| g.bounds.min.x }
    expected = analysis['placement']['origin_mm'] + [analysis['placement']['plane_offset_mm']]
    expected[0] += analysis['modules'].first['origin'][0] unless auxiliary
    raise 'Wrong source position' unless first.bounds.min.to_a.map(&:to_mm).zip(expected).all? { |a, b| (a - b).abs < 0.01 }
    receipts << { source: name, auxiliary: auxiliary, solids: groups.length, source_position: true, native_preflight: analysis.dig('local_ai', 'native_preflight') }
  ensure
    app::Settings.define_singleton_method(:read, read)
    originals.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
    originals[:abort_operation][0].call
    model.selection.clear; model.selection.add(selection.select(&:valid?))
  end
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'QA registry leaked' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { passed: true, cases: receipts, user_geometry_unchanged: true }
app::Storage.write_json(File.join(root, 'outputs', 'recessed-trims-native-result.json'), result)
puts JSON.generate(result)
