# encoding: utf-8
# MH_Thongke - Dialog & Callbacks
# show_dialog + 30+ action_callbacks
# Tach tu main.rb: dong 1156-2027

module MH_Thongke
  remove_const(:MAIN_DIALOG_VALID_TABS) if const_defined?(:MAIN_DIALOG_VALID_TABS, false)
  MAIN_DIALOG_VALID_TABS = %w[tab-all tab-project-total tab-acc tab-report tab-mat tab-import tab-settings tab-led tab-rules tab-files tab-restore].freeze

  def self.with_fast_attribute_edit(operation_name)
    model = @model || Sketchup.active_model
    detach_observers
    started = false
    begin
      model.start_operation(operation_name, true)
      started = true
      result = yield
      model.commit_operation if started
      @data_edit_dirty = true
      result
    rescue => e
      model.abort_operation if started
      raise e
    ensure
      attach_observers if mh_dialog_visible?
      @pending_model_refresh = false
      @pending_view_refresh = false
    end
  end

  def self.refresh_project_total_table
    return unless @dlg && @dlg.visible?
    rows = respond_to?(:build_project_total_bom_rows) ? build_project_total_bom_rows : ""
    script = <<~JS
      (function(){
        var table=document.getElementById('table-project-total');
        if(!table || !table.rows || table.rows.length===0)return;
        var header=table.rows[0].outerHTML;
        table.innerHTML=header + #{js_arg(rows)};
        if(typeof filterProjectTotal==='function')filterProjectTotal();
      })();
    JS
    main_dialog_execute_script(script)
  rescue => e
    puts "refresh_project_total_table error: #{e.message}"
  end

  def self.main_dialog_execute_script(script)
    return false unless @dlg && @dlg.visible?

    @dlg.execute_script(script.to_s)
    true
  rescue
    false
  end

  def self.main_dialog_register_callback(name, &block)
    return false unless @dlg

    @dlg.add_action_callback(name.to_s, &block)
    true
  rescue
    false
  end

  def self.main_dialog_parse_indices(raw_idx)
    raw = raw_idx.to_s.strip
    return [] if raw.empty?
    values = raw.split(/[,\s;]+/).map { |token| token.to_i }.uniq
    values.select { |idx| idx >= 0 }
  rescue
    []
  end

  def self.main_dialog_valid_tab?(tab_id)
    MAIN_DIALOG_VALID_TABS.include?(tab_id.to_s)
  rescue
    false
  end

  def self.main_dialog_apply_excel_path(path)
    clean_path = path.to_s.strip.gsub(/^["']|["']$/, "")
    if clean_path.empty? || !File.exist?(clean_path)
      UI.messagebox("Khong tim thay file Excel:\n#{clean_path}")
      return false
    end

    remember_import_excel_path(clean_path)
    load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)
    refresh_import_related_views(false, false, false)
    if @imported_excel_data && !@imported_excel_data.empty?
      UI.messagebox(import_excel_status_text("Da lay du lieu he thong"))
    else
      UI.messagebox("Da luu duong dan Excel. Bam Refresh Excel de nap file dau vao va tao JSON.")
    end
    true
  rescue => e
    UI.messagebox(e.message)
    false
  end

  def self.main_dialog_refresh_excel_data
    sync_import_excel_path
    if @import_excel_path.to_s.empty? || !File.exist?(@import_excel_path.to_s)
      UI.messagebox("Chua co file Excel hop le.")
      return false
    end
    @import_excel_status_message = "Dang nap Excel va tao JSON..."
    update_html(false) if @dlg && (@dlg.visible? rescue false)
    schedule_import_excel_reload(nil, "main_dialog")
    true
  rescue => e
    UI.messagebox(e.message)
    false
  end

  def self.fill_sp_tool_dir
    base_dir = if defined?(MH_Thongke::ROOT_DIR)
      MH_Thongke::ROOT_DIR
    elsif defined?(MH_Thongke::DIR)
      MH_Thongke::DIR
    else
      File.dirname(__dir__)
    end
    @fill_sp_tool_dir = File.join(base_dir, "tools", "fill_sp")
    @fill_sp_tool_dir
  end

  def self.fill_sp_script_path
    File.join(fill_sp_tool_dir, "generate_output.py")
  end

  def self.fill_sp_default_library_path
    File.join(fill_sp_tool_dir, "library.xlsx")
  end

  def self.fill_sp_log_file
    base = defined?(LOG_DIR) ? LOG_DIR : File.join(ROOT_DIR, "logs")
    File.join(base, "fill_sp.log")
  end

  def self.fill_sp_log(level, message)
    FileUtils.mkdir_p(File.dirname(fill_sp_log_file))
    File.open(fill_sp_log_file, "a:UTF-8") do |f|
      f.puts("[#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}] [#{level}] #{message}")
    end
    true
  rescue => e
    puts "fill_sp_log error: #{e.message}" rescue nil
    false
  end

  def self.fill_sp_path_norm(path)
    File.expand_path(path.to_s).tr("\\", "/").downcase
  rescue
    path.to_s.tr("\\", "/").downcase
  end

  def self.fill_sp_include_son_code?
    @fill_sp_include_son_code = true if @fill_sp_include_son_code.nil?
    !!@fill_sp_include_son_code
  end

  def self.fill_sp_spec_dir_for_model
    model = @model || Sketchup.active_model
    model_path = (model.path rescue "").to_s
    return "" if model_path.strip.empty?

    model_dir = File.dirname(model_path)
    dir_name = File.basename(model_dir).to_s.strip.upcase
    if dir_name == "SU"
      File.join(File.dirname(model_dir), "SPEC")
    else
      File.join(model_dir, "SPEC")
    end
  rescue
    ""
  end

  def self.fill_sp_sync_import_excel_path(path, auto_reload: false)
    output_path = path.to_s.strip
    return false if output_path.empty?

    remember_import_excel_path(output_path) if respond_to?(:remember_import_excel_path)
    if auto_reload && File.exist?(output_path) && respond_to?(:schedule_import_excel_reload)
      schedule_import_excel_reload(output_path, "mini_silent")
    end
    true
  rescue => e
    puts "fill_sp_sync_import_excel_path error: #{e.message}" rescue nil
    false
  end

  def self.main_dialog_fill_sp_fast_ui_refresh
    fill_sp_defaults!
    script = <<~JS
      (function(){
        var setVal=function(id,val){var el=document.getElementById(id); if(el) el.value=val||'';};
        var setTxt=function(id,val){var el=document.getElementById(id); if(el) el.textContent=val||'';};
        setVal('fill_sp_input', #{js_arg(@fill_sp_input_path.to_s)});
        setVal('fill_sp_output', #{js_arg(@fill_sp_output_path.to_s)});
        setVal('fill_sp_library', #{js_arg(@fill_sp_library_path.to_s)});
        setVal('import_Excel', #{js_arg(@import_excel_path.to_s)});
        setTxt('fill_sp_status_text', #{js_arg(fill_sp_status_text.to_s)});
        setTxt('import_excel_status_text', #{js_arg((@import_excel_error.to_s.empty? ? ((@imported_excel_data && !@imported_excel_data.empty?) ? import_excel_status_text("Da nap du lieu") : "Chua nap Excel") : "Loi Excel: #{@import_excel_error}").to_s)});
      })();
    JS
    main_dialog_execute_script(script)
  rescue => e
    puts "main_dialog_fill_sp_fast_ui_refresh error: #{e.message}" rescue nil
    false
  end

  def self.fill_sp_auto_output_path(input_path = nil, include_son_code = nil)
    candidate = fill_sp_default_output_path(input_path, include_son_code).to_s
    spec_dir = fill_sp_spec_dir_for_model.to_s
    return candidate if candidate.empty? || spec_dir.empty?

    file_name = File.basename(candidate)
    FileUtils.mkdir_p(spec_dir) unless File.directory?(spec_dir)
    File.join(spec_dir, file_name)
  rescue
    fill_sp_default_output_path(input_path, include_son_code).to_s
  end

  def self.fill_sp_default_output_path(input_path = nil, include_son_code = nil)
    input = input_path.to_s.strip
    return "" if input.empty?
    _include_son = include_son_code.nil? ? fill_sp_include_son_code? : !!include_son_code
    File.join(File.dirname(input), File.basename(input))
  rescue
    ""
  end

  def self.fill_sp_defaults!
    @fill_sp_input_path = @fill_sp_input_path.to_s
    @fill_sp_output_path = @fill_sp_output_path.to_s
    @fill_sp_library_path = @fill_sp_library_path.to_s
    local_library = fill_sp_default_library_path
    tool_dir_norm = fill_sp_path_norm(fill_sp_tool_dir)
    lib_norm = fill_sp_path_norm(@fill_sp_library_path)
    use_local_library = @fill_sp_library_path.strip.empty? || !File.exist?(@fill_sp_library_path)
    use_local_library ||= (!tool_dir_norm.empty? && !lib_norm.empty? && !lib_norm.start_with?(tool_dir_norm))
    if use_local_library
      @fill_sp_library_path = local_library
    end
    @fill_sp_include_son_code = true if @fill_sp_include_son_code.nil?
    @fill_sp_status = @fill_sp_status.to_s
    if !@fill_sp_input_path.strip.empty?
      if @fill_sp_output_path.strip.empty?
        @fill_sp_output_path = fill_sp_auto_output_path(@fill_sp_input_path, @fill_sp_include_son_code)
      else
        # Giữ nguyên tên file output hiện có, chỉ ép thư mục về SPEC theo model.
        spec_dir = fill_sp_spec_dir_for_model.to_s
        if !spec_dir.empty?
          begin
            FileUtils.mkdir_p(spec_dir) unless File.directory?(spec_dir)
          rescue
          end
          @fill_sp_output_path = File.join(spec_dir, File.basename(@fill_sp_output_path))
        end
      end
    end
    fill_sp_sync_import_excel_path(@fill_sp_output_path, auto_reload: false)
    true
  rescue
    false
  end

  def self.fill_sp_status_text
    fill_sp_defaults!
    text = @fill_sp_status.to_s.strip
    text.empty? ? "Sẵn sàng." : text
  rescue
    "Sẵn sàng."
  end

  def self.main_dialog_set_fill_sp_input_path(path, auto_output: false)
    @active_dialog_tab = "tab-files"
    fill_sp_defaults!
    @fill_sp_input_path = path.to_s.strip.gsub(/^["']|["']$/, "")
    @fill_sp_output_path = fill_sp_auto_output_path(@fill_sp_input_path, fill_sp_include_son_code?) if auto_output
    fill_sp_sync_import_excel_path(@fill_sp_output_path, auto_reload: false)
    @fill_sp_status = @fill_sp_input_path.empty? ? "Chưa chọn input Excel." : "Đã cập nhật input Excel."
    save_preferences if respond_to?(:save_preferences)
    main_dialog_fill_sp_fast_ui_refresh
    true
  rescue => e
    UI.messagebox("Lỗi cập nhật input Fill SP: #{e.message}")
    false
  end

  def self.main_dialog_set_fill_sp_output_path(path)
    @active_dialog_tab = "tab-files"
    fill_sp_defaults!
    @fill_sp_output_path = path.to_s.strip.gsub(/^["']|["']$/, "")
    spec_dir = fill_sp_spec_dir_for_model.to_s
    if !spec_dir.empty? && !@fill_sp_output_path.empty?
      begin
        FileUtils.mkdir_p(spec_dir) unless File.directory?(spec_dir)
      rescue
      end
      @fill_sp_output_path = File.join(spec_dir, File.basename(@fill_sp_output_path))
    end
    fill_sp_sync_import_excel_path(@fill_sp_output_path, auto_reload: false)
    @fill_sp_status = @fill_sp_output_path.empty? ? "Chưa chọn output Excel." : "Đã cập nhật output Excel."
    save_preferences if respond_to?(:save_preferences)
    main_dialog_fill_sp_fast_ui_refresh
    true
  rescue => e
    UI.messagebox("Lỗi cập nhật output Fill SP: #{e.message}")
    false
  end

  def self.main_dialog_set_fill_sp_library_path(path)
    @active_dialog_tab = "tab-files"
    fill_sp_defaults!
    @fill_sp_library_path = path.to_s.strip.gsub(/^["']|["']$/, "")
    @fill_sp_status = @fill_sp_library_path.empty? ? "Chưa chọn library.xlsx." : "Đã cập nhật library."
    save_preferences if respond_to?(:save_preferences)
    main_dialog_fill_sp_fast_ui_refresh
    true
  rescue => e
    UI.messagebox("Lỗi cập nhật library Fill SP: #{e.message}")
    false
  end

  def self.main_dialog_set_fill_sp_include_son(flag)
    @active_dialog_tab = "tab-files"
    fill_sp_defaults!
    @fill_sp_include_son_code = (flag.to_s == "true" || flag.to_s == "1")
    if !@fill_sp_input_path.to_s.strip.empty?
      @fill_sp_output_path = fill_sp_auto_output_path(@fill_sp_input_path, @fill_sp_include_son_code)
    end
    fill_sp_sync_import_excel_path(@fill_sp_output_path, auto_reload: false)
    @fill_sp_status = "Đã cập nhật tùy chọn mã sơn."
    save_preferences if respond_to?(:save_preferences)
    main_dialog_fill_sp_fast_ui_refresh
    true
  rescue => e
    UI.messagebox("Lỗi cập nhật tùy chọn mã sơn: #{e.message}")
    false
  end

  def self.main_dialog_fill_sp_python_cmd
    candidates = [
      ["py", "-3"],
      ["python"],
      ["python3"]
    ]
    candidates.each do |cmd|
      ok = system(*cmd, "--version", out: File::NULL, err: File::NULL)
      return cmd if ok
    rescue
      next
    end
    nil
  end

  def self.main_dialog_run_fill_sp_generate
    @active_dialog_tab = "tab-files"
    fill_sp_defaults!
    script_path = fill_sp_script_path
    input_path = @fill_sp_input_path.to_s.strip
    output_path = @fill_sp_output_path.to_s.strip
    library_path = @fill_sp_library_path.to_s.strip

    if script_path.empty? || !File.exist?(script_path)
      UI.messagebox("Không tìm thấy script:\n#{script_path}")
      return false
    end
    if input_path.empty? || !File.exist?(input_path)
      UI.messagebox("Không tìm thấy file input Excel:\n#{input_path}")
      return false
    end
    if library_path.empty? || !File.exist?(library_path)
      UI.messagebox("Không tìm thấy file library.xlsx:\n#{library_path}")
      return false
    end
    if output_path.empty?
      output_path = fill_sp_auto_output_path(input_path, fill_sp_include_son_code?)
      @fill_sp_output_path = output_path
    end

    py_cmd = main_dialog_fill_sp_python_cmd
    if py_cmd.nil?
      UI.messagebox("Không tìm thấy Python (`py -3` hoặc `python`).")
      return false
    end

    require "open3"
    cmd = py_cmd + [script_path, "--input", input_path, "--output", output_path, "--library", library_path]
    cmd << "--no-son-code" unless fill_sp_include_son_code?
    fill_sp_log("INFO", "Run: #{cmd.join(' ')}")
    stdout, stderr, status = Open3.capture3(*cmd, chdir: File.dirname(script_path))
    out_text = stdout.to_s.strip
    err_text = stderr.to_s.strip
    fill_sp_log("INFO", "stdout: #{out_text}") unless out_text.empty?
    fill_sp_log("WARN", "stderr: #{err_text}") unless err_text.empty?

    if status.success? && File.exist?(output_path)
      @fill_sp_status = "Đã xuất: #{output_path}"
      @fill_sp_output_path = output_path
      fill_sp_sync_import_excel_path(output_path, auto_reload: false)
      begin
        if respond_to?(:reload_import_excel_from_file!)
          reload_import_excel_from_file!(output_path)
          import_excel_refresh_dependent_views if respond_to?(:import_excel_refresh_dependent_views)
        elsif respond_to?(:schedule_import_excel_reload)
          schedule_import_excel_reload(output_path, "mini_silent")
        end
      rescue => import_error
        fill_sp_log("ERROR", "Auto import failed: #{import_error.class}: #{import_error.message}")
      end
      save_preferences if respond_to?(:save_preferences)
      main_dialog_fill_sp_fast_ui_refresh
      refresh_import_related_views(false, false, false)
      UI.messagebox("Fill SP: Thành công.")
      true
    else
      @fill_sp_status = "Lỗi Fill SP. Xem log."
      fill_sp_log("ERROR", "Failed status=#{status.exitstatus} output_exists=#{File.exist?(output_path)}")
      save_preferences if respond_to?(:save_preferences)
      UI.messagebox("Fill SP: Thất bại.")
      false
    end
  rescue => e
    fill_sp_log("ERROR", "Exception: #{e.class}: #{e.message}\n#{(e.backtrace || [])[0,8].join("\n")}")
    UI.messagebox("Fill SP: Thất bại.")
    false
  ensure
    main_dialog_fill_sp_fast_ui_refresh rescue nil
  end

  def self.main_dialog_open_fill_sp_output
    fill_sp_defaults!
    path = @fill_sp_output_path.to_s.strip
    if path.empty? || !File.exist?(path)
      UI.messagebox("Chưa có file output hợp lệ.")
      return false
    end
    system("start \"\" \"#{path.tr('/', '\\\\')}\"")
    true
  rescue => e
    UI.messagebox("Không mở được output: #{e.message}")
    false
  end

  def self.main_dialog_add_hidden_items(text)
    @active_dialog_tab = "tab-settings"
    restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
    incoming = text.to_s.split(/[\n\r|;,]+/).map { |name| fix_vietnamese_mojibake(name).to_s.strip }.reject(&:empty?)
    return false if incoming.empty?

    @hidden_list = normalize_hidden_names((@hidden_list || []) + incoming)
    session.hidden_list = @hidden_list if respond_to?(:session) && session
    @hidden_name_set_sig = nil
    save_project_state_hash("hidden_items", { "list" => @hidden_list }) if respond_to?(:save_project_state_hash)
    invalidate_mini_import_caches(model: true, excel: true) if respond_to?(:invalidate_mini_import_caches)
    record_known_pk_names(@hidden_list, false) if respond_to?(:record_known_pk_names)
    save_preferences
    if respond_to?(:main_dialog_refresh_import_state)
      main_dialog_refresh_import_state(true, false, false, true)
    else
      process_selection
    end
    record_restore_action("settings_add_hidden", "Thêm danh sách ẩn", { names: incoming.join(" | ") }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
    @last_main_html_hash = nil
    update_html(true) if @dlg && (@dlg.visible? rescue false)
    main_dialog_execute_script("var el=document.getElementById('hiddenInput'); if(el){ el.value=''; }") if @dlg
    true
  rescue => e
    UI.messagebox("Lỗi thêm danh sách ẩn: #{e.message}")
    false
  end

  def self.back_import_product_match?(excel_product, row_product)
    excel_code = product_code_exact(excel_product) rescue excel_product.to_s.strip.upcase
    row_code = product_code_exact(row_product) rescue row_product.to_s.strip.upcase
    return false if excel_code.empty? || row_code.empty? || excel_code == "--" || row_code == "--"
    return true if excel_code == row_code

    excel_base = product_code_base(excel_code) rescue excel_code.sub(/\.\d+\z/, "")
    row_base = product_code_base(row_code) rescue row_code.sub(/\.\d+\z/, "")
    !excel_base.empty? && excel_base == row_base
  end

  def self.back_import_name_key(value)
    norm = respond_to?(:import_name_norm) ? import_name_norm(value) : value.to_s.downcase.strip
    norm.sub(/\s+-?\s*dai\s+\d+(?:[\.,]\d+)?\s*(?:mm|m|md)?\z/i, "").strip
  rescue
    value.to_s.downcase.strip
  end

  def self.back_import_cache_file
    defined?(BACK_IMPORT_CACHE_FILE) ? BACK_IMPORT_CACHE_FILE : File.join(DATA_DIR, "back_import_cache.json")
  end

  def self.save_back_import_cache(path = nil)
    require "json"
    require "fileutils"
    rows = Array(session.back_imported_excel || @back_imported_excel).map do |row|
      {
        "name" => (row[:name] || row["name"]).to_s,
        "unit" => (row[:unit] || row["unit"]).to_s,
        "qty" => (row[:qty] || row["qty"]).to_f,
        "product" => (row[:product] || row["product"]).to_s,
        "ten_sp" => (row[:ten_sp] || row["ten_sp"]).to_s,
        "ghi_chu" => (row[:ghi_chu] || row["ghi_chu"]).to_s,
        "ngay_dat" => (row[:ngay_dat] || row["ngay_dat"]).to_s
      }
    end
    FileUtils.mkdir_p(DATA_DIR) if defined?(DATA_DIR)
    File.write(
      back_import_cache_file,
      JSON.pretty_generate({
        "source_path" => path.to_s,
        "saved_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
        "rows" => rows
      })
    )
    main_ui_debug("save_back_import_cache OK rows=#{rows.size} file=#{back_import_cache_file}") if respond_to?(:main_ui_debug)
    rows.size
  rescue => e
    main_ui_debug("save_back_import_cache ERROR #{e.class}: #{e.message}") if respond_to?(:main_ui_debug)
    0
  end

  def self.load_back_import_cache
    require "json"
    cached = session.back_imported_excel || @back_imported_excel
    return cached if cached && !cached.empty?
    file = back_import_cache_file
    return [] unless File.exist?(file)

    raw = JSON.parse(File.read(file))
    rows = Array(raw["rows"]).map do |row|
      {
        name: row["name"].to_s,
        unit: row["unit"].to_s,
        qty: row["qty"].to_f,
        product: row["product"].to_s,
        ten_sp: row["ten_sp"].to_s,
        ghi_chu: row["ghi_chu"].to_s,
        ngay_dat: row["ngay_dat"].to_s
      }
    end
    session.back_imported_excel = rows
    @back_imported_excel = rows
    main_ui_debug("load_back_import_cache OK rows=#{rows.size} file=#{file}") if respond_to?(:main_ui_debug)
    rows
  rescue => e
    main_ui_debug("load_back_import_cache ERROR #{e.class}: #{e.message}") if respond_to?(:main_ui_debug)
    []
  end

  def self.clear_back_import_cache
    File.delete(back_import_cache_file) if File.exist?(back_import_cache_file)
  rescue => e
    main_ui_debug("clear_back_import_cache ERROR #{e.class}: #{e.message}") if respond_to?(:main_ui_debug)
  end

  REFRESH_VIEWS_DEBOUNCE_INTERVAL = 0.2 unless const_defined?(:REFRESH_VIEWS_DEBOUNCE_INTERVAL)

  def self.refresh_import_related_views(process_model = true, mini_process_model = false, hud_process_model = false, main_delay = 0.0)
    if process_model
      respond_to?(:process_selection_cached) ? process_selection_cached(true) : process_selection
    end

    # Main dialog — immediate or delayed
    update_main = proc { update_html if @dlg && @dlg.visible? }
    if main_delay.to_f > 0.0 && defined?(UI)
      UI.start_timer(main_delay.to_f, false) { update_main.call }
    else
      update_main.call
    end

    # Stagger Mini and HUD refreshes to avoid simultaneous heavy work
    if respond_to?(:mini_import_dialog_visible?) && mini_import_dialog_visible?
      UI.stop_timer(@staggered_mini_timer) if @staggered_mini_timer
      @staggered_mini_timer = UI.start_timer(REFRESH_VIEWS_DEBOUNCE_INTERVAL, false) do
        @staggered_mini_timer = nil
        refresh_import_mini_dialog(mini_process_model, false) if respond_to?(:mini_import_dialog_visible?) && mini_import_dialog_visible?
      end
    end

    if respond_to?(:material_hud_visible?) && material_hud_visible?
      UI.stop_timer(@staggered_hud_timer) if @staggered_hud_timer
      @staggered_hud_timer = UI.start_timer(REFRESH_VIEWS_DEBOUNCE_INTERVAL * 2, false) do
        @staggered_hud_timer = nil
        refresh_import_material_hud(hud_process_model, false) if respond_to?(:material_hud_visible?) && material_hud_visible?
      end
    end
  end

  def self.refresh_main_dialog_after_data_change(process_model = true)
    if process_model
      respond_to?(:process_selection_cached) ? process_selection_cached(true) : process_selection
    end
    update_html if @dlg && @dlg.visible?
  end

  def self.main_dialog_refresh_import_state(process_model = true, mini_process_model = false, hud_process_model = false, reset_mini_refresh = false)
    invalidate_mini_import_caches(model: true, excel: true) if respond_to?(:invalidate_mini_import_caches)
    reset_mini_import_refresh_state(true) if reset_mini_refresh && respond_to?(:reset_mini_import_refresh_state)
    refresh_import_related_views(process_model, mini_process_model, hud_process_model)
  end

  def self.pk_report_extract_sources_from_json(path)
    payload = JSON.parse(File.read(path.to_s))
    sources = []
    add_snapshot = lambda do |snap, fallback_label|
      return unless snap.is_a?(Hash)
      items = Array(snap["items"]).select { |it| it.is_a?(Hash) }
      mat_items = Array(snap["mat_items"]).select { |it| it.is_a?(Hash) }
      return if items.empty? && mat_items.empty?
      skp_name = snap["skp_name"].to_s.strip
      cut_name = snap["label"].to_s.strip
      label = [fallback_label.to_s.strip, cut_name, skp_name].reject(&:empty?).join(" | ")
      label = fallback_label.to_s.strip if label.empty?
      sources << {
        "id" => "json:#{sources.size}",
        "label" => label,
        "path" => path.to_s,
        "items" => items,
        "mat_items" => mat_items
      }
    end

    if payload.is_a?(Hash) && payload["snapshot"].is_a?(Hash)
      add_snapshot.call(payload["snapshot"], File.basename(path.to_s))
    elsif payload.is_a?(Hash) && payload["files"].is_a?(Array)
      payload["files"].each_with_index do |snap, idx|
        add_snapshot.call(snap, "#{File.basename(path.to_s)} ##{idx + 1}")
      end
    elsif payload.is_a?(Hash) && payload["items"].is_a?(Array)
      add_snapshot.call(payload, File.basename(path.to_s))
    end

    sources
  rescue => e
    raise "Không đọc được JSON: #{e.message}"
  end

  def self.dialog_pairs_for_item(item)
    return [] unless item

    if item[:stat_entities] && !item[:stat_entities].empty?
      item[:stat_entities]
    else
      Array(item[:entities]).map { |entity| [entity, entity, Geom::Transformation.new] }
    end
  rescue
    []
  end

  def self.dialog_select_pairs_in_model(pairs)
    return if pairs.nil? || pairs.empty?

    sel_ents = pairs.map { |pair| pair[1] || pair[0] }.compact.uniq.reject { |entity| entity.respond_to?(:deleted?) && entity.deleted? }
    @model.selection.clear
    @model.selection.add(sel_ents) unless sel_ents.empty?
    @model.select_tool(HighlightTool.new(pairs))
  rescue => e
    puts "dialog_select_pairs_in_model error: #{e.message}"
  end

  def self.dialog_with_selection_lock
    @dialog_selecting = true
    yield
  ensure
    UI.start_timer(0.5, false) { @dialog_selecting = false }
  end

  def self.main_dialog_date_config(table)
    case table.to_s
    when "mat"
      {
        items_ivar: :@current_mat_items,
        attr_key: "mat_ngay_dat",
        order_scope: "mat",
        operation_update: "Cập nhật Ngày Đặt VL",
        operation_today: "Đặt hàng hôm nay VL",
        history_update: "Cập nhật Ngày Đặt VL",
        history_today: "Đặt hàng hôm nay VL",
        history_label: "VL",
        restore_update_key: "main_update_mat_ngay_dat",
        restore_update_label: "Cập nhật ngày đặt VL",
        restore_today_key: "main_set_mat_ngay_dat_today",
        restore_today_label: "Đặt hàng hôm nay VL",
        kind: "VL"
      }
    else
      {
        items_ivar: :@current_report_items,
        attr_key: "ngay_dat",
        order_scope: "acc",
        operation_update: "Cập nhật Ngày Đặt",
        operation_today: "Đặt hàng hôm nay",
        history_update: "Cập nhật Ngày Đặt",
        history_today: "Đặt hàng hôm nay",
        history_label: "PK",
        restore_update_key: "main_update_ngay_dat",
        restore_update_label: "Cập nhật ngày đặt",
        restore_today_key: "main_set_ngay_dat_today",
        restore_today_label: "Đặt hàng hôm nay",
        kind: "PK"
      }
    end
  end

  def self.main_dialog_date_data(table, idx)
    items = instance_variable_get(main_dialog_date_config(table)[:items_ivar]) || []
    items[idx.to_i]
  rescue
    nil
  end

  # Export helper: keep Excel output aligned with current acc grouping mode on UI.
  # - NAME: use current grouped rows as-is.
  # - PRODUCT: aggregate sub-product rows into base product rows (same behavior as table display).
  def self.main_dialog_export_acc_rows
    rows = Array(@current_report_items).compact
    return rows if rows.empty?
    return rows if @group_by.to_s == "NAME"

    product_code_fn = if respond_to?(:ui_product_code)
      ui_product_code
    else
      lambda { |value| value.to_s.sub(/\.\d+\z/, "") }
    end

    base_groups = {}
    rows.each do |item|
      prod = item[:product].to_s
      base = product_code_fn.call(prod).to_s
      slot = (base_groups[base] ||= { items: [], sub_items: [] })
      prod == base ? slot[:items] << item : slot[:sub_items] << item
    end

    out = []
    base_groups.keys.sort.each do |base|
      group = base_groups[base]
      if group[:sub_items].empty?
        out.concat(group[:items])
        next
      end

      merged = {}
      (group[:items] + group[:sub_items]).each do |item|
        merge_key = [import_name_norm(item[:name]), item[:type], item[:kich_thuoc].to_s].join("|")
        if merged[merge_key]
          target = merged[merge_key]
          target[:count] = target[:count].to_i + item[:count].to_i
          target[:sel_count] = target[:sel_count].to_i + item[:sel_count].to_i
          target[:length] = target[:length].to_f + item[:length].to_f
          target[:sel_length] = target[:sel_length].to_f + item[:sel_length].to_f
          target[:len_total_mm] = target[:len_total_mm].to_f + item[:len_total_mm].to_f if item.key?(:len_total_mm)
          target[:sel_len_mm] = target[:sel_len_mm].to_f + item[:sel_len_mm].to_f if item.key?(:sel_len_mm)
          target[:entities] = ((target[:entities] || []) + (item[:entities] || [])).compact.uniq
          target[:stat_entities] = (target[:stat_entities] || []) + (item[:stat_entities] || [])
          target[:length_items] = (target[:length_items] || []) + (item[:length_items] || [])
          target[:product_list] = ((target[:product_list] || []) + (item[:product_list] || [])).map { |v| v.to_s }.reject(&:empty?).uniq
          target[:ten_sp_list] = ((target[:ten_sp_list] || []) + (item[:ten_sp_list] || [])).map { |v| v.to_s }.reject(&:empty?).uniq
          if status_priority(item[:trang_thai]) > status_priority(target[:trang_thai])
            target[:trang_thai] = item[:trang_thai]
            target[:new_name] = item[:new_name]
          end
          target[:ghi_chu] = item[:ghi_chu] if target[:ghi_chu].to_s.empty?
          target[:ngay_dat] = item[:ngay_dat] if target[:ngay_dat].to_s.empty?
          target[:last_modified] = item[:last_modified] if target[:last_modified].to_s.empty?
          target[:layer] = item[:layer] if target[:layer].to_s.empty? || target[:layer].to_s == "-"
        else
          clone = item.dup
          clone[:entities] = Array(item[:entities]).dup
          clone[:stat_entities] = Array(item[:stat_entities]).dup
          clone[:length_items] = Array(item[:length_items]).dup
          clone[:product_list] = Array(item[:product_list]).dup
          clone[:ten_sp_list] = Array(item[:ten_sp_list]).dup
          clone[:product] = base
          clone[:actual_product] = base if clone[:actual_product].to_s.empty? || clone[:actual_product].to_s == "--"
          merged[merge_key] = clone
        end
      end

      out.concat(merged.values.sort_by { |v| v[:name].to_s })
    end
    out
  rescue
    rows
  end

  def self.main_dialog_apply_ngay_dat(table, idx, value, from_today = false)
    cfg = main_dialog_date_config(table)
    data = main_dialog_date_data(table, idx)
    return false unless data

    raw_val = value.to_s
    date_value = from_today ? Time.now.strftime("%d/%m/%Y") : normalize_order_date(value)
    restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
    model_before = respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(data[:stat_entities] || []) : []
    unless from_today
      log_date_commit(cfg[:order_scope], idx, raw_val, date_value, data) if respond_to?(:log_date_commit)
      puts "MH_Thongke date commit #{cfg[:order_scope]} idx=#{idx} raw=#{raw_val} normalized=#{date_value}"
    end

    operation_name = from_today ? cfg[:operation_today] : cfg[:operation_update]
    with_fast_attribute_edit(operation_name) do
      data[:ngay_dat] = date_value.to_s
      save_order_date_override(cfg[:order_scope], data, date_value) if respond_to?(:save_order_date_override)
      (data[:stat_entities] || []).each do |pair|
        ent = pair.is_a?(Array) ? pair[0] : pair
        ent.set_attribute("MH_Thongke", cfg[:attr_key], date_value.to_s) unless ent.deleted?
      end
      history_title = from_today ? cfg[:history_today] : cfg[:history_update]
      history_note = "Mã SP: #{data[:actual_product]}, #{cfg[:history_label]}: #{data[:name]}"
      history_note += ", Ngày: #{date_value}" unless from_today
      save_history(history_title, history_note)
      sync_date_inputs_in_dialog(table.to_s, idx, date_value)
    end

    restore_key = from_today ? cfg[:restore_today_key] : cfg[:restore_update_key]
    restore_label = from_today ? cfg[:restore_today_label] : cfg[:restore_update_label]
    payload = { product: data[:actual_product], kind: cfg[:kind], name: data[:name], value: date_value, model_before: model_before }
    record_restore_action(restore_key, restore_label, payload, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
    refresh_project_total_table
    true
  rescue => e
    UI.messagebox(e.message)
    false
  end

  def self.back_import_match_for_row(row, imported_rows = @back_imported_excel)
    return nil unless row.is_a?(Hash)

    product = row[:actual_product].to_s.empty? ? row[:product].to_s : row[:actual_product].to_s
    name_key = back_import_name_key(row[:name])
    row_code = product_code_exact(product) rescue product.to_s.strip.upcase
    exact_product_candidates = Array(imported_rows).select do |bx|
      bx_code = product_code_exact(bx[:product] || bx["product"]) rescue (bx[:product] || bx["product"]).to_s.strip.upcase
      !row_code.empty? && bx_code == row_code
    end
    base_product_candidates = Array(imported_rows).select do |bx|
      next false if exact_product_candidates.include?(bx)

      back_import_product_match?(bx[:product] || bx["product"], product)
    end
    candidates = exact_product_candidates + base_product_candidates
    exact = candidates.find { |bx| back_import_name_key(bx[:name] || bx["name"]) == name_key }
    return exact if exact

    # Fallback for older exported files with small naming differences.
    candidates.find do |bx|
      bx_key = back_import_name_key(bx[:name] || bx["name"])
      !bx_key.empty? && !name_key.empty? && (bx_key.include?(name_key) || name_key.include?(bx_key))
    end
  rescue
    nil
  end

  def self.apply_back_import_updates!(options = {})
    load_back_import_cache if respond_to?(:load_back_import_cache) && (!@back_imported_excel || @back_imported_excel.empty?)
    raise "Chua import nguoc Excel." unless @back_imported_excel && !@back_imported_excel.empty?
    save_back_import_cache if respond_to?(:save_back_import_cache)

    process_selection
    @data_map ||= {}
    @unit_overrides ||= {}
    @length_display_units ||= {}
    opts = options.is_a?(Hash) ? options : {}
    allowed_fields = %w[ngay_dat]
    selected_fields = Array(opts[:fields] || opts["fields"]).map { |f| f.to_s.strip }.reject(&:empty?).uniq
    selected_fields = allowed_fields if selected_fields.empty?
    selected_fields &= allowed_fields
    selected_fields = allowed_fields if selected_fields.empty?
    raise "Chua chon truong can cap nhat." if selected_fields.empty?

    scope = (opts[:scope] || opts["scope"]).to_s.strip.downcase
    scope = "all" if scope.empty?
    row_indices = Array(opts[:row_indices] || opts["row_indices"]).map { |v| v.to_i }.uniq
    if scope == "selected" && row_indices.empty? && !@last_selected_row_idx.nil?
      row_indices = [@last_selected_row_idx.to_i]
    end
    if scope == "selected" && row_indices.empty?
      row_indices = Array(@current_report_items).each_with_index.select do |data, _idx|
        next false unless data.is_a?(Hash)

        data[:sel_count].to_i > 0 || data[:sel_length].to_f > 0 || data[:sel_len_mm].to_f > 0
      end.map { |_data, idx| idx }
    end
    if scope == "selected" && row_indices.empty?
      raise "Chua co dong nao duoc chon. Hay click 1 dong trong bang hoac chon object trong model truoc."
    end

    matches = []
    @data_map.each do |data_key, data|
      next unless data.is_a?(Hash)

      if scope == "selected"
        row_idx = @current_report_items ? @current_report_items.index(data) : nil
        next unless row_idx && row_indices.include?(row_idx)
      end

      bx = back_import_match_for_row(data, @back_imported_excel)
      matches << [data_key, data, bx] if bx
    end
    raise "Khong tim thay dong nao khop de cap nhat." if matches.empty?

    restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
    snapshot_pairs = []
    matches.each { |_, data, _| snapshot_pairs.concat(data[:stat_entities] || []) }
    model_before = respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(snapshot_pairs) : []

    changed_rows = 0
    changed_fields = 0
    time_str = Time.now.strftime("%d/%m/%y %H:%M")

    with_fast_attribute_edit("Cap nhat tu Excel xuat") do
      matches.each do |data_key, data, bx|
        row_changed = false
        missing_row = !!data[:is_missing]
        diff_fields = data[:back_diff].is_a?(Hash) ? data[:back_diff] : {}
        pairs = data[:stat_entities] || []

        excel_date = normalize_order_date(bx[:ngay_dat] || bx["ngay_dat"])

        if selected_fields.include?("ngay_dat") && ((missing_row && diff_fields.key?(:ngay_dat)) || normalize_order_date(data[:ngay_dat]) != excel_date)
          save_order_date_override("acc", data, excel_date) if respond_to?(:save_order_date_override)
          pairs.each do |pair|
            ent = pair.is_a?(Array) ? pair[0] : pair
            next if ent.respond_to?(:deleted?) && ent.deleted?
            ent.set_attribute("MH_Thongke", "ngay_dat", excel_date)
            ent.set_attribute("MH_Thongke", "last_modified", time_str)
          end
          data[:ngay_dat] = excel_date
          row_changed = true
          changed_fields += 1
        end

        changed_rows += 1 if row_changed
      end
    end

    if changed_fields > 0
      save_preferences if respond_to?(:save_preferences)
      save_history("Import nguoc Excel cap nhat Ngay Dat", "#{changed_rows} dong, #{changed_fields} o")
      record_restore_action(
        "apply_back_import",
        "Import nguoc Excel cap nhat Ngay Dat",
        { rows: changed_rows, fields: changed_fields, scope: scope, selected_fields: selected_fields, model_before: model_before },
        restore_before,
        respond_to?(:current_restore_state) ? current_restore_state : nil
      ) if respond_to?(:record_restore_action)
    end

    @process_selection_cache_sig = nil
    process_selection
    update_html
    { rows: changed_rows, fields: changed_fields, matches: matches.size, scope: scope, selected_fields: selected_fields }
  end

  def self.sync_date_inputs_in_dialog(table, idx, value)
    return unless @dlg && @dlg.visible?
    selector = "input.bulk-edit[data-bulk-field='ngay_dat'][data-bulk-table='#{table}'][data-bulk-index='#{idx.to_i}']"
    script = <<~JS
      document.querySelectorAll(#{js_arg(selector)}).forEach(function(inp){
        inp.value=#{js_arg(value)};
        if(typeof bulkCommitSig==='function')inp.setAttribute('data-committed-sig',bulkCommitSig(inp,#{js_arg(value)}));
      });
    JS
    main_dialog_execute_script(script)
  rescue => e
    puts "sync_date_inputs_in_dialog error: #{e.message}"
  end

  def self.main_ui_debug(message)
    FileUtils.mkdir_p(LOG_DIR) if defined?(LOG_DIR)
    File.open(File.join(LOG_DIR, "main_ui_debug.log"), "a:utf-8") do |f|
      f.puts("#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{message}")
    end
  rescue => e
    puts "main_ui_debug error: #{e.message}"
  end

  def self.close_mh_thongke_dialog_windows
    begin
      return unless Sketchup.platform == :platform_win
    rescue
    end
    require 'fiddle'
    user32 = Fiddle.dlopen('user32')
    get_wnd_pid = Fiddle::Function.new(user32['GetWindowThreadProcessId'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    get_wnd_text = Fiddle::Function.new(user32['GetWindowTextA'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    enum_wnd = Fiddle::Function.new(user32['EnumWindows'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT)
    post_msg = Fiddle::Function.new(user32['PostMessageA'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INT, Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT)
    wm_close = 0x0010
    my_pid = Process.pid
    cb = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T]) do |hwnd, _|
      pid_buf = "\0" * 4
      get_wnd_pid.call(hwnd, pid_buf)
      if pid_buf.unpack1('L') == my_pid
        buf = "\0" * 512
        len = get_wnd_text.call(hwnd, buf, 512)
        title = buf[0, len].to_s
        post_msg.call(hwnd, wm_close, 0, 0) if title.include?("MH Thongke") && !title.include?("Info HUD") && !title.include?("info-HUD")
      end
      1
    end
    enum_wnd.call(cb, 0)
  rescue => e
    puts "close_mh_thongke_dialog_windows error: #{e.message}"
  end

  def self.show_dialog
    @active_dialog_tab = "tab-mat" unless main_dialog_valid_tab?(@active_dialog_tab)
    begin
      if respond_to?(:project_state_hash)
        hidden_state = project_state_hash("hidden_items")
        if hidden_state.is_a?(Hash) && hidden_state["list"].is_a?(Array)
          new_list = normalize_hidden_names(hidden_state["list"])
          session.hidden_list = new_list
          @hidden_list = new_list
          @hidden_name_set_sig = nil
        end
      end
    rescue
    end
    @dlg.close if @dlg && @dlg.visible? rescue nil
    close_mh_thongke_dialog_windows

    # Reset HTML cache so update_html always calls set_html on the new dialog
    @last_main_html_hash = nil

    @dlg = UI::HtmlDialog.new({
      :dialog_title    => "MH Thongke",
      :preferences_key => "MH_THONGKE",
      :scrollable      => true,
      :resizable       => true,
      :width  => 1100,
      :height => 750,
      :left   => 100,
      :top    => 100,
      :style  => UI::HtmlDialog::STYLE_DIALOG
    })
    if @dlg.respond_to?(:set_on_closed)
      dlg_ref = @dlg
      @dlg.set_on_closed {
        @dlg = nil if @dlg == dlg_ref
        detach_observers_if_idle
      }
    end

    main_dialog_register_callback("refresh_data") { |_|
      refresh_main_dialog_after_data_change
    }
    main_dialog_register_callback("dialog_tab_changed") { |_, tab_id|
      tab_id = tab_id.to_s
      @active_dialog_tab = tab_id if main_dialog_valid_tab?(tab_id)
      @dialog_activity_until = Time.now.to_f + 2.0
      update_html(false) if @dlg && @dlg.visible?
    }
    main_dialog_register_callback("mark_dialog_activity") { |_|
      @dialog_activity_until = Time.now.to_f + 2.0
    }
    main_dialog_register_callback("main_ui_debug") { |_, message|
      main_ui_debug("JS #{message}")
    }
    main_dialog_register_callback("open_import_mini") { |_|
      show_import_mini_dialog
    }
    main_dialog_register_callback("open_material_hud") { |_|
      open_import_material_hud
    }
    main_dialog_register_callback("open_info_hud") { |_|
      show_info_hud if respond_to?(:show_info_hud)
    }
    main_dialog_register_callback("set_import_excel_path") { |_, path| main_dialog_apply_excel_path(path) }
    main_dialog_register_callback("refresh_import_excel") { |_| main_dialog_refresh_excel_data }
    main_dialog_register_callback("fill_sp_set_input_path") { |_, path| main_dialog_set_fill_sp_input_path(path, auto_output: true) }
    main_dialog_register_callback("fill_sp_set_output_path") { |_, path| main_dialog_set_fill_sp_output_path(path) }
    main_dialog_register_callback("fill_sp_set_library_path") { |_, path| main_dialog_set_fill_sp_library_path(path) }
    main_dialog_register_callback("fill_sp_set_include_son") { |_, flag| main_dialog_set_fill_sp_include_son(flag) }
    main_dialog_register_callback("fill_sp_pick_input") { |_|
      @active_dialog_tab = "tab-files"
      current = @fill_sp_input_path.to_s
      model_dir = begin
        path = (Sketchup.active_model.path rescue "").to_s
        path.empty? ? "" : File.dirname(path)
      rescue
        ""
      end
      start_dir = if !current.to_s.strip.empty? && File.directory?(File.dirname(current))
        File.dirname(current)
      else
        model_dir
      end
      path = UI.openpanel("Chọn file Excel input Fill SP", start_dir, "*.xlsx;*.xlsm")
      main_dialog_set_fill_sp_input_path(path, auto_output: true) if path
    }
    main_dialog_register_callback("fill_sp_pick_output") { |_|
      @active_dialog_tab = "tab-files"
      current = @fill_sp_output_path.to_s
      suggest = current.to_s.strip.empty? ? fill_sp_auto_output_path(@fill_sp_input_path, fill_sp_include_son_code?) : current
      suggest = "output_generated_son.xlsx" if suggest.to_s.strip.empty?
      path = UI.savepanel("Chọn nơi lưu output Fill SP", File.dirname(suggest), File.basename(suggest))
      main_dialog_set_fill_sp_output_path(path) if path
    }
    main_dialog_register_callback("fill_sp_pick_library") { |_|
      @active_dialog_tab = "tab-files"
      current = @fill_sp_library_path.to_s
      path = UI.openpanel("Chọn file library.xlsx", File.dirname(current), "*.xlsx;*.xlsm")
      main_dialog_set_fill_sp_library_path(path) if path
    }
    main_dialog_register_callback("fill_sp_run_generate") { |_| main_dialog_run_fill_sp_generate }
    main_dialog_register_callback("fill_sp_open_output") { |_| main_dialog_open_fill_sp_output }
    main_dialog_register_callback("change_group") { |_, mode|
      session.group_by = mode
      @group_by = mode
      refresh_main_dialog_after_data_change
    }
    main_dialog_register_callback("change_display") { |_, mode|
      session.display_mode = mode
      @display_mode = mode
      process_selection if session.display_mode.to_s == "SELECTED"
      update_html
    }
    main_dialog_register_callback("change_pk_report_scope") { |_, mode|
      scope = mode.to_s.upcase
      scope = ["PROJECT", "CUT"].include?(scope) ? scope : "PROJECT"
      session.pk_report_view_scope = scope
      @pk_report_view_scope = scope
      save_preferences if respond_to?(:save_preferences)
      update_html(true)
    }
    main_dialog_register_callback("change_pk_report_source") { |_, source_id|
      session.pk_report_cut_source = source_id.to_s
      @pk_report_cut_source = source_id.to_s
      save_preferences if respond_to?(:save_preferences)
      update_html(true)
    }
    main_dialog_register_callback("import_pk_report_json") { |_|
      path = UI.openpanel("Chon file JSON phu kien", "", "*.json;*.JSON")
      next unless path
      begin
        sources = pk_report_extract_sources_from_json(path)
        if sources.empty?
          UI.messagebox("File JSON khong co du lieu phu kien (items).")
          next
        end
        @pk_report_external_sources = sources
        session.pk_report_view_scope = "CUT"
        @pk_report_view_scope = "CUT"
        session.pk_report_cut_source = sources.first["id"].to_s
        @pk_report_cut_source = session.pk_report_cut_source
        save_preferences if respond_to?(:save_preferences)
        update_html(true)
        UI.messagebox("Da nap JSON phu kien: #{File.basename(path)} (#{sources.size} nguon du lieu).")
      rescue => e
        UI.messagebox(e.message)
      end
    }
    main_dialog_register_callback("clear_pk_report_json") { |_|
      @pk_report_external_sources = []
      if session.pk_report_cut_source.to_s.start_with?("json:")
        session.pk_report_cut_source = ""
        @pk_report_cut_source = ""
      end
      save_preferences if respond_to?(:save_preferences)
      update_html(true)
    }
    main_dialog_register_callback("set_active_data_source") { |_, source_id|
      set_active_data_source(source_id.to_s)
    }
    # Note: importing JSON / SKP snapshots is done via tab 📁 FILE
    # (Update / Thêm File). The dropdown above picks among those snapshots.
    main_dialog_register_callback("select_row") { |_, idx|
      dialog_with_selection_lock do
        @last_selected_row_idx = idx.to_i
        item = @current_report_items[idx.to_i]
        dialog_select_pairs_in_model(dialog_pairs_for_item(item))
      end
    }
    main_dialog_register_callback("select_mat_row") { |_, idx|
      dialog_with_selection_lock do
        item = @current_mat_items[idx.to_i]
        dialog_select_pairs_in_model(dialog_pairs_for_item(item))
      end
    }
    main_dialog_register_callback("select_mat_summary") { |_, product, name, spec, ids = ""|
      dialog_with_selection_lock do
        pairs = respond_to?(:mini_stat_entries_for_ids) ? mini_stat_entries_for_ids(ids) : []
        unless pairs.empty?
          dialog_select_pairs_in_model(pairs)
          next
        end

        product_key = product.to_s.strip
        name_key = name.to_s.strip
        spec_key = spec.to_s.strip
        pairs = []
        Array(@current_mat_items).each do |item|
          next unless item.is_a?(Hash)
          item_product = item[:actual_product].to_s.strip
          item_product = item[:product].to_s.strip if item_product.empty?
          item_product = product_code_base(item_product) if respond_to?(:product_code_base)
          item_product = "--" if item_product.empty?
          item_name = item[:ma_vl_source].to_s.strip
          item_name = item[:name].to_s.strip if item_name.empty?
          item_name = "--" if item_name.empty?
          item_spec = item[:spec].to_s.strip
          next unless item_product == product_key && item_name == name_key && item_spec == spec_key

          pairs.concat(dialog_pairs_for_item(item))
        end
        dialog_select_pairs_in_model(pairs)
      end
    }
    main_dialog_register_callback("select_product") { |_, product_code|
      dialog_with_selection_lock do
        all_pairs = []
        @current_report_items.each do |item|
          next unless item[:actual_product] == product_code || item[:product] == product_code
          all_pairs.concat(dialog_pairs_for_item(item))
        end
        dialog_select_pairs_in_model(all_pairs)
      end
    }


    main_dialog_register_callback("toggle_tree") { |_, base|
      base_json = JSON.generate(base.to_s)
      js = "
        (function(){
          var treeBase = #{base_json};
          // Find which table contains the clicked element by checking all tables
          var tables = document.querySelectorAll('table');
          tables.forEach(function(tbl){
            var rows = Array.prototype.slice.call(tbl.querySelectorAll('[data-tree]')).filter(function(el){
              return el.getAttribute('data-tree') === treeBase;
            });
            if (rows.length === 0) return;
            var parents  = rows.filter(function(el){ return el.classList.contains('parent-row'); });
            var children = rows.filter(function(el){ return el.classList.contains('child-row'); });
            var headers  = rows.filter(function(el){ return el.classList.contains('header-row'); });
            var isExpanded = children.length > 0 && children[0].style.display !== 'none';
            if (isExpanded) {
              parents.forEach(function(el){ el.style.display = ''; });
              children.forEach(function(el){ el.style.display = 'none'; });
              headers.forEach(function(el){ el.style.display = 'none'; });
            } else {
              parents.forEach(function(el){ el.style.display = 'none'; });
              children.forEach(function(el){ el.style.display = ''; });
              headers.forEach(function(el){ el.style.display = ''; });
            }
          });
        })();
      "
      main_dialog_execute_script(js)
    }

    main_dialog_register_callback("undo_last") { |_|
      begin
        if respond_to?(:mini_dialog_visible?) && mini_dialog_visible? && respond_to?(:mini_undo_last_action)
          mini_undo_last_action
        else
          match_rules_before = (@match_rule_undo_stack ||= []).pop
          if respond_to?(:perform_model_undo)
            perform_model_undo
          else
            @model ||= Sketchup.active_model
            if @model.respond_to?(:undo)
              @model.undo
            elsif Sketchup.respond_to?(:undo)
              Sketchup.undo
            else
              UI.send_action("editUndo:") rescue nil
            end
          end
          if match_rules_before && respond_to?(:restore_match_rule_undo_snapshot)
            restore_match_rule_undo_snapshot(match_rules_before)
          end
        end
        @mini_accept_rules = nil if instance_variable_defined?(:@mini_accept_rules)
        refresh_import_related_views(true, false, false)
      rescue => e
        UI.messagebox(e.message)
      end
    }

    main_dialog_register_callback("forward_key") { |_, kc, shift, ctrl, alt|
      begin
        require 'fiddle'
        user32   = Fiddle.dlopen('user32')
        kernel32 = Fiddle.dlopen('kernel32')
        keycode  = kc.to_i; shift = shift.to_i; ctrl = ctrl.to_i; alt = alt.to_i
        get_wnd_pid  = Fiddle::Function.new(user32['GetWindowThreadProcessId'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        get_wnd_text = Fiddle::Function.new(user32['GetWindowTextA'], [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
        set_fg       = Fiddle::Function.new(user32['SetForegroundWindow'], [Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT)
        get_fg       = Fiddle::Function.new(user32['GetForegroundWindow'], [], Fiddle::TYPE_INTPTR_T)
        attach_input = Fiddle::Function.new(user32['AttachThreadInput'], [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
        get_tid      = Fiddle::Function.new(kernel32['GetCurrentThreadId'], [], Fiddle::TYPE_INT)
        keybd        = Fiddle::Function.new(user32['keybd_event'], [Fiddle::TYPE_CHAR, Fiddle::TYPE_CHAR, Fiddle::TYPE_INT, Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_VOID)
        enum_wnd     = Fiddle::Function.new(user32['EnumWindows'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INTPTR_T], Fiddle::TYPE_INT)
        main_hwnd = 0; my_pid = Process.pid
        cb = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INTPTR_T, Fiddle::TYPE_INTPTR_T]) do |hwnd, _|
          pid_buf = "\0" * 4; get_wnd_pid.call(hwnd, pid_buf)
          if pid_buf.unpack1('L') == my_pid
            buf = "\0" * 512; len = get_wnd_text.call(hwnd, buf, 512); title = buf[0, len]
            if title.include?("- SketchUp") && !title.include?("ABF"); main_hwnd = hwnd; next 0; end
          end
          1
        end
        enum_wnd.call(cb, 0)
        if main_hwnd != 0
          my_tid = get_tid.call; fg_hwnd = get_fg.call; fg_tid = get_wnd_pid.call(fg_hwnd, "\0" * 4)
          attach_input.call(my_tid, fg_tid, 1); set_fg.call(main_hwnd); attach_input.call(my_tid, fg_tid, 0)
          keybd.call(0x10, 0, 0, 0) if shift == 1
          keybd.call(0x11, 0, 0, 0) if ctrl == 1
          keybd.call(0x12, 0, 0, 0) if alt == 1
          keybd.call(keycode, 0, 0, 0); keybd.call(keycode, 0, 0x0002, 0)
          keybd.call(0x12, 0, 0x0002, 0) if alt == 1
          keybd.call(0x11, 0, 0x0002, 0) if ctrl == 1
          keybd.call(0x10, 0, 0x0002, 0) if shift == 1
        end
      rescue => e
        puts "Forward key error: #{e.message}"
      end
    }

    main_dialog_register_callback("update_name") { |_, idx, new_name|
      begin
        data = @current_report_items[idx.to_i]
        if data && new_name && !new_name.strip.empty?
          restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
          model_before = respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(data[:stat_entities] || []) : []
          detach_observers
          @model.start_operation("Rename Linh Kien", true)
          time_str = Time.now.strftime("%d/%m/%y %H:%M")
          (data[:stat_entities] || []).each do |pair|
            ent, _top = pair.is_a?(Array) ? pair : [pair, pair]
            next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
            next if ent.deleted?
            if respond_to?(:apply_import_entity_name)
              apply_import_entity_name(ent, new_name, data[:dict], data[:key])
            else
              ent.set_attribute(data[:dict], data[:key], new_name)
              ent.definition.set_attribute(data[:dict], data[:key], new_name) if ent.respond_to?(:definition)
            end
            ent.set_attribute("MH_Thongke", "last_modified", time_str)
          end
          save_history("Đổi tên", "Mã SP: #{data[:actual_product]}, Tên cũ: #{data[:name]}, Tên mới: #{new_name}")
          record_mini_name_lineage(data[:actual_product], "PK", data[:name], new_name, "", "rename", "main_manual_rename") if respond_to?(:record_mini_name_lineage)
          @model.commit_operation
          record_restore_action("main_rename", "Bảng chính sửa tên", { product: data[:actual_product], kind: "PK", old_name: data[:name], name: new_name, model_before: model_before }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          attach_observers
          main_dialog_refresh_import_state(true, false, false)
        end
      rescue => e
        @model.abort_operation rescue nil; attach_observers
        UI.messagebox("Lỗi Đổi Tên: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      end
    }
    main_dialog_register_callback("update_tag") { |_, idx, new_tag|
      begin
        data = @current_report_items[idx.to_i]
        if data && new_tag && !new_tag.strip.empty?
          detach_observers
          @model.start_operation("Rename Tag/Layer", true)
          layer = @model.layers[new_tag] || @model.layers.add(new_tag)
          sel = @model.selection
          (data[:stat_entities] || []).each do |pair|
            ent, top = pair.is_a?(Array) ? pair : [pair, pair]
            next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
            next if ent.deleted?
            next if !sel.empty? && !sel.include?(top)
            ent.layer = layer
          end
          @model.commit_operation
          attach_observers
          @pending_model_refresh = false
          @pending_view_refresh = false
        end
      rescue => e
        @model.abort_operation rescue nil; attach_observers
        UI.messagebox("Lỗi Đổi Tag: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      end
    }
    main_dialog_register_callback("change_unit") { |_, idx, new_unit|
      data = @current_report_items[idx.to_i]
      if data
        new_unit_s = new_unit.to_s
        dk = data[:_data_key]
        if dk
          old_unit = @unit_overrides[dk] || data[:unit]
          @length_display_units[dk] = old_unit if ["mm","m","md"].include?(old_unit) && !["mm","m","md"].include?(new_unit_s)
          @unit_overrides[dk] = new_unit_s
          data[:_data_key] = dk
        end
        data[:unit] = new_unit_s
        data[:_resolved_unit] = new_unit_s
        data[:_resolved_qty] = row_display_qty(data, dk, new_unit_s) rescue data[:count]
        prev_lu = (dk && @length_display_units[dk]) ? @length_display_units[dk] : (data[:_length_display_unit] || "mm")
        data[:_length_display_unit] = (["mm","m","md"].include?(new_unit_s) ? new_unit_s : prev_lu).to_s
        save_preferences; update_html
      end
    }
    main_dialog_register_callback("update_psu_list") { |_, list_str|
      new_list = list_str.to_s.split(",").map(&:to_i).select { |w| w > 0 }.uniq.sort.reverse
      @psu_list = new_list.empty? ? [200,100,60] : new_list
      refresh_main_dialog_after_data_change
    }
    main_dialog_register_callback("update_power_factor") { |_, p|
      @led_power_factor = p.to_f
      refresh_main_dialog_after_data_change
    }
    main_dialog_register_callback("rename_power_factor") { |_, p_str, new_name|
      val = p_str.to_f
      @led_factors[val] = new_name.to_s.strip if @led_factors.key?(val)
      update_html
    }
    main_dialog_register_callback("add_power_factor") { |_, p_str, n_str|
      val = p_str.to_f
      if val > 0 && !@led_factors.key?(val)
        @led_factors[val] = n_str.to_s.strip.empty? ? "Nguồn #{val}W" : n_str.to_s.strip
        @led_power_factor = val
        refresh_main_dialog_after_data_change
      end
    }
    main_dialog_register_callback("delete_power_factor") { |_, p|
      val = p.to_f
      if @led_factors.length > 1
        @led_factors.delete(val)
        @led_power_factor = @led_factors.keys.first if @led_power_factor == val
        refresh_main_dialog_after_data_change
      end
    }
    main_dialog_register_callback("save_settings") { |_, hidden_str|
      @active_dialog_tab = "tab-settings"
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      hidden_payload = hidden_str.to_s
      next if hidden_payload.strip.empty?

      new_list = if hidden_payload == "__MH_EMPTY_HIDDEN__"
        []
      else
        normalize_hidden_names(hidden_payload.split("|"))
      end
      session.hidden_list = new_list
      @hidden_list = new_list
      @hidden_name_set_sig = nil
      save_project_state_hash("hidden_items", { "list" => session.hidden_list }) if respond_to?(:save_project_state_hash)
      record_known_pk_names(session.hidden_list, false) if respond_to?(:record_known_pk_names)
      save_preferences
      record_restore_action("settings_hidden_list", "Cap nhat danh sach an", { count: session.hidden_list.size }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
      main_dialog_refresh_import_state(true, false, false, true)
    }
    main_dialog_register_callback("add_hidden_items") { |_, text| main_dialog_add_hidden_items(text) }
    main_dialog_register_callback("add_hidden_item") { |_, text| main_dialog_add_hidden_items(text) }
    main_dialog_register_callback("remove_hidden_item") { |_, name|
      @active_dialog_tab = "tab-settings"
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      target = hidden_name_norm(name)
      new_list = normalize_hidden_names(session.hidden_list || []).reject { |item| hidden_name_norm(item) == target }
      session.hidden_list = new_list
      @hidden_list = new_list
      @hidden_name_set_sig = nil
      save_project_state_hash("hidden_items", { "list" => session.hidden_list }) if respond_to?(:save_project_state_hash)
      save_preferences
      process_selection
      record_restore_action("settings_remove_hidden", "Xóa khỏi danh sách ẩn", { name: name }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
      main_dialog_refresh_import_state(false, false, false, true)
    }
    main_dialog_register_callback("change_project_total_view") { |_, mode|
      m = mode.to_s.upcase
      v = ["DETAIL", "COMPACT"].include?(m) ? m : "COMPACT"
      v = "COMPACT"  # enforce default for now
      session.project_total_view = v
      @project_total_view = v
      save_preferences
      update_html
    }
    main_dialog_register_callback("change_project_total_sort") { |_, mode|
      m = mode.to_s.upcase
      v = ["CUT", "PRODUCT"].include?(m) ? m : "CUT"
      session.project_total_sort = v
      @project_total_sort = v
      save_preferences
      update_html
    }

    # ==================== NGÀY ĐẶT ====================
    main_dialog_register_callback("update_ngay_dat") { |_, idx, val|
      main_dialog_apply_ngay_dat(:acc, idx, val, false)
    }
    main_dialog_register_callback("update_mat_ngay_dat") { |_, idx, val|
      main_dialog_apply_ngay_dat(:mat, idx, val, false)
    }
    main_dialog_register_callback("set_ngay_dat_today") { |_, idx|
      main_dialog_apply_ngay_dat(:acc, idx, Time.now.strftime("%d/%m/%Y"), true)
    }
    main_dialog_register_callback("set_mat_ngay_dat_today") { |_, idx|
      main_dialog_apply_ngay_dat(:mat, idx, Time.now.strftime("%d/%m/%Y"), true)
    }

    # ==================== EXPORT EXCEL (có cột Ngày Đặt) ====================
    main_dialog_register_callback("export_excel") { |_|
      if respond_to?(:session) && session
        current_mode = @group_by.to_s
        session.group_by = current_mode unless current_mode.empty?
      end
      # Ensure export rows are rebuilt from the currently selected grouping mode.
      if respond_to?(:process_selection_cached)
        process_selection_cached(false)
      elsif respond_to?(:process_selection)
        process_selection
      end
      path = UI.savepanel("Lưu file Excel (XLSX)", "", "ThongKe.xlsx")
      if path
        begin
          @current_report_items ||= []
          @data_map ||= {}
          @unit_overrides ||= {}
          @length_display_units ||= {}

          export_by_name = @group_by.to_s == "NAME"
          sheet_rows = [[
            "STT", "Tên hàng", "Kích thước", "", "ĐVT", "SL", "", "", "",
            "Mã SP", "Tên SP", "Ghi chú", "Ngày Đặt"
          ]]
          append_export_row = lambda do |name, size, unit, qty, product, ten_sp, note, date|
            row = Array.new(13, "")
            row[0] = sheet_rows.size
            row[1] = name
            row[2] = size
            row[4] = unit
            row[5] = qty
            row[9] = product
            row[10] = ten_sp
            row[11] = note
            row[12] = normalize_order_date(date)
            sheet_rows << row
          end

          export_rows = main_dialog_export_acc_rows
          export_rows.each_with_index do |data, idx|
            next unless data
            cu  = (data[:_resolved_unit] || data[:unit]).to_s
            prev_lu = (data[:_length_display_unit] || "mm").to_s
            is_ltc  = (data[:type] == :length && !["mm","m","md"].include?(cu) && data[:length_items].is_a?(Array) && !data[:length_items].empty?)
            is_pc   = data[:type] == :phaochi
            normalize_product_code = lambda do |value|
              begin
                product_code_exact(value)
              rescue
                value.to_s.strip.upcase
              end
            end
            valid_product_code = lambda do |value|
              begin
                product_code_valid?(value)
              rescue
                value.to_s =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?/
              end
            end
            product_values = Array(data[:product_list]).map { |p| normalize_product_code.call(p) }
                                                         .select { |p| valid_product_code.call(p) }
                                                         .uniq
            if product_values.empty?
              actual_product = normalize_product_code.call(data[:actual_product])
              product_values = [actual_product].select { |p| valid_product_code.call(p) }
            end
            ten_sp_values = Array(data[:ten_sp_list]).map { |v| fix_vietnamese_mojibake(v).to_s.strip }.reject(&:empty?).uniq
            ten_sp_values = [data[:ten_sp].to_s.strip].reject(&:empty?) if ten_sp_values.empty?
            export_product = export_by_name ? (product_values.size == 1 ? product_values.first : "") : data[:product]
            export_ten_sp  = if export_by_name
              (product_values.size == 1 && ten_sp_values.size <= 1 ? ten_sp_values.first.to_s : "")
            else
              ts = data[:ten_sp].to_s
              if ts.strip.empty? && !export_product.to_s.strip.empty? && respond_to?(:import_excel_product_name_for)
                import_excel_product_name_for(export_product, false).to_s
              else
                ts
              end
            end

            if is_pc
              # Phào chỉ xuất theo mét dài
              len_m = (data[:len_total_mm] / 1000.0).round(2)
              append_export_row.call(data[:name], data[:kich_thuoc].to_s, cu, len_m, export_product, export_ten_sp, data[:ghi_chu], data[:ngay_dat])
            elsif is_ltc
              groups = {}
              data[:length_items].each do |li|
                len_mm = (li[:len_inch] * 25.4).round(0)
                groups[len_mm] = (groups[len_mm] || 0) + 1
              end
              groups.sort_by { |k,_| k }.each do |len_mm, cnt|
                len_str = ["m","md"].include?(prev_lu) ? "#{(len_mm/1000.0).round(2)}#{prev_lu}" : "#{len_mm.to_i}mm"
                append_export_row.call("#{data[:name]} - dài #{len_str}", data[:kich_thuoc].to_s, cu, cnt, export_product, export_ten_sp, data[:ghi_chu], data[:ngay_dat])
              end
            else
              qty = data[:type] == :length ? (data[:length] * 25.4) : data[:count]
              unit = cu
              case cu
              when "m","md"
                qty = (qty / 1000.0).round(2) if data[:type] == :length
              when "mm"
                qty = qty.round(1) if data[:type] == :length
              else
                if data[:type] == :length && data[:name] =~ /led|nh[\u00f4o]m/i
                  unit = "md"; qty = (qty / 1000.0).round(2)
                elsif data[:type] == :length
                  qty = qty.round(1)
                end
              end
              append_export_row.call(data[:name], data[:kich_thuoc].to_s, unit, qty, export_product, export_ten_sp, data[:ghi_chu], data[:ngay_dat])
            end
          end
          path = "#{path}.xlsx" if File.extname(path.to_s).empty?
          MH::ExcelBridge.write(path, sheets: { "ThongKe" => sheet_rows })
          UI.messagebox("Đã xuất file thành công!\n#{path}")
        rescue => e
          UI.messagebox("Lỗi Excel: #{e.message}")
        end
      end
    }

    main_dialog_register_callback("export_material_excel") { |_|
      model = @model || Sketchup.active_model
      skp_path = model && !model.path.to_s.empty? ? model.path.to_s : ""
      skp_base = if !skp_path.empty?
        File.basename(skp_path, File.extname(skp_path))
      else
        "ThongKe_VatLieu"
      end
      suggested_name = "#{skp_base}.xlsx"
      path = UI.savepanel("Lưu file Excel Vật liệu (XLSX)", "", suggested_name)
      if path
        begin
          nesting_created_at = ""
          begin
            if respond_to?(:snapshots_for_current_project) && respond_to?(:snapshot_file_role) && respond_to?(:snapshot_file_created_at)
              snaps = snapshots_for_current_project(true)
              nesting_snaps = Array(snaps).select { |s| snapshot_file_role(s).to_s == "NESTING" }
              if nesting_snaps.any?
                best_pair = nesting_snaps.map do |s|
                  raw = snapshot_file_created_at(s).to_s
                  [respond_to?(:report_date_time) ? report_date_time(raw) : nil, raw]
                end.select { |pair| pair[0] }.max_by { |pair| pair[0] }
                nesting_created_at = best_pair ? best_pair[1].to_s : snapshot_file_created_at(nesting_snaps.first).to_s
              end
            end
          rescue
          end
          if nesting_created_at.to_s.strip.empty? && !skp_path.to_s.strip.empty?
            begin
              skp_dir = File.dirname(skp_path)
              nest_files = Dir.glob(File.join(skp_dir, "*.skp")).select { |fp| File.basename(fp).upcase.include?("_NESTING") }
              unless nest_files.empty?
                latest = nest_files.max_by do |fp|
                  begin
                    File.ctime(fp)
                  rescue
                    File.mtime(fp)
                  end
                end
                nesting_created_at = begin
                  File.ctime(latest).strftime("%Y-%m-%d %H:%M:%S")
                rescue
                  File.mtime(latest).strftime("%Y-%m-%d %H:%M:%S")
                end
              end
            rescue
            end
          end
          nesting_display = begin
            if respond_to?(:report_date_time)
              t = report_date_time(nesting_created_at)
              t ? t.strftime("%d/%m/%Y %H:%M") : nesting_created_at.to_s
            else
              nesting_created_at.to_s
            end
          rescue
            nesting_created_at.to_s
          end
          sheet_rows = [
            ["Ngày nesting", nesting_display],
            ["File", skp_base],
            [],
            [
              "STT", "Tên hàng", "Dày", "", "ĐVT", "SL", "SL(sel)", "Tag/Layer", "",
              "Mã SP", "Tên SP", "Ghi chú", "Trạng thái", "% Hoàn thành", "Ngày Đặt"
            ]
          ]
          export_product_base = lambda do |value|
            text = value.to_s.strip.upcase
            if text =~ /\A([A-Z]+\d+)(?:\.\d+)?\z/
              Regexp.last_match(1)
            else
              text.split(".").first.to_s
            end
          end

          material_export_rows = {}
          (@current_mat_items || []).each do |row|
            next unless row.is_a?(Hash)

            product = row[:actual_product].to_s.strip
            product = row[:product].to_s.strip if product.empty?
            product = export_product_base.call(product)
            product = "--" if product.empty?

            name = row[:ma_vl_source].to_s.strip
            name = row[:name].to_s.strip if name.empty?
            name = "--" if name.empty?

            thickness = row[:thickness].to_s.strip
            thickness = row[:spec].to_s.strip if thickness.empty?
            thickness = MH::MaterialCode.export_size(
              row[:name], fallback: MH::MaterialCode.export_size(name, fallback: thickness)
            )
            unit = row[:unit].to_s.strip
            key = [product, name, thickness, unit].join("\u0000")

            material_export_rows[key] ||= {
              product: product,
              ten_sp_values: [],
              name: name,
              thickness: thickness,
              note_values: [],
              unit: unit,
              date_values: [],
              status_values: [],
              completion_values: [],
              layer_values: [],
              count: 0.0,
              sel_count: 0
            }
            grouped = material_export_rows[key]
            ten_sp = row[:ten_sp].to_s.strip
            if ten_sp.empty? && respond_to?(:import_excel_product_name_for)
              ten_sp = import_excel_product_name_for(product, false).to_s.strip
            end
            grouped[:ten_sp_values] << ten_sp unless ten_sp.empty? || grouped[:ten_sp_values].include?(ten_sp)
            note = row[:ghi_chu].to_s.strip
            grouped[:note_values] << note unless note.empty? || grouped[:note_values].include?(note)
            date = normalize_order_date(row[:ngay_dat]).to_s.strip
            grouped[:date_values] << date unless date.empty? || grouped[:date_values].include?(date)
            status = row[:trang_thai].to_s.strip
            grouped[:status_values] << status unless status.empty? || grouped[:status_values].include?(status)
            completion = row[:completion_text].to_s.strip
            grouped[:completion_values] << completion unless completion.empty? || grouped[:completion_values].include?(completion)
            layer = row[:layer].to_s.strip
            grouped[:layer_values] << layer unless layer.empty? || grouped[:layer_values].include?(layer)
            grouped[:count] += row[:count].to_f
            grouped[:sel_count] += row[:sel_count].to_i
          end

          material_export_rows.values.sort_by { |row| [row[:product].to_s, row[:name].to_s, row[:thickness].to_s] }.each do |row|
            sheet_rows << [
              sheet_rows.size - 3,
              row[:name].to_s,
              row[:thickness].to_s,
              "",
              row[:unit].to_s,
              "",
              row[:sel_count].to_i,
              row[:layer_values].join(" | "),
              "",
              row[:product].to_s,
              row[:ten_sp_values].join(", "),
              row[:note_values].join(" | "),
              row[:status_values].join(" | "),
              row[:completion_values].join(" | "),
              row[:date_values].join(" | ")
            ]
          end

          final_path = path.to_s.strip
          final_path = "#{final_path}.xlsx" if File.extname(final_path).to_s.empty?
          MH::ExcelBridge.write(final_path, sheets: { "VatLieu" => sheet_rows })
          UI.messagebox("Đã xuất vật liệu thành công!\n#{final_path}")
        rescue => e
          UI.messagebox("Lỗi Excel vật liệu: #{e.message}")
        end
      end
    }

    # ==================== IMPORT EXCEL PHỤ KIỆN ====================
    # JSON-only runtime:
    # - UI/HUD/Mini Import luôn đọc @imported_excel_data từ JSON cache.
    # - Callback này chỉ dùng để nạp thủ công Excel -> convert -> ghi JSON cache.
    main_dialog_register_callback("import_excel") { |_|
      path = UI.openpanel("Chọn file Excel phụ kiện", "", "*.xlsx")
      schedule_import_excel_reload(path, "main_dialog") if path
    }

    # ==================== IMPORT NGƯỢC EXCEL ĐÃ XUẤT ====================
    # Đọc file Excel đã xuất bởi plugin, so sánh SL + Tên + ĐVT
    main_dialog_register_callback("import_back_excel") { |_|
      path = UI.openpanel("Chọn file Excel đã xuất (để so sánh)", "", "*.xlsx")
      if path
        begin
          rows = MH::ExcelBridge.read_sheet(path)
          @back_imported_excel = []
          # Tìm dòng header (có "Tên hàng" hoặc cột 2 là STT)
          # File xuất ra: col1=STT, col2=Tên hàng, col5=ĐVT, col6=SL, col10=Mã SP, col11=Tên SP, col12=Ghi chú, col13=Ngày Đặt
          start_row = 11  # Mặc định từ dòng 11 (theo template DMVT)
          empty_count = 0
          rows.drop(start_row - 1).each do |row|
            v2 = Array(row)[1].to_s.strip
            if v2.empty?
              empty_count += 1
              break if empty_count >= 10
              next
            end
            empty_count = 0
            @back_imported_excel << {
              name:     v2,
              unit:     Array(row)[4].to_s.strip,
              qty:      Array(row)[5].to_f,
              product:  Array(row)[9].to_s.strip.upcase,
              ten_sp:   Array(row)[10].to_s.strip,
              ghi_chu:  Array(row)[11].to_s.strip,
              ngay_dat: normalize_order_date(Array(row)[12])
            }
          end
          save_back_import_cache(path) if respond_to?(:save_back_import_cache)
          UI.messagebox("Da doc #{@back_imported_excel.size} dong tu Excel xuat ra.\nHe thong se highlight o sai khac.")
          refresh_main_dialog_after_data_change
        rescue => e
          UI.messagebox("Lỗi import ngược Excel: #{e.message}")
        end
      end
    }

    main_dialog_register_callback("clear_back_import") { |_|
      @back_imported_excel = nil
      clear_back_import_cache if respond_to?(:clear_back_import_cache)
      @data_map.values.each { |row| row[:back_diff] = nil } if @data_map
      refresh_main_dialog_after_data_change
    }

    main_dialog_register_callback("apply_back_import_updates") { |_, payload|
      begin
        main_ui_debug("apply_back_import_updates payload=#{payload.inspect}")
        options = {}
        begin
          parsed = JSON.parse(payload.to_s)
          options = parsed if parsed.is_a?(Hash)
        rescue
          options = {}
        end
        result = apply_back_import_updates!(options)
        main_ui_debug("apply_back_import_updates result=#{result.inspect}")
        if result[:fields].to_i <= 0
          UI.messagebox(
            "Khong co o nao can cap nhat tu Excel xuat.\n" \
            "- Pham vi: #{result[:scope]}\n" \
            "- Truong: #{Array(result[:selected_fields]).join(', ')}\n" \
            "- Dong khop: #{result[:matches]}\n\n" \
            "Neu van thay o mau do, hay Import nguoc Excel lai de nap du lieu moi."
          )
        else
          UI.messagebox(
            "Da cap nhat tu Excel xuat:\n" \
            "- Pham vi: #{result[:scope]}\n" \
            "- Truong: #{Array(result[:selected_fields]).join(', ')}\n" \
            "- Dong khop: #{result[:matches]}\n" \
            "- Dong co thay doi: #{result[:rows]}\n" \
            "- O da cap nhat: #{result[:fields]}"
          )
        end
      rescue => e
        main_ui_debug("apply_back_import_updates ERROR #{e.class}: #{e.message}")
        UI.messagebox("Loi cap nhat tu Import nguoc Excel: #{e.message}")
        puts "apply_back_import_updates error: #{e.class}: #{e.message}"
        puts e.backtrace.first(20).join("\n")
      end
    }

    main_dialog_register_callback("apply_back_import_updates_all") { |_|
      begin
        main_ui_debug("apply_back_import_updates_all clicked")
        result = apply_back_import_updates!(scope: "all", fields: %w[ngay_dat])
        main_ui_debug("apply_back_import_updates_all result=#{result.inspect}")
        if result[:fields].to_i <= 0
          UI.messagebox("Không có ô nào cần cập nhật.\n- Dòng khớp: #{result[:matches]}")
        else
          UI.messagebox(
            "Đã cập nhật toàn bộ:\n" \
            "- Dòng khớp: #{result[:matches]}\n" \
            "- Dòng có thay đổi: #{result[:rows]}\n" \
            "- Ô đã cập nhật: #{result[:fields]}"
          )
        end
      rescue => e
        main_ui_debug("apply_back_import_updates_all ERROR #{e.class}: #{e.message}")
        UI.messagebox("Lỗi cập nhật toàn bộ: #{e.message}")
        puts "apply_back_import_updates_all error: #{e.class}: #{e.message}"
      end
    }

    main_dialog_register_callback("apply_back_import_updates_selected") { |_|
      begin
        main_ui_debug("apply_back_import_updates_selected clicked last_idx=#{@last_selected_row_idx.inspect}")
        idx = @last_selected_row_idx.nil? ? nil : @last_selected_row_idx.to_i
        if idx.nil? || idx < 0
          raise "Hãy chọn 1 dòng trước khi cập nhật dòng chọn."
        end
        result = apply_back_import_updates!(scope: "selected", row_indices: [idx], fields: %w[ngay_dat])
        main_ui_debug("apply_back_import_updates_selected result=#{result.inspect}")
        if result[:fields].to_i <= 0
          UI.messagebox("Dòng chọn không có ô nào cần cập nhật.\n- Dòng khớp: #{result[:matches]}")
        else
          UI.messagebox(
            "Đã cập nhật dòng chọn:\n" \
            "- Dòng khớp: #{result[:matches]}\n" \
            "- Dòng có thay đổi: #{result[:rows]}\n" \
            "- Ô đã cập nhật: #{result[:fields]}"
          )
        end
      rescue => e
        main_ui_debug("apply_back_import_updates_selected ERROR #{e.class}: #{e.message}")
        UI.messagebox("Lỗi cập nhật dòng chọn: #{e.message}")
        puts "apply_back_import_updates_selected error: #{e.class}: #{e.message}"
      end
    }

    main_dialog_register_callback("export_history") { |_|
      path = UI.savepanel("Lưu lịch sử thay đổi (XLSX)", "", "LichSuThayDoi.xlsx")
      if path
        begin
          rows = [["Thời gian", "Hành động", "Chi tiết"]]
          (@change_history || []).each do |h|
            rows << [h[:time] || h["time"], h[:action] || h["action"], h[:details] || h["details"]]
          end
          path = "#{path}.xlsx" if File.extname(path.to_s).empty?
          MH::ExcelBridge.write(path, sheets: { "Lich su thay doi" => rows })
          UI.messagebox("Đã xuất lịch sử thay đổi thành công!")
        rescue => e
          UI.messagebox("Lỗi xuất lịch sử: #{e.message}")
        end
      end
    }

    main_dialog_register_callback("action_update") { |_, idx|
      begin
        indices = main_dialog_parse_indices(idx)
        data_items = indices.map { |row_idx| @current_report_items[row_idx.to_i] }.compact
        data_items = [@current_report_items[idx.to_i]].compact if data_items.empty?
        update_items = data_items.select { |row| report_row_update?(row) }
        if update_items.any?
          restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
          model_pairs = update_items.flat_map { |row| row[:stat_entities] || [] }
          model_before = respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(model_pairs) : []
          push_match_rule_undo_snapshot if respond_to?(:push_match_rule_undo_snapshot)
          @model.start_operation("Update Tên Phụ Kiện", true)
          time_str = Time.now.strftime("%d/%m/%y %H:%M")
          @match_rules ||= {}
          update_items.each do |data|
            target_name = data[:new_name].to_s
            target_name = pk_preserve_dimension_for_update(data[:name], target_name, data[:spec] || data[:kt]) if respond_to?(:pk_preserve_dimension_for_update)
            data[:new_name] = target_name
            (data[:stat_entities] || []).each do |pair|
              ent = pair.is_a?(Array) ? pair[0] : pair
              next if ent.deleted?
              if respond_to?(:apply_import_entity_name)
                apply_import_entity_name(ent, target_name, data[:dict], data[:key])
              else
                ent.set_attribute(data[:dict], data[:key], target_name)
                ent.definition.set_attribute(data[:dict], data[:key], target_name) if ent.respond_to?(:definition)
              end
              ent.set_attribute("MH_Thongke","last_modified", time_str)
            end
            rule_key = "#{data[:actual_product]}|#{data[:name].downcase.strip}"
            @match_rules[rule_key] = { "action"=>"update","new_name"=>target_name,"ex_name"=>target_name,"date"=>Time.now.strftime("%d/%m/%y %H:%M") }
            accept_spec = data[:spec].to_s
            accept_spec = data[:kt].to_s if accept_spec.empty?
            record_mini_accept(data[:actual_product], "PK", data[:name], target_name, accept_spec, "update") if respond_to?(:record_mini_accept)
          end
          save_match_rules
          first = update_items.first
          save_history("Cập nhật tên hàng","#{update_items.size} dòng | Mã SP: #{first[:actual_product]}, Tên cũ: #{first[:name]}, Tên mới: #{first[:new_name]}")
          @model.commit_operation
          first = update_items.first
          record_restore_action("main_update", "Bảng chính update tên", { product: first[:actual_product], kind: "PK", old_name: first[:name], name: first[:new_name], count: update_items.size, model_before: model_before }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
        end
      rescue => e
        @model.abort_operation rescue nil
        UI.messagebox("Lỗi Update: #{e.message}")
        puts "action_update error: #{e.class}: #{e.message}"
        puts e.backtrace.join("\n")
      end
    }
    main_dialog_register_callback("action_keep") { |_, idx|
      begin
        indices = main_dialog_parse_indices(idx)
        data_items = indices.map { |row_idx| @current_report_items[row_idx.to_i] }.compact
        data_items = [@current_report_items[idx.to_i]].compact if data_items.empty?
        keep_items = data_items.select { |row| report_row_update?(row) }
        if keep_items.any?
          restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
          push_match_rule_undo_snapshot if respond_to?(:push_match_rule_undo_snapshot)
          @model.start_operation("Keep Status Rule", true)
          @match_rules ||= {}
          keep_items.each do |data|
            rule_key = "#{data[:actual_product]}|#{data[:name].downcase.strip}"
            @match_rules[rule_key] = { "action"=>"keep","ex_name"=>data[:new_name].to_s,"date"=>Time.now.strftime("%d/%m/%y %H:%M") }
            accept_spec = data[:spec].to_s
            accept_spec = data[:kt].to_s if accept_spec.empty?
            record_mini_accept(data[:actual_product], "PK", data[:name], data[:new_name], accept_spec, "keep") if respond_to?(:record_mini_accept)
          end
          save_match_rules
          first = keep_items.first
          save_history("Giữ tên cũ","#{keep_items.size} dòng | Mã SP: #{first[:actual_product]}, Tên giữ: #{first[:name]}, Tên Excel: #{first[:new_name]}")
          @model.commit_operation
          first = keep_items.first
          record_restore_action("main_keep", "Bảng chính giữ tên", { product: first[:actual_product], kind: "PK", old_name: first[:name], name: first[:new_name], count: keep_items.size }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
        end
      rescue => e
        @model.abort_operation rescue nil
        UI.messagebox(e.message)
      end
    }
    main_dialog_register_callback("action_accept_no_spec") { |_, idx|
      begin
        indices = main_dialog_parse_indices(idx)
        data_items = indices.map { |row_idx| @current_report_items[row_idx.to_i] }.compact
        data_items = [@current_report_items[idx.to_i]].compact if data_items.empty?
        no_spec_items = data_items.select { |row| report_row_no_spec?(row) }
        if no_spec_items.any? && respond_to?(:record_mini_accept)
          restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
          @model.start_operation("Accept No SPEC Rule", true)
          no_spec_items.each do |data|
            record_mini_accept(data[:actual_product], "PK", data[:name], "", "", "accept_no_spec")
          end
          first = no_spec_items.first
          save_history("Chấp nhận No SPEC","#{no_spec_items.size} dòng | Mã SP: #{first[:actual_product]}, PK: #{first[:name]}")
          @model.commit_operation
          first = no_spec_items.first
          record_restore_action("main_accept_no_spec", "Bảng chính accept No SPEC", { product: first[:actual_product], kind: "PK", name: first[:name], count: no_spec_items.size }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
        end
      rescue => e
        @model.abort_operation rescue nil
        UI.messagebox(e.message)
      end
    }
    main_dialog_register_callback("action_accept_all") { |_|
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      accept_all_entities = (@current_report_items || []).select { |data| report_row_update?(data) }
                                                   .flat_map { |data| data[:stat_entities] || [] }
      model_before = respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(accept_all_entities) : []
      @model.start_operation("Accept All Updates", true)
      count = respond_to?(:mini_apply_all_status) ? mini_apply_all_status : 0
      @model.commit_operation
      record_restore_action("main_accept_all", "Bảng chính accept all", { count: count, model_before: model_before }, restore_before, current_restore_state) if count.to_i > 0 && restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
      puts "Accept All: #{count} dòng"
    }
    main_dialog_register_callback("delete_rule") { |_, rule_key|
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      @match_rules ||= {}
      if @match_rules.delete(rule_key)
        save_match_rules
        record_restore_action("delete_rule", "Xóa rule", { rule_key: rule_key }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
      end
    }
    main_dialog_register_callback("clear_all_rules") { |_|
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      @match_rules = {}; @general_rules = DEFAULT_GENERAL_RULES.dup
      save_match_rules
      record_restore_action("clear_all_rules", "Xóa toàn bộ rule", {}, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
    }
    main_dialog_register_callback("restore_action") { |_, entry_id|
      begin
        @active_dialog_tab = "tab-restore"
        restore_action(entry_id) if respond_to?(:restore_action)
        main_dialog_refresh_import_state(true, true, true, true)
      rescue => e
        UI.messagebox("Lỗi restore: #{e.message}")
      end
    }
    main_dialog_register_callback("clear_restore_log") { |_|
      begin
        @active_dialog_tab = "tab-restore"
        clear_restore_log if respond_to?(:clear_restore_log)
        update_html
      rescue => e
        UI.messagebox("Lỗi xóa restore log: #{e.message}")
      end
    }
    main_dialog_register_callback("add_ignore_keyword") { |_, keyword|
      keyword = keyword.to_s.strip
      unless keyword.empty?
        restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
        @general_rules ||= DEFAULT_GENERAL_RULES.dup
        @general_rules["ignore_keywords"] ||= []
        @general_rules["ignore_keywords"] << keyword unless @general_rules["ignore_keywords"].include?(keyword)
        save_match_rules
        record_restore_action("rules_add_ignore_keyword", "Thêm ignore keyword", { keyword: keyword }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
      end
    }
    main_dialog_register_callback("remove_ignore_keyword") { |_, keyword|
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      @general_rules ||= DEFAULT_GENERAL_RULES.dup
      (@general_rules["ignore_keywords"] || []).delete(keyword.to_s)
      save_match_rules
      record_restore_action("rules_remove_ignore_keyword", "Xóa ignore keyword", { keyword: keyword }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
    }
    main_dialog_register_callback("add_keep_numbers") { |_, pattern|
      pattern = pattern.to_s.strip
      unless pattern.empty?
        restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
        @general_rules ||= DEFAULT_GENERAL_RULES.dup
        @general_rules["keep_numbers_patterns"] ||= []
        @general_rules["keep_numbers_patterns"] << pattern unless @general_rules["keep_numbers_patterns"].include?(pattern)
        save_match_rules
        record_restore_action("rules_add_keep_numbers", "Thêm keep number rule", { pattern: pattern }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
      end
    }
    main_dialog_register_callback("remove_keep_numbers") { |_, pattern|
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      @general_rules ||= DEFAULT_GENERAL_RULES.dup
      (@general_rules["keep_numbers_patterns"] || []).delete(pattern.to_s)
      save_match_rules
      record_restore_action("rules_remove_keep_numbers", "Xóa keep number rule", { pattern: pattern }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
    }
    main_dialog_register_callback("open_rules_excel") { |_|
      export_rules_to_excel
      system("start \"\" \"#{RULES_EXCEL_FILE.tr('/','\\\\')}\""  )
    }
    main_dialog_register_callback("open_match_rules_excel") { |_|
      begin
        path = export_match_rules_to_excel if respond_to?(:export_match_rules_to_excel)
        path ||= EXCEL_MATCH_RULES_FILE if defined?(EXCEL_MATCH_RULES_FILE)
        if path && File.exist?(path)
          system("start \"\" \"#{path.tr('/', '\\\\')}\"")
        else
          UI.messagebox("Khong tao duoc file match_rules.xlsx") rescue nil
        end
      rescue => e
        UI.messagebox("Loi mo Match Rules Excel: #{e.message}") rescue nil
      end
    }
    main_dialog_register_callback("reload_match_rules_excel") { |_|
      begin
        load_match_rules_from_excel if respond_to?(:load_match_rules_from_excel)
        # Force re-match by invalidating caches
        @mini_pk_model_name_match_cache = nil
        invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)
        update_html(true) if @dlg && @dlg.visible?
        UI.messagebox("Da nap lai Match Rules tu Excel.") rescue nil
      rescue => e
        UI.messagebox("Loi nap lai Match Rules: #{e.message}") rescue nil
      end
    }
    main_dialog_register_callback("action_mat_accept") { |_, idx|
      begin
        data = @current_mat_items[idx.to_i]
        if data && respond_to?(:record_mini_accept)
          restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
          target_product = data[:actual_product].to_s.strip
          target_product_valid = begin
            product_code_valid?(target_product)
          rescue
            target_product =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
          end
          if target_product_valid
            selected_codes = respond_to?(:selected_product_codes) ? selected_product_codes(false) : []
            selected_products = selected_codes.map do |c|
              begin
                product_code_exact(c)
              rescue
                c.to_s.strip.upcase
              end
            end.select do |c|
              begin
                product_code_valid?(c)
              rescue
                c =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
              end
            end
                                             .uniq
            target_norm = begin
              product_code_exact(target_product)
            rescue
              target_product.upcase
            end
            unless selected_products.include?(target_norm)
              UI.messagebox("Vui lòng chọn đối tượng thuộc đúng #{target_product} trước khi Add vật liệu.")
              next
            end
          else
            UI.messagebox("Đối tượng đang chọn không thuộc mã sản phẩm hợp lệ. Không thể Add vật liệu.")
            next
          end

          @model.start_operation("Accept Material Status Rule", true)
          target = status_key(data[:trang_thai]) == "UPDATE" ? data[:new_name].to_s : ""
          target = data[:name].to_s if data[:is_missing] && target.empty?
          record_mini_accept(data[:actual_product], "VL", data[:is_missing] ? "" : data[:name], target, data[:thickness].to_s, "accept")
          save_history("Chấp nhận vật liệu","Mã SP: #{data[:actual_product]}, VL: #{data[:name]}")
          @model.commit_operation
          record_restore_action("main_material_accept", "Bảng chính accept vật liệu", { product: data[:actual_product], kind: "VL", name: data[:name], spec: data[:thickness] }, restore_before, current_restore_state) if restore_before && respond_to?(:record_restore_action)
          main_dialog_refresh_import_state(true, false, false)
        end
      rescue => e
        @model.abort_operation rescue nil
        UI.messagebox(e.message)
      end
    }
    main_dialog_register_callback("delete_row") { |_, idx|
      data = @current_report_items[idx.to_i]
      target_items =
        if data && data[:original_indices].is_a?(Array) && !data[:original_indices].empty?
          data[:original_indices].map { |oi| @current_report_items[oi.to_i] }.compact
        elsif data
          [data]
        else
          []
        end
      pairs = target_items.flat_map { |it| it[:stat_entities] || [] }
      pairs = (data[:stat_entities] || []) if pairs.empty? && data
      entities = pairs.map { |pair| pair.is_a?(Array) ? pair[0] : pair }.compact.uniq
      entities.reject! { |e| e.respond_to?(:deleted?) && e.deleted? }
      if data && !entities.empty?
        @model.start_operation("Xóa Phụ Kiện", true)
        by_parent = Hash.new { |h, k| h[k] = [] }
        entities.each do |ent|
          parent = ent.respond_to?(:parent) ? ent.parent : nil
          next unless parent.respond_to?(:erase_entities)
          by_parent[parent] << ent
        end
        by_parent.each do |parent, ents|
          live = ents.reject { |e| e.deleted? }
          parent.erase_entities(live) unless live.empty?
        end
        record_hidden_import_excel_item(data[:actual_product], "PK", data[:name], "") if respond_to?(:record_hidden_import_excel_item)
        save_history("Xóa Phụ Kiện","Mã SP: #{data[:actual_product]}, PK: #{data[:name]}")
        @model.commit_operation
          main_dialog_refresh_import_state(true, false, false)
      elsif data && data[:is_missing]
        if respond_to?(:remove_import_excel_item)
          remove_import_excel_item(data[:actual_product], "PK", data[:name], "")
        elsif @imported_excel_data
          @imported_excel_data.reject! { |ex| ex[:ma_sp] == data[:actual_product] && ex[:hw_name] == data[:name] }
        end
        save_history("Bỏ qua phụ kiện","Mã SP: #{data[:actual_product]}, PK: #{data[:name]}")
          main_dialog_refresh_import_state(true, false, false)
      end
    }
    main_dialog_register_callback("update_ghi_chu") { |_, idx, val|
      data = @current_report_items[idx.to_i] rescue nil
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      model_before = data && respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(data[:stat_entities] || []) : []
      with_fast_attribute_edit("Đổi ghi chú") do
        if data && !data[:is_missing]
          data[:ghi_chu] = val.to_s; time_str = Time.now.strftime("%d/%m/%y %H:%M")
          (data[:stat_entities] || []).each do |pair|
            ent = pair.is_a?(Array) ? pair[0] : pair
            unless ent.deleted?
              ent.set_attribute("MH_Thongke","ghi_chu", val.to_s)
              ent.set_attribute("MH_Thongke","last_modified", time_str)
            end
          end
          save_history("Đổi ghi chú","Mã SP: #{data[:actual_product]}, PK: #{data[:name]}, GC: #{val}")
        elsif data && data[:is_missing] && respond_to?(:update_import_excel_note)
          update_import_excel_note(data[:actual_product], "PK", data[:name], "", val.to_s)
          data[:ghi_chu] = val.to_s
          save_history("Đổi ghi chú Excel","Mã SP: #{data[:actual_product]}, PK: #{data[:name]}, GC: #{val}")
        end
      end
      record_restore_action("main_update_ghi_chu", "Đổi ghi chú", { product: data[:actual_product], kind: "PK", name: data[:name], value: val, model_before: model_before }, restore_before, current_restore_state) if data && !data[:is_missing] && restore_before && respond_to?(:record_restore_action)
      refresh_project_total_table
    }
    main_dialog_register_callback("update_ten_sp") { |_, idx, val|
      data = @current_report_items[idx.to_i] rescue nil
      restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
      model_before = data && respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(data[:stat_entities] || []) : []
      with_fast_attribute_edit("Đổi Tên SP") do
        if data && !data[:is_missing]
          data[:ten_sp] = val.to_s; time_str = Time.now.strftime("%d/%m/%y %H:%M")
          (data[:stat_entities] || []).each do |pair|
            ent = pair.is_a?(Array) ? pair[0] : pair
            unless ent.deleted?
              ent.set_attribute("MH_Thongke","ten_sp", val.to_s)
              ent.set_attribute("MH_Thongke","last_modified", time_str)
            end
          end
          save_history("Đổi Tên SP","Mã SP: #{data[:actual_product]}, Tên SP: #{val}")
        end
      end
      record_restore_action("main_update_ten_sp", "Đổi tên SP", { product: data[:actual_product], kind: "PK", name: data[:name], value: val, model_before: model_before }, restore_before, current_restore_state) if data && !data[:is_missing] && restore_before && respond_to?(:record_restore_action)
      refresh_project_total_table
    }

    main_dialog_register_callback("bulk_update_cells") { |_, payload|
      begin
        changes = JSON.parse(payload.to_s) rescue []
        changes = [] unless changes.is_a?(Array)
        changes = changes.select { |ch| ch.is_a?(Hash) }
        next if changes.empty?

        restore_before = respond_to?(:current_restore_state) ? current_restore_state : nil
        snapshot_pairs = []
        tag_only_change = changes.all? { |ch| ch["field"].to_s == "tag" }
        changes.each do |ch|
          field = ch["field"].to_s
          next unless ["name", "ten_sp", "ghi_chu", "ngay_dat", "tag"].include?(field)
          table = ch["table"].to_s
          idx = ch["idx"].to_i
          data = table == "mat" ? (@current_mat_items || [])[idx] : (@current_report_items || [])[idx]
          snapshot_pairs.concat(data[:stat_entities] || []) if data
        end
        model_before = respond_to?(:restore_entity_snapshot) ? restore_entity_snapshot(snapshot_pairs) : []
        changed = 0
        with_fast_attribute_edit("Cập nhật nhiều ô") do
          time_str = Time.now.strftime("%d/%m/%y %H:%M")

          changes.each do |ch|
            table = ch["table"].to_s
            field = ch["field"].to_s
            idx = ch["idx"].to_i
            val = ch["value"].to_s
            data = table == "mat" ? (@current_mat_items || [])[idx] : (@current_report_items || [])[idx]
            next unless data
            next if data[:is_missing] && !["ngay_dat", "ghi_chu"].include?(field)

            pairs = data[:stat_entities] || []
            case field
            when "name"
              next if table == "mat" || val.strip.empty?
              pairs.each do |pair|
                ent = pair.is_a?(Array) ? pair[0] : pair
                next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
                next if ent.deleted?
                if respond_to?(:apply_import_entity_name)
                  apply_import_entity_name(ent, val, data[:dict], data[:key])
                else
                  ent.set_attribute(data[:dict], data[:key], val)
                  ent.definition.set_attribute(data[:dict], data[:key], val) if ent.respond_to?(:definition)
                end
                ent.set_attribute("MH_Thongke", "last_modified", time_str)
              end
              data[:name] = val
            when "ten_sp"
              next if table == "mat"
              pairs.each do |pair|
                ent = pair.is_a?(Array) ? pair[0] : pair
                next if ent.deleted?
                ent.set_attribute("MH_Thongke", "ten_sp", val)
                ent.set_attribute("MH_Thongke", "last_modified", time_str)
              end
              data[:ten_sp] = val
            when "ghi_chu"
              next if table == "mat"
              if data[:is_missing]
                update_import_excel_note(data[:actual_product], "PK", data[:name], "", val) if respond_to?(:update_import_excel_note)
                data[:ghi_chu] = val
              else
                pairs.each do |pair|
                  ent = pair.is_a?(Array) ? pair[0] : pair
                  next if ent.deleted?
                  ent.set_attribute("MH_Thongke", "ghi_chu", val)
                  ent.set_attribute("MH_Thongke", "last_modified", time_str)
                end
                data[:ghi_chu] = val
              end
            when "tag"
              next if val.strip.empty?
              layer = @model.layers[val] || @model.layers.add(val)
              pairs.each do |pair|
                ent = pair.is_a?(Array) ? pair[0] : pair
                next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
                next if ent.deleted?
                ent.layer = layer
              end
              data[:layer] = val
            when "ngay_dat"
              attr_name = table == "mat" ? "mat_ngay_dat" : "ngay_dat"
              val = normalize_order_date(val)
              save_order_date_override(table == "mat" ? "mat" : "acc", data, val) if respond_to?(:save_order_date_override)
              pairs.each do |pair|
                ent = pair.is_a?(Array) ? pair[0] : pair
                next if ent.deleted?
                ent.set_attribute("MH_Thongke", attr_name, val)
              end
              data[:ngay_dat] = val
            else
              next
            end
            changed += 1
          end

          save_history("Cập nhật nhiều ô", "#{changed} ô")
        end
        record_restore_action("bulk_update_cells", "Cập nhật nhiều ô", { count: changed, model_before: model_before }, restore_before, current_restore_state) if changed.to_i > 0 && restore_before && respond_to?(:record_restore_action)
        refresh_project_total_table unless tag_only_change
      rescue => e
        attach_observers
        UI.messagebox("Lỗi cập nhật nhiều ô: #{e.message}")
      end
    }

    # ==================== SNAPSHOT / FILE QUẢN LÝ ====================
    main_dialog_register_callback("export_project_report") { |_|
      path = UI.savepanel("Xuất báo cáo CNC / DMVT", "", "BaoCao_CNC_DMVT.xlsx")
      next if path.to_s.strip.empty?
      begin
        count = export_project_report_xlsx(path)
        UI.messagebox("Đã xuất báo cáo CNC / DMVT: #{count} dòng\n#{path}")
      rescue LoadError
        UI.messagebox("Hệ điều hành không hỗ trợ Win32OLE.")
      rescue => e
        UI.messagebox("Lỗi xuất báo cáo: #{e.message}")
      end
    }
    main_dialog_register_callback("snapshot_current") { |_|
      if @snapshot_current_running
        @snapshot_current_last_status = "Đang update file hiện tại, bỏ qua lần bấm lặp."
        puts "snapshot_current skipped: update already running"
        next
      end

      begin
        @snapshot_current_running = true
        @snapshot_current_last_status = "Đang update file hiện tại..."
        @active_dialog_tab = "tab-files"
        unless @model
          UI.messagebox("Không tìm thấy model hiện tại.")
          next
        end
        skp_path = @model.path
        if skp_path.to_s.empty?
          UI.messagebox("File hiện tại chưa được lưu. Hãy lưu file SKP trước khi Update.")
          next
        end
        respond_to?(:process_selection_cached) ? process_selection_cached(true) : process_selection
        skp_name = skp_path.empty? ? "Unsaved_#{Time.now.to_i}" : File.basename(skp_path)
        existing = find_snapshot_by_path(skp_path)
        project_default = existing ? snapshot_project(existing) : project_name_for_path(skp_path)
        label_default = existing ? existing["label"].to_s : default_cut_label(project_default)
        snap = export_snapshot(skp_path, skp_name, label_default, project_default)
        @snapshot_current_last_status = "Đã update: #{snap['project']} / #{snap['label']} | #{snap['json_path']}"
        UI.start_timer(0.05, false) do
          begin
            @active_dialog_tab = "tab-files"
            update_html(false) if @dlg && @dlg.visible?
          rescue => timer_error
            puts "snapshot_current deferred update_html error: #{timer_error.class}: #{timer_error.message}"
          end
        end
      rescue => e
        @snapshot_current_last_status = "Lỗi Update file hiện tại: #{e.message}"
        UI.messagebox("Lỗi Update file hiện tại: #{e.message}")
        puts "snapshot_current error: #{e.class}: #{e.message}"
        puts e.backtrace.join("\n")
      ensure
        @snapshot_current_running = false
      end
    }
    main_dialog_register_callback("delete_snapshot") { |_, snap_id, json_path, skp_path|
      removed = delete_snapshot(snap_id, json_path, skp_path)
      UI.messagebox("Không tìm thấy snapshot để xoá.") if removed.to_i == 0
      update_html(true)
    }
    main_dialog_register_callback("open_skp_file") { |_, skp_path|
      skp_path = skp_path.to_s
      if File.exist?(skp_path)
        system("explorer.exe", "/select,#{skp_path.tr('/', '\\')}")
      elsif File.directory?(File.dirname(skp_path))
        system("explorer.exe", File.dirname(skp_path).tr('/', '\\'))
        UI.messagebox("Không tìm thấy file, đã mở thư mục chứa:\n#{skp_path}")
      else
        UI.messagebox("Không tìm thấy file:\n#{skp_path}")
      end
    }
    main_dialog_register_callback("add_file_manual") { |_|
      path = UI.openpanel("Chọn file SketchUp", "", "*.skp")
      if path && File.exist?(path)
        load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
        skp_name = File.basename(path)
        selected_project = project_name_for_path(path)
        active_project = current_project_name
        existing = find_snapshot_by_path(path)
        project_default = active_project.to_s.empty? || active_project == DEFAULT_PROJECT_NAME ? selected_project : active_project
        project_default = snapshot_project(existing) if existing
        auto_label = respond_to?(:snapshot_cut_label_from_file) ? snapshot_cut_label_from_file(path) : ""
        label_default = if existing
          existing["label"].to_s
        elsif !auto_label.to_s.empty?
          auto_label
        else
          default_cut_label(project_default)
        end
        values = UI.inputbox(["Dự án:", "Nhãn:"], [project_default, label_default], "Thêm file") rescue nil
        next unless values
        project = values[0].to_s.strip.empty? ? project_default : values[0].to_s.strip
        label = values[1].to_s.strip.empty? ? label_default : values[1].to_s.strip
        file_role = respond_to?(:skp_file_role) ? skp_file_role(path) : ""
        entry = {
          "id"          => existing ? existing["id"] : "#{Time.now.to_i}_#{rand(9999)}",
          "project"     => project,
          "label"       => label,
          "skp_path"    => path,
          "skp_name"    => skp_name,
          "file_role"   => file_role,
          "file_created_at" => (File.exist?(path) ? File.ctime(path).strftime("%Y-%m-%d %H:%M:%S") : ""),
          "exported_at" => existing ? existing["exported_at"].to_s : Time.now.strftime("%Y-%m-%d %H:%M:%S"),
          "json_path"   => existing ? existing["json_path"].to_s : "",
          "items"       => existing ? (existing["items"] || []) : [],
          "mat_items"   => existing ? (existing["mat_items"] || []) : []
        }
        ensure_snapshot_json_path!(entry) if respond_to?(:ensure_snapshot_json_path!)
        write_snapshot_json_file(entry) if respond_to?(:write_snapshot_json_file)
        existing ? existing.merge!(entry) : @file_snapshots << entry
        save_snapshots; update_html(true)
      end
    }
    main_dialog_register_callback("update_snapshot_json_path") { |_, snap_id, json_path|
      load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
      snap = @file_snapshots.find { |f| f["id"].to_s == snap_id.to_s }
      if snap
        snap["json_path"] = json_path.to_s.strip
        respond_to?(:save_snapshot_index_only) ? save_snapshot_index_only : save_snapshots
        update_html(true)
      end
    }
    main_dialog_register_callback("refresh_snapshot_json") { |_, snap_id, json_path|
      begin
        snap = refresh_snapshot_from_json_path!(snap_id, json_path)
        respond_to?(:save_snapshot_index_only) ? save_snapshot_index_only : save_snapshots
        update_html(true)
        UI.messagebox("Đã refresh dữ liệu từ JSON:\n#{snap['json_path']}")
      rescue => e
        UI.messagebox("Lỗi refresh JSON: #{e.message}")
        puts "refresh_snapshot_json error: #{e.class}: #{e.message}"
      end
    }
    main_dialog_register_callback("rename_snapshot") { |_, snap_id, new_label|
      snap = @file_snapshots.find { |f| f["id"] == snap_id }
      if snap && !new_label.to_s.strip.empty?
        snap["label"] = new_label.to_s.strip
        save_snapshots; update_html(true)
      end
    }

    register_mini_import_callbacks_on_main_dialog

    @dlg.set_html(<<~HTML)
      <!doctype html>
      <html><head><meta charset="utf-8">
      <style>
        body{margin:0;background:#181b20;color:#d8dee9;font-family:Arial,sans-serif;height:100vh;display:flex;align-items:center;justify-content:center}
        .box{border:1px solid #3a3f44;background:#222529;padding:18px 22px;border-radius:4px;font-size:13px}
        b{color:#27ae60}
      </style></head>
      <body><div class="box"><b>MH Thống kê</b><br>Đang tải dữ liệu JSON...</div></body></html>
    HTML
    @dlg.show
    UI.start_timer(0.05, false) do
      begin
        update_html(true) if @dlg && @dlg.visible?
      rescue => e
        puts "show_dialog deferred update_html error: #{e.class}: #{e.message}"
      end
    end
    attach_observers
  end

  def self.register_mini_import_callbacks_on_main_dialog
    return unless @dlg

    main_dialog_register_callback("select_item") { |_, product_code, hw_name, ids|
      begin
        @dialog_selecting = true
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        entries = respond_to?(:mini_stat_entries_for_ids) ? mini_stat_entries_for_ids(ids) : []
        entries = mini_stat_entries_for_name(product, hw_name) if entries.empty? && !hw_name.to_s.empty? && respond_to?(:mini_stat_entries_for_name)
        if entries && !entries.empty?
          sel_ents = entries.map { |p| p.is_a?(Array) ? (p[1] || p[0]) : p }.compact.uniq.reject { |e| e.respond_to?(:deleted?) && e.deleted? }
          @model.selection.clear
          @model.selection.add(sel_ents) unless sel_ents.empty?
          @model.select_tool(HighlightTool.new(entries))
        end
      rescue => e
        puts "select_item error: #{e.message}" rescue nil
      ensure
        UI.start_timer(0.5, false) { @dialog_selecting = false } rescue nil
      end
    }
    main_dialog_register_callback("accept_item") { |_, product_code, kind, old_name, new_name, spec|
      begin
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        @model.start_operation("Accept Status", true)
        record_mini_accept(product, kind, old_name, new_name, spec, "accept")
        @model.commit_operation
        respond_to?(:mark_mini_session_operation) ? mark_mini_session_operation : nil
        refresh_main_dialog_mini_tables
      rescue => e
        puts "accept_item error: #{e.message}" rescue nil
      end
    }
    main_dialog_register_callback("manual_match_item") { |_, product_code, kind, model_name|
      begin
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        kind = kind.to_s.empty? ? "PK" : kind.to_s
        model_name = model_name.to_s.strip
        excel_row = respond_to?(:mini_import_choose_manual_match) ? mini_import_choose_manual_match(product, kind, model_name) : nil
        next unless excel_row

        hw_name = excel_row[:hw_name].to_s.strip
        spec = excel_row[:spec].to_s.strip
        section = excel_row[:section].to_s.strip
        target_name = respond_to?(:import_display_name) ? import_display_name(hw_name, spec) : [hw_name, spec].reject(&:empty?).join(" ")
        entities = respond_to?(:mini_entities_for_name) ? mini_entities_for_name(product, model_name) : []
        @model.start_operation("Manual Match PK", true)
        record_mini_accept(product, kind, model_name, target_name, spec, "manual_match")
        Array(entities).each do |ent|
          next unless ent && !(ent.respond_to?(:deleted?) && ent.deleted?)
          record_entity_excel_match(ent, {
            product: product,
            kind: kind,
            old_name: model_name,
            target_name: target_name,
            excel_name: hw_name,
            spec: spec,
            section: section,
            source: "manual_match",
            action: "manual_match"
          }) if respond_to?(:record_entity_excel_match)
        end
        @model.commit_operation
        refresh_mini_runtime_after_model_change(product) if respond_to?(:refresh_mini_runtime_after_model_change)
        respond_to?(:mark_mini_session_operation) ? mark_mini_session_operation : nil
        respond_to?(:finish_mini_change) ? finish_mini_change : refresh_main_dialog_mini_tables
      rescue => e
        @model.abort_operation rescue nil
        puts "manual_match_item error: #{e.message}" rescue nil
      end
    }
    main_dialog_register_callback("update_item") { |_, product_code, old_name, new_name, spec|
      begin
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        entities = if respond_to?(:mini_entities_for_name)
          mini_entities_for_name(product, old_name)
        else
          []
        end
        target_name = new_name.to_s.strip
        target_name = pk_preserve_dimension_for_update(old_name, target_name, spec) if respond_to?(:pk_preserve_dimension_for_update)
        @model.start_operation("Update PK", true)
        # Snapshot/import rows may not have live entities in the current model.
        # In that case still record the accept rule so status can move forward.
        if entities && !entities.empty? && respond_to?(:mini_import_apply_name_to_entities)
          mini_import_apply_name_to_entities(entities, target_name, {
            product: product,
            kind: "PK",
            old_name: old_name,
            target_name: target_name,
            excel_name: target_name,
            spec: spec,
            source: "main_dialog",
            action: "update"
          })
        end
        record_mini_accept(product, "PK", old_name, target_name, spec, "update")
        @model.commit_operation
        refresh_mini_runtime_after_model_change(product) if respond_to?(:refresh_mini_runtime_after_model_change)
        respond_to?(:mark_mini_session_operation) ? mark_mini_session_operation : nil
        respond_to?(:finish_mini_change) ? finish_mini_change : refresh_main_dialog_mini_tables
      rescue => e
        @model.abort_operation rescue nil
        puts "update_item error: #{e.message}" rescue nil
      end
    }
    main_dialog_register_callback("keep_item") { |_, product_code, kind, old_name, new_name, spec|
      begin
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        @model.start_operation("Keep Name", true)
        record_mini_accept(product, kind, old_name, new_name, spec, "keep")
        @model.commit_operation
        respond_to?(:mark_mini_session_operation) ? mark_mini_session_operation : nil
        respond_to?(:finish_mini_change) ? finish_mini_change : refresh_main_dialog_mini_tables
      rescue => e
        @model.abort_operation rescue nil
        puts "keep_item error: #{e.message}" rescue nil
      end
    }
    main_dialog_register_callback("delete_item") { |_, product_code, hw_name, ids|
      begin
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        entities = respond_to?(:entities_by_ids) ? entities_by_ids(ids) : []
        entities = mini_entities_for_name(product, hw_name) if entities.empty? && respond_to?(:mini_entities_for_name)
        @model.start_operation("Delete PK", true)
        erase_mini_entities(entities) if respond_to?(:erase_mini_entities)
        record_hidden_import_excel_item(product, "PK", hw_name, "") if respond_to?(:record_hidden_import_excel_item)
        @model.commit_operation
        respond_to?(:mark_mini_session_operation) ? mark_mini_session_operation : nil
        respond_to?(:finish_mini_change) ? finish_mini_change : refresh_main_dialog_mini_tables
      rescue => e
        puts "delete_item error: #{e.message}" rescue nil
      end
    }
    main_dialog_register_callback("remove_excel_item") { |_, product_code, kind, hw_name, spec|
      begin
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        remove_import_excel_item(product, kind, hw_name, spec) if respond_to?(:remove_import_excel_item)
        respond_to?(:finish_mini_change) ? finish_mini_change : refresh_main_dialog_mini_tables
      rescue => e
        puts "remove_excel_item error: #{e.message}" rescue nil
      end
    }
    main_dialog_register_callback("rename_item") { |_, product_code, old_name, new_name, target_name, spec, kind|
      begin
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        kind = kind.to_s.empty? ? "PK" : kind.to_s
        entities = respond_to?(:mini_import_resolve_entities_for_name) ? mini_import_resolve_entities_for_name(product, old_name) : []
        @model.start_operation("Rename PK", true)
        mini_import_apply_name_to_entities(entities, new_name, {
          product: product,
          kind: kind,
          old_name: old_name,
          target_name: target_name,
          excel_name: target_name.to_s.strip.empty? ? new_name : target_name,
          spec: spec,
          source: "main_dialog",
          action: "rename"
        }) if respond_to?(:mini_import_apply_name_to_entities)
        record_mini_name_lineage(product, kind, old_name, new_name, spec, "rename", "manual_rename") if respond_to?(:record_mini_name_lineage)
        record_mini_accept(product, kind, new_name, target_name, spec, "rename_update") unless target_name.to_s.strip.empty?
        @model.commit_operation
        refresh_mini_runtime_after_model_change(product) if respond_to?(:refresh_mini_runtime_after_model_change)
        respond_to?(:mark_mini_session_operation) ? mark_mini_session_operation : nil
        respond_to?(:finish_mini_change) ? finish_mini_change : refresh_main_dialog_mini_tables
      rescue => e
        puts "rename_item error: #{e.message}" rescue nil
      end
    }
    main_dialog_register_callback("set_note") { |_, product_code, kind, hw_name, spec, note|
      begin
        product = respond_to?(:mini_action_product) ? mini_action_product(product_code) : product_code
        update_import_excel_note(product, kind, hw_name, spec, note) if respond_to?(:update_import_excel_note)
      rescue => e
        puts "set_note error: #{e.message}" rescue nil
      end
    }
  rescue => e
    puts "register_mini_import_callbacks_on_main_dialog error: #{e.message}" rescue nil
  end

  # === Active data source switcher ===
  # Allow user to switch between MODEL JSON (the SketchUp file currently open)
  # and imported snapshots ("Cắt lần 1", "Cắt lần 2" …). When a non-MODEL
  # source is active, @current_report_items / @current_mat_items get replaced
  # with the source's items so the entire mini-import pipeline (matching,
  # status, display) works on the imported data as if it were the live model.

  def self.active_data_source_id
    # Da bo dropdown source toan cuc: luon dung MODEL lam nen de tranh stale state.
    "MODEL"
  rescue
    "MODEL"
  end

  def self.set_active_data_source(source_id)
    sid = source_id.to_s.strip
    sid = "MODEL" if sid.empty?
    if session.respond_to?(:active_data_source_id=)
      session.active_data_source_id = sid
    else
      @active_data_source_id = sid
    end
    apply_active_data_source!
    invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)
    @last_main_html_hash = nil
    update_html(true) if @dlg && @dlg.visible?
    refresh_import_mini_dialog(true, false) if respond_to?(:refresh_import_mini_dialog) && respond_to?(:mini_import_dialog_visible?) && mini_import_dialog_visible?
    refresh_import_material_hud(true, false) if respond_to?(:refresh_import_material_hud) && respond_to?(:material_hud_visible?) && material_hud_visible?
    true
  rescue => e
    puts "set_active_data_source error: #{e.message}"
    false
  end

  # Swap @current_report_items / @current_mat_items based on active source.
  # Idempotent — call before any render path.
  def self.apply_active_data_source!
    sid = active_data_source_id
    @data_source_model_backup ||= nil

    if sid == "MODEL"
      if @data_source_model_backup
        @current_report_items = @data_source_model_backup[:report]
        @current_mat_items    = @data_source_model_backup[:mat]
        session.current_report_items = @current_report_items
        session.current_mat_items    = @current_mat_items
        @data_source_model_backup = nil
      end
      return
    end

    source = active_data_source_lookup(sid)
    return unless source

    @data_source_model_backup ||= {
      report: @current_report_items,
      mat:    @current_mat_items
    }

    @current_report_items = normalize_imported_source_items(source[:items], "PK")
    @current_mat_items    = normalize_imported_source_items(source[:mat_items] || source[:materials] || [], "VL")
    session.current_report_items = @current_report_items
    session.current_mat_items    = @current_mat_items
  rescue => e
    puts "apply_active_data_source! error: #{e.message}"
  end

  def self.active_data_source_lookup(sid)
    return nil if sid.to_s.empty? || sid == "MODEL"

    sources = respond_to?(:pk_report_cut_sources) ? pk_report_cut_sources : []
    sources.find { |s| s[:id].to_s == sid }
  rescue
    nil
  end

  # Convert imported JSON items (string keys, no entities) to the in-memory
  # row format used by @current_report_items / @current_mat_items.
  def self.normalize_imported_source_items(raw_items, kind = "PK")
    Array(raw_items).map do |it|
      next nil unless it.is_a?(Hash)
      h = {}
      it.each { |k, v| h[k.to_s.to_sym] = v }
      h[:type]            = (h[:type] || (kind == "VL" ? :material : :count)).to_s.to_sym
      h[:name]            = h[:name].to_s
      h[:actual_product]  = (h[:actual_product] || h[:product]).to_s
      h[:product]         = (h[:product] || h[:actual_product]).to_s
      h[:ten_sp]          = h[:ten_sp].to_s
      h[:trang_thai]      = h[:trang_thai].to_s
      h[:ghi_chu]         = h[:ghi_chu].to_s
      h[:layer]           = h[:layer].to_s
      h[:count]           = h[:count].to_i
      h[:length]          = h[:length].to_f
      h[:unit]            = h[:unit].to_s
      h[:stat_entities] ||= []
      h[:entities]      ||= []
      h
    end.compact
  end

  def self.refresh_main_dialog_mini_tables
    return unless @dlg && @dlg.visible?

    invalidate_mini_import_caches(model: true, excel: false) if respond_to?(:invalidate_mini_import_caches)

    UI.start_timer(0.1, false) do
      next unless @dlg && @dlg.visible?
      begin
        all_html = respond_to?(:build_tab_all_bom_rows) ? build_tab_all_bom_rows : ""
        acc_html = respond_to?(:build_tab_acc_bom_rows) ? build_tab_acc_bom_rows : ""
        mat_html = respond_to?(:build_tab_mat_bom_rows) ? build_tab_mat_bom_rows : ""
        main_dialog_execute_script("var e=document.getElementById('table-all-body');if(e)e.innerHTML=#{js_arg(all_html)};")
        main_dialog_execute_script("var e=document.getElementById('table-acc-body');if(e)e.innerHTML=#{js_arg(acc_html)};")
        main_dialog_execute_script("var e=document.getElementById('table-mat-body');if(e)e.innerHTML=#{js_arg(mat_html)};")
      rescue => e
        puts "refresh_main_dialog_mini_tables error: #{e.message}" rescue nil
      end
    end
  end

end
