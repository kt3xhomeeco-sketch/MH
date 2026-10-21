# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
analysis = JSON.parse(File.read(File.join(root, 'outputs', 'envelope-preview-fixture.json'), encoding: 'UTF-8'))
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
selection = model.selection.to_a
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Khung Bao Và Nhận Box Đúng', true)
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  source = model.entities.add_group
  analysis['outlines'].each do |outline|
    a, b = outline['points'].map { |point| point + [73] }
    source.entities.add_line(a.map(&:mm), b.map(&:mm))
  end
  analysis['source_watch'] = source.entities.grep(Sketchup::Edge).map do |edge|
    [edge.persistent_id.to_s, [source.persistent_id], edge.start.position.to_a.map(&:to_mm), edge.end.position.to_a.map(&:to_mm)]
  end
  preview = app::Model.build(analysis, 'E:/MH_CAD2Module_QA/AI/tests/envelope-preview-native', app::Ids.uuid, model)
  raise 'Preview must be one independent solid' unless preview.members.length == 1 && preview.members.first.manifold? && preview.members.first.parent == model
  raise 'Preview was not visually distinguished' unless preview.members.first.material.color.to_a.first(3) == [255, 180, 70]
  saved = JSON.parse(preview.get_attribute(app::Model::DICT, 'analysis'))
  raise 'Preview reported as correct' unless saved['status'] == 'needs_review' && saved['envelope_preview'] && saved['error']
  raise 'Preview source position changed' unless preview.members.first.bounds.min.to_a.map(&:to_mm).zip([30_000, 40_000, 73]).all? { |a, b| (a - b).abs < 0.01 }
  forged = Marshal.load(Marshal.dump(saved)); forged['modules'][0]['size'][0] += 10
  begin
    app::Placement.validate_envelope_preview(forged)
    raise 'Invented envelope size was accepted'
  rescue ArgumentError => error
    raise 'Wrong rejection' unless error.message.include?('khung bao')
  end
  app::Corrections.begin_manual(preview)
  raise 'Sai hid editable preview' if preview.hidden?
  boxes = 2.times.map do |i|
    app::Model.cube(model.entities, 'id' => "Q#{i}", 'origin' => [-5000 + 520 * i, -5000, 0], 'size' => [520, 500, 1600])
  end
  model.selection.clear; model.selection.add(boxes)
  event = app::Corrections.accept_manual
  corrected = JSON.parse(preview.get_attribute(app::Model::DICT, 'analysis'))
  raise 'Manual corrected result still marked provisional layout' unless corrected['status'] == 'ready' && !corrected['envelope_preview'] && corrected['manual_boxes']
  raise 'Wrong selected-box acceptance' unless event['status'] == 'accepted' && event['input_axes_ignored'] && event['after']['modules'].length == 2
  raise 'Corrected boxes not built independently' unless preview.members.length == 2 && preview.members.all?(&:manifold?)
ensure
  session = app::Corrections.instance_variable_get(:@session)
  if session
    model.remove_observer(app::Corrections.instance_variable_get(:@observer))
    app::Corrections.instance_variable_set(:@session, nil)
  end
  originals.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Temporary registry leaked' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
result = { passed: true, preview_solid_and_source_position: true, orange_preview: true, diagnostic_retained: true,
           wrong_and_selected_correct_boxes: true, correction_accepted: true, user_geometry_unchanged: true }
app::Storage.write_json(File.join(root, 'outputs', 'envelope-preview-native-result.json'), result)
puts JSON.generate(result)
