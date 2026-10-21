# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
state = %i[@activity_focus @history_product @manual_acceptance @last_built @focus_cad @message].to_h { |key| [key, app.instance_variable_get(key)] }
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
manager = app.method(:manager)
enqueue = app::PlanRules.method(:enqueue)
inputbox = UI.method(:inputbox)
root = File.join(app::Settings::ROOT, 'outputs', 'w')
base = { 'status' => 'ready', 'name' => 'Vùng quét CAD', 'automatic_scan' => true, 'parser_version' => '0.2.3',
  'build_stages' => { 'plan' => true, 'elevation' => false }, 'bounds' => [818, 600, 1600],
  'envelope' => [900_000, 900_000, 900_818, 900_600], 'source_plan_envelope' => [900_000, 900_000, 900_818, 900_600],
  'placement' => { 'mode' => 'source_plan', 'plane' => 'XY', 'origin_mm' => [900_000, 900_000], 'plane_offset_mm' => 0 },
  'modules' => [{ 'id' => 'M1', 'origin' => [18, 0, 0], 'size' => [800, 600, 1600] }],
  'trim_parts' => [{ 'id' => 'T1', 'role' => 'plan_auxiliary', 'origin' => [0, 0, 0], 'size' => [18, 600, 1600] }] }
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Quá Trình SP', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app.define_singleton_method(:manager) { nil }
  queued = []
  app::PlanRules.define_singleton_method(:enqueue) { |event| queued << event }
  built = %w[A B].each_with_index.map do |letter, index|
    analysis = JSON.parse(JSON.generate(base)).merge('code' => "SCAN-NATIVE-#{letter}", 'activity_id' => "native-activity-#{letter}",
      'source_hash' => (index + 1).to_s * 64, 'signature' => (index + 1).to_s * 64)
    analysis['placement']['origin_mm'][0] += index * 3000
    app::Model.build(analysis, root, app::Ids.uuid, model)
  end
  left, right = built
  app.open_activity('native-activity-A')
  detail = app.public_state['activity_detail']
  raise 'Wrong timeline identity' unless detail['key'] == 'native-activity-A' && detail['events'].any? { |event| event['kind'] == 'build' }
  model.selection.clear; model.selection.add(right.members)
  app.dispatch('action' => 'select_activity', 'activity_key' => 'native-activity-A')
  raise 'Select chose another product' unless model.selection.to_a.sort_by(&:persistent_id) == left.members.sort_by(&:persistent_id)
  module_group = left.members.find { |part| part.get_attribute(app::Model::DICT, 'role') == 'module' }
  model.selection.clear; model.selection.add(right.members)
  app.dispatch('action' => 'select_module', 'activity_key' => 'native-activity-A', 'id' => module_group.persistent_id)
  raise 'Module table followed another product selection' unless model.selection.to_a == [module_group]
  model.selection.clear; model.selection.add(right.members)
  app.dispatch('action' => 'wrong', 'activity_key' => 'native-activity-A')
  raise 'Sai followed current selection instead of row' unless left.members.all?(&:hidden?) && right.members.none?(&:hidden?)
  inputs = [[0, 18], [18, 800]].map do |x, width|
    group = app::Model.cube(model.entities, 'id' => "manual-#{x}", 'origin' => [0, 0, 0], 'size' => [width, 600, 1600])
    group.transformation = Geom::Transformation.translation([(920_000 + x).mm, 920_000.mm, 0])
    group
  end
  model.selection.clear; model.selection.add(inputs)
  session = app::Corrections.status['id']
  begin
    app.dispatch('action' => 'accept_manual_boxes', 'activity_key' => 'native-activity-B', 'request_id' => 'wrong-row', 'session_id' => session)
    raise 'Wrong-row acceptance was not rejected'
  rescue ArgumentError
    raise 'Wrong-row check lost manual selection' unless model.selection.map(&:persistent_id).sort == inputs.map(&:persistent_id).sort && app::Corrections.status['id'] == session
  end
  packet = { 'action' => 'accept_manual_boxes', 'activity_key' => 'native-activity-A', 'request_id' => app::Ids.uuid, 'session_id' => session }
  event = app.dispatch(packet)
  raise 'Acceptance selected generated boxes before capture' unless event['manual_source_ids'].sort == inputs.map(&:persistent_id).sort
  raise 'Learning not queued' unless queued == [event]
  raise 'Acknowledgement not bound to row' unless app.instance_variable_get(:@manual_acceptance)['activity_key'] == 'native-activity-A'
  files = Dir.glob(File.join(root, 'experiences', '**', '*.json'))
  app.dispatch(packet)
  raise 'Retry wrote another experience' unless files == Dir.glob(File.join(root, 'experiences', '**', '*.json'))
  right.erase!
  begin
    app.dispatch('action' => 'select_activity', 'activity_key' => 'native-activity-B')
    raise 'Deleted output selected another product'
  rescue ArgumentError
    # No fallback to left or last-built.
  end
  left.members.find { |part| part.get_attribute(app::Model::DICT, 'role') == 'trim_reference' }.erase!
  app.dispatch('action' => 'select_activity', 'activity_key' => 'native-activity-A')
  raise 'Select included deleted parts/manual inputs' unless model.selection.to_a == left.members && left.members.length == 1 && (model.selection.to_a & inputs).empty?
  failed = JSON.parse(JSON.generate(base)).merge('code' => 'SCAN-NATIVE-RECOVER', 'activity_id' => 'native-recover',
    'status' => 'needs_review', 'error' => 'Temporary failed source', 'signature' => '4' * 64, 'source_hash' => '4' * 64)
  app::Storage.event(root, 'kind' => 'scan', 'analysis' => failed)
  UI.define_singleton_method(:inputbox) { |*_args| [818, 600, 1600] }
  app.dispatch('action' => 'begin_correction', 'activity_key' => 'native-recover')
  raise 'Failed source recovery lost row identity' unless app::Corrections.status['activity_id'] == 'native-recover' && app.public_state.dig('activity_detail', 'key') == 'native-recover'
  app::Corrections.finish
ensure
  app::Corrections.cancel_manual if app::Corrections.active? && app::Corrections.status['manual']
  app.define_singleton_method(:manager, manager)
  app::PlanRules.define_singleton_method(:enqueue, enqueue)
  UI.define_singleton_method(:inputbox, inputbox)
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
  state.each { |key, value| app.instance_variable_set(key, value) }
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Assembly metadata changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { 'status' => 'passed', 'row_select' => true, 'wrong_targets_row' => true, 'wrong_row_rejected' => true,
  'external_selection_preserved' => true, 'acceptance_idempotent' => true, 'deleted_outputs_safe' => true, 'user_geometry_unchanged' => true }
result['failed_source_recovery_same_row'] = true
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'activity-native-result.json'), result)
puts JSON.generate(result)
