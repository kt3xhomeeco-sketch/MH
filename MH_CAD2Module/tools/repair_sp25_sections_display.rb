# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT; dict = app::Model::DICT
before = JSON.parse(File.read(File.join(root, 'outputs/sp25-repair-before.json'), encoding: 'UTF-8'))
raise 'Wrong captured SP25 session' unless Process.pid == 20_324 && Process.pid == before['pid'] && model.path == before['path']
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
target = JSON.parse(File.read(File.join(root, 'outputs/sp25-reference-repair-target.json'), encoding: 'UTF-8'))
app::PlanReference.validate(target)
products = before['products'].map { |r| app::Assembly.new(model, r['id']) }
primary_index = before['products'].index { |r| r['analysis'].dig('plan_reference', 'scope') == 'all_views' }
primary = products[primary_index]; original = before['products'][primary_index]['analysis']
raise 'Source geometry/origin changed' unless original['plan_reference']['segments'] == target['plan_reference']['segments'] && original['plan_reference']['source_origin_mm'] == target['plan_reference']['source_origin_mm']
before['products'].each_with_index do |record, i|
  raise 'SP25 module/product data changed since capture' unless products[i].valid? && products[i].data == record['raw'] && products[i].transformation.to_a == record['transform']
end
fingerprint = lambda do |g|
  Digest::SHA256.hexdigest(JSON.generate(g.entities.grep(Sketchup::Edge).map { |e| e.vertices.map { |v| v.position.to_a.map { |n| (n.to_mm * 10_000).round } }.sort }.uniq.sort))
end
groups = before['groups'].map do |r|
  g = model.find_entity_by_persistent_id(r['id'])
  unless g.is_a?(Sketchup::Group) && g.parent == model && g.transformation.to_a == r['transform'] && fingerprint.call(g) == r['geometry'] && g.layer.name == r['tag'] && g.name == r['name'] && g.hidden? == r['hidden']
    raise 'User changed/moved a CAD reference; leave it untouched'
  end
  g
end
raise 'Wrong complete source views' unless groups.length == 8 && target['plan_reference']['display_copies'].length == 3
raise 'Already has inspection copies' if model.entities.grep(Sketchup::Group).any? { |g| g.get_attribute(dict, 'job_id') == primary.get_attribute(dict, 'job_id') && g.get_attribute(dict, 'source_view_id') }
library = app::Settings.library; repair = app::Ids.uuid
source = File.join(library, 'sources', target['source_hash'], 'source.dwg')
raise 'Archived source damaged' unless Digest::SHA256.file(source).hexdigest == target['source_hash']
app::Storage.write_json(File.join(library, 'repairs', "#{repair}-sp25-before.json"), before)
groups.each do |g|
  path = File.join(library, 'skp', "#{repair}-cad-#{g.persistent_id}-before.skp")
  raise 'CAD backup failed' unless g.definition.save_as(path)
