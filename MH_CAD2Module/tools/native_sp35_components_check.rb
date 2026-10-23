# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT; dict = app::Model::DICT
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
%w[plan_components.rb product_height.rb partial_plan.rb placement.rb reference_build.rb].each { |file| load File.join(root, file) }
packet = JSON.parse(File.read(File.join(root, 'outputs/sp35-components-product.json'), encoding: 'UTF-8'))
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
ops = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
ops[:start_operation][0].call('CAD2Module: Test Nhánh L', true)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
begin
  ops.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qsp35')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa) }
  packet['code'] = 'SP99435'; packet['activity_id'] = app::Ids.uuid; packet['build_auxiliary'] = true
  outcome = app::ReferenceBuild.call(packet, qa, app::Ids.uuid, model); instance = outcome[:instance]
  raise 'Wrong native solids' unless instance.members.length == 12 && instance.members.all? { |g| g.parent == model && g.manifold? }
  measured = app::Model.state(instance)['modules']
  raise 'Wrong native dimensions' unless measured.map { |m| m['size'].first(2).map { |v| v.round(3) } } == [[512.001, 325], [968.037, 580], [666, 680], [500, 1102]]
  raise 'Invented measured tiers' unless measured.all? { |m| m['elevation_pending'] }
  refs = instance.get_attribute(dict, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
  ref_state = refs.map { |g| [g.persistent_id, g.transformation.to_a, g.entities.length] }
  raise 'Missing full CAD' unless refs.length == 14 && refs.all? { |g| g.valid? && g.parent == model }
  again = app::ReferenceBuild.call(packet, qa, app::Ids.uuid, model)
  raise 'Duplicate build/ref move' if again[:created] || again[:updated] || ref_state != refs.map { |g| [g.persistent_id, g.transformation.to_a, g.entities.length] }
  result = { passed: true, modules: 4, auxiliaries: 8, cad_groups: 14, closed_plan_bays: 3, provisional_bays: 1,
             front_a_sum_mm: 2170.038, front_b_sum_mm: 1730, measured_tiers_claimed: false, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
ensure
  app::Settings.define_singleton_method(:read, read)
  ops.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  ops[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_state_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/sp35-components-native-result.json'), result)
puts JSON.generate(result)
