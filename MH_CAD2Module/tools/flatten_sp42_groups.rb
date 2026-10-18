# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong working model' unless Process.pid == 2724 && model.path == 'E:\\MAC\\OneDrive\\Desktop\\1.skp'
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
old = model.find_entity_by_persistent_id(1001599)
raise 'Expected repaired SP42 Group' unless old && old.valid? && old.is_a?(Sketchup::Group) && old.get_attribute(app::Model::DICT, 'role') == 'product'
analysis = JSON.parse(old.get_attribute(app::Model::DICT, 'analysis'))
raise 'Unexpected SP42 source' unless analysis['source_hash'] == '18add59eeb5bbfa1d7f39d1bb14a327d6da8353435b283fd1226bd1c6bbdfd14'
raise 'Source origin no longer correct' unless (old.transformation.origin.x.to_mm - 327587.112972).abs < 0.01
before = app::Model.state(old)
old_id = old.persistent_id
frame = old.transformation
attributes = old.attribute_dictionaries.to_h { |dict| [dict.name, dict.to_h] }
name = old.name
baseline = model.entities.reject { |e| e == old }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
root = app::Settings.library('library' => old.get_attribute(app::Model::DICT, 'library'))
id = app::Ids.uuid
skp_before = app::Storage.snapshot(root, old, "#{id}-flat-before")
model.start_operation('CAD2Module: Group Module SP42 Riêng', true)
begin
  product = app::Assembly.create(model)
  product.transformation = frame
  product.name = name
  attributes.each { |dict, entries| entries.each { |key, value| product.set_attribute(dict, key, value) } }
  parts = old.explode.select { |e| app::Model.container?(e) }
  raise 'Unexpected parts after removing container' unless parts.length == 24 && parts.all? { |e| e.is_a?(Sketchup::Group) && e.parent == model }
  parts.each { |part| product.add_member(part) }
  after = app::Model.state(product)
  %w[modules trim_parts].each do |kind|
    before[kind].each do |part|
      actual = after[kind].find { |p| p['id'] == part['id'] }
      raise 'UnGrouping moved part geometry' unless actual && %w[origin size].all? { |key| actual[key].zip(part[key]).all? { |a, b| (a - b).abs < 0.01 } }
    end
  end
  raise 'Source frame changed' unless frame.to_a == product.transformation.to_a
  skp_after = app::Storage.snapshot(root, product, "#{id}-flat-after")
  event = app::Storage.event(root, 'id' => id, 'kind' => 'group_output_update', 'reason' => 'SP42: mỗi khối là Group riêng, bỏ nhóm bao sản phẩm',
    'code' => analysis['code'], 'old_product_id' => old_id, 'new_product_id' => product.persistent_id,
    'analysis' => analysis, 'before' => before, 'after' => after, 'skp_before' => skp_before, 'skp' => skp_after)
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
raise 'Other user geometry changed' unless baseline == model.entities.reject { |e| product.members.include?(e) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
model.selection.clear
selected = selection.filter_map { |e| e if e.valid? }
selected += product.members if selection.any? { |e| !e.valid? }
model.selection.add(selected)
last = app.instance_variable_get(:@last_built)
last[:ids].map! { |value| value == old_id ? product.persistent_id : value } if last && last[:model] == model
raise 'Product cannot be selected via its Groups' unless app::Model.selected_product == product
result = { 'status' => 'flattened', 'product_id' => product.persistent_id, 'root_groups' => product.members.length,
  'no_product_container' => true, 'geometry_unchanged' => true, 'imported_cad_unchanged' => true, 'history_id' => event['id'] }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp42-flat-live-update.json'), result)
app.publish('SP42 đã khớp CAD import. Các module/phần phụ là Group riêng, không có nhóm bao sản phẩm.')
puts JSON.generate(result)