end
ids = groups.map(&:persistent_id); selection = model.selection.to_a
baseline = model.entities.reject { |e| ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
sha = Digest::SHA256.file(model.path).hexdigest; created = []; moved = []
ref = target['plan_reference']; by_id = groups.to_h { |g| [g.get_attribute(dict, 'view_id'), g] }
model.start_operation('CAD2Module: Sửa SP25 Và Xếp Mặt Đứng Cách 500 mm', true)
begin
  ref['views'].each do |view|
    g = by_id.fetch(view['id']); transform = primary.transformation * app::CadViews.transform(view, ref['plan_bounds_mm'])
    unless g.transformation.to_a.zip(transform.to_a).all? { |a, b| (a - b).abs < 0.000001 }
      moved << view['id']; g.transformation = transform
    end
    g.name = "#{target['code']} · #{view['id']} · #{view['title']} · #{view['plane']}"
    g.layer = model.layers.add(app::PlanReference.view_tag(view))
    %w[plane alignment].each { |k| g.set_attribute(dict, k, view[k]) }
    g.set_attribute(dict, 'view_role', view['role']) if view['role']
  end
  raise 'Repair would move an unrelated view' unless (moved - %w[V06.1 V07.1 V08.1]).empty?
  ref['display_copies'].each do |copy|
    source_view = ref['views'].find { |v| v['id'] == copy['source_view_id'] }
    source_group = by_id.fetch(copy['source_view_id'])
    g = model.entities.add_group
    app::PlanReference.draw(g.entities, source_view['segment_indices'].map { |i| ref['segments'][i] })
    source_group.attribute_dictionary(dict).each_pair { |key, value| g.set_attribute(dict, key, value) }
    g.name = "#{target['code']} · #{copy['id']} · #{copy['title']} · XZ"
    g.layer = model.layers.add('MH_DWG2'); g.hidden = source_group.hidden?
    g.transformation = primary.transformation * app::CadViews.transform(copy, ref['plan_bounds_mm'])
    g.set_attribute(dict, 'view_id', copy['id']); g.set_attribute(dict, 'source_view_id', copy['source_view_id'])
    g.set_attribute(dict, 'plane', 'XZ'); g.set_attribute(dict, 'alignment', 'section_display_copy')
    created << g
  end
  before['products'].each_with_index do |record, i|
    data = record['analysis']; selected = data['plan_view_id']
    data['view_analysis'] = target['view_analysis'].merge('selected_view_id' => selected, 'selected_view_ids' => [selected])
    if i == primary_index
      %w[plan_reference cad_reference_views cad_reference_markers cad_reference_levels cad_reference_level].each { |key| data[key] = target[key] }
      products[i].set_attribute(dict, 'cad_reference_ids', ids + created.map(&:persistent_id))
    end
    data['cad_reference_registration_version'] = '0.22.0'
    products[i].set_attribute(dict, 'analysis', JSON.generate(data))
  end
  all_ids = ids + created.map(&:persistent_id)
  raise 'Box/other geometry changed' unless baseline == model.entities.reject { |e| all_ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
  before['products'].each_with_index do |record, i|
    now = JSON.parse(products[i].get_attribute(dict, 'analysis'))
    raise 'Modules or module placement changed' unless %w[modules trim_parts panel_parts display_layout placement bounds].all? { |key| now[key] == record['analysis'][key] }
  end
  previous = by_id.fetch('V02.1')
  ([by_id.fetch('V06.1')] + created).each do |g|
    raise 'Wrong live500 mm spacing' unless ((g.bounds.min.x - previous.bounds.max.x).to_mm - 500).abs < 0.01 && g.bounds.min.y.to_mm.abs < 0.01 && g.bounds.max.y.to_mm.abs < 0.01
    previous = g
  end
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
model.selection.clear; model.selection.add(selection.select(&:valid?))
raise 'Model file saved unexpectedly' unless sha == Digest::SHA256.file(model.path).hexdigest
app::Storage.event(library, 'kind' => 'cad_reference_relayout', 'code' => 'SP25', 'product_id' => primary.persistent_id,
                            'job_id' => primary.get_attribute(dict, 'job_id'), 'repair_id' => repair,
                            'reason' => 'Link unique vertical markers for2-2/3-3; preserveYOZ, separate open front and addXOZ copies at500 mm; tagMH_DWG2.',
                            'before_backup' => "#{repair}-sp25-before.json", 'moved_views' => moved, 'created' => created.map(&:persistent_id))
result = { passed: true, repair_id: repair, retained_original_ids: ids, moved_views: moved, xoz_copy_ids: created.map(&:persistent_id),
           side_tag: 'MH_DWG2', spacing_mm: 500, module_other_geometry_preserved: true, selection_preserved: true, model_saved: false }
app::Storage.write_json(File.join(root, 'outputs/sp25-sections-live-repair-result.json'), result)
app.publish
puts JSON.generate(result)
