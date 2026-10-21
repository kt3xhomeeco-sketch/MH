# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong working model' unless Process.pid == 2724 && model.path == 'E:\\MAC\\OneDrive\\Desktop\\1.skp'
raise 'Wait for current work' if app::Jobs.busy? || app::Corrections.active? || model.active_path
source = '2ff10c9c3305f3ce77839fd43d6fdbe73af8e507417f5f67732dbcd2f7bf896f'
products = app::Model.products(model).select { |e| JSON.parse(e.get_attribute(app::Model::DICT, 'analysis'))['source_hash'] == source }
raise 'Expected one SP40 source product' unless products.length == 1
product = products.first
analysis = JSON.parse(product.get_attribute(app::Model::DICT, 'analysis'))
trims = product.definition.entities.select { |e| e.get_attribute(app::Model::DICT, 'role') == 'trim_reference' }
raise 'Expected two unconverted side trims' unless trims.length == 2 && trims.all? { |e| e.definition.entities.grep(Sketchup::Face).empty? }
raise 'Unexpected source parts' unless analysis['trim_parts'].all? { |p| p['role'] == 'plan_auxiliary' && p['size'] == [18, 170, 1600] }
root = app::Settings.library('library' => product.get_attribute(app::Model::DICT, 'library'))
id = app::Ids.uuid
before = app::Model.state(product)
baseline = model.entities.reject { |e| e == product }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
snapshot_before = app::Storage.snapshot(root, product, "#{id}-solid-before")
model.start_operation('CAD2Module: Nẹp SP40 Thành Khối Đặc', true)
begin
  product.make_unique if product.definition.instances.length > 1
  old = product.definition.entities.select { |e| e.get_attribute(app::Model::DICT, 'role') == 'trim_reference' }
  analysis['trim_parts'].each { |p| p['solid_proxy'] = true }
  fresh = analysis['trim_parts'].map { |p| app::Model.reference_part(product.definition.entities, p) }
  raise 'Solid check failed' unless fresh.all? { |e| e.manifold? && (e.volume * (25.4**3) - 4_896_000).abs < 0.1 }
  old.each(&:erase!)
  analysis['build_auxiliary'] = true
  product.set_attribute(app::Model::DICT, 'analysis', JSON.generate(analysis))
  after = app::Model.state(product)
  raise 'Module layout changed' unless before['modules'] == after['modules']
  snapshot_after = app::Storage.snapshot(root, product, "#{id}-solid-after")
  event = app::Storage.event(root, 'id' => id, 'kind' => 'solid_auxiliary_update', 'code' => analysis['code'],
    'source_hash' => source, 'before' => before, 'after' => after, 'skp_before' => snapshot_before, 'skp' => snapshot_after)
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
raise 'Other user geometry changed' unless baseline == model.entities.reject { |e| e == product }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
result = { 'status' => 'updated', 'product_id' => product.persistent_id, 'trim_sizes_mm' => after['trim_parts'].map { |p| p['size'] },
           'solid_volumes_mm3' => fresh.map { |e| (e.volume * (25.4**3)).round(3) }, 'history_id' => event['id'], 'other_geometry_unchanged' => true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp40-solid-live-update.json'), result)
app.publish('Đã đổi hai nẹp SP40 thành khối đặc. Settings có ô Tạo khối phụ (nẹp), áp dụng lần dựng mới.')
puts JSON.generate(result)
