# encoding: UTF-8
#
# SmartScale::VectorFont -- single-stroke (centerline) numeric font drawn with
# draw2d GL_LINE_STRIP. Single stroke (not outline), renders on setups where
# view.draw_text does not work, and supports arbitrary rotation/scale.
#
# Glyph coords: x right, y DOWN, em box roughly [0,0.5] x [0.08,0.92].
#
module SmartScale
  module VectorFont
    CAP = 0.84          # digit height in em (0.08..0.92)
    CENTER_Y = 0.5

    module_function

    def ellipse(cx, cy, rx, ry, n = 18)
      (0..n).map do |i|
        t = 2 * Math::PI * i / n
        [cx + rx * Math.cos(t), cy + ry * Math.sin(t)]
      end
    end

    def build
      g = {}
      g['0'] = { w: 0.62, s: [ellipse(0.25, 0.5, 0.19, 0.42)] }
      g['1'] = { w: 0.46, s: [[[0.10, 0.28], [0.27, 0.10], [0.27, 0.92]], [[0.10, 0.92], [0.45, 0.92]]] }
      g['2'] = { w: 0.60, s: [[[0.07, 0.26], [0.13, 0.14], [0.26, 0.09], [0.38, 0.14], [0.43, 0.27],
                               [0.35, 0.42], [0.20, 0.58], [0.09, 0.76], [0.06, 0.92], [0.46, 0.92]]] }
      g['3'] = { w: 0.60, s: [[[0.07, 0.20], [0.20, 0.09], [0.34, 0.11], [0.42, 0.22], [0.36, 0.36],
                               [0.23, 0.42], [0.37, 0.48], [0.44, 0.63], [0.36, 0.83], [0.21, 0.92],
                               [0.09, 0.85], [0.06, 0.73]]] }
      g['4'] = { w: 0.62, s: [[[0.35, 0.10], [0.06, 0.65], [0.46, 0.65]], [[0.35, 0.10], [0.35, 0.92]]] }
      g['5'] = { w: 0.60, s: [[[0.42, 0.10], [0.12, 0.10], [0.10, 0.42], [0.24, 0.36], [0.38, 0.42],
                               [0.44, 0.62], [0.36, 0.84], [0.21, 0.92], [0.09, 0.86], [0.06, 0.74]]] }
      g['6'] = { w: 0.62, s: [[[0.41, 0.15], [0.29, 0.09], [0.17, 0.16], [0.09, 0.40], [0.07, 0.65],
                               [0.14, 0.85], [0.27, 0.92], [0.39, 0.85], [0.44, 0.67], [0.38, 0.51],
                               [0.24, 0.46], [0.12, 0.53], [0.08, 0.64]]] }
      g['7'] = { w: 0.58, s: [[[0.07, 0.10], [0.45, 0.10], [0.20, 0.92]]] }
      g['8'] = { w: 0.62, s: [ellipse(0.25, 0.28, 0.15, 0.19), ellipse(0.25, 0.68, 0.18, 0.24)] }
      g['9'] = { w: 0.62, s: [[[0.12, 0.85], [0.24, 0.91], [0.36, 0.84], [0.43, 0.60], [0.43, 0.35],
                               [0.35, 0.14], [0.22, 0.09], [0.10, 0.15], [0.06, 0.33], [0.13, 0.47],
                               [0.27, 0.50], [0.40, 0.45]]] }
      g['.'] = { w: 0.30, s: [[[0.15, 0.86], [0.27, 0.86], [0.27, 0.92], [0.15, 0.92], [0.15, 0.86]]] }
      g[','] = { w: 0.30, s: [[[0.27, 0.84], [0.27, 0.92], [0.16, 1.02]]] }
      g['-'] = { w: 0.50, s: [[[0.09, 0.50], [0.41, 0.50]]] }
      g[' '] = { w: 0.40, s: [] }
      g['m'] = { w: 0.90, s: [[[0.06, 0.40], [0.06, 0.92]], [[0.06, 0.48], [0.16, 0.40], [0.26, 0.48], [0.26, 0.92]],
                              [[0.26, 0.48], [0.36, 0.40], [0.46, 0.48], [0.46, 0.92]]] }
      g['c'] = { w: 0.55, s: [[[0.42, 0.50], [0.28, 0.40], [0.14, 0.46], [0.08, 0.66], [0.14, 0.86],
                               [0.28, 0.92], [0.42, 0.84]]] }
      g
    end

    GLYPHS = build.freeze

    def advance_em(ch)
      gl = GLYPHS[ch]
      gl ? gl[:w] : 0.5
    end

    # Total width (px) of `str` at digit height `h` px.
    def measure(str, h)
      f = h / CAP
      str.each_char.sum { |ch| advance_em(ch) * f }
    end

    # Draw `str` centered at screen (cx, cy), digit height `h` px, rotated
    # `angle` rad, in `color`, stroke width `lw`.
    def draw(view, str, cx, cy, h, angle, color, lw = 2)
      f = h / CAP
      ca = Math.cos(angle)
      sa = Math.sin(angle)
      total = measure(str, h)
      view.line_width = lw
      view.drawing_color = color

      penx = -total / 2.0
      str.each_char do |ch|
        gl = GLYPHS[ch]
        if gl
          gl[:s].each do |poly|
            pts = poly.map do |gx, gy|
              lx = penx + gx * f
              ly = (gy - CENTER_Y) * f
              [cx + lx * ca - ly * sa, cy + lx * sa + ly * ca, 0]
            end
            view.draw2d(GL_LINE_STRIP, pts)
          end
          penx += gl[:w] * f
        else
          penx += 0.5 * f
        end
      end
    end
  end
end
