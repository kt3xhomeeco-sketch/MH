# encoding: utf-8

module MH_Thongke
  module P4DeltaMergeHarness
    module_function

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue
      Time.now.to_f
    end

    def elapsed_ms(start_time)
      ((now - start_time) * 1000.0).round(1)
    end

    def benchmark_session
      if defined?(MH_Thongke::P3Harness) && MH_Thongke::P3Harness.respond_to?(:benchmark_session)
        return MH_Thongke::P3Harness.benchmark_session
      end

      src = MH_Thongke.session
      s = MH_Thongke::SessionState.new
      s.group_by = src.group_by
      s.hidden_list = Array(src.hidden_list).dup
      s.unit_overrides = src.unit_overrides.is_a?(Hash) ? src.unit_overrides.dup : {}
      s.imported_excel_data = Array(src.imported_excel_data).map { |row| row.is_a?(Hash) ? row.dup : row }
      s.match_rules = src.match_rules.is_a?(Hash) ? src.match_rules.dup : src.match_rules
      s.general_rules = src.general_rules.is_a?(Hash) ? src.general_rules.dup : src.general_rules
      s
    end

    def product_base(value)
      if MH_Thongke.respond_to?(:product_code_base)
        MH_Thongke.product_code_base(value.to_s)
      else
        value.to_s.sub(/\.\d+\z/, "")
      end
    rescue
      value.to_s
    end

    def product_exact(value)
      if MH_Thongke.respond_to?(:product_code_exact)
        MH_Thongke.product_code_exact(value.to_s)
      else
        value.to_s.strip.upcase
      end
    rescue
      value.to_s
    end

    def run_pipeline_for_roots(root_entities, product_bases: nil)
      model = Sketchup.active_model
      selection = model.selection
      s = benchmark_session
      bases = Array(product_bases).map { |base| product_base(base) }.reject(&:empty?).uniq
      unless bases.empty?
        s.imported_excel_data = Array(s.imported_excel_data).select do |row|
          bases.include?(product_base(row[:ma_sp] || row["ma_sp"]))
        end
      end
      t0 = now
      MH_Thongke::Pipeline.stage_scan_model(s, model, selection, root_entities: root_entities)
      scan_ms = elapsed_ms(t0)

      t1 = now
      MH_Thongke::Pipeline.stage_excel_match(s)
      MH_Thongke::Pipeline.stage_material_status(s)
      MH_Thongke::Pipeline.stage_autofill_product_names(s)
      MH_Thongke::Pipeline.stage_merge_and_filter(s)
      MH_Thongke::Pipeline.stage_apply_overrides(s)
      MH_Thongke::Pipeline.stage_normalize_status(s)
      MH_Thongke::Pipeline.stage_final_status_rematch(s)
      pipeline_ms = elapsed_ms(t1)

      {
        session: s,
        scan_ms: scan_ms,
        pipeline_ms: pipeline_ms,
        data_keys: s.data_map.keys,
        mat_keys: s.mat_data_map.keys
      }
    rescue => e
      {
        error: "#{e.class}: #{e.message}",
        backtrace: Array(e.backtrace).first(5),
        session: nil,
        scan_ms: 0.0,
        pipeline_ms: 0.0,
        data_keys: [],
        mat_keys: []
      }
    end

    def entity_key(entity)
      if defined?(MH_Thongke::P4DeltaTracker)
        MH_Thongke::P4DeltaTracker.entity_key(entity)
      else
        entity.respond_to?(:persistent_id) ? "pid:#{entity.persistent_id}" : "oid:#{entity.object_id}"
      end
    rescue
      nil
    end

    def row_top_keys(row)
      keys = []
      Array(row[:stat_entities]).each do |item|
        top = item.is_a?(Array) ? item[1] : item
        key = entity_key(top)
        keys << key unless key.to_s.empty?
      end
      Array(row[:entities]).each do |entity|
        key = entity_key(entity)
        keys << key unless key.to_s.empty?
      end
      keys.uniq
    rescue
      []
    end

    def row_products(row)
      products = []
      products << row[:actual_product]
      products << row[:product]
      products.concat(Array(row[:product_list]))
      products.map { |value| product_exact(value) }.reject { |value| value.empty? || value == "--" }.uniq
    rescue
      []
    end

    def row_product_bases(row)
      row_products(row).map { |value| product_base(value) }.reject(&:empty?).uniq
    rescue
      []
    end

    def affected_product_bases_for_top_keys(data_map, mat_map, top_keys)
      changed = Array(top_keys).map(&:to_s)
      bases = []
      [data_map, mat_map].each do |map|
        map.each_value do |row|
          next if (row_top_keys(row) & changed).empty?

          bases.concat(row_product_bases(row))
        end
      end
      bases.reject { |base| base.to_s.empty? || base == "--" }.uniq
    rescue
      []
    end

    def row_for_product_base?(row, bases)
      row_product_bases(row).any? { |base| bases.include?(base) }
    rescue
      false
    end

    def top_keys_for_product_bases(data_map, mat_map, bases)
      out = []
      [data_map, mat_map].each do |map|
        map.each_value do |row|
          next unless row_for_product_base?(row, bases)

          out.concat(row_top_keys(row))
        end
      end
      out.reject(&:empty?).uniq
    rescue
      []
    end

    def product_replace_candidate(current_map, changed_map, bases)
      out = {}
      current_map.each do |key, row|
        out[key] = clone_row(row) unless row_for_product_base?(row, bases)
      end
      changed_map.each { |key, row| out[key] = clone_row(row) }
      out
    rescue
      current_map
    end

    def collision_report(rows_by_key, affected_keys, changed_keys)
      changed = Array(changed_keys).map(&:to_s)
      Array(affected_keys).each_with_object([]) do |key, out|
        row = rows_by_key[key]
        roots = row_top_keys(row)
        outside = roots - changed
        next if outside.empty?

        out << {
          key: key,
          name: row[:name].to_s,
          product: (row[:actual_product] || row[:product]).to_s,
          root_count: roots.length,
          outside_count: outside.length,
          sample_outside: outside.first(5)
        }
      end
    rescue
      []
    end

    def fingerprint_rows(rows)
      Array(rows).map do |row|
        {
          data_key: row[:data_key],
          name: row[:name],
          product: row[:product],
          actual_product: row[:actual_product],
          ten_sp: row[:ten_sp],
          trang_thai: row[:trang_thai],
          count: row[:count],
          sel_count: row[:sel_count],
          length: row[:length],
          sel_length: row[:sel_length],
          unit: row[:unit],
          is_missing: row[:is_missing]
        }
      end.sort_by { |row| [row[:product].to_s, row[:name].to_s, row[:data_key].to_s] }
    rescue
      []
    end

    def capture_runtime_maps
      {
        data_map: MH_Thongke.instance_variable_get(:@data_map),
        mat_data_map: MH_Thongke.instance_variable_get(:@mat_data_map),
        prod_groups: MH_Thongke.instance_variable_get(:@prod_groups),
        all_item_names: MH_Thongke.instance_variable_get(:@all_item_names),
        all_item_names_set: MH_Thongke.instance_variable_get(:@all_item_names_set),
        led_per_product: MH_Thongke.instance_variable_get(:@led_per_product),
        current_report_items: MH_Thongke.instance_variable_get(:@current_report_items),
        current_mat_items: MH_Thongke.instance_variable_get(:@current_mat_items)
      }
    rescue
      {}
    end

    def restore_runtime_maps(state)
      state.each { |key, value| MH_Thongke.instance_variable_set(:"@#{key}", value) }
      true
    rescue
      false
    end

    def map_fingerprint(map)
      fingerprint_rows(Array(map).map do |key, row|
        row.is_a?(Hash) ? row.merge(data_key: key) : row
      end)
    rescue
      []
    end

    def diff_summary(candidate_map, expected_map, limit = 10)
      cand = map_fingerprint(candidate_map)
      exp = map_fingerprint(expected_map)
      return { pass: true, missing: 0, extra: 0, changed: 0, samples: [] } if cand == exp

      cand_by_key = cand.each_with_object({}) { |row, h| h[[row[:data_key], row[:name], row[:product]]] = row }
      exp_by_key = exp.each_with_object({}) { |row, h| h[[row[:data_key], row[:name], row[:product]]] = row }
      missing_keys = exp_by_key.keys - cand_by_key.keys
      extra_keys = cand_by_key.keys - exp_by_key.keys
      changed_keys = (exp_by_key.keys & cand_by_key.keys).select { |key| exp_by_key[key] != cand_by_key[key] }
      samples = []
      missing_keys.first(limit).each { |key| samples << { type: "missing", key: key, expected: exp_by_key[key] } }
      extra_keys.first(limit - samples.length).each { |key| samples << { type: "extra", key: key, actual: cand_by_key[key] } }
      changed_keys.first(limit - samples.length).each { |key| samples << { type: "changed", key: key, expected: exp_by_key[key], actual: cand_by_key[key] } }
      {
        pass: false,
        missing: missing_keys.length,
        extra: extra_keys.length,
        changed: changed_keys.length,
        samples: samples
      }
    rescue => e
      { pass: false, error: "#{e.class}: #{e.message}", samples: [] }
    end

    def row_replace_candidate(current_map, changed_map, affected_keys)
      out = {}
      current_map.each { |key, row| out[key] = row }
      Array(affected_keys).each { |key| out.delete(key) }
      changed_map.each { |key, row| out[key] = row if affected_keys.include?(key) }
      out
    rescue
      current_map
    end

    def entity_selected?(entity, selection_set)
      selection_set.include?(entity)
    rescue
      false
    end

    def top_key_from_pair(item)
      top = item.is_a?(Array) ? item[1] : item
      entity_key(top)
    rescue
      nil
    end

    def top_key_from_length_item(item)
      entity_key(item[:top] || item["top"])
    rescue
      nil
    end

    def row_quantity_zero?(row)
      row[:count].to_f <= 0.0 &&
        row[:length].to_f <= 0.0 &&
        row[:len_total_mm].to_f <= 0.0
    rescue
      false
    end

    def clone_row(row)
      out = {}
      row.each do |key, value|
        out[key] = case value
                   when Array
                     value.map { |item| item.is_a?(Hash) ? item.dup : (item.is_a?(Array) ? item.dup : item) }
                   when Hash
                     value.dup
                   else
                     value
                   end
      end
      out
    rescue
      row.dup
    end

    def subtract_root_contribution(row, changed_keys, selection_set)
      changed = Array(changed_keys).map(&:to_s)
      out = clone_row(row)
      type = out[:type].is_a?(Symbol) ? out[:type] : out[:type].to_s.to_sym rescue :count

      if out[:length_items].is_a?(Array) && !out[:length_items].empty?
        keep = []
        removed_length = 0.0
        removed_sel_length = 0.0
        removed_count = 0
        removed_sel_count = 0
        out[:length_items].each do |item|
          if changed.include?(top_key_from_length_item(item).to_s)
            len_inch = item[:len_inch] || item["len_inch"]
            len_mm = item[:len_mm] || item["len_mm"]
            selected = !!(item[:selected] || item["selected"])
            if len_mm
              removed_length += len_mm.to_f
              removed_sel_length += len_mm.to_f if selected
            else
              removed_length += len_inch.to_f
              removed_sel_length += len_inch.to_f if selected
            end
            removed_count += 1
            removed_sel_count += 1 if selected
          else
            keep << item
          end
        end
        out[:length_items] = keep
        if type == :phaochi || out.key?(:len_total_mm)
          out[:len_total_mm] = out[:len_total_mm].to_f - removed_length
          out[:sel_len_mm] = out[:sel_len_mm].to_f - removed_sel_length
        else
          out[:length] = out[:length].to_f - removed_length
          out[:sel_length] = out[:sel_length].to_f - removed_sel_length
        end
        out[:count] = out[:count].to_f - removed_count if out.key?(:count)
        out[:sel_count] = out[:sel_count].to_f - removed_sel_count if out.key?(:sel_count)
      elsif out[:stat_entities].is_a?(Array) && !out[:stat_entities].empty?
        keep = []
        removed_count = 0
        removed_sel_count = 0
        out[:stat_entities].each do |item|
          top_key = top_key_from_pair(item).to_s
          entity = item.is_a?(Array) ? item[0] : item
          top = item.is_a?(Array) ? item[1] : entity
          if changed.include?(top_key)
            removed_count += 1
            removed_sel_count += 1 if entity_selected?(entity, selection_set) || entity_selected?(top, selection_set)
          else
            keep << item
          end
        end
        out[:stat_entities] = keep
        out[:count] = out[:count].to_f - removed_count if out.key?(:count)
        out[:sel_count] = out[:sel_count].to_f - removed_sel_count if out.key?(:sel_count)
      elsif out[:entities].is_a?(Array) && !out[:entities].empty?
        keep_entities = out[:entities].reject { |entity| changed.include?(entity_key(entity).to_s) }
        removed = out[:entities].length - keep_entities.length
        out[:entities] = keep_entities
        if removed > 0 && out[:count].to_f > 0
          multiplier = out[:name].to_s =~ /bas treo suốt áo/i ? 2.0 : 1.0
          out[:count] = out[:count].to_f - (removed * multiplier)
        end
      else
        out[:p4_delta_unsupported] = true
      end

      if out[:entities].is_a?(Array)
        out[:entities] = out[:entities].reject { |entity| changed.include?(entity_key(entity).to_s) }
      end
      if out[:layer_tags].is_a?(Array) && out[:stat_entities].is_a?(Array)
        out[:layer_tags] = out[:stat_entities].map do |item|
          entity = item.is_a?(Array) ? item[0] : item
          entity.respond_to?(:layer) && entity.layer ? entity.layer.name.to_s : nil
        end.compact.uniq
      end

      row_quantity_zero?(out) ? nil : out
    rescue
      row
    end

    def merge_arrays(a, b)
      (Array(a) + Array(b)).uniq { |item| item.respond_to?(:object_id) ? item.object_id : item.hash }
    rescue
      Array(a) + Array(b)
    end

    def merge_row(base, incoming)
      return clone_row(incoming) unless base

      out = clone_row(base)
      out[:count] = out[:count].to_f + incoming[:count].to_f if out.key?(:count) || incoming.key?(:count)
      out[:sel_count] = out[:sel_count].to_f + incoming[:sel_count].to_f if out.key?(:sel_count) || incoming.key?(:sel_count)
      out[:length] = out[:length].to_f + incoming[:length].to_f if out.key?(:length) || incoming.key?(:length)
      out[:sel_length] = out[:sel_length].to_f + incoming[:sel_length].to_f if out.key?(:sel_length) || incoming.key?(:sel_length)
      out[:len_total_mm] = out[:len_total_mm].to_f + incoming[:len_total_mm].to_f if out.key?(:len_total_mm) || incoming.key?(:len_total_mm)
      out[:sel_len_mm] = out[:sel_len_mm].to_f + incoming[:sel_len_mm].to_f if out.key?(:sel_len_mm) || incoming.key?(:sel_len_mm)
      out[:entities] = merge_arrays(out[:entities], incoming[:entities])
      out[:stat_entities] = merge_arrays(out[:stat_entities], incoming[:stat_entities])
      out[:length_items] = merge_arrays(out[:length_items], incoming[:length_items])
      out[:layer_tags] = merge_arrays(out[:layer_tags], incoming[:layer_tags])
      out[:product_list] = merge_arrays(out[:product_list], incoming[:product_list])
      out[:ten_sp_list] = merge_arrays(out[:ten_sp_list], incoming[:ten_sp_list])
      %i[name product actual_product ten_sp ghi_chu ngay_dat last_modified layer unit dict key type is_missing].each do |field|
        out[field] = incoming[field] if out[field].to_s.empty? && incoming.key?(field)
      end
      out
    rescue
      incoming
    end

    def subtract_merge_candidate(current_map, changed_map, affected_keys, changed_keys, selection_set)
      out = {}
      current_map.each { |key, row| out[key] = clone_row(row) }
      Array(affected_keys).each do |key|
        next unless out[key]

        remaining = subtract_root_contribution(out[key], changed_keys, selection_set)
        if remaining
          out[key] = remaining
        else
          out.delete(key)
        end
      end
      changed_map.each do |key, row|
        out[key] = merge_row(out[key], row)
      end
      out
    rescue
      current_map
    end

    def postprocess_candidate(data_map, mat_map)
      runtime_before = capture_runtime_maps
      s = benchmark_session
      s.data_map = data_map
      s.mat_data_map = mat_map
      MH_Thongke.instance_variable_set(:@data_map, s.data_map)
      MH_Thongke.instance_variable_set(:@mat_data_map, s.mat_data_map)
      MH_Thongke::Pipeline.stage_material_status(s)
      MH_Thongke::Pipeline.stage_autofill_product_names(s)
      MH_Thongke::Pipeline.stage_merge_and_filter(s)
      MH_Thongke::Pipeline.stage_apply_overrides(s)
      MH_Thongke::Pipeline.stage_normalize_status(s)
      MH_Thongke::Pipeline.stage_final_status_rematch(s)
      { data_map: s.data_map, mat_data_map: s.mat_data_map }
    rescue
      { data_map: data_map, mat_data_map: mat_map }
    ensure
      restore_runtime_maps(runtime_before) if runtime_before
    end

    def dry_run(top_keys: nil, sample: true)
      MH_Thongke.process_selection_cached(true, "p4_delta_merge_dry_run_baseline") if MH_Thongke.respond_to?(:process_selection_cached)
      MH_Thongke.p4_delta_rebuild_watchers if MH_Thongke.respond_to?(:p4_delta_rebuild_watchers)

      runtime_before = capture_runtime_maps
      current_data = (runtime_before[:data_map] || {}).dup
      current_mat = (runtime_before[:mat_data_map] || {}).dup

      keys = Array(top_keys).map(&:to_s).reject(&:empty?)
      keys = MH_Thongke.p4_delta_changed_top_keys(20) if keys.empty? && MH_Thongke.respond_to?(:p4_delta_changed_top_keys)
      keys = Array(MH_Thongke.p4_delta_tracked_top_keys(1)) if keys.empty? && sample && MH_Thongke.respond_to?(:p4_delta_tracked_top_keys)
      roots = MH_Thongke.respond_to?(:p4_delta_root_entities_for_keys) ? MH_Thongke.p4_delta_root_entities_for_keys(keys) : []

      changed = run_pipeline_for_roots(roots)
      restore_runtime_maps(runtime_before)

      changed_s = changed[:session]
      changed_data_map = changed_s ? changed_s.data_map : {}
      changed_mat_map = changed_s ? changed_s.mat_data_map : {}
      affected_data_keys = Array(changed[:data_keys])
      affected_mat_keys = Array(changed[:mat_keys])
      data_collisions = collision_report(current_data, affected_data_keys, keys)
      mat_collisions = collision_report(current_mat, affected_mat_keys, keys)
      row_replace_safe = data_collisions.empty? && mat_collisions.empty?
      candidate_data = row_replace_safe ? row_replace_candidate(current_data, changed_data_map, affected_data_keys) : nil
      candidate_mat = row_replace_safe ? row_replace_candidate(current_mat, changed_mat_map, affected_mat_keys) : nil
      candidate_diff_pass = row_replace_safe &&
        map_fingerprint(candidate_data) == map_fingerprint(current_data) &&
        map_fingerprint(candidate_mat) == map_fingerprint(current_mat)
      selection_set = Sketchup.active_model.selection.respond_to?(:to_a) ? Sketchup.active_model.selection.to_a.to_set : Set.new
      subtract_data = subtract_merge_candidate(current_data, changed_data_map, affected_data_keys, keys, selection_set)
      subtract_mat = subtract_merge_candidate(current_mat, changed_mat_map, affected_mat_keys, keys, selection_set)
      postprocessed = postprocess_candidate(subtract_data, subtract_mat)
      subtract_data = postprocessed[:data_map]
      subtract_mat = postprocessed[:mat_data_map]
      subtract_data_diff = diff_summary(subtract_data, current_data, 5)
      subtract_mat_diff = diff_summary(subtract_mat, current_mat, 5)
      subtract_diff_pass = subtract_data_diff[:pass] && subtract_mat_diff[:pass]
      unsupported_data = subtract_data.values.count { |row| row[:p4_delta_unsupported] rescue false }
      unsupported_mat = subtract_mat.values.count { |row| row[:p4_delta_unsupported] rescue false }

      {
        ok: changed[:error].nil?,
        phase: "p4b_delta_merge_dry_run_v1",
        changed_top_keys: keys,
        root_count: roots.length,
        changed_scan_ms: changed[:scan_ms],
        changed_pipeline_ms: changed[:pipeline_ms],
        changed_data_keys: affected_data_keys.length,
        changed_mat_keys: affected_mat_keys.length,
        data_collision_count: data_collisions.length,
        mat_collision_count: mat_collisions.length,
        row_replace_safe: row_replace_safe,
        row_replace_diff_pass: candidate_diff_pass,
        subtract_merge_diff_pass: subtract_diff_pass,
        subtract_data_diff: subtract_data_diff,
        subtract_mat_diff: subtract_mat_diff,
        subtract_unsupported_data_rows: unsupported_data,
        subtract_unsupported_mat_rows: unsupported_mat,
        sample_data_collisions: data_collisions.first(10),
        sample_mat_collisions: mat_collisions.first(10),
        changed_error: changed[:error],
        watch_status: MH_Thongke.respond_to?(:p4_delta_status) ? MH_Thongke.p4_delta_status : {}
      }
    rescue => e
      {
        ok: false,
        phase: "p4b_delta_merge_dry_run_v1",
        error: "#{e.class}: #{e.message}",
        backtrace: Array(e.backtrace).first(8)
      }
    end

    def apply_product_candidate(data_map, mat_map)
      s = MH_Thongke.session
      s.data_map = data_map
      s.mat_data_map = mat_map
      MH_Thongke.instance_variable_set(:@data_map, data_map)
      MH_Thongke.instance_variable_set(:@mat_data_map, mat_map)
      MH_Thongke::Pipeline.stage_finalize(s, Sketchup.active_model)
      MH_Thongke.sync_session_to_module_ivars(s) if MH_Thongke.respond_to?(:sync_session_to_module_ivars)
      MH_Thongke.p4_delta_rebuild_watchers if MH_Thongke.respond_to?(:p4_delta_rebuild_watchers)
      true
    rescue
      false
    end

    def product_level_dry_run(top_keys: nil, sample: true, apply: false, baseline: true, max_products: nil, max_roots: nil)
      MH_Thongke.process_selection_cached(true, "p4_delta_product_dry_run_baseline") if baseline && MH_Thongke.respond_to?(:process_selection_cached)
      MH_Thongke.p4_delta_rebuild_watchers if baseline && MH_Thongke.respond_to?(:p4_delta_rebuild_watchers)

      runtime_before = capture_runtime_maps
      applied = false
      current_data = (runtime_before[:data_map] || {}).dup
      current_mat = (runtime_before[:mat_data_map] || {}).dup
      keys = Array(top_keys).map(&:to_s).reject(&:empty?)
      keys = MH_Thongke.p4_delta_changed_top_keys(20) if keys.empty? && MH_Thongke.respond_to?(:p4_delta_changed_top_keys)
      keys = Array(MH_Thongke.p4_delta_tracked_top_keys(1)) if keys.empty? && sample && MH_Thongke.respond_to?(:p4_delta_tracked_top_keys)

      affected_bases = affected_product_bases_for_top_keys(current_data, current_mat, keys)
      product_top_keys = top_keys_for_product_bases(current_data, current_mat, affected_bases)
      roots = MH_Thongke.respond_to?(:p4_delta_root_entities_for_keys) ? MH_Thongke.p4_delta_root_entities_for_keys(product_top_keys) : []
      max_products_i = max_products.to_i
      if max_products_i > 0 && affected_bases.length > max_products_i
        return {
          ok: false,
          phase: "p4b_product_level_dry_run_v1",
          skipped: true,
          skip_reason: "too_many_products",
          changed_top_keys: keys,
          affected_product_bases: affected_bases,
          product_top_key_count: product_top_keys.length,
          root_count: roots.length,
          applied: false,
          watch_status: MH_Thongke.respond_to?(:p4_delta_status) ? MH_Thongke.p4_delta_status : {}
        }
      end
      max_roots_i = max_roots.to_i
      if max_roots_i > 0 && roots.length > max_roots_i
        return {
          ok: false,
          phase: "p4b_product_level_dry_run_v1",
          skipped: true,
          skip_reason: "too_many_roots",
          changed_top_keys: keys,
          affected_product_bases: affected_bases,
          product_top_key_count: product_top_keys.length,
          root_count: roots.length,
          applied: false,
          watch_status: MH_Thongke.respond_to?(:p4_delta_status) ? MH_Thongke.p4_delta_status : {}
        }
      end
      changed = run_pipeline_for_roots(roots, product_bases: affected_bases)
      restore_runtime_maps(runtime_before)

      changed_s = changed[:session]
      changed_data_map = changed_s ? changed_s.data_map : {}
      changed_mat_map = changed_s ? changed_s.mat_data_map : {}
      candidate_data = product_replace_candidate(current_data, changed_data_map, affected_bases)
      candidate_mat = product_replace_candidate(current_mat, changed_mat_map, affected_bases)
      data_diff = diff_summary(candidate_data, current_data, 8)
      mat_diff = diff_summary(candidate_mat, current_mat, 8)
      diff_pass = data_diff[:pass] && mat_diff[:pass]
      applied = apply && diff_pass && apply_product_candidate(candidate_data, candidate_mat)
      runtime_before = nil if applied

      {
        ok: changed[:error].nil?,
        phase: "p4b_product_level_dry_run_v1",
        baseline: !!baseline,
        changed_top_keys: keys,
        affected_product_bases: affected_bases,
        product_top_key_count: product_top_keys.length,
        root_count: roots.length,
        changed_scan_ms: changed[:scan_ms],
        changed_pipeline_ms: changed[:pipeline_ms],
        changed_data_keys: Array(changed[:data_keys]).length,
        changed_mat_keys: Array(changed[:mat_keys]).length,
        product_replace_diff_pass: diff_pass,
        applied: applied,
        data_diff: data_diff,
        mat_diff: mat_diff,
        changed_error: changed[:error],
        watch_status: MH_Thongke.respond_to?(:p4_delta_status) ? MH_Thongke.p4_delta_status : {}
      }
    rescue => e
      {
        ok: false,
        phase: "p4b_product_level_dry_run_v1",
        error: "#{e.class}: #{e.message}",
        backtrace: Array(e.backtrace).first(8)
      }
    ensure
      restore_runtime_maps(runtime_before) if runtime_before
    end
  end

  module P4DeltaSmokeHarness
    module_function

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue
      Time.now.to_f
    end

    def measure
      t0 = now
      value = yield
      [value, ((now - t0) * 1000.0).round(1)]
    end

    def snapshot
      MH_Thongke::P3Harness.snapshot_fingerprint
    end

    def diff(a, b)
      MH_Thongke::P3Harness.diff_fingerprint(a, b)
    end

    def diff_pass?(d)
      MH_Thongke::P3Harness.diff_pass?(d)
    end

    def entity_key(entity)
      defined?(MH_Thongke::P4DeltaTracker) ? MH_Thongke::P4DeltaTracker.entity_key(entity) : nil
    rescue
      nil
    end

    def run_model_refresh
      detect = []
      _, detect_ms = measure do
        detect = MH_Thongke.p4_delta_detect_snapshot_changes if MH_Thongke.respond_to?(:p4_delta_detect_snapshot_changes)
      end
      status = MH_Thongke.process_selection_cached(true, "model")
      {
        status: status,
        detect_ms: detect_ms,
        detect_count: Array(detect).length,
        apply_result: MH_Thongke.respond_to?(:p4_delta_last_apply_result) ? MH_Thongke.p4_delta_last_apply_result : nil
      }
    end

    def operation(model, name)
      model.start_operation(name, true)
      yield
      model.commit_operation
    rescue => e
      model.abort_operation rescue nil
      raise e
    end

    def tracked_root
      keys = MH_Thongke.respond_to?(:p4_delta_tracked_top_keys) ? MH_Thongke.p4_delta_tracked_top_keys(80) : []
      roots = MH_Thongke.respond_to?(:p4_delta_root_entities_for_keys) ? MH_Thongke.p4_delta_root_entities_for_keys(keys) : []
      roots.find { |entity| entity && entity.valid? rescue false }
    end

    def add_temp_root(model, name)
      group = model.active_entities.add_group
      group.name = name if group.respond_to?(:name=)
      entities = group.entities
      points = [
        [0, 0, 0],
        [100.mm, 0, 0],
        [100.mm, 100.mm, 0],
        [0, 100.mm, 0]
      ]
      face = entities.add_face(points)
      face.pushpull(50.mm) if face && face.valid?
      group
    end

    def erase_entity(entity)
      entity.erase! if entity && entity.valid? && entity.respond_to?(:erase!)
    rescue
      nil
    end

    def run_case(label, baseline, mutate, restore)
      MH_Thongke.p4_delta_clear_changed if MH_Thongke.respond_to?(:p4_delta_clear_changed)
      mutate.call
      refresh = nil
      _, inc_ms = measure { refresh = run_model_refresh }
      status = refresh.is_a?(Hash) ? refresh[:status] : refresh
      inc_snap = snapshot
      full_status = nil
      _, full_ms = measure { full_status = MH_Thongke.process_selection_cached(true, "#{label}_full_verify") }
      full_snap = snapshot
      inc_full_diff = diff(inc_snap, full_snap)

      MH_Thongke.p4_delta_clear_changed if MH_Thongke.respond_to?(:p4_delta_clear_changed)
      restore.call
      restore_refresh = nil
      _, restore_inc_ms = measure { restore_refresh = run_model_refresh }
      restore_status = restore_refresh.is_a?(Hash) ? restore_refresh[:status] : restore_refresh
      restore_inc_snap = snapshot
      restore_full_status = nil
      _, restore_full_ms = measure { restore_full_status = MH_Thongke.process_selection_cached(true, "#{label}_restore_full_verify") }
      restore_full_snap = snapshot

      {
        label: label,
        status: status,
        inc_ms: inc_ms,
        detect_ms: refresh.is_a?(Hash) ? refresh[:detect_ms] : nil,
        detect_count: refresh.is_a?(Hash) ? refresh[:detect_count] : nil,
        apply_result: refresh.is_a?(Hash) ? refresh[:apply_result] : nil,
        full_status: full_status,
        full_ms: full_ms,
        diff_inc_full_pass: diff_pass?(inc_full_diff),
        diff_inc_full: inc_full_diff,
        restore_status: restore_status,
        restore_inc_ms: restore_inc_ms,
        restore_detect_ms: restore_refresh.is_a?(Hash) ? restore_refresh[:detect_ms] : nil,
        restore_detect_count: restore_refresh.is_a?(Hash) ? restore_refresh[:detect_count] : nil,
        restore_apply_result: restore_refresh.is_a?(Hash) ? restore_refresh[:apply_result] : nil,
        restore_full_status: restore_full_status,
        restore_full_ms: restore_full_ms,
        diff_restore_full_pass: diff_pass?(diff(restore_inc_snap, restore_full_snap)),
        diff_restore_baseline_pass: diff_pass?(diff(baseline, restore_full_snap))
      }
    end

    def cleanup_temp(model)
      out = {}
      mat = model.materials["P4_SMOKE_MAT"] rescue nil
      if mat
        begin
          model.materials.remove(mat)
          out[:material] = true
        rescue => e
          out[:material] = "#{e.class}: #{e.message}"
        end
      else
        out[:material] = false
      end

      layer = model.layers["P4_SMOKE_TAG"] rescue nil
      if layer
        begin
          model.layers.remove(layer, model.layers[0])
          out[:layer] = true
        rescue => e
          out[:layer] = "#{e.class}: #{e.message}"
        end
      else
        out[:layer] = false
      end
      out
    end

    def run(include_material: true)
      model = Sketchup.active_model
      MH_Thongke.process_selection_cached(true, "p4_smoke_harness_baseline")
      MH_Thongke.p4_delta_rebuild_watchers if MH_Thongke.respond_to?(:p4_delta_rebuild_watchers)
      MH_Thongke.p4_delta_clear_changed if MH_Thongke.respond_to?(:p4_delta_clear_changed)
      baseline = snapshot
      root = tracked_root
      raise "No tracked root for P4 smoke harness" unless root

      root_key = entity_key(root)
      results = []
      temp_roots = []

      temp_added = nil
      results << run_case(
        "add_root",
        baseline,
        -> { operation(model, "P4 smoke add root") { temp_added = add_temp_root(model, "P4_SMOKE_ADD_ROOT"); temp_roots << temp_added } },
        -> { operation(model, "P4 smoke remove added root") { erase_entity(temp_added) } }
      )

      temp_delete = nil
      operation(model, "P4 smoke seed delete root") { temp_delete = add_temp_root(model, "P4_SMOKE_DELETE_ROOT"); temp_roots << temp_delete }
      MH_Thongke.process_selection_cached(true, "p4_smoke_delete_seed_baseline")
      MH_Thongke.p4_delta_rebuild_watchers if MH_Thongke.respond_to?(:p4_delta_rebuild_watchers)
      delete_baseline = snapshot
      results << run_case(
        "delete_temp_root",
        delete_baseline,
        -> { operation(model, "P4 smoke delete temp root") { erase_entity(temp_delete) } },
        -> { operation(model, "P4 smoke restore deleted temp root") { temp_delete = add_temp_root(model, "P4_SMOKE_DELETE_ROOT"); temp_roots << temp_delete } }
      )
      operation(model, "P4 smoke cleanup delete seed") { erase_entity(temp_delete) }
      MH_Thongke.process_selection_cached(true, "p4_smoke_post_delete_seed_cleanup")
      MH_Thongke.p4_delta_rebuild_watchers if MH_Thongke.respond_to?(:p4_delta_rebuild_watchers)

      if root.respond_to?(:name) && root.respond_to?(:name=)
        old_name = root.name.to_s
        new_name = old_name.empty? ? "P4_SMOKE_NAME" : "#{old_name}_P4SMOKE"
        results << run_case(
          "rename_root",
          baseline,
          -> { operation(model, "P4 smoke rename root") { root.name = new_name } },
          -> { operation(model, "P4 smoke restore root name") { root.name = old_name } }
        )
      end

      if root.respond_to?(:transformation) && root.respond_to?(:transform!)
        old_tr = root.transformation
        move = Geom::Transformation.translation([10.mm, 0, 0])
        results << run_case(
          "move_root",
          baseline,
          -> { operation(model, "P4 smoke move root") { root.transform!(move) } },
          -> { operation(model, "P4 smoke restore root transform") { root.transformation = old_tr } }
        )
      end

      if root.respond_to?(:hidden?) && root.respond_to?(:hidden=)
        old_hidden = root.hidden?
        results << run_case(
          "hidden_root",
          baseline,
          -> { operation(model, "P4 smoke hidden root") { root.hidden = !old_hidden } },
          -> { operation(model, "P4 smoke restore hidden root") { root.hidden = old_hidden } }
        )
      end

      if root.respond_to?(:layer=)
        old_layer = root.layer rescue nil
        smoke_layer = model.layers["P4_SMOKE_TAG"] || model.layers.add("P4_SMOKE_TAG")
        if old_layer && smoke_layer && smoke_layer != old_layer
          results << run_case(
            "layer_root",
            baseline,
            -> { operation(model, "P4 smoke layer root") { root.layer = smoke_layer } },
            -> { operation(model, "P4 smoke restore layer root") { root.layer = old_layer } }
          )
        end
      end

      if root.respond_to?(:set_attribute)
        dict = "MH_Thongke"
        key = "ngay_dat"
        sentinel = Object.new
        old_attr = root.get_attribute(dict, key, sentinel)
        new_attr = old_attr.to_s == "06/06/2026" ? "07/06/2026" : "06/06/2026"
        restore_attr = lambda do
          if old_attr.equal?(sentinel)
            root.delete_attribute(dict, key) rescue root.set_attribute(dict, key, nil)
          else
            root.set_attribute(dict, key, old_attr)
          end
        end
        results << run_case(
          "attribute_ngay_dat_root",
          baseline,
          -> { operation(model, "P4 smoke attr ngay_dat root") { root.set_attribute(dict, key, new_attr) } },
          -> { operation(model, "P4 smoke restore attr ngay_dat root") { restore_attr.call } }
        )
      end

      if include_material && root.respond_to?(:material=)
        old_material = root.material rescue nil
        mat = model.materials["P4_SMOKE_MAT"] || model.materials.add("P4_SMOKE_MAT")
        mat.color = Sketchup::Color.new(255, 0, 64) rescue nil
        results << run_case(
          "material_root",
          baseline,
          -> { operation(model, "P4 smoke material root") { root.material = mat } },
          -> { operation(model, "P4 smoke restore material root") { root.material = old_material } }
        )
      end

      operation(model, "P4 smoke cleanup temp roots") do
        temp_roots.each { |entity| erase_entity(entity) }
      end
      cleanup = cleanup_temp(model)
      final_status = MH_Thongke.process_selection_cached(true, "p4_smoke_harness_final_full")
      final_snap = snapshot
      MH_Thongke.p4_delta_clear_changed if MH_Thongke.respond_to?(:p4_delta_clear_changed)

      {
        ok: results.all? { |row| row[:diff_inc_full_pass] && row[:diff_restore_full_pass] && row[:diff_restore_baseline_pass] },
        phase: "p4b_smoke_real_ops_harness_v1",
        root_key: root_key,
        root_class: root.class.to_s,
        results: results,
        cleanup: cleanup,
        final_full_status: final_status,
        final_baseline_pass: diff_pass?(diff(baseline, final_snap)),
        watch_status: MH_Thongke.respond_to?(:p4_delta_status) ? MH_Thongke.p4_delta_status : {}
      }
    rescue => e
      {
        ok: false,
        phase: "p4b_smoke_real_ops_harness_v1",
        error: "#{e.class}: #{e.message}",
        backtrace: Array(e.backtrace).first(8)
      }
    end
  end

  def self.p4_delta_merge_dry_run(top_keys: nil, sample: true)
    P4DeltaMergeHarness.dry_run(top_keys: top_keys, sample: sample)
  end

  def self.p4_delta_product_dry_run(top_keys: nil, sample: true, baseline: true, max_products: nil, max_roots: nil)
    P4DeltaMergeHarness.product_level_dry_run(
      top_keys: top_keys,
      sample: sample,
      baseline: baseline,
      max_products: max_products,
      max_roots: max_roots
    )
  end

  def self.p4_delta_product_apply(top_keys: nil, sample: false, baseline: true, max_products: nil, max_roots: nil)
    P4DeltaMergeHarness.product_level_dry_run(
      top_keys: top_keys,
      sample: sample,
      apply: true,
      baseline: baseline,
      max_products: max_products,
      max_roots: max_roots
    )
  end

  def self.p4_delta_smoke_real_ops(include_material: true)
    P4DeltaSmokeHarness.run(include_material: include_material)
  end
end
