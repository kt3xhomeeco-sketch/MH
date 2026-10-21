# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    module Axes
      module_function

      def center_origin(group)
        return nil unless group && group.respond_to?(:definition)

        definition = group.definition
        entities = definition.entities
        new_origin = definition.bounds.center
        new_axes = Geom::Transformation.axes(new_origin, X_AXIS, Y_AXIS, Z_AXIS)
        entities.transform_entities(new_axes.inverse, entities.to_a)
        definition.instances.each { |instance| instance.transformation *= new_axes }
      end

      def find_origin(edges)
        points = edges.flat_map(&:vertices).uniq.map(&:position)
        points.sort_by!(&:z)
        points.select! { |point| point.z == points.first.z }
        points.sort_by!(&:y)
        points.select! { |point| point.y == points.first.y }
        points.size == 1 ? points.first : points.sort_by(&:x).last
      end

      def find_edge_vectors(edges, origin)
        edges.select { |edge| edge.vertices.any? { |vertex| vertex.position == origin } }.map do |edge|
          vertex = edge.vertices.find { |v| v.position == origin }
          origin.vector_to(edge.other_vertex(vertex).position)
        end
      end

      def select_lowest_vectors(vectors, origin)
        normalized = vectors.map(&:normalize)
        points = normalized.map { |vector| origin.offset(vector) }
        points.sort_by!(&:z)
        selected = normalized.select { |vector| points[0..1].include?(origin.offset(vector)) }
        selected.length < 2 ? normalized[0..1] : selected
      end

      def find_longest_vector(vectors, selected_normalized)
        selected = vectors.select do |vector|
          next false if vector.length < TOL

          normalized = vector.normalize
          selected_normalized.any? do |candidate|
            (normalized.x - candidate.x).abs < TOL &&
              (normalized.y - candidate.y).abs < TOL &&
              (normalized.z - candidate.z).abs < TOL
          end
        end
        selected = vectors.select { |vector| vector.length >= TOL } if selected.empty?
        selected.sort_by! { |vector| -vector.length }
        selected.first&.normalize || X_AXIS
      end

      def calculate_axes(xaxis, second_vector)
        xaxis = xaxis.length > TOL ? xaxis.normalize : X_AXIS
        zaxis = xaxis.cross(second_vector)
        if zaxis.length < TOL
          perpendicular = [X_AXIS, Y_AXIS, Z_AXIS].find { |axis| xaxis.cross(axis).length > TOL }
          zaxis = xaxis.cross(perpendicular)
        end
        zaxis = zaxis.normalize
        yaxis = zaxis.cross(xaxis).normalize
        [xaxis, yaxis, zaxis]
      end

      def reset_axes(group, auto_rotate_grain = false)
        return nil unless group && group.respond_to?(:definition)

        definition = group.definition
        entities = definition.entities
        edges = entities.grep(Sketchup::Edge)
        return nil if edges.empty?

        origin = find_origin(edges)
        vectors = find_edge_vectors(edges, origin)
        selected = select_lowest_vectors(vectors, origin)
        xaxis = find_longest_vector(vectors, selected)
        second_vector = selected.find { |vector| xaxis.cross(vector).length > TOL }
        second_vector ||= vectors.select { |vector| vector.length > TOL }.map(&:normalize).find { |vector| xaxis.cross(vector).length > TOL }
        second_vector ||= [X_AXIS, Y_AXIS, Z_AXIS].find { |vector| xaxis.cross(vector).length > TOL }
        xaxis, yaxis, zaxis = calculate_axes(xaxis, second_vector)

        if auto_rotate_grain
          world_z = zaxis.transform(group.transformation).normalize
          local_target_x = if world_z.parallel?(Z_AXIS)
                             X_AXIS.transform(group.transformation.inverse).normalize
                           else
                             target_world_x = Z_AXIS - world_z * (Z_AXIS.dot(world_z))
                             target_world_x.normalize!
                             target_world_x.transform(group.transformation.inverse).normalize
                           end
          if local_target_x.dot(yaxis).abs > local_target_x.dot(xaxis).abs
            xaxis = yaxis
            yaxis = zaxis.cross(xaxis).normalize
          end
        end

        new_axes = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
        definition.entities.transform_entities(new_axes.inverse, entities.to_a)
        definition.instances.each { |instance| instance.transformation *= new_axes }
      end

      def fix_scale(group)
        return unless Util.is_container?(group)

        transformation = group.transformation
        scales = [X_AXIS, Y_AXIS, Z_AXIS].map { |axis| axis.transform(transformation).length }
        definition_transform = Geom::Transformation.scaling(*scales)
        instance_transform = definition_transform.inverse
        definition = group.definition
        definition.entities.transform_entities(definition_transform, definition.entities.to_a)
        definition.instances.each do |instance|
          instance_transform_current = instance.transformation
          instance.transform!(instance_transform_current * instance_transform * instance_transform_current.inverse)
        end
      end
    end
  end
end
