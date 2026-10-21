# encoding: utf-8
# MH_Thongke â€” Config & Constants
# TÃ¡ch tá»« main.rb: dÃ²ng 1â€“37, 121â€“133, 629â€“636

require 'sketchup.rb'
require 'fileutils'
require 'json'
require 'set'
require 'date'

module MH_Thongke
  ROOT_DIR = defined?(DIR) ? DIR : File.expand_path("..", __dir__) unless defined?(ROOT_DIR)
  CORE_DIR = File.join(ROOT_DIR, "core") unless defined?(CORE_DIR)
  ENGINE_DIR = File.join(ROOT_DIR, "engine") unless defined?(ENGINE_DIR)
  UI_DIR = File.join(ROOT_DIR, "ui") unless defined?(UI_DIR)
  TOOLS_DIR = File.join(ROOT_DIR, "tools") unless defined?(TOOLS_DIR)
  DATA_DIR = File.join(ROOT_DIR, "data") unless defined?(DATA_DIR)
  LOG_DIR = File.join(ROOT_DIR, "logs") unless defined?(LOG_DIR)
  DOCS_DIR = File.join(ROOT_DIR, "docs") unless defined?(DOCS_DIR)

  [DATA_DIR, LOG_DIR, DOCS_DIR].each { |dir| FileUtils.mkdir_p(dir) unless File.directory?(dir) rescue nil }

  if defined?(MH_THONGKE_DATA_JSON) && File.dirname(MH_THONGKE_DATA_JSON.to_s) != DATA_DIR
    remove_const(:MH_THONGKE_DATA_JSON) rescue nil
  end
  MH_THONGKE_DATA_JSON = File.join(DATA_DIR, "mh_thongke_data.json") unless defined?(MH_THONGKE_DATA_JSON)
  MH_THONGKE_PROJECT_DATA_DIR = File.expand_path(File.join(ROOT_DIR, "..", "MH_Thongke_Project_Data")) unless defined?(MH_THONGKE_PROJECT_DATA_DIR)
  PROJECT_DATA_DIR_NAME = "Project_Data" unless defined?(PROJECT_DATA_DIR_NAME)

  if defined?(MH_THONGKE_PREFS_JSON) && File.dirname(MH_THONGKE_PREFS_JSON.to_s) != DATA_DIR
    remove_const(:MH_THONGKE_PREFS_JSON) rescue nil
  end
  MH_THONGKE_PREFS_JSON = File.join(DATA_DIR, "mh_thongke_prefs.json") unless defined?(MH_THONGKE_PREFS_JSON)

  if defined?(IMPORT_EXCEL_CACHE_FILE) && File.dirname(IMPORT_EXCEL_CACHE_FILE.to_s) != DATA_DIR
    remove_const(:IMPORT_EXCEL_CACHE_FILE) rescue nil
  end
  IMPORT_EXCEL_CACHE_FILE = File.join(DATA_DIR, "import_excel_cache.json") unless defined?(IMPORT_EXCEL_CACHE_FILE)
  BACK_IMPORT_CACHE_FILE = File.join(DATA_DIR, "back_import_cache.json") unless defined?(BACK_IMPORT_CACHE_FILE)
  unless defined?(DEFAULT_PROJECT_NAME)
    DEFAULT_PROJECT_NAME = "Chưa phân loại"
  end

  # === SessionState: Single source of truth cho tất cả session-scoped state ===
  # Truy cập qua MH_Thongke.session — KHÔNG dùng @xxx module ivars trực tiếp nữa.
  def self.session
    @session ||= SessionState.new
  end

  # Reset toàn bộ scan/rules/excel state — giữ lại prefs.
  # Gọi khi: đổi model, dialog đóng (detach_observers).
  def self.reset_session!(keep_prefs: true)
    if keep_prefs && @session
      saved = {
        hidden_list:              @session.hidden_list.dup,
        unit_overrides:           @session.unit_overrides.dup,
        length_display_units:     @session.length_display_units.dup,
        known_pk_names:           @session.known_pk_names.dup,
        import_excel_path:        @session.import_excel_path.to_s,
        import_excel_paths:       @session.import_excel_paths.dup,
        import_excel_model_paths: @session.import_excel_model_paths.dup,
        project_total_view:       @session.project_total_view.to_s,
        project_total_sort:       @session.project_total_sort.to_s,
        pk_report_view_scope:     @session.pk_report_view_scope.to_s,
        pk_report_cut_source:     @session.pk_report_cut_source.to_s,
        group_by:                 @session.group_by.to_s,
        display_mode:             @session.display_mode.to_s,
        imported_excel_data:      @session.imported_excel_data,
      }
    end
    @session = SessionState.new
    if keep_prefs && saved
      saved.each { |k, v| @session.send(:"#{k}=", v) unless v.nil? }
    end
    clear_norm_caches!
  end

  def self.clear_norm_caches!
    @norm_cache = {}
    @normalizer.clear! if @normalizer
    @import_name_norm_cache = {} if defined?(@import_name_norm_cache)
    @import_equiv_norm_cache = {} if defined?(@import_equiv_norm_cache)
  end

  # === LED factors (không thuộc session — config cố định) ===
  @led_factors ||= { 12.0 => "Nguồn loại 1", 15.0 => "Nguồn loại 2" }
  if @led_factors.is_a?(Array)
    @led_factors = @led_factors.map.with_index { |w, i| [w, "Nguồn loại #{i + 1}"] }.to_h
  end

  # === Performance: norm cache dùng chung qua MH::Text ===
  @norm_cache ||= {}
  @norm_cache_max ||= 2000

  MOJIBAKE_MARKER_PARTS = [
    "\u00C3\u00A1", "\u00C3\u00A0", "\u00C3\u00A2", "\u00C3\u00A3",
    "\u00C3\u00AA", "\u00C3\u00A9", "\u00C3\u00A8", "\u00C3\u00AD",
    "\u00C3\u00AC", "\u00C3\u00B3", "\u00C3\u00B2", "\u00C3\u00B4",
    "\u00C3\u00B5", "\u00C3\u00BA", "\u00C3\u00B9", "\u00C3\u00BD",
    "áº", "á»", "Âº", "Â£", "Â¥", "Â°", "Â¡",
    "Æ°", "Æ¡", "Ä‘", "Ä", "â€", "â€“", "â€”", "â†"
  ].freeze unless defined?(MOJIBAKE_MARKER_PARTS)
  MOJIBAKE_MARKERS = Regexp.union(MOJIBAKE_MARKER_PARTS) unless defined?(MOJIBAKE_MARKERS)

  def self.fix_vietnamese_mojibake(value)
    MH::Text.fix_mojibake(value)
  rescue
    value.to_s
  end

  def self.cached_norm(value)
    return "" if value.nil?
    @norm_cache = {} unless @norm_cache.is_a?(Hash)
    @norm_cache_max = 2000 unless @norm_cache_max.to_i > 0
    key = fix_vietnamese_mojibake(value)
    return @norm_cache[key] if @norm_cache.key?(key)
    result = MH::Text.fold(key)
    @norm_cache.clear if @norm_cache.size > @norm_cache_max.to_i
    @norm_cache[key] = result
    result
  end

  def self.hidden_name_norm(value)
    cached_norm(fix_vietnamese_mojibake(value).to_s).gsub(/\s+/, " ").strip
  rescue
    value.to_s.downcase.gsub(/\s+/, " ").strip
  end

  def self.normalize_hidden_names(names)
    seen = {}
    Array(names).map { |name| fix_vietnamese_mojibake(name).to_s.strip }
                .reject(&:empty?)
                .each_with_object([]) do |name, out|
      key = hidden_name_norm(name)
      next if key.empty? || seen[key]
      seen[key] = true
      out << name
    end
  rescue
    []
  end

  def self.hidden_name_set
    list = normalize_hidden_names(@hidden_list || [])
    sig = list.map { |name| hidden_name_norm(name) }.join("|")
    if @hidden_name_set_sig != sig
      @hidden_name_set = Set.new(list.map { |name| hidden_name_norm(name) }.reject(&:empty?))
      @hidden_name_set_sig = sig
      @hidden_list = list
    end
    @hidden_name_set || Set.new
  end

  def self.hidden_item_name?(*values)
    hidden = hidden_name_set
    return false if hidden.empty?

    values.flatten.compact.any? do |value|
      key = hidden_name_norm(value)
      !key.empty? && hidden.include?(key)
    end
  rescue
    false
  end

  def self.hidden_names_signature
    hidden_name_set
    key = @hidden_name_set_sig.to_s
    if @hidden_names_signature_cache_key != key
      @hidden_names_signature_cache = (@hidden_name_set || Set.new).to_a.sort.join("|")
      @hidden_names_signature_cache_key = key
    end
    @hidden_names_signature_cache.to_s
  rescue
    Array(@hidden_list).map { |name| hidden_name_norm(name) }.sort.join("|")
  end

  @led_power_factor ||= 12.0
  @psu_list ||= [200, 100, 60]
  @file_snapshots ||= []

  # === Match Rules Constants ===
  if defined?(GLOBAL_RULES_FILE) && File.dirname(GLOBAL_RULES_FILE.to_s) != DATA_DIR
    remove_const(:GLOBAL_RULES_FILE) rescue nil
  end
  GLOBAL_RULES_FILE = File.join(DATA_DIR, "match_rules_global.json") unless defined?(GLOBAL_RULES_FILE)

  if defined?(RULES_EXCEL_FILE) && File.dirname(RULES_EXCEL_FILE.to_s) != DATA_DIR
    remove_const(:RULES_EXCEL_FILE) rescue nil
  end
  RULES_EXCEL_FILE = File.join(DATA_DIR, "match_rules_log.xlsx") unless defined?(RULES_EXCEL_FILE)

  DEFAULT_GENERAL_RULES = {
    "ignore_keywords"       => ["theo m\u1EABu"],
    "keep_numbers_patterns" => ["ray bi", "ray \u00E2m"],
    "synonym_pairs"         => [["doang cua", "gioang cua"]],
    "equivalent_pairs"      => [["banh xe cao", "banh xe"]]
  } unless defined?(DEFAULT_GENERAL_RULES)
  DEFAULT_GENERAL_RULES["ignore_keywords"] ||= ["theo m\u1EABu"]
  DEFAULT_GENERAL_RULES["keep_numbers_patterns"] ||= ["ray bi", "ray \u00E2m"]
  DEFAULT_GENERAL_RULES["synonym_pairs"] ||= [["doang cua", "gioang cua"]]
  DEFAULT_GENERAL_RULES["equivalent_pairs"] ||= [["banh xe cao", "banh xe"]]

  # === Session delegation — backward compat cho code đọc @xxx qua method call ===
  # Scan results
  def self.data_map;             session.data_map;             end
  def self.data_map=(v);         session.data_map = v;         end
  def self.mat_data_map;         session.mat_data_map;         end
  def self.mat_data_map=(v);     session.mat_data_map = v;     end
  def self.current_report_items; session.current_report_items; end
  def self.current_mat_items;    session.current_mat_items;    end
  def self.prod_groups;          session.prod_groups;          end
  def self.all_item_names;       session.all_item_names;       end
  def self.all_item_names_set;   session.all_item_names_set;   end
  def self.led_per_product;      session.led_per_product;      end

  # Preferences
  def self.hidden_list;     session.hidden_list;     end
  def self.hidden_list=(v); session.hidden_list = v; end
  def self.unit_overrides;     session.unit_overrides;     end
  def self.unit_overrides=(v); session.unit_overrides = v; end
  def self.known_pk_names;     session.known_pk_names;     end
  def self.known_pk_names=(v); session.known_pk_names = v; end
  def self.group_by;     session.group_by;     end
  def self.group_by=(v); session.group_by = v; end

  # Rules
  def self.match_rules;         session.match_rules;         end
  def self.match_rules=(v);     session.match_rules = v;     end
  def self.general_rules;       session.general_rules;       end
  def self.general_rules=(v);   session.general_rules = v;   end
  def self.mini_accept_rules;   session.mini_accept_rules;   end
  def self.mini_accept_rules=(v); session.mini_accept_rules = v; end

  # Excel
  def self.imported_excel_data;     session.imported_excel_data;     end
  def self.imported_excel_data=(v)
    if respond_to?(:set_imported_excel_data)
      set_imported_excel_data(v, "config_imported_excel_data_setter", sync_session: true)
    else
      session.imported_excel_data = v
    end
  end
  def self.back_imported_excel;     session.back_imported_excel;     end
  def self.back_imported_excel=(v); session.back_imported_excel = v; end

  # UI display state
  def self.display_mode;        session.display_mode;        end
  def self.display_mode=(v);    session.display_mode = v;    end
  def self.pk_report_view_scope;       session.pk_report_view_scope;       end
  def self.pk_report_view_scope=(v);   session.pk_report_view_scope = v;   end
  def self.pk_report_cut_source;       session.pk_report_cut_source;       end
  def self.pk_report_cut_source=(v);   session.pk_report_cut_source = v;   end
  def self.project_total_view;         session.project_total_view;         end
  def self.project_total_view=(v);     session.project_total_view = v;     end
  def self.project_total_sort;         session.project_total_sort;         end
  def self.project_total_sort=(v);     session.project_total_sort = v;     end
  def self.length_display_units;       session.length_display_units;       end
  def self.length_display_units=(v);   session.length_display_units = v;   end

  # === Utility Helpers ===
  def self.html_escape(value)
    fix_vietnamese_mojibake(value)
         .gsub("&", "&amp;")
         .gsub("'", "&#39;")
         .gsub('"', "&quot;")
         .gsub("<", "&lt;")
         .gsub(">", "&gt;")
  end

  def self.js_arg(value)
    JSON.generate(fix_vietnamese_mojibake(value))
  end

  def self.format_valid_date(year, month, day)
    year = year.to_i
    year += (year < 70 ? 2000 : 1900) if year < 100
    month = month.to_i
    day = day.to_i
    return nil unless ::Date.valid_date?(year, month, day)
    ::Date.new(year, month, day).strftime("%d/%m/%Y")
  rescue
    nil
  end

  def self.normalize_order_date(value)
    return "" if value.nil?
    if !value.is_a?(String) && value.respond_to?(:strftime)
      return value.strftime("%d/%m/%Y") rescue value.to_s
    end

    text = fix_vietnamese_mojibake(value).to_s.strip
    text = text.gsub(/\A['"]+|['"]+\z/, "").strip
    return "" if text.empty?
    return text if text =~ /\A\d{1,2}\z/ || text =~ /\A\d{1,2}[\/\-.]\z/

    numeric_text = text.tr(",", ".")
    if numeric_text =~ /\A\d+(?:\.\d+)?\z/
      serial = numeric_text.to_f
      if serial > 25_000 && serial < 80_000
        date = ::Date.new(1899, 12, 30) + serial.to_i
        return date.strftime("%d/%m/%Y")
      end
    end

    candidates = []
    if text =~ /\A(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})(?:\D|$)/
      candidates << [$1, $2, $3]
    end
    if text =~ /\A(\d{1,2})[\/\-.](\d{1,2})(?:[\/\-.](\d{2,4}))?(?:\D|$)/
      year = $3 || Time.now.year
      candidates << [year, $2, $1]
      candidates << [year, $1, $2] if $2.to_i > 12 && $1.to_i <= 12
    end

    digits = text.gsub(/\D/, "")
    case digits.length
    when 8
      if digits[0, 4].to_i.between?(1900, 2099)
        candidates << [digits[0, 4], digits[4, 2], digits[6, 2]]
      else
        candidates << [digits[4, 4], digits[2, 2], digits[0, 2]]
      end
    when 6
      candidates << [digits[4, 2], digits[2, 2], digits[0, 2]]
    when 4
      candidates << [Time.now.year, digits[2, 2], digits[0, 2]]
    end

    candidates.each do |year, month, day|
      formatted = format_valid_date(year, month, day)
      return formatted if formatted
    end

    parsed = (::Date.parse(text) rescue nil)
    parsed ? parsed.strftime("%d/%m/%Y") : text
  rescue
    value.to_s.strip
  end

  def self.order_date_overrides
    data = project_state_hash("order_date_overrides")
    return data if data.is_a?(Hash) && !data.empty?

    # Legacy fallback (model attribute) -> migrate vào Project_State.json
    model = Sketchup.active_model rescue nil
    raw = model ? model.get_attribute("MH_Thongke", "order_date_overrides").to_s : ""
    legacy = raw.empty? ? {} : (JSON.parse(raw) rescue {})
    legacy = {} unless legacy.is_a?(Hash)
    save_project_state_hash("order_date_overrides", legacy) unless legacy.empty?
    legacy
  end

  def self.order_date_key(table, data_or_product, name = nil, spec = nil)
    if data_or_product.is_a?(Hash)
      product = data_or_product[:actual_product] || data_or_product[:product]
      name = data_or_product[:name] if name.nil?
      if spec.nil?
        spec = table.to_s == "mat" ? (data_or_product[:thickness] || data_or_product[:spec]) : nil
      end
    else
      product = data_or_product
    end
    product = (product_code_exact(product) rescue product.to_s.strip.upcase)
    [table.to_s, product.to_s.strip.upcase, cached_norm(name), cached_norm(spec)].join("|")
  end

  def self.order_date_override(table, data)
    overrides = @order_date_overrides_batch_cache || order_date_overrides
    value = overrides[order_date_key(table, data)]
    normalize_order_date(value)
  rescue
    ""
  end

  def self.apply_order_date_override(table, data)
    return unless data.is_a?(Hash)
    value = order_date_override(table, data)
    data[:ngay_dat] = value unless value.to_s.strip.empty?
  end

  def self.save_order_date_override(table, data, value)
    return unless data.is_a?(Hash)
    value = normalize_order_date(value)
    overrides = order_date_overrides
    key = order_date_key(table, data)
    if value.to_s.strip.empty?
      overrides.delete(key)
    else
      overrides[key] = value
    end
    save_project_state_hash("order_date_overrides", overrides)
    value
  rescue => e
    puts "save_order_date_override error: #{e.message}"
    normalize_order_date(value)
  end

  def self.row_meta_overrides
    data = project_state_hash("row_meta_overrides")
    return data if data.is_a?(Hash) && !data.empty?

    model = Sketchup.active_model rescue nil
    raw = model ? model.get_attribute("MH_Thongke", "row_meta_overrides").to_s : ""
    legacy = raw.empty? ? {} : (JSON.parse(raw) rescue {})
    legacy = {} unless legacy.is_a?(Hash)
    save_project_state_hash("row_meta_overrides", legacy) unless legacy.empty?
    legacy
  end

  def self.with_override_batch_cache
    old_order_cache = @order_date_overrides_batch_cache
    old_meta_cache = @row_meta_overrides_batch_cache
    @order_date_overrides_batch_cache = order_date_overrides
    @row_meta_overrides_batch_cache = row_meta_overrides
    yield
  ensure
    @order_date_overrides_batch_cache = old_order_cache
    @row_meta_overrides_batch_cache = old_meta_cache
  end

  def self.row_meta_key(table, data)
    order_date_key(table, data)
  end

  def self.apply_row_meta_override(table, data)
    return unless data.is_a?(Hash)
    apply_one = lambda do |meta|
      next false unless meta.is_a?(Hash)

      data[:name] = meta["name"].to_s if meta.key?("name")
      data[:ten_sp] = meta["ten_sp"].to_s if meta.key?("ten_sp")
      data[:ghi_chu] = meta["ghi_chu"].to_s if meta.key?("ghi_chu")
      data[:last_modified] = meta["last_modified"].to_s if meta.key?("last_modified")
      true
    end

    overrides = @row_meta_overrides_batch_cache || row_meta_overrides
    first_key = row_meta_key(table, data)
    applied = apply_one.call(overrides[first_key])
    second_key = row_meta_key(table, data)
    applied = apply_one.call(overrides[second_key]) || applied if second_key != first_key
    applied
  end

  def self.apply_overrides_to_rows!(data_rows, mat_rows)
    with_override_batch_cache do
      if respond_to?(:apply_row_meta_override)
        Array(data_rows).each { |row| apply_row_meta_override("acc", row) }
        Array(mat_rows).each { |row| apply_row_meta_override("mat", row) }
      end
      if respond_to?(:apply_order_date_override)
        Array(data_rows).each { |row| apply_order_date_override("acc", row) }
        Array(mat_rows).each { |row| apply_order_date_override("mat", row) }
      end
    end
    true
  end

  def self.save_row_meta_override(table, data, field, value)
    return unless data.is_a?(Hash)
    field = field.to_s
    return unless ["name", "ten_sp", "ghi_chu"].include?(field)

    overrides = row_meta_overrides
    key = row_meta_key(table, data)
    meta = overrides[key].is_a?(Hash) ? overrides[key] : {}
    meta[field] = value.to_s
    meta["last_modified"] = Time.now.strftime("%d/%m/%y %H:%M")
    overrides[key] = meta
    save_project_state_hash("row_meta_overrides", overrides)
    value.to_s
  rescue => e
    puts "save_row_meta_override error: #{e.message}"
    value.to_s
  end

  def self.row_qty_overrides
    data = project_state_hash("row_qty_overrides")
    return data if data.is_a?(Hash) && !data.empty?

    model = Sketchup.active_model rescue nil
    raw = model ? model.get_attribute("MH_Thongke", "row_qty_overrides").to_s : ""
    legacy = raw.empty? ? {} : (JSON.parse(raw) rescue {})
    legacy = {} unless legacy.is_a?(Hash)
    save_project_state_hash("row_qty_overrides", legacy) unless legacy.empty?
    legacy
  end

  def self.row_qty_key(table, data)
    order_date_key(table, data)
  end

  def self.apply_row_qty_override(table, data)
    return unless data.is_a?(Hash)
    meta = row_qty_overrides[row_qty_key(table, data)]
    return unless meta.is_a?(Hash)

    data[:qty_override] = meta["qty"].to_f if meta.key?("qty")
    data[:last_modified] = meta["last_modified"].to_s if meta.key?("last_modified") && data[:last_modified].to_s.empty?
  end

  def self.save_row_qty_override(table, data, qty)
    return nil unless data.is_a?(Hash)
    qty = qty.to_f
    overrides = row_qty_overrides
    key = row_qty_key(table, data)
    meta = overrides[key].is_a?(Hash) ? overrides[key] : {}
    meta["qty"] = qty
    meta["last_modified"] = Time.now.strftime("%d/%m/%y %H:%M")
    overrides[key] = meta
    save_project_state_hash("row_qty_overrides", overrides)
    qty
  rescue => e
    puts "save_row_qty_override error: #{e.message}"
    qty.to_f
  end

  def self.project_state_path
    model = Sketchup.active_model rescue nil
    path = model ? model.path.to_s : ""
    return "" if path.empty?

    dir = File.dirname(path)
    return "" if dir.to_s.empty? || dir == "."

    data_dir = File.join(dir, PROJECT_DATA_DIR_NAME)
    FileUtils.mkdir_p(data_dir) unless File.directory?(data_dir)
    File.join(data_dir, "PROJECT_STATE.json")
  rescue
    ""
  end

  def self.load_project_state_data
    path = project_state_path
    return {} if path.empty? || !File.exist?(path)

    mtime = File.mtime(path).to_f rescue 0.0
    if @project_state_cache_path.to_s != path.to_s || @project_state_cache_mtime.to_f != mtime
      raw = JSON.parse(File.read(path)) rescue {}
      raw = {} unless raw.is_a?(Hash)
      @project_state_cache = raw
      @project_state_cache_path = path
      @project_state_cache_mtime = mtime
    end
    @project_state_cache || {}
  rescue
    {}
  end

  def self.save_project_state_data(data)
    path = project_state_path
    return false if path.empty?

    payload = data.is_a?(Hash) ? data : {}
    payload["schema"] = "mh_thongke_project_state"
    payload["schema_version"] = 1
    payload["updated_at"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    tmp = "#{path}.tmp"
    File.write(tmp, JSON.pretty_generate(payload))
    File.delete(path) if File.exist?(path)
    File.rename(tmp, path)
    @project_state_cache = payload
    @project_state_cache_path = path
    @project_state_cache_mtime = File.mtime(path).to_f rescue Time.now.to_f
    true
  rescue => e
    puts "save_project_state_data error: #{e.message}"
    false
  end

  def self.project_state_hash(key)
    data = load_project_state_data
    value = data[key.to_s]
    value.is_a?(Hash) ? value : {}
  rescue
    {}
  end

  def self.save_project_state_hash(key, hash)
    data = load_project_state_data
    payload = hash.is_a?(Hash) ? hash : {}
    if payload.empty?
      data.delete(key.to_s)
    else
      data[key.to_s] = payload
    end
    save_project_state_data(data)
    payload
  rescue => e
    puts "save_project_state_hash error: #{e.message}"
    hash.is_a?(Hash) ? hash : {}
  end

  def self.log_date_commit(table, idx, raw_value, normalized_value, data = nil)
    File.open(File.join(LOG_DIR, "date_debug.log"), "a:utf-8") do |f|
      f.puts [
        Time.now.strftime("%Y-%m-%d %H:%M:%S"),
        table,
        idx,
        raw_value,
        normalized_value,
        data && data[:actual_product],
        data && data[:name],
        data && data[:is_missing]
      ].join("\t")
    end
  rescue
  end
end
