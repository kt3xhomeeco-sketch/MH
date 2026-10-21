# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[cad_views.rb plan_reference.rb].each { |name| load File.join(root, name) }
data = JSON.parse(File.read(File.join(root, 'outputs/stretched-chain-product.json'), encoding: 'UTF-8'))
app::PlanReference.validate(data)
front = data['plan_reference']['views'].find { |v| v['role'] == 'front_open' }
w = front['axis_registration']['W']; link = w['path'].first
raise 'Missing two-sided stretch evidence' unless link['coverage'] == 0.5 && link['changed_gap']['sequence_coverage'] == 1 && data['elevation_pending']
bad = JSON.parse(JSON.generate(data)); b = bad['plan_reference']['views'].find { |v| v['role'] == 'front_open' }
b['axis_registration']['W']['path'].first['changed_gap']['right_offset_mm'] += 18
begin
  app::PlanReference.validate(bad)
  raise 'Changed gap tamper accepted'
rescue ArgumentError
  nil
end
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; selection = model.selection.to_a; layers = model.layers.map(&:name)
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
ops = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
ops[:start_operation][0].call('CAD2Module: Kiểm Tra Chuỗi Stretch', true)
result = {}
begin
  ops.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qstretch')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa, 'import_plan_reference' => false) }
  data['code'] = 'SP99991'; data['activity_id'] = app::Ids.uuid
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  built = app::Model.build(data, qa, app::Ids.uuid, model)
  groups = built.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
  raise 'Not independent source Groups' unless groups.length == 2 && groups.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model }
  group = groups.find { |g| g.get_attribute(app::Model::DICT, 'view_id') == front['id'] }
  raise 'Source was scaled to hide the error' unless (group.bounds.width.to_mm - 4518).abs < 0.01
  result = { passed: true, matched_ratio: link['coverage'], ordered_sequence_ratio: 1, independent_groups: 2,
             source_front_width_mm: group.bounds.width.to_mm, gap_difference_mm: link['changed_gap']['gap_difference_mm'],
             height_kept_provisional: data['elevation_pending'], tampered_gap_rejected: true,
             seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
ensure
  app::Settings.define_singleton_method(:read, read)
  ops.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  ops[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_state_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/view-registration-native-result.json'), result)
puts JSON.generate(result)
