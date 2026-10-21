# encoding: UTF-8

require 'set'

module MH
  # Immutable feature cache and inverted/range indexes for entity matching.
  # SketchUp API access is kept in Ruby; repeated candidate comparisons operate
  # only on cached values and small indexed candidate sets.
  class SimilarityIndex
    Feature = Struct.new(:entity, :dimensions, :material, :tag, :type, :name, :volume)

    attr_reader :entities, :features

    def initialize(entities, dimensions:, material:, tag:, name: nil)
      @entities = Array(entities).freeze
      @dimensions_reader = dimensions
      @material_reader = material
      @tag_reader = tag
      @name_reader = name
      @features = {}
      @by_material = Hash.new { |hash, key| hash[key] = [] }
      @by_tag = Hash.new { |hash, key| hash[key] = [] }
      @by_type = Hash.new { |hash, key| hash[key] = [] }
      @dimensions = Array.new(3) { [] }
      @volumes = []
      @without_dimensions = []

      @entities.each do |entity|
        dims = safe_call(dimensions, entity)
        dims = Array(dims).map(&:to_f).sort if dims && Array(dims).length == 3
        dims = nil unless dims && dims.all? { |value| value.finite? && value >= 0.0 }
        feature = Feature.new(
          entity,
          dims,
          safe_call(material, entity),
          safe_call(tag, entity),
          entity_type(entity),
          name ? safe_call(name, entity).to_s : nil,
          dims ? dims.reduce(1.0, :*) : nil
        )
        @features[entity] = feature
        @by_material[feature.material] << entity
        @by_tag[feature.tag] << entity
        @by_type[feature.type] << entity
        if dims
          3.times { |index| @dimensions[index] << [dims[index], entity] }
          @volumes << [feature.volume, entity]
        else
          @without_dimensions << entity
        end
      end

      @dimensions.each { |rows| rows.sort_by!(&:first) }
      @volumes.sort_by!(&:first)
    end

    def feature(entity)
      @features[entity]
    end

    # Returns a conservative superset. The caller should retain its exact
    # matcher as the final authority, especially for advanced name formulas.
    def candidates(reference, settings)
      ref = feature(reference)
      ref ||= transient_feature(reference)
      return @entities.dup unless ref

      result = nil
      result = intersect(result, @by_type[settings[:type_filter].to_s.to_sym]) if %w[group component].include?(settings[:type_filter].to_s)
      result = intersect(result, @by_material[ref.material]) if settings[:same_material]
      result = intersect(result, @by_tag[ref.tag]) if settings[:same_tag]

      dims = ref.dimensions
      if dims
        if settings[:min_thickness]
          tolerance = settings[:thickness_tolerance].to_f / 25.4
          result = intersect(result, range(@dimensions[0], dims[0] - tolerance, dims[0] + tolerance))
        end

        if settings[:bounding_size]
          tolerance = settings[:size_tolerance].to_f / 100.0
          middle = range_any_dimension(dims[1], tolerance)
          largest = range_any_dimension(dims[2], tolerance)
          size_candidates = case settings[:size_mode].to_i
                            when 0 then middle
                            when 1 then largest
                            when 2 then intersect(middle, largest)
                            when 3 then union(middle, largest)
                            else middle
                            end
          result = intersect(result, size_candidates)
        end

        if settings[:bounding_volume]
          low, high = relative_range(ref.volume, settings[:volume_tolerance].to_f / 100.0)
          result = intersect(result, range(@volumes, low, high))
        end
      end

      result ? result.to_a : @entities.dup
    end

    private

    def transient_feature(entity)
      dims = safe_call(@dimensions_reader, entity)
      dims = Array(dims).map(&:to_f).sort if dims && Array(dims).length == 3
      dims = nil unless dims && dims.all? { |value| value.finite? && value >= 0.0 }
      Feature.new(
        entity,
        dims,
        safe_call(@material_reader, entity),
        safe_call(@tag_reader, entity),
        entity_type(entity),
        @name_reader ? safe_call(@name_reader, entity).to_s : nil,
        dims ? dims.reduce(1.0, :*) : nil
      )
    end

    def safe_call(callable, entity)
      return nil unless callable

      callable.call(entity)
    rescue StandardError
      nil
    end

    def entity_type(entity)
      return :group if defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)
      return :component if defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance)

      :other
    end

    def intersect(left, right)
      right = right.is_a?(Set) ? right : Set.new(Array(right))
      left ? left.intersection(right) : right
    end

    def union(left, right)
      to_set(left).union(to_set(right))
    end

    def to_set(value)
      value.is_a?(Set) ? value : Set.new(Array(value))
    end

    def range_any_dimension(value, tolerance)
      low, high = relative_range(value, tolerance)
      @dimensions.reduce(Set.new(@without_dimensions)) { |set, rows| set.union(range(rows, low, high)) }
    end

    # Existing Select Similar tolerance is |a-b| / max(a,b) <= tolerance.
    def relative_range(value, tolerance)
      value = value.to_f
      tolerance = [[tolerance.to_f, 0.0].max, 0.999_999].min
      [value * (1.0 - tolerance), value / (1.0 - tolerance)]
    end

    def range(rows, low, high)
      first = lower_bound(rows, low)
      last = upper_bound(rows, high)
      Set.new(@without_dimensions).union(rows[first...last].to_a.map(&:last))
    end

    def lower_bound(rows, value)
      left = 0
      right = rows.length
      while left < right
        middle = (left + right) / 2
        rows[middle][0] < value ? left = middle + 1 : right = middle
      end
      left
    end

    def upper_bound(rows, value)
      left = 0
      right = rows.length
      while left < right
        middle = (left + right) / 2
        rows[middle][0] <= value ? left = middle + 1 : right = middle
      end
      left
    end
  end
end
