# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
%w[cad_views.rb plan_reference.rb].each { |file| load File.join(root, file) }
data = JSON.parse(File.read(File.join(root, 'outputs/sp25-sections-product.json'), encoding: 'UTF-8'))
children = data['plan_results']; ref = children.first['plan_reference']
app::PlanReference.validate(children.first)
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
operations = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
operations[:start_operation][0].call('CAD2Module: Kiểm Tra Mặt Cắt SP25 Và Bản XOZ', true)
result = {}
begin
  operations.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qsp25')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa) }
  job = app::Ids.uuid; started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  built = children.map do |p|
    p['code'] = 'SP99925'; p['activity_id'] = app::Ids.uuid
    app::Model.build(p, qa, job, model)
  end
  groups = built.first.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
  raise 'Lost or contained source groups' unless groups.length == 11 && groups.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model }
  by_view = groups.to_h { |g| [g.get_attribute(app::Model::DICT, 'view_id'), g] }
  %w[V03.1 V07.1 V08.1].each do |id|
    g = by_view[id]; view = ref['views'].find { |v| v['id'] == id }; transform = built.first.transformation.inverse * g.transformation
    points = g.entities.grep(Sketchup::Edge).flat_map(&:vertices).map { |v| v.position.transform(transform).to_a.map(&:to_mm) }
    raise 'Side still lying flat or missing marker X' unless points.all? { |p| (p[0] - view['display_x_mm']).abs < 0.01 } && points.map(&:last).max > 2700
    raise 'Wrong YOZ tag' unless g.layer.name == 'MH_DWG2'
  end
  closed = by_view['V02.1']; opened = by_view['V06.1']
  raise 'Fronts not overlaid' unless (closed.bounds.min.x - opened.bounds.min.x).to_mm.abs < 0.01 && closed.bounds.min.y == opened.bounds.min.y
  raise 'Fronts lost separate tags' unless closed.layer.name == 'MH_DWG1' && opened.layer.name == 'MH_DWG'
  previous = [closed, opened].max_by { |g| g.bounds.max.x }
  ref['display_copies'].map { |c| by_view[c['id']] }.each do |g|
    raise 'XOZ spacing not500 mm' unless ((g.bounds.min.x - previous.bounds.max.x).to_mm - 500).abs < 0.01 && g.bounds.min.y.to_mm.abs < 0.01 && g.bounds.max.y.to_mm.abs < 0.01
    previous = g
  end
  ref['display_copies'].each do |copy|
    group = by_view[copy['id']]; source = by_view[copy['source_view_id']]
    raise 'Copy lost native edges/arcs or tag' unless group.layer.name == 'MH_DWG2' && group.entities.grep(Sketchup::Edge).length == source.entities.grep(Sketchup::Edge).length
  end
  result = { passed: true, actual_sp25: true, independent_groups: groups.length, side_ids: %w[V03.1 V07.1 V08.1], xoz_copies: 3,
             front_overlay: true, checked_heights_mm: ref['views'].find { |v| v['id'] == 'V02.1' }['axis_registration']['W']['path'].last['height_checks'].map { |c| c['height_mm'] }, xoz_copy_gap_mm: 500, side_tag: 'MH_DWG2', seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
ensure
  app::Settings.define_singleton_method(:read, read)
  operations.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  operations[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_state_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/sp25-sections-native-result.json'), result)
puts JSON.generate(result)
