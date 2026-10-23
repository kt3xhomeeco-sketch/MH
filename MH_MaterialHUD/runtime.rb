# encoding: UTF-8
module MH
  module MaterialHUD
    # Remove the short-lived reservation API when this file is reloaded in a
    # running SketchUp session. The standalone HUD no longer changes SuperImp's
    # layout.
    remove_const(:PANEL_WIDTH) if const_defined?(:PANEL_WIDTH, false)
    MODE_ATTR_DICT = 'MH_MaterialHUD'.freeze unless const_defined?(:MODE_ATTR_DICT, false)
    MODE_ATTR_KEY = 'display_mode'.freeze unless const_defined?(:MODE_ATTR_KEY, false)

    class << self
      attr_reader :data, :last_refresh_ms, :index, :tool

      remove_method(:right_reserved_width) if method_defined?(:right_reserved_width)

      def mode
        @mode ||= stored_mode
      end

      def visible?
        !!(@overlay && @overlay_model == Sketchup.active_model && @overlay.enabled?)
      rescue RuntimeError => e
        raise unless e.message.to_s.downcase.include?('invalid overlay')

        # The overlay can become stale after a live plugin reload or when a
        # model changes. It must not make a JSON reload fail in another app.
        @overlay = nil
        @overlay_model = nil
        false
      end

      def set_mode(value)
        @mode = value.to_s == 'select' ? 'select' : 'view'
        if @mode == 'select' && @index_timer
          UI.stop_timer(@index_timer)
          @index_timer = nil
        elsif @mode == 'view' && @selection_material_timer
          UI.stop_timer(@selection_material_timer)
          @selection_material_timer = nil
        end
        model = Sketchup.active_model
        model.set_attribute(MODE_ATTR_DICT, MODE_ATTR_KEY, @mode) if model && model.respond_to?(:set_attribute)
        Sketchup.write_default(MODE_ATTR_DICT, MODE_ATTR_KEY, @mode) if Sketchup.respond_to?(:write_default)
        @scroll = 0
        refresh if visible?
        Sketchup.status_text = "Material HUD: #{mode.upcase} | Tab: View / Select | Click: chọn | Esc: thoát công cụ"
        mode
      end

      def toggle_mode
        set_mode(mode == 'view' ? 'select' : 'view')
      end

      def show
        bind_model
        @overlay.enabled = true
        load_source unless @catalog
        @tool = InteractionTool.new
        Sketchup.active_model.select_tool(@tool)
        schedule_refresh
        true
      end

      def hide
        @overlay.enabled = false if @overlay
        stop_timers
        @picked_path = @picked_selection_ids = nil
        @picked_paths_by_entity = {}
        @index = nil unless @index && @index.complete
        Sketchup.active_model.select_tool(nil) if @tool_active
        Sketchup.active_model.active_view.invalidate
      end

      def toggle
        visible? ? hide : show
      end

      def bind_model
        model = Sketchup.active_model
        return if @overlay_model == model && (@overlay.nil? || overlay_usable?)
        if @pick_model && @pick_model != model
          @picked_paths_by_entity = {}
          @picked_path = @picked_selection_ids = nil
        end
        stop_timers
        @product_store.dispose if @product_store
        @product_store = nil
        @pending_model_change = false
        @pending_view_change = false
        @camera_event_signature = nil
        begin
          @overlay.enabled = false if @overlay
        rescue RuntimeError => e
          raise unless e.message.to_s.downcase.include?('invalid overlay')
          @overlay = nil
          @overlay_model = nil
        end
        @overlay_model = model
        @mode = stored_mode(model)
        @overlay = ViewportOverlay.new
        model.overlays.add(@overlay)
        @catalog = nil
        @index = nil
        reset_selection_material_indexes
        @selection_resolver = nil
        @selection_resolver_model = nil
        @index_revision = 0
        @data = { rows: [], message: 'Đang nạp JSON...' }
      end

      def stored_mode(model = Sketchup.active_model)
        saved = if model && model.respond_to?(:get_attribute)
          model.get_attribute(MODE_ATTR_DICT, MODE_ATTR_KEY, nil)
        end
        saved = Sketchup.read_default(MODE_ATTR_DICT, MODE_ATTR_KEY, 'view') if saved.to_s.empty? && Sketchup.respond_to?(:read_default)
        saved.to_s == 'select' ? 'select' : 'view'
      rescue
        'view'
      end

      def load_source(path = nil, force: false)
        # accept_snapshot and source persistence can synchronously emit model
        # observer callbacks while @catalog is nil. Let the outer load finish.
        if @loading_source
          return ProjectData.snapshot
        end

        @loading_source = true
        begin
        # Registry records the exact project JSON it has just generated/reloaded.
        # Prefer that shared runtime file over ProjectData's older model fallback,
        # otherwise HUD can reopen on a legacy JSON with only material codes.
        registry_json = if !path && defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:last_mvl_json_path)
          MH::RegistryApp.last_mvl_json_path.to_s.strip
        end
        registry_snapshot = nil
        if !path && defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:load_runtime_project_data)
          sources, registry_snapshot = MH::RegistryApp.load_runtime_project_data([], reason: 'material_hud_registry_runtime')
          registry_snapshot = nil unless sources && sources['ok']
        end
        snapshot = if path
          ProjectData.load_json(path, force: force, reason: 'material_hud')
        elsif registry_snapshot
          registry_snapshot
        elsif !registry_json.to_s.empty? && File.exist?(registry_json)
          ProjectData.load_json(registry_json, force: force, reason: 'material_hud_registry_runtime')
        else
          ProjectData.ensure_loaded
        end
        # Optional startup discovery only; no Registry app is loaded here.
        # With Registry disabled, remembered paths / Choose JSON still work.
        if !path && !snapshot[:ok] && defined?(MH::RegistryApp) && MH::RegistryApp.respond_to?(:last_mvl_json_path)
          discovered = MH::RegistryApp.last_mvl_json_path.to_s
          snapshot = ProjectData.load_json(discovered, force: force, reason: 'material_hud_discovery') unless discovered.empty?
        end
        accept_snapshot(snapshot)
        ensure
          @loading_source = false
        end
      end

      def choose_json
        path = UI.openpanel('Material HUD — chọn JSON dùng chung', nil, 'JSON|*.json||')
        return unless path
        load_source(path, force: true)
        schedule_refresh
      end

      def reload_json
        load_source(nil, force: true)
        schedule_refresh
      end

      def accept_snapshot(snapshot)
        if !snapshot || !snapshot[:ok] || snapshot[:model_key] != ProjectData.current_model_key
          @catalog = nil
          @source_error = (snapshot && snapshot[:error]).to_s
          @data = { rows: [], message: 'Chưa có JSON hợp lệ. Chọn JSON trong menu HUD.' }
          return false
        end
        signature = [snapshot[:model_key], snapshot[:version], snapshot[:json_path]]
        if !@catalog || @catalog.signature != signature
          @catalog = Catalog.new(snapshot)
          @scroll = 0
        end
        @source_error = nil
        true
      end

      # Called by Registry RELOAD; no Excel conversion and no second JSON parse.
      def reload_project_data(snapshot)
        ok = accept_snapshot(snapshot)
        refresh if visible?
        { 'ok' => ok, 'visible' => visible?, 'rows_count' => @catalog ? @catalog.row_count : 0 }
      rescue => e
        @catalog = nil
        @source_error = e.message
        @data = { rows: [], message: "Lỗi nạp JSON: #{e.message}" }
        Sketchup.active_model.active_view.invalidate if visible?
        { 'ok' => false, 'error' => e.message }
      end

      def overlay_usable?
        return false unless @overlay

        @overlay.enabled?
        true
      rescue RuntimeError => e
        raise unless e.message.to_s.downcase.include?('invalid overlay')

        @overlay = nil
        @overlay_model = nil
        false
      end

      def model_changed
        bind_model if @overlay_model != Sketchup.active_model
        @pending_model_change = true
        unless @product_store
          @index = nil
          reset_selection_material_indexes
        end
        @selection_resolver = nil
        @selection_resolver_model = nil
        @index_revision = @index_revision.to_i + 1
        UI.stop_timer(@index_timer) if @index_timer
        @index_timer = nil
        UI.stop_timer(@selection_material_timer) if @selection_material_timer
        @selection_material_timer = nil
        load_source unless @catalog
        schedule_refresh if visible?
      end

      # Called by material editors (for example MH Van) after their operation
      # commits. This is deliberately separate from model_changed: SketchUp
      # does not consistently emit a ModelObserver transaction event for an
      # in-place Material#name change on every supported version.
      def model_materials_changed
        return false unless visible?

        if @product_store
          @pending_model_change = true
          flush_model_changes
        else
          @index = nil
          reset_selection_material_indexes
        end
        @index_revision = @index_revision.to_i + 1
        @draw_signature = nil
        UI.stop_timer(@index_timer) if @index_timer
        @index_timer = nil
        schedule_refresh
        true
      rescue
        false
      end

      def begin_material_change(entities, recursive: false)
        return nil unless @product_store
        flush_model_changes
        @product_store.begin_material_change(entities, recursive: recursive)
      end

      def finish_material_change(token)
        return model_materials_changed unless token && @product_store
        @product_store.finish_material_change(token)
        model_materials_changed
      end

      def schedule_refresh
        return unless visible?
        return if @view_settle_timer
        return if @refresh_timer
        @refresh_timer = UI.start_timer(0.05, false) do
          @refresh_timer = nil
          refresh if visible?
        end
      end

      def ensure_index
        unless @index
          @index = ensure_product_store || ModelIndex.new(Sketchup.active_model)
          @index_revision = @index_revision.to_i + 1
        end
        run_index_slice unless @index.complete || @index_timer
      end

      def ensure_product_store(products = [])
        model = Sketchup.active_model
        return nil unless model && model.respond_to?(:entities)
        if !@product_store || @product_store.model != model
          @product_store.dispose if @product_store
          priority = selection_target_contexts(model).filter_map { |entry| Array(entry[:instance_path]).first }
          @product_store = ProductStore.new(model, priority_roots: priority.uniq, priority_products: products)
        end
        @product_store
      end

      def flush_model_changes
        unless @product_store
          if @pending_model_change
            @index = nil
            reset_selection_material_indexes
          end
          @pending_model_change = false
          return
        end
        if @pending_model_change
          model = Sketchup.active_model
          products = mode == 'select' ? products_for_selection(model) : Array((@data || {})[:products])
          roots = selection_target_contexts(model).filter_map { |entry| Array(entry[:instance_path]).first }
          @product_store.prioritize_changes(products, roots)
        end
        affected = @product_store.synchronize(unknown_if_untracked: !!@pending_model_change)
        @pending_model_change = false
        if affected == :all
          reset_selection_material_indexes
        elsif !affected.empty?
          @selection_material_indexes ||= {}
          invalid = @selection_material_indexes.select { |key, _index| !(key & affected).empty? }
          if invalid.value?(@selection_material_index)
            UI.stop_timer(@selection_material_timer) if @selection_material_timer
            @selection_material_timer = @selection_material_index = nil
          end
          invalid.each_key { |key| @selection_material_indexes.delete(key) }
        end
        @index_revision = @index_revision.to_i + 1 unless affected == []
      end

      def reset_selection_material_indexes
        UI.stop_timer(@selection_material_timer) if @selection_material_timer
        @selection_material_timer = nil
        @selection_material_indexes = {}
        @selection_material_index = nil
        @selection_material_started_at = nil
        @selection_material_scan_ms = nil
        @selection_material_first_match_ms = nil
        @last_material_slice_ms = @max_material_slice_ms = nil
        @selection_material_signature = nil
        @selection_material_view_signature = nil
      end

      def ensure_selection_material_index(products)
        return @index if @index.is_a?(ModelIndex) && @index.complete
        if products.empty?
          UI.stop_timer(@selection_material_timer) if @selection_material_timer
          @selection_material_timer = @selection_material_index = nil
          return nil
        end

        view_signature = selection_material_view_signature
        reset_selection_material_indexes if @selection_material_view_signature && @selection_material_view_signature != view_signature
        @selection_material_view_signature = view_signature

        key = products.uniq.sort
        @product_store.prioritize(key) if @product_store
        @selection_material_indexes ||= {}
        candidate = @selection_material_indexes[key]
        unless candidate
          @selection_material_indexes.clear if @selection_material_indexes.size >= 24
          store = ensure_product_store(key)
          candidate = store ? store.scan(key) : ModelIndex.new(Sketchup.active_model, products: key)
          @selection_material_indexes[key] = candidate
          @index_revision = @index_revision.to_i + 1
        end
        unless @selection_material_index.equal?(candidate)
          UI.stop_timer(@selection_material_timer) if @selection_material_timer
          @selection_material_timer = nil
          @selection_material_index = candidate
          @selection_material_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @selection_material_first_match_ms = nil
          @selection_material_scan_ms = candidate.complete ? 0.0 : nil
          @selection_material_signature = nil
        end
        # A product scan advances the same directory. Never run two timer
        # chains against it at once in VIEW mode.
        if @product_store && @index_timer
          UI.stop_timer(@index_timer)
          @index_timer = nil
        end
        run_selection_material_slice unless candidate.complete || @selection_material_timer
        candidate
      end

      def run_selection_material_slice
        @selection_material_timer = nil
        return if @view_settle_timer
        return unless @selection_material_index
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        complete = @selection_material_index.step(0.004)
        @last_material_slice_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
        @max_material_slice_ms = [@max_material_slice_ms.to_f, @last_material_slice_ms].max
        if complete
          @selection_material_timer = nil
          @selection_material_scan_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @selection_material_started_at) * 1000).round(2)
          refresh if visible?
        else
          # Shorter gaps only until the first observed material. Slices stay
          # bounded at 4 ms and camera motion still pauses the scan entirely.
          delay = @selection_material_first_match_ms ? 0.03 : 0.01
          @selection_material_timer = UI.start_timer(delay, false) { run_selection_material_slice }
          signature = @selection_material_index.materials.map { |product, materials| [product, materials.keys.sort] }.sort
          if @selection_material_signature != signature
            @selection_material_signature = signature
            unless signature.all? { |_, keys| keys.empty? }
              @selection_material_first_match_ms ||= ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @selection_material_started_at) * 1000).round(2)
              refresh if visible? && mode == 'select'
            end
          end
        end
      rescue => e
        @selection_material_timer = nil
        @data = { rows: [], message: "Lỗi đọc vật liệu: #{e.message}" }
        puts "[MH Material HUD] #{e.full_message}"
      end

      def run_index_slice
        # MH Material can request product ownership while its HUD overlay is
        # hidden. Keep indexing in timer slices so that the shared resolver can
        # become ready without requiring the user to open this HUD first.
        @index_timer = nil
        return if @view_settle_timer
        return unless @index
        if @index.step(0.004)
          @index_timer = nil
          refresh if visible?
        else
          @index_timer = UI.start_timer(0.03, false) { run_index_slice }
        end
      rescue => e
        @index_timer = nil
        @data = { rows: [], message: "Lỗi đọc model: #{e.message}" }
        puts "[MH Material HUD] #{e.full_message}"
      end

      def refresh
        return unless visible?
        return if @view_settle_timer
        apply_pending_view_change
        @camera_event_signature = ProductContext.spatial_view_signature(Sketchup.active_model.active_view)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        flush_model_changes
        snapshot = ProjectData.snapshot
        accept_snapshot(snapshot)
        if mode == 'select'
          products = products_for_selection(Sketchup.active_model)
          material_index = ensure_selection_material_index(products)
        else
          ensure_index
          products = @index.visible_products(Sketchup.active_model.active_view)
          material_index = @index.is_a?(ProductStore) ? ensure_selection_material_index(products) : @index
        end
        if @catalog
          @scroll = 0 if (@data || {})[:products] != products
          rows = products.flat_map do |product|
            materials = (material_index ? material_index.materials[product] : nil) || {}
            complete = !!(material_index && material_index.complete)
            section = @catalog.section(product, materials, @index_revision, complete: complete)
            [{ type: :product, name: product, product_name: @catalog.product_name(product) }] + section
          end
          message = if material_index && !material_index.complete
            mode == 'select' ? 'Đang đọc vật liệu sản phẩm...' : 'Đang lập chỉ mục model...'
          elsif products.empty?
            mode == 'select' ? 'Chọn đối tượng có mã sản phẩm.' : 'Không có sản phẩm trong vùng nhìn.'
          else
            'Không có vật liệu cho sản phẩm này.'
          end
          @data = { rows: rows, message: message, products: products, path: @catalog.path,
            indexing: !!(material_index && !material_index.complete) }
        end
        @last_refresh_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
        draw_signature = [@data, mode, @scroll]
        if @draw_signature != draw_signature
          @draw_signature = draw_signature
          Sketchup.active_model.active_view.invalidate
        end
      rescue => e
        @data = { rows: [], message: "Lỗi HUD: #{e.message}" }
        puts "[MH Material HUD] #{e.full_message}"
      end

      def stop_timers
        UI.stop_timer(@refresh_timer) if @refresh_timer
        UI.stop_timer(@index_timer) if @index_timer
        UI.stop_timer(@selection_material_timer) if @selection_material_timer
        UI.stop_timer(@view_settle_timer) if @view_settle_timer
        @view_settle_timer = nil
        @selection_material_timer = nil
        @refresh_timer = @index_timer = nil
        @index = nil if @index && !@index.complete
      end

      # Called by InteractionTool immediately after it updates SketchUp's
      # selection. Keep this only while that exact selection remains active;
      # normal SketchUp selections must never reuse a stale pick path.
      def remember_pick_path(path, selected_entity, selected_entities: nil, additive: false)
        selected_entities = [selected_entity] if selected_entities.nil? && selected_entity
        ids = selected_entity_ids(selected_entities)
        @picked_paths_by_entity ||= {}
        if additive
          @picked_paths_by_entity.select! { |id, _path| ids.include?(id) }
        else
          @picked_paths_by_entity = {}
        end
        picked_id = selected_entity.entityID if selected_entity && selected_entity.respond_to?(:entityID)
        picked_path = Array(path).select { |entity| entity && entity.respond_to?(:valid?) && entity.valid? }
        if picked_id && ids.include?(picked_id) && !picked_path.empty?
          @picked_paths_by_entity[picked_id] = picked_path
          @picked_path = picked_path
        elsif !additive
          @picked_path = nil
        end
        @picked_selection_ids = ids
        @pick_model = Sketchup.active_model
      rescue
        @picked_path = @picked_selection_ids = nil
        @picked_paths_by_entity = {}
      end

      def picked_path_signature(model = Sketchup.active_model)
        return [] unless model && @picked_selection_ids == selected_entity_ids(model.selection.to_a)
        Array(@picked_paths_by_entity).sort_by { |id, _path| id }.map do |id, path|
          [id, *Array(path).filter_map { |entity| entity.entityID if entity.respond_to?(:entityID) }]
        end
      rescue
        []
      end

      def products_from_last_pick(selection)
        ids = Array(selection).filter_map { |entity| entity.entityID if entity.respond_to?(:entityID) }.sort
        return [] unless @picked_path && @picked_selection_ids == ids

        @index.products_for_entity_path(@picked_path)
      rescue
        []
      end

      # Shared read-only API for MH Material. It deliberately reuses the
      # spatial/index ownership already built by this standalone HUD; no Excel
      # parser or duplicate model scanner is introduced in MH Material.
      def material_choices_for_selection(model = Sketchup.active_model)
        bind_model
        load_source unless @catalog
        return { ok: false, materials: [], error: 'Chưa có JSON vật liệu hợp lệ.' } unless @catalog
        return { ok: false, materials: [], products: [], error: 'Chọn đối tượng thuộc một mã SP.' } unless model && !model.selection.empty?

        products = products_for_selection(model)
        return { ok: false, materials: [], products: [], error: 'Chọn đối tượng thuộc một mã SP.' } if products.empty?
        return { ok: false, materials: [], products: products, error: 'Chỉ chọn các đối tượng cùng một mã SP.' } if products.length > 1

        product = products.first
        material_options = @catalog.material_options_for_product(product)
        materials = material_options.map { |option| option[:code].to_s }.reject(&:empty?).uniq
        return { ok: false, materials: [], products: products, error: "SP #{product} không có mã vật liệu trong JSON." } if materials.empty?

        { ok: true, product: product, product_name: @catalog.product_name(product), products: products,
          materials: materials, material_options: material_options }
      rescue => e
        { ok: false, materials: [], error: e.message }
      end

      def products_for_selection(model = Sketchup.active_model)
        return [] unless model && !model.selection.empty?

        selected = model.selection.to_a
        contexts = selection_target_contexts(model)
        resolver = if @index && @index.respond_to?(:complete) && @index.complete &&
                      @index.respond_to?(:products_for_selected_entities)
          @index
        else
          selection_spatial_resolver(model)
        end
        index_contexts = contexts.empty? ? selected.map { |entity| { entity: entity, parent_transform: active_path_transform(model) } } : contexts
        indexed = index_contexts.flat_map do |entry|
          if entry[:instance_path] && resolver.respond_to?(:products_for_instance_path)
            resolver.products_for_instance_path(entry[:instance_path])
          else
            resolver.products_for_selected_entities([entry[:entity]], parent_transform: entry[:parent_transform])
          end
        end.uniq
        return indexed unless indexed.empty?

        picked_paths = if @picked_selection_ids == selected_entity_ids(selected)
          Array(@picked_paths_by_entity).values.flatten(1)
        else
          []
        end
        entities = picked_paths + Array(model.active_path) + selected
        direct = entities.flat_map { |entity| ProductContext.codes_for_entity(entity) }
          .map { |code| ProductContext.base(code) }.reject(&:empty?).uniq
        return direct unless direct.empty?
        @index && @index.respond_to?(:products_for_entities) ? @index.products_for_entities(entities).uniq : []
      rescue
        []
      end

      # Return the deepest component instance under the last HUD pick. In
      # Select mode SketchUp's Selection often contains only the picked Face;
      # the complete nested instance path is available from PickHelper.
      def selection_target_contexts(model = Sketchup.active_model)
        return [] unless model

        selected = model.selection.to_a
        ids = selected_entity_ids(selected)
        if @picked_selection_ids == ids && !Array(@picked_paths_by_entity).empty?
          contexts = []
          selected.each do |selected_entity|
            selected_id = selected_entity.entityID if selected_entity.respond_to?(:entityID)
            path = @picked_paths_by_entity[selected_id]
            if path && !path.empty?
              path_contexts = contexts_for_pick_path(path, model)
              if selected_entity.is_a?(Sketchup::Group) || selected_entity.is_a?(Sketchup::ComponentInstance)
                # When SketchUp selected a DC/Group itself, the pick path may
                # continue through one of its child details to the hit face.
                # Keep the selected instance as the assignment root so bulk
                # material assignment reaches all of its visible children.
                selected_context = path_contexts.reverse.find do |entry|
                  entry[:entity].entityID == selected_id
                end
                contexts << (selected_context || path_contexts.last) if path_contexts.any?
              else
                # A selected Face/Edge has no material instance of its own;
                # resolve it to the deepest Group/ComponentInstance in path.
                contexts << path_contexts.last if path_contexts.any?
              end
            elsif selected_entity.is_a?(Sketchup::Group) || selected_entity.is_a?(Sketchup::ComponentInstance)
              chain = Array(model.active_path) + [selected_entity]
              contexts << instance_path_context(chain, model, active_path_transform(model))
            end
          end
          return contexts.uniq { |entry| entry[:occurrence_signature] || [entry[:entity].entityID, entry[:parent_transform].object_id] } unless contexts.empty?
        end

        transform = active_path_transform(model)
        selected.filter_map do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          instance_path_context(Array(model.active_path) + [entity], model, transform)
        end
      rescue
        []
      end

      def contexts_for_pick_path(path, model = Sketchup.active_model)
        path = Array(path).select { |entity| entity && entity.respond_to?(:valid?) && entity.valid? }
        active_ids = Array(model && model.respond_to?(:active_path) ? model.active_path : nil).filter_map { |entity| entity.entityID rescue nil }
        path_ids = path.filter_map { |entity| entity.entityID rescue nil }
        unless active_ids.empty? || path_ids.first(active_ids.length) == active_ids
          path = Array(model.active_path) + path
        end
        transform = Geom::Transformation.new
        contexts = []
        instance_ids = []
        instance_path = []
        path.each do |entity|
          if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            instance_ids << (entity.entityID rescue nil)
            instance_path << entity
            contexts << instance_path_context(instance_path.dup, model, transform, instance_ids.dup)
            transform = transform * entity.transformation
          end
        end
        contexts
      rescue
        []
      end

      def instance_path_context(instance_path, model, parent_transform, occurrence_signature = nil)
        path = Array(instance_path)
        root = path.first
        root_slot = if root && model && model.respond_to?(:entities)
          model.entities.to_a.index(root)
        end
        child_slots = path.each_cons(2).map do |parent, child|
          entities = if parent.is_a?(Sketchup::Group)
            parent.entities
          elsif parent.respond_to?(:definition) && parent.definition
            parent.definition.entities
          else
            []
          end
          entities.to_a.index(child)
        end
        {
          entity: path.last,
          parent_transform: parent_transform,
          occurrence_signature: occurrence_signature || path.filter_map { |item| item.entityID rescue nil },
          instance_path: path,
          root_slot: root_slot,
          child_slots: child_slots
        }
      rescue
        { entity: path.last, parent_transform: parent_transform }
      end

      def selected_entity_ids(entities)
        Array(entities).filter_map { |entity| entity.entityID if entity.respond_to?(:entityID) }.sort
      rescue
        []
      end

      # Ctrl-click explicitly targets the deepest nested material instance in
      # the current PickHelper path; ordinary selection keeps the picked item.
      def deepest_material_instance_from_path(path, fallback = nil)
        Array(path).reverse.find do |entity|
          entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end || fallback
      end

      # Selection ownership needs only root product markers and the selected
      # instance path. Do not wait for the full-model index used in View mode.
      def selection_spatial_resolver(model)
        if @selection_resolver_model != model || !@selection_resolver
          @selection_resolver = ModelIndex.new(model)
          @selection_resolver_model = model
        end
        @selection_resolver
      end

      def view_changed
        signature = ProductContext.spatial_view_signature(Sketchup.active_model.active_view)
        return if @camera_event_signature == signature
        @camera_event_signature = signature
        @view_last_motion = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        # Observer callbacks must not remove thousands of observers, scan
        # geometry, or reset caches on every frame of an orbit.
        UI.stop_timer(@refresh_timer) if @refresh_timer
        UI.stop_timer(@index_timer) if @index_timer
        UI.stop_timer(@selection_material_timer) if @selection_material_timer
        @refresh_timer = @index_timer = @selection_material_timer = nil
        @pending_view_change = true
        return unless visible?
        @view_settle_timer ||= UI.start_timer(0.25, false) { settle_view_change }
      end

      def settle_view_change
        @view_settle_timer = nil
        return unless visible?
        quiet = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @view_last_motion
        if quiet < 0.25
          @view_settle_timer = UI.start_timer(0.25 - quiet, false) { settle_view_change }
          return
        end
        apply_pending_view_change
        schedule_refresh
      end

      def apply_pending_view_change
        return unless @pending_view_change
        @pending_view_change = false
        signature = selection_material_view_signature
        if @selection_material_view_signature && @selection_material_view_signature != signature
          @product_store.reset_ownership if @product_store
          @index = nil
          reset_selection_material_indexes
        else
          @product_store.refresh_probe if @product_store
        end
        @selection_resolver = nil
        @selection_resolver_model = nil
        @selection_material_view_signature = signature
      end

      def selection_material_view_signature
        view = Sketchup.active_model.active_view
        camera = view.camera if view.respond_to?(:camera)
        if camera && camera.respond_to?(:perspective?) && !camera.perspective?
          # Parallel-view pan/zoom translates/scales every marker equally;
          # product ownership is unchanged. Keep those completed scans cached.
          [camera.direction.to_a, camera.up.to_a].flatten.map { |value| value.round(6) }.hash
        else
          ProductContext.spatial_view_signature(view)
        end
      end

      # SketchUp returns selected entities relative to the current editing
      # context. Pair them with this transform before resolving their world
      # position (important for components nested several levels deep).
      def active_path_transform(model = Sketchup.active_model)
        Array(model && model.respond_to?(:active_path) ? model.active_path : nil)
          .reduce(Geom::Transformation.new) do |transform, entity|
            transform * entity.transformation
          end
      rescue
        Geom::Transformation.new
      end

      def tool_active=(value)
        @tool_active = value
      end

      def tool_active?
        !!@tool_active
      end

      def status
        material_index = @selection_material_index || @index
        { visible: visible?, mode: mode, json: @catalog && @catalog.path,
          rows_count: @catalog && @catalog.row_count, products: (@data || {})[:products],
          indexing: material_index && !material_index.complete, visited: material_index && material_index.visited,
          material_scan_ms: @selection_material_scan_ms,
          directory_roots: @product_store && @product_store.roots_count,
          directory_steps: @product_store && @product_store.visited,
          definitions_read: @product_store && @product_store.definitions.reads,
          observer_count: @product_store && @product_store.instance_variable_get(:@observers).length,
          last_slice_ms: @last_material_slice_ms, max_slice_ms: @max_material_slice_ms,
          first_material_ms: @selection_material_first_match_ms,
          refresh_ms: @last_refresh_ms, error: @source_error }
      end
    end
  end
end
