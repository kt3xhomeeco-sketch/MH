# encoding: utf-8
# MH_Thongke — mini import refreshing
# UI/render/dialog cho Mini Import. Không chứa logic xử lý thống kê lõi.
module MH_Thongke

  # === mini_import_refresh_state_pause.rb ===
  # --- mini_import_refresh_state_pause.rb ---
# MH_Thongke - Mini Import refresh pause/resume state.


  def self.import_mini_data_signature
    [
      mini_group_mode,
      mini_product_source_mode,
      @import_excel_loaded_path.to_s,
      @import_excel_loaded_mtime.to_f,
      (@imported_excel_data || []).size,
      (@match_rules || {}).hash,
      respond_to?(:mini_rules_source_signature) ? mini_rules_source_signature : "",
      (@mini_accept_rules || {}).hash,
      respond_to?(:mini_hidden_excel_items_signature) ? mini_hidden_excel_items_signature : 0,
      respond_to?(:hidden_names_signature) ? hidden_names_signature : "",
      defined?(MATERIAL_CODE_NORM_VERSION) ? MATERIAL_CODE_NORM_VERSION : 0,
      @process_selection_cache_sig.to_s
    ].join("::")
  rescue
    Time.now.to_f.to_s
  end

  def self.pause_mini_import_refresh(source = nil)
    @mini_import_external_mutation = true
    @mini_import_external_mutation_source = source.to_s
    @mini_import_external_mutation_started_at = Time.now.to_f
    respond_to?(:reset_mini_import_refresh_state) ? reset_mini_import_refresh_state : (@mini_last_refresh_state_sig = nil)
  rescue
    nil
  end

  def self.resume_mini_import_refresh(source = nil, refresh = true)
    @mini_import_external_mutation = false
    @mini_import_external_mutation_source = nil
    @mini_import_external_mutation_started_at = nil
    reset_mini_import_refresh_state if respond_to?(:reset_mini_import_refresh_state)
    return unless refresh && mini_import_dialog_visible?

    UI.start_timer(0.15, false) do
      refresh_import_mini_dialog(true, false) if mini_import_dialog_visible?
    end
  rescue => e
    puts "Mini Import resume refresh error: #{e.class}: #{e.message}" rescue nil
  end

  def self.mini_import_refresh_paused?
    return false unless @mini_import_external_mutation

    started = @mini_import_external_mutation_started_at.to_f
    if started > 0.0 && Time.now.to_f - started > 8.0
      @mini_import_external_mutation = false
      @mini_import_external_mutation_source = nil
      @mini_import_external_mutation_started_at = nil
      return false
    end
    true
  rescue
    false
  end

  def self.mini_import_dialog_visible?
    @mini_dlg && @mini_dlg.respond_to?(:visible?) && @mini_dlg.visible?
  rescue
    false
  end

  def self.import_mini_refresh_signature
    [
      current_mini_products.join("|"),
      import_mini_data_signature
    ].join("::")
  rescue
    Time.now.to_f.to_s
  end

  # === mini_import_refresh_state_dialog.rb ===
  # --- mini_import_refresh_state_dialog.rb ---
# MH_Thongke - Mini Import dialog JS bridge helpers.


  def self.mini_import_execute_script(script)
    return false unless mini_import_dialog_visible?

    @mini_dlg.execute_script(script)
    true
  rescue => e
    mini_import_debug("execute_script ERROR: #{e.class}: #{e.message}") if respond_to?(:mini_import_debug)
    false
  end

  def self.mini_import_update_js_value(last_var, function_name, value)
    return false if instance_variable_get(last_var) == value
    return false unless mini_import_execute_script("#{function_name}(#{js_arg(value)})")

    instance_variable_set(last_var, value)
    true
  end

  def self.mini_import_update_table_html(table_key, html)
    return false if table_key == @mini_last_table_key
    return false unless mini_import_execute_script("updateTable(#{js_arg(html)})")

    @mini_last_table_html = html
    @mini_last_table_key = table_key
    true
  end

  # === mini_import_refresh_state_cache.rb ===
  # --- mini_import_refresh_state_cache.rb ---
