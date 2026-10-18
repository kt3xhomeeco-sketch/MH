# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wait for current work' if app::Jobs.busy? || app::Corrections.active? || model.active_path
product = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'plan-feedback-replayed-product.json'), encoding: 'UTF-8'))
raise 'Feedback not applied' unless product.dig('learning', 'mode') == 'plan_exact'
product['code'] = 'NATIVE-FEEDBACK-VERIFY'
product['automatic_scan'] = false # Temporary fixture bypasses the live duplicate guard.
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
originals = %i[start_operation commit_operation abort_operation].to_h do |name|
  [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]]
end
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Mẫu', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  built = app::Model.build(product, File.join(app::Settings::ROOT, 'outputs', 'v'), app::Ids.uuid, model)
  parts = built.definition.entities.select { |e| app::Model.container?(e) && %w[module trim_reference].include?(e.get_attribute(app::Model::DICT, 'role')) }
  raise 'Missing rebuilt parts' unless parts.length == 3
  actual = parts.map do |e|
    bounds = Geom::BoundingBox.new
    8.times { |i| bounds.add(e.definition.bounds.corner(i).transform(built.transformation * e.transformation)) }
    bounds.min.to_a.map(&:to_mm) + bounds.max.to_a.map(&:to_mm)
  end.sort
  inputs = [973425, 973480, 973508].map { |id| model.find_entity_by_persistent_id(id) }
  expected = inputs.map { |e| e.bounds.min.to_a.map(&:to_mm) + e.bounds.max.to_a.map(&:to_mm) }.sort
  raise 'Rebuild differs from user boxes' unless actual.zip(expected).all? { |a, b| a.zip(b).all? { |x, y| (x - y).abs < 0.1 } }
  result = { 'status' => 'passed', 'learning_mode' => 'plan_exact', 'experience' => product['experience']['event'],
             'rebuilt_boxes' => 3, 'matches_user_dimensions_and_world_position' => true }
ensure
  originals.each do |name, (method, owned)|
    owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name)
  end
  originals[:abort_operation][0].call
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
result['temporary_geometry_removed'] = true
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'plan-feedback-native-rebuild.json'), result)
puts JSON.generate(result)
