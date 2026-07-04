# encoding: utf-8
# MH_Thongke - Restore log for reversible app-level changes.

module MH_Thongke
  RESTORE_LOG_FILE = File.join(DATA_DIR, "mh_thongke_restore_log.json") unless defined?(RESTORE_LOG_FILE)
  RESTORE_LOG_LIMIT = 300 unless defined?(RESTORE_LOG_LIMIT)
  RESTORE_ENTITY_ATTRS = [
    ["ABF", "statistical-name"],
    ["ABF", "setting-name"],
    ["ZSU_LED", "ten_hien_thi"],
    ["MH_Thongke", "pk_name"],
    ["MH_Thongke", "ten_sp"],
    ["MH_Thongke", "ghi_chu"],
    ["MH_Thongke", "ngay_dat"],
    ["MH_Thongke", "mat_ten_sp"],
    ["MH_Thongke", "mat_ghi_chu"],
    ["MH_Thongke", "mat_ngay_dat"],
    ["MH_Thongke", "last_modified"]
  ].freeze unless defined?(RESTORE_ENTITY_ATTRS)

  def self.restore_log_file
    project_file = respond_to?(:mini_project_rules_file) ? mini_project_rules_file.to_s : ""
    if !project_file.empty?
      dir = File.dirname(project_file)
      return File.join(dir, "restore_log.json") unless dir.to_s.empty? || dir == "."
    end
    RESTORE_LOG_FILE
  rescue
    RESTORE_LOG_FILE
  end

  def self.load_restore_log
    file = restore_log_file
    return [] if file.to_s.empty? || !File.exist?(file)

    data = JSON.parse(File.read(file))
    data.is_a?(Array) ? data : []
  rescue
    []
  end

  def self.save_restore_log(entries)
    file = restore_log_file
    return false if file.to_s.empty?

    FileUtils.mkdir_p(File.dirname(file))
    list = Array(entries).select { |row| row.is_a?(Hash) }
    File.write(file, JSON.pretty_generate(list.last(RESTORE_LOG_LIMIT)))
    true
  rescue => e
    puts "save_restore_log error: #{e.message}"
    false
  end

  def self.current_restore_state
    state = {}
    state["mini_accept_rules"] = restore_clone_value(ensure_mini_accept_rules) if respond_to?(:ensure_mini_accept_rules)
    state["mini_name_lineage"] = restore_clone_value(ensure_mini_name_lineage) if respond_to?(:ensure_mini_name_lineage)
    state["hidden_excel_items"] = Array(mini_hidden_excel_items).map(&:to_s) if respond_to?(:mini_hidden_excel_items)
    state["hidden_list"] = Array(@hidden_list).map(&:to_s)
    state["match_rules"] = restore_clone_value(@match_rules || {}) if defined?(@match_rules)
    state["general_rules"] = restore_clone_value(@general_rules || {}) if defined?(@general_rules)
    state["order_date_overrides"] = restore_clone_value(project_state_hash("order_date_overrides")) if respond_to?(:project_state_hash)
    state["row_meta_overrides"] = restore_clone_value(project_state_hash("row_meta_overrides")) if respond_to?(:project_state_hash)
    state["row_qty_overrides"] = restore_clone_value(project_state_hash("row_qty_overrides")) if respond_to?(:project_state_hash)
    state["unit_overrides"] = restore_clone_value(@unit_overrides || {}) if defined?(@unit_overrides)
    state
  rescue
    {}
  end

  def self.record_restore_action(action, label, metadata = {}, before_state = nil, after_state = nil)
    metadata = metadata.is_a?(Hash) ? metadata.dup : {}
    model_before = metadata.delete(:model_before) || metadata.delete("model_before")
    model_before = [] unless restore_model_snapshot_changed?(model_before)
    before_state ||= current_restore_state
    after_state ||= current_restore_state
    return nil if before_state == after_state && Array(model_before).empty?

    entries = load_restore_log
    entry = {
      "id" => "rt_#{Time.now.to_i}_#{rand(1_000_000)}",
      "time" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      "action" => action.to_s,
      "label" => fix_vietnamese_mojibake(label),
      "metadata" => restore_normalize_hash(metadata),
      "before" => before_state,
      "after" => after_state,
      "status" => "active"
    }
    entry["model_before"] = restore_clone_value(model_before) unless Array(model_before).empty?
    entry["fingerprint"] = restore_entry_fingerprint(entry)
    same_index = entries.rindex do |row|
      row.is_a?(Hash) &&
        row["status"].to_s != "restored" &&
        restore_entry_fingerprint(row) == entry["fingerprint"]
    end
    if same_index
      entries[same_index] = entry
    else
      entries << entry
    end
    save_restore_log(entries)
    entry["id"]
  rescue => e
    puts "record_restore_action error: #{e.message}"
    nil
  end

  def self.with_restore_action(action, label, metadata = {})
    before_state = current_restore_state
    result = yield
    after_state = current_restore_state
    record_restore_action(action, label, metadata, before_state, after_state)
    result
  end

  def self.restore_normalize_hash(value)
    return {} unless value.is_a?(Hash)

    value.each_with_object({}) do |(k, v), out|
      key = k.to_s
      out[key] = case v
      when Hash
        restore_normalize_hash(v)
      when Array
        v.map { |item| item.is_a?(Hash) ? restore_normalize_hash(item) : restore_json_scalar(item) }
      else
        restore_json_scalar(v)
      end
    end
  rescue
    {}
  end

  def self.restore_json_scalar(value)
    case value
    when NilClass, TrueClass, FalseClass, Numeric
      value
    else
      value.to_s
    end
  end

  def self.restore_clone_value(value)
    case value
    when Hash
      value.each_with_object({}) { |(k, v), out| out[k.to_s] = restore_clone_value(v) }
    when Array
      value.map { |item| restore_clone_value(item) }
    else
      value
    end
  rescue
    {}
  end

  def self.restore_action(entry_id)
    entries = load_restore_log
    entry = entries.find { |row| row["id"].to_s == entry_id.to_s }
    raise "Không tìm thấy restore entry." unless entry
    raise "Entry này đã restore rồi." if entry["status"].to_s == "restored"

    before = entry["before"].is_a?(Hash) ? entry["before"] : {}

    if before.key?("mini_accept_rules") && respond_to?(:restore_mini_accept_rules)
      restore_mini_accept_rules(before["mini_accept_rules"].is_a?(Hash) ? before["mini_accept_rules"] : {})
    end

    if before.key?("mini_name_lineage") && respond_to?(:save_mini_name_lineage)
      @mini_name_lineage = before["mini_name_lineage"].is_a?(Hash) ? before["mini_name_lineage"] : {}
      reset_mini_rule_caches(lineage: true, accept: false, refresh: true) if respond_to?(:reset_mini_rule_caches)
      save_mini_name_lineage
    end

    if before.key?("hidden_excel_items") && respond_to?(:save_mini_hidden_excel_items)
      save_mini_hidden_excel_items(Array(before["hidden_excel_items"]).map(&:to_s))
    end

    if before.key?("hidden_list")
      @hidden_list = respond_to?(:normalize_hidden_names) ? normalize_hidden_names(before["hidden_list"]) : Array(before["hidden_list"]).map(&:to_s)
      @hidden_name_set_sig = nil
      save_preferences if respond_to?(:save_preferences)
    end

    if before.key?("match_rules") || before.key?("general_rules")
      @match_rules = before["match_rules"].is_a?(Hash) ? before["match_rules"] : {}
      @general_rules = before["general_rules"].is_a?(Hash) ? before["general_rules"] : DEFAULT_GENERAL_RULES.dup
      save_match_rules if respond_to?(:save_match_rules)
    end

    save_project_state_hash("order_date_overrides", before["order_date_overrides"].is_a?(Hash) ? before["order_date_overrides"] : {}) if before.key?("order_date_overrides") && respond_to?(:save_project_state_hash)
    save_project_state_hash("row_meta_overrides", before["row_meta_overrides"].is_a?(Hash) ? before["row_meta_overrides"] : {}) if before.key?("row_meta_overrides") && respond_to?(:save_project_state_hash)
    save_project_state_hash("row_qty_overrides", before["row_qty_overrides"].is_a?(Hash) ? before["row_qty_overrides"] : {}) if before.key?("row_qty_overrides") && respond_to?(:save_project_state_hash)

    if before.key?("unit_overrides")
      @unit_overrides = before["unit_overrides"].is_a?(Hash) ? before["unit_overrides"] : {}
      save_preferences if respond_to?(:save_preferences)
    end

    restore_model_entity_snapshot(entry["model_before"]) if entry["model_before"].is_a?(Array) && !entry["model_before"].empty?

    entry["status"] = "restored"
    entry["restored_at"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    save_restore_log(entries)

    # Invalidate ALL caches so restored state takes effect immediately
    clear_caches if respond_to?(:clear_caches)

    # Force ensure_mini_accept_rules to NOT reload from files (which may
    # still contain post-change data).  By clearing the source signature
    # the next call to ensure_mini_accept_rules will see a mismatch and
    # rebuild, but we already set @mini_accept_rules above so we must
    # also update the tracking variables so it keeps our restored value.
    @mini_accept_rules_source_sig = nil
    @mini_accept_rules_model_id = nil
    @mini_accept_rules_project_file = nil
    reset_mini_rule_caches(lineage: true, accept: true, refresh: true) if respond_to?(:reset_mini_rule_caches)

    # Invalidate name lineage caches
    @mini_name_lineage_source_sig = nil
    @mini_name_lineage_model_id = nil
    @mini_name_lineage_project_file = nil

    # Invalidate hidden excel items cache
    @mini_hidden_excel_items_source_sig = nil
    @mini_hidden_excel_items_project_file = nil

    # Force mini import and main dialog full refresh
    @mini_last_table_html = nil
    invalidate_mini_import_caches(model: true, excel: true) if respond_to?(:invalidate_mini_import_caches)
    @last_main_html_hash = nil
    @process_selection_cache_sig = nil
    true
  rescue => e
    puts "restore_action error: #{e.message}"
    raise e
  end

  def self.clear_restore_log
    save_restore_log([])
  end

  def self.restore_log_summary
    entries = restore_display_entries(load_restore_log)
    {
      total: entries.size,
      active: entries.count { |row| row["status"].to_s != "restored" },
      file: restore_log_file
    }
  rescue
    { total: 0, active: 0, file: restore_log_file }
  end

  def self.restore_display_entries(entries = nil)
    list = Array(entries || load_restore_log).select { |row| row.is_a?(Hash) }
    seen = {}
    list.reverse_each.with_object([]) do |entry, out|
      fp = restore_entry_fingerprint(entry)
      next if seen[fp]

      seen[fp] = true
      out << entry
    end.reverse
  rescue
    []
  end

  def self.restore_entry_fingerprint(entry_or_action, metadata = nil)
    entry = if entry_or_action.is_a?(Hash)
      entry_or_action
    else
      { "action" => entry_or_action.to_s, "metadata" => metadata.is_a?(Hash) ? metadata : {} }
    end
    meta = entry["metadata"].is_a?(Hash) ? entry["metadata"] : {}
    [
      entry["action"].to_s,
      meta["product"].to_s,
      meta["kind"].to_s,
      meta["old_name"].to_s,
      meta["name"].to_s,
      meta["target"].to_s,
      meta["new_name"].to_s,
      meta["spec"].to_s,
      meta["rule_key"].to_s,
      meta["keyword"].to_s,
      meta["pattern"].to_s
    ].map { |part| part.strip.downcase }.join("|")
  rescue
    entry_or_action.to_s
  end

  def self.restore_entity_snapshot(items)
    entities = Array(items).map { |item| item.is_a?(Array) ? item[0] : item }
    entities.compact.uniq.map do |entity|
      next if entity.respond_to?(:deleted?) && entity.deleted?

      {
        "persistent_id" => (entity.persistent_id rescue nil),
        "entity_id" => (entity.entityID rescue nil),
        "name" => (entity.respond_to?(:name) ? entity.name.to_s : nil),
        "attrs" => restore_entity_attrs(entity),
        "definition_attrs" => (entity.respond_to?(:definition) && entity.definition ? restore_entity_attrs(entity.definition) : [])
      }
    end.compact
  rescue => e
    puts "restore_entity_snapshot error: #{e.message}"
    []
  end

  def self.restore_entity_attrs(entity)
    RESTORE_ENTITY_ATTRS.map do |dict, key|
      value = entity.get_attribute(dict, key) rescue nil
      { "dict" => dict, "key" => key, "exists" => !value.nil?, "value" => value }
    end
  end

  def self.restore_model_entity_snapshot(snapshot)
    rows = Array(snapshot).select { |row| row.is_a?(Hash) }
    return 0 if rows.empty?

    model = Sketchup.active_model
    restored = 0
    model.start_operation("MH Restore Model Attributes", true)
    rows.each do |row|
      entity = restore_find_entity(row["persistent_id"], row["entity_id"])
      next unless entity
      next if entity.respond_to?(:deleted?) && entity.deleted?

      entity.name = row["name"].to_s if row.key?("name") && entity.respond_to?(:name=)
      restore_apply_entity_attrs(entity, row["attrs"])
      if entity.respond_to?(:definition) && entity.definition
        restore_apply_entity_attrs(entity.definition, row["definition_attrs"])
      end
      restored += 1
    end
    model.commit_operation
    restored
  rescue => e
    model.abort_operation rescue nil
    puts "restore_model_entity_snapshot error: #{e.message}"
    raise e
  end

  def self.restore_model_snapshot_changed?(snapshot)
    rows = Array(snapshot).select { |row| row.is_a?(Hash) }
    return false if rows.empty?

    rows.any? do |row|
      entity = restore_find_entity(row["persistent_id"], row["entity_id"])
      next true unless entity
      next true if entity.respond_to?(:deleted?) && entity.deleted?

      current = {
        "name" => (entity.respond_to?(:name) ? entity.name.to_s : nil),
        "attrs" => restore_entity_attrs(entity),
        "definition_attrs" => (entity.respond_to?(:definition) && entity.definition ? restore_entity_attrs(entity.definition) : [])
      }
      current["name"] != row["name"].to_s ||
        restore_clone_value(current["attrs"]) != restore_clone_value(row["attrs"]) ||
        restore_clone_value(current["definition_attrs"]) != restore_clone_value(row["definition_attrs"])
    end
  rescue => e
    puts "restore_model_snapshot_changed? error: #{e.message}"
    true
  end

  def self.restore_apply_entity_attrs(entity, attrs)
    Array(attrs).each do |row|
      next unless row.is_a?(Hash)
      dict = row["dict"].to_s
      key = row["key"].to_s
      next if dict.empty? || key.empty?

      if row["exists"]
        entity.set_attribute(dict, key, row["value"])
      elsif entity.respond_to?(:delete_attribute)
        entity.delete_attribute(dict, key)
      end
    rescue => e
      puts "restore_apply_entity_attrs warning: #{dict}.#{key}: #{e.message}"
    end
  end

  def self.restore_find_entity(persistent_id, entity_id)
    model = Sketchup.active_model
    pid = persistent_id.to_i
    if pid > 0 && model.respond_to?(:find_entity_by_persistent_id)
      found = model.find_entity_by_persistent_id(pid) rescue nil
      return found if found
    end

    eid = entity_id.to_i
    return nil if eid <= 0
    if respond_to?(:entities_by_ids)
      found = entities_by_ids(eid.to_s).first rescue nil
      return found if found
    end
    restore_find_entity_by_id(model.entities, eid)
  end

  def self.restore_find_entity_by_id(entities, entity_id)
    entities.each do |entity|
      return entity if (entity.entityID rescue nil).to_i == entity_id.to_i
      child_entities = if entity.is_a?(Sketchup::Group)
        entity.entities
      elsif entity.is_a?(Sketchup::ComponentInstance)
        entity.definition.entities
      end
      found = restore_find_entity_by_id(child_entities, entity_id) if child_entities
      return found if found
    end
    nil
  rescue
    nil
  end
end
