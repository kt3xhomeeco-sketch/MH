# encoding: utf-8
# MH_Thongke — name lineage persistence, lookup, and recording.
module MH_Thongke

  # === mini_import_accept_lineage_store.rb ===
  # --- mini_import_accept_lineage_store.rb ---
# MH_Thongke - Mini Import name lineage persistence.


  def self.normalize_mini_name_lineage(lineage)
    out = {}
    return out unless lineage.is_a?(Hash)

    lineage.each do |key, raw|
      next unless raw.is_a?(Hash)

      product = product_code_exact(raw["product_code"] || raw[:product_code])
      product = product_code_exact(key.to_s.split("|").first) if product.empty?
      kind = (raw["kind"] || raw[:kind]).to_s
      kind = key.to_s.split("|")[1].to_s if kind.empty?
      kind = "PK" if kind.empty?
      root_name = (raw["root_name"] || raw[:root_name]).to_s
      root_norm = (raw["root_norm"] || raw[:root_norm]).to_s

      aliases = Array(raw["aliases"] || raw[:aliases]).map(&:to_s).reject(&:empty?).uniq
      display_names = Array(raw["display_names"] || raw[:display_names]).map(&:to_s).reject(&:empty?).uniq
      root_name = display_names.first.to_s if root_name.empty?
      root_name = aliases.first.to_s if root_name.empty?
      root_norm = mini_accept_norm(kind, root_name) if root_norm.empty? && !root_name.empty?

      chain = Array(raw["chain"] || raw[:chain]).select { |item| item.is_a?(Hash) }.map do |item|
        {
          "time" => item["time"] || item[:time],
          "product_code" => product,
          "kind" => kind,
          "from" => (item["from"] || item[:from]).to_s,
          "from_norm" => (item["from_norm"] || item[:from_norm]).to_s,
          "to" => (item["to"] || item[:to]).to_s,
          "to_norm" => (item["to_norm"] || item[:to_norm]).to_s,
          "action" => (item["action"] || item[:action]).to_s,
          "spec" => (item["spec"] || item[:spec]).to_s,
          "source" => (item["source"] || item[:source]).to_s
        }.delete_if { |_k, v| v.nil? || v.to_s.empty? }
      end

      normalized_key = [product, kind, root_norm.empty? ? key.to_s : root_norm].join("|")
      out[normalized_key] = {
        "product_code" => product,
        "kind" => kind,
        "root_name" => root_name,
        "root_norm" => root_norm,
        "aliases" => aliases,
        "display_names" => display_names,
        "chain" => chain,
        "created_at" => (raw["created_at"] || raw[:created_at]).to_s,
        "updated_at" => (raw["updated_at"] || raw[:updated_at]).to_s
      }.delete_if { |_k, v| v.respond_to?(:empty?) && v.empty? }
    end
    out
  rescue
    {}
  end

  def self.merge_mini_name_lineage_sets(*sets)
    merged = {}
    sets.each do |lineage|
      normalize_mini_name_lineage(lineage).each do |key, row|
        current = merged[key]
        unless current
          merged[key] = row
          next
        end

        current["aliases"] = (Array(current["aliases"]) + Array(row["aliases"])).uniq
        current["display_names"] = (Array(current["display_names"]) + Array(row["display_names"])).uniq
        current["chain"] = (Array(current["chain"]) + Array(row["chain"])).uniq
        current["updated_at"] = [current["updated_at"].to_s, row["updated_at"].to_s].max
      end
    end
    merged
  rescue
    {}
  end

  def self.ensure_mini_name_lineage
    # Fast path: Throttle full checks to at most once per 2 seconds
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    if @mini_name_lineage.is_a?(Hash) &&
       @mini_name_lineage_last_check_at.to_f > 0 &&
       now - @mini_name_lineage_last_check_at.to_f < 2.0
      return @mini_name_lineage
    end
    @mini_name_lineage_last_check_at = now

    @model ||= Sketchup.active_model
    model_id = @model ? @model.object_id : 0
    project_file = mini_project_rules_file
    raw_model = @model ? @model.get_attribute("MH_Thongke", "mini_name_lineage").to_s : ""
    source_sig = mini_name_lineage_source_signature(project_file, raw_model)
    if mini_name_lineage_cache_valid?(model_id, project_file, source_sig)
      return @mini_name_lineage
    end

    model_lineage = parse_mini_name_lineage_payload(raw_model)

    @mini_name_lineage = merge_mini_name_lineage_sets(
      load_global_mini_name_lineage,
      model_lineage,
      load_project_mini_name_lineage
    )
    @mini_name_lineage_model_id = model_id
    @mini_name_lineage_project_file = project_file
    @mini_name_lineage_source_sig = source_sig
    reset_mini_rule_caches(lineage: true, accept: false, refresh: false)
    seed_mini_name_lineage_from_accept_rules(@mini_accept_rules || {})
    @mini_name_lineage
  rescue
    @mini_name_lineage ||= {}
  end

  def self.save_mini_name_lineage
    ensure_mini_name_lineage unless @mini_name_lineage.is_a?(Hash)
    @mini_name_lineage = normalize_mini_name_lineage(@mini_name_lineage)
    @model ||= Sketchup.active_model
    @model.set_attribute("MH_Thongke", "mini_name_lineage", JSON.generate(@mini_name_lineage)) if @model
    save_global_mini_accept_rules(@mini_accept_rules || ensure_mini_accept_rules)
    save_project_mini_accept_rules(@mini_accept_rules || {}, @import_excel_path)
    reset_mini_rule_caches(lineage: true, accept: false, refresh: true)
    true
  rescue => e
    puts "save_mini_name_lineage error: #{e.message}"
    false
  end

  def self.mini_name_lineage_source_signature(project_file, raw_model)
    [mini_rules_source_signature(project_file), raw_model.to_s.hash].join("|")
  rescue
    ""
  end

  def self.mini_name_lineage_cache_valid?(model_id, project_file, source_sig)
    @mini_name_lineage.is_a?(Hash) &&
      @mini_name_lineage_model_id == model_id &&
      @mini_name_lineage_project_file.to_s == project_file.to_s &&
      @mini_name_lineage_source_sig.to_s == source_sig.to_s
  rescue
    false
  end

  def self.parse_mini_name_lineage_payload(raw_model)
    parsed = raw_model.to_s.empty? ? {} : JSON.parse(raw_model)
    parsed.is_a?(Hash) ? parsed : {}
  rescue
    {}
  end

  # === mini_import_accept_lineage_lookup.rb ===
  # --- mini_import_accept_lineage_lookup.rb ---
