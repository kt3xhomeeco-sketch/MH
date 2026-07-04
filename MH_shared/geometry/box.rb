# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    module Box
      AXIS_DIRECTIONS = {
        '+X' => X_AXIS,
        '-X' => X_AXIS.reverse,
        '+Y' => Y_AXIS,
        '-Y' => Y_AXIS.reverse,
        '+Z' => Z_AXIS,
        '-Z' => Z_AXIS.reverse
      }.freeze

      module_function

      def edges_are_collinear?(edge1, edge2)
        return false unless edge1 && edge2 && edge1.valid? && edge2.valid?

        edge1.line[1].parallel?(edge2.line[1])
      end

      def intersection_vertex?(vertex)
        return false unless vertex && vertex.valid?
        return true if vertex.edges.length > 2
        return !edges_are_collinear?(vertex.edges[0], vertex.edges[1]) if vertex.edges.length == 2

        false
      end

      def connected_collinear_edges(start_edge)
        return [] unless start_edge && start_edge.valid?

        result = [start_edge]
        2.times do |direction|
          current = start_edge
          vertex = direction.zero? ? current.start : current.end
          loop do
            break unless vertex.valid? && !intersection_vertex?(vertex)

            next_edge = vertex.edges.find do |edge|
              edge != current && edge.valid? && !result.include?(edge) && edges_are_collinear?(current, edge)
            end
            break unless next_edge

            result << next_edge
            current = next_edge
            vertex = (next_edge.start == vertex) ? next_edge.end : next_edge.start
          end
        end
        result.uniq
      end

      def edges_length(edges, transform = IDENTITY)
        Array(edges).sum do |edge|
          next 0 unless edge && edge.valid?

          edge.start.position.transform(transform).distance(edge.end.position.transform(transform))
        end
      end

      def edge_axis(edge, transform = IDENTITY)
        return :OTHER unless edge && edge.valid?

        p1 = edge.start.position.transform(transform)
        p2 = edge.end.position.transform(transform)
        vector = p1.vector_to(p2)
        return :OTHER if vector.length < 0.001.mm

        vector.normalize!
        return :X if vector.parallel?(X_AXIS) || vector.parallel?(X_AXIS.reverse)
        return :Y if vector.parallel?(Y_AXIS) || vector.parallel?(Y_AXIS.reverse)
        return :Z if vector.parallel?(Z_AXIS) || vector.parallel?(Z_AXIS.reverse)

        :OTHER
      end

      def edge_endpoints(edges, transform = IDENTITY)
        Array(edges).each_with_object([]) do |edge, points|
          next unless edge && edge.valid?

          points << edge.start.position.transform(transform)
          points << edge.end.position.transform(transform)
        end
      end

      def edge_line(edge, transform = IDENTITY)
        return nil unless edge && edge.valid?

        p1 = edge.start.position.transform(transform)
        p2 = edge.end.position.transform(transform)
        vector = p1.vector_to(p2)
        return nil if vector.length < 0.001.mm

        [p1, vector]
      end

      def edge_span(edges, transform = IDENTITY)
        line = edge_line(Array(edges).find { |edge| edge && edge.valid? }, transform)
        return nil unless line

        line_point, line_vector = line
        axis = line_vector.normalize
        points = edge_endpoints(edges, transform)
        return nil if points.empty?

        projections = points.map { |point| line_point.vector_to(point) % axis }
        {
          start: line_point.offset(axis, projections.min),
          end: line_point.offset(axis, projections.max),
          axis: axis,
          length: projections.max - projections.min,
          line: [line_point, line_vector]
        }
      end

      def pick_edge(view, x, y, aperture = 5)
        pick_helper = view.pick_helper
        pick_helper.do_pick(x, y, aperture)
        (0...pick_helper.count).each do |index|
          path = pick_helper.path_at(index)
          edge = Array(path).find { |entity| entity.is_a?(Sketchup::Edge) }
          next unless edge && edge.valid?

          transform = pick_helper.transformation_at(index) || Util.transform_from_path(path)
          return [edge, transform, path]
        end
        [nil, IDENTITY, nil]
      end

      def pick_face(view, x, y, aperture = 10)
        pick_helper = view.pick_helper
        pick_helper.do_pick(x, y, aperture)
        (0...pick_helper.count).each do |index|
          path = pick_helper.path_at(index)
          face = Array(path).find { |entity| entity.is_a?(Sketchup::Face) }
          next unless face && face.valid?

          transform = pick_helper.transformation_at(index) || Util.transform_from_path(path)
          next if block_given? && !yield(face, path, transform)

          return [face, transform, path]
        end
        [nil, IDENTITY, nil]
      end

      def face_points(face, transform = IDENTITY)
        return [] unless face && face.valid?

        face.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
      end

      def face_normal(face, transform = IDENTITY)
        return nil unless face && face.valid?

        normal = face.normal.transform(transform)
        return nil if normal.length <= 0.001.mm

        normal.normalize!
        normal
      end

      def corners_from_bounds(bounds)
        min = bounds.min
        max = bounds.max
        corners_from_min_max(min, max)
      end

      def corners_from_min_max(min, max)
        [
          Geom::Point3d.new(min.x, min.y, min.z),
          Geom::Point3d.new(max.x, min.y, min.z),
          Geom::Point3d.new(max.x, max.y, min.z),
          Geom::Point3d.new(min.x, max.y, min.z),
          Geom::Point3d.new(min.x, min.y, max.z),
          Geom::Point3d.new(max.x, min.y, max.z),
          Geom::Point3d.new(max.x, max.y, max.z),
          Geom::Point3d.new(min.x, max.y, max.z)
        ]
      end

      def axis_info_from_face(face, path, origin, model = Sketchup.active_model)
        transform = Util.transform_from_path(path)
        points = face.vertices.map { |vertex| vertex.position.transform(transform) }
        bounds = Geom::BoundingBox.new
        points.each { |point| bounds.add(point) }

        axis_info = {}
        AXIS_DIRECTIONS.each do |label, vector|
          edge_distance = distance_to_bounds(bounds, origin, label)
          edge_distance = nil if edge_distance && edge_distance <= 0.0
          hit = model.raytest([origin, vector])
          axis_info[label] = hit ? (edge_distance ? [origin.distance(hit[0]), edge_distance].min : origin.distance(hit[0])) : edge_distance
        end
        axis_info
      end

      def distance_to_bounds(bounds, origin, label)
        case label
        when '+X' then bounds.max.x - origin.x
        when '-X' then origin.x - bounds.min.x
        when '+Y' then bounds.max.y - origin.y
        when '-Y' then origin.y - bounds.min.y
        when '+Z' then bounds.max.z - origin.z
        when '-Z' then origin.z - bounds.min.z
        end
      end

      def corners_from_axis_info(origin, axis_info)
        dxp, dxm, dyp, dym, dzp, dzm = axis_info.values_at('+X', '-X', '+Y', '-Y', '+Z', '-Z')
        return nil if [dxp, dxm, dyp, dym, dzp, dzm].any? { |distance| !distance.is_a?(Numeric) || distance <= 0.0 }

        min = Geom::Point3d.new(origin.x - dxm, origin.y - dym, origin.z - dzm)
        max = Geom::Point3d.new(origin.x + dxp, origin.y + dyp, origin.z + dzp)
        corners_from_min_max(min, max)
      end

      def face_push_box(face:, path:, view:, x:, y:, live_size: nil, locked_base_point: nil, right_button_held: false, default_size: 100.mm)
        return nil unless face && face.valid? && path.is_a?(Array)

        transform = Util.transform_from_path(path)
        vertices = face.vertices.map { |vertex| vertex.position.transform(transform) }
        return nil if vertices.empty?

        normal = face.normal.transform(transform)
        return nil if normal.length == 0.0

        normal.normalize!
        ray = view.pickray(x, y) if x && y
        hit_point = ray ? Geom.intersect_line_plane(ray, [vertices.first, normal]) : nil
        base_point = hit_point || centroid(vertices)
        origin = base_point.offset(normal, 5.mm)
        axis_info = axis_info_from_face(face, path, origin, view.model)
        missing = %w[+X -X +Y -Y +Z -Z].select { |key| !axis_info[key].is_a?(Numeric) || axis_info[key] <= 0.0 }
        missing_axis = nil
        missing_axis_direction = nil
        live_override = live_size

        if missing.empty?
          live_override = nil
        elsif missing.length == 1
          missing_axis = missing.first
          missing_axis_direction = AXIS_DIRECTIONS[missing_axis]
          mouse_distance = live_override
          if !mouse_distance && right_button_held && locked_base_point && x && y
            screen_point = view.screen_coords(locked_base_point)
            screen_distance = Math.sqrt((x - screen_point.x)**2 + (y - screen_point.y)**2)
            mouse_distance = [screen_distance * view.pixels_to_model(1, locked_base_point), 10.mm].max
            live_override = mouse_distance
          end
          axis_info[missing_axis] = mouse_distance || default_size
        else
          return nil
        end

        corners = corners_from_axis_info(origin, axis_info)
        return nil unless corners

        {
          corners: corners,
          origin: origin,
          normal: normal,
          axis_info: axis_info,
          missing_axis: missing_axis,
          missing_axis_direction: missing_axis_direction,
          live_size_override: live_override
        }
      end

      def plane_corners(edge_start:, edge_end:, distance:, projected_point: nil, snap_point: nil, selected_axis: :OTHER, face_lock: nil)
        return nil unless edge_start && edge_end && distance && distance > 0.001.mm

        perp_vec = if snap_point
                     (projected_point || edge_start).vector_to(snap_point)
                   else
                     default_perp_for_axis(selected_axis)
                   end
        return nil unless perp_vec && perp_vec.length > 0.001.mm

        perp_vec = locked_perp_vector(perp_vec, face_lock)
        perp_vec.normalize!
        perp_vec.length = distance
        [edge_start, edge_end, edge_end.offset(perp_vec), edge_start.offset(perp_vec)]
      end

      def default_perp_for_axis(axis)
        case axis
        when :X then Y_AXIS.clone
        when :Y then X_AXIS.clone
        when :Z then X_AXIS.clone
        else Y_AXIS.clone
        end
      end

      def locked_perp_vector(vector, face_lock)
        case face_lock
        when :horizontal
          perp_x = vector % X_AXIS
          perp_y = vector % Y_AXIS
          new_vec = perp_x.abs >= perp_y.abs ? X_AXIS.clone : Y_AXIS.clone
          new_vec.reverse! if (perp_x.abs >= perp_y.abs ? perp_x : perp_y) < 0
          new_vec
        when :vertical
          new_vec = Z_AXIS.clone
          new_vec.reverse! if (vector % Z_AXIS) < 0
          new_vec
        else
          vector
        end
      end

      def centroid(points)
        Geom::Point3d.new(
          points.map(&:x).sum / points.length,
          points.map(&:y).sum / points.length,
          points.map(&:z).sum / points.length
        )
      end
    end
  end
end