# MH_Thongke - Mini Import table cache and prewarm helpers.


  MINI_IMPORT_ENABLE_CACHE_PREWARM = false unless const_defined?(:MINI_IMPORT_ENABLE_CACHE_PREWARM)
  MINI_IMPORT_PREWARM_MAX_PRODUCTS = 12 unless const_defined?(:MINI_IMPORT_PREWARM_MAX_PRODUCTS)

  def self.import_mini_table_cache_key(process_model = false, load_excel = false)
    [
      import_mini_refresh_signature,
      process_model ? "pm1" : "pm0",
      load_excel ? "xl1" : "xl0"
    ].join("::")
  rescue
    Time.now.to_f.to_s
  end

  def self.import_mini_table_cache_fetch(cache_key)
    return nil if defined?(MINI_IMPORT_USE_HTML_CACHE) && !MINI_IMPORT_USE_HTML_CACHE
    return instance_cache_fetch(:@mini_table_html_cache, cache_key) if respond_to?(:instance_cache_fetch)

    @mini_table_html_cache ||= {}
    @mini_table_html_cache.key?(cache_key) ? @mini_table_html_cache[cache_key] : nil
  rescue
    nil
  end

  def self.import_mini_table_cache_store(cache_key, html)
    return html if defined?(MINI_IMPORT_USE_HTML_CACHE) && !MINI_IMPORT_USE_HTML_CACHE
    return instance_cache_store(:@mini_table_html_cache, cache_key, html, 600) if respond_to?(:instance_cache_store)

    @mini_table_html_cache ||= {}
    @mini_table_html_cache.clear if @mini_table_html_cache.size > 600
    @mini_table_html_cache[cache_key] = html
    html
  rescue
    html
  end

  def self.import_mini_all_product_codes
    return import_excel_product_codes(mini_group_mode) if respond_to?(:import_excel_product_codes)

    []
  rescue
    []
  end

  def self.import_mini_all_product_cache_signature
    [
      import_mini_refresh_signature.sub(current_mini_products.join("|"), "*"),
      import_mini_all_product_codes.join("|")
    ].join("::")
  rescue
    Time.now.to_f.to_s
  end

  def self.schedule_import_mini_cache_prewarm(delay = 0.25)
    return unless MINI_IMPORT_ENABLE_CACHE_PREWARM
    return unless mini_import_dialog_visible?
    return if @mini_table_prewarm_running
    return if !@imported_excel_data || @imported_excel_data.empty?

    products = import_mini_all_product_codes
    return if products.empty?
    products = products.first(MINI_IMPORT_PREWARM_MAX_PRODUCTS.to_i) if MINI_IMPORT_PREWARM_MAX_PRODUCTS.to_i > 0

    sig = import_mini_all_product_cache_signature
    return if @mini_table_prewarm_sig == sig && @mini_table_prewarm_count.to_i >= products.size

    UI.stop_timer(@mini_table_prewarm_timer) if @mini_table_prewarm_timer
    @mini_table_prewarm_timer = UI.start_timer(delay.to_f, false) do
      @mini_table_prewarm_timer = nil
      @mini_table_prewarm_running = true
      import_mini_cache_prewarm_step(products, sig, 0)
    end
  rescue => e
    @mini_table_prewarm_running = false
    puts "schedule_import_mini_cache_prewarm error: #{e.class}: #{e.message}"
  end

  def self.import_mini_cache_prewarm_step(products, sig, index)
    return finish_import_mini_cache_prewarm(sig, index) unless MINI_IMPORT_ENABLE_CACHE_PREWARM
    return finish_import_mini_cache_prewarm(sig, products.size) if index >= products.size
    return finish_import_mini_cache_prewarm(sig, index) unless mini_import_dialog_visible?

    old_products = current_mini_products
    begin
      set_mini_products([products[index]])
      build_import_mini_rows(false, false)
    rescue => e
      puts "import_mini_cache_prewarm_step error: #{e.class}: #{e.message}"
    ensure
      set_mini_products(old_products)
    end

    @mini_table_prewarm_timer = UI.start_timer(0.035, false) do
      @mini_table_prewarm_timer = nil
      import_mini_cache_prewarm_step(products, sig, index + 1)
    end
  rescue => e
    @mini_table_prewarm_running = false
    puts "import_mini_cache_prewarm_step error: #{e.class}: #{e.message}"
  end

  def self.finish_import_mini_cache_prewarm(sig, count)
    @mini_table_prewarm_sig = sig
    @mini_table_prewarm_count = count.to_i
    @mini_table_prewarm_running = false
  rescue
    @mini_table_prewarm_running = false
  end

  # === mini_import_refresh_state.rb ===
  # --- mini_import_refresh_state.rb ---
# MH_Thongke - Mini Import refresh state entrypoint.
#
# Logic is split into:
# - mini_import_refresh_state_pause.rb
# - mini_import_refresh_state_dialog.rb
# - mini_import_refresh_state_cache.rb

  # === mini_import_refresh.rb ===
  # --- mini_import_refresh.rb ---
