# encoding: utf-8
# MH_Thongke — accept rules matching logic.
module MH_Thongke

  # === mini_import_accept_rules.rb ===
  # --- mini_import_accept_rules.rb ---
# MH_Thongke - Mini Import accept rules.


  def self.mini_accept_key(product_code, kind, model_name, target_name, spec = "")
    kind_norm = mini_accept_kind(kind)
    [
      product_code_exact(product_code),
      kind_norm,
      mini_accept_norm(kind_norm, model_name),
      mini_accept_norm(kind_norm, target_name),
      mini_accept_spec_norm(spec)
    ].join("|")
  end

  def self.record_mini_accept(product_code, kind, model_name, target_name, spec = "", action = "accept")
    rules = ensure_mini_accept_rules
    key = mini_accept_key(product_code, kind, model_name, target_name, spec)
    product = product_code_exact(product_code)
    kind_value = mini_accept_kind(kind)
    existing = rules[key]
    if existing.is_a?(Hash) &&
       existing["action"].to_s == action.to_s &&
       existing["product_code"].to_s == product &&
       existing["kind"].to_s == kind_value &&
       mini_accept_name_equivalent?(kind_value, existing["model_name"].to_s, model_name.to_s) &&
       mini_accept_name_equivalent?(kind_value, existing["target_name"].to_s, target_name.to_s) &&
       mini_accept_spec_norm(existing["spec"].to_s) == mini_accept_spec_norm(spec.to_s)
      return key
    end

    push_mini_rule_undo_snapshot
    snapshot = (@mini_undo_rule_stack ||= []).last
    if snapshot.is_a?(Hash) && snapshot.key?("rules")
      snapshot["actions"] ||= []
      snapshot["actions"] << action.to_s unless snapshot["actions"].include?(action.to_s)
    end
    rules[key] = {
      "action" => action.to_s,
      "time" => Time.now.to_i,
      "product_code" => product,
      "kind" => kind_value,
      "model_name" => model_name.to_s,
      "target_name" => target_name.to_s,
      "spec" => spec.to_s
    }
    (@mini_session_accept_keys ||= []) << key unless @mini_session_accept_keys.include?(key)
    record_mini_name_lineage(product_code, kind, model_name, target_name, spec, action, "accept_rule")
    reset_mini_rule_caches(lineage: false, accept: true, refresh: true)
    save_mini_accept_rules
    key
  end

  def self.remove_mini_accept(product_code, kind, model_name, target_name, spec = "", action = nil)
    rules = ensure_mini_accept_rules
    return 0 unless rules.is_a?(Hash) && rules.any?

    kind_value = mini_accept_kind(kind)
    products = mini_accept_product_variants(product_code).map(&:to_s)
    model_norm = mini_accept_norm(kind_value, model_name)
    target_norm = mini_accept_norm(kind_value, target_name)
    spec_norm = mini_accept_spec_norm(spec)
    action_text = action.to_s
    removed = 0

    push_mini_rule_undo_snapshot
    rules.delete_if do |key, val|
      parts = key.to_s.split("|", 5)
      next false unless products.include?(parts[0].to_s)
      next false unless parts[1].to_s == kind_value
      next false unless spec_norm.empty? || parts[4].to_s.empty? || parts[4].to_s == spec_norm
      stored_action = mini_accept_rule_value_action(val)
      next false unless action_text.empty? || stored_action == action_text

      stored_model = val.is_a?(Hash) && !val["model_name"].to_s.empty? ? val["model_name"].to_s : parts[2].to_s
      stored_target = val.is_a?(Hash) && !val["target_name"].to_s.empty? ? val["target_name"].to_s : parts[3].to_s
      model_ok = model_norm.empty? || mini_accept_name_equivalent?(kind_value, stored_model, model_norm)
      target_ok = target_norm.empty? || mini_accept_name_equivalent?(kind_value, stored_target, target_norm)
      matched = model_ok && target_ok
      removed += 1 if matched
      matched
    end

    save_mini_accept_rules if removed > 0
    removed
  rescue => e
    puts "remove_mini_accept error: #{e.class}: #{e.message}" rescue nil
    0
  end

  def self.mini_accept_rule?(product_code, kind, model_name, target_name, spec = "")
    !!mini_accept_rule_action(product_code, kind, model_name, target_name, spec)
  end

  def self.mini_accept_canonical_norm(kind, value)
    tokens = mini_accept_norm(kind, value).split
    compact = []
    tokens.each { |token| compact << token unless token == compact.last }
    compact.join(" ")
  rescue
    mini_accept_norm(kind, value).to_s
  end

  def self.mini_accept_name_equivalent?(kind, a, b)
    left = mini_accept_norm(kind, a)
    right = mini_accept_norm(kind, b)
    return true if left == right
    return true if mini_accept_canonical_norm(kind, left) == mini_accept_canonical_norm(kind, right)

    import_names_match?(a, b)
  rescue
    false
  end

  def self.mini_accept_rule_action(product_code, kind, model_name, target_name, spec = "")
    cache_key = mini_accept_rule_action_cache_key(product_code, kind, model_name, target_name, spec)
    @mini_accept_rule_cache ||= {}
    return @mini_accept_rule_cache[cache_key] if @mini_accept_rule_cache.key?(cache_key)

    rules = ensure_mini_accept_rules
    direct_keys = mini_accept_rule_direct_keys(product_code, kind, model_name, target_name, spec)
    direct_keys.each do |key|
      next unless rules.key?(key)
      val = rules[key]
      action = mini_accept_rule_value_action(val)
      if val.is_a?(Hash) &&
         respond_to?(:led_light_strict_mismatch?) &&
         led_light_strict_mismatch?(val["model_name"].to_s, val["target_name"].to_s) &&
         !["manual_match", "rename_update"].include?(action.to_s)
        next
      end
      @mini_accept_rule_cache[cache_key] = action
      return action
    end

    context = mini_accept_rule_match_context(product_code, kind, model_name, target_name, spec)
    result = mini_accept_find_fallback_rule_action(rules, context, true)

    allow_cross_product_rule = context[:kind_norm] != "VL"
    result = mini_accept_find_fallback_rule_action(rules, context, false) if result.nil? && allow_cross_product_rule
    @mini_accept_rule_cache[cache_key] = result
    result
  end

  def self.mini_accept_rule_action_cache_key(product_code, kind, model_name, target_name, spec = "")
    kind_norm = mini_accept_kind(kind)
    ["action", product_code_exact(product_code), kind_norm, mini_accept_norm(kind_norm, model_name), mini_accept_norm(kind_norm, target_name), mini_accept_spec_norm(spec)].join("|")
  end

  def self.mini_accept_rule_direct_keys(product_code, kind, model_name, target_name, spec = "")
    base = product_code_base(product_code)
    keys = [mini_accept_key(product_code, kind, model_name, target_name, spec)]
    keys << mini_accept_key(product_code, kind, model_name, target_name, "") unless spec.to_s.empty?
    unless base.empty? || base == product_code_exact(product_code)
      keys << mini_accept_key(base, kind, model_name, target_name, spec)
      keys << mini_accept_key(base, kind, model_name, target_name, "") unless spec.to_s.empty?
    end
    # NOTE: We intentionally do NOT add keys with empty target_name when the
    # query has a non-empty target. Accept No SPEC rules (stored target="")
    # mean "this model is valid by itself", not "this model matches any target".
    # Those rules are still found via the fallback path with accept_no_spec_match
    # semantics that also requires query target to be empty.
    keys.uniq
  end

  def self.mini_accept_rule_match_context(product_code, kind, model_name, target_name, spec = "")
    kind_norm = mini_accept_kind(kind)
    {
      kind_norm: kind_norm,
      product_keys: mini_accept_product_variants(product_code),
      model_norm: mini_accept_norm(kind_norm, model_name),
      target_norm: mini_accept_norm(kind_norm, target_name),
      spec_norm: mini_accept_spec_norm(spec)
    }
  end

  def self.mini_accept_rule_value_action(val)
    action = val.is_a?(Hash) ? val["action"].to_s : val.to_s
    action.empty? ? "accept" : action
  end

  def self.mini_accept_allowed_action?(action)
    action.empty? || ["accept", "update", "keep", "add", "manual_add", "manual_match", "rename_update", "accept_no_spec"].include?(action)
  end

  def self.mini_accept_rule_parts_match_action(parts, val, context, require_product)
    return nil if require_product && !context[:product_keys].include?(parts[0].to_s)
    return nil unless parts[1].to_s == context[:kind_norm]

    stored_model = parts[2].to_s
    stored_target = parts[3].to_s
    stored_spec = parts[4].to_s
    spec_ok = context[:spec_norm].empty? || stored_spec.empty? || stored_spec == context[:spec_norm]
    return nil unless spec_ok

    action = val.is_a?(Hash) ? val["action"].to_s : val.to_s
    return nil unless mini_accept_allowed_action?(action)
    action = action.empty? ? "accept" : action
    raw_model = val.is_a?(Hash) && !val["model_name"].to_s.empty? ? val["model_name"].to_s : stored_model
    raw_target = val.is_a?(Hash) && !val["target_name"].to_s.empty? ? val["target_name"].to_s : stored_target
    if respond_to?(:led_light_strict_mismatch?) &&
       led_light_strict_mismatch?(raw_model, raw_target) &&
       !["manual_match", "rename_update"].include?(action)
      return nil
    end

    model_matches = !context[:model_norm].empty? && mini_accept_name_equivalent?(context[:kind_norm], stored_model, context[:model_norm])
    target_matches = !context[:target_norm].empty? && mini_accept_name_equivalent?(context[:kind_norm], stored_target, context[:target_norm])
    pair_ok =
      (model_matches && (context[:target_norm].empty? ? stored_target.empty? : target_matches)) ||
      (target_matches && (context[:model_norm].empty? || stored_model.empty? || model_matches))
    if !pair_ok && action == "manual_match" && model_matches && !stored_target.empty? && !context[:target_norm].empty?
      pair_ok = target_matches || context[:target_norm].start_with?("#{stored_target} ")
    end
    pair_ok ? action : nil
  end

  def self.mini_accept_find_fallback_rule_action(rules, context, require_product)
    # Use indexed rules for O(k) lookup instead of O(n) full scan.
    # The index groups rules by "kind|product" for fast subset selection.
    indexed = mini_accept_rules_fallback_index(rules)
    candidates = []
    if require_product
      context[:product_keys].each do |pk|
        idx_key = "#{context[:kind_norm]}|#{pk}"
        candidates.concat(indexed[idx_key]) if indexed.key?(idx_key)
      end
    else
      # Cross-product: only check rules matching the kind
      idx_key_prefix = "#{context[:kind_norm]}|"
      indexed.each do |idx_key, entries|
        candidates.concat(entries) if idx_key.start_with?(idx_key_prefix)
      end
    end
    candidates.each do |entry|
      action = mini_accept_rule_parts_match_action_fast(entry, context)
      return action if action
    end
    nil
  end

  def self.mini_accept_rules_fallback_index(rules)
    # Cache the index; invalidate when rules object changes
    rules_id = Array(rules).hash
    rules_size = rules.size
    if @mini_accept_fallback_index &&
       @mini_accept_fallback_index_id == rules_id &&
       @mini_accept_fallback_index_size == rules_size
      return @mini_accept_fallback_index
    end

    index = Hash.new { |h, k| h[k] = [] }
    rules.each do |key, val|
      parts = key.to_s.split("|", 5)
      next if parts.size < 4
      action_str = val.is_a?(Hash) ? val["action"].to_s : val.to_s
      next unless mini_accept_allowed_action?(action_str)
      idx_key = "#{parts[1]}|#{parts[0]}"
      # Pre-compute norms for fast matching
      index[idx_key] << {
        parts: parts,
        val: val,
        action: action_str.empty? ? "accept" : action_str,
        stored_model: parts[2].to_s,
        stored_target: parts[3].to_s,
        raw_model: val.is_a?(Hash) ? val["model_name"].to_s : "",
        raw_target: val.is_a?(Hash) ? val["target_name"].to_s : "",
        stored_spec: parts[4].to_s
      }
    end
    @mini_accept_fallback_index = index
    @mini_accept_fallback_index_id = rules_id
    @mini_accept_fallback_index_size = rules_size
    index
  end

  def self.mini_accept_rule_parts_match_action_fast(entry, context)
    stored_spec = entry[:stored_spec]
    spec_ok = context[:spec_norm].empty? || stored_spec.empty? || stored_spec == context[:spec_norm]
    return nil unless spec_ok

    stored_model = entry[:stored_model]
    stored_target = entry[:stored_target]
    raw_model = entry[:raw_model].to_s.empty? ? stored_model : entry[:raw_model].to_s
    raw_target = entry[:raw_target].to_s.empty? ? stored_target : entry[:raw_target].to_s
    if respond_to?(:led_light_strict_mismatch?) &&
       led_light_strict_mismatch?(raw_model, raw_target) &&
       !["manual_match", "rename_update"].include?(entry[:action].to_s)
      return nil
    end

    # Fast path: exact norm match (avoids expensive equivalent/synonym checks)
    model_matches = !context[:model_norm].empty? && (
      stored_model == context[:model_norm] ||
      mini_accept_name_equivalent?(context[:kind_norm], stored_model, context[:model_norm])
    )
    target_matches = !context[:target_norm].empty? && (
      stored_target == context[:target_norm] ||
      mini_accept_name_equivalent?(context[:kind_norm], stored_target, context[:target_norm])
    )

    # Accept-no-spec semantics: rule with empty stored_target only applies in
    # MODEL-ONLY context (no target to match against). Symmetrically, a rule
    # with empty stored_model (e.g. manual_add — "this Excel item is valid")
    # only applies when query model also matches the target (or is empty).
    accept_no_spec_match = model_matches && stored_target.empty? && context[:target_norm].empty?
    manual_add_match     = target_matches && stored_model.empty? &&
                           (context[:model_norm].empty? || context[:model_norm] == context[:target_norm])
    manual_match_target  = entry[:action].to_s == "manual_match" &&
                           model_matches &&
                           !stored_target.empty? &&
                           !context[:target_norm].empty? &&
                           (target_matches || context[:target_norm].start_with?("#{stored_target} "))

    pair_ok =
      accept_no_spec_match ||
      manual_add_match ||
      manual_match_target ||
      (model_matches && target_matches) ||
      (model_matches && context[:target_norm].empty? && stored_target.empty?) ||
      (target_matches && context[:model_norm].empty? && stored_model.empty?)
    pair_ok ? entry[:action] : nil
  end

  def self.mini_accept_rule_ok?(product_code, kind, model_name, target_name, spec = "")
    action = mini_accept_rule_action(product_code, kind, model_name, target_name, spec).to_s
    !action.empty?
  end

  def self.mini_accept_kind(kind)
    kind.to_s.empty? ? "PK" : kind.to_s
  rescue
    "PK"
  end

  def self.mini_accept_spec_norm(spec)
    import_name_norm(spec.to_s)
  rescue
    ""
  end

  def self.mini_accept_product_variants(product_code)
    [product_code_exact(product_code), product_code_base(product_code)].reject { |value| value.to_s.empty? || value == "--" }.uniq
  rescue
    []
  end


  # --- Alias methods (without mini_ prefix) for backward-compatible rename ---
  def self.accept_key(*a, **kw, &b); mini_accept_key(*a, **kw, &b); end
  def self.accept_rule?(*a, **kw, &b); mini_accept_rule?(*a, **kw, &b); end
  def self.accept_canonical_norm(*a, **kw, &b); mini_accept_canonical_norm(*a, **kw, &b); end
  def self.accept_name_equivalent?(*a, **kw, &b); mini_accept_name_equivalent?(*a, **kw, &b); end
  def self.accept_rule_action(*a, **kw, &b); mini_accept_rule_action(*a, **kw, &b); end
  def self.accept_rule_action_cache_key(*a, **kw, &b); mini_accept_rule_action_cache_key(*a, **kw, &b); end
  def self.accept_rule_direct_keys(*a, **kw, &b); mini_accept_rule_direct_keys(*a, **kw, &b); end
  def self.accept_rule_match_context(*a, **kw, &b); mini_accept_rule_match_context(*a, **kw, &b); end
  def self.accept_rule_value_action(*a, **kw, &b); mini_accept_rule_value_action(*a, **kw, &b); end
  def self.accept_allowed_action?(*a, **kw, &b); mini_accept_allowed_action?(*a, **kw, &b); end
  def self.accept_rule_parts_match_action(*a, **kw, &b); mini_accept_rule_parts_match_action(*a, **kw, &b); end
  def self.accept_find_fallback_rule_action(*a, **kw, &b); mini_accept_find_fallback_rule_action(*a, **kw, &b); end
  def self.accept_rules_fallback_index(*a, **kw, &b); mini_accept_rules_fallback_index(*a, **kw, &b); end
  def self.accept_rule_parts_match_action_fast(*a, **kw, &b); mini_accept_rule_parts_match_action_fast(*a, **kw, &b); end
  def self.accept_rule_ok?(*a, **kw, &b); mini_accept_rule_ok?(*a, **kw, &b); end
  def self.accept_kind(*a, **kw, &b); mini_accept_kind(*a, **kw, &b); end
  def self.accept_spec_norm(*a, **kw, &b); mini_accept_spec_norm(*a, **kw, &b); end
  def self.accept_product_variants(*a, **kw, &b); mini_accept_product_variants(*a, **kw, &b); end

end
