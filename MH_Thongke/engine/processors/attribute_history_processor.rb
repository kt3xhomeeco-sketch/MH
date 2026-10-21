# encoding: utf-8
# MH_Thongke — attribute history and virtual key helpers.
require 'json'
require 'time'

module MH_Thongke
  ATTR_HISTORY_DICT = "MH_Thongke" unless defined?(ATTR_HISTORY_DICT)
  ATTR_HISTORY_LIMIT = 10 unless defined?(ATTR_HISTORY_LIMIT)

  def self.mh_attr_time_iso
    Time.now.iso8601
  rescue
    Time.now.to_s
  end

  def self.mh_attr_live_entity?(entity)
    entity && !(entity.respond_to?(:deleted?) && entity.deleted?)
  rescue
    false
  end

  def self.mh_attr_json(entity, key, fallback = [])
    return fallback unless mh_attr_live_entity?(entity)

    raw = entity.get_attribute(ATTR_HISTORY_DICT, key).to_s.strip
    return fallback if raw.empty?

    JSON.parse(raw)
  rescue
    fallback
  end

  def self.mh_attr_write_json(entity, key, value)
    return false unless mh_attr_live_entity?(entity)

    entity.set_attribute(ATTR_HISTORY_DICT, key, JSON.generate(value))
    true
  rescue => e
    puts "mh_attr_write_json error: #{e.class}: #{e.message}" rescue nil
    false
  end

  def self.mh_attr_append_history(entity, key, record, limit = ATTR_HISTORY_LIMIT)
    list = mh_attr_json(entity, key, [])
    list = [] unless list.is_a?(Array)
    list << record
    list = list.last(limit.to_i > 0 ? limit.to_i : ATTR_HISTORY_LIMIT)
    mh_attr_write_json(entity, key, list)
    list
  end

  def self.mh_attr_norm_token(value)
    text = value.to_s.strip
    text = import_name_norm(text) if respond_to?(:import_name_norm)
    text = text.upcase
    text.gsub(/[^A-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  rescue
    value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  def self.build_excel_match_key(product_code:, kind:, excel_name:, spec: "", material_code: "", section: "")
    [
      product_code,
      kind,
      excel_name,
      spec,
      material_code,
      section
    ].map { |part| mh_attr_norm_token(part) }
     .reject(&:empty?)
     .join("|")
  end

  def self.record_entity_rename_history(entity, from_name, to_name, metadata = {})
    return false unless mh_attr_live_entity?(entity)

    from_text = fix_vietnamese_mojibake(from_name).to_s.strip rescue from_name.to_s.strip
    to_text = fix_vietnamese_mojibake(to_name).to_s.strip rescue to_name.to_s.strip
    return false if to_text.empty?

    at = mh_attr_time_iso
    original = entity.get_attribute(ATTR_HISTORY_DICT, "original-name").to_s.strip
    entity.set_attribute(ATTR_HISTORY_DICT, "original-name", from_text) if original.empty? && !from_text.empty?
    entity.set_attribute(ATTR_HISTORY_DICT, "current-name", to_text)
    entity.set_attribute(ATTR_HISTORY_DICT, "last-rename-from", from_text)
    entity.set_attribute(ATTR_HISTORY_DICT, "last-rename-to", to_text)
    entity.set_attribute(ATTR_HISTORY_DICT, "last-rename-at", at)

    record = {
      "from" => from_text,
      "to" => to_text,
      "kind" => metadata[:kind].to_s,
      "product" => metadata[:product].to_s,
      "section" => metadata[:section].to_s,
      "source" => metadata[:source].to_s,
      "action" => metadata[:action].to_s,
      "at" => at,
      "excel_key" => metadata[:excel_key].to_s
    }.reject { |_, value| value.to_s.empty? }

    mh_attr_append_history(entity, "rename-history", record)
    true
  rescue => e
    puts "record_entity_rename_history error: #{e.class}: #{e.message}" rescue nil
    false
  end

  def self.record_entity_excel_match(entity, metadata = {})
    return false unless mh_attr_live_entity?(entity)

    excel_name = metadata[:excel_name].to_s.strip
    excel_name = metadata[:target_name].to_s.strip if excel_name.empty?
    excel_name = metadata[:to_name].to_s.strip if excel_name.empty?
    match_key = metadata[:excel_key].to_s.strip
    if match_key.empty?
      match_key = build_excel_match_key(
        product_code: metadata[:product].to_s,
        kind: metadata[:kind].to_s,
        excel_name: excel_name,
        spec: metadata[:spec].to_s,
        material_code: metadata[:material_code].to_s,
        section: metadata[:section].to_s
      )
    end

    at = mh_attr_time_iso
    entity.set_attribute(ATTR_HISTORY_DICT, "excel-match-key", match_key)
    entity.set_attribute(ATTR_HISTORY_DICT, "excel-match-name", excel_name)
    entity.set_attribute(ATTR_HISTORY_DICT, "excel-match-spec", metadata[:spec].to_s)
    entity.set_attribute(ATTR_HISTORY_DICT, "excel-match-kind", metadata[:kind].to_s)
    entity.set_attribute(ATTR_HISTORY_DICT, "excel-match-section", metadata[:section].to_s)
    entity.set_attribute(ATTR_HISTORY_DICT, "excel-match-source", metadata[:source].to_s)
    entity.set_attribute(ATTR_HISTORY_DICT, "excel-match-at", at)

    record = {
      "key" => match_key,
      "name" => excel_name,
      "spec" => metadata[:spec].to_s,
      "kind" => metadata[:kind].to_s,
      "product" => metadata[:product].to_s,
      "section" => metadata[:section].to_s,
      "source" => metadata[:source].to_s,
      "action" => metadata[:action].to_s,
      "at" => at
    }.reject { |_, value| value.to_s.empty? }

    mh_attr_append_history(entity, "excel-match-history", record)
    match_key
  rescue => e
    puts "record_entity_excel_match error: #{e.class}: #{e.message}" rescue nil
    false
  end

  def self.virtual_anchor_for_entity(entity)
    return "" unless mh_attr_live_entity?(entity)

    if entity.respond_to?(:persistent_id)
      pid = entity.persistent_id rescue nil
      return pid.to_s if pid && pid.to_i > 0
    end
    entity.respond_to?(:entityID) ? entity.entityID.to_s : ""
  rescue
    ""
  end

  def self.classify_virtual_group(name)
    norm = import_name_norm(name) rescue name.to_s.downcase
    return "LED_POWER" if norm.include?("led") && (norm.include?("nguon") || norm.include?("driver") || norm.include?("adapter"))
    return "LED_PROFILE" if norm.include?("led") && (norm.include?("thanh nhom") || norm.include?("nhom led") || norm.include?("ray led"))
    return "SUOT_AO" if norm.include?("suot ao") || norm.include?("suot treo ao")
    return "PHAO_CHI" if norm.include?("phao")
    return "TAY_NAM" if norm.include?("tay nam")
    return "EXCEL_ONLY" if norm.include?("excel only") || norm.include?("excel_only")

    "VIRTUAL"
  end

  def self.virtual_key(product_code:, group:, spec: "", source: "", anchor: "", kind: "PKV")
    parts = [
      mh_attr_norm_token(product_code),
      mh_attr_norm_token(kind),
      mh_attr_norm_token(group),
      mh_attr_norm_token(spec)
    ].reject(&:empty?)
    parts << "SOURCE:#{mh_attr_norm_token(source)}" unless source.to_s.strip.empty?
    parts << "ANCHOR:#{mh_attr_norm_token(anchor)}" unless anchor.to_s.strip.empty?
    parts.join("|")
  end

  def self.record_entity_virtual_key(entity, product_code:, name:, spec: "", source: "", group: nil)
    return false unless mh_attr_live_entity?(entity)

    virtual_group = group.to_s.strip.empty? ? classify_virtual_group(name) : group.to_s.strip
    anchor = virtual_anchor_for_entity(entity)
    key = virtual_key(
      product_code: product_code,
      group: virtual_group,
      spec: spec.to_s.strip.empty? ? name.to_s : spec.to_s,
      source: source.to_s.strip.empty? ? "MODEL" : source.to_s,
      anchor: anchor
    )
    entity.set_attribute(ATTR_HISTORY_DICT, "virtual-key", key)
    entity.set_attribute(ATTR_HISTORY_DICT, "virtual-source", source.to_s)
    entity.set_attribute(ATTR_HISTORY_DICT, "virtual-anchor", anchor)
    key
  rescue => e
    puts "record_entity_virtual_key error: #{e.class}: #{e.message}" rescue nil
    false
  end
end
