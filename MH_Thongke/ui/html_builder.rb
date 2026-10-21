require_relative 'project_total_bom'
# encoding: utf-8
# MH_Thongke - HTML Builder
# update_html + build helpers
# Tach tu main.rb: dong 2032-3238

module MH_Thongke

  def self.ui_product_code
    lambda do |value|
      text = value.to_s.strip
      next text if text.empty? || text == "--"

      respond_to?(:product_code_base) ? product_code_base(text) : text.sub(/\.\d+\z/, "")
    end
  end

  def self.ui_product_name
    lambda do |product, fallback|
      excel_name = respond_to?(:import_excel_product_name_for) ? import_excel_product_name_for(product, false) : ""
      excel_name.to_s.empty? ? fallback.to_s : excel_name
    end
  end

  def self.ui_count_text(value)
    value.to_i.to_s
  rescue
    "0"
  end

  def self.ui_number_text(value)
    number = value.to_f
    rounded = number.round(2)
    rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
  rescue
    "0"
  end

  def self.ui_selected_qty_html(value)
    number = value.to_f
    return "-" unless number > 0

    "<b style='color:#2980b9'>#{ui_number_text(number)}</b>"
  rescue
    "-"
  end

  def self.ui_selection_opacity(value, empty_style = "")
    return empty_style if @selection.nil? || @selection.empty?

    value.to_f > 0 ? "opacity:1;background-color:#2c3e50;" : "opacity:0.35;"
  rescue
    empty_style
  end

  def self.material_count_completion_summary(items = nil)
    rows = Array(items || @current_mat_items)
    groups = {}
    get = lambda { |row, key|
      row[key.to_sym] || row[key.to_s]
    }
    product_base = lambda do |value|
      text = value.to_s.strip.upcase
      if text =~ /\A([A-Z]+\d+)(?:\.\d+)?\z/
        Regexp.last_match(1)
      else
        text.split(".").first.to_s
      end
    end

    rows.each do |row|
      next unless row.is_a?(Hash)
      next if get.call(row, :is_missing)

      product = get.call(row, :actual_product).to_s.strip
      product = get.call(row, :product).to_s.strip if product.empty?
      product = product_base.call(product)
      product = "--" if product.empty?

      name = get.call(row, :ma_vl_source).to_s.strip
      name = get.call(row, :name).to_s.strip if name.empty?
      name = "--" if name.empty?

      spec = get.call(row, :spec).to_s.strip
      spec = get.call(row, :kich_thuoc).to_s.strip if spec.empty?
      spec = get.call(row, :thickness).to_s.strip if spec.empty?
      key = [product, name, spec].join("\u0000")
      groups[key] ||= { product: product, name: name, spec: spec, total: 0, pending: 0, ids: [], ten_sp_values: [] }
      group = groups[key]
      ten_sp_value = get.call(row, :ten_sp).to_s.strip
      if ten_sp_value.empty? && respond_to?(:import_excel_product_name_for)
        ten_sp_value = import_excel_product_name_for(product, false).to_s
      end
      group[:ten_sp_values] << ten_sp_value unless ten_sp_value.empty? || group[:ten_sp_values].include?(ten_sp_value)

      pairs = Array(get.call(row, :stat_entities))
      if pairs.any?
        pairs.each do |pair|
          ent = pair.is_a?(Array) ? pair[0] : pair
          next unless ent
          next if ent.respond_to?(:deleted?) && ent.deleted?

          group[:total] += 1
          ent_id = ent.entityID rescue nil
          group[:ids] << ent_id if ent_id && !group[:ids].include?(ent_id)
          layer_name = ent.respond_to?(:layer) && ent.layer ? ent.layer.name.to_s : ""
          pending = respond_to?(:material_layer_pending?) ? material_layer_pending?(layer_name) : (cached_norm(layer_name).gsub(/\s+/, "_") == "chua_dat")
          group[:pending] += 1 if pending
        end
      else
        qty = (get.call(row, :count) || get.call(row, :qty)).to_i
        next if qty <= 0

        group[:total] += qty
        Array(get.call(row, :ids)).each do |raw_id|
          ent_id = raw_id.to_i
          group[:ids] << ent_id if ent_id > 0 && !group[:ids].include?(ent_id)
        end
        tags = Array(get.call(row, :layer_tags)).map { |v| cached_norm(v).gsub(/\s+/, "_") rescue v.to_s.downcase.strip }
        group[:pending] += qty if tags.include?("chua_dat")
      end
    end

    groups.values.select { |group| group[:total].to_i > 0 }
  rescue
    []
  end

  def self.material_completion_source_items(fallback_items = nil)
    load_snapshots if respond_to?(:load_snapshots) && (@file_snapshots.nil? || @file_snapshots.empty?)
    normalize_snapshots! if respond_to?(:normalize_snapshots!)
    snapshots = respond_to?(:snapshots_for_current_project) ? snapshots_for_current_project(false) : []
    nesting = Array(snapshots).select do |snap|
      respond_to?(:snapshot_file_role) && snapshot_file_role(snap).to_s == "NESTING" && Array(snap["mat_items"]).any?
    end
    if nesting.any?
      latest = nesting.max_by do |snap|
        time = respond_to?(:snapshot_label_sort_time) ? snapshot_label_sort_time(snap["exported_at"]) : nil
        time || Time.at(0)
      end
      return Array(latest["mat_items"])
    end

    []
  rescue
    []
  end

  def self.material_abf_project_root_for_path(path)
    text = path.to_s.strip
    return "" if text.empty?

    dir = File.directory?(text) ? text : File.dirname(text)
    8.times do
      return dir if File.directory?(File.join(dir, "VT"))
      return File.dirname(dir) if File.basename(dir).to_s.upcase == "VT"

      parent = File.dirname(dir)
      break if parent.to_s.empty? || parent == dir

      dir = parent
    end
    ""
  rescue
    ""
  end

  def self.material_abf_project_root
    candidates = []
    model_path = (Sketchup.active_model.path rescue "").to_s
    candidates << model_path
    candidates << @import_excel_path.to_s
    candidates << @import_excel_loaded_path.to_s
    if respond_to?(:snapshots_for_current_project)
      Array(snapshots_for_current_project(false)).each { |snap| candidates << snap["skp_path"].to_s if snap.is_a?(Hash) }
    end

    candidates.each do |path|
      root = material_abf_project_root_for_path(path)
      return root unless root.empty?
    end
    ""
  rescue
    ""
  end

  def self.material_abf_header_key(value)
    value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip.
      sub(/\A\uFEFF/, "").
      downcase.gsub(/[^a-z0-9]/, "")
  rescue
    ""
  end

  def self.material_abf_sheet_key(value)
    material_abf_header_key(value)
  end

  def self.material_abf_xlsx_files(dir)
    return [] unless File.directory?(dir)

    Dir.children(dir).map { |name| File.join(dir, name) }.select do |path|
      File.file?(path) &&
        !File.basename(path).start_with?("~$") &&
        File.extname(path).to_s.downcase == ".xlsx"
    end.sort_by { |path| File.basename(path).downcase }
  rescue
    []
  end

  def self.material_abf_xml_unescape(value)
    value.to_s.gsub(/<!\[CDATA\[(.*?)\]\]>/m, '\1').
      gsub(/&#x([0-9a-fA-F]+);/) { Regexp.last_match(1).hex.chr(Encoding::UTF_8) }.
      gsub(/&#(\d+);/) { Regexp.last_match(1).to_i.chr(Encoding::UTF_8) }.
      gsub("&quot;", '"').gsub("&apos;", "'").gsub("&lt;", "<").gsub("&gt;", ">").gsub("&amp;", "&")
  rescue
    value.to_s
  end

  def self.material_abf_shared_strings(xml)
    return [] if xml.to_s.empty?

    xml.scan(/<si\b[^>]*>(.*?)<\/si>/m).map do |match|
      si = match[0].to_s
      si.scan(/<t\b[^>]*>(.*?)<\/t>/m).map { |m| material_abf_xml_unescape(m[0]) }.join
    end
  rescue
    []
  end

  def self.material_abf_cell_value(attrs, body, shared)
    type = attrs.to_s[/\bt="([^"]+)"/, 1].to_s
    case type
    when "s"
      idx = body.to_s[/<v\b[^>]*>(.*?)<\/v>/m, 1].to_i
      shared[idx].to_s
    when "inlineStr"
      body.to_s.scan(/<t\b[^>]*>(.*?)<\/t>/m).map { |m| material_abf_xml_unescape(m[0]) }.join
    else
      material_abf_xml_unescape(body.to_s[/<v\b[^>]*>(.*?)<\/v>/m, 1].to_s)
    end
  rescue
    ""
  end

  def self.material_abf_parse_sheet_fast(xml, shared)
    rows = []
    xml.to_s.scan(/<row\b[^>]*>(.*?)<\/row>/m).each do |row_match|
      row_xml = row_match[0].to_s
      cells = []
      next_col = 0
      row_xml.scan(/<c\b([^>]*?)(?:\/>|>(.*?)<\/c>)/m).each do |cell_match|
        attrs = cell_match[0].to_s
        body = cell_match[1].to_s
        ref = attrs[/\br="([^"]+)"/, 1]
        col = ref ? MH::XlsxIO.col_index(ref) : next_col
        col = next_col if col.to_i < 0
        cells[col] = material_abf_cell_value(attrs, body, shared)
        next_col = col + 1
      end
      rows << cells
    end
    rows
  rescue => e
    main_ui_debug("material_abf_parse_sheet_fast ERROR #{e.class}: #{e.message}") if respond_to?(:main_ui_debug)
    []
  end

  def self.material_abf_sheet_rows(path)
    bytes = File.binread(path)
    io = StringIO.new(bytes)

    ::Zip::File.open_buffer(io) do |zip|
      entries = MH::XlsxIO.index_entries(zip)
      sheets = MH::XlsxIO.workbook_sheets(zip, entries)
      target = sheets.find { |name, _target_path| material_abf_sheet_key(name) == "abfdata" }
      return [] unless target

      shared = material_abf_shared_strings(MH::XlsxIO.read_entry(zip, entries["xl/sharedstrings.xml"]))
      target_path = target[1].to_s
      xml = MH::XlsxIO.read_entry(zip, entries[target_path.downcase])
      return xml ? material_abf_parse_sheet_fast(xml, shared) : []
    end
    []
  rescue => e
    main_ui_debug("material_abf_sheet_rows #{File.basename(path)} ERROR #{e.class}: #{e.message}") if respond_to?(:main_ui_debug)
    []
  end

  def self.material_abf_rows_from_file(path)
    return [] unless defined?(MH::XlsxIO) && File.file?(path)

    rows = material_abf_sheet_rows(path)
    return [] if rows.empty?

    header_index = nil
    material_index = nil
    product_index = nil

    Array(rows).each_with_index do |row, idx|
      keys = Array(row).map { |cell| material_abf_header_key(cell) }
      material_index = keys.index("material")
      product_index = keys.index("masp")
      product_index ||= keys.index("productcode")
      product_index ||= keys.index("product")
      if material_index && product_index
        header_index = idx
        break
      end
    end
    return [] unless header_index && material_index && product_index

    out = []
    Array(rows)[(header_index + 1)..-1].to_a.each do |row|
      material = Array(row)[material_index].to_s.strip
      product = Array(row)[product_index].to_s.strip
      next if material.empty? || product.empty?

      out << { product: product, material: material }
    end
    out
  rescue => e
    main_ui_debug("material_abf_rows_from_file #{File.basename(path)} ERROR #{e.class}: #{e.message}") if respond_to?(:main_ui_debug)
    []
  end

  def self.material_abf_completion_summary
    root = material_abf_project_root
    return { root: root, groups: [], nhap_files: 0, du_kien_files: 0, nhap_total: 0, du_kien_total: 0 } if root.empty?

    nhap_dir = File.join(root, "VT", "DMVT")
    du_kien_dir = File.join(root, "VT", "NESTING")
    nhap_files = material_abf_xlsx_files(nhap_dir)
    du_kien_files = material_abf_xlsx_files(du_kien_dir)
    all_files = nhap_files + du_kien_files
    signature = ([root] + all_files.map { |path|
      size = File.size(path) rescue 0
      mtime = File.mtime(path).to_i rescue 0
      [path, size, mtime].join(":")
    }).join("|")

    @material_abf_completion_cache ||= {}
    cached = @material_abf_completion_cache[signature]
    return cached if cached
    @material_abf_completion_cache.clear if @material_abf_completion_cache.size > 3

    groups = {}
    add_rows = lambda do |paths, field|
      used = 0
      total = 0
      paths.each do |path|
        rows = material_abf_rows_from_file(path)
        next if rows.empty?

        used += 1
        rows.each do |row|
          product = row[:product].to_s.strip
          material = row[:material].to_s.strip
          key = [product.upcase, material.upcase].join("\u0000")
          groups[key] ||= { product: product, material: material, nhap: 0, du_kien: 0 }
          groups[key][field] += 1
          total += 1
        end
      end
      [used, total]
    end

    nhap_used, nhap_total = add_rows.call(nhap_files, :nhap)
    du_kien_used, du_kien_total = add_rows.call(du_kien_files, :du_kien)
    result = {
      root: root,
      groups: groups.values.select { |group| group[:nhap].to_i > 0 || group[:du_kien].to_i > 0 },
      nhap_files: nhap_used,
      du_kien_files: du_kien_used,
      nhap_total: nhap_total,
      du_kien_total: du_kien_total
    }
    @material_abf_completion_cache[signature] = result
  rescue => e
    main_ui_debug("material_abf_completion_summary ERROR #{e.class}: #{e.message}") if respond_to?(:main_ui_debug)
    { root: "", groups: [], nhap_files: 0, du_kien_files: 0, nhap_total: 0, du_kien_total: 0 }
  end

  def self.build_material_completion_summary_html(items = nil)
    summary = material_abf_completion_summary
    groups = Array(summary[:groups])
    if groups.empty?
      root_text = if summary[:root].to_s.empty?
        ""
      else
        nhap_path = File.join(summary[:root].to_s, "VT", "DMVT")
        du_kien_path = File.join(summary[:root].to_s, "VT", "NESTING")
        "<br><span style='font-size:10px;color:#a1a1aa'>#{html_escape(nhap_path)} và #{html_escape(du_kien_path)}</span>"
      end
      return "<div style='color:#7f8c8d;font-size:11px;padding:7px 8px;border:1px solid #4b5563;border-radius:4px;background:#20242a;margin:6px 0'>Chưa có dữ liệu <b>ABF DATA</b> đủ cột <b>material</b> và <b>Ma_SP</b>.#{root_text}</div>"
    end

    nhap_total = summary[:nhap_total].to_i
    du_kien_total = summary[:du_kien_total].to_i
    total_percent = du_kien_total > 0 ? (nhap_total * 100.0 / du_kien_total) : 0.0
    total_text = respond_to?(:material_completion_text) ? material_completion_text(total_percent) : "#{total_percent.round(1)}%"

    rows_html = groups.sort_by { |group| [group[:product].to_s.upcase, group[:material].to_s.upcase] }.map do |group|
      nhap = group[:nhap].to_i
      du_kien = group[:du_kien].to_i
      percent = du_kien > 0 ? (nhap * 100.0 / du_kien) : 0.0
      percent_text = du_kien > 0 ? (respond_to?(:material_completion_text) ? material_completion_text(percent) : "#{percent.round(1)}%") : "--"
      color = if du_kien <= 0
        "#a1a1aa"
      elsif nhap >= du_kien
        "#2ecc71"
      elsif nhap > 0
        "#f1c40f"
      else
        "#e74c3c"
      end

      <<~HTML
        <tr>
          <td><b style='color:#e67e22'>#{html_escape(group[:product])}</b></td>
          <td>#{html_escape(group[:material])}</td>
          <td style='text-align:center;color:#2ecc71'>#{nhap}</td>
          <td style='text-align:center;color:#3498db'>#{du_kien}</td>
          <td style='text-align:center'><b style='color:#{color}'>#{html_escape(percent_text)}</b></td>
        </tr>
      HTML
    end.join

    <<~HTML
      <div style="border:1px solid #4b5563;border-radius:4px;background:#20242a;margin:6px 0 8px 0;overflow:hidden" onclick="event.stopPropagation()" onmousedown="event.stopPropagation()" ondblclick="event.stopPropagation()">
        <div style="display:flex;justify-content:space-between;gap:8px;align-items:center;background:#2f3640;padding:6px 8px;font-size:11px">
          <b style="color:#27ae60">BẢNG % VẬT LIỆU THEO ABF DATA</b>
          <span style="color:#bdc3c7">Nhập: <b style="color:#2ecc71">#{nhap_total}</b> (#{summary[:nhap_files].to_i} file) | Dự kiến: <b style="color:#3498db">#{du_kien_total}</b> (#{summary[:du_kien_files].to_i} file) | <b>#{html_escape(total_text)}</b></span>
        </div>
        <div style="max-height:190px;overflow:auto">
          <table id="mat-completion-summary-table" data-no-resize="1" style="margin:0;user-select:none">
            <thead><tr>
              <th width="13%">Mã SP</th>
              <th>Material</th>
              <th width="70" style="text-align:center">SL nhập</th>
              <th width="75" style="text-align:center">SL dự kiến</th>
              <th width="60" style="text-align:center">%</th>
            </tr></thead>
            <tbody>#{rows_html}</tbody>
          </table>
        </div>
      </div>
    HTML
  rescue => e
    main_ui_debug("build_material_completion_summary_html ERROR #{e.class}: #{e.message}") if respond_to?(:main_ui_debug)
    ""
  end

  def self.ui_back_import_active?
    data = session.back_imported_excel || @back_imported_excel
    data && !data.empty?
  rescue
    false
  end

  def self.ui_back_diff_cell(row, field, active = nil)
    enabled = active.nil? ? ui_back_import_active? : active
    return nil unless enabled

    diff = row[:back_diff]
    return nil unless diff.is_a?(Hash)

    value = diff[field]
    value.is_a?(Hash) ? value : nil
  rescue
    nil
  end

  def self.ui_back_diff_value_text(value)
    case value
    when Numeric
      f = value.to_f
      (f - f.round).abs < 0.0001 ? f.round.to_i.to_s : f.round(2).to_s
    else
      text = value.to_s
      text.strip.empty? ? "-" : text
    end
  rescue
    "-"
  end

  def self.ui_back_diff_note(cell)
    return "" unless cell

    "<span class='excel-diff-note'>Excel: #{html_escape(ui_back_diff_value_text(cell[:excel]))}</span>"
  rescue
    ""
  end

  def self.ui_back_diff_td_class(cell)
    cell ? " class='cell-diff'" : ""
  rescue
    ""
  end

  def self.ui_execute_main_dialog_script(script)
    return main_dialog_execute_script(script) if respond_to?(:main_dialog_execute_script)
    return false unless @dlg && @dlg.visible?

    @dlg.execute_script(script.to_s)
    true
  rescue
    false
  end

  def self.pk_report_view_scope_value
    mode = (session.pk_report_view_scope || @pk_report_view_scope).to_s.upcase
    ["PROJECT", "CUT"].include?(mode) ? mode : "PROJECT"
  rescue
    "PROJECT"
  end

  # Render <option> list for the data-source switcher dropdown.
  # Always includes MODEL (current SketchUp model) plus any imported snapshots.
  def self.render_data_source_options
    active = respond_to?(:active_data_source_id) ? active_data_source_id : "MODEL"
    options = []
    options << "<option value='MODEL' #{active == 'MODEL' ? 'selected' : ''}>MODEL hiện tại</option>"
    sources = respond_to?(:pk_report_cut_sources) ? pk_report_cut_sources : []
    sources.each do |src|
      sid = src[:id].to_s
      sel = sid == active ? "selected" : ""
      options << "<option value='#{html_escape(sid)}' #{sel}>#{html_escape(src[:label])}</option>"
    end
    options.join
  rescue
    "<option value='MODEL' selected>MODEL hiện tại</option>"
  end

  def self.pk_report_cut_sources
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    normalize_snapshots!
    sources = []
    snapshots_for_current_project.each do |snap|
      next if respond_to?(:snapshot_file_role) && snapshot_file_role(snap).to_s != "CNC"
      items = Array(snap["items"]).select { |it| it.is_a?(Hash) }
      mat_items = Array(snap["mat_items"]).select { |it| it.is_a?(Hash) }
      next if items.empty? && mat_items.empty?
      label = [snap["label"].to_s.strip, snap["skp_name"].to_s.strip].reject(&:empty?).join(" | ")
      label = snap["skp_name"].to_s.strip if label.empty?
      sources << {
        id: "snap:#{snap['id']}",
        label: label,
        items: items,
        mat_items: mat_items
      }
    end
    Array(@pk_report_external_sources).each do |source|
      next unless source.is_a?(Hash)
      items = Array(source["items"]).select { |it| it.is_a?(Hash) }
      mat_items = Array(source["mat_items"]).select { |it| it.is_a?(Hash) }
      next if items.empty? && mat_items.empty?
      sid = source["id"].to_s.strip
      sid = "json:#{sources.size}" if sid.empty?
      sources << {
        id: sid,
        label: source["label"].to_s.strip.empty? ? "JSON ngoài" : source["label"].to_s,
        items: items,
        mat_items: mat_items
      }
    end
    sources
  rescue
    []
  end

  def self.pk_report_status_badge(text)
    key = status_key(text)
    case key
    when "OK"
      "<span style='color:#27ae60;font-weight:bold'>✓</span>"
    when "UPDATE"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#3498db;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>UPDATE</span>"
    when "SPEC"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#7f8c8d;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>SPEC</span>"
    when "NO_SPEC"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#e74c3c;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>NO SPEC</span>"
    when "GHOST"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#8e44ad;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>GHOST</span>"
    else
      html_escape(text.to_s)
    end
  rescue
    html_escape(text.to_s)
  end

  def self.pk_report_row_status_text(item)
    return "" unless item.is_a?(Hash)

    raw = item["trang_thai"] || item[:trang_thai]
    normalized = status_text(raw)
    return normalized unless normalized.to_s.empty?

    has_obj =
      if item.key?("has_obj") || item.key?(:has_obj)
        item["has_obj"] == true || item[:has_obj] == true
      elsif item.key?("obj_count") || item.key?(:obj_count)
        (item["obj_count"] || item[:obj_count]).to_i > 0
      else
        nil
      end
    is_missing = item["is_missing"] == true || item[:is_missing] == true

    return "THIEU" if is_missing || has_obj == false
    return "OK" if has_obj == true

    # Legacy snapshots may miss status/obj metadata; keep status column visible.
    "OK"
  rescue
    ""
  end

  def self.pk_excel_rows_by_product
    rows = Array(@imported_excel_data).select { |row| row.is_a?(Hash) }
    grouped = Hash.new { |h, k| h[k] = [] }
    product_codes = []
    rows.each do |row|
      kind = (row[:kind] || row["kind"]).to_s.strip.upcase
      next if kind == "VL"
      product_code = report_product_code(row[:ma_sp] || row["ma_sp"])
      next if product_code.to_s.empty?
      product_codes << product_code
    end

    product_codes.uniq.each do |product_code|
      source_rows =
        if respond_to?(:mini_excel_items)
          Array(mini_excel_items(product_code, false))
        else
          rows.select { |row| report_product_code(row[:ma_sp] || row["ma_sp"]) == product_code }
        end

      source_rows.each do |row|
        kind = (row[:kind] || row["kind"]).to_s.strip.upcase
        next if kind == "VL"
        grouped[product_code] << {
          ma_sp: product_code,
          kind: "PK",
          hw_name: (row[:hw_name] || row["hw_name"]).to_s,
          spec: (row[:spec] || row["spec"]).to_s,
          ten_sp: (row[:ten_sp] || row["ten_sp"]).to_s,
          ghi_chu: (row[:ghi_chu] || row["ghi_chu"]).to_s,
          qty: 1,
          raw: row
        }
      end
    end
    grouped
  rescue
    {}
  end

  # Build PROJECT view PK rows by comparing snapshot items with Excel source.
  # This keeps status aligned with Mini Import matching rules.
  def self.pk_project_items_with_excel_status(items)
    model_items = Array(items).map { |it| it.is_a?(Hash) ? it.dup : nil }.compact
    excel_by_product = pk_excel_rows_by_product
    grouped_model = Hash.new { |h, k| h[k] = [] }
    model_items.each do |item|
      code = report_product_code(item["product"])
      code = item["product"].to_s.strip.upcase if code.to_s.empty?
      grouped_model[code] << item unless code.to_s.empty?
    end

    output = []
    all_products = (grouped_model.keys + excel_by_product.keys).uniq
    all_products.each do |product_code|
      product_model_items = grouped_model[product_code] || []
      excel_rows = excel_by_product[product_code] || []
      excel_rows = mini_group_excel_items(excel_rows, true) if respond_to?(:mini_group_excel_items)
      matched_excel = Array.new(excel_rows.size, false)

      product_model_items.each do |item|
        name = item["name"].to_s
        model_section = strip_product_code_prefix(item["ten_sp"].to_s).to_s.strip
        status =
          if item["is_missing"] == true
            "THIEU"
          elsif excel_rows.empty?
            resolve_mini_model_only_status_key(product_code, "PK", name)
          else
            matched_index = nil
            matched_target = ""
            excel_rows.each_with_index do |ex, idx|
              next if matched_excel[idx]

              if !model_section.empty?
                ex_section = ex[:section].to_s
                ex_section = mini_excel_section_name(ex).to_s if ex_section.empty? && respond_to?(:mini_excel_section_name)
                unless ex_section.to_s.strip.empty?
                  model_section_norm = respond_to?(:import_section_norm) ? import_section_norm(model_section) : import_name_norm(model_section)
                  ex_section_norm = respond_to?(:import_section_norm) ? import_section_norm(ex_section) : import_name_norm(ex_section)
                  next if !model_section_norm.empty? && !ex_section_norm.empty? && model_section_norm != ex_section_norm
                end
              end

              if respond_to?(:mini_name_family_key)
                model_family = mini_name_family_key(name)
                excel_family = mini_name_family_key(ex[:hw_name].to_s)
                next if model_family && excel_family && model_family != excel_family
              end

              special_target = nil
              if respond_to?(:special_hafele_update_name)
                special_target = special_hafele_update_name(ex[:hw_name].to_s, name, ex[:spec].to_s)
              end
              next unless pk_matches_excel_like_mini?(product_code, name, ex, special_target)

              matched_index = idx
              matched_target = respond_to?(:pk_update_target_name) ? pk_update_target_name(ex, special_target) : (special_target.to_s.strip.empty? ? import_display_name(ex[:hw_name].to_s, ex[:spec].to_s) : special_target.to_s)
              break
            end
            if matched_index
              matched_excel[matched_index] = true
              if respond_to?(:resolve_mini_matched_status_key)
                spec = excel_rows[matched_index][:spec].to_s
                exact = import_name_norm(name) == import_name_norm(matched_target.to_s)
                resolve_mini_matched_status_key(product_code, "PK", name, matched_target.to_s, spec, exact)
              else
                "OK"
              end
            else
              resolve_mini_model_only_status_key(product_code, "PK", name)
            end
          end

        item["trang_thai"] = status_text(status)
        item["product"] = product_code if item["product"].to_s.strip.empty?
        output << item
      end

      # Add missing rows from Excel so PROJECT scope doesn't hide products absent in model.
      excel_rows.each_with_index do |ex, idx|
        next if matched_excel[idx]
        hw_name = ex[:hw_name].to_s.strip
        next if hw_name.empty?
        status = resolve_mini_excel_only_status_key(product_code, "PK", false, ex[:hw_name].to_s, ex[:spec].to_s)
        output << {
          "name" => import_display_name(ex[:hw_name].to_s, ex[:spec].to_s),
          "product" => product_code,
          "ten_sp" => begin
            section = ex[:section].to_s
            section = mini_excel_section_name(ex).to_s if section.empty? && respond_to?(:mini_excel_section_name)
            section
          rescue
            ex[:ten_sp].to_s
          end,
          "qty" => ex[:qty].to_i <= 0 ? 1 : ex[:qty].to_i,
          "unit" => "Cái",
          "kich_thuoc" => "",
          "ghi_chu" => ex[:ghi_chu].to_s,
          "ngay_dat" => "",
          "layer" => "-",
          "last_modified" => "",
          "type" => "count",
          "trang_thai" => status_text(status),
          "is_missing" => true,
          "obj_count" => 0,
          "has_obj" => false
        }
      end
    end

    output
  rescue
    Array(items)
  end

  def self.build_pk_report_cut_rows(items, include_missing: false, unified_source: false)
    # Cache by content + flags. Big speedup for repeated calls.
    list = Array(items).select { |it| it.is_a?(Hash) }
    list_sig = if respond_to?(:mini_model_rows_signature)
      mini_model_rows_signature(list)
    else
      list.hash
    end
    excel_sig = if respond_to?(:mini_excel_rows_signature)
      mini_excel_rows_signature(@imported_excel_data)
    else
      Array(@imported_excel_data).hash
    end
    cache_key = [list_sig, include_missing ? 1 : 0, unified_source ? 1 : 0, excel_sig].join("::")
    @build_pk_report_cut_rows_cache ||= {}
    return @build_pk_report_cut_rows_cache[cache_key] if @build_pk_report_cut_rows_cache.key?(cache_key)
    @build_pk_report_cut_rows_cache.clear if @build_pk_report_cut_rows_cache.size > 20

    rows = String.new
    return @build_pk_report_cut_rows_cache[cache_key] = "<tr><td colspan='13' style='text-align:center;color:#7f8c8d;padding:15px'>Không có dữ liệu phụ kiện trong nguồn đã chọn.</td></tr>" if list.empty?

    has_obj_flag = lambda do |item|
      return true if item["has_obj"] == true
      return item["obj_count"].to_i > 0 if item.key?("obj_count")
      nil
    rescue
      nil
    end
    missing_item = lambda do |item|
      return !include_missing if item["is_missing"] == true
      st = begin
        MH_Thongke.status_key(pk_report_row_status_text(item))
      rescue
        pk_report_row_status_text(item).to_s.strip.upcase
      end
      layer = item["layer"].to_s.strip
      layer == "-" && ["SPEC", "GHOST"].include?(st)
    rescue
      false
    end
    normalize_product = lambda do |value|
      raw = value.to_s.strip
      if unified_source
        exact = respond_to?(:product_code_exact) ? product_code_exact(raw) : raw.upcase
        return exact.to_s.strip
      end
      raw = report_product_code(raw) if respond_to?(:report_product_code)
      raw = raw.to_s.strip
      raw = respond_to?(:product_code_base) ? product_code_base(raw) : raw.split(".").first.to_s.upcase
      raw.to_s.strip.upcase
    rescue
      value.to_s.strip.upcase
    end
    has_meta = list.any? { |item| item.key?("has_obj") || item.key?("obj_count") || item.key?("is_missing") }
    groups = {}
    list.each do |it|
      next if !unified_source && missing_item.call(it)
      has_obj = has_obj_flag.call(it)
      next if !unified_source && has_meta && has_obj == false && !(include_missing && it["is_missing"] == true)

      product = normalize_product.call(it["product"])
      if unified_source
        next if product.to_s.strip.empty?
      else
        next unless product_code_valid?(product) rescue product =~ /\A[A-Z]+\d+[A-Z]?\z/i
      end

      name = fix_vietnamese_mojibake(it["name"]).to_s.strip
      next if name.empty?
      next if !unified_source && respond_to?(:hidden_item_name?) && hidden_item_name?(name)

      kt = fix_vietnamese_mojibake(it["kich_thuoc"]).to_s.strip
      unit = fix_vietnamese_mojibake(it["unit"]).to_s.strip
      qty = it["qty"].to_f
      qty = 0.0 if qty.nan? || qty.infinite?
      key = [product, cached_norm(name), cached_norm(kt), unit]
      groups[key] ||= {
        product: product,
        ten_sp_values: [],
        name: name,
        kt: kt,
        note_values: [],
        status_values: [],
        updated_values: [],
        layer_values: [],
        ngay_dat_values: [],
        qty: 0.0,
        unit: unit
      }
      g = groups[key]
      g[:ten_sp_values] << it["ten_sp"].to_s
      g[:note_values] << it["ghi_chu"].to_s
      g[:status_values] << pk_report_row_status_text(it)
      g[:updated_values] << it["last_modified"].to_s
      g[:layer_values] << it["layer"].to_s
      g[:ngay_dat_values] << normalize_order_date(it["ngay_dat"])
      g[:qty] += qty
    end
    empty_msg = unified_source ? "Không có dữ liệu phụ kiện hợp lệ trong nguồn project-total." : "Không có dữ liệu phụ kiện hợp lệ (đã lọc dòng ảo/ẩn)."
    return "<tr><td colspan='13' style='text-align:center;color:#7f8c8d;padding:15px'>#{empty_msg}</td></tr>" if groups.empty?

    join_values = lambda do |values|
      values.map { |v| fix_vietnamese_mojibake(v).to_s.strip }.reject(&:empty?).uniq.join("; ")
    end

    groups.values.sort_by do |row|
      [
        (respond_to?(:product_code_sort_key) ? product_code_sort_key(row[:product]) : row[:product].to_s),
        cached_norm(row[:name].to_s),
        cached_norm(row[:kt].to_s)
      ]
    end.each do |row|
      note_text = join_values.call(row[:note_values])
      layer_text = join_values.call(row[:layer_values])
      ten_sp_text = join_values.call(row[:ten_sp_values])
      ngay_dat_text = join_values.call(row[:ngay_dat_values])
      status_text = row[:status_values].map { |s| s.to_s }.max_by { |s| status_priority(s) rescue 0 }.to_s
      updated_text = join_values.call(row[:updated_values])
      qty_text = ui_number_text(row[:qty].to_f)
      search_text = [row[:product], ten_sp_text, row[:name], row[:kt], note_text, layer_text].join(" ").downcase
      rows << "<tr class='data-row' data-search='#{html_escape(search_text)}'>"
      rows << "<td><b style='color:#e67e22'>#{html_escape(row[:product])}</b></td>"
      rows << "<td>#{html_escape(ten_sp_text)}</td>"
      rows << "<td>#{html_escape(row[:name])}</td>"
      rows << "<td>#{html_escape(row[:kt])}</td>"
      rows << "<td>#{html_escape(note_text)}</td>"
      rows << "<td>#{pk_report_status_badge(status_text)}</td>"
      rows << "<td style='font-size:11px;color:gray'>#{html_escape(updated_text)}</td>"
      rows << "<td>#{html_escape(layer_text)}</td>"
      rows << "<td>#{html_escape(ngay_dat_text)}</td>"
      rows << "<td style='text-align:center'>-</td>"
      rows << "<td><b style='color:#e74c3c'>#{html_escape(qty_text)}</b></td>"
      rows << "<td>#{html_escape(row[:unit])}</td>"
      rows << "<td></td>"
      rows << "</tr>"
    end

    @build_pk_report_cut_rows_cache[cache_key] = rows
  rescue => e
    "<tr><td colspan='13' style='text-align:center;color:#e74c3c;padding:15px'>Lỗi đọc dữ liệu theo lần cắt: #{html_escape(e.message)}</td></tr>"
  end

  def self.update_html(force_full = false)
    return unless @dlg

    # Phase 2: Pull state from session — UI always reads the latest data
    s = session
    @current_report_items = s.current_report_items || []
    @current_mat_items    = s.current_mat_items    || []
    # If user has switched to an imported data source ("Cắt lần 1" etc.),
    # swap @current_report_items / @current_mat_items so all builders below
    # see the imported data as if it were the live model.
    apply_active_data_source! if respond_to?(:apply_active_data_source!)
    @group_by             = s.group_by
    @display_mode         = s.display_mode
    @hidden_list          = s.hidden_list          || []
    @unit_overrides       = s.unit_overrides       || {}
    @length_display_units = s.length_display_units || {}
    @known_pk_names       = s.known_pk_names       || []
    @back_imported_excel  = s.back_imported_excel
    # Preserve @imported_excel_data if session is empty — module variable may
    # hold data loaded from JSON cache by mini import or HUD. Overwriting with
    # empty session data wipes that and forces mini to fall back to "no excel".
    if s.imported_excel_data && !s.imported_excel_data.empty?
      if respond_to?(:set_imported_excel_data)
        set_imported_excel_data(s.imported_excel_data, "html_builder_session_sync", sync_session: false)
      else
        @imported_excel_data = s.imported_excel_data
      end
    elsif @imported_excel_data.nil? || @imported_excel_data.empty?
      load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)
    end

  # Phase 3: Stateless UI - Load tu final_stamped_report.json (overrides session if file is newer)
  # CACHED by mtime to avoid re-parsing 175KB JSON on every update_html call.
  # SKIP when user switched to a non-MODEL data source — final_stamped_report.json
  # is the MODEL's data and would clobber the imported snapshot we just swapped in.
  source_active = respond_to?(:active_data_source_id) && active_data_source_id != "MODEL"
  json_path = defined?(MH_Thongke::Engine::CoreMatcher::FINAL_REPORT_JSON) ? MH_Thongke::Engine::CoreMatcher::FINAL_REPORT_JSON : nil
  if !@main_fast_open && !source_active && json_path && File.exist?(json_path)
    begin
      mtime = File.mtime(json_path).to_f
      if @final_report_json_loaded_mtime != mtime || @final_report_json_cached_acc.nil?
        json_data = JSON.parse(File.read(json_path, encoding: "UTF-8"), symbolize_names: true)
        @final_report_json_cached_acc = json_data[:accessories] || []
        @final_report_json_cached_mat = json_data[:materials] || []
        @final_report_json_loaded_mtime = mtime
      end
      @current_report_items = @final_report_json_cached_acc
      @current_mat_items    = @final_report_json_cached_mat
      s.current_report_items = @current_report_items
      s.current_mat_items    = @current_mat_items
    rescue => e
      puts "Error parsing final_stamped_report.json in html_builder: #{e.message}"
    end
  end

  sync_import_excel_path
  load_back_import_cache if respond_to?(:load_back_import_cache) && (@back_imported_excel.nil? || @back_imported_excel.empty?)
    t_rows = String.new
    ui_product_code = self.ui_product_code
    ui_product_name = self.ui_product_name
    report_index_by_object_id = {}
    (@current_report_items || []).each_with_index { |item, idx| report_index_by_object_id[item.object_id] ||= idx }
    mat_index_by_object_id = {}
    (@current_mat_items || []).each_with_index { |item, idx| mat_index_by_object_id[item.object_id] ||= idx }
    @html_report_index_by_object_id = report_index_by_object_id
    @html_mat_index_by_object_id = mat_index_by_object_id

    display_items = @current_report_items
    if @display_mode == "SELECTED" && !@selection.empty?
      display_items = @current_report_items.select do |data|
        if data[:type] == :length || data[:type] == :phaochi
          data[:sel_length].to_f > 0 || data[:sel_count].to_i > 0
        else
          data[:sel_count].to_i > 0
        end
      end
    end

    display_items_with_tree = []
    if @group_by == "PRODUCT"
      base_groups = {}
      display_items.each do |item|
        prod = item[:product].to_s
        base = ui_product_code.call(prod)
        base_groups[base] ||= { items: [], sub_items: [] }
        prod == base ? base_groups[base][:items] << item : base_groups[base][:sub_items] << item
      end
      base_groups.keys.sort.each do |base|
        g = base_groups[base]
        if g[:sub_items].empty?
          g[:items].each { |item| display_items_with_tree << { mode: :normal, base: base, data: item } }
        else
          agg = {}
          (g[:items] + g[:sub_items]).each do |item|
            k = "#{item[:name]}_#{item[:type]}"
            if agg[k]
              agg[k][:count] = agg[k][:count].to_i + item[:count].to_i
              agg[k][:sel_count] = agg[k][:sel_count].to_i + item[:sel_count].to_i
              if item[:type] == :length
                agg[k][:length] = agg[k][:length].to_f + item[:length].to_f
                agg[k][:sel_length] = agg[k][:sel_length].to_f + item[:sel_length].to_f
                agg[k][:length_items] = Array(agg[k][:length_items]) + Array(item[:length_items])
              elsif item[:type] == :phaochi
                agg[k][:len_total_mm] = (agg[k][:len_total_mm] || 0) + item[:len_total_mm].to_f
                agg[k][:sel_len_mm]   = (agg[k][:sel_len_mm] || 0)   + item[:sel_len_mm].to_f
              end
              agg[k][:stat_entities] = (agg[k][:stat_entities] || []) + (item[:stat_entities] || [])
              agg[k][:entities]      = (agg[k][:entities] || [])      + (item[:entities] || [])
              agg[k][:original_indices] = (agg[k][:original_indices] || []) + [report_index_by_object_id[item.object_id]]
            else
              agg[k] = item.dup; agg[k][:product] = base
              agg[k][:original_indices] = [report_index_by_object_id[item.object_id]]
            end
          end
          agg.values.sort_by { |v| v[:name].to_s }.each { |item| display_items_with_tree << { mode: :parent, base: base, data: item } }
          g[:items].each    { |item| display_items_with_tree << { mode: :child,  base: base, data: item } }
          g[:sub_items].each { |item| display_items_with_tree << { mode: :child, base: base, data: item } }
          display_items_with_tree << { mode: :child_dummy, base: base, data: nil }
        end
      end
    else
      display_items.sort_by { |item| [item[:name].to_s.downcase, item[:product].to_s] }
                   .each { |item| display_items_with_tree << { mode: :normal, base: item[:name], data: item } }
    end

    # Mat tree
    display_mat_items = @current_mat_items || []
    display_mat_items = display_mat_items.select { |d| d[:sel_count].to_i > 0 } if @display_mode == "SELECTED" && !@selection.empty?
    display_mat_items_with_tree = []
    if @group_by == "PRODUCT"
      m_base_groups = {}
      display_mat_items.each do |item|
        prod = item[:product].to_s; base = ui_product_code.call(prod)
        m_base_groups[base] ||= { items: [], sub_items: [] }
        prod == base ? m_base_groups[base][:items] << item : m_base_groups[base][:sub_items] << item
      end
      m_base_groups.keys.sort.each do |base|
        g = m_base_groups[base]
        agg = {}
        (g[:items] + g[:sub_items]).each do |item|
          k = item[:name]
          if agg[k]
            agg[k][:count] = agg[k][:count].to_i + item[:count].to_i
            agg[k][:sel_count] = agg[k][:sel_count].to_i + item[:sel_count].to_i
            agg[k][:entities] = (agg[k][:entities] || []) + (item[:entities] || [])
            agg[k][:children] << item
          else
            agg[k] = item.dup; agg[k][:product] = base; agg[k][:children] = [item]
          end
        end
        agg.values.sort_by { |v| v[:name].to_s }.each do |item|
          pd = item.dup; pd.delete(:children)
          display_mat_items_with_tree << { mode: :parent, base: base, data: pd }
        end
        agg.values.sort_by { |v| v[:name].to_s }.each do |item|
          item[:children].each { |child| display_mat_items_with_tree << { mode: :child, base: base, data: child } }
        end
        display_mat_items_with_tree << { mode: :child_dummy, base: base, data: nil }
      end
    else
      display_mat_items.each { |item| display_mat_items_with_tree << { mode: :normal, base: item[:product], data: item } }
    end

    # Rowspan
    product_rowspan = Hash.new(0)
    display_items_with_tree.each do |ti|
      next if ti[:mode] == :child_dummy
      row = ti[:data]
      cu  = row[:_resolved_unit] || row[:unit]
      pk  = "#{ti[:mode]}_#{row[:product]}"
      ti[:p_key] = pk
      if row[:type] == :length && !["mm","m","md"].include?(cu) && row[:length_items].is_a?(Array) && !row[:length_items].empty?
        product_rowspan[pk] += row[:length_items].map { |li| (li[:len_inch].to_f * 25.4).round(0) }.uniq.size
      else
        product_rowspan[pk] += 1
      end
    end
    mat_product_rowspan = Hash.new(0)
    display_mat_items_with_tree.each do |ti|
      next if ti[:mode] == :child_dummy
      pk = "#{ti[:mode]}_#{ti[:data][:product]}"
      ti[:p_key] = pk; mat_product_rowspan[pk] += 1
    end

    current_pkey = nil
    header_rendered = {}
    acc_child_bases = display_items_with_tree.select { |ti| ti[:mode] == :child }.map { |ti| ti[:base] }.uniq
    mat_child_bases = display_mat_items_with_tree.select { |ti| ti[:mode] == :child }.map { |ti| ti[:base] }.uniq
    unit_options_count  = ["Cái","Chiếc","Bộ","Đôi","Cuộn","Thanh","thanh"]
    unit_options_length = ["mm","m","md"]
    all_unit_options    = unit_options_count + unit_options_length

    back_import_active = ui_back_import_active?

    unless respond_to?(:build_tab_acc_bom_rows)
    display_items_with_tree.each_with_index do |tree_item, _vi|
      mode = tree_item[:mode]; base = tree_item[:base]
      if mode == :child_dummy
        t_rows << "<tr class='child-row' data-tree='#{html_escape(base)}' style='display:none;'><td class='tree-span' colspan='13' style='background:#1e272e;border-bottom:1px solid #7f8c8d;'>&nbsp;</td></tr>"
        next
      end
      data  = tree_item[:data]
      p_key = tree_item[:p_key]
      if !header_rendered[base] && acc_child_bases.include?(base)
        prod_safe = base.to_s.gsub("'","\\\\'")
        t_rows << "<tr class='data-row header-row' data-tree='#{html_escape(base)}' style='display:none;background:#34495e;'><td class='tree-span' colspan='13' style='cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{base}</b><br><span class='tree-icon' onclick='sketchup.toggle_tree(#{js_arg(base)});event.stopPropagation()' style='font-size:11px;color:#e74c3c;cursor:pointer'>▲</span></td></tr>"
        header_rendered[base] = true
      end
      current_unit = data[:_resolved_unit] || data[:unit]
      data[:unit] = current_unit
      ten_sp_input = data[:ten_sp].to_s.gsub("'","&apos;").gsub('"','&quot;')
      ghi_chu_input = data[:ghi_chu].to_s.gsub("'","&apos;").gsub('"','&quot;')
      layer_input = data[:layer].to_s.gsub('"','&quot;')
      product_values = if @group_by == "NAME"
        vals = Array(data[:product_list])
        vals = [data[:actual_product], data[:product]] if vals.empty?
        vals.map { |v| ui_product_code.call(v) }.map(&:to_s).map(&:strip).reject { |v| v.empty? || v == "--" }.uniq
      else
        [ui_product_code.call(data[:product])]
      end
      product_display = product_values.empty? ? data[:product].to_s : product_values.join(", ")
      product_click = (product_values.first || data[:actual_product] || data[:product]).to_s
      excel_ten_sp_values = product_values.map { |p| ui_product_name.call(p, "") }.reject(&:empty?).uniq
      ten_sp_values = if excel_ten_sp_values.any?
        excel_ten_sp_values
      elsif @group_by == "NAME"
        vals = Array(data[:ten_sp_list])
        vals = [data[:ten_sp]] if vals.empty?
        vals.map(&:to_s).map(&:strip).reject(&:empty?).uniq
      else
        [ui_product_name.call(data[:actual_product] || data[:product], data[:ten_sp].to_s)]
      end
      ten_sp_display = ten_sp_values.empty? ? data[:ten_sp].to_s : ten_sp_values.join(", ")
      ten_sp_input = ten_sp_display.to_s.gsub("'","&apos;").gsub('"','&quot;')
      search_text = "#{data[:product]} #{product_display} #{data[:name]} #{ten_sp_display}".downcase

      i = mode == :parent ? data[:original_indices].first : report_index_by_object_id[data.object_id]

      # --- Phào Chỉ ---
      is_phaochi = data[:type] == :phaochi
      # --- Length-to-count split ---
      is_length_to_count = (!is_phaochi && data[:type] == :length && !["mm","m","md"].include?(current_unit) && data[:length_items].is_a?(Array) && !data[:length_items].empty?)

      if is_length_to_count
        prev_len_unit = data[:_length_display_unit] || "mm"
        groups = {}
        data[:length_items].each do |li|
          lm = (li[:len_inch].to_f * 25.4).round(0)
          groups[lm] ||= { count: 0, sel_count: 0 }
          groups[lm][:count] += 1; groups[lm][:sel_count] += 1 if li[:selected]
        end
        sorted_groups = groups.sort_by { |lm,_| lm }

        status_target = (mode == :parent && data[:original_indices].is_a?(Array) && !data[:original_indices].empty?) ? data[:original_indices] : i
        status_btn = build_status_btn(data, status_target)
        update_info = status_key(data[:trang_thai]) == "UPDATE" ? "<br><span style='font-size:10px;color:#3498db'>→ #{data[:new_name]}</span>" : ""
        diff_name = ui_back_diff_cell(data, :name, back_import_active)
        diff_ten_sp = ui_back_diff_cell(data, :ten_sp, back_import_active)
        diff_note = ui_back_diff_cell(data, :ghi_chu, back_import_active)
        diff_date = ui_back_diff_cell(data, :ngay_dat, back_import_active)
        diff_qty = ui_back_diff_cell(data, :qty, back_import_active)
        diff_unit = ui_back_diff_cell(data, :unit, back_import_active)
        sorted_groups.each_with_index do |(len_mm, grp), gi|
          len_display = ["m","md"].include?(prev_len_unit) ? "#{(len_mm/1000.0).round(2)}#{prev_len_unit}" : "#{len_mm.to_i}mm"
          sub_name  = "#{data[:name]} - dài #{len_display}"
          sub_name_input = sub_name.gsub('"','&quot;')
          display_qty = ui_count_text(grp[:count])
          display_sel_qty = ui_selected_qty_html(grp[:sel_count])
          opacity_style = ui_selection_opacity(grp[:sel_count])
          row_bg = ""
          cls   = "data-row#{mode == :parent ? " parent-row" : (mode == :child ? " child-row" : "")}"
          style = [opacity_style, row_bg, (mode == :child ? "display:none;" : "")].join
          t_rows << "<tr id='row_#{i}' class='#{cls}' data-tree='#{html_escape(base)}' style='#{style}' data-search='#{html_escape(search_text)}' onclick='doSelectRow(#{i})'>"
          unless @group_by == "NAME"
            if mode != :child
              if gi == 0 && p_key != current_pkey
                prod_display_code = ui_product_code.call(data[:product])
                prod_safe = prod_display_code.to_s.gsub("'","\\\\'")
                btn = mode == :parent ? "<br><span class='tree-icon' onclick='sketchup.toggle_tree(#{js_arg(base)});event.stopPropagation()' style='font-size:11px;color:#3498db;cursor:pointer'>▼</span>" : ""
                t_rows << "<td rowspan='#{product_rowspan[p_key]}' style='vertical-align:middle;cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{prod_display_code}</b>#{btn}</td>"
                current_pkey = p_key
              end
            else
              prod_display_code = ui_product_code.call(data[:product])
              prod_safe = prod_display_code.to_s.gsub("'","\\\\'")
              t_rows << "<td style='vertical-align:middle;cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{prod_display_code}</b></td>"
            end
          end
          unit_sel = gi == 0 ? build_unit_select(i, current_unit, all_unit_options) : ""
          name_td_class = gi == 0 ? ui_back_diff_td_class(diff_name) : ""
          ten_sp_td_class = gi == 0 ? ui_back_diff_td_class(diff_ten_sp) : ""
          note_td_class = gi == 0 ? ui_back_diff_td_class(diff_note) : ""
          qty_td_class = gi == 0 ? ui_back_diff_td_class(diff_qty) : ""
          unit_td_class = gi == 0 ? ui_back_diff_td_class(diff_unit) : ""
          name_note = gi == 0 ? ui_back_diff_note(diff_name) : ""
          ten_sp_note = gi == 0 ? ui_back_diff_note(diff_ten_sp) : ""
          note_note = gi == 0 ? ui_back_diff_note(diff_note) : ""
          qty_note = gi == 0 ? ui_back_diff_note(diff_qty) : ""
          unit_note = gi == 0 ? ui_back_diff_note(diff_unit) : ""
          ngay_dat_cell = gi == 0 ? build_ngay_dat_cell(i, data[:ngay_dat].to_s, :acc, diff_date) : ""
          if @group_by == "NAME"
            name_cell = gi == 0 ? "<input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='name' data-bulk-index='#{i}' id='rename_#{i}' value='#{sub_name_input}' spellcheck='false' onclick='event.stopPropagation()' onchange='if(!handleBulkChange(this)) sketchup.update_name(#{i},this.value)'>#{update_info}#{name_note}" : sub_name
            note_cell = gi == 0 ? "<input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='ghi_chu' data-bulk-index='#{i}' value='#{ghi_chu_input}' onchange='if(!handleBulkChange(this)) sketchup.update_ghi_chu(#{i},this.value)' onclick='event.stopPropagation()'>" : ""
            tag_cell = gi == 0 ? "<input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='tag' data-bulk-index='#{i}' id='retag_#{i}' value='#{layer_input}' spellcheck='false' onclick='event.stopPropagation()' onchange='if(!handleBulkChange(this)) sketchup.update_tag(#{i},this.value)'>" : ""
            t_rows << "<td#{name_td_class} style='white-space:nowrap'>#{name_cell}</td>"
            t_rows << "<td style='cursor:pointer' onclick='doSelectRow(#{i})'>#{gi == 0 ? data[:kich_thuoc].to_s : ''}</td>"
            t_rows << "<td#{note_td_class}>#{note_cell}#{note_note}</td>"
            t_rows << "<td>#{gi == 0 ? status_btn : ''}</td>"
            t_rows << "<td style='font-size:11px;color:gray'>#{gi == 0 ? data[:last_modified] : ''}</td>"
            t_rows << "<td style='white-space:nowrap'>#{tag_cell}</td>"
            t_rows << (gi == 0 ? ngay_dat_cell : "<td></td>")
          elsif gi == 0
            t_rows << "<td#{ten_sp_td_class}><input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='ten_sp' data-bulk-index='#{i}' value='#{ten_sp_input}' onchange='if(!handleBulkChange(this)) sketchup.update_ten_sp(#{i},this.value)' onclick='event.stopPropagation()'>#{ten_sp_note}</td>"
            t_rows << "<td#{name_td_class} style='white-space:nowrap'><input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='name' data-bulk-index='#{i}' id='rename_#{i}' value='#{sub_name_input}' spellcheck='false' onclick='event.stopPropagation()' onchange='if(!handleBulkChange(this)) sketchup.update_name(#{i},this.value)'>#{update_info}#{name_note}</td>"
            t_rows << "<td style='cursor:pointer' onclick='doSelectRow(#{i})'>#{data[:kich_thuoc].to_s}</td>"
            t_rows << "<td#{note_td_class}><input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='ghi_chu' data-bulk-index='#{i}' value='#{ghi_chu_input}' onchange='if(!handleBulkChange(this)) sketchup.update_ghi_chu(#{i},this.value)' onclick='event.stopPropagation()'>#{note_note}</td>"
            t_rows << "<td>#{status_btn}</td>"
            t_rows << "<td style='font-size:11px;color:gray'>#{data[:last_modified]}</td>"
            t_rows << "<td style='white-space:nowrap'><input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='tag' data-bulk-index='#{i}' id='retag_#{i}' value='#{layer_input}' spellcheck='false' onclick='event.stopPropagation()' onchange='if(!handleBulkChange(this)) sketchup.update_tag(#{i},this.value)'></td>"
            t_rows << ngay_dat_cell
          else
            t_rows << "<td></td><td style='cursor:pointer' onclick='doSelectRow(#{i})'>#{sub_name}</td><td></td><td></td><td></td>"
            t_rows << "<td style='font-size:11px;color:gray'>#{data[:last_modified]}</td>"
            t_rows << "<td style='cursor:pointer' onclick='doSelectRow(#{i})'>#{data[:layer]}</td><td></td>"
          end
          t_rows << "<td style='cursor:pointer;text-align:center' onclick='doSelectRow(#{i})'>#{display_sel_qty}</td>"
          t_rows << "<td#{qty_td_class} style='cursor:pointer' onclick='doSelectRow(#{i})'><b style='color:#e74c3c'>#{display_qty}</b>#{qty_note}</td>"
          t_rows << "<td#{unit_td_class}>#{unit_sel}#{unit_note}</td>"
          t_rows << "<td><button class='btn btn-red' style='padding:3px 5px;font-size:11px' onclick='if(confirm(\"Xóa?\")) sketchup.delete_row(#{i});event.stopPropagation()'>✕</button></td>"
          t_rows << "</tr>"
        end
        next
      end

      # --- Bình thường (kể cả Phào Chỉ) ---
      if is_phaochi
        len_md = (data[:len_total_mm].to_f / 1000.0).round(2)
        display_qty = ui_number_text(len_md)
        sel_md = (data[:sel_len_mm].to_f / 1000.0).round(2)
        display_sel_qty = ui_selected_qty_html(sel_md)
        opacity_style = ui_selection_opacity(sel_md)
      elsif data[:type] == :length
        raw_mm = data[:length].to_f * 25.4
        display_qty = case current_unit
                      when "m","md" then (raw_mm/1000.0).round(2).to_s
                      when "mm"     then raw_mm.round(1).to_s
                      else ui_count_text(data[:count])
                      end
        sel_mm = data[:sel_length].to_f * 25.4
        sv = current_unit == "mm" ? sel_mm.round(1) : (sel_mm/1000.0).round(2)
        display_sel_qty = ui_selected_qty_html(sv)
        opacity_style = ui_selection_opacity(sv)
      else
        display_qty = ui_count_text(data[:count])
        display_sel_qty = ui_selected_qty_html(data[:sel_count])
        opacity_style = ui_selection_opacity(data[:sel_count])
      end
      status_target = (mode == :parent && data[:original_indices].is_a?(Array) && !data[:original_indices].empty?) ? data[:original_indices] : i
      status_btn  = build_status_btn(data, status_target)
      update_info = status_key(data[:trang_thai]) == "UPDATE" ? "<br><span style='font-size:10px;color:#3498db'>&rarr; #{data[:new_name]}</span>" : ""
      diff_name = ui_back_diff_cell(data, :name, back_import_active)
      diff_ten_sp = ui_back_diff_cell(data, :ten_sp, back_import_active)
      diff_note = ui_back_diff_cell(data, :ghi_chu, back_import_active)
      diff_date = ui_back_diff_cell(data, :ngay_dat, back_import_active)
      diff_qty = ui_back_diff_cell(data, :qty, back_import_active)
      diff_unit = ui_back_diff_cell(data, :unit, back_import_active)
      ghost_info = data[:trang_thai] == "GHOST" ? "<span style='color:#8e44ad;font-size:11px'>(Khong con trong model)</span>" : ""
      name_td_class = ui_back_diff_td_class(diff_name)
      ten_sp_td_class = ui_back_diff_td_class(diff_ten_sp)
      note_td_class = ui_back_diff_td_class(diff_note)
      qty_td_class = ui_back_diff_td_class(diff_qty)
      unit_td_class = ui_back_diff_td_class(diff_unit)
      name_note = ui_back_diff_note(diff_name)
      ten_sp_note = ui_back_diff_note(diff_ten_sp)
      note_note = ui_back_diff_note(diff_note)
      qty_note = ui_back_diff_note(diff_qty)
      unit_note = ui_back_diff_note(diff_unit)

      row_bg = data[:trang_thai] == "GHOST" ? "background-color:#2d1b3d;" : ""
      cls   = "data-row#{mode == :parent ? " parent-row" : (mode == :child ? " child-row" : "")}" 
      style = [opacity_style, row_bg, (mode == :child ? "display:none;" : "")].join

      t_rows << "<tr id='row_#{i}' class='#{cls}' data-tree='#{html_escape(base)}' style='#{style}' data-search='#{html_escape(search_text)}' onclick='doSelectRow(#{i})'>"
      unless @group_by == "NAME"
        if mode != :child
          if p_key != current_pkey
            prod_display_code = ui_product_code.call(data[:product])
            prod_safe = prod_display_code.to_s.gsub("'","\\\\'")
            btn = mode == :parent ? "<br><span class='tree-icon' onclick='sketchup.toggle_tree(#{js_arg(base)});event.stopPropagation()' style='font-size:11px;color:#3498db;cursor:pointer'>&#9660;</span>" : ""
            t_rows << "<td rowspan='#{product_rowspan[p_key]}' style='vertical-align:middle;cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{prod_display_code}</b>#{btn}</td>"
            current_pkey = p_key
          end
        else
          prod_display_code = ui_product_code.call(data[:product])
          prod_safe = prod_display_code.to_s.gsub("'","\\\\'")
          t_rows << "<td style='vertical-align:middle;cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{prod_display_code}</b></td>"
        end
      end

      if @group_by == "NAME"
        t_rows << <<~HTML
          <td#{name_td_class} style='white-space:nowrap'>
            <input type="text" class="bulk-edit" data-bulk-table="acc" data-bulk-field="name" data-bulk-index="#{i}" id="rename_#{i}" value="#{data[:name].to_s.gsub('"','&quot;')}" spellcheck="false" onclick="event.stopPropagation();" onchange="if(!handleBulkChange(this)) sketchup.update_name(#{i},this.value);">
            #{update_info}#{ghost_info}#{name_note}
          </td>
          <td style='cursor:pointer' onclick='doSelectRow(#{i})'>#{data[:kich_thuoc].to_s}</td>
          <td#{note_td_class}><input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='ghi_chu' data-bulk-index='#{i}' value='#{data[:ghi_chu].to_s.gsub("'","&apos;").gsub('"','&quot;')}' onchange='if(!handleBulkChange(this)) sketchup.update_ghi_chu(#{i},this.value)' onclick='event.stopPropagation()'>#{note_note}</td>
          <td>#{status_btn}</td>
          <td style='font-size:11px;color:gray'>#{data[:last_modified]}</td>
          <td style='white-space:nowrap'><input type="text" class="bulk-edit" data-bulk-table="acc" data-bulk-field="tag" data-bulk-index="#{i}" id="retag_#{i}" value="#{data[:layer].to_s.gsub('"','&quot;')}" spellcheck="false" onclick="event.stopPropagation();" onchange="if(!handleBulkChange(this)) sketchup.update_tag(#{i},this.value);"></td>
          #{build_ngay_dat_cell(i, data[:ngay_dat].to_s, :acc, diff_date)}
          <td style='cursor:pointer;text-align:center' onclick='doSelectRow(#{i})'>#{display_sel_qty}</td>
          <td#{qty_td_class} style='cursor:pointer' onclick='doSelectRow(#{i})'><b style='color:#e74c3c'>#{display_qty}</b>#{qty_note}</td>
          <td#{unit_td_class}>#{build_unit_select(i, current_unit, all_unit_options)}#{unit_note}</td>
          <td><button class='btn btn-red' style='padding:3px 5px;font-size:11px' onclick='if(confirm("Xoa?")) sketchup.delete_row(#{i});event.stopPropagation()'>&#10006;</button></td>
        </tr>
        HTML
      else
        t_rows << <<~HTML
        <td#{ten_sp_td_class}><input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='ten_sp' data-bulk-index='#{i}' value='#{data[:ten_sp].to_s.gsub("'","&apos;").gsub('"','&quot;')}' onchange='if(!handleBulkChange(this)) sketchup.update_ten_sp(#{i},this.value)' onclick='event.stopPropagation()'>#{ten_sp_note}</td>
        <td#{name_td_class} style='white-space:nowrap'>
          <input type="text" class="bulk-edit" data-bulk-table="acc" data-bulk-field="name" data-bulk-index="#{i}" id="rename_#{i}" value="#{data[:name].to_s.gsub('"','&quot;')}" spellcheck="false" onclick="event.stopPropagation();" onchange="if(!handleBulkChange(this)) sketchup.update_name(#{i},this.value);">
          #{update_info}#{ghost_info}#{name_note}
        </td>
        <td style='cursor:pointer' onclick='doSelectRow(#{i})'>#{data[:kich_thuoc].to_s}</td>
        <td#{note_td_class}><input type='text' class='bulk-edit' data-bulk-table='acc' data-bulk-field='ghi_chu' data-bulk-index='#{i}' value='#{data[:ghi_chu].to_s.gsub("'","&apos;").gsub('"','&quot;')}' onchange='if(!handleBulkChange(this)) sketchup.update_ghi_chu(#{i},this.value)' onclick='event.stopPropagation()'>#{note_note}</td>
        <td>#{status_btn}</td>
        <td style='font-size:11px;color:gray'>#{data[:last_modified]}</td>
        <td style='white-space:nowrap'><input type="text" class="bulk-edit" data-bulk-table="acc" data-bulk-field="tag" data-bulk-index="#{i}" id="retag_#{i}" value="#{data[:layer].to_s.gsub('"','&quot;')}" spellcheck="false" onclick="event.stopPropagation();" onchange="if(!handleBulkChange(this)) sketchup.update_tag(#{i},this.value);"></td>
        #{build_ngay_dat_cell(i, data[:ngay_dat].to_s, :acc, diff_date)}
        <td style='cursor:pointer;text-align:center' onclick='doSelectRow(#{i})'>#{display_sel_qty}</td>
        <td#{qty_td_class} style='cursor:pointer' onclick='doSelectRow(#{i})'><b style='color:#e74c3c'>#{display_qty}</b>#{qty_note}</td>
        <td#{unit_td_class}>#{build_unit_select(i, current_unit, all_unit_options)}#{unit_note}</td>
        <td><button class='btn btn-red' style='padding:3px 5px;font-size:11px' onclick='if(confirm("Xoa?")) sketchup.delete_row(#{i});event.stopPropagation()'>&#10006;</button></td>
      </tr>
      HTML
      end
    end
    end

    # --- Mat rows ---
    m_rows = String.new; current_m_pkey = nil; m_header_rendered = {}
    unless respond_to?(:build_tab_mat_bom_rows)
    display_mat_items_with_tree.each_with_index do |tree_item, vi|
      mode = tree_item[:mode]; base = tree_item[:base]
      if mode == :child_dummy
        m_rows << "<tr class='child-row' data-tree='#{html_escape(base)}' style='display:none;'><td class='tree-span' colspan='13' style='background:#1e272e;border-bottom:1px solid #7f8c8d;'>&nbsp;</td></tr>"; next
      end
      data  = tree_item[:data]; p_key = tree_item[:p_key]
      if !m_header_rendered[base] && mat_child_bases.include?(base)
        prod_safe = base.to_s.gsub("'","\\\\'")
        m_rows << "<tr class='data-row header-row' data-tree='#{html_escape(base)}' style='display:none;background:#34495e;'><td class='tree-span' colspan='13' style='cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{base}</b><br><span class='tree-icon' onclick='sketchup.toggle_tree(#{js_arg(base)});event.stopPropagation()' style='font-size:11px;color:#e74c3c;cursor:pointer'>▲</span></td></tr>"
        m_header_rendered[base] = true
      end
      display_qty = ui_count_text(data[:count])
      display_sel_qty = ui_selected_qty_html(data[:sel_count])
      opacity_style = ui_selection_opacity(data[:sel_count], "opacity:1;").sub("background-color:", "background:")
      mat_update_info = status_key(data[:trang_thai]) == "UPDATE" ? "<br><span style='font-size:10px;color:#3498db'>→ #{html_escape(data[:new_name])}</span>" : ""
      cls   = "data-row#{mode == :parent ? " parent-row" : (mode == :child ? " child-row" : "")}"
      style = [opacity_style, (mode == :child ? "display:none;" : "")].join
      m_rows << "<tr id='mat_row_#{vi}' class='#{cls}' data-tree='#{html_escape(base)}' style='#{style}' data-search='#{data[:product].to_s.downcase} #{data[:name].to_s.downcase}' onclick='doSelectMatRow(#{vi})'>"
      if mode != :child
        if p_key != current_m_pkey
          prod_display_code = ui_product_code.call(data[:product])
          prod_safe = prod_display_code.to_s.gsub("'","\\\\'")
          btn = mode == :parent ? "<br><span class='tree-icon' onclick='sketchup.toggle_tree(#{js_arg(base)});event.stopPropagation()' style='font-size:11px;color:#3498db;cursor:pointer'>▼</span>" : ""
          m_rows << "<td rowspan='#{mat_product_rowspan[p_key]}' style='vertical-align:middle;cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{prod_display_code}</b>#{btn}</td>"
          current_m_pkey = p_key
        end
      else
        prod_display_code = ui_product_code.call(data[:product])
        prod_safe = prod_display_code.to_s.gsub("'","\\\\'")
        m_rows << "<td style='vertical-align:middle;cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{prod_display_code}</b></td>"
      end
      mat_ten_sp = data[:ten_sp].to_s
      if mat_ten_sp.strip.empty? && respond_to?(:import_excel_product_name_for)
        mat_prod_code = data[:actual_product].to_s.strip.empty? ? data[:product].to_s : data[:actual_product].to_s
        mat_ten_sp = import_excel_product_name_for(mat_prod_code, false).to_s
      end
      completion_text = data[:completion_text].to_s.empty? ? "0%" : data[:completion_text].to_s
      completion_color = begin
        st = MH_Thongke.status_key(data[:trang_thai])
        (st == "THIEU" || st == "NO_SPEC") ? "#e74c3c" : "#0b74d1"
      rescue
        "#0b74d1"
      end
      excel_ma_vl = data[:ma_vl_source].to_s.strip
      model_mat_name = data[:name].to_s.strip
      spec_text = data[:spec].to_s.strip
      if !model_mat_name.empty? &&
         model_mat_name != excel_ma_vl &&
         (!respond_to?(:material_code_subgroup?) || material_code_subgroup?(model_mat_name))
        excel_ma_vl = model_mat_name
      end
      spec_text = data[:display_sub].to_s.strip if data.key?(:display_sub) && !data[:display_sub].to_s.strip.empty?
      mat_top_text = excel_ma_vl.empty? ? "---" : excel_ma_vl
      mat_sub_text = spec_text.empty? ? "---" : spec_text
      mat_name_html = "#{html_escape(mat_top_text)}<br><span style='font-size:10px;color:#a1a1aa;line-height:12px'>#{html_escape(mat_sub_text)}</span>"
      m_rows << <<~HTML
        <td style='cursor:pointer' onclick='doSelectMatRow(#{vi})'>#{html_escape(mat_ten_sp)}</td>
        <td style='cursor:pointer' onclick='doSelectMatRow(#{vi})'>#{mat_name_html}#{mat_update_info}</td>
        <td style='cursor:pointer' onclick='doSelectMatRow(#{vi})'>#{data[:thickness]}</td>
        <td style='cursor:pointer' onclick='doSelectMatRow(#{vi})'>#{data[:ghi_chu]}</td>
        <td style='cursor:pointer' onclick='doSelectMatRow(#{vi})'>#{build_mat_status_btn(data, vi)}</td>
        <td style='cursor:pointer;text-align:center' onclick='doSelectMatRow(#{vi})'><b style='color:#{completion_color}'>#{html_escape(completion_text)}</b></td>
        <td style='cursor:pointer' onclick='doSelectMatRow(#{vi})'>#{data[:layer]}</td>
        #{build_ngay_dat_cell(vi, data[:ngay_dat].to_s, :mat)}
        <td style='text-align:center;cursor:pointer' onclick='doSelectMatRow(#{vi})'>#{display_sel_qty}</td>
        <td style='cursor:pointer' onclick='doSelectMatRow(#{vi})'><b style='color:#e74c3c'>#{display_qty}</b></td>
        <td>#{data[:unit]}</td>
        <td></td>
      HTML
      m_rows << "</tr>"
    end
    end
    active_tab = @active_dialog_tab.to_s
    begin
      active_tab = "tab-all" unless main_dialog_valid_tab?(active_tab)
    rescue
      active_tab = "tab-all"
    end
    mat_completion_items = active_tab == "tab-mat" ? material_completion_source_items(display_mat_items) : display_mat_items
    mat_completion_summary_html = active_tab == "tab-mat" ? build_material_completion_summary_html(mat_completion_items) : ""

    # --- Settings rows ---
    set_rows = String.new
    hidden_names = normalize_hidden_names(@hidden_list || []) if respond_to?(:normalize_hidden_names)
    hidden_names ||= (@hidden_list || [])
    hidden_names.map { |n| fix_vietnamese_mojibake(n).to_s.strip }.reject(&:empty?).uniq.sort_by { |n| cached_norm(n) rescue n.downcase }.each do |n|
      safe_n = html_escape(n)
      set_rows << "<tr class='hidden-item-row' data-hidden-name='#{safe_n}'><td style='color:#f59e0b;font-weight:bold'>#{safe_n}</td><td style='width:70px;text-align:center'><button class='btn btn-red' style='padding:3px 8px;font-size:11px' onclick='sketchup.remove_hidden_item(#{js_arg(n)})'>Xóa</button></td></tr>"
    end
    set_rows = "<tr><td colspan='2' style='text-align:center;color:#7f8c8d;padding:12px'>Chưa có PK/VL nào trong danh sách ẩn.</td></tr>" if set_rows.empty?

    gname = @group_by == "NAME" ? "checked" : ""
    gprod = @group_by == "PRODUCT" ? "checked" : ""
    @project_total_view = "COMPACT"
    pt_sort_cut = @project_total_sort.to_s.upcase == "PRODUCT" ? "" : "selected"
    pt_sort_product = @project_total_sort.to_s.upcase == "PRODUCT" ? "selected" : ""

    # --- Rules ---
    load_match_rules if @match_rules.nil?
    @general_rules ||= DEFAULT_GENERAL_RULES.dup
    ignore_rows = String.new
    (@general_rules["ignore_keywords"] || []).each do |kw|
      kw_safe = kw.gsub("'","\\\\'")
      ignore_rows << "<tr><td style='color:#e67e22'>Bỏ qua</td><td>#{kw}</td><td>Tên Excel chứa '#{kw}' → Keep</td><td><button class='btn btn-red' style='padding:2px 6px;font-size:10px' onclick=\"sketchup.remove_ignore_keyword('#{kw_safe}')\">Xóa</button></td></tr>"
    end
    keep_nums_rows = String.new
    (@general_rules["keep_numbers_patterns"] || []).each do |pt|
      pt_safe = pt.gsub("'","\\\\'")
      keep_nums_rows << "<tr><td style='color:#3498db'>Giữ số</td><td>#{pt}</td><td>Tên bắt đầu '#{pt}' → giữ số</td><td><button class='btn btn-red' style='padding:2px 6px;font-size:10px' onclick=\"sketchup.remove_keep_numbers('#{pt_safe}')\">Xóa</button></td></tr>"
    end
    specific_rows = String.new
    (@match_rules || {}).each do |key, val|
      parts = key.split("|",2); ma_sp = parts[0]||""; su_name = parts[1]||""
      act = val["action"] == "keep" ? "<span style='color:#e67e22'>Giữ</span>" : "<span style='color:#3498db'>Update</span>"
      disp = val["action"] == "update" ? "#{val['ex_name']} → #{val['new_name']}" : val["ex_name"].to_s
      key_safe = key.gsub("'","\\\\'")
      specific_rows << "<tr><td>#{ma_sp}</td><td title='#{su_name.gsub("'","\\\\'") }'>#{su_name}</td><td>#{act}</td><td>#{disp}</td><td>#{val['date']}</td><td><button class='btn btn-red' style='padding:2px 6px;font-size:10px' onclick=\"sketchup.delete_rule('#{key_safe}')\">Xóa</button></td></tr>"
    end
    specific_rows = "<tr><td colspan='6' style='text-align:center;color:#7f8c8d;padding:10px'>Chưa có quy tắc riêng</td></tr>" if specific_rows.empty?

    # --- File snapshots ---
    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    normalize_snapshots!
    current_project = current_project_name
    project_data_dir = respond_to?(:current_project_data_dir) ? current_project_data_dir.to_s : ""
    snap_rows = String.new
    sorted_snapshots = snapshots_for_current_project.sort_by { |snap| [snap["label"].to_s, snap["exported_at"].to_s, snap["skp_name"].to_s] }
    current_project_total_rows = sorted_snapshots.inject(0) { |sum, s| sum + (s["items"] || []).size + (s["mat_items"] || []).size }
    sorted_snapshots.each_with_index do |snap, idx|
      sid_safe  = html_escape(snap["id"])
      sid_js    = js_arg(snap["id"])
      path_html = html_escape(snap["skp_path"])
      path_js   = js_arg(snap["skp_path"])
      json_path = respond_to?(:ensure_snapshot_json_path!) ? ensure_snapshot_json_path!(snap) : snap["json_path"].to_s
      json_html = html_escape(json_path)
      name_html = html_escape(snap["skp_name"])
      lbl_safe  = html_escape(snap["label"])
      exists    = File.exist?(snap["skp_path"].to_s)
      path_color = exists ? "#27ae60" : "#e74c3c"
      rename_handler = html_escape("sketchup.rename_snapshot(#{sid_js},this.value)")
      json_handler = html_escape("sketchup.update_snapshot_json_path(#{sid_js},this.value)")
      delete_handler = html_escape("sketchup.delete_snapshot(#{sid_js},#{js_arg(json_path)},#{path_js})")
      open_handler = html_escape("sketchup.open_skp_file(#{path_js})")
      refresh_json_handler = html_escape("var inp=this.parentNode.querySelector('input');sketchup.refresh_snapshot_json(#{sid_js},inp?inp.value:'')")
      snap_rows << "<tr>"
      snap_rows << "<td style='text-align:center;font-weight:bold;color:#e67e22'>#{idx + 1}</td>"
      snap_rows << "<td><input type='text' value='#{lbl_safe}' style='width:120px;font-size:12px;padding:3px' onchange=\"#{rename_handler}\" onclick='event.stopPropagation()'></td>"
      snap_rows << "<td style='font-size:11px;color:#{path_color};max-width:280px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap' title='#{path_html}'>#{name_html}<br><span style='color:#7f8c8d;font-size:10px'>#{path_html}</span></td>"
      snap_rows << "<td style='font-size:11px;min-width:280px'><input type='text' value='#{json_html}' title='#{json_html}' style='width:220px;font-size:11px;padding:3px;color:#ecf0f1;background:#1e1e24;border:1px solid #555d65' onchange=\"#{json_handler}\" onclick='event.stopPropagation()'> <button class='btn btn-blue' style='padding:3px 6px;font-size:10px' onclick=\"#{refresh_json_handler}\">Refresh</button></td>"
      snap_rows << "<td style='font-size:11px;color:#7f8c8d'>#{html_escape(snap["exported_at"])}</td>"
      snap_rows << "<td style='text-align:center'>#{(snap["items"] || []).size + (snap["mat_items"] || []).size}</td>"
      snap_rows << "<td style='white-space:nowrap'>"
      snap_rows << "<button class='btn btn-green' style='padding:3px 7px;font-size:11px;margin:1px' onclick=\"#{open_handler}\">📂 Mở</button> "
      snap_rows << "<button class='btn btn-red' style='padding:3px 7px;font-size:11px;margin:1px' onclick=\"#{delete_handler}\">✕</button>"
      snap_rows << "</td></tr>"
    end
    if snap_rows.empty?
      snap_rows = "<tr><td colspan='7' style='text-align:center;color:#7f8c8d;padding:15px'>Chưa có file nào trong dự án #{html_escape(current_project)}. Nhấn \"Update\" hoặc \"Thêm File\" để bắt đầu.</td></tr>"
    end

    back_import_badge = back_import_active ? "<span style='background:#e74c3c;color:#fff;padding:2px 6px;border-radius:10px;font-size:10px;margin-left:5px'>#{@back_imported_excel.size} dòng Excel</span>" : ""
    acc_header = if @group_by == "NAME"
      <<~HTML
        <th width="24%">Tên hàng</th><th width="7%">KT</th><th width="12%">Ghi chú</th>
        <th width="8%">Trạng thái</th><th width="7%">Cập nhật</th><th width="11%">Tag/Layer</th>
        <th width="9%">Ngày Đặt</th><th width="5%">SL(sel)</th><th width="6%">SL</th>
        <th width="7%">Đơn vị</th><th width="4%"></th>
      HTML
    else
      <<~HTML
        <th width="6%">Mã SP</th><th width="10%">Tên SP</th><th width="14%">Tên hàng</th>
        <th width="6%">KT</th><th width="9%">Ghi chú</th><th width="8%">Trạng thái</th><th width="7%">Cập nhật</th>
        <th width="11%">Tag/Layer</th><th width="8%">Ngày Đặt</th>
        <th width="4%">SL(sel)</th><th width="5%">SL</th><th width="7%">Đơn vị</th><th width="4%"></th>
      HTML
    end

    report_scope = pk_report_view_scope_value
    report_sources = pk_report_cut_sources
    selected_report_source_id = @pk_report_cut_source.to_s
    # Legacy CUT-scope path: only build if build_tab_acc_bom_rows is unavailable.
    # The newer flow uses the global data-source dropdown above the tabs and
    # build_tab_acc_bom_rows for table-acc, so this 1+ second of work is wasted.
    if !respond_to?(:build_tab_acc_bom_rows)
      if report_scope == "CUT"
        allowed_ids = report_sources.map { |src| src[:id].to_s }
        if !allowed_ids.include?(selected_report_source_id) && report_sources.first
          selected_report_source_id = report_sources.first[:id].to_s
        end
        @pk_report_cut_source = selected_report_source_id
        selected_source = report_sources.find { |src| src[:id].to_s == selected_report_source_id }
        cut_items = selected_source ? selected_source[:items] : []
        cut_items = pk_project_items_with_excel_status(cut_items) if respond_to?(:pk_project_items_with_excel_status) && !cut_items.empty?
        report_t_rows = build_pk_report_cut_rows(cut_items)
      else
        project_items = respond_to?(:project_total_source_rows) ? project_total_source_rows(:items) : []
        report_t_rows = build_pk_report_cut_rows(project_items, include_missing: true, unified_source: true)
      end
      report_acc_header = acc_header
    else
      report_t_rows = ""
      report_acc_header = acc_header
    end
    report_scope_project_checked = report_scope == "PROJECT" ? "checked" : ""
    report_scope_cut_checked = report_scope == "CUT" ? "checked" : ""
    report_source_options_html = report_sources.map do |src|
      sid = src[:id].to_s
      sel = sid == selected_report_source_id.to_s ? "selected" : ""
      "<option value='#{html_escape(sid)}' #{sel}>#{html_escape(src[:label])}</option>"
    end.join
    report_source_options_html = "<option value=''>Không có lần cắt</option>" if report_source_options_html.empty?
    report_json_badge = Array(@pk_report_external_sources).empty? ? "" : "<span style='color:#7f8c8d;font-size:11px'>JSON ngoài: #{Array(@pk_report_external_sources).size} nguồn</span>"

    # --- LED rows ---
    psu_rows = @psu_list.sort.reverse.map { |w| "<tr><td>Nguồn LED #{w}W</td><td><b style='color:#e67e22'>#{w}W</b></td><td><button class='btn btn-gray' style='padding:3px 8px;font-size:11px' onclick='removePsu(#{w})'>Xóa</button></td></tr>" }.join
    factor_html = @led_factors.map { |w, name|
      chk = @led_power_factor == w ? 'checked' : ''
      w_str = w == w.to_i ? w.to_i : w
      "<div style='display:flex;align-items:center;gap:5px;background:#1e1e24;padding:5px 10px;border-radius:4px;border:1px solid #454d55;'>
         <input type='radio' name='p_factor' value='#{w}' #{chk} style='cursor:pointer' onchange='sketchup.update_power_factor(#{w})'>
         <input type='text' value='#{name}' onchange='sketchup.rename_power_factor(#{w},this.value)' style='width:90px;border:none;background:transparent;font-weight:bold;color:#dcdcdc;outline:none;border-bottom:1px solid #454d55;padding:2px;'>
         <b style='color:#e67e22'>#{w_str}W</b>
         <span style='color:#e74c3c;font-size:14px;margin-left:3px;cursor:pointer' onclick='sketchup.delete_power_factor(#{w})'>✖</span>
       </div>"
    }.join
    led_stat_items = (@current_report_items || []).select { |row|
      norm = cached_norm(row[:name].to_s) rescue row[:name].to_s.downcase
      norm.include?("led") || norm.include?("cam bien") || norm.include?("cham")
    }.sort_by { |row|
      product_sort_key = begin
        product_code_sort_key(row[:actual_product] || row[:product])
      rescue
        row[:actual_product].to_s
      end
      name_sort_key = begin
        cached_norm(row[:name].to_s)
      rescue
        row[:name].to_s.downcase
      end
      [product_sort_key, name_sort_key]
    }
    led_row_html = lambda do |row|
      unit = (row[:_resolved_unit] || row[:unit]).to_s
      qty = if row[:type] == :length
        raw_mm = row[:length].to_f * 25.4
        case unit
        when "m", "md" then (raw_mm / 1000.0).round(2)
        when "mm" then raw_mm.round(1)
        else row[:count].to_i
        end
      else
        row[:count].to_i
      end
      product_code = ui_product_code.call(row[:actual_product] || row[:product])
      product_name = ui_product_name.call(product_code, row[:ten_sp])
      "<tr><td>#{html_escape(product_code)}</td><td>#{html_escape(product_name)}</td><td>#{html_escape(row[:name])}</td><td style='text-align:right'><b>#{qty}</b></td><td>#{html_escape(unit)}</td></tr>"
    end
    led_stat_rows = led_stat_items.map { |row| led_row_html.call(row) }.join
    led_stat_rows = "<tr><td colspan='5' style='text-align:center;color:#a1a1aa;padding:12px'>Chưa có dữ liệu LED / cảm biến.</td></tr>" if led_stat_rows.empty?
    tab_click_js = lambda do |tab_id|
      safe_id = tab_id.to_s
      "document.querySelectorAll('.content').forEach(function(c){c.style.display='none';});" \
      "document.querySelectorAll('.tab').forEach(function(t){t.classList.remove('active');});" \
      "var c=document.getElementById('#{safe_id}')||document.getElementById('tab-all');" \
      "if(c)c.style.display='block';this.classList.add('active');" \
      "try{sessionStorage.setItem('lastTabMHThongke','#{safe_id}');" \
      "if(window.sketchup&&sketchup.dialog_tab_changed)sketchup.dialog_tab_changed('#{safe_id}');}catch(e){}"
    end
    led_mini_rows = led_stat_items.first(8).map { |row| led_row_html.call(row) }.join
    led_extra = led_stat_items.size > 8 ? "<div style='color:#a1a1aa;font-size:11px;margin-top:6px'>Còn #{led_stat_items.size - 8} dòng nữa trong tab NGUỒN LED.</div>" : ""
    led_mini_panel = if led_stat_items.empty?
      ""
    else
      <<~HTML
        <div style="background:#20242a;border:1px solid #4b5563;border-radius:5px;padding:10px;margin:8px 0 12px 0">
          <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:6px">
            <b style="color:#e67e22">Mini thống kê LED / cảm biến</b>
            <button class="btn btn-blue" style="padding:3px 8px;font-size:11px" onclick="tab('tab-led',document.getElementById('t3'))">Mở tab NGUỒN LED</button>
          </div>
          <table id="led-mini-stat-table">
            <tr><th width="10%">Mã SP</th><th width="24%">Tên SP</th><th width="36%">Tên hàng</th><th width="10%">SL</th><th width="10%">ĐVT</th></tr>
            #{led_mini_rows}
          </table>
          #{led_extra}
        </div>
      HTML
    end
    restore_entries = if respond_to?(:restore_display_entries)
      restore_display_entries
    elsif respond_to?(:load_restore_log)
      load_restore_log
    else
      []
    end
    restore_summary = respond_to?(:restore_log_summary) ? restore_log_summary : { total: restore_entries.size, active: 0, file: "" }
    restore_rows = restore_entries.last(80).reverse.map do |entry|
      meta = entry["metadata"].is_a?(Hash) ? entry["metadata"] : {}
      before = entry["before"].is_a?(Hash) ? entry["before"] : {}
      after = entry["after"].is_a?(Hash) ? entry["after"] : {}
      changed = []
      {
        "mini_accept_rules" => "rules",
        "mini_name_lineage" => "lineage",
        "hidden_excel_items" => "hidden excel",
        "hidden_list" => "setting ẩn",
        "match_rules" => "match rules",
        "general_rules" => "general rules"
      }.each do |key, label|
        changed << label if before[key] != after[key]
      end
      changed << "model attrs" if entry["model_before"].is_a?(Array) && !entry["model_before"].empty?
      changed_text = changed.empty? ? "-" : changed.join(", ")
      status = entry["status"].to_s == "restored" ? "<span style='color:#2ecc71;font-weight:bold'>RESTORED</span>" : "<span style='color:#f1c40f;font-weight:bold'>ACTIVE</span>"
      restore_btn = if entry["status"].to_s == "restored"
        "<button class='btn btn-gray' style='padding:3px 8px;font-size:11px' disabled>Đã khôi phục</button>"
      else
        "<button class='btn btn-blue' style='padding:3px 8px;font-size:11px' onclick='sketchup.restore_action(#{js_arg(entry["id"])})'>Khôi phục</button>"
      end
      item_text = [meta["product"], meta["kind"], meta["name"] || meta["old_name"], meta["target"] || meta["new_name"]].map(&:to_s).reject(&:empty?).join(" | ")
      item_text = "-" if item_text.empty?

      # Before: luôn là tên model entity (chữ to = old_name)
      before_name = meta["old_name"].to_s

      # After: tùy theo hành động
      action_type = entry["action"].to_s
      after_name = case action_type
      when "mini_keep"
        # Giữ tên → After giống Before
        meta["old_name"].to_s
      when "mini_update", "mini_rename"
        # Update/Rename → After là tên mới (chữ bé = Excel target)
        n = meta["name"].to_s
        n = meta["target"].to_s if n.empty?
        n
      when "mini_accept"
        meta["name"].to_s
      else
        n = meta["name"].to_s
        n = meta["target"].to_s if n.empty?
        n = meta["new_name"].to_s if n.empty?
        n
      end

      before_cell = before_name.empty? ? "-" : html_escape(before_name)
      after_cell = after_name.to_s.empty? ? "-" : html_escape(after_name)
      # Highlight nếu before != after
      name_changed = !before_name.empty? && !after_name.to_s.empty? && before_name != after_name
      before_style = name_changed ? "color:#e74c3c" : ""
      after_style = name_changed ? "color:#2ecc71" : ""

      "<tr><td>#{html_escape(entry["time"])}</td><td><b style='color:#e67e22'>#{html_escape(entry["label"] || entry["action"])}</b><br><span style='font-size:10px;color:#9ca3af'>#{html_escape(changed_text)}</span></td><td>#{html_escape(item_text)}</td><td style='#{before_style}' title='#{before_cell}'>#{before_cell}</td><td style='#{after_style}' title='#{after_cell}'>#{after_cell}</td><td style='text-align:center'>#{status}</td><td style='text-align:center'>#{restore_btn}</td></tr>"
    end.join
    restore_rows = "<tr><td colspan='7' style='text-align:center;color:#7f8c8d;padding:15px'>Chưa có restore log. Từ các thay đổi tiếp theo app sẽ ghi vào đây.</td></tr>" if restore_rows.empty?
    fill_sp_defaults! if respond_to?(:fill_sp_defaults!)
    fill_sp_input_path = respond_to?(:html_escape) ? html_escape(@fill_sp_input_path.to_s) : @fill_sp_input_path.to_s
    fill_sp_output_path = respond_to?(:html_escape) ? html_escape(@fill_sp_output_path.to_s) : @fill_sp_output_path.to_s
    fill_sp_library_path = respond_to?(:html_escape) ? html_escape(@fill_sp_library_path.to_s) : @fill_sp_library_path.to_s
    fill_sp_status_label = respond_to?(:fill_sp_status_text) ? html_escape(fill_sp_status_text()) : "Sẵn sàng."
    fill_sp_status_color = @fill_sp_status.to_s.downcase.include?("lỗi") ? "#e74c3c" : "#7f8c8d"
    fill_sp_include_checked = respond_to?(:fill_sp_include_son_code?) && fill_sp_include_son_code? ? "checked" : ""

    css_path = File.join(MH_Thongke::UI_DIR, "shared_style.css")
