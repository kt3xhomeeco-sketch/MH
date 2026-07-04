# encoding: utf-8
#
# MH_Thongke classified import payload.
# This is a separate channel from source Excel import rows.

module MH_Thongke
  CLASSIFIED_IMPORT_STATE_KEY = "classified_import_payload".freeze unless const_defined?(:CLASSIFIED_IMPORT_STATE_KEY)
  CLASSIFIED_IMPORT_SCHEMA_VERSION = 1 unless const_defined?(:CLASSIFIED_IMPORT_SCHEMA_VERSION)

  def self.import_classified_payload!(payload, source_path:, source_mtime: nil, source: "thongke_classified_import", refresh: true)
    data = normalize_classified_payload(payload, source_path: source_path, source_mtime: source_mtime, source: source)
    @classified_import_payload = data
    save_classified_import_payload(data)
    invalidate_classified_import_caches
    refresh_import_related_views(false, true, true) if refresh && respond_to?(:refresh_import_related_views)
    data
  rescue => e
    {
      "ok" => false,
      "mode" => "classified_import_error",
      "schema_version" => payload_schema_version(payload),
      "source" => source.to_s,
      "path" => source_path.to_s,
      "error" => e.message
    }
  end

  def self.classified_import_payload
    @classified_import_payload ||= load_classified_import_payload
  rescue
    empty_classified_import_payload
  end

  def self.classified_import_status
    data = classified_import_payload
    {
      "ok" => !!data["ok"],
      "mode" => data["mode"].to_s,
      "schema_version" => data["schema_version"].to_i,
      "source" => data["source"].to_s,
      "path" => data["path"].to_s,
      "rows_count" => Array(data["classified_rows"]).length,
      "loaded_at" => data["loaded_at"].to_s,
      "error" => data["error"]
    }
  rescue => e
    { "ok" => false, "mode" => "classified_import_error", "error" => e.message }
  end

  def self.normalize_classified_payload(payload, source_path:, source_mtime: nil, source: "thongke_classified_import")
    raise "classified payload must be a Hash." unless payload.is_a?(Hash)

    schema_version = payload_schema_version(payload)
    raise "unsupported classified schema_version=#{schema_version}." unless schema_version == CLASSIFIED_IMPORT_SCHEMA_VERSION

    rows = payload["classified_rows"] || payload[:classified_rows]
    rows = payload["rows"] || payload[:rows] if rows.nil?
    rows = Array(rows).map { |row| normalize_classified_row(row) }.select { |row| row.is_a?(Hash) && !row.empty? }
    raise "classified_rows empty." if rows.empty?

    groups = payload["groups"] || payload[:groups] || {}
    groups = {} unless groups.is_a?(Hash)

    {
      "ok" => true,
      "mode" => "classified_import",
      "schema_version" => schema_version,
      "source" => source.to_s.empty? ? payload_source(payload) : source.to_s,
      "payload_source" => payload_source(payload),
      "path" => source_path.to_s,
      "mtime" => source_mtime.to_f,
      "loaded_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      "classified_rows" => rows,
      "groups" => import_excel_deep_fix(groups),
      "error" => nil
    }
  end

  def self.normalize_classified_row(row)
    return {} unless row.is_a?(Hash)
    fixed = import_excel_deep_fix(row)
    fixed.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
  end

  def self.payload_schema_version(payload)
    return 0 unless payload.is_a?(Hash)
    (payload["schema_version"] || payload[:schema_version]).to_i
  rescue
    0
  end

  def self.payload_source(payload)
    return "" unless payload.is_a?(Hash)
    (payload["source"] || payload[:source]).to_s
  rescue
    ""
  end

  def self.save_classified_import_payload(data)
    if respond_to?(:save_project_state_hash)
      save_project_state_hash(CLASSIFIED_IMPORT_STATE_KEY, data)
    else
      @classified_import_payload = data
      true
    end
  end

  def self.load_classified_import_payload
    data = respond_to?(:project_state_hash) ? project_state_hash(CLASSIFIED_IMPORT_STATE_KEY) : {}
    data.is_a?(Hash) && data["ok"] ? data : empty_classified_import_payload
  rescue
    empty_classified_import_payload
  end

  def self.empty_classified_import_payload
    {
      "ok" => false,
      "mode" => "classified_import_empty",
      "schema_version" => CLASSIFIED_IMPORT_SCHEMA_VERSION,
      "classified_rows" => [],
      "groups" => {},
      "error" => nil
    }
  end

  def self.invalidate_classified_import_caches
    @classified_import_payload = nil
    invalidate_mini_import_caches(excel: false, model: false) if respond_to?(:invalidate_mini_import_caches)
    true
  rescue
    true
  end
end
