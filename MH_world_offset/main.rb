# encoding: UTF-8
require 'sketchup.rb'

module MH
  module WorldOffset
    PLUGIN_ID = 'mh_world_offset'.freeze
    CMD_TEXT = 'MH World Resize'.freeze
    EPSILON = 1.0e-9

    # Standalone geometry helpers copied/adapted from the MH shared geometry
    # layer. Keep this extension independent from MH_shared.
    module Geometry
      module_function

      def container?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def child_entities(entity)
        return entity.entities if entity.is_a?(Sketchup::Group)
        return entity.definition.entities if entity.is_a?(Sketchup::ComponentInstance) && entity.definition

        nil
      rescue
        nil
      end

      def path_transform(path)
        transform = Geom::Transformation.new
        Array(path).each do |entity|
          transform *= entity.transformation if container?(entity)
        end
        transform
      end

      def pick_face(view, x, y, aperture = 8)
        helper = view.pick_helper
        helper.do_pick(x, y, aperture)

        (0...helper.count).each do |index|
          path = helper.path_at(index)
          next unless path

          face = Array(path).reverse.find { |entity| entity.is_a?(Sketchup::Face) }
          next unless face && face.valid?

          instances = Array(path).select { |entity| container?(entity) }
          next if instances.empty?

          transform = helper.transformation_at(index)
          transform ||= path_transform(path)
          axes = face_axes_world(face, transform)
          axes = orient_axes_to_view(view, face.bounds.center.transform(transform), axes) if axes
          return {
            face: face,
            target: instances.last,
            transform: transform,
            axes: axes,
            path: path
          }
        end

        nil
      rescue
        nil
      end

      def active_context_transform(model)
        return Geom::Transformation.new unless model && model.respond_to?(:edit_transform)

        model.edit_transform || Geom::Transformation.new
      rescue
        Geom::Transformation.new
      end

      def instance_world_transform(instance, model = Sketchup.active_model)
        active_context_transform(model) * instance.transformation
      rescue
        instance.transformation
      end

      def local_bounds(instance)
        return nil unless instance
        return instance.definition.bounds if instance.respond_to?(:definition) && instance.definition
        return instance.local_bounds if instance.respond_to?(:local_bounds)

        instance.bounds if instance.respond_to?(:bounds)
      rescue
        nil
      end

      def collect_content_points(instance)
        entities = child_entities(instance)
        return [] unless entities

        points = []
        collect_entity_points(entities, Geom::Transformation.new, points)
        points
      rescue
        []
      end

      def collect_entity_points(entities, transform, points)
        entities.each do |entity|
          if entity.is_a?(Sketchup::Edge)
            points << entity.start.position.transform(transform)
            points << entity.end.position.transform(transform)
          elsif container?(entity)
            nested_entities = child_entities(entity)
            collect_entity_points(nested_entities, transform * entity.transformation, points) if nested_entities
          end
        end
      end

      def bbox_corners(bounds)
        (0..7).map { |index| bounds.corner(index) }
      end

      def content_points_or_bounds(instance, bounds)
        points = collect_content_points(instance)
        points.empty? ? bbox_corners(bounds) : points
      end

      def face_axes_world(face, transform)
        world_edges = face.outer_loop.edges.filter_map do |edge|
          p1 = edge.start.position.transform(transform)
          p2 = edge.end.position.transform(transform)
          vector = p1.vector_to(p2)
          vector.length > EPSILON ? vector : nil
        end
        return nil if world_edges.length < 2

        u = world_edges.max_by(&:length).clone
        u.normalize!
        second = world_edges.max_by { |vector| u.cross(vector).length }
        return nil unless second

        normal = u.cross(second)
        return nil if normal.length <= EPSILON
        normal.normalize!

        transformed_normal = face.normal.transform(transform)
        normal.reverse! if transformed_normal.length > EPSILON && normal.dot(transformed_normal) < 0.0

        v = normal.cross(u)
        return nil if v.length <= EPSILON
        v.normalize!

        { u: u, v: v, n: normal }
      rescue
        nil
      end

      def orient_axes_to_view(view, center, axes)
        return axes unless view && center && axes

        u = axes[:u]
        v = axes[:v]
        probe = 100.mm
        center_screen = view.screen_coords(center)
        u_screen = view.screen_coords(center.offset(u, probe))
        v_screen = view.screen_coords(center.offset(v, probe))
        u_dx = u_screen.x - center_screen.x
        u_dy = u_screen.y - center_screen.y
        v_dx = v_screen.x - center_screen.x
        v_dy = v_screen.y - center_screen.y

        if u_dx.abs >= v_dx.abs
          right = u_dx >= 0.0 ? u.clone : u.reverse
          top = v_dy <= 0.0 ? v.clone : v.reverse
        else
          right = v_dx >= 0.0 ? v.clone : v.reverse
          top = u_dy <= 0.0 ? u.clone : u.reverse
        end

        normal = right.cross(top)
        normal.normalize! if normal.length > EPSILON
        { u: right, v: top, n: normal }
      rescue
        axes
      end

      def local_basis_from_world_axes(transform, axes)
        inverse = transform.inverse
        u = axes[:u].transform(inverse)
        v_hint = axes[:v].transform(inverse)
        return nil if u.length <= EPSILON || v_hint.length <= EPSILON

        u.normalize!
        w = u.cross(v_hint)
        return nil if w.length <= EPSILON
        w.normalize!
        v = w.cross(u)
        return nil if v.length <= EPSILON
        v.normalize!

        { u: u, v: v, w: w }
      rescue
        nil
      end

      def projected_range(points, axis)
        values = points.map { |point| point.x * axis.x + point.y * axis.y + point.z * axis.z }
        [values.min, values.max]
      end

      def oriented_center(points, basis)
        ur = projected_range(points, basis[:u])
        vr = projected_range(points, basis[:v])
        wr = projected_range(points, basis[:w])
        coords = [
          (ur[0] + ur[1]) * 0.5,
          (vr[0] + vr[1]) * 0.5,
          (wr[0] + wr[1]) * 0.5
        ]
        Geom::Point3d.new(
          basis[:u].x * coords[0] + basis[:v].x * coords[1] + basis[:w].x * coords[2],
          basis[:u].y * coords[0] + basis[:v].y * coords[1] + basis[:w].y * coords[2],
          basis[:u].z * coords[0] + basis[:v].z * coords[1] + basis[:w].z * coords[2]
        )
      end

      def extent_world(points_local, transform, axis_world)
        axis = axis_world.clone
        axis.normalize!
        values = points_local.map do |point|
          world = point.transform(transform)
          world.x * axis.x + world.y * axis.y + world.z * axis.z
        end
        (values.max - values.min).abs
      end

      def principal_face(instance, transform)
        entities = child_entities(instance)
        return nil unless entities

        faces = entities.grep(Sketchup::Face)
        faces.max_by { |face| face.area(transform).to_f }
      rescue
        nil
      end

      def camera_facing_face(instance, transform, view)
        entities = child_entities(instance)
        return nil unless entities && view && view.camera

        eye = view.camera.eye
        dir = view.camera.direction.clone
        return nil if dir.length <= EPSILON
        dir.normalize!

        faces = entities.grep(Sketchup::Face).select(&:valid?)
        return nil if faces.empty?

        picked = faces.map do |face|
          axes = face_axes_world(face, transform)
          next unless axes

          normal = axes[:n]

          center = face.bounds.center.transform(transform)
          to_eye = center.vector_to(eye)
          if to_eye.length > EPSILON
            to_eye.normalize!
            facing = normal.dot(to_eye)
          else
            facing = -normal.dot(dir)
          end

          depth = eye.vector_to(center).dot(dir)
          area = face.area(transform).to_f
          [face, facing, depth, area]
        end.compact

        front = picked.select { |item| item[1] > 0.05 }
        candidates = front.empty? ? picked : front
        best = candidates.max_by { |item| [item[1], -item[2], item[3]] }
        best && best[0]
      rescue
        nil
      end
    end

    class ObjectResizeTool
      def initialize
        @hover_pick = nil
        @last_pair_text = Sketchup.read_default(PLUGIN_ID, 'last_pair_text', '1,1')
        @selected_picks = []
        @last_cam_dir = nil
        @last_selection_signature = nil
      end

      def activate
        refresh_selected_picks(Sketchup.active_model.active_view)
        if @selected_picks.empty?
          Sketchup.status_text = 'VCB: "tren,phai" hoac "tren,phai,duoi,trai". Hover/click mat de ap dung.'
        else
          Sketchup.status_text = "Da nhan #{@selected_picks.length} object duoc chon truoc. Click de ap dung theo VCB."
        end
        sync_vcb_display
      end

      def deactivate(view)
        @hover_pick = nil
        @selected_picks = []
        @last_cam_dir = nil
        @last_selection_signature = nil
        view.invalidate if view
      end

      def enableVCB?
        true
      end

      def onMouseMove(_flags, x, y, view)
        pick = face_owner_pick_from_view(view, x, y)
        if !@selected_picks.empty? && pick
          selected_targets = @selected_picks.map { |item| item[:target] }
          pick = nil unless selected_targets.include?(pick[:target])
        end
        if !same_pick?(@hover_pick, pick)
          @hover_pick = pick
          view.invalidate
        end
      end

      def onLButtonDown(_flags, x, y, view)
        unless @selected_picks.empty?
          maybe_refresh_selected_picks(view)
          apply_resize_to_selected
          sync_vcb_display
          view.invalidate
          return
        end

        pick = face_owner_pick_from_view(view, x, y)
        unless pick
          UI.beep
          Sketchup.status_text = 'Khong pick duoc mat thuoc Group/Component.'
          return
        end
        apply_resize_from_pick(pick)
        sync_vcb_display
      end

      def onUserText(text, view)
        pair = parse_pair_text(text)
        unless pair
          UI.beep
          Sketchup.status_text = 'Sai dinh dang. Nhap "tren,phai" hoac "tren,phai,duoi,trai".'
          return
        end

        @last_pair_text = text.to_s.strip
        Sketchup.write_default(PLUGIN_ID, 'last_pair_text', @last_pair_text)
        sync_vcb_display
        if @selected_picks.empty?
          Sketchup.status_text = "Da cap nhat VCB: #{@last_pair_text}. Hover/click object de ap dung."
        else
          Sketchup.status_text = "Da cap nhat VCB: #{@last_pair_text}. Click de ap dung cho #{@selected_picks.length} object da chon."
        end
      end

      def resume(_view)
        sync_vcb_display
      end

      def apply_resize_from_pick(pick)
        pair = parse_pair_text(@last_pair_text)
        unless pair
          UI.messagebox('VCB khong hop le. Nhap "1,2" hoac "1,2,3,4".')
          return
        end
        model = Sketchup.active_model
        model.start_operation('MH World Resize by Hover Face', true)
        begin
          result = resize_pick_geometry(pick, pair)
          unless result[:ok]
            model.abort_operation
            UI.messagebox(result[:message])
            return
          end
          model.commit_operation
          Sketchup.status_text = "Da thu: Len=#{result[:reduce_len].to_l} Rong=#{result[:reduce_wid].to_l} (world, tong 2 ben)"
          sync_vcb_display
        rescue => e
          model.abort_operation
          UI.messagebox("Khong the thu kich thuoc object: #{e.message}")
          sync_vcb_display
        end
      end

      def apply_resize_to_selected
        if @selected_picks.empty?
          UI.beep
          return
        end
        model = Sketchup.active_model
        model.start_operation('MH World Resize Selected Objects', true)
        begin
          ok_count = 0
          pair = parse_pair_text(@last_pair_text)
          @selected_picks.each do |pick|
            result = resize_pick_geometry(pick, pair)
            ok_count += 1 if result[:ok]
          end
          model.commit_operation
          refresh_selected_picks(model.active_view)
          Sketchup.status_text = "Da ap dung cho #{ok_count}/#{@selected_picks.length} object theo VCB #{@last_pair_text}."
          sync_vcb_display
        rescue => e
          model.abort_operation
          UI.messagebox("Khong the ap dung cho selection: #{e.message}")
          sync_vcb_display
        end
      end

      def draw(view)
        maybe_refresh_selected_picks(view)

        unless @selected_picks.empty?
          @selected_picks.each { |pick| draw_pick_face(view, pick) }
          return
        end
        return unless @hover_pick

        draw_pick_face(view, @hover_pick)
      end

      private

      def sync_vcb_display
        Sketchup.vcb_label = 'Tren,Phai[,Duoi,Trai] mm'
        Sketchup.vcb_value = @last_pair_text.to_s
      rescue
        nil
      end

      def draw_pick_face(view, pick)
        face = pick[:face]
        tr = pick[:transform]
        target = pick[:target]
        bb = local_bounds_for_instance(target)
        return unless face&.valid? && bb

        face_pts = face.outer_loop.vertices.map { |v| v.position.transform(tr) }
        return if face_pts.length < 3

        dir_sign = preview_direction_sign

        # Outer dashed blue border
        view.drawing_color = Sketchup::Color.new(0, 60, 255)
        view.line_width = 3
        blue_loop = inset_loop_world(face, tr, 0.8.mm * dir_sign)
        blue_loop = face_pts unless blue_loop && blue_loop.length >= 3
        draw_dashed_loop(view, blue_loop, 8.mm, 4.mm)

        # Dashed orange border near boundary (inside when +, outside when -)
        inset_a = inset_loop_world(face, tr, 1.5.mm * dir_sign)
        if inset_a && inset_a.length >= 3
          view.drawing_color = Sketchup::Color.new(255, 165, 0)
          view.line_width = 2
          draw_dashed_loop(view, inset_a, 6.mm, 3.mm)
        end

        # Dashed green border deeper (inside when +, outside when -)
        inset_b = inset_loop_world(face, tr, 12.mm * dir_sign)
        if inset_b && inset_b.length >= 3
          view.drawing_color = Sketchup::Color.new(0, 160, 60)
          view.line_width = 2
          draw_dashed_loop(view, inset_b, 6.mm, 3.mm)
        end

        axes = pick[:axes] || Geometry.face_axes_world(face, tr)
        # Center 4 triangular arrows in red (aligned to face plane)
        c = face.bounds.center.transform(tr)
        draw_center_arrows(view, c, axes, 100.mm, 36.mm)
      end

      def preview_direction_sign
        pair = parse_pair_text(@last_pair_text)
        return 1.0 unless pair
        avg = [:top, :right, :bottom, :left].sum { |key| pair[key].to_f } / 4.0
        avg < 0.0 ? -1.0 : 1.0
      rescue
        1.0
      end

      def draw_center_arrows(view, center, axes, offset, stem_gap)
        return unless axes
        u = axes[:u]
        v = axes[:v]
        directions = [
          [u, v], [u.reverse, v],
          [v, u], [v.reverse, u]
        ]
        view.drawing_color = Sketchup::Color.new(255, 0, 0)
        directions.each do |dir, side|
          base_center = center.offset(dir, stem_gap)
          tip = center.offset(dir, offset)
          depth = base_center.distance(tip)
          next if depth <= 1.0e-9
          half_base = depth / Math.sqrt(3.0) # equilateral triangle
          p1 = base_center.offset(side, half_base)
          p2 = base_center.offset(side.reverse, half_base)
          view.draw(GL_TRIANGLES, tip, p1, p2)
        end
      end

      def draw_dashed_loop(view, pts, dash_len, gap_len)
        n = pts.length
        return if n < 2
        n.times do |i|
          p0 = pts[i]
          p1 = pts[(i + 1) % n]
          draw_dashed_segment(view, p0, p1, dash_len, gap_len)
        end
      end

      def draw_dashed_segment(view, p0, p1, dash_len, gap_len)
        edge = p0.vector_to(p1)
        len = edge.length
        return if len <= 1.0e-9
        dir = edge.clone
        dir.length = 1.0
        step = dash_len + gap_len
        t = 0.0
        while t < len
          a = t
          b = [t + dash_len, len].min
          pa = p0.offset(dir, a)
          pb = p0.offset(dir, b)
          view.draw(GL_LINES, pa, pb)
          t += step
        end
      end

      def draw_face_filled(view, face, tr)
        mesh = face.mesh
        return unless mesh
        view.drawing_color = Sketchup::Color.new(255, 170, 60, 90)
        mesh.polygons.each do |poly|
          pts = poly.map { |idx| mesh.point_at(idx.abs).transform(tr) }
          next if pts.length < 3
          view.draw(GL_POLYGON, pts)
        end
      rescue
        nil
      end

      def inset_loop_world(face, tr_world, dist)
        verts = face.outer_loop.vertices.map(&:position)
        return nil if verts.length < 3

        origin, u, v = face_plane_axes_local(face)
        poly = verts.map do |pt|
          vec = origin.vector_to(pt)
          [vec.dot(u), vec.dot(v)]
        end
        poly = remove_duplicate_2d_points(poly)
        poly = remove_collinear_2d_points(poly)
        return nil if poly.length < 3

        area = signed_area_2d(poly)
        return nil if area.abs < 1.0e-9
        inward = area > 0.0 ? dist.to_f : -dist.to_f
        off = offset_polygon_2d(poly, inward)
        return nil unless off && off.length >= 3

        off.map do |xy|
          p = origin.offset(u, xy[0]).offset(v, xy[1])
          p.transform(tr_world)
        end
      rescue
        nil
      end

      def face_plane_axes_local(face)
        origin = face.vertices.first.position
        n = face.normal
        ref = n.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
        u = n * ref
        if u.length <= 1.0e-9
          ref = Y_AXIS
          u = n * ref
        end
        u.normalize!
        v = n * u
        v.normalize!
        [origin, u, v]
      end

      def remove_duplicate_2d_points(poly)
        result = []
        poly.each do |p|
          if result.empty?
            result << p
            next
          end
          result << p unless near_2d?(p, result[-1])
        end
        result.pop if result.length > 2 && near_2d?(result[0], result[-1])
        result
      end

      def remove_collinear_2d_points(poly, eps = 1.0e-10)
        return poly if poly.length < 4
        out = []
        n = poly.length
        n.times do |i|
          a = poly[(i - 1) % n]
          b = poly[i]
          c = poly[(i + 1) % n]
          abx = b[0] - a[0]
          aby = b[1] - a[1]
          bcx = c[0] - b[0]
          bcy = c[1] - b[1]
          cross = abx * bcy - aby * bcx
          out << b if cross.abs > eps
        end
        out.length >= 3 ? out : poly
      end

      def near_2d?(a, b, eps = 1.0e-9)
        (a[0] - b[0]).abs <= eps && (a[1] - b[1]).abs <= eps
      end

      def signed_area_2d(poly)
        area = 0.0
        n = poly.length
        n.times do |i|
          j = (i + 1) % n
          area += poly[i][0] * poly[j][1] - poly[j][0] * poly[i][1]
        end
        area * 0.5
      end

      def offset_polygon_2d(poly, signed_distance)
        n = poly.length
        lines = []
        n.times do |i|
          p1 = poly[i]
          p2 = poly[(i + 1) % n]
          ex = p2[0] - p1[0]
          ey = p2[1] - p1[1]
          len = Math.sqrt(ex * ex + ey * ey)
          return nil if len <= 1.0e-12
          nx = -ey / len
          ny = ex / len
          q1 = [p1[0] + nx * signed_distance, p1[1] + ny * signed_distance]
          q2 = [p2[0] + nx * signed_distance, p2[1] + ny * signed_distance]
          lines << [q1, q2]
        end

        out = []
        n.times do |i|
          l_prev = lines[(i - 1) % n]
          l_curr = lines[i]
          ip = line_intersection_2d(l_prev[0], l_prev[1], l_curr[0], l_curr[1])
          ip ||= l_curr[0]
          out << ip
        end
        out
      end

      def line_intersection_2d(a1, a2, b1, b2)
        x1, y1 = a1
        x2, y2 = a2
        x3, y3 = b1
        x4, y4 = b2
        den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        return nil if den.abs <= 1.0e-12
        t1 = (x1 * y2 - y1 * x2)
        t2 = (x3 * y4 - y3 * x4)
        px = (t1 * (x3 - x4) - (x1 - x2) * t2) / den
        py = (t1 * (y3 - y4) - (y1 - y2) * t2) / den
        [px, py]
      end

      def same_pick?(a, b)
        return true if a.nil? && b.nil?
        return false if a.nil? || b.nil?
        a[:target] == b[:target] && a[:face] == b[:face]
      end

      def refresh_selected_picks(view = nil)
        @selected_picks = []
        model = Sketchup.active_model
        selection = model.selection.to_a
        @last_selection_signature = selection_signature(selection)
        @last_cam_dir = camera_dir(view)
        return if selection.empty?

        selection.each do |ent|
          next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
          tr = Geometry.instance_world_transform(ent, model)
          face = Geometry.camera_facing_face(ent, tr, view)
          face ||= Geometry.principal_face(ent, tr)
          next unless face
          axes = Geometry.face_axes_world(face, tr)
          axes = Geometry.orient_axes_to_view(view, face.bounds.center.transform(tr), axes) if axes
          @selected_picks << { face: face, target: ent, transform: tr, axes: axes }
        end
      end

      def maybe_refresh_selected_picks(view)
        model = Sketchup.active_model
        selection = model.selection.to_a
        sig = selection_signature(selection)
        cam = camera_dir(view)

        selection_changed = (sig != @last_selection_signature)
        camera_changed = camera_dir_changed?(cam, @last_cam_dir)
        return unless selection_changed || camera_changed

        refresh_selected_picks(view)
      end

      def selection_signature(selection)
        ids = selection.map do |e|
          begin
            e.persistent_id
          rescue
            e.object_id
          end
        end
        ids.sort.join('|')
      end

      def camera_dir(view)
        return nil unless view && view.camera
        v = view.camera.direction.clone
        return nil if v.length <= 1.0e-9
        v.normalize!
        v
      rescue
        nil
      end

      def camera_dir_changed?(a, b)
        return true if a.nil? != b.nil?
        return false if a.nil? && b.nil?
        # refresh only when camera direction changed enough
        (a.dot(b) < 0.9995)
      end

      def resize_pick_geometry(pick, pair = nil)
        pair ||= parse_pair_text(@last_pair_text)
        return resize_error('Gia tri VCB khong hop le.') unless pair
        top = pair[:top]
        right = pair[:right]
        bottom = pair[:bottom]
        left = pair[:left]
        reduce_horizontal = left + right
        reduce_vertical = top + bottom

        target = pick[:target]
        tr_world = pick[:transform]
        face = pick[:face]
        bb = Geometry.local_bounds(target)
        return resize_error('Khong doc duoc bounding box cua object.') unless bb && face

        face_axes = pick[:axes] || Geometry.face_axes_world(face, tr_world)
        return resize_error('Khong xac dinh duoc truc Dai/Rong tu mat.') unless face_axes
        right_world = face_axes[:u]
        top_world = face_axes[:v]

        points_local = Geometry.content_points_or_bounds(target, bb)
        extent_horizontal = Geometry.extent_world(points_local, tr_world, right_world)
        extent_vertical = Geometry.extent_world(points_local, tr_world, top_world)
        if extent_horizontal <= 1.0e-6 || extent_vertical <= 1.0e-6
          return resize_error('Kich thuoc object theo mat qua nho.')
        end

        new_horizontal = extent_horizontal - reduce_horizontal
        new_vertical = extent_vertical - reduce_vertical
        if new_horizontal <= 1.0e-6 || new_vertical <= 1.0e-6
          return resize_error(
            "Gia tri giam qua lon. Hien tai Ngang=#{extent_horizontal.to_l}, Doc=#{extent_vertical.to_l}"
          )
        end

        sx = new_horizontal / extent_horizontal
        sy = new_vertical / extent_vertical

        local_axes = Geometry.local_basis_from_world_axes(tr_world, face_axes)
        return resize_error('Khong doi duoc truc world ve local cua object.') unless local_axes

        center_local = Geometry.oriented_center(points_local, local_axes)
        basis = Geom::Transformation.axes(
          center_local,
          local_axes[:u],
          local_axes[:v],
          local_axes[:w]
        )
        scale = Geom::Transformation.scaling(ORIGIN, sx, sy, 1.0)
        scale_about_center = basis * scale * basis.inverse

        # Positive U points right, positive V points up on screen.
        # Move the scaled result so every requested side offset is independent.
        shift_world = Geom::Vector3d.new(
          right_world.x * ((left - right) * 0.5) + top_world.x * ((bottom - top) * 0.5),
          right_world.y * ((left - right) * 0.5) + top_world.y * ((bottom - top) * 0.5),
          right_world.z * ((left - right) * 0.5) + top_world.z * ((bottom - top) * 0.5)
        )
        shift_local = shift_world.transform(tr_world.inverse)
        local_adjust = Geom::Transformation.translation(shift_local) * scale_about_center
        target.transformation = target.transformation * local_adjust
        {
          ok: true,
          reduce_len: reduce_vertical,
          reduce_wid: reduce_horizontal,
          extent_len: extent_vertical,
          extent_wid: extent_horizontal
        }
      rescue => e
        resize_error("Khong the tinh resize: #{e.message}")
      end

      def resize_error(message)
        { ok: false, message: message }
      end

      def face_owner_pick_from_view(view, x, y)
        Geometry.pick_face(view, x, y)
      end

      def parse_length(value)
        return nil if value.nil?
        s = value.to_s.strip
        return nil if s.empty?
        if s =~ /[a-zA-Z\"']/
          s.to_l
        else
          "#{s}mm".to_l
        end
      rescue
        nil
      end

      def parse_pair_text(text)
        raw = text.to_s.strip
        return nil if raw.empty?
        parts = raw.split(',').map(&:strip)
        return nil unless parts.length == 2 || parts.length == 4

        values = parts.map { |part| parse_length(part) }
        return nil if values.any?(&:nil?)

        if values.length == 2
          {
            top: values[0],
            right: values[1],
            bottom: values[0],
            left: values[1]
          }
        else
          {
            top: values[0],
            right: values[1],
            bottom: values[2],
            left: values[3]
          }
        end
      end

      def local_bounds_for_instance(inst)
        Geometry.local_bounds(inst)
      end
    end

    def self.activate_tool
      Sketchup.active_model.select_tool(ObjectResizeTool.new)
    end

    unless file_loaded?(__FILE__)
      cmd = UI::Command.new(CMD_TEXT) { activate_tool }
      icon_path = File.join(__dir__, 'offset.svg')
      if File.exist?(icon_path)
        cmd.small_icon = icon_path
        cmd.large_icon = icon_path
      end
      cmd.tooltip = 'Resize 2/4 canh cua Group/Component theo mat hover (world size).'
      cmd.status_bar_text = 'VCB: tren,phai hoac tren,phai,duoi,trai.'

      UI.menu('Plugins').add_item(cmd)

      toolbar = UI::Toolbar.new(CMD_TEXT)
      toolbar.add_item(cmd)
      toolbar.restore

      file_loaded(__FILE__)
    end
  end
end
