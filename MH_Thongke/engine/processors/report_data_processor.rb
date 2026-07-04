# encoding: utf-8
# MH_Thongke — Report Data Processor
# Hàm tính toán trung tâm: process_report_data
# Trả về mảng dữ liệu thô (Array of Hash) — KHÔNG chứa HTML.
# Phục vụ cho: Mini Import, Tổng Dự Án, table-acc, table-all.

module MH_Thongke

  # -------------------------------------------------------
  # process_report_data(product_code, opts = {})
  #
  # Ghép cặp dữ liệu Excel (JSON) với Model, áp Rulers,
  # tính số lượng, xác định trạng thái cho từng dòng PK/VL.
  #
  # Trả về Array of Hash, mỗi Hash có dạng:
  #   {
  #     source:       :matched | :excel_only | :model_only,
  #     kind:         "PK" | "VL" | "STAT",
  #     name:         "Bản lề lọt lòng",
  #     target_name:  "Bản lề lọt lòng",   # tên chuẩn theo Excel
  #     spec:         "Hafele 35mm",
  #     section:      "Tủ bếp dưới",
  #     note:         "Ghi chú...",
  #     kt:           "35mm",
  #     unit:         "cái",
  #     excel_qty:    4.0,
  #     model_qty:    4.0,
  #     status:       "OK" | "LECH_SL" | "THIEU_MODEL" | "DU_MODEL" | "NO_SPEC" | "UPDATE",
  #     exact_match:  true/false,
  #     editable:     true/false,
  #     ids:          [123, 456],       # entityID từ Model
  #     product_code: "SP31",
  #     model_item:   { ... },          # raw model item (nếu có)
  #     excel_item:   { ... },          # raw excel item (nếu có)
  #   }
  # -------------------------------------------------------
  def self.process_report_data(product_code, opts = {})
    load_excel   = opts.fetch(:load_excel, false)
    kind_filter  = opts.fetch(:kind_filter, nil)       # "PK", "VL", nil (cả 2)
    include_unmatched = opts.fetch(:include_unmatched, true)
    section_filter    = opts.fetch(:section_filter, nil)

    # --- 1. Thu thập dữ liệu Excel (JSON target) ---
    ex_items = respond_to?(:mini_excel_items) ? mini_excel_items(product_code, load_excel) : []

    # --- 2. Thu thập dữ liệu Model (thực tế) ---
    model_pk_items = respond_to?(:mini_pk_grouped_model_items) ? mini_pk_grouped_model_items(product_code) : []
    model_vl_items = respond_to?(:mini_model_items) ? mini_model_items(product_code).select { |m| m[:kind].to_s == "VL" } : []

    results = []
    matched_model_keys = opts.fetch(:matched_model_keys, [])

    # --- 3. Xử lý PK ---
    unless kind_filter == "VL"
      pk_excel = ex_items.reject { |ex| ex[:kind].to_s == "VL" }
      pk_excel_grouped = respond_to?(:mini_group_excel_items) ? mini_group_excel_items(pk_excel, true) : pk_excel

      pk_excel_grouped.each do |ex|
        row = _match_pk_excel_with_model(product_code, ex, model_pk_items, matched_model_keys, section_filter)
        results << row
      end

      # Model-only PK (không khớp với Excel)
      if include_unmatched
        model_pk_items.each do |m|
          key = respond_to?(:mini_model_item_key) ? mini_model_item_key(m) : "#{m[:name]}:#{m[:kind]}"
          next if matched_model_keys.include?(key)
          next if (m[:ids] || []).empty? && !m[:virtual]

          results << _build_model_only_row(product_code, m, "PK")
          matched_model_keys << key
        end
      end
    end

    # --- 4. Xử lý VL ---
    unless kind_filter == "PK"
      vl_excel = ex_items.select { |ex| ex[:kind].to_s == "VL" }
      vl_results = _process_vl_matching(product_code, vl_excel, model_vl_items, matched_model_keys, include_unmatched, section_filter)
      results.concat(vl_results)
    end

    results
  rescue => e
    puts "process_report_data error: #{e.message}" rescue nil
    []
  end

  # -------------------------------------------------------
  # process_report_data_all_products(product_codes, opts = {})
  #
  # Gộp kết quả process_report_data cho nhiều Mã SP.
  # Dùng cho bảng Tổng Dự Án.
  # -------------------------------------------------------
  def self.process_report_data_all_products(product_codes, opts = {})
    Array(product_codes).flat_map do |pc|
      process_report_data(pc, opts)
    end
  rescue => e
    puts "process_report_data_all_products error: #{e.message}" rescue nil
    []
  end

  # -------------------------------------------------------
  # process_report_data_aggregated(product_codes, opts = {})
  #
  # Gộp + Gom nhóm theo (kind, name_norm, kt_norm).
  # Cộng dồn excel_qty, model_qty. Gộp danh sách product_codes.
  # Dùng cho bảng Tổng Dự Án (BOM view).
  # -------------------------------------------------------
  def self.process_report_data_aggregated(product_codes, opts = {})
    raw = process_report_data_all_products(product_codes, opts)
    groups = {}

    raw.each do |row|
      name_n = import_name_norm(row[:name])
      kt_n   = import_name_norm(row[:kt].to_s)
      g_key  = "#{row[:kind]}|#{name_n}|#{kt_n}"

      if groups[g_key]
        g = groups[g_key]
        g[:excel_qty]  += row[:excel_qty].to_f
        g[:model_qty]  += row[:model_qty].to_f
        g[:products] << row[:product_code] unless g[:products].include?(row[:product_code])
        g[:ids].concat(Array(row[:ids]))
        if !row[:note].to_s.empty? && !g[:note].to_s.include?(row[:note].to_s)
          g[:note] = [g[:note], row[:note]].reject { |s| s.to_s.empty? }.join("; ")
        end
      else
        groups[g_key] = {
          kind:         row[:kind],
          name:         row[:name],
          target_name:  row[:target_name],
          kt:           row[:kt].to_s,
          unit:         row[:unit],
          note:         row[:note].to_s,
          excel_qty:    row[:excel_qty].to_f,
          model_qty:    row[:model_qty].to_f,
          products:     [row[:product_code]],
          ids:          Array(row[:ids]).dup,
        }
      end
    end

    # Tính status tổng hợp cho mỗi nhóm
    groups.values.each do |g|
      g[:status] = _compute_aggregated_status(g[:excel_qty], g[:model_qty])
    end

    groups.values.sort_by { |g| [g[:kind] == "VL" ? 1 : 0, g[:name].to_s] }
  rescue => e
    puts "process_report_data_aggregated error: #{e.message}" rescue nil
    []
  end

  private

  # -------------------------------------------------------
  # PRIVATE: Ghép cặp 1 dòng PK Excel với danh sách Model
  # -------------------------------------------------------
  def self._match_pk_excel_with_model(product_code, ex, model_items, matched_model_keys, section_filter)
    hw      = ex[:hw_name].to_s
    spec    = ex[:spec].to_s.strip
    section = ex[:section].to_s.strip
    section = section_filter.to_s.strip if section.empty? && !section_filter.to_s.strip.empty?

    target_name = respond_to?(:pk_update_target_name) ? pk_update_target_name(ex, nil) : (respond_to?(:import_display_name) ? import_display_name(hw, spec) : "#{hw} #{spec}".strip)
    norm_hw     = import_name_norm(hw)
    norm_target = import_name_norm(target_name)
    excel_qty   = ex[:qty].to_i
    note        = ex[:ghi_chu].to_s

    # Tìm model item khớp
    item_data = { hw: hw, spec: spec, target_name: target_name, norm_hw: norm_hw, norm_target: norm_target }
    model, resolved_target, _dup = respond_to?(:mini_pk_match_model_item) ?
      mini_pk_match_model_item(product_code, model_items, item_data, matched_model_keys) :
      [nil, target_name, false]

    model = nil if model && (model[:ids] || []).empty? && !model[:virtual]

    if model
      model_key = respond_to?(:mini_model_item_key) ? mini_model_item_key(model) : "#{model[:name]}:#{model[:kind]}"
      matched_model_keys << model_key unless matched_model_keys.include?(model_key)

      exact = import_name_norm(model[:name]) == import_name_norm(resolved_target)
      status_key = respond_to?(:resolve_mini_matched_status_key) ?
        resolve_mini_matched_status_key(product_code, "PK", model[:name], resolved_target, spec, exact) : (exact ? "OK" : "NO_SPEC")

      model_qty = _extract_model_qty(model)

      {
        source:       :matched,
        kind:         "PK",
        name:         model[:name],
        target_name:  resolved_target,
        spec:         spec,
        section:      section,
        note:         note,
        kt:           spec,
        unit:         model[:unit].to_s,
        excel_qty:    excel_qty.to_f,
        model_qty:    model_qty,
        status:       status_key,
        exact_match:  exact,
        editable:     model[:editable] != false,
        ids:          Array(model[:ids]),
        product_code: product_code,
        model_item:   model,
        excel_item:   ex,
      }
    else
      {
        source:       :excel_only,
        kind:         "PK",
        name:         hw,
        target_name:  target_name,
        spec:         spec,
        section:      section,
        note:         note,
        kt:           spec,
        unit:         "",
        excel_qty:    excel_qty.to_f,
        model_qty:    0.0,
        status:       "THIEU_MODEL",
        exact_match:  false,
        editable:     false,
        ids:          [],
        product_code: product_code,
        model_item:   nil,
        excel_item:   ex,
      }
    end
  rescue => e
    puts "_match_pk_excel_with_model error: #{e.message}" rescue nil
    { source: :error, kind: "PK", name: ex[:hw_name].to_s, status: "ERROR", excel_qty: 0.0, model_qty: 0.0, product_code: product_code }
  end

  # -------------------------------------------------------
  # PRIVATE: Xử lý ghép cặp VL
  # -------------------------------------------------------
  def self._process_vl_matching(product_code, vl_excel, model_vl_items, matched_model_keys, include_unmatched, section_filter)
    results = []
    vl_matched_keys = []

    vl_excel.each do |ex|
      hw      = ex[:hw_name].to_s
      spec    = ex[:spec].to_s.strip
      target  = respond_to?(:import_display_name) ? import_display_name(hw, spec) : "#{hw} #{spec}".strip
      note    = ex[:ghi_chu].to_s
      excel_qty = ex[:qty].to_f

      # Tìm model VL khớp
      matched_model = model_vl_items.find do |m|
        next false if vl_matched_keys.include?(m.object_id)
        respond_to?(:material_model_match_for_import?) ?
          material_model_match_for_import?(hw, m[:name]) || material_model_match_for_import?(target, m[:name]) :
          import_name_norm(m[:name]) == import_name_norm(hw) || import_name_norm(m[:name]) == import_name_norm(target)
      end

      if matched_model
        vl_matched_keys << matched_model.object_id
        model_key = "VL:#{matched_model[:name]}"
        matched_model_keys << model_key unless matched_model_keys.include?(model_key)

        exact = import_name_norm(matched_model[:name]) == import_name_norm(target)
        status_key = respond_to?(:resolve_mini_matched_status_key) ?
          resolve_mini_matched_status_key(product_code, "VL", matched_model[:name], target, spec, exact) : (exact ? "OK" : "NO_SPEC")

        model_qty = _extract_model_qty(matched_model)

        results << {
          source:       :matched,
          kind:         "VL",
          name:         matched_model[:name],
          target_name:  target,
          spec:         spec,
          section:      ex[:section].to_s,
          note:         note,
          kt:           spec,
          unit:         matched_model[:unit].to_s,
          excel_qty:    excel_qty,
          model_qty:    model_qty,
          status:       status_key,
          exact_match:  exact,
          editable:     false,
          ids:          Array(matched_model[:ids]),
          product_code: product_code,
          model_item:   matched_model,
          excel_item:   ex,
        }
      else
        # Excel-only VL
        status_key = respond_to?(:resolve_mini_excel_only_status_key) ?
          resolve_mini_excel_only_status_key(product_code, "VL", true, hw, spec) : "THIEU_MODEL"

        results << {
          source:       :excel_only,
          kind:         "VL",
          name:         hw,
          target_name:  target,
          spec:         spec,
          section:      ex[:section].to_s,
          note:         note,
          kt:           spec,
          unit:         "",
          excel_qty:    excel_qty,
          model_qty:    0.0,
          status:       status_key,
          exact_match:  false,
          editable:     false,
          ids:          [],
          product_code: product_code,
          model_item:   nil,
          excel_item:   ex,
        }
      end
    end

    # Model-only VL
    if include_unmatched
      model_vl_items.each do |m|
        next if vl_matched_keys.include?(m.object_id)
        next if (m[:ids] || []).empty? && !m[:virtual]

        results << _build_model_only_row(product_code, m, "VL")
      end
    end

    results
  rescue => e
    puts "_process_vl_matching error: #{e.message}" rescue nil
    []
  end

  # -------------------------------------------------------
  # PRIVATE: Dựng dòng Model-Only (không có Excel)
  # -------------------------------------------------------
  def self._build_model_only_row(product_code, model, kind)
    status_key = respond_to?(:resolve_mini_model_only_status_key) ?
      resolve_mini_model_only_status_key(product_code, kind, model[:name]) : "DU_MODEL"

    model_qty = _extract_model_qty(model)

    {
      source:       :model_only,
      kind:         kind,
      name:         model[:name],
      target_name:  "",
      spec:         "",
      section:      "",
      note:         "",
      kt:           "",
      unit:         model[:unit].to_s,
      excel_qty:    0.0,
      model_qty:    model_qty,
      status:       status_key,
      exact_match:  false,
      editable:     model[:editable] != false && kind != "VL",
      ids:          Array(model[:ids]),
      product_code: product_code,
      model_item:   model,
      excel_item:   nil,
    }
  rescue => e
    puts "_build_model_only_row error: #{e.message}" rescue nil
    { source: :error, kind: kind, name: model[:name].to_s, status: "ERROR", excel_qty: 0.0, model_qty: 0.0, product_code: product_code }
  end

  # -------------------------------------------------------
  # PRIVATE: Trích xuất số lượng từ model item
  # -------------------------------------------------------
  def self._extract_model_qty(model)
    qty = model[:qty].to_f
    unit = model[:unit].to_s.downcase

    # Cho các item dạng length (LED, thanh nhôm, suốt áo...)
    if qty <= 0 && model[:length].to_f > 0
      len_mm = model[:len_total_mm].to_f > 0 ? model[:len_total_mm].to_f : (model[:length].to_f * 25.4)
      if ["m", "md"].include?(unit)
        qty = (len_mm / 1000.0).round(2)
      else
        qty = model[:count].to_f
      end
    end

    qty = model[:count].to_f if qty <= 0
    qty
  rescue
    0.0
  end

  # -------------------------------------------------------
  # PRIVATE: Tính status tổng hợp cho nhóm gộp (aggregated)
  # -------------------------------------------------------
  def self._compute_aggregated_status(excel_qty, model_qty)
    eq = excel_qty.to_f
    mq = model_qty.to_f

    return "OK"           if eq > 0 && mq > 0 && (eq - mq).abs <= 0.01
    return "THIEU_MODEL"  if eq > 0 && mq <= 0
    return "DU_MODEL"     if eq <= 0 && mq > 0
    return "LECH_SL"      if eq > 0 && mq > 0 && (eq - mq).abs > 0.01
    "OK"
  rescue
    "UNKNOWN"
  end

end
