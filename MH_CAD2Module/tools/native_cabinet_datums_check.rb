# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[cad_views.rb plan_reference.rb].each { |name| load File.join(root, name) }
data = JSON.parse(File.read(File.join(root, 'outputs/sp27-ymin-product.json'), encoding: 'UTF-8'))
app::PlanReference.validate(data)
ref = data['plan_reference']; side = ref['views'].find { |v| v['plane'] == 'YZ' }
raise 'Not actual SP27 wall regression' unless ref['plan_bounds_mm'][3] == 785 && side['display_y_mm'].zero? && side['reversed_depth']
bad = JSON.parse(JSON.generate(data)); bad['plan_reference']['views'].find { |v| v['plane'] == 'YZ' }['display_y_mm'] += 180
begin
  app::PlanReference.validate(bad)
  raise 'Wall-shifted Y accepted'
rescue ArgumentError
  nil
end
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; selection = model.selection.to_a; layers = model.layers.map(&:name)
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
operations = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
operations[:start_operation][0].call('CAD2Module: Kiểm Tra Mốc Y Tấm Ván', true)
result = {}
begin
  operations.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qdatum')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa) }
  data['code'] = 'SP99927'; data['activity_id'] = app::Ids.uuid
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  built = app::Model.build(data, qa, app::Ids.uuid, model)
  refs = built.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
  raise 'Lost independent CAD groups' unless refs.length == 5 && refs.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model }
  group = refs.find { |g| g.get_attribute(app::Model::DICT, 'view_id') == side['id'] }
  transform = built.transformation.inverse * group.transformation
  cabinet = side['cabinet_datum']['box_mm']
  points = [cabinet[0], cabinet[2]].map { |x| Geom::Point3d.new([x, cabinet[1], 0].map(&:mm)).transform(transform).to_a.map(&:to_mm) }
  raise 'Cabinet still shifted by architectural context' unless points.map { |p| p[1] }.min.abs < 0.001 && (points.map { |p| p[1] }.max - 600).abs < 0.001
  raise 'Side lost marker X or YOZ' unless points.all? { |p| (p[0] - side['display_x_mm']).abs < 0.001 } && transform.xaxis.y.negative?
  plan = refs.find { |g| g.get_attribute(app::Model::DICT, 'view_role') == 'plan' }
  local = built.transformation.inverse * plan.transformation
  ys = plan.entities.grep(Sketchup::Edge).flat_map(&:vertices).map { |v| v.position.transform(local).y.to_mm }
  raise 'Wall source was deleted to fake alignment' unless (ys.max - 785).abs < 0.001
  result = { passed: true, actual_source: 'SP27', complete_plan_max_y_mm: ys.max, cabinet_side_y_mm: points.map { |p| p[1] }.minmax,
             independent_views: refs.length, marker_x_mm: side['display_x_mm'], wall_shift_rejected: true,
             seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
ensure
  app::Settings.define_singleton_method(:read, read)
  operations.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  operations[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_state_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/cabinet-datums-native-result.json'), result)
puts JSON.generate(result)
