# encoding: utf-8
# MH_Thongke — bom data processor
# Logic xử lý dùng chung cho Mini Import và các bảng thống kê.
module MH_Thongke

  # === mini_import_model_items.rb ===
  # --- mini_import_model_items.rb ---
# MH_Thongke - Mini Import model item aggregation.

  def self.mini_model_rows_signature(rows)
    Array(rows).map do |row|
      next 0 unless row.is_a?(Hash)
      [
        row[:product], row[:actual_product], row[:product_list],
        row[:name], row[:ten_sp], row[:type], row[:unit],
        row[:count], row[:length], row[:len_total_mm],
        row[:ma_vl_source], row[:spec], row[:section], row[:ghi_chu],
        row[:virtual_source], row[:is_missing]
      ].hash
    end.hash
  rescue
    Array(rows).size
  end

  def self.mini_excel_rows_signature(rows)
    Array(rows).map do |row|
      next 0 unless row.is_a?(Hash)
      [
        row[:ma_sp], row[:kind], row[:hw_name], row[:spec],
        row[:section], row[:ghi_chu], row[:qty], row[:ma_vl_source],
        row["ma_sp"], row["kind"], row["hw_name"], row["spec"],
        row["section"], row["ghi_chu"], row["qty"], row["ma_vl_source"]
      ].hash
    end.hash
  rescue
    Array(rows).size
  end


  def self.rebuild_mini_model_row_indexes(mode)
    key = [
      mode.to_s,
      @process_selection_cache_sig.to_s,
      mini_model_rows_signature(@current_report_items),
      mini_model_rows_signature(@current_mat_items)
    ].join("::")
    return if @mini_model_row_index_key == key

    report_exact = Hash.new { |h, k| h[k] = [] }
    report_base  = Hash.new { |h, k| h[k] = [] }
    mat_exact = Hash.new { |h, k| h[k] = [] }
    mat_base  = Hash.new { |h, k| h[k] = [] }

    build_index = lambda do |rows, exact_idx, base_idx|
      Array(rows).each do |row|
        next unless row.is_a?(Hash)
        products = []
        products << row[:actual_product]
        products << row[:product]
        products.concat(Array(row[:product_list]))
        seen = {}
        products.each do |code|
          exact = product_code_exact(code)
          next if exact.empty? || exact == "--" || seen[exact]
          seen[exact] = true
          exact_idx[exact] << row
          base_idx[product_code_base(exact)] << row
        end
      end
    end

    build_index.call(@current_report_items, report_exact, report_base)
    build_index.call(@current_mat_items, mat_exact, mat_base)

    @mini_model_row_report_exact_index = report_exact
    @mini_model_row_report_base_index = report_base
    @mini_model_row_mat_exact_index = mat_exact
    @mini_model_row_mat_base_index = mat_base
    @mini_model_row_index_key = key
  rescue
    @mini_model_row_report_exact_index = {}
    @mini_model_row_report_base_index = {}
    @mini_model_row_mat_exact_index = {}
    @mini_model_row_mat_base_index = {}
    @mini_model_row_index_key = nil
  end

  def self.mini_model_items(product_code, mode = mini_group_mode)
    if @current_report_items.nil? && @current_mat_items.nil?
      respond_to?(:process_selection_cached) ? process_selection_cached(false) : process_selection
    end
    rebuild_mini_model_row_indexes(mode)
    cache_key = [
      product_code_exact(product_code),
      mode.to_s,
      @process_selection_cache_sig.to_s,
      mini_model_rows_signature(@current_report_items),
      mini_model_rows_signature(@current_mat_items),
      respond_to?(:mini_hidden_excel_items_signature) ? mini_hidden_excel_items_signature : 0,
      respond_to?(:hidden_names_signature) ? hidden_names_signature : ""
    ].join("::")
    live_only = defined?(MINI_IMPORT_LIVE_ONLY) && MINI_IMPORT_LIVE_ONLY
    cached = !live_only && respond_to?(:instance_cache_fetch) ? instance_cache_fetch(:@mini_model_items_cache, cache_key) : nil
    return cached unless cached.nil?

    target_exact = product_code_exact(product_code)
    target_base = product_code_base(target_exact)
    module_mode = mode.to_s != "product" && product_code_module?(target_exact)

    rows_pool = if module_mode
      Array(@mini_model_row_report_exact_index[target_exact]) + Array(@mini_model_row_report_base_index[target_base])
    else
      Array(@mini_model_row_report_base_index[target_base])
    end
    mat_rows_pool = if module_mode
      Array(@mini_model_row_mat_exact_index[target_exact]) + Array(@mini_model_row_mat_base_index[target_base])
    else
      Array(@mini_model_row_mat_base_index[target_base])
    end

    rows = rows_pool.uniq { |row| row.object_id }.select { |row| mini_model_row_for_product?(row, product_code, mode) }
    mat_rows = mat_rows_pool.uniq { |row| row.object_id }.select { |row| mini_model_row_for_product?(row, product_code, mode) }

    # Normalize row[:type] — JSON snapshot stores as String, live scan as Symbol.
    type_of = ->(row) { row[:type].is_a?(Symbol) ? row[:type] : row[:type].to_s.to_sym rescue :count }

    grouped = {}
    rows.each do |row|
      name = row[:name].to_s
      next if name.empty?
      section = strip_product_code_prefix(row[:ten_sp].to_s).strip
      stat_entries = live_stat_entries(row[:stat_entities])
      live_entries = live_row_entries(row)
      auto_generated_no_stat = stat_entries.empty? && !live_entries.empty?
      has_qty = row[:count].to_f > 0 || row[:length].to_f > 0 || row[:len_total_mm].to_f > 0
      next if live_entries.empty? && !has_qty
      row_type = type_of.call(row)
      row_virtual_source = row[:virtual_source].to_s.strip
      row_virtual_key = row[:virtual_key].to_s.strip
      if row_virtual_key.empty? && auto_generated_no_stat && respond_to?(:virtual_key)
        virtual_group = respond_to?(:classify_virtual_group) ? classify_virtual_group(name) : "VIRTUAL"
        row_virtual_key = virtual_key(
          product_code: row[:actual_product] || row[:product],
          group: virtual_group,
          spec: name,
          source: row_virtual_source.empty? ? "AUTO" : row_virtual_source,
          anchor: ""
        )
      end
      key = mini_model_group_key(name, section)
      grouped[key] ||= {
        name: name,
        section: section,
        qty: 0.0,
        unit: row_type == :phaochi ? "md" : row[:unit].to_s,
        kind: row_type == :phaochi ? "STAT" : "PK",
        editable: row_type != :phaochi && !auto_generated_no_stat,
        virtual: auto_generated_no_stat,
        virtual_key: row_virtual_key,
        virtual_source: row_virtual_source,
        rows: [],
        ids: []
      }
      grouped[key][:virtual_key] ||= row_virtual_key
      grouped[key][:virtual_source] ||= row_virtual_source
      grouped[key][:qty] += if row_type == :length
        raw_mm = row[:length].to_f * 25.4
        ["m", "md"].include?(row[:unit].to_s.downcase) ? raw_mm / 1000.0 : raw_mm
      elsif row_type == :phaochi
        row[:len_total_mm].to_f / 1000.0
      else
        row[:count].to_f > 0 ? row[:count].to_f : live_entries.size.to_f
      end
      grouped[key][:unit] = row_type == :phaochi ? "md" : row[:unit].to_s unless row[:unit].to_s.empty?
      grouped[key][:editable] = grouped[key][:editable] && (row_type != :phaochi && !auto_generated_no_stat)
      grouped[key][:rows] << row
      grouped[key][:ids].concat(mini_entity_ids_from_entries(stat_entries))
    end
    mat_rows.each do |row|
      raw_name = row[:name].to_s
      next if raw_name.empty?
      name = respond_to?(:material_code_display) ? material_code_display(raw_name) : raw_name
      name = raw_name if name.to_s.strip.empty?
      section = strip_product_code_prefix(row[:ten_sp].to_s).strip
      live_entries = live_row_entries(row)
      # Allow VL rows from JSON snapshot (entities stripped) when count > 0
      has_qty = row[:count].to_f > 0 || row[:length].to_f > 0
      next if live_entries.empty? && !has_qty
      key = mini_model_group_key(name, section, "vl")
      grouped[key] ||= {
        name: name,
        source_names: [],
        section: section,
        qty: 0.0,
        unit: row[:unit].to_s,
        kind: "VL",
        editable: false,
        rows: [],
        ids: []
      }
      qty_add = live_entries.empty? ? row[:count].to_f : live_entries.size.to_f
      grouped[key][:qty] += qty_add
      grouped[key][:unit] = row[:unit].to_s unless row[:unit].to_s.empty?
      grouped[key][:rows] << row
      grouped[key][:source_names] << raw_name unless grouped[key][:source_names].include?(raw_name)
      grouped[key][:ids].concat(mini_entity_ids_from_entries(live_entries))
    end
    items = grouped.values
    if respond_to?(:hidden_item_name?)
      items = items.reject { |item| hidden_item_name?(item[:name]) }
    end
    return items if live_only

    if respond_to?(:instance_cache_store)
      instance_cache_store(:@mini_model_items_cache, cache_key, items, 80)
    else
      @mini_model_items_cache ||= {}
      @mini_model_items_cache.clear if @mini_model_items_cache.size > 80
      @mini_model_items_cache[cache_key] = items
    end
  end

  def self.mini_model_row_for_product?(row, product_code, mode)
    return false if row[:is_missing]

    [row[:actual_product], row[:product]].any? { |value| mini_product_code_match?(value, product_code, mode) }
  rescue
    false
  end

  def self.mini_model_group_key(name, section, prefix = nil)
    key = import_name_norm(name)
    key = "#{prefix}:#{key}" unless prefix.to_s.empty?
    return key if prefix.to_s.empty?

    section_norm = import_name_norm(section)
    section_norm.empty? ? key : "#{key}|section:#{section_norm}"
  rescue
    prefix.to_s.empty? ? name.to_s : "#{prefix}:#{name}"
  end

  def self.mini_entity_ids_from_entries(entries)
    Array(entries).map do |pair|
      entity = pair.is_a?(Array) ? pair[0] : pair
      entity.entityID rescue nil
    end.compact
  rescue
    []
  end

  def self.mini_model_item_key(item)
    ids = Array(item[:ids]).map { |id| id.to_i }.reject(&:zero?).sort
    section = import_name_norm(item[:section])
    base = ids.empty? ? [import_name_norm(item[:name]), section].reject(&:empty?).join("|section:") : ids.join(",")
    "#{item[:kind]}:#{base}"
  end

  def self.mini_model_item_section_match?(item, section)
    wanted = import_name_norm(section)
    return true if wanted.empty?

    current = import_name_norm(item[:section])
    return true if current.empty?
    current == wanted
  rescue
    true
  end

  def self.mini_model_item_render_section_match?(item, section, strict_empty = false)
    wanted_raw = section.to_s.strip
    current_raw = item[:section].to_s.strip
    return strict_empty ? current_raw.empty? : true if wanted_raw.empty?
    return false if current_raw.empty?

    import_name_norm(current_raw) == import_name_norm(wanted_raw)
  rescue
    false
  end

  # === mini_import_excel_items.rb ===
  # --- mini_import_excel_items.rb ---
