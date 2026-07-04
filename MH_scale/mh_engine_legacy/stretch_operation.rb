# encoding: UTF-8

module MH
module Scale
  module StretchOperation
    MIN_AMOUNT = 0.001.mm

    module_function

    def commit(model, axis:, side:, plane_pos:, amount:, clearance: PlaneVertexSelector::DEFAULT_CLEARANCE)
      return result(false, 0, 'Selection rong.') if model.selection.empty?
      return result(false, 0, 'Doan keo qua nho.') if amount.to_f.abs <= MIN_AMOUNT

      model.start_operation('MH Scale Grip Stretch', true)
      PlaneVertexSelector.make_selection_unique(model.selection.to_a)
      buckets = PlaneVertexSelector.select(
        model,
        axis: axis,
        side: side,
        plane_pos: plane_pos,
        clearance: clearance
      )
      world_delta = PlaneVertexSelector.world_delta(axis, amount.to_f)
      moved = move_origin_containers(buckets[:origin_containers], world_delta)
      moved += move_containers(buckets[:containers], world_delta)
      moved += move_curves(buckets[:curves], world_delta)
      moved += move_vertex_buckets(buckets[:vertex_buckets], world_delta)
      model.commit_operation
      result(moved.positive?, moved, moved.positive? ? "Da move #{moved} doi tuong/vertex." : 'Khong co vertex trong vung grip-plane.')
    rescue => error
      model.abort_operation rescue nil
      result(false, 0, "#{error.class}: #{error.message}")
    end

    def move_containers(containers, world_delta)
      moved = 0
      containers.each do |bucket|
        entity = bucket[:entity]
        next unless entity && entity.valid?

        local_delta = world_delta.transform(bucket[:parent_to_world].inverse)
        entity.transformation = Geom::Transformation.translation(local_delta) * entity.transformation
        moved += 1
      end
      moved
    end

    def move_origin_containers(containers, world_delta)
      moved = 0
      containers.each do |bucket|
        entity = bucket[:entity]
        next unless entity && entity.valid?

        old_transform = entity.transformation
        parent_to_world = bucket[:parent_to_world]
        child_to_world = parent_to_world * old_transform
        delta_in_parent = world_delta.transform(parent_to_world.inverse)
        delta_in_child = world_delta.transform(child_to_world.inverse)

        entity.transformation = Geom::Transformation.translation(delta_in_parent) * old_transform
        compensate_container_contents(entity, delta_in_child.reverse)
        moved += 1
      end
      moved
    end

    def compensate_container_contents(entity, local_delta)
      entities = PlaneVertexSelector.child_entities(entity)
      targets = entities.to_a
      return if targets.empty?

      entities.transform_entities(Geom::Transformation.translation(local_delta), targets)
    rescue => error
      warn "MH Scale origin compensation failed: #{error.class}: #{error.message}"
    end

    def move_vertex_buckets(buckets, world_delta)
      moved = 0
      buckets.each do |bucket|
        vertices = bucket[:vertices]
        next if vertices.empty?

        local_delta = world_delta.transform(bucket[:parent_to_world].inverse)
        transform = Geom::Transformation.translation(local_delta)
        bucket[:entities].transform_entities(transform, vertices)
        moved += vertices.length
      end
      moved
    end

    def move_curves(curves, world_delta)
      moved = 0
      curves.each do |bucket|
        curve = bucket[:curve]
        vertices = bucket[:vertices]
        next unless curve && vertices && !vertices.empty?

        local_delta = world_delta.transform(bucket[:parent_to_world].inverse)
        active_curve = curve
        active_vertices = vertices

        if partial_curve?(bucket)
          replacement = convert_arc_curve_if_needed(bucket)
          if replacement
            active_curve = replacement[:curve]
            active_vertices = replacement[:vertices]
          end
        end

        moved += move_curve_vertices(active_curve, active_vertices, local_delta)
      end
      moved
    end

    def partial_curve?(bucket)
      bucket[:vertices].length < bucket[:all_vertices_count].to_i
    end

    def convert_arc_curve_if_needed(bucket)
      curve = bucket[:curve]
      return nil unless defined?(Sketchup::ArcCurve) && curve.is_a?(Sketchup::ArcCurve)

      old_vertices = curve.vertices
      positions = old_vertices.map(&:position)
      moving_indexes = bucket[:vertices].map { |vertex| old_vertices.index(vertex) }.compact
      parent_entities = bucket[:entities]
      curve.edges.first.explode_curve
      edges = parent_entities.add_curve(positions)
      new_curve = edges.first.curve
      {
        curve: new_curve,
        vertices: moving_indexes.map { |index| new_curve.vertices[index] }.compact
      }
    rescue => error
      warn "MH Scale arc curve conversion failed: #{error.class}: #{error.message}"
      nil
    end

    def move_curve_vertices(curve, vertices, local_delta)
      moving = curve.vertices.map do |vertex|
        vertices.include?(vertex) ? vertex.position.offset(local_delta) : vertex.position
      end
      curve.move_vertices(moving)
      vertices.length
    rescue => error
      warn "MH Scale curve move failed: #{error.class}: #{error.message}"
      0
    end

    def result(ok, changed, message)
      { ok: ok, changed: changed, message: message }
    end
  end
end
end
