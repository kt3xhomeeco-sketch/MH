# frozen_string_literal: true

module MH
  module CAD2Module
    # Circular plan evidence is independent of an instance's local axes.
    module PlanProfile
      TOL = 0.02
      module_function

      def key(point)
        point.map { |v| (v / 0.001).round }
      end

      def loop_points(edges)
        graph = Hash.new { |h, k| h[k] = [] }
        points = {}
        edges.each do |a, b|
          ka = key(a); kb = key(b)
          next if ka == kb
          points[ka] = a; points[kb] = b
          graph[ka] << kb unless graph[ka].include?(kb)
          graph[kb] << ka unless graph[kb].include?(ka)
        end
        raise ArgumentError, 'Biên khối cong phải là một vòng kín, không có lỗ hoặc nhánh bên trong.' if graph.empty? || graph.values.any? { |v| v.length != 2 }
        start = graph.keys.min
        order = [start]; previous = nil; current = start
        loop do
          following = graph[current].find { |p| p != previous }
          break if following == start
          raise ArgumentError, 'Biên khối cong bị đứt hoặc tự nối.' if order.include?(following)
          order << following
          previous = current; current = following
        end
        raise ArgumentError, 'Chỉ nhận một biên ngoài kín, chưa hỗ trợ khối có lỗ.' unless order.length == graph.length
        order.map { |k| points.fetch(k) }
      end

      def axis_edge?(a, b)
        (a[0] - b[0]).abs < 0.001 || (a[1] - b[1]).abs < 0.001
      end

      def arc(points)
        a = points.first
        b = points[points.length / 2].zip(a).map { |v, origin| v - origin }
        c = points.last.zip(a).map { |v, origin| v - origin }
        det = 2.0 * (b[0] * c[1] - b[1] * c[0])
        return nil if det.abs < 1e-9
        bb = b.sum { |v| v * v }; cc = c.sum { |v| v * v }
        center = [a[0] + (bb * c[1] - cc * b[1]) / det, a[1] + (b[0] * cc - c[0] * bb) / det]
        radius = Math.hypot(a[0] - center[0], a[1] - center[1])
        return nil unless radius > TOL && points.all? { |p| (Math.hypot(p[0] - center[0], p[1] - center[1]) - radius).abs <= TOL }
        turns = points.each_cons(2).map do |p, q|
          u = [p[0] - center[0], p[1] - center[1]]; v = [q[0] - center[0], q[1] - center[1]]
          Math.atan2(u[0] * v[1] - u[1] * v[0], u.zip(v).sum { |x, y| x * y })
        end
        return nil if turns.any? { |t| t.abs > Math::PI / 3 } || turns.any? { |t| t * turns.first <= 0 }
        sweep = turns.sum
        return nil unless sweep.abs.between?(0.001, 2 * Math::PI)
        { 'type' => 'arc', 'start' => a, 'end' => points.last, 'center' => center,
          'radius' => radius, 'sweep' => sweep, 'segments' => points.length - 1 }
      end

      def from_points(points)
        # Start on a straight edge so a rounded corner cannot be split at the seam.
        index = points.each_index.find { |i| axis_edge?(points[i], points[(i + 1) % points.length]) }
        raise ArgumentError, 'Biên cong cần cạnh thẳng và cung tròn; chưa hỗ trợ đường spline hoặc vòng tròn kín.' unless index
        points = points.rotate(index)
        closed = points + [points.first]
        result = []; i = 0
        while i < points.length
          if axis_edge?(closed[i], closed[i + 1])
            finish = i + 1
            while finish < points.length && axis_edge?(closed[finish], closed[finish + 1]) &&
                  ((closed[i][0] - closed[finish + 1][0]).abs < 0.001 || (closed[i][1] - closed[finish + 1][1]).abs < 0.001)
              finish += 1
            end
            result << { 'type' => 'line', 'start' => closed[i], 'end' => closed[finish] }
          else
            finish = i + 1
            finish += 1 while finish < points.length && !axis_edge?(closed[finish], closed[finish + 1])
            fitted = finish - i >= 3 ? arc(closed[i..finish]) : nil
            raise ArgumentError, 'Đường cong chưa khớp cung tròn; chưa nhận spline hoặc cạnh xiên làm góc bo.' unless fitted
            result << fitted
          end
          i = finish
        end
        { 'schema' => 1, 'segments' => result }
      end

      def prism(edges)
        return nil if edges.empty?
        pts = edges.flatten(1)
        low = 3.times.map { |i| pts.map { |p| p[i] }.min }
        high = 3.times.map { |i| pts.map { |p| p[i] }.max }
        return nil if 3.times.any? { |i| high[i] - low[i] < 0.1 }
        bottom = edges.select { |e| e.all? { |p| (p[2] - low[2]).abs < 0.1 } }.map { |e| e.map { |p| p[0, 2] } }
        return nil if bottom.all? { |a, b| axis_edge?(a, b) }
        top = edges.select { |e| e.all? { |p| (p[2] - high[2]).abs < 0.1 } }.map { |e| e.map { |p| p[0, 2] } }
        points = loop_points(bottom)
        raise ArgumentError, 'Mặt trên và dưới của khối cong phải cùng biên dạng.' unless bottom.map { |e| e.map { |p| key(p) }.sort }.sort == top.map { |e| e.map { |p| key(p) }.sort }.sort
        vertical = edges - edges.select { |e| e.all? { |p| (p[2] - low[2]).abs < 0.1 } || e.all? { |p| (p[2] - high[2]).abs < 0.1 } }
        raise ArgumentError, 'Khối cong phải đùn thẳng theo chiều cao, không vát hoặc xoắn.' unless vertical.all? { |a, b| 2.times.all? { |i| (a[i] - b[i]).abs < 0.1 } }
        points.each do |p|
          spans = vertical.filter_map { |a, b| [a[2], b[2]].minmax if 2.times.all? { |i| (a[i] - p[i]).abs < 0.1 } }.sort
          reach = low[2]
          spans.each do |a, b|
            raise ArgumentError, 'Khối cong chưa kín theo chiều cao.' if a > reach + 0.1
            reach = [reach, b].max
          end
          raise ArgumentError, 'Khối cong thiếu cạnh đứng.' if reach < high[2] - 0.1
        end
        relative = points.map { |p| 2.times.map { |i| p[i] - low[i] } }
        profile = from_points(relative)
        { 'origin' => low, 'size' => 3.times.map { |i| high[i] - low[i] }, 'plan_profile' => profile }
      end

      def measured(entity, transform = entity.transformation)
        edges = []
        walk = lambda do |entities, transform, depth|
          raise ArgumentError, 'Khối cong lồng quá nhiều cấp.' if depth > 15
          entities.each do |item|
            if item.is_a?(Sketchup::Edge)
              edges << [item.start.position, item.end.position].map { |p| p.transform(transform).to_a.map(&:to_mm) }
            elsif item.is_a?(Sketchup::Group) || item.is_a?(Sketchup::ComponentInstance)
              walk.call(item.definition.entities, transform * item.transformation, depth + 1)
            end
          end
        end
        walk.call(entity.definition.entities, transform, 0)
        prism(edges)
      end

      def face(entities, profile)
        edges = profile.fetch('segments').flat_map do |segment|
          a = segment.fetch('start'); b = segment.fetch('end')
          if segment['type'] == 'arc'
            center = segment.fetch('center')
            sweep = segment.fetch('sweep')
            point = Geom::Point3d.new(center[0].mm, center[1].mm, 0)
            xaxis = Geom::Vector3d.new(a[0] - center[0], a[1] - center[1], 0)
            # Positive sweeps keep the entire corner in one ArcCurve (MH_panel).
            normal = Geom::Vector3d.new(0, 0, sweep.negative? ? -1 : 1)
            entities.add_arc(point, xaxis, normal, segment.fetch('radius').mm, 0, sweep.abs, segment.fetch('segments'))
          elsif segment['type'] == 'line'
            [entities.add_line([a[0].mm, a[1].mm, 0], [b[0].mm, b[1].mm, 0])]
          else
            raise ArgumentError, 'Loại cạnh biên dạng chưa được hỗ trợ.'
          end
        end
        edges.first.find_faces
        face = entities.grep(Sketchup::Face).max_by(&:area)
        raise ArgumentError, 'Không tạo được mặt kín từ biên cong.' unless face
        face.reverse! if face.normal.z.negative?
        face
      end
    end
  end
end
