# encoding: utf-8
# MH_Thongke — mini import rendering
# UI/render/dialog cho Mini Import. Không chứa logic xử lý thống kê lõi.
module MH_Thongke
  MINI_IMPORT_USE_SNAPSHOT_CACHE = false unless const_defined?(:MINI_IMPORT_USE_SNAPSHOT_CACHE)
  MINI_IMPORT_USE_HTML_CACHE = false unless const_defined?(:MINI_IMPORT_USE_HTML_CACHE)
  MINI_IMPORT_LIVE_ONLY = true unless const_defined?(:MINI_IMPORT_LIVE_ONLY)
  MINI_IMPORT_SIMPLE_LIST_MODE = true unless const_defined?(:MINI_IMPORT_SIMPLE_LIST_MODE)
  MINI_IMPORT_SIMPLE_MATCH_TEST = true unless const_defined?(:MINI_IMPORT_SIMPLE_MATCH_TEST)

  # === mini_import_table.rb ===
  # --- mini_import_table.rb ---
# MH_Thongke - mini import table data helpers.


  def self.mini_group_header(product_code, title = nil)
    product = product_code_base(product_code) rescue product_code.to_s.strip
    label = html_escape(title || mini_import_title(product, false, "product"))
    product_attr = html_escape(product)
    [
      "<tr class='mini-product-row' data-product='#{product_attr}'>",
      "<td colspan='5'>",
      "<div class='mini-product-head'><span class='mini-product-title'>#{label}</span></div>",
      "</td>",
      "</tr>"
    ].join
  end

  def self.mini_section_header(label)
    "<tr class='mini-section-row'><td colspan='5'>#{html_escape(label)}</td></tr>"
  end

  def self.mini_split_rows(html_rows)
    rows = html_rows.to_s.scan(/<tr\b.*?<\/tr>/m)
    pk_rows = []
    vl_rows = []
    rows.each do |row_html|
      if row_html.include?("data-kind='VL'")
        vl_rows << row_html
      else
        pk_rows << row_html
      end
    end
    [pk_rows, vl_rows]
  end

  def self.mini_qty_display(item)
    qty = item[:qty].to_f
    unit = item[:unit].to_s.downcase
    if ["m", "md"].include?(unit)
      respond_to?(:ui_number_text) ? ui_number_text(qty.round(2)) : qty.round(2).to_s
    elsif qty <= 0 || (qty - qty.round).abs > 0.001
      respond_to?(:ui_number_text) ? ui_number_text(qty.round(2)) : qty.round(2).to_s
    else
      respond_to?(:ui_count_text) ? ui_count_text(qty.round) : qty.round.to_i.to_s
    end
  rescue
    "0"
  end

  def self.mini_import_ten_sp_names(product_code, load_excel = false, mode = mini_group_mode)
    mini_excel_items(product_code, load_excel, mode).map { |ex|
      strip_product_code_prefix(ex[:ten_sp])
    }.map(&:strip).reject(&:empty?).uniq
  end

  def self.mini_import_title(product_code, load_excel = false, mode = mini_group_mode)
    display_code = mode.to_s == "module" ? product_code_exact(product_code) : product_code_base(product_code)
    excel_name = respond_to?(:import_excel_product_name_for) ? import_excel_product_name_for(display_code, load_excel) : ""
    return "#{display_code} - #{excel_name}" unless excel_name.to_s.empty?

    names = mini_import_ten_sp_names(product_code, load_excel, mode)
    names = mini_import_ten_sp_names(product_code, false, "product") if names.empty?
    return display_code if names.empty? || names.size > 1

    "#{display_code} - #{names.first}"
  end

  # === mini_import_render_status.rb ===
  # --- mini_import_render_status.rb ---
# MH_Thongke - Mini Import status/action HTML helpers.


  def self.mini_import_status_ok_html
    "<span class='status-khop'>&#10003;</span>"
  end

  def self.mini_import_unmatch_button_html(product_safe, row_kind, model_name_safe, target_safe, spec_safe)
    onclick = "event.stopPropagation();if(window.sketchup&&sketchup.unmatch_item){sketchup.unmatch_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-kind\")||\"PK\",this.getAttribute(\"data-old\")||\"\",this.getAttribute(\"data-name\")||\"\",this.getAttribute(\"data-spec\")||\"\");}"
    "<button class='btn btn-unmatch' title='UNMATCH' aria-label='UNMATCH' data-product='#{product_safe}' data-kind='#{row_kind}' data-old='#{model_name_safe}' data-name='#{target_safe}' data-spec='#{spec_safe}' onclick='#{onclick}'></button>"
  end

  def self.mini_import_status_label_html(label, css_class = "status-extra")
    "<span class='#{css_class}'>#{label}</span>"
  end

  def self.mini_import_static_name_html(top_text, sub_text = "")
    top_safe = html_escape(top_text.to_s.strip.empty? ? "---" : top_text)
    sub_safe = html_escape(sub_text.to_s.strip)
    sub = sub_safe.empty? ? "" : "<span class='spec-text'>#{sub_safe}</span>"
    "<input class='name-input' type='text' value='#{top_safe}' disabled readonly>#{sub}"
  end

  def self.mini_import_simple_editable_name_html(product_safe, row_kind, old_safe, value_safe, target_safe = "", spec_safe = "", section_safe = "", sub_text = "")
    mini_import_name_input_html(product_safe, row_kind, old_safe, value_safe, target_safe, spec_safe, section_safe, html_escape(sub_text), false)
  rescue
    mini_import_static_name_html(value_safe, sub_text)
  end

  def self.mini_import_static_note_html(note_text = "")
    note_safe = html_escape(note_text.to_s)
    "<input class='note-input' type='text' value='#{note_safe}' disabled readonly>"
  end

  def self.mini_import_accept_button_html(product_safe, row_kind, old_safe, name_safe, spec_safe, label = "NO SPEC", extra_class = nil)
    classes = ["btn-nospec", extra_class, "btn-accept"].compact.join(" ")
    onclick = "event.stopPropagation();if(window.sketchup&&sketchup.accept_item){sketchup.accept_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-kind\")||\"PK\",this.getAttribute(\"data-old\")||\"\",this.getAttribute(\"data-name\")||\"\",this.getAttribute(\"data-spec\")||\"\");}"
    "<button class='#{classes}' data-product='#{product_safe}' data-kind='#{row_kind}' data-old='#{old_safe}' data-name='#{name_safe}' data-spec='#{spec_safe}' onclick='#{onclick}'>#{label}</button>"
  end

  def self.mini_import_update_actions_html(product_safe, row_kind, model_name_safe, target_safe, spec_safe)
    update_onclick = "event.stopPropagation();if(window.sketchup&&sketchup.update_item){sketchup.update_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-old\")||\"\",this.getAttribute(\"data-name\")||\"\",this.getAttribute(\"data-spec\")||\"\");}"
    keep_onclick = "event.stopPropagation();if(window.sketchup&&sketchup.keep_item){sketchup.keep_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-kind\")||\"PK\",this.getAttribute(\"data-old\")||\"\",this.getAttribute(\"data-name\")||\"\",this.getAttribute(\"data-spec\")||\"\");}"
    [
      "<div class='status-actions'>",
      "<button class='btn btn-update' data-product='#{product_safe}' data-old='#{model_name_safe}' data-name='#{target_safe}' data-spec='#{spec_safe}' onclick='#{update_onclick}'>UPDATE</button>",
      "<button class='btn btn-keep' data-product='#{product_safe}' data-kind='#{row_kind}' data-old='#{model_name_safe}' data-name='#{target_safe}' data-spec='#{spec_safe}' onclick='#{keep_onclick}'>KEEP</button>",
      "</div>"
    ].join
  end

  def self.mini_import_manual_match_button_html(product_safe, row_kind, model_name_safe)
    onclick = "event.stopPropagation();if(window.sketchup&&sketchup.manual_match_item){sketchup.manual_match_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-kind\")||\"PK\",this.getAttribute(\"data-old\")||\"\");}"
    [
      "<div class='status-actions'>",
      "<button class='btn btn-keep' data-product='#{product_safe}' data-kind='#{row_kind}' data-old='#{model_name_safe}' onclick='#{onclick}'>MATCH</button>",
      "</div>"
    ].join
  end

  def self.mini_import_matched_status_html(product_code, product_safe, row_kind, model, target_name, target_safe, spec, spec_safe, exact, editable)
    key = resolve_mini_matched_status_key(product_code, row_kind, model[:name], target_name, spec, exact)
    model_name_safe = html_escape(model[:name])
    return mini_import_status_ok_html if key == "OK"
    return mini_import_update_actions_html(product_safe, row_kind, model_name_safe, target_safe, spec_safe) if editable

    mini_import_accept_button_html(product_safe, row_kind, model_name_safe, target_safe, spec_safe)
  end

  def self.mini_import_excel_only_status_html(product_code, product_safe, excel_is_mat, hw, hw_safe, spec, spec_safe, row_kind = "PK")
    key = resolve_mini_excel_only_status_key(product_code, row_kind, excel_is_mat, hw, spec)
    return mini_import_status_ok_html if key == "OK"
    # Unified: SPEC and THIEU mean the same — Excel has it, model does not.
    # Use single label "SPEC" for both PK and VL.
    kind_for_accept = excel_is_mat ? "VL" : "PK"
    mini_import_accept_button_html(product_safe, kind_for_accept, "", hw_safe, spec_safe, "SPEC", "btn-spec")
  end

  def self.mini_import_model_only_status_html(product_code, product_safe, row_kind, model_name, name_safe)
    key = resolve_mini_model_only_status_key(product_code, row_kind, model_name)
    return mini_import_status_ok_html if key == "OK"

    row_kind.to_s == "PK" ? mini_import_manual_match_button_html(product_safe, row_kind, name_safe) : mini_import_accept_button_html(product_safe, row_kind, name_safe, "", "")
  end

  # === mini_import_render_inputs.rb ===
  # --- mini_import_render_inputs.rb ---
