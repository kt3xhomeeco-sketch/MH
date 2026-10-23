# encoding: utf-8
# MH_Thongke — matching rules processor
# Logic xử lý dùng chung cho Mini Import và các bảng thống kê.
module MH_Thongke

  # === mini_import_rules.rb ===
  # --- mini_import_rules.rb ---
# MH_Thongke - Mini Import rules entrypoint.
#
# Logic is split into:
# - mini_import_rules_names.rb
# - mini_import_rules_hardware.rb
# - mini_import_rules_grouping.rb


  remove_const(:MATERIAL_CODE_NORM_VERSION) if const_defined?(:MATERIAL_CODE_NORM_VERSION)
  MATERIAL_CODE_NORM_VERSION = 4

  # === mini_import_rules_names.rb ===
  # --- mini_import_rules_names.rb ---
# MH_Thongke - name normalization and equivalent matching.


  # Memoization caches for name normalization (invalidated when rules change)
  @import_name_norm_cache = {}
  @import_equiv_norm_cache = {}

  def self.import_name_norm(s)
    return "" if s.nil?
    key = s.to_s
    return @import_name_norm_cache[key] if @import_name_norm_cache.is_a?(Hash) && @import_name_norm_cache.key?(key)

    norm = cached_norm(key)
    pairs = (@general_rules && @general_rules["synonym_pairs"]).is_a?(Array) ? @general_rules["synonym_pairs"] : []
    pairs = DEFAULT_GENERAL_RULES["synonym_pairs"] if pairs.empty? && defined?(DEFAULT_GENERAL_RULES)
    pairs.each do |pair|
      next unless pair.is_a?(Array) && pair.size >= 2
      a = pair[0].to_s.strip
      b = pair[1].to_s.strip
      next if a.empty? || b.empty?
      canon = b
      norm = norm.gsub(/\b#{Regexp.escape(a)}\b/, canon)
      norm = norm.gsub(/\b#{Regexp.escape(b)}\b/, canon)
    end
    @import_name_norm_cache = {} if !@import_name_norm_cache.is_a?(Hash) || @import_name_norm_cache.size > 4000
    @import_name_norm_cache[key] = norm
    norm
  end

  def self.import_equivalent_norm(s)
    key = s.to_s
    return @import_equiv_norm_cache[key] if @import_equiv_norm_cache.is_a?(Hash) && @import_equiv_norm_cache.key?(key)

    norm = import_name_norm(s)
    pairs = (@general_rules && @general_rules["equivalent_pairs"]).is_a?(Array) ? @general_rules["equivalent_pairs"] : []
    pairs = DEFAULT_GENERAL_RULES["equivalent_pairs"] if pairs.empty? && defined?(DEFAULT_GENERAL_RULES)
    pairs = [] unless pairs.is_a?(Array)
    pairs.each do |pair|
      next unless pair.is_a?(Array) && pair.size >= 2
      from = pair[0].to_s.strip
      to = pair[1].to_s.strip
      next if from.empty? || to.empty?
      norm = norm.gsub(/\b#{Regexp.escape(from)}\b/, to)
    end
    result = norm.gsub(/\s+/, " ").strip
    @import_equiv_norm_cache = {} if !@import_equiv_norm_cache.is_a?(Hash) || @import_equiv_norm_cache.size > 4000
    @import_equiv_norm_cache[key] = result
    result
  end

  def self.import_names_match?(a, b)
    na = import_name_norm(a)
    nb = import_name_norm(b)
    return true if !na.empty? && na == nb
    return false if respond_to?(:led_light_strict_mismatch?) && led_light_strict_mismatch?(a, b)

    ea = import_equivalent_norm(a)
    eb = import_equivalent_norm(b)
    !ea.empty? && ea == eb
  end

  def self.led_light_strict_pair?(a, b)
    fa = mini_name_family_key(a)
    fb = mini_name_family_key(b)
    fa == :led_light && fb == :led_light
  rescue
    false
  end

  def self.led_light_exact_match?(a, b)
    led_light_strict_pair?(a, b) && !import_name_norm(a).empty? && import_name_norm(a) == import_name_norm(b)
  rescue
    false
  end

  def self.led_light_strict_mismatch?(a, b)
    led_light_strict_pair?(a, b) && !led_light_exact_match?(a, b)
  rescue
    false
  end

  def self.strip_product_code_prefix(value)
    text = value.to_s.strip
    code = respond_to?(:product_codes_from_text) ? product_codes_from_text(text).first : nil
    if code && text.upcase.start_with?(code.to_s.upcase)
      text[code.length..-1].to_s.sub(/\A[\s_\-]+/, "").strip
    else
      text.sub(/\A[A-Z]+\d+[A-Z]?(?:\.\d+)?[\s_\-]+/i, "").strip
    end
  end

  def self.mini_accept_norm(kind, value)
    kind.to_s == "VL" ? material_code_norm(value) : import_name_norm(value)
  end

  # === mini_import_rules_hardware.rb ===
  # --- mini_import_rules_hardware.rb ---
# MH_Thongke - hardware relation/equivalent rule helpers.


  def self.mini_name_family_key(value)
    norm = import_name_norm(value)
    return nil if norm.empty?

    has_led = norm.include?("led")
    return :sensor_touch if norm.include?("cam bien") || norm.include?("cham")
    return :led_power if has_led && (norm.include?("nguon") || norm.include?("driver") || norm.include?("adapter"))
    return :led_profile if has_led && (norm.include?("thanh nhom") || norm.include?("nhom led") || norm.include?("ray led"))
    return :led_light if has_led
    return :ray_am if norm.include?("ray am")
    return :ray_bi if norm.include?("ray bi")
    return :hinge if norm.include?("ban le")
    return :suot_ao if norm.include?("suot ao")

    nil
  end

  def self.mini_match_tokens(value)
    stop = %w[cai bo phu kien hang loai mau mm m md pcs pc hafele blum hettich]
    import_name_norm(value).split(/\s+/).map(&:strip).reject do |token|
      token.empty? || token.length <= 1 || stop.include?(token) || token =~ /\A\d+(?:mm)?\z/
    end.uniq
  rescue
    []
  end

  def self.mini_hardware_signature(value)
    norm = import_name_norm(value)
    return nil if norm.empty?

    family = mini_name_family_key(norm)
    case family
    when :ray_am, :ray_bi
      trait = norm.include?("giam chan") ? "giam_chan" : "std"
      "#{family}:#{trait}"
    when :hinge
      trait = norm.include?("giam chan") ? "giam_chan" : "std"
      hinge_type = import_hinge_type_token(value).to_s.downcase
      "#{family}:#{trait}:#{hinge_type}"
    when :suot_ao, :led_light, :led_power, :led_profile, :sensor_touch
      family.to_s
    else
      nil
    end
  rescue
    nil
  end

  def self.mini_names_related?(model_name, excel_name)
    return true if import_names_match?(model_name, excel_name)

    model_norm = import_name_norm(model_name)
    excel_norm = import_name_norm(excel_name)
    return false if model_norm.empty? || excel_norm.empty?
    return false if respond_to?(:led_light_strict_mismatch?) && led_light_strict_mismatch?(model_name, excel_name)

    model_family = mini_name_family_key(model_norm)
    excel_family = mini_name_family_key(excel_norm)
    return false if mini_family_conflict?(model_family, excel_family)

    signature_match = mini_signature_relation(model_name, excel_name, model_family, excel_family)
    return true if signature_match == :matched
    return false if signature_match == :conflict

    model_tokens = mini_match_tokens(model_norm)
    excel_tokens = mini_match_tokens(excel_norm)
    shared = model_tokens & excel_tokens
    return false if shared.empty?

    return true if mini_shared_tokens_satisfy_family?(shared, model_family, excel_family, model_tokens, excel_tokens)

    shorter, longer = [model_tokens, excel_tokens].sort_by(&:size)
    return true if shorter.size >= 2 && (shorter - longer).empty?

    shared.size >= 2 && shared.size.to_f / [model_tokens.size, excel_tokens.size].min >= 0.6
  rescue
    false
  end

  def self.mini_family_conflict?(model_family, excel_family)
    model_family && excel_family && model_family != excel_family
  rescue
    false
  end

  def self.mini_signature_relation(model_name, excel_name, model_family, excel_family)
    model_sig = mini_hardware_signature(model_name)
    excel_sig = mini_hardware_signature(excel_name)
    return :matched if model_sig && excel_sig && model_sig == excel_sig
    return :conflict if model_sig && excel_sig && model_sig != excel_sig &&
                        [model_family, excel_family].all? { |family| [:ray_am, :ray_bi, :hinge].include?(family) }

    :none
  rescue
    :none
  end

  def self.mini_shared_tokens_satisfy_family?(shared, model_family, excel_family, model_tokens, excel_tokens)
    return false unless model_family && excel_family && model_family == excel_family

    case model_family
    when :led_light
      shared.include?("den") || (shared - ["led"]).any?
    when :sensor_touch
      shared.size >= 1
    else
      shared.size >= 2 || (shared.size >= 1 && [model_tokens.size, excel_tokens.size].min <= 2)
    end
  rescue
    false
  end

  def self.import_equivalent_group_key(hw_name, spec = nil, kind = "PK")
    return nil if kind.to_s == "VL"

    text = [hw_name.to_s, spec.to_s].reject(&:empty?).join(" ")
    norm = import_name_norm(text)
    family = import_hardware_family(text)
    case family
    when :ray_bi, :ray_am
      trait = if norm.include?("toan phan")
        "giam_chan_toan_phan"
      elsif norm.include?("giam chan")
        "giam_chan"
      else
        "std"
      end
      "eq:rail:#{family}:#{trait}"
    when :hinge
      hinge_type = import_hinge_type_token(text).to_s.downcase
      trait = norm.include?("giam chan") ? "giam_chan" : "std"
      "eq:hinge:#{hinge_type}:#{trait}"
    when :suot_ao
      "eq:suot_ao"
    else
      nil
    end
  end

  def self.import_excel_specificity_score(hw_name, spec = nil)
    text = [hw_name.to_s, spec.to_s].reject(&:empty?).join(" ")
    norm = import_name_norm(text)
    score = norm.length
    score += 1000 if norm.include?("hafele")
    score += 500 if norm.include?("toan phan")
    score += 250 if norm.include?("giam chan")
    score += 100 if import_hardware_family(text)
    score
  end

  # === mini_import_rules_grouping.rb ===
  # --- mini_import_rules_grouping.rb ---
# MH_Thongke - grouping Excel items for Mini Import matching.


  def self.mini_group_excel_items(ex_items_raw, include_notes = false)
    exact_groups = {}
    ex_items_raw.each_with_index do |ex, order|
      hw = ex[:hw_name].to_s.strip
      next if hw.empty?

      spec = ex[:spec].to_s.strip
      kind = ex[:kind].to_s.empty? ? "PK" : ex[:kind].to_s
      ma_vl_source = (ex[:ma_vl_source] || ex["ma_vl_source"]).to_s.strip
      target_name = import_display_name(hw, spec)
      section = mini_excel_section_name(ex)
      display_sub = mini_excel_sub_text(ex, target_name)
      material_group = kind == "VL" ? mini_excel_material_group_parts(ex, hw, spec, display_sub) : nil
      if material_group
        key = [
          "vl",
          material_code_norm(ma_vl_source.empty? ? hw : ma_vl_source),
          import_name_norm(material_group[:quy_cach]),
          import_name_norm(material_group[:hoan_thien])
        ].join("|")
      else
        key = import_name_norm(target_name)
        key = "#{key}|sub:#{import_name_norm(display_sub)}" unless display_sub.empty?
        key = "#{key}|section:#{import_name_norm(section)}" unless section.empty?
        key = "vl:#{key}" if kind == "VL"
      end
      exact_groups[key] ||= { ma_sp: ex[:ma_sp].to_s, hw_name: hw, spec: spec, ma_vl_source: ma_vl_source, ghi_chu: "", notes: [], qty: 0, kind: kind, ten_sp: ex[:ten_sp].to_s, section: section, display_sub: display_sub, details: [], order: order }
      exact_groups[key][:qty] += 1
      exact_groups[key][:ma_sp] = ex[:ma_sp].to_s unless ex[:ma_sp].to_s.empty?
      exact_groups[key][:spec] = spec unless spec.empty?
      exact_groups[key][:ma_vl_source] = ma_vl_source unless ma_vl_source.empty?
      exact_groups[key][:ten_sp] = ex[:ten_sp].to_s unless ex[:ten_sp].to_s.empty?
      exact_groups[key][:section] = section unless section.empty?
      if material_group
        detail = material_group[:detail].to_s.strip
        exact_groups[key][:details] << detail unless detail.empty? || exact_groups[key][:details].include?(detail)
        exact_groups[key][:display_sub] = mini_excel_material_group_display_sub(
          exact_groups[key][:details],
          material_group[:quy_cach],
          material_group[:hoan_thien],
          display_sub
        )
      else
        exact_groups[key][:display_sub] = display_sub unless display_sub.empty?
      end
      exact_groups[key][:order] = [exact_groups[key][:order].to_i, order].min

      if include_notes
        note = ex[:ghi_chu].to_s.strip
        exact_groups[key][:notes] << note unless note.empty? || exact_groups[key][:notes].include?(note)
        exact_groups[key][:ghi_chu] = exact_groups[key][:notes].join(" | ")
      end
    end

    merged = {}
    exact_groups.values.each do |item|
      eq_key = import_equivalent_group_key(item[:hw_name], item[:spec], item[:kind])
      merge_key = eq_key || "#{item[:kind]}:#{import_name_norm(import_display_name(item[:hw_name], item[:spec]))}"
      section_key = import_name_norm(item[:section])
      sub_key = import_name_norm(item[:display_sub])
      merge_key = "#{merge_key}|section:#{section_key}" unless section_key.empty?
      merge_key = "#{merge_key}|sub:#{sub_key}" if (eq_key.nil? || item[:kind].to_s == "VL") && !sub_key.empty?
      # A single Excel detail may deliberately expand into multiple material
      # rows (for example LK063A + LKAFP16). They share the same description
      # and display text, but are distinct material choices and must remain
      # separate in both Mini Import and the on-screen Material HUD.
      if item[:kind].to_s == "VL"
        material_code_key = material_code_norm(item[:ma_vl_source])
        merge_key = "#{merge_key}|material:#{material_code_key}" unless material_code_key.empty?
      end
      if merged[merge_key]
        current = merged[merge_key]
        if import_excel_specificity_score(item[:hw_name], item[:spec]) > import_excel_specificity_score(current[:hw_name], current[:spec])
          current[:hw_name] = item[:hw_name]
          current[:spec] = item[:spec]
          current[:ma_vl_source] = item[:ma_vl_source]
          current[:ten_sp] = item[:ten_sp]
          current[:section] = item[:section]
          current[:display_sub] = item[:display_sub]
        end
        current[:ma_vl_source] = item[:ma_vl_source] if current[:ma_vl_source].to_s.empty? && !item[:ma_vl_source].to_s.empty?
        current[:qty] = [current[:qty].to_i, item[:qty].to_i].max
        current[:order] = [current[:order].to_i, item[:order].to_i].min
        if include_notes
          item[:notes].to_a.each { |note| current[:notes] << note unless note.empty? || current[:notes].include?(note) }
          current[:ghi_chu] = current[:notes].join(" | ")
        end
      else
        merged[merge_key] = {
          ma_sp: item[:ma_sp].to_s,
          hw_name: item[:hw_name],
          spec: item[:spec],
          ma_vl_source: item[:ma_vl_source].to_s,
          ghi_chu: item[:ghi_chu].to_s,
          notes: item[:notes].to_a.dup,
          qty: item[:qty].to_i,
          kind: item[:kind],
          ten_sp: item[:ten_sp].to_s,
          section: item[:section].to_s,
          display_sub: item[:display_sub].to_s,
          details: item[:details].to_a.dup,
          order: item[:order].to_i
        }
      end
    end

    merged.values.sort_by { |item| [item[:order].to_i, -import_excel_specificity_score(item[:hw_name], item[:spec]), import_name_norm(import_display_name(item[:hw_name], item[:spec]))] }
  end

  def self.mini_excel_material_group_parts(ex, hw, spec, display_sub)
    parts = Array(ex[:display_sub_parts] || ex["display_sub_parts"]).map(&:to_s).map(&:strip).reject(&:empty?)
    return nil if parts.length < 4

    {
      detail: parts[1],
      quy_cach: parts[2],
      hoan_thien: parts[3],
      display_sub: display_sub.to_s,
      hw: hw.to_s,
      spec: spec.to_s
    }
  rescue
    nil
  end

  def self.mini_excel_material_group_display_sub(details, quy_cach, hoan_thien, fallback)
    detail_text = Array(details).map(&:to_s).map(&:strip).reject(&:empty?).join(", ")
    spec_text = quy_cach.to_s.strip
    finish_text = hoan_thien.to_s.strip
    text = [detail_text, spec_text, finish_text].reject(&:empty?).join(" ")
    text.empty? ? fallback.to_s.strip : text
  end

  def self.mini_excel_material_row_display_sub(material_group, fallback)
    detail = material_group[:detail].to_s.strip
    quy_cach = material_group[:quy_cach].to_s.strip
    hoan_thien = material_group[:hoan_thien].to_s.strip
    text = import_display_sub_text(detail, quy_cach, hoan_thien)
    text.empty? ? fallback.to_s.strip : text
  rescue
    fallback.to_s.strip
  end

  # === mini_import_material_codes.rb ===
  # --- mini_import_material_codes.rb ---
# MH_Thongke - Material code normalization helpers.


  def self.material_code_norm(value)
    code = if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:normalize)
             MH::MaterialCode.normalize(value)
           else
             value.to_s.strip.upcase.gsub(/\s+/, "")
           end
    parts = code.split(".")
    parts.delete_at(1) if parts.size > 1 && parts[1].to_s =~ /\A\d+(?:\.\d+)?\z/
    parts = parts.reject { |part| part.to_s =~ /\A[12]M\z/i }
    parts = canonical_material_code_parts(parts)
    parts.join(".")
  end

  def self.material_code_variant_norm(value)
    code = if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:normalize)
             MH::MaterialCode.normalize(value)
           else
             value.to_s.strip.upcase.gsub(/\s+/, "")
           end
    parts = code.split(".")
    parts.delete_at(1) if parts.size > 1 && parts[1].to_s =~ /\A\d+(?:\.\d+)?\z/
    parts = parts.reject { |part| part.to_s =~ /\A[12]M\z/i }
    parts = canonical_material_code_parts(parts)
    parts.join(".")
  end

  def self.canonical_material_code_parts(parts)
    out = []
    parts.each do |part|
      next if part.to_s == "VER" && parts.any? { |other| other.to_s != "VER" && other.to_s.start_with?("VER") }
      out << part
    end
    out
  end

  # Display helper for model material code:
  # removes thickness token right after family prefix (e.g. PLY.9.AC -> PLY.AC)
  def self.material_code_display(value)
    text = fix_vietnamese_mojibake(value).to_s.strip
    return "" if text.empty?

    text = MH::MaterialCode.display(text) if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:display)
    parts = text.split(".")
    parts.delete_at(1) if parts.size > 1 && parts[1].to_s.strip =~ /\A\d+(?:\.\d+)?\z/
    parts = canonical_material_code_parts(parts) if respond_to?(:canonical_material_code_parts)
    parts.join(".").gsub(/\s+/, " ").strip
  rescue
    value.to_s
  end

  def self.material_code_subgroup?(value)
    value.to_s.strip.upcase.gsub(/\s+/, "").split(".").any? { |part| part =~ /\A[12]M\z/i }
  rescue
    false
  end

  def self.split_material_codes(value)
    text = fix_vietnamese_mojibake(value).strip
    return [] if text.empty?

    return MH::MaterialCode.split(text) if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:split)

    text.split(/\s*&\s*/).map(&:strip).reject(&:empty?)
  end

  # === mini_import_hardware_rules.rb ===
  # --- mini_import_hardware_rules.rb ---
