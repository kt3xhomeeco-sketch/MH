# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    module Poly2D
      EPSILON = 1e-10 unless const_defined?(:EPSILON, false)

      module_function

      # Tạo 2 trục 2D vuông góc nằm trên mặt phẳng có normal cho trước.
      # Trả về [u, v], cả hai là Geom::Vector3d đã normalize.
      def axes_for_normal(normal)
        n = normalize_vector(normal)
        return nil unless n

        ref = n.x.abs < 0.9 ? X_AXIS : Y_AXIS
        u = ref.cross(n)
        return nil if u.length < EPSILON

        u.normalize!
        v = n.cross(u)
        return nil if v.length < EPSILON

        v.normalize!
        [u, v]
      end

      # Diện tích có dấu của polygon 2D.
      # Polygon dùng dạng [[x, y], ...].
      def signed_area(poly)
        pts = normalize_poly(poly)
        return 0.0 if pts.length < 3

        area = 0.0
        pts.length.times do |index|
          nxt = (index + 1) % pts.length
          area += pts[index][0] * pts[nxt][1] - pts[nxt][0] * pts[index][1]
        end
        area / 2.0
      end

      def area(poly)
        signed_area(poly).abs
      end

      def ensure_ccw(poly)
        pts = normalize_poly(poly)
        signed_area(pts) >= 0.0 ? pts : pts.reverse
      end

      # Chiếu points 3D lên mặt phẳng normal·p = d, rồi lấy tọa độ theo 2 trục u/v.
      # Nếu d nil, dùng point đầu tiên của points làm mặt phẳng gốc.
      def project_points(points, normal, d = nil, u: nil, v: nil)
        pts = Array(points).compact
        return [] if pts.empty?

        n = normalize_vector(normal)
        return [] unless n

        axes = if u && v
                 [normalize_vector(u), normalize_vector(v)]
               else
                 axes_for_normal(n)
               end
        return [] unless axes && axes[0] && axes[1]

        u_axis, v_axis = axes
        plane_d = d
        plane_d = point_dot(pts.first, n) if plane_d.nil?

        pts.map do |point|
          projected = project_point_to_plane(point, n, plane_d)
          [point_dot(projected, u_axis), point_dot(projected, v_axis)]
        end
      end

      # Clip polygon theo cạnh clip-edge định hướng CCW.
      def clip_polygon(poly, edge_start_x, edge_start_y, edge_end_x, edge_end_y, epsilon: EPSILON)
        pts = normalize_poly(poly)
        output = []
        return output if pts.empty?

        inside = lambda do |x, y|
          ((edge_end_x - edge_start_x) * (y - edge_start_y) -
            (edge_end_y - edge_start_y) * (x - edge_start_x)) >= -epsilon
        end

        intersect = lambda do |x1, y1, x2, y2|
          dx1 = x2 - x1
          dy1 = y2 - y1
          dx2 = edge_end_x - edge_start_x
          dy2 = edge_end_y - edge_start_y
          denom = dx1 * dy2 - dy1 * dx2
          return [x1, y1] if denom.abs < epsilon

          t = ((edge_start_x - x1) * dy2 - (edge_start_y - y1) * dx2) / denom
          [x1 + t * dx1, y1 + t * dy1]
        end

        pts.length.times do |index|
          current = pts[index]
          previous = pts[(index - 1) % pts.length]
          current_inside = inside.call(current[0], current[1])
          previous_inside = inside.call(previous[0], previous[1])

          if current_inside
            output << intersect.call(previous[0], previous[1], current[0], current[1]) unless previous_inside
            output << current
          elsif previous_inside
            output << intersect.call(previous[0], previous[1], current[0], current[1])
          end
        end

        output
      end

      # Giao hai convex polygon 2D bằng Sutherland–Hodgman.
      # Đây là primitive tách từ fast_rename cp_poly_intersect.
      def intersection(poly_a, poly_b, epsilon: EPSILON)
        subject = ensure_ccw(poly_a)
        clipper = ensure_ccw(poly_b)
        return [] if subject.length < 3 || clipper.length < 3

        result = subject.dup
        clipper.length.times do |index|
          break if result.empty?

          edge_start = clipper[index]
          edge_end = clipper[(index + 1) % clipper.length]
          result = clip_polygon(
            result,
            edge_start[0], edge_start[1],
            edge_end[0], edge_end[1],
            epsilon: epsilon
          )
        end
        result
      end

      def normalize_poly(poly)
        Array(poly).filter_map do |point|
          if point.is_a?(Array) && point.length >= 2
            [point[0].to_f, point[1].to_f]
          elsif point.respond_to?(:x) && point.respond_to?(:y)
            [point.x.to_f, point.y.to_f]
          end
        end
      end

      def normalize_vector(vector)
        return nil unless vector

        v = if vector.is_a?(Geom::Vector3d)
              vector.clone
            elsif vector.respond_to?(:x) && vector.respond_to?(:y) && vector.respond_to?(:z)
              Geom::Vector3d.new(vector.x, vector.y, vector.z)
            elsif vector.is_a?(Array) && vector.length >= 3
              Geom::Vector3d.new(vector[0].to_f, vector[1].to_f, vector[2].to_f)
            end
        return nil unless v && v.length > EPSILON

        v.normalize!
        v
      rescue
        nil
      end

      def project_point_to_plane(point, normal, d)
        t = d.to_f - point_dot(point, normal)
        Geom::Point3d.new(
          point.x + t * normal.x,
          point.y + t * normal.y,
          point.z + t * normal.z
        )
      end

      def point_dot(point, vector)
        point.x.to_f * vector.x.to_f + point.y.to_f * vector.y.to_f + point.z.to_f * vector.z.to_f
      end
    end
  end
end
