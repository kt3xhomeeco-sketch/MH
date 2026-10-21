# frozen_string_literal: true

app = MH::CAD2Module
model = Sketchup.active_model
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
root = app::Settings::ROOT
%w[selection_source.rb jobs.rb corrections.rb main.rb].each { |file| load File.join(root, file) }
%i[STOCK TOLERANCE].each { |name| app::ManualBoxes.send(:remove_const, name) }
load File.join(root, 'manual_boxes.rb')
baseline = model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
selection = model.selection.to_a
registry = model.attribute_dictionary(app::Assembly::DICT)&.to_h
analysis = JSON.parse(File.read(File.join(root, 'library/jobs/bebea3df-edcb-b4f7-ef26-080cd4059920/response.json')))['analyses'][0]['products'][0]
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
started = clock.call
app::SelectionSource.validate_watch(analysis['source_watch'], model)
watch_seconds = clock.call - started
qa_root = 'E:/MH_CAD2Module_QA/AI/tests/latency-registration-native'
originals = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
originals[:start_operation][0].call('CAD2Module: Kiểm Tra Vị Trí Nhận Box', true)
results = []
begin
  originals.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  %w[XY XZ YZ].each do |plane|
    fixture = JSON.parse(File.read(File.join(root, 'outputs/envelope-preview-fixture.json')))
    fixture.delete('envelope_preview'); fixture.delete('error')
    fixture['status'] = 'ready'; fixture['code'] = "QA-#{app::Ids.uuid}"
    fixture['placement']['plane'] = plane
    fixture['modules'][0].delete('envelope_preview')
    fixture['modules'][0]['origin'] = [0, 23.986, 0]
    fixture['modules'][0]['size'] = [1040, 476.014, 1600]
    product = app::Model.build(fixture, qa_root, app::Ids.uuid, model)
    app::Corrections.begin_manual(product)
    boxes = [510, 530].each_with_index.map do |width, index|
      box = app::Model.cube(model.entities, 'id' => "Q#{index}", 'origin' => [index * 510, 23.986, 0], 'size' => [width, 476.014, 1600])
      box.transformation = product.transformation * box.transformation
      box
    end
    expected = boxes.map { |box| [box.bounds.min.to_a, box.bounds.max.to_a] }.sort
    model.selection.clear; model.selection.add(boxes)
    event = app::Corrections.accept_manual
    actual = product.members.map { |box| [box.bounds.min.to_a, box.bounds.max.to_a] }.sort
    raise 'Acceptance moved selected boxes' unless expected.flatten.zip(actual.flatten).all? { |a, b| (a - b).abs < 0.001 }
    raise 'Lost Y offset in accepted experience' unless (event['plan_origin_offset_mm'][1] - 23.986).abs < 0.001
    raise 'Original inputs not retained' unless boxes.all?(&:hidden?)
    results << { plane: plane, captured_y_mm: 23.986, world_position_preserved: true, experience_offset_preserved: true }
  end
  source = model.entities.add_group
  edge = source.entities.add_line([0, 0, 0], [10, 0, 0])
  watch = [[edge.persistent_id.to_s, [source.persistent_id], [0, 0, 0], [254, 0, 0]]]
  app::SelectionSource.validate_watch(watch, model)
  source.transform!(Geom::Transformation.translation([1, 0, 0]))
  rejected = false
  begin
    app::SelectionSource.validate_watch(watch, model)
  rescue ArgumentError
    rejected = true
  end
  raise 'Moved source was accepted' unless rejected
ensure
  model.remove_observer(app::Corrections.instance_variable_get(:@observer))
  app::Corrections.instance_variable_set(:@session, nil)
  originals.each do |name, (method, singleton)|
    model.singleton_class.send(:remove_method, name)
    model.define_singleton_method(name) { |*args| method.call(*args) } if singleton
  end
  originals[:abort_operation][0].call
  model.selection.clear; model.selection.add(selection.select(&:valid?))
end
raise 'User geometry changed' unless baseline == model.entities.map { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?] }
raise 'Registry changed' unless registry == model.attribute_dictionary(app::Assembly::DICT)&.to_h
receipt = { passed: true, source_watch_seconds: watch_seconds, correction_cases: results, moved_source_rejected: true, user_geometry_unchanged: true }
app::Storage.write_json(File.join(root, 'outputs/latency-registration-native-result.json'), receipt)
puts JSON.generate(receipt)
