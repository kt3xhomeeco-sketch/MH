# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'placement.rb')
app::Model.send(:remove_const, :DICT)
load File.join(root, 'model.rb')
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
methods[:start_operation][0].call('CAD2Module: Kiểm Tra Mặt Cắt Đứng', true)
qa_root = File.join(root, 'outputs/elevation-native', app::Ids.uuid)
results = []
begin
  methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
  %w[measured provisional floor].each do |name|
    product = JSON.parse(File.read(File.join(root, "outputs/elevation-#{name}.json"), encoding: 'UTF-8'))
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    built = app::Model.build(product, qa_root, app::Ids.uuid, model)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    raise 'Expected module count changed' unless built.members.length == (name == 'provisional' ? 2 : 4)
    raise 'Non-solid directional module' unless built.members.all?(&:manifold?)
    raise 'Preflight not run' unless JSON.parse(built.get_attribute(app::Model::DICT, 'analysis')).dig('geometry_check', 'passed')
    state = app::Model.state(built)
    expected_z = { 'measured' => [0, 1000, 0, 1200], 'provisional' => [0, 0], 'floor' => [50, 1050, 50, 1250] }.fetch(name)
    raise 'Section height/placement lost' unless state['modules'].map { |part| part['origin'][2].round } == expected_z
    volume = built.members.sum { |part| part.volume * 25.4**3 }
    expected = 1618 * 600 * (name == 'provisional' ? 1600 : 2400)
    raise 'Footprint filled an empty corner or lost geometry' unless (volume - expected).abs < expected * 0.00001
    results << { name: name, modules: built.members.length, volume_mm3: volume, native_seconds: elapsed, z_positions_preserved: true }
  end
ensure
  methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
  methods[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { passed: true, products: results, user_geometry_registry_restored: true }
app::Storage.write_json(File.join(root, 'outputs/elevation-native-result.json'), result)
puts JSON.generate(result)
