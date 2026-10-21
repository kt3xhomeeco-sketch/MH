# encoding: utf-8
# MH_Thongke - Material HUD render helpers.

module MH_Thongke
  def self.material_hud_group_header(product_code, title = nil)
    "<tr class='hud-product-row'><td colspan='3'>#{html_escape(title || mini_import_title(product_code, false))}</td></tr>"
  end

  def self.material_hud_status_key(status)
    case status_key(status)
    when "OK" then "OK"
    when "SPEC" then "SPEC"
    when "UPDATE" then "UPDATE"
    when "THIEU" then "THIEU"
    else "NO SPEC"
    end
  rescue
    "NO SPEC"
  end

  def self.material_hud_status_badge(status)
    case material_hud_status_key(status)
    when "OK"
      "<span class='hud-status status-ok'>&#10003;</span>"
    when "SPEC"
      "<span class='hud-status status-spec'>SPEC</span>"
    when "UPDATE"
      "<span class='hud-status status-update'>UPDATE</span>"
    when "THIEU"
      "<span class='hud-status status-nospec'>THIEU</span>"
    else
      "<span class='hud-status status-nospec'>NO SPEC</span>"
    end
  end

  def self.material_hud_status_draw_text(status)
    material_hud_status_key(status)
  end

  def self.material_hud_status_draw_style(status)
    text = material_hud_status_draw_text(status)
    if const_defined?(:HUD_STATUS_DRAW_STYLES)
      HUD_STATUS_DRAW_STYLES[text] || [HUD_COLOR_STATUS_MISSING, HUD_COLOR_WHITE, text]
    else
      [Sketchup::Color.new(192, 57, 43, 235), Sketchup::Color.new(255, 255, 255), text]
    end
  rescue
    [Sketchup::Color.new(192, 57, 43, 235), Sketchup::Color.new(255, 255, 255), "NO SPEC"]
  end

  def self.material_hud_row(product_code, name, note, status, sub_text = nil)
    product_safe = html_escape(product_code)
    name_safe = html_escape(name)
    note_safe = html_escape(note)
    sub = sub_text.to_s.strip
    same_text = import_name_norm(sub) == import_name_norm(name)
    same_material = !sub.empty? && material_code_norm(sub) == material_code_norm(name)
    sub_html = sub.empty? || same_text || same_material ? "" : "<span class='hud-sub'>#{html_escape(sub)}</span>"
    [
      "<tr class='hud-row' data-product='#{product_safe}'>",
      "<td><span class='hud-name'>#{name_safe}</span>#{sub_html}</td>",
      "<td>#{note_safe}</td>",
      "<td class='hud-status-cell'>#{material_hud_status_badge(status)}</td>",
      "</tr>"
    ].join
  end

  def self.material_hud_entry(name, note, status, target = "")
    {
      type: :item,
      name: name.to_s,
      note: note.to_s,
      status: material_hud_status_draw_text(status),
      target: target.to_s
    }
  rescue
    { type: :item, name: "", note: "", status: "NO SPEC", target: "" }
  end

  # VL display rule:
  # - ALL statuses (OK / UPDATE / SPEC / THIEU / NO_SPEC):
  #   BIG = ma_vl_source (Excel Ma_vat_lieu), SMALL = spec
  def self.material_hud_name_lines_from_import_data(row)
    excel = row[:excel].is_a?(Hash) ? row[:excel] : {}

    excel_ma_vl = row[:ma_vl_source].to_s.strip
    excel_ma_vl = (excel[:ma_vl_source] || excel["ma_vl_source"]).to_s.strip if excel_ma_vl.empty?
    excel_ma_vl = row[:target_name].to_s.strip if excel_ma_vl.empty?
    excel_ma_vl = row[:hw].to_s.strip if excel_ma_vl.empty?
    if excel_ma_vl.empty?
      name_text = row[:name].to_s.strip
      excel_ma_vl = respond_to?(:material_code_display) ? material_code_display(name_text) : name_text
    end

    spec_text = row[:spec].to_s.strip
    spec_text = (excel[:spec] || excel["spec"]).to_s.strip if spec_text.empty?
    spec_text = row[:display_sub].to_s.strip if spec_text.empty?

    top = excel_ma_vl.empty? ? "---" : excel_ma_vl
    sub = spec_text.empty? ? "" : spec_text
    [top, sub]
  rescue
    [row[:name].to_s, row[:display_sub].to_s]
  end

  def self.material_hud_row_from_import_data(row)
    return "" if respond_to?(:mini_import_material_row_renderable?) && !mini_import_material_row_renderable?(row)

    top_name, sub_text = material_hud_name_lines_from_import_data(row)
    material_hud_row(row[:product_code], top_name, row[:note], row[:status], sub_text)
  rescue
    ""
  end

  def self.material_hud_entry_from_import_data(row)
    return nil if respond_to?(:mini_import_material_row_renderable?) && !mini_import_material_row_renderable?(row)

    top_name, sub_text = material_hud_name_lines_from_import_data(row)
    material_hud_entry(top_name, row[:note], row[:status], sub_text)
  rescue
    nil
  end
end
