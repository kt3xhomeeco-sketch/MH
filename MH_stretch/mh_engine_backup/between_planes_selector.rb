# encoding: UTF-8

module MH
module Stretch
  # Selects only geometry inside a closed interval on one model axis.
  # This is intentionally separate from PlaneVertexSelector so the legacy
  # one-sided/multi-plane stretch behavior remains untouched.
  module BetweenPlanesSelector
    DEFAULT_CLEARANCE = PlaneVertexSelector::DEFAULT_CLEARANCE

    module_function

    def select(model, axis:, min_pos:, max_pos:, clearance: DEFAULT_CLEARANCE)
      result = {
        vertex_buckets: {},
        containers: [],
        origin_containers: [],
        curves: {}
      }
      return finalize(result) unless valid_interval?(min_pos, max_pos, clearance)

      seen = {}
      seen_curves = {}
      identity = Geom::Transformation.new
      model.selection.each do |entity|
        if PlaneVertexSelector.group_or_component?(entity)
          classify_and_collect_container(entity, identity, axis, min_pos, max_pos, clearance, result, seen, seen_curves)
        elsif entity.is_a?(Sketchup::Edge)
          collect_edge(PlaneVertexSelector.parent_entities_for(model, entity), entity, identity, axis, min_pos, max_pos, clearance, result, seen, seen_curves)
        elsif entity.is_a?(Sketchup::Face)
          collect_vertices(PlaneVertexSelector.parent_entities_for(model, entity), entity.vertices, identity, axis, min_pos, max_pos, clearance, result, seen)
        end
      end
      finalize(result)
    end

    def in_moving_zone?(point, axis, min_pos, max_pos, clearance = DEFAULT_CLEARANCE)
      value = PlaneVertexSelector.axis_value(point, axis)
      value >= min_pos.to_f + clearance.to_f && value <= max_pos.to_f - clearance.to_f
    end

    def valid_interval?(min_pos, max_pos, clearance = DEFAULT_CLEARANCE)
      max_pos.to_f - min_pos.to_f > clearance.to_f * 2.0
    end

    def finalize(result)
      result[:vertex_buckets] = result[:vertex_buckets].values
      result[:curves] = result[:curves].values
      result
    end

    def collect_entities(entities, parent_to_world, axis, min_pos, max_pos, clearance, result, seen, seen_curves)
      entities.each do |entity|
        if entity.is_a?(Sketchup::Edge)
          collect_edge(entities, entity, parent_to_world, axis, min_pos, max_pos, clearance, result, seen, seen_curves)
        elsif PlaneVertexSelector.group_or_component?(entity)
          classify_and_collect_container(entity, parent_to_world, axis, min_pos, max_pos, clearance, result, seen, seen_curves)
        end
      end
    end

    def classify_and_collect_container(entity, parent_to_world, axis, min_pos, max_pos, clearance, result, seen, seen_curves)
      child_to_world = parent_to_world * entity.transformation
      case classify_bounds(entity, child_to_world, axis, min_pos, max_pos, clearance)
      when :moving
        result[:containers] << { entity: entity, parent_to_world: parent_to_world }
      when :crossing
        if origin_in_moving_zone?(child_to_world, axis, min_pos, max_pos, clearance)
          result[:origin_containers] << {
            entity: entity,
            parent_to_world: parent_to_world,
            child_to_world: child_to_world
          }
        end
        collect_entities(PlaneVertexSelector.child_entities(entity), child_to_world, axis, min_pos, max_pos, clearance, result, seen, seen_curves)
      end
    end

    def collect_edge(entities, edge, parent_to_world, axis, min_pos, max_pos, clearance, result, seen, seen_curves)
      curve = edge.curve
      if curve
        collect_curve(entities, curve, parent_to_world, axis, min_pos, max_pos, clearance, result, seen_curves)
      else
        collect_vertices(entities, edge.vertices, parent_to_world, axis, min_pos, max_pos, clearance, result, seen)
      end
    end

    def collect_curve(entities, curve, parent_to_world, axis, min_pos, max_pos, clearance, result, seen_curves)
      key = PlaneVertexSelector.curve_key(curve)
      return if seen_curves[key]

      seen_curves[key] = true
      vertices = curve.vertices.select do |vertex|
        in_moving_zone?(vertex.position.transform(parent_to_world), axis, min_pos, max_pos, clearance)
      end
      return if vertices.empty?

      result[:curves][key] = {
        entities: entities,
        curve: curve,
        vertices: vertices,
        all_vertices_count: curve.vertices.length,
        parent_to_world: parent_to_world
      }
    rescue
      nil
    end

    def collect_vertices(entities, vertices, parent_to_world, axis, min_pos, max_pos, clearance, result, seen)
      vertices.each do |vertex|
        next if PlaneVertexSelector.vertex_on_curve?(vertex)

        key = PlaneVertexSelector.vertex_key(vertex)
        next if seen[key]
        next unless in_moving_zone?(vertex.position.transform(parent_to_world), axis, min_pos, max_pos, clearance)

        seen[key] = true
        bucket = result[:vertex_buckets][entities.object_id] ||= {
          entities: entities,
          vertices: [],
          parent_to_world: parent_to_world
        }
        bucket[:vertices] << vertex
      end
    end

    def origin_in_moving_zone?(entity_to_world, axis, min_pos, max_pos, clearance)
      origin = Geom::Point3d.new(0, 0, 0).transform(entity_to_world)
      in_moving_zone?(origin, axis, min_pos, max_pos, clearance)
    rescue
      false
    end

    def classify_bounds(entity, entity_to_world, axis, min_pos, max_pos, clearance)
      values = (0..7).map do |index|
        point = PlaneVertexSelector.local_bounds_for(entity).corner(index).transform(entity_to_world)
        PlaneVertexSelector.axis_value(point, axis)
      end
      lower = min_pos.to_f + clearance.to_f
      upper = max_pos.to_f - clearance.to_f
      return :moving if values.all? { |value| value >= lower && value <= upper }
      return :static if values.all? { |value| value < lower } || values.all? { |value| value > upper }

      :crossing
    rescue
      :crossing
    end
  end
end
end
