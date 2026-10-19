# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
load File.join(root, 'placement.rb')
load File.join(root, 'plan_profile.rb')
analysis = JSON.parse(File.read(File.join(root, 'outputs', 'stepped-response.json'), encoding: 'UTF-8')).dig('analyses', 0, 'products', 0)
raise analysis['error'].to_s unless analysis['status'] == 'ready'
app::SelectionSource.validate_watch(analysis.fetch('source_watch'), model)
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Hậu Giật Cấp', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  built = app::Model.build(analysis, 'E:/MH_CAD2Module_QA/AI/tests/stepped-native', app::Ids.uuid, model)
  raise 'Expected three independent solid Groups' unless built.members.length == 3 && built.members.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model && g.manifold? }
  body = built.members.find { |g| g.get_attribute(app::Model::DICT, 'role') == 'module' }
  shape = app::PlanProfile.measured(body)
  raise 'Concave outline was lost' unless shape['plan_profile']['segments'].length == 8
  raise 'Wrong size' unless shape['size'].zip([1004, 500, 1600]).all? { |a, b| (a - b).abs < 0.01 }
  actual = body.bounds.min.to_a.map(&:to_mm)
  expected = analysis['placement']['origin_mm'].zip(analysis['modules'][0]['origin']).map { |a, b| a + b } + [analysis['placement']['plane_offset_mm']]
  raise 'Wrong CAD position' unless actual.zip(expected).all? { |a, b| (a - b).abs < 0.01 }
  bad = Marshal.load(Marshal.dump(analysis))
  bad['modules'][0].delete('plan_profile')
  begin
    app::Placement.validate_ai_product(bad)
    raise 'Filled recess was accepted'
  rescue ArgumentError => error
    raise 'Wrong rejection' unless error.message.include?('giật cấp')
  end
ensure
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Temporary registry leaked' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { passed: true, solids: 3, concave_profile: true, correct_source_position: true,
           feedback_profile_preserved: true, filled_recess_rejected: true, user_geometry_unchanged: true,
           local_ai: analysis['local_ai'] }
app::Storage.write_json(File.join(root, 'outputs', 'stepped-native-result.json'), result)
puts JSON.generate(result)
