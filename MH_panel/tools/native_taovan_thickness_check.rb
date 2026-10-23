# encoding: UTF-8
# QA probe for TaoVan draw-box auto-thickness. Run ONLY in a disposable empty Untitled model; no settings/material/camera/selection writes.
require 'sketchup'
unless defined?(MH::Panel::TaoVan)
  require File.join(File.expand_path('..', __dir__), 'src', 'main.rb')
end
module MH
  module Panel
    class NativeQaThicknessProbe < TaoVan
      def current_instance_setting; ''; end
      def source_for_detail_codes(_s, _d); nil; end
      def product_code_for_detail_codes(_s, _d); nil; end
      def sync_material_appearance(_t, _s); nil; end
      def apply_material_to_board(_b, _m); nil; end
    end
  end
end
def qa_mm(v); v.respond_to?(:to_mm) ? v.to_mm : (v.to_f / 1.mm); end
def qa_fmt(v); v.nil? ? 'nil' : format('%.3f', v); end
def qa_ivar(tool, vars); vars.each { |k, v| tool.instance_variable_set(k, v) }; end
def qa_pair(container)
  container.definition.entities.grep(Sketchup::Face).max_by(2) { |face| face.area }
end
def qa_world_thickness(container, transform)
  pair = qa_pair(container)
  return nil unless pair && pair.size == 2
  first, second = pair
  c1 = first.bounds.center.transform(transform)
  c2 = second.bounds.center.transform(transform)
  points = first.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
  normal = points.length >= 3 ? points[0].vector_to(points[1]).cross(points[1].vector_to(points[2])) : nil
  normal = first.normal.transform(transform) if !normal || normal.length < 0.001.mm
  normal.normalize!
  (c2 - c1).dot(normal).abs
rescue
  nil
end
def qa_snapshot(*containers)
  containers.compact.map do |container|
    faces = container.definition.entities.grep(Sketchup::Face).map do |face|
      [face.entityID, face.area.to_f, face.normal.to_a,
       face.outer_loop.vertices.map { |vertex| vertex.position.to_a }]
    end
    [container.entityID, container.transformation.to_a, faces]
  end
end
def qa_plate(entities, width, depth, thickness, transform = nil)
  group = entities.add_group
  face = group.entities.add_face(
    Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(width, 0, 0),
    Geom::Point3d.new(width, depth, 0), Geom::Point3d.new(0, depth, 0)
  )
  face.pushpull(thickness)
  group.transformation = transform if transform
  group
end
def qa_standalone(model, owned, thickness, transform)
  group = qa_plate(model.active_entities, 600.mm, 400.mm, thickness, transform)
  owned << group
  [nil, group, -> { group.transformation }]
end
def qa_nested(model, owned, thickness, outer_transform)
  outer = model.active_entities.add_group
  parent = qa_plate(outer.entities, 600.mm, 400.mm, thickness)
  outer.transformation = outer_transform
  owned << outer
  [outer, parent, -> { outer.transformation * parent.transformation }]
end
def qa_geometry(tool, parent, transform, ancestors = [])
  face = qa_pair(parent).first
  normal = face.normal.transform(transform)
  normal.normalize!
  points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
  qa_ivar(tool, {
    :@parent => parent, :@face => face, :@tr => transform, :@last_face => face,
    :@last_tr => transform, :@last_path => Array(ancestors).compact + [parent, face],
    :@normal => normal, :@p1 => points[0], :@p2 => points[0].offset(normal, 100.mm),
    :@p3 => points[0], :@free => false, :@locked_rect => points,
    :@rect_points => points, :@all_box_points => nil
  })
  face
end
def qa_init(tool, auto, manual)
  qa_ivar(tool, {
    :@do_day_tu_dong => auto, :@do_day => manual, :@do_day_khong_gian => manual,
    :@tinh_theo_khong_gian => true, :@so_khoang_cach => 1, :@che_do => 'lot_long',
    :@che_do_mo_rong => 2, :@mo_rong_bien => 0.0.mm, :@tut_hoi => 0.0.mm,
    :@tao_component => false, :@tu_dong_xoay_van => false, :@material => nil,
    :@material_name => nil, :@layer => '', :@instance => ''
  })
