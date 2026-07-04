# encoding: utf-8
# MH_Thongke â€” Data Processor
# Core data engine: process_selection
# TÃ¡ch tá»« main.rb: dÃ²ng 719â€“1150

module MH_Thongke

  # Materials máº·c Ä‘á»‹nh cá»§a SketchUp â€” bá»  qua trong thá»‘ng kÃª váº­t liá»‡u
  SKIP_DEFAULT_MATERIALS = Set.new(%w[white red black green blue yellow gray grey]).freeze

require_relative 'processors/material_processor'
require_relative 'processors/report_data_processor'
require_relative 'processors/project_total_processor'
  def self.pk_accept_rule_ok_for_status?(product_code, model_name, target_name, spec = "")
    respond_to?(:pk_rule_ok?) ? pk_rule_ok?(product_code, model_name, target_name, spec) : false
  rescue
    false
  end

  def self.pk_lineage_same_for_status?(product_code, model_name, target_name)
    respond_to?(:pk_lineage_same?) ? pk_lineage_same?(product_code, model_name, target_name) : false
  rescue
    false
  end

  def self.pk_match_ok_like_mini?(product_code, model_name, target_name, spec = "")
    respond_to?(:pk_match_ok?) ? pk_match_ok?(product_code, model_name, target_name, spec) : false
  rescue
    false
  end

  def self.pk_match_target_names(ex_row, special_target = nil)
    names = []
    names << special_target.to_s
    names << (respond_to?(:import_display_name) ? import_display_name(ex_row[:hw_name], ex_row[:spec]) : "")
    names << ex_row[:hw_name].to_s
    names.map { |v| fix_vietnamese_mojibake(v).to_s.strip }.reject(&:empty?).uniq
  rescue
    [special_target.to_s, ex_row[:hw_name].to_s].map(&:to_s).reject(&:empty?).uniq
  end

  def self.pk_update_target_name(ex_row, special_target = nil)
    special = fix_vietnamese_mojibake(special_target).to_s.strip
    return special unless special.empty?

    hw = fix_vietnamese_mojibake(ex_row[:hw_name] || ex_row["hw_name"]).to_s.strip
    spec = fix_vietnamese_mojibake(ex_row[:spec] || ex_row["spec"]).to_s.strip
    target = respond_to?(:import_display_name) ? import_display_name(hw, spec) : [hw, spec].reject(&:empty?).join(" ")
    target.to_s.strip.empty? ? hw : target.to_s.strip
  rescue
    special_target.to_s.strip.empty? ? ex_row[:hw_name].to_s : special_target.to_s.strip
  end

  def self.pk_preserve_dimension_for_update(old_name, new_name, spec = nil)
    target = fix_vietnamese_mojibake(new_name).to_s.strip
    return target if target.empty?

    current_length = respond_to?(:import_length_token) ? import_length_token(target) : nil
    return target if current_length

    length = respond_to?(:import_length_token) ? import_length_token(old_name, spec) : nil
    return target unless length

    "#{target} #{length}".gsub(/\s+/, " ").strip
  rescue
    new_name.to_s.strip
  end

  def self.pk_matches_excel_like_mini?(product_code, model_name, ex_row, special_target = nil)
    hw_name = ex_row[:hw_name].to_s
    spec = ex_row[:spec].to_s
    model_norm = import_name_norm(model_name)
    target_name = pk_update_target_name(ex_row, special_target)
    return true if model_norm == import_name_norm(target_name)
    return true if spec.to_s.strip.empty? && model_norm == import_name_norm(hw_name)

    pk_match_ok_like_mini?(product_code, model_name, target_name, spec)
  rescue
    false
  end

  # -------------------------------------------------------
  # Shared Mini status resolver (Mini only renders HTML)
  # -------------------------------------------------------
  def self.resolve_mini_matched_status_key(product_code, row_kind, model_name, target_name, spec = "", exact = false)
    if row_kind.to_s == "PK"
      pk_match_ok_like_mini?(product_code, model_name, target_name, spec) ? "OK" : "NO_SPEC"
    else
      return "OK" if exact
      material_rule_ok?(product_code, model_name, target_name, spec) ? "OK" : "NO_SPEC"
    end
  rescue
    "NO_SPEC"
  end

  def self.resolve_mini_excel_only_status_key(product_code, row_kind, excel_is_mat, hw_name, spec = "")
    return "THIEU" unless excel_is_mat

    if respond_to?(:mini_accept_rule?) && mini_accept_rule?(product_code, "VL", "", hw_name, spec)
      "OK"
    elsif row_kind.to_s == "VL"
      "SPEC"
    else
      "NO_SPEC"
    end
  rescue
    excel_is_mat ? "SPEC" : "THIEU"
  end

  def self.resolve_mini_model_only_status_key(product_code, row_kind, model_name)
    if row_kind.to_s == "PK"
      pk_rule_ok?(product_code, model_name, "", "") ? "OK" : "NO_SPEC"
    else
      if respond_to?(:mini_accept_rule?) && mini_accept_rule?(product_code, row_kind, model_name, "", "")
        "OK"
      else
        "NO_SPEC"
      end
    end
  rescue
    "NO_SPEC"
  end

  def self.resolve_mini_material_row_status_key(row)
    material_row_status_key(row)
  rescue
    "NO_SPEC"
  end

  def self.mini_pk_model_name_match?(product_code, model_name, hw_name, target_name, spec = "")
    cache_key = "#{product_code_exact(product_code)}|#{model_name}|#{hw_name}|#{target_name}|#{spec}"
    @mini_pk_model_name_match_cache ||= {}
    return @mini_pk_model_name_match_cache[cache_key] if @mini_pk_model_name_match_cache.key?(cache_key)
    
    @mini_pk_model_name_match_cache.clear if @mini_pk_model_name_match_cache.size > 2000

    model_norm = import_name_norm(model_name)
    target_norm = import_name_norm(target_name)
    hw_norm = import_name_norm(hw_name)
    hw_exact_allowed = spec.to_s.strip.empty?
    if !model_norm.empty? && (model_norm == target_norm || (hw_exact_allowed && model_norm == hw_norm))
      return @mini_pk_model_name_match_cache[cache_key] = true
    end

    @mini_pk_model_name_match_cache[cache_key] = pk_rule_ok?(product_code, model_name, target_name, spec)
  rescue
    false
  end

  def self.report_row_status_key(row)
    return "" unless row.is_a?(Hash)
    status_text(row[:trang_thai])
  rescue
    ""
  end

  def self.report_row_update?(row)
    report_row_status_key(row) == "UPDATE" && !row[:new_name].to_s.strip.empty?
  rescue
    false
  end

  # Re-match PK status using Mini Import logic after ExcelMatcher runs.
  # This ensures the main report status column matches Mini Import exactly.
  def self.apply_mini_pk_status_rematch!
    return unless @data_map && !@data_map.empty?
    return unless @imported_excel_data && !@imported_excel_data.empty?
    return unless respond_to?(:pk_matches_excel_like_mini?) && respond_to?(:resolve_mini_matched_status_key)

    # Build excel PK items grouped by product_code_base
    excel_pk_by_base = Hash.new { |h, k| h[k] = [] }
    Array(@imported_excel_data).each do |ex|
      kind = ex[:kind].to_s.strip.upcase
      next if kind == "VL"
      code = ex[:ma_sp].to_s.strip
      next if code.empty?
      base = respond_to?(:product_code_base) ? product_code_base(code) : code.sub(/\.\d+\z/, "")
      excel_pk_by_base[base] << ex unless base.to_s.empty?
    end
    return if excel_pk_by_base.empty?

    # Group excel items for quick dedup
    grouped_excel = {}
    excel_pk_by_base.each do |base, items|
      grouped = respond_to?(:mini_group_excel_items) ? mini_group_excel_items(items.map { |ex| { ma_sp: ex[:ma_sp], kind: "PK", hw_name: ex[:hw_name].to_s, spec: ex[:spec].to_s, ten_sp: ex[:ten_sp].to_s, ghi_chu: ex[:ghi_chu].to_s, qty: 1, raw: ex } }, true) : items
      grouped_excel[base] = grouped
    end

    @data_map.each_value do |row|
      next if row[:is_missing]
      next if row[:type] == :phaochi
      current = status_key(row[:trang_thai])
      # Skip rows already correctly resolved
      next if current == "GHOST"
      # Only re-match if status could improve
      next if current == "OK" && !row[:new_name].to_s.strip.empty?

      product = row[:actual_product].to_s
      next if product.empty?
      base = respond_to?(:product_code_base) ? product_code_base(product) : product.sub(/\.\d+\z/, "")
      excel_rows = grouped_excel[base]
      next unless excel_rows && !excel_rows.empty?

      su_name = row[:name].to_s
      next if su_name.empty?
      model_section = respond_to?(:strip_product_code_prefix) ? strip_product_code_prefix(row[:ten_sp].to_s).to_s.strip : row[:ten_sp].to_s.strip

      matched_ex = nil
      matched_target = ""
      excel_rows.each do |ex|
        hw_name = ex[:hw_name].to_s
        spec = ex[:spec].to_s

        # Section filtering (same as pk_project_items_with_excel_status)
        if !model_section.empty?
          ex_section = ex[:section].to_s
          ex_section = mini_excel_section_name(ex).to_s if ex_section.empty? && respond_to?(:mini_excel_section_name)
          unless ex_section.to_s.strip.empty?
            ms_norm = respond_to?(:import_section_norm) ? import_section_norm(model_section) : import_name_norm(model_section)
            es_norm = respond_to?(:import_section_norm) ? import_section_norm(ex_section) : import_name_norm(ex_section)
            next if !ms_norm.empty? && !es_norm.empty? && ms_norm != es_norm
          end
        end

        next unless pk_matches_excel_like_mini?(product, su_name, ex, nil)

        matched_ex = ex
        matched_target = pk_update_target_name(ex, nil)
        break
      end

      if matched_ex
        spec = matched_ex[:spec].to_s
        exact = import_name_norm(su_name) == import_name_norm(matched_target.to_s)
        new_status = resolve_mini_matched_status_key(product, "PK", su_name, matched_target.to_s, spec, exact)
        
        row[:trang_thai] = new_status
        row[:new_name] = new_status == "UPDATE" ? matched_target.to_s : ""
      else
        # Model-only: resolve using accept rules
        new_status = resolve_mini_model_only_status_key(product, "PK", su_name)
        row[:trang_thai] = new_status
        row[:new_name] = "" if new_status != "UPDATE"
      end
    end
  rescue => e
    puts "apply_mini_pk_status_rematch! error: #{e.message}" rescue nil
  end

  def self.report_row_no_spec?(row)
    report_row_status_key(row) == "NO_SPEC"
  rescue
    false
  end

  def self.material_model_match_for_import?(excel_name, model_name)
    return false if excel_name.to_s.strip.empty? || model_name.to_s.strip.empty?

    if respond_to?(:material_code_subgroup?) && material_code_subgroup?(excel_name)
      excel_norm = material_code_variant_norm(excel_name)
      model_norm = material_code_variant_norm(model_name)
    else
      excel_norm = material_code_norm(excel_name)
      model_norm = material_code_norm(model_name)
    end

    # Exact normalized match
    return true if excel_norm == model_norm

    # Variant suffix match: ONLY "/" indicates a color/finish suffix that can
    # be ignored for matching. "." segments are real product code subdivisions
    # (e.g. PLY.AC vs PLY.AC.VERKT are DIFFERENT products) and must match.
    #
    # Example accepted:  "PLY.AC.30YY-68" ↔ "PLY.AC.30YY-68/024-30"
    # Example rejected:  "PLY.AC"         vs "PLY.AC.VERKT.30YY-68"
    larger, smaller = excel_norm.length >= model_norm.length ? [excel_norm, model_norm] : [model_norm, excel_norm]
    return false if smaller.empty?
    return true if larger.start_with?(smaller) && larger[smaller.length] == "/"

    false
  rescue
    false
  end

  def self.material_model_only_has_excel_spec?(product_code, model_name)
    model_text = model_name.to_s.strip
    return false if model_text.empty?

    product_exact = product_code_exact(product_code)
    product_base = product_code_base(product_exact)
    Array(@imported_excel_data).any? do |ex|
      next false unless ex[:kind].to_s.strip.upcase == "VL"

      ex_product = ex[:ma_sp].to_s.strip
      ex_exact = product_code_exact(ex_product)
      ex_base = product_code_base(ex_exact)
      next false unless ex_exact == product_exact || (!product_base.empty? && ex_base == product_base)

      hw_name = ex[:hw_name].to_s
      spec = ex[:spec].to_s
      target = respond_to?(:import_display_name) ? import_display_name(hw_name, spec) : "#{hw_name} #{spec}".strip
      material_model_match_for_import?(hw_name, model_text) || material_model_match_for_import?(target, model_text)
    end
  rescue
    false
  end

  def self.file_time_for_material_date(path)
    return nil if path.to_s.empty? || !File.exist?(path.to_s)
    begin
      File.birthtime(path.to_s)
    rescue
      File.ctime(path.to_s)
    end
  rescue
    nil
  end

  def self.material_nesting_order_date
    model = Sketchup.active_model rescue nil
    skp_path = (model.path rescue "").to_s
    return "" if skp_path.to_s.strip.empty?

    dir = File.dirname(skp_path)
    return "" if dir.to_s.strip.empty? || !File.directory?(dir)
    dir_mtime = File.mtime(dir).to_f rescue 0.0
    cache_key = [skp_path, dir, dir_mtime].join("|")
    return @material_nesting_order_date_cache[:value] if @material_nesting_order_date_cache.is_a?(Hash) &&
      @material_nesting_order_date_cache[:key] == cache_key

    candidates = Dir.entries(dir).select { |name| name =~ /_NESTING/i && name =~ /\.skp\z/i rescue false }
    dated = candidates.map do |name|
      full = File.join(dir, name)
      t = file_time_for_material_date(full)
      t ? [t, full] : nil
    end.compact
    if dated.empty? && respond_to?(:snapshots_for_current_project)
      begin
        from_snapshots = Array(snapshots_for_current_project(false)).select do |snap|
          role = respond_to?(:snapshot_file_role) ? snapshot_file_role(snap) : ""
          role == "NESTING"
        end.map do |snap|
          t = report_date_time(snap["file_created_at"].to_s)
          t ? [t, snap["skp_path"].to_s] : nil
        end.compact
        dated = from_snapshots unless from_snapshots.empty?
      rescue
      end
    end
    if dated.empty?
      @material_nesting_order_date_cache = { key: cache_key, value: "" }
      return ""
    end

    newest = dated.max_by { |pair| pair[0] }
    value = newest && newest[0] ? newest[0].strftime("%d/%m/%Y") : ""
    @material_nesting_order_date_cache = { key: cache_key, value: value }
    value
  rescue
    ""
  end

  def self.apply_material_order_date_from_nesting_file!
    date_text = normalize_order_date(material_nesting_order_date)
    return if date_text.to_s.empty?

    (@mat_data_map || {}).each_value do |row|
      row[:ngay_dat] = date_text
    end
  rescue
    nil
  end

  def self.led_psu_combo(required_power_w, psu_list)
    req = required_power_w.to_f
    return {} if req <= 0.0001

    watts = Array(psu_list).map { |w| w.to_i }.select { |w| w > 0 }.uniq.sort
    return {} if watts.empty?

    target = req.ceil
    max_w = watts.last
    limit = target + max_w * 4

    dp = Array.new(limit + 1)
    dp[0] = { count: 0, combo: Hash.new(0) }
    (0..limit).each do |p|
      next unless dp[p]
      watts.each do |w|
        np = p + w
        next if np > limit
        nc = dp[p][:count] + 1
        if dp[np].nil? || nc < dp[np][:count]
          combo = dp[p][:combo].dup
          combo[w] += 1
          dp[np] = { count: nc, combo: combo }
        end
      end
    end

    best = nil
    best_power = nil
    (target..limit).each do |p|
      next unless dp[p]
      if best.nil?
        best = dp[p]
        best_power = p
        next
      end
      better_count = dp[p][:count] < best[:count]
      same_count_less_over = dp[p][:count] == best[:count] && (p - target) < (best_power - target)
      if better_count || same_count_less_over
        best = dp[p]
        best_power = p
      end
    end
    return {} unless best

    result = {}
    best[:combo].each { |w, c| result[w] = c.to_i if c.to_i > 0 }
    result
  rescue
    {}
  end

  def self.recompute_back_import_diff!
    @back_import_diff = []
    return unless @data_map.is_a?(Hash)

    if @back_imported_excel && !@back_imported_excel.empty?
      Array(@back_imported_excel).each { |bx| bx.delete(:found) if bx.respond_to?(:delete) }
      @data_map.delete_if { |key, _row| key.to_s.start_with?("GHOST_") }

      @data_map.values.each do |row|
        match = back_import_match_row(row, @back_imported_excel)

        if match
          match[:found] = true
          date_diff = back_import_date_diff(match[:ngay_dat] || match["ngay_dat"], row[:ngay_dat])
          row[:back_diff] = date_diff ? { ngay_dat: date_diff } : nil
        else
          row[:back_diff] = nil
        end
      end

      @back_imported_excel.each do |bx|
        next if bx[:found]

        ghost_key = "GHOST_#{bx[:product]}_#{bx[:name]}"
        next if @data_map[ghost_key]

        ghost = {
          name: bx[:name], product: (@group_by == "NAME" ? "--" : bx[:product]),
          actual_product: bx[:product], ten_sp: bx[:ten_sp].to_s, ghi_chu: "", ngay_dat: "",
          trang_thai: "GHOST", new_name: "", layer: "-",
          count: bx[:qty].to_i, length: 0.0, sel_count: 0, sel_length: 0.0,
          unit: bx[:unit].to_s, type: :count, entities: [], stat_entities: [],
          length_items: [], last_modified: "", is_missing: true
        }

        date_key = respond_to?(:order_date_key) ? order_date_key("acc", ghost) : nil
        date_accepted = begin
          date_key && order_date_overrides.key?(date_key)
        rescue
          false
        end

        apply_order_date_override("acc", ghost) if respond_to?(:apply_order_date_override)

        date_diff = back_import_date_diff(bx[:ngay_dat] || bx["ngay_dat"], (date_accepted ? ghost[:ngay_dat] : ""))
        ghost[:back_diff] = date_diff ? { ngay_dat: date_diff } : nil
        @data_map[ghost_key] = ghost
      end
    else
      @data_map.values.each { |row| row[:back_diff] = nil }
    end
  end

  def self.back_import_match_row(row, imported_rows = @back_imported_excel)
    if respond_to?(:back_import_match_for_row)
      return back_import_match_for_row(row, imported_rows)
    end
    Array(imported_rows).find do |bx|
      bx[:name].to_s.downcase.strip == row[:name].to_s.downcase.strip &&
        bx[:product].to_s.upcase == row[:actual_product].to_s.upcase
    end
  rescue
    nil
  end

  def self.back_import_date_diff(excel_value, current_value)
    excel_date = normalize_order_date(excel_value)
    current_date = normalize_order_date(current_value)
    return nil if excel_date == current_date

    { excel: excel_date, current: current_date }
  rescue
    nil
  end

  def self.row_display_qty(row, data_key = nil, current_unit = nil)
    return 0.0 unless row.is_a?(Hash)

    cu = current_unit || ((data_key && @unit_overrides && @unit_overrides[data_key]) ? @unit_overrides[data_key] : row[:unit])
    if row[:type] == :length || row[:type] == :phaochi
      raw_mm = row[:type] == :phaochi ? row[:len_total_mm].to_f : (row[:length].to_f * 25.4)
      case cu
      when "m", "md" then (raw_mm / 1000.0).round(2)
      when "mm"      then raw_mm.round(1)
      else row[:count]
      end
    else
      row[:count]
    end
  end

  def self.resolve_snapshot_export_fields!
    @unit_overrides ||= {}
    @length_display_units ||= {}
    data_key_by_object_id = {}
    (@data_map || {}).each { |k, v| data_key_by_object_id[v.object_id] = k if v }

    (@current_report_items || []).each do |d|
      dk = data_key_by_object_id[d.object_id]
      cu = (dk && @unit_overrides[dk]) ? @unit_overrides[dk] : d[:unit]
      d[:_resolved_unit] = cu.to_s
      d[:_resolved_qty] = row_display_qty(d, dk, cu)
      d[:_length_display_unit] = ((dk && @length_display_units[dk]) ? @length_display_units[dk] : "mm").to_s
      d[:_data_key] = dk
    end

    (@current_mat_items || []).each do |d|
      d[:_resolved_unit] = d[:unit].to_s
      d[:_resolved_qty] = d[:count]
      d[:_data_key] = nil
    end
  end

  def self.format_qty_value(qty)
    n = qty.to_f
    return n.round.to_i.to_s if (n - n.round).abs < 0.0001

    text = n.round(2).to_s
    text.sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, "\\1")
  end

  def self.merge_name_grouped_accessories!
    return unless @group_by.to_s == "NAME"
    return unless @data_map.is_a?(Hash)

    grouped = {}
    @data_map.each_value do |row|
      next unless row
      key = "#{cached_norm(row[:name]) rescue row[:name].to_s.downcase}|#{row[:type]}"
      if grouped[key]
        base = grouped[key]
        base[:count] = base[:count].to_i + row[:count].to_i
        base[:sel_count] = base[:sel_count].to_i + row[:sel_count].to_i
        base[:length] = base[:length].to_f + row[:length].to_f
        base[:sel_length] = base[:sel_length].to_f + row[:sel_length].to_f
        base[:len_total_mm] = base[:len_total_mm].to_f + row[:len_total_mm].to_f if row.key?(:len_total_mm)
        base[:sel_len_mm] = base[:sel_len_mm].to_f + row[:sel_len_mm].to_f if row.key?(:sel_len_mm)
        base[:entities] = ((base[:entities] || []) + (row[:entities] || [])).compact.uniq
        base[:stat_entities] = (base[:stat_entities] || []) + (row[:stat_entities] || [])
        base[:length_items] = (base[:length_items] || []) + (row[:length_items] || [])
        base[:is_missing] = !!base[:is_missing] && !!row[:is_missing]
        if status_priority(row[:trang_thai]) > status_priority(base[:trang_thai])
          base[:trang_thai] = row[:trang_thai]
          base[:new_name] = row[:new_name]
        end
        base[:ghi_chu] = row[:ghi_chu] if base[:ghi_chu].to_s.empty?
        base[:ngay_dat] = row[:ngay_dat] if base[:ngay_dat].to_s.empty?
        base[:last_modified] = row[:last_modified] if base[:last_modified].to_s.empty?
        base[:layer] = row[:layer] if base[:layer].to_s.empty? || base[:layer].to_s == "-"
      else
        grouped[key] = row.dup
      end

      base = grouped[key]
      base[:product_list] ||= []
      base[:ten_sp_list] ||= []
      products = Array(row[:product_list]) + [row[:actual_product], row[:product]]
      products.map { |p| product_code_exact(p) rescue p.to_s.strip.upcase }.select { |p| product_code_valid?(p) rescue p =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?/ }.each do |p|
        base[:product_list] << p unless base[:product_list].include?(p)
      end
      ten_sps = Array(row[:ten_sp_list]) + [row[:ten_sp]]
      ten_sps.map { |v| fix_vietnamese_mojibake(v).to_s.strip }.reject(&:empty?).each do |v|
        base[:ten_sp_list] << v unless base[:ten_sp_list].include?(v)
      end
      if base[:product_list].size == 1
        base[:actual_product] = base[:product_list].first
        base[:ten_sp] = base[:ten_sp_list].first.to_s if base[:ten_sp].to_s.empty? || base[:ten_sp_list].size == 1
      else
        base[:actual_product] = "--"
        base[:ten_sp] = ""
      end
      base[:product] = "--"
    end

    @data_map = {}
    grouped.each_with_index { |(_, row), idx| @data_map["NAME_GROUP_#{idx}"] = row }
  end

  # === Aliases: mini_* → neutral names ===
  def self.resolve_matched_status_key(*a, **kw, &b); resolve_mini_matched_status_key(*a, **kw, &b); end
  def self.resolve_excel_only_status_key(*a, **kw, &b); resolve_mini_excel_only_status_key(*a, **kw, &b); end
  def self.resolve_model_only_status_key(*a, **kw, &b); resolve_mini_model_only_status_key(*a, **kw, &b); end
  def self.resolve_material_row_status_key(*a, **kw, &b); resolve_mini_material_row_status_key(*a, **kw, &b); end
  def self.pk_model_name_match?(*a, **kw, &b); mini_pk_model_name_match?(*a, **kw, &b); end

end

