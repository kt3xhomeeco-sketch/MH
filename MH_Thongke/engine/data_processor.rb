# encoding: utf-8
require_relative 'data_processor_utils'

module MH_Thongke

  # process_selection: orchestrator goi Pipeline stages theo thu tu.
  # Moi stage la 1 method doc lap — de test, de debug, de skip.
  def self.process_selection
    s = session
    @model     = Sketchup.active_model
    @selection = @model.selection

    if @defer_next_process_selection && !@force_process_selection_once
      @defer_next_process_selection = false
      @main_fast_open = true
      s.current_report_items = []
      s.current_mat_items = []
      @current_report_items = []
      @current_mat_items = []
      @process_selection_last_status = :deferred_open
      @process_selection_last_at = Time.now.to_f
      return :deferred_open
    end

    unless @force_process_selection_once
      begin
        current_rows_ready = @current_report_items && @current_mat_items &&
          (!Array(@current_report_items).empty? || !Array(@current_mat_items).empty?)
        cache_ready = current_rows_ready && respond_to?(:model_base_signature)
        clean_session = !s.respond_to?(:any_dirty?) || !s.any_dirty?
        if cache_ready && clean_session
          base_sig = model_base_signature
          sel_sig = respond_to?(:selection_signature) ? selection_signature : ""
          if @process_selection_base_sig.to_s == base_sig.to_s
            if @process_selection_sel_sig.to_s != sel_sig.to_s && respond_to?(:fast_update_selection)
              fast_update_selection
              @process_selection_sel_sig = sel_sig
              @process_selection_last_status = :fast_update
            else
              @process_selection_last_status = false
            end
            @process_selection_last_at = Time.now.to_f
            return @process_selection_last_status
          end
        end
      rescue
      end
    end
    @force_process_selection_once = false

    # Load prerequisites
    load_history    if s.change_history.nil? || s.change_history.empty?
    load_match_rules if s.match_rules.nil?
    load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)

    # Ensure session sees Excel data loaded from JSON cache (module → session sync)
    if (s.imported_excel_data.nil? || s.imported_excel_data.empty?) && @imported_excel_data && !@imported_excel_data.empty?
      s.imported_excel_data = @imported_excel_data
    end

    # Run pipeline
    @main_fast_open = false
    Pipeline.run(s, @model, @selection)

    # Sync backward-compat module ivars (transition period — se xoa dan)
    @data_map             = s.data_map
    @mat_data_map         = s.mat_data_map
    @prod_groups          = s.prod_groups
    @all_item_names       = s.all_item_names
    @all_item_names_set   = s.all_item_names_set
    @led_per_product      = s.led_per_product
    # NEVER overwrite @imported_excel_data with empty session data —
    # the module variable may hold data loaded directly from JSON cache.
    if s.imported_excel_data && !s.imported_excel_data.empty?
      if respond_to?(:set_imported_excel_data)
        set_imported_excel_data(s.imported_excel_data, "process_selection_sync", sync_session: false)
      else
        @imported_excel_data = s.imported_excel_data
      end
    end
    @match_rules          = s.match_rules
    @general_rules        = s.general_rules
    @current_report_items = s.current_report_items
    @current_mat_items    = s.current_mat_items
    @process_selection_cache_sig = s.process_selection_cache_sig
    @process_selection_base_sig = model_base_signature if respond_to?(:model_base_signature)
    @process_selection_sel_sig = selection_signature if respond_to?(:selection_signature)
    @p4_delta_watch_status = p4_delta_rebuild_watchers if respond_to?(:p4_delta_rebuild_watchers)
    @process_selection_last_at = Time.now.to_f
    @process_selection_last_status = :full_scan
  end

  # Incremental version: skip full rescan if only selection/overrides changed.
  # Returns :full_scan, :partial, :fast_update, or :no_change.
  def self.process_selection_incremental
    s = session
    @model     = Sketchup.active_model
    @selection = @model.selection
    profile_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    flags_before = respond_to?(:pipeline_dirty_flags_snapshot) ? pipeline_dirty_flags_snapshot(s) : {}
    result = :no_change

    # Load prerequisites if needed
    load_history    if s.change_history.nil? || s.change_history.empty?
    load_match_rules if s.match_rules.nil?
    load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)

    # First run or no data — must do full pipeline
    if s.current_report_items.nil? || s.current_report_items.empty?
      s.mark_all_dirty!
    end

    result = Pipeline.run_incremental(s, @model, @selection)

    # Sync backward-compat module ivars
    sync_session_to_module_ivars(s) if result != :no_change && result != :fast_update

    result
  ensure
    if respond_to?(:record_pipeline_profile_event) && profile_t0
      profile_t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
      record_pipeline_profile_event(
        reason: "incremental",
        status: result,
        duration_ms: (profile_t1 - profile_t0) * 1000.0,
        flags_before: flags_before || {},
        flags_after: respond_to?(:pipeline_dirty_flags_snapshot) ? pipeline_dirty_flags_snapshot(s) : {}
      )
    end
  end

  def self.sync_session_to_module_ivars(s)
    @data_map             = s.data_map
    @mat_data_map         = s.mat_data_map
    @prod_groups          = s.prod_groups
    @all_item_names       = s.all_item_names
    @all_item_names_set   = s.all_item_names_set
    @led_per_product      = s.led_per_product
    # Preserve @imported_excel_data if session is empty (JSON cache may be the source)
    if s.imported_excel_data && !s.imported_excel_data.empty?
      if respond_to?(:set_imported_excel_data)
        set_imported_excel_data(s.imported_excel_data, "sync_session_to_module_ivars", sync_session: false)
      else
        @imported_excel_data = s.imported_excel_data
      end
    end
    @match_rules          = s.match_rules
    @general_rules        = s.general_rules
    @current_report_items = s.current_report_items
    @current_mat_items    = s.current_mat_items
    @process_selection_cache_sig = s.process_selection_cache_sig
    @p4_delta_watch_status = p4_delta_rebuild_watchers if respond_to?(:p4_delta_rebuild_watchers) && @current_report_items && @current_mat_items
  end

  def self.fast_update_selection
    return unless @current_report_items

    sel = Sketchup.active_model.selection

    [@current_report_items, @current_mat_items].compact.each do |list|
      list.each do |row|
        row[:sel_count] = 0
        row[:sel_length] = 0.0
        row[:sel_len_mm] = 0.0

        next unless row[:stat_entities]
        row[:stat_entities].each do |item|
          e = item[0]
          current_top = item[1]
          parent_wt = item[2]

          if sel.include?(current_top) || sel.include?(e)
            if row[:type] == :length || row[:type] == :phaochi
              len = respond_to?(:get_world_length) ? get_world_length(e, parent_wt) : 0.0
              row[:sel_length] += len
              row[:sel_len_mm] += len if row[:type] == :phaochi
            else
              row[:sel_count] += 1
            end
          end
        end
      end
    end
  end

  def self.update_html_fast_selection
    return unless @dlg && @dlg.visible?
    payload = { selection_empty: @selection.empty?, acc: {}, mat: {} }

    (@current_report_items || []).each_with_index do |row, idx|
      payload[:acc][idx.to_s] = row[:sel_count].to_i if row[:sel_count].to_i > 0
    end
    (@current_mat_items || []).each_with_index do |row, idx|
      payload[:mat][idx.to_s] = row[:sel_count].to_i if row[:sel_count].to_i > 0
    end

    script = <<~JS
      (function(){
        var p = #{payload.to_json};
        var empty = p.selection_empty;
        var cells = document.querySelectorAll('.sel-count-cell');
        for(var i=0; i<cells.length; i++) {
          var td = cells[i];
          var src = td.getAttribute('data-src');
          var idx = td.getAttribute('data-orig-idx');
          var count = (p[src] && p[src][idx]) ? p[src][idx] : 0;
          td.innerHTML = count > 0 ? "<b style='color:#2980b9'>" + count + "</b>" : "-";
          var tr = td.parentNode;
          if (empty) {
            tr.style.opacity = '';
            tr.style.backgroundColor = '';
          } else {
            if (count > 0) {
              tr.style.opacity = '1';
              tr.style.backgroundColor = '#2c3e50';
            } else {
              tr.style.opacity = '0.35';
              tr.style.backgroundColor = '';
            }
          }
        }
      })();
    JS
    @dlg.execute_script(script)
  rescue => e
    puts "fast update selection js error: #{e.message}"
  end

end
