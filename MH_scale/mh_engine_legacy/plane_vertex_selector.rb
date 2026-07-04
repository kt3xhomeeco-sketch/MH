# encoding: UTF-8

module MH
module Scale
  module PlaneVertexSelector
    DEFAULT_CLEARANCE = 0.1.mm

    module_function

    def select(model, axis:, side:, plane_pos:, clearance: DEFAULT_CLEARANCE)
      result = {
        vertex_buckets: {},
        containers: [],
        origin_containers: [],
        curves: {}
      }
      seen = {}
      seen_curves = {}
      identity = Geom::Transformation.new

      model.selection.each do |entity|
        if group_or_component?(entity)
          classify_and_collect_container(entity, identity, axis, side, plane_pos, clearance, result, seen, seen_curves)
        elsif entity.is_a?(Sketchup::Edge)
          collect_edge(parent_entities_for(model, entity), entity, identity, axis, side, plane_pos, clearance, result, seen, seen_curves)
        elsif entity.is_a?(Sketchup::Face)
          collect_vertices(parent_entities_for(model, entity), entity.vertices, identity, axis, side, plane_pos, clearance, result, seen)
        end
      end

      result[:vertex_buckets] = result[:vertex_buckets].values
      result[:curves] = result[:curves].values
      result
    end

    def make_selection_unique(selection)
      selection.each do |entity|
        make_container_tree_unique(entity) if group_or_component?(entity)
      end
    end

    def world_delta(axis, amount)
      case axis
      when :x then Geom::Vector3d.new(amount.to_f, 0, 0)
      when :y then Geom::Vector3d.new(0, amount.to_f, 0)
      else Geom::Vector3d.new(0, 0, amount.to_f)
      end
    end

    def axis_value(point, axis)
      BoxModel.axis_value(point, axis)
    end

    def in_moving_zone?(point, axis, side, plane_pos, clearance)
      value = axis_value(point, axis)
      if side == :minus
        value <= plane_pos.to_f - clearance.to_f
      else
        value >= plane_pos.to_f + clearance.to_f
      end
    end

    def collect_entities(entities, parent_to_world, axis, side, plane_pos, clearance, result, seen, seen_curves)
      entities.each do |entity|
        if entity.is_a?(Sketchup::Edge)
          collect_edge(entities, entity, parent_to_world, axis, side, plane_pos, clearance, result, seen, seen_curves)
        elsif group_or_component?(entity)
          classify_and_collect_container(entity, parent_to_world, axis, side, plane_pos, clearance, result, seen, seen_curves)
        end
      end
    end

    def classify_and_collect_container(entity, parent_to_world, axis, side, plane_pos, clearance, result, seen, seen_curves)
      child_to_world = parent_to_world * entity.transformation
      case classify_bounds(entity, child_to_world, axis, side, plane_pos, clearance)
      when :moving
        result[:containers] << {
          entity: entity,
          parent_to_world: parent_to_world
        }
      when :crossing
        if origin_in_moving_zone?(child_to_world, axis, side, plane_pos, clearance)
          result[:origin_containers] << {
            entity: entity,
            parent_to_world: parent_to_world,
            child_to_world: child_to_world
          }
        end
        collect_entities(child_entities(entity), child_to_world, axis, side, plane_pos, clearance, result, seen, seen_curves)
      end
    end

    def collect_edge(entities, edge, parent_to_world, axis, side, plane_pos, clearance, result, seen, seen_curves)
      curve = edge.curve
      if curve
        collect_curve(entities, curve, parent_to_world, axis, side, plane_pos, clearance, result, seen_curves)
      else
        collect_vertices(entities, edge.vertices, parent_to_world, axis, side, plane_pos, clearance, result, seen)
      end
    end

    def collect_curve(entities, curve, parent_to_world, axis, side, plane_pos, clearance, result, seen_curves)
      key = curve_key(curve)
      return if seen_curves[key]

      seen_curves[key] = true
      moving_vertices = curve.vertices.select do |vertex|
        world = vertex.position.transform(parent_to_world)
        in_moving_zone?(world, axis, side, plane_pos, clearance)
      end
      return if moving_vertices.empty?

      result[:curves][key] = {
        entities: entities,
        curve: curve,
        vertices: moving_vertices,
        all_vertices_count: curve.vertices.length,
        parent_to_world: parent_to_world
      }
    rescue
      nil
    end

    def origin_in_moving_zone?(entity_to_world, axis, side, plane_pos, clearance)
      origin = Geom::Point3d.new(0, 0, 0).transform(entity_to_world)
      in_moving_zone?(origin, axis, side, plane_pos, clearance)
    rescue
      false
    end

    def classify_bounds(entity, entity_to_world, axis, side, plane_pos, clearance)
      values = local_bounds_for(entity).then do |bounds|
        (0..7).map { |index| axis_value(bounds.corner(index).transform(entity_to_world), axis) }
      end
      threshold =
        if side == :minus
          plane_pos.to_f - clearance.to_f
        else
          plane_pos.to_f + clearance.to_f
        end

      if side == :minus
        return :moving if values.all? { |value| value <= threshold }
        return :static if values.all? { |value| value > threshold }
      else
        return :moving if values.all? { |value| value >= threshold }
        return :static if values.all? { |value| value < threshold }
      end

      :crossing
    rescue
      :crossing
    end

    def collect_vertices(entities, vertices, parent_to_world, axis, side, plane_pos, clearance, result, seen)
      vertices.each do |vertex|
        next if vertex_on_curve?(vertex)

        key = vertex_key(vertex)
        next if seen[key]

        world = vertex.position.transform(parent_to_world)
        next unless in_moving_zone?(world, axis, side, plane_pos, clearance)

        seen[key] = true
        bucket_key = entities.object_id
        bucket = result[:vertex_buckets][bucket_key] ||= {
          entities: entities,
          vertices: [],
          parent_to_world: parent_to_world
        }
        bucket[:vertices] << vertex
      end
    end

    def make_container_tree_unique(entity)
      entity.make_unique if needs_unique?(entity)
      child_entities(entity).each do |child|
        make_container_tree_unique(child) if group_or_component?(child)
      end
    rescue
      nil
    end

    def group_or_component?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def child_entities(entity)
      entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
    end

    def local_bounds_for(entity)
      if entity.is_a?(Sketchup::Group)
        entity.local_bounds
      else
        entity.definition.bounds
      end
    end

    def parent_entities_for(model, entity)
      parent = entity.parent
      return parent if parent.is_a?(Sketchup::Entities)

      model.active_entities
    rescue
      model.active_entities
    end

    def needs_unique?(entity)
      return false unless entity.respond_to?(:definition)

      entity.definition.instances.length > 1
    rescue
      false
    end

    def vertex_key(vertex)
      return vertex.persistent_id if vertex.respond_to?(:persistent_id)

      vertex.object_id
    rescue
      vertex.object_id
    end

    def curve_key(curve)
      return curve.persistent_id if curve.respond_to?(:persistent_id)

      curve.object_id
    rescue
      curve.object_id
    end

    def vertex_on_curve?(vertex)
      vertex.edges.any? { |edge| edge.curve }
    rescue
      false
    end
  end
end
end
