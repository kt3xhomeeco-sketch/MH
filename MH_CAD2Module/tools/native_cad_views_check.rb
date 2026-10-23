# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[cad_views.rb plan_reference.rb product_labels.rb].each { |file| load File.join(root, file) }
app::Model.send(:remove_const, :DICT)
load File.join(root, 'model.rb')
data = JSON.parse(File.read(File.join(root, 'outputs/cad-views-low-product.json'), encoding: 'UTF-8'))
raise 'Expected actual provisional source' unless data['elevation_pending'] && data['plan_reference']['segments'].length == 169
ref = data['plan_reference']; front = ref['views'].find { |v| v['plane'] == 'XZ' }
# A true arc wholly inside the front tests native ArcCurve preservation under XZ.
b = front['box_mm']; x = b[0] + 150; y = b[1] + 150
front['segment_indices'] << ref['segments'].length
ref['segments'] << { 'type' => 'arc', 'start' => [x + 50, y], 'end' => [x, y + 50], 'center' => [x, y], 'radius' => 50, 'sweep' => Math::PI / 2, 'segments' => 12 }
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
layers = model.layers.map(&:name)
selection = model.selection.to_a
read = app::Settings.method(:read); settings = read.call(model)
sha = Digest::SHA256.file(model.path).hexdigest unless model.path.empty?
methods = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
methods[:start_operation][0].call('CAD2Module: Kiểm Tra Bộ Hình Chiếu CAD', true)
qa_root = File.join(root, 'outputs/qcv')
result = {}; records = []
begin
  methods.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app::Settings.define_singleton_method(:read) { |*_args| settings.merge('import_plan_reference' => false) }
  [false, true].each_with_index do |direct, i|
    p = JSON.parse(JSON.generate(data)); p['code'] = "SP#{98760 + i}"; p['activity_id'] = app::Ids.uuid
    p['placement'] = { 'mode' => 'source_plan', 'plane' => 'XY', 'origin_mm' => p['plan_reference']['source_origin_mm'], 'plane_offset_mm' => 0 } if direct
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    built = app::Model.build(p, qa_root, app::Ids.uuid, model)
    reference = model.find_entity_by_persistent_id(built.get_attribute(app::Model::DICT, 'plan_reference_id')) if built.get_attribute(app::Model::DICT, 'plan_reference_id')
    raise 'Wrong module height/solid' unless built.members.length == 1 && built.members.first.manifold? && app::Model.state(built)['modules'].first['size'] == [1300, 582, 1600]
    if direct
      raise 'Duplicated direct-scan CAD' if reference
    else
      raise 'Missing all-view CAD despite provisional height' unless reference.is_a?(Sketchup::Group) && reference.parent == model && reference.transformation.to_a == built.transformation.to_a
      raise 'CAD selected as module' if app::Model.selection_entities(built).include?(reference)
      children = built.get_attribute(app::Model::DICT, 'cad_reference_ids').map { |id| model.find_entity_by_persistent_id(id) }
      raise 'Lost/contained source views' unless children.length == 5 && children.all? { |g| g.is_a?(Sketchup::Group) && g.parent == model && g.entities.grep(Sketchup::Group).empty? && !built.members.include?(g) }
      ref['views'].each do |view|
        child = children.find { |e| e.get_attribute(app::Model::DICT, 'view_id') == view['id'] }
        expected = built.transformation * app::CadViews.transform(view, ref['plan_bounds_mm'])
        raise 'View moved/scaled' unless child && child.transformation.to_a.zip(expected.to_a).all? { |a, z| (a - z).abs < 0.000001 }
        raise 'Face appeared in reference' unless child.entities.grep(Sketchup::Face).empty?
        raise 'Wrong user CAD tag' unless child.layer.name == { 'front_check' => 'MH_DWG1', 'section_vertical' => 'MH_DWG2' }.fetch(view['role'], 'MH_DWG')
        local = built.transformation.inverse * child.transformation
        points = child.entities.grep(Sketchup::Edge).flat_map(&:vertices).map { |v| v.position.transform(local).to_a.map(&:to_mm) }
        raise 'Plan off XOY' if view['plane'] == 'XY' && points.any? { |pt| pt[2].abs > 0.01 }
        raise 'Front off XOZ' if view['plane'] == 'XZ' && points.any? { |pt| pt[1].abs > 0.01 }
        raise 'Side off YOZ' if view['plane'] == 'YZ' && points.any? { |pt| (pt[0] - view['display_x_mm']).abs > 0.01 }
      end
      projected_front = children.find { |e| e.get_attribute(app::Model::DICT, 'view_id') == front['id'] }
      raise 'Arc lost on standing plane' unless projected_front.entities.grep(Sketchup::Edge).any? { |e| e.curve.is_a?(Sketchup::ArcCurve) }
      app::Corrections.begin_manual(built)
      raise 'Correction hid reference/boxes' if children.any?(&:hidden?) || built.hidden?
      app::Corrections.cancel_manual
    end
    records << { direct_scan: direct, modules: 1, provisional_height: 1600, independent_views: direct ? 0 : 5, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
  end
  result = { passed: true, records: records, planar_alignment: true, arc_curve_retained: true, full_import_even_with_plan_toggle_off: true }
ensure
  app::Settings.define_singleton_method(:read, read)
  methods.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  methods[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User model/registry/tags/settings changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] } && registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h && layers == model.layers.map(&:name) && settings == read.call(model)
raise 'Source file changed' if sha && sha != Digest::SHA256.file(model.path).hexdigest
result[:user_model_registry_tags_settings_selection_file_preserved] = true
app::Storage.write_json(File.join(root, 'outputs/cad-views-native-result.json'), result)
puts JSON.generate(result)