# MH_Thongke - Mini Import Excel item helpers.


  def self.rebuild_mini_excel_product_indexes(data, mode)
    key = [
      mode.to_s,
      @import_excel_loaded_path.to_s,
      @import_excel_loaded_mtime.to_f,
      data.size,
      mini_excel_rows_signature(data)
    ].join("::")
    return if @mini_excel_product_index_key == key

    exact_index = Hash.new { |h, k| h[k] = [] }
    base_index  = Hash.new { |h, k| h[k] = [] }
    Array(data).each do |ex|
      code = product_code_exact(ex[:ma_sp])
      next if code.empty? || code == "--"
      exact_index[code] << ex
      base_index[product_code_base(code)] << ex
    end

    @mini_excel_exact_index = exact_index
    @mini_excel_base_index = base_index
    @mini_excel_product_index_key = key
  rescue
    @mini_excel_exact_index = {}
    @mini_excel_base_index = {}
    @mini_excel_product_index_key = nil
  end

  def self.mini_excel_items(product_code, load_excel = true, mode = mini_group_mode)
    if load_excel
      ensure_import_excel_loaded
    elsif (!defined?(MINI_IMPORT_LIVE_ONLY) || !MINI_IMPORT_LIVE_ONLY) &&
          (!@imported_excel_data || @imported_excel_data.empty?) &&
          respond_to?(:load_import_excel_snapshot_only)
      load_import_excel_snapshot_only
    end
    data = @imported_excel_data || []
    rebuild_mini_excel_product_indexes(data, mode)
    hidden_excel_items = respond_to?(:mini_hidden_excel_items) ? mini_hidden_excel_items : []
    cache_key = [
      product_code_exact(product_code),
      mode.to_s,
      @import_excel_loaded_path.to_s,
      @import_excel_loaded_mtime.to_f,
      data.size,
      mini_excel_rows_signature(data),
      respond_to?(:mini_hidden_excel_items_signature) ? mini_hidden_excel_items_signature : hidden_excel_items.hash,
      respond_to?(:hidden_names_signature) ? hidden_names_signature : ""
    ].join("::")
    live_only = defined?(MINI_IMPORT_LIVE_ONLY) && MINI_IMPORT_LIVE_ONLY
    cached = !live_only && respond_to?(:instance_cache_fetch) ? instance_cache_fetch(:@mini_excel_items_cache, cache_key) : nil
    return cached unless cached.nil?

    target_exact = product_code_exact(product_code)
    target_base = product_code_base(target_exact)
    pool = if mode.to_s == "product" || !product_code_module?(target_exact)
      Array(@mini_excel_base_index[target_base])
    else
      Array(@mini_excel_exact_index[target_exact]) + Array(@mini_excel_base_index[target_base])
    end
    pool = pool.uniq { |ex| ex.object_id }

    items = pool.select { |ex|
      mini_product_code_match?(ex[:ma_sp], product_code, mode) &&
        !mini_excel_item_setting_hidden?(ex) &&
        !mini_excel_item_variant_only?(ex) &&
        !(hidden_excel_items.any? && respond_to?(:mini_excel_item_hidden?) && mini_excel_item_hidden?(product_code, ex))
    }
    return items if live_only

    if respond_to?(:instance_cache_store)
      instance_cache_store(:@mini_excel_items_cache, cache_key, items, 80)
    else
      @mini_excel_items_cache ||= {}
      @mini_excel_items_cache.clear if @mini_excel_items_cache.size > 80
      @mini_excel_items_cache[cache_key] = items
    end
  end

  def self.mini_excel_item_setting_hidden?(ex)
    return false unless respond_to?(:hidden_item_name?)

    name = ex[:hw_name].to_s
    spec = ex[:spec].to_s
    display_sub = if respond_to?(:mini_excel_display_sub_text)
      mini_excel_display_sub_text(ex, import_display_name(name, spec))
    else
      mini_excel_sub_text(ex, import_display_name(name, spec)) rescue ""
    end
    raw_parts_text = if respond_to?(:import_display_sub_text)
      import_display_sub_text(ex[:display_sub_parts] || ex["display_sub_parts"])
    else
      Array(ex[:display_sub_parts] || ex["display_sub_parts"]).map(&:to_s).join(" ")
    end
    material_row_text = if respond_to?(:mini_excel_material_group_parts) && respond_to?(:mini_excel_material_row_display_sub)
      group = mini_excel_material_group_parts(ex, name, spec, display_sub)
      group ? mini_excel_material_row_display_sub(group, display_sub) : ""
    else
      ""
    end
    hidden_item_name?(name, spec, import_display_name(name, spec), display_sub, raw_parts_text, material_row_text)
  rescue
    false
  end

  # Excel often duplicates a material as two rows:
  #   row 1: hw="PLY.AC.30YY-68"   spec="THÙNG ... 30YY 68/024 ..."
  #   row 2: hw="024-30"           spec="THÙNG ... 30YY 68/024 ..."
  # The second one is the COLOR/FINISH variant code, not a real material.
  # Filter it out (the main code already captures the item).
  def self.mini_excel_item_variant_only?(ex)
    name = ex[:hw_name].to_s.strip
    return false if name.empty?
    # Variant-only patterns: pure digits with optional -NN suffix, no letters
    # e.g. "024-30", "129-30", "300", "024", "1M-024"
    !!(name =~ /\A\d{2,4}(?:[-\/]\d{1,3})*\z/i)
  rescue
    false
  end

  def self.mini_excel_item_hidden?(product_code, ex)
    kind = ex[:kind].to_s.empty? ? "PK" : ex[:kind].to_s
    name = ex[:hw_name].to_s
    spec = ex[:spec].to_s
    [product_code, ex[:ma_sp]].any? do |product|
      mini_import_item_hidden?(product, kind, name, spec) ||
        mini_import_item_hidden?(product, kind, import_display_name(name, spec), "")
    end
  rescue
    false
  end

  def self.mini_excel_section_groups(ex_items_raw)
    groups = []
    index = {}
    Array(ex_items_raw).each do |ex|
      section = mini_excel_section_name(ex)
      key = section.empty? ? "__default__" : import_name_norm(section)
      unless index.key?(key)
        index[key] = groups.length
        groups << { section: section, items: [] }
      end
      groups[index[key]][:items] << ex
    end
    groups
  end

  def self.mini_import_section_title(product_code, section)
    display_code = product_code_base(product_code)
    section = section.to_s.strip
    section.empty? ? mini_import_title(product_code, false, "product") : "#{display_code} - #{section}"
  end

  def self.update_import_excel_note(product_code, kind, hw_name, spec, note)
    updated = 0
    target_product = product_code.to_s
    target_kind = mini_excel_item_kind(kind)
    target_hw = import_name_norm(hw_name)
    target_spec = import_name_norm(spec)
    (@imported_excel_data || []).each do |ex|
      next unless mini_excel_item_match?(ex, target_product, target_kind, target_hw, target_spec)
      ex[:ghi_chu] = note.to_s
      updated += 1
    end
    if updated > 0
      mini_import_invalidate_excel_caches
      save_import_excel_json_cache(nil, nil, @imported_excel_data, "json_edit") if respond_to?(:save_import_excel_json_cache)
    end
    updated
  end

  def self.remove_import_excel_item(product_code, kind, hw_name, spec)
    return 0 unless @imported_excel_data.is_a?(Array)
    target_product = product_code.to_s
    target_kind = mini_excel_item_kind(kind)
    target_hw = import_name_norm(hw_name)
    target_spec = import_name_norm(spec)
    removed = 0
    @imported_excel_data.each do |ex|
      next false unless mini_excel_item_match?(ex, target_product, target_kind, target_hw, target_spec)
      removed += 1
    end
    if removed > 0
      record_hidden_import_excel_item(target_product, target_kind, hw_name, spec) if respond_to?(:record_hidden_import_excel_item)
      mini_import_invalidate_excel_caches
    end
    removed
  rescue
    0
  end

  def self.mini_excel_item_kind(value)
    value.to_s.empty? ? "PK" : value.to_s
  rescue
    "PK"
  end

  def self.mini_excel_item_match?(ex, target_product, target_kind, target_hw_norm, target_spec_norm)
    mini_product_code_match?(ex[:ma_sp], target_product, mini_group_mode) &&
      mini_excel_item_kind(ex[:kind]) == target_kind &&
      import_name_norm(ex[:hw_name]) == target_hw_norm &&
      import_name_norm(ex[:spec]) == target_spec_norm
  rescue
    false
  end

  def self.mini_import_invalidate_excel_caches
    if respond_to?(:invalidate_mini_import_caches)
      invalidate_mini_import_caches(excel: true)
    else
      @mini_excel_items_cache = nil
      @mini_table_html_cache = nil
      @mini_last_refresh_state_sig = nil
      @mini_last_table_key = nil
    end
  end

  # === mini_import_material_rows.rb ===
  # --- mini_import_material_rows.rb ---
