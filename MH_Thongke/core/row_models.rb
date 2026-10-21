# encoding: utf-8
# MH_Thongke — Row Data Models
# Tach biet live data (entity refs, computed fields) khoi snapshot data (serializable).
# Converter ro rang giua 2 dang.

module MH_Thongke

  # Fields chi ton tai trong live data (khong bao gio serialize)
  LIVE_ONLY_FIELDS = %i[
    stat_entities entities length_items
    sel_count sel_length sel_len_mm
    _resolved_unit _resolved_qty _length_display_unit _data_key
    original_indices back_diff
  ].freeze

  # Fields duoc persist vao snapshot JSON
  SNAPSHOT_FIELDS = %w[
    name product actual_product qty unit kich_thuoc layer type
    is_missing obj_count has_obj trang_thai new_name
    ten_sp ghi_chu ngay_dat last_modified count length
    len_total_mm product_list ten_sp_list
  ].freeze

  # Convert live row (symbol-keyed hash) → snapshot row (string-keyed hash)
  # Strips entity references and computed fields.
  def self.live_to_snapshot(row, table = "acc")
    return nil unless row.is_a?(Hash)

    snap = {}
    SNAPSHOT_FIELDS.each do |field|
      sym = field.to_sym
      if row.key?(sym)
        snap[field] = row[sym]
      elsif row.key?(field)
        snap[field] = row[field]
      end
    end

    # Normalize types for JSON safety
    snap["name"]    = snap["name"].to_s
    snap["product"] = snap["product"].to_s
    snap["unit"]    = snap["unit"].to_s
    snap["type"]    = snap["type"].to_s
    snap["is_missing"] = !!snap["is_missing"] if snap.key?("is_missing")

    # qty: use count or length depending on type
    unless snap.key?("qty")
      if snap["type"] == "length" || snap["type"] == "phaochi"
        snap["qty"] = row[:length].to_f
      else
        snap["qty"] = row[:count].to_i
      end
    end

    snap
  end

  # Convert snapshot row (string-keyed hash) → live row (symbol-keyed hash)
  # Adds empty live-only fields so code can iterate without nil checks.
  def self.snapshot_to_live(snap, table = "acc")
    return nil unless snap.is_a?(Hash)

    row = {}
    snap.each do |k, v|
      row[k.to_sym] = v
    end

    # Ensure live-only fields exist with safe defaults
    row[:stat_entities] ||= []
    row[:entities]      ||= []
    row[:length_items]  ||= []
    row[:sel_count]     ||= 0
    row[:sel_length]    ||= 0.0
    row[:sel_len_mm]    ||= 0.0
    row[:back_diff]     ||= nil

    # Type coercion
    row[:count]  = row[:count].to_i  if row[:count]
    row[:length] = row[:length].to_f if row[:length]
    row[:is_missing] = !!row[:is_missing]
    row[:type] = row[:type].to_s.to_sym if row[:type].is_a?(String) && !row[:type].empty?

    row
  end

  # Batch convert: live report items → snapshot-safe array
  def self.live_items_to_snapshot(items, table = "acc")
    Array(items).filter_map { |row| live_to_snapshot(row, table) }
  end

  # Batch convert: snapshot items → live rows
  def self.snapshot_items_to_live(items, table = "acc")
    Array(items).filter_map { |snap| snapshot_to_live(snap, table) }
  end

  # Check if a hash is a live row (has entity references)
  def self.live_row?(row)
    row.is_a?(Hash) && (row.key?(:stat_entities) || row.key?(:entities))
  end

  # Strip live-only fields from a hash (in-place, for lightweight cleanup)
  def self.strip_live_fields!(row)
    return row unless row.is_a?(Hash)
    LIVE_ONLY_FIELDS.each { |f| row.delete(f) }
    row
  end

end
