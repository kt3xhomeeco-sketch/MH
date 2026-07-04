# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / hud.rb
# ---------------------------------------------------------------------------
# HUD presentation helpers for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        module_function

        def hud_detail_finish_for_context(context = {}, material_code = nil)
          product = context_value(context || {}, :product_code, 'product_code').to_s.strip
          code = material_code.to_s.strip
          code = preferred_material_code_for_context(product, context) if code.empty? && !product.empty?
          return {} if product.empty? || code.empty?

          cache_key = [product.upcase, material_code_key(code)].join("\u0001")
          @hud_detail_finish_cache ||= {}
          cached = @hud_detail_finish_cache[cache_key]
          return cached.dup if cached

          row = hud_material_excel_row(product, code)
          return {} unless row

          text = hud_mini_import_sub_text_from_row(row)
          result = { 'detail' => '', 'finish' => '', 'text' => text.to_s.strip }
          @hud_detail_finish_cache[cache_key] = result.dup
          result
        rescue => e
          puts "[DCImportPipeline] hud detail/finish error: #{e.class}: #{e.message}"
          {}
        end

        def hud_thickness_option_tokens_for_material_code(material_code)
          code = material_code.to_s.strip
          return [] if code.empty?

          list = thickness_options_for_material_code(code)
          list.map { |option| hud_thickness_option_label(option) }
        end

        def selected_hud_thickness_selection(context = {})
          if manual_mode?(context)
            entries = manual_material_profiles(context)
            unless entries.empty?
              idx = (@selected_thickness_index ||= {})[context_key(context)] || 0
              idx = 0 if idx >= entries.length || idx < 0
              selected = entries[idx] || {}
              selected_code = selected['material_code'].to_s
              selected_key = material_code_key(selected_code)
              option_index = entries[0..idx].count { |entry| material_code_key(entry['material_code']) == selected_key } - 1
              return { 'material_code' => selected_code, 'option_index' => [option_index, 0].max }
            end
          end

          entries = thickness_profile_entries_for_context(context)
          unless entries.empty?
            idx = (@selected_thickness_index ||= {})[context_key(context)] || 0
            idx = 0 if idx >= entries.length || idx < 0
            selected = entries[idx] || {}
            selected_code = selected['material_code'].to_s
            selected_key = material_code_key(selected_code)
            option_index = entries[0..idx].count { |entry| material_code_key(entry['material_code']) == selected_key } - 1
            return { 'material_code' => selected_code, 'option_index' => [option_index, 0].max }
          end

          idx = (@selected_thickness_index ||= {})[context_key(context)] || 0
          { 'material_code' => '', 'option_index' => [idx, 0].max }
        end

        def hud_thickness_option_label(option)
          panel = option && option['panel_mm']
          back = option && option['back_mm']
          return '--' if panel.nil? && back.nil?
          return hud_mm_token(panel) if back.nil?

          "#{hud_mm_token(panel)}/#{hud_mm_token(back)}"
        end

        def hud_mm_token(value)
          text = value.to_s.strip
          text = format('%.3f', value.to_f).sub(/0+$/, '').sub(/\.$/, '') if value.is_a?(Numeric)
          text.empty? ? '--' : text
        end

        def hud_material_rows_for_context(context = {})
          product = context_value(context || {}, :product_code, 'product_code').to_s.strip
          if manual_mode?(context)
            selection_index = (@selected_thickness_index ||= {})[context_key(context)] || 0
            cache_key = ['manual', context_key(context), selection_index].join("\u0001")
            @hud_material_rows_cache ||= {}
            cached = @hud_material_rows_cache[cache_key]
            return cached.map(&:dup) if cached

            rows = manual_hud_material_rows_for_context(context, product)
            @hud_material_rows_cache[cache_key] = rows.map(&:dup)
            return rows
          end
          return [] if product.empty?

          selection_index = (@selected_thickness_index ||= {})[context_key(context)] || 0
          cache_key = [
            context_key(context),
            product.upcase,
            selection_index,
            preferred_material_code_for_context(product, context).to_s.strip.upcase
          ].join("\u0001")
          @hud_material_rows_cache ||= {}
          cached = @hud_material_rows_cache[cache_key]
          return cached.map(&:dup) if cached

          codes = Array(material_row_codes_for_context(product, context)).map(&:to_s).map(&:strip).reject(&:empty?)
          selection = selected_hud_thickness_selection(context)
          selected_key = material_code_key(selection['material_code'])
          rows = codes.map do |code|
            tokens = thickness_options_for_material_code_or_context(code, context).map { |option| hud_thickness_option_label(option) }
            selected = !selected_key.empty? && material_code_key(code) == selected_key
            {
              'product_code' => product,
              'material_code' => code,
              'sub_text' => hud_detail_finish_for_context(context, code)['text'].to_s,
              'thickness_tokens' => tokens,
              'selected_option_index' => selected ? selection['option_index'].to_i : -1,
              'selected' => selected
            }
          end
          @hud_material_rows_cache[cache_key] = rows.map(&:dup)
          rows
        rescue => e
          puts "[DCImportPipeline] hud material rows error: #{e.class}: #{e.message}"
          []
        end

        def manual_hud_material_rows_for_context(context, product)
          groups = manual_entry_groups_for_context(context).each_with_index.sort_by do |group, index|
            order = group['sort_order']
            [order.nil? ? 1 : 0, order || 0, index]
          end.map(&:first)
          selection = selected_hud_thickness_selection(context)
          selected_key = material_code_key(selection['material_code'])

          groups.map do |group|
            code = group['material_code'].to_s
            selected = !selected_key.empty? && material_code_key(code) == selected_key
            {
              'product_code' => product,
              'material_code' => code,
              'sub_text' => '',
              'thickness_tokens' => group['entries'].map { |entry| hud_profile_option_label(entry) },
              'selected_option_index' => selected ? selection['option_index'].to_i : -1,
              'selected' => selected
            }
          end
        end

        def hud_profile_option_label(profile)
          tokens = Array(profile['hud_tokens']).map(&:to_s).reject(&:empty?)
          tokens = hud_tokens_for_profile(profile) if tokens.empty?
          return '--' if tokens.empty?
          return tokens.first if tokens.length == 1

          "#{tokens[0]}/#{tokens[1]}"
        rescue
          '--'
        end

        def hud_material_excel_row(product_code, material_code)
          product = product_code.to_s.strip.upcase
          wanted = material_code_key(material_code)
          return nil if product.empty? || wanted.empty?

          @hud_material_excel_row_cache ||= {}
          cache_key = [product, wanted].join("\u0001")
          return @hud_material_excel_row_cache[cache_key] if @hud_material_excel_row_cache.key?(cache_key)

          rows = defined?(MH::MaterialApp) && MH::MaterialApp.respond_to?(:excel_data) ? Array(MH::MaterialApp.excel_data) : []
          if rows.empty?
            thongke = MH::RegistryApp::Connector.get('thongke') rescue nil
            rows = thongke && thongke.respond_to?(:import_excel_data) ? Array(thongke.import_excel_data(product_code)) : []
          end

          found = rows.find do |row|
            next false unless row.respond_to?(:[])

            row_product = row_value(row, :ma_sp, 'ma_sp', :Ma_SP, 'Ma_SP', 'Mã SP').to_s.strip.upcase
            next false unless row_product.empty? || row_product == product || row_product.split('.').first == product.split('.').first

            codes = [
              row_value(row, :ma_vl_source, 'ma_vl_source'),
              row_value(row, :ma_vl, 'ma_vl'),
              row_value(row, :hw_name, 'hw_name'),
              row_value(row, 'Ma_vat_lieu', :Ma_vat_lieu, 'Mã vật liệu')
            ].flat_map do |value|
              if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:split)
                MH::MaterialCode.split(value)
              else
                value.to_s.split(/\s*&\s*/)
              end
            end
            codes.any? { |candidate| material_code_key(candidate) == wanted }
          end
          @hud_material_excel_row_cache[cache_key] = found
          found
        end

        def hud_mini_import_sub_text_from_row(row)
          text = row_value(row, :display_sub, 'display_sub').to_s.strip
          return text unless text.empty?

          if defined?(::MH_Thongke) && ::MH_Thongke.respond_to?(:mini_excel_display_sub_text)
            text = ::MH_Thongke.mini_excel_display_sub_text(row).to_s.strip
            return text unless text.empty?
          end

          text = row_value(row, :spec, 'spec', :quy_cach, 'quy_cach', 'Quy cách', 'Kích thước').to_s.strip
          return text unless text.empty?

          detail = row_value(row, :Ten_chi_tiet, 'Ten_chi_tiet', 'QUY CÁCH VẬT LIỆU', 'Quy cách vật liệu').to_s.strip
          material = row_value(row, :ma_vl_source, 'ma_vl_source', :ma_vl, 'ma_vl', :Ma_vat_lieu, 'Ma_vat_lieu', 'MÃ VẬT LIỆU', 'Mã vật liệu').to_s.strip
          finish = row_value(row, :finish, 'finish', :hoan_thien, 'hoan_thien', 'HOÀN THIỆN', 'Hoàn thiện').to_s.strip
          text = [detail, material, finish].reject(&:empty?).join(' ')
          return text unless text.empty?

          parts = Array(row_value(row, :display_sub_parts, 'display_sub_parts')).map(&:to_s).map(&:strip).reject(&:empty?)
          parts.join(' ')
        end

        def row_value(row, *keys)
          keys.each do |key|
            return row[key] if row.respond_to?(:key?) && row.key?(key)
          end
          nil
        end
      end
    end
  end
end
