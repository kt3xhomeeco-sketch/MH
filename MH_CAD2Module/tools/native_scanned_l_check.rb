# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
settings_read = app::Settings.method(:read)
settings_before = settings_read.call(model)
methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
methods[:start_operation][0].call('CAD2Module: Kiểm Tra Mặt Bằng L Đã Quét', true)
qa_root = File.join(root, 'outputs/scanned-l-native', app::Ids.uuid)
results = []
begin
  methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
  [true, false].each do |auxiliary|
    app::Settings.define_singleton_method(:read) { |m = Sketchup.active_model| settings_read.call(m).merge('build_auxiliary' => auxiliary) }
    product = JSON.parse(File.read(File.join(root, 'outputs/scan-l-fixed.json'), encoding: 'UTF-8'))
    product['code'] = auxiliary ? 'SCAN-QA-L-ON' : 'SCAN-QA-L-OFF'
    product['activity_id'] = app::Ids.uuid
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    built = app::Model.build(product, qa_root, app::Ids.uuid, model)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    state = app::Model.state(built)
    raise 'Wrong module count' unless state['modules'].length == 7
    raise 'Auxiliary toggle ignored' unless state['trim_parts'].length == (auxiliary ? 4 : 0)
    raise 'Non-solid output' unless built.members.all?(&:manifold?)
    raise 'Missing native preflight' unless JSON.parse(built.get_attribute(app::Model::DICT, 'analysis')).dig('geometry_check', 'passed')
    expected = (3_005_548 + (auxiliary ? 43_092 : 0)) * 1600
    volume = built.members.sum { |part| part.volume * 25.4**3 }
    raise 'Filled empty L corner or changed dimensions' unless (volume - expected).abs < expected * 0.00001
    results << { auxiliary: auxiliary, modules: state['modules'].length, trims: state['trim_parts'].length,
                 volume_mm3: volume, native_seconds: elapsed }
  end
ensure
  app::Settings.define_singleton_method(:read, settings_read)
  methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
  methods[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
raise 'Settings changed' unless settings_before == settings_read.call(model)
result = { passed: true, products: results, user_geometry_registry_settings_restored: true }
app::Storage.write_json(File.join(root, 'outputs/scanned-l-native-result.json'), result)
puts JSON.generate(result)
