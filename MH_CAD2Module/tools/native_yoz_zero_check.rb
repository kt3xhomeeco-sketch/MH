# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[cad_views.rb plan_reference.rb].each { |name| load File.join(root, name) }
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h; layers = model.layers.map(&:name); selection = model.selection.to_a
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
read = app::Settings.method(:read); settings = read.call(model)
operations = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
operations[:start_operation][0].call('CAD2Module: Kiểm Tra YOZ Và Z0', true)
result = {}; records = []
begin
  operations.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('library' => File.join(root, 'outputs/qyz'), 'import_plan_reference' => false) }
  %w[single-plan-zero-product sp20-yoz-product].each_with_index do |file, index|
    data = JSON.parse(File.read(File.join(root, "outputs/#{file}.json"), encoding: 'UTF-8'))
    children = data.fetch('plan_results', [data]); ref = children.first['plan_reference']
    side = ref['views'].find { |v| v['plane'] == 'YZ' }
    raise 'No YOZ section' unless side
    box = side['box_mm']; x = box[0] + 60; y = box[1] + 60
    side['segment_indices'] << ref['segments'].length
    ref['segments'] << { 'type' => 'arc', 'start' => [x + 20, y], 'end' => [x, y + 20], 'center' => [x, y], 'radius' => 20, 'sweep' => Math::PI / 2, 'segments' => 12 }
    job = app::Ids.uuid; started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    built = children.map do |p|
      p['code'] = "SP#{99771 + index}"; p['activity_id'] = app::Ids.uuid
      app::Model.build(p, File.join(root, 'outputs/qyz'), job, model)
    end
    refs = built.first.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
    raise 'Missing independent groups' unless refs.length == ref['views'].length + ref.fetch('display_copies', []).length && refs.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model && !built.flat_map(&:members).include?(g) }
    ref['views'].each do |view|
      g = refs.find { |item| item.get_attribute(app::Model::DICT, 'view_id') == view['id'] }
      local = built.first.transformation.inverse * g.transformation
      points = g.entities.grep(Sketchup::Edge).flat_map(&:vertices).map { |v| v.position.transform(local).to_a.map(&:to_mm) }
      raise 'Wrong CAD tag' unless g.layer.name == { 'front_check' => 'MH_DWG1', 'section_vertical' => 'MH_DWG2' }.fetch(view['role'], 'MH_DWG')
      case view['plane']
      when 'YZ'
        raise 'Side off YOZ or incorrect floor' unless points.all? { |p| (p[0] - view['display_x_mm']).abs < 0.01 } && points.map(&:last).min.abs < 0.01
        actual_y = points.map { |p| p[1] }.minmax
        expected_y = [ref['plan_bounds_mm'][1], ref['plan_bounds_mm'][1] + view['anchor_box_mm'][2] - view['anchor_box_mm'][0]]
        raise 'Side depth shifted/scaled' unless actual_y.zip(expected_y).all? { |a, b| (a - b).abs < 0.01 }
      when 'XZ' then raise 'Front off XOZ' unless points.all? { |p| p[1].abs < 0.01 }
      when 'XY' then raise 'Plan off placement level' unless points.all? { |p| (p[2] - view.fetch('z_mm', 0)).abs < 0.01 }
      end
    end
    side_group = refs.find { |g| g.get_attribute(app::Model::DICT, 'view_id') == side['id'] }
    raise 'Arc flattened into untyped lines' unless side_group.entities.grep(Sketchup::Edge).any? { |e| e.curve.is_a?(Sketchup::ArcCurve) }
    plans = built.map { |p| model.find_entity_by_persistent_id(p.get_attribute(app::Model::DICT, 'plan_reference_id')) }
    if index.zero?
      raise 'Single measured section not at zero' unless plans.first.bounds.min.z.to_mm.abs < 0.01 && plans.first.get_attribute(app::Model::DICT, 'source_level_mm') == 700
    else
      raise 'Multi-plan levels changed' unless plans.map { |g| g.bounds.min.z.to_mm.round(3) } == [0, 1000] && refs.include?(plans.last)
    end
    records << { fixture: file, groups: refs.length, plan_levels_mm: plans.map { |g| g.bounds.min.z.to_mm.round(3) },
                 seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
  end
  result = { passed: true, yoz_sections: true, xoz_fronts: true, true_arc_on_yoz: true, source_700_retained_at_display_zero: true, multi_plan_levels_preserved: true, records: records }
ensure
  app::Settings.define_singleton_method(:read, read)
  operations.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  operations[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User state changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'User file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_state_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/yoz-zero-native-result.json'), result)
puts JSON.generate(result)
