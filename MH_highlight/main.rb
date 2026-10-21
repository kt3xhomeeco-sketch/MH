# encoding: UTF-8
# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'base64'

module MH
  module Highlight
    PLUGIN_ID = 'mh.highlight'.freeze
    OVERLAY_ID = 'mh.highlight.edges'.freeze
    OVERLAY_NAME = 'MH Highlight Edges'.freeze
    PREF_SECTION = 'MH_highlight'.freeze
    # SketchUp Preferences evaluates persisted values as Ruby. Store Base64
    # instead of JSON so the value contains no embedded quotes or braces.
    PREF_KEY = 'tag_styles_v3'.freeze
    SELECTED_COLOR_PREF_KEY = 'selected_color_v1'.freeze
    DEFAULT_COLOR = '#ff3b30'.freeze
    DEFAULT_SELECTED_COLOR = '#00c8ff'.freeze
    DEFAULT_WIDTH = 3
    MAX_WIDTH = 10.0
    EDGES_PER_CHUNK = 2_000
    EDGES_PER_TIMER_TICK = 500
    SCAN_TICK_SECONDS = 0.01
    REBUILD_DEBOUNCE_SECONDS = 0.35

    # Every configured tag is active. The checkbox in the dialog controls this
    # per-tag X-ray mode instead of enabling/disabling the tag.
    TagStyle = Struct.new(:xray, :color, :width, keyword_init: true)
    Chunk = Struct.new(:points, :bounds, keyword_init: true)
    Source = Struct.new(
      :tag_name, :entity, :path, :world_transform, :transform_signature,
      :chunks, :points, :bounds, :visible,
      keyword_init: true
    )

    # Clean up the retired Move + Snap 2D runtime when this file is hot-loaded.
    # A normal SketchUp restart clears it automatically; this keeps VBO reloads
    # from retaining the old custom Tool implementation in memory.
    if instance_variable_get(:@native_snap_enabled) && (snap_model = instance_variable_get(:@native_snap_model))
      previous = instance_variable_get(:@native_snap_original_transparency)
      snap_model.rendering_options['ModelTransparency'] = previous unless previous.nil?
    end
    %i[@native_snap_enabled @native_snap_model @native_snap_original_transparency].each do |ivar|
      remove_instance_variable(ivar) if instance_variable_defined?(ivar)
    end
    remove_const(:MoveSnapTool) if const_defined?(:MoveSnapTool, false)
    class << self
      %i[
        snap_at activate_snap_move toggle_native_snap native_snap_enabled
        enable_native_snap disable_native_snap
        nearest_snap_candidate nearest_edge_candidate
      ].each do |method_name|
        remove_method(method_name) if method_defined?(method_name)
      end
    end

    # A Sketchup::Overlay does not activate a Tool, so normal SketchUp tools and
    # third-party commands remain usable while the highlight is enabled.
    class EdgeOverlay < Sketchup::Overlay
      def initialize
        super(OVERLAY_ID, OVERLAY_NAME)
      end

      def start
        MH::Highlight.invalidate_view
      end

      def stop
        MH::Highlight.invalidate_view
      end

      def draw(view)
        MH::Highlight.draw(view)
      rescue => error
        puts "[MH Highlight] draw failed: #{error.class}: #{error.message}"
      end
    end

    class ModelChangeObserver < Sketchup::ModelObserver
      def onTransactionCommit(_model)
        MH::Highlight.model_changed
      end

      def onTransactionUndo(_model)
        MH::Highlight.model_changed
      end

      def onTransactionRedo(_model)
        MH::Highlight.model_changed
      end

      def onEraseAll(_model)
        MH::Highlight.model_changed
      end

      def onActivePathChanged(model)
        MH::Highlight.active_path_changed(model)
      end
    end

    class AddedEntitiesObserver < Sketchup::EntitiesObserver
      def onElementAdded(_entities, entity)
        MH::Highlight.entity_added(entity)
      end

      # MH_DWG imports a hidden, untagged component first, then assigns the
      # configured tag only after the user places it. Watch this later change.
      def onElementModified(_entities, entity)
        MH::Highlight.entity_modified(entity)
      end
    end

    class TaggedEntityObserver < Sketchup::EntityObserver
      def onChangeEntity(_entity)
        MH::Highlight.tagged_entity_changed
      end

      def onEraseEntity(_entity)
        MH::Highlight.tagged_entity_erased
      end
    end

    class SelectionChangeObserver < Sketchup::SelectionObserver
      def onSelectionAdded(_selection, _entity)
        MH::Highlight.selection_changed
      end

      def onSelectionRemoved(_selection, _entity)
        MH::Highlight.selection_changed
      end

      def onSelectionBulkChange(_selection)
        MH::Highlight.selection_changed
      end

      def onSelectionCleared(_selection)
        MH::Highlight.selection_changed
      end
    end

    class AppChangeObserver < Sketchup::AppObserver
      def onNewModel(model)
        MH::Highlight.model_opened(model)
      end

      def onOpenModel(model)
        MH::Highlight.model_opened(model)
      end
    end

    class << self
      def start
        # Hot-upgrade cleanup for v1.0.0: that version attached a ViewObserver
        # which invalidated the same view and could create a continuous redraw
        # loop. Remove the retained runtime observer before returning early.
        if @view_observer && @observed_model
          @observed_model.active_view.remove_observer(@view_observer) rescue nil
          @view_observer = nil
        end
        @desired_enabled = enabled? unless instance_variable_defined?(:@desired_enabled)
        if @started
          install_commands unless @commands_installed
          unless instance_variable_defined?(:@sources)
            @sources = []
            @cache_dirty = true
          end
          attach_model_observers(Sketchup.active_model) if enabled?
          request_rebuild(0.0) if enabled? && cache_stale?
          return
        end

        @started = true
        @styles = load_styles
        @selected_color = load_selected_color
        @cache = {} # { tag_name => [Chunk, ...] }
        @sources = []
        @cache_model = nil
        @cache_dirty = true
        @scan_generation = 0
        install_commands
        attach_app_observer
      rescue => error
        puts "[MH Highlight] start failed: #{error.class}: #{error.message}"
      end

      def toggle
        start
        ensure_overlay
        return unless @overlay

        @desired_enabled = !@desired_enabled
        @overlay.enabled = @desired_enabled
        if @desired_enabled
          attach_model_observers(Sketchup.active_model)
          if cache_stale?
            request_rebuild(0.0)
          else
            attach_source_observers
          end
        else
          cancel_rebuild
          detach_source_observers
        end
        invalidate_view
        refresh_dialog
      rescue => error
        UI.messagebox("MH Highlight loi: #{error.message}")
      end

      def show_dialog
        start
        ensure_overlay
        build_dialog unless @dialog && @dialog.visible?
        @dialog.show
        refresh_dialog
      rescue => error
        UI.messagebox("Khong mo duoc MH Highlight: #{error.message}")
      end

      def refresh_cache
        start
        ensure_overlay
        attach_model_observers(Sketchup.active_model)
        request_rebuild(0.0, force: true)
      end

      def model_opened(model)
        desired_enabled = @desired_enabled == true
        detach_source_observers
        detach_model_observers
        @overlay = nil
        @overlay_model = nil
        @cache = {}
        @sources = []
        @cache_model = nil
        @cache_dirty = true
        @scan_generation = @scan_generation.to_i + 1
        if desired_enabled
          ensure_overlay
          @overlay.enabled = true if @overlay
          attach_model_observers(model)
          request_rebuild(0.10)
        end
        refresh_dialog
      end

      def model_changed
        return unless enabled?

        schedule_added_entity_check(0.05) unless Array(@pending_added_entities).empty?
        # A transform-only refresh misses edits to raw edges inside a tagged
        # group/component. Keep the fast transform path for an immediate
        # redraw, then rebuild the cache after the transaction settles so the
        # overlay always reflects the actual 2D geometry.
        schedule_transform_sync(0.016)
        @cache_dirty = true
        request_rebuild(REBUILD_DEBOUNCE_SECONDS)
      end

      def entity_added(entity)
        return unless enabled?
        return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        @pending_added_entities ||= []
        @pending_added_entities << entity unless @pending_added_entities.include?(entity)
        schedule_added_entity_check(0.10)
      rescue => error
        puts "[MH Highlight] added entity queue failed: #{error.message}"
      end

      def entity_modified(entity)
        return unless enabled?
        return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        layer = entity.layer
        return unless layer && active_tag_names.include?(layer.name.to_s)

        @pending_added_entities ||= []
        @pending_added_entities << entity unless @pending_added_entities.include?(entity)
        schedule_added_entity_check(0.10)
      rescue => error
        puts "[MH Highlight] modified entity queue failed: #{error.message}"
      end

      def active_path_changed(model)
        return unless enabled?

        attach_entities_observers(model)
      end

      def tagged_entity_changed
        return unless enabled?

        schedule_transform_sync(0.016)
        @cache_dirty = true
        request_rebuild(REBUILD_DEBOUNCE_SECONDS)
      end

      def tagged_entity_erased
        return unless enabled?

        @cache_dirty = true
        request_rebuild(REBUILD_DEBOUNCE_SECONDS)
      end

      def selection_changed
        invalidate_view if enabled?
      end

      def invalidate_view
        Sketchup.active_model.active_view.invalidate
      rescue
        nil
      end

      def enabled?
        @overlay && @overlay.respond_to?(:enabled?) && @overlay.enabled?
      rescue
        false
      end

      # Called by EdgeOverlay. This deliberately contains no entity traversal.
      def draw(view)
        return unless enabled?

        camera_signature = view_signature(view)
        selection = Sketchup.active_model.selection
        Array(@sources).each do |source|
          next if source.visible == false

          style = style_for(source.tag_name)
          color = source_selected?(source, selection) ? selected_sketchup_color : cached_sketchup_color(style)
          view.drawing_color = color
          view.line_width = style.width
          source.chunks.each do |chunk|
            next unless chunk_visible?(view, chunk, camera_signature)

            if style.xray
              # draw2d is not depth-tested. Coordinates are projected from the
              # cached world points only; no entity/model traversal happens here.
              view.draw2d(GL_LINES, screen_points(view, chunk, camera_signature))
            else
              view.draw(GL_LINES, chunk.points)
            end
          end
        end
      ensure
        view.line_width = 1 if view
      end

      private

      def install_commands
        return if @commands_installed

        toggle_command = UI::Command.new('Bat/tat MH Highlight') { toggle }
        toggle_command.tooltip = 'Bat/tat highlight edge theo Tag'
        toggle_command.status_bar_text = 'Bat/tat overlay highlight edge theo Tag'
        icon = File.join(__dir__, 'icons', 'mh_highlight.svg')
        toggle_command.small_icon = icon
        toggle_command.large_icon = icon
        toggle_command.set_validation_proc { enabled? ? MF_CHECKED : MF_UNCHECKED }

        dialog_command = UI::Command.new('Cau hinh MH Highlight') { show_dialog }
        dialog_command.tooltip = 'Cau hinh Tag, mau va do day highlight'

        refresh_command = UI::Command.new('Lam moi cache MH Highlight') { refresh_cache }

        menu = UI.menu('Extensions').add_submenu('MH Highlight')
        menu.add_item(toggle_command)
        menu.add_item(dialog_command)
        menu.add_item(refresh_command)

        toolbar = UI::Toolbar.new('MH Highlight')
        toolbar.add_item(toggle_command)
        toolbar.add_item(dialog_command)
        toolbar.show
        @commands_installed = true
      end

      def attach_app_observer
        return if @app_observer

        @app_observer = AppChangeObserver.new
        Sketchup.add_observer(@app_observer)
      end

      def attach_model_observers(model)
        return unless model
        if @observed_model == model && @model_observer
          attach_entities_observers(model)
          attach_selection_observer(model)
          return
        end

        detach_model_observers
        @observed_model = model
        @model_observer = ModelChangeObserver.new
        model.add_observer(@model_observer)
        attach_entities_observers(model)
        attach_selection_observer(model)
      rescue => error
        puts "[MH Highlight] observer attach failed: #{error.message}"
      end

      def detach_model_observers
        if @observed_model && @model_observer
          @observed_model.remove_observer(@model_observer)
        end
        detach_entities_observers
        detach_selection_observer
      rescue
        nil
      ensure
        @observed_model = @model_observer = nil
      end

      def attach_entities_observers(model)
        detach_entities_observers
        return unless model && defined?(Sketchup::EntitiesObserver)

        @added_entities_observer = AddedEntitiesObserver.new
        @observed_entity_collections = [model.entities, model.active_entities].compact.uniq
        @observed_entity_collections.each { |entities| entities.add_observer(@added_entities_observer) }
      rescue => error
        puts "[MH Highlight] entities observer attach failed: #{error.message}"
      end

      def detach_entities_observers
        Array(@observed_entity_collections).each do |entities|
          entities.remove_observer(@added_entities_observer) if @added_entities_observer
        rescue
          nil
        end
        @observed_entity_collections = []
        @added_entities_observer = nil
      end

      def attach_selection_observer(model)
        selection = model && model.selection
        return unless selection
        return if @observed_selection == selection && @selection_observer

        detach_selection_observer
        @selection_observer = SelectionChangeObserver.new
        selection.add_observer(@selection_observer)
        @observed_selection = selection
      rescue => error
        puts "[MH Highlight] selection observer attach failed: #{error.message}"
      end

      def detach_selection_observer
        @observed_selection.remove_observer(@selection_observer) if @observed_selection && @selection_observer
      rescue
        nil
      ensure
        @observed_selection = @selection_observer = nil
      end

      def ensure_overlay
        return nil unless defined?(Sketchup::Overlay)

        model = Sketchup.active_model
        if @overlay.nil? || @overlay_model != model
          @overlay = EdgeOverlay.new
          model.overlays.add(@overlay)
          @overlay.enabled = @desired_enabled == true
          @overlay_model = model
        end
        @overlay
      rescue => error
        puts "[MH Highlight] overlay unavailable: #{error.message}"
        nil
      end

      def cache_stale?
        @cache_dirty || @cache_model != Sketchup.active_model || @cache.nil? || @cache.empty?
      end

      def request_rebuild(delay = REBUILD_DEBOUNCE_SECONDS, force: false)
        return unless enabled?

        @scan_generation = @scan_generation.to_i + 1
        generation = @scan_generation
        stop_timer(@rebuild_timer)
        @rebuild_timer = UI.start_timer(delay, false) do
          next unless enabled? && generation == @scan_generation

          begin_rebuild(generation, force)
        end
      end

      def cancel_rebuild
        @scan_generation = @scan_generation.to_i + 1
        stop_timer(@rebuild_timer)
        stop_timer(@scan_timer)
        stop_timer(@sync_timer)
        stop_timer(@added_entity_timer)
        @rebuild_timer = @scan_timer = @sync_timer = @added_entity_timer = nil
      rescue
        nil
      end

      def begin_rebuild(generation, _force = false)
        model = Sketchup.active_model
        @pending_added_entities = []
        stop_timer(@added_entity_timer)
        @added_entity_timer = nil
        selected_tags = active_tag_names
        if selected_tags.empty?
          detach_source_observers
          @cache = {}
          @sources = []
          @cache_model = model
          @cache_dirty = false
          invalidate_view
          refresh_dialog
          return
        end

        @scan_started_at = Time.now
        @scan_edge_count = 0
        @scan_sources = []
        @scan_enumerator = edge_enumerator(model, selected_tags)
        scan_next_batch(generation, model)
      rescue => error
        puts "[MH Highlight] cache setup failed: #{error.class}: #{error.message}"
      end

      def scan_next_batch(generation, model)
        return unless enabled? && generation == @scan_generation && Sketchup.active_model == model

        processed = 0
        begin
          while processed < EDGES_PER_TIMER_TICK
            source, first, second = @scan_enumerator.next
            append_source_edge(source, first, second)
            processed += 1
          end
          @scan_timer = UI.start_timer(SCAN_TICK_SECONDS, false) { scan_next_batch(generation, model) }
        rescue StopIteration
          finalize_rebuild(model)
        rescue => error
          puts "[MH Highlight] cache scan failed: #{error.class}: #{error.message}"
        end
      end

      def append_source_edge(source, first, second)
        source.points << first << second
        source.bounds ||= Geom::BoundingBox.new
        source.bounds.add(first)
        source.bounds.add(second)
        @scan_edge_count += 1
        return unless source.points.length >= EDGES_PER_CHUNK * 2

        source.chunks << Chunk.new(points: source.points, bounds: source.bounds)
        source.points = []
        source.bounds = nil
      end

      def finalize_rebuild(model)
        @scan_sources.each do |source|
          unless source.points.empty?
            source.chunks << Chunk.new(points: source.points, bounds: source.bounds)
            source.points = []
            source.bounds = nil
          end
        end
        @sources = @scan_sources.reject { |source| source.chunks.empty? }
        rebuild_cache_index
        @cache_model = model
        @cache_dirty = false
        elapsed = Time.now - @scan_started_at
        puts format('[MH Highlight] cached %d edges in %.2fs', @scan_edge_count, elapsed)
        @scan_enumerator = @scan_sources = @scan_timer = nil
        attach_source_observers
        invalidate_view
        refresh_dialog
      end

      # Traverses only while rebuilding. A selected tagged instance supplies the
      # effective tag to all nested raw edges; a nested selected tag takes over.
      def edge_enumerator(model, selected_tags)
        Enumerator.new do |yielded|
          walk_entities(
            model.entities,
            Geom::Transformation.new,
            nil,
            selected_tags,
            yielded,
            []
          )
        end
      end

      def walk_entities(entities, transform, inherited_source, selected_tags, yielded, path)
        entities.each do |entity|
          next unless entity.valid?
          next if entity.hidden?
          next unless entity_layer_visible?(entity)

          if entity.is_a?(Sketchup::Edge)
            next unless inherited_source
            next if entity.soft? || entity.smooth?

            yielded << [
              inherited_source,
              entity.start.position.transform(transform),
              entity.end.position.transform(transform)
            ]
          elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            tag_name = entity.layer ? entity.layer.name.to_s : ''
            child_transform = transform * entity.transformation
            child_path = path + [entity]
            effective_source = inherited_source
            if selected_tags.include?(tag_name)
              effective_source = Source.new(
                tag_name: tag_name,
                entity: entity,
                path: child_path,
                world_transform: child_transform,
                transform_signature: transformation_signature(child_transform),
                chunks: [],
                points: [],
                bounds: nil,
                visible: true
              )
              @scan_sources << effective_source
            end
            child_entities = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
            walk_entities(child_entities, child_transform, effective_source, selected_tags, yielded, child_path)
          end
        end
      rescue => error
        puts "[MH Highlight] entity traversal warning: #{error.message}"
      end

      def rebuild_cache_index
        next_cache = Hash.new { |hash, key| hash[key] = [] }
        Array(@sources).each do |source|
          next if source.visible == false

          next_cache[source.tag_name].concat(source.chunks)
        end
        @cache = next_cache
      end

      def schedule_transform_sync(delay = 0.016)
        stop_timer(@sync_timer)
        @sync_timer = UI.start_timer(delay, false) do
          @sync_timer = nil
          sync_tagged_transforms if enabled?
        end
      rescue => error
        puts "[MH Highlight] transform sync schedule failed: #{error.message}"
      end

      def schedule_added_entity_check(delay = 0.10)
        stop_timer(@added_entity_timer)
        @added_entity_timer = UI.start_timer(delay, false) do
          @added_entity_timer = nil
          process_added_entities if enabled?
        end
      rescue => error
        puts "[MH Highlight] added entity check schedule failed: #{error.message}"
      end

      # Inspect only entities reported by EntitiesObserver. Importing a new
      # component can therefore add highlight sources without scanning the rest
      # of the model after ordinary unrelated edits.
      def process_added_entities
        additions = Array(@pending_added_entities)
        @pending_added_entities = []
        return if additions.empty?

        configured = active_tag_names.each_with_object({}) { |name, set| set[name] = true }
        return if configured.empty?

        contains_highlight_tag = additions.any? do |entity|
          entity && entity.valid? && subtree_contains_configured_tag?(entity, configured, {})
        end
        return unless contains_highlight_tag

        @cache_dirty = true
        request_rebuild(0.0)
      rescue => error
        puts "[MH Highlight] added entity check failed: #{error.class}: #{error.message}"
      end

      def subtree_contains_configured_tag?(entity, configured, visited_definitions)
        layer = entity.layer
        return true if layer && configured[layer.name.to_s]

        child_entities = if entity.is_a?(Sketchup::Group)
                           entity.entities
                         elsif entity.is_a?(Sketchup::ComponentInstance)
                           definition = entity.definition
                           return false if visited_definitions[definition.object_id]

                           visited_definitions[definition.object_id] = true
                           definition.entities
                         else
                           return false
                         end

        child_entities.any? do |child|
          next false unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)

          subtree_contains_configured_tag?(child, configured, visited_definitions)
        end
      rescue
        false
      end

      # Fast path used after every model transaction. It inspects only the
      # cached tagged instance paths. Unrelated model edits therefore do not
      # traverse entities, rebuild points, or invalidate the viewport.
      def sync_tagged_transforms
        return if @scan_enumerator

        changed = false
        index_changed = false
        needs_full_rebuild = false

        Array(@sources).each do |source|
          unless source_path_valid?(source)
            needs_full_rebuild = true
            break
          end

          visible = source_path_visible?(source)
          if source.visible != visible
            source.visible = visible
            index_changed = true
          end

          world_transform = current_world_transform(source.path)
          unless world_transform
            needs_full_rebuild = true
            break
          end
          signature = transformation_signature(world_transform)
          next if signature == source.transform_signature

          unless transform_source_points(source, world_transform)
            needs_full_rebuild = true
            break
          end
          source.transform_signature = signature
          source.world_transform = world_transform
          changed = true
        end

        if needs_full_rebuild
          @cache_dirty = true
          request_rebuild(REBUILD_DEBOUNCE_SECONDS)
          return
        end

        rebuild_cache_index if index_changed
        invalidate_view if changed || index_changed
      rescue => error
        puts "[MH Highlight] transform sync failed: #{error.class}: #{error.message}"
      end

      def source_path_valid?(source)
        return false unless source.entity && source.entity.valid?
        return false unless source.path.all? { |entity| entity && entity.valid? }

        layer = source.entity.layer
        layer && layer.name.to_s == source.tag_name
      rescue
        false
      end

      def source_path_visible?(source)
        source.path.all? do |entity|
          !entity.hidden? && entity_layer_visible?(entity)
        end
      rescue
        false
      end

      def current_world_transform(path)
        path.reduce(Geom::Transformation.new) do |transform, entity|
          return nil unless entity && entity.valid?

          transform * entity.transformation
        end
      rescue
        nil
      end

      def transformation_signature(transformation)
        transformation.to_a.hash
      rescue
        transformation.hash
      end

      def transform_source_points(source, next_world_transform)
        delta = next_world_transform * source.world_transform.inverse
        source.chunks.each do |chunk|
          bounds = Geom::BoundingBox.new
          chunk.points.each do |point|
            point.transform!(delta)
            bounds.add(point)
          end
          chunk.bounds = bounds
          clear_chunk_view_cache(chunk)
        end
        true
      rescue => error
        puts "[MH Highlight] source transform failed: #{error.message}"
        false
      end

      def clear_chunk_view_cache(chunk)
        %i[
          @mh_visibility_signature @mh_visible
          @mh_screen_signature @mh_screen_points
        ].each do |ivar|
          chunk.remove_instance_variable(ivar) if chunk.instance_variable_defined?(ivar)
        end
      end

      def attach_source_observers
        detach_source_observers
        return unless defined?(Sketchup::EntityObserver)

        @source_entity_observer = TaggedEntityObserver.new
        @observed_source_entities = Array(@sources).flat_map(&:path).uniq
        @observed_source_entities.select! { |entity| entity && entity.valid? }
        @observed_source_entities.each { |entity| entity.add_observer(@source_entity_observer) }
      rescue => error
        puts "[MH Highlight] tagged observer attach failed: #{error.message}"
      end

      def detach_source_observers
        Array(@observed_source_entities).each do |entity|
          entity.remove_observer(@source_entity_observer) if entity && entity.valid? && @source_entity_observer
        rescue
          nil
        end
        @observed_source_entities = []
        @source_entity_observer = nil
      end

      def entity_layer_visible?(entity)
        layer = entity.layer
        !layer || !layer.respond_to?(:visible?) || layer.visible?
      rescue
        true
      end

      # Conservative chunk culling: test only eight cached bounding-box corners.
      # It never touches model entities and deliberately keeps partly-visible
      # chunks rather than risk hiding a highlight at the viewport border.
      def chunk_visible?(view, chunk, camera_signature)
        cached_signature = chunk.instance_variable_get(:@mh_visibility_signature)
        if cached_signature == camera_signature
          return chunk.instance_variable_get(:@mh_visible)
        end

        bounds = chunk.bounds
        return true unless bounds && bounds.valid?

        screen = 8.times.map do |index|
          point = bounds.corner(index)
          view.screen_coords(point)
        end
        width = view.vpwidth.to_f
        height = view.vpheight.to_f
        visible = !(screen.all? { |point| point.x < 0 } ||
                    screen.all? { |point| point.x > width } ||
                    screen.all? { |point| point.y < 0 } ||
                    screen.all? { |point| point.y > height })
        chunk.instance_variable_set(:@mh_visibility_signature, camera_signature)
        chunk.instance_variable_set(:@mh_visible, visible)
        visible
      rescue
        true
      end

      def screen_points(view, chunk, camera_signature)
        # Reuse one mutable screen buffer per chunk. Camera changes only update
        # x/y values; the cached world-coordinate array stays untouched.
        buffer = chunk.instance_variable_get(:@mh_screen_points)
        cached_signature = chunk.instance_variable_get(:@mh_screen_signature)
        return buffer if buffer && cached_signature == camera_signature

        unless buffer && buffer.length == chunk.points.length
          buffer = Array.new(chunk.points.length) { Geom::Point3d.new }
          chunk.instance_variable_set(:@mh_screen_points, buffer)
        end
        chunk.points.each_with_index do |point, index|
          screen = view.screen_coords(point)
          target = buffer[index]
          target.x = screen.x
          target.y = screen.y
          target.z = 0
        end
        chunk.instance_variable_set(:@mh_screen_signature, camera_signature)
        buffer
      end

      def view_signature(view)
        camera = view.camera
        eye = camera.eye
        target = camera.target
        up = camera.up
        [
          view.vpwidth.to_i, view.vpheight.to_i,
          eye.x, eye.y, eye.z,
          target.x, target.y, target.z,
          up.x, up.y, up.z,
          camera.perspective?,
          (camera.fov rescue nil),
          (camera.aspect_ratio rescue nil)
        ].hash
      rescue
        Time.now.to_f
      end

      def cached_sketchup_color(style)
        key = style.color.to_s
        cached_key = style.instance_variable_get(:@mh_color_key)
        cached = style.instance_variable_get(:@mh_color)
        return cached if cached && cached_key == key

        color = sketchup_color(key)
        style.instance_variable_set(:@mh_color_key, key)
        style.instance_variable_set(:@mh_color, color)
        color
      end

      def selected_sketchup_color
        color_key = selected_color
        return @cached_selected_sketchup_color if @cached_selected_color_key == color_key && @cached_selected_sketchup_color

        @cached_selected_color_key = color_key
        @cached_selected_sketchup_color = sketchup_color(color_key)
      end

      def source_selected?(source, selection)
        selection.include?(source.entity)
      rescue
        false
      end

      def build_dialog
        @dialog = UI::HtmlDialog.new(
          dialog_title: 'MH Highlight',
          preferences_key: 'MH_Highlight_Dialog',
          scrollable: true,
          resizable: true,
          width: 570,
          height: 540,
          min_width: 430,
          min_height: 320,
          style: UI::HtmlDialog::STYLE_UTILITY
        )
        @dialog.set_html(dialog_html)
        @dialog.add_action_callback('ready') { |_dialog| refresh_dialog }
        @dialog.add_action_callback('upsertTag') do |_dialog, old_name, tag_name, xray, color, width|
          upsert_style(old_name, tag_name, xray == 'true', color, width)
        end
        @dialog.add_action_callback('removeTag') { |_dialog, tag_name| remove_style(tag_name) }
        @dialog.add_action_callback('toggleOverlay') { |_dialog| toggle }
        @dialog.add_action_callback('refreshCache') { |_dialog| refresh_cache }
        @dialog.add_action_callback('setSelectedColor') { |_dialog, color| set_selected_color(color) }
        @dialog.set_on_closed { @dialog = nil }
      end

      def refresh_dialog
        return unless @dialog && @dialog.visible?

        data = {
          enabled: enabled?,
          scanning: !@scan_enumerator.nil?,
          edge_count: @scan_edge_count || cache_edge_count,
          selectedColor: selected_color,
          tags: configured_tag_names.map do |name|
            style = style_for(name)
            { name: name, xray: style.xray, color: style.color, width: style.width }
          end
        }
        @dialog.execute_script("window.MHHighlight && window.MHHighlight.render(#{JSON.generate(data)});")
      rescue => error
        puts "[MH Highlight] dialog refresh failed: #{error.message}"
      end

      def upsert_style(old_name, tag_name, xray, color, width)
        old_name = old_name.to_s.strip
        name = tag_name.to_s.strip
        if name.empty?
          remove_style(old_name) unless old_name.empty?
          return
        end

        @styles.delete(old_name) if !old_name.empty? && old_name != name
        old = @styles[name]
        style = TagStyle.new(xray: !!xray, color: normalize_color(color), width: normalize_width(width))
        @styles[name] = style
        save_styles
        # Editing the tag name changes cache membership. Color/width/X-ray only
        # alter drawing and do not scan the model again.
        membership_changed = old_name != name || old.nil?
        @cache_dirty = true if membership_changed
        request_rebuild(0.0) if membership_changed && enabled?
        invalidate_view
        refresh_dialog
      end

      def selected_color
        @selected_color = normalize_color(@selected_color || DEFAULT_SELECTED_COLOR)
      end

      def set_selected_color(color)
        @selected_color = normalize_color(color)
        Sketchup.write_default(PREF_SECTION, SELECTED_COLOR_PREF_KEY, @selected_color)
        @cached_selected_color_key = @cached_selected_sketchup_color = nil
        invalidate_view
        refresh_dialog
      rescue => error
        puts "[MH Highlight] selected color save failed: #{error.message}"
      end

      def remove_style(tag_name)
        name = tag_name.to_s.strip
        return if name.empty?

        removed = @styles.delete(name)
        return unless removed

        save_styles
        @cache_dirty = true
        request_rebuild(0.0) if enabled?
        invalidate_view
        refresh_dialog
      end

      def configured_tag_names
        (@styles || {}).keys.map(&:to_s).reject(&:empty?).sort
      end

      def active_tag_names
        configured_tag_names
      end

      def style_for(tag_name)
        @styles ||= load_styles
        key = tag_name.to_s
        stored = @styles[key]
        # Hot reload can retain Struct instances created by the prior version.
        # Convert the old enabled/color/width form before the new draw/dialog
        # code reads xray from it.
        if stored && !stored.respond_to?(:xray)
          stored = TagStyle.new(
            xray: stored.respond_to?(:enabled) ? !!stored.enabled : true,
            color: stored.respond_to?(:color) ? normalize_color(stored.color) : DEFAULT_COLOR,
            width: stored.respond_to?(:width) ? normalize_width(stored.width) : DEFAULT_WIDTH
          )
          @styles[key] = stored
        end
        @styles[key] ||= TagStyle.new(xray: true, color: DEFAULT_COLOR, width: DEFAULT_WIDTH)
      end

      def load_styles
        encoded = Sketchup.read_default(PREF_SECTION, PREF_KEY, Base64.strict_encode64('{}')).to_s
        parsed = JSON.parse(Base64.strict_decode64(encoded))
        parsed.each_with_object({}) do |(name, value), styles|
          value = {} unless value.is_a?(Hash)
          styles[name.to_s] = TagStyle.new(
            # Existing configurations used enabled. They are migrated as active
            # tags, with their old checkbox state becoming the X-ray state.
            xray: value.key?('xray') ? !!value['xray'] : !!value['enabled'],
            color: normalize_color(value['color']),
            width: normalize_width(value['width'])
          )
        end
      rescue
        {}
      end

      def load_selected_color
        normalize_color(Sketchup.read_default(PREF_SECTION, SELECTED_COLOR_PREF_KEY, DEFAULT_SELECTED_COLOR))
      rescue
        DEFAULT_SELECTED_COLOR
      end

      def save_styles
        serializable = @styles.each_with_object({}) do |(name, style), data|
          data[name] = { xray: style.xray, color: style.color, width: style.width }
        end
        Sketchup.write_default(PREF_SECTION, PREF_KEY, Base64.strict_encode64(JSON.generate(serializable)))
      rescue => error
        puts "[MH Highlight] settings save failed: #{error.message}"
      end

      def normalize_color(value)
        color = value.to_s.strip
        color.match?(/\A#[0-9a-fA-F]{6}\z/) ? color.downcase : DEFAULT_COLOR
      end

      def normalize_width(value)
        width = Float(value)
        return DEFAULT_WIDTH unless width.finite?

        [[width, 0.1].max, MAX_WIDTH].min.round(1)
      rescue ArgumentError, TypeError
        DEFAULT_WIDTH
      end

      def sketchup_color(hex)
        value = normalize_color(hex)
        Sketchup::Color.new(value[1..2].to_i(16), value[3..4].to_i(16), value[5..6].to_i(16))
      end

      def cache_edge_count
        @cache.values.flatten.sum { |chunk| chunk.points.length / 2 }
      rescue
        0
      end

      def stop_timer(timer_id)
        UI.stop_timer(timer_id) if timer_id && UI.respond_to?(:stop_timer)
      rescue
        nil
      end

      def dialog_html
        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
            * { box-sizing: border-box; } body { margin: 0; padding: 16px; font: 13px 'Segoe UI', Arial, sans-serif; color: #202124; background: #f7f8fa; }
            header { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:14px; } h2 { margin:0; font-size:18px; } .status { color:#5f6368; font-size:12px; }
            .actions { display:flex; gap:8px; margin-bottom:12px; } button { border:0; border-radius:5px; padding:8px 12px; color:white; background:#1769e0; cursor:pointer; } button.secondary { background:#5f6368; } button.remove { color:#b3261e; background:transparent; padding:3px 6px; font-size:18px; line-height:16px; }
            table { width:100%; border-collapse:collapse; background:white; border:1px solid #dfe3e8; } th { text-align:left; font-size:12px; color:#5f6368; background:#f1f3f4; padding:9px; } td { border-top:1px solid #edf0f2; padding:7px 9px; } th:nth-child(1) { width:58%; } th:nth-child(2) { width:22%; } th:nth-child(3) { width:20%; }
            .tag { display:flex; align-items:center; gap:7px; } .tag-name { min-width:0; flex:1; padding:5px; border:1px solid #c7ccd1; border-radius:4px; } .xray { accent-color:#1769e0; } .xray-label { color:#5f6368; font-size:11px; white-space:nowrap; } input[type=color] { width:42px; height:26px; padding:0; border:0; background:transparent; cursor:pointer; } input[type=number] { width:58px; padding:5px; border:1px solid #c7ccd1; border-radius:4px; } .hint { color:#6f757b; font-size:12px; margin:0 0 10px; } .selected-style { display:flex; align-items:center; gap:8px; margin:0 0 12px; padding:8px 10px; background:#fff; border:1px solid #dfe3e8; border-radius:5px; color:#3c4043; font-size:12px; }
          </style></head><body>
            <header><div><h2>MH Highlight</h2><div id="status" class="status">Dang tai...</div></div></header>
            <p class="hint">Nhap ten Tag thu cong. Tag da nhap se luon highlight; tick <em>Xuyen obj</em> de hien ca phan bi che. Neu sua hinh hoc cua Tag, bam <em>Lam moi cache</em>.</p>
            <div class="selected-style"><label for="selected-color">Mau highlight khi chon chi tiet:</label><input id="selected-color" type="color" value="#00c8ff"></div>
            <div class="actions"><button id="toggle">Bat overlay</button><button id="add">+ Them Tag</button><button id="refresh" class="secondary">Lam moi cache</button></div>
            <table><thead><tr><th>Ten Tag</th><th>Mau highlight</th><th>Do day (px)</th></tr></thead><tbody id="rows"></tbody></table>
            <script>
              const bridge = (name, ...args) => window.sketchup && window.sketchup[name] && window.sketchup[name](...args);
              const rows = document.getElementById('rows');
              function send(row) { const name=row.querySelector('.tag-name').value.trim(); bridge('upsertTag', row.dataset.name || '', name, row.querySelector('.xray').checked ? 'true' : 'false', row.querySelector('.color').value, row.querySelector('.width').value); row.dataset.name=name; }
              function addRow(tag={name:'',xray:true,color:'#ff3b30',width:3}) { const tr=document.createElement('tr'); tr.dataset.name=tag.name || ''; tr.innerHTML='<td><div class="tag"><input class="tag-name" type="text" placeholder="Nhap ten Tag"><label class="xray-label" title="Hien highlight xuyen qua vat the"><input class="xray" type="checkbox"> Xuyen obj</label><button class="remove" title="Xoa Tag">×</button></div></td><td><input class="color" type="color"></td><td><input class="width" type="number" min="0.1" max="10" step="0.1"></td>'; tr.querySelector('.tag-name').value=tag.name || ''; tr.querySelector('.xray').checked=tag.xray !== false; tr.querySelector('.color').value=tag.color || '#ff3b30'; tr.querySelector('.width').value=tag.width || 3; tr.querySelectorAll('input').forEach(input => input.addEventListener('change', () => send(tr))); tr.querySelector('.remove').addEventListener('click', () => { if(tr.dataset.name) bridge('removeTag', tr.dataset.name); else tr.remove(); }); rows.appendChild(tr); }
              window.MHHighlight = { render(data) {
                document.getElementById('toggle').textContent = data.enabled ? 'Tat overlay' : 'Bat overlay';
                document.getElementById('status').textContent = data.scanning ? 'Dang cap nhat cache...' : (data.edge_count || 0).toLocaleString() + ' edge da cache';
                document.getElementById('selected-color').value = data.selectedColor || '#00c8ff';
                rows.innerHTML = '';
                data.tags.forEach(addRow);
              }};
              document.getElementById('toggle').addEventListener('click', () => bridge('toggleOverlay'));
              document.getElementById('selected-color').addEventListener('change', event => bridge('setSelectedColor', event.target.value));
              document.getElementById('add').addEventListener('click', () => addRow());
              document.getElementById('refresh').addEventListener('click', () => bridge('refreshCache'));
              bridge('ready');
            </script>
          </body></html>
        HTML
      end
    end

    start
  end
end
