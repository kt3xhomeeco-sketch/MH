# encoding: utf-8

module MH_PK_Addon
  # Font ky thuat 1 net de tao geometry Edge that trong model.
  # Toa do glyph nam trong em-box: x 0..width, y 0..1 (tren xuong duoi).
  module SingleLineFont
    SPACING = 0.20

    GLYPHS = {
      'A' => [1.0, [[[0, 1], [0.5, 0], [1, 1]], [[0.2, 0.62], [0.8, 0.62]]]],
      'B' => [0.9, [[[0, 1], [0, 0], [0.55, 0], [0.85, 0.18], [0.55, 0.5], [0, 0.5]],
                    [[0.55, 0.5], [0.9, 0.7], [0.55, 1], [0, 1]]]],
      'C' => [0.9, [[[0.9, 0.15], [0.7, 0], [0.2, 0], [0, 0.2], [0, 0.8], [0.2, 1], [0.7, 1], [0.9, 0.85]]]],
      'D' => [0.9, [[[0, 1], [0, 0], [0.5, 0], [0.9, 0.25], [0.9, 0.75], [0.5, 1], [0, 1]]]],
      'E' => [0.8, [[[0.8, 0], [0, 0], [0, 1], [0.8, 1]], [[0, 0.5], [0.65, 0.5]]]],
      'F' => [0.8, [[[0, 1], [0, 0], [0.8, 0]], [[0, 0.5], [0.65, 0.5]]]],
      'G' => [1.0, [[[0.9, 0.15], [0.7, 0], [0.2, 0], [0, 0.2], [0, 0.8], [0.2, 1], [0.75, 1], [0.95, 0.8], [0.95, 0.55], [0.55, 0.55]]]],
      'H' => [0.9, [[[0, 0], [0, 1]], [[0.9, 0], [0.9, 1]], [[0, 0.5], [0.9, 0.5]]]],
      'I' => [0.6, [[[0, 0], [0.6, 0]], [[0.3, 0], [0.3, 1]], [[0, 1], [0.6, 1]]]],
      'J' => [0.8, [[[0.1, 0], [0.8, 0], [0.8, 0.78], [0.62, 1], [0.2, 1], [0, 0.82]]]],
      'K' => [0.9, [[[0, 0], [0, 1]], [[0.9, 0], [0, 0.58]], [[0.35, 0.38], [0.9, 1]]]],
      'L' => [0.8, [[[0, 0], [0, 1], [0.8, 1]]]],
      'M' => [1.1, [[[0, 1], [0, 0], [0.55, 0.58], [1.1, 0], [1.1, 1]]]],
      'N' => [1.0, [[[0, 1], [0, 0], [1, 1], [1, 0]]]],
      'O' => [1.0, [[[0.25, 0], [0.75, 0], [1, 0.25], [1, 0.75], [0.75, 1], [0.25, 1], [0, 0.75], [0, 0.25], [0.25, 0]]]],
      'P' => [0.9, [[[0, 1], [0, 0], [0.55, 0], [0.9, 0.2], [0.55, 0.5], [0, 0.5]]]],
      'Q' => [1.0, [[[0.25, 0], [0.75, 0], [1, 0.25], [1, 0.75], [0.75, 1], [0.25, 1], [0, 0.75], [0, 0.25], [0.25, 0]], [[0.6, 0.65], [1.05, 1.08]]]],
      'R' => [0.95, [[[0, 1], [0, 0], [0.55, 0], [0.9, 0.2], [0.55, 0.5], [0, 0.5]], [[0.45, 0.5], [0.95, 1]]]],
      'S' => [0.9, [[[0.9, 0.15], [0.7, 0], [0.2, 0], [0, 0.2], [0.2, 0.48], [0.7, 0.52], [0.9, 0.8], [0.7, 1], [0.2, 1], [0, 0.85]]]],
      'T' => [0.9, [[[0, 0], [0.9, 0]], [[0.45, 0], [0.45, 1]]]],
      'U' => [0.9, [[[0, 0], [0, 0.78], [0.2, 1], [0.7, 1], [0.9, 0.78], [0.9, 0]]]],
      'V' => [1.0, [[[0, 0], [0.5, 1], [1, 0]]]],
      'W' => [1.2, [[[0, 0], [0.25, 1], [0.6, 0.5], [0.95, 1], [1.2, 0]]]],
      'X' => [1.0, [[[0, 0], [1, 1]], [[1, 0], [0, 1]]]],
      'Y' => [1.0, [[[0, 0], [0.5, 0.5], [1, 0]], [[0.5, 0.5], [0.5, 1]]]],
      'Z' => [0.9, [[[0, 0], [0.9, 0], [0, 1], [0.9, 1]]]],
      '0' => [0.9, [[[0.2, 0], [0.7, 0], [0.9, 0.2], [0.9, 0.8], [0.7, 1], [0.2, 1], [0, 0.8], [0, 0.2], [0.2, 0]], [[0.1, 0.85], [0.8, 0.15]]]],
      '1' => [0.6, [[[0.05, 0.25], [0.3, 0], [0.3, 1]], [[0.05, 1], [0.6, 1]]]],
      '2' => [0.9, [[[0, 0.2], [0.2, 0], [0.7, 0], [0.9, 0.2], [0.9, 0.4], [0, 1], [0.9, 1]]]],
      '3' => [0.9, [[[0, 0.15], [0.2, 0], [0.7, 0], [0.9, 0.2], [0.65, 0.5], [0.9, 0.8], [0.7, 1], [0.2, 1], [0, 0.85]]]],
      '4' => [0.9, [[[0.7, 1], [0.7, 0], [0, 0.7], [0.9, 0.7]]]],
      '5' => [0.9, [[[0.9, 0], [0.1, 0], [0, 0.48], [0.65, 0.48], [0.9, 0.7], [0.75, 1], [0.2, 1], [0, 0.85]]]],
      '6' => [0.9, [[[0.85, 0.12], [0.65, 0], [0.25, 0], [0, 0.35], [0, 0.8], [0.2, 1], [0.7, 1], [0.9, 0.78], [0.7, 0.5], [0.1, 0.5]]]],
      '7' => [0.9, [[[0, 0], [0.9, 0], [0.25, 1]]]],
      '8' => [0.9, [[[0.2, 0], [0.7, 0], [0.9, 0.2], [0.7, 0.5], [0.2, 0.5], [0, 0.2], [0.2, 0]], [[0.2, 0.5], [0, 0.8], [0.2, 1], [0.7, 1], [0.9, 0.8], [0.7, 0.5]]]],
      '9' => [0.9, [[[0.8, 0.5], [0.2, 0.5], [0, 0.25], [0.2, 0], [0.7, 0], [0.9, 0.2], [0.9, 0.65], [0.65, 1], [0.2, 1], [0.05, 0.88]]]],
      ' ' => [0.5, []], '-' => [0.6, [[[0, 0.5], [0.6, 0.5]]]],
      '_' => [0.8, [[[0, 1], [0.8, 1]]]], '.' => [0.15, [[[0.05, 0.95], [0.1, 1]]]],
      ',' => [0.2, [[[0.15, 0.9], [0.05, 1.15]]]], ':' => [0.15, [[[0.08, 0.3], [0.1, 0.32]], [[0.08, 0.78], [0.1, 0.8]]]],
      '/' => [0.7, [[[0, 1], [0.7, 0]]]], '\\' => [0.7, [[[0, 0], [0.7, 1]]]],
      '(' => [0.35, [[[0.35, 0], [0.1, 0.2], [0, 0.5], [0.1, 0.8], [0.35, 1]]]],
      ')' => [0.35, [[[0, 0], [0.25, 0.2], [0.35, 0.5], [0.25, 0.8], [0, 1]]]],
      '+' => [0.7, [[[0, 0.5], [0.7, 0.5]], [[0.35, 0.15], [0.35, 0.85]]]],
      '?' => [0.8, [[[0, 0.2], [0.2, 0], [0.6, 0], [0.8, 0.2], [0.8, 0.35], [0.4, 0.6], [0.4, 0.72]], [[0.4, 0.95], [0.4, 1]]]]
    }.freeze

    module_function

    def normalize(text)
      value = text.to_s
      value = MH::Text.fix_mojibake(value) if defined?(MH::Text) && MH::Text.respond_to?(:fix_mojibake)
      value.upcase.gsub(/\s+/, ' ').strip
    rescue
      text.to_s.upcase.strip
    end

    # Dau Unicode sau khi NFD. Moi dau la mot stroke centerline, khong phai outline.
    DIACRITICS = {
      "\u0301" => [[[0.38, -0.10], [0.66, -0.34]]], # sac
      "\u0300" => [[[0.62, -0.10], [0.34, -0.34]]], # huyen
      "\u0309" => [[[0.35, -0.31], [0.52, -0.38], [0.65, -0.29], [0.50, -0.14]]], # hoi
      "\u0303" => [[[0.18, -0.20], [0.34, -0.30], [0.50, -0.20], [0.66, -0.30], [0.82, -0.20]]], # nga
      "\u0323" => [[[0.46, 1.18], [0.54, 1.18]]], # nang
      "\u0302" => [[[0.18, -0.10], [0.50, -0.32], [0.82, -0.10]]], # mu
      "\u0306" => [[[0.18, -0.28], [0.28, -0.12], [0.50, -0.06], [0.72, -0.12], [0.82, -0.28]]], # trang
      "\u031B" => [[[0.74, 0.06], [0.98, -0.02], [1.04, -0.24]]] # rau
    }.freeze
    STRUCTURAL_MARKS = ["\u0302", "\u0306", "\u031B"].freeze
    TONE_MARKS = ["\u0301", "\u0300", "\u0309", "\u0303"].freeze

    def clusters(text)
      value = normalize(text)
      value = 'PHU KIEN' if value.empty?
      decomposed = value.unicode_normalize(:nfd)
      result = []
      decomposed.each_char do |ch|
        if ch.match?(/\p{Mn}/) && !result.empty?
          result[-1][1] << ch
        else
          result << [ch, []]
        end
      end
      result
    rescue
      normalize(text).each_char.map { |ch| [ch, []] }
    end

    def layout(text)
      runs = clusters(text)
      pen_x = 0.0
      all_strokes = []

      runs.each_with_index do |(base, marks), index|
        is_d_stroke = base == 'Đ'
        glyph = GLYPHS[is_d_stroke ? 'D' : base] || GLYPHS['?']
        width, strokes = glyph
        strokes.each do |stroke|
          all_strokes << stroke.map { |x, y| [pen_x + x, y] }
        end
        if is_d_stroke
          all_strokes << [[pen_x - 0.10, 0.48], [pen_x + 0.38, 0.48]]
        end

        structural = marks.any? { |mark| STRUCTURAL_MARKS.include?(mark) }
        marks.each do |mark|
          templates = DIACRITICS[mark]
          next unless templates

          lift = structural && TONE_MARKS.include?(mark) ? -0.30 : 0.0
          templates.each do |stroke|
            all_strokes << stroke.map { |x, y| [pen_x + x * width, y + lift] }
          end
        end
        pen_x += width
        pen_x += SPACING unless index == runs.length - 1
      end

      xs = all_strokes.flatten(1).map(&:first)
      ys = all_strokes.flatten(1).map(&:last)
      min_x = xs.empty? ? 0.0 : xs.min
      max_x = xs.empty? ? pen_x : xs.max
      min_y = ys.empty? ? 0.0 : ys.min
      max_y = ys.empty? ? 1.0 : ys.max
      center_x = (min_x + max_x) / 2.0
      center_y = (min_y + max_y) / 2.0
      {
        strokes: all_strokes.map { |stroke| stroke.map { |x, y| [x - center_x, y - center_y] } },
        width: [max_x - min_x, 0.01].max,
        height: [max_y - min_y, 0.01].max
      }
    end

    def measure(text)
      data = layout(text)
      { width_em: data[:width], height_em: data[:height] }
    end

    def add_edges(entities, text, height, z: 0.0)
      data = layout(text)
      data[:strokes].each do |stroke|
        points = stroke.map do |x, y|
          Geom::Point3d.new(x * height, -y * height, z)
        end
        entities.add_edges(points) if points.length >= 2
      end

      # Mot so SketchUp context tu dong tao Face khi stroke dong kin.
      # Xoa rieng Face, giu lai toan bo canh centerline.
      entities.grep(Sketchup::Face).each { |face| face.erase! if face.valid? }
      entities.grep(Sketchup::Edge)
    end
  end
end
