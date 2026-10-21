# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong working session' unless Process.pid == 14_572 && model.path.tr('\\', '/') == 'E:/MAC/OneDrive/Desktop/1.skp'
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[cad_views.rb plan_reference.rb].each { |name| load File.join(root, name) }
assembly = app::Assembly.new(model, 'assembly-b2a6eba2-df1a-d801-c949-18e079b6882b')
raise 'Reported result missing' unless assembly.valid? && assembly.get_attribute(app::Model::DICT, 'job_id') == '3cc162cc-74e7-617c-eb4f-b44b1c3d6451'
old = JSON.parse(assembly.get_attribute(app::Model::DICT, 'analysis')); data = JSON.parse(JSON.generate(old)); ref = data.fetch('plan_reference')
raise 'Unexpected source/layout' unless old['code'] == 'SP23' && old['source_hash'] == '556ddc0207b72b3d60b7d46a59bcbdc55c24302aac321a267f42195d39f14dbb' &&
                                       ref['scope'] == 'all_views' && ref['views'].count { |v| v['role'] == 'plan' } == 1 && ref['z_mm'] == 1517.911672
archived = File.join(app::Settings.library, 'sources', old['source_hash'], 'source.dwg')
raise 'Imported source damaged' unless Digest::SHA256.file(archived).hexdigest == old['source_hash']
groups = assembly.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
raise 'Imported references missing' unless groups.length == ref['views'].length && groups.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model }
fingerprint = lambda { |g|
  g.entities.grep(Sketchup::Edge).map { |e| e.vertices.map { |v| v.position.to_a.map { |n| (n.to_mm * 10_000).round } }.sort }.uniq.sort
}
# Compare only with this delivery's immutable drawing instructions, in an aborted verification operation.
model.start_operation('CAD2Module: Kiểm Tra CAD SP23', true)
begin
  ref['views'].each do |view|
    g = groups.find { |v| v.get_attribute(app::Model::DICT, 'view_id') == view['id'] }
    expected = assembly.transformation * app::CadViews.transform(view, ref['plan_bounds_mm'])
    raise 'Reference moved' unless g && g.transformation.to_a.zip(expected.to_a).all? { |a, b| (a - b).abs < 0.000001 }
    temp = model.entities.add_group
    app::PlanReference.draw(temp.entities, view['segment_indices'].map { |i| ref['segments'][i] })
    raise 'Reference geometry edited' unless fingerprint.call(g) == fingerprint.call(temp) && g.entities.all? { |e| e.is_a?(Sketchup::Edge) }
    temp.erase!
  end
ensure
  model.abort_operation
end
level = ref['level'].merge('placement_basis' => 'single_plan_zero', 'placement_z_mm' => 0, 'plan_count' => 1)
ref['level'] = level; ref['z_mm'] = 0; data['cad_reference_level'] = level
data['cad_reference_levels'] = { ref['view_id'] => level }
ref['views'].each do |view|
  view['plane'] = 'YZ' if view['role'] == 'section_vertical'
  if view['role'] == 'plan'
    view['level'] = level; view['z_mm'] = 0
  end
end
points = ref['views'].flat_map do |view|
  b = view['box_mm']; transform = app::CadViews.transform(view, ref['plan_bounds_mm'])
  [0, 2].product([1, 3]).map { |i, j| Geom::Point3d.new(b[i].mm, b[j].mm, 0).transform(transform).to_a.map(&:to_mm) }
end
ref['placed_bounds_mm'] = (0..2).map { |i| points.map { |p| p[i] }.min } + (0..2).map { |i| points.map { |p| p[i] }.max }
app::PlanReference.validate(data)
ids = groups.map(&:persistent_id); baseline = model.entities.reject { |e| ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a; sha = Digest::SHA256.file(model.path).hexdigest
repair = app::Ids.uuid; library = app::Settings.library
before = { 'analysis' => old, 'references' => groups.map { |g| { 'id' => g.persistent_id, 'transform' => g.transformation.to_a } } }
groups.each do |g|
  path = File.join(library, 'skp', "#{repair}-cad-#{g.persistent_id}-before.skp")
  raise 'Reference backup failed' unless g.definition.save_as(path)
end
app::Storage.write_json(File.join(library, 'repairs', "#{repair}-sp23-yoz-zero-before.json"), before)
model.start_operation('CAD2Module: Đặt CAD SP23 YOZ Và Z0', true)
begin
  ref['views'].each do |view|
    g = groups.find { |v| v.get_attribute(app::Model::DICT, 'view_id') == view['id'] }
    g.transformation = assembly.transformation * app::CadViews.transform(view, ref['plan_bounds_mm'])
    g.set_attribute(app::Model::DICT, 'plane', view['plane'])
    g.name = g.name.sub(/ · XZ\z/, ' · YZ') if view['plane'] == 'YZ'
    next unless view['level']
    g.set_attribute(app::Model::DICT, 'level_mm', view['z_mm'])
    g.set_attribute(app::Model::DICT, 'source_level_mm', view['level']['level_mm']) if view['level']['status'] == 'measured'
  end
  assembly.set_attribute(app::Model::DICT, 'analysis', JSON.generate(data))
  raise 'Other geometry changed' unless baseline == model.entities.reject { |e| ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
  primary = model.find_entity_by_persistent_id(assembly.get_attribute(app::Model::DICT, 'plan_reference_id'))
  raise 'Single plan not at zero' unless primary.bounds.min.z.to_mm.abs < 0.01
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
model.selection.clear; model.selection.add(selection.select(&:valid?))
raise 'Working file changed' unless Digest::SHA256.file(model.path).hexdigest == sha
app::Storage.event(library, 'kind' => 'cad_reference_relayout', 'code' => 'SP23', 'product_id' => assembly.persistent_id, 'repair_id' => repair, 'before' => before,
                            'source_level_mm' => level['level_mm'], 'display_z_mm' => 0)
result = { passed: true, repair_id: repair, single_plan_z_mm: 0, source_cut_level_mm: level['level_mm'], side_plane: 'YZ', independent_references: ids,
           module_other_geometry_preserved: true, model_saved: false }
app::Storage.write_json(File.join(root, 'outputs/yoz-zero-live-repair-result.json'), result)
app.publish
puts JSON.generate(result)
