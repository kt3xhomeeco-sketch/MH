# frozen_string_literal: true

require 'json'
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Unexpected model/edit/job' unless model.title == '1' && !model.active_path && !app::Jobs.busy? && !app::Corrections.active?
plugin = File.expand_path('..', __dir__)
response = JSON.parse(File.read(File.join(plugin, 'outputs', 'stages-response.json'), encoding: 'UTF-8'))
products = response.fetch('analyses').flat_map { |a| a.fetch('products') }
raise 'Wrong source products' unless products.map { |p| p['code'] }.sort == %w[SP28 SP29 SP30]
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
selection = model.selection.to_a
receipts = []
begin
  model.start_operation('CAD2Module: kiểm tra Mặt bằng cao 1600 tạm', true)
  operation = true
  products.each do |product|
    raise 'Wrong stage' unless product['status'] == 'ready' && product['build_stages'] == { 'plan' => true, 'elevation' => false }
    raise 'Elevation still active' if product['geometry_pipeline']['horizontal']
    group = model.entities.add_group
    product['modules'].each { |part| app::Model.module_instance(group.entities, part) }
    product['trim_parts'].each { |part| app::Model.reference_part(group.entities, part) }
    group.set_attribute(app::Model::DICT, 'analysis', JSON.generate(product))
    centre = app::Model.labels(model).find { |label| label['code'] == product['code'] }.fetch('center_x')
    group.transformation = Geom::Transformation.translation([app::Placement.base_x(centre, product['bounds'][0]).mm, 0, 0])
    actual = app::Model.state(group)
    %w[modules trim_parts].each do |key|
      raise 'Part count mismatch' unless actual[key].length == product[key].length
      actual[key].each do |part|
        wanted = product[key].find { |p| p['id'] == part['id'] }
        raise 'Measured footprint mismatch' unless %w[origin size].all? { |field| 3.times.all? { |a| (part[field][a] - wanted[field][a]).abs < 0.01 } }
        raise 'Wrong default height' unless (part['size'][2] - 1600).abs < 0.01 && part['origin'][2].abs < 0.01
      end
    end
    raise 'Centring mismatch' unless (group.bounds.center.x.to_mm - centre).abs < 0.01
    raise 'Front/floor mismatch' unless group.bounds.min.y.to_mm.abs < 0.01 && group.bounds.min.z.to_mm.abs < 0.01
    receipts << { code: product['code'], modules: actual['modules'].length, auxiliary: actual['trim_parts'].length, height_mm: 1600 }
  end
ensure
  model.abort_operation if operation
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'Existing geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
result = { status: 'passed', original_geometry_unchanged: true, products: receipts }
app::Storage.write_json(File.join(plugin, 'outputs', 'stages-native-result.json'), result)
puts JSON.generate(result)
