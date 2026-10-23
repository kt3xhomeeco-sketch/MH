# frozen_string_literal: true

# One-time, guarded update of the two untouched trim Groups delivered in 0.18.0.
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong model or busy' unless model.path.tr('\\', '/') == 'E:/MAC/OneDrive/Desktop/Untitled1.skp' && !model.active_path && !app::Jobs.busy? && !app::Corrections.active?
ids = [511526, 511558]
old = ids.map { |id| model.find_entity_by_persistent_id(id) }
raise 'Trim already changed' unless old.all? { |e| e.is_a?(Sketchup::Group) && e.valid? }
owner = old.map { |e| e.get_attribute(app::Model::DICT, 'assembly_id') }.uniq
raise 'Ambiguous ownership' unless owner.length == 1 && owner.first
assembly = app::Assembly.new(model, owner.first)
before = JSON.parse(assembly.get_attribute(app::Model::DICT, 'analysis'))
raise 'Different result' unless before['code'] == 'SCAN-9254EC31-A982-5381-5E11-2682927F0CFB' && assembly.members.length == 8
candidate = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs/registered-native-product.json'), encoding: 'UTF-8'))
raise 'Different geometry' unless before['modules'].map { |p| [p['origin'], p['size']] } == candidate['modules'].map { |p| [p['origin'], p['size']] }
part = candidate['trim_parts'].last
raise 'Missing confirmed trim' unless part['size'].last(2) == [50, 30] && part.dig('elevation_evidence', 'kind') == 'top_trim_proxy'
app::SelectionSource.validate_watch(candidate['source_watch'], model)
old.zip(before['trim_parts'].last(2)).each do |entity, data|
  actual = JSON.parse(entity.get_attribute(app::Model::DICT, 'source_part'))
  expected = assembly.transformation * Geom::Transformation.translation(data['origin'].map(&:mm))
  local = entity.definition.bounds
  raise 'User edited trim; preserve it' unless actual == data && entity.manifold? && entity.entities.grep(Sketchup::Edge).length == 12 &&
    local.min.to_a.all? { |v| v.abs < 0.00001 } && [local.width, local.height, local.depth].map(&:to_mm).zip(data['size']).all? { |a, b| (a - b).abs < 0.01 } &&
    entity.transformation.to_a.zip(expected.to_a).all? { |a, b| (a - b).abs < 0.00001 }
end
after = JSON.parse(JSON.generate(before)); after['trim_parts'] = before['trim_parts'].first(2) + [part]
app::Placement.validate_elevation_product(after)
baseline = model.entities.reject { |e| ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest
root = assembly.get_attribute(app::Model::DICT, 'library')
repair = app::Ids.uuid
snapshot = app::Storage.snapshot(root, assembly, "trim-#{repair}-before")
app::Storage.write_json(File.join(root, 'repairs', "#{repair}-before.json"), 'analysis' => before, 'skp' => snapshot)
model.start_operation('CAD2Module: Nẹp Chữ L Một Khối 50 x 30', true)
begin
  new_group = app::Model.reference_part(assembly.definition.entities, part)
  raise 'Wrong trim solid' unless new_group.manifold? && (new_group.volume * 25.4**3 - part['size'].inject(:*)).abs < 1
  old.each(&:erase!)
  values = assembly.data; values['members'] -= ids; assembly.write(values)
  assembly.set_attribute(app::Model::DICT, 'analysis', JSON.generate(after))
  raise 'Other geometry changed' unless baseline == model.entities.reject { |e| e == new_group }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
  raise 'File changed' unless sha == Digest::SHA256.file(model.path).hexdigest
  model.selection.clear; model.selection.add(selection.select(&:valid?))
  model.selection.add(new_group) if selection.any? { |e| old.include?(e) }
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
event = app::Storage.event(root, 'kind' => 'edit', 'reason' => 'Nẹp chữ L một khối 50 x 30 theo xác nhận người dùng.',
  'product_id' => assembly.persistent_id, 'activity_id' => after['activity_id'], 'code' => after['code'],
  'before' => before, 'after' => after, 'skp' => snapshot, 'repair_id' => repair)
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs/trim-box-live-result.json'), passed: true, group_id: new_group.persistent_id,
  size_mm: part['size'], origin_mm: part['origin'], members: assembly.members.map(&:persistent_id), event: event['id'],
  other_geometry_preserved: true, file_saved: false)
puts 'Replaced only the two unchanged top trim Groups with one confirmed50 x30 solid; all other geometry retained, file not saved.'
