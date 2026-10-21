# frozen_string_literal: true

# Development-only: check real worker output in an aborted native operation.
require 'json'
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Unexpected model/edit/job' unless model.title == '1' && !model.active_path && !app::Jobs.busy? && !app::Corrections.active?
plugin = File.expand_path('..', __dir__)
response = JSON.parse(File.read(File.join(plugin, 'outputs', 'three-response.json'), encoding: 'UTF-8'))
products = response.fetch('analyses').flat_map { |analysis| analysis.fetch('products') }
raise 'Unexpected response' unless products.map { |p| p['code'] }.sort == %w[SP28 SP29 SP30]
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
selection = model.selection.to_a
receipts = []
begin
  model.start_operation('CAD2Module: kiểm tra ba SP bằng khối tạm', true)
  operation = true
  products.each do |product|
    raise 'Product needs review' unless product['status'] == 'ready'
    group = model.entities.add_group
    product['modules'].each { |part| app::Model.module_instance(group.entities, part) }
    product.fetch('trim_parts').each { |part| app::Model.reference_part(group.entities, part) }
    group.set_attribute(app::Model::DICT, 'analysis', JSON.generate(product))
    centre = app::Model.labels(model).find { |label| label['code'] == product['code'] }.fetch('center_x')
    group.transformation = Geom::Transformation.translation([app::Placement.base_x(centre, product['bounds'][0]).mm, 0, 0])
    actual = app::Model.state(group)
    %w[modules trim_parts].each do |key|
      expected = product.fetch(key)
      raise 'Native part count mismatch' unless actual.fetch(key).length == expected.length
      actual.fetch(key).each do |part|
        wanted = expected.find { |item| item['id'] == part['id'] }
        raise 'Native size/position mismatch' unless %w[origin size].all? { |field| 3.times.all? { |axis| (part[field][axis] - wanted[field][axis]).abs < 0.01 } }
        if key == 'modules'
          instance = group.entities.find { |e| e.persistent_id == part['entity_id'] }
          raise 'Non-solid module' unless instance.manifold?
        end
      end
    end
    raise 'Centre X mismatch' unless (group.bounds.center.x.to_mm - centre).abs < 0.01
    raise 'Front/floor mismatch' unless group.bounds.min.y.to_mm.abs < 0.01 && group.bounds.min.z.to_mm.abs < 0.01
    receipts << { code: product['code'], modules: actual['modules'].length, auxiliary: actual['trim_parts'].length,
                  bounds_mm: product['bounds'], centre_x_mm: centre }
  end
ensure
  model.abort_operation if operation
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'Existing geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a] }
result = { status: 'passed', original_geometry_unchanged: true, products: receipts }
app::Storage.write_json(File.join(plugin, 'outputs', 'three-native-result.json'), result)
puts JSON.generate(result)
