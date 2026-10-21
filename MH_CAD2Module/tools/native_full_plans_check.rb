# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
require File.join(root, 'product_requests.rb')
scan_method = app.method(:scan)
scan_owned = app.singleton_class.instance_methods(false).include?(:scan)
variables = %i[@entry_mode @last_products @last_product_end].to_h { |key| [key, [app.instance_variable_defined?(key), app.instance_variable_get(key)]] }
captured = []
begin
  app.define_singleton_method(:scan) { |values, &_completion| captured << values }
  app.instance_variable_set(:@entry_mode, 'dwg')
  app.dispatch('action' => 'build', 'products' => 'SP08', 'product_end' => 'SP11')
  app.dispatch('action' => 'build', 'products' => '', 'product_end' => 'SP11')
  app.dispatch('action' => 'build', 'products' => 'SP08')
  raise 'Range dispatch lost an endpoint' unless captured.map { |v| v['targets'] } == [%w[SP08 SP09 SP10 SP11], ['SP11'], ['SP08']]
ensure
  scan_owned ? app.define_singleton_method(:scan, scan_method) : app.singleton_class.send(:remove_method, :scan)
  variables.each { |key, (owned, value)| owned ? app.instance_variable_set(key, value) : app.remove_instance_variable(key) if owned || app.instance_variable_defined?(key) }
end
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
methods = %i[start_operation commit_operation abort_operation].to_h { |key| [key, [model.method(key), model.singleton_class.instance_methods(false).include?(key)]] }
qa_root = File.join('E:/MH_CAD2Module_QA/AI/tests/full-plans-0140/native', app::Ids.uuid)
methods[:start_operation][0].call('CAD2Module: Kiểm Tra Nét Đầy Đủ Và Chữ L', true)
results = []
begin
  methods.each_key { |key| model.define_singleton_method(key) { |*_args| true } }
  %w[sp08 sp11].each do |code|
    data = JSON.parse(File.read(File.join(root, "outputs/#{code}-full-plans.json"), encoding: 'UTF-8'))
    built = data['plan_results'].map do |p|
      p['code'] = code == 'sp08' ? 'SP99008' : 'SP99011'
      p['activity_id'] = app::Ids.uuid
      app::Model.build(p, qa_root, app::Ids.uuid, model)
    end
    refs = built.map { |a| model.find_entity_by_persistent_id(a.get_attribute(app::Model::DICT, 'plan_reference_id')) }
    refs.zip(data['plan_results']).each do |ref, p|
      frame = p.fetch('source_plan_envelope')
      raise 'Clipped reference width/depth' unless [ref.bounds.width.to_mm, ref.bounds.height.to_mm].zip([frame[2] - frame[0], frame[3] - frame[1]]).all? { |actual, expected| (actual - expected).abs < 0.02 }
      raise 'CAD not planar/independent' unless ref.bounds.depth.to_mm.abs < 0.001 && built.none? { |a| a.members.include?(ref) }
    end
    gaps = refs.each_cons(2).map { |a, b| b.bounds.min.x.to_mm - a.bounds.max.x.to_mm }
    raise 'Wrong clear gaps' unless gaps.all? { |gap| (gap - 1000).abs < 0.02 }
    raise 'Non-solid module' unless built.all? { |a| a.members.all?(&:manifold?) }
    results << { code: code, views: data['plan_results'].map { |p| p['plan_view_id'] }, reference_sizes_mm: refs.map { |r| [r.bounds.width.to_mm, r.bounds.height.to_mm] }, gaps_mm: gaps }
  end
ensure
  methods.each { |key, (method, owned)| owned ? model.define_singleton_method(key, method) : model.singleton_class.send(:remove_method, key) }
  methods[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { passed: true, range_dispatch: true, products: results, user_geometry_registry_restored: true }
app::Storage.write_json(File.join(root, 'outputs/full-plans-native-result.json'), result)
puts JSON.generate(result)
