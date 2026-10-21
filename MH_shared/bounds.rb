# encoding: UTF-8

module MH
  module Bounds
    module_function

    @dims_cache = {}

    def clear!
      @dims_cache = {}
    end

    def entity_key(entity)
      return nil unless entity
      entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.object_id
    rescue
      entity.object_id
    end

    def valid_entity?(entity)
      entity && (!entity.respond_to?(:valid?) || entity.valid?)
    rescue
      false
    end

    def world(entity, transform = nil)
      return nil unless valid_entity?(entity) && entity.respond_to?(:bounds)
      bounds = entity.bounds
      return nil if bounds.empty?

      tr = transform || Geom::Transformation.new
      bb = Geom::BoundingBox.new
      8.times { |i| bb.add(tr * bounds.corner(i)) }
      bb
    rescue
      nil
    end

    def dims(entity)
      return nil unless valid_entity?(entity)
      key = entity_key(entity)
      return @dims_cache[key] if key && @dims_cache.key?(key)

      value = panel_dimensions_from_faces(entity)
      value ||= scaled_local_dimensions(entity)
      value = value.sort if value
      @dims_cache[key] = value if key
      value
    rescue
      nil
    end

    def content_bounds(entity, reject: nil)
      return nil unless valid_entity?(entity)
      return entity.bounds unless container?(entity)
      return nil if reject && safe_reject?(reject, entity)

      points = []
      collect_content_points(entity, Geom::Transformation.new, points, reject)
      return nil if points.empty?

      bb = Geom::BoundingBox.new
      points.each { |point| bb.add(point) }
      bb
    rescue
      entity.bounds rescue nil
    end

    def scaled_local_dimensions(entity)
      return nil unless valid_entity?(entity)

      bounds = if defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance)
                 entity.definition.bounds
               elsif defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group) && entity.respond_to?(:local_bounds)
                 entity.local_bounds
               elsif entity.respond_to?(:bounds)
                 entity.bounds
               end
      return nil unless bounds && !bounds.empty?

      min = bounds.min
      max = bounds.max
      dims = [max.x - min.x, max.y - min.y, max.z - min.z]
      if entity.respond_to?(:transformation)
        tr = entity.transformation
        scales = [
          Geom::Vector3d.new(tr.xaxis).length,
          Geom::Vector3d.new(tr.yaxis).length,
          Geom::Vector3d.new(tr.zaxis).length
        ]
        dims = dims.each_with_index.map { |d, i| d * scales[i] }
      end
      dims
    rescue
      nil
    end

    def panel_dimensions_from_faces(entity)
      faces = collect_faces(entity)
      return nil if faces.size < 2

      groups = {}
      faces.each do |face|
        normal = face[:normal]
        key = [normal.x.round(4), normal.y.round(4), normal.z.round(4)]
        neg_key = [(-normal.x).round(4), (-normal.y).round(4), (-normal.z).round(4)]
        groups[groups.key?(neg_key) ? neg_key : key] ||= []
        groups[groups.key?(neg_key) ? neg_key : key] << face
      end

      largest_area = 0
      thickness = nil
      panel_face = nil
      groups.each_value do |group_faces|
        next if group_faces.size < 2
        sorted = group_faces.sort_by { |f| -f[:area] }
        next unless sorted[0][:area] > largest_area && sorted[1]

        normal = sorted[0][:normal]
        a = sorted[0][:center]
        b = sorted[1][:center]
        distance = ((a.x - b.x) * normal.x + (a.y - b.y) * normal.y + (a.z - b.z) * normal.z).abs
        next unless distance > 0.001

        largest_area = sorted[0][:area]
        thickness = distance
        panel_face = sorted[0]
      end
      return nil unless thickness && panel_face

      [panel_face[:bounds][:width], panel_face[:bounds][:height], thickness]
    rescue
      nil
    end

    def container?(entity)
      (defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)) ||
        (defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance))
    end

    def child_entities(entity)
      if defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)
        entity.entities
      elsif defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance) && entity.definition
        entity.definition.entities
      else
        []
      end
    rescue
      []
    end

    def collect_content_points(entity, transform, points, reject)
      return unless valid_entity?(entity)
      return if reject && safe_reject?(reject, entity)

      if container?(entity)
        next_transform = transform * entity.transformation
        child_entities(entity).each { |child| collect_content_points(child, next_transform, points, reject) }
        return
      end

      return unless entity.respond_to?(:bounds)
      bounds = entity.bounds
      return if bounds.empty?
      8.times { |i| points << (transform * bounds.corner(i)) }
    rescue
      nil
    end

    def safe_reject?(reject, entity)
      reject.call(entity)
    rescue
      false
    end

    def collect_faces(entity, transform = nil)
      return [] unless valid_entity?(entity)

      transform ||= Geom::Transformation.new
      entities = if defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance)
                   entity.definition.entities
                 elsif defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)
                   entity.entities
                 else
                   return []
                 end
      transform = transform * entity.transformation if entity.respond_to?(:transformation)

      faces = []
      entities.each do |child|
        if defined?(Sketchup::Face) && child.is_a?(Sketchup::Face)
          normal = child.normal.transform(transform)
          normal.normalize!
          corners = (0..7).map { |i| child.bounds.corner(i).transform(transform) }
          xs = corners.map(&:x)
          ys = corners.map(&:y)
          zs = corners.map(&:z)
          extents = [xs.max - xs.min, ys.max - ys.min, zs.max - zs.min].sort
          faces << {
            normal: normal,
            center: child.bounds.center.transform(transform),
            area: child.area,
            bounds: { width: extents[1], height: extents[2] }
          }
        elsif (defined?(Sketchup::Group) && child.is_a?(Sketchup::Group)) ||
              (defined?(Sketchup::ComponentInstance) && child.is_a?(Sketchup::ComponentInstance))
          faces.concat(collect_faces(child, transform))
        end
      end
      faces
    rescue
      []
    end
  end
end
