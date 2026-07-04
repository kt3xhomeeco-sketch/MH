# encoding: UTF-8

module SmartScaleLab
  class DimensionRenderer
    DIM_OFFSET_PX = 45
    TEXT_OFFSET_PX = 11
    TEXT_HEIGHT_PX = 10
    FRONT_VIEW_TOLERANCE = 0.95
    TOP_VIEW_TOLERANCE = 0.95

    def initialize(view, bb, preview = nil, hits = nil, hover_axis = nil)
      @view = view
      @bb = bb
      @preview = preview
      @hits = hits
      @hover_axis = hover_axis
      @scale = ui_scale
    end

    def draw
      @hits.clear if @hits
      dimension_data.each do |data|
        color = BoxModel.color(data[:axis])
        p1 = screen_point(data[:p1])
        p2 = screen_point(data[:p2])
        a1 = screen_point(data[:a1])
        a2 = screen_point(data[:a2])

        @view.line_stipple = data[:hidden] ? '_' : ''
        @view.line_width = 1 * @scale
        @view.drawing_color = color
        @view.draw2d(GL_LINES, [p1, a1, p2, a2])
        @view.line_width = (data[:hidden] ? 1 : 2) * @scale
        @view.draw2d(GL_LINES, [a1, a2])
        @view.line_stipple = ''

        draw_tick(a1, a2, color)
        draw_tick(a2, a1, color)
        draw_number(data, color)
      end
    end

    private

    def dimension_data
      center = @bb.center
      eye = @view.camera.eye

      BoxModel::AXES.filter_map do |axis|
        length = preview_length(axis)
        next if length <= 0

        edges = parallel_edges(axis)
        index, hidden = choose_edge(edges, eye, axis)
        p1, p2 = edges[index][:points]
        middle = Geom.linear_combination(0.5, p1, 0.5, p2)
        outward = outward_direction(p1, p2, middle, center)
        next unless outward

        if axis == :x && front_view?
          outward = Geom::Vector3d.new(0, 0, 1)
        elsif axis == :y && top_view?
          outward = Geom::Vector3d.new(1, 0, 0)
        elsif axis != :z
          outward = Geom::Vector3d.new(outward.x, outward.y, 0)
          next if outward.length == 0
          outward.normalize!
        end

        offset = @view.pixels_to_model(DIM_OFFSET_PX * @scale, middle)
        a1 = p1.offset(outward, offset)
        a2 = p2.offset(outward, offset)
        line_middle = Geom.linear_combination(0.5, a1, 0.5, a2)
        {
          axis: axis,
          length: length,
          hidden: hidden,
          p1: p1,
          p2: p2,
          a1: a1,
          a2: a2,
          anchor: line_middle.offset(
            outward,
            @view.pixels_to_model(TEXT_OFFSET_PX * @scale, middle)
          )
        }
      end
    end

    def preview_length(axis)
      length = BoxModel.axis_length(@bb, axis)
      return length unless @preview && @preview[:axis] == axis

      amount = @preview[:amount].to_f
      value = @preview[:side] == :minus ? length - amount : length + amount
      [value, BoxModel::MIN_LEN].max
    end

    def parallel_edges(axis)
      c = BoxModel.corners(@bb)
      vx = Geom::Vector3d.new(1, 0, 0)
      vy = Geom::Vector3d.new(0, 1, 0)
      vz = Geom::Vector3d.new(0, 0, 1)

      case axis
      when :x
        [
          { points: [c[0], c[1]], faces: [vy.reverse, vz.reverse] },
          { points: [c[2], c[3]], faces: [vy, vz.reverse] },
          { points: [c[4], c[5]], faces: [vy.reverse, vz] },
          { points: [c[6], c[7]], faces: [vy, vz] }
        ]
      when :y
        [
          { points: [c[0], c[2]], faces: [vx.reverse, vz.reverse] },
          { points: [c[1], c[3]], faces: [vx, vz.reverse] },
          { points: [c[4], c[6]], faces: [vx.reverse, vz] },
          { points: [c[5], c[7]], faces: [vx, vz] }
        ]
      else
        [
          { points: [c[0], c[4]], faces: [vx.reverse, vy.reverse] },
          { points: [c[1], c[5]], faces: [vx, vy.reverse] },
          { points: [c[2], c[6]], faces: [vx.reverse, vy] },
          { points: [c[3], c[7]], faces: [vx, vy] }
        ]
      end
    end

    def choose_edge(edges, eye, axis)
      choices = edges.each_with_index.map do |edge, index|
        middle = Geom.linear_combination(0.5, edge[:points][0], 0.5, edge[:points][1])
        screen = @view.screen_coords(middle)
        front = edge[:faces].any? { |normal| (eye - middle).dot(normal) > 0 }
        [index, screen.x, screen.y, front]
      end
      visible = choices.select { |choice| choice[3] }
      visible = choices if visible.empty?
      chosen =
        if axis == :z
          visible.min_by { |choice| choice[1] }
        else
          visible.max_by { |choice| choice[2] }
        end
      [chosen[0], !chosen[3]]
    end

    def outward_direction(p1, p2, middle, center)
      edge = p2 - p1
      return nil if edge.length == 0

      edge.normalize!
      from_center = middle - center
      along = Geom::Vector3d.new(
        edge.x * from_center.dot(edge),
        edge.y * from_center.dot(edge),
        edge.z * from_center.dot(edge)
      )
      outward = from_center - along
      return nil if outward.length == 0

      outward.normalize!
      outward
    end

    def draw_tick(a, b, color)
      dx = b[0] - a[0]
      dy = b[1] - a[1]
      length = Math.hypot(dx, dy)
      return if length < 1

      ux = dx / length
      uy = dy / length
      px = -uy
      py = ux
      size = 3 * @scale
      d1 = [(ux + px) * size, (uy + py) * size]
      d2 = [(ux - px) * size, (uy - py) * size]

      @view.line_width = 2 * @scale
      @view.drawing_color = color
      @view.draw2d(GL_LINES, [
        [a[0] - d1[0], a[1] - d1[1], 0],
        [a[0] + d1[0], a[1] + d1[1], 0],
        [a[0] - d2[0], a[1] - d2[1], 0],
        [a[0] + d2[0], a[1] + d2[1], 0]
      ])
    end

    def draw_number(data, color)
      text = dimension_text(data[:length])
      height = TEXT_HEIGHT_PX * @scale
      anchor = @view.screen_coords(data[:anchor])
      a1 = @view.screen_coords(data[:a1])
      a2 = @view.screen_coords(data[:a2])
      angle = Math.atan2(a2.y - a1.y, a2.x - a1.x)
      angle += Math::PI if angle > Math::PI / 2 || angle < -Math::PI / 2

      width = SmartScale::VectorFont.measure(text, height) + 6 * @scale
      plate_height = height + 4 * @scale
      hovered = data[:axis] == @hover_axis
      @view.drawing_color = Sketchup::Color.new(255, 255, 255, hovered ? 255 : 235)
      @view.draw2d(GL_POLYGON, rectangle(anchor.x, anchor.y, width, plate_height, angle))
      SmartScale::VectorFont.draw(
        @view,
        text,
        anchor.x,
        anchor.y,
        height,
        angle,
        color,
        (hovered ? 2 : 1.5) * @scale
      )

      cos = Math.cos(angle).abs
      sin = Math.sin(angle).abs
      hit_width = width * cos + plate_height * sin
      hit_height = width * sin + plate_height * cos
      @hits[data[:axis]] = [
        anchor.x - hit_width / 2.0,
        anchor.y - hit_height / 2.0,
        hit_width,
        hit_height
      ] if @hits
    end

    def rectangle(cx, cy, width, height, angle)
      cos = Math.cos(angle)
      sin = Math.sin(angle)
      half_width = width / 2.0
      half_height = height / 2.0
      [
        [-half_width, -half_height],
        [half_width, -half_height],
        [half_width, half_height],
        [-half_width, half_height]
      ].map do |x, y|
        [cx + x * cos - y * sin, cy + x * sin + y * cos, 0]
      end
    end

    def dimension_text(length)
      text = length.to_mm.round(1).to_s
      text.sub(/\.0$/, '')
    end

    def screen_point(point)
      screen = @view.screen_coords(point)
      [screen.x, screen.y, 0]
    end

    def front_view?
      direction = @view.camera.direction
      direction = direction.clone
      direction.normalize!
      direction.dot(Geom::Vector3d.new(0, 1, 0)).abs >= FRONT_VIEW_TOLERANCE
    rescue
      false
    end

    def top_view?
      direction = @view.camera.direction
      direction = direction.clone
      direction.normalize!
      direction.dot(Geom::Vector3d.new(0, 0, 1)).abs >= TOP_VIEW_TOLERANCE
    rescue
      false
    end

    def ui_scale
      UI.scale_factor
    rescue
      1.0
    end
  end
end
