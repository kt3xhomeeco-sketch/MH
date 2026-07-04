# encoding: UTF-8

module MH::Scale
  class HitTest
    HANDLE_HIT_PX = 14
    PLANE_GRIP_HIT_PX = 12
    PLANE_STRETCH_HIT_PX = 12
    PLANE_STRETCH_OFFSET_PX = 28
    PLANE_EDGE_HIT_PX = 8

    def initialize(view, bb, planes, show_plane_stretch_grips = true)
      @view = view
      @bb = bb
      @planes = planes
      @show_plane_stretch_grips = show_plane_stretch_grips
      @scale = ui_scale
    end

    def hit(x, y)
      return nil if BoxModel.empty_bounds?(@bb)

      (@show_plane_stretch_grips && hit_plane_stretch_grip(x, y)) ||
        hit_face_handle(x, y) ||
        hit_plane_grip(x, y) ||
        hit_plane_body(x, y)
    end

    def hit_handle(x, y)
      return nil if BoxModel.empty_bounds?(@bb)

      hit_face_handle(x, y)
    end

    private

    def hit_plane_grip(x, y)
      @planes.each do |plane|
        next unless plane[:usable]

        center = BoxModel.plane_center(@bb, plane)
        sp = @view.screen_coords(center)
        next if Math.hypot(x - sp.x, y - sp.y) > PLANE_GRIP_HIT_PX * @scale

        return { kind: :plane, id: plane[:id], hit: :grip }
      end
      nil
    end

    def hit_plane_stretch_grip(x, y)
      @planes.each do |plane|
        next unless plane[:usable]

        [:minus, :plus].each do |side|
          sx, sy = plane_stretch_grip_xy(plane, side)
          next if Math.hypot(x - sx, y - sy) > PLANE_STRETCH_HIT_PX * @scale

          return { kind: :plane_stretch, id: plane[:id], side: side, hit: :stretch }
        end
      end
      nil
    end

    def hit_face_handle(x, y)
      BoxModel.face_handles(@bb).each do |key, point|
        sp = @view.screen_coords(point)
        next if Math.hypot(x - sp.x, y - sp.y) > HANDLE_HIT_PX * @scale

        return { kind: :handle, axis: key[:axis], side: key[:side] }
      end
      nil
    end

    def hit_plane_body(x, y)
      @planes.each do |plane|
        next unless plane[:usable]

        poly = BoxModel.display_plane_points(@bb, plane).map do |point|
          sp = @view.screen_coords(point)
          [sp.x, sp.y]
        end
        next unless point_near_polygon?(x, y, poly)

        return { kind: :plane, id: plane[:id], hit: :body }
      end
      nil
    end

    def point_near_polygon?(x, y, poly)
      return false if poly.length < 2

      poly.each_with_index do |pt, index|
        nxt = poly[(index + 1) % poly.length]
        return true if point_line_distance(x, y, pt, nxt) <= PLANE_EDGE_HIT_PX * @scale
      end
      false
    end

    def point_line_distance(x, y, a, b)
      ax, ay = a
      bx, by = b
      dx = bx - ax
      dy = by - ay
      len2 = dx * dx + dy * dy
      return Math.hypot(x - ax, y - ay) if len2 <= 0

      t = [0.0, [1.0, ((x - ax) * dx + (y - ay) * dy).to_f / len2].min].max
      px = ax + t * dx
      py = ay + t * dy
      Math.hypot(x - px, y - py)
    end

    def plane_stretch_grip_xy(plane, side)
      center = BoxModel.plane_center(@bb, plane)
      c = @view.screen_coords(center)
      vec = side_axis_vector(plane[:axis], side)
      p2 = @view.screen_coords(center.offset(vec, @view.pixels_to_model(80, center)))
      dx = p2.x - c.x
      dy = p2.y - c.y
      len = Math.hypot(dx, dy)
      return [c.x, c.y] if len <= 0

      offset = PLANE_STRETCH_OFFSET_PX * @scale
      [c.x + dx / len * offset, c.y + dy / len * offset]
    end

    def side_axis_vector(axis, side)
      sign = side == :minus ? -1 : 1
      case axis
      when :x then Geom::Vector3d.new(sign, 0, 0)
      when :y then Geom::Vector3d.new(0, sign, 0)
      else Geom::Vector3d.new(0, 0, sign)
      end
    end

    def ui_scale
      UI.scale_factor
    rescue
      1.0
    end
  end
end

