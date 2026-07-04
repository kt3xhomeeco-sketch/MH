# encoding: utf-8
# MH_Thongke — accept rules storage, hidden items, cache invalidation.
module MH_Thongke

  # === mini_import_accept_store_rules.rb ===
  # --- mini_import_accept_store_rules.rb ---
# MH_Thongke - Mini Import accept rule storage (global/project).


  PROJECT_RULES_DIR_NAME = "MH_Thongke_Project_Data" unless defined?(PROJECT_RULES_DIR_NAME)

  def self.load_global_mini_accept_rules
    extract_mini_accept_rules_from_payload(load_rules_file_payload(GLOBAL_RULES_FILE))
  end

  def self.load_global_mini_name_lineage
    extract_mini_name_lineage_from_payload(load_rules_file_payload(GLOBAL_RULES_FILE))
  end

  def self.save_global_mini_accept_rules(rules)
    data = ensure_global_rules_payload(load_rules_file_payload(GLOBAL_RULES_FILE))
    data["mini_accept_rules"] = rules.is_a?(Hash) ? rules : {}
    if @mini_name_lineage.is_a?(Hash)
      data["mini_name_lineage"] = normalize_mini_name_lineage(@mini_name_lineage)
    else
      data["mini_name_lineage"] ||= {}
    end
    File.write(GLOBAL_RULES_FILE, JSON.pretty_generate(data))
  rescue => e
    puts "save_global_mini_accept_rules error: #{e.message}"
  end

  def self.mini_rules_file_mtime(path)
    path = path.to_s
    return 0.0 if path.empty? || !File.exist?(path)

    File.mtime(path).to_f
  rescue
    0.0
  end

  def self.mini_rules_source_signature(project_rules_file = nil)
    # Cache signature for 2 seconds to avoid excessive File.mtime calls
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    prf = project_rules_file || mini_project_rules_file
    cache_key = "#{GLOBAL_RULES_FILE}|#{prf}"
    if @mini_rules_sig_cache_key == cache_key &&
       @mini_rules_sig_cache_at.to_f > 0 &&
       now - @mini_rules_sig_cache_at.to_f < 2.0
      return @mini_rules_sig_cache_value.to_s
    end
    sig = [
      mini_rules_file_mtime(GLOBAL_RULES_FILE),
      prf.to_s,
      mini_rules_file_mtime(prf)
    ].join("|")
    @mini_rules_sig_cache_key = cache_key
    @mini_rules_sig_cache_at = now
    @mini_rules_sig_cache_value = sig
    sig
  rescue
    ""
  end

  def self.mini_rule_time(value)
    value.is_a?(Hash) ? value["time"].to_i : 0
  rescue
    0
  end

  def self.merge_mini_accept_rule_sets(*sets)
    merged = {}
    sets.each do |rules|
      next unless rules.is_a?(Hash)

      rules.each do |key, value|
        old_value = merged[key]
        if old_value.nil? || mini_rule_time(value) >= mini_rule_time(old_value)
          merged[key] = value
        end
      end
    end
    merged
  end

  def self.safe_project_rules_name(value)
    text = fix_vietnamese_mojibake(value).to_s.strip
    text = "project" if text.empty? || text == DEFAULT_PROJECT_NAME
    safe = cached_norm(text).gsub(/[^a-z0-9]+/, "_").gsub(/_+/, "_")
    safe = safe.gsub(/\A_+|_+\z/, "")
    safe.empty? ? "project" : safe
  rescue
    "project"
  end

  def self.mini_project_rules_file(excel_path = nil)
    path = excel_path.to_s.strip
    if path.empty?
      path = sync_import_excel_path.to_s if respond_to?(:sync_import_excel_path)
      path = @import_excel_path.to_s if path.empty?
    end
    path = path.gsub(/^["']|["']$/, "")
    return "" if path.empty?

    excel_dir = File.dirname(path)
    return "" if excel_dir.nil? || excel_dir.empty? || excel_dir == "."

    project = ""
    begin
      project = import_excel_project_key if respond_to?(:import_excel_project_key)
    rescue
      project = ""
    end
    project = File.basename(excel_dir).to_s if project.to_s.strip.empty? || project == DEFAULT_PROJECT_NAME
    project_dir = File.join(excel_dir, PROJECT_RULES_DIR_NAME)
    File.join(project_dir, "#{safe_project_rules_name(project)}_accept_rules.json")
  rescue
    ""
  end

  def self.load_project_mini_accept_rules(excel_path = nil)
    extract_mini_accept_rules_from_payload(load_project_mini_rules_payload(excel_path))
  end

  def self.load_project_mini_name_lineage(excel_path = nil)
    extract_mini_name_lineage_from_payload(load_project_mini_rules_payload(excel_path))
  end

  def self.load_project_mini_rules_payload(excel_path = nil)
    file = mini_project_rules_file(excel_path)
    load_rules_file_payload(file)
  end

  def self.save_project_mini_accept_rules(rules, excel_path = nil)
    file = mini_project_rules_file(excel_path)
    return "" if file.to_s.empty?

    FileUtils.mkdir_p(File.dirname(file))
    existing = load_project_mini_rules_payload(excel_path)
    hidden_items = project_hidden_items(existing)
    payload = existing.merge(project_rules_metadata_payload(excel_path))
    payload["mini_accept_rules"] = rules.is_a?(Hash) ? rules : {}
    payload["hidden_excel_items"] = Array(hidden_items).map(&:to_s).reject(&:empty?).uniq
    payload["mini_name_lineage"] = normalize_mini_name_lineage(@mini_name_lineage) if @mini_name_lineage.is_a?(Hash)
    File.write(file, JSON.pretty_generate(payload))
    file
  rescue => e
    puts "save_project_mini_accept_rules error: #{e.message}"
    ""
  end

  def self.load_rules_file_payload(path)
    path = path.to_s
    return {} if path.empty? || !File.exist?(path)

    data = JSON.parse(File.read(path)) rescue {}
    data.is_a?(Hash) ? data : {}
  rescue
    {}
  end

  def self.extract_mini_accept_rules_from_payload(data)
    return {} unless data.is_a?(Hash)

    rules = data["mini_accept_rules"] || data["accept_rules"] || data["rules"]
    rules.is_a?(Hash) ? rules : {}
  rescue
    {}
  end

  def self.extract_mini_name_lineage_from_payload(data)
    return {} unless data.is_a?(Hash)

    lineage = data["mini_name_lineage"] || data["name_lineage"]
    lineage.is_a?(Hash) ? lineage : {}
  rescue
    {}
  end

  def self.ensure_global_rules_payload(data)
    payload = data.is_a?(Hash) ? data : {}
    if !payload.key?("general_rules") && @general_rules
      payload["general_rules"] = @general_rules
    end
    if !payload.key?("specific_rules") && @match_rules
      payload["specific_rules"] = @match_rules
    end
    payload["general_rules"] ||= DEFAULT_GENERAL_RULES.dup
    payload["specific_rules"] ||= {}
    payload
  end

  def self.project_rules_metadata_payload(excel_path = nil)
    {
      "project" => begin
        respond_to?(:import_excel_project_key) ? import_excel_project_key.to_s : ""
      rescue
        ""
      end,
      "excel_path" => excel_path.to_s.empty? ? @import_excel_path.to_s : excel_path.to_s,
      "updated_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S")
    }
  end

  def self.project_hidden_items(existing)
    hidden_items = existing["hidden_excel_items"]
    hidden_items = @mini_hidden_excel_items if !hidden_items.is_a?(Array) && @mini_hidden_excel_items.is_a?(Array)
    hidden_items
  end

  # === mini_import_accept_store_hidden.rb ===
  # --- mini_import_accept_store_hidden.rb ---
# MH_Thongke - Mini Import hidden Excel item storage.


  def self.mini_hidden_excel_items_signature
    items = mini_hidden_excel_items
    key = [items.size, items.hash].join(":")
    if @mini_hidden_excel_items_sig_key.to_s != key
      @mini_hidden_excel_items_sig = items.hash
      @mini_hidden_excel_items_sig_key = key
    end
    @mini_hidden_excel_items_sig.to_i
  rescue
    0
  end

  def self.mini_hidden_excel_items
    # Fast path: Throttle full checks to at most once per 2 seconds
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    if @mini_hidden_excel_items.is_a?(Array) &&
       @mini_hidden_excel_items_last_check_at.to_f > 0 &&
       now - @mini_hidden_excel_items_last_check_at.to_f < 2.0
      return @mini_hidden_excel_items
    end
    @mini_hidden_excel_items_last_check_at = now

    project_file = mini_project_rules_file
    sig = mini_rules_source_signature(project_file)
    if @mini_hidden_excel_items.is_a?(Array) &&
       @mini_hidden_excel_items_project_file.to_s == project_file.to_s &&
       @mini_hidden_excel_items_source_sig.to_s == sig.to_s
      return @mini_hidden_excel_items
    end

    data = load_project_mini_rules_payload
    @mini_hidden_excel_items = Array(data["hidden_excel_items"]).map(&:to_s).reject(&:empty?).uniq
    @mini_hidden_excel_items_project_file = project_file
    @mini_hidden_excel_items_source_sig = sig
    @mini_hidden_excel_items
  rescue
    @mini_hidden_excel_items ||= []
  end

  def self.save_mini_hidden_excel_items(items)
    project_file = mini_project_rules_file
    return false if project_file.to_s.empty?

    data = load_project_mini_rules_payload
    FileUtils.mkdir_p(File.dirname(project_file))
    data["project"] = respond_to?(:import_excel_project_key) ? import_excel_project_key.to_s : data["project"].to_s
    data["excel_path"] = @import_excel_path.to_s
    data["updated_at"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    data["mini_accept_rules"] = @mini_accept_rules if @mini_accept_rules.is_a?(Hash)
    data["mini_accept_rules"] ||= load_project_mini_accept_rules
    data["hidden_excel_items"] = Array(items).map(&:to_s).reject(&:empty?).uniq
    File.write(project_file, JSON.pretty_generate(data))
    @mini_hidden_excel_items = data["hidden_excel_items"]
    @mini_hidden_excel_items_project_file = project_file
    @mini_hidden_excel_items_source_sig = mini_rules_source_signature(project_file)
    @mini_hidden_excel_items_sig_key = nil
    @mini_hidden_excel_items_sig = nil
    mini_hidden_items_invalidate_caches
    true
  rescue => e
    puts "save_mini_hidden_excel_items error: #{e.message}"
    false
  end

  def self.mini_hidden_item_key(product_code, kind, name, spec = "")
    product = mini_hidden_product_key(product_code)
    kind_text = mini_hidden_kind(kind)
    [
      product.to_s.upcase,
      kind_text,
      mini_accept_norm(kind_text, name),
      import_name_norm(spec)
    ].join("|")
  end

  def self.mini_hidden_item_keys(product_code, kind, name, spec = "")
    products = mini_hidden_product_variants(product_code)
    names = mini_hidden_name_variants(name, spec)
    specs = mini_hidden_spec_variants(spec)
    products.flat_map do |product|
      names.flat_map do |item_name|
        specs.map { |item_spec| mini_hidden_item_key(product, kind, item_name, item_spec) }
      end
    end.uniq
  rescue
    []
  end

  def self.mini_import_item_hidden?(product_code, kind, name, spec = "")
    hidden = mini_hidden_excel_items
    return false if hidden.empty?

    mini_hidden_item_keys(product_code, kind, name, spec).any? { |key| hidden.include?(key) }
  rescue
    false
  end

  def self.record_hidden_import_excel_item(product_code, kind, name, spec = "")
    keys = mini_hidden_item_keys(product_code, kind, name, spec)
    return false if keys.empty?

    hidden = (mini_hidden_excel_items + keys).uniq
    @mini_hidden_excel_items = hidden
    @mini_hidden_excel_items_sig_key = nil
    @mini_hidden_excel_items_sig = nil
    save_mini_hidden_excel_items(hidden)
    remove_mini_accept_rules_for_hidden(product_code, kind, name, spec)
    true
  rescue => e
    puts "record_hidden_import_excel_item error: #{e.message}"
    false
  end

  def self.remove_mini_accept_rules_for_hidden(product_code, kind, name, spec = "")
    rules = ensure_mini_accept_rules
    return 0 unless rules.is_a?(Hash) && rules.any?

    products = mini_hidden_product_variants(product_code).map(&:to_s).map(&:upcase).uniq
    kind_text = mini_hidden_kind(kind)
    names = mini_hidden_name_variants(name, spec).map { |value| mini_accept_norm(kind_text, value) }.uniq
    specs = [import_name_norm(spec), ""].uniq
    removed = 0
    rules.delete_if do |key, _val|
      parts = key.to_s.split("|", 5)
      next false unless products.include?(parts[0].to_s.upcase) || products.include?(product_code_base(parts[0]).to_s.upcase)
      next false unless parts[1].to_s == kind_text
      next false unless specs.include?(parts[4].to_s)
      matched = names.include?(parts[2].to_s) || names.include?(parts[3].to_s)
      removed += 1 if matched
      matched
    end
    save_mini_accept_rules if removed > 0
    removed
  rescue => e
    puts "remove_mini_accept_rules_for_hidden error: #{e.message}"
    0
  end

  def self.mini_hidden_product_key(product_code)
    product = product_code_base(product_code)
    product = product_code_exact(product_code) if product.to_s.empty? || product == "--"
    product
  rescue
    product_code.to_s
  end

  def self.mini_hidden_kind(kind)
    kind.to_s.empty? ? "PK" : kind.to_s
  rescue
    "PK"
  end

  def self.mini_hidden_product_variants(product_code)
    [product_code_exact(product_code), product_code_base(product_code)].reject { |value| value.to_s.empty? || value == "--" }.uniq
  rescue
    []
  end

  def self.mini_hidden_name_variants(name, spec = "")
    [name.to_s, import_display_name(name, spec)].reject { |value| value.to_s.strip.empty? }.uniq
  rescue
    []
  end

  def self.mini_hidden_spec_variants(spec = "")
    [spec.to_s, ""].uniq
  rescue
    [""]
  end

  def self.mini_hidden_items_invalidate_caches
    if respond_to?(:invalidate_mini_import_caches)
      invalidate_mini_import_caches(model: true, excel: true)
    else
      @mini_excel_items_cache = nil
      @mini_model_items_cache = nil
      @mini_last_refresh_state_sig = nil
    end
  end

  # === mini_import_accept_store.rb ===
  # --- mini_import_accept_store.rb ---
# MH_Thongke - Mini Import accept storage entrypoint.
#
# Logic is split into:
# - mini_import_accept_store_rules.rb
# - mini_import_accept_store_hidden.rb


  # --- Alias methods (without mini_ prefix) for backward-compatible rename ---
  def self.rules_file_mtime(*a, **kw, &b); mini_rules_file_mtime(*a, **kw, &b); end
  def self.rules_source_signature(*a, **kw, &b); mini_rules_source_signature(*a, **kw, &b); end
  def self.rule_time(*a, **kw, &b); mini_rule_time(*a, **kw, &b); end
  def self.project_rules_file(*a, **kw, &b); mini_project_rules_file(*a, **kw, &b); end
  def self.hidden_item_key(*a, **kw, &b); mini_hidden_item_key(*a, **kw, &b); end
  def self.hidden_item_keys(*a, **kw, &b); mini_hidden_item_keys(*a, **kw, &b); end
  def self.import_item_hidden?(*a, **kw, &b); mini_import_item_hidden?(*a, **kw, &b); end
  def self.hidden_product_key(*a, **kw, &b); mini_hidden_product_key(*a, **kw, &b); end
  def self.hidden_kind(*a, **kw, &b); mini_hidden_kind(*a, **kw, &b); end
  def self.hidden_product_variants(*a, **kw, &b); mini_hidden_product_variants(*a, **kw, &b); end
  def self.hidden_name_variants(*a, **kw, &b); mini_hidden_name_variants(*a, **kw, &b); end
  def self.hidden_spec_variants(*a, **kw, &b); mini_hidden_spec_variants(*a, **kw, &b); end

  def self.hidden_excel_items_signature(*a, **kw, &b); mini_hidden_excel_items_signature(*a, **kw, &b); end
  def self.hidden_excel_items(*a, **kw, &b); mini_hidden_excel_items(*a, **kw, &b); end
  def self.hidden_items_invalidate_caches(*a, **kw, &b); mini_hidden_items_invalidate_caches(*a, **kw, &b); end
end
