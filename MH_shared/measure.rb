# encoding: UTF-8

require 'sketchup'

module MH
  module Measure
    LENGTH_SOURCE_LONGEST_EDGE = 'longest_edge'.freeze

    module_function

    def live_entity?(entity)
      entity && !(entity.respond_to?(:deleted?) && entity.deleted?)
    rescue
      false
    end

    def container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def target_entities(entity)
      return nil unless live_entity?(entity)
      return entity.entities if entity.is_a?(Sketchup::Group)
      return entity.definition.entities if entity.is_a?(Sketchup::ComponentInstance) && entity.definition
      return entity if entity.is_a?(Sketchup::Entities)
      return entity.entities if entity.is_a?(Sketchup::ComponentDefinition)

      nil
    rescue
      nil
    end

    # Tìm world transform của target trong model hiện tại.
    # Nếu caller đã có transform chính xác, truyền trực tiếp vào các hàm đo để tránh scan model.
    def entity_world_transform(target, model = Sketchup.active_model)
      return IDENTITY unless target
      return target.transformation if model && target.respond_to?(:parent) && target.parent == model.entities && target.respond_to?(:transformation)

      found = nil
      visited = {}

      finder = lambda do |entities, parent_transform|
        return if found || !entities

        entities.each do |entity|
          next unless container?(entity)

          transform = parent_transform * entity.transformation
          if entity == target
            found = transform
            return
          end

          child_entities = target_entities(entity)
          next unless child_entities

          key = child_entities.object_id
          next if visited[key]

          visited[key] = true
          finder.call(child_entities, transform)
          return if found
        end
      end

      finder.call(model.entities, IDENTITY) if model
      found || (target.respond_to?(:transformation) ? target.transformation : IDENTITY)
    rescue
      IDENTITY
    end

    # Longest dimension của target trong world-space, trả về inch nội bộ SketchUp.
    def target_longest_dimension(target, world_transform = nil)
      bounds = target_world_bounds(target, world_transform)
      return 0.0 unless bounds && bounds.valid?

      [
        bounds.max.x - bounds.min.x,
        bounds.max.y - bounds.min.y,
        bounds.max.z - bounds.min.z
      ].map(&:to_f).max || 0.0
    rescue
      0.0
    end

    # Longest dimension của target trong world-space, trả về mm.
    # Tách từ MH_PK_Addon.target_longest_dimension_mm để các app khác dùng chung.
    def target_longest_dimension_mm(target, world_transform = nil, precision: 1)
      (target_longest_dimension(target, world_transform).to_f * 25.4).round(precision)
    rescue
      0.0
    end

    def target_world_bounds(target, world_transform = nil)
      entities = target_entities(target)
      return bounds_for_entity(target, world_transform || IDENTITY) unless entities

      transform = world_transform || entity_world_transform(target)
      bounds = Geom::BoundingBox.new
      has_any = false

      entities.each do |entity|
        next unless entity && entity.respond_to?(:bounds)

        entity_bounds = entity.bounds rescue nil
        next unless entity_bounds && entity_bounds.valid?

        add_bounds_corners(bounds, entity_bounds, transform)
        has_any = true
      end

      has_any ? bounds : nil
    rescue
      nil
    end

    def bounds_for_entity(entity, transform = IDENTITY)
      return nil unless entity && entity.respond_to?(:bounds)

      source = entity.bounds rescue nil
      return nil unless source && source.valid?

      bounds = Geom::BoundingBox.new
      add_bounds_corners(bounds, source, transform || IDENTITY)
      bounds
    rescue
      nil
    end

    def add_bounds_corners(target_bounds, source_bounds, transform = IDENTITY)
      8.times do |index|
        target_bounds.add(source_bounds.corner(index).transform(transform || IDENTITY))
      end
      target_bounds
    end

    # Đọc tổng length_mm từ row Excel/JSON.
    # Giữ tương thích với MH_PK_Addon.excel_row_length_mm.
    def excel_row_length_mm(row, precision: 1)
      raw = row.is_a?(Hash) ? (row[:raw] || row['raw'] || row) : row
      return 0.0 unless raw.is_a?(Hash)

      direct = (raw['length_mm'] || raw[:length_mm]).to_f
      return direct.round(precision) if direct > 0

      items = Array(raw['length_items'] || raw[:length_items])
      total = items.sum do |item|
        if item.is_a?(Hash)
          (item['length_mm'] || item[:length_mm] || item['mm'] || item[:mm] || item['length'] || item[:length]).to_f
        else
          item.to_f
        end
      end
      total.round(precision)
    rescue
      0.0
    end
  end
end
