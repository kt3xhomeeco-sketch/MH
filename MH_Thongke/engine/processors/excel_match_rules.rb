# encoding: utf-8
# MH_Thongke — Excel Match Rules
#
# Source of truth for name matching: a user-editable .xlsx file.
# Goals:
#   - Replace the maze of family/token/lineage Ruby code with declarable rules.
#   - Let users add rules by editing Excel, no code touch.
#
# File: <DATA_DIR>/MH_Thongke_Match_Rules.xlsx
#
# Sheet 1: "matches"
#   Columns: Product | Kind | Model Pattern | Excel Pattern | Action | Note
#   - Product: SP31 / * (any product)
#   - Kind: PK / VL / * (any kind)
#   - Model Pattern: model name (or * = any, supports * wildcard)
#   - Excel Pattern: Excel hw_name (or * = any, supports * wildcard)
#   - Action: match / reject / model_only
#   - Note: free text for user
#
# Sheet 2: "synonyms"
#   Columns: Term A | Term B | Note
#   - Both terms get normalized to ASCII lowercase (đ→d, è→e, …)
#   - Matching is bidirectional: A↔B
#   - When checking if name X matches name Y, system also checks
#     all synonym chains: X→A→B and Y→A→B
#
# Sheet 3: "ignore_words"
#   Columns: Word | Note
#   - Words stripped before token comparison ("hafele", "blum", etc.)
#
# Sheet 4: "variants"
#   Columns: Family Pattern | Variant Regex | Note
#   - Family Pattern (normalized): which name family does this apply to?
#     e.g. "ray bi" applies to any name containing "ray bi"
#   - Variant Regex: pattern to extract the meaningful variant token
#     e.g. "\d{3}" for sizes 200..500
#     e.g. "(?<=ban le )[A-Z](?=\b|\z)" for "bản lề A/B/C"
#   - Rule: if BOTH names match the family AND both extract a variant,
#     the variants must be EQUAL. Otherwise it's a conflict → no match.
#   - If only one side has a variant, no conflict (subset allowed).
#   - Example:
#     ray bi    | \d{3}        | length 200-500 must match
#     ray am    | \d{3}        | length must match
#     ban le    | \b[A-Z]\b    | letter variant A/B/C must match
#
# Runtime API:
#   - excel_match_rule(product, kind, model, target) → :match | :reject | :model_only | nil
#   - excel_synonyms_match?(a, b) → true/false
#   - excel_ignore_word?(word) → true/false
#   - excel_variant_conflict?(model, target) → true if both names have
#     conflicting variants (different values for same family)

