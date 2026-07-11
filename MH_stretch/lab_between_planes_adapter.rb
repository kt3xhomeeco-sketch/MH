# encoding: UTF-8

module MH::Stretch
  # UI bridge for the Ctrl custom-grip bounded region workflow.
  module BetweenPlanesAdapter
    module_function

    def available?
      defined?(BetweenPlanesSelector) && defined?(BetweenPlanesOperation)
    end

    def region_for_grip(axis:, grip_point:, planes:, clearance: PlaneVertexSelector::DEFAULT_CLEARANCE)
      return nil unless axis && grip_point

      position = BoxModel.axis_value(grip_point, axis)
      cuts = planes.to_a.select { |plane| plane && plane[:usable] && plane[:axis] == axis && plane[:pos] }
      lower = cuts.select { |plane| plane[:pos].to_f < position - clearance.to_f }.max_by { |plane| plane[:pos].to_f }
      upper = cuts.select { |plane| plane[:pos].to_f > position + clearance.to_f }.min_by { |plane| plane[:pos].to_f }
      return nil unless lower && upper

      {
        axis: axis,
        min_plane: lower,
        max_plane: upper,
        min_pos: lower[:pos].to_f,
        max_pos: upper[:pos].to_f
      }
    end

    def commit(model, region, amount, make_unique: false)
      return UiAdapter.ui_result(false, 0, 'MH Stretch: engine giua 2 plane chua load.') unless available?
      return UiAdapter.ui_result(false, 0, 'MH Stretch: khong tim thay cap plane bao quanh grip.') unless region

      BetweenPlanesOperation.commit(
        model,
        axis: region[:axis],
        min_pos: region[:min_pos],
        max_pos: region[:max_pos],
        amount: amount,
        make_unique: make_unique
      )
    rescue => error
      UiAdapter.ui_result(false, 0, "#{error.class}: #{error.message}")
    end

    def preview(model, region, amount, max_segments: UiAdapter::MAX_PREVIEW_SEGMENTS)
      return [] unless available? && region
      return [] if amount.to_f.abs <= StretchOperation::MIN_AMOUNT

      delta = PlaneVertexSelector.world_delta(region[:axis], amount.to_f)
      segments = []
      seen = {}
      model.selection.each do |entity|
        collect_preview_entity(entity, Geom::Transformation.new, region, delta, segments, seen, max_segments)
        break if segments.length >= max_segments
      end
      segments
    rescue => error
      warn "MH Stretch between-plane preview failed: #{error.class}: #{error.message}"
      []
    end

    def collect_preview_entity(entity, parent_to_world, region, delta, segments, seen, max_segments)
      return if segments.length >= max_segments
      return unless entity && (!entity.respond_to?(:valid?) || entity.valid?)
      return if entity.respond_to?(:hidden?) && entity.hidden?

      if entity.is_a?(Sketchup::Edge)
        add_edge_preview(entity, parent_to_world, region, delta, segments, seen)
      elsif entity.is_a?(Sketchup::Face)
        entity.edges.each do |edge|
          add_edge_preview(edge, parent_to_world, region, delta, segments, seen)
          break if segments.length >= max_segments
        end
      elsif PlaneVertexSelector.group_or_component?(entity)
        child_to_world = parent_to_world * entity.transformation
        PlaneVertexSelector.child_entities(entity).each do |child|
          collect_preview_entity(child, child_to_world, region, delta, segments, seen, max_segments)
          break if segments.length >= max_segments
        end
      end
    rescue
      nil
    end

    def add_edge_preview(edge, parent_to_world, region, delta, segments, seen)
      return unless edge && edge.valid?

      key = UiAdapter.edge_key(edge, parent_to_world)
      return if seen[key]

      p1 = edge.start.position.transform(parent_to_world)
      p2 = edge.end.position.transform(parent_to_world)
      s1 = preview_point(p1, region, delta)
      s2 = preview_point(p2, region, delta)
      return if UiAdapter.same_point?(p1, s1) && UiAdapter.same_point?(p2, s2)

      seen[key] = true
      segments << [s1, s2]
    rescue
      nil
    end

    def preview_point(point, region, delta)
      return point unless BetweenPlanesSelector.in_moving_zone?(point, region[:axis], region[:min_pos], region[:max_pos])

      point.offset(delta)
    end
  end
end
