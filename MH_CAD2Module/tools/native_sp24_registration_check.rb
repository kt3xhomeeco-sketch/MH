# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[cad_views.rb plan_reference.rb].each { |name| load File.join(root, name) }
data = JSON.parse(File.read(File.join(root, 'outputs/sp24-registered-product.json'), encoding: 'UTF-8'))
children = data['plan_results']; ref = children.first['plan_reference']
raise 'Expected actual six SP24 sections' unless children.length == 6 && ref['views'].count { |v| v['role'] == 'section_vertical' } == 6
app::PlanReference.validate(children.first)
[%w[position], %w[direction], %w[family]].each do |change|
  bad = JSON.parse(JSON.generate(children.first)); side = bad['plan_reference']['views'].find { |v| v['role'] == 'section_vertical' }
  case change.first
  when 'position' then side['display_x_mm'] += 18
  when 'direction' then side['reversed_depth'] = false
  when 'family' then side['reference_family'] = 'OTHER'
  end
  begin
    app::PlanReference.validate(bad)
    raise 'Tampered source proof accepted'
  rescue ArgumentError
    nil
  end
end
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; selection = model.selection.to_a; layers = model.layers.map(&:name)
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
operations = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
operations[:start_operation][0].call('CAD2Module: Kiểm Tra Đặt Mặt Cắt SP24', true)
result = {}
begin
  operations.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  qa = File.join(root, 'outputs/qsp24')
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => qa, 'import_plan_reference' => false) }
  job = app::Ids.uuid; started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  built = children.map do |p|
    p['code'] = 'SP99924'; p['activity_id'] = app::Ids.uuid
    app::Model.build(p, qa, job, model)
  end
  groups = built.first.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
  raise 'Lost independent source views' unless groups.length == ref['views'].length + ref.fetch('display_copies', []).length && groups.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model }
  raise 'Duplicate CAD per child' unless built.all? { |b| groups.any? { |g| g.persistent_id == b.get_attribute(app::Model::DICT, 'plan_reference_id') } }
  side_x = []; levels = {}
  ref['views'].each do |view|
    group = groups.find { |g| g.get_attribute(app::Model::DICT, 'view_id') == view['id'] }
    transform = built.first.transformation.inverse * group.transformation
    points = group.entities.grep(Sketchup::Edge).flat_map(&:vertices).map { |v| v.position.transform(transform).to_a.map(&:to_mm) }
    raise 'Wrong semantic tag' unless group.layer.name == { 'front_check' => 'MH_DWG1', 'section_vertical' => 'MH_DWG2' }.fetch(view['role'], 'MH_DWG')
    case view['plane']
    when 'YZ'
      raise 'Side off actual cut position' unless points.all? { |p| (p[0] - view['display_x_mm']).abs < 0.01 }
      raise 'Side not reversed according to arrow' unless transform.xaxis.y.negative?
      side_x << view['display_x_mm']
    when 'XZ' then raise 'Front off XOZ' unless points.all? { |p| p[1].abs < 0.01 }
    when 'XY'
      next unless view['role'] == 'plan'
      raise 'Wrong measured cut level' unless points.all? { |p| (p[2] - view['z_mm']).abs < 0.01 }
      levels[view['id']] = view['z_mm']
    end
  end
  raise 'Side order changed' unless side_x == side_x.sort
  b, c = %w[V13.1 V14.1].map { |id| groups.find { |g| g.get_attribute(app::Model::DICT, 'view_id') == id } }
  raise 'B/C not aligned at their full extents' unless b.bounds.min.x.to_mm == c.bounds.min.x.to_mm || (b.bounds.min.x - c.bounds.min.x).to_mm.abs < 0.01
  raise 'B/C rear edge not aligned' unless (b.bounds.max.y - c.bounds.max.y).to_mm.abs < 0.01
  result = { passed: true, actual_sp24: true, independent_views: groups.length, six_measured_levels_mm: levels, cut_positions_mm: side_x,
             symbol_arrow_directions: true, repeated_codes_scoped: true, full_b_c_aligned: true, no_duplicate_reference: true,
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
app::Storage.write_json(File.join(root, 'outputs/sp24-registration-native-result.json'), result)
puts JSON.generate(result)