# MH_Thongke - Mini Import input/button HTML helpers.


  def self.mini_import_qty_input_html(product_safe, name_safe, qty, spec_safe = "", section_safe = "")
    qty_safe = html_escape(qty)
    "<input class='qty-input' type='text' data-product='#{product_safe}' data-name='#{name_safe}' data-spec='#{spec_safe}' data-section='#{section_safe}' value='#{qty_safe}' disabled readonly>"
  end

  def self.mini_import_name_input_html(product_safe, row_kind, old_safe, value_safe, target_safe = "", spec_safe = "", section_safe = "", sub_safe = "", readonly = false)
    attrs = [
      "class='name-input'",
      "data-product='#{product_safe}'",
      "data-old='#{old_safe}'",
      "data-section='#{section_safe}'",
      "value='#{value_safe}'",
      "onclick='event.stopPropagation()'"
    ]
    attrs << "data-kind='#{row_kind}'" unless row_kind.to_s.empty?
    attrs << "data-target='#{target_safe}'" unless target_safe.to_s.empty?
    attrs << "data-spec='#{spec_safe}'" unless spec_safe.to_s.empty?
    rename_onchange = "if(window.sketchup&&sketchup.rename_item){sketchup.rename_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-old\")||\"\",this.value||\"\",this.getAttribute(\"data-target\")||\"\",this.getAttribute(\"data-spec\")||\"\",this.getAttribute(\"data-kind\")||\"PK\");}"
    attrs << (readonly ? "readonly" : "onchange='#{rename_onchange}'")
    sub = sub_safe.to_s.empty? ? "" : "<span class='spec-text'>#{sub_safe}</span>"
    "<input #{attrs.join(' ')}>#{sub}"
  end

  def self.mini_import_note_input_html(product_safe, row_kind, name_safe, spec_safe = "", section_safe = "", note_safe = "")
    note_onchange = "if(window.sketchup&&sketchup.set_note){sketchup.set_note(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-kind\")||\"PK\",this.getAttribute(\"data-name\")||\"\",this.getAttribute(\"data-spec\")||\"\",this.value||\"\");}"
    [
      "<input class='note-input'",
      "data-product='#{product_safe}'",
      "data-kind='#{row_kind}'",
      "data-name='#{name_safe}'",
      "data-spec='#{spec_safe}'",
      "data-section='#{section_safe}'",
      "value='#{note_safe}'",
      "onclick='event.stopPropagation()'",
      "onchange='#{note_onchange}'>"
    ].join(" ")
  end

  def self.mini_import_delete_button_html(product_safe, name_safe, ids_safe = "", row_kind = "", spec_safe = "", mode = :model)
    attrs = [
      "class='btn btn-del'",
      "data-product='#{product_safe}'",
      "data-name='#{name_safe}'"
    ]
    attrs << "data-ids='#{ids_safe}'" unless ids_safe.to_s.empty?
    attrs << "data-kind='#{row_kind}'" unless row_kind.to_s.empty?
    attrs << "data-spec='#{spec_safe}'" unless spec_safe.to_s.empty?
    callback = if mode == :excel
      "event.stopPropagation();if(window.sketchup&&sketchup.remove_excel_item){sketchup.remove_excel_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-kind\")||\"PK\",this.getAttribute(\"data-name\")||\"\",this.getAttribute(\"data-spec\")||\"\");}"
    else
      "event.stopPropagation();if(window.sketchup&&sketchup.delete_item){sketchup.delete_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-name\")||\"\",this.getAttribute(\"data-ids\")||\"\");}"
    end
    "<button #{attrs.join(' ')} onclick='#{callback}'>X</button>"
  end

  # === mini_import_render_rows.rb ===
  # --- mini_import_render_rows.rb ---