# MH_Thongke - Mini Import name lineage lookup and matching.


  def self.mini_lineage_product_keys(product_code)
    exact = product_code_exact(product_code)
    base = product_code_base(product_code)
    [exact, base].reject { |value| value.to_s.empty? || value == "--" }.uniq
  rescue
    [product_code.to_s.upcase]
  end

  def self.mini_lineage_lookup
    ensure_mini_name_lineage
    return @mini_lineage_lookup_cache if @mini_lineage_lookup_cache.is_a?(Hash)

    lookup = {}
    (@mini_name_lineage || {}).each do |lineage_key, row|
      product = product_code_exact(row["product_code"])
      kind = row["kind"].to_s.empty? ? "PK" : row["kind"].to_s
      Array(row["aliases"]).each do |alias_norm|
        next if alias_norm.to_s.empty?

        lookup[[product, kind, alias_norm.to_s]] ||= []
        lookup[[product, kind, alias_norm.to_s]] << lineage_key
      end
    end
    @mini_lineage_lookup_cache = lookup
  rescue
    {}
  end

  def self.mini_name_lineage_relation(product_code, kind, model_name, target_name)
    kind_text = kind.to_s.empty? ? "PK" : kind.to_s
    model_norm = mini_accept_norm(kind_text, model_name)
    target_norm = mini_accept_norm(kind_text, target_name)
    return nil if model_norm.empty? || target_norm.empty?

    lookup = mini_lineage_lookup
    model_keys = []
    target_keys = []
    mini_lineage_product_keys(product_code).each do |product|
      model_keys.concat(Array(lookup[[product, kind_text, model_norm]]))
      target_keys.concat(Array(lookup[[product, kind_text, target_norm]]))
    end
    model_keys.uniq!
    target_keys.uniq!
    return nil if model_keys.empty? && target_keys.empty?
    return :same if (model_keys & target_keys).any?
    return :separate if model_keys.any? && target_keys.any?

    nil
  rescue
    nil
  end

  def self.mini_item_names_related?(product_code, kind, model_name, target_name)
    return true if import_names_match?(model_name, target_name)

    relation = mini_name_lineage_relation(product_code, kind, model_name, target_name)
    return true if relation == :same
    return false if relation == :separate

    mini_names_related?(model_name, target_name)
  rescue
    mini_names_related?(model_name, target_name)
  end

  # === mini_import_accept_lineage_record.rb ===
  # --- mini_import_accept_lineage_record.rb ---
