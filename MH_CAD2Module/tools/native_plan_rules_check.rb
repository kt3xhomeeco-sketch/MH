# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
original_activity_focus = app.instance_variable_get(:@activity_focus)
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
fixture = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'plan-rule-native-fixture.json'), encoding: 'UTF-8'))
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
last_built = app.instance_variable_get(:@last_built)
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
root = File.join(app::Settings::ROOT, 'outputs', 'l')
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Quy Tắc Tự Học', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  fixture['products'].each_with_index do |analysis, index|
    product = app::Model.build(analysis, root, app::Ids.uuid, model)
    raise 'Expected independent Groups' unless product.is_a?(app::Assembly) && product.members.length == 2 && product.members.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model && g.manifold? }
    state = app::Model.state(product)
    actual = state['modules'].sort_by { |part| part['origin'][0] }
    expected = analysis['modules']
    actual.zip(expected).each do |a, b|
      raise 'Unseen dimensions not remeasured' unless (a['origin'] + a['size']).zip(b['origin'] + b['size']).all? { |x, y| (x - y).abs < 0.01 }
    end
    left = product.members.min_by { |g| g.bounds.min.x }
    raise 'World position changed' unless (left.bounds.min.x.to_mm - 30_000).abs < 0.01 && (left.bounds.min.y.to_mm - 40_000).abs < 0.01 && (left.bounds.min.z.to_mm - 73).abs < 0.01
    if index == 1
      arcs = left.entities.grep(Sketchup::Edge).filter_map(&:curve).grep(Sketchup::ArcCurve).uniq
      raise 'Learned circular geometry flattened' unless arcs.length == 2 && arcs.all? { |arc| (arc.radius.to_mm - 140).abs < 0.01 }
    end
    model.selection.clear; model.selection.add(left)
    raise 'Provenance lost' unless app.public_state.dig('focused', 'learning', 'mode') == 'plan_rule'
  end
ensure
  app.instance_variable_set(:@activity_focus, original_activity_focus)
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
  app.instance_variable_set(:@last_built, last_built)
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Temporary assembly metadata leaked' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { 'status' => 'passed', 'independent_root_groups' => true, 'unseen_dimensions' => true,
  'cad_origin_and_offset' => true, 'native_r140_arc_curves' => true, 'provenance' => true, 'user_geometry_unchanged' => true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'plan-rules-native-result.json'), result)
puts JSON.generate(result)