# MH_Thongke - Mini Import row/cell rendering helpers.


  def self.render_import_mini_material_rows(data_rows)
    Array(data_rows).select { |row| mini_import_material_row_renderable?(row) }
                    .map { |row| render_import_mini_material_row(row) }.join
  end

  def self.mini_import_material_row_renderable?(row)
    return false unless row.is_a?(Hash)

    [
      row[:name],
      row[:hw],
      row[:target_name],
      row[:ma_vl_source],
      row[:spec],
      row[:display_sub]
    ].any? { |value| !value.to_s.strip.empty? }
  rescue
    false
  end

  def self.render_import_mini_material_row(row)
    ctx = mini_import_material_row_context(row)
    case row[:type]
    when :matched, :related
      render_import_mini_material_matched_row(row, ctx)
    when :excel_only
      render_import_mini_material_excel_only_row(row, ctx)
    else
      render_import_mini_material_model_only_row(row, ctx)
    end
  end

  def self.mini_import_material_row_context(row)
    {
      product_safe: html_escape(row[:product_code]),
      section_safe: html_escape(row[:section]),
      spec_safe: html_escape(row[:spec]),
      hw_safe: html_escape(row[:hw]),
      note_safe: html_escape(row[:note]),
      target_safe: html_escape(row[:target_name]),
      name_safe: html_escape(row[:name]),
      ids_safe: html_escape(Array(row[:ids]).join(",")),
      display_sub_safe: html_escape(row[:display_sub])
    }
  end

  # Material display rule (VL):
  # - ALL statuses (OK / UPDATE / SPEC / THIEU / NO_SPEC):
  #   BIG = ma_vl_source (Excel Ma_vat_lieu), SMALL = spec
  def self.mini_import_material_name_lines(row, ctx)
    excel = row[:excel].is_a?(Hash) ? row[:excel] : {}

    excel_ma_vl = row[:ma_vl_source].to_s.strip
    excel_ma_vl = (excel[:ma_vl_source] || excel["ma_vl_source"]).to_s.strip if excel_ma_vl.empty?
    excel_ma_vl = row[:target_name].to_s.strip if excel_ma_vl.empty?
    excel_ma_vl = row[:hw].to_s.strip if excel_ma_vl.empty?
    if excel_ma_vl.empty?
      name_text = row[:name].to_s.strip
      excel_ma_vl = respond_to?(:material_code_display) ? material_code_display(name_text) : name_text
    end

    model_name = row[:name].to_s.strip
    if [:matched, :related].include?(row[:type]) &&
       !model_name.empty? &&
       model_name != excel_ma_vl &&
       (!respond_to?(:material_code_subgroup?) || material_code_subgroup?(model_name))
      excel_ma_vl = model_name
    end

    spec_text = row[:display_sub].to_s.strip
    spec_text = row[:spec].to_s.strip if spec_text.empty?
    spec_text = (excel[:spec] || excel["spec"]).to_s.strip if spec_text.empty?

    top_text = excel_ma_vl.empty? ? "---" : excel_ma_vl
    sub_text = spec_text.empty? ? "" : spec_text
    [html_escape(top_text), html_escape(sub_text)]
  end

  def self.render_import_mini_material_matched_row(row, ctx)
    title_safe, sub_safe = mini_import_material_name_lines(row, ctx)
    status = if row[:type] == :related
               mini_import_status_ok_html
             else
               mini_import_matched_status_html(
                 row[:product_code],
                 ctx[:product_safe],
                 "VL",
                 row[:model],
                 row[:target_name],
                 ctx[:target_safe],
                 row[:spec],
                 ctx[:spec_safe],
                 row[:exact],
                 false
               )
             end

    mini_import_row_html(ctx[:product_safe], "VL", ctx[:name_safe], ctx[:ids_safe], [
      mini_import_cell_html(
        mini_import_name_input_html(
          ctx[:product_safe], "VL", ctx[:name_safe], title_safe,
          ctx[:target_safe], ctx[:spec_safe], ctx[:section_safe], sub_safe
        )
      ),
      mini_import_cell_html(mini_import_note_input_html(ctx[:product_safe], "VL", ctx[:hw_safe], ctx[:spec_safe], ctx[:section_safe], ctx[:note_safe])),
      mini_import_cell_html(status, true),
      mini_import_cell_html(mini_import_qty_input_html(ctx[:product_safe], ctx[:name_safe], row[:qty], ctx[:spec_safe], ctx[:section_safe]), true),
      mini_import_cell_html("")
    ], ctx[:section_safe])
  end

  def self.render_import_mini_material_excel_only_row(row, ctx)
    title_safe, sub_safe = mini_import_material_name_lines(row, ctx)
    status = mini_import_excel_only_status_html(row[:product_code], ctx[:product_safe], true, row[:hw], ctx[:hw_safe], row[:spec], ctx[:spec_safe], "VL")
    mini_import_row_html(ctx[:product_safe], "VL", ctx[:target_safe], "", [
      mini_import_cell_html(
        mini_import_name_input_html(
          ctx[:product_safe], "VL", ctx[:hw_safe], title_safe, "", "",
          ctx[:section_safe], sub_safe, true
        )
      ),
      mini_import_cell_html(mini_import_note_input_html(ctx[:product_safe], "VL", ctx[:hw_safe], ctx[:spec_safe], ctx[:section_safe], ctx[:note_safe])),
      mini_import_cell_html(status, true),
      mini_import_cell_html(mini_import_qty_input_html(ctx[:product_safe], ctx[:hw_safe], row[:qty], ctx[:spec_safe], ctx[:section_safe]), true),
      mini_import_cell_html("")
    ], ctx[:section_safe])
  end

  def self.render_import_mini_material_model_only_row(row, ctx)
    title_safe, sub_safe = mini_import_material_name_lines(row, ctx)
    status = mini_import_model_only_status_html(row[:product_code], ctx[:product_safe], "VL", row[:name], ctx[:name_safe])
    mini_import_row_html(ctx[:product_safe], "VL", ctx[:name_safe], ctx[:ids_safe], [
      mini_import_cell_html(mini_import_name_input_html(ctx[:product_safe], "VL", ctx[:name_safe], title_safe, "", "", ctx[:section_safe], sub_safe)),
      mini_import_cell_html(mini_import_note_input_html(ctx[:product_safe], "VL", ctx[:name_safe])),
      mini_import_cell_html(status, true),
      mini_import_cell_html(mini_import_qty_input_html(ctx[:product_safe], ctx[:name_safe], row[:qty]), true),
      mini_import_cell_html("")
    ])
  end

  def self.mini_import_cell_html(content, center = false)
    center ? "<td style='text-align:center'>#{content}</td>" : "<td>#{content}</td>"
  end

  def self.mini_import_row_html(product_safe, row_kind, name_safe, ids_safe, cells, section_safe = nil)
    attrs = [
      "class='mini-row'",
      "data-product='#{product_safe}'",
      "data-kind='#{row_kind}'",
      "data-name='#{name_safe}'",
      "data-ids='#{ids_safe}'"
    ]
    attrs << "data-section='#{section_safe}'" unless section_safe.nil?
    select_onclick = "if(window.sketchup&&sketchup.select_item){sketchup.select_item(this.getAttribute(\"data-product\")||\"\",this.getAttribute(\"data-name\")||\"\",this.getAttribute(\"data-ids\")||\"\");}"
    attrs << "onclick='#{select_onclick}'"
    "<tr #{attrs.join(' ')}>#{cells.join}</tr>"
  end

  # === mini_import_render.rb ===
  # --- mini_import_render.rb ---
# MH_Thongke - Mini Import render entrypoint.
#
# Logic is split into:
# - mini_import_render_status.rb
# - mini_import_render_inputs.rb
# - mini_import_render_rows.rb

  # === mini_import_rows.rb ===
  # --- mini_import_rows.rb ---
