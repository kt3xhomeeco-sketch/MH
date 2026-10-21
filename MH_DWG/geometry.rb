# frozen_string_literal: true

module MH
  # Normalizes unused imported roots and collects placement anchor candidates.
  module DWG
    def self.import_options
      { preserve_origin: false }
    end

    def self.normalize_definition_origin(defn, model)
      offset = unused_definition_origin(defn)
      if origin_normalized?(offset)
        log_event('paste.origin_already_normalized', bounds_min: point_log(offset))
        return
      end
      normalize_shifted_definition(defn, model, offset)
    end

    def self.normalize_shifted_definition(defn, model, offset)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      log_event('paste.before_normalize_origin', defn: definition_summary(defn))
      with_origin_operation(model) { translate_definition_origin(defn, offset) }
      log_normalized_definition(defn, offset, started_at)
    end

    def self.with_origin_operation(model)
      raise 'Không mở được operation chuẩn hóa CAD.' unless model.start_operation('Chuẩn Hóa Gốc CAD', true)

      operation_open = true
      yield
      model.commit_operation
      operation_open = false
    rescue StandardError
      model.abort_operation if operation_open
      raise
    end

    def self.log_normalized_definition(defn, offset, started_at)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      log_event('paste.after_normalize_origin', original_min: point_log(offset),
                                                defn: definition_summary(defn), duration_ms: duration_ms)
    end

    def self.unused_definition_origin(definition)
      # Never move shared child definitions or a root that already has instances.
      raise 'Không chuẩn hóa CAD đã có instance trong model.' unless definition.instances.empty?

      bounds = definition.bounds
      raise 'CAD không có bounds hợp lệ.' if bounds.empty?

      offset = bounds.min
      raise 'Tọa độ CAD không hợp lệ.' unless [offset.x, offset.y, offset.z].all? { |value| value.to_f.finite? }

      offset
    end

    def self.origin_normalized?(point)
      [point.x, point.y, point.z].all? { |value| value.to_f.finite? && value.to_f.abs <= 1.0e-6 }
    end

    def self.translate_definition_origin(definition, offset)
      entities = definition.entities
      result = entities.transform_entities(origin_translation(offset), entities.to_a)
      raise 'Không dịch được hình học CAD về gốc.' unless result

      definition.invalidate_bounds
      validate_normalized_bounds(definition.bounds)
    end

    def self.origin_translation(offset)
      Geom::Transformation.translation(Geom::Point3d.new(-offset.x, -offset.y, -offset.z))
    end

    def self.validate_normalized_bounds(bounds)
      raise 'Bounds CAD rỗng sau chuẩn hóa.' if bounds.empty?
      raise 'Gốc CAD chưa chuẩn hóa; dừng đặt để tránh dùng tọa độ cũ.' unless origin_normalized?(bounds.min)
    end

    def self.placement_anchor_points(defn)
      bounds = defn.bounds
      base_point = bounds.empty? ? ORIGIN : bounds.min
      alternatives = find_all_vertices_on_x_axis(defn.entities)
      [base_point] + alternatives.reject { |point| point == base_point }
    end

    # Retained for external Ruby callers, although default placement uses all anchors.
    def self.find_vertex_on_x_axis(entities)
      candidates = anchor_candidates(entities)
      on_axis = vertices_on_x_axis(candidates)
      on_axis.min_by(&:x) || nearest_x_axis_point(candidates)
    end

    def self.find_all_vertices_on_x_axis(entities)
      candidates = anchor_candidates(entities)
      on_axis = vertices_on_x_axis(candidates)
      return [nearest_x_axis_point(candidates)] if on_axis.empty?

      on_axis.uniq { |point| point.x.round(2) }.sort_by(&:x)
    end

    def self.anchor_candidates(entities)
      entities.flat_map { |entity| entity_anchor_candidates(entity) }
    end

    def self.entity_anchor_candidates(entity)
      case entity
      when Sketchup::Edge then [entity.start.position, entity.end.position]
      when Sketchup::Face then entity.vertices.map(&:position)
      when Sketchup::ComponentInstance, Sketchup::Group then bounds_corners(entity.bounds)
      else []
      end
    end

    def self.bounds_corners(bounds)
      bounds.empty? ? [] : Array.new(8) { |index| bounds.corner(index) }
    end

    def self.vertices_on_x_axis(candidates)
      candidates.select { |point| point.y.abs < 0.1 && point.z.abs < 0.1 }
    end

    def self.nearest_x_axis_point(candidates)
      candidates.min_by { |point| point.y.abs + point.z.abs } || ORIGIN
    end
  end
end
