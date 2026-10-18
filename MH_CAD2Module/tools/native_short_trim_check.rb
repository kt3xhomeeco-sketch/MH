# frozen_string_literal: true

require 'json'
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Unexpected model/edit/job' unless model.title == '1' && !model.active_path && !app::Jobs.busy? && !app::Corrections.active?
plugin = app::Settings::ROOT
response = JSON.parse(File.read(File.join(plugin, 'outputs', 'sp32-trim-response.json'), encoding: 'UTF-8'))
product = response.fetch('analyses').first.fetch('products').first
raise 'Wrong product/stage' unless product['code'] == 'SP32' && product.dig('build_stages', 'elevation') == false
short = product['trim_parts'].select { |p| p['solid_proxy'] }
raise 'Expected two 18 x 250 x 1600 proxies' unless short.length == 2 && short.all? { |p| p['size'] == [18, 250, 1600] }
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
begin
  model.start_operation('CAD2Module: kiểm tra hai nẹp ngắn tạm', true)
  operation = true
  group = model.entities.add_group
  group.transformation = Geom::Transformation.new(app::Placement.source_matrix(product.fetch('placement')))
  group.set_attribute(app::Model::DICT, 'analysis', JSON.generate(product))
  product['modules'].each { |part| app::Model.module_instance(group.entities, part) }
  product['trim_parts'].each { |part| app::Model.reference_part(group.entities, part) }
  actual = app::Model.state(group)
  raise 'Wrong roles/counts' unless actual['modules'].length == 4 && actual['trim_parts'].length == 3 && actual['panel_parts'].empty?
  actual['trim_parts'].select { |p| p['solid_proxy'] }.each do |part|
    wanted = short.find { |p| p['id'] == part['id'] }
    raise 'Coordinates mismatch' unless %w[origin size].all? { |key| 3.times.all? { |axis| (part[key][axis] - wanted[key][axis]).abs < 0.01 } }
    instance = group.entities.find { |e| e.persistent_id == part['entity_id'] }
    raise 'Trim not a solid' unless instance.manifold?
  end
  product['modules'].each do |part|
    point = Geom::Point3d.new(part['origin'].map(&:mm)).transform(group.transformation)
    raise 'Module not on scanned CAD' unless (point.x.to_mm - part['source_box'][0]).abs < 0.01 && (point.y.to_mm - part['source_box'][1]).abs < 0.01
  end
  matrix = app::Placement.source_matrix(product['placement'].merge('plane_offset_mm' => 73))
  origin = Geom::Point3d.new.transform(Geom::Transformation.new(matrix))
  raise 'Source plane offset lost' unless (origin.z.to_mm - 73).abs < 0.01
ensure
  model.abort_operation if operation
end
raise 'Existing geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
result = { status: 'passed', original_geometry_unchanged: true, solid_trims: 2, trim_size_mm: [18, 250, 1600], direct_source_placement: true }
app::Storage.write_json(File.join(plugin, 'outputs', 'sp32-trim-native-result.json'), result)
puts JSON.generate(result)
