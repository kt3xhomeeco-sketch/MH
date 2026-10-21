# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT; dict = app::Model::DICT
raise 'Wrong captured session' unless Process.pid == 20_324 && model.path == 'E:\\MAC\\OneDrive\\Desktop\\2.skp'
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
%w[plan_reference.rb reference_build.rb].each { |f| load File.join(root, f) }
response = JSON.parse(File.read(File.join(root, 'library/jobs/61d75182-1b55-9e12-95bb-a9a2dfbc090f/response.json'), encoding: 'UTF-8'))
targets = response['analyses'].first['products'].find { |p| p['code'] == 'SP25' }['plan_results']
raise 'Unexpected SP25 source' unless targets.first.dig('plan_reference', 'views')&.length == 8 && targets.first.dig('plan_reference', 'display_copies')&.length == 3
products = targets.map do |p|
  matches = app::Model.products(model).select { |item| item.get_attribute(dict, 'code') == 'SP25' && item.get_attribute(dict, 'plan_view_id') == p['plan_view_id'] }
  raise 'SP25 boxes changed; no auto replacement' unless matches.length == 1 && JSON.parse(matches.first.get_attribute(dict, 'analysis'))['source_hash'] == p['source_hash']
  matches.first
end
primary = products.first
raise 'Wrong primary delivery' unless primary.get_attribute(dict, 'job_id') == 'a7a822b0-5b2c-7989-8e20-60b55d55a314'
refs = model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(dict, 'role') == 'plan_reference' && g.get_attribute(dict, 'code') == 'SP25' }
retained = refs.select { |g| g.get_attribute(dict, 'product_id') == primary.persistent_id }
raise 'Reference state changed' unless retained.length == 1 && retained.first.persistent_id == 613_203
fallback = refs.find { |g| g.persistent_id == 661_973 }
raise 'Unexpected partial fallback' unless fallback && fallback.get_attribute(dict, 'product_id') == products.last.persistent_id && fallback.get_attribute(dict, 'reference_scope') == 'plan'
fingerprint = lambda { |g| g.entities.grep(Sketchup::Edge).map { |e| e.vertices.map { |v| v.position.to_a.map { |n| (n.to_mm * 10_000).round } }.sort }.uniq.sort }
old = JSON.parse(products.last.get_attribute(dict, 'analysis')); source = old['plan_reference']
expected = products.last.transformation * app::CadViews.transform(source.merge('plane' => 'XY'), [])
raise 'User moved the partial fallback' unless fallback.transformation.to_a.zip(expected.to_a).all? { |a, b| (a - b).abs < 0.000001 }
model.start_operation('CAD2Module: kiểm tra CAD tạm SP25', true)
begin
  temp = model.entities.add_group
  app::PlanReference.draw(temp.entities, source['segments'])
  raise 'User edited partial CAD; preserve it' unless fingerprint.call(temp) == fingerprint.call(fallback)
ensure
  model.abort_operation
end
library = app::Settings.library; repair = app::Ids.uuid; sha = Digest::SHA256.file(model.path).hexdigest
archive = File.join(library, 'sources', targets.first['source_hash'], 'source.dwg')
raise 'Source archive changed' unless Digest::SHA256.file(archive).hexdigest == targets.first['source_hash']
backup = File.join(library, 'skp', "#{repair}-partial-B-B-before.skp")
raise 'Cannot back up partial CAD' unless fallback.definition.save_as(backup)
before = { 'pid' => Process.pid, 'path' => model.path, 'products' => products.map { |p| { 'id' => p.persistent_id, 'data' => p.data } },
           'fallback_id' => fallback.persistent_id, 'fallback_backup' => backup, 'retained_ref' => { 'id' => retained.first.persistent_id, 'transform' => retained.first.transformation.to_a, 'geometry' => fingerprint.call(retained.first) } }
app::Storage.write_json(File.join(library, 'repairs', "#{repair}-sp25-missing-before.json"), before)
before_ids = refs.map(&:persistent_id); selection = model.selection.to_a; selection_ids = selection.map(&:persistent_id); removed_id = fallback.persistent_id
baseline = model.entities.reject { |e| before_ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
owner = nil
outcomes = targets.map do |p|
  outcome = app::ReferenceBuild.call(p, library, '61d75182-1b55-9e12-95bb-a9a2dfbc090f', model, owner)
  owner = outcome[:owner]; outcome
end
raise 'Unexpected box creation' if outcomes.any? { |r| r[:created] }
ids = primary.get_attribute(dict, 'cad_reference_ids'); groups = ids.map { |id| model.find_entity_by_persistent_id(id) }
raise 'Source still incomplete' unless groups.length == 11 && groups.all?(&:valid?)
raise 'Surviving front changed' unless retained.first.transformation.to_a == before['retained_ref']['transform'] && fingerprint.call(retained.first) == before['retained_ref']['geometry']
replacement = app::PlanReference.shared_group(model, targets.last, primary)
model.start_operation('CAD2Module: bỏ bản mặt bằng tạm đã có bộ CAD đầy đủ', true)
begin
  fallback.erase!
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
raise 'Modules/other entities changed' unless baseline == model.entities.reject { |e| ids.include?(e.persistent_id) }.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
model.selection.clear; model.selection.add(selection.each_with_index.filter_map { |e, i| e.valid? ? e : (replacement if selection_ids[i] == removed_id) })
raise 'Model file saved' unless Digest::SHA256.file(model.path).hexdigest == sha
result = { passed: true, repair_id: repair, restored_groups: outcomes.sum { |r| r[:restored] }, complete_groups: groups.length,
           kept_front_id: retained.first.persistent_id, kept_box_ids: products.flat_map { |p| p.members.map(&:persistent_id) },
           removed_partial_fallback_id: removed_id, source_owner: primary.persistent_id, box_other_geometry_preserved: true, model_saved: false }
app::Storage.event(library, 'kind' => 'cad_reference_repair', 'code' => 'SP25', 'product_id' => primary.persistent_id, 'repair_id' => repair,
                            'reason' => 'Restore complete CAD despite existing boxes; share across retry jobs and replace verified cropped fallback.', 'result' => result)
app::Storage.write_json(File.join(root, 'outputs/sp25-missing-restored-result.json'), result)
app.publish
puts JSON.generate(result)
