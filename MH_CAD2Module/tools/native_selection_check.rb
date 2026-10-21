# frozen_string_literal: true

require 'json'
plugin = File.expand_path('..', __dir__)
app = MH::CAD2Module
%w[settings storage jobs placement model corrections templates selection_source scan_tool main].each do |name|
  load File.join(plugin, name + '.rb')
end
model = Sketchup.active_model
baseline = model.entities.map(&:persistent_id).sort
previous_selection = model.selection.to_a
original_camera = model.active_view.camera
source = JSON.parse(File.read(File.join(plugin, 'outputs', 'actual-analysis.json'), encoding: 'UTF-8'))['products'][0]
model.start_operation('CAD2Module: Test Selection Source', true)
group = model.active_entities.add_group
source['outlines'].each do |outline|
  outline['points'].each_cons(2) do |a,b|
    next if a == b
    group.entities.add_line([*a,0].map(&:mm), [*b,0].map(&:mm))
  end
end
model.commit_operation
begin
  model.selection.clear
  model.selection.add(group)
  geometry = app::SelectionSource.capture(model)
  root = File.join(plugin, 'outputs', 'selection-worker')
  FileUtils.mkdir_p(root)
  request = { 'action'=>'geometry','geometry'=>geometry,'code'=>'SP01','library'=>root }
  app::Storage.write_json(File.join(plugin, 'outputs', 'selection-request.json'), request)
  view = model.active_view
  centre = group.bounds.center
  view.camera = Sketchup::Camera.new(centre.offset(Z_AXIS, 10_000.mm), centre, Y_AXIS, false)
  view.zoom(group)
  screen = 8.times.map { |i| view.screen_coords(group.bounds.corner(i)) }
  x0 = screen.map(&:x).min - 10
  y0 = screen.map(&:y).min - 10
  x1 = screen.map(&:x).max + 10
  y1 = screen.map(&:y).max + 10
  tool = app::ScanTool.new
  tool.onLButtonDown(0, x0, y0, view)
  tool.onMouseMove(0, x1, y1, view)
  tool.onLButtonUp(0, x1, y1, view)
  scanned = app.instance_variable_get(:@selection_geometry)
  raise 'Scan tool did not capture the chosen CAD region' unless scanned && scanned['lines'].length == geometry['lines'].length
  app::Storage.write_json(File.join(plugin, 'outputs', 'scan-tool-result.json'), {'status'=>'passed','edges'=>scanned['lines'].length})
  puts JSON.generate({ edges: geometry['lines'].length, plane: geometry['plane'], snapshot: geometry['hash'] })
ensure
  app.instance_variable_get(:@entry)&.close
  app.instance_variable_set(:@selection_geometry, nil)
  model.active_view.camera = original_camera
  Sketchup.undo
  model.selection.clear
  model.selection.add(previous_selection.select(&:valid?))
  raise 'Original model changed' unless model.entities.map(&:persistent_id).sort == baseline
end
