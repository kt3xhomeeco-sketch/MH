# encoding: utf-8
# MH_Thongke - Shared Excel import loading and cache state.

module MH_Thongke
  EXCEL_ASYNC_TIMEOUT_SECONDS = 30.0 unless const_defined?(:EXCEL_ASYNC_TIMEOUT_SECONDS)
  IMPORT_EXCEL_CACHE_VERSION = 1 unless const_defined?(:IMPORT_EXCEL_CACHE_VERSION)

  def self.clear_excel_loading_state
    stop_excel_loading_poll_timer if respond_to?(:stop_excel_loading_poll_timer)
    reset_import_excel_loading_flags
    @excel_async_results = {}
    @excel_async_callbacks = {}
  rescue
    @excel_loading = false
  end

  def self.stop_excel_loading_poll_timer
    if @excel_loading_poll_timer
      UI.stop_timer(@excel_loading_poll_timer) rescue nil
      @excel_loading_poll_timer = nil
    end
  rescue
    @excel_loading_poll_timer = nil
  end

  def self.reset_import_excel_loading_flags
    @excel_loading = false
    @excel_loading_sig = nil
    @excel_loading_path = nil
    @excel_loading_mtime = nil
    @excel_loading_started_at = nil
  rescue
    @excel_loading = false
  end

  def self.clear_excel_product_name_caches!
    @excel_rows_sig_key = nil
    @excel_rows_sig = nil
    @excel_product_names_cache = {}
    @excel_product_names_cache_sig = nil
    @excel_product_name_index = nil
    @excel_product_name_index_sig = nil
    true
  rescue
    true
  end

  def self.bump_excel_data_version!(reason = nil)
    @excel_data_version = @excel_data_version.to_i + 1
    @excel_data_version = 1 if @excel_data_version <= 0
    @excel_data_object_id = @imported_excel_data.object_id
    @excel_rows_sig_key = @excel_data_object_id
    @excel_rows_sig = @excel_data_version
    @excel_data_version
  rescue
    @excel_data_version = Time.now.to_f
  end

  def self.set_imported_excel_data(rows, reason = "set_imported_excel_data", normalize: false, sync_session: true, clear_caches: true)
    @imported_excel_data = normalize ? normalize_import_excel_rows(rows || []) : Array(rows || [])
    bump_excel_data_version!(reason)
    clear_excel_product_name_caches! if clear_caches
    if sync_session && respond_to?(:session)
      begin
        session.imported_excel_data = @imported_excel_data
      rescue
      end
    end
    @imported_excel_data
  end

  def self.excel_loading_timed_out?
    @excel_loading && @excel_loading_started_at.to_f > 0 &&
      (Time.now.to_f - @excel_loading_started_at.to_f) > EXCEL_ASYNC_TIMEOUT_SECONDS.to_f
  rescue
    false
  end

  def self.clear_import_excel_loaded_state
    set_imported_excel_data([], "clear_import_excel_loaded_state", sync_session: true)
    @import_excel_loaded_path = nil
    @import_excel_loaded_mtime = nil
    @import_excel_cache_key = nil
    @import_excel_cache_stale = false
    @import_excel_source = nil
    invalidate_mini_import_caches(excel: true) if respond_to?(:invalidate_mini_import_caches)
    true
  rescue
    false
  end

  def self.set_import_excel_loaded_state(rows, path, path_mtime, source, cache_key = nil, stale = false)
    set_imported_excel_data(rows || [], "set_import_excel_loaded_state:#{source}", normalize: true, sync_session: false)
    @import_excel_loaded_path = path.to_s
    @import_excel_loaded_mtime = path_mtime.to_f
    @import_excel_last_error_at = nil
    @import_excel_cache_key = cache_key if cache_key
    @import_excel_cache_stale = !!stale
    @import_excel_source = source.to_s
    # Sync to session so pipeline.stage_excel_match and other consumers see it
    if respond_to?(:session)
      begin
        session.imported_excel_data = @imported_excel_data
      rescue
      end
    end
    if respond_to?(:invalidate_mini_import_caches)
      invalidate_mini_import_caches(excel: true)
    else
      @mini_excel_items_cache = nil
    end
    @imported_excel_data
  end

  def self.import_excel_cache_file
    defined?(IMPORT_EXCEL_CACHE_FILE) ? IMPORT_EXCEL_CACHE_FILE : File.join(DATA_DIR, "import_excel_cache.json")
  end

  def self.import_excel_normalized_path(path)
    File.expand_path(path.to_s).tr("\\", "/").downcase
  rescue
    path.to_s.tr("\\", "/").downcase
  end

  def self.import_excel_cache_key(path, project = nil)
    project = fix_vietnamese_mojibake(project || import_excel_project_key).to_s.strip
    [project, import_excel_normalized_path(path)].join("|")
  end

  def self.import_excel_deep_fix(value)
    case value
    when String
      fix_vietnamese_mojibake(value)
    when Array
      value.map { |item| import_excel_deep_fix(item) }
    when Hash
      value.each_with_object({}) { |(key, val), out| out[key.to_s] = import_excel_deep_fix(val) }
    else
      value
    end
  end

  def self.normalize_import_excel_row(row)
    source = row.is_a?(Hash) ? row : {}
    data = {}
    source.each do |key, value|
      data[key.to_s.to_sym] = import_excel_deep_fix(value)
    end

    data[:ma_sp] = fix_vietnamese_mojibake(data[:ma_sp]).to_s.strip.upcase
    data[:ten_sp] = fix_vietnamese_mojibake(data[:ten_sp]).to_s.strip
    data[:hw_name] = sanitize_legacy_duplicate_finish_code(fix_vietnamese_mojibake(data[:hw_name]).to_s.strip)
    data[:spec] = fix_vietnamese_mojibake(data[:spec]).to_s.strip
    data[:ghi_chu] = fix_vietnamese_mojibake(data[:ghi_chu]).to_s.strip
    data[:excel_col6] = fix_vietnamese_mojibake(data[:excel_col6]).to_s.strip
    data[:display_sub_parts] = Array(data[:display_sub_parts]).map do |part|
      sanitize_legacy_duplicate_finish_code(fix_vietnamese_mojibake(part).to_s.strip)
    end.reject(&:empty?)
    data[:kind] = data[:kind].to_s.strip.empty? ? "PK" : data[:kind].to_s.strip.upcase
    data[:ma_vl] = sanitize_legacy_duplicate_finish_code(fix_vietnamese_mojibake(data[:ma_vl]).to_s.strip) if data.key?(:ma_vl)
    data[:ma_vl_source] = sanitize_legacy_duplicate_finish_code(fix_vietnamese_mojibake(data[:ma_vl_source]).to_s.strip) if data.key?(:ma_vl_source)
    # Mã vật liệu phải giữ nguyên đúng giá trị đã có trong Excel/JSON.
    # Không suy diễn mã phủ từ spec/ghi chú vì sẽ làm thay đổi mã nguồn và,
    # khi normalize cache nhiều lần, từng gây lặp MS.MS... trong HUD.
    data
  rescue
    {}
  end

  # Dọn dữ liệu cache đã bị logic enrich cũ nối lặp nhiều lần:
  # HDFCA.AC.MS.256SH.MS.MS.MS256SH -> HDFCA.AC.MS.256SH
  # PICOMAT.MS.MS.MS502MM           -> PICOMAT
  # Không đụng mã hợp lệ HDFCA.AC.MS.MS256SH vì mã đó không có ".MS.MS.".
  def self.sanitize_legacy_duplicate_finish_code(value)
    text = value.to_s.strip
    marker = text.upcase.index(".MS.MS.")
    marker ? text[0...marker].sub(/[.\-]+\z/, "") : text
  rescue
    value.to_s.strip
  end

  def self.import_excel_material_dedupe_key(row)
    product = row[:ma_sp].to_s.strip.upcase
    code = row[:ma_vl_source].to_s.strip
    code = row[:ma_vl].to_s.strip if code.empty?
    code = row[:hw_name].to_s.strip if code.empty?
    norm_code =
      if respond_to?(:material_code_norm)
        material_code_norm(code)
      else
        parts = code.to_s.strip.upcase.gsub(/\s+/, "").split(".")
        parts.delete_at(1) if parts.size > 1 && parts[1].to_s =~ /\A\d+(?:\.\d+)?\z/
        parts.reject! { |part| part == "VER" && parts.any? { |other| other != "VER" && other.start_with?("VER") } }
        parts.join(".")
      end
    detail_key = Array(row[:display_sub_parts]).map(&:to_s).reject(&:empty?).join("|")
    detail_key = [row[:hw_name], row[:excel_col6], row[:spec]].map(&:to_s).reject(&:empty?).join("|") if detail_key.empty?
    detail_norm = respond_to?(:import_name_norm) ? import_name_norm(detail_key) : detail_key.to_s.downcase.strip
    "#{product}|#{norm_code}|#{detail_norm}"
  rescue
    "#{row[:ma_sp]}|#{row[:hw_name]}"
  end

  def self.dedupe_import_material_rows(rows)
    seen = {}
    Array(rows).each_with_object([]) do |row, out|
      if row[:kind].to_s.strip.upcase == "VL"
        key = import_excel_material_dedupe_key(row)
        next if seen[key]
        seen[key] = true
      end
      out << row
    end
  end

  def self.normalize_import_excel_rows(rows)
    parsed = Array(rows).map { |row| normalize_import_excel_row(row) }
                        .reject { |row| row.empty? || row[:ma_sp].to_s.empty? || row[:hw_name].to_s.empty? }
    dedupe_import_material_rows(parsed)
  end

  def self.serialize_import_excel_rows(rows)
    normalize_import_excel_rows(rows).map do |row|
      row.each_with_object({}) { |(key, value), out| out[key.to_s] = import_excel_deep_fix(value) }
    end
  end

  def self.import_excel_history_payload
    ensure_mini_accept_rules if respond_to?(:ensure_mini_accept_rules)
    ensure_mini_name_lineage if respond_to?(:ensure_mini_name_lineage)
    {
      "saved_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      "match_rules_count" => (@match_rules || {}).size,
      "mini_accept_rules_count" => (@mini_accept_rules || {}).size,
      "mini_name_lineage_count" => (@mini_name_lineage || {}).size,
      "mini_accept_rules" => import_excel_deep_fix(@mini_accept_rules || {}),
      "mini_name_lineage" => import_excel_deep_fix(@mini_name_lineage || {})
    }
  rescue
    { "saved_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S") }
  end

  def self.load_import_excel_cache_store
    path = import_excel_cache_file
    return { "version" => IMPORT_EXCEL_CACHE_VERSION, "entries" => {} } unless File.exist?(path)

    data = JSON.parse(File.read(path, encoding: "UTF-8"))
    data = {} unless data.is_a?(Hash)
    data["entries"] = {} unless data["entries"].is_a?(Hash)
    data["version"] ||= IMPORT_EXCEL_CACHE_VERSION
    data
  rescue => e
    puts "Load import Excel cache error: #{e.message}" rescue nil
    { "version" => IMPORT_EXCEL_CACHE_VERSION, "entries" => {} }
  end

  def self.save_import_excel_cache_store(store)
    store = {} unless store.is_a?(Hash)
    store["version"] = IMPORT_EXCEL_CACHE_VERSION
    store["updated_at"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    store["entries"] = {} unless store["entries"].is_a?(Hash)
    FileUtils.mkdir_p(File.dirname(import_excel_cache_file)) rescue nil
    File.write(import_excel_cache_file, JSON.pretty_generate(store))
    true
  rescue => e
    puts "Save import Excel cache error: #{e.message}" rescue nil
    false
  end

  def self.import_excel_cache_entry(path, project = nil)
    store = load_import_excel_cache_store
    key = import_excel_cache_key(path, project)
    entry = store["entries"][key]
    return [store, key, entry] if entry.is_a?(Hash)

    path_key = import_excel_normalized_path(path)
    project_text = fix_vietnamese_mojibake(project || import_excel_project_key).to_s.strip
    pair = store["entries"].find do |_, value|
      next false unless value.is_a?(Hash)
      same_path = import_excel_normalized_path(value["path"]) == path_key
      same_project = project_text.empty? || project_name_match?(value["project"], project_text)
      same_path && same_project
    end
    return [store, pair[0], pair[1]] if pair

    # Fallback: project key can drift (e.g. model path name changed) while Excel
    # path is still the same. In that case prefer same-path cache entry regardless
    # of stored project to avoid dropping snapshot data.
    same_path_pair = store["entries"].find do |_, value|
      value.is_a?(Hash) && import_excel_normalized_path(value["path"]) == path_key
    end
    same_path_pair ? [store, same_path_pair[0], same_path_pair[1]] : [store, key, nil]
  rescue
    [{ "version" => IMPORT_EXCEL_CACHE_VERSION, "entries" => {} }, import_excel_cache_key(path, project), nil]
  end

  def self.save_import_excel_json_cache(path = nil, path_mtime = nil, rows = nil, source = "excel")
    path = (path || @import_excel_loaded_path || sync_import_excel_path).to_s
    return false if path.empty?

    project = import_excel_project_key
    path_mtime = path_mtime || (File.mtime(path).to_f rescue @import_excel_loaded_mtime.to_f)
    rows = rows || @imported_excel_data || []
    store, key, _entry = import_excel_cache_entry(path, project)
    store["entries"] ||= {}
    store["entries"][key] = {
      "project" => project,
      "path" => path,
      "path_key" => import_excel_normalized_path(path),
      "mtime" => path_mtime.to_f,
      "row_count" => normalize_import_excel_rows(rows).size,
      "loaded_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      "source" => source.to_s,
      "data_role" => "system_json_source",
      "history" => import_excel_history_payload,
      "rows" => serialize_import_excel_rows(rows)
    }
    ok = save_import_excel_cache_store(store)
    @import_excel_cache_key = key if ok
    ok
  end

  def self.load_import_excel_json_cache(path = nil, path_mtime = nil, strict_mtime: true)
    path = (path || sync_import_excel_path).to_s
    return nil if path.empty?

    _, key, entry = import_excel_cache_entry(path, import_excel_project_key)
    return nil unless entry.is_a?(Hash)

    if strict_mtime && path_mtime && entry["mtime"].to_f != path_mtime.to_f
      @import_excel_cache_stale = true
      return nil
    end

    rows = normalize_import_excel_rows(entry["rows"] || [])
    return nil if rows.empty?

    stale = !!(path_mtime && entry["mtime"].to_f != path_mtime.to_f)
    set_import_excel_loaded_state(
      rows,
      entry["path"].to_s.empty? ? path : entry["path"].to_s,
      entry["mtime"].to_f,
      stale ? "json_stale" : "json",
      key,
      stale
    )
    rows.size
  rescue => e
    puts "Load import Excel JSON snapshot error: #{e.message}" rescue nil
    nil
  end

  EXCEL_MTIME_CHECK_INTERVAL = 10.0 unless const_defined?(:EXCEL_MTIME_CHECK_INTERVAL)
  EXCEL_STALE_AUTO_RELOAD_INTERVAL = 30.0 unless const_defined?(:EXCEL_STALE_AUTO_RELOAD_INTERVAL)

  def self.auto_reload_import_excel_if_stale(path, current_mtime)
    return false if path.to_s.empty? || current_mtime.to_f <= 0
    return false if @excel_loading || @manual_excel_reload_busy

    now = Time.now.to_f
    sig = "#{path}|#{current_mtime.to_f}"
    return false if @import_excel_stale_reload_sig == sig && (now - @import_excel_stale_reload_at.to_f) < EXCEL_STALE_AUTO_RELOAD_INTERVAL

    @import_excel_stale_reload_sig = sig
    @import_excel_stale_reload_at = now
    start_import_excel_async(path.to_s, current_mtime.to_f) do |_rows, error|
      if error
        @import_excel_status_message = "Excel da thay doi nhung nap lai loi: #{error.message}. Tam dung JSON cu."
      else
        @import_excel_status_message = import_excel_status_text("Da tu nap lai Excel moi")
        import_excel_refresh_dependent_views(false) if respond_to?(:import_excel_refresh_dependent_views)
      end
    end
    true
  rescue => e
    puts "Auto reload stale Excel error: #{e.message}" rescue nil
    false
  end

  def self.load_import_excel_snapshot_only
    clear_excel_loading_state if excel_loading_timed_out?
    path = sync_import_excel_path

    # Fast path: data already loaded for this path — throttle File.mtime checks
    if !@imported_excel_data.nil? && @import_excel_loaded_path.to_s == path.to_s
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
      if @import_excel_mtime_last_check.to_f > 0 && (now - @import_excel_mtime_last_check.to_f) < EXCEL_MTIME_CHECK_INTERVAL
        return (@imported_excel_data || []).size
      end
      @import_excel_mtime_last_check = now
      current_mtime = File.exist?(path.to_s) ? (File.mtime(path.to_s).to_f rescue nil) : nil
      @import_excel_cache_stale = !!(current_mtime && @import_excel_loaded_mtime.to_f != current_mtime.to_f)
      auto_reload_import_excel_if_stale(path, current_mtime) if @import_excel_cache_stale
      return (@imported_excel_data || []).size
    end

    current_mtime = File.exist?(path.to_s) ? (File.mtime(path.to_s).to_f rescue nil) : nil
    @import_excel_mtime_last_check = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    result = load_import_excel_json_cache(path, current_mtime, strict_mtime: false)
    auto_reload_import_excel_if_stale(path, current_mtime) if @import_excel_cache_stale
    result
  rescue
    nil
  end

  def self.import_excel_source_label
    case @import_excel_source.to_s
    when "excel"
      "Excel"
    when "manual_excel_to_json"
      "JSON vua tao tu Excel"
    when "json"
      "JSON"
    when "json_stale"
      "JSON cu"
    when "json_fallback"
      "JSON du phong"
    else
      @imported_excel_data && !@imported_excel_data.empty? ? "du lieu he thong" : ""
    end
  end

  def self.import_excel_status_text(prefix = "Da nap")
    count = (@imported_excel_data || []).size
    source = import_excel_source_label
    stale = @import_excel_cache_stale ? " - JSON dang dung ban cu; bam EXCEL neu muon nap lai file dau vao" : ""
    source.empty? ? "#{prefix}: #{count} dong" : "#{prefix}: #{count} dong tu #{source}#{stale}"
  end

  def self.import_excel_base_product_code(code)
    text = code.to_s.strip.upcase
    text.empty? ? "" : text.split(".").first.to_s
  end

  def self.import_excel_product_codes(mode = nil, rows = nil)
    mode ||= respond_to?(:mini_group_mode) ? mini_group_mode : "product"
    source_rows = rows || @imported_excel_data || []
    codes = []
    Array(source_rows).each do |row|
      next unless row.is_a?(Hash)

      raw_code = row[:ma_sp] || row["ma_sp"]
      code = if mode.to_s == "module" && respond_to?(:product_code_exact)
        product_code_exact(raw_code)
      elsif respond_to?(:product_code_base)
        product_code_base(raw_code)
      else
        import_excel_base_product_code(raw_code)
      end
      next if code.empty? || code == "--"
      next unless respond_to?(:product_code_valid?) ? product_code_valid?(code) : code =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i

      codes << code unless codes.include?(code)
    end
    codes.sort_by { |code| respond_to?(:product_code_sort_key) ? product_code_sort_key(code) : code }
  rescue
    []
  end

  def self.import_excel_clean_product_name(value)
    text = fix_vietnamese_mojibake(value).to_s.strip
    return "" if text.empty?

    if respond_to?(:strip_product_code_prefix)
      strip_product_code_prefix(text).to_s.strip
    else
      code = respond_to?(:product_codes_from_text) ? product_codes_from_text(text).first : nil
      if code && text.upcase.start_with?(code.to_s.upcase)
        text[code.length..-1].to_s.sub(/\A[\s_\-]+/, "").strip
      else
        text.sub(/\A[A-Z]+\d+[A-Z]?(?:\.\d+)?[\s_\-]+/i, "").strip
      end
    end
  rescue
    value.to_s.strip
  end

  def self.excel_rows_signature_cached
    rows = @imported_excel_data
    current_id = rows.object_id
    if @excel_data_object_id != current_id || @excel_data_version.to_i <= 0
      @excel_data_version = @excel_data_version.to_i + 1
      @excel_data_version = 1 if @excel_data_version <= 0
      @excel_data_object_id = current_id
    end
    @excel_data_version
  rescue
    @excel_data_version ||= 1
  end

  def self.excel_product_name_index
    sig = excel_rows_signature_cached
    return @excel_product_name_index if @excel_product_name_index_sig == sig && @excel_product_name_index

    counts_by_base = Hash.new { |h, k| h[k] = Hash.new(0) }
    order_by_base = Hash.new { |h, k| h[k] = [] }

    Array(@imported_excel_data).each do |row|
      next unless row.is_a?(Hash)

      row_code = row[:ma_sp] || row["ma_sp"]
      row_base = if respond_to?(:product_code_base)
        product_code_base(row_code)
      else
        import_excel_base_product_code(row_code)
      end
      next if row_base.to_s.empty?

      name = import_excel_clean_product_name(row[:ten_sp] || row["ten_sp"])
      next if name.empty?

      order = order_by_base[row_base]
      order << name unless order.include?(name)
      counts_by_base[row_base][name] += 1
    end

    index = {}
    counts_by_base.each do |base, counts|
      order = order_by_base[base]
      index[base] = order.empty? ? "" : order.max_by { |name| [counts[name].to_i, -order.index(name).to_i] }.to_s
    end

    @excel_product_name_index = index
    @excel_product_name_index_sig = sig
    index
  rescue
    {}
  end

  def self.import_excel_product_name_for(product_code, load_snapshot = true)
    if load_snapshot && (!@imported_excel_data || @imported_excel_data.empty?) && respond_to?(:load_import_excel_snapshot_only)
      load_import_excel_snapshot_only
    end

    base = if respond_to?(:product_code_base)
      product_code_base(product_code)
    else
      import_excel_base_product_code(product_code)
    end
    return "" if base.to_s.empty?

    @excel_product_names_cache ||= {}
    sig = excel_rows_signature_cached
    if @excel_product_names_cache_sig != sig
      @excel_product_names_cache = {}
      @excel_product_names_cache_sig = sig
    end

    return @excel_product_names_cache[base] if @excel_product_names_cache.key?(base)

    result = excel_product_name_index.fetch(base, "")
    @excel_product_names_cache[base] = result
    result
  rescue
    ""
  end

  def self.import_excel_product_title(product_code, load_snapshot = true)
    code = if respond_to?(:product_code_base)
      product_code_base(product_code)
    else
      import_excel_base_product_code(product_code)
    end
    name = import_excel_product_name_for(code, load_snapshot)
    name.empty? ? code : "#{code} - #{name}"
  rescue
    product_code.to_s
  end

  def self.reload_import_excel_from_file!(path = nil)
    @model = Sketchup.active_model
    remember_import_excel_path(path) if path && !path.to_s.strip.empty?
    path = sync_import_excel_path.to_s
    raise "Chua co file Excel hop le." if path.empty? || !File.exist?(path)

    clear_excel_loading_state
    @import_excel_error = nil
    @import_excel_last_error_at = nil
    invalidate_mini_import_caches(excel: true) if respond_to?(:invalidate_mini_import_caches)

    path_mtime = File.mtime(path).to_f
    rows = normalize_import_excel_rows(parse_import_excel_data(path))
    set_import_excel_loaded_state(rows, path, path_mtime, "manual_excel_to_json", nil, false)
    save_import_excel_json_cache(path, path_mtime, rows, "manual_excel_to_json")
    @process_selection_cache_sig = nil
    rows.size
  rescue => e
    @import_excel_error = e.message
    @import_excel_last_error_at = Time.now.to_f
    raise
  end

  def self.load_import_excel_rows!(rows, source_path:, source_mtime: nil, source: "mh_registry_payload", refresh: true, json_path: nil)
    path = source_path.to_s.strip
    raise "source_path empty." if path.empty?

    remember_import_excel_path(path) if respond_to?(:remember_import_excel_path)
    clear_excel_loading_state
    @import_excel_error = nil
    @import_excel_last_error_at = nil
    invalidate_mini_import_caches(excel: true) if respond_to?(:invalidate_mini_import_caches)

    path_mtime = source_mtime || (File.mtime(path).to_f rescue 0.0)
    normalized = normalize_import_excel_rows(rows || [])
    raise "payload rows empty." if normalized.empty?

    set_import_excel_loaded_state(normalized, path, path_mtime, source.to_s, nil, false)
    @import_excel_json_path = json_path.to_s unless json_path.to_s.empty?
    save_import_excel_json_cache(path, path_mtime, normalized, source.to_s)
    @process_selection_cache_sig = nil
    import_excel_refresh_dependent_views(false) if refresh && respond_to?(:import_excel_refresh_dependent_views)
    normalized.size
  rescue => e
    @import_excel_error = e.message
    @import_excel_last_error_at = Time.now.to_f
    raise
  end

  def self.import_excel_refresh_dependent_views(process_model = false)
    invalidate_mini_import_caches(excel: true) if respond_to?(:invalidate_mini_import_caches)
    if respond_to?(:refresh_import_related_views)
      # Excel reload must not force a model scan on the SketchUp UI thread.
      refresh_import_related_views(process_model, false, false, 0.05)
      return
    end

    process_selection if process_model && respond_to?(:process_selection)
    update_html if @dlg && (@dlg.visible? rescue false) && respond_to?(:update_html)
    if respond_to?(:mini_dialog_visible?) && mini_dialog_visible? && respond_to?(:refresh_import_mini_dialog)
      refresh_import_mini_dialog(false, false)
    end
    if respond_to?(:material_hud_visible?) && material_hud_visible? && respond_to?(:refresh_import_material_hud)
      refresh_import_material_hud(false, false)
    end
  end

  def self.schedule_import_excel_reload(path = nil, source = "manual")
    if @manual_excel_reload_busy
      UI.messagebox("Dang nap Excel. Vui long cho lenh hien tai ket thuc.") rescue nil
      return false
    end

    @manual_excel_reload_busy = true
    remember_import_excel_path(path) if path && !path.to_s.strip.empty?
    @import_excel_error = nil
    @import_excel_last_error_at = nil
    @import_excel_status_message = "Dang nap Excel va tao JSON..."

    loading_html = "<tr><td colspan='5' class='empty'>Dang nap Excel va tao JSON...</td></tr>"
    if respond_to?(:mini_import_execute_script)
      mini_import_execute_script("updateTable(#{js_arg(loading_html)})")
    elsif respond_to?(:mini_dialog_visible?) && mini_dialog_visible?
      @mini_dlg.execute_script("updateTable(#{js_arg(loading_html)})") rescue nil
    end

    excel_path = sync_import_excel_path.to_s
    path_mtime = File.mtime(excel_path).to_f rescue Time.now.to_f
    start_import_excel_async(excel_path, path_mtime) do |_rows, error|
      begin
        if error
          load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)
          @import_excel_status_message = "Loi nap Excel: #{error.message}. Da quay ve JSON hien co."
          UI.messagebox("Loi nap Excel: #{error.message}\nDa quay ve du lieu JSON hien co.") rescue nil
        else
          @import_excel_status_message = import_excel_status_text("Da nap Excel va tao JSON")
        end
        import_excel_refresh_dependent_views(false)
      ensure
        @manual_excel_reload_busy = false
      end
    end
    true
  rescue => e
    @manual_excel_reload_busy = false
    @import_excel_status_message = "Loi len lich nap Excel: #{e.message}"
    UI.messagebox("Loi len lich nap Excel: #{e.message}") rescue nil
    false
  end

  def self.finish_import_excel_async(token, path, path_mtime, parsed, error)
    return unless token == @excel_loading_token

    reset_import_excel_loading_flags

    if error
      @import_excel_error = error.message
      clear_import_excel_loaded_state if respond_to?(:clear_import_excel_loaded_state)
      @import_excel_last_error_at = Time.now.to_f
      @imported_excel_data ||= []
    else
      set_import_excel_loaded_state(parsed || [], path, path_mtime, "excel", nil, false)
      save_import_excel_json_cache(path, path_mtime, @imported_excel_data, "excel")
    end

    cb = (@excel_async_callbacks ||= {}).delete(token)
    cb.call(@imported_excel_data || [], error) if cb
  rescue => e
    reset_import_excel_loading_flags
    @import_excel_error = e.message
  end

  def self.parse_import_excel_data(path)
    # Phase 1: Stateless Data Pipeline - CLI Excel Helper
    helper_exe = File.join(MH_Thongke::ROOT_DIR, 'engine', 'dist', 'excel_helper.exe')
    
    unless File.exist?(helper_exe)
      # Fallback hoặc cảnh báo
      raise "Excel Helper executable not found at #{helper_exe}"
    end

    temp_json = File.join(MH_Thongke::DATA_DIR, 'temp_excel_output.json')
    File.delete(temp_json) if File.exist?(temp_json)

    # Thực thi ẩn trên Windows
    cmd = "\"#{helper_exe}\" \"#{path.tr("/", "\\")}\" \"#{temp_json.tr("/", "\\")}\""
    
    system(cmd)

    if File.exist?(temp_json)
      json_data = File.read(temp_json, encoding: "UTF-8")
      begin
        rows = JSON.parse(json_data, symbolize_names: true)
        File.delete(temp_json) rescue nil
        return rows
      rescue => e
        raise "Failed to parse excel_helper output: #{e.message}"
      end
    else
      raise "Excel Helper failed to generate output file"
    end
  end

  def self.start_import_excel_async(path, path_mtime, &on_done)
    helper_exe = File.join(MH_Thongke::ROOT_DIR, 'engine', 'dist', 'excel_helper.exe')
    raise "Excel Helper executable not found at #{helper_exe}" unless File.exist?(helper_exe)
    raise "Chua co file Excel hop le." if path.to_s.empty? || !File.exist?(path.to_s)

    clear_excel_loading_state
    @import_excel_error = nil
    @import_excel_last_error_at = nil
    token = "#{Time.now.to_i}_#{rand(1_000_000)}"
    @excel_loading_token = token
    @excel_loading = true
    @excel_loading_path = path.to_s
    @excel_loading_mtime = path_mtime.to_f
    @excel_loading_started_at = Time.now.to_f
    @excel_async_callbacks ||= {}
    @excel_async_callbacks[token] = on_done if on_done

    FileUtils.mkdir_p(MH_Thongke::DATA_DIR) rescue nil
    temp_json = File.join(MH_Thongke::DATA_DIR, "temp_excel_output_#{token}.json")
    log_path = File.join(MH_Thongke::DATA_DIR, "temp_excel_output_#{token}.log")
    File.delete(temp_json) if File.exist?(temp_json)
    File.delete(log_path) if File.exist?(log_path)

    cmd = "\"#{helper_exe}\" \"#{path.to_s.tr("/", "\\")}\" \"#{temp_json.tr("/", "\\")}\""
    Process.spawn(helper_exe, path.to_s, temp_json, [:out, :err] => log_path)

    @excel_loading_poll_timer = UI.start_timer(0.25, true) do
      import_excel_poll_async_result(token, path.to_s, path_mtime.to_f, temp_json)
    end
    true
  rescue => e
    stop_excel_loading_poll_timer
    reset_import_excel_loading_flags
    @import_excel_error = e.message
    @import_excel_last_error_at = Time.now.to_f
    on_done.call(@imported_excel_data || [], e) if on_done
    nil
  end

  def self.import_excel_poll_async_result(token, path, path_mtime, temp_json)
    return unless token == @excel_loading_token

    if File.exist?(temp_json) && File.size(temp_json).to_i > 0
      begin
        json_data = File.read(temp_json, encoding: "UTF-8")
        rows = JSON.parse(json_data, symbolize_names: true)
        File.delete(temp_json) rescue nil
        stop_excel_loading_poll_timer
        finish_import_excel_async(token, path, path_mtime, normalize_import_excel_rows(rows), nil)
      rescue => e
        stop_excel_loading_poll_timer
        finish_import_excel_async(token, path, path_mtime, [], RuntimeError.new("Failed to parse excel_helper output: #{e.message}"))
      end
      return
    end

    if @excel_loading_started_at.to_f > 0 && Time.now.to_f - @excel_loading_started_at.to_f > EXCEL_ASYNC_TIMEOUT_SECONDS.to_f
      stop_excel_loading_poll_timer
      finish_import_excel_async(token, path, path_mtime, [], RuntimeError.new("Excel Helper qua #{EXCEL_ASYNC_TIMEOUT_SECONDS.to_i}s chua tao output JSON."))
    end
  rescue => e
    stop_excel_loading_poll_timer
    finish_import_excel_async(token, path, path_mtime, [], e)
  end

  def self.import_excel_project_key
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    if @import_excel_project_key_cache && @import_excel_project_key_last_check.to_f > 0 && (now - @import_excel_project_key_last_check.to_f) < 5.0
      return @import_excel_project_key_cache
    end
    @import_excel_project_key_last_check = now

    @model = Sketchup.active_model
    key = current_project_name rescue ""
    if key.to_s.strip.empty? || key == DEFAULT_PROJECT_NAME
      begin
        model_project = @model.get_attribute("MH_Thongke", "import_excel_project").to_s
        key = model_project unless model_project.to_s.strip.empty?
      rescue
      end
    end
    if key.to_s.strip.empty? || key == DEFAULT_PROJECT_NAME
      model_path = (@model.path rescue "").to_s
      key = project_name_for_path(model_path) unless model_path.empty?
    end
    @import_excel_project_key_cache = fix_vietnamese_mojibake(key).to_s.strip
    @import_excel_project_key_cache
  rescue
    @import_excel_project_key_cache = DEFAULT_PROJECT_NAME
    @import_excel_project_key_cache
  end

  def self.import_excel_project_token(value)
    cached_norm(fix_vietnamese_mojibake(value)).gsub(/[^a-z0-9]+/, "")
  rescue
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
  end

  def self.import_excel_model_token(value)
    text = File.basename(value.to_s).upcase
    token = text[/[A-Z]{2}\d{6,}/]
    token.to_s
  rescue
    ""
  end

  def self.import_excel_guess_path_for_model(model_path)
    token = import_excel_model_token(model_path)
    return "" if token.empty?

    candidates = []
    Array(@import_excel_paths).each do |project, path|
      path_text = path.to_s
      next if path_text.empty?
      next unless path_text.upcase.include?(token)
      candidates << { path: path_text, score: 10 }
    end

    store = load_import_excel_cache_store
    entries = store["entries"].is_a?(Hash) ? store["entries"] : {}
    entries.each_value do |entry|
      next unless entry.is_a?(Hash)
      entry_path = entry["path"].to_s
      next if entry_path.empty?
      next unless entry_path.upcase.include?(token)
      loaded_at = begin
        Time.parse(entry["loaded_at"].to_s).to_i
      rescue
        0
      end
      candidates << { path: entry_path, score: 20 + loaded_at }
    end

    best = candidates.max_by { |item| item[:score].to_i }
    best ? best[:path].to_s : ""
  rescue
    ""
  end

  def self.import_excel_path_belongs_to_project?(path, project)
    project = fix_vietnamese_mojibake(project).to_s.strip
    return false if project.empty? || project == DEFAULT_PROJECT_NAME
    project_token = import_excel_project_token(project)
    return false if project_token.length < 4
    import_excel_project_token(path).include?(project_token)
  rescue
    false
  end

  def self.import_excel_path_matches_model?(path, model_path)
    model_token = import_excel_model_token(model_path)
    return true if model_token.empty?

    path_token = import_excel_model_token(File.basename(path.to_s))
    path_token.empty? || path_token == model_token
  rescue
    true
  end

  def self.import_excel_path_usable_for_context?(path, project_key, model_path)
    path = path.to_s.strip
    return false if path.empty?

    project_ok = project_key == DEFAULT_PROJECT_NAME ||
                 import_excel_path_belongs_to_project?(path, project_key)
    project_ok && import_excel_path_matches_model?(path, model_path)
  rescue
    false
  end

  def self.import_excel_path_for_project(project)
    @import_excel_paths ||= {}
    key = fix_vietnamese_mojibake(project).to_s.strip
    exact = @import_excel_paths[key].to_s
    return exact unless exact.empty?

    pair = @import_excel_paths.find { |stored_project, _| project_name_match?(stored_project, key) }
    pair ? pair[1].to_s : ""
  rescue
    ""
  end

  def self.remember_import_excel_path(path)
    @model = Sketchup.active_model
    path = path.to_s.strip.gsub(/^["']|["']$/, "")
    project_key = import_excel_project_key
    old_path = @import_excel_path.to_s
    @import_excel_path = path
    @import_excel_project_key = project_key
    @import_excel_paths ||= {}
    @import_excel_paths[project_key] = path unless project_key.to_s.empty?
    @import_excel_model_paths ||= {}
    begin
      model_guid = @model.guid.to_s
      @import_excel_model_paths[model_guid] = path unless model_guid.empty?
    rescue
    end
    @model.set_attribute("MH_Thongke", "import_excel_path", path) rescue nil
    @model.set_attribute("MH_Thongke", "import_excel_project", project_key) rescue nil
    if old_path != path
      @mini_accept_rules = nil
      reset_mini_rule_caches(lineage: true, accept: true, refresh: true) if respond_to?(:reset_mini_rule_caches)
      @mini_accept_rules_project_file = nil
      @mini_accept_rules_source_sig = nil
    end
    save_preferences
    path
  end

  def self.sync_import_excel_path
    @model = Sketchup.active_model
    old_path = @import_excel_path.to_s
    project_key = import_excel_project_key
    stored_project_path = import_excel_path_for_project(project_key)
    @import_excel_model_paths ||= {}
    model_guid = (@model.guid.to_s rescue "")
    model_mapped_path = model_guid.empty? ? "" : @import_excel_model_paths[model_guid].to_s
    model_path = @model.get_attribute("MH_Thongke", "import_excel_path").to_s
    model_project = @model.get_attribute("MH_Thongke", "import_excel_project").to_s
    model_file_path = (@model.path rescue "").to_s

    # Model-level path must win to avoid being overwritten by the latest global
    # project mapping from another file/session.
    path = ""
    unless model_path.empty?
      if !model_project.empty?
        if project_name_match?(model_project, project_key) || project_key == DEFAULT_PROJECT_NAME
          path = model_path if import_excel_path_matches_model?(model_path, model_file_path)
        end
      elsif import_excel_path_usable_for_context?(model_path, project_key, model_file_path)
        path = model_path
      end
    end
    if path.empty? && import_excel_path_usable_for_context?(model_mapped_path, project_key, model_file_path)
      path = model_mapped_path
    end
    guessed_model_path = import_excel_guess_path_for_model(model_file_path)
    if path.empty? && import_excel_path_usable_for_context?(guessed_model_path, project_key, model_file_path)
      path = guessed_model_path
    end
    use_project_map = !(project_key == DEFAULT_PROJECT_NAME && model_path.to_s.empty? && model_mapped_path.to_s.empty?)
    if path.empty? && use_project_map &&
       import_excel_path_usable_for_context?(stored_project_path, project_key, model_file_path)
      path = stored_project_path.to_s
    end
    if path.empty? && use_project_map && @import_excel_project_key && project_name_match?(@import_excel_project_key, project_key)
      if import_excel_path_usable_for_context?(@import_excel_path, project_key, model_file_path)
        path = @import_excel_path.to_s
      end
    end
    if path.empty? && use_project_map && project_key == DEFAULT_PROJECT_NAME && File.exist?(MH_THONGKE_PREFS_JSON)
      begin
        pref = JSON.parse(File.read(MH_THONGKE_PREFS_JSON))
        path = pref["import_excel_path"].to_s if pref.is_a?(Hash)
      rescue
      end
    end
    if path.empty? &&
       import_excel_path_usable_for_context?(@import_excel_loaded_path, project_key, model_file_path)
      path = @import_excel_loaded_path.to_s
    end
    path = path.to_s.strip.gsub(/^["']|["']$/, "")
    if !path.empty? && project_key != DEFAULT_PROJECT_NAME
      @import_excel_paths ||= {}
      if import_excel_path_for_project(project_key).to_s.empty?
        @import_excel_paths[project_key] = path
        save_preferences
      end
    end
    clear_import_excel_loaded_state if @import_excel_loaded_path && @import_excel_loaded_path.to_s != path.to_s
    @import_excel_path = path
    @import_excel_project_key = project_key
    if old_path != path
      @mini_accept_rules = nil
      reset_mini_rule_caches(lineage: true, accept: true, refresh: true) if respond_to?(:reset_mini_rule_caches)
      @mini_accept_rules_project_file = nil
      @mini_accept_rules_source_sig = nil
    end
    @import_excel_path
  end

  def self.import_excel_cache_stale?
    clear_excel_loading_state if excel_loading_timed_out?
    path = sync_import_excel_path
    return false if path.to_s.empty?

    unless File.exist?(path.to_s)
      return false if load_import_excel_json_cache(path, nil, strict_mtime: false)
      return false
    end

    current_mtime = File.mtime(path.to_s).to_f rescue nil
    return false unless load_import_excel_json_cache(path, current_mtime, strict_mtime: false)

    @import_excel_cache_stale ? true : false
  end

  def self.ensure_import_excel_loaded(force = false, async: false, &on_done)
    clear_excel_loading_state if @excel_loading && !async
    @import_excel_error = nil
    if force
      path = sync_import_excel_path.to_s
      if !path.empty? && File.exist?(path)
        if async
          path_mtime = File.mtime(path).to_f rescue Time.now.to_f
          start_import_excel_async(path, path_mtime, &on_done)
          return (@imported_excel_data || []).size
        end
        result = reload_import_excel_from_file!(path)
        on_done.call(@imported_excel_data || [], nil) if on_done
        return result
      end
    end
    result = load_import_excel_snapshot_only
    if async
      on_done.call(@imported_excel_data || [], nil) if on_done
    end
    result
  end

end