# MH_Thongke - Mini Import table row builders.


  def self.mini_import_product_block_cache_key(product_code)
    [
      product_code_exact(product_code),
      respond_to?(:import_mini_data_signature) ? import_mini_data_signature : import_mini_refresh_signature
    ].join("::")
  rescue
    nil
  end

  def self.mini_rows_resolve_products
    if defined?(MINI_IMPORT_SIMPLE_LIST_MODE) && MINI_IMPORT_SIMPLE_LIST_MODE
      products = mini_rows_selected_products
      set_mini_products(products) if respond_to?(:set_mini_products) && !products.empty?
      return products
    end

    products = mini_display_products
    if products.empty?
      refresh_mini_products_from_source(false)
      products = mini_display_products
    end
    products
  rescue
    []
  end

  def self.mini_rows_selected_products
    products = if respond_to?(:selected_product_codes)
      if defined?(MH::ModelReader) && MH::ModelReader.respond_to?(:product_codes_from_selection)
        MH::ModelReader.product_codes_from_selection(Sketchup.active_model, allow_slow_scan: false)
      else
        selected_product_codes(false)
      end
    else
      []
    end
    products = Array(products).map { |code| product_code_exact(code) rescue code.to_s.strip.upcase }
                              .select { |code| product_code_valid?(code) rescue code =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i }
                              .uniq
    if products.empty?
      products = Array(@mini_products)
      products = [@mini_product] if products.empty? && !@mini_product.to_s.strip.empty?
      products = products.map { |code| product_code_exact(code) rescue code.to_s.strip.upcase }
                         .select { |code| product_code_valid?(code) rescue code =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i }
                         .uniq
    end
    if respond_to?(:mini_group_mode) && mini_group_mode.to_s != "module"
      products = products.map { |code| product_code_base(code) rescue code.to_s.sub(/\.\d+\z/, "") }.uniq
    end
    products.sort_by { |code| respond_to?(:product_code_sort_key) ? product_code_sort_key(code) : code }
  rescue
    []
  end

  def self.mini_rows_entity_matches_product?(entity, products)
    targets = Array(products).map { |code| product_code_exact(code) rescue code.to_s.strip.upcase }.uniq
    bases = targets.map { |code| product_code_base(code) rescue code.to_s.sub(/\.\d+\z/, "") }.uniq
    codes = if respond_to?(:entity_product_codes)
      if defined?(MH::ModelReader) && MH::ModelReader.respond_to?(:entity_product_codes)
        MH::ModelReader.entity_product_codes(entity)
      else
        entity_product_codes(entity)
      end
    else
      text = "#{entity.respond_to?(:name) ? entity.name : ""} #{entity.respond_to?(:definition) && entity.definition ? entity.definition.name : ""}"
      respond_to?(:product_codes_from_text) ? product_codes_from_text(text) : text.scan(/[A-Z]+\d+[A-Z]?(?:\.\d+)?/i)
    end
    Array(codes).any? do |code|
      exact = product_code_exact(code) rescue code.to_s.strip.upcase
      base = product_code_base(exact) rescue exact.sub(/\.\d+\z/, "")
      targets.include?(exact) || bases.include?(base)
    end
  rescue
    false
  end

  def self.mini_rows_selected_scan_roots(products)
    @model ||= Sketchup.active_model
    if defined?(MH::ModelReader) && MH::ModelReader.respond_to?(:selected_roots)
      roots = MH::ModelReader.selected_roots(@model)
      product_roots = MH::ModelReader.roots_matching_products(roots, products) if MH::ModelReader.respond_to?(:roots_matching_products)
      return product_roots unless product_roots.nil? || product_roots.empty?
      return roots
    end

    roots = respond_to?(:selected_import_roots) ? selected_import_roots : Array(@model.selection.to_a)
    roots = roots.select { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }
                 .reject { |entity| entity.respond_to?(:deleted?) && entity.deleted? }
                 .uniq
    product_roots = roots.select { |entity| mini_rows_entity_matches_product?(entity, products) }
    product_roots.empty? ? roots : product_roots
  rescue
    []
  end

  def self.mini_rows_scan_selected_products(products)
    @model ||= Sketchup.active_model
    @mini_selected_raw_records = []
    source = session

    if defined?(MH::ModelReader) && MH::ModelReader.respond_to?(:records_for_product)
      mode = respond_to?(:mini_group_mode) ? mini_group_mode : "product"
      force_index = !!@mini_data_dirty || !!@mini_force_live_rows || !!@mini_force_sp_index_rebuild
      @mini_selected_raw_records = Array(products).flat_map do |product_code|
        MH::ModelReader.records_for_product(product_code, model: @model, mode: mode, force: force_index)
      end.uniq { |record| record[:entity_id] || record.object_id }
      @mini_force_sp_index_rebuild = false
    else
      roots = mini_rows_selected_scan_roots(products)
      @mini_selected_raw_records = defined?(MH::ModelReader) && MH::ModelReader.respond_to?(:scan) ? MH::ModelReader.scan(scope: :roots, roots: roots, max_depth: 3, types: %i[group component]) : []
    end

    @current_report_items = []
    @current_mat_items = []
    source.current_report_items = @current_report_items if source.respond_to?(:current_report_items=)
    source.current_mat_items = @current_mat_items if source.respond_to?(:current_mat_items=)
    @mini_selected_scan_last_result = {
      status: :shared_sp_index,
      products: products,
      raw_records: @mini_selected_raw_records.length,
      rows: 0,
      mat_rows: 0
    }
    true
  rescue => e
    @mini_selected_scan_last_result = { error: "#{e.class}: #{e.message}", products: products }
    false
  end

  def self.load_mini_rows_from_current_snapshot_cache
    return false unless MINI_IMPORT_USE_SNAPSHOT_CACHE
    return false unless respond_to?(:find_snapshot_by_path) && respond_to?(:snapshot_row_to_runtime_row)
    return false if @mini_data_dirty
    return false if Array(@mini_changed_products_for_save).any?
    return false if @mini_force_live_rows

    model = Sketchup.active_model rescue nil
    path = model ? model.path.to_s : ""
    return false if path.empty?

    load_snapshots if respond_to?(:load_snapshots)
    snap = find_snapshot_by_path(path)
    return false unless snap.is_a?(Hash)

    report_rows = Array(snap["items"]).map { |row| snapshot_row_to_runtime_row(row, :items) }.compact
    mat_rows = Array(snap["mat_items"]).map { |row| snapshot_row_to_runtime_row(row, :mat_items) }.compact
    return false if report_rows.empty? && mat_rows.empty?

    @current_report_items = report_rows
    @current_mat_items = mat_rows
    s = session if respond_to?(:session)
    if s
      s.current_report_items = report_rows if s.respond_to?(:current_report_items=)
      s.current_mat_items = mat_rows if s.respond_to?(:current_mat_items=)
    end
    @mini_loaded_from_snapshot_cache = true
    true
  rescue => e
    puts "load_mini_rows_from_current_snapshot_cache error: #{e.class}: #{e.message}" rescue nil
    false
  end

  def self.mini_rows_prepare_context(process_model, load_excel)
    products = mini_rows_resolve_products
    return { state: :no_product, products: [] } if products.empty?

    if defined?(MINI_IMPORT_SIMPLE_LIST_MODE) && MINI_IMPORT_SIMPLE_LIST_MODE
      s = session
      @imported_excel_data = s.imported_excel_data if s.respond_to?(:imported_excel_data) && s.imported_excel_data && !s.imported_excel_data.empty?
      need_excel_load = load_excel || @imported_excel_data.nil? || @imported_excel_data.empty?
      ensure_import_excel_loaded(need_excel_load) if need_excel_load && respond_to?(:ensure_import_excel_loaded)
      s = session
      @imported_excel_data = s.imported_excel_data if s.respond_to?(:imported_excel_data) && s.imported_excel_data && !s.imported_excel_data.empty?

      if process_model
        unless mini_rows_scan_selected_products(products)
          @current_report_items = []
          @current_mat_items = []
          s.current_report_items = [] if s.respond_to?(:current_report_items=)
          s.current_mat_items = [] if s.respond_to?(:current_mat_items=)
        end
      else
        @current_report_items ||= []
        @current_mat_items ||= []
      end
      @mini_loaded_from_snapshot_cache = false
      @mini_force_live_rows = false
      return { state: :no_excel, products: products } if @imported_excel_data.nil? || @imported_excel_data.empty?
      return { state: :ready, products: products }
    end

    # Pull data from session — but NEVER overwrite @imported_excel_data if it
    # was already loaded by another view (HUD, main tables) from JSON cache.
    s = session
    @current_report_items = s.current_report_items || []
    @current_mat_items    = s.current_mat_items    || []
    s_excel = s.imported_excel_data
    if s_excel && !s_excel.empty?
      respond_to?(:set_imported_excel_data) ? set_imported_excel_data(s_excel, "mini_rows_session_sync", sync_session: false) : (@imported_excel_data = s_excel)
    end

    need_live_rows =
      process_model ||
      @mini_force_live_rows ||
      @mini_data_dirty ||
      Array(@mini_changed_products_for_save).any? ||
      (process_model && (@mini_loaded_from_snapshot_cache || (@current_report_items.empty? && @current_mat_items.empty?)))

    if need_live_rows
      if respond_to?(:process_selection_cached)
        process_selection_cached(true, "mini_live_rows")
      elsif respond_to?(:process_selection)
        begin
          @force_process_selection_once = true
          process_selection
        ensure
          @force_process_selection_once = false
        end
      end
      s = session
      @current_report_items = s.current_report_items || []
      @current_mat_items    = s.current_mat_items    || []
      @mini_loaded_from_snapshot_cache = false
      @mini_force_live_rows = false unless @mini_data_dirty || Array(@mini_changed_products_for_save).any?
    end

    if MINI_IMPORT_USE_SNAPSHOT_CACHE && @current_report_items.empty? && @current_mat_items.empty?
      load_mini_rows_from_current_snapshot_cache if respond_to?(:load_mini_rows_from_current_snapshot_cache)
      @current_report_items ||= []
      @current_mat_items ||= []
    end

    # Ensure pipeline has run at least once
    if @current_report_items.empty? && @current_mat_items.empty?
      process_selection if process_model
      @current_report_items = s.current_report_items || []
      @current_mat_items    = s.current_mat_items    || []
      s_excel = s.imported_excel_data
      if s_excel && !s_excel.empty?
        respond_to?(:set_imported_excel_data) ? set_imported_excel_data(s_excel, "mini_rows_post_process_sync", sync_session: false) : (@imported_excel_data = s_excel)
      end
    end

    # Fallback: load Excel data from JSON cache (disabled in live-only Mini Import).
    if (!defined?(MINI_IMPORT_LIVE_ONLY) || !MINI_IMPORT_LIVE_ONLY) &&
       (@imported_excel_data.nil? || @imported_excel_data.empty?) &&
       respond_to?(:load_import_excel_snapshot_only)
      load_import_excel_snapshot_only
    end

    return { state: :no_excel, products: products } if @imported_excel_data.nil? || @imported_excel_data.empty?

    # Ensure restore system data is loaded (rules, lineage, hidden items)
    ensure_mini_accept_rules if respond_to?(:ensure_mini_accept_rules)
    ensure_mini_name_lineage if respond_to?(:ensure_mini_name_lineage)

    { state: :ready, products: products }
  rescue
    { state: :error, products: [] }
  end

  def self.mini_rows_material_sections_html(product_code, vl_ex_items)
    html = +""
    build_import_material_section_data_for_product(product_code, vl_ex_items, true).each do |section|
      section_html = render_import_mini_material_rows(section[:rows])
      next if section_html.empty?

      html << mini_section_header(section[:title]) unless section[:leftover] && !html.empty?
      html << section_html
    end
    html
  rescue
    ""
  end

  def self.mini_import_simple_excel_row_html(product_code, item, row_kind)
    product_safe = html_escape(product_code)
    row_kind = row_kind.to_s == "VL" ? "VL" : "PK"
    name = if row_kind == "VL"
      item[:ma_vl_source].to_s.strip
    else
      item[:target_name].to_s.strip
    end
    name = item[:hw].to_s.strip if name.empty?
    sub = item[:display_sub].to_s.strip
    sub = item[:spec].to_s.strip if sub.empty?
    note = item[:note].to_s.strip
    note = item[:ghi_chu].to_s.strip if note.empty?
    qty = item[:qty].to_f
    qty = item[:excel_qty].to_f if qty <= 0 && item.key?(:excel_qty)
    qty = qty.to_i if (qty - qty.round).abs <= 0.001
    name_safe = html_escape(name)
    spec_safe = html_escape(item[:spec])
    section_safe = html_escape(item[:section])

    mini_import_row_html(product_safe, row_kind, name_safe, "", [
      mini_import_cell_html(mini_import_static_name_html("---", name.empty? ? sub : name)),
      mini_import_cell_html(mini_import_static_note_html(note)),
      mini_import_cell_html(mini_import_status_label_html("SPEC", "btn-spec"), true),
      mini_import_cell_html(mini_import_qty_input_html(product_safe, name_safe, qty, spec_safe, section_safe), true),
      mini_import_cell_html("")
    ], section_safe)
  rescue
    ""
  end

  def self.mini_import_simple_model_row_html(product_code, model, sub_text = "---")
    product_safe = html_escape(product_code)
    row_kind = model[:kind].to_s == "VL" ? "VL" : "PK"
    name = model[:name].to_s.strip
    return "" if name.empty?

    ids_safe = html_escape(Array(model[:ids]).join(","))
    name_safe = html_escape(name)
    qty = mini_qty_display(model)
    status = if row_kind == "PK" && defined?(MINI_IMPORT_SIMPLE_MATCH_TEST) && MINI_IMPORT_SIMPLE_MATCH_TEST
      mini_import_manual_match_button_html(product_safe, row_kind, name_safe)
    else
      mini_import_status_label_html("NO SPEC", "btn-nospec")
    end
    mini_import_row_html(product_safe, row_kind, name_safe, ids_safe, [
      mini_import_cell_html(mini_import_simple_editable_name_html(product_safe, row_kind, name_safe, name_safe, "", "", "", sub_text)),
      mini_import_cell_html(mini_import_static_note_html("")),
      mini_import_cell_html(status, true),
      mini_import_cell_html(mini_import_qty_input_html(product_safe, name_safe, qty), true),
      mini_import_cell_html("")
    ])
  rescue
    ""
  end

  def self.mini_import_simple_matched_row_html(product_code, model, item)
    product_safe = html_escape(product_code)
    row_kind = model[:kind].to_s == "VL" ? "VL" : "PK"
    name = model[:name].to_s.strip
    return "" if name.empty?

    ids_safe = html_escape(Array(model[:ids]).join(","))
    name_safe = html_escape(name)
    target_name = item[:target_name].to_s.strip
    target_name = item[:hw].to_s.strip if target_name.empty?
    spec = item[:spec].to_s.strip
    note = item[:note].to_s.strip
    note = item[:ghi_chu].to_s.strip if note.empty?
    sub_text = target_name.empty? ? spec : target_name
    qty = mini_qty_display(model)
    qty = item[:excel_qty] if qty.to_f <= 0 && item[:excel_qty].to_f > 0

    target_safe = html_escape(target_name)
    spec_safe = html_escape(spec)
    action = mini_import_unmatch_button_html(product_safe, row_kind, name_safe, target_safe, spec_safe)

    mini_import_row_html(product_safe, row_kind, name_safe, ids_safe, [
      mini_import_cell_html(mini_import_simple_editable_name_html(product_safe, row_kind, name_safe, name_safe, target_safe, spec_safe, html_escape(item[:section]), sub_text)),
      mini_import_cell_html(mini_import_static_note_html(note)),
      mini_import_cell_html(mini_import_status_ok_html, true),
      mini_import_cell_html(mini_import_qty_input_html(product_safe, name_safe, qty, spec_safe, html_escape(item[:section])), true),
      mini_import_cell_html(action, true)
    ], html_escape(item[:section]))
  rescue
    ""
  end

  def self.mini_simple_virtual_key_for(product_code, group, spec, source)
    if respond_to?(:virtual_key)
      virtual_key(product_code: product_code, group: group, spec: spec, source: source, anchor: "")
    else
      [product_code_exact(product_code), "PKV", group, spec, "SOURCE:#{source}"].map { |v| v.to_s.strip.upcase.gsub(/\s+/, "_") }.reject(&:empty?).join("|")
    end
  rescue
    ""
  end

  def self.mini_simple_virtual_record(product_code, name, group, spec, source, qty = 1, unit = "cai")
    {
      kind: "PK",
      name: name,
      qty: qty,
      unit: unit,
      ids: [],
      rows: [],
      raw_model: true,
      virtual: true,
      virtual_key: mini_simple_virtual_key_for(product_code, group, spec, source),
      virtual_source: source,
      sub: "VIRTUAL | #{group}"
    }
  rescue
    nil
  end

  def self.mini_simple_virtual_records(product_code, raw_model_items)
    names = Array(raw_model_items).map { |item| mini_simple_name_norm(item[:name]) }
    out = []
    has_led = names.any? { |name| name.include?("led") }
    has_suot = names.any? { |name| name.include?("suot ao") || name.include?("suot treo ao") }

    if has_led
      out << mini_simple_virtual_record(product_code, "Thanh nhôm led", "LED_PROFILE", "THANH_NHOM_LED", "LED_TOTAL", 1, "md")
      out << mini_simple_virtual_record(product_code, "Nguồn led", "LED_POWER", "NGUON_LED", "LED_TOTAL", 1, "cai")
    end
    if has_suot
      out << mini_simple_virtual_record(product_code, "Bas treo suốt áo", "SUOT_AO", "BAS_TREO_SUOT_AO", "MODEL_LENGTH", 2, "cai")
    end

    seen = {}
    out.compact.reject do |item|
      key = mini_simple_name_norm(item[:name])
      hidden = mini_simple_raw_model_hidden_name?(item[:name])
      dup = seen[key]
      seen[key] = true
      hidden || dup
    end
  rescue
    []
  end

  def self.mini_simple_raw_model_records(product_code)
    return [] unless defined?(MH::ModelReader) && MH::ModelReader.respond_to?(:scan)

    target_exact = product_code_exact(product_code) rescue product_code.to_s.strip.upcase
    target_base = product_code_base(target_exact) rescue target_exact.sub(/\.\d+\z/, "")
    records = Array(@mini_selected_raw_records)
    records = MH::ModelReader.scan(scope: :selection, max_depth: 3, types: %i[group component]) if records.empty?
    product_by_id = {}
    records.each do |record|
      codes = Array(record[:product_codes]).map { |code| product_code_exact(code) rescue code.to_s.strip.upcase }
      product_by_id[record[:entity_id]] = codes unless codes.empty?
    end

    seen = {}
    records.map do |record|
      next if mini_simple_raw_model_noise_record?(record)
      name = mini_simple_raw_model_pk_display_name(record)
      next if name.empty?
      next if mini_simple_raw_model_hidden_name?(name)

      own_codes = Array(record[:product_codes]).map { |code| product_code_exact(code) rescue code.to_s.strip.upcase }
      inherited_codes = Array(record[:path_ids]).reverse.flat_map { |id| Array(product_by_id[id]) }
      codes = (own_codes + inherited_codes).uniq
      next if codes.empty?
      hit = codes.any? do |code|
        exact = product_code_exact(code) rescue code.to_s.strip.upcase
        base = product_code_base(exact) rescue exact.sub(/\.\d+\z/, "")
        exact == target_exact || base == target_base
      end
      next unless hit

      key = "#{name}\u001F#{record[:entity_id]}"
      next if seen[key]
      seen[key] = true

      attr_names = Array(record[:attrs].is_a?(Hash) ? record[:attrs].keys : [])
      sub_parts = []
      sub_parts << codes.join(", ") unless codes.empty?
      sub_parts << attr_names.join(", ") unless attr_names.empty?
      {
        kind: "PK",
        name: name,
        qty: 1,
        unit: "cai",
        ids: [record[:entity_id]].compact,
        rows: [],
        raw_model: true,
        sub: sub_parts.empty? ? "MODEL SCAN" : sub_parts.join(" | ")
      }
    end.compact
  rescue => e
    puts "mini_simple_raw_model_records error: #{e.class}: #{e.message}" rescue nil
    []
  end

  def self.mini_simple_raw_model_pk_display_name(record)
    attrs = record.is_a?(Hash) && record[:attrs].is_a?(Hash) ? record[:attrs] : {}
    definition_attrs = record.is_a?(Hash) && record[:definition_attrs].is_a?(Hash) ? record[:definition_attrs] : {}
    abf = attrs["ABF"].is_a?(Hash) ? attrs["ABF"] : {}
    def_abf = definition_attrs["ABF"].is_a?(Hash) ? definition_attrs["ABF"] : {}
    thongke = attrs["MH_Thongke"].is_a?(Hash) ? attrs["MH_Thongke"] : {}
    def_thongke = definition_attrs["MH_Thongke"].is_a?(Hash) ? definition_attrs["MH_Thongke"] : {}

    [
      abf["setting-name"],
      abf["statistical-name"],
      thongke["pk_name"],
      def_abf["setting-name"],
      def_abf["statistical-name"],
      def_thongke["pk_name"]
    ].map { |value| value.to_s.strip }.find { |value| !value.empty? }.to_s
  rescue
    ""
  end

  def self.mini_simple_raw_model_hidden_name?(name)
    respond_to?(:hidden_item_name?) && hidden_item_name?(name)
  rescue
    false
  end

  def self.mini_simple_raw_model_noise_name?(name)
    text = name.to_s.strip
    return true if text.empty?
    return true if text == "__ABF_Nesting"
    return true if text =~ /\AABF_CenterLine/i
    return true if text =~ /\AABF_Lockdowel_Preview/i
    return true if text =~ /\AABF_(?:Line|Preview)/i

    false
  rescue
    false
  end

  def self.mini_simple_raw_model_noise_record?(record)
    return true unless record.is_a?(Hash)

    names = [record[:name], record[:definition_name]]
    names.concat(Array(record[:path_names]))
    return true if names.any? { |value| value.to_s.strip == "__ABF_Nesting" }

    mini_simple_raw_model_noise_name?(record[:name])
  rescue
    false
  end

  def self.mini_simple_name_norm(name)
    respond_to?(:import_name_norm) ? import_name_norm(name) : name.to_s.strip.downcase
  rescue
    name.to_s.strip.downcase
  end

  def self.build_import_mini_rows_simple(products)
    rows = +""
    Array(products).each do |product_code|
      ex_items = mini_excel_items(product_code, false)
      model_items = []
      pk_ex_items = ex_items.reject { |ex| ex[:kind].to_s == "VL" }
      vl_ex_items = ex_items.select { |ex| ex[:kind].to_s == "VL" }
      pk_model_items = model_items.reject { |item| item[:kind].to_s == "VL" }
      vl_model_items = model_items.select { |item| item[:kind].to_s == "VL" }
      raw_model_items = mini_simple_raw_model_records(product_code)
      raw_model_items.concat(mini_simple_virtual_records(product_code, raw_model_items))
      known_model_names = (pk_model_items + vl_model_items).map { |item| mini_simple_name_norm(item[:name]) }.uniq
      raw_model_items = raw_model_items.reject { |item| known_model_names.include?(mini_simple_name_norm(item[:name])) }

      prepared_pk_ex_items = mini_group_excel_items(pk_ex_items, true).map { |ex| mini_pk_prepare_excel_item(ex) }
      matched_excel_indexes = {}
      matched_raw_indexes = {}
      matched_simple_rows = []
      raw_model_items.each_with_index do |model, model_index|
        prepared_pk_ex_items.each_with_index do |item, excel_index|
          target_name = item[:target_name].to_s.strip
          target_name = item[:hw].to_s.strip if target_name.empty?
          spec = item[:spec].to_s.strip
          action = respond_to?(:mini_accept_rule_action) ? mini_accept_rule_action(product_code, "PK", model[:name], target_name, spec).to_s : ""
          next unless action == "manual_match"

          matched_excel_indexes[excel_index] = true
          matched_raw_indexes[model_index] = true
          matched_simple_rows << [model, item]
          break
        end
      end

      pk_rows = +""
      prepared_pk_ex_items.each_with_index do |item, excel_index|
        next if matched_excel_indexes[excel_index]
        pk_rows << mini_import_simple_excel_row_html(product_code, item.merge(qty: item[:excel_qty]), "PK")
      end
      matched_simple_rows.each do |model, item|
        pk_rows << mini_import_simple_matched_row_html(product_code, model, item)
      end
      pk_model_items.each { |model| pk_rows << mini_import_simple_model_row_html(product_code, model) }
      raw_model_items.each_with_index do |model, model_index|
        next if matched_raw_indexes[model_index]
        pk_rows << mini_import_simple_model_row_html(product_code, model, model[:sub])
      end
      pk_rows = mini_group_pk_rows_by_display(pk_rows)

      vl_rows = +""
      vl_ex_items.each do |ex|
        vl_rows << mini_import_simple_excel_row_html(product_code, {
          hw: ex[:hw_name],
          ma_vl_source: ex[:ma_vl_source] || ex[:ma_vat_lieu] || ex[:ma_vl],
          spec: ex[:spec],
          display_sub: respond_to?(:mini_excel_display_sub_text) ? mini_excel_display_sub_text(ex, ex[:hw_name]) : ex[:spec],
          note: ex[:ghi_chu],
          section: ex[:section],
          qty: ex[:qty]
        }, "VL")
      end
      vl_model_items.each { |model| vl_rows << mini_import_simple_model_row_html(product_code, model) }

      next if pk_rows.empty? && vl_rows.empty?

      rows << mini_group_header(product_code)
      unless pk_rows.empty?
        rows << mini_section_header("Ph\u1EE5 ki\u1EC7n")
        rows << pk_rows
      end
      unless vl_rows.empty?
        rows << mini_section_header("V\u1EADt li\u1EC7u")
        rows << vl_rows
      end
    end
    rows
  rescue => e
    puts "build_import_mini_rows_simple error: #{e.class}: #{e.message}" rescue nil
    ""
  end

  def self.build_import_mini_rows(process_model = true, load_excel = true)
    t_build_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if defined?(MINI_IMPORT_LIVE_ONLY) && MINI_IMPORT_LIVE_ONLY
      @mini_model_items_cache = nil
      @mini_excel_items_cache = nil
      @mini_model_row_index_key = nil
      @mini_excel_product_index_key = nil
      @mini_table_html_cache = nil
      @mini_pk_rows_html_cache = nil
      @mini_product_block_cache = nil
      @import_material_section_data_cache = nil
      @mini_loaded_from_snapshot_cache = false
    end
    ctx = mini_rows_prepare_context(process_model, load_excel)
    return "<tr><td colspan='5' class='empty'>Ch&#432;a x&#225;c &#273;&#7883;nh SP.</td></tr>" if ctx[:state] == :no_product
    return "<tr><td colspan='5' class='empty'>Loi du lieu mini import.</td></tr>" if ctx[:state] == :error
    products = ctx[:products]

    if ctx[:state] == :loading_excel
      model_rows = build_import_mini_model_only_rows(products)
      loading_row = "<tr><td colspan='5' class='empty'>Dang nap Excel... dang hien PK/VL trong model truoc.</td></tr>"
      return model_rows.empty? ? "<tr><td colspan='5' class='empty'>Dang nap Excel...</td></tr>" : loading_row + model_rows
    end
    if ctx[:state] == :no_excel
      if defined?(MINI_IMPORT_SIMPLE_LIST_MODE) && MINI_IMPORT_SIMPLE_LIST_MODE
        model_rows = build_import_mini_rows_simple(products)
        return model_rows unless model_rows.empty?
      end
      model_rows = build_import_mini_model_only_rows(products)
      return model_rows unless model_rows.empty?

      return "<tr><td colspan='5' class='empty'>Chua nap Excel. Bam nut EXCEL de nap du lieu.</td></tr>"
    end

    if defined?(MINI_IMPORT_SIMPLE_LIST_MODE) && MINI_IMPORT_SIMPLE_LIST_MODE
      rows = build_import_mini_rows_simple(products)
      return rows unless rows.empty?

      return "<tr><td colspan='5' class='empty'>Kh\u00F4ng t\u00ECm th\u1EA5y d\u00F2ng Excel/model cho SP #{html_escape(products.join(', '))}.</td></tr>"
    end

    cache_key = import_mini_table_cache_key(process_model, load_excel)
    cached = import_mini_table_cache_fetch(cache_key)
    return cached if cached

    rows = +""
    missing_products = []
    product_timings = []
    products.each do |product_code|
      t_product_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pk_rows = []
      vl_html = ""
      live_only = defined?(MINI_IMPORT_LIVE_ONLY) && MINI_IMPORT_LIVE_ONLY
      block_cache_key = live_only ? nil : mini_import_product_block_cache_key(product_code)
      cached_block = block_cache_key && respond_to?(:instance_cache_fetch) ? instance_cache_fetch(:@mini_product_block_cache, block_cache_key) : nil
      if cached_block.is_a?(Hash)
        pk_rows = Array(cached_block[:pk_rows])
        vl_html = cached_block[:vl_html].to_s
      else
        ex_items = mini_excel_items(product_code, false)
        pk_ex_items = ex_items.reject { |ex| ex[:kind].to_s == "VL" }
        vl_ex_items = ex_items.select { |ex| ex[:kind].to_s == "VL" }

        pk_html = build_import_mini_rows_for_product(product_code, pk_ex_items, true, [], nil, false, "PK")
        pk_rows, = mini_split_rows(pk_html)
        vl_html = mini_rows_material_sections_html(product_code, vl_ex_items)
        if block_cache_key && respond_to?(:instance_cache_store)
          instance_cache_store(:@mini_product_block_cache, block_cache_key, { pk_rows: pk_rows, vl_html: vl_html }, 300)
        end
      end

      if pk_rows.empty? && vl_html.empty?
        missing_products << product_code
        product_timings << [product_code, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_product_start) * 1000.0).round(1)]
        next
      end

      rows << mini_group_header(product_code)
      if pk_rows.any?
        rows << mini_section_header("Ph\u1EE5 ki\u1EC7n") if products.size > 1 || !vl_html.empty?
        rows << pk_rows.join
      end
      rows << vl_html
      product_timings << [product_code, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_product_start) * 1000.0).round(1)]
    end

    if rows.empty?
      names = missing_products.empty? ? products : missing_products
      return "<tr><td colspan='5' class='empty'>Kh\u00F4ng t\u00ECm th\u1EA5y d\u00F2ng Excel/model cho SP #{html_escape(names.join(', '))}.</td></tr>"
    end

    total_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_build_start) * 1000.0).round(1)
    if total_ms > 180.0
      top = product_timings.sort_by { |(_, ms)| -ms.to_f }.first(3).map { |code, ms| "#{code}:#{ms}ms" }.join(", ")
      puts "Mini rows slow: #{total_ms}ms | products=#{products.size} | top=#{top}"
    end
    import_mini_table_cache_store(cache_key, rows)
  end

  def self.build_import_mini_model_only_rows(products)
    rows = +""
    product_list = Array(products)
    product_list.each do |product_code|
      pk_html = build_import_mini_rows_for_product(product_code, [], true, [], nil, false, "PK")
      vl_html = build_import_mini_rows_for_product(product_code, [], true, [], nil, false, "VL")
      pk_rows, = mini_split_rows(pk_html)
      _, vl_rows = mini_split_rows(vl_html)
      next if pk_rows.empty? && vl_rows.empty?

      rows << mini_group_header(product_code)
      if pk_rows.any?
        rows << mini_section_header("Ph\u1EE5 ki\u1EC7n") if product_list.size > 1 || vl_rows.any?
        rows << pk_rows.join
      end
      if vl_rows.any?
        rows << mini_section_header("V\u1EADt li\u1EC7u")
        rows << vl_rows.join
      end
    end
    rows
  end

  # === mini_import_rows_product_helpers.rb ===
  # --- mini_import_rows_product_helpers.rb ---
