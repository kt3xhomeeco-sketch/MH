# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[cad_views.rb plan_reference.rb].each { |name| load File.join(root, name) }
data = JSON.parse(File.read(File.join(root, 'outputs/sp20-levels-product.json'), encoding: 'UTF-8'))
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
fingerprint = lambda do |g|
  Digest::SHA256.hexdigest(JSON.generate(g.entities.grep(Sketchup::Edge).map { |edge|
    edge.vertices.map { |v| v.position.to_a.map { |n| (n.to_mm * 10_000).round } }.sort
  }.uniq.sort))
end
operations = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
operations[:start_operation][0].call('CAD2Module: Kiểm Tra Cao Độ Tạm SP20', true)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC); guards = []; result = {}
begin
  operations.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => File.join(root, 'outputs/qsp20'), 'import_plan_reference' => false) }
  job = app::Ids.uuid
  built = data['plan_results'].map do |p|
    p['code'] = 'SP99020'; p['activity_id'] = app::Ids.uuid
    app::Model.build(p, File.join(root, 'outputs/qsp20'), job, model)
  end
  refs = built.map { |p| model.find_entity_by_persistent_id(p.get_attribute(app::Model::DICT, 'plan_reference_id')) }
  raise 'Reference duplicated or missing' unless refs.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model } && built[0].get_attribute(app::Model::DICT, 'cad_reference_ids').include?(refs[1].persistent_id)
  raise 'Wrong provisional levels' unless refs.map { |g| g.bounds.min.z.to_mm.round(3) } == [0, 1000] && refs.all? { |g| g.get_attribute(app::Model::DICT, 'level_status') == 'provisional' && g.layer.name == 'MH_DWG' }
  raise 'Different XY' unless refs[0].bounds.min.to_a.first(2).zip(refs[1].bounds.min.to_a.first(2)).all? { |a, b| (a - b).abs < 0.00001 } && refs[0].bounds.max.to_a.first(2).zip(refs[1].bounds.max.to_a.first(2)).all? { |a, b| (a - b).abs < 0.00001 }
  raise 'View/solid inference changed' unless built[0].get_attribute(app::Model::DICT, 'cad_reference_ids').length == 7 && built.all? { |p| JSON.parse(p.get_attribute(app::Model::DICT, 'analysis'))['elevation_pending'] }
  # Verify the reported delivery against its old drawing instructions before any repair.
  %w[assembly-3eec4565-759e-1053-c1dc-0e7282404d56 assembly-19cb7214-c374-1c25-43ad-376a2b1290d0].each do |id|
    old = app::Assembly.new(model, id)
    next unless old.valid? && old.get_attribute(app::Model::DICT, 'job_id') == 'd6ef327f-853f-4a20-0383-9898ed234046'
    analysis = JSON.parse(old.get_attribute(app::Model::DICT, 'analysis')); ref = analysis['plan_reference']
    ids = old.get_attribute(app::Model::DICT, 'cad_reference_ids') || [old.get_attribute(app::Model::DICT, 'plan_reference_id')]
    group_guards = ids.map do |pid|
      g = model.find_entity_by_persistent_id(pid)
      raise 'Reported CAD group missing' unless g.is_a?(Sketchup::Group) && g.parent == model
      view = ref['scope'] == 'all_views' ? ref['views'].find { |v| v['id'] == g.get_attribute(app::Model::DICT, 'view_id') } : ref.merge('plane' => 'XY')
      raise 'Unknown CAD view' unless view
      expected = old.transformation * app::CadViews.transform(view, ref['plan_bounds_mm'])
      raise 'Reported CAD moved by user' unless g.transformation.to_a.zip(expected.to_a).all? { |a, b| (a - b).abs < 0.000001 }
      temp = model.entities.add_group
      segments = ref['scope'] == 'all_views' ? view['segment_indices'].map { |i| ref['segments'][i] } : ref['segments']
      app::PlanReference.draw(temp.entities, segments)
      raise 'Reported CAD differs from recorded geometry' unless fingerprint.call(g) == fingerprint.call(temp) && g.entities.all? { |e| e.is_a?(Sketchup::Edge) }
      temp.erase!
      { id: pid, transform: g.transformation.to_a, geometry: fingerprint.call(g), view_id: g.get_attribute(app::Model::DICT, 'view_id') }
    end
    guards << { id: id, analysis: old.get_attribute(app::Model::DICT, 'analysis'), references: group_guards }
  end
  result = { passed: true, actual_sp20_source: true, same_xy: true, provisional_levels_mm: [0, 1000], independent_views: 7,
             duplicate_reference: false, module_elevation_still_pending: true, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
ensure
  app::Settings.define_singleton_method(:read, read)
  operations.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  operations[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_state_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/sp20-levels-native-result.json'), result)
app::Storage.write_json(File.join(root, 'outputs/sp20-levels-repair-guard.json'), { pid: Process.pid, model_path: model.path, products: guards })
puts JSON.generate(result)