shared_css = File.exist?(css_path) ? File.read(css_path) : ""
js_path = File.join(MH_Thongke::UI_DIR, "js", "main_scripts.js")
shared_js = File.exist?(js_path) ? File.read(js_path) : ""
lazy_body = "<tr><td colspan='5' style='text-align:center;color:#7f8c8d;padding:14px'>Bấm tab để tải dữ liệu.</td></tr>"
acc_body_html = active_tab == "tab-acc" ? (respond_to?(:build_tab_acc_bom_rows) ? build_tab_acc_bom_rows : report_t_rows) : lazy_body
mat_body_html = active_tab == "tab-mat" ? (respond_to?(:build_tab_mat_bom_rows) ? build_tab_mat_bom_rows : m_rows) : lazy_body
all_body_html = active_tab == "tab-all" ? (respond_to?(:build_tab_all_bom_rows) ? build_tab_all_bom_rows : build_all_rows(display_items_with_tree, display_mat_items_with_tree)) : lazy_body
html = <<~HTML
  <html><head><meta charset="UTF-8"><style>
    #{shared_css}
      #{respond_to?(:mini_import_inline_css) ? mini_import_inline_css : ""}
      </style></head><body>
        <script>window.MHRubyTab=#{js_arg(@active_dialog_tab.to_s)};
