# frozen_string_literal: true

require 'json'
app = MH::CAD2Module
model = Sketchup.active_model
original_activity_focus = app.instance_variable_get(:@activity_focus)
raise 'Wait for job/edit/correction' if app::Jobs.busy? || model.active_path || app::Corrections.active?
original_enqueue = app::PlanRules.method(:enqueue)
queued_events = []
app::PlanRules.define_singleton_method(:enqueue) { |event| queued_events << event }
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
initial_acceptance = app.instance_variable_get(:@manual_acceptance)
initial_last_built = app.instance_variable_get(:@last_built)
library = File.join(app::Settings::ROOT, 'outputs', 'm')
originals = %i[start_operation commit_operation abort_operation].to_h do |name|
  [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]]
end
originals[:start_operation][0].call('CAD2Module: Test Box', true)
operation = true
begin
  # A real native operation contains the fixture and all API writes. Suppress
  # nested operation boundaries solely in this test so one abort removes it all.
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  analysis = { 'code' => 'NATIVE-MANUAL-TEST', 'name' => 'Temporary test', 'parser_version' => '0.2.3',
               'signature' => 'f' * 64, 'source_hash' => 'f' * 64, 'bounds' => [1818, 600, 1600],
               'build_stages' => { 'plan' => true, 'elevation' => false },
               'placement' => { 'mode' => 'source_plan', 'plane' => 'XY', 'origin_mm' => [900_000, 900_000], 'plane_offset_mm' => 0 },
               'modules' => [], 'trim_parts' => [], 'panel_parts' => [] }
  product = model.entities.add_group
  product.transformation = Geom::Transformation.translation([900_000.mm, 900_000.mm, 0])
  product.set_attribute(app::Model::DICT, 'role', 'product')
  product.set_attribute(app::Model::DICT, 'code', analysis['code'])
  product.set_attribute(app::Model::DICT, 'analysis', JSON.generate(analysis))
  product.set_attribute(app::Model::DICT, 'library', library)
  app::Model.cube(product.entities, 'id' => 'old', 'origin' => [0, 0, 0], 'size' => [1818, 600, 1600])
  inputs = [[0, 18], [18, 800], [818, 1000]].map do |x, width|
    group = model.entities.add_group
    # Local coordinates are deliberately skewed by a rotated/scaled/mirrored
    # axis frame; transformed physical geometry remains the correct cuboid.
    axes = Geom::Transformation.translation([330.mm, -470.mm, 250.mm]) *
           Geom::Transformation.rotation(ORIGIN, Z_AXIS, 37.degrees) *
           Geom::Transformation.scaling(2, 0.5, -1)
    points = 8.times.map { |n| Geom::Point3d.new(n[0] * width.mm, n[1] * 600.mm, n[2] * 1600.mm).transform(axes.inverse) }
    [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]].each do |indices|
      group.entities.add_face(indices.map { |i| points[i] })
    end
    group.transformation = product.transformation * Geom::Transformation.translation([(5000 + x).mm, 7000.mm, 9000.mm]) * axes
    group
  end
  input_before = inputs.map { |e| [e.persistent_id, e.transformation.to_a, e.definition.bounds.min.to_a, e.definition.bounds.max.to_a] }
  model.selection.clear
  app.instance_variable_set(:@last_built, nil)
  begin
    app.correction_target
    raise 'Arbitrary old product selected'
  rescue ArgumentError
    # A product existing in the model does not make it the user's intended target.
  end
  app.instance_variable_set(:@last_built, { model: model, ids: [product.persistent_id] })
  raise 'Latest build target lost' unless app.correction_target == product
  model.selection.add(product)
  raise 'Explicit target lost' unless app.correction_target == product
  model.selection.clear
  app::Corrections.begin_manual(product)
  raise 'Wrong result not hidden' unless product.hidden?
  app::Corrections.cancel_manual
  raise 'Cancel failed' if product.hidden? || app::Corrections.active?
  app::Corrections.begin_manual(product)
  model.selection.clear
  begin
    app.accept_manual_boxes('native-empty-selection')
    raise 'Empty selection accepted'
  rescue ArgumentError
    raise 'Empty selection closed correction' unless app::Corrections.active? && product.hidden?
    raise 'Missing selection error acknowledgement' unless app.instance_variable_get(:@manual_acceptance)['status'] == 'error'
  end
  cad_reference = model.entities.add_group
  cad_reference.entities.add_line([0, 0, 0], [100.mm, 0, 0])
  model.selection.add(inputs + [cad_reference])
  begin
    app.accept_manual_boxes('native-stale-session', 'a-different-session')
    raise 'Stale session accepted'
  rescue ArgumentError
    raise 'Stale session changed correction' unless app::Corrections.active? && product.hidden?
  end
  event = app.accept_manual_boxes('native-selected-boxes', app::Corrections.status['id'])
  acknowledgement = app.instance_variable_get(:@manual_acceptance)
  raise 'Missing saved acknowledgement' unless acknowledgement['status'] == 'saved' && acknowledgement['request_id'] == 'native-selected-boxes'
  accepted_files = Dir.glob(File.join(library, 'experiences', '**', '*.json'))
  raise 'Status lost saved result' unless app.manual_acceptance_status('native-selected-boxes')['status'] == 'saved'
  raise 'Unknown request promoted' unless app.manual_acceptance_status('never-received')['status'] == 'unknown'
  raise 'Duplicate request lost acknowledgement' unless app.accept_manual_boxes('native-selected-boxes')['status'] == 'saved'
  raise 'Status/retry wrote duplicate experience' unless Dir.glob(File.join(library, 'experiences', '**', '*.json')) == accepted_files
  raise 'Ignored CAD reference hidden' if cad_reference.hidden?
  raise 'Wrong selected box count' unless event['manual_source_ids'].length == 3
  state = app::Model.state(product)
  state['modules'].sort_by! { |part| part['origin'] }
  raise 'Wrong module/auxiliary roles' unless state['modules'].length == 2 && state['trim_parts'].length == 1
  raise "Axis-dependent dimensions: #{state['modules'].map { |p| p['size'] }.inspect}" unless state['modules'].map { |p| p['size'] } == [[800, 600, 1600], [1000, 600, 1600]]
  raise 'Relative placement lost' unless state['modules'].map { |p| p['origin'] } == [[18, 0, 0], [818, 0, 0]]
  raise 'Wrong trim' unless state['trim_parts'].first['size'] == [18, 600, 1600]
  raise 'Canonical result hidden' if product.hidden?
  raise 'CAD source anchor moved' unless product.transformation.origin.distance(Geom::Point3d.new(900_000.mm, 900_000.mm, 0)).to_mm < 0.1
  raise 'Original manual boxes not preserved' unless inputs.all?(&:valid?) && inputs.all?(&:hidden?)
  raise 'Original box geometry changed' unless input_before == inputs.map { |e| [e.persistent_id, e.transformation.to_a, e.definition.bounds.min.to_a, e.definition.bounds.max.to_a] }
  raise 'Accepted example missing' unless event['status'] == 'accepted' && event['input_axes_ignored'] && File.file?(event['skp'])
  raise 'Correction still active' if app::Corrections.active?
  # The DWG lane must recenter corrected total width on the label, unlike the
  # direct-scan lane which retains its CAD source anchor.
  label = model.entities.add_group
  label.name = 'SP999999'
  label.entities.add_line([0, 0, 0], [100.mm, 0, 0])
  label.transformation = Geom::Transformation.translation([1200.mm, 0, 0])
  labelled = JSON.parse(product.get_attribute(app::Model::DICT, 'analysis'))
  labelled['code'] = 'SP999999'
  labelled.delete('placement')
  product.set_attribute(app::Model::DICT, 'analysis', JSON.generate(labelled))
  product.set_attribute(app::Model::DICT, 'code', labelled['code'])
  app::Corrections.begin_manual(product)
  inputs.each { |e| e.hidden = false }
  model.selection.clear
  model.selection.add(inputs)
  app::Corrections.accept_manual
  raise 'DWG label centring lost' if (product.bounds.center.x.to_mm - label.bounds.center.x.to_mm).abs > 0.1
  raise 'DWG floor/front moved' unless product.bounds.min.to_a[1..].all? { |v| v.to_mm.abs < 0.1 }
  result = { status: 'passed', changed_local_axes_supported: true, translated_scaled_mirrored_axes: true,
             source_boxes_preserved: true, cancel_restores_result: true, modules: 2, auxiliary: 1,
             source_anchor_preserved: true, dwg_label_centred: true,
             direct_selection: true, empty_selection_rejected: true, ignored_cad_preserved: true,
             saved_acknowledgement: true, accept_ms: acknowledgement['elapsed_ms'],
             read_only_status: true, duplicate_request_cached: true,
             stale_session_rejected: true,
             explicit_or_latest_target_only: true,
             accepted_event: event['path'], original_geometry_unchanged: true }
ensure
  app.instance_variable_set(:@activity_focus, original_activity_focus)
  app::PlanRules.define_singleton_method(:enqueue, original_enqueue)
  app::Corrections.cancel_manual if app::Corrections.active? && %w[NATIVE-MANUAL-TEST SP999999].include?(app::Corrections.status['code'])
  originals.each do |name, (method, owned)|
    owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name)
  end
  originals[:abort_operation][0].call if operation
  model.selection.clear
  model.selection.add(selection.select(&:valid?))
  app.instance_variable_set(:@manual_acceptance, initial_acceptance)
  app.instance_variable_set(:@last_built, initial_last_built)
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
app::Storage.write_json(File.join(app::Settings::ROOT, 'outputs', 'manual-boxes-native-result.json'), result)
app.publish
puts JSON.generate(result)
