# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
original_activity_focus = app.instance_variable_get(:@activity_focus)
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
product = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'sp42-origin-fixed-analysis.json'), encoding: 'UTF-8'))
reference = Dir.glob(File.join(app::Settings::ROOT, 'library', 'experiences', '**', '*.json')).filter_map do |file|
  row = JSON.parse(File.read(file, encoding: 'UTF-8'))
  row if row['id'] == 'f85bb3d1-5d8d-a64c-f16e-ff77c2979786'
end.first
raise 'Missing accepted source' unless reference
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
last_built = app.instance_variable_get(:@last_built)
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
root = File.join(app::Settings::ROOT, 'outputs', 's')
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Gốc SP42', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  product['code'] = 'NATIVE-SP42-ORIGIN'; product['automatic_scan'] = false
  built = app::Model.build(product, root, app::Ids.uuid, model)
  raise 'Expected independent root Groups' unless built.is_a?(app::Assembly)
  children = built.definition.entities.select { |e| app::Model.container?(e) }
  raise 'Modules/auxiliaries still Components' unless children.length == 24 && children.all? { |e| e.is_a?(Sketchup::Group) && e.manifold? && e.parent == model }
  model.selection.clear; model.selection.add(children.first)
  raise 'Selected module lost its product' unless app::Model.selected_product == built
  app.instance_variable_set(:@last_built, { model: model, ids: [built.persistent_id] })
  model.selection.clear
  raise 'Latest flat product lost' unless app.correction_target == built
  frame = reference['analysis'].fetch('source_plan_envelope')
  shift = 2.times.map { |i| product['placement']['origin_mm'][i] - frame[i] }
  parts = product['modules'] + product['trim_parts']
  parts.each do |part|
    instance = children.find { |e| JSON.parse(e.get_attribute(app::Model::DICT, 'source_module', e.get_attribute(app::Model::DICT, 'source_part', '{}')))['id'] == part['id'] }
    original = model.find_entity_by_persistent_id(part.fetch('source_entity_id'))
    raise 'Original manual shape missing' unless original && original.valid?
    [0, 1].each do |axis|
      actual = [instance.bounds.min[axis], instance.bounds.max[axis]].map { |v| v.to_mm }
      expected = [original.bounds.min[axis], original.bounds.max[axis]].map { |v| v.to_mm + shift[axis] }
      raise "Wrong world placement for #{part['id']}" unless actual.zip(expected).all? { |a, b| (a - b).abs < 0.01 }
    end
  end
  curves = children.flat_map { |e| e.definition.entities.grep(Sketchup::Edge).map(&:curve).compact.uniq.grep(Sketchup::ArcCurve) }
  raise 'R150 lost' unless curves.length == 2 && curves.all? { |c| (c.radius.to_mm - 150).abs < 0.01 }
  built.erase!
  # Acceptance must repair the same partial-origin case before a future replay.
  source = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'sp42-baseline-analysis.json'), encoding: 'UTF-8'))
  source['code'] = 'NATIVE-SP42-ACCEPT'; source['automatic_scan'] = false
  built = app::Model.build(source, root, app::Ids.uuid, model)
  translation = Geom::Transformation.translation([*shift.map(&:mm), 0])
  inputs = reference['manual_source_ids'].map { |id| model.find_entity_by_persistent_id(id) }
  copies = inputs.map { |e| model.entities.add_instance(e.definition, translation * e.transformation) }
  app::Corrections.begin_manual(built)
  model.selection.clear; model.selection.add(copies)
  event = app::Corrections.accept_manual
  raise 'Acceptance retains partial origin' unless built.transformation.origin.to_a.map(&:to_mm)[0, 2].zip(product['placement']['origin_mm']).all? { |a, b| (a - b).abs < 0.01 }
  raise 'New origin basis not saved' unless event['plan_origin_basis'] == 'source_plan_envelope'
  raise 'Output still uses Components' unless built.definition.entities.select { |e| app::Model.container?(e) }.all? { |e| e.is_a?(Sketchup::Group) }
  app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp42-native-accepted-event.json'), event)
ensure
  app.instance_variable_set(:@activity_focus, original_activity_focus)
  app::Corrections.cancel_manual if app::Corrections.active?
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
  app.instance_variable_set(:@last_built, last_built)
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
result = { 'status' => 'passed', 'placement_mm' => product['placement']['origin_mm'], 'groups' => 24, 'no_product_container' => true,
           'world_bounds_match_user_shapes' => true, 'r150_preserved' => true, 'acceptance_rebased' => true,
           'original_geometry_unchanged' => true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp42-native-origin-result.json'), result)
puts JSON.generate(result)
