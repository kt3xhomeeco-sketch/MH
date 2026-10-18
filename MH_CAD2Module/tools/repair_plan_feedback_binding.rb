# frozen_string_literal: true

# One-time repair of the user's externally drawn boxes, not a runtime recogniser.
app = MH::CAD2Module
model = Sketchup.active_model
raise 'Wrong working model' unless Process.pid == 25728 && model.path == 'E:\\MAC\\OneDrive\\Desktop\\1.skp'
raise 'Wait for current work' if app::Jobs.busy? || app::Corrections.active? || model.active_path
target = model.find_entity_by_persistent_id(973702)
wrong = model.find_entity_by_persistent_id(968169)
raise 'Expected products missing' unless target&.valid? && wrong&.valid?
root = target.get_attribute(app::Model::DICT, 'library')
path = File.join(root, 'history', '20261018T121202217049-6c8a9945-2113-7ffe-dae8-2ba38d1bcc4b.json')
original = JSON.parse(File.read(path, encoding: 'UTF-8'))
analysis = JSON.parse(target.get_attribute(app::Model::DICT, 'analysis'))
raise 'Target source changed' unless analysis['signature'] == '7a674cbf16413d478da8b3997c26c6de17efa58e64bd353e6fbe47873989313d'
raise 'Target already corrected' if analysis['manual_boxes']
inputs = original.fetch('manual_source_ids').map { |id| model.find_entity_by_persistent_id(id) }
raise 'Original external boxes missing' if inputs.any?(&:nil?)
capture = app::ManualBoxes.capture(model, target, inputs)
parts = app::ManualBoxes.parts(capture, analysis)
raise 'Unexpected user boxes' unless parts['bounds'] == [1310, 600, 1600] && capture['boxes'].length == 3
raise 'CAD anchors do not agree' unless app::ManualBoxes.plan_offset(parts, analysis) == [-18, -9]
excluded = [target.persistent_id, wrong.persistent_id]
unchanged = lambda do
  model.entities.reject { |e| excluded.include?(e.persistent_id) }.map do |e|
    [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?, app::Model.container?(e) ? e.transformation.to_a : nil]
  end
end
baseline = unchanged.call
wrong_before = app::Model.state(wrong)
wrong_snapshot = app::Storage.snapshot(root, wrong, "#{app::Ids.uuid}-misbound-before")
app::Corrections.begin_manual(target)
app::Corrections.instance_variable_get(:@session)[:relinked_from_event] = original['id']
model.selection.clear
model.selection.add(inputs)
accepted = app.accept_manual_boxes("binding-repair-#{app::Ids.uuid}", app::Corrections.status['id'])
raise 'Wrong repair event' unless accepted['relinked_from_event'] == original['id'] && accepted['plan_origin_offset_mm'] == [-18, -9]

# Restore the older product that the incorrect binding had modified.
model.start_operation('CAD2Module: Sửa Liên Kết', true)
operation = true
begin
  wrong.make_unique if wrong.definition.instances.length > 1
  old = wrong.definition.entities.select { |e| app::Model.container?(e) && %w[module trim_reference panel_part].include?(e.get_attribute(app::Model::DICT, 'role')) }
  state = original.fetch('before')
  state['modules'].each { |part| app::Model.module_instance(wrong.definition.entities, part) }
  Array(state['trim_parts']).each { |part| app::Model.reference_part(wrong.definition.entities, part) }
  Array(state['panel_parts']).each { |part| app::Model.panel_part(wrong.definition.entities, part) }
  old.each(&:erase!)
  wrong.transformation = Geom::Transformation.new(state['product_transform'])
  wrong.set_attribute(app::Model::DICT, 'analysis', JSON.generate(original['analysis']))
  after = app::Model.state(wrong)
  snapshot = app::Storage.snapshot(root, wrong, "#{app::Ids.uuid}-binding-restored")
  repair = app::Storage.event(root, 'kind' => 'binding_repair', 'status' => 'resolved',
                             'reason' => 'Gắn bộ box ngoài vào đúng CAD một khoang; khôi phục nguồn hai khoang bị gắn nhầm.',
                             'relinked_from_event' => original['id'], 'accepted_event' => accepted['id'],
                             'before' => wrong_before, 'after' => after, 'before_skp' => wrong_snapshot, 'skp' => snapshot)
  app::Storage.write_json(File.join(root, 'experience_exclusions', "#{original['id']}.json"),
                         'reason' => 'wrong_source_binding', 'replacement_event' => accepted['id'], 'repair_event' => repair['id'])
  model.commit_operation
  operation = false
ensure
  model.abort_operation if operation
end
raise 'Unrelated geometry changed' unless unchanged.call == baseline
built = target.definition.entities.select { |e| app::Model.container?(e) && %w[module trim_reference].include?(e.get_attribute(app::Model::DICT, 'role')) }
actual = built.map do |e|
  b = Geom::BoundingBox.new
  8.times { |i| b.add(e.definition.bounds.corner(i).transform(target.transformation * e.transformation)) }
  b.min.to_a.map(&:to_mm) + b.max.to_a.map(&:to_mm)
end.sort
expected = inputs.map { |e| e.bounds.min.to_a.map(&:to_mm) + e.bounds.max.to_a.map(&:to_mm) }.sort
raise 'Correct boxes moved from their measured CAD planes' unless actual.zip(expected).all? { |a, b| a.zip(b).all? { |x, y| (x - y).abs < 0.1 } }
app.instance_variable_set(:@last_built, { model: model, ids: [target.persistent_id] })
app.instance_variable_set(:@focused, analysis['code'])
app.instance_variable_set(:@focus_cad, false)
model.selection.clear
model.selection.add(target)
result = { 'status' => 'repaired', 'target_id' => target.persistent_id, 'accepted_event' => accepted['path'],
           'source_signature' => analysis['signature'], 'boxes' => 3, 'bounds' => app::Model.state(target)['bounds'],
           'source_offset_mm' => [-18, -9], 'world_boxes_match_user_originals' => true,
           'old_source_restored' => true, 'unrelated_geometry_unchanged' => true, 'original_boxes_preserved' => inputs.all?(&:valid?) }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'plan-feedback-binding-repair.json'), result)
app.publish('Đã gắn đúng bộ 3 khối ngoài vào CAD một khoang, khôi phục nguồn cũ bị gắn nhầm và lưu kinh nghiệm đúng nguồn.')
puts JSON.generate(result)