#{shared_js}
#{respond_to?(:mini_import_inline_js) ? mini_import_inline_js : ""}
        </script>
        <div class="tabs">
          <div class="tab active" id="t7" data-tab="tab-all" onclick="#{tab_click_js.call('tab-all')}">TỔNG HỢP</div>
          <div class="tab" id="t9" data-tab="tab-project-total" onclick="#{tab_click_js.call('tab-project-total')}">TỔNG DỰ ÁN</div>
          <div class="tab" id="t1" data-tab="tab-acc" onclick="#{tab_click_js.call('tab-acc')}">PHỤ KIỆN</div>
          <div class="tab" id="t6" data-tab="tab-mat" onclick="#{tab_click_js.call('tab-mat')}">VẬT LIỆU</div>
          <div class="tab" id="t2" data-tab="tab-settings" onclick="#{tab_click_js.call('tab-settings')}">SETTING</div>
          <div class="tab" id="t3" data-tab="tab-led" onclick="#{tab_click_js.call('tab-led')}">NGUỒN LED</div>
          <div class="tab" id="t5" data-tab="tab-rules" onclick="#{tab_click_js.call('tab-rules')}">QUY TẮC</div>
          <div class="tab" id="t11" data-tab="tab-restore" onclick="#{tab_click_js.call('tab-restore')}">RESTORE</div>
          <div class="tab" id="t8" data-tab="tab-files" onclick="#{tab_click_js.call('tab-files')}">📁 FILE</div>
        </div>
        <!-- ====== TAB PHỤ KIỆN ====== -->
        <div id="tab-acc" class="content">
          <div class="group-filter" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:5px;">
            <div>
              <b style="color:#27ae60">Gom theo: </b>
              <label><input type="radio" name="g_mode" value="NAME" #{gname} onchange="sketchup.change_group(this.value)"> Tên hàng</label>
              <label><input type="radio" name="g_mode" value="PRODUCT" #{gprod} onchange="sketchup.change_group(this.value)"> Mã SP</label>
              &nbsp;&nbsp;
              <b style="color:#8e44ad">Hiển thị: </b>
              <label><input type="radio" name="d_mode" value="ALL" #{@display_mode=='ALL'?'checked':''} onchange="sketchup.change_display(this.value)"> Tất cả</label>
              <label><input type="radio" name="d_mode" value="SELECTED" #{@display_mode=='SELECTED'?'checked':''} onchange="sketchup.change_display(this.value)"> Đang chọn</label>
            </div>
            <div style="display:flex;gap:5px;flex-wrap:wrap">
              <input type="text" id="searchInput" placeholder="🔍 Tìm Mã SP, Tên hàng..." style="padding:5px;width:200px;border-radius:4px;" onkeyup="filterTable()">
              <button class="btn btn-green" onclick="sketchup.export_excel()" style="padding:4px 8px;font-size:11px">📥 Xuất Excel</button>
              <button class="btn btn-orange" onclick="sketchup.import_back_excel()" style="padding:4px 8px;font-size:11px">📤 Import ngược Excel#{back_import_badge}</button>
              #{back_import_active ? "<button class='btn btn-green' onclick='applyBackImportUpdate(\"all\")' style='padding:4px 8px;font-size:11px'>Cập nhật tất cả</button><button class='btn btn-green' onclick='applyBackImportUpdate(\"selected\")' style='padding:4px 8px;font-size:11px'>Cập nhật dòng chọn</button>" : ""}
              #{back_import_active ? "<button class='btn btn-gray' onclick='sketchup.clear_back_import()' style='padding:4px 8px;font-size:11px'>✕ Xóa so sánh</button>" : ""}
              <button class="btn btn-blue" onclick="if(confirm('Accept all?')) sketchup.action_accept_all()" style="padding:4px 8px;font-size:11px">✔ Accept All</button>
              <button class="btn btn-gray" onclick="deleteBulkCells()" style="padding:4px 8px;font-size:11px">Xóa ô chọn</button>
              <button class="btn btn-blue" onclick="sketchup.refresh_data()" style="padding:4px 8px;font-size:11px">🔄 Làm Mới</button>
              <button class="btn btn-blue" onclick="sketchup.export_history()" style="padding:4px 8px;font-size:11px">📜 Lịch Sử</button>
            </div>
          </div>
          <div style="overflow-x:auto">
          <table id="table-acc">
            <thead><tr>
              <th>Tên hàng</th>
              <th width="60">Ghi chú</th>
              <th width="60" style="text-align:center">Trạng thái</th>
              <th width="50" style="text-align:center">SL</th>
              <th width="25" style="text-align:center"></th>
            </tr></thead>
            <tbody id="table-acc-body">#{acc_body_html}</tbody>
          </table>
          </div>
        </div>

        <!-- ====== TAB VẬT LIỆU ====== -->
        <div id="tab-mat" class="content">
          <div class="group-filter" style="display:flex;justify-content:space-between;align-items:center;gap:6px;flex-wrap:wrap">
            <span style="color:#7f8c8d;font-size:11px">*Vật liệu từ các đối tượng không phải phụ kiện</span>
            <div style="display:flex;gap:5px;flex-wrap:wrap">
              <button class="btn btn-green" onclick="sketchup.export_material_excel()" style="padding:4px 8px;font-size:11px">📥 Xuất Excel VL</button>
              <button class="btn btn-blue" onclick="sketchup.refresh_data()" style="padding:4px 8px;font-size:11px">🔄 Làm Mới</button>
            </div>
          </div>
          <div id="mat-completion-summary">#{mat_completion_summary_html}</div>
          <div style="overflow-x:auto">
          <table id="table-mat">
            <thead><tr>
              <th>Tên hàng</th>
              <th width="60">Ghi chú</th>
              <th width="60" style="text-align:center">Trạng thái</th>
              <th width="50" style="text-align:center">SL</th>
              <th width="25" style="text-align:center"></th>
            </tr></thead>
            <tbody id="table-mat-body">#{mat_body_html}</tbody>
          </table>
          </div>
        </div>

        <!-- ====== TAB TỔNG HỢP ====== -->
        <div id="tab-all" class="content" style="display:block">
          <div class="group-filter" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:6px">
            <span><b style="color:#27ae60">TỔNG HỢP</b> <span id="summary-all-counts" style="color:#7f8c8d;font-size:11px">📦 PK: #{@current_report_items.size} | 🧱 VL: #{@current_mat_items.size}</span></span>
            <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
              <button class="btn btn-green" onclick="sketchup.export_excel()" style="padding:4px 8px;font-size:11px">📥 Xuất Excel</button>
              <button class="btn btn-blue" onclick="sketchup.refresh_data()" style="padding:4px 8px;font-size:11px">🔄 Làm Mới</button>
            </div>
          </div>
          #{led_mini_panel}
          <div style="overflow-x:auto">
          <table id="table-all">
            <thead><tr>
              <th>Tên hàng</th>
              <th width="60">Ghi chú</th>
              <th width="60" style="text-align:center">Trạng thái</th>
              <th width="50" style="text-align:center">SL</th>
              <th width="25" style="text-align:center"></th>
            </tr></thead>
            <tbody id="table-all-body">#{all_body_html}</tbody>
          </table>
          </div>
        </div>

        <!-- ====== TAB TỔNG DỰ ÁN ====== -->
        <div id="tab-project-total" class="content">
          <div class="group-filter" style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap">
            <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap">
              <span><b style="color:#27ae60">TỔNG DỰ ÁN</b> <span id="summary-project-counts" style="color:#7f8c8d;font-size:11px">#{html_escape(current_project)}</span></span>
              <span style="font-size:12px;color:#95a5a6">Chế độ: Thu gọn</span>
            </div>
            <div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap">
              <select style="padding:5px;border-radius:4px" onchange="sketchup.change_project_total_sort(this.value)">
                <option value="CUT" #{pt_sort_cut}>Sort: Lần cắt</option>
                <option value="PRODUCT" #{pt_sort_product}>Sort: Mã SP</option>
              </select>
              <input type="text" id="projectSearchInput" placeholder="Tìm nhiều từ khóa, cách nhau bằng dấu ," style="padding:5px;width:320px;border-radius:4px;" onkeyup="filterProjectTotal()">
              <button class="btn btn-green" onclick="sketchup.export_project_report()" style="padding:5px 10px;font-size:12px">Xuất báo cáo</button>
            </div>
          </div>
          <div style="overflow-x:auto">
          <table id="table-project-total" data-compact="1">
            <tr>
              <th width="12%">Dự án</th><th width="9%">Lần cắt</th><th width="16%">File</th>
              <th width="8%">Mã SP</th><th width="14%">Tên SP</th><th width="9%">Ngày bắt đầu CNC</th>
              <th width="9%">Ngày kết thúc CNC</th><th width="8%">TT file CNC</th><th width="9%">Ngày đặt ĐMVT</th>
              <th width="8%">TT DMVT</th><th width="8%">Cập nhật</th>
            </tr>
            #{build_project_total_rows(@project_total_view, @project_total_sort)}
          </table>
          </div>
        </div>

        <!-- ====== TAB ẨN/HIỆN ====== -->
        <div id="tab-settings" class="content">
          <div class="settings-box">
            <h4 style="color:#e67e22;margin-top:0">Danh sách ẩn PK/VL</h4>
            <div style="color:#bdc3c7;font-size:12px;margin-bottom:8px">
              Nhập tên phụ kiện/vật liệu không cần hiển thị. App sẽ lưu vào JSON và lọc ở bảng chính, Mini Import, HUD.
            </div>
            <div style="display:flex;gap:6px;margin-bottom:10px;align-items:flex-start">
              <textarea id="hiddenInput" rows="3" placeholder="Ví dụ:&#10;CAM 17.5&#10;CAM U 17.6" style="flex:1;background:#1e1e24;color:#fff;border:1px solid #555d65;border-radius:4px;padding:6px;font-size:12px"></textarea>
              <button class="btn btn-green" style="padding:6px 12px;font-size:12px" onclick="var el=document.getElementById('hiddenInput');var v=el?(el.value||''):'';if(!v.trim()){alert('Nhập tên PK/VL cần ẩn.');}else{sketchup.add_hidden_items(v);}">Thêm</button>
            </div>
            <table><tr><th>Tên đang ẩn</th><th width="70">Xóa</th></tr>#{set_rows}</table>
          </div>
        </div>

        <!-- ====== TAB QUY TẮC ====== -->
        <div id="tab-rules" class="content">
          <div class="settings-box">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px">
              <h4 style="color:#e67e22;margin:0">📋 Bảng Quy Tắc (#{(@match_rules||{}).size} rules)</h4>
              <div>
                <button class="btn btn-blue" onclick="sketchup.open_match_rules_excel()" style="padding:4px 10px;font-size:11px;margin-right:5px" title="Mở file Excel chứa rules để chỉnh sửa bằng tay">📒 Match Rules Excel</button>
                <button class="btn btn-blue" onclick="sketchup.reload_match_rules_excel()" style="padding:4px 10px;font-size:11px;margin-right:5px" title="Nạp lại rules từ file Excel sau khi chỉnh sửa">🔄 Reload Excel</button>
                <button class="btn btn-green" onclick="sketchup.open_rules_excel()" style="padding:4px 10px;font-size:11px;margin-right:5px">Quy tắc legacy</button>
                <button class="btn btn-red" onclick="if(confirm('Xóa tất cả quy tắc?')) sketchup.clear_all_rules()" style="padding:4px 10px;font-size:11px">🗑 Xóa Tất Cả</button>
              </div>
            </div>
            <h5 style="color:#27ae60;margin:15px 0 5px 0">1. Quy tắc chung</h5>
            <div style="display:flex;margin-bottom:5px">
              <input type="text" id="new_ignore" placeholder="Từ khóa bỏ qua..." style="width:140px;margin-right:5px;font-size:11px;padding:4px">
              <button class="btn btn-blue" onclick="sketchup.add_ignore_keyword(document.getElementById('new_ignore').value)" style="padding:4px 8px;font-size:11px;margin-right:15px">Thêm</button>
              <input type="text" id="new_keep" placeholder="Mẫu giữ số..." style="width:140px;margin-right:5px;font-size:11px;padding:4px">
              <button class="btn btn-blue" onclick="sketchup.add_keep_numbers(document.getElementById('new_keep').value)" style="padding:4px 8px;font-size:11px">Thêm</button>
            </div>
            <table><tr><th width="15%">Loại</th><th width="20%">Từ khóa</th><th width="55%">Mô tả</th><th width="10%"></th></tr>#{ignore_rows}#{keep_nums_rows}</table>
            <h5 style="color:#2980b9;margin:15px 0 5px 0">2. Quy tắc riêng</h5>
            <table><tr><th width="8%">Mã SP</th><th width="23%">Tên SketchUp</th><th width="8%">Hành động</th><th width="46%">Tên Excel</th><th width="10%">Ngày</th><th width="5%"></th></tr>#{specific_rows}</table>
          </div>
        </div>

        <!-- ====== TAB NGUỒN LED ====== -->
        <div id="tab-led" class="content">
          <h3 style="color:#2c3e50;margin-top:0">⚡ TÍNH NGUỒN CẤP LED</h3>
          <div style="background:#222529;padding:15px;border-radius:4px;border:1px solid #3a3f44;margin-bottom:15px">
            <h4 style="color:#27ae60;margin-top:0">1. Danh sách nguồn LED sẵn có</h4>
            <table id="psu-table"><tr><th style="width:60%">Loại nguồn</th><th style="width:25%">Công suất</th><th style="width:15%"></th></tr>#{psu_rows}</table>
            <div style="display:flex;gap:8px;margin-top:12px;align-items:center">
              <input type="number" id="new_psu_w" placeholder="Nhập công suất (W)" min="1" step="10" style="padding:7px;width:170px">
              <button class="btn btn-green" onclick="addPsu()">➕ Thêm nguồn</button>
            </div>
          </div>
          <div style="background:#222529;padding:15px;border-radius:4px;border:1px solid #3a3f44;margin-bottom:15px">
            <h4 style="color:#2980b9;margin-top:0">2. Công suất / 1000mm</h4>
            <div style="display:flex;gap:15px;align-items:center;flex-wrap:wrap;margin:10px 0 15px 0">#{factor_html}</div>
            <div style="display:flex;gap:8px;align-items:center">
              <input type="text" id="new_factor_name" placeholder="Tên loại LED" style="padding:7px;width:110px">
              <input type="number" id="new_factor_w" placeholder="Định mức (W)" min="1" step="1" style="padding:7px;width:90px">
              <button class="btn btn-blue" onclick="addFactor()">➕ Thêm định mức</button>
            </div>
          </div>
          <div style="background:#222529;padding:15px;border-radius:4px;border:1px solid #3a3f44;margin-bottom:15px">
            <h4 style="color:#e67e22;margin-top:0">3. Thống kê LED / cảm biến hiện tại</h4>
            <table id="led-stat-table">
              <tr><th width="10%">Mã SP</th><th width="24%">Tên SP</th><th width="36%">Tên hàng</th><th width="10%">SL</th><th width="10%">ĐVT</th></tr>
              #{led_stat_rows}
            </table>
          </div>
        </div>

        <!-- ====== TAB FILE QUẢN LÝ ====== -->
        <div id="tab-files" class="content">
          <div style="background:#222529;border:1px solid #3a3f44;border-radius:4px;padding:10px;margin-bottom:10px">
            <div class="group-filter" style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
              <b style="color:#27ae60;min-width:90px">Import Excel</b>
              <input id="import_Excel" type="text" value="#{html_escape(@import_excel_path)}" placeholder="Dan duong dan file .xlsx" style="flex:1;min-width:360px" onchange="sketchup.set_import_excel_path(this.value)">
              <button class="btn btn-blue" onclick="sketchup.import_excel()" style="padding:5px 10px;font-size:12px">Chon file</button>
              <button class="btn btn-blue" onclick="this.disabled=true;this.textContent='Dang nap...';var st=document.getElementById('import_excel_status_text');if(st)st.textContent='Dang nap Excel va tao JSON...';sketchup.refresh_import_excel()" style="padding:5px 10px;font-size:12px">Refresh Excel</button>
              <button class="btn btn-green" onclick="sketchup.open_import_mini()" style="padding:5px 10px;font-size:12px">Mini Import</button>
              <button class="btn btn-orange" onclick="sketchup.open_material_hud()" style="padding:5px 10px;font-size:12px">Material HUD</button>
              <button class="btn btn-blue" onclick="sketchup.open_info_hud()" style="padding:5px 10px;font-size:12px">Info HUD</button>
              <span id="import_excel_status_text" style="color:#{@import_excel_error.to_s.empty? ? '#7f8c8d' : '#e74c3c'};font-size:11px;margin-left:4px">
                #{if @excel_loading
                    "Dang nap Excel va tao JSON..."
                  elsif !@import_excel_error.to_s.empty?
                    "Loi Excel: #{html_escape(@import_excel_error)}"
                  elsif !@import_excel_status_message.to_s.empty?
                    html_escape(@import_excel_status_message)
                  else
                    (@imported_excel_data && !@imported_excel_data.empty?) ? html_escape(import_excel_status_text("Da nap du lieu")) : "Chua nap Excel"
                  end}
              </span>
            </div>
            <div style="margin-top:10px;padding-top:10px;border-top:1px dashed #3f4752">
              <div class="group-filter" style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
                <b style="color:#27ae60;min-width:90px">Fill SP Input</b>
                <input id="fill_sp_input" type="text" value="#{fill_sp_input_path}" placeholder="Đường dẫn file input .xlsx" style="flex:1;min-width:360px" onchange="sketchup.fill_sp_set_input_path(this.value)">
                <button class="btn btn-blue" onclick="sketchup.fill_sp_pick_input()" style="padding:5px 10px;font-size:12px">Chọn input</button>
              </div>
              <div class="group-filter" style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-top:6px">
                <b style="color:#27ae60;min-width:90px">Fill SP Output</b>
                <input id="fill_sp_output" type="text" value="#{fill_sp_output_path}" placeholder="Đường dẫn file output .xlsx" style="flex:1;min-width:360px" onchange="sketchup.fill_sp_set_output_path(this.value)">
                <button class="btn btn-blue" onclick="sketchup.fill_sp_pick_output()" style="padding:5px 10px;font-size:12px">Chọn output</button>
                <button class="btn btn-green" onclick="sketchup.fill_sp_open_output()" style="padding:5px 10px;font-size:12px">Mở output</button>
              </div>
              <div class="group-filter" style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-top:6px">
                <b style="color:#27ae60;min-width:90px">Library</b>
                <input id="fill_sp_library" type="text" value="#{fill_sp_library_path}" placeholder="Đường dẫn library.xlsx" style="flex:1;min-width:360px" onchange="sketchup.fill_sp_set_library_path(this.value)">
                <button class="btn btn-blue" onclick="sketchup.fill_sp_pick_library()" style="padding:5px 10px;font-size:12px">Chọn library</button>
                <label style="font-size:11px;color:#bdc3c7;display:flex;align-items:center;gap:5px">
                  <input id="fill_sp_include_son" type="checkbox" #{fill_sp_include_checked} onchange="sketchup.fill_sp_set_include_son(this.checked)">
                  Xuất mã sơn
                </label>
                <button class="btn btn-orange" onclick="sketchup.fill_sp_run_generate()" style="padding:5px 10px;font-size:12px">Xuất file</button>
              </div>
              <div id="fill_sp_status_text" style="margin-top:6px;font-size:11px;color:#{fill_sp_status_color}">#{fill_sp_status_label}</div>
            </div>
          </div>
          <div class="group-filter" style="display:flex;justify-content:space-between;align-items:center">
            <div>
              <b style="color:#27ae60">Quản lý File SKP</b> <span style="color:#f1c40f;font-size:11px;margin-left:8px">#{html_escape(current_project)}</span>
              <span style="color:#95a5a6;font-size:11px;margin-left:8px">#{sorted_snapshots.size} file · #{current_project_total_rows} dòng</span>
              <span style="color:#7f8c8d;font-size:11px;margin-left:8px">Dữ liệu lần cắt: #{html_escape(project_data_dir.empty? ? "Chưa lưu SKP" : project_data_dir)}</span>
            </div>
            <div style="display:flex;gap:5px">
              <button class="btn btn-green" onclick="this.disabled=true;this.textContent='Đang update...';var st=document.getElementById('snapshot_status_text');if(st)st.textContent='Đang update file hiện tại...';sketchup.snapshot_current()" style="padding:5px 10px;font-size:12px">💾 Update (File hiện tại)</button>
              <button class="btn btn-blue" onclick="sketchup.add_file_manual()" style="padding:5px 10px;font-size:12px">➕ Thêm File</button>
            </div>
          </div>
          <div id="snapshot_status_text" style="margin-top:6px;font-size:11px;color:#95a5a6">#{html_escape(@snapshot_current_last_status.to_s)}</div>
          <div style="margin-top:8px;background:#222529;padding:10px;border-radius:4px;font-size:11px;color:#7f8c8d">
            <b>Hướng dẫn:</b> Mỗi file SKP là một lần cắt. Có thể sửa đường dẫn File JSON, rồi bấm Refresh để đọc lại JSON mới nhất vào bảng.
            Nhấn "Update" để ghi dữ liệu hiện tại ra JSON.
          </div>
          <table id="import_json" style="margin-top:10px">
            <tr>
              <th width="4%" style="text-align:center">STT</th>
              <th width="12%">Nhãn</th>
              <th width="30%">File SKP</th>
              <th width="24%">File JSON</th>
              <th width="15%">Xuất lúc</th>
              <th width="8%" style="text-align:center">Số dòng</th>
              <th width="7%">Thao tác</th>
            </tr>
            #{snap_rows}
          </table>
        </div>

        <!-- ====== TAB RESTORE ====== -->
        <div id="tab-restore" class="content">
          <div class="group-filter" style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap">
            <div>
              <b style="color:#27ae60">Restore thay đổi</b>
              <span style="color:#f1c40f;font-size:11px;margin-left:8px">#{restore_summary[:active]} active / #{restore_summary[:total]} log</span>
              <span style="color:#7f8c8d;font-size:11px;margin-left:8px">#{html_escape(restore_summary[:file])}</span>
            </div>
            <div style="display:flex;gap:5px">
              <button class="btn btn-blue" onclick="sketchup.refresh_data()" style="padding:5px 10px;font-size:12px">Làm mới</button>
              <button class="btn btn-red" onclick="if(confirm('Xóa toàn bộ restore log?'))sketchup.clear_restore_log()" style="padding:5px 10px;font-size:12px">Xóa log</button>
            </div>
          </div>
          <div style="margin-top:8px;background:#222529;padding:10px;border-radius:4px;font-size:11px;color:#bdc3c7">
            Tab này khôi phục các thay đổi hệ thống đã ghi log: rule accept/update/keep, lineage tên, danh sách ẩn Excel, danh sách ẩn trong Setting và attribute trong model như tên, tên SP, ghi chú, ngày đặt. Geometry đã bị xóa thật trước khi có restore log thì không thể dựng lại từ JSON.
          </div>
          <table style="margin-top:10px">
            <tr>
              <th width="11%">Thời gian</th>
              <th width="18%">Thao tác</th>
              <th width="15%">Đối tượng</th>
              <th width="18%">Before</th>
              <th width="18%">After</th>
              <th width="9%" style="text-align:center">Trạng thái</th>
              <th width="11%" style="text-align:center">Restore</th>
            </tr>
            #{restore_rows}
          </table>
        </div>

        <script>#{shared_js}</script>
      </body></html>
    HTML
    html_hash = html.hash
    return if @last_main_html_hash == html_hash
    
    if !force_full && @last_main_html_hash && @dlg && @dlg.visible?
      # Incremental update: mini-style bodies for acc/mat/all; project-total keeps its own legacy table
      acc_body = active_tab == "tab-acc" ? (respond_to?(:build_tab_acc_bom_rows) ? build_tab_acc_bom_rows : report_t_rows) : nil
      mat_body = active_tab == "tab-mat" ? (respond_to?(:build_tab_mat_bom_rows) ? build_tab_mat_bom_rows : m_rows) : nil
      mat_completion_summary = active_tab == "tab-mat" ? build_material_completion_summary_html(material_completion_source_items(display_mat_items)) : nil
      all_body = active_tab == "tab-all" ? (respond_to?(:build_tab_all_bom_rows) ? build_tab_all_bom_rows : build_all_rows(display_items_with_tree, display_mat_items_with_tree)) : nil
      project_table = "<tr>\n              <th width=\"12%\">Dự án</th><th width=\"9%\">Lần cắt</th><th width=\"16%\">File</th>\n              <th width=\"8%\">Mã SP</th><th width=\"14%\">Tên SP</th><th width=\"9%\">Ngày bắt đầu CNC</th>\n              <th width=\"9%\">Ngày kết thúc CNC</th><th width=\"8%\">TT file CNC</th><th width=\"9%\">Ngày đặt ĐMVT</th>\n              <th width=\"8%\">TT DMVT</th><th width=\"8%\">Cập nhật</th>\n            </tr>\n            #{build_project_total_rows(@project_total_view, @project_total_sort)}"
      payload = {
        acc_body: acc_body,
        mat_body: mat_body,
        mat_completion_summary: mat_completion_summary,
        all_body: all_body,
        project_table: project_table,
        summary_all: "📦 PK: #{@current_report_items.size} | 🧱 VL: #{@current_mat_items.size}",
        summary_project: html_escape(current_project)
      }
      script = <<~JS
        try {
          var p = #{payload.to_json};
          var bAcc = document.getElementById('table-acc-body'); if (bAcc && p.acc_body !== null) bAcc.innerHTML = p.acc_body;
          var bMat = document.getElementById('table-mat-body'); if (bMat && p.mat_body !== null) bMat.innerHTML = p.mat_body;
          var sMat = document.getElementById('mat-completion-summary'); if (sMat && p.mat_completion_summary !== null) sMat.innerHTML = p.mat_completion_summary;
          var bAll = document.getElementById('table-all-body'); if (bAll && p.all_body !== null) bAll.innerHTML = p.all_body;
          var tProj = document.getElementById('table-project-total'); if (tProj) tProj.innerHTML = p.project_table;

          var sAll = document.getElementById('summary-all-counts'); if (sAll) sAll.innerHTML = p.summary_all;
          var sProj = document.getElementById('summary-project-counts'); if (sProj) sProj.innerHTML = p.summary_project;
        } catch(e) { console.error(e); }
      JS
      ui_execute_main_dialog_script(script)
      @last_main_html_hash = html_hash
      return
    end

    @last_main_html_hash = html_hash
    @dlg.set_html(html)
  rescue => e
    main_ui_debug("update_html ERROR #{e.class}: #{e.message} | #{e.backtrace.first(5).join(' | ')}") if respond_to?(:main_ui_debug)
    puts "MH_Thongke update_html error: #{e.class}: #{e.message}"
    puts e.backtrace.first(20).join("\n") if e.backtrace
    if @dlg
      msg = "#{e.class}: #{e.message}".to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      @dlg.set_html("<html><body style='font-family:Segoe UI,sans-serif;background:#2b2d31;color:#eee;padding:16px'><h3>MH Thongke khong render duoc bang chinh</h3><pre style='white-space:pre-wrap;color:#ffb4b4'>#{msg}</pre></body></html>")
    end
  end

  # -------------------------------------------------------
  # HELPER: Build Ngày Đặt cell
  # -------------------------------------------------------
  def self.build_ngay_dat_cell(idx, val, table = :acc, diff_cell = nil)
    cb = table == :mat ? "update_mat_ngay_dat" : "update_ngay_dat"
    today_cb = table == :mat ? "set_mat_ngay_dat_today" : "set_ngay_dat_today"
    val = normalize_order_date(val)
    date_ready_js = "var v=(this.value||'').toString().trim();if(!(!v||/^\\d{1,2}[\\/\\-.]\\d{2}$/.test(v)||/^\\d{1,2}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{2,4}$/.test(v)||/^\\d{4}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{1,2}$/.test(v)||/^\\d{4}$/.test(v)||/^\\d{6}$/.test(v)||/^\\d{8}$/.test(v)))return;"
    direct_commit_js = "#{date_ready_js}if(window.sketchup&&sketchup.#{cb}){clearTimeout(this._mhDirectDateTimer);var el=this;this._mhDirectDateTimer=setTimeout(function(){sketchup.#{cb}(#{idx},el.value)},300)}"
    direct_commit_now_js = "if(window.sketchup&&sketchup.#{cb}){sketchup.#{cb}(#{idx},this.value)}"
    confirm_commit_js = "var inp=this.parentNode.querySelector('input.date-edit');if(inp&&window.sketchup&&sketchup.#{cb}){sketchup.#{cb}(#{idx},inp.value)}event.stopPropagation()"
    diff_class = diff_cell ? " class='cell-diff'" : ""
    diff_note = diff_cell ? "<span class='excel-diff-note'>Excel: #{html_escape(diff_cell[:excel].to_s.empty? ? '-' : diff_cell[:excel].to_s)}</span>" : ""
    <<~HTML
      <td#{diff_class} style='white-space:nowrap'>
        <input type='text' class='bulk-edit date-edit' data-bulk-table='#{table}' data-bulk-field='ngay_dat' data-bulk-index='#{idx}' id='ngaydat_#{table}_#{idx}' value='#{val.gsub("'","&apos;").gsub('"','&quot;')}' placeholder='DD/MM/YYYY' style='width:75px;font-size:11px' oninput='window.MHDateCommit&&MHDateCommit(this,true);#{direct_commit_js}' onkeyup='window.MHDateCommit&&MHDateCommit(this,true);#{direct_commit_js}' onchange='window.MHDateCommit&&MHDateCommit(this,false);#{direct_commit_now_js}' onblur='window.MHDateCommit&&MHDateCommit(this,false);#{direct_commit_now_js}' onkeydown='if(event.keyCode===13){event.preventDefault();window.MHDateCommit&&MHDateCommit(this,false);#{direct_commit_now_js}}' onclick='event.stopPropagation()'>
        <button class='ngay-dat-btn' onclick="#{confirm_commit_js}" title='Xac nhan ngay'>&#10003;</button>
        <button class='ngay-dat-btn' onclick='sketchup.#{today_cb}(#{idx});event.stopPropagation()' title='Dat hom nay'>&#128197;</button>
        #{diff_note}
      </td>
    HTML
  end

  def self.build_unit_select(idx, current_unit, all_unit_options)
    html = "<select onchange='sketchup.change_unit(#{idx},this.value)' style='padding:2px;font-size:11px;border:1px solid #ccc;border-radius:3px;cursor:pointer' onclick='event.stopPropagation()'>"
    all_unit_options.each do |opt|
      sel = opt == current_unit ? "selected" : ""
      html += "<option value='#{opt}' #{sel}>#{opt}</option>"
    end
    html += "</select>"
    html
  end

  def self.build_status_btn(data, i)
    idx_payload =
      if i.is_a?(Array)
        i.map(&:to_i).uniq.join(",")
      else
        i.to_i.to_s
      end
    case MH_Thongke.status_key(data[:trang_thai])
    when "OK"
      "<span style='color:#27ae60;font-weight:bold'>✓</span>"
    when "UPDATE"
      "<button class='btn btn-blue' style='padding:2px 4px;font-size:10px' onclick='sketchup.action_update(#{js_arg(idx_payload)});event.stopPropagation()'>Update</button> <button class='btn btn-gray' style='padding:2px 4px;font-size:10px' onclick='sketchup.action_keep(#{js_arg(idx_payload)});event.stopPropagation()'>Keep</button>"
    when "SPEC"
      "<span style='color:#7f8c8d;font-weight:bold;font-size:10px'>SPEC</span>"
    when "THIEU"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#e74c3c;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>THIEU</span>"
    when "NO_SPEC"
      "<button class='btn btn-red' style='padding:2px 4px;font-size:10px' onclick='sketchup.action_accept_no_spec(#{js_arg(idx_payload)});event.stopPropagation()'>No SPEC</button>"
    when "GHOST"
      "<span style='color:#8e44ad;font-weight:bold;font-size:10px'>GHOST</span>"
    else
      ""
    end
  end

  def self.build_mat_status_btn(data, i = nil)
    state = MH_Thongke.status_key(data[:trang_thai])
    case state
    when "OK", "DU"
      label = state == "DU" ? "&#272;&#7910;" : "OK"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#0b74d1;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>#{label}</span>"
    when "SPEC"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#7f8c8d;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>SPEC</span>"
    when "THIEU", "NO_SPEC"
      label = state == "THIEU" ? "THI&#7870;U" : "NO SPEC"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#e74c3c;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>#{label}</span>"
    when "UPDATE"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#3498db;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>UPDATE</span>"
    when "GHOST"
      "<span style='display:inline-block;min-width:56px;text-align:center;background:#8e44ad;color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:1px'>GHOST</span>"
    else ""
    end
  end

  def self.project_status_badge(text)
    color =
      case text.to_s
      when "Xong CNC", "Xong định mức" then "#0b74d1"
      when "Đang làm CNC", "Đang định mức" then "#f1c40f"
      when "Vướng thông tin", "Thiếu thông tin" then "#e74c3c"
      else "#95a5a6"
      end
    "<span style='display:inline-block;min-width:70px;text-align:center;background:#{color};color:#111;font-weight:bold;font-size:10px;padding:2px 4px;border-radius:2px'>#{html_escape(text)}</span>"
  end

  def self.build_project_total_rows(mode = "COMPACT", sort_mode = nil)
    sort_mode = sort_mode.to_s.upcase
    sort_mode = "CUT" unless ["CUT", "PRODUCT"].include?(sort_mode)

    # FAST cache key — avoid loading snapshots / normalize on every call.
    # Use simple stat of @file_snapshots if available.
    cache_key = [
      mode.to_s,
      sort_mode,
      (@file_snapshots || []).size,
      (@imported_excel_data || []).size,
      @import_excel_loaded_mtime.to_f
    ].join("::")
    cached = instance_variable_get(:@build_project_total_rows_cache_value)
    cached_key = instance_variable_get(:@build_project_total_rows_cache_key)
    return cached if cached && cached_key == cache_key

    load_snapshots if @file_snapshots.nil? || @file_snapshots.empty?
    normalize_snapshots!

    rows = String.new
    current_project = current_project_name
    sorted = respond_to?(:project_total_source_snapshots) ? project_total_source_snapshots : []
    join_values = lambda do |values|
      values.map { |v| fix_vietnamese_mojibake(v).to_s.strip }.reject(&:empty?).uniq.join("; ")
    end
    join_dates = lambda do |values|
      values.map { |v| report_date_display(v).to_s.strip }.reject(&:empty?).uniq.join("; ")
    end
    excel_name_cache = {}
    excel_loaded = false
    resolve_ten_sp = lambda do |product, current_name|
      name = fix_vietnamese_mojibake(current_name).to_s.strip
      return name unless name.empty?
      return "" unless respond_to?(:import_excel_product_name_for)
      unless excel_loaded
        load_import_excel_snapshot_only if respond_to?(:load_import_excel_snapshot_only)
        excel_loaded = true
      end
      code = product.to_s.strip
      return "" if code.empty?
      return excel_name_cache[code] if excel_name_cache.key?(code)
      excel_name_cache[code] = fix_vietnamese_mojibake(import_excel_product_name_for(code, false)).to_s.strip
    rescue
      ""
    end
    product_sort_key = lambda do |product|
      respond_to?(:product_code_sort_key) ? product_code_sort_key(product) : product.to_s
    rescue
      product.to_s
    end
    cut_sort_key = lambda do |cut|
      text = cut.to_s.strip
      nums = text.scan(/\d+/).map(&:to_i)
      [nums.empty? ? 1 : 0, nums, text]
    rescue
      [1, [], cut.to_s]
    end
    excel_products = []
    excel_product_names = {}
    begin
      if respond_to?(:load_import_excel_snapshot_only)
        load_import_excel_snapshot_only if @imported_excel_data.nil? || @imported_excel_data.empty?
      end
      Array(@imported_excel_data).each do |row|
        next unless row.is_a?(Hash)
        raw_code = row[:ma_sp] || row["ma_sp"]
        code = report_product_code(raw_code)
        code = raw_code.to_s.strip.upcase if code.to_s.strip.empty?
        next unless product_code_valid?(code) rescue code =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
        code = code.upcase
        excel_products << code unless excel_products.include?(code)
        name = fix_vietnamese_mojibake(row[:ten_sp] || row["ten_sp"]).to_s.strip
        excel_product_names[code] = name unless name.empty?
      end
    rescue
      excel_products = []
      excel_product_names = {}
    end
    row_items = []

    sorted.each do |snap|
      project = snapshot_project(snap)
      cut_path = snap["skp_path"].to_s.empty? ? snap["skp_name"].to_s : snap["skp_path"].to_s
      cut_auto = respond_to?(:snapshot_cut_label_from_file) ? snapshot_cut_label_from_file(cut_path) : ""
      cut = cut_auto.to_s.empty? ? snap["label"].to_s : cut_auto.to_s
      cut_index = respond_to?(:skp_cut_index) ? skp_cut_index(cut_path) : nil
      file_name = snap["skp_name"].to_s
      has_nesting = !snap["nesting_at"].to_s.strip.empty?
      raw_items = (snap["items"] || []).map { |item| [item, "PK"] } + (snap["mat_items"] || []).map { |item| [item, "VL"] }
      missing_item = lambda do |item|
        return true if item["is_missing"] == true
        st = begin
          MH_Thongke.status_key(item["trang_thai"])
        rescue
          item["trang_thai"].to_s.strip.upcase
        end
        layer = item["layer"].to_s.strip
        layer == "-" && ["SPEC", "GHOST"].include?(st)
      rescue
        false
      end
      has_obj_flag = lambda do |item|
        return true if item["has_obj"] == true
        return item["obj_count"].to_i > 0 if item.key?("obj_count")
        nil
      rescue
        nil
      end
      has_obj_meta = raw_items.any? do |pair|
        item = pair[0]
        item.is_a?(Hash) && (item.key?("has_obj") || item.key?("obj_count"))
      end
      obj_products = {}
      if has_obj_meta
        raw_items.each do |item, _type_label|
          next unless has_obj_flag.call(item) == true
          prod = item["product"].to_s
          product_code = report_product_code(prod)
          product_code = prod if product_code.empty?
          next if product_code.to_s.strip.empty?
          obj_products[product_code] = true
        end
      end
      groups = {}
      raw_items.each do |item, type_label|
        next if missing_item.call(item)
        prod = item["product"].to_s
        product = report_product_code(prod)
        product = prod if product.empty?
        next if product.to_s.strip.empty? || product.to_s.strip == "--"
        next if has_obj_meta && !obj_products[product]
        ten_sp = item["ten_sp"].to_s
        key = product
        groups[key] ||= {
          product: product,
          ten_sp_values: [],
          notes: [],
          statuses: [],
          updated_dates: [],
          order_dates: [],
          pk_items: [],
          vl_items: [],
          search_parts: []
        }
        group = groups[key]
        group[:ten_sp_values] << ten_sp
        group[:notes] << item["ghi_chu"].to_s
        group[:statuses] << item["trang_thai"].to_s
        group[:updated_dates] << item["last_modified"].to_s
        if type_label == "PK"
          group[:pk_items] << item
          group[:order_dates] << item["ngay_dat"].to_s
        else
          group[:vl_items] << item
        end
        group[:search_parts] << [type_label, item["name"], item["kich_thuoc"], item["layer"], item["qty"], item["unit"]].join(" ")
      end

      groups.values.sort_by { |g| product_sort_key.call(g[:product]) }.each do |group|
        ten_sp = resolve_ten_sp.call(group[:product], join_values.call(group[:ten_sp_values]))
        pk_items = group[:pk_items]
        vl_items = group[:vl_items]
        start_cnc_raw = respond_to?(:snapshot_file_created_at) ? snapshot_file_created_at(snap).to_s : snap["file_created_at"].to_s
        finish_cnc_raw = snap["nesting_at"].to_s.empty? ? snap["exported_at"].to_s : snap["nesting_at"].to_s
        start_cnc_date = report_date_display(start_cnc_raw)
        finish_cnc_date = report_date_display(finish_cnc_raw)
        dmvt_order_date = join_dates.call(group[:order_dates])
