# encoding: utf-8
# MH_Thongke - Material HUD cache helpers.

module MH_Thongke
  def self.material_hud_cache_key(process_model = false, load_excel = false)
    [
      current_mini_products.join("|"),
      mini_group_mode,
      respond_to?(:mini_product_source_mode) ? mini_product_source_mode : "",
      @import_excel_loaded_path.to_s,
      @import_excel_loaded_mtime.to_f,
      (@imported_excel_data || []).size,
      respond_to?(:mini_excel_rows_signature) ? mini_excel_rows_signature(@imported_excel_data) : (@imported_excel_data || []).hash,
      respond_to?(:mini_model_rows_signature) ? mini_model_rows_signature(@current_report_items) : (@current_report_items || []).hash,
      respond_to?(:mini_model_rows_signature) ? mini_model_rows_signature(@current_mat_items) : (@current_mat_items || []).hash,
      @process_selection_cache_sig.to_s,
      (@match_rules || {}).hash,
      respond_to?(:mini_rules_source_signature) ? mini_rules_source_signature : "",
      (@mini_accept_rules || {}).hash,
      respond_to?(:mini_hidden_excel_items_signature) ? mini_hidden_excel_items_signature : 0,
      respond_to?(:hidden_names_signature) ? hidden_names_signature : "",
      defined?(MATERIAL_CODE_NORM_VERSION) ? MATERIAL_CODE_NORM_VERSION : 0,
      process_model ? "pm1" : "pm0",
      load_excel ? "xl1" : "xl0"
    ].join("::")
  rescue
    Time.now.to_f.to_s
  end

  def self.material_hud_cache_fetch(cache_name, cache_key)
    return instance_cache_fetch(cache_name, cache_key) if respond_to?(:instance_cache_fetch)

    cache = instance_variable_get(cache_name) || {}
    instance_variable_set(cache_name, cache)
    cache.key?(cache_key) ? cache[cache_key] : nil
  rescue
    nil
  end

  def self.material_hud_cache_store(cache_name, cache_key, value)
    return instance_cache_store(cache_name, cache_key, value, 500) if respond_to?(:instance_cache_store)

    cache = instance_variable_get(cache_name) || {}
    cache.clear if cache.size > 500
    cache[cache_key] = value
    instance_variable_set(cache_name, cache)
    value
  rescue
    value
  end

  def self.material_hud_all_product_codes
    return import_excel_product_codes(mini_group_mode) if respond_to?(:import_excel_product_codes)

    []
  rescue
    []
  end

  def self.material_hud_all_product_cache_signature
    [
      mini_group_mode,
      @import_excel_loaded_path.to_s,
      @import_excel_loaded_mtime.to_f,
      (@imported_excel_data || []).size,
      respond_to?(:mini_excel_rows_signature) ? mini_excel_rows_signature(@imported_excel_data) : (@imported_excel_data || []).hash,
      respond_to?(:mini_model_rows_signature) ? mini_model_rows_signature(@current_report_items) : (@current_report_items || []).hash,
      respond_to?(:mini_model_rows_signature) ? mini_model_rows_signature(@current_mat_items) : (@current_mat_items || []).hash,
      @process_selection_cache_sig.to_s,
      (@match_rules || {}).hash,
      (@mini_accept_rules || {}).hash,
      respond_to?(:mini_hidden_excel_items_signature) ? mini_hidden_excel_items_signature : 0,
      respond_to?(:hidden_names_signature) ? hidden_names_signature : "",
      defined?(MATERIAL_CODE_NORM_VERSION) ? MATERIAL_CODE_NORM_VERSION : 0
    ].join("::")
  rescue
    Time.now.to_f.to_s
  end

  def self.schedule_material_hud_cache_prewarm(delay = 0.25)
    return unless HUD_ENABLE_CACHE_PREWARM
    return unless material_hud_visible?
    return if @material_hud_prewarm_running
    return if !@imported_excel_data || @imported_excel_data.empty?

    products = material_hud_all_product_codes
    return if products.empty?

    sig = material_hud_all_product_cache_signature
    return if @material_hud_prewarm_sig == sig && @material_hud_prewarm_count.to_i >= products.size

    UI.stop_timer(@material_hud_prewarm_timer) if @material_hud_prewarm_timer
    @material_hud_prewarm_timer = UI.start_timer(delay.to_f, false) do
      @material_hud_prewarm_timer = nil
      @material_hud_prewarm_running = true
      material_hud_prewarm_cache_step(products, sig, 0)
    end
  rescue => e
    @material_hud_prewarm_running = false
    puts "schedule_material_hud_cache_prewarm error: #{e.class}: #{e.message}"
  end

  def self.material_hud_prewarm_cache_step(products, sig, index)
    return finish_material_hud_prewarm(sig, index) unless HUD_ENABLE_CACHE_PREWARM
    return finish_material_hud_prewarm(sig, products.size) if index >= products.size
    return finish_material_hud_prewarm(sig, index) unless material_hud_visible?

    old_products = current_mini_products
    begin
      set_mini_products([products[index]])
      build_material_overlay_draw_data(false, false) if respond_to?(:material_overlay_visible?) && material_overlay_visible?
    rescue => e
      puts "material_hud_prewarm_cache_step error: #{e.class}: #{e.message}"
    ensure
      set_mini_products(old_products)
    end

    @material_hud_prewarm_timer = UI.start_timer(0.035, false) do
      @material_hud_prewarm_timer = nil
      material_hud_prewarm_cache_step(products, sig, index + 1)
    end
  rescue => e
    @material_hud_prewarm_running = false
    puts "material_hud_prewarm_cache_step error: #{e.class}: #{e.message}"
  end

  def self.finish_material_hud_prewarm(sig, count)
    @material_hud_prewarm_sig = sig
    @material_hud_prewarm_count = count.to_i
    @material_hud_prewarm_running = false
  rescue
    @material_hud_prewarm_running = false
  end
end
