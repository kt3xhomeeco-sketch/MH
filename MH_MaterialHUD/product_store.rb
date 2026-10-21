# encoding: UTF-8
module MH
  module MaterialHUD
    # Geometry/material contents are shared by all occurrences of a definition.
    # Ownership is still resolved independently for each occurrence.
    class DefinitionContents
      attr_reader :reads

      def initialize
        @entries = {}
        @product_entries = {}
        @container_entries = {}
        @product_parents = Hash.new { |hash, key| hash[key] = {} }
        @reads = 0
      end

      def fetch(definition, output = nil)
        @entries.fetch(definition) do
          faces, containers, materials = [], [], {}
          definition.entities.each_with_index do |entity, position|
            output << nil if output && (position % 128).zero?
            next unless entity.valid?
            if entity.is_a?(Sketchup::Face)
              faces << entity
              materials[entity.material] = true if entity.material
              materials[entity.back_material] = true if entity.back_material
            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
              containers << entity
            end
          end
          @reads += 1
          @entries[definition] = { faces: faces, containers: containers, materials: materials.keys }
        end
      end

      def invalidate(definition = nil)
        if definition
          @entries.delete(definition)
          @container_entries.delete(definition)
          pending, seen = [definition], {}
          until pending.empty?
            current = pending.pop
            next if seen[current]
            seen[current] = true
            @product_entries.delete(current)
            pending.concat(@product_parents[current].keys)
          end
        else
          @entries.clear
          @container_entries.clear
          @product_entries.clear
          @product_parents.clear
        end
      end

      def containers(definition, output = nil)
        @container_entries.fetch(definition) do
          @container_entries[definition] = definition.entities.each_with_index.filter_map do |entity, position|
            output << nil if output && (position % 128).zero?
            entity if (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && entity.valid?
          end
        end
      end

      # Used only for rectangles below every spatial marker. There, ownership
      # can come only from product metadata/names or inherited ownership.
      # This proof lets unrelated imported/nesting geometry stay out of scans.
      def products_in(definition, output, ancestors = {})
        return @product_entries[definition] if @product_entries.key?(definition)
        return [] if ancestors[definition]
        ancestors = ancestors.merge(definition => true)
        products = []
        containers(definition, output).each do |entity|
          output << nil if output
          products.concat(ProductContext.codes_for_entity(entity).map { |code| ProductContext.base(code) })
          @product_parents[entity.definition][definition] = true
          products.concat(products_in(entity.definition, output, ancestors))
        end
        @product_entries[definition] = products.reject(&:empty?).uniq
      end
    end

    # The directory inspects only top-level bounds. Product scans then read
    # matching roots, with conservative fallbacks for ambiguous ownership.
    class ProductStore
      attr_reader :complete, :visited, :definitions, :model

      def initialize(model, priority_roots: [], priority_products: [])
        @model = model
        @priority_roots = priority_roots
        @priority_products = priority_products
        @definitions = DefinitionContents.new
        @records = {}
        @by_product = Hash.new { |hash, key| hash[key] = {} }
        @fallback = {}
        @definition_roots = Hash.new { |hash, key| hash[key] = {} }
        @material_roots = Hash.new { |hash, key| hash[key] = {} }
        @dirty_roots, @dirty_definitions = {}, {}
        @observers = []
        @known_change = @unknown_change = false
        @synced_revision = revision
        reset_directory
        attach_observers
      end

      def reset_directory
        @probe = ModelIndex.new(@model)
        @complete, @visited = false, 0
        @walker = Enumerator.new do |output|
          roots = (@priority_roots + @model.entities.to_a).uniq.reject do |entity|
            entity.respond_to?(:entityID) && @records.key?(entity.entityID)
          end
          priority = @priority_roots.to_h { |entity| [entity, true] }
          # Read changed/inserted roots before sorting the rest of the model.
          # In particular a copied panel must not wait behind a nesting proof.
          urgent, roots = roots.partition { |entity| priority[entity] }
          urgent.each do |entity|
            output << nil
            put_root(entity, output) if container?(entity) && entity.valid?
          end
          markers = @probe.instance_variable_get(:@spatial_markers).select { |marker| !(ProductContext.spatial_product_codes(marker[:code]) & @priority_products).empty? }
          unless markers.empty?
            view = @model.active_view
            roots.sort_by! do |entity|
              output << nil
              next Float::INFINITY unless container?(entity) && entity.valid?
              markers.map { |marker| (marker[:x] - entity.bounds.center.x).abs }.min
            end
          end
          roots.each do |entity|
            output << nil
            next unless container?(entity) && entity.valid?
            put_root(entity, output)
          end
        end
      end

      def step(budget = 0.008)
        return true if @complete
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + budget
        while true
          @walker.next
          @visited += 1
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        end
        false
      rescue StopIteration
        @complete = true
      end

      def put_root(entity, output = nil)
        points = @probe.world_points(entity, entity.transformation)
        products, wildcard = [], true
        marker = ProductContext.spatial_marker_entity?(entity)
        if marker
          products, wildcard = [], false
        elsif !points.empty?
          code = ProductContext.infer_spatial_product(points, model: @model, entity: entity)
          products = ProductContext.spatial_product_codes(code)
          wildcard = products.empty? # Wrapper có thể chứa nhiều cụm SP con.
        end
        id = entity.entityID
        record = { id: id, entity: entity, points: points, products: products, wildcard: wildcard, marker: !!marker, index: nil }
        @records[id] = record
        products.each { |product| @by_product[product][id] = record }
        @fallback[id] = record if wildcard
        record
      end

      def roots_for(products)
        ids = {}
        products.each { |product| ids.merge!(@by_product[product]) }
        @fallback.each { |id, record| ids[id] ||= record }
        ids.values.sort_by { |record| record[:wildcard] ? 1 : 0 }.reject do |record|
          index = record[:index]
          index && index.complete && index.materials.values.all?(&:empty?)
        end
      end

      def roots_count
        @records.size
      end

      def generation
        @generation.to_i
      end

      # Camera ownership changes, but the underlying definition contents do
      # not. Reuse those contents and the four collection observers.
      def reset_ownership
        @generation = generation + 1
        @records.clear
        @by_product.clear
        @fallback.clear
        @definition_roots.clear
        @material_roots.clear
        reset_directory
      end

      def refresh_probe
        @probe = ModelIndex.new(@model)
      end

      def scan(products)
        prioritize(products)
        ProductScan.new(self, products)
      end

      def prioritize(products)
        products = products.uniq.sort
        return if @priority_products == products
        @priority_products = products
        # A new selection may arrive halfway through a directory/proof walk.
        # Keep finished records and root scans, but reorder remaining work for
        # the current SP, not the SP selected when the HUD was first opened.
        reset_directory unless @complete
      end

      def prioritize_changes(products, roots)
        @priority_products = Array(products).uniq.sort unless Array(products).empty?
        related = roots_for(@priority_products).select do |record|
          index = record[:index]
          !record[:marker] && (!record[:wildcard] || (index && @priority_products.any? do |product|
            !index.materials.fetch(product, {}).empty?
          end))
        end.map { |record| record[:entity] }
        dirty = @dirty_roots.values.select { |entity| container?(entity) }
        @priority_roots = (dirty + Array(roots) + related).uniq
      end

      def index_for(record)
        record[:index] ||= ModelIndex.new(@model, roots: [record[:entity]], definition_cache: @definitions)
      end

      def record_finished(record)
        index = record[:index]
        index.used_definitions.each_key { |definition| @definition_roots[definition][record[:id]] = true }
        index.used_materials.each_key { |material| @material_roots[material][record[:id]] = true }
      end

      def visible_products(view)
        scores = Hash.new(0.0)
        @records.each_value do |record|
          entity = record[:entity]
          next unless entity.valid? && !entity.hidden? && entity.layer.visible?
          screen = record[:points].select { |point| (point - view.camera.eye).dot(view.camera.direction) > 0 }
            .map { |point| view.screen_coords(point) }
          next if screen.empty?
          left, right = screen.map(&:x).minmax
          top, bottom = screen.map(&:y).minmax
          overlap_x = [right, view.vpwidth * 0.9].min - [left, view.vpwidth * 0.1].max
          overlap_y = [bottom, view.vpheight * 0.9].min - [top, view.vpheight * 0.1].max
          next unless overlap_x > 0 && overlap_y > 0
          products = record[:products]
          products = record[:index].materials.keys if record[:index] && record[:index].complete
          products.each { |product| scores[product] += overlap_x * overlap_y }
        end
        scores.sort_by { |code, score| [-score, ProductContext.sort_key(code)] }.first(6).map(&:first)
          .sort_by { |code| ProductContext.sort_key(code) }
      end

      # Preserve the shared selection/assignment API without rebuilding a
      # full model index just to resolve one selected parent or instance path.
      def products_for_entities(entities)
        products = []
        @records.each_value do |record|
          if record[:index] && record[:index].complete
            products.concat(record[:index].products_for_entities(entities))
          elsif entities.any? { |entity| entity.respond_to?(:entityID) && entity.entityID == record[:id] }
            products.concat(record[:products])
          end
        end
        products.uniq.sort_by { |code| ProductContext.sort_key(code) }
      end

      def products_for_selected_entities(entities, parent_transform: nil)
        spatial = @probe.products_for_selected_entities(entities, parent_transform: parent_transform)
        ProductContext.spatial_markers(@model).empty? && spatial.empty? ? products_for_entities(entities) : spatial
      end

      def products_for_instance_path(path)
        resolved = @probe.products_for_instance_path(path)
        ProductContext.spatial_markers(@model).empty? && resolved.empty? ? products_for_entities(Array(path)) : resolved
      end

      def changed_entity(entity, definition = nil)
        @known_change = true
        if definition
          @dirty_definitions[definition] = true
        else
          id = entity.respond_to?(:entityID) ? entity.entityID : entity
          @dirty_roots[id] = entity.respond_to?(:entityID) ? entity : @records[id] && @records[id][:entity]
          @unknown_change = true if container?(entity) && entity.valid? && ProductContext.spatial_marker_entity?(entity)
          @unknown_change = true if @records[id] && @records[id][:marker]
        end
        MaterialHUD.schedule_refresh if MaterialHUD.instance_variable_get(:@product_store).equal?(self)
      end

      def changed_material(material)
        @known_change = true
        @material_roots[material].each_key { |id| @dirty_roots[id] = @records[id] && @records[id][:entity] }
        MaterialHUD.schedule_refresh if MaterialHUD.instance_variable_get(:@product_store).equal?(self)
      end

      def unknown_change!
        @unknown_change = true
      end

      # Explicit editor notifications describe a whole atomic material edit.
      # Capture both before and after: make_unique can replace definitions.
      def begin_material_change(entities, recursive: false)
        { store: self, generation: generation, entities: Array(entities), recursive: recursive,
          scope: material_scope(entities, recursive) }
      end

      def finish_material_change(token)
        unless token && token[:store].equal?(self) && token[:generation] == generation
          unknown_change!
          return false
        end
        before = token[:scope]
        after = material_scope(token[:entities], token[:recursive])
        if before[:unknown] || after[:unknown]
          unknown_change!
          return false
        end
        (before[:definitions] + after[:definitions]).uniq.each { |definition| @dirty_definitions[definition] = true }
        roots = (before[:roots] + after[:roots]).uniq
        entities = @model.entities.to_a.to_h { |entity| [entity.entityID, entity] }
        roots.each { |id| @dirty_roots[id] = entities[id] || (@records[id] && @records[id][:entity]) }
        @known_change = true
        @unknown_change = false
        @material_change_revision = revision
        true
      end

      def material_scope(entities, recursive)
        definitions, roots, seen, expanded = {}, {}, {}, {}
        pending = Array(entities).dup
        unknown = false
        until pending.empty?
          entity = pending.pop
          next unless entity && entity.respond_to?(:valid?) && entity.valid?
          next if seen[entity]
          seen[entity] = true
          if seen.size > 512
            unknown = true
            break
          end
          parent = entity.parent
          if parent == @model
            roots[entity.entityID] = true if container?(entity)
          elsif parent.respond_to?(:instances)
            definitions[parent] = true
            root_ids_for_definition(parent, {}, strict: true).each { |id| roots[id] = true }
          else
            unknown = true
          end
          if container?(entity)
            unknown = true if ProductContext.spatial_marker_entity?(entity)
            if recursive
              definition = entity.definition
              next if expanded[definition]
              expanded[definition] = true
              definitions[definition] = true
              root_ids_for_definition(definition, {}, strict: true).each { |id| roots[id] = true }
              definition.entities.each { |child| pending << child if container?(child) && child.valid? }
            end
          end
        end
        { definitions: definitions.keys, roots: roots.keys, unknown: unknown }
      rescue StandardError
        { definitions: [], roots: [], unknown: true }
      end

      def synchronize(unknown_if_untracked: false)
        # No observer on every definition: an untracked model transaction
        # must invalidate conservatively, including nested face edits.
        scoped = @material_change_revision && @material_change_revision == revision
        unknown = @unknown_change || (unknown_if_untracked && revision != @synced_revision && !scoped)
        unless unknown
          @dirty_definitions.each_key do |definition|
            root_ids_for_definition(definition).each do |id|
              @dirty_roots[id] = @records[id] && @records[id][:entity]
              unknown = true if @records[id] && @records[id][:marker]
            end
          end
        end
        was_complete = @complete
        if unknown || (!@complete && @known_change && !scoped)
          @records.clear
          @by_product.clear
          @fallback.clear
          @definition_roots.clear
          @material_roots.clear
          @definitions.invalidate
          reset_directory
          affected = :all
        else
          affected = {}
          @probe = ModelIndex.new(@model) unless @dirty_roots.empty?
          @dirty_definitions.each_key { |definition| @definitions.invalidate(definition) }
          @dirty_roots.each do |id, entity|
            previous = @records.delete(id)
            if previous
              affected[:all] = true if previous[:wildcard]
              previous[:products].each { |product| affected[product] = true; @by_product[product].delete(id) }
              if previous[:index]
                previous[:index].materials.each { |product, materials| affected[product] = true unless materials.empty? }
                previous[:index].used_definitions.each_key { |definition| @definition_roots[definition].delete(id) }
                previous[:index].used_materials.each_key { |material| @material_roots[material].delete(id) }
              end
              @fallback.delete(id)
            end
            if container?(entity) && entity.valid?
              current = put_root(entity)
              affected[:all] = true if current[:wildcard]
              current[:products].each { |product| affected[product] = true }
            end
          end
          affected = affected[:all] ? :all : affected.keys
          reset_directory if scoped && !was_complete && affected != []
        end
        @dirty_roots.clear
        @dirty_definitions.clear
        @known_change = @unknown_change = false
        @material_change_revision = nil
        @generation = generation + 1 unless affected == []
        @synced_revision = revision
        affected
      end

      def root_ids_for_definition(definition, seen = {}, strict: false)
        return [] if seen[definition]
        seen[definition] = true
        ids = @definition_roots[definition].keys
        Array(definition.instances).each do |instance|
          next unless instance.valid?
          parent = instance.parent
          if parent == @model
            ids << instance.entityID
          elsif parent.respond_to?(:instances)
            ids.concat(root_ids_for_definition(parent, seen, strict: strict))
          end
        end
        ids.uniq
      rescue StandardError
        raise if strict
        @unknown_change = true
        @definition_roots[definition].keys
      end

      def container?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def revision
        defined?(MH::ModelHub) ? MH::ModelHub.model_signature(@model) : 0
      end

      def attach_observers
        observe(@model.entities, ContentsObserver.new(self, nil)) if @model.entities.respond_to?(:add_observer)
        if @model.respond_to?(:definitions)
          observe(@model.definitions, DefinitionsObserver.new(self)) if @model.definitions.respond_to?(:add_observer)
        end
        observe(@model.materials, MaterialsObserver.new(self)) if @model.respond_to?(:materials) && @model.materials.respond_to?(:add_observer)
        observe(@model, HistoryObserver.new(self)) if @model.respond_to?(:add_observer)
      end

      def observe(target, observer)
        target.add_observer(observer)
        @observers << [target, observer]
      end

      def dispose
        @observers.each do |target, observer|
          target.remove_observer(observer)
        rescue StandardError
          nil
        end
        @observers.clear
      end
    end

    class ProductScan
      attr_reader :materials, :complete, :visited

      def initialize(store, products)
        @store, @products = store, products
        @materials = Hash.new { |hash, key| hash[key] = {} }
        @complete, @visited = false, 0
        @position = 0
        @roots, @root_ids = [], {}
        @generation = store.generation
      end

      def step(budget = 0.020)
        if @generation != @store.generation
          @generation = @store.generation
          @materials.clear
          @roots, @root_ids = [], {}
          @position, @visited, @complete = 0, 0, false
        end
        return true if @complete
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + budget
        unless @store.complete
          @store.step(budget * (@position < @roots.size ? 0.5 : 0.9))
        end
        # Confirm observed matches while the directory is still being built.
        # Missing/extra statuses remain pending until that proof is complete.
        @store.roots_for(@products).each do |record|
          next if @root_ids[record[:id]]
          @roots << record
          @root_ids[record[:id]] = true
        end
        if @position < @roots.size
          pending = @roots.drop(@position).sort_by do |record|
            [(record[:products] & @products).empty? ? 1 : 0, record[:wildcard] ? 1 : 0]
          end
          @roots = @roots.first(@position) + pending
        end
        while @position < @roots.size
          record = @roots[@position]
          index = @store.index_for(record)
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0
          index.step(remaining) unless index.complete
          @products.each { |product| @materials[product].merge!(index.materials.fetch(product, {})) }
          break unless index.complete
          @store.record_finished(record)
          @position += 1
        end
        @visited = @roots.sum { |record| record[:index] ? record[:index].visited : 0 }
        @complete = @store.complete && @position == @roots.size
      end
    end

    class ContentsObserver < (defined?(Sketchup::EntitiesObserver) ? Sketchup::EntitiesObserver : Object)
      def initialize(store, definition)
        @store, @definition = store, definition
      end
      def onElementAdded(_entities, entity); @store.changed_entity(entity, @definition); end
      def onElementModified(_entities, entity); @store.changed_entity(entity, @definition); end
      def onElementRemoved(_entities, id); @store.changed_entity(id, @definition); end
      def onEraseEntities(_entities); @store.unknown_change!; end
    end

    class DefinitionsObserver < (defined?(Sketchup::DefinitionsObserver) ? Sketchup::DefinitionsObserver : Object)
      def initialize(store); @store = store; end
      def onComponentAdded(_definitions, _definition); @store.unknown_change!; end
      def onComponentRemoved(_definitions, _definition); @store.unknown_change!; end
      def onComponentPropertiesChanged(_definitions, definition); @store.changed_entity(nil, definition); end
    end

    class MaterialsObserver < (defined?(Sketchup::MaterialsObserver) ? Sketchup::MaterialsObserver : Object)
      def initialize(store); @store = store; end
      def onMaterialChange(_materials, material); @store.changed_material(material); end
      def onMaterialRemove(_materials, material); @store.changed_material(material); end
    end

    class HistoryObserver < (defined?(Sketchup::ModelObserver) ? Sketchup::ModelObserver : Object)
      def initialize(store); @store = store; end
      def onTransactionUndo(_model); @store.unknown_change!; end
      def onTransactionRedo(_model); @store.unknown_change!; end
    end
  end
end
