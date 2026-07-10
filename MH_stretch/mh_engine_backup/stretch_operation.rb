# encoding: UTF-8

module MH
module Stretch
  module StretchOperation
    MIN_AMOUNT = 0.001.mm

    module_function

    def commit(model, axis:, side:, plane_pos:, amount:, clearance: PlaneVertexSelector::DEFAULT_CLEARANCE, make_unique: true)
      return result(false, 0, 'Selection rong.') if model.selection.empty?
      return result(false, 0, 'Doan keo qua nho.') if amount.to_f.abs <= MIN_AMOUNT

      model.start_operation('MH Stretch Grip Stretch', true)
      unique_count =
        make_unique ? PlaneVertexSelector.make_selection_unique(model.selection.to_a) : 0
      moved = move_for_plane(
        model,
        axis: axis,
        side: side,
        plane_pos: plane_pos,
        amount: amount,
        clearance: clearance
      )
      model.commit_operation
      output = result(moved.positive?, moved, moved.positive? ? "Da stretch #{moved} doi tuong/vertex." : 'Khong co vertex trong vung grip-plane.')
      output[:unique_count] = unique_count
      output
    rescue => error
      model.abort_operation rescue nil
      result(false, 0, "#{error.class}: #{error.message}")
    end

    def commit_many(model, planes:, amount:, clearance: PlaneVertexSelector::DEFAULT_CLEARANCE, make_unique: true)
      planes = normalize_planes(planes)
      return result(false, 0, 'Selection rong.') if model.selection.empty?
      return result(false, 0, 'Khong co plane hop le.') if planes.empty?
      return commit(model, axis: planes.first[:axis], side: planes.first[:side], plane_pos: planes.first[:pos], amount: amount, clearance: clearance, make_unique: make_unique) if planes.length == 1
      return result(false, 0, 'Doan keo qua nho.') if amount.to_f.abs <= MIN_AMOUNT

      step_amount = amount.to_f / planes.length
      return result(false, 0, 'Doan keo qua nho.') if step_amount.abs <= MIN_AMOUNT

      model.start_operation('MH Stretch Multi Plane Stretch', true)
      unique_count =
        make_unique ? PlaneVertexSelector.make_selection_unique(model.selection.to_a) : 0
      moved = 0
      ordered_planes(planes).each do |plane|
        moved += move_for_plane(
          model,
          axis: plane[:axis],
          side: plane[:side],
          plane_pos: plane[:pos],
          amount: step_amount,
          clearance: clearance
        )
      end
      model.commit_operation
      output = result(
        moved.positive?,
        moved,
        moved.positive? ? "Da stretch #{moved} doi tuong/vertex qua #{planes.length} plane." : 'Khong co vertex trong vung grip-plane.'
      )
      output[:unique_count] = unique_count
      output
    rescue => error
      model.abort_operation rescue nil
      result(false, 0, "#{error.class}: #{error.message}")
    end

    def move_for_plane(model, axis:, side:, plane_pos:, amount:, clearance:)
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
      moved + move_vertex_buckets(buckets[:vertex_buckets], world_delta)
    end

    def normalize_planes(planes)
      planes.to_a.each_with_object([]) do |plane, list|
        next unless plane && plane[:axis] && plane[:pos]

        list << {
          axis: plane[:axis],
          side: plane[:side] || :plus,
          pos: plane[:pos].to_f
        }
      end
    end

    def ordered_planes(planes)
      sorted = planes.sort_by { |plane| plane[:pos].to_f }
      sorted.first && sorted.first[:side] == :minus ? sorted : sorted.reverse
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
      warn "MH Stretch origin compensation failed: #{error.class}: #{error.message}"
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
      prepared = curves.filter_map { |bucket| prepare_curve_move(bucket, world_delta) }
      return 0 if prepared.empty?

      preserved = full_curves_safe_to_transform(prepared)
      moved = move_full_curve_edges(preserved)
      prepared -= preserved

      # Every connected curve must be plain edges before a shared vertex moves.
      # Otherwise SketchUp re-solves a neighboring ArcCurve before it is exploded.
      prepared.select! { |entry| explode_prepared_curve(entry) }

      moved += move_prepared_curve_vertices(prepared)
      prepared.each { |entry| rebuild_isolated_curve(entry) }
      moved
    rescue => error
      warn "MH Stretch curve rebuild failed: #{error.class}: #{error.message}"
      0
    end

    def prepare_curve_move(bucket, world_delta)
      curve = bucket[:curve]
      vertices = bucket[:vertices]
      return nil unless curve && vertices && !vertices.empty?

      edges = curve.edges.dup

      {
        entities: bucket[:entities],
        first_edge: edges.first,
        edge_keys: edges.map { |edge| edge_key(edge) },
        vertices: curve.vertices,
        moving_keys: vertices.each_with_object({}) { |vertex, keys| keys[vertex_key(vertex)] = true },
        local_delta: world_delta.transform(bucket[:parent_to_world].inverse),
        full_move: vertices.length == curve.vertices.length
      }
    rescue
      nil
    end

    def full_curves_safe_to_transform(prepared)
      partial_vertex_keys = prepared.reject { |entry| entry[:full_move] }
                                    .flat_map { |entry| entry[:vertices] }
                                    .map { |vertex| vertex_key(vertex) }
                                    .uniq
      prepared.select do |entry|
        entry[:full_move] && entry[:vertices].none? { |vertex| partial_vertex_keys.include?(vertex_key(vertex)) }
      end
    end

    def move_full_curve_edges(prepared)
      moved_vertex_keys = {}
      prepared.group_by do |entry|
        [entry[:entities].object_id, entry[:local_delta].to_a.map { |value| value.round(9) }]
      end.each_value do |entries|
        entities = entries.first[:entities]
        edges = entries.flat_map { |entry| entry[:edge_keys] }
        targets = entities.grep(Sketchup::Edge).select { |edge| edges.include?(edge_key(edge)) }
        next if targets.empty?

        entities.transform_entities(Geom::Transformation.translation(entries.first[:local_delta]), targets)
        entries.each do |entry|
          entry[:vertices].each { |vertex| moved_vertex_keys[vertex_key(vertex)] = true if vertex.valid? }
        end
      end
      moved_vertex_keys.length
    rescue => error
      warn "MH Stretch full curve move failed: #{error.class}: #{error.message}"
      0
    end

    def explode_prepared_curve(entry)
      edge = entry[:first_edge]
      return false unless edge && edge.valid?

      edge.explode_curve
      true
    rescue => error
      warn "MH Stretch curve explode failed: #{error.class}: #{error.message}"
      false
    end

    def move_prepared_curve_vertices(prepared)
      moved = 0
      moved_vertex_keys = {}
      prepared.each do |entry|
        vertices = entry[:vertices].select do |vertex|
          vertex.valid? && entry[:moving_keys][vertex_key(vertex)] && !moved_vertex_keys[vertex_key(vertex)]
        end
        next if vertices.empty?

        entry[:entities].transform_entities(Geom::Transformation.translation(entry[:local_delta]), vertices)
        vertices.each { |vertex| moved_vertex_keys[vertex_key(vertex)] = true }
        moved += vertices.length
      end
      moved
    end

    def current_points(vertices)
      vertices.filter_map { |vertex| vertex.position if vertex.valid? }
    end

    def rebuild_isolated_curve(entry)
      return false if entry[:full_move]
      return false unless curve_rebuildable?(entry)

      points = current_points(entry[:vertices])
      return false if points.length < 2

      edges = entry[:entities].add_curve(points)
      edges && !edges.empty?
    rescue => error
      warn "MH Stretch curve restore failed: #{error.class}: #{error.message}"
      false
    end

    def curve_rebuildable?(entry)
      edge_keys = entry[:edge_keys]
      interior = entry[:vertices][1...-1] || []
      interior.all? do |vertex|
        vertex.valid? && vertex.edges.all? { |edge| edge_keys.include?(edge_key(edge)) }
      end
    rescue
      false
    end

    def vertex_key(vertex)
      return vertex.persistent_id if vertex.respond_to?(:persistent_id)

      vertex.object_id
    rescue
      vertex.object_id
    end

    def edge_key(edge)
      return edge.persistent_id if edge.respond_to?(:persistent_id)

      edge.object_id
    rescue
      edge.object_id
    end

    def result(ok, changed, message)
      { ok: ok, changed: changed, message: message }
    end
  end
end
end

