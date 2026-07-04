# encoding: utf-8
# MH_Thongke — accept state, persistence, and undo helpers.
module MH_Thongke

  # === mini_import_accept_state.rb ===
  # --- mini_import_accept_state.rb ---
# MH_Thongke - Mini Import accept state, persistence, and undo helpers.


  def self.reset_mini_rule_caches(lineage: true, accept: true, refresh: true)
    @mini_accept_rule_cache = {} if accept
    @mini_accept_fallback_index = nil if accept
    if accept
      @import_name_norm_cache = {} if instance_variable_defined?(:@import_name_norm_cache)
      @import_equiv_norm_cache = {} if instance_variable_defined?(:@import_equiv_norm_cache)
    end
    @mini_lineage_lookup_cache = nil if lineage
    reset_mini_import_refresh_state if refresh && respond_to?(:reset_mini_import_refresh_state)
    true
  rescue
    false
  end

  def self.ensure_mini_accept_rules
    # Fast path: Throttle full checks to at most once per 2 seconds
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    if @mini_accept_rules.is_a?(Hash) &&
       @mini_accept_rules_last_check_at.to_f > 0 &&
       now - @mini_accept_rules_last_check_at.to_f < 2.0
      return @mini_accept_rules
    end
    @mini_accept_rules_last_check_at = now

    @model = Sketchup.active_model
    model_id = @model ? @model.object_id : 0
    project_rules_file = mini_project_rules_file
    source_sig = mini_rules_source_signature(project_rules_file)
    if @mini_accept_rules.is_a?(Hash) &&
       @mini_accept_rules_model_id == model_id &&
       @mini_accept_rules_project_file.to_s == project_rules_file.to_s &&
       @mini_accept_rules_source_sig.to_s == source_sig.to_s
      return @mini_accept_rules
    end

    begin
      global_rules = load_global_mini_accept_rules
      project_rules = load_project_mini_accept_rules
      raw = @model.get_attribute("MH_Thongke", "mini_accept_rules").to_s
      parsed = raw.empty? ? {} : JSON.parse(raw)
      model_rules = parsed.is_a?(Hash) ? parsed : {}
      @mini_accept_rules = merge_mini_accept_rule_sets(global_rules, model_rules, project_rules)
      mini_assign_accept_rules_state(model_id, project_rules_file, source_sig)
      reset_mini_rule_caches(lineage: false, accept: true, refresh: false)
      ensure_mini_name_lineage
      mini_sync_accept_rules_storage(@mini_accept_rules, global_rules, project_rules, project_rules_file)
      @mini_accept_rules
    rescue
      @mini_accept_rules = merge_mini_accept_rule_sets(load_global_mini_accept_rules, load_project_mini_accept_rules)
      mini_assign_accept_rules_state(model_id, project_rules_file, source_sig)
      reset_mini_rule_caches(lineage: false, accept: true, refresh: false)
      ensure_mini_name_lineage
      @mini_accept_rules
    end
  end

  def self.save_mini_accept_rules
    if @mini_defer_accept_rules_save
      @mini_accept_rules_dirty = true
      return true
    end

    @model ||= Sketchup.active_model
    rules = ensure_mini_accept_rules
    rules = {} unless rules.is_a?(Hash)
    mini_write_accept_rules_model_attributes(@model, rules)
    @mini_accept_rules_model_id = @model.object_id if @model
    save_global_mini_accept_rules(rules)
    save_project_mini_accept_rules(rules)
    @mini_accept_rules_project_file = mini_project_rules_file
    @mini_accept_rules_source_sig = mini_rules_source_signature(@mini_accept_rules_project_file)
    reset_mini_rule_caches(lineage: false, accept: true, refresh: true)
    @mini_accept_rules_dirty = false
    trigger_mini_rules_export
    MH_Thongke::Engine::RulesManager.export_rules_data_json(@model) rescue nil
  rescue
  end

  def self.flush_mini_accept_rules
    return true unless @mini_accept_rules_dirty

    old_defer = @mini_defer_accept_rules_save
    @mini_defer_accept_rules_save = false
    save_mini_accept_rules
  ensure
    @mini_defer_accept_rules_save = old_defer
  end

  def self.with_deferred_mini_accept_rules
    old_defer = @mini_defer_accept_rules_save
    @mini_defer_accept_rules_save = true
    yield
  ensure
    @mini_defer_accept_rules_save = old_defer
    flush_mini_accept_rules unless @mini_defer_accept_rules_save
  end

  def self.clone_mini_accept_rules
    JSON.parse(JSON.generate(ensure_mini_accept_rules))
  rescue
    {}
  end

  def self.restore_mini_accept_rules(rules)
    @mini_accept_rules = rules.is_a?(Hash) ? rules : {}
    reset_mini_rule_caches(lineage: true, accept: true, refresh: true)
    save_mini_accept_rules
  end

  def self.push_mini_rule_undo_snapshot
    return if @mini_suppress_rule_snapshot
    (@mini_undo_rule_stack ||= []) << { "rules" => clone_mini_accept_rules, "added_ids" => [] }
  end

  def self.mark_mini_session_operation
    @mini_session_operation_count = @mini_session_operation_count.to_i + 1
  end

  def self.mini_undo_rules_from(snapshot)
    if snapshot.is_a?(Hash) && snapshot.key?("rules")
      snapshot["rules"].is_a?(Hash) ? snapshot["rules"] : {}
    elsif snapshot.is_a?(Hash)
      snapshot
    else
      {}
    end
  end

  def self.mini_undo_added_ids_from(snapshot)
    return [] unless snapshot.is_a?(Hash)
    ids = snapshot["added_ids"] || snapshot[:added_ids] || []
    Array(ids).map { |id| id.to_i }.reject(&:zero?).uniq
  end

  def self.mini_added_entities_from(snapshot)
    ids = mini_undo_added_ids_from(snapshot)
    ids.empty? ? [] : entities_by_ids(ids.join(","))
  end

  def self.append_mini_undo_added_entities(entities)
    list = Array(entities).compact
    ids = list.map { |ent| ent.entityID rescue nil }.compact.uniq
    return if ids.empty?

    stack = (@mini_undo_rule_stack ||= [])
    stack << { "rules" => clone_mini_accept_rules, "added_ids" => [] } if stack.empty?
    snapshot = stack.last
    unless snapshot.is_a?(Hash) && snapshot.key?("rules")
      snapshot = { "rules" => mini_undo_rules_from(snapshot), "added_ids" => [] }
      stack[-1] = snapshot
    end
    snapshot["added_ids"] ||= []
    snapshot["added_ids"] = (Array(snapshot["added_ids"]) + ids).map(&:to_i).reject(&:zero?).uniq
  end

  def self.mini_assign_accept_rules_state(model_id, project_rules_file, source_sig)
    @mini_accept_rules_model_id = model_id
    @mini_accept_rules_project_file = project_rules_file
    @mini_accept_rules_source_sig = source_sig
  end

  def self.mini_sync_accept_rules_storage(rules, global_rules, project_rules, project_rules_file)
    if !project_rules_file.to_s.empty? && rules.empty? && !File.exist?(project_rules_file)
      save_project_mini_accept_rules(rules)
      return
    end
    return unless rules.any?

    save_global_mini_accept_rules(rules) if rules != global_rules
    save_project_mini_accept_rules(rules) if !project_rules_file.to_s.empty? && rules != project_rules
  end

  def self.trigger_mini_rules_export
    if respond_to?(:queue_rules_excel_export)
      queue_rules_excel_export
    elsif respond_to?(:export_rules_to_excel)
      export_rules_to_excel
    end
  end

  def self.mini_write_accept_rules_model_attributes(model, rules)
    return unless model

    model.set_attribute("MH_Thongke", "mini_accept_rules", JSON.generate(rules))
    model.set_attribute("MH_Thongke", "mini_name_lineage", JSON.generate(normalize_mini_name_lineage(@mini_name_lineage || {})))
  rescue
    nil
  end


  # --- Alias methods (without mini_ prefix) for backward-compatible rename ---
  def self.undo_rules_from(*a, **kw, &b); mini_undo_rules_from(*a, **kw, &b); end
  def self.undo_added_ids_from(*a, **kw, &b); mini_undo_added_ids_from(*a, **kw, &b); end
  def self.added_entities_from(*a, **kw, &b); mini_added_entities_from(*a, **kw, &b); end
  def self.assign_accept_rules_state(*a, **kw, &b); mini_assign_accept_rules_state(*a, **kw, &b); end
  def self.sync_accept_rules_storage(*a, **kw, &b); mini_sync_accept_rules_storage(*a, **kw, &b); end
  def self.write_accept_rules_model_attributes(*a, **kw, &b); mini_write_accept_rules_model_attributes(*a, **kw, &b); end

end
