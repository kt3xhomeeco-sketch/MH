# frozen_string_literal: true

module MH
  module DWG
    # Collects bounded wireframe data without creating any preview instance.
    module CustomPreviewGeometry
      private

      def collect_preview_segments(entities, transform: IDENTITY, segments: [], limit: 12_000, ancestors: [])
        entities.each do |entity|
          break if segments.length >= limit

          append_preview_entity(entity, transform, segments, limit, ancestors)
        end
        segments
      end

      def append_preview_entity(entity, transform, segments, limit, ancestors)
        case entity
        when Sketchup::Edge
          segments << [entity.start.position.transform(transform), entity.end.position.transform(transform)]
        when Sketchup::ComponentInstance, Sketchup::Group
          append_nested_preview(entity, transform, segments, limit, ancestors)
        end
      end

      def append_nested_preview(entity, transform, segments, limit, ancestors)
        return unless entity.valid?

        definition = entity.definition
        return if ancestors.include?(definition) || ancestors.length >= 64

        options = { transform: transform * entity.transformation, segments: segments,
                    limit: limit, ancestors: ancestors + [definition] }
        collect_preview_segments(definition.entities, **options)
      end

      def bounds_preview_segments(definition)
        bounds = definition_bounds(definition)
        return [] if bounds.empty?

        [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4],
         [0, 4], [1, 5], [2, 6], [3, 7]].map { |first, last| [bounds.corner(first), bounds.corner(last)] }
      end

      def definition_bounds(definition)
        bounds = Geom::BoundingBox.new
        if definition.respond_to?(:bounds)
          add_bounds(bounds, definition.bounds)
          return bounds unless bounds.empty?
        end
        add_entity_bounds(bounds, definition.entities)
        bounds
      end

      def add_entity_bounds(bounds, entities)
        entities.each do |entity|
          add_bounds(bounds, entity.bounds) if entity.respond_to?(:bounds)
        end
      end

      def add_bounds(target, source)
        return if source.empty?

        8.times { |index| target.add(source.corner(index)) }
      end

      def drawable_point?(point)
        [point.x, point.y, point.z].all? { |value| value.to_f.finite? && value.to_f.abs < 1.0e9 }
      rescue StandardError
        false
      end
    end

    # Transforms and draws the collected wireframe with the original Euler order.
    module CustomPreviewTransform
      private

      def draw_preview(view)
        points = @preview_segments.flat_map { |first, last| transformed_segment(first, last) }
        return if points.empty?

        view.line_width = 1
        view.drawing_color = 'black'
        view.draw(GL_LINES, points)
      end

      def transformed_segment(first, last)
        points = [first.transform(@preview_transform), last.transform(@preview_transform)]
        points.all? { |point| drawable_point?(point) } ? points : []
      end

      def update_transform
        return unless @current_pos && preview_changed?

        rotation = preview_rotation
        @preview_transform = preview_translation(rotation) * rotation
        @last_pos = @current_pos.clone
        @last_rot = @rot.clone
      end

      def preview_changed?
        @last_pos.nil? || @current_pos != @last_pos || @last_rot.nil? || @rot != @last_rot
      end

      def preview_rotation
        rx = Geom::Transformation.rotation(ORIGIN, X_AXIS, @rot[0].degrees)
        ry = Geom::Transformation.rotation(ORIGIN, Y_AXIS, @rot[1].degrees)
        rz = Geom::Transformation.rotation(ORIGIN, Z_AXIS, @rot[2].degrees)
        rx * ry * rz
      end

      def preview_translation(rotation)
        offset = @base_offset.transform(rotation)
        position = Geom::Point3d.new(@current_pos.x - offset.x, @current_pos.y - offset.y, @current_pos.z - offset.z)
        Geom::Transformation.translation(position)
      end
    end
  end
end