# MH_Thongke - mini import refresh and row rendering.


  MINI_IMPORT_LIGHT_REFRESH_MIN_INTERVAL = 0.16 unless const_defined?(:MINI_IMPORT_LIGHT_REFRESH_MIN_INTERVAL)

  # Đồng bộ lại toàn bộ sau thao tác thay đổi từ Mini Import (rename/update/delete...).
  def self.finish_mini_change
    invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)
    reset_mini_import_refresh_state(true) if respond_to?(:reset_mini_import_refresh_state)
    if respond_to?(:process_selection)
      process_selection
      @process_selection_base_sig = model_base_signature if respond_to?(:model_base_signature)
      @process_selection_sel_sig = selection_signature if respond_to?(:selection_signature)
      @process_selection_last_status = :mini_name_full_scan
      @process_selection_last_at = Time.now.to_f
    end
    if respond_to?(:refresh_import_related_views)
      refresh_import_related_views(false, false, false)
    else
      refresh_import_mini_dialog(false, false)
      refresh_import_material_hud(false, false) if respond_to?(:material_hud_visible?) && material_hud_visible?
      update_html(true) if @dlg && @dlg.visible?
    end
    true
  rescue => e
    puts "finish_mini_change error: #{e.class}: #{e.message}"
    false
  end

  def self.refresh_import_mini_dialog(process_model = true, load_excel = false)
    return unless mini_import_dialog_visible?
    return if mini_import_refresh_paused?
    if defined?(MINI_IMPORT_SIMPLE_LIST_MODE) && MINI_IMPORT_SIMPLE_LIST_MODE && !process_model
      current_product_sig = if respond_to?(:refresh_selection_product_signature)
                              refresh_selection_product_signature.to_s
                            else
                              Array(current_mini_products).map(&:to_s).sort.join("|")
                            end
      if !current_product_sig.empty? && @mini_simple_last_product_sig.to_s != current_product_sig
        process_model = true
        @mini_simple_last_product_sig = current_product_sig
      end
    end
    return if !process_model && !load_excel && respond_to?(:sketchup_ui_foreground?) && !sketchup_ui_foreground?
    if !process_model && !load_excel
      now = Time.now.to_f
      delta = now - @mini_last_light_refresh_at.to_f
      if @mini_last_light_refresh_at.to_f > 0.0 && delta < MINI_IMPORT_LIGHT_REFRESH_MIN_INTERVAL.to_f
        @mini_refresh_pending ||= [false, false]
        unless @mini_light_refresh_timer
          wait = [MINI_IMPORT_LIGHT_REFRESH_MIN_INTERVAL.to_f - delta, 0.02].max
          @mini_light_refresh_timer = UI.start_timer(wait, false) do
            @mini_light_refresh_timer = nil
            refresh_import_mini_dialog(false, false) if mini_import_dialog_visible?
          end
        end
        return
      end
    end
    if @mini_refresh_busy
      pending = @mini_refresh_pending || [false, false]
      @mini_refresh_pending = [pending[0] || process_model, pending[1] || load_excel]
      return
    end
    @mini_refresh_busy = true

    if process_model || load_excel
      sync_mini_product_from_selection(false, force: true)
    end
    ensure_mini_accept_rules if respond_to?(:ensure_mini_accept_rules)
    state_sig = import_mini_refresh_signature
    if !process_model && !load_excel &&
       @mini_last_refresh_state_sig == state_sig &&
       @mini_last_table_key
      return
    end

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    html = build_import_mini_rows(process_model, load_excel)
    @mini_last_build_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0).round(1)
    if @mini_last_build_ms > 120.0
      puts "Mini Import build slow: #{@mini_last_build_ms}ms (products=#{current_mini_products.size}, process_model=#{process_model}, load_excel=#{load_excel})"
    end
    product_title = mini_product_display_title
    group_mode = mini_group_mode
    source_mode = mini_product_source_mode
    table_key = [
      current_mini_products.join("|"),
      group_mode,
      source_mode,
      html.hash
    ].join("::")
    @mini_last_refresh_state_sig = import_mini_refresh_signature

    mini_import_update_table_html(table_key, html)
    mini_import_update_js_value(:@mini_last_product_title, "setProduct", product_title)
    mini_import_update_js_value(:@mini_last_group_mode, "setModeButtons", group_mode)
    mini_import_update_js_value(:@mini_last_source_mode, "setSourceButtons", source_mode)
    @mini_last_light_refresh_at = Time.now.to_f if !process_model && !load_excel
    schedule_import_mini_cache_prewarm(0.2)
  rescue => e
    reset_mini_import_refresh_state if respond_to?(:reset_mini_import_refresh_state)
    message = "Mini Import refresh error: #{e.class}: #{e.message}"
    puts message
    puts e.backtrace.first(30).join("\n") rescue nil
    if mini_import_dialog_visible?
      html = "<tr><td colspan='5' class='empty'>#{html_escape(message)}</td></tr>"
      mini_import_execute_script("updateTable(#{js_arg(html)})")
    end
  ensure
    @mini_refresh_busy = false
    if @mini_refresh_pending && mini_import_dialog_visible?
      pending_model, pending_excel = @mini_refresh_pending
      @mini_refresh_pending = nil
      UI.start_timer(0.02, false) do
        refresh_import_mini_dialog(pending_model, pending_excel) if mini_import_dialog_visible?
      end
    end
  end
end