end
def qa_run(name, model, owned, auto, manual, expected_physical, expected_created)
  before_ids = []
  before_ids = model.entities.to_a.map(&:entityID)
  tool = MH::Panel::NativeQaThicknessProbe.allocate
  qa_init(tool, auto, manual)
  outer, parent, after_transform = yield(model, owned)
  qa_geometry(tool, parent, after_transform.call, outer)
  snapshot_before = qa_snapshot(outer, parent)
  tool.cap_nhat_do_day(parent)              # real sampling; must be read-only
  snapshot_after = qa_snapshot(outer, parent)
  source_same = snapshot_before == snapshot_after
  world_tr = after_transform.call
  qa_geometry(tool, parent, world_tr, outer) # next-hover refresh; sampled ivars intentionally retained
  physical = qa_world_thickness(parent, world_tr)
  sampled = tool.instance_variable_get(:@do_day_khong_gian)
  local = MH::Panel::Board.calc_thickness(parent)
  tool.calc_all_box_points
  boards = Array(tool.create_box)
  owned.concat(boards)
  created = boards.empty? ? nil : qa_world_thickness(boards.first, boards.first.transformation)
  pass = physical && sampled && created && source_same &&
         (qa_mm(physical) - expected_physical).abs <= 0.05 &&
         (qa_mm(sampled) - expected_created).abs <= 0.05 &&
         (qa_mm(created) - expected_created).abs <= 0.05
  puts format('QA_CASE %-22s physical=%-8s local=%-8s sampled=%-8s created=%-8s expected=%-6s source_same=%-5s %s',
              name, qa_fmt(physical && qa_mm(physical)), qa_fmt(local && qa_mm(local)),
              qa_fmt(sampled && qa_mm(sampled)), qa_fmt(created && qa_mm(created)),
              qa_fmt(expected_created), source_same.to_s, pass ? 'PASS' : 'FAIL')
  { name: name, pass: pass }
rescue => e
  puts "QA_CASE #{name} ERROR #{e.class}: #{e.message}"
  { name: name, pass: false, error: e.message }
ensure
  if before_ids
    owned.concat(model.entities.to_a.reject { |entity| before_ids.include?(entity.entityID) })
  end
  begin
    model.start_operation('MH QA cleanup', true, false, true)
    owned.select { |entity| entity && entity.valid? }.uniq { |entity| entity.entityID }.each(&:erase!)
  ensure
    model.commit_operation rescue nil
  end
  begin; model.definitions.purge_unused if model.definitions.respond_to?(:purge_unused); rescue; end
end
model = Sketchup.active_model
unless model.entities.to_a.empty? && model.definitions.to_a.empty?
  puts "QA_ABORT model not empty: entities=#{model.entities.length} definitions=#{model.definitions.length}"
  return
end
puts "QA_PID #{Process.pid}"
puts "QA_SRC cap_nhat_do_day=#{MH::Panel::TaoVan.instance_method(:cap_nhat_do_day).source_location.inspect}"
puts "QA_SRC calc_thickness=#{MH::Panel::Board.method(:calc_thickness).source_location.inspect}"
settings_before = MH::Panel::Settings.read_all
selection_before = model.selection.to_a.map(&:entityID)
view = model.active_view
camera_before = [view.camera.eye.to_a, view.camera.target.to_a, view.camera.up.to_a]
materials_before = model.materials.map(&:name)
owned = []
results = []
results << qa_run('standalone', model, owned, true, 17.6.mm, 17.6, 17.6) do |m, own|
  qa_standalone(m, own, 17.6.mm, Geom::Transformation.translation([100.mm, 0, 0]))
end
results << qa_run('own_scale_1.8', model, owned, true, 17.6.mm, 17.6, 17.6) do |m, own|
  tr = Geom::Transformation.translation([100.mm, 0, 0]) * Geom::Transformation.scaling(1.8)
  qa_standalone(m, own, 17.6.mm / 1.8, tr)
end
results << qa_run('nested_ancestor_1.8', model, owned, true, 17.6.mm, 17.6, 17.6) do |m, own|
  tr = Geom::Transformation.translation([100.mm, 0, 0]) * Geom::Transformation.scaling(1, 1, 1.8)
  qa_nested(m, own, 17.6.mm / 1.8, tr)
end
results << qa_run('rot_mirror_nonuniform', model, owned, true, 17.6.mm, 17.6, 17.6) do |m, own|
  tr = Geom::Transformation.translation([200.mm, 50.mm, 0]) *
       Geom::Transformation.rotation(ORIGIN, X_AXIS, 25.degrees) *
       Geom::Transformation.scaling(-0.7, 1.0, 1.8)
  qa_nested(m, own, 17.6.mm / 1.8, tr)
end
results << qa_run('auto_off_manual_9', model, owned, false, 9.0.mm, 17.6, 9.0) do |m, own|
  qa_standalone(m, own, 17.6.mm, Geom::Transformation.translation([100.mm, 0, 0]))
end
settings_after = MH::Panel::Settings.read_all
selection_after = model.selection.to_a.map(&:entityID)
camera_after = [view.camera.eye.to_a, view.camera.target.to_a, view.camera.up.to_a]
materials_after = model.materials.map(&:name)
puts "QA_SUMMARY pass=#{results.count { |r| r[:pass] }}/#{results.length} cases=#{results.map { |r| r[:name] }.join(',')}"
puts "QA_CLEANUP entities=#{model.entities.length} definitions=#{model.definitions.length} " \
     "settings_same=#{settings_before == settings_after} " \
     "selection_same=#{selection_before == selection_after} camera_same=#{camera_before == camera_after} " \
     "materials_same=#{materials_before == materials_after}"
puts 'QA_DONE'
