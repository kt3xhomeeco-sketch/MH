# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
original_activity_focus = app.instance_variable_get(:@activity_focus)
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
original_enqueue = app::PlanRules.method(:enqueue)
queued_events = []
app::PlanRules.define_singleton_method(:enqueue) { |event| queued_events << event }
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
initial_acceptance = app.instance_variable_get(:@manual_acceptance)
initial_last_built = app.instance_variable_get(:@last_built)
root = File.join(app::Settings::ROOT, 'outputs', 'f')
analysis = { 'status' => 'ready', 'code' => 'NATIVE-FLAT-GROUPS', 'name' => 'Temporary', 'source_hash' => 'f' * 64,
  'signature' => 'f' * 64, 'parser_version' => '0.2.3', 'build_stages' => { 'plan' => true, 'elevation' => false },
  'bounds' => [818, 600, 1600], 'envelope' => [900_000, 900_000, 900_818, 900_600],
  'source_plan_envelope' => [900_000, 900_000, 900_818, 900_600],
  'placement' => { 'mode' => 'source_plan', 'plane' => 'XY', 'origin_mm' => [900_000, 900_000], 'plane_offset_mm' => 0 },
  'modules' => [{ 'id' => 'M1', 'origin' => [18, 0, 0], 'size' => [800, 600, 1600] }],
  'trim_parts' => [{ 'id' => 'T1', 'role' => 'plan_auxiliary', 'origin' => [0, 0, 0], 'size' => [18, 600, 1600] }] }
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Group Riêng', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  product = app::Model.build(analysis, root, app::Ids.uuid, model)
  raise 'Unexpected container' unless product.is_a?(app::Assembly) && product.members.length == 2
  raise 'Groups not at model root' unless product.members.all? { |e| e.is_a?(Sketchup::Group) && e.parent == model }
  restored = app::Assembly.all(model).find { |p| p.persistent_id == product.persistent_id }
  raise 'Membership did not persist' unless restored && restored == product
  module_group = product.members.find { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }
  model.selection.clear; model.selection.add(module_group)
  raise 'Selected Group has no product' unless app::Model.selected_product == product
  app.select_module(module_group.persistent_id)
  raise 'Selection unnecessarily enters a container' if model.active_path
  app::Corrections.begin_session(product, 'Native flat group verification')
  app::Corrections.resize([800, 600, 1600], [18, 0, 0])
  module_group = product.members.find { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }
  model.selection.clear; model.selection.add(module_group)
  app::Corrections.split(0, 400)
  modules = product.members.select { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }
  raise 'Split lost ownership/world position' unless modules.length == 2 && app::Model.state(product)['modules'].map { |m| m['origin'][0] }.sort == [18, 418]
  model.selection.clear; model.selection.add(modules)
  app::Corrections.merge
  module_group = product.members.find { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }
  model.selection.clear; model.selection.add(module_group)
  template = File.join(root, 'template.skp')
  module_group.definition.save_as(template)
  app::Templates.replace(template)
  raise 'Template replaced root Group with Component' unless product.members.all? { |e| e.is_a?(Sketchup::Group) }
  app::Corrections.finish
  module_group = product.members.find { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }
  copied = module_group.copy
  copied.transform!(Geom::Transformation.translation([4000.mm, 0, 0]))
  raise 'Manual copy silently joined the source product' unless product.members.length == 2
  raise 'A copied Group cannot be selected as corrected input' unless app::ManualBoxes.capture(model, product, [copied])['boxes'].length == 1
  copied.erase!
  on_side = JSON.parse(JSON.generate(analysis))
  on_side['code'] = 'NATIVE-FLAT-XZ'
  on_side['placement'].merge!('plane' => 'XZ', 'plane_offset_mm' => 52)
  side_product = app::Model.build(on_side, root, app::Ids.uuid, model)
  raise 'Non-XY frame lost' unless app::Model.state(side_product)['modules'].first['origin'] == [18, 0, 0]
  side_module = side_product.members.find { |e| e.get_attribute(app::Model::DICT, 'role') == 'module' }
  raise 'Non-XY world placement wrong' unless (side_module.bounds.min.x.to_mm - 900_018).abs < 0.01 && (side_module.bounds.max.y.to_mm - 52).abs < 0.01
  side_product.erase!
  raise 'Local frame shifted' unless app::Model.state(product)['modules'].first['origin'] == [18, 0, 0]
  auxiliary = product.members.find { |e| e.get_attribute(app::Model::DICT, 'role') == 'trim_reference' }
  auxiliary.hidden = true
  app::Corrections.begin_manual(product)
  raise 'Sai did not hide product Groups' unless product.members.all?(&:hidden?)
  app::Corrections.cancel_manual
  raise 'Cancel lost individual visibility' unless auxiliary.hidden? && product.members.any? { |e| !e.hidden? }
  auxiliary.hidden = false
  copies = [[0, 18], [18, 800]].map do |x, width|
    group = app::Model.cube(model.entities, 'id' => "input-#{x}", 'origin' => [0, 0, 0], 'size' => [width, 600, 1600])
    group.transformation = Geom::Transformation.translation([(910_000 + x).mm, 910_000.mm, 0])
    group
  end
  app::Corrections.begin_manual(product)
  model.selection.clear; model.selection.add(copies)
  event = app.accept_manual_boxes('native-flat-accept', app::Corrections.status['id'])
  raise 'Acceptance did not queue learning exactly once' unless queued_events == [event]
  raise 'Missing saved acknowledgement' unless app.instance_variable_get(:@manual_acceptance)['status'] == 'saved'
  raise 'Acceptance did not select independent Groups' unless model.selection.to_a.sort_by(&:persistent_id) == product.members.sort_by(&:persistent_id)
  raise 'Acceptance lost Groups' unless product.members.all? { |e| e.is_a?(Sketchup::Group) && e.parent == model }
  definition = model.definitions.load(event['skp'])
  saved = definition.entities.select { |e| app::Model.container?(e) }
  raise 'Product snapshot lost independent parts' unless saved.length == 2 && saved.all? { |e| e.is_a?(Sketchup::Group) }
  model.definitions.remove(definition)
ensure
  app.instance_variable_set(:@activity_focus, original_activity_focus)
  app::PlanRules.define_singleton_method(:enqueue, original_enqueue)
  app::Corrections.cancel_manual if app::Corrections.active? && app::Corrections.status['manual']
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
  app.instance_variable_set(:@manual_acceptance, initial_acceptance)
  app.instance_variable_set(:@last_built, initial_last_built)
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Temporary product metadata leaked' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { 'status' => 'passed', 'independent_root_groups' => true, 'membership_persisted' => true,
  'resize_split_merge' => true, 'template_group' => true, 'manual_acceptance' => true, 'saved_snapshot_groups' => true,
  'cancel_restores_individual_visibility' => true, 'original_geometry_and_registry_unchanged' => true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'flat-groups-native-result.json'), result)
puts JSON.generate(result)
