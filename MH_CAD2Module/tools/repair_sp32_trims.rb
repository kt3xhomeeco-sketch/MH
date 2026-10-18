# frozen_string_literal: true

require 'json'
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Unexpected model/edit/job' unless model.title == '1' && !model.active_path && !app::Jobs.busy? && !app::Corrections.active?
root = model.find_entity_by_persistent_id(963869)
raise 'SP32 result missing/shared' unless root && root.get_attribute(app::Model::DICT, 'code') == 'SP32' && root.definition.instances.length == 1
response = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'sp32-current-response.json'), encoding: 'UTF-8'))
product = response.fetch('analyses').first.fetch('products').first
raise 'Unexpected repaired product' unless product['code'] == 'SP32' && product['status'] == 'ready' && product.dig('placement', 'mode') == 'source_plan'
before = app::Model.state(root)
raise 'Existing result changed' unless before['modules'].length == 4 && before['trim_parts'].length == 1
before['modules'].each do |part|
  wanted = product['modules'].find { |p| p['id'] == part['id'] }
  raise 'User module dimensions/positions changed' unless wanted && %w[origin size].all? { |key| 3.times.all? { |axis| (part[key][axis] - wanted[key][axis]).abs < 0.01 } }
end
other_roots = model.entities.reject { |e| e == root }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
module_before = root.definition.entities.select { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }.map { |e| [e.persistent_id, e.transformation.to_a, e.bounds.min.to_a, e.bounds.max.to_a] }
library = app::Settings.resolve_library(root.get_attribute(app::Model::DICT, 'library'))
repair_id = "repair-#{app::Ids.uuid}"
before_skp = app::Storage.snapshot(library, root, "#{repair_id}-before")
old_analysis = JSON.parse(root.get_attribute(app::Model::DICT, 'analysis'))
begin
  model.start_operation('CAD2Module: bổ sung hai nẹp SP32 trên CAD quét', true)
  operation = true
  added = product['trim_parts'].select { |part| part['solid_proxy'] }.map { |part| app::Model.reference_part(root.definition.entities, part) }
  raise 'Expected two added solid trims' unless added.length == 2 && added.all?(&:manifold?)
  root.transformation = Geom::Transformation.new(app::Placement.source_matrix(product['placement']))
  root.set_attribute(app::Model::DICT, 'analysis', JSON.generate(product))
  root.set_attribute(app::Model::DICT, 'repair_id', repair_id)
  root.delete_attribute(app::Model::DICT, 'label_id')
  after = app::Model.state(root)
  raise 'Wrong final counts' unless after['modules'].length == 4 && after['trim_parts'].length == 3
  after['trim_parts'].select { |p| p['solid_proxy'] }.each do |part|
    raise 'Wrong trim size' unless part['size'] == [18, 250, 1600]
  end
  module_after = root.definition.entities.select { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }.map { |e| [e.persistent_id, e.transformation.to_a, e.bounds.min.to_a, e.bounds.max.to_a] }
  raise 'Existing modules changed' unless module_before == module_after
  raise 'Source/other geometry changed' unless other_roots == model.entities.reject { |e| e == root }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
  product['modules'].each do |part|
    point = Geom::Point3d.new(part['origin'].map(&:mm)).transform(root.transformation)
    raise 'Result is not on current CAD' unless (point.x.to_mm - part['source_box'][0]).abs < 0.01 && (point.y.to_mm - part['source_box'][1]).abs < 0.01
  end
  after_skp = app::Storage.snapshot(library, root, "#{repair_id}-after")
  event = app::Storage.event(library, 'kind' => 'repair', 'status' => 'applied', 'code' => 'SP32',
                            'reason' => 'Bổ sung hai nẹp CAD sâu 50 mm thành khối phụ sâu bằng tủ 250 mm; dựng tại CAD quét.',
                            'analysis' => product, 'previous_analysis' => old_analysis, 'before' => before,
                            'after' => after, 'before_skp' => before_skp, 'skp' => after_skp)
  model.commit_operation
  operation = false
rescue StandardError
  model.abort_operation if operation
  raise
end
app.instance_variable_set(:@analyses, response['analyses'])
app.instance_variable_set(:@focused, 'SP32')
app.instance_variable_set(:@focus_cad, false)
app.instance_variable_set(:@history_product, nil)
model.selection.clear
model.selection.add(root)
model.active_view.zoom(root)
app.publish('Đã bổ sung hai nẹp 18 × 250 × 1600 mm cho SP32, dựng tại CAD quét. Giữ nguyên bốn module.')
result = { status: 'passed', product_id: root.persistent_id, modules_unchanged: true,
           original_cad_and_other_geometry_unchanged: true, added_solid_trims: added.map(&:persistent_id),
           trim_size_mm: [18, 250, 1600], placement: product['placement'], history: event['path'] }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp32-trim-repair-result.json'), result)
puts JSON.generate(result)