# MH_Thongke - Mini Import PK row helper logic.


  def self.mini_pk_grouped_model_items(product_code)
    grouped = {}
    mini_model_items(product_code).select { |m| m[:kind].to_s != "VL" }.each do |m|
      key = "#{m[:kind].to_s}:#{import_name_norm(m[:name])}"
      grouped[key] ||= m.dup.merge(section: "", qty: 0.0, rows: [], ids: [])
      target = grouped[key]
      target[:qty] = target[:qty].to_f + m[:qty].to_f
      target[:unit] = m[:unit].to_s unless m[:unit].to_s.empty?
      target[:editable] = target[:editable] != false && m[:editable] != false
      target[:virtual] = !!target[:virtual] || !!m[:virtual]
      target[:virtual_key] ||= m[:virtual_key]
      target[:virtual_source] ||= m[:virtual_source]
      target[:rows] = Array(target[:rows]) + Array(m[:rows])
      target[:ids] = (Array(target[:ids]) + Array(m[:ids])).compact.uniq
    end
    grouped.values
  end

  def self.mini_pk_prepare_excel_item(ex, section_filter = nil)
    hw = ex[:hw_name].to_s
    spec = ex[:spec].to_s.strip
    section = ex[:section].to_s.strip
    section = section_filter.to_s.strip if section.empty? && !section_filter.to_s.strip.empty?
    target_name = respond_to?(:pk_update_target_name) ? pk_update_target_name(ex, nil) : import_display_name(hw, spec)
    {
      hw: hw,
      spec: spec,
      section: section,
      target_name: target_name,
      norm_hw: import_name_norm(hw),
      norm_target: import_name_norm(target_name),
      hw_safe: html_escape(hw),
      spec_safe: html_escape(ex[:spec]),
      section_safe: html_escape(section),
      note_safe: html_escape(ex[:ghi_chu]),
      target_safe: html_escape(target_name),
      display_sub_safe: html_escape(respond_to?(:mini_excel_display_sub_text) ? mini_excel_display_sub_text(ex, target_name) : mini_excel_sub_text(ex, target_name)),
      excel_qty: ex[:qty].to_i
    }
  end

  def self.mini_pk_match_model_item(product_code, model_items, item, matched_model_keys)
    hw = item[:hw]
    spec = item[:spec]
    target_name = item[:target_name]
    norm_hw = item[:norm_hw]
    norm_target = item[:norm_target]
    duplicate_used = false

    model = model_items.find do |m|
      model_norm = import_name_norm(m[:name])
      matched = model_norm == norm_target ||
                (spec.to_s.strip.empty? && model_norm == norm_hw) ||
                mini_pk_model_name_match?(product_code, m[:name], hw, target_name, spec)
      if matched && matched_model_keys.include?(mini_model_item_key(m))
        duplicate_used = true
        next false
      end
      matched
    end

    [model, target_name, duplicate_used]
  end

  # === mini_import_rows_product_rows.rb ===
  # --- mini_import_rows_product_rows.rb ---
