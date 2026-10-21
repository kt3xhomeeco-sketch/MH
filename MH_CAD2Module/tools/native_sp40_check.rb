# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wait for current work' if app::Jobs.busy? || app::Corrections.active? || model.active_path
product = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'sp40-repaired-product.json'), encoding: 'UTF-8'))
raise 'Unexpected SP40 result' unless product['status'] == 'ready' && product['modules'].map { |m| m['size'] } == [[1072, 170, 1600], [300, 170, 1600], [982, 170, 1600]]
raise 'Repeated auxiliary subloops' unless product['trim_parts'].length == 2
product['code'] = 'NATIVE-SP40-CHECK'
product['automatic_scan'] = false
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
originals = %i[start_operation commit_operation abort_operation].to_h do |name|
  [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]]
end
originals[:start_operation][0].call('CAD2Module: Kiểm Tra SP40', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  built = app::Model.build(product, File.join(app::Settings::ROOT, 'outputs', 'v'), app::Ids.uuid, model)
  state = app::Model.state(built)
  %w[modules trim_parts].each do |kind|
    raise 'Part count changed' unless state[kind].length == product[kind].length
    state[kind].each do |part|
      expected = product[kind].find { |p| p['id'] == part['id'] }
      raise 'Dimensions/positions changed' unless %w[origin size].all? { |field| part[field].zip(expected[field]).all? { |a, b| (a - b).abs < 0.01 } }
    end
  end
  parts = state['modules'] + state['trim_parts']
  raise 'Overlapping native proxies' if parts.combination(2).any? { |a, b| app::Placement.overlap?(a, b) }
  expected_origin = product['placement']['origin_mm'] + [0]
  raise 'Source origin moved' unless built.transformation.origin.to_a.map(&:to_mm).zip(expected_origin).all? { |a, b| (a - b).abs < 0.01 }
ensure
  originals.each do |name, (method, owned)|
    owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name)
  end
  originals[:abort_operation][0].call
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
result = { 'status' => 'passed', 'modules_mm' => product['modules'].map { |m| m['size'] },
           'auxiliary' => 2, 'overlaps' => false, 'source_placement_verified' => true, 'original_geometry_unchanged' => true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp40-native-result.json'), result)
puts JSON.generate(result)