# MH_Thongke - Mini Import hardware matching helpers.


  def self.import_length_token(*values)
    values.compact.each do |value|
      token = value.to_s.scan(/\b\d{3,4}\s*mm\b/i).first
      return token.gsub(/\s+/, "").downcase if token

      token = value.to_s.scan(/\b\d{3,4}\b/).first
      return token if token
    end
    nil
  end

  def self.import_hinge_type_token(*values)
    values.compact.each do |value|
      token = value.to_s.split(/\s+/).find { |t| t =~ /\A[A-C]\z/i }
      return token.upcase if token
    end
    nil
  end

  def self.import_remove_dimension_tokens(value)
    value.to_s.gsub(/\b\d{3,4}\s*mm\b/i, "").gsub(/\b\d{3,4}\b/, "").gsub(/\s+/, " ").strip
  end

  def self.import_remove_hinge_type_tokens(value)
    value.to_s.split(/\s+/).reject { |token| token =~ /\A[A-C]\z/i }.join(" ").strip
  end

  def self.import_display_name(hw_name, spec = nil)
    name = fix_vietnamese_mojibake(hw_name).strip
    suffix = fix_vietnamese_mojibake(spec).strip
    return suffix if name.empty?
    return name if suffix.empty?
    return name if import_name_norm(name).include?(import_name_norm(suffix))

    "#{name} #{suffix}".gsub(/\s+/, " ").strip
  end

  def self.import_hardware_family(value)
    norm = import_name_norm(value)
    return :ray_am if norm.include?("ray am")
    return :ray_bi if norm.include?("ray bi")
    return :hinge if norm.include?("ban le")
    return :suot_ao if norm.include?("suot ao")
    nil
  end

  def self.import_rail_display(family)
    family == :ray_am ? "ray \u00E2m" : "ray bi"
  end

  def self.special_hafele_update_name(ex_name, model_name, ex_spec = nil)
    ex_text = [ex_name, ex_spec].compact.join(" ")
    ex_norm = import_name_norm(ex_text)
    return nil unless ex_norm.include?("hafele")

    ex_family = import_hardware_family(ex_text)
    model_family = import_hardware_family(model_name)
    generic_hafele = ex_norm.include?("phu kien")

    if generic_hafele
      case model_family
      when :ray_bi, :ray_am
        length = import_length_token(model_name, ex_text)
        target = "#{import_rail_display(model_family)} gi\u1EA3m ch\u1EA5n hafele"
        target += " #{length}" if length
        return target
      when :hinge
        hinge_type = import_hinge_type_token(model_name, ex_text)
        target = "b\u1EA3n l\u1EC1 gi\u1EA3m ch\u1EA5n hafele"
        target += " #{hinge_type}" if hinge_type
        return target
      when :suot_ao
        base = model_name.to_s.strip.empty? ? "Su\u1ED1t \u00E1o" : import_remove_dimension_tokens(model_name)
        return "#{base} hafele".gsub(/\s+/, " ").strip
      end
    end

    if [:ray_bi, :ray_am].include?(ex_family) && [:ray_bi, :ray_am].include?(model_family)
      length = import_length_token(model_name, ex_text)
      base = import_remove_dimension_tokens(ex_text)
      target = base.empty? ? "#{import_rail_display(ex_family)} hafele" : base
      target += " #{length}" if length && !import_name_norm(target).split.include?(length)
      return target.gsub(/\s+/, " ").strip
    end

    if ex_family == :hinge && model_family == :hinge
      hinge_type = import_hinge_type_token(model_name, ex_text)
      base = import_remove_hinge_type_tokens(ex_text)
      target = base.empty? ? "b\u1EA3n l\u1EC1 hafele" : base
      target += " #{hinge_type}" if hinge_type && !import_name_norm(target).split.include?(hinge_type.downcase)
      return target.gsub(/\s+/, " ").strip
    end

    if ex_family == :suot_ao && model_family == :suot_ao
      base = ex_name.to_s.strip
      base += " #{ex_spec}" unless ex_spec.to_s.strip.empty?
      return base.gsub(/\s+/, " ").strip
    end

    # Excel named only the brand/trait but the model carries a known Hafele family.
    # MUST ALSO check Excel family \u2014 without it, Excel "b\u1EA3n l\u1EC1 gi\u1EA3m ch\u1EA5n" (hinge)
    # would wrongly match model "ray \u00E2m gi\u1EA3m ch\u1EA5n 400mm" just because both have
    # "gi\u1EA3m ch\u1EA5n" in the name.
    if ex_norm.include?("giam chan") &&
       [:ray_bi, :ray_am].include?(model_family) &&
       (ex_family.nil? || [:ray_bi, :ray_am].include?(ex_family))
      length = import_length_token(model_name, ex_text)
      target = "#{import_rail_display(model_family)}"
      target += " gi\u1EA3m ch\u1EA5n to\u00E0n ph\u1EA7n" if ex_norm.include?("toan phan")
      target += " gi\u1EA3m ch\u1EA5n" unless ex_norm.include?("toan phan")
      target += " hafele"
      target += " #{length}" if length
      return target
    end

    nil
  end

  # === mini_import_display_text.rb ===
  # --- mini_import_display_text.rb ---
