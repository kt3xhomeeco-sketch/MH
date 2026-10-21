# encoding: utf-8
# MH_Thongke::Engine::ProductMatcher
# Unified matching engine — thay the ExcelMatcher.
# Extract DATA logic tu bom_tables_rendering.rb, tach HTML ra.
# Dung chung cho ca main table va import dialog.

require 'set'

module MH_Thongke
  module Engine
    module ProductMatcher

      MatchedRow = Struct.new(:model, :excel, :status, :target_name, :exact, :spec, keyword_init: true)
      ExcelOnlyRow = Struct.new(:excel, :status, :hw, :spec, :target_name, keyword_init: true)
      ModelOnlyRow = Struct.new(:model, :status, keyword_init: true)

      ProductDetail = Struct.new(:product_code, :matched, :excel_only, :model_only, keyword_init: true)

      ProductMatchResult = Struct.new(
        :merged_data_map,
        :product_details,
        :matched_rows,
        :updated_rules,
        keyword_init: true
      )

      # =================================================================
      # match_all: Batch match tat ca products — thay the ExcelMatcher.match()
      # =================================================================
      def self.match_all(data_map:, imported_rows:, group_by:, match_rules:, general_rules:)
        return ProductMatchResult.new(
          merged_data_map: data_map,
          product_details: {},
          matched_rows: imported_rows,
          updated_rules: match_rules
        ) unless imported_rows && !imported_rows.empty?

        # Index excel rows by product_code_base
        excel_by_base = Hash.new { |h, k| h[k] = [] }
        Array(imported_rows).each do |ex|
          code = ex[:ma_sp].to_s.strip
          next if code.empty?
          base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(code) : code.sub(/\.\d+\z/, "")
          excel_by_base[base] << ex unless base.to_s.empty?
        end

        # Collect all product bases from model
        model_bases = Set.new
        data_map.each_value do |row|
          p = row[:actual_product] || row[:product]
          base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(p.to_s) : p.to_s.sub(/\.\d+\z/, "")
          model_bases << base unless base.to_s.empty?
        end

        # All product bases to process (union of model + excel)
        all_bases = (model_bases.to_a + excel_by_base.keys).uniq

        product_details = {}
        global_matched_keys = Set.new

        all_bases.each do |base|
          excel_items = excel_by_base[base] || []
          detail = match_product(base, data_map, excel_items, group_by, general_rules)
          product_details[base] = detail

          # Mark matched excel rows
          detail.matched.each do |mr|
            next unless mr.excel
            mr.excel[:_matched] = true
          end
        end

        # Update data_map with match results
        merged = data_map.dup
        product_details.each do |base, detail|
          # Update status for matched model items
          detail.matched.each do |mr|
            next unless mr.model
            model_key = find_data_map_key(merged, mr.model)
            next unless model_key
            row = merged[model_key]
            row[:trang_thai] = mr.status
            row[:new_name] = (mr.status == "UPDATE" && mr.target_name != mr.model[:name]) ? mr.target_name : ""
          end

          # Update status for model-only items
          detail.model_only.each do |mo|
            model_key = find_data_map_key(merged, mo.model)
            next unless model_key
            merged[model_key][:trang_thai] = mo.status
          end

          # Add excel-only items as "missing" rows
          detail.excel_only.each do |eo|
            hw = eo.hw.to_s
            next if hw.empty?
            missing_key = "MISSING_#{base}_#{MH_Thongke.import_name_norm(hw)}"
            next if merged.key?(missing_key)
            merged[missing_key] = {
              name: hw,
              product: base,
              actual_product: base,
              ten_sp: (eo.excel[:ten_sp] || "").to_s,
              ghi_chu: (eo.excel[:ghi_chu] || "").to_s,
              ngay_dat: "",
              trang_thai: eo.status,
              new_name: "",
              layer: "-",
              count: eo.excel[:qty].to_i,
              length: 0.0,
              sel_count: 0,
              sel_length: 0.0,
              unit: "Cái",
              type: :count,
              entities: [],
              stat_entities: [],
              length_items: [],
              last_modified: "",
              is_missing: true
            }
          end
        end

        ProductMatchResult.new(
          merged_data_map: merged,
          product_details: product_details,
          matched_rows: imported_rows,
          updated_rules: match_rules
        )
      end

      # =================================================================
      # match_product: Core per-product matching — tra ve data, KHONG HTML
      # =================================================================
      def self.match_product(product_code, data_map, excel_items, group_by, general_rules)
        model_items = grouped_model_items(product_code, data_map, group_by)
        grouped_excel = MH_Thongke.respond_to?(:mini_group_excel_items) ?
          MH_Thongke.mini_group_excel_items(excel_items.reject { |ex| ex[:kind].to_s == "VL" }, true) :
          excel_items.reject { |ex| ex[:kind].to_s == "VL" }

        matched = []
        excel_only = []
        model_only = []
        matched_model_keys = []

        grouped_excel.each do |ex|
          item = prepare_excel_item(ex)
          model, target_name, duplicate_used = match_model_item(product_code, model_items, item, matched_model_keys)
          model = nil if model && (model[:ids] || []).empty? && !model[:virtual]
          next if duplicate_used && !model

          if model
            model_key = model_item_key(model)
            matched_model_keys << model_key unless matched_model_keys.include?(model_key)
            exact = MH_Thongke.import_name_norm(model[:name]) == MH_Thongke.import_name_norm(target_name)
            status = MH_Thongke.resolve_mini_matched_status_key(product_code, "PK", model[:name], target_name, item[:spec], exact)
            matched << MatchedRow.new(model: model, excel: ex, status: status, target_name: target_name, exact: exact, spec: item[:spec])
          else
            status = MH_Thongke.resolve_mini_excel_only_status_key(product_code, "PK", false, ex[:hw_name].to_s, ex[:spec].to_s)
            excel_only << ExcelOnlyRow.new(excel: ex, status: status, hw: ex[:hw_name].to_s, spec: ex[:spec].to_s, target_name: item[:target_name])
          end
        end

        # Unmatched model items
        model_items.each do |m|
          key = model_item_key(m)
          next if matched_model_keys.include?(key)
          next if (m[:ids] || []).empty? && !m[:virtual]
          status = MH_Thongke.resolve_mini_model_only_status_key(product_code, "PK", m[:name])
          model_only << ModelOnlyRow.new(model: m, status: status)
          matched_model_keys << key
        end

        ProductDetail.new(
          product_code: product_code,
          matched: matched,
          excel_only: excel_only,
          model_only: model_only
        )
      end

      # =================================================================
      # Helper: group model items by kind+name (from mini_pk_grouped_model_items)
      # =================================================================
      def self.grouped_model_items(product_code, data_map = nil, group_by = nil)
        if data_map.nil? && MH_Thongke.respond_to?(:mini_pk_grouped_model_items)
          return MH_Thongke.mini_pk_grouped_model_items(product_code)
        end

        items = model_items_for_product(product_code, data_map, group_by)
        grouped = {}
        items.select { |m| m[:kind].to_s != "VL" }.each do |m|
          key = "#{m[:kind]}:#{MH_Thongke.import_name_norm(m[:name])}"
          grouped[key] ||= m.dup.merge(section: "", qty: 0.0, rows: [], ids: [])
          target = grouped[key]
          target[:qty] = target[:qty].to_f + m[:qty].to_f
          target[:unit] = m[:unit].to_s unless m[:unit].to_s.empty?
          target[:editable] = target[:editable] != false && m[:editable] != false
          target[:virtual] = !!target[:virtual] || !!m[:virtual]
          target[:virtual_key] ||= m[:virtual_key]
          target[:virtual_source] ||= m[:virtual_source]
          target[:rows] = Array(target[:rows]) + Array(m[:rows])
          target[:ids] = (Array(target[:ids]) + Array(m[:ids])).compact.uniq
        end
        grouped.values
      end

      # =================================================================
      # Helper: get model items for a product from data_map
      # =================================================================
      def self.model_items_for_product(product_code, data_map, group_by)
        return [] unless data_map.is_a?(Hash)
        base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(product_code) : product_code.to_s.sub(/\.\d+\z/, "")
        exact = MH_Thongke.respond_to?(:product_code_exact) ? MH_Thongke.product_code_exact(product_code) : product_code.to_s.strip.upcase

        data_map.values.select do |row|
          next false if row[:is_missing]
          p = (row[:actual_product] || row[:product]).to_s
          pb = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(p) : p.sub(/\.\d+\z/, "")
          pe = MH_Thongke.respond_to?(:product_code_exact) ? MH_Thongke.product_code_exact(p) : p.strip.upcase
          pe == exact || pb == base
        end.map do |row|
          {
            name: row[:name].to_s,
            kind: "PK",
            qty: row[:count].to_f,
            unit: row[:unit].to_s,
            editable: true,
            virtual: !!row[:virtual] || !row[:virtual_source].to_s.empty?,
            virtual_key: row[:virtual_key],
            virtual_source: row[:virtual_source],
            ids: (row[:stat_entities] || []).map { |se| se.is_a?(Array) ? (se[0].entityID rescue nil) : nil }.compact,
            rows: [row]
          }
        end
      end

      # =================================================================
      # Helper: prepare excel item for matching (from mini_pk_prepare_excel_item)
      # =================================================================
      def self.prepare_excel_item(ex, section_filter = nil)
        hw = ex[:hw_name].to_s
        spec = ex[:spec].to_s.strip
        section = ex[:section].to_s.strip
        section = section_filter.to_s.strip if section.empty? && !section_filter.to_s.strip.empty?
        target_name = MH_Thongke.respond_to?(:import_display_name) ? MH_Thongke.import_display_name(hw, spec) : hw
        {
          hw: hw,
          spec: spec,
          section: section,
          target_name: target_name,
          norm_hw: MH_Thongke.import_name_norm(hw),
          norm_target: MH_Thongke.import_name_norm(target_name),
          excel_qty: ex[:qty].to_i
        }
      end

      # =================================================================
      # Core matching: find model item for an excel item (from mini_pk_match_model_item)
      # =================================================================
      def self.match_model_item(product_code, model_items, item, matched_model_keys)
        hw = item[:hw]
        spec = item[:spec]
        target_name = item[:target_name]
        norm_hw = item[:norm_hw]
        norm_target = item[:norm_target]
        duplicate_used = false

          model = model_items.find do |m|
            model_norm = MH_Thongke.import_name_norm(m[:name])
            matched = model_norm == norm_target ||
                      (spec.to_s.strip.empty? && model_norm == norm_hw) ||
                      MH_Thongke.mini_pk_model_name_match?(product_code, m[:name], hw, target_name, spec)
          if matched && matched_model_keys.include?(model_item_key(m))
            duplicate_used = true
            next false
          end
          matched
        end

        [model, target_name, duplicate_used]
      end

      # =================================================================
      # Helpers
      # =================================================================
      def self.model_item_key(model)
        "#{model[:kind]}:#{MH_Thongke.import_name_norm(model[:name])}"
      end

      def self.find_data_map_key(data_map, model_item)
        return nil unless model_item && data_map.is_a?(Hash)
        name_norm = MH_Thongke.import_name_norm(model_item[:name])
        data_map.each do |key, row|
          next if row[:is_missing]
          if MH_Thongke.import_name_norm(row[:name]) == name_norm
            p = (row[:actual_product] || row[:product]).to_s
            return key
          end
        end
        nil
      end

    end
  end
end
