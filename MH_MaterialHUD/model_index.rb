# encoding: UTF-8
module MH
  module MaterialHUD
    # Build once per model revision, in small UI timer slices. Camera/selection
    # changes only query this index, never traverse the whole model again.
    class ModelIndex
      attr_reader :items, :materials, :complete, :visited, :used_definitions, :used_materials

      def initialize(model, products: nil, roots: nil, definition_cache: nil)
        @model = model
        @requested_products = products && Array(products).each_with_object({}) { |code, memo| memo[ProductContext.base(code)] = true }
        @items = []
        @materials = Hash.new { |hash, key| hash[key] = {} }
        @code_cache = {}
        @material_cache = {}
        @product_base_cache = {}
        @spatial_product_cache = {}
        @nested_definition_cache = {}
        @definition_cache = definition_cache
        @used_definitions = {}
        @used_materials = {}
        @entity_products = {}
        @descendant_products = Hash.new { |hash, key| hash[key] = {} }
        @view = model.active_view if model.respond_to?(:active_view)
        @spatial_markers = ProductContext.spatial_markers(model, @view)
        @complete = false
        @visited = 0
        @walker = Enumerator.new do |output|
          walk(roots || model.entities, Geom::Transformation.new, '', [], output)
        end
      end

      def step(budget = 0.008)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + budget
        # A pan/zoom between timer slices changes screen coordinates, but not
        # ownership in parallel view. Keep markers aligned with this slice.
        markers = ProductContext.spatial_markers(@model, @view)
        @spatial_product_cache.clear unless markers.equal?(@spatial_markers)
        @spatial_markers = markers
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
          if @requested_products
            # Walk containers to preserve nested/renamed product ownership,
            # but never inspect another product's faces, edges or ABF geometry.
            next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) ||
              (entity.is_a?(Sketchup::Face) && requested_product?(product))
          end
          output << nil
          next unless entity.valid?
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Face)
          if entity.is_a?(Sketchup::Face)
            @entity_products[entity.entityID] = product unless product.empty?
            record_descendant_product(product, definitions)
            collect_material(entity.material, product)
            collect_material(entity.back_material, product)
            next
          end
          code = @requested_products ? '' : product_code_for_entity(entity)
          next if ProductContext.spatial_annotation_entity?(entity)
          world = transform * entity.transformation
          definition = entity.definition
          # Cụm chi tiết theo X đỏ quyết định SP; không dùng vùng camera.
          resolved_product, _resolved_world, inferred = ProductContext.resolve_instance_product(
            entity,
            inherited_product: product,
            world_transform: world,
            model: @model,
            view: @view,
            markers: @spatial_markers,
            spatial_product: spatial_product_for_instance(entity, world)
          )
          next_product = @product_base_cache[resolved_product] ||= resolved_product.include?('|') ? resolved_product : ProductContext.base(resolved_product)
          if @requested_products && !requested_product?(next_product) &&
             !inferred.empty? && definition_has_containers?(definition) &&
             unrequested_spatial_subtree?(entity, world, next_product)
            next
          end
          named_code = @requested_products ? '' : instance_name_product_code(entity)
          explicit_rename = !named_code.empty? &&
            (code.empty? || ProductContext.base(named_code) != ProductContext.base(code))
          path = definitions.map { |entry| entry[1] } + [entity]
          @entity_products[entity.entityID] = next_product unless next_product.empty?
          record_descendant_product(next_product, definitions)
          if !@requested_products && ((!code.empty? && code != product) || !inferred.empty? || explicit_rename)
            ProductContext.spatial_product_codes(next_product).each do |child_code|
              @items << { code: child_code, path: path, points: world_points(entity, world), inferred: !inferred.empty? }
            end
          end
          collect_material(entity.material, next_product)
          next if definitions.any? { |entry| entry[0] == definition }
          @used_definitions[definition] = true
          if @definition_cache
            summary = @definition_cache.fetch(definition, output)
            summary[:materials].each { |material| collect_material(material, next_product) }
            summary[:faces].each_with_index do |face, position|
              output << nil if (position % 128).zero?
              @entity_products[face.entityID] = next_product unless next_product.empty?
            end
            walk(summary[:containers], world, next_product, definitions + [[definition, entity]], output)
          else
            walk(definition.entities, world, next_product, definitions + [[definition, entity]], output)
          end
        end
      end

      def definition_has_containers?(definition)
        @nested_definition_cache.fetch(definition) do
          @nested_definition_cache[definition] = definition.entities.any? do |child|
            child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
          end
        end
      end

      # In a parallel view, a container's projected bounds enclose all child
      # centers. Skip it only when that entire rectangle belongs to another
      # product's marker zone. Boundary-crossing containers still recurse, so
      # copied/nested details in the requested product are not lost.
      def unrequested_spatial_subtree?(entity, world, product)
        # Không dùng vùng màn hình để cắt nhánh trong cơ chế trục X.
        false
      end

      def spatial_product_for_instance(entity, world)
        return '' if ProductContext.spatial_marker_entity?(entity)
        ProductContext.infer_spatial_product(world_points(entity, world), model: @model, entity: entity)
      end

      def product_code_for_entity(entity)
        text = ProductContext.text_for_entity(entity)
        entity_codes = ProductContext.codes_for_entity(entity)
        cache_key = [text, entity_codes]
        @code_cache.fetch(cache_key) do
          @code_cache[cache_key] = ProductContext.base(entity_codes.first)
        end
      rescue
        ''
      end

      # An instance can be renamed for its new product while its copied
      # Registry/DC attributes still contain the source product. Treat that
      # changed instance name as current; definition names and copied metadata
      # remain fallback ownership only.
      def instance_name_product_code(entity)
        ProductContext.base(ProductContext.instance_name_product_code(entity))
      rescue
        ''
      end

      def requested_product?(product)
        !@requested_products || ProductContext.spatial_product_codes(product).any? { |code| @requested_products[code] }
      end

      def collect_material(material, product)
        return if material.nil? || product.empty?
        @used_materials[material] = true if @used_materials
        name = material_name(material)
        return unless self.class.displayable_material_name?(name)
        code = @material_cache[name] ||= Catalog.material_key(name)
        ProductContext.spatial_product_codes(product).each do |owner|
          next if @requested_products && !@requested_products[owner]
          @materials[owner][code] = name unless code.empty?
        end
      end

      # Keep this aligned with MH Van and Thongke. SketchUp can retain an
      # internal Material#name after a rename, while #display_name is the
      # value presented to users and stored by the material tools.
      def material_name(material)
        display = material.display_name.to_s.strip if material.respond_to?(:display_name)
        return display unless display.to_s.empty?

        material.name.to_s.strip
      rescue
        ''
      end

      # Test-only spatial ownership: markers are named 3D Text groups (SP09,
      # SP10, ...). Nothing is written to the model; the result exists only in
      # this HUD index and is recalculated when the index is rebuilt.
      def inferred_product(points)
        ProductContext.infer_spatial_product(points, model: @model, view: @view)
      end

      def products_for_entities(entities)
        products = Array(entities).flat_map do |entity|
          next [] unless entity.respond_to?(:entityID)
          code = @entity_products[entity.entityID].to_s
          code.empty? ? @descendant_products[entity.entityID].keys : ProductContext.spatial_product_codes(code)
        end
        products.uniq.sort_by { |code| ProductContext.sort_key(code) }
      rescue
        []
      end

      # Re-evaluate selected instances against the current camera/model position
      # even when their index entry predates a move. `parent_transform` is the
      # transform of SketchUp's active edit path for nested selections.
      def products_for_selected_entities(entities, parent_transform: nil)
        parent_transform ||= Geom::Transformation.new
        products = Array(entities).flat_map do |entity|
          next [] unless entity.respond_to?(:entityID)
          entity_transform = entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new
          spatial = ProductContext.infer_spatial_product(world_points(entity, parent_transform * entity_transform), model: @model, entity: entity)
          next ProductContext.spatial_product_codes(spatial) unless spatial.to_s.empty?
          next [] unless ProductContext.spatial_markers(@model).empty?

          code = @entity_products[entity.entityID].to_s
          code.empty? ? @descendant_products[entity.entityID].keys : ProductContext.spatial_product_codes(code)
        end
        products.uniq.sort_by { |code| ProductContext.sort_key(code) }
      rescue
        []
      end

      # Resolve a nested pick against every instance in its occurrence path.
      # Spatial ownership from a copied/moved parent outranks stale child
      # attributes, while a more specific spatial match can update the owner.
      def products_for_instance_path(path)
        ProductContext.codes_for_instance_path(path, model: @model, view: @view).map { |code| ProductContext.base(code) }.reject(&:empty?)
      rescue
        []
      end

      def spatial_marker_entity?(entity)
        ProductContext.spatial_marker_entity?(entity)
      end

      def record_descendant_product(product, definitions)
        return if product.to_s.empty?

        definitions.each do |_definition, ancestor|
          ProductContext.spatial_product_codes(product).each { |code| @descendant_products[ancestor.entityID][code] = true }
        end
      rescue
        nil
      end

      # PickHelper retains the full container path for a clicked face/component.
      # Prefer the first mapped ancestor: it is the actual group instance in
      # the model, while a nested definition entity can be shared by several
      # products and therefore has no reliable standalone owner.
      def products_for_entity_path(path)
        Array(path).each do |entity|
          next unless entity.respond_to?(:entityID)
          code = @entity_products[entity.entityID].to_s
          return ProductContext.spatial_product_codes(code) unless code.empty?
        end
        []
      rescue
        []
      end

      def world_points(entity, transform)
        ProductContext.world_points_for_entity(entity, transform)
      end

      def average_point(points)
        size = points.length.to_f
        Geom::Point3d.new(
          points.sum(&:x) / size,
          points.sum(&:y) / size,
          points.sum(&:z) / size
        )
      end

      def self.spatial_markers(model, view)
        ProductContext.spatial_markers(model, view)
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