module MH_Thongke

  EXCEL_MATCH_RULES_FILE = File.join(DATA_DIR, "MH_Thongke_Match_Rules.xlsx") unless defined?(EXCEL_MATCH_RULES_FILE)
  EXCEL_MATCH_RULES_RELOAD_INTERVAL = 5.0 unless const_defined?(:EXCEL_MATCH_RULES_RELOAD_INTERVAL)

  # === Cache ===
  # @excel_match_rules = [ {product, kind, model_pattern, excel_pattern, action, note}, … ]
  # @excel_synonyms    = [ {a, b, note}, … ]
  # @excel_ignore_words = Set of normalized words

  def self.excel_match_rules
    ensure_excel_match_rules_loaded
    @excel_match_rules || []
  end

  def self.excel_synonyms
    ensure_excel_match_rules_loaded
    @excel_synonyms || []
  end

  def self.excel_ignore_words
    ensure_excel_match_rules_loaded
    @excel_ignore_words ||= Set.new
  end

  def self.excel_variants
    ensure_excel_match_rules_loaded
    @excel_variants || []
  end

  def self.ensure_excel_match_rules_loaded
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    if @excel_match_rules_loaded_at.to_f > 0 &&
       (now - @excel_match_rules_loaded_at.to_f) < EXCEL_MATCH_RULES_RELOAD_INTERVAL
      return
    end
    @excel_match_rules_loaded_at = now

    path = EXCEL_MATCH_RULES_FILE
    if !File.exist?(path)
      @excel_match_rules ||= []
      @excel_synonyms ||= []
      @excel_ignore_words ||= Set.new
      return
    end

    current_mtime = File.mtime(path).to_f rescue 0.0
    return if @excel_match_rules_loaded_mtime.to_f == current_mtime && @excel_match_rules

    load_match_rules_from_excel(path)
    @excel_match_rules_loaded_mtime = current_mtime
  rescue => e
    puts "ensure_excel_match_rules_loaded error: #{e.message}" rescue nil
  end

  def self.load_match_rules_from_excel(path = EXCEL_MATCH_RULES_FILE)
    return false unless File.exist?(path)

    begin
      wb = MH::ExcelBridge.read_all(path)

      @excel_match_rules = read_excel_match_sheet(wb)
      @excel_synonyms    = read_excel_synonyms_sheet(wb)
      @excel_ignore_words = read_excel_ignore_words_sheet(wb)
      @excel_variants    = read_excel_variants_sheet(wb)

      puts "MH_Thongke: loaded #{@excel_match_rules.size} match rules, #{@excel_synonyms.size} synonyms, #{@excel_ignore_words.size} ignore words, #{@excel_variants.size} variant patterns from #{File.basename(path)}"
      true
    rescue => e
      puts "load_match_rules_from_excel error: #{e.message}" rescue nil
      false
    end
  end

  def self.read_excel_match_sheet(wb)
    sheet = excel_find_sheet(wb, "matches")
    return [] unless sheet && sheet.size > 1

    rows = []
    sheet.drop(1).each do |row|
      product = excel_cell_text(row, 1)
      kind    = excel_cell_text(row, 2)
      model_p = excel_cell_text(row, 3)
      excel_p = excel_cell_text(row, 4)
      action  = excel_cell_text(row, 5).to_s.downcase.strip
      note    = excel_cell_text(row, 6)
      next if product.empty? && kind.empty? && model_p.empty? && excel_p.empty?
      next if action.empty?

      rows << {
        product: product.upcase.strip,
        kind:    kind.upcase.strip,
        model_pattern: model_p,
        excel_pattern: excel_p,
        action:  action,
        note:    note
      }
    end
    rows
  rescue
    []
  end

  def self.read_excel_synonyms_sheet(wb)
    sheet = excel_find_sheet(wb, "synonyms")
    return [] unless sheet && sheet.size > 1

    rows = []
    sheet.drop(1).each do |row|
      a = excel_cell_text(row, 1)
      b = excel_cell_text(row, 2)
      note = excel_cell_text(row, 3)
      next if a.empty? || b.empty?
      rows << { a: a, b: b, note: note }
    end
    rows
  rescue
    []
  end

  def self.read_excel_variants_sheet(wb)
    sheet = excel_find_sheet(wb, "variants")
    return [] unless sheet && sheet.size > 1

    rows = []
    sheet.drop(1).each do |row|
      family  = excel_cell_text(row, 1)
      pattern = excel_cell_text(row, 2)
      note    = excel_cell_text(row, 3)
      next if family.empty? || pattern.empty?
      compiled = begin
        Regexp.new(pattern, Regexp::IGNORECASE)
      rescue
        nil
      end
      next unless compiled

      rows << {
        family: import_name_norm(family),
        regex:  compiled,
        note:   note
      }
    end
    rows
  rescue
    []
  end

  def self.read_excel_ignore_words_sheet(wb)
    sheet = excel_find_sheet(wb, "ignore_words")
    return Set.new unless sheet && sheet.size > 1

    words = Set.new
    sheet.drop(1).each do |row|
      w = excel_cell_text(row, 1)
      next if w.empty?
      words << import_name_norm(w)
    end
    words
  rescue
    Set.new
  end

  def self.excel_find_sheet(wb, name)
    return nil unless wb.respond_to?(:each)
    pair = wb.find { |sheet_name, _rows| sheet_name.to_s.downcase == name.to_s.downcase }
    pair ? pair[1] : nil
  rescue
    nil
  end

  def self.excel_cell_text(row, col)
    v = Array(row)[col.to_i - 1]
    v.nil? ? "" : v.to_s.strip
  rescue
    ""
  end

  # === Matching engine ===

  # Returns :match | :reject | :model_only | nil
  def self.excel_match_rule(product_code, kind, model_name, target_name)
    rules = excel_match_rules
    return nil if rules.empty?

    product = product_code_exact(product_code).to_s.upcase rescue product_code.to_s.upcase
    product_base = (product_code_base(product_code).to_s.upcase rescue "")
    kind_norm = kind.to_s.upcase
    model_norm = import_name_norm(model_name)
    target_norm = import_name_norm(target_name)

    # Iterate rules in declared order. First match wins.
    rules.each do |rule|
      # Reject "match-all" rules (both name patterns blank/wildcard) — too liberal,
      # they'd silently approve every pair. User must specify at least one side.
      mp = rule[:model_pattern].to_s.strip
      ep = rule[:excel_pattern].to_s.strip
      mp_all = mp.empty? || mp == "*"
      ep_all = ep.empty? || ep == "*"
      next if mp_all && ep_all

      next unless rule_product_matches?(rule[:product], product, product_base)
      next unless rule_kind_matches?(rule[:kind], kind_norm)
      next unless excel_pattern_matches?(rule[:model_pattern], model_norm)
      next unless excel_pattern_matches?(rule[:excel_pattern], target_norm)

      # Blank-pattern semantics (distinct from `*` wildcard):
      # - Blank model pattern + non-blank model_norm in query → rule only applies
      #   in model-only context (query model empty), so skip here.
      # - Blank excel pattern + non-blank target_norm in query → rule only applies
      #   in excel-only / accept-no-spec context, so skip here.
      next if mp.empty? && !model_norm.empty?
      next if ep.empty? && !target_norm.empty?

      return rule[:action].to_sym if %w[match reject model_only].include?(rule[:action])
    end
    nil
  rescue
    nil
  end

  def self.rule_product_matches?(rule_product, product, product_base)
    return true if rule_product.empty? || rule_product == "*"
    return true if rule_product == product
    return true if !product_base.empty? && rule_product == product_base
    false
  end

  def self.rule_kind_matches?(rule_kind, kind_norm)
    return true if rule_kind.empty? || rule_kind == "*"
    rule_kind == kind_norm
  end

  # Pattern supports * wildcard. Empty pattern means *.
  def self.excel_pattern_matches?(pattern, normalized_value)
    return true if pattern.to_s.strip.empty? || pattern.strip == "*"

    pattern_norm = import_name_norm(pattern)
    return true if pattern_norm == normalized_value

    # Convert * to .* in regex, anchor full match
    regex_src = "\\A" + Regexp.escape(pattern_norm).gsub('\\*', '.*') + "\\z"
    !!Regexp.new(regex_src).match(normalized_value)
  rescue
    false
  end

  # Check if two names are synonyms (bidirectional).
  # Builds an equivalence-class lookup once per cache cycle.
  def self.excel_synonyms_match?(name_a, name_b)
    return false if name_a.to_s.empty? || name_b.to_s.empty?

    classes = excel_synonyms_classes
    norm_a = import_name_norm(name_a)
    norm_b = import_name_norm(name_b)

    classes.any? { |klass| klass.include?(norm_a) && klass.include?(norm_b) }
  rescue
    false
  end

  def self.excel_synonyms_classes
    ensure_excel_match_rules_loaded
    return @excel_synonyms_classes if @excel_synonyms_classes &&
                                      @excel_synonyms_classes_mtime == @excel_match_rules_loaded_mtime

    # Build union-find equivalence classes from synonym pairs
    parent = {}
    find = lambda do |x|
      until parent[x] == x
        parent[x] = parent[parent[x]] if parent[parent[x]]
        x = parent[x]
      end
      x
    end
    union = lambda do |x, y|
      parent[x] ||= x
      parent[y] ||= y
      rx = find.call(x)
      ry = find.call(y)
      parent[rx] = ry unless rx == ry
    end

    (excel_synonyms || []).each do |pair|
      a = import_name_norm(pair[:a])
      b = import_name_norm(pair[:b])
      next if a.empty? || b.empty?
      union.call(a, b)
    end

    classes_map = Hash.new { |h, k| h[k] = Set.new }
    parent.each { |term, _| classes_map[find.call(term)] << term }

    @excel_synonyms_classes = classes_map.values
    @excel_synonyms_classes_mtime = @excel_match_rules_loaded_mtime
    @excel_synonyms_classes
  end

  # Returns true if two names belong to the same variant family AND have
  # DIFFERENT variant values. E.g. "ray bi 500" vs "ray bi 450" → true.
  # "ray bi" vs "ray bi 500" → false (one missing variant = compatible).
  # "ban le A" vs "ban le B" → true.
  def self.excel_variant_conflict?(name_a, name_b)
    variants = excel_variants
    return false if variants.empty? || name_a.to_s.empty? || name_b.to_s.empty?

    norm_a = import_name_norm(name_a)
    norm_b = import_name_norm(name_b)

    variants.each do |v|
      family = v[:family]
      next if family.empty?
      # Family must be present in BOTH names to apply this variant rule
      next unless norm_a.include?(family) && norm_b.include?(family)

      val_a = extract_variant_value(norm_a, v[:regex])
      val_b = extract_variant_value(norm_b, v[:regex])
      next if val_a.nil? || val_b.nil?
      return true if val_a != val_b
    end
    false
  rescue
    false
  end

  def self.extract_variant_value(text, regex)
    m = text.match(regex)
    return nil unless m
    (m[1] || m[0]).to_s.downcase.strip
  rescue
    nil
  end

  # Returns true if two names share a variant family AND extract the SAME
  # variant value. E.g. "ray bi 500" vs "ray bi giảm chấn hafele 500" → true.
  # Positive companion to excel_variant_conflict?:
  #   conflict?  → both have variants, different → REJECT
  #   agreement? → both have variants, same     → STRONG MATCH SIGNAL
  #   neither    → variants don't apply         → fall through
  def self.excel_variant_agreement?(name_a, name_b)
    variants = excel_variants
    return false if variants.empty? || name_a.to_s.empty? || name_b.to_s.empty?

    norm_a = import_name_norm(name_a)
    norm_b = import_name_norm(name_b)

    variants.each do |v|
      family = v[:family]
      next if family.empty?
      next unless norm_a.include?(family) && norm_b.include?(family)

      val_a = extract_variant_value(norm_a, v[:regex])
      val_b = extract_variant_value(norm_b, v[:regex])
      next if val_a.nil? || val_b.nil?
      return true if val_a == val_b
    end
    false
  rescue
    false
  end

  def self.excel_ignore_word?(word)
    ensure_excel_match_rules_loaded
    return false if word.to_s.empty?
    norm = import_name_norm(word)
    excel_ignore_words.include?(norm)
  rescue
    false
  end

  # === Export current accept rules → Excel ===

  def self.export_match_rules_to_excel(path = EXCEL_MATCH_RULES_FILE)
    FileUtils.mkdir_p(File.dirname(path)) rescue nil

    begin
      wb = File.exist?(path) ? MH::ExcelBridge.read_all(path) : {}
      wb["matches"] = ensure_or_create_matches_sheet(wb["matches"])
      wb["synonyms"] = ensure_or_create_synonyms_sheet(wb["synonyms"])
      wb["ignore_words"] = ensure_or_create_ignore_words_sheet(wb["ignore_words"])
      wb["variants"] = ensure_or_create_variants_sheet(wb["variants"])
      wb = wb.select { |name, _rows| %w[matches synonyms ignore_words variants].include?(name.to_s.downcase) }
      MH::ExcelBridge.write(path, sheets: wb)

      puts "MH_Thongke: exported match rules to #{path}"
      path
    rescue => e
      puts "export_match_rules_to_excel error: #{e.message}" rescue nil
      nil
    end
  end

  def self.ensure_or_create_matches_sheet(sheet)
    headers = ["Product", "Kind", "Model Pattern", "Excel Pattern", "Action", "Note"]
    rows = normalize_sheet_rows(sheet, headers)

    return rows if rows.size > 1

    rules = ensure_mini_accept_rules || {}
    rules.each do |key, val|
      next unless val.is_a?(Hash)
      product = val["product_code"].to_s.strip
      kind    = val["kind"].to_s.strip
      model   = val["model_name"].to_s.strip
      target  = val["target_name"].to_s.strip
      action_old = val["action"].to_s.strip

      # Skip rules where ALL of product / model / target are empty — too liberal.
      # Such a rule would match every pair.
      next if product.empty? && model.empty? && target.empty?
      # Also skip rules with only kind set
      next if model.empty? && target.empty?

      action_new = case action_old
                   when "accept", "update", "rename_update", "manual_add" then "match"
                   when "keep", "accept_no_spec" then "model_only"
                   else "match"
                   end

      rows << [product, kind, model, target, action_new, "Migrated from JSON (#{action_old})"]
    end
    rows
  end

  def self.ensure_or_create_synonyms_sheet(sheet)
    headers = ["Term A", "Term B", "Note"]
    rows = normalize_sheet_rows(sheet, headers)

    return rows if rows.size > 1

    # Seed from hard-coded synonyms in DEFAULT_GENERAL_RULES
    pairs = []
    pairs.concat(Array((DEFAULT_GENERAL_RULES["synonym_pairs"] rescue []) || []))
    pairs.concat(Array((DEFAULT_GENERAL_RULES["equivalent_pairs"] rescue []) || []))
    # Seed common hardware family synonyms. Bidirectional union-find means
    # adding (A↔B) and (B↔C) automatically makes A↔C through the same class.
    # So a generic name like "đèn led" reaches every more-specific variant.
    pairs << ["đèn led", "đèn led trung tính"]
    pairs << ["đèn led trung tính", "đèn led trung tính góc 45"]
    pairs << ["đèn led", "đèn led ấm"]
    pairs << ["đèn led", "đèn led lạnh"]
    pairs << ["đèn led", "đèn led 60w"]
    pairs << ["nguồn led", "nguồn led 60w"]
    pairs << ["nguồn led", "nguồn led 100w"]
    pairs << ["nguồn led", "nguồn led 200w"]
    pairs << ["thanh nhôm led", "thanh nhôm led"]
    pairs << ["ray bi", "ray bi giảm chấn"]
    pairs << ["ray bi", "ray bi giảm chấn hafele"]
    pairs << ["ray bi", "ray bi giảm chấn blum"]
    pairs << ["ray âm", "ray âm giảm chấn"]
    pairs << ["ray âm", "ray âm giảm chấn hafele"]
    pairs << ["bản lề", "bản lề giảm chấn"]
    pairs << ["bản lề", "bản lề giảm chấn hafele"]
    pairs << ["bản lề", "bản lề blum"]
    pairs << ["suốt áo", "suốt áo hafele"]
    pairs << ["cảm biến", "cảm biến chạm"]

    pairs.uniq.each do |pair|
      next unless pair.is_a?(Array) && pair.size >= 2
      rows << [pair[0].to_s, pair[1].to_s, "Seed"]
    end
    rows
  end

  def self.ensure_or_create_variants_sheet(sheet)
    headers = ["Family Pattern", "Variant Regex", "Note"]
    rows = normalize_sheet_rows(sheet, headers)

    return rows if rows.size > 1

    seed = [
      ["ray bi",  '\b(200|250|300|350|400|450|500|550|600)\b', "Length 200..600 must match between ray bi variants"],
      ["ray am",  '\b(200|250|300|350|400|450|500|550|600)\b', "Length 200..600 must match between ray am variants"],
      ["suot ao", '\b(200|250|300|350|400|450|500|550|600|700|800|900|1000)\b', "Length variant for suot ao"],
      ["ban le",  '\b([A-C])\b',                                "Letter variant A/B/C for ban le must match"]
    ]
    seed.each do |family, pattern, note|
      rows << [family, pattern, note]
    end
    rows
  end

  def self.ensure_or_create_ignore_words_sheet(sheet)
    headers = ["Word", "Note"]
    rows = normalize_sheet_rows(sheet, headers)

    return rows if rows.size > 1

    seed = %w[hafele blum hettich cái bộ phụ kiện hàng loại màu]
    seed.each do |w|
      rows << [w, "Seed: brand/noise word"]
    end
    rows
  end

  def self.normalize_sheet_rows(sheet, headers)
    rows = Array(sheet).map { |row| Array(row) }
    if rows.empty?
      [headers]
    else
      rows[0] = headers
      rows
    end
  end

  # === Integration hook for existing matching code ===
  #
  # Wrap mini_pk_model_name_match? to consult Excel rules first.
  # Excel :match → returns true (accept)
  # Excel :reject → returns false (don't match)
  # Excel :model_only → returns false here (only used in model-only context)
  # Excel nil → fall through to original logic

  def self.excel_match_check(product_code, kind, model_name, target_name)
    action = excel_match_rule(product_code, kind, model_name, target_name)
    case action
    when :match  then true
    when :reject then false
    else nil
    end
  end

end
