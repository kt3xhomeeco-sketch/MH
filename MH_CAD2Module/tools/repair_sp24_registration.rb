# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
root = app::Settings::ROOT
before = JSON.parse(File.read(File.join(root, 'outputs/sp24-live-before.json'), encoding: 'UTF-8'))
raise 'Wrong SP24 working session' unless Process.pid == before['pid'] && model.path == before['path'] && Process.pid == 23_188
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
target = JSON.parse(File.read(File.join(root, 'outputs/sp24-repair-reference.json'), encoding: 'UTF-8'))
primary_before = before['products'].find { |p| p['refs'] }
raise 'Wrong SP24 delivery' unless primary_before && primary_before['job'] == '5e4cac36-6e30-ebd6-826e-b9895a8f76b7'
products = before['products'].map { |p| app::Assembly.new(model, p['id']) }
primary = products.find { |p| p.persistent_id == primary_before['id'] }
before['products'].each_with_index do |record, i|
  p = products[i]
  raise 'SP24 changed since capture' unless p.valid? && p.transformation.to_a == record['transform'] && JSON.parse(p.get_attribute(app::Model::DICT, 'analysis')) == record['analysis']
end
source = File.join(app::Settings.library, 'sources', target['source_hash'], 'source.dwg')
raise 'Archived SP24 source damaged' unless Digest::SHA256.file(source).hexdigest == target['source_hash']
app::PlanReference.validate(target)
old_ref = primary_before['analysis']['plan_reference']
groups = primary_before['refs'].map { |id| model.find_entity_by_persistent_id(id) }
raise 'Old references missing' unless groups.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model }
fingerprint = lambda { |g|
  g.entities.grep(Sketchup::Edge).map { |e| e.vertices.map { |v| v.position.to_a.map { |n| (n.to_mm * 10_000).round } }.sort }.uniq.sort
}
selection = model.selection.to_a
model.start_operation('CAD2Module: Kiểm Tra CAD SP24', true)
begin
  old_ref['views'].each do |view|
    g = groups.find { |v| v.get_attribute(app::Model::DICT, 'view_id') == view['id'] }
    expected = primary.transformation * app::CadViews.transform(view, old_ref['plan_bounds_mm'])
    raise 'User moved a CAD reference' unless g && g.transformation.to_a.zip(expected.to_a).all? { |a, b| (a - b).abs < 0.000001 }
    temp = model.entities.add_group
    app::PlanReference.draw(temp.entities, view['segment_indices'].map { |i| old_ref['segments'][i] })
    raise 'User edited CAD geometry' unless g.entities.all? { |e| e.is_a?(Sketchup::Edge) } && fingerprint.call(g) == fingerprint.call(temp)
    temp.erase!
  end
ensure
  model.abort_operation
end
ids = groups.map(&:persistent_id)
baseline = model.entities.reject { |e| ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
hidden = groups.to_h { |g| [g.get_attribute(app::Model::DICT, 'view_id'), g.hidden?] }
selected_views = selection.filter_map { |g| g.get_attribute(app::Model::DICT, 'view_id') if ids.include?(g.persistent_id) }
library = app::Settings.library; repair = app::Ids.uuid; sha = Digest::SHA256.file(model.path).hexdigest
groups.each do |g|
  path = File.join(library, 'skp', "#{repair}-cad-#{g.persistent_id}-before.skp")
  raise 'CAD backup failed' unless g.definition.save_as(path)
end
app::Storage.write_json(File.join(library, 'repairs', "#{repair}-sp24-reference-before.json"), before)
ref = target['plan_reference']; created = []
model.start_operation('CAD2Module: Sửa Liên Kết Và Vị Trí CAD SP24', true)
begin
  app::PlanReference.create(model, target, primary)
  created = primary.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
  created.each { |g| g.hidden = hidden.fetch(g.get_attribute(app::Model::DICT, 'view_id'), false) }
  before['products'].each_with_index do |record, i|
    p = products[i]; data = record['analysis']; view_id = data['plan_view_id']
    level = target['cad_reference_levels'].fetch(view_id)
    data['view_analysis'] = target['view_analysis'].merge('selected_view_id' => view_id, 'selected_view_ids' => [view_id])
    if p == primary || p.persistent_id == primary.persistent_id
      %w[plan_reference cad_reference_views cad_reference_outlines cad_reference_levels cad_reference_markers cad_reference_level].each { |key| data[key] = target[key] }
    else
      view = ref['views'].find { |v| v['id'] == view_id }
      child_base = data['plan_reference']['source_origin_mm']; base = ref['source_origin_mm']
      offset = (0..1).map { |j| primary.transformation.origin.to_a[j].to_mm - p.transformation.origin.to_a[j].to_mm + child_base[j] - base[j] + view['xy_offset_mm'][j] }
      data['cad_reference_level'] = level; data['cad_reference_shared'] = true; data['cad_reference_offset_mm'] = offset
      data['plan_reference'].merge!('level' => level, 'z_mm' => view['z_mm'], 'xy_offset_mm' => offset, 'shared' => true)
    end
    data['cad_reference_registration_version'] = '0.21.0'
    p.set_attribute(app::Model::DICT, 'analysis', JSON.generate(data))
    group = created.find { |g| g.get_attribute(app::Model::DICT, 'view_id') == view_id }
    p.set_attribute(app::Model::DICT, 'plan_reference_id', group.persistent_id)
  end
  groups.each(&:erase!)
  all_ids = ids + created.map(&:persistent_id)
  raise 'Module/other geometry changed' unless baseline == model.entities.reject { |e| all_ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
model.selection.clear
model.selection.add(selection.select(&:valid?) + created.select { |g| selected_views.include?(g.get_attribute(app::Model::DICT, 'view_id')) })
raise 'Working model file changed' unless Digest::SHA256.file(model.path).hexdigest == sha
app::Storage.event(library, 'kind' => 'cad_reference_relayout', 'code' => 'SP24', 'product_id' => primary.persistent_id,
                            'job_id' => primary_before['job'], 'repair_id' => repair, 'before' => before,
                            'reason' => 'Local section families, arrow orientation, measured levels and complete-source XY registration.')
result = { passed: true, repair_id: repair, reference_groups: created.length, replaced_reference_ids: ids, new_reference_ids: created.map(&:persistent_id),
           module_other_geometry_preserved: true, model_saved: false, source_cut_levels: ref['views'].filter_map { |v| [v['id'], v['z_mm']] if v['role'] == 'plan' } }
app::Storage.write_json(File.join(root, 'outputs/sp24-registration-live-result.json'), result)
app.publish
puts JSON.generate(result)
