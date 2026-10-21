# frozen_string_literal: true

# Development check: temporary geometry only; no product, history or model save.
require 'json'
plugin = File.expand_path('..', __dir__)
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Exit editing before native learning check' if model.active_path
raise 'Finish the running job/correction first' if app::Jobs.busy? || app::Corrections.active?
product = JSON.parse(File.read(File.join(plugin, 'outputs', 'learning-native-product.json'), encoding: 'UTF-8'))
raise 'Expected a transferred example' unless product.dig('learning', 'mode') == 'similar'
baseline = model.entities.select { |e| app::Model.container?(e) }.map do |e|
  [e.persistent_id, e.transformation.to_a, e.name, e.bounds.min.to_a, e.bounds.max.to_a]
end
all_ids = model.entities.map(&:persistent_id).sort
labels = app::Model.labels(model)
selection = model.selection.to_a
parts = product['modules'] + product['panel_parts']
begin
  model.start_operation('CAD2Module: kiểm tra suy rộng bằng khối tạm', true)
  operation = true
  group = model.entities.add_group
  product['modules'].each { |part| app::Model.module_instance(group.entities, part) }
  product['panel_parts'].each { |part| app::Model.panel_part(group.entities, part) }
  group.set_attribute(app::Model::DICT, 'analysis', JSON.generate(product))
  centre = 500_000.0
  group.transformation = Geom::Transformation.translation([app::Placement.base_x(centre, product['bounds'][0]).mm, 0, 0])
  actual = app::Model.state(group)
  raise 'Wrong native module/auxiliary roles' unless actual['modules'].length == 4 && actual['panel_parts'].length == 7
  (actual['modules'] + actual['panel_parts']).each do |part|
    wanted = parts.find { |p| p['id'] == part['id'] }
    raise 'Native coordinate/size mismatch' unless %w[origin size].all? { |key| 3.times.all? { |a| (part[key][a] - wanted[key][a]).abs < 0.01 } }
    instance = group.entities.find { |e| e.persistent_id == part['entity_id'] }
    raise 'Native part is not a solid' unless instance.manifold?
    raise 'Lost target CAD face links' unless part.fetch('anchor_evidence').length == 6
  end
  raise 'World X centring' unless (group.bounds.center.x.to_mm - centre).abs < 0.01
  raise 'Front/floor normalisation' unless group.bounds.min.y.to_mm.abs < 0.01 && group.bounds.min.z.to_mm.abs < 0.01
  invalid = product.merge('status' => 'needs_review', 'error' => 'Mẫu còn thiếu phần phụ.')
  begin
    app::Model.build(invalid, File.join(plugin, 'outputs', 'native-learning'), 'must-not-build', model)
    raise 'Review-only example was built'
  rescue ArgumentError => error
    raise unless error.message.include?('thiếu')
  end
ensure
  model.abort_operation if operation
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
after = model.entities.select { |e| app::Model.container?(e) }.map do |e|
  [e.persistent_id, e.transformation.to_a, e.name, e.bounds.min.to_a, e.bounds.max.to_a]
end
raise 'Native check changed existing geometry' unless baseline == after && all_ids == model.entities.map(&:persistent_id).sort
raise 'Native check changed labels' unless labels == app::Model.labels(model)
result = { 'status' => 'passed', 'modules' => 4, 'auxiliary_boxes' => 7, 'solids' => 11,
           'original_geometry_unchanged' => true, 'review_build_blocked' => true, 'bounds_mm' => product['bounds'] }
app::Storage.write_json(File.join(plugin, 'outputs', 'learning-native-result.json'), result)
puts JSON.generate(result)