# MH_Thongke - Mini Import PK row render helpers.


  def self.mini_import_pk_matched_row_html(product_code, product_safe, model, target_name, item)
    has_qty = model[:qty].to_f > 0 || model[:count].to_f > 0
    return "" if (model[:ids] || []).empty? && !model[:virtual] && !has_qty

    row_kind = model[:kind].to_s == "VL" ? "VL" : "PK"
    model_name_safe = html_escape(model[:name])
    ids_safe = html_escape((model[:ids] || []).join(","))
    spec = item[:spec]
    spec_safe = item[:spec_safe]
    section_safe = item[:section_safe]
    target_safe = html_escape(target_name)
    exact = import_name_norm(model[:name]) == import_name_norm(target_name)
    editable = model[:editable] != false && model[:kind] != "VL"
    qty = mini_qty_display(model)
    status = mini_import_matched_status_html(product_code, product_safe, row_kind, model, target_name, target_safe, spec, spec_safe, exact, editable)
    action = editable ? mini_import_delete_button_html(product_safe, model_name_safe, ids_safe) : ""

    # Display rule (PK):
    # - BIG (top): model value, or update-target after accepted update rule
    # - SMALL (bottom): raw excel display name (hw_name + spec), never auto-extended by model length
    accepted_action = if respond_to?(:mini_accept_rule_action)
      mini_accept_rule_action(product_code, row_kind, model[:name], target_name, spec).to_s
    else
      ""
    end
    excel_display_name = item[:target_name].to_s.strip
    sub_text = excel_display_name.empty? ? target_name.to_s.strip : excel_display_name
    sub_safe = html_escape(sub_text)
    accepted_update = accepted_action == "update" || accepted_action == "rename_update"
    model_is_target = import_name_norm(model[:name]) == import_name_norm(target_name)
    model_related_to_target = respond_to?(:mini_item_names_related?) && mini_item_names_related?(product_code, row_kind, model[:name], target_name)
    big_value_safe = if accepted_update && (model_is_target || !model_related_to_target)
      target_safe.to_s.empty? ? model_name_safe : target_safe
    else
      model_name_safe
    end

    mini_import_row_html(product_safe, row_kind, model_name_safe, ids_safe, [
      mini_import_cell_html(mini_import_name_input_html(product_safe, row_kind, model_name_safe, big_value_safe, target_safe, spec_safe, section_safe, sub_safe, !editable)),
      mini_import_cell_html(mini_import_note_input_html(product_safe, row_kind, item[:hw_safe], spec_safe, section_safe, item[:note_safe])),
      mini_import_cell_html(status, true),
      mini_import_cell_html(mini_import_qty_input_html(product_safe, model_name_safe, qty, spec_safe, section_safe), true),
      mini_import_cell_html(action)
    ], section_safe)
  end

  def self.mini_import_pk_excel_only_row_html(product_code, product_safe, item)
    row_kind = "PK"
    hw_safe = item[:hw_safe]
    spec = item[:spec]
    spec_safe = item[:spec_safe]
    section_safe = item[:section_safe]
    excel_status_key = resolve_mini_excel_only_status_key(product_code, row_kind, false, item[:hw], spec).to_s
    big_safe = hw_safe
    sub_safe = item[:display_sub_safe]
    if excel_status_key == "SPEC" || excel_status_key == "THIEU"
      big_safe = html_escape("---")
      sub_safe = item[:target_safe].to_s.empty? ? item[:display_sub_safe] : item[:target_safe]
    end
    status_cell = mini_import_excel_only_status_html(product_code, product_safe, false, item[:hw], hw_safe, spec, spec_safe, "PK")
    action_cell = mini_import_delete_button_html(product_safe, hw_safe, "", "PK", spec_safe, :excel)

    mini_import_row_html(product_safe, row_kind, item[:target_safe], "", [
      mini_import_cell_html(mini_import_name_input_html(product_safe, row_kind, hw_safe, big_safe, "", "", section_safe, sub_safe, true)),
      mini_import_cell_html(mini_import_note_input_html(product_safe, row_kind, hw_safe, spec_safe, section_safe, item[:note_safe])),
      mini_import_cell_html(status_cell, true),
      mini_import_cell_html(mini_import_qty_input_html(product_safe, hw_safe, item[:excel_qty], spec_safe, section_safe), true),
      mini_import_cell_html(action_cell)
    ], section_safe)
  end

  def self.mini_import_pk_model_only_row_html(product_code, product_safe, model)
    # Allow render when:
    # - model has entity ids (live scan)
    # - OR model is virtual (auto-generated like LED)
    # - OR model has quantity > 0 (loaded from JSON snapshot, entities stripped)
    has_qty = model[:qty].to_f > 0 || model[:count].to_f > 0
    return "" if (model[:ids] || []).empty? && !model[:virtual] && !has_qty

    name_safe = html_escape(model[:name])
    ids_safe = html_escape((model[:ids] || []).join(","))
    kind = model[:kind].to_s.empty? ? "PK" : model[:kind]
    row_kind = kind.to_s == "VL" ? "VL" : "PK"
    editable = model[:editable] != false && kind != "VL"
    action = editable ? mini_import_delete_button_html(product_safe, name_safe, ids_safe) : ""
    qty = mini_qty_display(model)
    model_status_key = resolve_mini_model_only_status_key(product_code, row_kind, model[:name]).to_s
    sub_safe = model_status_key == "NO_SPEC" ? html_escape("---") : ""
    status = mini_import_model_only_status_html(product_code, product_safe, row_kind, model[:name], name_safe)

    mini_import_row_html(product_safe, row_kind, name_safe, ids_safe, [
      mini_import_cell_html(mini_import_name_input_html(product_safe, row_kind, name_safe, name_safe, "", "", "", sub_safe)),
      mini_import_cell_html(mini_import_note_input_html(product_safe, row_kind, name_safe)),
      mini_import_cell_html(status, true),
      mini_import_cell_html(mini_import_qty_input_html(product_safe, name_safe, qty), true),
      mini_import_cell_html(action)
    ])
  end

  # === mini_import_rows_product.rb ===
  # --- mini_import_rows_product.rb ---
