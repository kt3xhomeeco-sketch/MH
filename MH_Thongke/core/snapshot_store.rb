# encoding: utf-8
# MH_Thongke — Snapshot Store
# Quản lý multi-file snapshot (load/save JSON)
# Tách từ main.rb: dòng 57–216

module MH_Thongke
  require 'time'

  REPORT_BLOCK_KEYWORDS = ["chua co ma", "cho duyet"].freeze unless defined?(REPORT_BLOCK_KEYWORDS)

  def self.load_snapshots
    # Cache by file mtime to avoid re-parsing the JSON on every update_html call.
    # ~400ms on disk + 400ms normalize was running tens of times per render.
    if File.exist?(MH_THONGKE_DATA_JSON)
      mtime = File.mtime(MH_THONGKE_DATA_JSON).to_f rescue 0.0
      if @file_snapshots && @file_snapshots_loaded_mtime == mtime
        # Already loaded the latest version. normalize_snapshots! has its own
        # idempotency via @file_snapshots_normalized signature, so still cheap.
        normalize_snapshots!
        return @file_snapshots
      end
      @file_snapshots = []
      begin
        data = JSON.parse(File.read(MH_THONGKE_DATA_JSON))
        @file_snapshots = data["files"] || []
        @file_snapshots_loaded_mtime = mtime
      rescue => e
        puts "Load snapshots error: #{e.message}"
      end
    else
      @file_snapshots = []
      @file_snapshots_loaded_mtime = nil
    end
    normalize_snapshots!
  end

  def self.save_snapshots
    @snapshots_for_current_project_cache = nil
    @project_total_source_snapshots_cache = nil
    @project_total_source_rows_cache = nil
    @file_snapshots_normalized_sig = nil
    @file_snapshots_loaded_mtime = nil
    normalize_snapshots!(false)
    (@file_snapshots || []).each do |snap|
      next if snap["live"]
      next if Array(snap["items"]).empty? && Array(snap["mat_items"]).empty?
      write_snapshot_json_file(snap)
    end
    write_project_backup_json_files
    File.write(MH_THONGKE_DATA_JSON, JSON.pretty_generate({ "files" => @file_snapshots }))
  rescue => e
    puts "Save snapshots error: #{e.message}"
  end

  def self.save_snapshot_index_only
    normalize_snapshots!(false)
    write_project_backup_json_files
    File.write(MH_THONGKE_DATA_JSON, JSON.pretty_generate({ "files" => @file_snapshots }))
  rescue => e
    puts "Save snapshot index error: #{e.message}"
  end

  def self.project_json_safe_name(value)
    text = fix_vietnamese_mojibake(value).to_s.strip
    text = cached_norm(text).gsub(/[^a-z0-9._-]+/i, "_").gsub(/\A_+|_+\z/, "") rescue text.gsub(/[^\w.-]+/, "_")
    text.empty? ? "project" : text
  end

  def self.snapshot_project_data_dir_for(skp_path)
    path = skp_path.to_s.strip
    return "" if path.empty?

    dir = File.dirname(path)
    return "" if dir.nil? || dir.empty? || dir == "."

    File.join(dir, PROJECT_DATA_DIR_NAME)
  end

  def self.current_project_data_dir
    model = Sketchup.active_model rescue nil
    snapshot_project_data_dir_for(model ? model.path.to_s : "")
  rescue
    ""
  end

  def self.snapshot_json_file_name_for(snap)
    source = snap["skp_path"].to_s.strip
    source = snap["skp_name"].to_s.strip if source.empty?
    base = File.basename(source, ".*").to_s.strip
    base = "UNSAVED_#{Time.now.to_i}" if base.empty?
    "#{base.upcase}.JSON"
  end

  def self.snapshot_json_path_for(snap)
    dir = snapshot_project_data_dir_for(snap["skp_path"])
    return File.join(dir, snapshot_json_file_name_for(snap)) unless dir.empty?

    project = project_json_safe_name(snapshot_project(snap))
    File.join(MH_THONGKE_PROJECT_DATA_DIR, project, snapshot_json_file_name_for(snap))
  end

  def self.ensure_snapshot_json_path!(snap)
    return "" unless snap.is_a?(Hash)
    path = snap["json_path"].to_s.strip
    preferred = snapshot_json_path_for(snap)
    unless path.empty?
      legacy_dir = normalized_skp_path(MH_THONGKE_PROJECT_DATA_DIR)
      if !legacy_dir.empty? && normalized_skp_path(path).start_with?(legacy_dir)
        begin
          FileUtils.mkdir_p(File.dirname(preferred))
          FileUtils.cp(path, preferred) if File.exist?(path) && !File.exist?(preferred)
        rescue => e
          puts "migrate snapshot json error: #{e.message}"
        end
        snap["json_path"] = preferred
        return preferred
      end
      return path
    end

    snap["json_path"] = preferred
    preferred
  end

  def self.snapshot_json_payload(snap)
    snapshot_copy = snap.reject { |key, _| key.to_s == "live" }.dup
    snapshot_copy["items"] = snapshot_items_base_payload(Array(snap["items"]), "acc")
    snapshot_copy["mat_items"] = snapshot_items_base_payload(Array(snap["mat_items"]), "mat")
    {
      "schema" => "mh_thongke_project_snapshot",
      "schema_version" => 1,
      "generated_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      "source" => {
        "skp_path" => snap["skp_path"].to_s,
        "skp_name" => snap["skp_name"].to_s,
        "skp_mtime" => (File.exist?(snap["skp_path"].to_s) ? File.mtime(snap["skp_path"].to_s).strftime("%Y-%m-%d %H:%M:%S") : "")
      },
      "snapshot" => snapshot_copy
    }
  end

  def self.snapshot_resolved_ten_sp(row, product = nil)
    get = lambda { |key| row[key.to_s] || row[key.to_sym] }
    current = respond_to?(:fix_vietnamese_mojibake) ? fix_vietnamese_mojibake(get.call(:ten_sp)).to_s.strip : get.call(:ten_sp).to_s.strip
    code = product.to_s.strip
    code = (get.call(:actual_product) || get.call(:product)).to_s.strip if code.empty?
    code = report_product_code(code) if respond_to?(:report_product_code)
    return current if code.to_s.strip.empty?

    begin
      if respond_to?(:import_excel_product_name_for)
        excel_name = import_excel_product_name_for(code, false).to_s.strip
        return fix_vietnamese_mojibake(excel_name).to_s.strip unless excel_name.empty?
      end
    rescue
    end
    current
  end

  def self.snapshot_items_base_payload(items, table)
    fix = lambda { |v|
      respond_to?(:fix_vietnamese_mojibake) ? fix_vietnamese_mojibake(v).to_s : v.to_s
    }
    get = lambda { |row, key|
      row[key.to_s] || row[key.to_sym]
    }
    Array(items).filter_map do |row|
      next unless row.is_a?(Hash)

      # Always run strings through fix_vietnamese_mojibake before serializing —
      # SketchUp on Windows sometimes hands back CP1252-tagged strings that
      # would otherwise land in the JSON file as "CÃ¡i" instead of "Cái".
      payload = {
        "name" => fix.call(get.call(row, :name)),
        "product" => fix.call(get.call(row, :actual_product) || get.call(row, :product)),
        "qty" => get.call(row, :qty) || get.call(row, :count),
        "unit" => fix.call(get.call(row, :unit)),
        "kich_thuoc" => fix.call(get.call(row, :kich_thuoc) || get.call(row, :thickness) || get.call(row, :spec)),
        "layer" => fix.call(get.call(row, :layer)),
        "type" => get.call(row, :type).to_s,
        "is_missing" => !!get.call(row, :is_missing),
        "obj_count" => (get.call(row, :obj_count) || Array(get.call(row, :stat_entities)).size).to_i,
        "has_obj" => !!(get.call(row, :has_obj) || Array(get.call(row, :stat_entities)).any?)
      }
      # Optional fields that often carry Vietnamese text
      payload["ten_sp"]        = fix.call(snapshot_resolved_ten_sp(row, payload["product"])) if row.key?("ten_sp") || row.key?(:ten_sp)
      payload["ghi_chu"]       = fix.call(get.call(row, :ghi_chu))       if row.key?("ghi_chu") || row.key?(:ghi_chu)
      payload["ngay_dat"]      = fix.call(get.call(row, :ngay_dat))      if row.key?("ngay_dat") || row.key?(:ngay_dat)
      payload["last_modified"] = fix.call(get.call(row, :last_modified)) if row.key?("last_modified") || row.key?(:last_modified)
      payload["layer_tags"] = Array(get.call(row, :layer_tags)).map { |v| fix.call(v) }
      if table.to_s == "mat"
        completion_percent = get.call(row, :completion_percent)
        payload["completion_percent"] = completion_percent if completion_percent
        completion_text = get.call(row, :completion_text)
        payload["completion_text"] = fix.call(completion_text) if completion_text
      end
      payload.delete("obj_count") unless row.key?("obj_count") || row.key?(:obj_count) || Array(get.call(row, :stat_entities)).any?
      payload.delete("has_obj") unless row.key?("has_obj") || row.key?(:has_obj) || Array(get.call(row, :stat_entities)).any?
      payload
    end
  rescue
    []
  end

  def self.apply_snapshot_item_state!(table, item)
    return unless item.is_a?(Hash)
    return unless respond_to?(:order_date_override) && respond_to?(:row_meta_key)

    data = {
      actual_product: item["product"].to_s,
      product: item["product"].to_s,
      name: item["name"].to_s
    }
    data[:thickness] = item["kich_thuoc"].to_s if table.to_s == "mat"

    begin
      date_value = order_date_override(table, data).to_s
      item["ngay_dat"] = date_value unless date_value.empty?
    rescue
    end

    begin
      meta = row_meta_overrides[row_meta_key(table, data)]
      if meta.is_a?(Hash)
        item["name"] = meta["name"].to_s if meta.key?("name")
        item["ten_sp"] = meta["ten_sp"].to_s if meta.key?("ten_sp")
        item["ghi_chu"] = meta["ghi_chu"].to_s if meta.key?("ghi_chu")
        item["last_modified"] = meta["last_modified"].to_s if meta.key?("last_modified")
      end
    rescue
    end
  end

  def self.snapshot_json_file_time(path)
    return "" if path.to_s.empty? || !File.exist?(path.to_s)

    time = begin
      File.birthtime(path.to_s)
    rescue
      File.mtime(path.to_s)
    end
    time.strftime("%Y-%m-%d %H:%M:%S")
  rescue
    ""
  end

  def self.write_snapshot_json_file(snap)
    path = ensure_snapshot_json_path!(snap)
    return "" if path.empty?

    FileUtils.mkdir_p(File.dirname(path))
    # Write trực tiếp để giữ nguyên thời gian tạo file JSON trên Windows.
    # Nếu xóa + rename thì birthtime sẽ bị reset theo thời điểm refresh.
    # mode "w:UTF-8" ensures Vietnamese chars stay as proper UTF-8 bytes
    # instead of being re-encoded under the default codepage.
    File.write(path, JSON.pretty_generate(snapshot_json_payload(snap)), mode: "w:UTF-8")
    file_time = snapshot_json_file_time(path)
    snap["exported_at"] = file_time unless file_time.empty?
    path
  rescue => e
    puts "write_snapshot_json_file error: #{e.message}"
    ""
  end

  def self.save_snapshot_entry_only(entry)
    return nil unless entry.is_a?(Hash)

    @snapshots_for_current_project_cache = nil
    @project_total_source_snapshots_cache = nil
    @project_total_source_rows_cache = nil
    @file_snapshots_normalized_sig = nil
    @file_snapshots_loaded_mtime = nil

    load_snapshots if @file_snapshots.nil?
    normalize_snapshots!(false)
    existing = find_snapshot_by_path(entry["skp_path"])
    if existing
      existing.merge!(entry)
    else
      @file_snapshots ||= []
      @file_snapshots << entry
    end
    write_snapshot_json_file(existing || entry)
    save_snapshot_index_only
    existing || entry
  rescue => e
    puts "save_snapshot_entry_only error: #{e.class}: #{e.message}"
    nil
  end

  def self.project_backup_json_path_for(dir, project)
    return "" if dir.to_s.empty?

    name = project_json_safe_name(project).upcase
    File.join(dir, "#{name}_PROJECT_BACKUP.JSON")
  end

  def self.write_project_backup_json_files
    groups = {}
    (@file_snapshots || []).each do |snap|
      next if snap["live"]

      dir = snapshot_project_data_dir_for(snap["skp_path"])
      next if dir.to_s.empty?

      project = snapshot_project(snap)
      key = [dir, project].join("|")
      groups[key] ||= { dir: dir, project: project, files: [] }
      groups[key][:files] << snap.reject { |snap_key, _| snap_key.to_s == "live" }
    end

    groups.each_value do |group|
      path = project_backup_json_path_for(group[:dir], group[:project])
      next if path.empty?

      payload = {
        "schema" => "mh_thongke_project_backup",
        "schema_version" => 1,
        "generated_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
        "project" => group[:project],
        "files" => group[:files]
      }
      FileUtils.mkdir_p(File.dirname(path))
      tmp_path = "#{path}.tmp"
      File.write(tmp_path, JSON.pretty_generate(payload))
      File.delete(path) if File.exist?(path)
      File.rename(tmp_path, path)
    end
  rescue => e
    puts "write_project_backup_json_files error: #{e.message}"
  end

  def self.hydrate_snapshot_from_json!(snap)
    path = ensure_snapshot_json_path!(snap)
    return snap if path.empty? || !File.exist?(path)

    payload = JSON.parse(File.read(path)) rescue nil
    data = payload.is_a?(Hash) ? (payload["snapshot"] || payload) : nil
    return snap unless data.is_a?(Hash)

    %w[file_created_at nesting_at exported_at items mat_items].each do |key|
      snap[key] = data[key] if data.key?(key)
    end
    Array(snap["items"]).each { |item| apply_snapshot_item_state!("acc", item) }
    Array(snap["mat_items"]).each { |item| apply_snapshot_item_state!("mat", item) }
    file_time = snapshot_json_file_time(path)
    snap["exported_at"] = file_time unless file_time.empty?
    snap
  rescue => e
    puts "hydrate_snapshot_from_json error: #{e.message}"
    snap
  end

  def self.project_name_for_path(skp_path)
    path = skp_path.to_s.strip
    return DEFAULT_PROJECT_NAME if path.empty?

    dir = File.dirname(path)
    return DEFAULT_PROJECT_NAME if dir.nil? || dir.empty? || dir == "."

    name = File.basename(dir).to_s.strip
    if ["SU", "SKP", "SKETCHUP", "MODEL", "MODELS", "SPEC", "EXCEL"].include?(name.upcase)
      parent_name = File.basename(File.dirname(dir)).to_s.strip
      name = parent_name unless parent_name.empty? || parent_name == "."
    end

    name.empty? ? DEFAULT_PROJECT_NAME : name
  end

  def self.skp_display_name(path_or_name)
    value = path_or_name.to_s.strip
    return "" if value.empty?
    File.basename(value, ".*")
  rescue
    path_or_name.to_s
  end

  def self.skp_file_role(path_or_name)
    name = skp_display_name(path_or_name).upcase
    return "NESTING" if name.include?("_NESTING")
    return "CNC" if name.include?("_CNC")
    "OTHER"
  rescue
    "OTHER"
  end

  def self.skp_cut_index(path_or_name)
    return nil unless skp_file_role(path_or_name) == "CNC"
    name = skp_display_name(path_or_name)
    return nil if name.empty?
    m = name.match(/\A\s*(\d+)\b/)
    m ? m[1].to_i : nil
  rescue
    nil
  end

  def self.snapshot_file_role(snap)
    return "OTHER" unless snap.is_a?(Hash)
    source = snap["skp_path"].to_s.strip
    source = snap["skp_name"].to_s if source.empty?
    skp_file_role(source)
  rescue
    "OTHER"
  end

  def self.snapshot_cut_label_from_file(path_or_name)
    return "Tính VL" if skp_file_role(path_or_name) == "NESTING"

    idx = skp_cut_index(path_or_name)
    idx ? "Cắt lần #{idx}" : ""
  rescue
    ""
  end

  def self.snapshot_label_sort_time(value)
    text = value.to_s.strip
    return nil if text.empty?

    report_date_time(text)
  rescue
    nil
  end

  def self.snapshot_label_sort_key(snap)
    path = snap["skp_path"].to_s
    [
      skp_cut_index(path) || 99_999,
      snapshot_label_sort_time(snapshot_file_created_at(snap)) || snapshot_label_sort_time(snap["exported_at"]) || Time.at(0),
      snap["skp_name"].to_s.downcase,
      path.downcase
    ]
  rescue
    [99_999, Time.at(0), "", ""]
  end

  def self.apply_snapshot_label_rules!
    return unless @file_snapshots.is_a?(Array)

    @file_snapshots.each do |snap|
      next unless snap.is_a?(Hash)
      snap["label"] = "Tính VL" if snapshot_file_role(snap) == "NESTING"
    end

    groups = {}
    @file_snapshots.each do |snap|
      next unless snap.is_a?(Hash)
      next unless snapshot_file_role(snap) == "CNC"

      project = snapshot_project(snap)
      groups[project] ||= []
      groups[project] << snap
    end

    groups.each_value do |snaps|
      snaps.sort_by { |snap| snapshot_label_sort_key(snap) }.each_with_index do |snap, index|
        snap["label"] = "Cắt lần #{index + 1}"
      end
    end
  rescue => e
    puts "apply_snapshot_label_rules error: #{e.message}"
  end

  def self.snapshot_project(snap)
    project = snap["project"].to_s.strip
    project.empty? ? project_name_for_path(snap["skp_path"]) : project
  end

  def self.project_name_match?(a, b)
    fix_vietnamese_mojibake(a).to_s.strip == fix_vietnamese_mojibake(b).to_s.strip
  end

  def self.abf_nesting_entities(entities, visited = {}, depth = 0, found = [])
    return found if entities.nil? || depth > 8
    entities.each do |entity|
      next if entity.respond_to?(:deleted?) && entity.deleted?
      name = ""
      name = entity.name.to_s if entity.respond_to?(:name)
      if name.empty? && entity.respond_to?(:definition) && entity.definition
        name = entity.definition.name.to_s
      end
      found << entity if name.upcase.include?("_ABF_NESTING")

      child_entities = nil
      if entity.respond_to?(:definition) && entity.definition && entity.definition.respond_to?(:entities)
        defn_id = entity.definition.object_id
        next if visited[defn_id]
        visited[defn_id] = true
        child_entities = entity.definition.entities
      elsif entity.respond_to?(:entities)
        child_entities = entity.entities
      end
      abf_nesting_entities(child_entities, visited, depth + 1, found) if child_entities
    end
    found
  rescue
    found || []
  end

  def self.current_nesting_finished_at
    model = Sketchup.active_model rescue nil
    return "" unless model
    nesting_entities = abf_nesting_entities(model.entities)
    return "" if nesting_entities.empty?

    now = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    times = nesting_entities.map do |entity|
      detected = entity.get_attribute("MH_Thongke", "nesting_detected_at").to_s rescue ""
      legacy = entity.get_attribute("MH_Thongke", "abf_nesting_created_at").to_s rescue ""
      detected = legacy if detected.empty? && !legacy.empty?
      if detected.empty?
        detected = now
        entity.set_attribute("MH_Thongke", "nesting_detected_at", detected) rescue nil
      end
      detected
    end
    latest = times.compact.map { |t| [report_date_time(t), t] }.select { |pair| pair[0] }.max_by { |pair| pair[0] }
    result = latest ? latest[1] : times.compact.last.to_s
    model.set_attribute("MH_Thongke", "abf_nesting_latest_at", result) rescue nil
    result
  rescue
    ""
  end

  def self.normalize_snapshots!(sync_local = true)
    @file_snapshots ||= []
    # Skip if already normalized for current snapshot set (saves 400ms/call).
    # Re-run when @file_snapshots is replaced (load_snapshots resets the marker).
    sig = [@file_snapshots.size, @file_snapshots.hash, sync_local ? 1 : 0].join(":")
    return if @file_snapshots_normalized_sig == sig

    sync_project_data_snapshots! if sync_local
    @file_snapshots.each do |snap|
      snap["project"] = snapshot_project(snap)
      role = snapshot_file_role(snap)
      snap["file_role"] = role
      ensure_snapshot_json_path!(snap)
      hydrate_snapshot_from_json!(snap) if sync_local
    end
    apply_snapshot_label_rules!
    @file_snapshots_normalized_sig = sig
  end

  def self.snapshot_from_json_file(path)
    payload = JSON.parse(File.read(path)) rescue nil
    return nil unless payload.is_a?(Hash)

    snap = payload["snapshot"].is_a?(Hash) ? payload["snapshot"] : payload
    return nil unless snap.is_a?(Hash)
    return nil if snap["skp_path"].to_s.strip.empty?

    snap = snap.dup
    snap["id"] = "#{File.mtime(path).to_i}_#{File.basename(path).hash.abs % 10_000}" if snap["id"].to_s.strip.empty?
    snap["skp_name"] = File.basename(snap["skp_path"].to_s) if snap["skp_name"].to_s.strip.empty?
    snap["project"] = snapshot_project(snap)
    snap["json_path"] = path
    file_time = snapshot_json_file_time(path)
    snap["exported_at"] = file_time unless file_time.empty?
    snap
  rescue => e
    puts "snapshot_from_json_file error: #{e.message}"
    nil
  end

  def self.refresh_snapshot_from_json_path!(snap_id, json_path = nil)
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    snap = (@file_snapshots || []).find { |item| item["id"].to_s == snap_id.to_s }
    raise "Không tìm thấy dòng file trong tab FILE." unless snap

    path = json_path.to_s.strip
    path = snap["json_path"].to_s.strip if path.empty?
    raise "Chưa có đường dẫn file JSON." if path.empty?
    raise "Không tìm thấy file JSON:\n#{path}" unless File.exist?(path)

    loaded = snapshot_from_json_file(path)
    raise "File JSON không đúng dạng dữ liệu lần cắt MH_Thongke." unless loaded

    keep_id = snap["id"].to_s
    snap.merge!(loaded)
    snap["id"] = keep_id unless keep_id.empty?
    snap["json_path"] = path
    snap["project"] = snapshot_project(snap)
    snap
  end

  def self.sync_project_data_snapshots!
    return if @syncing_project_data_snapshots

    @syncing_project_data_snapshots = true
    dirs = []
    current_dir = current_project_data_dir
    dirs << current_dir unless current_dir.to_s.empty?
    (@file_snapshots || []).each do |snap|
      dir = snapshot_project_data_dir_for(snap["skp_path"])
      dirs << dir unless dir.to_s.empty?
    end

    dirs.uniq.each do |dir|
      next unless File.directory?(dir)

      Dir.glob(File.join(dir, "*.{json,JSON}")).each do |path|
        snap = snapshot_from_json_file(path)
        next unless snap

        existing = (@file_snapshots || []).find do |item|
          normalized_skp_path(item["skp_path"]) == normalized_skp_path(snap["skp_path"]) ||
            (!item["id"].to_s.empty? && item["id"].to_s == snap["id"].to_s)
        end
        existing ? existing.merge!(snap) : @file_snapshots << snap
      end
    end
  ensure
    @syncing_project_data_snapshots = false
  end

  def self.default_cut_label(project)
    normalize_snapshots!
    count = @file_snapshots.count do |snap|
      project_name_match?(snapshot_project(snap), project) && snapshot_file_role(snap) == "CNC"
    end
    "Cắt lần #{count + 1}"
  end

  def self.normalized_skp_path(path)
    path.to_s.tr("\\", "/").downcase
  end

  def self.find_snapshot_by_path(skp_path)
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    target = normalized_skp_path(skp_path)
    @file_snapshots.find { |snap| normalized_skp_path(snap["skp_path"]) == target }
  end

  def self.current_project_name
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    normalize_snapshots!
    model_path = (Sketchup.active_model.path rescue "").to_s
    exact = find_snapshot_by_path(model_path) unless model_path.empty?
    return snapshot_project(exact) if exact

    inferred = project_name_for_path(model_path)
    saved = (@file_snapshots || []).find { |snap| project_name_match?(snapshot_project(snap), inferred) }
    return snapshot_project(saved) if saved

    inferred.empty? ? DEFAULT_PROJECT_NAME : inferred
  rescue
    DEFAULT_PROJECT_NAME
  end

  # Persist PK status in snapshot using Mini Import-aligned logic.
  def self.snapshot_pk_status_text(row)
    status =
      if respond_to?(:report_row_status_key)
        report_row_status_key(row)
      elsif respond_to?(:status_text)
        status_text(row[:trang_thai])
      else
        row[:trang_thai].to_s.strip.upcase
      end
    return status unless status.to_s.strip.empty?

    return "THIEU" if row[:is_missing]

    product_code = row[:actual_product] || row[:product]
    if respond_to?(:resolve_mini_model_only_status_key)
      derived = resolve_mini_model_only_status_key(product_code, "PK", row[:name].to_s)
      return derived unless derived.to_s.strip.empty?
    end

    "OK"
  rescue
    row[:is_missing] ? "THIEU" : "OK"
  end

  def self.current_live_snapshot
    report_items = @current_report_items || []
    mat_items = @current_mat_items || []
    return nil if report_items.empty? && mat_items.empty?

    model = Sketchup.active_model rescue nil
    skp_path = (model.path rescue "").to_s
    skp_name = skp_path.empty? ? "File dang mo" : File.basename(skp_path)
    existing = skp_path.empty? ? nil : find_snapshot_by_path(skp_path)
    project = current_project_name
    auto_label = snapshot_cut_label_from_file(skp_path)
    label = existing ? existing["label"].to_s : (auto_label.empty? ? "File hien tai" : auto_label)
    now = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    nesting_finished_at = current_nesting_finished_at

    items_data = report_items.map do |d|
      cu = d[:_resolved_unit] || d[:unit]
      qty = d[:_resolved_qty] || d[:count]
      {
        "name"          => d[:name],
        "product"       => d[:actual_product] || d[:product],
        "ten_sp"        => snapshot_resolved_ten_sp(d, d[:actual_product] || d[:product]),
        "qty"           => qty,
        "unit"          => cu,
        "kich_thuoc"    => d[:kich_thuoc].to_s,
        "ghi_chu"       => d[:ghi_chu].to_s,
        "ngay_dat"      => normalize_order_date(d[:ngay_dat]),
        "layer"         => d[:layer].to_s,
        "last_modified" => d[:last_modified].to_s,
        "type"          => d[:type].to_s,
        "trang_thai"    => snapshot_pk_status_text(d),
        "is_missing"    => !!d[:is_missing],
        "layer_tags"    => Array(d[:layer_tags]).map(&:to_s),
        "obj_count"     => Array(d[:stat_entities]).size,
        "has_obj"       => Array(d[:stat_entities]).any?
      }
    end

    mat_data = mat_items.map do |d|
      {
        "name"     => d[:name],
        "product"  => d[:actual_product] || d[:product],
        "ten_sp"   => snapshot_resolved_ten_sp(d, d[:actual_product] || d[:product]),
        "qty"      => d[:count],
        "unit"     => d[:unit],
        "kich_thuoc" => d[:thickness].to_s,
        "ghi_chu"  => d[:ghi_chu].to_s,
        "ngay_dat" => normalize_order_date(d[:ngay_dat]),
        "layer"    => d[:layer].to_s,
        "last_modified" => d[:last_modified].to_s,
        "trang_thai" => d[:trang_thai].to_s,
        "type"     => "material",
        "is_missing" => !!d[:is_missing],
        "layer_tags" => Array(d[:layer_tags]).map(&:to_s),
        "completion_percent" => d[:completion_percent],
        "completion_text" => d[:completion_text].to_s,
        "obj_count"  => Array(d[:stat_entities]).size,
        "has_obj"    => Array(d[:stat_entities]).any?
      }
    end

    {
      "id"          => "__live_current__",
      "project"     => project,
      "label"       => label,
      "skp_path"    => skp_path,
      "skp_name"    => skp_name,
      "file_created_at" => skp_path.empty? || !File.exist?(skp_path) ? "" : File.ctime(skp_path).strftime("%Y-%m-%d %H:%M:%S"),
      "nesting_at"  => nesting_finished_at,
      "exported_at" => existing ? existing["exported_at"].to_s : now,
      "json_path"   => existing ? existing["json_path"].to_s : "",
      "live"        => true,
      "items"       => items_data,
      "mat_items"   => mat_data
    }
  rescue => e
    puts "current_live_snapshot error: #{e.message}"
    nil
  end

  def self.snapshot_project_root_dir_for_path(path)
    text = path.to_s.strip
    return "" if text.empty?
    dir = File.dirname(text)
    return "" if dir.to_s.empty? || dir == "."

    leaf = File.basename(dir).to_s.strip.upcase
    root = if ["SU", "SKP", "SPEC", "EXCEL", "MODEL", "MODELS", "SKETCHUP"].include?(leaf)
      File.dirname(dir)
    else
      dir
    end
    normalized_skp_path(root)
  rescue
    ""
  end

  def self.snapshots_for_current_project(include_live_current = false)
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    normalize_snapshots!
    project = current_project_name

    # Cache: called many times during update_html. Invalidate when snapshots change.
    cache_key = [project, include_live_current ? 1 : 0, Array(@file_snapshots).size, Array(@file_snapshots).map { |s| s["id"].to_s }.join(",")].join("::")
    @snapshots_for_current_project_cache ||= {}
    return @snapshots_for_current_project_cache[cache_key] if @snapshots_for_current_project_cache.key?(cache_key)
    @snapshots_for_current_project_cache.clear if @snapshots_for_current_project_cache.size > 8

    snapshots = (@file_snapshots || []).select { |snap| project_name_match?(snapshot_project(snap), project) }
    active_model_path = (Sketchup.active_model.path rescue "").to_s
    active_root = snapshot_project_root_dir_for_path(active_model_path)
    if !active_root.empty?
      rooted = snapshots.select do |snap|
        snap_root = snapshot_project_root_dir_for_path(snap["skp_path"])
        !snap_root.empty? && snap_root == active_root
      end
      snapshots = rooted unless rooted.empty?
    end
    unless include_live_current
      return @snapshots_for_current_project_cache[cache_key] = snapshots
    end

    live = current_live_snapshot
    return @snapshots_for_current_project_cache[cache_key] = snapshots unless live

    live_path = normalized_skp_path(live["skp_path"])
    replaced = false
    snapshots = snapshots.map do |snap|
      if !live_path.empty? && normalized_skp_path(snap["skp_path"]) == live_path
        replaced = true
        live
      else
        snap
      end
    end
    snapshots << live unless replaced
    @snapshots_for_current_project_cache[cache_key] = snapshots
  end

  def self.project_total_source_snapshots
    cache_key = [(@file_snapshots || []).size, (@file_snapshots || []).map { |s| s["id"].to_s }.join(",")].join("::")
    @project_total_source_snapshots_cache ||= {}
    return @project_total_source_snapshots_cache[cache_key] if @project_total_source_snapshots_cache.key?(cache_key)
    @project_total_source_snapshots_cache.clear if @project_total_source_snapshots_cache.size > 4

    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    normalize_snapshots!
    @project_total_source_snapshots_cache[cache_key] = snapshots_for_current_project.select { |snap| !respond_to?(:snapshot_file_role) || snapshot_file_role(snap) == "CNC" }
                                 .sort_by { |snap| [snap["label"].to_s, snap["skp_name"].to_s] }
  rescue
    []
  end

  def self.project_total_source_snapshots_for_kind(kind = :items)
    key = kind.to_s == "mat_items" || kind.to_s == "materials" ? "mat_items" : "items"
    snapshots = snapshots_for_current_project(false)
    sort_snapshots = lambda do |rows|
      rows.sort_by { |snap| [respond_to?(:snapshot_label_sort_key) ? snapshot_label_sort_key(snap["label"]) : snap["label"].to_s, snap["skp_name"].to_s] }
    end
    has_data = lambda { |snap| Array(snap[key]).any? { |item| item.is_a?(Hash) } }

    cnc = snapshots.select { |snap| (!respond_to?(:snapshot_file_role) || snapshot_file_role(snap) == "CNC") && has_data.call(snap) }
    nesting = snapshots.select { |snap| (!respond_to?(:snapshot_file_role) || snapshot_file_role(snap) == "NESTING") && has_data.call(snap) }
    cnc.empty? ? sort_snapshots.call(nesting) : sort_snapshots.call(cnc)
  rescue
    []
  end

  def self.project_total_source_rows(kind = :items)
    key = kind.to_s == "mat_items" || kind.to_s == "materials" ? "mat_items" : "items"
    cache_key = [key, (@file_snapshots || []).size, (@file_snapshots || []).map { |s| s["id"].to_s }.join(",")].join("::")
    @project_total_source_rows_cache ||= {}
    return @project_total_source_rows_cache[cache_key] if @project_total_source_rows_cache.key?(cache_key)
    @project_total_source_rows_cache.clear if @project_total_source_rows_cache.size > 8

    if key != "items"
      return @project_total_source_rows_cache[cache_key] = project_total_source_snapshots_for_kind(kind).flat_map { |snap| Array(snap[key]).select { |item| item.is_a?(Hash) } }
    end

    snapshots = snapshots_for_current_project(false)
    rows_for_role = lambda do |role|
      snapshots.flat_map do |snap|
        next [] unless !respond_to?(:snapshot_file_role) || snapshot_file_role(snap) == role

        Array(snap["items"]).select { |item| item.is_a?(Hash) }
      end
    end

    family = lambda do |row|
      row_type = (row["type"] || row[:type]).to_s
      row_type == "phaochi" ? :phaochi : :regular
    end

    cnc_rows = rows_for_role.call("CNC")
    nesting_rows = rows_for_role.call("NESTING")
    product_key = lambda do |row|
      product = (row["product"] || row[:product]).to_s.strip.upcase
      product.empty? ? "--" : product
    end

    out = []
    [:regular, :phaochi].each do |family_key|
      cnc_by_product = {}
      nesting_by_product = {}
      cnc_rows.select { |row| family.call(row) == family_key }.each do |row|
        (cnc_by_product[product_key.call(row)] ||= []) << row
      end
      nesting_rows.select { |row| family.call(row) == family_key }.each do |row|
        (nesting_by_product[product_key.call(row)] ||= []) << row
      end

      (cnc_by_product.keys + nesting_by_product.keys).uniq.sort.each do |prod|
        chosen = cnc_by_product[prod]
        chosen = nesting_by_product[prod] if chosen.nil? || chosen.empty?
        out.concat(Array(chosen))
      end
    end
    @project_total_source_rows_cache[cache_key] = out
  rescue
    []
  end

  def self.project_total_source_runtime_rows(kind = :items)
    source_kind = kind.to_s == "mat_items" || kind.to_s == "materials" ? :mat_items : :items
    project_total_source_rows(source_kind).map { |row| snapshot_row_to_runtime_row(row, source_kind) }.compact
  rescue
    []
  end

  def self.snapshot_row_to_runtime_row(row, kind = :items)
    get = lambda { |key| row[key.to_s] || row[key.to_sym] }
    type = get.call(:type).to_s
    type = kind.to_s == "mat_items" ? "material" : "count" if type.empty?
    qty = get.call(:qty).to_f
    runtime = {
      name: fix_vietnamese_mojibake(get.call(:name)).to_s,
      product: get.call(:product).to_s,
      actual_product: get.call(:product).to_s,
      ten_sp: fix_vietnamese_mojibake(get.call(:ten_sp)).to_s,
      count: 0.0,
      sel_count: 0,
      length: 0.0,
      sel_length: 0.0,
      len_total_mm: 0.0,
      sel_len_mm: 0.0,
      unit: fix_vietnamese_mojibake(get.call(:unit)).to_s,
      layer: fix_vietnamese_mojibake(get.call(:layer)).to_s,
      ghi_chu: fix_vietnamese_mojibake(get.call(:ghi_chu)).to_s,
      ngay_dat: get.call(:ngay_dat).to_s,
      last_modified: get.call(:last_modified).to_s,
      trang_thai: get.call(:trang_thai).to_s,
      kich_thuoc: fix_vietnamese_mojibake(get.call(:kich_thuoc)).to_s,
      layer_tags: Array(get.call(:layer_tags)).map { |v| fix_vietnamese_mojibake(v).to_s },
      completion_percent: get.call(:completion_percent),
      completion_text: get.call(:completion_text).to_s,
      type: type.to_sym,
      is_missing: !!get.call(:is_missing),
      stat_entities: [],
      entities: [],
      virtual_source: :project_total
    }
    unit_text = runtime[:unit].to_s.downcase
    if type == "length"
      length_mm = ["m", "md"].include?(unit_text) ? qty * 1000.0 : qty
      runtime[:length] = length_mm / 25.4
    elsif type == "phaochi"
      runtime[:len_total_mm] = qty * 1000.0
    else
      runtime[:count] = qty
      runtime[:type] = :material if kind.to_s == "mat_items"
    end
    runtime
  rescue
    nil
  end

  def self.snapshot_priority_row_key(row)
    return "" unless row.is_a?(Hash)

    norm = lambda do |value|
      text = fix_vietnamese_mojibake(value).to_s.strip
      if respond_to?(:cached_norm)
        cached_norm(text)
      else
        text.downcase
      end
    rescue
      value.to_s.strip.downcase
    end

    product = (row[:actual_product] || row[:product]).to_s.strip.upcase
    name = norm.call(row[:name])
    kind = row[:type].to_s.strip.downcase
    unit = norm.call(row[:unit])
    spec = norm.call(row[:kich_thuoc])
    [product, name, kind, unit, spec].join("|")
  rescue
    ""
  end

  def self.fill_snapshot_missing_fields!(target, source)
    return target unless target.is_a?(Hash) && source.is_a?(Hash)

    # Snapshot uu tien: cho phep bo sung/ghi de so luong hop ly khi target chua co du lieu.
    if target[:type].to_s == "material" || target[:type].to_s == "count"
      if target[:count].to_f <= 0 && source[:count].to_f > 0
        target[:count] = source[:count].to_f
      end
    elsif target[:type].to_s == "length"
      if target[:length].to_f <= 0 && source[:length].to_f > 0
        target[:length] = source[:length].to_f
      end
    elsif target[:type].to_s == "phaochi"
      if target[:len_total_mm].to_f <= 0 && source[:len_total_mm].to_f > 0
        target[:len_total_mm] = source[:len_total_mm].to_f
      end
    end

    %i[ten_sp ghi_chu ngay_dat trang_thai last_modified kich_thuoc layer unit].each do |key|
      next unless target[key].to_s.strip.empty?
      next if source[key].to_s.strip.empty?
      target[key] = source[key]
    end

    target[:stat_entities] = Array(source[:stat_entities]) if Array(target[:stat_entities]).empty? && !Array(source[:stat_entities]).empty?
    target[:entities] = Array(source[:entities]) if Array(target[:entities]).empty? && !Array(source[:entities]).empty?
    target
  rescue
    target
  end

  def self.preferred_snapshot_for_tables(snapshots = nil)
    snapshots = Array(snapshots || project_total_source_snapshots)
    return nil if snapshots.empty?

    preferred = pk_report_cut_source.to_s
    if preferred.start_with?("snap:")
      preferred_id = preferred.sub(/\Asnap:/, "").strip
      hit = snapshots.find { |snap| snap["id"].to_s == preferred_id }
      return hit if hit
    end

    model_path = normalized_skp_path((Sketchup.active_model.path rescue "").to_s)
    unless model_path.empty?
      hit = snapshots.find { |snap| normalized_skp_path(snap["skp_path"]) == model_path }
      return hit if hit
    end

    snapshots.first
  rescue
    snapshots.first
  end

  def self.snapshot_runtime_rows_for_snapshot(snap, kind = :items)
    return [] unless snap.is_a?(Hash)
    source_kind = kind.to_s == "mat_items" || kind.to_s == "materials" ? :mat_items : :items
    key = source_kind == :mat_items ? "mat_items" : "items"
    Array(snap[key]).map { |row| snapshot_row_to_runtime_row(row, source_kind) }.compact
  rescue
    []
  end

  # Luon dua snapshot FILE vao bang chinh:
  # - Uu tien nguon _CNC theo tung nhom du lieu; chi fallback _NESTING khi _CNC
  #   khong co bat ky dong nao cho nhom do, tranh tron 2 nguon gay duplicate.
  # - JSON-only: khong lay du lieu live tu model dang mo de tinh bang.
  def self.merged_priority_snapshot_runtime_rows(base_rows, kind = :items)
    source_rows = project_total_source_runtime_rows(kind)
    return [] if source_rows.empty?

    out = []
    seen = {}
    append = lambda do |rows|
      rows.each do |row|
        key = snapshot_priority_row_key(row)
        if key.empty?
          out << row
          next
        end
        existing = seen[key]
        if existing
          fill_snapshot_missing_fields!(existing, row)
        else
          clone = row.dup
          out << clone
          seen[key] = clone
        end
      end
    end

    append.call(source_rows)
    out
  rescue
    []
  end

  def self.export_snapshot(skp_path, skp_name, label, project = nil)
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    project = project.to_s.strip
    project = project_name_for_path(skp_path) if project.empty?

    items_data = (@current_report_items || []).map do |d|
      is_phaochi = d[:type].to_s == "phaochi"
      cu = is_phaochi ? "md" : (d[:_resolved_unit] || d[:unit])
      qty = if is_phaochi
        d[:len_total_mm].to_f / 1000.0
      else
        d[:_resolved_qty] || d[:count]
      end
      {
        "name"          => d[:name],
        "product"       => d[:actual_product] || d[:product],
        "ten_sp"        => snapshot_resolved_ten_sp(d, d[:actual_product] || d[:product]),
        "qty"           => qty,
        "unit"          => cu,
        "kich_thuoc"    => d[:kich_thuoc].to_s,
        "ghi_chu"       => d[:ghi_chu].to_s,
        "ngay_dat"      => normalize_order_date(d[:ngay_dat]),
        "layer"         => d[:layer].to_s,
        "last_modified" => d[:last_modified].to_s,
        "type"          => d[:type].to_s,
        "trang_thai"    => snapshot_pk_status_text(d),
        "is_missing"    => !!d[:is_missing],
        "layer_tags"    => Array(d[:layer_tags]).map(&:to_s),
        "obj_count"     => Array(d[:stat_entities]).size,
        "has_obj"       => Array(d[:stat_entities]).any?
      }
    end

    mat_data = (@current_mat_items || []).map do |d|
      {
        "name"     => d[:name],
        "product"  => d[:actual_product] || d[:product],
        "ten_sp"   => snapshot_resolved_ten_sp(d, d[:actual_product] || d[:product]),
        "qty"      => d[:count],
        "unit"     => d[:unit],
        "kich_thuoc" => d[:thickness].to_s,
        "ghi_chu"  => d[:ghi_chu].to_s,
        "ngay_dat" => normalize_order_date(d[:ngay_dat]),
        "layer"    => d[:layer].to_s,
        "last_modified" => d[:last_modified].to_s,
        "trang_thai" => d[:trang_thai].to_s,
        "type"     => "material",
        "is_missing" => !!d[:is_missing],
        "layer_tags" => Array(d[:layer_tags]).map(&:to_s),
        "completion_percent" => d[:completion_percent],
        "completion_text" => d[:completion_text].to_s,
        "obj_count"  => Array(d[:stat_entities]).size,
        "has_obj"    => Array(d[:stat_entities]).any?
      }
    end

    existing = find_snapshot_by_path(skp_path)
    role = skp_file_role(skp_path)
    auto_label = snapshot_cut_label_from_file(skp_path)
    final_label = if role == "NESTING"
      "Tính VL"
    elsif role == "CNC" && !auto_label.empty?
      auto_label
    else
      label
    end
    entry = {
      "id"          => existing ? existing["id"] : "#{Time.now.to_i}_#{rand(9999)}",
      "project"     => project,
      "label"       => final_label,
      "skp_path"    => skp_path,
      "skp_name"    => skp_name,
      "file_role"   => role,
      "file_created_at" => (File.exist?(skp_path) ? File.ctime(skp_path).strftime("%Y-%m-%d %H:%M:%S") : ""),
      "nesting_at"  => current_nesting_finished_at,
      "exported_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      "json_path"   => existing ? existing["json_path"].to_s : "",
      "items"       => items_data,
      "mat_items"   => mat_data
    }
    ensure_snapshot_json_path!(entry)
    save_snapshot_entry_only(entry) || entry
  end

  def self.export_current_snapshot_from_current_cache
    model = Sketchup.active_model rescue nil
    return nil unless model

    skp_path = model.path.to_s
    return nil if skp_path.empty?

    skp_name = File.basename(skp_path)
    existing = find_snapshot_by_path(skp_path)
    project = existing ? snapshot_project(existing) : project_name_for_path(skp_path)
    auto_label = snapshot_cut_label_from_file(skp_path)
    label = existing ? existing["label"].to_s : (auto_label.empty? ? default_cut_label(project) : auto_label)
    export_snapshot(skp_path, skp_name, label, project)
  rescue => e
    puts "export_current_snapshot_from_current_cache error: #{e.class}: #{e.message}"
    nil
  end

  def self.export_current_snapshot_for_saved_model
    model = Sketchup.active_model rescue nil
    return nil unless model

    skp_path = model.path.to_s
    return nil if skp_path.empty?

    process_status = nil
    if @skip_next_snapshot_export_process
      @skip_next_snapshot_export_process = false
      process_status = @process_selection_last_status || :cached
    elsif respond_to?(:process_selection_cached)
      process_status = process_selection_cached(true, "save_snapshot")
    else
      process_selection
      process_status = :full_scan
    end

    skp_name = File.basename(skp_path)
    existing = find_snapshot_by_path(skp_path)
    project = existing ? snapshot_project(existing) : project_name_for_path(skp_path)
    auto_label = snapshot_cut_label_from_file(skp_path)
    label = existing ? existing["label"].to_s : (auto_label.empty? ? default_cut_label(project) : auto_label)
    snap = export_snapshot(skp_path, skp_name, label, project)
    p4_delta_clear_changed if process_status == :full_scan && respond_to?(:p4_delta_clear_changed)
    snap
  rescue => e
    puts "export_current_snapshot_for_saved_model error: #{e.class}: #{e.message}"
    nil
  end

  def self.report_product_code(value)
    text = value.to_s.strip
    code = respond_to?(:product_codes_from_text) ? product_codes_from_text(text).first : nil
    code.to_s
  end

  def self.report_date_time(value)
    text = value.to_s.strip
    return nil if text.empty?
    patterns = [
      "%Y-%m-%d %H:%M:%S",
      "%Y-%m-%d",
      "%d/%m/%Y %H:%M:%S",
      "%d/%m/%Y %H:%M",
      "%d/%m/%y %H:%M:%S",
      "%d/%m/%y %H:%M",
      "%d/%m/%Y",
      "%d/%m/%y",
      "%d-%m-%Y",
      "%d-%m-%y"
    ]
    patterns.each do |fmt|
      begin
        return Time.strptime(text, fmt)
      rescue
      end
    end
    nil
  end

  def self.report_date_display(time_or_text)
    return time_or_text.strftime("%d/%m/%Y") if time_or_text.is_a?(Time)
    normalized = normalize_order_date(time_or_text)
    time = report_date_time(normalized)
    time ? time.strftime("%d/%m/%Y") : normalized.to_s
  end

  def self.report_blocked_note?(text)
    norm = cached_norm(fix_vietnamese_mojibake(text))
    REPORT_BLOCK_KEYWORDS.any? { |kw| norm.include?(kw) }
  rescue
    false
  end

  def self.snapshot_file_created_at(snap)
    stored = snap["file_created_at"].to_s
    return stored unless stored.empty?

    path = snap["skp_path"].to_s
    File.exist?(path) ? File.ctime(path).strftime("%Y-%m-%d %H:%M:%S") : ""
  rescue
    ""
  end

  def self.project_report_rows
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    normalize_snapshots!
    rows = []
    excel_name_cache = {}
    excel_loaded = false
    resolve_ten_sp = lambda do |product, current_name|
      name = fix_vietnamese_mojibake(current_name).to_s.strip
      return name unless name.empty?
      return "" unless respond_to?(:import_excel_product_name_for)
      unless excel_loaded
        load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)
        excel_loaded = true
      end
      code = product.to_s.strip
      return "" if code.empty?
      return excel_name_cache[code] if excel_name_cache.key?(code)
      excel_name_cache[code] = fix_vietnamese_mojibake(import_excel_product_name_for(code, false)).to_s.strip
    rescue
      ""
    end

    snapshots_for_current_project(false).each do |snap|
      project = snapshot_project(snap)
      cut = snap["label"].to_s
      file_name = snap["skp_name"].to_s
      start_cnc = snapshot_file_created_at(snap)
      finish_cnc = snap["nesting_at"].to_s.empty? ? snap["exported_at"].to_s : snap["nesting_at"].to_s
      products = {}

      (snap["items"] || []).each do |item|
        product = report_product_code(item["product"])
        next if product.empty?
        products[product] ||= { pk: [], vl: [], ten_sp: "" }
        products[product][:pk] << item
        products[product][:ten_sp] = item["ten_sp"].to_s if products[product][:ten_sp].to_s.empty?
      end
      (snap["mat_items"] || []).each do |item|
        product = report_product_code(item["product"])
        next if product.empty?
        products[product] ||= { pk: [], vl: [], ten_sp: "" }
        products[product][:vl] << item
        products[product][:ten_sp] = item["ten_sp"].to_s if products[product][:ten_sp].to_s.empty?
      end

      products.keys.sort_by { |p| p.split(/(\d+)/).map { |s| s =~ /\d/ ? [1, s.to_i] : [0, s.downcase] } }.each do |product|
        info = products[product]
        ten_sp_name = resolve_ten_sp.call(product, info[:ten_sp])
        pk_items = info[:pk]
        vl_items = info[:vl]
        all_items = pk_items + vl_items
        blocked_items = all_items.select { |item| report_blocked_note?(item["ghi_chu"]) }
        pk_with_date = pk_items.select { |item| !item["ngay_dat"].to_s.strip.empty? }
        date_values = pk_items.map { |item| report_date_time(item["ngay_dat"]) }.compact
        latest_dmvt = date_values.max
