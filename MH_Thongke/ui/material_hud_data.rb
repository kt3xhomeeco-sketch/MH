# encoding: utf-8
# MH_Thongke - Material HUD data builders.

module MH_Thongke
  def self.material_hud_product_model_context(product_code, use_model_items)
    model_items = use_model_items ? mini_model_items(product_code).select { |m| m[:kind].to_s == "VL" } : []
    { items: model_items }
  rescue
    { items: [] }
  end

  def self.material_hud_model_data_available?
    Array(@current_report_items).any? || Array(@current_mat_items).any?
  rescue
    false
  end

  def self.material_hud_safe_products
    products = mini_display_products
    return products unless products.empty?

    selected = selected_product_codes(false).select { |code| product_code_valid?(code) } rescue []
    set_mini_products(selected) unless selected.empty?
    mini_display_products
  rescue
    []
  end

  def self.material_hud_resolve_products
    return material_hud_safe_products if @material_hud_lazy_open

    products = mini_display_products
    if products.empty?
      refresh_mini_products_from_source(false)
      products = mini_display_products
    end
    products
  rescue
    []
  end

  def self.material_hud_prepare_context(process_model, load_excel)
    products = material_hud_resolve_products
    return { state: :no_product, products: [], title: "" } if products.empty?

    # Phase 3: Stateless UI - Load từ final_stamped_report.json.
    # Khi mới bật HUD, tránh parse/scan nặng trong draw path để SketchUp không treo.
    if @material_hud_lazy_open
      @current_report_items ||= []
      @current_mat_items ||= []
      load_import_excel_snapshot_only if (!@imported_excel_data || @imported_excel_data.empty?) && respond_to?(:load_import_excel_snapshot_only)
      @imported_excel_data ||= []
      title = mini_product_display_title(products)
      return { state: :no_excel, products: products, title: title } if @imported_excel_data.empty?
      return { state: :ready, products: products, title: title, use_model_items: material_hud_model_data_available? }
    end

    json_path = defined?(MH_Thongke::Engine::CoreMatcher::FINAL_REPORT_JSON) ? MH_Thongke::Engine::CoreMatcher::FINAL_REPORT_JSON : nil
    if json_path && File.exist?(json_path)
      begin
        json_data = JSON.parse(File.read(json_path, encoding: "UTF-8"), symbolize_names: true)
        @current_report_items = json_data[:accessories] || []
        @current_mat_items = json_data[:materials] || []
        # Only overwrite Excel data if JSON has it; otherwise preserve existing
        # (mini import may have loaded it from import_excel_cache.json earlier)
        json_excel = json_data[:excel_data]
        if json_excel && !json_excel.empty?
          if respond_to?(:set_imported_excel_data)
            set_imported_excel_data(json_excel, "material_hud_final_report_json", sync_session: true)
          else
            @imported_excel_data = json_excel
          end
        elsif @imported_excel_data.nil? || @imported_excel_data.empty?
          load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)
          @imported_excel_data ||= []
        end
      rescue => e
        puts "Error parsing final_stamped_report.json in HUD: #{e.message}"
        @current_report_items ||= []
        @current_mat_items ||= []
        @imported_excel_data ||= []
      end
    else
      @current_report_items ||= []
      @current_mat_items ||= []
      if @imported_excel_data.nil? || @imported_excel_data.empty?
        load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)
        @imported_excel_data ||= []
      end
    end

    title = mini_product_display_title(products)
    return { state: :no_excel, products: products, title: title } if !@imported_excel_data || @imported_excel_data.empty?

    {
      state: :ready,
      products: products,
      title: title,
      use_model_items: true
    }
  rescue
    { state: :error, products: [], title: "" }
  end

  def self.material_hud_each_section(products, use_model_items)
    products.each do |product_code|
      sections = build_import_material_section_data_for_product(product_code, nil, use_model_items)
      show_header = products.size > 1 || sections.size > 1
      sections.each do |section|
        rows = Array(section[:rows])
        next if rows.empty?

        yield product_code, section, rows, show_header if block_given?
      end
    end
  rescue
    nil
  end

  def self.build_import_material_hud_rows(process_model = true, load_excel = false)
    ctx = material_hud_prepare_context(process_model, load_excel) { refresh_import_material_hud(false, false) }
    empty_msg = case ctx[:state]
                when :no_product    then "Ch\u01B0a x\u00E1c \u0111\u1ECBnh SP tr\u00EAn m\u00E0n h\u00ECnh."
                when :loading_excel then "Dang nap Excel..."
                when :no_excel      then "Kh\u00F4ng c\u00F3 d\u1EEF li\u1EC7u Excel."
                end
    return "<tr><td colspan='5' class='empty'>#{empty_msg}</td></tr>" if empty_msg
    return "<tr><td colspan='5' class='empty'>Loi du lieu HUD.</td></tr>" if ctx[:state] != :ready

    cache_key = material_hud_cache_key(process_model, load_excel)
    cached = material_hud_cache_fetch(:@material_hud_rows_cache, cache_key)
    return cached if cached

    # Unified flow: same renderer as Mini Import and main dialog material tables.
    # Iterate visible products; for each, build VL rows via the mini pipeline so
    # matching/status/display stay consistent across all surfaces.
    rows = +""
    Array(ctx[:products]).each do |product_code|
      ex_items = respond_to?(:mini_excel_items) ? mini_excel_items(product_code, false) : []
      vl_ex_items = ex_items.select { |ex| ex[:kind].to_s == "VL" }
      vl_html = respond_to?(:mini_rows_material_sections_html) ? mini_rows_material_sections_html(product_code, vl_ex_items) : ""
      next if vl_html.empty?

      rows << mini_group_header(product_code) if respond_to?(:mini_group_header)
      rows << vl_html
    end
    result = rows.empty? ? "<tr><td colspan='5' class='empty'>Kh\u00F4ng c\u00F3 d\u00F2ng v\u1EADt li\u1EC7u cho SP \u0111ang th\u1EA5y.</td></tr>" : rows
    material_hud_cache_store(:@material_hud_rows_cache, cache_key, result)
  end

  def self.build_import_material_hud_rows_for_product(product_code, ex_items_raw_override = nil, include_unmatched_model = true, use_model_items = true, matched_model_keys = nil, model_context = nil, section_filter = nil, strict_section_filter = false)
    model_context ||= material_hud_product_model_context(product_code, use_model_items)
    model_items = Array(model_context[:items])
    data_rows = build_import_material_data_rows_for_product(product_code, ex_items_raw_override, include_unmatched_model, matched_model_keys, section_filter, strict_section_filter, model_items)
    data_rows.map { |row| material_hud_row_from_import_data(row) }.join
  rescue => e
    puts "build_import_material_hud_rows_for_product error: #{e.message}"
    ""
  end

  def self.build_import_material_hud_entries(process_model = true, load_excel = false)
    ctx = material_hud_prepare_context(process_model, load_excel) { refresh_material_overlay_data(false, false, true) }
    return { title: "", rows: [], message: "Chua xac dinh SP tren man hinh." } if ctx[:state] == :no_product
    return { title: ctx[:title], rows: [], message: "Dang nap Excel..." } if ctx[:state] == :loading_excel
    return { title: ctx[:title], rows: [], message: "Khong co du lieu Excel." } if ctx[:state] == :no_excel
    return { title: ctx[:title], rows: [], message: "Loi du lieu HUD." } if ctx[:state] != :ready

    cache_key = material_hud_cache_key(process_model, load_excel)
    cached = material_hud_cache_fetch(:@material_hud_entries_cache, cache_key)
    return cached if cached

    rows = []
    max_rows = const_defined?(:HUD_MAX_BUILD_ROWS) ? HUD_MAX_BUILD_ROWS.to_i : 24
    material_hud_each_section(ctx[:products], ctx[:use_model_items]) do |_product_code, section, section_rows, show_header|
      product_rows = section_rows.map { |row| material_hud_entry_from_import_data(row) }.compact
      next if product_rows.empty?

      rows << { type: :product, title: section[:hud_title] } if show_header
      rows.concat(product_rows)
      break if max_rows > 0 && rows.size >= max_rows
    end
    rows = rows.first(max_rows) if max_rows > 0 && rows.size > max_rows
    message = rows.empty? ? "Khong co dong vat lieu cho SP dang thay." : ""
    result = { title: ctx[:title], rows: rows, message: message }
    material_hud_cache_store(:@material_hud_entries_cache, cache_key, result)
  rescue => e
    puts "build_import_material_hud_entries error: #{e.message}"
    { title: "", rows: [], message: "Loi HUD: #{e.message}" }
  end

  def self.build_import_material_hud_entries_for_product(product_code, ex_items_raw_override = nil, include_unmatched_model = true, use_model_items = true, matched_model_keys = nil, model_context = nil, section_filter = nil, strict_section_filter = false)
    model_context ||= material_hud_product_model_context(product_code, use_model_items)
    model_items = Array(model_context[:items])
    data_rows = build_import_material_data_rows_for_product(product_code, ex_items_raw_override, include_unmatched_model, matched_model_keys, section_filter, strict_section_filter, model_items)
    data_rows.map { |row| material_hud_entry_from_import_data(row) }
  rescue => e
    puts "build_import_material_hud_entries_for_product error: #{e.message}"
    []
  end

  def self.material_overlay_truncate_text(value, max_chars)
    text = fix_vietnamese_mojibake(value)
    text.length > max_chars ? "#{text[0, max_chars - 3]}..." : text
  rescue
    value.to_s
  end

  def self.material_overlay_estimated_text_width(text, size = 6)
    scale = size.to_f / 6.0
    text.to_s.each_char.sum do |char|
      width = case char
              when " "
                2.1
              when ".", ",", "/", "-", "_"
                2.5
              when "I", "i", "l", "1"
                2.4
              when "M", "W", "Â", "Ă", "Ê", "Ô", "Ư", "Đ"
                5.0
              when /[A-Z0-9]/
                4.1
              else
                char.ord > 127 ? 4.2 : 3.4
              end
      width * scale
    end
  rescue
    text.to_s.length * size.to_f * 0.58
  end

  def self.material_overlay_truncate_to_width(value, max_px, size = 6)
    text = fix_vietnamese_mojibake(value).to_s
    return text if material_overlay_estimated_text_width(text, size) <= max_px.to_f

    suffix = "..."
    suffix_w = material_overlay_estimated_text_width(suffix, size)
    used = 0.0
    out = +""
    text.each_char do |char|
      char_w = material_overlay_estimated_text_width(char, size)
      break if used + char_w + suffix_w > max_px.to_f

      out << char
      used += char_w
    end
    out.rstrip + suffix
  rescue
    material_overlay_truncate_text(value, 50)
  end

  def self.prepare_material_overlay_draw_data(data)
    data = data.is_a?(Hash) ? data.dup : {}
    title = data[:title].to_s
    data[:draw_title] = material_overlay_truncate_text(title.empty? ? "SP: --" : title, 58)
    data[:draw_message] = material_overlay_truncate_text(data[:message].to_s.empty? ? "Khong co du lieu." : data[:message].to_s, 80)
    data[:draw_rows] = Array(data[:rows]).map do |row|
      row = row.is_a?(Hash) ? row.dup : {}
      if row[:type] == :product
        row[:draw_title] = material_overlay_truncate_text(row[:title], 54)
      else
        sub = row[:target].to_s.strip
        sub = "" if sub.empty? ||
                    import_name_norm(sub) == import_name_norm(row[:name]) ||
                    material_code_norm(sub) == material_code_norm(row[:name])
        row[:draw_name] = material_overlay_truncate_text(row[:name], 40)
        row[:draw_sub] = material_overlay_truncate_to_width(sub, HUD_NAME_COLUMN_WIDTH - 12, 6)
        row[:draw_note] = material_overlay_truncate_text(row[:note], 12)
        row[:draw_status] = material_hud_status_draw_text(row[:status])
      end
      row
    end
    data
  rescue
    data
  end

  def self.build_material_overlay_draw_data(process_model = false, load_excel = false)
    cache_key = material_hud_cache_key(process_model, load_excel)
    cached = material_hud_cache_fetch(:@material_overlay_draw_cache, cache_key)
    return cached if cached

    material_hud_cache_store(
      :@material_overlay_draw_cache,
      cache_key,
      prepare_material_overlay_draw_data(build_import_material_hud_entries(process_model, load_excel))
    )
  end
end
