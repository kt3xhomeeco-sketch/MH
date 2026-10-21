# encoding: utf-8
# MH_Thongke — Pipeline Stages
# process_selection pipeline tach thanh cac stage co ten ro rang.
# Moi stage nhan session (s), doc/ghi qua s.xxx, va co the chay doc lap.
# Goi theo thu tu: stage_1_scan → stage_2_excel_match → ... → stage_9_finalize

module MH_Thongke
  module Pipeline

    # Stage 1: Scan model → data_map, mat_data_map, prod_groups
    def self.stage_scan_model(s, model, selection, root_entities: nil)
      scan_result = MH_Thongke::Engine::ModelScanner.scan(
        model: model,
        selection: selection,
        group_by: s.group_by,
        hidden_list: s.hidden_list,
        unit_overrides: s.unit_overrides,
        led_power_factor: MH_Thongke.instance_variable_get(:@led_power_factor),
        psu_list: MH_Thongke.instance_variable_get(:@psu_list),
        root_entities: root_entities
      )
      s.data_map           = scan_result.data_map
      s.mat_data_map       = scan_result.mat_data_map
      s.prod_groups        = scan_result.prod_groups
      s.all_item_names     = scan_result.all_item_names
      s.all_item_names_set = scan_result.all_item_names_set
      s.led_per_product    = scan_result.led_per_product
    end

    # Stage 2: Match data_map against Excel import rows (unified ProductMatcher)
    def self.stage_excel_match(s)
      return unless s.imported_excel_data && !s.imported_excel_data.empty?

      s.general_rules ||= MH_Thongke::DEFAULT_GENERAL_RULES.dup
      match_result = MH_Thongke::Engine::ProductMatcher.match_all(
        data_map: s.data_map,
        imported_rows: s.imported_excel_data,
        group_by: s.group_by,
        match_rules: s.match_rules || {},
        general_rules: s.general_rules
      )
      s.data_map              = match_result.merged_data_map
      s.imported_excel_data   = match_result.matched_rows
      s.match_rules           = match_result.updated_rules
      s.product_match_details = match_result.product_details || {}
    end

    # Stage 3: Material status + completion percent
    def self.stage_material_status(s)
      MH_Thongke.apply_obj_material_status! if MH_Thongke.respond_to?(:apply_obj_material_status!)
      MH_Thongke.apply_material_completion_percent! if MH_Thongke.respond_to?(:apply_material_completion_percent!)
    end

    # Stage 4: Auto-fill ten_sp (product name) from Excel data
    def self.stage_autofill_product_names(s)
      data_map = s.data_map
      mat_data_map = s.mat_data_map
      all_items = data_map.values + mat_data_map.values

      if MH_Thongke.respond_to?(:import_excel_product_name_for)
        all_items.each do |v|
          products = Array(v[:product_list]) + [v[:actual_product], v[:product]]
          names = products.map { |p| MH_Thongke.import_excel_product_name_for(p, false) }.reject(&:empty?).uniq
          next if names.empty?
          v[:ten_sp_list] = names if v[:ten_sp_list].is_a?(Array) || s.group_by.to_s == "NAME"
          v[:ten_sp] = names.size == 1 ? names.first : ""
        end
      end

      product_names = {}
      product_base_names = {}
      all_items.each do |v|
        next unless v[:ten_sp] && !v[:ten_sp].strip.empty? && v[:actual_product]
        product = v[:actual_product].to_s
        name = v[:ten_sp].strip
        product_names[product] ||= name
        base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(product) : product.sub(/\.\d+\z/, "")
        product_base_names[base] ||= name unless base.to_s.empty?
      end
      all_items.each do |v|
        next unless v[:ten_sp].to_s.strip.empty? && v[:actual_product]
        product = v[:actual_product].to_s
        base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(product) : product.sub(/\.\d+\z/, "")
        v[:ten_sp] = product_names[product] || product_base_names[base] if product_names[product] || product_base_names[base]
      end
    end

    # Stage 5: Merge name-grouped accessories + record known names + filter hidden
    def self.stage_merge_and_filter(s)
      MH_Thongke.merge_name_grouped_accessories! if MH_Thongke.respond_to?(:merge_name_grouped_accessories!)
      # Sync data_map back to session after possible merge rewrite
      s.data_map = MH_Thongke.instance_variable_get(:@data_map) if MH_Thongke.respond_to?(:merge_name_grouped_accessories!)

      known_names = (s.all_item_names || []) + s.data_map.values.map { |row| row[:name] } + (s.hidden_list || [])
      MH_Thongke.record_known_pk_names(known_names, true) if MH_Thongke.respond_to?(:record_known_pk_names)
      s.data_map.delete_if { |_, row| MH_Thongke.hidden_item_name?(row[:name].to_s) }
    end

    # Stage 6: Apply overrides (meta, order date, nesting date)
    def self.stage_apply_overrides(s)
      data_rows = s.data_map.values
      mat_rows = s.mat_data_map.values
      if MH_Thongke.respond_to?(:apply_overrides_to_rows!)
        MH_Thongke.apply_overrides_to_rows!(data_rows, mat_rows)
      else
        data_rows.each { |row| MH_Thongke.apply_row_meta_override("acc", row) } if MH_Thongke.respond_to?(:apply_row_meta_override)
        mat_rows.each { |row| MH_Thongke.apply_row_meta_override("mat", row) } if MH_Thongke.respond_to?(:apply_row_meta_override)
        data_rows.each { |row| MH_Thongke.apply_order_date_override("acc", row) } if MH_Thongke.respond_to?(:apply_order_date_override)
        mat_rows.each { |row| MH_Thongke.apply_order_date_override("mat", row) } if MH_Thongke.respond_to?(:apply_order_date_override)
      end
      MH_Thongke.apply_material_order_date_from_nesting_file! if MH_Thongke.respond_to?(:apply_material_order_date_from_nesting_file!)
    end

    # Stage 7: Normalize status text + recompute back-import diff
    def self.stage_normalize_status(s)
      s.data_map.values.each { |row| row[:trang_thai] = MH_Thongke.status_text(row[:trang_thai]) } if MH_Thongke.respond_to?(:status_text)
      s.mat_data_map.values.each { |row| row[:trang_thai] = MH_Thongke.status_text(row[:trang_thai]) } if MH_Thongke.respond_to?(:status_text)
      MH_Thongke.recompute_back_import_diff! if MH_Thongke.respond_to?(:recompute_back_import_diff!)
    end

    # Stage 8: Clean excel-only duplicate rows (ProductMatcher handles status directly)
    def self.stage_final_status_rematch(s)
      # apply_mini_pk_status_rematch! removed — ProductMatcher.match_all already
      # produces correct statuses via the same matching logic.

      if s.data_map.is_a?(Hash)
        matched_norms = Set.new
        s.data_map.each_value do |row|
          next if row[:is_missing]
          sk = MH_Thongke.status_key(row[:trang_thai]) rescue row[:trang_thai].to_s
          matched_norms << MH_Thongke.import_name_norm(row[:name]) if sk == "OK"
        end
        s.data_map.delete_if do |_key, row|
          next false unless row[:is_missing]
          sk = MH_Thongke.status_key(row[:trang_thai]) rescue row[:trang_thai].to_s
          next false unless sk == "THIEU"
          matched_norms.include?(MH_Thongke.import_name_norm(row[:name]))
        end
      end
    end

    # Stage 9: Sort + compute final report items + export
    def self.stage_finalize(s, model)
      nat_sort = ->(v) {
        [ v[:product].to_s.split(/(\d+)/).map { |p| p =~ /\d/ ? [1, p.to_i] : [0, p.downcase] },
          v[:name].to_s.split(/(\d+)/).map    { |p| p =~ /\d/ ? [1, p.to_i] : [0, p.downcase] } ]
      }
      s.current_report_items = s.data_map.values.sort_by(&nat_sort)
      s.current_mat_items    = s.mat_data_map.values.sort_by(&nat_sort)

      MH_Thongke.resolve_snapshot_export_fields! if MH_Thongke.respond_to?(:resolve_snapshot_export_fields!)

      s.process_selection_cache_sig =
        if MH_Thongke.respond_to?(:model_base_signature)
          MH_Thongke.model_base_signature
        else
          [
            (model.guid rescue ""),
            (model.active_entities.length rescue 0),
            s.current_report_items.size,
            s.current_mat_items.size
          ].join("::")
        end

      # Temporarily disabled: avoid writing data/final_stamped_report.json on every pipeline run/save.
    end

    # === Run full pipeline (all stages) ===
    def self.run(s, model, selection)
      stage_scan_model(s, model, selection)
      stage_excel_match(s)
      stage_material_status(s)
      stage_autofill_product_names(s)
      stage_merge_and_filter(s)
      stage_apply_overrides(s)
      stage_normalize_status(s)
      stage_final_status_rematch(s)
      stage_finalize(s, model)
      s.last_full_scan_at = Time.now.to_f
      s.reset_dirty!
    end

    # === Run partial pipeline (skip scan + excel match, reuse existing data) ===
    # Goi khi chi thay doi overrides/rules/hidden — khong can rescan model.
    def self.run_partial(s, model)
      return unless s.data_map && !s.data_map.empty?

      stage_apply_overrides(s)
      stage_normalize_status(s)
      stage_final_status_rematch(s)
      stage_finalize(s, model)
      s.dirty_overrides = false
      s.dirty_status = false
      s.dirty_html = false
    end

    # === Run incremental: chon mode dua tren dirty flags ===
    def self.run_incremental(s, model, selection)
      if s.needs_full_pipeline?
        run(s, model, selection)
        :full_scan
      elsif s.needs_partial_pipeline?
        run_partial(s, model)
        :partial
      elsif s.needs_selection_update_only?
        MH_Thongke.fast_update_selection if MH_Thongke.respond_to?(:fast_update_selection)
        s.dirty_selection = false
        s.dirty_html = false
        :fast_update
      else
        :no_change
      end
    end

  end
end