=begin legacy_local_status
        pk_blocked = pk_items.select { |item| report_blocked_note?(item["ghi_chu"]) }
        pk_with_date = pk_items.select { |item| !normalize_order_date(item["ngay_dat"]).to_s.strip.empty? }
        cnc_status =
          if has_nesting && (product_code_valid?(group[:product]) rescue group[:product].to_s =~ /\A[A-Z]+\d+/i) && vl_items.empty?
            "Vướng thông tin"
          elsif has_nesting
            "Xong CNC"
          else
            "Đang làm CNC"
          end
        dmvt_status =
          if !pk_blocked.empty?
            "Thiếu thông tin"
          elsif pk_items.empty? || pk_with_date.size == pk_items.size
            "Xong định mức"
          elsif pk_with_date.any?
            "Đang định mức"
          else
            "Đang định mức"
          end
=end
        blocked_items = (pk_items + vl_items).select { |item| report_blocked_note?(item["ghi_chu"]) }
        pk_with_date = pk_items.select { |item| !normalize_order_date(item["ngay_dat"]).to_s.strip.empty? }
        # Shared status resolver for all report views.
        cnc_status = project_cnc_status_text(has_nesting, group[:product], vl_items, blocked_items.any?, pk_items + vl_items)
        dmvt_status = project_dmvt_status_text(pk_items)
        notes = group[:notes].dup
        notes << "PK: #{pk_with_date.size}/#{pk_items.size} có ngày đặt" unless pk_items.empty?
        notes << "Chưa có dữ liệu CNC cho SP này" if cnc_status == "Vướng thông tin"
        note = join_values.call(notes)
        updated = join_dates.call(group[:updated_dates])
        item_status = join_values.call(group[:statuses])
        search_text = [project, cut, file_name, group[:product], ten_sp, start_cnc_date, finish_cnc_date, dmvt_order_date, cnc_status, dmvt_status, note, item_status, updated, group[:search_parts].join(" ")].join(" ").downcase
        row_items << {
          project: project,
          cut: cut,
          cut_index: cut_index,
          file_name: file_name,
          skp_path: snap["skp_path"].to_s,
          product: group[:product].to_s,
          ten_sp: ten_sp,
          start_cnc_date: start_cnc_date,
          finish_cnc_date: finish_cnc_date,
          dmvt_order_date: dmvt_order_date,
          cnc_status: cnc_status,
          dmvt_status: dmvt_status,
          updated: updated,
          search_text: search_text
        }
      end
    end
    if excel_products.any?
      present_products = row_items.map { |row| row[:product].to_s.upcase }.uniq
      excel_products.each do |code|
        next if present_products.include?(code.to_s.upcase)
        ten_sp = resolve_ten_sp.call(code, excel_product_names[code].to_s)
        search_text = [current_project, code, ten_sp].join(" ").downcase
        row_items << {
          project: current_project,
          cut: "--",
          cut_index: nil,
          file_name: "--",
          skp_path: "",
          product: code.to_s,
          ten_sp: ten_sp,
          start_cnc_date: "",
          finish_cnc_date: "",
          dmvt_order_date: "",
          cnc_status: "",
          dmvt_status: "",
          updated: "",
          search_text: search_text
        }
      end
    end
    sorted_rows =
      if sort_mode == "PRODUCT"
        row_items.sort_by { |row| [product_sort_key.call(row[:product]), row[:cut_index].to_i <= 0 ? 9_999 : row[:cut_index].to_i, cut_sort_key.call(row[:cut]), row[:file_name].to_s] }
      else
        row_items.sort_by { |row| [row[:cut_index].to_i <= 0 ? 9_999 : row[:cut_index].to_i, cut_sort_key.call(row[:cut]), row[:file_name].to_s, product_sort_key.call(row[:product])] }
      end

    sorted_rows.each do |row|
      rows << "<tr class='data-row project-total-row' data-search='#{html_escape(row[:search_text])}'>"
      rows << "<td>#{html_escape(row[:project])}</td>"
      rows << "<td>#{html_escape(row[:cut])}</td>"
      rows << "<td title='#{html_escape(row[:skp_path])}'>#{html_escape(row[:file_name])}</td>"
      rows << "<td><b style='color:#e67e22'>#{html_escape(row[:product])}</b></td>"
      rows << "<td>#{html_escape(row[:ten_sp])}</td>"
      rows << "<td>#{html_escape(row[:start_cnc_date])}</td>"
      rows << "<td>#{html_escape(row[:finish_cnc_date])}</td>"
      rows << "<td>#{row[:cnc_status].to_s.strip.empty? ? "" : project_status_badge(row[:cnc_status])}</td>"
      rows << "<td>#{html_escape(row[:dmvt_order_date])}</td>"
      rows << "<td>#{row[:dmvt_status].to_s.strip.empty? ? "" : project_status_badge(row[:dmvt_status])}</td>"
      rows << "<td>#{html_escape(row[:updated])}</td>"
      rows << "</tr>"
    end

    final = rows.empty? ? "<tr><td colspan='11' style='text-align:center;color:#7f8c8d;padding:15px'>Chưa có dữ liệu cho dự án #{html_escape(current_project)}. Vào tab FILE và bấm Update để lưu dữ liệu.</td></tr>" : rows
    instance_variable_set(:@build_project_total_rows_cache_value, final)
    instance_variable_set(:@build_project_total_rows_cache_key, cache_key)
    final
  end

  # -------------------------------------------------------
  # BUILD ALL ROWS (bảng tổng hợp)
  # -------------------------------------------------------
  def self.build_all_rows(acc_tree, mat_tree)
    return build_tab_all_bom_rows if respond_to?(:build_tab_all_bom_rows)

    all_rows = String.new; all_header_rendered = {}
    report_index_by_object_id = @html_report_index_by_object_id || {}
    mat_index_by_object_id = @html_mat_index_by_object_id || {}
    combined = []
    base_has_expand = {}
    bases = (acc_tree.map { |ti| ti[:base] } + mat_tree.map { |ti| ti[:base] }).uniq.compact.sort do |a, b|
      if a == "PK" && b != "PK"
        1
      elsif b == "PK" && a != "PK"
        -1
      elsif a == "--" && b != "--"
        1
      elsif b == "--" && a != "--"
        -1
      else
        a <=> b
      end
    end
    bases.each do |base|
      ai = acc_tree.select { |ti| ti[:base] == base && ti[:mode] != :child_dummy }
      mi = mat_tree.select { |ti| ti[:base] == base && ti[:mode] != :child_dummy }
      expandable = (mi + ai).any? { |ti| ti[:mode] == :child }
      base_has_expand[base] = expandable

      mi.select { |ti| ti[:mode] == :parent }.each { |ti| combined << ti.merge(source: :mat) }
      ai.select { |ti| ti[:mode] == :parent }.each { |ti| combined << ti.merge(source: :acc) }

      if expandable
        # Keep non-detail rows visible in collapsed mode and hidden in expanded mode.
        # Treat :normal rows as :parent inside expandable groups.
        mi.select { |ti| ti[:mode] == :normal }.each { |ti| combined << ti.merge(source: :mat, mode: :parent) }
        ai.select { |ti| ti[:mode] == :normal }.each { |ti| combined << ti.merge(source: :acc, mode: :parent) }

        # Duplicate :normal rows as :child so they remain visible when expanded.
        mi.select { |ti| ti[:mode] == :normal }.each { |ti| combined << ti.merge(source: :mat, mode: :child) }
        ai.select { |ti| ti[:mode] == :normal }.each { |ti| combined << ti.merge(source: :acc, mode: :child) }

        child_prods = (mi + ai).select { |ti| ti[:mode] == :child && ti[:source] != :acc && ti[:data][:type] != :length }.map { |ti| ti[:data][:product] }.uniq.sort

        child_prods.each do |cp|
          mi.select { |ti| ti[:mode] == :child && ti[:data][:product] == cp }.each { |ti| combined << ti.merge(source: :mat) }
          ai.select { |ti| ti[:mode] == :child && ti[:data][:product] == cp }.each { |ti| combined << ti.merge(source: :acc) }
        end
        combined << { mode: :child_dummy, base: base, data: nil, source: :none }
      else
        mi.select { |ti| ti[:mode] == :normal }.each { |ti| combined << ti.merge(source: :mat) }
        ai.select { |ti| ti[:mode] == :normal }.each { |ti| combined << ti.merge(source: :acc) }
      end
    end
    all_child_bases = base_has_expand.select { |_, v| v }.map { |k, _| k }

    row_count_for = lambda do |ti|
      return 1 unless ti[:source] == :acc
      data = ti[:data]
      cu = data[:_resolved_unit] || data[:unit]
      is_pc = data[:type] == :phaochi
      if !is_pc && data[:type] == :length && !["mm","m","md"].include?(cu) && data[:length_items].is_a?(Array) && !data[:length_items].empty?
        data[:length_items].map { |li| (li[:len_inch].to_f * 25.4).round(0) }.uniq.size
      else
        1
      end
    end

    collapsed_base_rowspan = Hash.new(0)
    combined.each do |ti|
      next if ti[:mode] == :child_dummy || ti[:mode] == :child
      collapsed_base_rowspan[ti[:base]] += row_count_for.call(ti)
    end

    collapsed_base_rendered = {}
    combined.each_with_index do |ti, ci|
      mode = ti[:mode]; base = ti[:base]; src = ti[:source]
      if mode == :child_dummy
        all_rows << "<tr class='child-row' data-tree='#{html_escape(base)}' style='display:none'><td class='tree-span' colspan='12' style='background:#1e272e;border-bottom:1px solid #7f8c8d'>&nbsp;</td></tr>"; next
      end
      data = ti[:data]
      if !all_header_rendered[base] && all_child_bases.include?(base)
        prod_safe = base.to_s.gsub("'","\\\\'")
        all_rows << "<tr class='data-row header-row' data-tree='#{html_escape(base)}' style='display:none;background:#34495e'><td class='tree-span' colspan='12' style='cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{base}</b><br><span class='tree-icon' onclick='sketchup.toggle_tree(#{js_arg(base)});event.stopPropagation()' style='font-size:11px;color:#e74c3c;cursor:pointer'>▲</span></td></tr>"
        all_header_rendered[base] = true
      end
      orig_idx =
        if src == :acc
          if mode == :parent && data[:original_indices].is_a?(Array) && !data[:original_indices].empty?
            data[:original_indices].first
          else
            report_index_by_object_id[data.object_id]
          end
        else
          mat_index_by_object_id[data.object_id]
        end
      cu = src == :acc ? (data[:_resolved_unit] || data[:unit]) : data[:unit]
      is_pc = src == :acc && data[:type] == :phaochi

      sorted_groups = []
      if src == :acc && !is_pc && data[:type] == :length && !["mm","m","md"].include?(cu) && data[:length_items].is_a?(Array) && !data[:length_items].empty?
        groups = {}
        data[:length_items].each do |li|; lm = (li[:len_inch].to_f * 25.4).round(0); groups[lm] ||= { count:0,sel_count:0 }; groups[lm][:count]+=1; groups[lm][:sel_count]+=1 if li[:selected]; end
        sorted_groups = groups.sort_by { |lm,_| lm }
      end
      sorted_groups = [[0, { count: data[:count].to_i, sel_count: data[:sel_count].to_i }]] if sorted_groups.empty?

      sorted_groups.each_with_index do |(len_mm, grp), gi|
        if src == :acc
          if is_pc
            sub_name   = data[:name]; display_qty = ui_number_text((data[:len_total_mm].to_f) / 1000.0)
          elsif sorted_groups.size > 1
            prev_lu = data[:_length_display_unit] || "mm"
            len_display = ["m","md"].include?(prev_lu) ? "#{(len_mm/1000.0).round(2)}#{prev_lu}" : "#{len_mm.to_i}mm"
            sub_name = "#{data[:name]} - dài #{len_display}"; display_qty = ui_count_text(grp[:count])
          else
            sub_name = data[:name]
            if data[:type] == :length
              raw_mm = data[:length].to_f * 25.4
              display_qty = case cu; when "m","md" then ui_number_text(raw_mm / 1000.0); when "mm" then ui_number_text(raw_mm.round(1)); else ui_count_text(grp[:count]); end
            else; display_qty = ui_count_text(grp[:count]); end
          end
        else
          sub_name = data[:name]; display_qty = ui_count_text(grp[:count])
        end

        sel_count = grp[:sel_count].to_i
        dsel = ui_selected_qty_html(sel_count)
        op_style = ui_selection_opacity(sel_count)
        type_lbl = src == :acc ? "<span style='color:#e67e22;font-weight:bold;font-size:10px'>PK</span>" : "<span style='color:#3498db;font-weight:bold;font-size:10px'>VL</span>"
        cls   = "data-row#{mode == :parent ? " parent-row" : (mode == :child ? " child-row" : "")}"
        style = [op_style, (mode == :child ? "display:none;" : "")].join

        click_fn = src == :acc ? "doSelectRow(#{orig_idx})" : "doSelectMatRow(#{orig_idx})"
        all_rows << "<tr id='all_row_#{ci}_#{gi}' class='#{cls}' data-tree='#{html_escape(base)}' style='#{style}' data-search='#{data[:product].to_s.downcase} #{data[:name].to_s.downcase}' onclick='#{click_fn}'>"
        if mode == :child
          prod_display_code = ui_product_code.call(data[:product])
          prod_safe = prod_display_code.to_s.gsub("'","\\\\'")
          all_rows << "<td style='vertical-align:middle;cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{prod_display_code}</b></td>"
        elsif gi == 0 && !collapsed_base_rendered[base]
          prod_display_code = ui_product_code.call(data[:product])
          prod_safe = prod_display_code.to_s.gsub("'","\\\\'")
          btn = all_child_bases.include?(base) ? "<br><span class='tree-icon' onclick='sketchup.toggle_tree(#{js_arg(base)});event.stopPropagation()' style='font-size:11px;color:#3498db;cursor:pointer'>▼</span>" : ""
          span = [collapsed_base_rowspan[base].to_i, 1].max
          all_rows << "<td rowspan='#{span}' style='vertical-align:middle;cursor:pointer' onclick='doSelectProduct(\"#{prod_safe}\")'><b style='color:#e67e22'>#{prod_display_code}</b>#{btn}</td>"
          collapsed_base_rendered[base] = true
        end
        thickness = src == :mat ? data[:thickness].to_s : data[:kich_thuoc].to_s
        disp_unit = src == :acc ? cu : data[:unit]
        ngay_str  = normalize_order_date(data[:ngay_dat])

        all_rows << "<td style='cursor:pointer' onclick='#{click_fn}'>#{type_lbl}</td>"
        all_rows << "<td style='cursor:pointer' onclick='#{click_fn}'>#{sub_name}</td>"
        all_rows << "<td style='cursor:pointer' onclick='#{click_fn}'>#{thickness}</td>"
        status_html = src == :acc ? build_status_btn(data, orig_idx) : build_mat_status_btn(data, orig_idx)
        all_rows << "<td style='cursor:pointer' onclick='#{click_fn}'>#{data[:ghi_chu]}</td>"
        all_rows << "<td style='cursor:pointer;text-align:center' onclick='#{click_fn}'>#{status_html}</td>"
        all_rows << "<td style='cursor:pointer' onclick='#{click_fn}'>#{data[:layer]}</td>"
        all_rows << "<td style='cursor:pointer;font-size:11px;color:#aaa' onclick='#{click_fn}'>#{ngay_str}</td>"
        all_rows << "<td style='text-align:center;cursor:pointer' class='sel-count-cell' data-src='#{src}' data-orig-idx='#{orig_idx}' onclick='#{click_fn}'>#{dsel}</td>"
        all_rows << "<td style='cursor:pointer' onclick='#{click_fn}'><b style='color:#e74c3c'>#{display_qty}</b></td>"
        all_rows << "<td style='cursor:pointer' onclick='#{click_fn}'>#{disp_unit}</td>"
        all_rows << "<td></td></tr>"
      end
    end
    all_rows
  end

end
