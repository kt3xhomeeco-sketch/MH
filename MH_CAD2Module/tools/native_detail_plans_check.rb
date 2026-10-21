# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
data = JSON.parse(File.read(File.join(root, 'outputs/detail-plans-sp04.json'), encoding: 'UTF-8'))
children = data.fetch('plan_results')
raise 'Wrong selected views' unless children.map { |p| p['plan_view_id'] } == %w[V01.1 V02.1 V06.1]
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
methods[:start_operation][0].call('CAD2Module: Kiểm Tra Lọc Chi Tiết', true)
result = {}
qa_root = File.join('E:/MH_CAD2Module_QA/AI/tests/detail-plans-0131/native', app::Ids.uuid)
begin
  methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
  built = children.map do |p|
    p['code'] = 'SP99004'; p['activity_id'] = app::Ids.uuid
    app::Model.build(p, qa_root, app::Ids.uuid, model)
  end
  refs = built.map { |a| model.find_entity_by_persistent_id(a.get_attribute(app::Model::DICT, 'plan_reference_id')) }
  gaps = refs.each_cons(2).map { |a, b| b.bounds.min.x.to_mm - a.bounds.max.x.to_mm }
  raise 'Wrong CAD gaps' unless gaps.all? { |gap| (gap - 1000).abs < 0.01 }
  raise 'Wrong measured width' unless built.all? { |a| (a.bounds.width.to_mm - 5200).abs < 0.01 }
  raise 'Non-solid preview' unless built.all? { |a| a.members.length == 1 && a.members.first.manifold? }
  result = { passed: true, view_ids: children.map { |p| p['plan_view_id'] }, clear_gaps_mm: gaps, widths_mm: built.map { |a| a.bounds.width.to_mm } }
ensure
  methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
  methods[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result[:user_geometry_and_registry_restored] = true
app::Storage.write_json(File.join(root, 'outputs/detail-plans-native-result.json'), result)
puts JSON.generate(result)
