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

          rows = hud_material_excel_rows(product, code)
          row = rows.first
          return {} unless row

          text = hud_mini_import_sub_text_from_row(row)
          specification_columns = hud_grouped_material_specification_columns(rows)
          result = {
            'detail' => '',
            'finish' => '',
            'text' => text.to_s.strip,
            # HUD hien thi tach hai cot: Excel_E va Excel_F + Excel_G.
            # Giu truong cu de cac caller cu van nhan duoc mo ta day du.
            'material_specification_primary' => specification_columns['primary'],
            'material_specification_secondary' => specification_columns['secondary'],
            'material_specification' => [specification_columns['primary'], specification_columns['secondary']].reject(&:empty?).join(' ')
          }
          @hud_detail_finish_cache[cache_key] = result.dup
          result
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] hud detail/finish error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
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
          ensure_thickness_library_current if respond_to?(:ensure_thickness_library_current)
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
            selected_hud_row_key(context),
            preferred_material_code_for_context(product, context).to_s.strip.upcase
          ].join("\u0001")
          @hud_material_rows_cache ||= {}
          cached = @hud_material_rows_cache[cache_key]
          return cached.map(&:dup) if cached

          codes = Array(material_row_codes_for_context(product, context)).map(&:to_s).map(&:strip).reject(&:empty?)
          selection = selected_hud_thickness_selection(context)
          selected_key = material_code_key(selection['material_code'])
          grouped_rows = hud_source_groups_for_product(product, codes)
          rows = if grouped_rows.empty?
            codes.map do |code|
            tokens = thickness_options_for_material_code_or_context(code, context).map { |option| hud_thickness_option_label(option) }
            selected = !selected_key.empty? && material_code_key(code) == selected_key
            hud_data = hud_detail_finish_for_context(context, code)
            {
              'product_code' => product,
              'product_name' => hud_product_names_for_material(product, code),
              'material_code' => code,
              'sub_text' => hud_data['text'].to_s,
              'material_specification_primary' => hud_data['material_specification_primary'].to_s,
              'material_specification_secondary' => hud_data['material_specification_secondary'].to_s,
              'material_specification' => hud_data['material_specification'].to_s,
              'thickness_tokens' => tokens,
              'selected_option_index' => selected ? selection['option_index'].to_i : -1,
              'selected' => selected
            }
            end
          else
            # Thu tu HUD: Ten SP -> Excel_F + Excel_G. Excel_E la danh sach
            # hang muc nam trong moi group; mot group tuong ung mot ma VL.
            previous_product_name = nil
            first_selected_code_row = nil
            grouped_rows.map.with_index do |group, group_index|
              code = group['material_code'].to_s
              tokens = thickness_options_for_material_code_or_context(code, context).map { |option| hud_thickness_option_label(option) }
              row_key = group['hud_row_key'].to_s
              code_selected = !selected_key.empty? && material_code_key(code) == selected_key
              first_selected_code_row ||= group_index if code_selected
              # Khi chưa có thao tác Tab, chỉ đánh dấu lần xuất hiện đầu tiên
              # của mã. Khi đã có, ưu tiên đúng dòng HUD đã được chọn.
              selected = if selected_hud_row_key(context).empty?
                code_selected && group_index == first_selected_code_row
              else
                row_key == selected_hud_row_key(context)
              end
              product_group_start = group['product_name'].to_s != previous_product_name.to_s
              previous_product_name = group['product_name'].to_s
              {
                'product_code' => product,
                'product_name' => group['product_name'].to_s,
                'product_group_start' => product_group_start,
                'material_code' => code,
                'hud_row_key' => row_key,
                'sub_text' => code,
                'material_specification_primary' => group['primary'].to_s,
                'material_specification_secondary' => group['secondary'].to_s,
                'material_specification' => [group['primary'], group['secondary']].reject { |value| value.to_s.empty? }.join(' '),
                'thickness_tokens' => tokens,
                'selected_option_index' => selected ? selection['option_index'].to_i : -1,
                'selected' => selected
              }
            end
          end
          @hud_material_rows_cache[cache_key] = rows.map(&:dup)
          rows
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] hud material rows error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
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
          hud_material_excel_rows(product_code, material_code).first
        end

        def hud_material_excel_rows(product_code, material_code)
          product = product_code.to_s.strip.upcase
          wanted = material_code_key(material_code)
          return [] if product.empty? || wanted.empty?

          @hud_material_excel_rows_cache ||= {}
          cache_key = [product, wanted].join("\u0001")
          cached = @hud_material_excel_rows_cache[cache_key]
          return cached.map(&:dup) if cached

          found = hud_material_excel_rows_for_product(product).select do |row|
            hud_row_material_codes(row).any? { |candidate| material_code_key(candidate) == wanted }
          end
          @hud_material_excel_rows_cache[cache_key] = found.map(&:dup)
          found
        end

        def hud_material_excel_rows_for_product(product_code)
          product = product_code.to_s.strip.upcase
          return [] if product.empty?

          @hud_material_excel_product_rows_cache ||= {}
          cached = @hud_material_excel_product_rows_cache[product]
          return cached.map(&:dup) if cached

          rows = defined?(MH::MaterialApp) && MH::MaterialApp.respond_to?(:excel_data) ? Array(MH::MaterialApp.excel_data) : []
          if rows.empty?
            thongke = MH::RegistryApp::Connector.get('thongke') rescue nil
            rows = thongke && thongke.respond_to?(:import_excel_data) ? Array(thongke.import_excel_data(product_code)) : []
          end
          found = rows.select do |row|
            next false unless row.respond_to?(:[])

            row_product = row_value(row, :ma_sp, 'ma_sp', :Ma_SP, 'Ma_SP', 'Mã SP').to_s.strip.upcase
            row_product.empty? || row_product == product || row_product.split('.').first == product.split('.').first
          end
          @hud_material_excel_product_rows_cache[product] = found.map(&:dup)
          found
        end

        def hud_row_material_codes(row)
          [
            row_value(row, :ma_vl_source, 'ma_vl_source'),
            row_value(row, :ma_vl, 'ma_vl'),
            row_value(row, :hw_name, 'hw_name'),
            row_value(row, 'Ma_vat_lieu', :Ma_vat_lieu, 'Mã vật liệu')
          ].flat_map { |value| MH::MaterialCode.split(value) }
        end

        # Nhóm dữ liệu theo tên SP trước, sau đó theo Excel_F + Excel_G.
        # Excel_E được giữ theo thứ tự nguồn và đặt thành các dòng trong group.
        def hud_source_groups_for_product(product_code, allowed_codes)
          allowed = Array(allowed_codes).map { |code| material_code_key(code) }.reject(&:empty?)
          return [] if allowed.empty?

          cache_key = [product_code.to_s.strip.upcase, allowed.sort.join('|')].join("\u0001")
          @hud_source_groups_cache ||= {}
          cached = @hud_source_groups_cache[cache_key]
          return cached.map(&:dup) if cached

          groups = []
          hud_material_excel_rows_for_product(product_code).each do |row|
            codes = hud_row_material_codes(row).select { |code| allowed.include?(material_code_key(code)) }
            next if codes.empty?

            product_name = row_value(row, :ten_sp, 'ten_sp', :Ten_SP, 'Ten_SP', 'Tên SP').to_s.strip
            primary = row_value(row, :Excel_E, 'Excel_E').to_s.strip
            secondary = [
              row_value(row, :Excel_F, 'Excel_F'),
              row_value(row, :Excel_G, 'Excel_G')
            ].map(&:to_s).map(&:strip).reject(&:empty?).join(' ')
            secondary = hud_material_specification_from_row(row) if secondary.empty?
            key = [product_name.upcase, secondary.upcase].join("\u0001")
            group = groups.find { |item| item['_key'] == key }
            unless group
              group = {
                '_key' => key,
                'product_name' => product_name,
                'primary_values' => [],
                'secondary' => secondary,
                'material_codes' => []
              }
              groups << group
            end
            group['primary_values'] << primary unless primary.empty? || group['primary_values'].include?(primary)
            codes.each do |code|
              normalized = normalize_logical_material_code(code)
              group['material_codes'] << normalized unless normalized.empty? || group['material_codes'].include?(normalized)
            end
          end
          result = groups.filter_map do |group|
            code = group['material_codes'].first.to_s
            next if code.empty?

            {
              'product_name' => group['product_name'],
              'primary' => group['primary_values'].join("\n"),
              'secondary' => group['secondary'],
              'material_code' => code,
              # Khóa theo cấu trúc lớp hiển thị, không chỉ theo mã VL. Đây là
              # điều giúp hai dòng trùng mã vẫn được Tab chọn riêng.
              'hud_row_key' => [group['product_name'].to_s.upcase, group['secondary'].to_s.upcase, material_code_key(code)].join("\u0001")
            }
          end
          @hud_source_groups_cache[cache_key] = result.map(&:dup)
          result
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] hud source groups error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        # Một mã vật liệu có thể xuất hiện dưới nhiều tên SP trong cùng SPxx.
        # Trả về tất cả tên theo đúng mã thay vì lấy tên của dòng SP đầu tiên.
        def hud_product_names_for_material(product_code, material_code)
          hud_material_excel_rows(product_code, material_code).map do |row|
            row_value(row, :ten_sp, 'ten_sp', :Ten_SP, 'Ten_SP', 'Tên SP').to_s.strip
          end.reject(&:empty?).uniq.join("\n")
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

        def hud_material_specification_from_row(row)
          direct = row_value(row, :Quy_cach_vat_lieu, 'Quy_cach_vat_lieu', :quy_cach_vat_lieu, 'quy_cach_vat_lieu').to_s.strip
          return direct unless direct.empty?

          [
            row_value(row, :Excel_E, 'Excel_E'),
            row_value(row, :Excel_F, 'Excel_F'),
            row_value(row, :Excel_G, 'Excel_G')
          ].map(&:to_s).map(&:strip).reject(&:empty?).join(' ')
        end

        # Excel_E là tên hạng mục ngắn dùng cho HUD (CÁNH, ỐP ĐÁY...).
        # Chỉ fallback về quy cách đầy đủ khi dữ liệu không có cột này.
        def hud_material_specification_label_from_row(row)
          label = row_value(row, :Excel_E, 'Excel_E').to_s.strip
          return label unless label.empty?

          hud_material_specification_from_row(row)
        end

        # "CÁNH GỖ ...", "ỐP ĐÁY GỖ ..." cùng mã sẽ thành
        # "CÁNH, ỐP ĐÁY GỖ ...". Khi phần sau không giống nhau, giữ nguyên
        # từng quy cách đầy đủ để không làm mất thông tin.
        def hud_grouped_material_specification(rows)
          columns = hud_grouped_material_specification_columns(rows)
          [columns['primary'], columns['secondary']].reject(&:empty?).join(' ')
        end

        # Excel_E la cot thu nhat (hang muc: CANH, THUNG HAU...). Excel_F va
        # Excel_G tao cot thu hai (vat lieu va ma hoan thien). Moi phan chi
        # giu mot lan khi nhieu dong cung dung mot ma vat lieu.
        def hud_grouped_material_specification_columns(rows)
          entries = Array(rows).map do |row|
            primary = row_value(row, :Excel_E, 'Excel_E').to_s.strip
            secondary = [
              row_value(row, :Excel_F, 'Excel_F'),
              row_value(row, :Excel_G, 'Excel_G')
            ].map(&:to_s).map(&:strip).reject(&:empty?).join(' ')
            { primary: primary, secondary: secondary }
          end
          # Excel_E la danh sach hang muc, moi gia tri phai o mot dong rieng
          # tren HUD thay vi bi gop thanh mot chuoi co dau phay.
          primary = entries.map { |entry| entry[:primary] }.reject(&:empty?).uniq.join("\n")
          secondary = entries.map { |entry| entry[:secondary] }.reject(&:empty?).uniq.join(', ')
          return { 'primary' => primary, 'secondary' => secondary } unless primary.empty? && secondary.empty?

          # File cu khong co Excel_E/F/G: giu lai mo ta cu o cot thu hai.
          full = Array(rows).map { |row| hud_material_specification_from_row(row).to_s.strip }.reject(&:empty?).uniq.join(', ')
          { 'primary' => '', 'secondary' => full }
        end

        def legacy_hud_grouped_material_specification(rows)
          entries = Array(rows).map do |row|
            label = hud_material_specification_label_from_row(row).to_s.strip
            full = hud_material_specification_from_row(row).to_s.strip
            tail = full
            tail = full.sub(/\A#{Regexp.escape(label)}\s*/i, '').strip unless label.empty?
            { label: label, full: full, tail: tail }
          end

          labels = entries.map { |entry| entry[:label] }.reject(&:empty?).uniq
          fulls = entries.map { |entry| entry[:full] }.reject(&:empty?).uniq
          return fulls.join(', ') if labels.empty?

          tails = entries.map { |entry| entry[:tail] }.reject(&:empty?).uniq
          return labels.join(', ') if tails.empty?
          return "#{labels.join(', ')} #{tails.first}" if tails.length == 1

          fulls.join(', ')
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
