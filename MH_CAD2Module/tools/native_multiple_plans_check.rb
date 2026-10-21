# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[placement.rb product_labels.rb plan_reference.rb storage.rb activity.rb corrections.rb].each { |file| load File.join(root, file) }
app::Model.send(:remove_const, :DICT)
load File.join(root, 'model.rb')
data = JSON.parse(File.read(File.join(root, 'outputs/multiple-plans-sp01.json')))
raise 'Expected two full source previews' unless data['plan_results'].length == 2 && data['plan_results'].all? { |p| p['envelope_preview'] && p['bounds'] == [2255, 600, 1600] }
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
layers = model.layers.map(&:name)
selection = model.selection.to_a
read = app::Settings.method(:read)
settings = read.call
settings_owned = app::Settings.singleton_class.instance_methods(false).include?(:read)
methods = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
methods[:start_operation][0].call('CAD2Module: Kiểm Tra Nhiều Mặt Bằng', true)
qa_root = File.join('E:/MH_CAD2Module_QA/AI/tests/product-plan-0130/native', app::Ids.uuid)
result = {}
begin
  methods.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('import_plan_reference' => true, 'build_auxiliary' => true) }
  code = 'SP99000'
  raise 'QA label already exists' if app::Model.labels(model).any? { |l| l['code'] == code }
  built = data['plan_results'].map do |p|
    p['code'] = code; p['activity_id'] = app::Ids.uuid
    app::Model.build(p, qa_root, app::Ids.uuid, model)
  end
  labels = app::Model.labels(model).select { |l| l['code'] == code }
  raise 'Missing/duplicate auto label' unless labels.length == 1 && labels.first['curic']
  references = built.map { |p| model.find_entity_by_persistent_id(p.get_attribute(app::Model::DICT, 'plan_reference_id')) }
  gap = references[1].bounds.min.x.to_mm - references[0].bounds.max.x.to_mm
  raise 'Incorrect clear plan gap' unless (gap - 1000).abs < 0.01
  center = (references[0].bounds.min.x.to_mm + references[1].bounds.max.x.to_mm) / 2
  raise 'Shared SP label centre lost' unless (center - labels.first['center_x']).abs < 0.01
  raise 'Reference moved off XOY' unless references.all? { |r| r.bounds.min.z.to_mm.abs < 0.001 && r.bounds.min.y.to_mm.abs < 0.001 }
  raise 'Preview sizes/solids changed' unless built.all? { |p| p.members.length == 1 && p.members.first.manifold? && app::Model.state(p)['modules'][0]['size'] == [2255.0, 600.0, 1600.0] }
  wide = app::ProductLabels.ensure_label(model, 'SP99001', 16_000)
  narrow = app::ProductLabels.ensure_label(model, 'SP99002', 2000)
  raise 'Minimum auto-label spacing lost' unless wide['center_x'] - labels.first['center_x'] >= 7999.99 && narrow['center_x'] - wide['center_x'] >= 7999.99
  raise 'Long SP overlaps previous row' unless wide['center_x'] - 8000 - references[1].bounds.max.x.to_mm >= 999.99
  raise 'Long SP overlaps next row' unless narrow['center_x'] - 1000 - (wide['center_x'] + 8000) >= 999.99
  sibling_before = built[1].transformation.to_a
  first_before = built[0].transformation.to_a
  app::Corrections.begin_manual(built[0])
  raise 'Wrong correction scope' unless !built[0].hidden? && !built[1].hidden? && references.none?(&:hidden?)
  box = app::Model.cube(model.entities, 'id' => 'CORRECTED', 'origin' => [0, 0, 0], 'size' => [2255, 600, 1600])
  box.transformation = built[0].transformation * box.transformation
  model.selection.clear; model.selection.add(box)
  event = app::Corrections.accept_manual
  raise 'Accepted boxes jumped to label centre' unless built[0].transformation.to_a == first_before
  raise 'Correcting first moved second plan' unless built[1].transformation.to_a == sibling_before
  raise 'Corrected view not accepted' unless event['status'] == 'accepted'
  rows = app::Activity.rows(qa_root, built)
  scoped = rows.select { |r| r['code'] == code }
  raise 'Per-plan activity scope ambiguous' unless scoped.length == 2 && scoped.all? { |r| r['available'] && !r['ambiguous'] } && scoped.map { |r| r['label'] }.uniq.length == 2
  result = { passed: true, plan_count: 2, clear_gap_mm: gap, one_curic_label: true, label_spacing_and_long_sp_clearance: true,
             xoy: true, orange_full_envelopes: true, independent_correction_and_history: true, accepted_without_jump: true }
ensure
  observer = app::Corrections.instance_variable_get(:@observer)
  model.remove_observer(observer) if observer
  app::Corrections.instance_variable_set(:@session, nil)
  settings_owned ? app::Settings.define_singleton_method(:read, read) : app::Settings.singleton_class.send(:remove_method, :read)
  methods.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  methods[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'User assembly registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
raise 'User tags changed' unless layers == model.layers.map(&:name)
raise 'Settings changed' unless settings == read.call
result[:user_geometry_registry_tags_settings_restored] = true
app::Storage.write_json(File.join(root, 'outputs/multiple-plans-native-result.json'), result)
puts JSON.generate(result)
