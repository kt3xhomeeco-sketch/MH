# encoding: utf-8
# MH_Thongke — session undo/cancel, apply-all.
module MH_Thongke

  # === mini_import_accept_session.rb ===
  # --- mini_import_accept_session.rb ---
# MH_Thongke - Mini Import session state, undo and cancel helpers.


  def self.cancel_mini_session_accepts
    rules = @mini_session_accept_rules_base ? clone_hash(@mini_session_accept_rules_base) : ensure_mini_accept_rules
    @mini_accept_rules = rules
    @mini_session_accept_keys = []
    @mini_session_accept_rules_base = clone_mini_accept_rules
    @mini_undo_rule_stack = []
    @mini_session_operation_count = 0
    save_mini_accept_rules
  end

  def self.clone_hash(value)
    JSON.parse(JSON.generate(value || {}))
  rescue
    {}
  end

  def self.push_match_rule_undo_snapshot
    (@match_rule_undo_stack ||= []) << clone_hash(@match_rules || {})
  end

  def self.restore_match_rule_undo_snapshot(rules)
    return unless rules.is_a?(Hash)
    @match_rules = rules
    save_match_rules if respond_to?(:save_match_rules)
  end

  def self.perform_model_undo
    @model ||= Sketchup.active_model
    if @model.respond_to?(:undo)
      @model.undo
    elsif Sketchup.respond_to?(:undo)
      Sketchup.undo
    else
      UI.send_action("editUndo:") rescue nil
    end
  end

  def self.mini_undo_last_action
    undo_stack = (@mini_undo_rule_stack ||= [])
    if @mini_session_operation_count.to_i <= 0 && undo_stack.empty?
      perform_model_undo
      return true
    end

    snapshot = undo_stack.pop
    perform_model_undo
    perform_model_undo if snapshot && !mini_undo_added_ids_from(snapshot).empty? && !mini_added_entities_from(snapshot).empty?
    restore_mini_accept_rules(mini_undo_rules_from(snapshot)) if snapshot
    cleanup_mini_added_entities(snapshot)
    @mini_session_operation_count = [@mini_session_operation_count.to_i - 1, 0].max
    @mini_accept_rules = nil
    true
  end

  def self.cleanup_mini_added_entities(snapshot)
    ids = mini_undo_added_ids_from(snapshot)
    return false if ids.empty?
    entities = entities_by_ids(ids.join(","))
    return false if entities.empty?

    began = false
    begin
      @model ||= Sketchup.active_model
      @model.start_operation("Mini Import Undo Added", true, false, true)
      began = true
      erase_mini_entities(entities)
      @model.commit_operation
      true
    rescue
      @model.abort_operation rescue nil if began
      erase_mini_entities(entities) rescue nil
      true
    end
  end

  def self.mini_cancel_session
    snapshots = []
    while @mini_session_operation_count.to_i > 0
      snapshot = (@mini_undo_rule_stack ||= []).pop
      perform_model_undo
      perform_model_undo if snapshot && !mini_undo_added_ids_from(snapshot).empty? && !mini_added_entities_from(snapshot).empty?
      snapshots << snapshot if snapshot
      @mini_session_operation_count = [@mini_session_operation_count.to_i - 1, 0].max
    end
    restore_mini_accept_rules(clone_hash(@mini_session_accept_rules_base)) if @mini_session_accept_rules_base
    snapshots.each { |snapshot| cleanup_mini_added_entities(snapshot) }
    @mini_session_accept_keys = []
    @mini_undo_rule_stack = []
    @mini_session_operation_count = 0
    clear_caches if respond_to?(:clear_caches)
    invalidate_mini_import_caches(model: true, excel: true) if respond_to?(:invalidate_mini_import_caches)
  end

  def self.mini_ok_session
    @mini_session_accept_rules_base = clone_mini_accept_rules
    @mini_session_accept_keys = []
    @mini_undo_rule_stack = []
    @mini_session_operation_count = 0
  end

  # === mini_import_accept_apply_all.rb ===
  # --- mini_import_accept_apply_all.rb ---
