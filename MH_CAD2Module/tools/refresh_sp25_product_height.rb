# frozen_string_literal: true

app = MH::CAD2Module; model = Sketchup.active_model; root = app::Settings::ROOT; dict = app::Model::DICT
raise 'Busy/editing/correcting' if app::Jobs.busy? || app::Corrections.active? || model.active_path
raise 'Wrong model' unless model.path.tr('\\', '/').casecmp('E:/MAC/OneDrive/Desktop/1.skp').zero?
targets = { 'V01.1' => ['assembly-6848aaec-ec50-ac98-7b02-4b7f480b056a', 619361],
            'V04.1' => ['assembly-77fe5478-5e1f-3763-ace9-19dfc54dd439', 622735],
            'V05.1' => ['assembly-f7931bc1-ff68-d4e5-613e-4b6dc44a6e94', 622805] }
packets = JSON.parse(File.read(File.join(root, 'outputs/sp25-sections-product.json'), encoding: 'UTF-8'))['plan_results']
products = app::Model.products(model)
pairs = targets.map do |view, (id, box_id)|
  instance = products.find { |p| p.persistent_id == id }
  raise 'SP25 membership changed' unless instance && instance.members.map(&:persistent_id) == [box_id] &&
    instance.get_attribute(dict, 'code') == 'SP25' && instance.get_attribute(dict, 'plan_view_id') == view &&
    instance.get_attribute(dict, 'job_id') == '9eb649ce-84b6-3d26-6267-13040297de57'
  [instance, packets.find { |p| p['plan_view_id'] == view }]
end
snapshot = lambda { |e| [e.persistent_id, e.bounds.min.to_a, e.bounds.max.to_a, e.hidden?, e.layer.name, e.respond_to?(:transformation) ? e.transformation.to_a : nil] }
moving = targets.values.map(&:last); ids = model.entities.map(&:persistent_id)
protected = model.entities.reject { |e| moving.include?(e.persistent_id) }.map(&snapshot)
before = pairs.map { |p, _| { 'id' => p.persistent_id, 'analysis' => JSON.parse(p.get_attribute(dict, 'analysis')), 'state' => app::Model.state(p) } }
selection = model.selection.to_a; camera = model.active_view.camera; camera_state = [camera.eye.to_a, camera.target.to_a, camera.up.to_a]
sha = Digest::SHA256.file(model.path).hexdigest
backup = File.join(root, 'outputs', "sp25-height-before-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json")
app::Storage.write_json(backup, 'model' => model.path, 'products' => before)
ops = %i[start_operation commit_operation abort_operation].to_h { |name| [name, [model.method(name), model.singleton_class.instance_methods(false).include?(name)]] }
event = app::Storage.method(:event); queued = []; committed = false
library = app::Settings.library(app::Settings.read(model))
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ops[:start_operation][0].call('CAD2Module: Cao SP25', true)
begin
  ops.each_key { |name| model.define_singleton_method(name) { |*_args| true } }
  app::Storage.define_singleton_method(:event) { |*args| queued << args }
  pairs.each do |instance, packet|
    raise 'Edited/locked/already updated box; no live changes retained' unless app::ProductHeight.refresh_preview(model, instance, packet, library)
    box = app::Model.state(instance)['modules'].first
    raise 'Wrong live height' unless box['size'][2] == 2730 && box['origin'][2] == 0
  end
  raise 'CAD/other entities changed' unless ids == model.entities.map(&:persistent_id) && protected == model.entities.reject { |e| moving.include?(e.persistent_id) }.map(&snapshot)
  raise 'View/selection/file changed' unless selection == model.selection.to_a && camera_state == [camera.eye.to_a, camera.target.to_a, camera.up.to_a] && sha == Digest::SHA256.file(model.path).hexdigest
  ops[:commit_operation][0].call; committed = true
ensure
  app::Storage.define_singleton_method(:event, event)
  ops.each { |name, (method, owned)| owned ? model.define_singleton_method(name, method) : model.singleton_class.send(:remove_method, name) }
  ops[:abort_operation][0].call unless committed
end
queued.each { |args| event.call(*args) }
result = { passed: true, height_mm: 2730, updated_box_ids: moving, same_ids_xy: true, cad_other_geometry_selection_camera_preserved: true,
           module_partition_still_pending: true, backup: backup, model_saved: false, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
app::Storage.write_json(File.join(root, 'outputs/sp25-height-live-result.json'), result)
puts JSON.generate(result)
