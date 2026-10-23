# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT; dict = app::Model::DICT
raise 'Wrong model/busy' unless model.path.tr('\\', '/').casecmp?('E:/MAC/OneDrive/Desktop/2.skp') && !app::Jobs.busy? && !app::Corrections.active? && !model.active_path
id = 'assembly-bdb68e3b-2dc7-e917-8dfc-cb6e078bf77c'
instance = app::Model.products(model).find { |p| p.persistent_id == id }
raise 'Original product was deleted; do not recreate it' unless instance
packet = JSON.parse(File.read(File.join(root, 'outputs/sp25-archived-bands-product.json'), encoding: 'UTF-8'))['plan_results'].first
old = JSON.parse(instance.get_attribute(dict, 'analysis'))
raise 'Different source or CAD geometry' unless old['code'] == 'SP25' && old['source_hash'] == packet['source_hash'] &&
  old['cad_reference_outlines'] == packet['cad_reference_outlines'] && old['product_height']['source_signature'] == packet['product_height']['source_signature']
packet['build_auxiliary'] = old['build_auxiliary']
refs = instance.get_attribute(dict, 'cad_reference_ids').map { |pid| model.find_entity_by_persistent_id(pid) }
cad = refs.map { |g| [g.persistent_id, g.transformation.to_a, g.entities.length, g.hidden?] }
transform = instance.transformation.to_a; source_ids = model.entities.map(&:persistent_id) - instance.members.map(&:persistent_id)
selection = model.selection.to_a; old_members = instance.members
sha = Digest::SHA256.file(model.path).hexdigest
changed = app::PartialPlan.refresh_preview(model, instance, packet, instance.get_attribute(dict, 'library'))
raise 'No change' unless changed
if !selection.empty? && (selection - old_members).empty?
  model.selection.clear; model.selection.add(instance.members)
end
raise 'CAD/model placement changed' unless cad == refs.map { |g| [g.persistent_id, g.transformation.to_a, g.entities.length, g.hidden?] } &&
  transform == instance.transformation.to_a && (model.entities.map(&:persistent_id) - instance.members.map(&:persistent_id)) == source_ids
raise 'Model saved unexpectedly' unless sha == Digest::SHA256.file(model.path).hexdigest
result = { passed: true, assembly_id: id, source_revision: old['source_hash'], refreshed_from_archived_source: true,
           model: model.path, file_saved: false, cad_preserved: true, modules: app::Model.state(instance)['modules'].map { |p| p.slice('name', 'origin', 'size') } }
app::Storage.write_json(File.join(root, 'outputs/sp25-bands-live-result.json'), result)
puts JSON.generate(result)
