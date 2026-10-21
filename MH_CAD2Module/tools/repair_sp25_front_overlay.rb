# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
raise 'Wrong model' unless model.path.tr('\\', '/').casecmp('E:/MAC/OneDrive/Desktop/1.skp').zero?
owner = app::Model.products(model).find { |p| p.persistent_id == 'assembly-6848aaec-ec50-ac98-7b02-4b7f480b056a' }
raise 'SP25 owner no longer exists' unless owner && owner.get_attribute(app::Model::DICT, 'job_id') == '9eb649ce-84b6-3d26-6267-13040297de57'
ids = [619394, 620734, 621206, 621363, 621548, 621741, 622120, 622239, 622331, 622486, 622605]
raise 'Source membership changed' unless owner.get_attribute(app::Model::DICT, 'cad_reference_ids') == ids
data = JSON.parse(File.read(File.join(root, 'outputs/sp25-sections-product.json'), encoding: 'UTF-8'))['plan_results'].first
old = JSON.parse(owner.get_attribute(app::Model::DICT, 'analysis'))
raise 'Already repaired or source changed' unless old.dig('plan_reference', 'display_mode').nil? && old['source_hash'] == data['source_hash']
groups = ids.map { |id| model.find_entity_by_persistent_id(id) }
raise 'Missing/foreign source group' unless groups.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model && g.get_attribute(app::Model::DICT, 'product_id') == owner.persistent_id }
existing = groups.group_by { |g| g.get_attribute(app::Model::DICT, 'view_id') }
changes = app::PlanReference.relayout_candidates(data['plan_reference'], old['plan_reference'], owner, existing)
moving = [621741, 622331, 622486, 622605]
raise 'Unexpected proposed change' unless changes.map { |c| c[:group].persistent_id }.sort == moving.sort && changes.all? { |c| !c[:group].locked? && app::PlanReference.same_transform?(c[:group].transformation, c[:before]) }
snapshot = lambda do |entity|
  [entity.persistent_id, entity.bounds.min.to_a, entity.bounds.max.to_a, entity.hidden?, entity.respond_to?(:transformation) ? entity.transformation.to_a : nil, entity.layer.name]
end
protected_before = model.entities.reject { |e| moving.include?(e.persistent_id) }.map(&snapshot)
entity_ids = model.entities.map(&:persistent_id); selection = model.selection.to_a; camera = model.active_view.camera
camera_before = [camera.eye.to_a, camera.target.to_a, camera.up.to_a]
box_before = app::Model.products(model).flat_map(&:members).map(&snapshot)
sha = Digest::SHA256.file(model.path).hexdigest
backup = File.join(root, 'outputs', "sp25-overlay-before-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json")
app::Storage.write_json(backup, 'model' => model.path, 'owner' => owner.persistent_id, 'source_hash' => old['source_hash'],
  'analysis' => old, 'groups' => groups.map { |g| { 'id' => g.persistent_id, 'transform' => g.transformation.to_a, 'name' => g.name, 'tag' => g.layer.name } })
ops = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
event = app::Storage.method(:event); queued = []; committed = false
ops[:start_operation][0].call('CAD2Module: Chồng Mặt Đứng SP25', true)
begin
  ops.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app::Storage.define_singleton_method(:event) { |*args| queued << args }
  app::PlanReference.restore_missing(model, data, owner, app::Settings.library(app::Settings.read(model)))
  by_view = groups.to_h { |g| [g.get_attribute(app::Model::DICT, 'view_id'), g] }
  raise 'Fronts did not overlay' unless (by_view['V06.1'].bounds.min.x - by_view['V02.1'].bounds.min.x).to_mm.abs < 0.01
  raise 'Source geometry was edited; repair canceled' unless queued.last.last['preserved_edited_ids'].empty? && queued.last.last['moved_views'].map { |v| v['id'] }.sort == moving.sort
  raise 'Protected geometry changed' unless entity_ids == model.entities.map(&:persistent_id) && protected_before == model.entities.reject { |e| moving.include?(e.persistent_id) }.map(&snapshot) && box_before == app::Model.products(model).flat_map(&:members).map(&snapshot)
  raise 'Selection/camera/file changed' unless selection == model.selection.to_a && camera_before == [camera.eye.to_a, camera.target.to_a, camera.up.to_a] && sha == Digest::SHA256.file(model.path).hexdigest
  ops[:commit_operation][0].call; committed = true
ensure
  app::Storage.define_singleton_method(:event, event)
  ops.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  ops[:abort_operation][0].call unless committed
end
queued.each { |args| event.call(*args) }
result = { passed: true, front_overlay: true, moved_ids: moving, same_group_ids: true, boxes_and_other_geometry_preserved: true,
           source_signature_checked: true, backup: backup, selection_camera_preserved: true, model_saved: false }
app::Storage.write_json(File.join(root, 'outputs/sp25-overlay-live-repair-result.json'), result)
puts JSON.generate(result)