# MH_Thongke - Mini Import display text helpers.


  def self.import_display_sub_text(*parts)
    out = []
    parts.flatten.compact.each do |part|
      text = fix_vietnamese_mojibake(part).strip
      next if text.empty?
      next if out.any? { |existing| import_name_norm(existing) == import_name_norm(text) }

      out << text
    end
    out.join(" ").gsub(/\s+/, " ").strip
  end

  def self.mini_excel_sub_text(ex, fallback = nil)
    parts = ex[:display_sub_parts] || ex["display_sub_parts"]
    text = import_display_sub_text(parts) unless parts.nil?
    text = ex[:display_sub].to_s.strip if text.to_s.empty? && ex.key?(:display_sub)
    text = fallback.to_s.strip if text.to_s.empty?
    text
  rescue
    fallback.to_s
  end

  def self.material_display_sub_redundant?(text, codes)
    text_norm = import_name_norm(text).gsub(/\s+/, " ").strip
    return true if text_norm.empty?

    text_compact = text_norm.gsub(/[^a-z0-9]+/, "")
    Array(codes).any? do |code|
      code_compact = import_name_norm(code).gsub(/[^a-z0-9]+/, "")
      next false if code_compact.empty?

      text_compact == code_compact
    end
  rescue
    false
  end

  def self.strip_material_code_display_text(text, codes)
    words = import_name_norm(text).split(/\s+/)
    raw_words = text.to_s.strip.split(/\s+/)
    return text.to_s.strip if words.empty?

    spans = []
    code_compacts = Array(codes).map { |code| import_name_norm(code).gsub(/[^a-z0-9]+/, "") }
                              .reject(&:empty?)
                              .uniq
    code_compacts.each do |code_compact|
      words.each_index do |start_idx|
        compact = ""
        (start_idx...words.size).each do |idx|
          compact << words[idx].gsub(/[^a-z0-9]+/, "")
          break if compact.length > code_compact.length
          next unless compact == code_compact

          spans << [start_idx, idx]
          break
        end
      end
    end
    return text.to_s.strip if spans.empty?

    remove = {}
    spans.each { |first, last| (first..last).each { |idx| remove[idx] = true } }
    raw_words.each_with_index.reject { |_, idx| remove[idx] }.map(&:first).join(" ").strip
  rescue
    text.to_s.strip
  end

  def self.material_display_preserve_plywood_text(text, codes)
    value = text.to_s.strip
    return value if value.empty?

    has_ply_material = Array(codes).any? { |code| material_code_norm(code).start_with?("PLY") }
    return value unless has_ply_material

    norm = import_name_norm(value)
    return value if norm.include?("plywood")

    if norm.include?("ply wood")
      return value.gsub(/\bPLY\s+WOOD\b/i, "PLYWOOD")
    end

    norm_words = norm.split(/\s+/)
    return value unless norm_words.include?("go") && norm_words.include?("wood")

    value.gsub(/\bWOOD\b/i, "PLYWOOD")
  rescue
    text.to_s.strip
  end

  def self.mini_excel_display_sub_text(ex, fallback = nil)
    text = mini_excel_sub_text(ex, fallback).to_s.strip
    return "" if text.empty?

    kind = mini_excel_item_kind(ex)
    codes = mini_excel_material_codes(ex, kind)
    text = mini_excel_strip_codes_from_text(text, codes)
    text = mini_excel_normalize_sub_text_spacing(text)
    text = mini_excel_process_material_sub_text(text, codes, kind)
    fallback_text = fallback.to_s.strip
    return "" if text.empty?
    return "" if kind == "VL" && material_display_sub_redundant?(text, codes)
    return "" if mini_excel_sub_text_matches_fallback?(text, fallback_text)

    text
  rescue
    ""
  end

  def self.mini_excel_section_name(ex)
    strip_product_code_prefix(fix_vietnamese_mojibake(ex[:ten_sp] || ex["ten_sp"])).strip
  rescue
    ""
  end

  def self.mini_excel_full_sub_text(ex, fallback = nil)
    section = mini_excel_section_name(ex)
    detail = mini_excel_sub_text(ex, fallback).to_s.strip
    return detail if section.empty?
    return section if detail.empty? || import_name_norm(section) == import_name_norm(detail)

    "#{section} - #{detail}"
  rescue
    fallback.to_s
  end

  def self.mini_excel_item_kind(ex)
    (ex[:kind] || ex["kind"]).to_s
  rescue
    ""
  end

  def self.mini_excel_material_codes(ex, kind)
    codes = []
    [:ma_vl, "ma_vl", :ma_vl_source, "ma_vl_source"].each do |key|
      codes.concat(split_material_codes(ex[key])) if ex.respond_to?(:[])
    end
    codes << (ex[:hw_name] || ex["hw_name"]).to_s if kind == "VL"
    codes.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  rescue
    []
  end

  def self.mini_excel_strip_codes_from_text(text, codes)
    value = text.to_s
    codes.each { |code| value = value.gsub(/#{Regexp.escape(code)}/i, " ") }
    value
  rescue
    text.to_s
  end

  def self.mini_excel_normalize_sub_text_spacing(text)
    text.to_s.gsub(/[\/|]+/, " ").gsub(/\s+/, " ").strip
  rescue
    text.to_s.strip
  end

  def self.mini_excel_process_material_sub_text(text, codes, kind)
    return text unless kind == "VL"

    value = strip_material_code_display_text(text, codes)
    material_display_preserve_plywood_text(value, codes)
  rescue
    text.to_s
  end

  def self.mini_excel_sub_text_matches_fallback?(text, fallback_text)
    return false if fallback_text.to_s.empty?

    import_name_norm(text) == import_name_norm(fallback_text) ||
      material_code_norm(text) == material_code_norm(fallback_text)
  rescue
    false
  end

  # --- Alias methods (without mini_ prefix) for backward-compatible rename ---
  def self.accept_norm(*a, **kw, &b); mini_accept_norm(*a, **kw, &b); end
  def self.name_family_key(*a, **kw, &b); mini_name_family_key(*a, **kw, &b); end
  def self.match_tokens(*a, **kw, &b); mini_match_tokens(*a, **kw, &b); end
  def self.hardware_signature(*a, **kw, &b); mini_hardware_signature(*a, **kw, &b); end
  def self.names_related?(*a, **kw, &b); mini_names_related?(*a, **kw, &b); end
  def self.family_conflict?(*a, **kw, &b); mini_family_conflict?(*a, **kw, &b); end
  def self.signature_relation(*a, **kw, &b); mini_signature_relation(*a, **kw, &b); end
  def self.shared_tokens_satisfy_family?(*a, **kw, &b); mini_shared_tokens_satisfy_family?(*a, **kw, &b); end
  def self.group_excel_items(*a, **kw, &b); mini_group_excel_items(*a, **kw, &b); end
  def self.excel_sub_text(*a, **kw, &b); mini_excel_sub_text(*a, **kw, &b); end
  def self.excel_display_sub_text(*a, **kw, &b); mini_excel_display_sub_text(*a, **kw, &b); end
  def self.excel_section_name(*a, **kw, &b); mini_excel_section_name(*a, **kw, &b); end
  def self.excel_full_sub_text(*a, **kw, &b); mini_excel_full_sub_text(*a, **kw, &b); end
  def self.excel_item_kind(*a, **kw, &b); mini_excel_item_kind(*a, **kw, &b); end
  def self.excel_material_codes(*a, **kw, &b); mini_excel_material_codes(*a, **kw, &b); end
  def self.excel_strip_codes_from_text(*a, **kw, &b); mini_excel_strip_codes_from_text(*a, **kw, &b); end
  def self.excel_normalize_sub_text_spacing(*a, **kw, &b); mini_excel_normalize_sub_text_spacing(*a, **kw, &b); end
  def self.excel_process_material_sub_text(*a, **kw, &b); mini_excel_process_material_sub_text(*a, **kw, &b); end
  def self.excel_sub_text_matches_fallback?(*a, **kw, &b); mini_excel_sub_text_matches_fallback?(*a, **kw, &b); end

end
