# encoding: utf-8
# MH_Thongke - Material HUD overlay refresh helpers.

module MH_Thongke
  remove_const(:MATERIAL_HUD_LIGHT_REFRESH_MIN_INTERVAL) if const_defined?(:MATERIAL_HUD_LIGHT_REFRESH_MIN_INTERVAL)
  MATERIAL_HUD_LIGHT_REFRESH_MIN_INTERVAL = 0.45

  def self.import_material_hud_screen_size
    require 'fiddle'
    user32 = Fiddle.dlopen('user32')
    get_metric = Fiddle::Function.new(user32['GetSystemMetrics'], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    [get_metric.call(0), get_metric.call(1)]
  rescue
    [nil, nil]
  end

  def self.schedule_import_material_hud_light_refresh(force_context = true, delay = nil)
    return unless material_hud_visible?

    delay = HUD_REFRESH_DELAY_SECONDS if delay.nil?
    UI.stop_timer(@mini_hud_refresh_timer) if @mini_hud_refresh_timer
    @mini_hud_refresh_timer = UI.start_timer(delay.to_f, false) do
      @mini_hud_refresh_timer = nil
      refresh_import_material_hud_light(force_context)
    end
  rescue => e
    @mini_hud_refresh_timer = nil
    puts "schedule_import_material_hud_light_refresh error: #{e.class}: #{e.message}"
  end

  def self.refresh_import_material_hud_light(force_context = true)
    products_before = current_mini_products
    if respond_to?(:sync_mini_products_from_active_source)
      sync_mini_products_from_active_source(force_context, false)
    elsif respond_to?(:mini_product_source_mode) && mini_product_source_mode == "view"
      refresh_mini_products_from_source(false) if force_context || current_mini_products.empty?
    else
      selected_products = selected_product_codes(false).select { |code| product_code_valid?(code) } rescue []
      if !selected_products.empty?
        set_mini_products(selected_products)
      elsif current_mini_products.empty?
        refresh_mini_products_from_source(false)
      end
    end

    load_import_excel_snapshot_only if (!@imported_excel_data || @imported_excel_data.empty?) && respond_to?(:load_import_excel_snapshot_only)
    if !@material_hud_lazy_open && (@current_report_items.nil? || @current_mat_items.nil?)
      respond_to?(:process_selection_cached) ? process_selection_cached(false) : process_selection
    end

    product_changed = current_mini_products != products_before
    invalidate_material_hud_caches if product_changed && respond_to?(:invalidate_material_hud_caches)
    schedule_material_hud_cache_prewarm(0.2)
    refresh_import_material_hud(false, false)
  rescue => e
    puts "refresh_import_material_hud_light error: #{e.class}: #{e.message}"
  end

  def self.show_import_material_hud(product_code = nil)
    show_import_material_overlay(product_code, nil)
  end

  def self.refresh_import_material_hud(process_model = true, load_excel = false)
    return unless respond_to?(:material_overlay_visible?) && material_overlay_visible?

    if !process_model && !load_excel
      now = Time.now.to_f
      delta = now - @mini_hud_last_light_refresh_at.to_f
      if @mini_hud_last_light_refresh_at.to_f > 0.0 && delta < MATERIAL_HUD_LIGHT_REFRESH_MIN_INTERVAL.to_f
        @mini_hud_refresh_pending ||= [false, false]
        unless @mini_hud_light_refresh_timer
          wait = [MATERIAL_HUD_LIGHT_REFRESH_MIN_INTERVAL.to_f - delta, 0.02].max
          @mini_hud_light_refresh_timer = UI.start_timer(wait, false) do
            @mini_hud_light_refresh_timer = nil
            refresh_import_material_hud(false, false) if material_hud_visible?
          end
        end
        return
      end
    end

    if @mini_hud_refresh_busy
      pending = @mini_hud_refresh_pending || [false, false]
      @mini_hud_refresh_pending = [pending[0] || process_model, pending[1] || load_excel]
      return
    end

    @mini_hud_refresh_busy = true
    refresh_material_overlay_data(process_model, load_excel, load_excel)
    @mini_hud_last_light_refresh_at = Time.now.to_f if !process_model && !load_excel
  ensure
    @mini_hud_refresh_busy = false
    if @mini_hud_refresh_pending && material_hud_visible?
      pending_model, pending_excel = @mini_hud_refresh_pending
      @mini_hud_refresh_pending = nil
      UI.start_timer(0.02, false) do
        refresh_import_material_hud(pending_model, pending_excel) if material_hud_visible?
      end
    end
  end
end
