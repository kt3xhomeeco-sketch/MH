# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong working model' unless Process.pid == 2724 && model.path == 'E:\\MAC\\OneDrive\\Desktop\\1.skp'
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
old = model.find_entity_by_persistent_id(994564)
raise 'Expected original SP42 result' unless old && old.valid? && old.get_attribute(app::Model::DICT, 'role') == 'product'
analysis = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'sp42-origin-fixed-analysis.json'), encoding: 'UTF-8'))
previous = JSON.parse(old.get_attribute(app::Model::DICT, 'analysis'))
raise 'Source changed' unless previous['source_hash'] == analysis['source_hash'] && previous['code'] == analysis['code']
raise 'Unexpected placement' unless (old.transformation.origin.x.to_mm - 329765.112972).abs < 0.01
source = model.find_entity_by_persistent_id(987296)
raise 'Imported CAD missing' unless source && source.valid?
edges = []
app::ManualBoxes.collect_edges(source.definition.entities, source.transformation, edges)
request = JSON.parse(File.read(File.join(app::Settings::ROOT, 'library', 'jobs', '86f4fdaa-c49c-183e-998a-b7c4a9e4bd5e', 'request.json'), encoding: 'UTF-8'))
lines = edges.map { |e| e.map { |p| p.to_a.map(&:to_mm)[0, 2] } }
match = lambda { |a, b| a.zip(b).all? { |x, y| (x - y).abs < 0.01 } }
raise 'CAD changed after scanning' unless lines.length == 165 && request['geometry']['lines'].all? do |row|
  lines.any? { |a, b| (match.call(a, row['a']) && match.call(b, row['b'])) || (match.call(b, row['a']) && match.call(a, row['b'])) }
end
before = app::Model.state(old)
expected = analysis['modules'] + analysis['trim_parts']
raise 'Part count changed' unless expected.length == 24 && before['modules'].length + before['trim_parts'].length == 24
(before['modules'] + before['trim_parts']).each do |part|
  target = expected.find { |p| p['id'] == part['id'] }
  raise 'User edited part layout' unless target && %w[origin size].all? { |key| part[key].zip(target[key]).all? { |a, b| (a - b).abs < 0.01 } }
end
old_id = old.persistent_id
baseline = model.entities.reject { |e| e == old }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
root = app::Settings.library('library' => old.get_attribute(app::Model::DICT, 'library'))
id = app::Ids.uuid
skp_before = app::Storage.snapshot(root, old, "#{id}-origin-before")
copy_group = lambda do |entities, original|
  group = entities.add_group
  copy = group.entities.add_instance(original.definition, Geom::Transformation.new)
  copy.explode
  group.transformation = original.transformation
  group.name = original.name
  group.layer = original.layer
  group.material = original.material
  group.hidden = original.hidden?
  group.casts_shadows = original.casts_shadows?
  group.receives_shadows = original.receives_shadows?
  original.attribute_dictionaries&.each { |dict| dict.each_pair { |key, value| group.set_attribute(dict.name, key, value) } }
  group
end
model.start_operation('CAD2Module: Sửa Gốc SP42 Và Đổi Group', true)
begin
  replacement = copy_group.call(model.entities, old)
  children = replacement.entities.select { |e| app::Model.container?(e) && %w[module trim_reference panel_part].include?(e.get_attribute(app::Model::DICT, 'role')) }
  children.each do |child|
    group = copy_group.call(replacement.entities, child)
    key = child.get_attribute(app::Model::DICT, 'role') == 'module' ? 'source_module' : 'source_part'
    part = JSON.parse(child.get_attribute(app::Model::DICT, key))
    target = expected.find { |p| p['id'] == part['id'] }
    group.set_attribute(app::Model::DICT, key, JSON.generate(target))
    child.erase!
  end
  replacement.transformation = Geom::Transformation.new(app::Placement.source_matrix(analysis['placement']))
  analysis['build_auxiliary'] = previous.fetch('build_auxiliary', true)
  replacement.set_attribute(app::Model::DICT, 'analysis', JSON.generate(analysis))
  after = app::Model.state(replacement)
  groups = replacement.entities.select { |e| app::Model.container?(e) }
  raise 'Group conversion failed' unless groups.length == 24 && groups.all? { |e| e.is_a?(Sketchup::Group) && e.manifold? }
  raise 'Module sizes changed' unless after['modules'].map { |p| p['size'] } == before['modules'].map { |p| p['size'] }
  raise 'CAD alignment failed' unless (replacement.bounds.min.x.to_mm - source.bounds.min.x.to_mm).abs < 0.01 && (replacement.bounds.max.x.to_mm - source.bounds.max.x.to_mm).abs < 0.01
  arcs = groups.flat_map { |e| e.entities.grep(Sketchup::Edge).map(&:curve).compact.uniq.grep(Sketchup::ArcCurve) }
  raise 'R150 lost during conversion' unless arcs.length == 2 && arcs.all? { |a| (a.radius.to_mm - 150).abs < 0.01 }
  skp_after = app::Storage.snapshot(root, replacement, "#{id}-origin-after")
  event = app::Storage.event(root, 'id' => id, 'kind' => 'placement_repair', 'reason' => 'SP42: sửa lệch gốc 2178 mm, chuyển Component thành Group',
    'code' => analysis['code'], 'old_product_id' => old_id, 'new_product_id' => replacement.persistent_id,
    'before_analysis' => previous, 'analysis' => analysis, 'before' => before, 'after' => after,
    'skp_before' => skp_before, 'skp' => skp_after)
  old.erase!
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
raise 'Other geometry changed' unless baseline == model.entities.reject { |e| e == replacement }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
model.selection.clear
model.selection.add(selection.filter_map { |e| e.valid? ? e : replacement })
last = app.instance_variable_get(:@last_built)
last[:ids].map! { |value| value == old_id ? replacement.persistent_id : value } if last && last[:model] == model
Array(app.instance_variable_get(:@analyses)).each { |row| Array(row['products']).map! { |p| p['code'] == analysis['code'] ? analysis : p } }
result = { 'status' => 'repaired', 'product_id' => replacement.persistent_id, 'shift_x_mm' => -2178,
  'groups' => 24, 'r150_preserved' => true, 'imported_cad_unchanged' => true, 'other_geometry_unchanged' => true, 'history_id' => event['id'] }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp42-live-origin-repair.json'), result)
app.publish('Đã sửa SP42 về đúng CAD import, giữ cung R150 và đổi các khối sang Group.')
puts JSON.generate(result)
