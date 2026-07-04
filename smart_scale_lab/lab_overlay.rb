# encoding: UTF-8

module SmartScaleLab
  class Overlay
    GRIP_PX = 7
    STRETCH_OFFSET_PX = 28
    GRID_SIZE_PX = 40
    GRID_MAX_DIVISIONS = 24

    def initialize(
      view,
      bb,
      state,
      planes,
      preview_segments = [],
      creation_preview = nil,
      dimension_preview = nil,
      show_plane_stretch_grips = true,
      dimension_hits = nil,
      hover_dimension_axis = nil
    )
      @view = view
      @bb = bb
      @state = state
      @planes = planes
      @preview_segments = preview_segments || []
      @creation_preview = creation_preview
      @dimension_preview = dimension_preview
      @show_plane_stretch_grips = show_plane_stretch_grips
      @dimension_hits = dimension_hits
      @hover_dimension_axis = hover_dimension_axis
      @scale = ui_scale
    end

    def draw
      return if BoxModel.empty_bounds?(@bb)

      draw_box
      draw_planes
      draw_creation_preview
      draw_preview
      DimensionRenderer.new(
        @view,
        @bb,
        @dimension_preview,
        @dimension_hits,
        @hover_dimension_axis
      ).draw
      draw_axis_handles
    end

    private

    def draw_box
      c = BoxModel.corners(@bb)
      @view.line_stipple = ''
      @view.line_width = 1 * @scale
      @view.drawing_color = Sketchup::Color.new(95, 95, 95)
      @view.draw(GL_LINE_LOOP, [c[0], c[1], c[3], c[2]])
      @view.draw(GL_LINE_LOOP, [c[4], c[5], c[7], c[6]])
      [[0, 4], [1, 5], [3, 7], [2, 6]].each { |a, b| @view.draw(GL_LINES, [c[a], c[b]]) }
    end

    def draw_planes
      @planes.each do |plane|
        next unless plane[:usable]

        move_hot =
          @state.hover[:kind] == :plane &&
          @state.hover[:id] == plane[:id] &&
          @state.hover[:hit] == :grip
        border_color = Sketchup::Color.new(220, 45, 45)
        content_color =
          if move_hot
            Sketchup::Color.new(255, 200, 20)
          else
            border_color
          end
        pts = BoxModel.display_plane_points(@bb, plane)

        alpha = move_hot ? 82 : 54
        @view.drawing_color = Sketchup::Color.new(
          content_color.red,
          content_color.green,
          content_color.blue,
          alpha
        )
        @view.draw(GL_QUADS, pts)

        pts2 = pts.map { |pt| screen_point(pt) }
        @view.line_stipple = ''
        @view.line_width = 2 * @scale
        @view.drawing_color = Sketchup::Color.new(
          border_color.red,
          border_color.green,
          border_color.blue,
          235
        )
        @view.draw2d(GL_LINE_LOOP, pts2)
        draw_plane_grid(plane, pts, content_color)

        center = screen_point(BoxModel.plane_center(@bb, plane))
        draw_square(center[0], center[1], border_color, move_hot)
        next unless @show_plane_stretch_grips

        [:minus, :plus].each do |side|
          sx, sy = plane_stretch_grip_xy(plane, side)
          stretch_hot =
            @state.hover[:kind] == :plane_stretch &&
            @state.hover[:id] == plane[:id] &&
            @state.hover[:side] == side
          draw_diamond(sx, sy, border_color, stretch_hot, side)
        end
      end
    end

    def draw_creation_preview
      return unless @creation_preview && @creation_preview[:usable]

      color = Sketchup::Color.new(70, 165, 255)
      pts = BoxModel.display_plane_points(@bb, @creation_preview)
      @view.drawing_color = Sketchup::Color.new(color.red, color.green, color.blue, 45)
      @view.draw(GL_QUADS, pts)

      @view.line_stipple = '-'
      @view.line_width = 2 * @scale
      @view.drawing_color = Sketchup::Color.new(color.red, color.green, color.blue, 255)
      @view.draw2d(GL_LINE_LOOP, pts.map { |pt| screen_point(pt) })
      @view.line_stipple = ''
    end

    def draw_plane_grid(plane, pts, color)
      center = BoxModel.plane_center(@bb, plane)
      grid_size = @view.pixels_to_model(GRID_SIZE_PX * @scale, center)
      return unless grid_size && grid_size > 0

      count_u = grid_divisions(pts[0].distance(pts[1]), grid_size)
      count_v = grid_divisions(pts[1].distance(pts[2]), grid_size)
      segments = []

      (1...count_u).each do |index|
        t = index.to_f / count_u
        segments << interpolate(pts[0], pts[1], t)
        segments << interpolate(pts[3], pts[2], t)
      end
      (1...count_v).each do |index|
        t = index.to_f / count_v
        segments << interpolate(pts[0], pts[3], t)
        segments << interpolate(pts[1], pts[2], t)
      end
      return if segments.empty?

      @view.line_stipple = '-'
      @view.line_width = 2 * @scale
      @view.drawing_color = Sketchup::Color.new(color.red, color.green, color.blue, 235)
      @view.draw2d(GL_LINES, segments.map { |point| screen_point(point) })
      @view.line_stipple = ''
    end

    def grid_divisions(length, grid_size)
      count = ((length * 0.5) / grid_size).ceil
      [[count, 1].max, GRID_MAX_DIVISIONS].min
    end

    def interpolate(a, b, factor)
      Geom.linear_combination(1.0 - factor, a, factor, b)
    end

    def draw_axis_handles
      handles = BoxModel.face_handles(@bb)
      BoxModel::AXES.each do |axis|
        minus = handles.find { |key, _| key[:axis] == axis && key[:side] == :minus }&.last
        plus = handles.find { |key, _| key[:axis] == axis && key[:side] == :plus }&.last
        next unless minus && plus

        color = BoxModel.color(axis)
        axis_hot =
          (@state.hover[:kind] == :handle && @state.hover[:axis] == axis) ||
          (@state.active[:kind] == :handle && @state.active[:axis] == axis)

        @view.line_stipple = '-'
        @view.line_width = (axis_hot ? 2 : 1) * @scale
        @view.drawing_color = Sketchup::Color.new(
          color.red,
          color.green,
          color.blue,
          axis_hot ? 255 : 190
        )
        @view.draw2d(GL_LINES, [screen_point(minus), screen_point(plus)])
        @view.line_stipple = ''

        draw_axis_grip(axis, :minus, minus)
        draw_axis_grip(axis, :plus, plus)
      end
    end

    def draw_axis_grip(axis, side, point)
      hot =
        (@state.hover[:kind] == :handle &&
         @state.hover[:axis] == axis &&
         @state.hover[:side] == side) ||
        (@state.active[:kind] == :handle &&
         @state.active[:axis] == axis &&
         @state.active[:side] == side)
      draw_fredo_grip_cube(point, hot)
    end

    def draw_fredo_grip_cube(center, hot)
      half = @view.pixels_to_model((hot ? 5.2 : 3.9) * @scale, center)
      x = Geom::Vector3d.new(half, 0, 0)
      y = Geom::Vector3d.new(0, half, 0)
      z = Geom::Vector3d.new(0, 0, half)
      corners = [
        center.offset(x.reverse).offset(y.reverse).offset(z.reverse),
        center.offset(x).offset(y.reverse).offset(z.reverse),
        center.offset(x.reverse).offset(y).offset(z.reverse),
        center.offset(x).offset(y).offset(z.reverse),
        center.offset(x.reverse).offset(y.reverse).offset(z),
        center.offset(x).offset(y.reverse).offset(z),
        center.offset(x.reverse).offset(y).offset(z),
        center.offset(x).offset(y).offset(z)
      ].map { |point| screen_point(point) }

      faces = [
        [0, 1, 3, 2],
        [4, 5, 7, 6],
        [0, 1, 5, 4],
        [2, 3, 7, 6],
        [0, 2, 6, 4],
        [1, 3, 7, 5]
      ]
      @view.drawing_color =
        if hot
          Sketchup::Color.new(255, 255, 255, 245)
        else
          Sketchup::Color.new(20, 20, 20, 235)
        end
      faces.each { |indices| @view.draw2d(GL_QUADS, indices.map { |index| corners[index] }) }

      @view.line_width = (hot ? 2 : 1) * @scale
      @view.drawing_color =
        if hot
          Sketchup::Color.new(20, 20, 20)
        else
          Sketchup::Color.new(130, 235, 130)
        end
      [
        [0, 1], [1, 3], [3, 2], [2, 0],
        [4, 5], [5, 7], [7, 6], [6, 4],
        [0, 4], [1, 5], [2, 6], [3, 7]
      ].each do |a, b|
        @view.draw2d(GL_LINES, [corners[a], corners[b]])
      end
    end

    def draw_preview
      return if @preview_segments.empty?

      @view.line_stipple = ''
      @view.line_width = 2 * @scale
      @view.drawing_color = Sketchup::Color.new(30, 120, 255)
      @preview_segments.each { |a, b| @view.draw(GL_LINES, [a, b]) }
    end

    def draw_square(x, y, color, hot)
      s = (hot ? GRIP_PX + 2 : GRIP_PX) * @scale
      pts = [[x - s, y - s, 0], [x + s, y - s, 0], [x + s, y + s, 0], [x - s, y + s, 0]]
      @view.drawing_color = hot ? Sketchup::Color.new(255, 255, 255) : Sketchup::Color.new(20, 20, 20)
      @view.draw2d(GL_POLYGON, pts)
      @view.line_width = hot ? 2 * @scale : 1 * @scale
      @view.drawing_color = hot ? Sketchup::Color.new(230, 45, 45) : color
      @view.draw2d(GL_LINE_LOOP, pts)
    end

    def draw_diamond(x, y, color, hot, side)
      s = (hot ? GRIP_PX + 3 : GRIP_PX + 1) * @scale
      pts = [[x, y - s, 0], [x + s, y, 0], [x, y + s, 0], [x - s, y, 0]]
      @view.drawing_color = hot ? Sketchup::Color.new(255, 255, 255) : Sketchup::Color.new(20, 20, 20)
      @view.draw2d(GL_POLYGON, pts)
      @view.line_width = hot ? 2 * @scale : 1 * @scale
      @view.drawing_color = hot ? Sketchup::Color.new(30, 120, 255) : color
      @view.draw2d(GL_LINE_LOOP, pts)
      label = side == :minus ? '-' : '+'
      @view.draw_text([x - 3 * @scale, y - 7 * @scale], label, size: (10 * @scale).to_i, bold: true, color: hot ? Sketchup::Color.new(30, 120, 255) : color)
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

      offset = STRETCH_OFFSET_PX * @scale
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

    def screen_point(point)
      sp = @view.screen_coords(point)
      [sp.x, sp.y, 0]
    end

    def ui_scale
      UI.scale_factor
    rescue
      1.0
    end
  end
end
