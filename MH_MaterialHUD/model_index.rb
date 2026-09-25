# encoding: UTF-8
module MH
  module MaterialHUD
    # Build once per model revision, in small UI timer slices. Camera/selection
    # changes only query this index, never traverse the whole model again.
    class ModelIndex
      attr_reader :items, :materials, :complete, :visited

      def initialize(model)
        @items = []
        @materials = Hash.new { |hash, key| hash[key] = {} }
        @code_cache = {}
        @material_cache = {}
        @entity_products = {}
        @view = model.active_view if model.respond_to?(:active_view)
        @spatial_markers = self.class.spatial_markers(model.entities, @view)
        @complete = false
        @visited = 0
        @walker = Enumerator.new do |output|
          walk(model.entities, Geom::Transformation.new, '', [], output)
        end
      end

      def step(budget = 0.008)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + budget
        MaterialCode.with_rules_snapshot do
          while true
            @walker.next
            @visited += 1
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          end
        end
        false
      rescue StopIteration
        @complete = true
      end

      def walk(entities, transform, product, definitions, output)
        entities.each do |entity|
          output << nil
          next unless entity.valid?
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Face)
          if entity.is_a?(Sketchup::Face)
            @entity_products[entity.entityID] = product unless product.empty?
            collect_material(entity.material, product)
            collect_material(entity.back_material, product)
            next
          end
          text = ProductContext.text_for_entity(entity)
          code = @code_cache.fetch(text) do
            @code_cache[text] = ProductContext.base(ProductContext.code_from_entity(entity))
          end
          world = transform * entity.transformation
          inferred = code.empty? && product.empty? ? inferred_product(world_points(entity, world)) : ''
          next_product = code.empty? ? (inferred.empty? ? product : inferred) : code
          path = definitions.map { |entry| entry[1] } + [entity]
          @entity_products[entity.entityID] = next_product unless next_product.empty?
          if (!code.empty? && code != product) || !inferred.empty?
            @items << { code: next_product, path: path, points: world_points(entity, world), inferred: !inferred.empty? }
          end
          collect_material(entity.material, next_product)
          definition = entity.definition
          next if definitions.any? { |entry| entry[0] == definition }
          walk(definition.entities, world, next_product, definitions + [[definition, entity]], output)
        end
      end

      def collect_material(material, product)
        return if material.nil? || product.empty?
        name = material.name.to_s
        return unless self.class.displayable_material_name?(name)
        code = @material_cache[name] ||= Catalog.material_key(name)
        @materials[product][code] = name unless code.empty?
      end

      # Test-only spatial ownership: markers are named 3D Text groups (SP09,
      # SP10, ...). Nothing is written to the model; the result exists only in
      # this HUD index and is recalculated when the index is rebuilt.
      def inferred_product(points)
        return '' if @spatial_markers.empty? || points.empty? || !@view

        screen = @view.screen_coords(average_point(points))
        candidates = @spatial_markers.filter_map do |marker|
          dx = screen.x.to_f - marker[:x]
          dy = marker[:y] - screen.y.to_f
          next if dy <= 0

          distance = Math.sqrt(dx * dx + dy * dy)
          radius = marker[:radius]
          next if distance > radius
          # The label owns a forward-facing wedge, not the whole circle. This
          # rejects nearby details that sit beside/below a different marker.
          next if dx.abs > dy * 1.25 + marker[:width] * 0.5

          marker.merge(distance: distance)
        end
        return '' if candidates.empty?

        candidates.sort_by! { |entry| entry[:distance] }
        first, second = candidates[0], candidates[1]
        # A component nearly equidistant to two labels remains unassigned for
        # review instead of being silently attached to the wrong product.
        return '' if second && (second[:distance] - first[:distance]).abs < [first[:width], second[:width]].min * 0.15

        first[:code]
      rescue
        ''
      end

      def products_for_entities(entities)
        Array(entities).filter_map { |entity| @entity_products[entity.entityID] if entity.respond_to?(:entityID) }
          .uniq.sort_by { |code| ProductContext.sort_key(code) }
      rescue
        []
      end

      # PickHelper retains the full container path for a clicked face/component.
      # Prefer the first mapped ancestor: it is the actual group instance in
      # the model, while a nested definition entity can be shared by several
      # products and therefore has no reliable standalone owner.
      def products_for_entity_path(path)
        Array(path).each do |entity|
          next unless entity.respond_to?(:entityID)
          code = @entity_products[entity.entityID].to_s
          return [code] unless code.empty?
        end
        []
      rescue
        []
      end

      def world_points(entity, transform)
        bounds = if entity.respond_to?(:definition) && entity.definition
          entity.definition.bounds
        elsif entity.respond_to?(:bounds)
          entity.bounds
        end
        return [] unless bounds && !bounds.empty?

        (0..7).map { |index| bounds.corner(index).transform(transform) }
      rescue
        []
      end

      def average_point(points)
        size = points.length.to_f
        Geom::Point3d.new(
          points.sum(&:x) / size,
          points.sum(&:y) / size,
          points.sum(&:z) / size
        )
      end

      def self.spatial_markers(entities, view)
        return [] unless entities && view

        entities.to_a.filter_map do |entity|
          next unless entity.valid?
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

          code = ProductContext.base(ProductContext.code_from_entity(entity))
          definition_name = entity.respond_to?(:definition) && entity.definition ? entity.definition.name.to_s : ''
          # The first native 3D Text definition is named "Text"; every later
          # copy becomes "Text#1", "Text#2", ... . Both are product markers.
          next if code.empty? || definition_name !~ /\AText(?:#|\z)/i

          points = begin
            # Entity#bounds is already expressed in model coordinates. Applying
            # entity.transformation here moves a label twice and makes nearby
            # details appear to belong to a different SP marker.
            bounds = entity.bounds
            (0..7).map { |index| bounds.corner(index) }
          rescue
            []
          end
          next if points.empty?

          screen = points.map { |point| view.screen_coords(point) }
          xs = screen.map(&:x)
          ys = screen.map(&:y)
          width = xs.max.to_f - xs.min.to_f
          height = ys.max.to_f - ys.min.to_f
          next if width <= 0 || height <= 0

          { code: code, x: (xs.min + xs.max) * 0.5, y: (ys.min + ys.max) * 0.5,
            width: width, radius: [width * 3.0, height * 4.0, 120.0].max }
        end
      rescue
        []
      end

      # SketchUp may expose a painted face with an auto-generated color such
      # as #FFFFFF. It is a display color, not a material code, so it must not
      # become a "NO SPEC" line in the HUD.
      def self.displayable_material_name?(value)
        name = value.to_s.strip
        return false if name.empty?
        return false if name =~ /\A(?:white|red|black|green|blue|yellow|gr[ae]y|<auto>\d*|\[.*\]|color_[0-9a-f]+)\z/i
        return false if name =~ /\A#[0-9a-f]{3,8}\z/i
        return false if name =~ /\Argba?\([^)]*\)\z/i

        true
      end

      def visible_products(view)
        width, height = view.vpwidth.to_f, view.vpheight.to_f
        eye, direction = view.camera.eye, view.camera.direction
        scores = Hash.new(0.0)
        @items.each do |item|
          next unless item[:path].all? { |entity| entity.valid? && !entity.hidden? && entity.layer.visible? }
          points = item[:points].select { |point| (point - eye).dot(direction) > 0 }
          next if points.empty?
          screen = points.map { |point| view.screen_coords(point) }
          left, right = screen.map(&:x).minmax
          top, bottom = screen.map(&:y).minmax
          # Same central 80% focus region as the former HUD.
          overlap_x = [right, width * 0.9].min - [left, width * 0.1].max
          overlap_y = [bottom, height * 0.9].min - [top, height * 0.1].max
          scores[item[:code]] += overlap_x * overlap_y if overlap_x > 0 && overlap_y > 0
        end
        scores.sort_by { |code, score| [-score, ProductContext.sort_key(code)] }.first(6).map(&:first).sort_by { |code| ProductContext.sort_key(code) }
      end
    end
  end
end
