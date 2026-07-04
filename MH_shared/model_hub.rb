# encoding: UTF-8

module MH
  module ModelHub
    Subscriber = Struct.new(:name, :on_selection, :on_model, :on_view, :on_save, :visible, keyword_init: true)
    ScanRecord = Struct.new(:entity, :context, :transform, :world_transform, :depth, :path, :parent, :key, :parent_key, keyword_init: true)

    module_function

    @subscribers = {}
    @started = false
    @model = nil
    @selection_observer = nil
    @model_observer = nil
    @view_observer = nil
    @app_observer = nil
    @view = nil
    @model_revision = 0
    @selection_revision = 0
    @view_revision = 0
    @scan_cache = {}

    def subscribe(name, on_selection: nil, on_model: nil, on_view: nil, on_save: nil, visible: nil)
      key = name.to_s.strip
      return nil if key.empty?

      @subscribers[key] = Subscriber.new(
        name: key,
        on_selection: on_selection,
        on_model: on_model,
        on_view: on_view,
        on_save: on_save,
        visible: visible
      )
      start!
      @subscribers[key]
    end

    def unsubscribe(name)
      @subscribers.delete(name.to_s)
    end

    def subscribers
      @subscribers.dup
    end

    def start!
      return true unless defined?(Sketchup)

      attach_to_model(Sketchup.active_model)
      unless @app_observer
        @app_observer = AppObserver.new
        Sketchup.add_observer(@app_observer) if Sketchup.respond_to?(:add_observer)
      end
      @started = true
    rescue
      false
    end

    def stop!
      detach_from_model
      @app_observer = nil
      @started = false
      true
    rescue
      false
    end

    def attach_to_model(model)
      return false unless model
      return true if @model == model && @selection_observer && @model_observer

      detach_from_model
      @model = model
      @selection_observer = SelectionObserver.new
      @model_observer = ModelObserver.new
      model.selection.add_observer(@selection_observer) if model.respond_to?(:selection) && model.selection
      model.add_observer(@model_observer) if model.respond_to?(:add_observer)
      attach_to_view(model.active_view) if model.respond_to?(:active_view)
      invalidate!(:model)
      true
    rescue
      false
    end

    def detach_from_model
      if @model
        @model.selection.remove_observer(@selection_observer) if @selection_observer && @model.respond_to?(:selection) && @model.selection.respond_to?(:remove_observer)
        @model.remove_observer(@model_observer) if @model_observer && @model.respond_to?(:remove_observer)
      end
      detach_from_view
      @model = nil
      @selection_observer = nil
      @model_observer = nil
      true
    rescue
      true
    end

    def attach_to_view(view)
      return false unless defined?(Sketchup::ViewObserver)
      return false unless view && view.respond_to?(:add_observer)
      return true if @view == view && @view_observer

      detach_from_view
      @view = view
      @view_observer = ViewObserver.new
      view.add_observer(@view_observer)
      true
    rescue
      false
    end

    def detach_from_view
      @view.remove_observer(@view_observer) if @view && @view_observer && @view.respond_to?(:remove_observer)
      @view = nil
      @view_observer = nil
      true
    rescue
      true
    end

    def invalidate!(kind = :model)
      @model_revision += 1 if kind == :model || kind == :all
      @selection_revision += 1 if kind == :selection || kind == :all
      @view_revision += 1 if kind == :view || kind == :all
      @scan_cache = {} if kind == :model || kind == :all
      MH::Bounds.clear!
      notify(kind)
      true
    rescue
      false
    end

    def notify(kind)
      @subscribers.values.each do |sub|
        next if sub.visible && !safe_visible?(sub)

        callback = case kind
                   when :selection then sub.on_selection
                   when :view then sub.on_view
                   when :save then sub.on_save
                   else sub.on_model
                   end
        safe_call(callback, kind) if callback
      end
    end

    def selection_signature(model = current_model)
      selection = model && model.respond_to?(:selection) ? model.selection : nil
      ids = Array(selection).map { |entity| entity_signature(entity) }.compact.sort
      path_ids = Array(model && model.respond_to?(:active_path) ? model.active_path : nil).map { |entity| entity_signature(entity) }.compact
      [@selection_revision, path_ids, ids].hash
    rescue
      @selection_revision
    end

    def model_signature(model = current_model)
      entities = model && model.respond_to?(:entities) ? model.entities : nil
      count = entities.respond_to?(:length) ? entities.length : 0
      [@model_revision, count, model.respond_to?(:path) ? model.path.to_s : ""].hash
    rescue
      @model_revision
    end

    def view_signature
      @view_revision
    end

    def scan(types: %i[group component], depth: -1, root: nil, include_hidden: false, **opts)
      root ||= current_model
      return scan_uncached(types: types, depth: depth, root: root, include_hidden: include_hidden, **opts) unless cacheable_scan_options?(opts)

      key = scan_cache_key(root, types, depth, include_hidden, opts)
      cached = @scan_cache[key]
      return cached.dup if cached

      result = scan_uncached(types: types, depth: depth, root: root, include_hidden: include_hidden, **opts)
      @scan_cache.clear if @scan_cache.size > 24
      @scan_cache[key] = result
      result.dup
    rescue
      []
    end

    def scan_records(types: %i[group component], depth: -1, root: nil, include_hidden: false, reject_names: nil, **opts, &block)
      root ||= current_model
      return scan_records_uncached(types: types, depth: depth, root: root, include_hidden: include_hidden, reject_names: reject_names, **opts, &block) unless cacheable_scan_options?(opts)

      key = scan_cache_key(root, types, depth, include_hidden, opts.merge(records: true, reject_names: Array(reject_names).map(&:to_s).sort))
      cached = @scan_cache[key]
      if cached
        cached.each(&block) if block
        return cached.dup
      end

      result = scan_records_uncached(types: types, depth: depth, root: root, include_hidden: include_hidden, reject_names: reject_names, **opts, &block)
      @scan_cache.clear if @scan_cache.size > 24
      @scan_cache[key] = result
      result.dup
    rescue
      []
    end

    def each_record(types: %i[group component], depth: -1, root: nil, include_hidden: false, reject_names: nil, **_opts, &block)
      return enum_for(:each_record, types: types, depth: depth, root: root, include_hidden: include_hidden, reject_names: reject_names) unless block

      root ||= current_model
      reject_name_set = Array(reject_names).map(&:to_s)
      record_types = Array(types).map(&:to_sym)
      count = 0
      roots_for_records(root).each do |entity|
        count += walk_records(
          entity,
          Geom::Transformation.new,
          nil,
          [],
          [],
          1,
          depth.to_i,
          record_types,
          include_hidden,
          reject_name_set,
          nil,
          block
        ).to_i
      end
      count
    rescue
      0
    end
    module_function :each_record

    def scan_uncached(types:, depth:, root:, include_hidden:, **opts)
      MH::TraverseModel.collect(
        root: root,
        max_depth: depth,
        types: types,
        include_hidden: include_hidden,
        **opts
      )
    end

    def scan_records_uncached(types:, depth:, root:, include_hidden:, reject_names: nil, **opts, &block)
      records = []
      reject_name_set = Array(reject_names).map(&:to_s)
      record_types = Array(types).map(&:to_sym)
      roots_for_records(root).each do |entity|
        walk_records(
          entity,
          Geom::Transformation.new,
          nil,
          [],
          [],
          1,
          depth.to_i,
          record_types,
          include_hidden,
          reject_name_set,
          records,
          block
        )
      end
      records
    end

    def walk_records(entity, parent_tr, parent, path, key_stack, depth, max_depth, types, include_hidden, reject_names, records, block)
      return unless valid_entity?(entity)
      return if max_depth >= 0 && depth > max_depth
      return if hidden_entity?(entity) && !include_hidden

      is_container = container_entity?(entity)
      type_matches = type_match_entity?(entity, types)
      return unless is_container || type_matches
      return if is_container && reject_names.include?(entity_name(entity))

      world_tr = entity.respond_to?(:transformation) ? parent_tr * entity.transformation : parent_tr
      sig = record_entity_signature(entity)
      key = (key_stack + [sig]).compact.join("/")
      parent_key = key_stack.empty? ? nil : key_stack.compact.join("/")
      record_path = path.dup

      if type_matches
        ctx = if defined?(MH::TraverseModel::Context)
                MH::TraverseModel::Context.new(
                  transform: parent_tr,
                  world_transform: world_tr,
                  depth: depth,
                  path: record_path,
                  parent: parent,
                  name: entity_name(entity),
                  errors: []
                )
              end
        record = ScanRecord.new(
          entity: entity,
          context: ctx,
          transform: parent_tr,
          world_transform: world_tr,
          depth: depth,
          path: record_path,
          parent: parent,
          key: key,
          parent_key: parent_key
        )
        records << record if records
        block.call(record) if block
        yielded_count = 1
      end

      return yielded_count.to_i unless is_container

      path << entity
      key_stack << sig
      child_count = 0
      children_of_entity(entity).each do |child|
        child_count += walk_records(child, world_tr, entity, path, key_stack, depth + 1, max_depth, types, include_hidden, reject_names, records, block).to_i
      end
      key_stack.pop
      path.pop
      yielded_count.to_i + child_count
    rescue
      0
    end

    def roots_for_records(root)
      if defined?(Sketchup::Model) && root.is_a?(Sketchup::Model)
        root.entities.to_a
      elsif defined?(Sketchup::Entities) && root.is_a?(Sketchup::Entities)
        root.to_a
      elsif defined?(Sketchup::Selection) && root.is_a?(Sketchup::Selection)
        root.to_a
      elsif root.is_a?(Array)
        root
      elsif container_entity?(root)
        children_of_entity(root).to_a
      else
        [root]
      end
    rescue
      []
    end

    def type_match_entity?(entity, types)
      return true if types.empty?
      (types.include?(:group) && defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)) ||
        (types.include?(:component) && defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance)) ||
        (types.include?(:face) && defined?(Sketchup::Face) && entity.is_a?(Sketchup::Face)) ||
        (types.include?(:edge) && defined?(Sketchup::Edge) && entity.is_a?(Sketchup::Edge))
    end

    def container_entity?(entity)
      (defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)) ||
        (defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance))
    end

    def children_of_entity(entity)
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

    def hidden_entity?(entity)
      (entity.respond_to?(:hidden?) && entity.hidden?) ||
        (entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?)
    rescue
      false
    end

    def valid_entity?(entity)
      entity && (!entity.respond_to?(:valid?) || entity.valid?)
    rescue
      false
    end

    def record_key(entity, path)
      (Array(path) + [entity]).map { |entry| record_entity_signature(entry) }.compact.join("/")
    rescue
      record_entity_signature(entity).to_s
    end

    def record_parent_key(path)
      return nil if Array(path).empty?
      Array(path).map { |entry| record_entity_signature(entry) }.compact.join("/")
    rescue
      nil
    end

    def cacheable_scan_options?(opts)
      !opts.values.any? { |value| value.respond_to?(:call) }
    rescue
      false
    end

    def scan_cache_key(root, types, depth, include_hidden, opts)
      [
        model_signature,
        root_signature(root),
        Array(types).map(&:to_sym).sort,
        depth.to_i,
        include_hidden ? 1 : 0,
        opts.hash
      ].hash
    end

    def root_signature(root)
      if defined?(Sketchup::Model) && root.is_a?(Sketchup::Model)
        [:model, root.respond_to?(:path) ? root.path.to_s : ""]
      elsif defined?(Sketchup::Entities) && root.is_a?(Sketchup::Entities)
        [:entities, root.object_id]
      elsif defined?(Sketchup::Selection) && root.is_a?(Sketchup::Selection)
        [:selection, selection_signature]
      elsif root.is_a?(Array)
        [:array, root.map { |entity| entity_signature(entity) }.compact.sort]
      else
        [:entity, entity_signature(root)]
      end
    rescue
      root.object_id
    end

    def current_model
      defined?(Sketchup) ? Sketchup.active_model : @model
    rescue
      @model
    end

    def entity_signature(entity)
      return nil unless entity
      if entity.respond_to?(:persistent_id)
        entity.persistent_id
      else
        entity.object_id
      end
    rescue
      entity.object_id
    end

    def record_entity_signature(entity)
      return nil unless entity
      entity.respond_to?(:entityID) ? entity.entityID : entity_signature(entity)
    rescue
      entity_signature(entity)
    end

    def entity_name(entity)
      name = entity.respond_to?(:name) ? entity.name.to_s : ""
      name = entity.definition.name.to_s if name.strip.empty? && entity.respond_to?(:definition) && entity.definition
      name.strip
    rescue
      ""
    end

    def safe_visible?(sub)
      return true unless sub.visible
      sub.visible.call
    rescue
      false
    end

    def safe_call(callback, kind)
      callback.call(kind)
    rescue
      nil
    end

    if defined?(Sketchup::SelectionObserver)
      class SelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(_selection)
          MH::ModelHub.invalidate!(:selection)
        end

        def onSelectionCleared(_selection)
          MH::ModelHub.invalidate!(:selection)
        end

        def onSelectedAdded(_selection, _entity)
          MH::ModelHub.invalidate!(:selection)
        end

        def onSelectedRemoved(_selection, _entity)
          MH::ModelHub.invalidate!(:selection)
        end

        def onSelectionAdded(_selection, _entity)
          MH::ModelHub.invalidate!(:selection)
        end

        def onSelectionRemoved(_selection, _entity)
          MH::ModelHub.invalidate!(:selection)
        end
      end
    else
      class SelectionObserver; end
    end

    if defined?(Sketchup::ModelObserver)
      class ModelObserver < Sketchup::ModelObserver
        def onTransactionCommit(_model)
          MH::ModelHub.invalidate!(:model)
        end

        def onTransactionUndo(_model)
          MH::ModelHub.invalidate!(:model)
        end

        def onTransactionRedo(_model)
          MH::ModelHub.invalidate!(:model)
        end

        def onEraseAll(_model)
          MH::ModelHub.invalidate!(:all)
        end

        def onSaveModel(_model)
          MH::ModelHub.notify(:save)
        end

        def onPostSaveModel(_model)
          MH::ModelHub.notify(:save)
        end

        def onActivePathChanged(_model)
          MH::ModelHub.invalidate!(:selection)
          MH::ModelHub.attach_to_view(Sketchup.active_model.active_view) if defined?(Sketchup) && Sketchup.active_model
        end
      end
    else
      class ModelObserver; end
    end

    if defined?(Sketchup::ViewObserver)
      class ViewObserver < Sketchup::ViewObserver
        def onViewChanged(_view)
          MH::ModelHub.invalidate!(:view)
        end
      end
    else
      class ViewObserver; end
    end

    if defined?(Sketchup::AppObserver)
      class AppObserver < Sketchup::AppObserver
        def onNewModel(model)
          MH::ModelHub.attach_to_model(model)
          MH::ModelHub.attach_to_view(model.active_view) if model.respond_to?(:active_view)
        end

        def onOpenModel(model)
          MH::ModelHub.attach_to_model(model)
          MH::ModelHub.attach_to_view(model.active_view) if model.respond_to?(:active_view)
        end
      end
    else
      class AppObserver; end
    end
  end
end