# MH_Thongke - Mini Import name lineage recording and migration.


  def self.record_mini_name_lineage(product_code, kind, from_name, to_name, spec = "", action = "accept", source = "mini_import")
    kind_text = kind.to_s.empty? ? "PK" : kind.to_s
    from_text = fix_vietnamese_mojibake(from_name).to_s.strip
    to_text = fix_vietnamese_mojibake(to_name).to_s.strip
    return false if from_text.empty? || to_text.empty?

    from_norm = mini_accept_norm(kind_text, from_text)
    to_norm = mini_accept_norm(kind_text, to_text)
    return false if from_norm.empty? || to_norm.empty?

    ensure_mini_name_lineage
    product = product_code_exact(product_code)
    now_text = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    lookup = mini_lineage_lookup
    existing_keys = []
    mini_lineage_product_keys(product).each do |prod|
      existing_keys.concat(Array(lookup[[prod, kind_text, from_norm]]))
      existing_keys.concat(Array(lookup[[prod, kind_text, to_norm]]))
    end
    existing_keys = existing_keys.uniq

    if existing_keys.empty?
      root_norm = from_norm
      lineage_key = [product, kind_text, root_norm].join("|")
      @mini_name_lineage[lineage_key] ||= {
        "product_code" => product,
        "kind" => kind_text,
        "root_name" => from_text,
        "root_norm" => root_norm,
        "aliases" => [],
        "display_names" => [],
        "chain" => [],
        "created_at" => now_text
      }
    else
      lineage_key = existing_keys.shift
      existing_keys.each do |other_key|
        next if other_key == lineage_key

        target = @mini_name_lineage[lineage_key] ||= {}
        other = @mini_name_lineage.delete(other_key) || {}
        target["aliases"] = (Array(target["aliases"]) + Array(other["aliases"])).uniq
        target["display_names"] = (Array(target["display_names"]) + Array(other["display_names"])).uniq
        target["chain"] = (Array(target["chain"]) + Array(other["chain"])).uniq
      end
    end

    row = @mini_name_lineage[lineage_key]
    row["product_code"] = product
    row["kind"] = kind_text
    row["root_name"] = from_text if row["root_name"].to_s.empty?
    row["root_norm"] = from_norm if row["root_norm"].to_s.empty?
    row["aliases"] = (Array(row["aliases"]) + [from_norm, to_norm]).uniq
    row["display_names"] = (Array(row["display_names"]) + [from_text, to_text]).reject(&:empty?).uniq
    row["chain"] ||= []
    step = {
      "time" => Time.now.to_i,
      "product_code" => product,
      "kind" => kind_text,
      "from" => from_text,
      "from_norm" => from_norm,
      "to" => to_text,
      "to_norm" => to_norm,
      "action" => action.to_s,
      "spec" => spec.to_s,
      "source" => source.to_s
    }
    row["chain"] << step unless row["chain"].any? { |item|
      item["from_norm"].to_s == from_norm &&
        item["to_norm"].to_s == to_norm &&
        item["action"].to_s == action.to_s &&
        item["spec"].to_s == spec.to_s
    }
    row["updated_at"] = now_text
    reset_mini_rule_caches(lineage: true, accept: false, refresh: true)
    true
  rescue => e
    puts "record_mini_name_lineage error: #{e.message}"
    false
  end

  def self.seed_mini_name_lineage_from_accept_rules(rules)
    return false unless rules.is_a?(Hash) && rules.any?
    return false if @mini_lineage_seeding

    @mini_lineage_seeding = true
    changed = false
    rules.each do |key, val|
      parts = key.to_s.split("|", 5)
      data = val.is_a?(Hash) ? val : {}
      product = data["product_code"].to_s.empty? ? parts[0].to_s : data["product_code"].to_s
      kind = data["kind"].to_s.empty? ? parts[1].to_s : data["kind"].to_s
      model_name = data["model_name"].to_s.empty? ? parts[2].to_s : data["model_name"].to_s
      target_name = data["target_name"].to_s.empty? ? parts[3].to_s : data["target_name"].to_s
      spec = data["spec"].to_s.empty? ? parts[4].to_s : data["spec"].to_s
      action = data["action"].to_s.empty? ? val.to_s : data["action"].to_s
      next if model_name.to_s.empty? || target_name.to_s.empty?
      next if ["accept_no_spec", "add", "manual_add"].include?(action)

      changed = true if record_mini_name_lineage(product, kind, model_name, target_name, spec, action, "accept_rule_migration")
    end
    changed
  ensure
    @mini_lineage_seeding = false
  end

  # === mini_import_accept_lineage.rb ===
  # --- mini_import_accept_lineage.rb ---
# MH_Thongke - Mini Import name lineage entrypoint.
#
# Logic is split into:
# - mini_import_accept_lineage_store.rb
# - mini_import_accept_lineage_lookup.rb
# - mini_import_accept_lineage_record.rb


  # --- Alias methods (without mini_ prefix) for backward-compatible rename ---
  def self.name_lineage_source_signature(*a, **kw, &b); mini_name_lineage_source_signature(*a, **kw, &b); end
  def self.name_lineage_cache_valid?(*a, **kw, &b); mini_name_lineage_cache_valid?(*a, **kw, &b); end
  def self.lineage_product_keys(*a, **kw, &b); mini_lineage_product_keys(*a, **kw, &b); end
  def self.name_lineage_relation(*a, **kw, &b); mini_name_lineage_relation(*a, **kw, &b); end
  def self.item_names_related?(*a, **kw, &b); mini_item_names_related?(*a, **kw, &b); end

  def self.lineage_lookup(*a, **kw, &b); mini_lineage_lookup(*a, **kw, &b); end
end