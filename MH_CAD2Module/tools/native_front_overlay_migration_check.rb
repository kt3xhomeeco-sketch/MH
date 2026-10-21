# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
old = JSON.parse(File.read(File.join(root, 'outputs/sp25-user-latest-product.json'), encoding: 'UTF-8'))['plan_results'].first
fresh = JSON.parse(File.read(File.join(root, 'outputs/sp25-sections-product.json'), encoding: 'UTF-8'))['plan_results'].first
raise 'Wrong migration fixture' if old['plan_reference']['display_mode'] || fresh['plan_reference']['display_mode'] != 'front_overlay'
baseline = model.entities.map { |g| [g.persistent_id, g.bounds.min.to_a, g.bounds.max.to_a, g.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
ops = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
ops[:start_operation][0].call('CAD2Module: Kiểm Tra Chồng Mặt Đứng Cũ', true)
result = {}
begin
  ops.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qoverlay')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa) }
  old['code'] = fresh['code'] = 'SP99951'; old['activity_id'] = app::Ids.uuid
  built = app::Model.build(old, qa, app::Ids.uuid, model)
  groups = built.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
  by_view = groups.to_h { |g| [g.get_attribute(app::Model::DICT, 'view_id'), g] }
  opened = by_view['V06.1']; closed = by_view['V02.1']
  opened.delete_attribute(app::Model::DICT, 'cad_geometry_signature') # Actual0.23.0 groups have no fingerprint.
  box_state = built.members.map { |g| [g.persistent_id, g.transformation.to_a] }
  ids = groups.map(&:persistent_id); closed_transform = closed.transformation.to_a
  count = model.entities.length
  app::PlanReference.restore_missing(model, fresh, built, qa)
  raise 'Front did not move onto the closed front' unless (opened.bounds.min.x - closed.bounds.min.x).to_mm.abs < 0.01
  raise 'Boxes/IDs/closed front changed or scratch leaked' unless box_state == built.members.map { |g| [g.persistent_id, g.transformation.to_a] } && ids == built.get_attribute(app::Model::DICT, 'cad_reference_ids') && closed_transform == closed.transformation.to_a && model.entities.length == count
  transforms = groups.map { |g| g.transformation.to_a }
  raise 'Repeated migration changed state' unless app::PlanReference.restore_missing(model, fresh, built, qa).zero? && transforms == groups.map { |g| g.transformation.to_a }
  edited = by_view['V03.1-XZ']; edited.entities.add_line([0, 0, 1], [1, 0, 1])
  before = edited.transformation.to_a
  shifted = by_view['V07.1-XZ']; shifted.transform!(Geom::Transformation.translation([1, 2, 0]))
  shifted_before = shifted.transformation.to_a
  desired = JSON.parse(JSON.generate(fresh)); desired['plan_reference']['display_copies'].each do |c|
    c['x_offset_mm'] += 50; c['display_placement']['min_x_mm'] += 50
  end
  # Exercise edit guards directly; desired spacing itself is intentionally not a production packet.
  changes = app::PlanReference.relayout_candidates(desired['plan_reference'], fresh['plan_reference'], built, by_view.transform_values { |g| [g] })
  moved, skipped = app::PlanReference.apply_relayout(model, changes, fresh['plan_reference'])
  raise 'Edited CAD was moved' unless before == edited.transformation.to_a && skipped.include?(edited.persistent_id)
  raise 'User-positioned CAD was moved' unless shifted_before == shifted.transformation.to_a && skipped.include?(shifted.persistent_id)
  result = { passed: true, legacy_front_overlaid: true, existing_ids_and_boxes_preserved: true, scratch_removed: true, idempotent: true, edited_cad_preserved: true, other_unedited_copies_moved: moved.length }
ensure
  app::Settings.define_singleton_method(:read, read)
  ops.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  ops[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |g| [g.persistent_id, g.bounds.min.to_a, g.bounds.max.to_a, g.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_state_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/front-overlay-migration-native-result.json'), result)
puts JSON.generate(result)
