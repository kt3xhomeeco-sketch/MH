# encoding: UTF-8
#
# MH::OverlayEngine -- primitive helpers for SketchUp viewport overlays/tools.
# Giữ module này nhỏ: không biết nghiệp vụ app, chỉ vẽ 2D ổn định và tái dùng scratch points.

module MH
  module OverlayEngine
    @rect_points = [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]]

    module_function

    def rect(view, x, y, w, h, color, points = nil)
      pts = points || @rect_points
      pts[0][0] = x
      pts[0][1] = y
      pts[1][0] = x + w
      pts[1][1] = y
      pts[2][0] = x + w
      pts[2][1] = y + h
      pts[3][0] = x
      pts[3][1] = y + h
      view.drawing_color = color
      view.draw2d(GL_QUADS, pts)
    end

    def text(view, x, y, value, color: nil, size: nil, bold: nil, italic: nil, align: nil, font: nil, options: nil)
      opts = options.is_a?(Hash) ? options.dup : {}
      opts[:color] = color if color
      opts[:size] = size if size
      opts[:bold] = bold unless bold.nil?
      opts[:italic] = italic unless italic.nil?
      opts[:align] = align if align
      opts[:font] = font if font
      view.drawing_color = color if color
      opts.empty? ? view.draw_text([x, y, 0], value.to_s) : view.draw_text([x, y, 0], value.to_s, opts)
    end

    def rect_outline(view, x, y, w, h, color, points = nil)
      pts = points || [[x, y, 0], [x + w, y, 0], [x + w, y + h, 0], [x, y + h, 0]]
      if points
        pts[0][0] = x
        pts[0][1] = y
        pts[1][0] = x + w
        pts[1][1] = y
        pts[2][0] = x + w
        pts[2][1] = y + h
        pts[3][0] = x
        pts[3][1] = y + h
      end
      view.drawing_color = color
      view.draw2d(GL_LINE_LOOP, pts)
    end

    def polygon2d(view, points, color: nil)
      view.drawing_color = color if color
      view.draw2d(GL_POLYGON, points)
    end

    def line2d(view, points, color: nil, mode: GL_LINES, stipple: nil, width: nil)
      old_stipple = nil
      view.line_width = width if width
      if !stipple.nil? && view.respond_to?(:line_stipple)
        old_stipple = view.line_stipple rescue nil
        view.line_stipple = stipple rescue nil
      end
      view.drawing_color = color if color
      view.draw2d(mode, points)
    ensure
      view.line_stipple = old_stipple if !stipple.nil? && !old_stipple.nil? && view.respond_to?(:line_stipple)
    end

    def panel_origin(view, width, height, anchor: :bottom_right, margin_x: 0, margin_y: 0)
      vpw = view.vpwidth.to_i
      vph = view.vpheight.to_i
      case anchor
      when :top_right
        [[vpw - width - margin_x, margin_x].max, [margin_y, 0].max]
      when :bottom_left
        [[margin_x, 0].max, [vph - height - margin_y, 0].max]
      when :top_left
        [[margin_x, 0].max, [margin_y, 0].max]
      else
        [[vpw - width - margin_x, 0].max, [vph - height - margin_y, 0].max]
      end
    end
  end
end