=begin legacy_status_block_disabled

            "Vướng thông tin"
          elsif vl_items.empty?
            "Đang làm CNC"
          else
            "Xong CNC"
          end

          if !pk_blocked.empty?
            "Thiếu thông tin"
          elsif pk_items.empty? || pk_with_date.size == pk_items.size
            "Xong định mức"
          elsif pk_with_date.any?
            "Đang định mức"
          else
            "Đang định mức"
          end

=end
        # Shared status resolver for all report views.
        has_nesting = !snap["nesting_at"].to_s.strip.empty?
        cnc_status = project_cnc_status_text(has_nesting, product, vl_items, !blocked_items.empty?, all_items)
        dmvt_status = project_dmvt_status_text(pk_items)

        notes = []
        notes << "PK: #{pk_with_date.size}/#{pk_items.size} có ngày đặt" unless pk_items.empty?
        notes << "Chưa có dữ liệu CNC" if vl_items.empty?
        blocked_items.each do |item|
          name = fix_vietnamese_mojibake(item["name"]).to_s
          note = fix_vietnamese_mojibake(item["ghi_chu"]).to_s
          notes << "#{name}: #{note}" unless note.empty?
        end

        rows << {
          project: project,
          cut: cut,
          file_name: file_name,
          file_path: snap["skp_path"].to_s,
          product: product,
          ten_sp: ten_sp_name,
          start_cnc: report_date_display(start_cnc),
          finish_cnc: cnc_status == "Xong CNC" ? report_date_display(finish_cnc) : "",
          cnc_status: cnc_status,
          dmvt_status: dmvt_status,
          dmvt_done_date: latest_dmvt ? latest_dmvt.strftime("%d/%m/%Y") : "",
          pk_total: pk_items.size,
          pk_ordered: pk_with_date.size,
          vl_total: vl_items.size,
          note: notes.uniq.join("; ")
        }
      end
    end
    append_project_report_excel_only_rows!(rows, resolve_ten_sp)
    sort_project_report_rows!(rows)
    rows
  end

  def self.append_project_report_excel_only_rows!(rows, resolve_ten_sp = nil)
    return rows unless rows.is_a?(Array)

    excel_products = []
    excel_product_names = {}
    begin
      load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only) && (@imported_excel_data.nil? || @imported_excel_data.empty?)
      Array(@imported_excel_data).each do |row|
        next unless row.is_a?(Hash)

        raw_code = row[:ma_sp] || row["ma_sp"] || row[:product] || row["product"]
        code = report_product_code(raw_code)
        code = raw_code.to_s.strip.upcase if code.to_s.strip.empty?
        next unless product_code_valid?(code) rescue code =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i

        code = code.upcase
        excel_products << code unless excel_products.include?(code)
        name = fix_vietnamese_mojibake(row[:ten_sp] || row["ten_sp"]).to_s.strip
        excel_product_names[code] = name unless name.empty?
      end
    rescue => e
      puts "append_project_report_excel_only_rows load Excel error: #{e.message}" rescue nil
      return rows
    end

    present = rows.map { |row| row[:product].to_s.upcase }.uniq
    current_project = respond_to?(:current_project_name) ? current_project_name.to_s : ""
    excel_products.each do |code|
      next if present.include?(code)

      ten_sp = excel_product_names[code].to_s
      ten_sp = resolve_ten_sp.call(code, ten_sp) if resolve_ten_sp.respond_to?(:call)
      rows << {
        project: current_project,
        cut: "--",
        file_name: "--",
        file_path: "",
        product: code,
        ten_sp: ten_sp.to_s,
        start_cnc: "",
        finish_cnc: "",
        cnc_status: "",
        dmvt_status: "",
        dmvt_done_date: "",
        pk_total: 0,
        pk_ordered: 0,
        vl_total: 0,
        note: "Chưa có thông tin trong JSON dự án"
      }
      present << code
    end

    rows
  rescue => e
    puts "append_project_report_excel_only_rows error: #{e.message}" rescue nil
    rows
  end

  def self.sort_project_report_rows!(rows, sort_mode = nil)
    return rows unless rows.is_a?(Array)

    mode = sort_mode.to_s.upcase
    mode = @project_total_sort.to_s.upcase if mode.empty?
    mode = project_total_sort.to_s.upcase if mode.empty? && respond_to?(:project_total_sort)
    mode = "CUT" unless ["CUT", "PRODUCT"].include?(mode)

    product_key = lambda do |product|
      respond_to?(:product_code_sort_key) ? product_code_sort_key(product) : product.to_s.split(/(\d+)/).map { |part| part =~ /\d/ ? [1, part.to_i] : [0, part.downcase] }
    end
    cut_key = lambda do |cut|
      text = cut.to_s.strip
      nums = text.scan(/\d+/).map(&:to_i)
      [nums.empty? ? 1 : 0, nums, text]
    end

    rows.sort_by! do |row|
      if mode == "PRODUCT"
        [product_key.call(row[:product]), cut_key.call(row[:cut]), row[:file_name].to_s]
      else
        [cut_key.call(row[:cut]), row[:file_name].to_s, product_key.call(row[:product])]
      end
    end
    rows
  rescue => e
    puts "sort_project_report_rows error: #{e.message}" rescue nil
    rows
  end

  def self.export_project_report_xlsx(path)
    rows = project_report_rows
    headers = [
      "Dự án", "Lần cắt", "File", "Mã SP", "Tên SP",
      "Ngày bắt đầu CNC", "Ngày kết thúc CNC", "Trạng thái CNC",
      "Ngày xong DMVT", "Trạng thái DMVT",
      "Tổng PK", "PK đã đặt", "Tổng VL", "Ghi chú"
    ]

    sheet_rows = [headers]
    rows.each do |row|
      sheet_rows << [
        row[:project], row[:cut], row[:file_name], row[:product], row[:ten_sp],
        row[:start_cnc], row[:finish_cnc], row[:cnc_status],
        row[:dmvt_done_date], row[:dmvt_status],
        row[:pk_total], row[:pk_ordered], row[:vl_total], row[:note]
      ]
    end
    MH::ExcelBridge.write(path, sheets: { "Bao cao CNC DMVT" => sheet_rows })
    rows.size
  rescue => e
    raise e
  end

  def self.delete_snapshot(snap_id, json_path = nil, skp_path = nil)
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    @file_snapshots ||= []

    id_key = snap_id.to_s.strip
    json_key = normalized_skp_path(json_path.to_s)
    skp_key = normalized_skp_path(skp_path.to_s)

    removed = []
    unless id_key.empty?
      removed = @file_snapshots.select { |snap| snap["id"].to_s.strip == id_key }
    end

    if removed.empty? && !json_key.empty?
      removed = @file_snapshots.select do |snap|
        snap_json = snap["json_path"].to_s.strip
        snap_json = ensure_snapshot_json_path!(snap) if snap_json.empty?
        normalized_skp_path(snap_json) == json_key
      end
    end

    if removed.empty? && !skp_key.empty?
      removed = @file_snapshots.select { |snap| normalized_skp_path(snap["skp_path"]) == skp_key }
    end

    return 0 if removed.empty?

    removed_ids = removed.map { |snap| snap["id"].to_s.strip }.reject(&:empty?).uniq
    removed_json_paths = removed.map do |snap|
      path = snap["json_path"].to_s.strip
      path = snapshot_json_path_for(snap) if path.empty?
      normalized_skp_path(path)
    end.reject(&:empty?).uniq
    removed_skp_paths = removed.map { |snap| normalized_skp_path(snap["skp_path"]) }.reject(&:empty?).uniq

    @file_snapshots.reject! do |snap|
      sid = snap["id"].to_s.strip
      sjson = snap["json_path"].to_s.strip
      sjson = snapshot_json_path_for(snap) if sjson.empty?
      sjson = normalized_skp_path(sjson)
      sskp = normalized_skp_path(snap["skp_path"])
      removed_ids.include?(sid) || removed_json_paths.include?(sjson) || removed_skp_paths.include?(sskp)
    end

    removed.each do |snap|
      path = snap["json_path"].to_s.strip
      path = snapshot_json_path_for(snap) if path.empty?
      File.delete(path) if !path.empty? && File.exist?(path)
    rescue => e
      puts "delete snapshot json error: #{e.message}"
    end
    save_snapshots
    removed.size
  end

end
