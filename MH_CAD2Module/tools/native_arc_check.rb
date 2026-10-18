# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing' if app::Jobs.busy? || model.active_path
session = app::Corrections.instance_variable_get(:@session)
selection = model.selection.to_a
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
product = JSON.parse(File.read(File.join(app::Settings::ROOT, 'outputs', 'sp41-arc-analysis.json'), encoding: 'UTF-8'))
originals = %i[start_operation commit_operation abort_operation].to_h do |name|
  [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]]
end
root = File.join(app::Settings::ROOT, 'outputs', 'a')
results = []
observer = app::Corrections.instance_variable_get(:@observer)
fixture_session = false
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Arc', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  product['code'] = 'NATIVE-ARC-CHECK'; product['automatic_scan'] = false
  built = app::Model.build(product, root, app::Ids.uuid, model)
  state = app::Model.state(built)
  raise 'CAD end not reconstructed' unless state['modules'].length == 3 && state['modules'].last['size'] == [120, 350, 1600]
  curved = built.definition.entities.find { |e| e.get_attribute(app::Model::DICT, 'module_id') == 'M03' }
  curves = curved.definition.entities.grep(Sketchup::Edge).map(&:curve).compact.uniq
  arcs = curves.grep(Sketchup::ArcCurve)
  raise 'Rounded CAD end is not ArcCurve solid' unless curved.manifold? && arcs.length == 2 && arcs.all? { |a| (a.radius.to_mm - 100).abs < 0.01 }
  results << { 'lane' => 'cad', 'arcs' => arcs.length, 'radius_mm' => arcs.first.radius.to_mm, 'manifold' => true }
  source = session && session[:product]
  raise 'Expected current SP41 correction' unless source && source.valid?
  inputs = [976216, 976271, 977325, 977381].map { |id| model.find_entity_by_persistent_id(id) }
  raise 'Manual inputs changed' unless inputs.all?(&:valid?)
  capture = app::ManualBoxes.capture(model, source, inputs)
  parts = app::ManualBoxes.parts(capture, product)
  raise 'Manual rounded profile lost' unless parts['modules'].length == 3 && parts['trim_parts'].length == 1 && parts['bounds'] == [2860, 350, 1600]
  odd = model.entities.add_group
  frame = Geom::Transformation.translation([330.mm, -470.mm, 250.mm]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, 37.degrees) * Geom::Transformation.scaling(2, 0.5, -1)
  odd.entities.add_instance(inputs.last.definition, frame.inverse * inputs.last.transformation)
  odd.transformation = frame
  odd_capture = app::ManualBoxes.capture(model, source, [odd])['boxes'].first
  raise 'Rounded capture depends on local axes' unless odd_capture['size'] == [118, 350, 1600] && odd_capture['plan_profile']
  odd.erase!
  rounded = parts['modules'].find { |m| m['plan_profile'] }
  # Test the native corrected profile in both orientations; normal reversal must
  # retain each rounded corner as a single ArcCurve, even for clockwise input.
  [false, true].each do |reverse|
    part = JSON.parse(JSON.generate(rounded))
    if reverse
      part['plan_profile']['segments'].reverse!
      part['plan_profile']['segments'].each do |segment|
        segment['start'], segment['end'] = segment['end'], segment['start']
        segment['sweep'] *= -1 if segment['type'] == 'arc'
      end
    end
    part['id'] = "ROUND-#{reverse}"
    instance = app::Model.cube(built.definition.entities, part)
    arcs = instance.definition.entities.grep(Sketchup::Edge).map(&:curve).compact.uniq.grep(Sketchup::ArcCurve)
    raise 'Manual corner split or flattened' unless instance.manifold? && arcs.length == 2 && arcs.all? { |a| a.edges.length == 40 }
    results << { 'lane' => 'manual', 'reverse' => reverse, 'arcs' => arcs.length, 'radius_mm' => arcs.first.radius.to_mm, 'manifold' => true }
    instance.erase!
  end
  app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'sp41-arc-accepted-parts.json'), parts)
  # Exercise acceptance in an isolated session/library; original user inputs and
  # the active correction are restored after aborting all temporary geometry.
  model.remove_observer(observer) if observer
  app::Corrections.instance_variable_set(:@session, nil)
  fixture_session = true
  copies = inputs.map { |input| model.entities.add_instance(input.definition, input.transformation) }
  app::Corrections.begin_manual(built)
  model.selection.clear
  model.selection.add(copies)
  event = app::Corrections.accept_manual
  accepted = app::Model.state(built)
  rounded = built.definition.entities.find { |e| e.get_attribute(app::Model::DICT, 'module_id') == 'M3' }
  raise 'Accepted profile not rebuilt as arcs' unless rounded && rounded.manifold? && rounded.definition.entities.grep(Sketchup::Edge).map(&:curve).compact.uniq.grep(Sketchup::ArcCurve).length == 2
  raise 'Acceptance hid user originals' if inputs.any?(&:hidden?)
  raise 'Acceptance did not preserve source copies' unless copies.all?(&:hidden?)
  raise 'Accepted profile dimensions changed' unless accepted['bounds'] == [2860, 350, 1600]
  app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'arc-native-accepted-event.json'), event)
  results << { 'lane' => 'acceptance', 'accepted_event' => event['path'], 'profile_persisted' => true }

ensure
  if fixture_session
    app::Corrections.cancel_manual if app::Corrections.active?
    app::Corrections.instance_variable_set(:@session, session)
    model.add_observer(observer) if session && observer
  end
  originals.each do |name, (method, owned)|
    owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name)
  end
  originals[:abort_operation][0].call
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'User correction session changed' unless app::Corrections.instance_variable_get(:@session).equal?(session)
result = { 'status' => 'passed', 'cases' => results, 'source_bounds_mm' => product['bounds'], 'manual_bounds_mm' => parts['bounds'],
           'original_geometry_unchanged' => true, 'current_correction_preserved' => true }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'arc-native-result.json'), result)
puts JSON.generate(result)
