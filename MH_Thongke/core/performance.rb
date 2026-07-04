# encoding: utf-8
# MH_Thongke - performance helpers and scan cache signatures.

module MH_Thongke
  def self.clear_caches
    @cached_entity_scan = nil
    @cached_entity_scan_sig = nil
    @process_selection_cache_sig = nil
    @process_selection_last_at = nil
    @mini_model_items_cache = nil
    @mini_excel_items_cache = nil
    @mini_model_row_index_key = nil
    @mini_model_row_report_exact_index = nil
    @mini_model_row_report_base_index = nil
    @mini_model_row_mat_exact_index = nil
    @mini_model_row_mat_base_index = nil
    @mini_excel_product_index_key = nil
    @mini_excel_exact_index = nil
    @mini_excel_base_index = nil
    @mini_table_html_cache = nil
    @mini_pk_rows_html_cache = nil
    @mini_product_block_cache = nil
    @import_material_section_data_cache = nil
    @mini_table_prewarm_sig = nil
    @mini_table_prewarm_count = nil
    @material_hud_rows_cache = nil
    @material_hud_entries_cache = nil
    @material_overlay_draw_cache = nil
    @material_hud_prewarm_sig = nil
    @material_hud_prewarm_count = nil
    @visible_product_index_cache = nil
    @cached_model_structure_sig = nil
    @selected_product_codes_cache_key = nil
    @selected_product_codes_cache = nil
    @mini_pk_model_name_match_cache = nil
    @merged_priority_runtime_memo = nil
  end

  def self.invalidate_material_hud_caches(refresh_state = true)
    @material_hud_rows_cache = nil
    @material_hud_entries_cache = nil
    @material_overlay_draw_cache = nil
    @material_hud_prewarm_sig = nil
    @material_hud_prewarm_count = nil
    if refresh_state
      @mini_hud_last_table_key = nil
      @material_overlay_last_state_sig = nil
    end
    true
  rescue
    false
  end

  def self.reset_mini_import_refresh_state(clear_table_html = false)
    @mini_last_refresh_state_sig = nil
    @mini_last_table_key = nil
    @mini_last_table_html = nil if clear_table_html
    true
  rescue
    false
  end

  def self.invalidate_mini_import_caches(model: false, excel: false, table: true, refresh_state: true, hud: true)
    if model
      @mini_model_items_cache = nil
      @mini_model_row_index_key = nil
      @mini_model_row_report_exact_index = nil
      @mini_model_row_report_base_index = nil
      @mini_model_row_mat_exact_index = nil
      @mini_model_row_mat_base_index = nil
    end
    if excel
      @mini_excel_items_cache = nil
      @mini_excel_product_index_key = nil
      @mini_excel_exact_index = nil
      @mini_excel_base_index = nil
    end
    if model || excel || table
      @import_material_section_data_cache = nil
      @mini_pk_rows_html_cache = nil
      @mini_product_block_cache = nil
      @tab_bom_mini_rows_cache = nil
      @merged_priority_runtime_memo = nil
    end
    @mini_table_html_cache = nil if table
    @mini_table_prewarm_sig = nil if table
    @mini_table_prewarm_count = nil if table
    reset_mini_import_refresh_state if refresh_state
    invalidate_material_hud_caches(refresh_state) if hud && respond_to?(:invalidate_material_hud_caches)
    true
  rescue
    false
  end

  def self.instance_cache_fetch(cache_name, cache_key)
    cache = instance_variable_get(cache_name) || {}
    instance_variable_set(cache_name, cache)
    cache.key?(cache_key) ? cache[cache_key] : nil
  rescue
    nil
  end

  def self.instance_cache_store(cache_name, cache_key, value, max_size = 500)
    cache = instance_variable_get(cache_name) || {}
    limit = max_size.to_i
    cache.clear if limit > 0 && cache.size > limit
    cache[cache_key] = value
    instance_variable_set(cache_name, cache)
    value
  rescue
    value
  end

  def self.pipeline_dirty_flags_snapshot(s = nil)
    s ||= respond_to?(:session) ? session : nil
    return {} unless s

    {
      dirty_scan: !!s.dirty_scan,
      dirty_excel: !!s.dirty_excel,
      dirty_overrides: !!s.dirty_overrides,
      dirty_status: !!s.dirty_status,
      dirty_html: !!s.dirty_html,
      dirty_selection: !!s.dirty_selection
    }
  rescue
    {}
  end

  def self.record_pipeline_profile_event(event)
    @pipeline_profile_events ||= []
    row = {
      time: Time.now.strftime("%H:%M:%S"),
      reason: event[:reason].to_s,
      status: event[:status],
      duration_ms: event[:duration_ms].to_f.round(1),
      force: !!event[:force],
      model_refresh: !!event[:model_refresh],
      view_refresh: !!event[:view_refresh],
      flags_before: event[:flags_before] || {},
      flags_after: event[:flags_after] || {}
    }
    @pipeline_profile_events << row
    @pipeline_profile_events.shift while @pipeline_profile_events.length > 80
    row
  rescue
    nil
  end

  def self.pipeline_profile_events(limit = 20)
    Array(@pipeline_profile_events).last(limit.to_i)
  rescue
    []
  end

  def self.clear_pipeline_profile_events
    @pipeline_profile_events = []
    true
  rescue
    false
  end


  def self.model_structure_signature(model = nil)
    model ||= Sketchup.active_model
    model.active_entities.map { |e| e.entityID.to_s }.join("-").hash.to_s
  end

  def self.model_base_signature
    model = Sketchup.active_model
    path_ids = Array(model.active_path).map { |e| e.entityID rescue nil }.compact
    import_sig = [
      @import_excel_loaded_path.to_s,
      @import_excel_loaded_mtime.to_f,
      (@imported_excel_data || []).size
    ].join(":")
    [
      model_structure_signature(model),
      path_ids.join("/"),
      @group_by.to_s,
      @display_mode.to_s,
      respond_to?(:hidden_names_signature) ? hidden_names_signature : (@hidden_list || []).join("|"),
      (@unit_overrides || {}).hash,
      @led_power_factor.to_f,
      Array(@psu_list).join(","),
      import_sig,
      (@match_rules || {}).hash,
      (@mini_accept_rules || {}).hash
    ].join("::")
  rescue
    Time.now.to_f.to_s
  end

  def self.selection_signature
    model = Sketchup.active_model
    model.selection.to_a.map { |e| e.entityID rescue nil }.compact.sort.join(",")
  rescue
    Time.now.to_f.to_s
  end

  def self.p4_delta_incremental_eligible?(reason = nil)
    return false unless reason.to_s == "model"
    return false if @current_report_items.nil? || @current_mat_items.nil?
    return false unless respond_to?(:p4_delta_changed_top_keys) && respond_to?(:p4_delta_product_apply)
    model = Sketchup.active_model
    return false unless Array(model.active_path).empty?

    true
  rescue
    false
  end

  def self.try_p4_delta_product_incremental(reason = nil)
    @p4_delta_last_apply_result = nil
    # P4b auto product-incremental TẮT mặc định: chưa pass P7 (add/delete component + undo/redo).
    # Tracker theo tập entity cố định → bỏ sót component mới (vd phào chỉ) và có thể bỏ qua full scan
    # → BOM/mini hiển thị sai/cũ. Mọi model-change sẽ luôn full scan (đúng, ~800ms).
    # Bật lại bằng: MH_Thongke.instance_variable_set(:@p4_delta_auto_enabled, true) sau khi P7 xong.
    return nil unless @p4_delta_auto_enabled
    return nil unless p4_delta_incremental_eligible?(reason)

    keys = Array(p4_delta_changed_top_keys(30)).map(&:to_s).reject(&:empty?)
    return nil if keys.empty?
    if keys.include?("__STRUCTURE__")
      @p4_delta_last_apply_result = {
        ok: false,
        skipped: true,
        skip_reason: "structure_change",
        changed_top_keys: keys
      }
      return nil
    end

    result = p4_delta_product_apply(
      top_keys: keys,
      sample: false,
      baseline: false,
      max_products: 4,
      max_roots: 500
    )
    @p4_delta_last_apply_result = result
    return nil unless result.is_a?(Hash) && result[:applied]

    @process_selection_base_sig = model_base_signature
    @process_selection_sel_sig = selection_signature
    @process_selection_last_at = Time.now.to_f
    @process_selection_last_status = :product_incremental
    session.reset_dirty! if respond_to?(:session) && session.respond_to?(:reset_dirty!)
    p4_delta_clear_changed if respond_to?(:p4_delta_clear_changed)
    :product_incremental
  rescue => e
    @p4_delta_last_apply_result = {
      ok: false,
      error: "#{e.class}: #{e.message}",
      backtrace: Array(e.backtrace).first(5)
    }
    nil
  end

  def self.p4_delta_last_apply_result
    @p4_delta_last_apply_result
  rescue
    nil
  end

  def self.product_root_entities_for_codes(product_codes, max_depth = 4)
    targets = Array(product_codes).map { |code| product_code_exact(code) rescue code.to_s.strip.upcase }
                                  .select { |code| product_code_valid?(code) rescue code =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i }
                                  .uniq
    return [] if targets.empty?

    target_bases = targets.map { |code| product_code_base(code) rescue code.to_s.split(".").first }.uniq
    roots = []
    seen = {}
    child_entities = lambda do |entity|
      if entity.is_a?(Sketchup::Group)
        entity.entities
      elsif entity.respond_to?(:definition) && entity.definition
        entity.definition.entities
      end
    rescue
      nil
    end
    codes_for = lambda do |entity|
      if respond_to?(:entity_product_codes)
        entity_product_codes(entity)
      else
        text = "#{entity.respond_to?(:name) ? entity.name : ""} #{entity.respond_to?(:definition) && entity.definition ? entity.definition.name : ""}"
        respond_to?(:product_codes_from_text) ? product_codes_from_text(text) : text.scan(/[A-Z]+\d+[A-Z]?(?:\.\d+)?/i).map(&:upcase).uniq
      end
    rescue
      []
    end

    walker = lambda do |entities, depth|
      return if depth > max_depth || !entities

      entities.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        next if entity.respond_to?(:deleted?) && entity.deleted?

        codes = codes_for.call(entity)
        hit = codes.any? do |code|
          exact = product_code_exact(code) rescue code.to_s.strip.upcase
          base = product_code_base(exact) rescue exact.split(".").first
          targets.include?(exact) || target_bases.include?(base)
        end
        if hit
          key = entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.entityID
          unless seen[key]
            roots << entity
            seen[key] = true
          end
          next
        end

        walker.call(child_entities.call(entity), depth + 1)
      end
    end
    walker.call(Sketchup.active_model.active_entities, 0)
    roots
  rescue
    []
  end

  def self.row_product_bases_for_save(row)
    values = [row[:actual_product], row[:product]]
    values.concat(Array(row[:product_list]))
    values.map { |value| product_code_base(value) rescue value.to_s.split(".").first.upcase }
          .reject { |value| value.to_s.empty? || value.to_s == "--" }
          .uniq
  rescue
    []
  end

  def self.replace_product_rows_in_map(current_map, changed_map, product_bases)
    bases = Array(product_bases).map { |value| product_code_base(value) rescue value.to_s.split(".").first.upcase }
                                .reject(&:empty?)
                                .uniq
    out = {}
    Hash(current_map).each do |key, row|
      out[key] = row unless (row_product_bases_for_save(row) & bases).any?
    end
    Hash(changed_map).each do |key, row|
      next unless (row_product_bases_for_save(row) & bases).any?

      out[key] = row
    end
    out
  rescue
    current_map || {}
  end

  def self.process_current_mini_products_for_save
    products = (Array(@mini_changed_products_for_save) + current_mini_products).map { |code| product_code_exact(code) rescue code.to_s.strip.upcase }
      .select { |code| product_code_valid?(code) rescue code =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i }
      .uniq
    return nil if products.empty?
    return nil unless defined?(MH_Thongke::P4DeltaMergeHarness)
    return nil if @data_map.nil? || @mat_data_map.nil?

    roots = product_root_entities_for_codes(products)
    return nil if roots.empty?

    bases = products.map { |code| product_code_base(code) }.uniq
    result = MH_Thongke::P4DeltaMergeHarness.run_pipeline_for_roots(roots, product_bases: bases)
    return nil unless result.is_a?(Hash) && result[:session] && result[:error].nil?

    changed_s = result[:session]
    data_map = replace_product_rows_in_map(@data_map, changed_s.data_map, bases)
    mat_data_map = replace_product_rows_in_map(@mat_data_map, changed_s.mat_data_map, bases)
    s = session
    s.data_map = data_map
    s.mat_data_map = mat_data_map
    @data_map = data_map
    @mat_data_map = mat_data_map
    Pipeline.stage_finalize(s, Sketchup.active_model)
    sync_session_to_module_ivars(s) if respond_to?(:sync_session_to_module_ivars)
    @p4_delta_watch_status = p4_delta_rebuild_watchers if respond_to?(:p4_delta_rebuild_watchers)
    @process_selection_last_status = :mini_product_save_scan
    @process_selection_last_at = Time.now.to_f
    @mini_save_scan_last_result = {
      status: :mini_product_save_scan,
      products: products,
      roots: roots.length,
      scan_ms: result[:scan_ms],
      pipeline_ms: result[:pipeline_ms]
    }
    @mini_changed_products_for_save = []
    :mini_product_save_scan
  rescue => e
    @mini_save_scan_last_result = {
      status: :error,
      error: "#{e.class}: #{e.message}",
      backtrace: Array(e.backtrace).first(5)
    }
    nil
  end

  def self.mini_save_scan_last_result
    @mini_save_scan_last_result
  rescue
    nil
  end

  def self.process_selection_cached(force = false, reason = nil)
    # Guard: prevent concurrent duplicate runs (e.g. Mini + HUD both triggering at startup)
    if @process_selection_running
      return @process_selection_last_status || false
    end
    profile_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    flags_before = pipeline_dirty_flags_snapshot if respond_to?(:pipeline_dirty_flags_snapshot)
    status = false

    base_sig = model_base_signature
    sel_sig = selection_signature

    need_full_scan = force || 
                     @process_selection_base_sig != base_sig || 
                     @current_report_items.nil? || 
                     @current_mat_items.nil? ||
                     (Array(@current_report_items).empty? && Array(@current_mat_items).empty?)

    if need_full_scan
      if force && respond_to?(:try_p4_delta_product_incremental)
        incremental_status = try_p4_delta_product_incremental(reason)
        if incremental_status
          status = incremental_status
          return status
        end
      end

      @process_selection_running = true
      begin
        @force_process_selection_once = true
        process_selection
      ensure
        @force_process_selection_once = false
        @process_selection_running = false
      end
      @process_selection_base_sig = base_sig
      @process_selection_sel_sig = sel_sig
      @process_selection_last_at = Time.now.to_f
      @process_selection_last_status = :full_scan
      status = :full_scan
      return status
    end

    if @process_selection_sel_sig != sel_sig
      if respond_to?(:fast_update_selection)
        fast_update_selection
        status = :fast_update
      else
        @process_selection_running = true
        begin
          process_selection
        ensure
          @process_selection_running = false
        end
        status = :full_scan
      end
      @process_selection_sel_sig = sel_sig
      @process_selection_last_at = Time.now.to_f
      @process_selection_last_status = status
      return status
    end

    status = false
    false
  ensure
    if respond_to?(:record_pipeline_profile_event) && profile_t0
      profile_t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
      record_pipeline_profile_event(
        reason: reason || (force ? "force" : "cached"),
        status: status,
        duration_ms: (profile_t1 - profile_t0) * 1000.0,
        force: force,
        flags_before: flags_before || {},
        flags_after: respond_to?(:pipeline_dirty_flags_snapshot) ? pipeline_dirty_flags_snapshot : {}
      )
    end
  end

  # Singleton Fiddle handles — dlopen 1 lần, tái sử dụng suốt session
  def self.fiddle_user32_handles
    return @fiddle_user32 if @fiddle_user32
    require 'fiddle'
    u32 = Fiddle.dlopen('user32')
    @fiddle_user32 = {
      get_fg:   Fiddle::Function.new(u32['GetForegroundWindow'], [], Fiddle::TYPE_INTPTR_T),
      get_pid:  Fiddle::Function.new(u32['GetWindowThreadProcessId'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT),
      get_text: Fiddle::Function.new(u32['GetWindowTextA'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    }
  rescue
    nil
  end

  def self.sketchup_ui_foreground?
    return true unless Sketchup.platform == :platform_win

    now = Time.now.to_f
    if @foreground_window_cache && now - @foreground_window_cache[:at].to_f < 0.6
      return @foreground_window_cache[:active]
    end

    handles = fiddle_user32_handles
    return true unless handles

    hwnd = handles[:get_fg].call
    pid_buf = "\0" * 4
    handles[:get_pid].call(hwnd, pid_buf)
    pid = pid_buf.unpack1('L')
    buf = "\0" * 512
    len = handles[:get_text].call(hwnd, buf, 512)
    title = buf[0, len].to_s
    active = pid == Process.pid ||
      title.include?("SketchUp") ||
      title.include?("MH Thongke") ||
      title.include?("Mini Import")
    @foreground_window_cache = { at: now, active: active }
    active
  rescue
    true
  end

  def self.mini_and_hud_visible?
    respond_to?(:mini_dialog_visible?) && respond_to?(:material_hud_visible?) &&
      mini_dialog_visible? && material_hud_visible?
  rescue
    false
  end
end
