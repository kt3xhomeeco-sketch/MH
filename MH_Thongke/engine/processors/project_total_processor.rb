# encoding: utf-8
# MH_Thongke — Project Total Processor
# Xử lý data cho bảng Tổng Dự Án + Tab All.
# THUẦN LOGIC — không chứa HTML.

module MH_Thongke

  # === Helpers chung ===
  def self.project_total_hash_value(source, *keys)
    return nil unless source.is_a?(Hash)
    keys.each do |key|
      return source[key] if source.key?(key)
      key_text = key.to_s
      return source[key_text] if source.key?(key_text)
      key_sym = key_text.to_sym
      return source[key_sym] if source.key?(key_sym)
    end
    nil
  end

  def self.project_total_text(value)
    fix_vietnamese_mojibake(value).to_s.strip
  rescue
    value.to_s.strip
  end

  def self.project_total_product_code(value)
    raw_text = value.to_s.strip.upcase
    exact = respond_to?(:product_code_exact) ? product_code_exact(raw_text) : ""
    return exact if !exact.to_s.empty? && (!respond_to?(:product_code_valid?) || product_code_valid?(exact))
    code = respond_to?(:product_codes_from_text) ? product_codes_from_text(raw_text).first : nil
    code || raw_text
  rescue
    value.to_s.strip.upcase
  end

  def self.project_total_product_base(value)
    if respond_to?(:product_code_base)
      product_code_base(value)
    else
      project_total_product_code(value).sub(/\.\d+\z/, "")
    end
  rescue
    project_total_product_code(value).sub(/\.\d+\z/, "")
  end

  def self.project_total_kind(value)
    kind_text = value.to_s.strip.upcase
    return "VL" if kind_text == "VL" || kind_text == "MATERIAL"
    "PK"
  end

  def self.project_total_excel_target_name(row)
    kind_text = project_total_kind(project_total_hash_value(row, :kind))
    hardware_name = project_total_text(project_total_hash_value(row, :hw_name, :hw, :name))
    spec_text = project_total_text(project_total_hash_value(row, :spec, :quy_cach, :kich_thuoc))
    return hardware_name if kind_text == "VL"
    if respond_to?(:import_display_name)
      import_display_name(hardware_name, spec_text).to_s.strip
    else
      [hardware_name, spec_text].reject(&:empty?).join(" ").strip
    end
  rescue
    project_total_text(project_total_hash_value(row, :hw_name, :hw, :name))
  end

  def self.project_total_excel_unit(row)
    explicit_unit = project_total_text(project_total_hash_value(row, :unit, :don_vi, :dvt))
    return explicit_unit unless explicit_unit.empty?
    kind_text = project_total_kind(project_total_hash_value(row, :kind))
    return "" if kind_text == "VL"
    target_name = project_total_excel_target_name(row)
    if respond_to?(:accessory_unit_for_name)
      accessory_unit_for_name(target_name).to_s.empty? ? "Cái" : accessory_unit_for_name(target_name).to_s
    else
      "Cái"
    end
  rescue
    "Cái"
  end

  def self.project_total_excel_quantity(row)
    raw_qty = project_total_hash_value(row, :qty, :quantity, :so_luong, :sl)
    has_explicit_qty = !(raw_qty.nil? || raw_qty.to_s.strip.empty?)
    [has_explicit_qty ? raw_qty.to_f : 1.0, has_explicit_qty]
  rescue
    [1.0, false]
  end

  def self.project_total_excel_hidden?(row)
    product_code = project_total_product_code(project_total_hash_value(row, :ma_sp, :product))
    kind_text = project_total_kind(project_total_hash_value(row, :kind))
    hardware_name = project_total_text(project_total_hash_value(row, :hw_name, :hw, :name))
    spec_text = project_total_text(project_total_hash_value(row, :spec, :quy_cach, :kich_thuoc))
    target_name = project_total_excel_target_name(row)
    return true if respond_to?(:hidden_item_name?) && hidden_item_name?(hardware_name, target_name)
    if respond_to?(:mini_excel_item_hidden?)
      return true if mini_excel_item_hidden?(product_code, row)
      return true if mini_import_item_hidden?(product_code, kind_text, hardware_name, spec_text) if respond_to?(:mini_import_item_hidden?)
    end
    false
  rescue
    false
  end

  def self.project_total_snapshot_hidden?(row, name_text)
    return true if respond_to?(:hidden_item_name?) && hidden_item_name?(name_text)
    product_code = project_total_product_code(project_total_hash_value(row, :product, :ma_sp))
    kind_text = project_total_kind(project_total_hash_value(row, :kind, :type))
    spec_text = project_total_text(project_total_hash_value(row, :spec, :kich_thuoc, :quy_cach))
    respond_to?(:mini_import_item_hidden?) && mini_import_item_hidden?(product_code, kind_text, name_text, spec_text)
  rescue
    false
  end

  def self.project_total_snapshot_unit(row, kind_text, name_text)
    explicit_unit = project_total_text(project_total_hash_value(row, :unit, :don_vi, :dvt))
    return explicit_unit if kind_text == "VL"
    type_text = project_total_hash_value(row, :type).to_s
    return "md" if type_text == "length" || type_text == "phaochi"
    expected_unit = respond_to?(:accessory_unit_for_name) ? accessory_unit_for_name(name_text).to_s : ""
    return expected_unit unless expected_unit.empty?
    explicit_unit.empty? ? "Cái" : explicit_unit
  rescue
    "Cái"
  end

  def self.project_total_snapshot_quantity(row, kind_text, name_text)
    source_unit = project_total_text(project_total_hash_value(row, :unit, :don_vi, :dvt))
    target_unit = project_total_snapshot_unit(row, kind_text, name_text)
    type_text = project_total_hash_value(row, :type).to_s
    quantity = project_total_hash_value(row, :qty, :quantity, :count, :sl).to_f
    source_unit_downcase = source_unit.downcase
    target_unit_downcase = target_unit.downcase
    if kind_text == "PK" && ["m", "md"].include?(target_unit_downcase)
      return [quantity, target_unit] if ["m", "md"].include?(source_unit_downcase)
      return [(quantity / 1000.0), target_unit] if source_unit_downcase == "mm" || type_text == "length" || type_text == "phaochi"
    end
    [quantity, target_unit]
  rescue
    [0.0, ""]
  end

  def self.project_total_append_product(group, product_code)
    product_text = project_total_product_code(product_code)
    return if product_text.empty?
    group[:products] << product_text unless group[:products].include?(product_text)
  end

  def self.project_total_pk_matches_excel?(product_code, model_name, excel_row)
    hardware_name = project_total_text(project_total_hash_value(excel_row, :hw_name, :hw, :name))
    spec_text = project_total_text(project_total_hash_value(excel_row, :spec, :quy_cach, :kich_thuoc))
    target_name = project_total_excel_target_name(excel_row)
    return true if respond_to?(:pk_matches_excel_like_mini?) && pk_matches_excel_like_mini?(product_code, model_name, { hw_name: hardware_name, spec: spec_text }, nil)
    false
  rescue
    false
  end

  def self.project_total_vl_matches_excel?(product_code, model_name, excel_row)
    target_name = project_total_excel_target_name(excel_row)
    spec_text = project_total_text(project_total_hash_value(excel_row, :spec, :quy_cach, :kich_thuoc))
    return true if respond_to?(:mini_import_material_model_match?) && mini_import_material_model_match?(target_name, model_name)
    return true if respond_to?(:material_model_match_for_import?) && material_model_match_for_import?(target_name, model_name)
    return true if respond_to?(:mini_accept_rule?) && mini_accept_rule?(product_code, "VL", model_name, target_name, spec_text)
    respond_to?(:import_names_match?) ? import_names_match?(model_name, target_name) : model_name.to_s.casecmp?(target_name.to_s)
  rescue
    false
  end

  def self.project_total_find_excel_group_key(groups, product_code, kind_text, model_name)
    exact_product = project_total_product_code(product_code)
    base_product = project_total_product_base(product_code)
    candidates = groups.select do |_, group|
      next false unless group[:kind].to_s == kind_text.to_s
      next false if Array(group[:excel_rows]).empty?
      group_product = group[:product].to_s
      group_product == exact_product || (!base_product.empty? && project_total_product_base(group_product) == base_product)
    end
    candidates.each do |candidate_key, group|
      matched = Array(group[:excel_rows]).any? do |excel_row|
        kind_text == "VL" ? project_total_vl_matches_excel?(product_code, model_name, excel_row) : project_total_pk_matches_excel?(product_code, model_name, excel_row)
      end
      return candidate_key if matched
    end
    nil
  rescue
    nil
  end

  def self.project_total_status(group)
    excel_qty = group[:excel_qty].to_f
    model_qty = group[:model_qty].to_f
    return "THIẾU MODEL" if excel_qty > 0.0 && model_qty <= 0.0
    return "DƯ MODEL" if excel_qty <= 0.0 && model_qty > 0.0
    return "LỆCH SL" if group[:excel_has_qty] && (excel_qty - model_qty).abs > 0.01
    "OK"
  end

  def self.project_total_qty_text(quantity)
    return "-" if quantity.to_f <= 0.0
    if respond_to?(:format_qty_value)
      format_qty_value(quantity)
    elsif (quantity.to_f - quantity.to_f.round).abs < 0.0001
      quantity.to_f.round.to_i.to_s
    else
      quantity.to_f.round(2).to_s
    end
  end

  # === Grouping helpers ===
  def self.project_total_group_key(product_code, kind_text, name_text, spec_text, unit_text)
    [
      project_total_product_code(product_code), kind_text.to_s,
      respond_to?(:import_name_norm) ? import_name_norm(name_text) : name_text.to_s.downcase,
      respond_to?(:import_name_norm) ? import_name_norm(spec_text) : spec_text.to_s.downcase,
      unit_text.to_s.downcase
    ].join("|")
  end

  def self.project_total_group(groups, product_code, kind_text, name_text, spec_text, unit_text)
    key = project_total_group_key(product_code, kind_text, name_text, spec_text, unit_text)
    groups[key] ||= {
      product: project_total_product_code(product_code), kind: kind_text, name: name_text,
      spec: spec_text, unit: unit_text, note: "", excel_qty: 0.0, model_qty: 0.0,
      excel_has_qty: false, excel_rows: [], products: [], order: groups.size
    }
    groups[key]
  end

  def self.tab_all_product_code(value)
    base = project_total_product_base(value)
    base.to_s.empty? ? project_total_product_code(value) : base
  rescue
    project_total_product_code(value)
  end

  def self.tab_all_group_key(product_code, kind_text, name_text, spec_text, unit_text)
    [
      tab_all_product_code(product_code), kind_text.to_s,
      respond_to?(:import_name_norm) ? import_name_norm(name_text) : name_text.to_s.downcase,
      respond_to?(:import_name_norm) ? import_name_norm(spec_text) : spec_text.to_s.downcase,
      unit_text.to_s.downcase
    ].join("|")
  end

  def self.tab_all_group(groups, product_code, kind_text, name_text, spec_text, unit_text)
    key = tab_all_group_key(product_code, kind_text, name_text, spec_text, unit_text)
    groups[key] ||= {
      product: tab_all_product_code(product_code), kind: kind_text, name: name_text,
      spec: spec_text, unit: unit_text, note: "", excel_qty: 0.0, model_qty: 0.0,
      excel_has_qty: false, excel_rows: [], layers: [], order_dates: [], products: [], order: groups.size
    }
    groups[key]
  end

  def self.tab_all_find_excel_group_key(groups, product_code, kind_text, model_name)
    base_product = tab_all_product_code(product_code)
    candidates = groups.select do |_, group|
      group[:kind].to_s == kind_text.to_s && group[:product].to_s == base_product && Array(group[:excel_rows]).any?
    end
    candidates.each do |candidate_key, group|
      matched = Array(group[:excel_rows]).any? do |excel_row|
        kind_text == "VL" ? project_total_vl_matches_excel?(base_product, model_name, excel_row) : project_total_pk_matches_excel?(base_product, model_name, excel_row)
      end
      return candidate_key if matched
    end
    nil
  rescue
    nil
  end

  # -------------------------------------------------------
  # compute_project_total_data -> Array of Hash (NO HTML)
  # -------------------------------------------------------
  def self.compute_project_total_data
    load_match_rules if respond_to?(:load_match_rules) && @match_rules.nil?
    load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only) && (@imported_excel_data.nil? || @imported_excel_data.empty?)

    groups = {}

    # Excel rows
    Array(@imported_excel_data).each do |excel_row|
      next unless excel_row.is_a?(Hash)
      next if project_total_excel_hidden?(excel_row)
      product_code = project_total_product_code(project_total_hash_value(excel_row, :ma_sp, :product))
      next if product_code.empty?
      kind_text = project_total_kind(project_total_hash_value(excel_row, :kind))
      target_name = project_total_excel_target_name(excel_row)
      next if target_name.empty?
      spec_text = project_total_text(project_total_hash_value(excel_row, :spec, :quy_cach, :kich_thuoc))
      unit_text = project_total_excel_unit(excel_row)
      quantity_value, has_explicit_qty = project_total_excel_quantity(excel_row)
      group = project_total_group(groups, product_code, kind_text, target_name, spec_text, unit_text)
      group[:excel_qty] += quantity_value
      group[:excel_has_qty] ||= has_explicit_qty
      group[:excel_rows] << excel_row
      project_total_append_product(group, product_code)
      note_text = project_total_text(project_total_hash_value(excel_row, :ghi_chu, :note))
      group[:note] = [group[:note], note_text].reject(&:empty?).uniq.join("; ") unless note_text.empty?
    end

    # Snapshot rows
    [[:items, "PK"], [:mat_items, "VL"]].each do |source_pair|
      source_kind, default_kind = source_pair
      source_rows = respond_to?(:project_total_source_rows) ? project_total_source_rows(source_kind) : []
      Array(source_rows).each do |snapshot_row|
        next unless snapshot_row.is_a?(Hash)
        next if project_total_hash_value(snapshot_row, :is_missing)
        product_code = project_total_product_code(project_total_hash_value(snapshot_row, :product, :ma_sp))
        product_code = "--" if product_code.empty?
        name_text = project_total_text(project_total_hash_value(snapshot_row, :name, :hw_name, :hw))
        next if name_text.empty? || project_total_snapshot_hidden?(snapshot_row, name_text)
        kind_text = default_kind
        kind_text = "VL" if source_kind == :mat_items
        quantity_value, unit_text = project_total_snapshot_quantity(snapshot_row, kind_text, name_text)
        next if quantity_value <= 0.0
        match_key = project_total_find_excel_group_key(groups, product_code, kind_text, name_text)
        group = match_key ? groups[match_key] : project_total_group(groups, product_code, kind_text, name_text, project_total_text(project_total_hash_value(snapshot_row, :kich_thuoc, :spec)), unit_text)
        group[:model_qty] += quantity_value
        group[:unit] = unit_text if group[:unit].to_s.empty? || group[:model_qty].to_f > 0.0
        project_total_append_product(group, product_code)
        note_text = project_total_text(project_total_hash_value(snapshot_row, :ghi_chu, :note))
        group[:note] = [group[:note], note_text].reject(&:empty?).uniq.join("; ") unless note_text.empty?
      end
    end

    # Sort & compute status
    sort_mode = @project_total_sort.to_s.upcase
    rows = groups.values
    rows = if sort_mode == "PRODUCT"
      rows.sort_by { |g| [respond_to?(:product_code_sort_key) ? product_code_sort_key(g[:product]) : g[:product].to_s, g[:kind].to_s, respond_to?(:import_name_norm) ? import_name_norm(g[:name]) : g[:name].to_s.downcase] }
    else
      rows.sort_by { |g| [g[:order].to_i, respond_to?(:product_code_sort_key) ? product_code_sort_key(g[:product]) : g[:product].to_s] }
    end
    rows.each { |g| g[:status] = project_total_status(g) }
    rows
  rescue => e
    puts "compute_project_total_data error: #{e.message}" rescue nil
    []
  end

  # -------------------------------------------------------
  # compute_tab_all_data -> Array of Hash (NO HTML)
  # -------------------------------------------------------
  def self.compute_tab_all_data
    load_match_rules if respond_to?(:load_match_rules) && @match_rules.nil?
    load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only) && (@imported_excel_data.nil? || @imported_excel_data.empty?)

    groups = {}

    Array(@imported_excel_data).each do |excel_row|
      next unless excel_row.is_a?(Hash)
      next if project_total_excel_hidden?(excel_row)
      product_code = tab_all_product_code(project_total_hash_value(excel_row, :ma_sp, :product))
      next if product_code.empty?
      kind_text = project_total_kind(project_total_hash_value(excel_row, :kind))
      target_name = project_total_excel_target_name(excel_row)
      next if target_name.empty?
      spec_text = project_total_text(project_total_hash_value(excel_row, :spec, :quy_cach, :kich_thuoc))
      unit_text = project_total_excel_unit(excel_row)
      quantity_value, has_explicit_qty = project_total_excel_quantity(excel_row)
      group = tab_all_group(groups, product_code, kind_text, target_name, spec_text, unit_text)
      group[:excel_qty] += quantity_value
      group[:excel_has_qty] ||= has_explicit_qty
      group[:excel_rows] << excel_row
      project_total_append_product(group, product_code)
      note_text = project_total_text(project_total_hash_value(excel_row, :ghi_chu, :note))
      group[:note] = [group[:note], note_text].reject(&:empty?).uniq.join("; ") unless note_text.empty?
    end

    [[:items, "PK"], [:mat_items, "VL"]].each do |source_kind, default_kind|
      source_rows = respond_to?(:project_total_source_rows) ? project_total_source_rows(source_kind) : []
      Array(source_rows).each do |snapshot_row|
        next unless snapshot_row.is_a?(Hash)
        next if project_total_hash_value(snapshot_row, :is_missing)
        product_code = tab_all_product_code(project_total_hash_value(snapshot_row, :product, :ma_sp))
        product_code = "--" if product_code.empty?
        name_text = project_total_text(project_total_hash_value(snapshot_row, :name, :hw_name, :hw))
        next if name_text.empty? || project_total_snapshot_hidden?(snapshot_row, name_text)
        kind_text = default_kind
        kind_text = "VL" if source_kind == :mat_items
        quantity_value, unit_text = project_total_snapshot_quantity(snapshot_row, kind_text, name_text)
        next if quantity_value <= 0.0
        match_key = tab_all_find_excel_group_key(groups, product_code, kind_text, name_text)
        group = match_key ? groups[match_key] : tab_all_group(groups, product_code, kind_text, name_text, project_total_text(project_total_hash_value(snapshot_row, :kich_thuoc, :spec)), unit_text)
        group[:model_qty] += quantity_value
        group[:unit] = unit_text if group[:unit].to_s.empty? || group[:model_qty].to_f > 0.0
        project_total_append_product(group, product_code)
        layer_text = project_total_text(project_total_hash_value(snapshot_row, :layer))
        group[:layers] << layer_text unless layer_text.empty? || group[:layers].include?(layer_text)
        order_date = respond_to?(:normalize_order_date) ? normalize_order_date(project_total_hash_value(snapshot_row, :ngay_dat)) : project_total_hash_value(snapshot_row, :ngay_dat).to_s
        group[:order_dates] << order_date unless order_date.to_s.empty? || group[:order_dates].include?(order_date)
        note_text = project_total_text(project_total_hash_value(snapshot_row, :ghi_chu, :note))
        group[:note] = [group[:note], note_text].reject(&:empty?).uniq.join("; ") unless note_text.empty?
      end
    end

    rows = groups.values.sort_by do |g|
      [respond_to?(:product_code_sort_key) ? product_code_sort_key(g[:product]) : g[:product].to_s, g[:kind].to_s == "VL" ? 1 : 0, respond_to?(:import_name_norm) ? import_name_norm(g[:name]) : g[:name].to_s.downcase]
    end
    rows.each { |g| g[:status] = project_total_status(g) }
    rows
  rescue => e
    puts "compute_tab_all_data error: #{e.message}" rescue nil
    []
  end

end
