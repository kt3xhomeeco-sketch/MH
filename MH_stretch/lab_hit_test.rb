# encoding: UTF-8

module MH::Stretch
  class HitTest
    HANDLE_HIT_PX = 14
    AXIS_HIT_PX = 9
    PLANE_GRIP_HIT_PX = 12
    PLANE_SIDE_HIT_PX = 12
    PLANE_SIDE_OFFSET_PX = 28
    PLANE_EDGE_HIT_PX = 8

    def initialize(view, bb, planes, show_plane_grips = true)
      @view = view
      @bb = bb
      @planes = planes
      @show_plane_grips = show_plane_grips
      @ui_factor = ui_scale
    end

    def hit(x, y)
      return nil if BoxModel.empty_bounds?(@bb)

      (@show_plane_grips && hit_plane_side_grip(x, y)) ||
        hit_plane_grip(x, y) ||
        hit_face_handle(x, y) ||
        hit_axis_line(x, y) ||
        hit_plane_body(x, y)
    end

    def hit_handle(x, y)
      return nil if BoxModel.empty_bounds?(@bb)

      hit_face_handle(x, y) || hit_axis_line(x, y)
    end

    private

    def hit_plane_grip(x, y)
      @planes.each do |plane|
        next unless plane[:usable]
        next if plane[:hidden]

        center = BoxModel.plane_center(@bb, plane)
        sp = @view.screen_coords(center)
        next if Math.hypot(x - sp.x, y - sp.y) > PLANE_GRIP_HIT_PX * @ui_factor

        return { kind: :plane, id: plane[:id], hit: :grip }
      end
      nil
    end

    def hit_plane_side_grip(x, y)
      @planes.each do |plane|
        next unless plane[:usable]
        next if plane[:hidden]

        [:minus, :plus].each do |side|
          sx, sy = plane_side_grip_xy(plane, side)
          next if Math.hypot(x - sx, y - sy) > PLANE_SIDE_HIT_PX * @ui_factor

          return { kind: :plane_grip, id: plane[:id], side: side, hit: :grip }
        end
      end
      nil
    end

    def hit_face_handle(x, y)
      best_hit = nil
      best_distance = HANDLE_HIT_PX * @ui_factor
      BoxModel.face_handles(@bb).each do |key, point|
        sp = @view.screen_coords(point)
        distance = Math.hypot(x - sp.x, y - sp.y)
        next if distance > best_distance

        best_distance = distance
        best_hit = { kind: :handle, axis: key[:axis], side: key[:side] }
      end
      best_hit
    end

    # A visible axis is also a grip.  Previously only its two endpoint cubes
    # were clickable, which made selecting a thin or distant object needlessly
    # precise.  Preserve the endpoint hit priority above so clicking a cube
    # still selects that exact side; a line hit selects the nearer side.
    def hit_axis_line(x, y)
      handles = BoxModel.face_handles(@bb)
      best_hit = nil
      best_distance = AXIS_HIT_PX * @ui_factor
      BoxModel::AXES.each do |axis|
        minus = handles.find { |key, _| key[:axis] == axis && key[:side] == :minus }&.last
        plus = handles.find { |key, _| key[:axis] == axis && key[:side] == :plus }&.last
        next unless minus && plus

        start = @view.screen_coords(minus)
        finish = @view.screen_coords(plus)
        distance, t = point_segment_distance(x, y, start.x, start.y, finish.x, finish.y)
        next if distance > best_distance

        best_distance = distance
        best_hit = { kind: :handle, axis: axis, side: t < 0.5 ? :minus : :plus, hit: :axis }
      end
      best_hit
    end

    def hit_plane_body(x, y)
      @planes.each do |plane|
        next unless plane[:usable]
        next if plane[:hidden]

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
        return true if point_line_distance(x, y, pt, nxt) <= PLANE_EDGE_HIT_PX * @ui_factor
      end
      point_inside_polygon?(x, y, poly)
    end

    # The plane used to be selectable only along its border. Treat its whole
    # projected face as a hit area, so dragging anywhere on the face moves it.
    def point_inside_polygon?(x, y, poly)
      inside = false
      previous = poly.last
      poly.each do |current|
        xi, yi = current
        xj, yj = previous
        crosses_scanline = (yi > y) != (yj > y)
        if crosses_scanline
          crossing_x = (xj - xi) * (y - yi).to_f / (yj - yi) + xi
          inside = !inside if x < crossing_x
        end
        previous = current
      end
      inside
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

    def point_segment_distance(x, y, ax, ay, bx, by)
      dx = bx - ax
      dy = by - ay
      len2 = dx * dx + dy * dy
      return [Math.hypot(x - ax, y - ay), 0.0] if len2 <= 0

      t = [0.0, [1.0, ((x - ax) * dx + (y - ay) * dy).to_f / len2].min].max
      px = ax + t * dx
      py = ay + t * dy
      [Math.hypot(x - px, y - py), t]
    end

    def plane_side_grip_xy(plane, side)
      center = BoxModel.plane_center(@bb, plane)
      c = @view.screen_coords(center)
      vec = side_axis_vector(plane[:axis], side)
      p2 = @view.screen_coords(center.offset(vec, @view.pixels_to_model(80, center)))
      dx = p2.x - c.x
      dy = p2.y - c.y
      len = Math.hypot(dx, dy)
      return [c.x, c.y] if len <= 0

      offset = PLANE_SIDE_OFFSET_PX * @ui_factor
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




