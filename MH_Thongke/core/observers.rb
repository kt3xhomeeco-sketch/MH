# encoding: utf-8
# MH_Thongke — Observers & Debounce
# Selection/Model observers + debounce refresh timer
# Tách từ main.rb: dòng 513–562

module MH_Thongke
  REFRESH_DEBOUNCE_SECONDS = 0.65 unless const_defined?(:REFRESH_DEBOUNCE_SECONDS)
  PERIODIC_REFRESH_SECONDS = 30 * 60 unless const_defined?(:PERIODIC_REFRESH_SECONDS)
  IDLE_SNAPSHOT_UPDATE_SECONDS = 2.0 unless const_defined?(:IDLE_SNAPSHOT_UPDATE_SECONDS)
  IDLE_SNAPSHOT_MAX_PRODUCTS = 2 unless const_defined?(:IDLE_SNAPSHOT_MAX_PRODUCTS)
  IDLE_SNAPSHOT_MAX_ROOTS = 500 unless const_defined?(:IDLE_SNAPSHOT_MAX_ROOTS)

  begin
    old_model = @observed_model || Sketchup.active_model
    old_model.selection.remove_observer(@sel_obs) if @sel_obs && old_model
    old_model.remove_observer(@mdl_obs) if @mdl_obs && old_model
    (@observed_view || old_model.active_view).remove_observer(@view_obs) if @view_obs && old_model
    MH::ModelHub.unsubscribe(:thongke)
    UI.stop_timer(@debounce_timer) if @debounce_timer
    UI.stop_timer(@periodic_refresh_timer) if @periodic_refresh_timer
    UI.stop_timer(@save_snapshot_timer) if @save_snapshot_timer
    UI.stop_timer(@idle_preload_timer) if @idle_preload_timer
    UI.stop_timer(@idle_snapshot_update_timer) if @idle_snapshot_update_timer
    MH::ModelHub.unsubscribe(:thongke_snapshot_export) if defined?(MH::ModelHub)
  rescue
  end
  @observed_model = nil
  @observed_view = nil
  @observers_attached = false

  @sel_obs = nil
  @mdl_obs = nil
  @view_obs = nil
  @debounce_timer = nil
  @periodic_refresh_timer = nil
  @save_snapshot_timer = nil
  @idle_preload_timer = nil
  @idle_snapshot_update_timer = nil
  @pending_model_refresh = false
  @pending_view_refresh = false
  @refresh_busy = false
  @model_hub_subscription = nil
  @snapshot_export_subscription = nil
  @snapshot_export_observer_attached = false

  def self.main_dialog_visible?
    @dlg && @dlg.respond_to?(:visible?) && @dlg.visible?
  rescue
    false
  end

  def self.mini_dialog_visible?
    @mini_dlg && @mini_dlg.respond_to?(:visible?) && @mini_dlg.visible?
  rescue
    false
  end

  def self.material_hud_visible?
    !!(respond_to?(:material_overlay_visible?) && material_overlay_visible?)
  rescue
    false
  end

  def self.info_hud_runtime_visible?
    respond_to?(:info_hud_visible?) && info_hud_visible?
  rescue
    false
  end

  def self.mh_dialog_visible?
    main_dialog_visible? || mini_dialog_visible? || material_hud_visible? || info_hud_runtime_visible?
  end

  def self.main_dialog_needs_refresh?(model_refresh, view_refresh)
    # Bang chinh hien doc du lieu tu JSON snapshot. Model/view observer khong
    # duoc tu quet lai bang, neu khong autosave/model event se gay khung ngan.
    return false if main_dialog_uses_snapshot_json_only?
    return false if view_refresh
    return false unless main_dialog_visible?
    return true if model_refresh

    false
  end

  def self.main_dialog_uses_snapshot_json_only?
    true
  rescue
    true
  end

  def self.auto_snapshot_after_save_enabled?
    false
  rescue
    false
  end

  def self.refresh_selection_signature
    MH::ModelHub.selection_signature.to_s
  rescue
    ""
  end

  def self.refresh_selection_product_signature
    products = if respond_to?(:selected_product_codes)
                 selected_product_codes(false)
               elsif defined?(MH::ModelReader) && MH::ModelReader.respond_to?(:product_codes_from_selection)
                 MH::ModelReader.product_codes_from_selection(Sketchup.active_model, allow_slow_scan: false)
               else
                 []
               end
    Array(products).map(&:to_s).reject(&:empty?).sort.join("|")
  rescue
    ""
  end

  def self.detach_observers_if_idle
    detach_observers unless mh_dialog_visible?
  end

  def self.debounce_refresh(reason = :selection)
    return if @dialog_selecting
    return if @mini_observer_skip_until && Time.now.to_f < @mini_observer_skip_until.to_f

    unless mh_dialog_visible?
      detach_observers_if_idle
      return
    end

    reason_text = reason.to_s
    is_view_change = reason_text == "view"
    is_scheduled_refresh = reason_text == "save" || reason_text == "periodic"
    return if is_scheduled_refresh && !main_dialog_visible? && !mini_dialog_visible? && !material_hud_visible?
    return if is_view_change && !mini_dialog_visible? && !material_hud_visible?
    return if is_view_change && respond_to?(:mini_product_source_mode) && mini_product_source_mode == "select"
    return if is_view_change && respond_to?(:sketchup_ui_foreground?) && !sketchup_ui_foreground?

    if is_view_change
      now = Time.now.to_f
      # Khi chỉ có main dialog (không mini/hud), view change không cần cập nhật thường xuyên
      min_view_interval = if respond_to?(:mini_and_hud_visible?) && mini_and_hud_visible?
                            2.0
                          elsif respond_to?(:mini_dialog_visible?) && mini_dialog_visible?
                            1.5
                          elsif respond_to?(:material_hud_visible?) && material_hud_visible?
                            1.5
                          else
                            3.0
                          end
      return if @last_view_debounce_at && now - @last_view_debounce_at.to_f < min_view_interval
      @last_view_debounce_at = now
    end

    is_model_change = is_scheduled_refresh || reason_text == "model"
    @pending_model_refresh = true if is_model_change
    @pending_view_refresh = true if is_view_change
    # Model change → invalidate entity scan cache + structure sig cache + set dirty
    if is_model_change && respond_to?(:clear_caches)
      # Plan Mini 2026-06-08: model-change chỉ đánh dấu dirty. Không scan, không
      # idle auto-update để tránh lag khi user đang sửa/kéo.
      clear_caches
      @cached_model_structure_sig = nil
      @cached_model_structure_key = nil
      session.mark_all_dirty!
    end
    # Selection change → only mark selection dirty (skip full rescan)
    session.mark_selection_dirty! if reason_text == "selection" && !is_model_change
    @visible_product_codes_cache = nil if is_model_change

    UI.stop_timer(@debounce_timer) if @debounce_timer
    debounce_delay = if is_view_change && respond_to?(:mini_and_hud_visible?) && mini_and_hud_visible?
                       1.2
                     elsif reason_text == "selection" && material_hud_visible? && !mini_dialog_visible?
                       0.35
                     elsif reason_text == "selection"
                       0.15
                     else
                       REFRESH_DEBOUNCE_SECONDS
                     end
    @debounce_timer = UI.start_timer(debounce_delay, false) {
      @debounce_timer = nil
      begin
        # Skip if a mini import mutation is still running
        if @mini_mutation_refreshing
          @pending_model_refresh = false
          @pending_view_refresh = false
          next
        end
        if !mh_dialog_visible?
          @pending_model_refresh = false
          @pending_view_refresh = false
          detach_observers_if_idle
        elsif @refresh_busy
          debounce_refresh(reason)
        else
          model_refresh = @pending_model_refresh
          view_refresh = @pending_view_refresh
          @pending_model_refresh = false
          @pending_view_refresh = false
          selection_sig = refresh_selection_signature

          unless !model_refresh && !view_refresh && selection_sig == @last_refresh_selection_sig
            @last_refresh_selection_sig = selection_sig
            @refresh_busy = true
            # Don't nullify @mini_accept_rules here — that flips the hash on every
            # debounce, which forces model_base_signature to change and triggers
            # full pipeline re-runs on every selection click. ensure_mini_accept_rules
            # has its own 2-second freshness throttle.
            main_dialog_busy = main_dialog_visible? &&
              @dialog_activity_until &&
              Time.now.to_f < @dialog_activity_until.to_f
            did_scan = false
            if main_dialog_needs_refresh?(model_refresh, view_refresh)
              unless main_dialog_busy
                status = false
                begin
                  status = respond_to?(:process_selection_cached) ? process_selection_cached(model_refresh, reason_text) : (process_selection; :full_scan)
                  did_scan = true
                rescue => e
                  mini_import_debug("debounce process_selection ERROR: #{e.class}: #{e.message}") rescue nil
                end
                begin
                  if main_dialog_visible?
                    if status == :fast_update && respond_to?(:update_html_fast_selection)
                      update_html_fast_selection
                    elsif status
                      update_html
                    end
                  end
                rescue => e
                  mini_import_debug("debounce update_html ERROR: #{e.class}: #{e.message}") rescue nil
                end
              end
            end
            # GIẢM LAG (yêu cầu user 2026-06-08): model đổi (thêm/xoá/sửa/số lượng) → KHÔNG
            # rescan ngay (tránh giật). Chỉ đánh dấu dữ liệu cũ; cập nhật thật khi Save file
            # hoặc ấn nút Refresh. Selection đổi vẫn lọc lại nhẹ ở khối mini bên dưới.
            @mini_data_dirty = true if model_refresh
            if mini_dialog_visible?
              product_sig = refresh_selection_product_signature
              selection_changed_sp = !product_sig.empty? && product_sig != @last_mini_selection_product_sig.to_s
              @last_mini_selection_product_sig = product_sig unless product_sig.empty?

              begin
                sync_mini_product_from_selection(false) if selection_changed_sp
              rescue
              end
              # Model-change không được truyền process_model=true vào Mini, nếu không
              # nó sẽ full scan và gây giật. Selection/view chỉ re-filter từ data/cache sẵn có.
              mini_live_selection = selection_changed_sp &&
                reason_text == "selection" &&
                defined?(MINI_IMPORT_SIMPLE_LIST_MODE) &&
                MINI_IMPORT_SIMPLE_LIST_MODE
              begin
                refresh_import_mini_dialog(mini_live_selection, false) if mini_live_selection || model_refresh || view_refresh
              rescue
              end
            end
            # Stagger HUD refresh to next tick — avoid blocking the UI thread
            # with both Mini + HUD in the same callback
            if material_hud_visible?
              hud_context_refresh = view_refresh && !mini_dialog_visible?
              hud_delay = mini_dialog_visible? ? 0.15 : 0.35
              UI.start_timer(hud_delay, false) do
                next unless material_hud_visible?
                if respond_to?(:schedule_import_material_hud_light_refresh)
                  schedule_import_material_hud_light_refresh(hud_context_refresh) rescue nil
                else
                  refresh_import_material_hud(hud_context_refresh, false) rescue nil
                end
              end
            end
            refresh_info_hud(false) if info_hud_runtime_visible? && respond_to?(:refresh_info_hud)
          end
        end
      rescue => e
        puts "debounce_refresh error: #{e.message}"
        mini_import_debug("debounce_refresh CRASH: #{e.class}: #{e.message} | #{e.backtrace.first(3).join(' | ')}") rescue nil
      ensure
        @refresh_busy = false
      end
    }
  end

  def self.start_periodic_refresh_timer
    UI.stop_timer(@periodic_refresh_timer) if @periodic_refresh_timer
    @periodic_refresh_timer = UI.start_timer(PERIODIC_REFRESH_SECONDS, true) do
      if mh_dialog_visible?
        debounce_refresh(:periodic)
      else
        detach_observers_if_idle
      end
    end
    # Pre-load: warm up data cache when main dialog is idle.
    # This ensures Mini/HUD open instantly when triggered later.
    schedule_idle_preload
  rescue => e
    puts "MH_Thongke periodic refresh timer error: #{e.message}"
    @periodic_refresh_timer = nil
  end

  def self.idle_preload_status
    {
      scheduled: !!@idle_preload_scheduled,
      main_visible: !!(main_dialog_visible? rescue false),
      mini_visible: !!(mini_dialog_visible? rescue false),
      hud_visible: !!(material_hud_visible? rescue false),
      has_report: !@current_report_items.nil?,
      has_materials: !@current_mat_items.nil?,
      last: @idle_preload_last_status
    }
  rescue
    { scheduled: !!@idle_preload_scheduled, last: @idle_preload_last_status }
  end

  def self.run_idle_preload_now(reason = "idle_preload_manual", require_visible: false)
    if require_visible && (!main_dialog_visible? || (!mini_dialog_visible? && !material_hud_visible?))
      @idle_preload_last_status = idle_preload_status.merge(ran: false, reason: reason.to_s, skip_reason: "not_visible")
      return @idle_preload_last_status
    end

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    excel_loaded = false
    process_status = false
    mini_prewarm = false
    hud_prewarm = false

    if respond_to?(:load_import_excel_snapshot_only) && (@imported_excel_data.nil? || @imported_excel_data.empty?)
      load_import_excel_snapshot_only
      excel_loaded = true
    end

    if respond_to?(:process_selection_cached)
      process_status = process_selection_cached(false, reason.to_s)
    elsif respond_to?(:process_selection)
      process_selection
      process_status = :full_scan
    end

    if respond_to?(:schedule_import_mini_cache_prewarm) && mini_dialog_visible?
      schedule_import_mini_cache_prewarm(0.05)
      mini_prewarm = true
    end
    if respond_to?(:schedule_material_hud_cache_prewarm) && material_hud_visible?
      schedule_material_hud_cache_prewarm(0.05)
      hud_prewarm = true
    end

    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    @idle_preload_last_status = idle_preload_status.merge(
      ran: true,
      reason: reason.to_s,
      process_status: process_status,
      excel_loaded: excel_loaded,
      mini_prewarm: mini_prewarm,
      hud_prewarm: hud_prewarm,
      duration_ms: ((t1 - t0) * 1000.0).round(1)
    )
  rescue => e
    @idle_preload_last_status = idle_preload_status.merge(
      ran: false,
      reason: reason.to_s,
      error: "#{e.class}: #{e.message}",
      backtrace: Array(e.backtrace).first(5)
    )
  end

  def self.schedule_idle_preload(delay = 2.0)
    return idle_preload_status.merge(scheduled: false, skip_reason: "already_scheduled") if @idle_preload_scheduled
    return idle_preload_status.merge(scheduled: false, skip_reason: "main_dialog_hidden") unless main_dialog_visible?
    return idle_preload_status.merge(scheduled: false, skip_reason: "mini_hud_hidden") unless mini_dialog_visible? || material_hud_visible?

    @idle_preload_scheduled = true
    @idle_preload_last_status = idle_preload_status.merge(scheduled: true, delay: delay.to_f, reason: "scheduled")
    @idle_preload_timer = UI.start_timer(delay.to_f, false) do
      @idle_preload_timer = nil
      @idle_preload_scheduled = false
      run_idle_preload_now("idle_preload", require_visible: true)
    end
    @idle_preload_last_status
  rescue => e
    @idle_preload_scheduled = false
    @idle_preload_last_status = idle_preload_status.merge(scheduled: false, error: "#{e.class}: #{e.message}")
  end

  def self.idle_snapshot_update_status
    {
      scheduled: !!@idle_snapshot_update_timer,
      last: @idle_snapshot_update_last_status,
      p4: (respond_to?(:p4_delta_status) ? p4_delta_status : nil)
    }
  rescue
    { scheduled: !!@idle_snapshot_update_timer, last: @idle_snapshot_update_last_status }
  end

  def self.schedule_idle_snapshot_update(reason = "model", delay = IDLE_SNAPSHOT_UPDATE_SECONDS)
    return idle_snapshot_update_status.merge(scheduled: false, skip_reason: "auto_snapshot_off") unless auto_snapshot_after_save_enabled?
    return idle_snapshot_update_status.merge(scheduled: false, skip_reason: "not_visible") unless mh_dialog_visible?
    return idle_snapshot_update_status.merge(scheduled: false, skip_reason: "missing_delta_api") unless respond_to?(:p4_delta_product_apply) && respond_to?(:p4_delta_changed_top_keys)
    return idle_snapshot_update_status.merge(scheduled: false, skip_reason: "unsaved_model") if (Sketchup.active_model.path rescue "").to_s.empty?

    UI.stop_timer(@idle_snapshot_update_timer) if @idle_snapshot_update_timer
    @idle_snapshot_update_last_status = idle_snapshot_update_status.merge(scheduled: true, reason: reason.to_s, delay: delay.to_f)
    @idle_snapshot_update_timer = UI.start_timer(delay.to_f, false) do
      @idle_snapshot_update_timer = nil
      run_idle_snapshot_update(reason.to_s)
    end
    @idle_snapshot_update_last_status
  rescue => e
    @idle_snapshot_update_timer = nil
    @idle_snapshot_update_last_status = idle_snapshot_update_status.merge(scheduled: false, error: "#{e.class}: #{e.message}")
  end

  def self.run_idle_snapshot_update(reason = "model")
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    status = { ran: false, reason: reason.to_s }
    return @idle_snapshot_update_last_status = status.merge(skip_reason: "not_visible") unless mh_dialog_visible?
    return @idle_snapshot_update_last_status = status.merge(skip_reason: "save_pending") if @save_snapshot_timer
    return @idle_snapshot_update_last_status = status.merge(skip_reason: "missing_delta_api") unless respond_to?(:p4_delta_product_apply) && respond_to?(:p4_delta_changed_top_keys)
    return @idle_snapshot_update_last_status = status.merge(skip_reason: "missing_export_cache_api") unless respond_to?(:export_current_snapshot_from_current_cache)

    p4_delta_detect_snapshot_changes if respond_to?(:p4_delta_detect_snapshot_changes)
    keys = Array(p4_delta_changed_top_keys(30)).map(&:to_s).reject(&:empty?)
    return @idle_snapshot_update_last_status = status.merge(skip_reason: "no_changed_keys") if keys.empty?
    return @idle_snapshot_update_last_status = status.merge(skip_reason: "structure_change", changed_top_keys: keys) if keys.include?("__STRUCTURE__")

    result = p4_delta_product_apply(
      top_keys: keys,
      sample: false,
      baseline: false,
      max_products: IDLE_SNAPSHOT_MAX_PRODUCTS,
      max_roots: IDLE_SNAPSHOT_MAX_ROOTS
    )

    unless result.is_a?(Hash) && result[:applied]
      @idle_snapshot_update_last_status = status.merge(
        skip_reason: result.is_a?(Hash) ? (result[:skip_reason] || result[:error] || "not_applied") : "not_applied",
        changed_top_keys: keys,
        result: result
      )
      main_ui_debug("idle snapshot skipped #{@idle_snapshot_update_last_status[:skip_reason]}") if respond_to?(:main_ui_debug)
      return @idle_snapshot_update_last_status
    end

    snap = export_current_snapshot_from_current_cache
    p4_delta_clear_changed if respond_to?(:p4_delta_clear_changed)
    invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)
    update_html(false) if main_dialog_visible? && respond_to?(:update_html)
    refresh_import_mini_dialog(false, false) if mini_dialog_visible? && respond_to?(:refresh_import_mini_dialog)
    refresh_import_material_hud(false, false) if material_hud_visible? && respond_to?(:refresh_import_material_hud)

    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    @idle_snapshot_update_last_status = status.merge(
      ran: true,
      applied: true,
      json_path: snap && snap["json_path"],
      changed_top_keys: keys,
      affected_product_bases: result[:affected_product_bases],
      root_count: result[:root_count],
      duration_ms: ((t1 - t0) * 1000.0).round(1)
    )
    main_ui_debug("idle snapshot updated #{@idle_snapshot_update_last_status[:json_path]} products=#{Array(result[:affected_product_bases]).join(',')}") if respond_to?(:main_ui_debug)
    @idle_snapshot_update_last_status
  rescue => e
    @idle_snapshot_update_last_status = status.merge(ran: false, error: "#{e.class}: #{e.message}", backtrace: Array(e.backtrace).first(5))
  end

  def self.schedule_snapshot_after_save
    unless auto_snapshot_after_save_enabled?
      main_ui_debug("auto snapshot after save skipped: manual JSON update mode") if respond_to?(:main_ui_debug)
      return
    end

    UI.stop_timer(@save_snapshot_timer) if @save_snapshot_timer
    @save_snapshot_timer = UI.start_timer(0.8, false) do
      @save_snapshot_timer = nil
      begin
        # SAVE → cập nhật dữ liệu model nếu đã sửa từ lần scan trước (user chốt: refresh khi Save).
        if @mini_data_dirty && respond_to?(:process_selection_cached)
          status = respond_to?(:process_current_mini_products_for_save) ? process_current_mini_products_for_save : nil
          process_selection_cached(true, "save") unless status
          @mini_data_dirty = false
        end
        p4_delta_detect_snapshot_changes if respond_to?(:p4_delta_detect_snapshot_changes)
        # JSON is the source for MH Thongke Desktop. Always let the save exporter
        # rescan the saved model so the snapshot cannot be stale when UI is closed.
        @skip_next_snapshot_export_process = false
        snap = respond_to?(:export_current_snapshot_for_saved_model) ? export_current_snapshot_for_saved_model : nil
        main_ui_debug("auto snapshot after save #{snap && snap['json_path']}") if respond_to?(:main_ui_debug)
        invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)
        update_html if main_dialog_visible?
        refresh_import_mini_dialog(false, false) if mini_dialog_visible? && respond_to?(:refresh_import_mini_dialog)
        refresh_import_material_hud(false, false) if material_hud_visible? && respond_to?(:refresh_import_material_hud)
      rescue => e
        puts "schedule_snapshot_after_save error: #{e.class}: #{e.message}"
        mini_import_debug("schedule_snapshot_after_save ERROR: #{e.class}: #{e.message}") rescue nil
      end
    end
  rescue => e
    puts "schedule_snapshot_after_save timer error: #{e.message}"
    @save_snapshot_timer = nil
  end

  def self.attach_snapshot_export_observer
    return false unless defined?(MH::ModelHub)
    existing = MH::ModelHub.subscribers["thongke_snapshot_export"] rescue nil
    return true if @snapshot_export_observer_attached && existing

    @snapshot_export_subscription = MH::ModelHub.subscribe(
      :thongke_snapshot_export,
      on_save: ->(_kind) { MH_Thongke.schedule_snapshot_after_save },
      visible: -> { true }
    )
    @snapshot_export_observer_attached = true
  rescue => e
    puts "MH_Thongke snapshot export observer error: #{e.message}"
    @snapshot_export_observer_attached = false
  end

  def self.attach_observers
    model = Sketchup.active_model
    unless @observers_attached && @observed_model == model
      detach_observers if @observers_attached
      begin
        @model_hub_subscription = MH::ModelHub.subscribe(
          :thongke,
          on_selection: ->(_kind) { MH_Thongke.debounce_refresh(:selection) },
          on_model: ->(_kind) { MH_Thongke.debounce_refresh(:model) },
          on_view: ->(_kind) { MH_Thongke.debounce_refresh(:view) },
          on_save: ->(_kind) { MH_Thongke.schedule_snapshot_after_save },
          visible: -> { MH_Thongke.mh_dialog_visible? }
        )
      rescue => e
        puts "MH_Thongke ModelHub observer error: #{e.message}"
      end
      @view_observer_attached = false
      @observed_model = model
      @observed_view = model.active_view
      @observers_attached = true
      start_periodic_refresh_timer
    end
    # LUÔN ép ModelHub gắn lại observer SketchUp tươi: attach_to_model early-return
    # khi @model đã trỏ model có thể để lại trạng thái "đăng ký rỗng" (object có nhưng
    # SU không dispatch onSelectionBulkChange/onTransactionCommit) → selection/model không refresh.
    begin
      if MH::ModelHub.respond_to?(:detach_from_model) && MH::ModelHub.respond_to?(:attach_to_model)
        MH::ModelHub.detach_from_model
        MH::ModelHub.attach_to_model(model)
      end
    rescue => e
      puts "MH_Thongke ModelHub reattach error: #{e.message}"
    end
  end

  def self.detach_observers
    return unless @observers_attached
    model = @observed_model || Sketchup.active_model
    begin
      MH::ModelHub.unsubscribe(:thongke)
    rescue
    end
    begin
      UI.stop_timer(@debounce_timer) if @debounce_timer
      UI.stop_timer(@periodic_refresh_timer) if @periodic_refresh_timer
      UI.stop_timer(@save_snapshot_timer) if @save_snapshot_timer
      UI.stop_timer(@idle_preload_timer) if @idle_preload_timer
      UI.stop_timer(@idle_snapshot_update_timer) if @idle_snapshot_update_timer
    rescue
    end
    @debounce_timer = nil
    @periodic_refresh_timer = nil
    @save_snapshot_timer = nil
    @idle_preload_timer = nil
    @idle_snapshot_update_timer = nil
    @idle_preload_scheduled = false
    @view_observer_attached = false
    @pending_model_refresh = false
    @pending_view_refresh = false
    @refresh_busy = false
    @model_hub_subscription = nil
    @last_refresh_selection_sig = nil
    @observed_model = nil
    @observed_view = nil
    @observers_attached = false

    # === Memory cleanup: Giai phong entity references khi dialog dong ===
    unless mh_dialog_visible?
      P4DeltaTracker.detach_all if defined?(P4DeltaTracker)
      session.reset!
      # Sync backward-compat module ivars
      @data_map = nil; @mat_data_map = nil; @phaochi_map = nil
      @current_report_items = nil; @current_mat_items = nil
      @prod_groups = nil; @led_per_product = nil
      @all_item_names = nil; @all_item_names_set = nil
      @stat_entity_ids = nil; @entity_ids_in_data = nil
      @back_imported_excel = nil; @back_import_diff = nil
      @visible_product_codes_cache = nil
      clear_caches if respond_to?(:clear_caches)
    end
  end

  begin
    attach_snapshot_export_observer
    UI.start_timer(0.05, false) { attach_observers if mh_dialog_visible? }
  rescue
  end

end