# MH_Thongke - shared material row matching for Mini Import and HUD.


  def self.mini_import_material_model_match?(excel_name, model_name)
    material_model_match_for_import?(excel_name, model_name)
  rescue
    false
  end

  def self.mini_import_material_row_status(row)
    key = resolve_mini_material_row_status_key(row)
    key == "NO_SPEC" ? "NO SPEC" : key
  rescue
    "NO SPEC"
  end

  def self.build_import_material_data_rows_for_product(product_code, ex_items_raw_override = nil, include_unmatched_model = true, matched_model_keys = nil, section_filter = nil, strict_section_filter = false, model_items_override = nil)
    model_items = Array(model_items_override || mini_model_items(product_code)).select { |m| m[:kind].to_s == "VL" }
    ex_items_raw = ex_items_raw_override || mini_excel_items(product_code, false).select { |ex| ex[:kind].to_s == "VL" }
    return [] if ex_items_raw.empty? && model_items.empty?

    rows = []
    matched_model_keys ||= []
    mini_group_excel_items(ex_items_raw, true).select { |ex| ex[:kind].to_s == "VL" }.each do |ex|
      hw = ex[:hw_name].to_s
      spec = ex[:spec].to_s.strip
      section = ex[:section].to_s.strip
      section = section_filter.to_s.strip if section.empty? && !section_filter.to_s.strip.empty?
      target_name = import_display_name(hw, spec)
      model = mini_import_find_material_model(model_items, hw, target_name, section)

      norm_hw = import_name_norm(hw)
      norm_target = import_name_norm(target_name)
      model_norm = model ? import_name_norm(model[:name]) : ""
      exact = !!model && (model_norm == norm_target || model_norm == norm_hw || mini_import_material_model_match?(hw, model[:name]))
      # Allow matched model when ids are stripped (JSON snapshot) but qty > 0
      model_has_qty = model && (model[:qty].to_f > 0 || model[:count].to_f > 0)
      model = nil if model && (model[:ids] || []).empty? && !model[:virtual] && !model_has_qty

      if model
        model_key = mini_model_item_key(model)
        matched_model_keys << model_key unless matched_model_keys.include?(model_key)
        display_sub = mini_import_material_display_sub(ex, target_name, model)
        row = mini_import_material_row(
          :matched,
          product_code,
          model[:name].to_s,
          Array(model[:ids]),
          hw,
          spec,
          section,
          ex[:ghi_chu].to_s,
          target_name,
          display_sub,
          mini_qty_display(model),
          exact,
          model,
          ex
        )
        row[:status] = mini_import_material_row_status(row)
        rows << row

        mini_import_append_related_material_rows(rows, matched_model_keys, model_items, model_key, product_code, hw, spec, section, ex, target_name, display_sub) if exact
      else
        display_sub = mini_import_material_display_sub(ex, target_name, nil)
        row = mini_import_material_row(
          :excel_only,
          product_code,
          target_name,
          [],
          hw,
          spec,
          section,
          ex[:ghi_chu].to_s,
          target_name,
          display_sub,
          ex[:qty].to_i,
          false,
          nil,
          ex
        )
        row[:status] = mini_import_material_row_status(row)
        rows << row
      end
    end

    mini_import_append_model_only_material_rows(rows, matched_model_keys, model_items, product_code, section_filter, strict_section_filter) if include_unmatched_model

    rows
  end

  def self.mini_import_material_candidates_for_section(model_items, section)
    candidates = model_items
    return [candidates, nil] if section.to_s.empty?

    sectioned_candidates = candidates.select { |item| !item[:section].to_s.strip.empty? }
    section_matches = sectioned_candidates.select { |item| mini_model_item_section_match?(item, section) }
    if sectioned_candidates.empty? && section_matches.empty?
      [candidates, nil]
    else
      [section_matches, section_matches]
    end
  end

  def self.mini_import_find_material_model(model_items, hw, target_name, section)
    norm_hw = import_name_norm(hw)
    norm_target = import_name_norm(target_name)
    candidates, section_limited_candidates = mini_import_material_candidates_for_section(model_items, section)
    model = candidates.find { |item| [norm_target, norm_hw].include?(import_name_norm(item[:name])) }
    model ||= candidates.find { |item| mini_import_material_model_match?(hw, item[:name]) }
    if !model && section_limited_candidates
      model = model_items.find { |item| [norm_target, norm_hw].include?(import_name_norm(item[:name])) }
      model ||= model_items.find { |item| mini_import_material_model_match?(hw, item[:name]) }
    end
    model
  rescue
    nil
  end

  def self.mini_import_material_display_sub(ex, target_name, model = nil)
    display_sub = respond_to?(:mini_excel_display_sub_text) ? mini_excel_display_sub_text(ex, target_name) : mini_excel_sub_text(ex, target_name)
    return display_sub unless model

    material_code_norm(mini_excel_sub_text(ex, target_name)) == material_code_norm(model[:name]) ? "" : display_sub
  rescue
    ""
  end

  def self.mini_import_material_row(type, product_code, name, ids, hw, spec, section, note, target_name, display_sub, qty, exact, model, excel)
    ma_vl_source = if excel.is_a?(Hash)
      (excel[:ma_vl_source] || excel["ma_vl_source"]).to_s
    else
      ""
    end
    {
      type: type,
      product_code: product_code,
      kind: "VL",
      name: name.to_s,
      ids: Array(ids),
      hw: hw,
      spec: spec,
      section: section,
      note: note.to_s,
      target_name: target_name,
      ma_vl_source: ma_vl_source,
      display_sub: display_sub,
      qty: qty,
      exact: exact,
      editable: false,
      model: model,
      excel: excel
    }
  end

  def self.mini_import_append_related_material_rows(rows, matched_model_keys, model_items, model_key, product_code, hw, spec, section, ex, target_name, display_sub)
    model_items.each do |candidate|
      next unless candidate[:kind].to_s == "VL"
      next unless mini_import_material_model_match?(hw, candidate[:name])

      related_key = mini_model_item_key(candidate)
      next if related_key == model_key
      next if matched_model_keys.include?(related_key)
      next if (candidate[:ids] || []).empty? && !candidate[:virtual]

      matched_model_keys << related_key
      related_row = mini_import_material_row(
        :related,
        product_code,
        candidate[:name].to_s,
        Array(candidate[:ids]),
        hw,
        spec,
        section,
        ex[:ghi_chu].to_s,
        target_name,
        display_sub,
        mini_qty_display(candidate),
        true,
        candidate,
        ex
      )
      related_row[:status] = mini_import_material_row_status(related_row)
      rows << related_row
    end
  end

  def self.mini_import_append_model_only_material_rows(rows, matched_model_keys, model_items, product_code, section_filter, strict_section_filter)
    model_items.each do |item|
      key = mini_model_item_key(item)
      next if matched_model_keys.include?(key)
      next unless mini_model_item_render_section_match?(item, section_filter, strict_section_filter)
      # Allow render when ids are stripped (JSON snapshot) but qty/count > 0
      item_has_qty = item[:qty].to_f > 0 || item[:count].to_f > 0
      next if (item[:ids] || []).empty? && !item[:virtual] && !item_has_qty

      row = mini_import_material_row(
        :model_only,
        product_code,
        item[:name].to_s,
        Array(item[:ids]),
        "",
        "",
        item[:section].to_s,
        "",
        "",
        "",
        mini_qty_display(item),
        false,
        item,
        nil
      )
      row[:status] = mini_import_material_row_status(row)
      rows << row
      matched_model_keys << key unless matched_model_keys.include?(key)
    end
  end

  # === mini_import_material_data.rb ===
  # --- mini_import_material_data.rb ---
