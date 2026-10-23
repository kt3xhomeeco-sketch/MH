# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
root = app::Settings::ROOT
guard = JSON.parse(File.read(File.join(root, 'outputs/sp20-levels-repair-guard.json'), encoding: 'UTF-8'))
raise 'Wrong model/session' unless Process.pid == guard['pid'] && model.path == guard['model_path'] && model.path == 'E:/MAC/OneDrive/Desktop/1.skp'
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
raise 'Missing guarded SP20 pair' unless guard['products'].length == 2
products = guard['products'].map { |g| app::Assembly.new(model, g['id']) }
data = JSON.parse(File.read(File.join(root, 'outputs/sp20-levels-product.json'), encoding: 'UTF-8'))['plan_results']
fingerprint = lambda { |g|
  Digest::SHA256.hexdigest(JSON.generate(g.entities.grep(Sketchup::Edge).map { |edge|
    edge.vertices.map { |v| v.position.to_a.map { |n| (n.to_mm * 10_000).round } }.sort
  }.uniq.sort))
}
guard['products'].each_with_index do |g, i|
  p = products[i]
  raise 'SP20 changed since verification' unless p.valid? && p.get_attribute(app::Model::DICT, 'analysis') == g['analysis']
  old = JSON.parse(g['analysis']); target = data.find { |item| item['plan_view_id'] == old['plan_view_id'] }
  # Relayout the already-imported revision; a later DWG save cannot change it.
  archived = File.join(app::Settings.library, 'sources', old['source_hash'], 'source.dwg')
  raise 'Imported revision changed' unless target && target['source_hash'] == old['source_hash'] && Digest::SHA256.file(archived).hexdigest == old['source_hash']
  app::PlanReference.validate(target)
  g['references'].each do |r|
    entity = model.find_entity_by_persistent_id(r['id'])
    raise 'CAD changed since verification' unless entity && entity.transformation.to_a == r['transform'] && fingerprint.call(entity) == r['geometry'] && entity.entities.all? { |e| e.is_a?(Sketchup::Edge) }
  end
end
first = products.first; full = data.find { |p| p['plan_reference']['scope'] == 'all_views' }['plan_reference']
refs = guard['products'].first['references'].to_h { |r| [r['view_id'], model.find_entity_by_persistent_id(r['id'])] }
raise 'Incomplete reference map' unless full['views'].all? { |v| refs[v['id']] }
duplicate = model.find_entity_by_persistent_id(guard['products'].last['references'].first['id'])
raise 'Unexpected shared reference' if refs.values.include?(duplicate)
affected = refs.values.map(&:persistent_id) + [duplicate.persistent_id]
baseline = model.entities.reject { |e| affected.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a; sha = Digest::SHA256.file(model.path).hexdigest
repair = app::Ids.uuid; library = app::Settings.library
guard['products'].each do |g|
  g['references'].each do |r|
    path = File.join(library, 'skp', "#{repair}-cad-#{r['id']}-before.skp")
    raise 'Backup failed' unless model.find_entity_by_persistent_id(r['id']).definition.save_as(path)
    r['snapshot'] = path
  end
end
app::Storage.write_json(File.join(library, 'repairs', "#{repair}-sp20-reference-before.json"), guard)
model.start_operation('CAD2Module: Xếp Cao Độ CAD SP20', true)
begin
  full['views'].each do |view|
    group = refs.fetch(view['id'])
    group.transformation = first.transformation * app::CadViews.transform(view, full['plan_bounds_mm'])
    group.set_attribute(app::Model::DICT, 'alignment', view['alignment'])
    next unless view['level']
    group.set_attribute(app::Model::DICT, 'level_status', view['level']['status'])
    group.set_attribute(app::Model::DICT, 'level_mm', view['z_mm'])
  end
  products.each_with_index do |p, i|
    old = JSON.parse(guard['products'][i]['analysis']); target = data.find { |c| c['plan_view_id'] == old['plan_view_id'] }
    %w[plan_reference cad_reference_level cad_reference_levels cad_reference_offset_mm cad_reference_shared cad_reference_reserved_width_mm].each do |key|
      target.key?(key) ? old[key] = target[key] : old.delete(key)
    end
    p.set_attribute(app::Model::DICT, 'analysis', JSON.generate(old))
    p.set_attribute(app::Model::DICT, 'plan_reference_id', refs.fetch(old['plan_view_id']).persistent_id)
  end
  duplicate.erase!
  plans = full['views'].select { |v| v['role'] == 'plan' }.map { |v| refs.fetch(v['id']) }
  raise 'Repair did not stack' unless plans.map { |g| g.bounds.min.z.to_mm.round(3) } == [0, 1000] &&
                                    plans[0].bounds.min.to_a.first(2).zip(plans[1].bounds.min.to_a.first(2)).all? { |a, b| (a - b).abs < 0.00001 }
  raise 'Other geometry changed' unless baseline == model.entities.reject { |e| affected.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
model.selection.clear; model.selection.add(selection.select(&:valid?))
raise 'Working file changed' unless Digest::SHA256.file(model.path).hexdigest == sha
app::Storage.event(library, 'kind' => 'cad_reference_relayout', 'code' => 'SP20', 'repair_id' => repair,
                            'product_ids' => products.map(&:persistent_id), 'provisional_levels_mm' => [0, 1000], 'before' => guard)
result = { passed: true, repair_id: repair, provisional_levels_mm: [0, 1000], same_xy: true, reference_groups: refs.values.map(&:persistent_id),
           duplicate_removed: affected.last, module_and_other_geometry_preserved: true, model_saved: false }
app::Storage.write_json(File.join(root, 'outputs/sp20-levels-live-repair-result.json'), result)
app.publish
puts JSON.generate(result)