# MH_Thongke - Mini Import bulk status apply.


  def self.mini_apply_all_status
    respond_to?(:load_import_excel_snapshot_only) ? load_import_excel_snapshot_only : ensure_import_excel_loaded(false)
    respond_to?(:process_selection_cached) ? process_selection_cached(false) : process_selection
    products = if respond_to?(:mini_rows_resolve_products)
      mini_rows_resolve_products
    else
      mini_display_products
    end
    return 0 if products.empty?

    applied = 0
    @mini_suppress_rule_snapshot = true
    (@mini_undo_rule_stack ||= []) << { "rules" => clone_mini_accept_rules, "added_ids" => [] }
    with_deferred_mini_accept_rules do
      products.each do |product_code|
        model_items = mini_model_items(product_code)
        ex_items_raw = mini_excel_items(product_code, false).reject { |ex| ex[:kind].to_s == "VL" }
        next if ex_items_raw.empty? && model_items.empty?

        pk_model_items = model_items.select { |m| m[:kind] != "VL" }
        matched_model_keys = []
        mini_group_excel_items(ex_items_raw, false).each do |ex|
          hw = ex[:hw_name].to_s
          spec = ex[:spec].to_s.strip
          section = ex[:section].to_s.strip
          target_name = import_display_name(hw, spec)
          candidates = mini_apply_all_candidates_for_section(pk_model_items, section)
          found = mini_apply_all_find_model_for_excel(product_code, candidates, hw, target_name, spec, matched_model_keys)
          model = found[:model]
          target_name = found[:target_name]
          norm_target = found[:norm_target]
          duplicate_used = found[:duplicate_used]
          next if duplicate_used && !model
          model = nil if model && (model[:ids] || []).empty?
          if model
            matched_model_keys << mini_model_item_key(model)
            if mini_apply_all_skip_model?(product_code, model, target_name, spec, norm_target)
              next
            elsif model[:editable] != false
              mini_entities_for_name(product_code, model[:name], section).each do |ent|
                apply_import_entity_name(ent, target_name)
                ent.set_attribute("MH_Thongke", "last_modified", Time.now.strftime("%d/%m/%y %H:%M"))
              end
              record_mini_accept(product_code, "PK", model[:name], target_name, spec, "update")
              applied += 1
            else
              record_mini_accept(product_code, "PK", model[:name], target_name, spec, "accept")
              applied += 1
            end
          end
        end

        model_items.each do |m|
          next if m[:kind].to_s == "VL"
          next if matched_model_keys.include?(mini_model_item_key(m))
          next if resolve_mini_model_only_status_key(product_code, "PK", m[:name]) == "OK"
          record_mini_accept(product_code, "PK", m[:name], "", "", "accept_no_spec")
          applied += 1
        end
      end
    end
    (@mini_undo_rule_stack ||= []).pop if applied.to_i <= 0
    applied
  ensure
    @mini_suppress_rule_snapshot = false
  end

  def self.mini_apply_all_candidates_for_section(pk_model_items, section)
    candidates = pk_model_items
    return candidates if section.to_s.empty?

    sectioned_candidates = candidates.select { |item| !item[:section].to_s.strip.empty? }
    return candidates if sectioned_candidates.empty?

    sectioned_candidates.select { |item| mini_model_item_section_match?(item, section) }
  end

  def self.mini_apply_all_model_name_match?(product_code, model_name, hw, target_name, spec)
    mini_pk_model_name_match?(product_code, model_name, hw, target_name, spec)
  rescue
    false
  end

  def self.mini_apply_all_find_model_for_excel(product_code, candidates, hw, target_name, spec, matched_model_keys)
    duplicate_used = false
    model = candidates.find do |item|
      matched = mini_apply_all_model_name_match?(product_code, item[:name], hw, target_name, spec)
      if matched && matched_model_keys.include?(mini_model_item_key(item))
        duplicate_used = true
        next false
      end
      matched
    end

    norm_target = import_name_norm(target_name)
    { model: model, target_name: target_name, norm_target: norm_target, duplicate_used: duplicate_used }
  end

  def self.mini_apply_all_skip_model?(product_code, model, target_name, spec, norm_target = nil)
    pk_match_ok_like_mini?(product_code, model[:name], target_name, spec)
  rescue
    false
  end

  # === mini_import_accept.rb ===
  # --- mini_import_accept.rb ---
# MH_Thongke - Mini Import accept entrypoint.
#
# Logic is split into:
# - mini_import_accept_session.rb
# - mini_import_accept_apply_all.rb


  # --- Alias methods (without mini_ prefix) for backward-compatible rename ---
  def self.apply_all_candidates_for_section(*a, **kw, &b); mini_apply_all_candidates_for_section(*a, **kw, &b); end
  def self.apply_all_model_name_match?(*a, **kw, &b); mini_apply_all_model_name_match?(*a, **kw, &b); end
  def self.apply_all_find_model_for_excel(*a, **kw, &b); mini_apply_all_find_model_for_excel(*a, **kw, &b); end
  def self.apply_all_skip_model?(*a, **kw, &b); mini_apply_all_skip_model?(*a, **kw, &b); end

  def self.undo_last_action(*a, **kw, &b); mini_undo_last_action(*a, **kw, &b); end
  def self.cancel_session(*a, **kw, &b); mini_cancel_session(*a, **kw, &b); end
  def self.ok_session(*a, **kw, &b); mini_ok_session(*a, **kw, &b); end
  def self.apply_all_status(*a, **kw, &b); mini_apply_all_status(*a, **kw, &b); end
end