# MH_Thongke - shared material section cache for Mini Import and Material HUD.


  def self.import_material_excel_items_signature(vl_ex_items)
    Array(vl_ex_items).map do |ex|
      [
        ex[:kind].to_s,
        ex[:ma_sp].to_s,
        ex[:hw_name].to_s,
        ex[:spec].to_s,
        ex[:section].to_s,
        ex[:ghi_chu].to_s,
        ex[:qty].to_s
      ].join("\u001F")
    end.join("\u001E").hash
  rescue
    Array(vl_ex_items).hash
  end

  def self.import_material_section_cache_key(product_code, vl_ex_items, use_model_items)
    [
      product_code_exact(product_code),
      use_model_items ? "model1" : "model0",
      Array(vl_ex_items).size,
      import_material_excel_items_signature(vl_ex_items),
      respond_to?(:import_mini_data_signature) ? import_mini_data_signature : import_mini_refresh_signature
    ].join("::")
  rescue
    nil
  end

  def self.build_import_material_section_data_for_product(product_code, vl_ex_items = nil, use_model_items = true)
    vl_ex_items = (vl_ex_items || mini_excel_items(product_code, false).select { |ex| ex[:kind].to_s == "VL" })
    live_only = defined?(MINI_IMPORT_LIVE_ONLY) && MINI_IMPORT_LIVE_ONLY
    cache_key = live_only ? nil : import_material_section_cache_key(product_code, vl_ex_items, use_model_items)
    cached = cache_key && respond_to?(:instance_cache_fetch) ? instance_cache_fetch(:@import_material_section_data_cache, cache_key) : nil
    return cached unless cached.nil?

    model_items = use_model_items ? mini_model_items(product_code).select { |m| m[:kind].to_s == "VL" } : []
    sections = []
    matched_model_keys = []
    groups = mini_excel_section_groups(vl_ex_items)

    if groups.size > 1
      groups.each do |group|
        rows = build_import_material_data_rows_for_product(product_code, group[:items], true, matched_model_keys, group[:section], true, model_items)
        next if rows.empty?

        section = group[:section].to_s.strip
        sections << {
          product_code: product_code,
          section: section,
          title: section.empty? ? "V\u1EADt li\u1EC7u" : "V\u1EADt li\u1EC7u - #{section}",
          hud_title: mini_import_section_title(product_code, group[:section]),
          leftover: false,
          rows: rows
        }
      end

      rows = build_import_material_data_rows_for_product(product_code, [], true, matched_model_keys, nil, false, model_items)
      if rows.any?
        sections << {
          product_code: product_code,
          section: "",
          title: "V\u1EADt li\u1EC7u",
          hud_title: "V\u1EADt li\u1EC7u",
          leftover: true,
          rows: rows
        }
      end
    else
      rows = build_import_material_data_rows_for_product(product_code, vl_ex_items, true, matched_model_keys, nil, false, model_items)
      if rows.any?
        sections << {
          product_code: product_code,
          section: "",
          title: "V\u1EADt li\u1EC7u",
          hud_title: mini_import_title(product_code, false),
          leftover: false,
          rows: rows
        }
      end
    end

    if cache_key && respond_to?(:instance_cache_store)
      instance_cache_store(:@import_material_section_data_cache, cache_key, sections, 200)
    end
    sections
  rescue => e
    puts "build_import_material_section_data_for_product error: #{e.message}"
    []
  end

  # --- Alias methods (without mini_ prefix) for backward-compatible rename ---
  def self.model_items_for_product(*a, **kw, &b); mini_model_items(*a, **kw, &b); end
  def self.model_row_for_product?(*a, **kw, &b); mini_model_row_for_product?(*a, **kw, &b); end
  def self.model_group_key(*a, **kw, &b); mini_model_group_key(*a, **kw, &b); end
  def self.entity_ids_from_entries(*a, **kw, &b); mini_entity_ids_from_entries(*a, **kw, &b); end
  def self.model_item_key(*a, **kw, &b); mini_model_item_key(*a, **kw, &b); end
  def self.model_item_section_match?(*a, **kw, &b); mini_model_item_section_match?(*a, **kw, &b); end
  def self.model_item_render_section_match?(*a, **kw, &b); mini_model_item_render_section_match?(*a, **kw, &b); end
  def self.excel_items_for_product(*a, **kw, &b); mini_excel_items(*a, **kw, &b); end
  def self.excel_item_setting_hidden?(*a, **kw, &b); mini_excel_item_setting_hidden?(*a, **kw, &b); end
  def self.excel_item_hidden?(*a, **kw, &b); mini_excel_item_hidden?(*a, **kw, &b); end
  def self.excel_section_groups(*a, **kw, &b); mini_excel_section_groups(*a, **kw, &b); end
  def self.import_section_title(*a, **kw, &b); mini_import_section_title(*a, **kw, &b); end
  def self.excel_item_kind(*a, **kw, &b); mini_excel_item_kind(*a, **kw, &b); end
  def self.excel_item_match?(*a, **kw, &b); mini_excel_item_match?(*a, **kw, &b); end
  def self.import_material_model_match?(*a, **kw, &b); mini_import_material_model_match?(*a, **kw, &b); end
  def self.import_material_row_status(*a, **kw, &b); mini_import_material_row_status(*a, **kw, &b); end
  def self.import_material_candidates_for_section(*a, **kw, &b); mini_import_material_candidates_for_section(*a, **kw, &b); end
  def self.import_find_material_model(*a, **kw, &b); mini_import_find_material_model(*a, **kw, &b); end
  def self.import_material_display_sub(*a, **kw, &b); mini_import_material_display_sub(*a, **kw, &b); end
  def self.import_material_row(*a, **kw, &b); mini_import_material_row(*a, **kw, &b); end
  def self.import_append_related_material_rows(*a, **kw, &b); mini_import_append_related_material_rows(*a, **kw, &b); end
  def self.import_append_model_only_material_rows(*a, **kw, &b); mini_import_append_model_only_material_rows(*a, **kw, &b); end

  def self.import_invalidate_excel_caches(*a, **kw, &b); mini_import_invalidate_excel_caches(*a, **kw, &b); end
end
