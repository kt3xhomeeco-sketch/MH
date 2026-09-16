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
            collect_material(entity.material, product)
            collect_material(entity.back_material, product)
            next
          end
          text = ProductContext.text_for_entity(entity)
          code = @code_cache.fetch(text) do
            @code_cache[text] = ProductContext.base(ProductContext.code_from_entity(entity))
          end
          next_product = code.empty? ? product : code
          world = transform * entity.transformation
          path = definitions.map { |entry| entry[1] } + [entity]
          if !code.empty? && code != product
            bounds = entity.definition.bounds
            @items << { code: code, path: path, points: (0..7).map { |i| bounds.corner(i).transform(world) } }
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