# MH_Thongke - Mini Import per-product row builder.


  def self.mini_import_pk_rows_cache_eligible?(row_kind_filter, include_unmatched_model, matched_model_keys, section_filter, strict_section_filter)
    row_kind_filter.to_s.upcase == "PK" &&
      include_unmatched_model &&
      (matched_model_keys.nil? || matched_model_keys.empty?) &&
      section_filter.to_s.strip.empty? &&
      !strict_section_filter
  rescue
    false
  end

  def self.mini_import_pk_rows_cache_key(product_code, ex_items_raw)
    ex_sig = Array(ex_items_raw).map { |ex|
      [ex[:ma_sp], ex[:kind], ex[:hw_name], ex[:spec], ex[:section], ex[:ghi_chu], ex[:qty]].join("\u001F")
    }.join("\u001E").hash
    [
      product_code_exact(product_code),
      respond_to?(:import_mini_data_signature) ? import_mini_data_signature : import_mini_refresh_signature,
      ex_sig
    ].join("::")
  rescue
    nil
  end

  # Group PK rows by display name shown in UI:
  # - Prefer BIG line (name-input value)
  # - If BIG is empty/"---", fallback to SMALL line (spec-text)
  # Keep first row's behavior/status/actions, only sum qty into that row.
  def self.mini_group_pk_rows_by_display(rows_html)
    rows = rows_html.to_s.scan(/<tr\b.*?<\/tr>/m)
    return rows_html if rows.size <= 1

    groups = {}
    order = []
    rows.each_with_index do |row_html, idx|
      big_text = row_html[/class='name-input'[^>]*\bvalue='([^']*)'/m, 1].to_s.strip
      sub_text = row_html[/<span class='spec-text'>(.*?)<\/span>/m, 1].to_s.strip
      key_text = (!big_text.empty? && big_text != "---") ? big_text : sub_text
      key_norm = import_name_norm(key_text)
      key = key_norm.empty? ? "__row_#{idx}" : key_norm

      qty_text = row_html[/class='qty-input'[^>]*\bvalue='([^']*)'/m, 1].to_s.strip
      qty_num = qty_text.gsub(",", ".").to_f

      unless groups[key]
        groups[key] = { first_row: row_html, qty_sum: 0.0, count: 0 }
        order << key
      end
      groups[key][:qty_sum] += qty_num
      groups[key][:count] += 1
    end

    out = +""
    order.each do |key|
      group = groups[key]
      row_html = group[:first_row]
      if group[:count].to_i > 1
        sum = group[:qty_sum].to_f
        qty_display = if (sum - sum.round).abs <= 0.001
          ui_count_text(sum.round)
        else
          ui_number_text(sum.round(2))
        end
        row_html = row_html.sub(/(class='qty-input'[^>]*\bvalue=')([^']*)(')/m, "\\1#{qty_display}\\3")
      end
      out << row_html
    end
    out
  rescue
    rows_html
  end

  def self.build_import_mini_rows_for_product(product_code, ex_items_raw_override = nil, include_unmatched_model = true, matched_model_keys = nil, section_filter = nil, strict_section_filter = false, row_kind_filter = nil)
    product_safe = html_escape(product_code)
    ex_items_raw = ex_items_raw_override || mini_excel_items(product_code, false)
    row_kind_filter = row_kind_filter.to_s.upcase

    if row_kind_filter == "VL"
      data_rows = build_import_material_data_rows_for_product(product_code, ex_items_raw, include_unmatched_model, matched_model_keys, section_filter, strict_section_filter)
      return render_import_mini_material_rows(data_rows)
    end

    ex_items_raw = ex_items_raw.reject { |ex| ex[:kind].to_s == "VL" }.map do |ex|
      copy = ex.dup
      copy[:ten_sp] = ""
      copy["ten_sp"] = ""
      copy
    end
    cache_key = nil
    live_only = defined?(MINI_IMPORT_LIVE_ONLY) && MINI_IMPORT_LIVE_ONLY
    if !live_only && mini_import_pk_rows_cache_eligible?(row_kind_filter, include_unmatched_model, matched_model_keys, section_filter, strict_section_filter)
      cache_key = mini_import_pk_rows_cache_key(product_code, ex_items_raw)
      if cache_key && respond_to?(:instance_cache_fetch)
        cached = instance_cache_fetch(:@mini_pk_rows_html_cache, cache_key)
        return cached unless cached.nil?
      end
    end
    model_items = mini_pk_grouped_model_items(product_code)
    return "" if ex_items_raw.empty? && model_items.empty?

    rows = +""
    matched_model_keys ||= []

    mini_group_excel_items(ex_items_raw, true).each do |ex|
      item = mini_pk_prepare_excel_item(ex, section_filter)
      model, target_name, duplicate_used = mini_pk_match_model_item(product_code, model_items, item, matched_model_keys)
      # Keep matched model when it has qty > 0 (JSON snapshot strips entity ids).
      cand_qty = model && (model[:qty].to_f > 0 || model[:count].to_f > 0)
      model = nil if model && (model[:ids] || []).empty? && !model[:virtual] && !cand_qty
      next if duplicate_used && !model

      if model
        model_key = mini_model_item_key(model)
        matched_model_keys << model_key unless matched_model_keys.include?(model_key)
        rows << mini_import_pk_matched_row_html(product_code, product_safe, model, target_name, item)
      else
        rows << mini_import_pk_excel_only_row_html(product_code, product_safe, item)
      end
    end

    if include_unmatched_model
      model_items.each do |model|
        key = mini_model_item_key(model)
        next if matched_model_keys.include?(key)

        row_html = mini_import_pk_model_only_row_html(product_code, product_safe, model)
        next if row_html.empty?

        rows << row_html
        matched_model_keys << key unless matched_model_keys.include?(key)
      end
    end

    rows = mini_group_pk_rows_by_display(rows)

    if !live_only && cache_key && respond_to?(:instance_cache_store)
      instance_cache_store(:@mini_pk_rows_html_cache, cache_key, rows, 250)
    end
    rows
  end
end
