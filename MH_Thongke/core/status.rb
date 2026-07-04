# encoding: utf-8
# MH_Thongke - shared status normalization helpers.

module MH_Thongke
  STATUS_PRIORITY = {
    "" => 0,
    "OK" => 1,
    "GHOST" => 2,
    "NO_SPEC" => 3,
    "SPEC" => 4,
    "THIEU" => 5,
    "DU" => 6,
    "UPDATE" => 7
  }.freeze unless defined?(STATUS_PRIORITY)

  def self.status_key(value)
    norm = cached_norm(fix_vietnamese_mojibake(value).to_s)
    case norm
    when "", nil
      ""
    when "ok", "khop", "khop."
      "OK"
    when "update", "cap nhat"
      "UPDATE"
    when "spec"
      "SPEC"
    when "nospec", "no spec", "no_spec"
      "NO_SPEC"
    when "ghost"
      "GHOST"
    when "thieu"
      "THIEU"
    when "du"
      "DU"
    else
      text = value.to_s.strip.upcase
      text.empty? ? "" : text
    end
  rescue
    value.to_s.strip.upcase
  end

  def self.status_priority(value)
    STATUS_PRIORITY[status_key(value)].to_i
  rescue
    0
  end

  # Canonical status string used across Mini/HUD/Main/Project reports.
  def self.status_text(value, fallback = "")
    key = status_key(value)
    key.to_s.empty? ? fallback.to_s : key
  rescue
    fallback.to_s
  end

  def self.pk_rule_ok?(product_code, model_name, target_name, spec = "")
    return false unless respond_to?(:mini_accept_rule_action)

    action = mini_accept_rule_action(product_code, "PK", model_name, target_name, spec).to_s
    ["manual_match", "update", "rename_update", "keep"].include?(action)
  rescue
    false
  end

  def self.pk_lineage_same?(product_code, model_name, target_name)
    return false unless respond_to?(:mini_name_lineage_relation)
    mini_name_lineage_relation(product_code, "PK", model_name, target_name) == :same
  rescue
    false
  end

  def self.pk_match_ok?(product_code, model_name, target_name, spec = "")
    return false if model_name.to_s.strip.empty? || target_name.to_s.strip.empty?
    model_norm = respond_to?(:import_name_norm) ? import_name_norm(model_name) : model_name.to_s.strip.downcase
    target_norm = respond_to?(:import_name_norm) ? import_name_norm(target_name) : target_name.to_s.strip.downcase
    return true if !model_norm.empty? && model_norm == target_norm

    pk_rule_ok?(product_code, model_name, target_name, spec)
  rescue
    false
  end

  def self.material_rule_ok?(product_code, model_name, target_name, spec = "")
    if respond_to?(:mini_accept_rule_ok?)
      mini_accept_rule_ok?(product_code, "VL", model_name, target_name, spec)
    elsif respond_to?(:mini_accept_rule?)
      mini_accept_rule?(product_code, "VL", model_name, target_name, spec)
    else
      false
    end
  rescue
    false
  end

  # Shared resolver for Mini/HUD material rows.
  def self.material_row_status_key(row)
    product_code = row[:product_code].to_s
    case row[:type]
    when :matched
      return "OK" if row[:exact]
      return "OK" if material_rule_ok?(product_code, row[:name], row[:target_name], row[:spec])
      "NO_SPEC"
    when :related
      "OK"
    when :excel_only
      if respond_to?(:mini_accept_rule?) && mini_accept_rule?(product_code, "VL", "", row[:hw], row[:spec])
        "OK"
      else
        "SPEC"
      end
    when :model_only
      return "OK" if respond_to?(:material_model_only_has_excel_spec?) && material_model_only_has_excel_spec?(product_code, row[:name])
      if respond_to?(:mini_accept_rule?) && mini_accept_rule?(product_code, "VL", row[:name], "", "")
        "OK"
      else
        "NO_SPEC"
      end
    else
      "NO_SPEC"
    end
  rescue
    "NO_SPEC"
  end

  def self.project_pk_blocked?(pk_items)
    Array(pk_items).any? { |item| respond_to?(:report_blocked_note?) && report_blocked_note?(item["ghi_chu"]) }
  rescue
    false
  end

  def self.project_pk_with_order_count(pk_items)
    Array(pk_items).count { |item| !normalize_order_date(item["ngay_dat"]).to_s.strip.empty? }
  rescue
    0
  end

  def self.project_dmvt_status_text(pk_items)
    items = Array(pk_items)
    return "Xong định mức" if items.empty?
    return "Thiếu thông tin" if project_pk_blocked?(items)
    done = project_pk_with_order_count(items)
    done == items.size ? "Xong định mức" : "Đang định mức"
  rescue
    "Đang định mức"
  end

  def self.project_cnc_pending_layer_text?(value)
    text = if respond_to?(:cached_norm)
      cached_norm(value).to_s
    else
      value.to_s.downcase
    end
    text.gsub(/\s+/, "_") == "chua_cat"
  rescue
    false
  end

  def self.project_cnc_pending_items?(items)
    Array(items).any? do |item|
      next false unless item.is_a?(Hash)

      layer = item["layer"] || item[:layer]
      tags = item["layer_tags"] || item[:layer_tags]
      project_cnc_pending_layer_text?(layer) ||
        Array(tags).any? { |tag| project_cnc_pending_layer_text?(tag) }
    end
  rescue
    false
  end

  def self.project_cnc_status_text(has_nesting, product_code, vl_items, blocked = false, cnc_items = nil)
    return "Vướng thông tin" if blocked
    return "Đang làm CNC" if project_cnc_pending_items?(cnc_items)
    return "Đang làm CNC" unless has_nesting
    return "Vướng thông tin" if (respond_to?(:product_code_valid?) ? product_code_valid?(product_code) : product_code.to_s =~ /\A[A-Z]+\d+/i) && Array(vl_items).empty?
    "Xong CNC"
  rescue
    "Đang làm CNC"
  end
end
