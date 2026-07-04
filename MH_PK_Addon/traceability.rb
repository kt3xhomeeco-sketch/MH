# encoding: utf-8
# MH_PK_Addon — ghi truy vet excel-match / rename-history.
# Uu tien API chinh chu cua MH_Thongke (attribute_history_processor); fallback ghi truc tiep
# cung schema khi MH_Thongke vang mat de MH_Thongke doc duoc ve sau.

require 'json'
require 'time'

module MH_PK_Addon
  TRACE_DICT = 'MH_Thongke'.freeze
  TRACE_HISTORY_LIMIT = 10

  def self.trace_time_iso
    Time.now.iso8601
  rescue
    Time.now.to_s
  end

  def self.trace_norm_token(value)
    search_text(value).upcase.gsub(/[^A-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
  rescue
    value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
  end

  def self.trace_build_excel_match_key(product_code:, kind:, excel_name:, spec: '', material_code: '', section: '')
    if defined?(MH_Thongke) && MH_Thongke.respond_to?(:build_excel_match_key)
      return MH_Thongke.build_excel_match_key(
        product_code: product_code, kind: kind, excel_name: excel_name,
        spec: spec, material_code: material_code, section: section
      )
    end

    [product_code, kind, excel_name, spec, material_code, section]
      .map { |part| trace_norm_token(part) }
      .reject(&:empty?)
      .join('|')
  rescue
    ''
  end

  def self.trace_append_history(entity, key, record, limit = TRACE_HISTORY_LIMIT)
    raw = entity.get_attribute(TRACE_DICT, key).to_s.strip
    list = raw.empty? ? [] : (JSON.parse(raw) rescue [])
    list = [] unless list.is_a?(Array)
    list << record.reject { |_, value| value.to_s.empty? }
    list = list.last(limit)
    entity.set_attribute(TRACE_DICT, key, JSON.generate(list))
    list
  rescue
    nil
  end

  def self.trace_fallback_excel_match(entity, meta)
    excel_name = meta[:excel_name].to_s.strip
    match_key = meta[:excel_key].to_s.strip
    if match_key.empty?
      match_key = trace_build_excel_match_key(
        product_code: meta[:product].to_s, kind: meta[:kind].to_s, excel_name: excel_name,
        spec: meta[:spec].to_s, material_code: meta[:material_code].to_s, section: meta[:section].to_s
      )
    end
    at = trace_time_iso
    entity.set_attribute(TRACE_DICT, 'excel-match-key', match_key)
    entity.set_attribute(TRACE_DICT, 'excel-match-name', excel_name)
    entity.set_attribute(TRACE_DICT, 'excel-match-spec', meta[:spec].to_s)
    entity.set_attribute(TRACE_DICT, 'excel-match-kind', meta[:kind].to_s)
    entity.set_attribute(TRACE_DICT, 'excel-match-section', meta[:section].to_s)
    entity.set_attribute(TRACE_DICT, 'excel-match-source', meta[:source].to_s)
    entity.set_attribute(TRACE_DICT, 'excel-match-at', at)
    trace_append_history(entity, 'excel-match-history', {
      'key' => match_key, 'name' => excel_name, 'spec' => meta[:spec].to_s,
      'kind' => meta[:kind].to_s, 'product' => meta[:product].to_s,
      'section' => meta[:section].to_s, 'source' => meta[:source].to_s,
      'action' => meta[:action].to_s, 'at' => at
    })
    match_key
  rescue
    ''
  end

  def self.trace_fallback_rename(entity, from_name, to_name, meta)
    from_text = from_name.to_s.strip
    to_text = to_name.to_s.strip
    return false if to_text.empty?

    at = trace_time_iso
    original = entity.get_attribute(TRACE_DICT, 'original-name').to_s.strip
    entity.set_attribute(TRACE_DICT, 'original-name', from_text) if original.empty? && !from_text.empty?
    entity.set_attribute(TRACE_DICT, 'current-name', to_text)
    entity.set_attribute(TRACE_DICT, 'last-rename-from', from_text)
    entity.set_attribute(TRACE_DICT, 'last-rename-to', to_text)
    entity.set_attribute(TRACE_DICT, 'last-rename-at', at)
    trace_append_history(entity, 'rename-history', {
      'from' => from_text, 'to' => to_text, 'kind' => meta[:kind].to_s,
      'product' => meta[:product].to_s, 'section' => meta[:section].to_s,
      'source' => meta[:source].to_s, 'action' => meta[:action].to_s,
      'at' => at, 'excel_key' => meta[:excel_key].to_s
    })
    true
  rescue
    false
  end

  def self.trace_excel_match_meta(data, action)
    {
      excel_name: data[:name].to_s.strip,
      spec: data[:spec].to_s.strip,
      kind: 'PK',
      product: product_code_base(data[:product_code]),
      section: data[:section].to_s.strip,
      source: 'pk_addon',
      action: action.to_s,
      excel_key: data[:excel_key].to_s.strip
    }
  end

  # Virtual key cho cac nhom phu kien dac biet (nguon led, thanh nhom led, suot ao/bas treo,
  # phao chi, tay nam) — de MH_Thongke gom nhom va truy vet (classifier cua MH_Thongke).
  def self.trace_record_virtual(marker, data)
    return unless defined?(MH_Thongke)
    return unless MH_Thongke.respond_to?(:record_entity_virtual_key) && MH_Thongke.respond_to?(:classify_virtual_group)

    label = display_name(data[:name], data[:spec])
    group = MH_Thongke.classify_virtual_group(label)
    return if group.to_s == 'VIRTUAL'

    MH_Thongke.record_entity_virtual_key(
      marker,
      product_code: product_code_base(data[:product_code]),
      name: label,
      spec: data[:spec].to_s,
      source: 'pk_addon',
      group: group
    )
  rescue => e
    puts "MH_PK_Addon trace_record_virtual error: #{e.class}: #{e.message}" rescue nil
    nil
  end

  # Goi ngay sau create_marker_group, trong cung start_operation.
  def self.trace_record_add(marker, data)
    return unless live_entity?(marker)

    label = display_name(data[:name], data[:spec])
    original = marker.get_attribute(TRACE_DICT, 'original-name').to_s.strip
    marker.set_attribute(TRACE_DICT, 'original-name', label) if original.empty?
    marker.set_attribute(TRACE_DICT, 'current-name', label)

    meta = trace_excel_match_meta(data, 'add')
    match_ok = false
    if defined?(MH_Thongke) && MH_Thongke.respond_to?(:record_entity_excel_match)
      match_ok = MH_Thongke.record_entity_excel_match(marker, meta)
    end
    trace_fallback_excel_match(marker, meta) if match_ok == false || match_ok.nil?
    trace_record_virtual(marker, data)
  rescue => e
    puts "MH_PK_Addon trace_record_add error: #{e.class}: #{e.message}" rescue nil
    nil
  end

  # Goi ngay sau rename_marker, trong cung start_operation.
  def self.trace_record_rename(marker, from_label, data)
    return unless live_entity?(marker)

    to_label = display_name(data[:name], data[:spec])
    meta = trace_excel_match_meta(data, 'rename')
    rename_meta = {
      kind: 'PK',
      product: meta[:product],
      section: meta[:section],
      source: 'pk_addon',
      action: 'rename',
      excel_key: meta[:excel_key]
    }
    ok = false
    if defined?(MH_Thongke) && MH_Thongke.respond_to?(:record_entity_rename_history)
      ok = MH_Thongke.record_entity_rename_history(marker, from_label, to_label, rename_meta)
    end
    # recorder fail (tra false) → tu ghi fallback de KHONG mat lich su
    trace_fallback_rename(marker, from_label, to_label, rename_meta) unless ok

    # Rename la override cua user, khong cap nhat lai excel-match chinh.
    # Neu ghi excel-match bang cung excel_key, lan add Excel tiep theo co the sync nguoc
    # va keo ten manual truoc do ve ten Excel.
    trace_record_virtual(marker, data)
  rescue => e
    puts "MH_PK_Addon trace_record_rename error: #{e.class}: #{e.message}" rescue nil
    nil
  end
end
