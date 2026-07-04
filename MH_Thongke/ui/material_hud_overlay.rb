# encoding: utf-8
# MH_Thongke - Material HUD viewport overlay.

module MH_Thongke
  if defined?(Sketchup::Overlay)
    class MaterialHudViewportOverlay < Sketchup::Overlay
      OVERLAY_ID = "mh.thongke.material_hud"
      OVERLAY_NAME = "MH Thongke Material HUD"

      def initialize
        super(OVERLAY_ID, OVERLAY_NAME)
      end

      def start
        Sketchup.active_model.active_view.invalidate rescue nil
      end

      def stop
        Sketchup.active_model.active_view.invalidate rescue nil
      end

      def draw(view)
        data = MH_Thongke.material_overlay_data
        draw_panel(view, data)
      rescue => e
        puts "MaterialHudViewportOverlay draw error: #{e.message}"
      end

      private

      def draw_panel(view, data)
        data = data.is_a?(Hash) ? data : {}
        panel_w = MH_Thongke::HUD_PANEL_WIDTH
        pad = MH_Thongke::HUD_PANEL_PADDING
        row_h = MH_Thongke::HUD_ROW_HEIGHT
        title_h = MH_Thongke::HUD_TITLE_HEIGHT
        header_h = MH_Thongke::HUD_HEADER_HEIGHT
        rows = Array(data[:draw_rows] || data[:rows]).map { |row| row.is_a?(Hash) ? row : {} }
        message = (data[:draw_message] || data[:message]).to_s
        max_visible_rows = MH_Thongke.const_defined?(:HUD_MAX_VISIBLE_ROWS) ? MH_Thongke::HUD_MAX_VISIBLE_ROWS : 9
        visible_count = rows.empty? ? 1 : [rows.size, max_visible_rows].min
        more_h = rows.size > max_visible_rows ? 14 : 0
        panel_h = pad + title_h + header_h + visible_count * row_h + more_h + 4
        panel_h = [panel_h, view.vpheight.to_i].min
        x0, y0 = MH::OverlayEngine.panel_origin(view, panel_w, panel_h, anchor: :bottom_right)

        draw_rect(view, x0, y0, panel_w, panel_h, MH_Thongke::HUD_COLOR_PANEL)

        title = data[:draw_title].to_s
        title = truncate_text(data[:title].to_s, 58) if title.empty?
        MH::OverlayEngine.text(view, x0 + pad, y0 + 5, title.empty? ? "SP: --" : title, color: MH_Thongke::HUD_COLOR_TITLE, size: 10, bold: true)

        table_y = y0 + pad + title_h
        name_w = MH_Thongke::HUD_NAME_COLUMN_WIDTH
        note_w = MH_Thongke::HUD_NOTE_COLUMN_WIDTH
        status_w = panel_w - pad * 2 - name_w - note_w
        table_x = x0 + pad

        draw_rect(view, table_x, table_y, panel_w - pad * 2, header_h, MH_Thongke::HUD_COLOR_HEADER_BG)
        MH::OverlayEngine.text(view, table_x + 6, table_y + 5, "TEN HANG", color: MH_Thongke::HUD_COLOR_WHITE, size: 8, bold: true)
        MH::OverlayEngine.text(view, table_x + name_w + 6, table_y + 5, "GHI CHU", color: MH_Thongke::HUD_COLOR_WHITE, size: 8, bold: true)
        MH::OverlayEngine.text(view, table_x + name_w + note_w + 4, table_y + 5, "TRANG THAI", color: MH_Thongke::HUD_COLOR_WHITE, size: 8, bold: true)

        y = table_y + header_h
        max_rows = visible_count
        if rows.empty?
          MH::OverlayEngine.text(view, table_x + 6, y + 8, message.empty? ? "Khong co du lieu." : message, color: MH_Thongke::HUD_COLOR_EMPTY_TEXT, size: 9)
        else
          rows.first(max_rows).each do |row|
            if row[:type] == :product
              draw_rect(view, table_x, y, panel_w - pad * 2, row_h, MH_Thongke::HUD_COLOR_PRODUCT_BG)
              MH::OverlayEngine.text(view, table_x + 6, y + 7, (row[:draw_title] || truncate_text(row[:title], 54)).to_s, color: MH_Thongke::HUD_COLOR_PRODUCT_TEXT, size: 8, bold: true)
            else
              draw_rect(view, table_x, y, panel_w - pad * 2, row_h, MH_Thongke::HUD_COLOR_ROW_BG)
              MH::OverlayEngine.text(view, table_x + 6, y + 3, (row[:draw_name] || truncate_text(row[:name], 40)).to_s, color: MH_Thongke::HUD_COLOR_ROW_TEXT, size: 8)
              sub = row.key?(:draw_sub) ? row[:draw_sub].to_s : hud_sub_text(row)
              unless sub.empty?
                MH::OverlayEngine.text(view, table_x + 6, y + 15, sub, color: MH_Thongke::HUD_COLOR_SUB_TEXT, size: 6)
              end
              MH::OverlayEngine.text(view, table_x + name_w + 6, y + 6, (row[:draw_note] || truncate_text(row[:note], 12)).to_s, color: MH_Thongke::HUD_COLOR_NOTE_TEXT, size: 8)
              draw_status(view, table_x + name_w + note_w + 5, y + 5, status_w - 10, 16, row[:draw_status] || row[:status])
            end
            y += row_h
          end
          if rows.size > max_rows
            MH::OverlayEngine.text(view, table_x + 6, y + 4, "+#{rows.size - max_rows} dong nua...", color: MH_Thongke::HUD_COLOR_MORE_TEXT, size: 8)
          end
        end
      end

      def draw_status(view, x, y, w, h, status)
        color, text_color, label = MH_Thongke.material_hud_status_draw_style(status)
        draw_rect(view, x, y, w, h, color)
        MH::OverlayEngine.text(view, x + 7, y + 3, label, color: text_color, size: 8, bold: true)
      end

      def hud_sub_text(row)
        sub = row[:target].to_s.strip
        return "" if sub.empty?
        return "" if MH_Thongke.import_name_norm(sub) == MH_Thongke.import_name_norm(row[:name])
        return "" if MH_Thongke.material_code_norm(sub) == MH_Thongke.material_code_norm(row[:name])

        sub
      rescue
        ""
      end

      def draw_rect(view, x, y, w, h, color)
        MH::OverlayEngine.rect(view, x, y, w, h, color, (@rect_points ||= [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]]))
      end

      def truncate_text(value, max_chars)
        text = MH_Thongke.fix_vietnamese_mojibake(value)
        text.length > max_chars ? "#{text[0, max_chars - 3]}..." : text
      end
    end
  end
  def self.material_overlay_data
    @material_overlay_data ||= prepare_material_overlay_draw_data({ title: "", rows: [], message: "Dang nap du lieu..." })
  end

  def self.hud_draw_signature(view = nil)
    [
      import_mini_refresh_signature,
      current_mini_products.join("|")
    ].join("::")
  rescue
    Time.now.to_f.to_s
  end

  def self.material_overlay_visible?
    @material_overlay && @material_overlay.respond_to?(:enabled?) && @material_overlay.enabled?
  rescue
    false
  end

  def self.register_material_overlay
    return nil unless defined?(Sketchup::Overlay)

    model = Sketchup.active_model
    if @material_overlay.nil? || @material_overlay_model != model
      @material_overlay = MaterialHudViewportOverlay.new
      model.overlays.add(@material_overlay)
      @material_overlay_model = model
    end
    @material_overlay
  rescue => e
    puts "register_material_overlay error: #{e.message}"
    nil
  end

  def self.show_import_material_overlay(product_code = nil, force_enable = nil)
    @model = Sketchup.active_model
    overlay = register_material_overlay
    unless overlay
      UI.messagebox("SketchUp nay khong ho tro Viewport Overlay.")
      return
    end

    enable = force_enable.nil? ? !overlay.enabled? : !!force_enable
    if enable
      # First paint must be instant: do not resolve products, attach observers,
      # invalidate caches, or build HUD rows synchronously in the toggle call.
      @material_hud_lazy_open = true
      @material_overlay_data ||= prepare_material_overlay_draw_data({ title: mini_product_display_title, rows: [], message: "Dang nap du lieu..." })
      @material_overlay_last_draw_sig = nil
    else
      @material_hud_lazy_open = false
    end
    overlay.enabled = enable
    @model.active_view.invalidate
    if enable
      UI.start_timer(0.05, false) do
        next unless material_overlay_visible?

        attach_observers
        set_mini_group_mode(@mini_group_mode)
        mini_product_source_mode
        if product_code
          set_mini_products([product_code])
        else
          products = material_hud_safe_products if respond_to?(:material_hud_safe_products)
          set_mini_products(products) if products && !products.empty?
        end

        # Mở HUD phải nhẹ: vẽ ngay dữ liệu cache đang có, không xoá cache/force
        # rebuild. Refresh nhẹ chạy sau và tôn trọng debounce/cache hiện tại.
        UI.start_timer(0.8, false) do
          next unless material_overlay_visible?

          @material_hud_lazy_open = false
          refresh_material_overlay_data(false, false, false)
        end
      end
    else
      detach_observers_if_idle
    end
  rescue => e
    puts "show_import_material_overlay error: #{e.class}: #{e.message}"
    UI.messagebox("Material HUD loi:\n#{e.class}: #{e.message}") rescue nil
  end

  def self.refresh_material_overlay_data(process_model = true, load_excel = false, force = false, invalidate_view = true)
    return if !force && !material_overlay_visible?
    return if !force && respond_to?(:sketchup_ui_foreground?) && !sketchup_ui_foreground?
    return if @material_overlay_refresh_busy
    @material_overlay_refresh_busy = true

    now = Time.now.to_f
    min_interval = respond_to?(:mini_and_hud_visible?) && mini_and_hud_visible? ? 3.0 : (respond_to?(:mini_dialog_visible?) && mini_dialog_visible? ? 2.4 : 1.4)
    return if !force && @material_overlay_last_refresh_at && now - @material_overlay_last_refresh_at.to_f < min_interval

    if respond_to?(:sync_mini_products_from_active_source)
      sync_mini_products_from_active_source(force, false)
    else
      refresh_mini_products_from_source(false) if force || current_mini_products.empty?
    end
    state_sig = import_mini_refresh_signature
    if !force && !process_model && !load_excel &&
       @material_overlay_last_state_sig == state_sig &&
       @material_overlay_data
      @material_overlay_last_refresh_at = now
      return
    end

    next_data = build_material_overlay_draw_data(process_model, load_excel)
    data_changed = next_data != @material_overlay_data
    @material_overlay_data = next_data
    @material_overlay_last_state_sig = import_mini_refresh_signature
    @material_overlay_last_refresh_at = now
    schedule_material_hud_cache_prewarm(0.2) if force || load_excel || @material_hud_prewarm_sig != material_hud_all_product_cache_signature
    begin
      Sketchup.active_model.active_view.invalidate if invalidate_view && (force || data_changed)
    rescue
    end
  rescue => e
    @material_overlay_data = prepare_material_overlay_draw_data({ title: "", rows: [], message: "Loi HUD: #{e.message}" })
    puts "refresh_material_overlay_data error: #{e.message}"
  ensure
    @material_overlay_refresh_busy = false
  end

  def self.open_import_material_hud(product_code = nil)
    show_import_material_overlay(product_code, true)
  end

end
