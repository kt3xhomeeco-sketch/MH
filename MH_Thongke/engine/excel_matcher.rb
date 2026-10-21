# encoding: utf-8

module MH_Thongke
  module Engine
    module ExcelMatcher
      MatchResult = Struct.new(
        :merged_data_map,
        :matched_rows,
        :updated_rules,
        keyword_init: true
      )

      def self.match(data_map:, imported_rows:, group_by:, match_rules:, general_rules: nil)
        working_map = {}
        (data_map || {}).each do |key, row|
          working_map[key] = row.is_a?(Hash) ? row.dup : row
        end

        working_rows = Array(imported_rows).map { |row| row.is_a?(Hash) ? row.dup : row }
        working_rows.each { |ex| ex.delete(:matched) if ex.respond_to?(:delete) }

        working_rules = match_rules.is_a?(Hash) ? match_rules.dup : {}
        effective_general_rules =
          if general_rules.is_a?(Hash) && !general_rules.empty?
            general_rules
          elsif MH_Thongke.const_defined?(:DEFAULT_GENERAL_RULES)
            MH_Thongke::DEFAULT_GENERAL_RULES.dup
          else
            {}
          end

        excel_pk_rows = working_rows.reject { |ex| ex[:kind].to_s == "VL" }
        excel_pk_by_masp = {}
        excel_pk_rows.each do |ex|
          key = ex[:ma_sp].to_s.strip
          base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(key) : key.sub(/\.\d+\z/, "")
          base = key if base.to_s.empty?
          (excel_pk_by_masp[base] ||= []) << ex
        end

        # Collect product bases present in the model to avoid creating
        # excel-only rows for products not in the current selection.
        model_product_bases = Set.new
        working_map.each_value do |row|
          next unless row.is_a?(Hash)
          product = row[:actual_product].to_s
          next if product.empty?
          base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(product) : product.sub(/\.\d+\z/, "")
          model_product_bases << base unless base.to_s.empty?
        end

        # Memoization cache for expensive name matching (avoids O(n²) redundant checks)
        match_memo = {}

        working_map.values.each do |row|
          su_name = row[:name].to_s
          su_words = su_name.downcase.split
          base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(row[:actual_product].to_s) : row[:actual_product].to_s.sub(/\.\d+\z/, "")
          base = row[:actual_product].to_s if base.to_s.empty?
          ex_candidates = excel_pk_by_masp[base] || []
          best_ex = nil
          best_score = 0
          best_special_name = nil

          ex_candidates.each do |ex|
            memo_key = "#{row[:actual_product]}|#{su_name}|#{ex[:hw_name]}|#{ex[:spec]}"
            matched = match_memo.key?(memo_key) ? match_memo[memo_key] : (match_memo[memo_key] = pk_matches_excel_like_mini?(row[:actual_product], su_name, ex))
            if matched
              best_ex = ex
              best_score = 1000
              best_special_name = nil
              break
            end

          end

          if best_ex
            rule_key = "#{row[:actual_product]}|#{su_name.downcase.strip}"
            if working_rules[rule_key]
              rule = working_rules[rule_key]
              if rule["ex_name"].to_s.downcase.strip == best_ex[:hw_name].to_s.downcase.strip
                if rule["action"] == "keep" || rule["action"] == "update"
                  row[:trang_thai] = "OK"
                  row[:ten_sp] = best_ex[:ten_sp] if row[:ten_sp].to_s.empty?
                  best_ex[:matched] = true
                  next
                end
              else
                working_rules.delete(rule_key)
              end
            end

            ex_name_lower = best_ex[:hw_name].to_s.downcase
            ignore_hit = Array(effective_general_rules["ignore_keywords"]).any? { |kw| ex_name_lower.include?(kw.to_s.downcase) }
            if ignore_hit
              row[:trang_thai] = "OK"
              row[:ten_sp] = best_ex[:ten_sp] if row[:ten_sp].to_s.empty?
              best_ex[:matched] = true
              next
            end

            keep_nums_patterns = Array(effective_general_rules["keep_numbers_patterns"])
            # So khop khong dau (giong cached_norm cua engine) de bat ca "ray am" lan
            # cac bien the sai dau pho bien trong du lieu nhu "ray am" / "RAY AM".
            su_name_norm = MH_Thongke.cached_norm(su_name)
            is_keep_nums = keep_nums_patterns.any? do |pt|
              pt_norm = MH_Thongke.cached_norm(pt)
              !pt_norm.empty? && su_name_norm.start_with?(pt_norm)
            end
            number_words = []
            if is_keep_nums && best_special_name.nil?
              ex_words_dn = best_ex[:hw_name].to_s.downcase.split
              number_words = su_name.split.select { |w| w =~ /^\d+\w*$/ && !ex_words_dn.include?(w.downcase) }
            end

            new_name = pk_update_target_name(best_ex, best_special_name)
            new_name = "#{new_name} #{number_words.join(' ')}" unless number_words.empty?
            normalize = ->(s) { s.to_s.gsub(/\s*[\-]\s*/, " ").gsub(/\s+/, " ").strip.downcase }
            norm_old = normalize.call(su_name)
            norm_new = normalize.call(new_name)
            old_text_tokens = norm_old.split.reject { |t| t =~ /\d/ }
            new_text_tokens = norm_new.split.reject { |t| t =~ /\d/ }
            candidate_targets = pk_match_target_names(best_ex, new_name)
            matched_like_mini = candidate_targets.any? do |target|
              pk_match_ok_like_mini?(row[:actual_product], su_name, target, best_ex[:spec])
            end

            if matched_like_mini
              row[:trang_thai] = "OK"
            elsif norm_old == norm_new || MH_Thongke.import_name_norm(su_name) == MH_Thongke.import_name_norm(best_ex[:hw_name])
              row[:trang_thai] = "OK"
            elsif (new_text_tokens - old_text_tokens).empty? && (norm_new.split.select { |t| t =~ /\d/ } - norm_old.split.select { |t| t =~ /\d/ }).empty?
              row[:trang_thai] = "OK"
            else
              row[:trang_thai] = "UPDATE"
              row[:new_name] = new_name
            end
            row[:ten_sp] = best_ex[:ten_sp] if row[:ten_sp].to_s.empty?
            best_ex[:matched] = true
          else
            fallback_ex = ex_candidates.find do |ex|
              memo_key = "#{row[:actual_product]}|#{su_name}|#{ex[:hw_name]}|#{ex[:spec]}"
              match_memo.key?(memo_key) ? match_memo[memo_key] : (match_memo[memo_key] = pk_matches_excel_like_mini?(row[:actual_product], su_name, ex))
            end
            if fallback_ex
              row[:trang_thai] = "OK"
              row[:ten_sp] = fallback_ex[:ten_sp] if row[:ten_sp].to_s.empty?
              fallback_ex[:matched] = true
              next
            end

            row[:trang_thai] = pk_accept_rule_ok_for_status?(row[:actual_product], su_name, "", "") ? "OK" : "NO_SPEC"
          end
        end

        excel_pk_rows.each do |ex|
          next if ex[:matched]
          # Only create missing rows for products present in the model
          ex_base = MH_Thongke.respond_to?(:product_code_base) ? MH_Thongke.product_code_base(ex[:ma_sp].to_s) : ex[:ma_sp].to_s.sub(/\.\d+\z/, "")
          next unless model_product_bases.include?(ex_base)

          new_key = group_by == "NAME" ? "NEW_NAME_#{MH_Thongke.import_name_norm(ex[:hw_name])}" : "NEW_#{ex[:ma_sp]}_#{ex[:hw_name]}"
          if working_map[new_key]
            working_map[new_key][:count] = working_map[new_key][:count].to_i + 1
            working_map[new_key][:trang_thai] = "THIEU"
          else
            working_map[new_key] = {
              name: ex[:hw_name], product: (group_by == "NAME" ? "--" : ex[:ma_sp]),
              actual_product: ex[:ma_sp], ten_sp: ex[:ten_sp], ghi_chu: "", ngay_dat: "",
              trang_thai: "THIEU", new_name: "", layer: "-", count: 1, length: 0.0,
              sel_count: 0, sel_length: 0.0, unit: "Cái",
              type: :count, entities: [], stat_entities: [], length_items: [],
              last_modified: "", is_missing: true
            }
          end

          if group_by == "NAME"
            working_map[new_key][:product_list] ||= []
            working_map[new_key][:ten_sp_list] ||= []
            working_map[new_key][:product_list] << ex[:ma_sp] unless ex[:ma_sp].to_s.empty? || working_map[new_key][:product_list].include?(ex[:ma_sp])
            working_map[new_key][:ten_sp_list] << ex[:ten_sp] unless ex[:ten_sp].to_s.empty? || working_map[new_key][:ten_sp_list].include?(ex[:ten_sp])
          end
        end

        MatchResult.new(
          merged_data_map: working_map,
          matched_rows: working_rows,
          updated_rules: working_rules
        )
      end

      def self.pk_accept_rule_ok_for_status?(product_code, model_name, target_name, spec = "")
        MH_Thongke.respond_to?(:pk_rule_ok?) ? MH_Thongke.pk_rule_ok?(product_code, model_name, target_name, spec) : false
      rescue
        false
      end
      private_class_method :pk_accept_rule_ok_for_status?

      def self.pk_match_ok_like_mini?(product_code, model_name, target_name, spec = "")
        MH_Thongke.respond_to?(:pk_match_ok?) ? MH_Thongke.pk_match_ok?(product_code, model_name, target_name, spec) : false
      rescue
        false
      end
      private_class_method :pk_match_ok_like_mini?

      def self.pk_match_target_names(ex_row, special_target = nil)
        names = []
        names << special_target.to_s
        names << (MH_Thongke.respond_to?(:import_display_name) ? MH_Thongke.import_display_name(ex_row[:hw_name], ex_row[:spec]) : "")
        names << ex_row[:hw_name].to_s
        names.map { |v| MH_Thongke.fix_vietnamese_mojibake(v).to_s.strip }.reject(&:empty?).uniq
      rescue
        [special_target.to_s, ex_row[:hw_name].to_s].map(&:to_s).reject(&:empty?).uniq
      end
      private_class_method :pk_match_target_names

      def self.pk_update_target_name(ex_row, special_target = nil)
        if MH_Thongke.respond_to?(:pk_update_target_name)
          return MH_Thongke.pk_update_target_name(ex_row, special_target)
        end

        special = MH_Thongke.fix_vietnamese_mojibake(special_target).to_s.strip
        return special unless special.empty?

        hw = MH_Thongke.fix_vietnamese_mojibake(ex_row[:hw_name]).to_s.strip
        spec = MH_Thongke.fix_vietnamese_mojibake(ex_row[:spec]).to_s.strip
        target = MH_Thongke.respond_to?(:import_display_name) ? MH_Thongke.import_display_name(hw, spec) : [hw, spec].reject(&:empty?).join(" ")
        target.to_s.strip.empty? ? hw : target.to_s.strip
      rescue
        special_target.to_s.strip.empty? ? ex_row[:hw_name].to_s : special_target.to_s.strip
      end
      private_class_method :pk_update_target_name

      def self.pk_matches_excel_like_mini?(product_code, model_name, ex_row, special_target = nil)
        hw_name = ex_row[:hw_name].to_s
        spec = ex_row[:spec].to_s

        model_norm = MH_Thongke.import_name_norm(model_name)
        hw_norm = MH_Thongke.import_name_norm(hw_name)
        return true if spec.to_s.strip.empty? && !model_norm.empty? && model_norm == hw_norm

        target_name = pk_update_target_name(ex_row, special_target)
        target_norm = MH_Thongke.import_name_norm(target_name)
        return true if !target_norm.empty? && model_norm == target_norm

        pk_match_ok_like_mini?(product_code, model_name, target_name, spec)
      rescue
        false
      end
      private_class_method :pk_matches_excel_like_mini?
    end
  end
end
