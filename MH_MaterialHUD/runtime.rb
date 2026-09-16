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
      end

      def set_mode(value)
        @mode = value.to_s == 'select' ? 'select' : 'view'
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
        @index = nil unless @index && @index.complete
        Sketchup.active_model.select_tool(nil) if @tool_active
        Sketchup.active_model.active_view.invalidate
      end

      def toggle
        visible? ? hide : show
      end

      def bind_model
        model = Sketchup.active_model
        return if @overlay_model == model
        stop_timers
        @overlay.enabled = false if @overlay
        @overlay_model = model
        @mode = stored_mode(model)
        @overlay = ViewportOverlay.new
        model.overlays.add(@overlay)
        @catalog = nil
        @index = nil
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
        snapshot = if path
          ProjectData.load_json(path, force: force, reason: 'material_hud')
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
      end

      def choose_json
        path = UI.openpanel('Material HUD — chọn JSON dùng chung', nil, 'JSON|*.json||')
        return unless path
        load_source(path, force: true)
        schedule_refresh
      end

      def reload_json
        path = @catalog && @catalog.path
        load_source(path.to_s.empty? ? nil : path, force: true)
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
        bind_model
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

      def model_changed
        return unless @overlay && @overlay.enabled?
        bind_model
        @overlay.enabled = true
        @index = nil
        @index_revision = @index_revision.to_i + 1
        UI.stop_timer(@index_timer) if @index_timer
        @index_timer = nil
        load_source unless @catalog
        schedule_refresh
      end

      def schedule_refresh
        return unless visible?
        return if @refresh_timer
        @refresh_timer = UI.start_timer(0.05, false) do
          @refresh_timer = nil
          refresh if visible?
        end
      end

      def ensure_index
        return if @index
        @index = ModelIndex.new(Sketchup.active_model)
        @index_revision = @index_revision.to_i + 1
        run_index_slice
      end

      def run_index_slice
        return unless visible? && @index
        if @index.step
          @index_timer = nil
          refresh
        else
          @index_timer = UI.start_timer(0.01, false) { run_index_slice }
        end
      rescue => e
        @index_timer = nil
        @data = { rows: [], message: "Lỗi đọc model: #{e.message}" }
        puts "[MH Material HUD] #{e.full_message}"
      end

      def refresh
        return unless visible?
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        snapshot = ProjectData.snapshot
        accept_snapshot(snapshot)
        ensure_index
        products = if mode == 'select'
          model = Sketchup.active_model
          if model.selection.empty?
            []
          else
            (Array(model.active_path) + model.selection.to_a).flat_map { |entity| ProductContext.codes_for_entity(entity) }
              .map { |code| ProductContext.base(code) }.uniq
          end
        else
          @index.visible_products(Sketchup.active_model.active_view)
        end
        if @catalog
          @scroll = 0 if (@data || {})[:products] != products
          rows = products.flat_map do |product|
            section = @catalog.section(product, @index.materials[product], @index_revision, complete: @index.complete)
            [{ type: :product, name: product, product_name: @catalog.product_name(product) }] + section
          end
          message = if !@index.complete
            'Đang lập chỉ mục model...'
          elsif products.empty?
            mode == 'select' ? 'Chọn đối tượng có mã sản phẩm.' : 'Không có sản phẩm trong vùng nhìn.'
          else
            'Không có vật liệu cho sản phẩm này.'
          end
          @data = { rows: rows, message: message, products: products, path: @catalog.path, indexing: !@index.complete }
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
        @refresh_timer = @index_timer = nil
        @index = nil if @index && !@index.complete
      end

      def tool_active=(value)
        @tool_active = value
      end

      def tool_active?
        !!@tool_active
      end

      def status
        { visible: visible?, mode: mode, json: @catalog && @catalog.path,
          rows_count: @catalog && @catalog.row_count, products: (@data || {})[:products],
          indexing: @index && !@index.complete, visited: @index && @index.visited,
          refresh_ms: @last_refresh_ms, error: @source_error }
      end
    end
  end
end
