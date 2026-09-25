# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / thickness_selection.rb
# ---------------------------------------------------------------------------
# Thickness/profile selection helpers for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        module_function

        def thickness_option_list(context)
          thickness_options_for_context(context)
        end

        def thickness_profile_from_option(option)
          panel = option['panel_mm']
          raw_back = option['back_mm']
          back  = raw_back
          back = panel if back.nil?
          back_token = raw_back.nil? || raw_back.to_s.strip.empty? ? '--' : raw_back
          {
            'profile_id'         => "TH_#{panel}_#{back}".to_s.tr('.', '_'),
            'profile_name'       => "Day #{panel}#{back.nil? ? '' : "/#{back}"}",
            'material_code'      => '',
            'panel_thickness_mm' => panel,
            'back_thickness_mm'  => back,
            'hud_tokens'         => [panel, back_token].map { |v| v.to_s.sub(/\.0$/, '') }
          }
        end

        def thickness_profile_entries_for_context(context = nil)
          product = context_value(context || {}, :product_code, 'product_code').to_s.strip
          return [] if product.empty?

          cache_key = [
            context_key(context),
            product.upcase,
            preferred_material_code_for_context(product, context).to_s.strip.upcase,
            (@material_options || DEFAULT_MATERIAL_OPTIONS).map { |row|
              [row['material_code'], row['panel_thickness_mm'], row['back_thickness_mm']].join(':')
            }.join('|'),
            (@thickness_options_by_type || {}).map { |key, rows|
              [key, Array(rows).map { |row| [row['panel_mm'], row['back_mm']].join('/') }.join(',')]
            }.sort.map { |item| item.join('=') }.join('|')
          ].join("\u0001")
          @thickness_profile_entries_cache ||= {}
          cached = @thickness_profile_entries_cache[cache_key]
          return cached.map(&:dup) if cached

          entries = ordered_material_codes_for_context(product, context).flat_map do |code|
            list = thickness_options_for_material_code_or_context(code, context)
            list.map do |option|
              profile = thickness_profile_from_option(option)
              profile['material_code'] = code
              profile['profile_id'] = [
                material_code_key(code).gsub(/[^A-Za-z0-9]+/, '_'),
                profile['profile_id']
              ].join('_')
              profile['profile_name'] = "#{material_code_key(code)} | #{profile['profile_name']}"
              profile
            end
          end
          @thickness_profile_entries_cache[cache_key] = entries.map(&:dup)
          entries
        end

        def default_profile?(profile)
          id = (profile && (profile['profile_id'] || profile[:profile_id])).to_s
          id.empty? || id == 'PROJECT_DEFAULT'
        end

        def selected_thickness_profile_for_material_code(material_code, context = nil)
          code = material_code.to_s.strip
          return nil if code.empty?

          list = thickness_options_for_material_code(code)
          return nil if list.empty?

          key = context_key(context)
          idx = (@selected_thickness_index ||= {})[key] || 0
          idx = 0 if idx >= list.length
          profile = thickness_profile_from_option(list[idx])
          profile['material_code'] = code
          profile['profile_name'] = "#{material_code_key(code)} | #{profile['profile_name']}"
          profile
        end

        def selected_thickness_profile(context)
          list = thickness_profile_entries_for_context(context)
          unless list.empty?
            key = context_key(context)
            idx = (@selected_thickness_index ||= {})[key] || 0
            idx = 0 if idx >= list.length
            return list[idx]
          end

          list = thickness_option_list(context)
          return nil if list.empty?
          key = context_key(context)
          idx = (@selected_thickness_index ||= {})[key] || 0
          idx = 0 if idx >= list.length
          thickness_profile_from_option(list[idx])
        end

        def cycle_thickness_option(context)
          list = thickness_profile_entries_for_context(context)
          list = thickness_option_list(context) if list.empty?
          return { 'ok' => false, 'error' => 'Khong co option do day cho loai vat lieu nay' } if list.empty?
          key = context_key(context)
          idx = ((@selected_thickness_index ||= {})[key] || 0) + 1
          idx = 0 if idx >= list.length
          @selected_thickness_index[key] = idx
          profile = list[idx].key?('panel_thickness_mm') ? list[idx] : thickness_profile_from_option(list[idx])
          profile.merge('ok' => true, 'label' => profile_label(profile))
        end

        def cycle_thickness_material_row(context, step = 1)
          return cycle_manual_material_row(context, step) if manual_mode?(context)

          groups = thickness_entry_groups_for_context(context)
          return cycle_material_profile(context) if groups.empty?
          if groups.length <= 1
            current = selected_profile(context) rescue nil
            current = groups.first['entries'].first if !current && groups.first && groups.first['entries']
            current = normalize_profile(current || {})
            return current.merge('ok' => true, 'label' => 'Chi co 1 VL - bam Alt doi do day')
          end

          current = selected_thickness_matrix_position(context, groups)
          next_group_index = (current['group_index'] + step.to_i) % groups.length
          next_group = groups[next_group_index]
          next_option_index = [current['option_index'], next_group['entries'].length - 1].min
          select_thickness_entry(context, next_group['entries'][next_option_index])
        end

        def cycle_thickness_option_in_row(context, step = 1)
          return cycle_manual_option_in_row(context, step) if manual_mode?(context)

          groups = thickness_entry_groups_for_context(context)
          return cycle_thickness_option(context) if groups.empty?

          current = selected_thickness_matrix_position(context, groups)
          group = groups[current['group_index']]
          next_option_index = (current['option_index'] + step.to_i) % group['entries'].length
          select_thickness_entry(context, group['entries'][next_option_index])
        end

        def cycle_manual_material_row(context, step = 1)
          groups = manual_entry_groups_for_context(context)
          return { 'ok' => false, 'error' => 'Danh sach VL thu cong rong (them o dialog Registry).' } if groups.empty?

          current = selected_manual_matrix_position(context, groups)
          next_group_index = (current['group_index'] + step.to_i) % groups.length
          next_group = groups[next_group_index]
          next_option_index = [current['option_index'], next_group['entries'].length - 1].min
          select_manual_entry(context, next_group['entries'][next_option_index])
        end

        def cycle_manual_option_in_row(context, step = 1)
          groups = manual_entry_groups_for_context(context)
          return { 'ok' => false, 'error' => 'Danh sach VL thu cong rong (them o dialog Registry).' } if groups.empty?

          current = selected_manual_matrix_position(context, groups)
          group = groups[current['group_index']]
          next_option_index = (current['option_index'] + step.to_i) % group['entries'].length
          select_manual_entry(context, group['entries'][next_option_index])
        end

        def manual_entry_groups_for_context(context)
          cache_key = context_key(context)
          @manual_entry_groups_cache ||= {}
          cached = @manual_entry_groups_cache[cache_key]
          return cached.map { |group| group.merge('entries' => group['entries'].map(&:dup)) } if cached

          entries = manual_material_profiles(context)
          groups = []
          entries.each_with_index do |entry, flat_index|
            material_key = material_code_key(entry['material_code'])
            group = groups.find { |item| item['material_key'] == material_key }
            unless group
              group = {
                'material_key' => material_key,
                'material_code' => entry['material_code'],
                'sort_order' => entry['sort_order'],
                'entries' => []
              }
              groups << group
            end
            group['entries'] << entry.merge('_flat_index' => flat_index)
          end
          @manual_entry_groups_cache[cache_key] = groups.map { |group| group.merge('entries' => group['entries'].map(&:dup)) }
          groups
        end

        def selected_manual_matrix_position(context, groups)
          key = context_key(context)
          idx = (@selected_thickness_index ||= {})[key] || 0
          idx = 0 if idx < 0

          groups.each_with_index do |group, group_index|
            option_index = group['entries'].index { |entry| entry['_flat_index'].to_i == idx }
            return { 'group_index' => group_index, 'option_index' => option_index } if option_index
          end

          { 'group_index' => 0, 'option_index' => 0 }
        end

        def select_manual_entry(context, entry)
          key = context_key(context)
          idx = entry['_flat_index'].to_i
          (@selected_thickness_index ||= {})[key] = idx
          profile = entry.dup
          profile.delete('_flat_index')
          profile.merge('ok' => true, 'label' => profile_label(profile))
        end

        def thickness_entry_groups_for_context(context)
          entries = thickness_profile_entries_for_context(context)
          return [] if entries.empty?

          groups = []
          entries.each_with_index do |entry, flat_index|
            material_key = material_code_key(entry['material_code'])
            group = groups.find { |item| item['material_key'] == material_key }
            unless group
              group = {
                'material_key' => material_key,
                'material_code' => entry['material_code'],
                'entries' => []
              }
              groups << group
            end
            group['entries'] << entry.merge('_flat_index' => flat_index)
          end
          groups
        end

        def selected_thickness_matrix_position(context, groups)
          key = context_key(context)
          idx = (@selected_thickness_index ||= {})[key] || 0
          idx = 0 if idx < 0

          groups.each_with_index do |group, group_index|
            option_index = group['entries'].index { |entry| entry['_flat_index'].to_i == idx }
            return { 'group_index' => group_index, 'option_index' => option_index } if option_index
          end

          { 'group_index' => 0, 'option_index' => 0 }
        end

        def select_thickness_entry(context, entry)
          key = context_key(context)
          idx = entry['_flat_index'].to_i
          (@selected_thickness_index ||= {})[key] = idx
          profile = entry.dup
          profile.delete('_flat_index')
          profile.merge('ok' => true, 'label' => profile_label(profile))
        end

        def normalize_profile(row)
          source = row || {}
          profile = {
            'profile_id' => 'PROJECT_DEFAULT',
            'profile_name' => 'Project Default',
            'material_code' => '',
            'panel_thickness_mm' => 20.6,
            'back_thickness_mm' => 25.0,
            'panel_material' => '',
            'back_material' => ''
          }
          source.each do |key, value|
            next if value.nil?
            next if value.respond_to?(:empty?) && value.empty?
            profile[key.to_s] = value
          end
          profile['material_code'] = profile['material_code'].to_s.strip
          profile['panel_thickness_mm'] = profile['panel_thickness_mm'].to_f
          profile['back_thickness_mm'] = profile['back_thickness_mm'].to_f
          profile['panel_material'] = profile['panel_material'].to_s.strip
          profile['back_material'] = profile['back_material'].to_s.strip
          if profile['panel_material'].empty?
            profile['panel_material'] = material_name_from_code(profile['material_code'], profile['panel_thickness_mm'])
          end
          if profile['back_material'].empty?
            profile['back_material'] = material_name_from_code(profile['material_code'], profile['back_thickness_mm'])
          end
          profile['panel_material'] = "MH_DC_PANEL_#{profile['panel_thickness_mm'].to_s.tr('.', '_')}" if profile['panel_material'].to_s.empty?
          profile['back_material'] = "MH_DC_BACK_#{profile['back_thickness_mm'].to_s.tr('.', '_')}" if profile['back_material'].to_s.empty?
          profile['hud_tokens'] = hud_tokens_for_profile(profile) if Array(profile['hud_tokens']).empty?
          profile
        end

        def context_key(context)
          context ||= {}
          product = context_value(context, :product_code, 'product_code').to_s.strip.upcase
          material_source = context_value(context, :material_source, 'material_source').to_s.strip.downcase
          material_source = 'auto' if material_source.empty?
          # Nho lua chon do day/VL theo SAN PHAM (khong gan import_path/group) de
          # khi doi DC import van giu nguyen lua chon HUD da chon truoc do. Product
          # rong (dang dat, chua chon SP) -> dung chung 1 o nho cho moi DC.
          "#{material_source}|#{product}"
        end

        def selected_profile(context = nil)
          if manual_mode?(context)
            list = manual_material_profiles(context)
            return normalize_profile({}) if list.empty?
            key = context_key(context)
            idx = (@selected_thickness_index ||= {})[key] || 0
            idx = 0 if idx >= list.length
            return list[idx]
          end

          th = selected_thickness_profile(context)
          if th
            product = context_value(context || {}, :product_code, 'product_code').to_s.strip
            code = preferred_material_code_for_context(product, context)
            th['material_code'] = code if th['material_code'].to_s.strip.empty? && !code.to_s.strip.empty?
            return th
          end

          list = profiles_for_context(context)
          key = context_key(context)
          selected = @selected_by_group[key] || @selected_by_path[key]
          chosen = list.find { |row| row['profile_id'] == selected }
          unless chosen
            product = context_value(context || {}, :product_code, 'product_code').to_s.strip
            preferred = preferred_material_code_for_context(product, context)
            unless preferred.to_s.strip.empty?
              preferred_up = preferred.to_s.strip.upcase
              chosen = list.find { |row| row['material_code'].to_s.strip.upcase == preferred_up }
              chosen ||= list.find { |row| material_option_match?(row['material_code'], preferred) }
            end
          end
          chosen || list.first
        end

        def cycle_material_profile(context = nil)
          # Che do MANUAL: xoay vong qua danh sach ma VL thu cong x do day.
          if manual_mode?(context)
            list = manual_material_profiles(context)
            return { 'ok' => false, 'error' => 'Danh sach VL thu cong rong (them o dialog Registry).' } if list.empty?
            key = context_key(context)
            idx = ((@selected_thickness_index ||= {})[key] || 0) + 1
            idx = 0 if idx >= list.length
            @selected_thickness_index[key] = idx
            chosen = list[idx]
            return chosen.merge('ok' => true, 'label' => profile_label(chosen))
          end

          # Ưu tiên xoay vòng option độ dày (dc_thickness_options) nếu loại VL có.
          return cycle_thickness_option(context) unless thickness_option_list(context).empty? && thickness_profile_entries_for_context(context).empty?

          list = profiles_for_context(context)
          key = context_key(context)
          current = selected_profile(context)
          current_index = list.index { |row| row['profile_id'] == current['profile_id'] } || 0
          chosen = list[(current_index + 1) % list.length]
          @selected_by_group[key] = chosen['profile_id']

          {
            'ok' => true,
            'profile_id' => chosen['profile_id'],
            'profile_name' => chosen['profile_name'],
            'label' => profile_label(chosen),
            'hud_tokens' => chosen['hud_tokens'],
            'material_code' => chosen['material_code'],
            'panel_thickness_mm' => chosen['panel_thickness_mm'],
            'back_thickness_mm' => chosen['back_thickness_mm'],
            'panel_material' => chosen['panel_material'],
            'back_material' => chosen['back_material']
          }
        end

        def profile_label(profile)
          tokens = profile['hud_tokens']
          if tokens.is_a?(Array) && !tokens.empty?
            material = profile['material_code'].to_s.strip
            return ([material] + tokens).reject(&:empty?).join(' ')
          end

          "#{profile['profile_name']} | back #{profile['back_thickness_mm']} / panel #{profile['panel_thickness_mm']}"
        end

        def product_profiles(product_code, context = nil)
          cache_key = [
            product_code.to_s.strip.upcase,
            preferred_material_code_for_context(product_code, context).to_s.strip.upcase,
            (@material_options || DEFAULT_MATERIAL_OPTIONS).map { |row|
              [row['material_code'], row['panel_thickness_mm'], row['back_thickness_mm']].join(':')
            }.join('|')
          ].join('::')
          return @product_profiles_cache[cache_key] if @product_profiles_cache[cache_key]

          material_codes = ordered_material_codes_for_context(product_code, context)
          return [] if material_codes.empty?

          list = []
          material_codes.each do |code|
            options = options_for_material(code)
            options = [default_option_for_material(code)] if options.empty?
            options.each do |option|
              list << build_material_option_profile(code, option)
            end
          end
          @product_profiles_cache[cache_key] = list
        end

        def ordered_material_codes_for_context(product_code, context = nil)
          codes = Array(ordered_material_codes(product_code)).map(&:to_s).map(&:strip).reject(&:empty?)
          preferred = preferred_material_code_for_context(product_code, context).to_s.strip
          return codes if preferred.empty?

          preferred_up = preferred.upcase
          hit = codes.find { |code| code.upcase == preferred_up }
          hit ||= codes.find { |code| material_option_match?(code, preferred) || material_option_match?(preferred, code) }
          return codes unless hit

          [hit] + codes.reject { |code| code.upcase == hit.upcase }
        end

        # Danh sach "dong vat lieu" cho HUD.
        # Auto chi hien ma lay tu Excel theo san pham.
        # Manual chi hien danh sach VL thu cong khi context da bat manual_mode?.
        def material_row_codes_for_context(product_code, context = nil)
          if manual_mode?(context)
            return Array(@manual_material_codes).map { |row| normalize_logical_material_code(row['material_code']) }.reject(&:empty?)
          end

          Array(ordered_material_codes_for_context(product_code, context)).map { |code| normalize_logical_material_code(code) }.reject(&:empty?).uniq
        end

        def ordered_material_codes(product_code)
          product = product_code.to_s.strip
          return [] if product.empty?

          cache_key = product.upcase
          @ordered_material_codes_cache ||= {}
          cached = @ordered_material_codes_cache[cache_key]
          return cached.dup if cached

          return [] unless defined?(MH::RegistryApp::Connector)

          material_assign = MH::RegistryApp::Connector.get('material_assign') rescue nil
          codes = []
          codes = material_assign.material_codes_for_product(product) if material_assign && material_assign.respond_to?(:material_codes_for_product)
          unless codes.empty?
            @ordered_material_codes_cache[cache_key] = codes.map(&:to_s)
            return codes
          end

          thongke = MH::RegistryApp::Connector.get('thongke') rescue nil
          if thongke && thongke.respond_to?(:material_codes_for_product)
            codes = thongke.material_codes_for_product(product)
            @ordered_material_codes_cache[cache_key] = Array(codes).map(&:to_s)
            return codes
          end
          []
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] ordered material codes error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def options_for_material(material_code)
          rows = @material_options || DEFAULT_MATERIAL_OPTIONS
          exact = rows.select { |row| material_option_match?(row['material_code'], material_code) }
          exact
        end

        def default_option_for_material(material_code)
          {
            'enabled' => '1',
            'material_code' => material_code.to_s.strip,
            'panel_thickness_mm' => DEFAULT_PROFILE['panel_thickness_mm'],
            'back_thickness_mm' => DEFAULT_PROFILE['back_thickness_mm']
          }
        end

        def material_option_match?(pattern, material_code)
          pat = pattern.to_s.strip.upcase
          code = material_code.to_s.strip.upcase
          return false if pat.empty? || code.empty?
          pat == code || code.start_with?(pat + '.') || pat.start_with?(code + '.')
        end

        def build_material_option_profile(material_code, option)
          panel = option['panel_thickness_mm'].to_f
          back = option['back_thickness_mm'].to_s.strip.empty? ? panel : option['back_thickness_mm'].to_f
          names = material_names_for_code(material_code, panel, back)
          resolved_code = names['material_code'].to_s.strip
          resolved_code = material_code if resolved_code.empty?
          profile = {
            'profile_id' => [
              resolved_code.gsub(/[^A-Za-z0-9]+/, '_'),
              panel.to_s.gsub('.', '_'),
              back.to_s.gsub('.', '_')
            ].join('_'),
            'profile_name' => "#{resolved_code} #{panel} #{back}",
            'material_code' => resolved_code,
            'panel_thickness_mm' => panel,
            'back_thickness_mm' => back,
            'panel_material' => names['panel_material'].to_s,
            'back_material' => names['back_material'].to_s,
            'panel_source_material' => names['panel_source_material'].to_s,
            'back_source_material' => names['back_source_material'].to_s,
            'panel_code' => names['panel_code'].to_s,
            'back_code' => names['back_code'].to_s
          }
          profile['hud_tokens'] = hud_tokens_for_profile(profile)
          normalize_profile(profile)
        end

        def material_names_for_code(material_code, panel, back)
          if defined?(MH::RegistryApp::Connector)
            connector = MH::RegistryApp::Connector.get('material_assign') rescue nil
            if connector && connector.respond_to?(:material_names_for_code)
              result = connector.material_names_for_code(material_code, panel, back)
              return result if result && result['ok']
            end
          end
          panel_name = material_name_from_code(material_code, panel)
          back_name = material_name_from_code(material_code, back)
          {
            'ok' => true,
            'material_code' => material_code,
            'panel_material' => panel_name,
            'back_material' => back_name,
            'panel_code' => map_thickness(panel),
            'back_code' => map_thickness(back)
          }
        end

        def format_mm_token(value)
          text = value.to_s.strip
          return '' if text.empty?
          number = text.tr(',', '.').to_f
          number.round(3).to_s.sub(/\.0+\z/, '').sub(/(\.\d*?)0+\z/, '\\1')
        end

        def hud_tokens_for_profile(profile)
          panel = format_mm_token(profile['panel_thickness_mm'])
          back = format_mm_token(profile['back_thickness_mm'])
          tokens = [panel].reject(&:empty?)
          tokens << back unless back.empty?
          tokens
        end

        def thickness_options_for_material_code(material_code)
          code = material_code.to_s.strip
          return [] if code.empty?

          keys = [material_code_key(code)]
          keys.concat(global_parent_material_keys(code))
          keys << type_key(code)
          keys = keys.reject(&:empty?)
          keys.uniq.each do |key|
            list = thickness_options(key)
            return list unless list.empty?
          end
          []
        end

        def global_parent_material_keys(material_code)
          key = material_code_key(material_code)
          return [] if key.empty?

          # The thickness library itself declares the valid groups.  Do not
          # require each group to be duplicated in material_code_rules.parent_codes:
          # a paint code such as PLY.AC.05YR-08/272-30 normalizes to
          # PLY.AC.SON.05YR-08/272-30, whose nearest thickness group is
          # PLY.AC.SON.  The old direct-parent check rejected that group unless
          # it was also listed as a global parent, and then incorrectly fell
          # back to another material in the same product.
          parts = key.split('.').map(&:strip).reject(&:empty?)
          return [] if parts.empty?

          # Nearest parent first.  The caller only accepts a candidate that
          # actually exists in @thickness_options_by_type, so this remains
          # data-driven and cannot select an undeclared thickness group.
          (parts.length - 1).downto(1).map { |length| parts.first(length).join('.') }
        rescue
          []
        end

        def thickness_options_for_material_code_or_context(material_code, context = nil)
          list = thickness_options_for_material_code(material_code)
          return list unless list.empty?

          product = context_value(context || {}, :product_code, 'product_code').to_s.strip
          return [] if product.empty?

          current_key = material_code_key(material_code)
          ordered_material_codes_for_context(product, context).each do |code|
            next if material_code_key(code) == current_key

            fallback = thickness_options_for_material_code(code)
            return fallback unless fallback.empty?
          end

          []
        end


        def thickness_options(type_key_value)
          key = type_key_value.to_s.strip.upcase
          (@thickness_options_by_type || {})[key] || []
        end

        def thickness_options_for_context(context = nil)
          product = context_value(context || {}, :product_code, 'product_code').to_s.strip
          codes = product.empty? ? [] : ordered_material_codes_for_context(product, context)
          code = Array(codes).first
          return [] unless code
          thickness_options_for_material_code(code)
        end

        # Danh sách mã vật liệu trong dự án — cho UI tự sinh bảng độ dày DC.
        def project_material_types(_force_reload = false)
          names = []
          if defined?(MH::RegistryApp::Connector)
            ma = MH::RegistryApp::Connector.get('material_assign') rescue nil
            names = Array(ma.material_names) if ma && ma.respond_to?(:material_names)
          end
          names.map { |n| material_code_key(n) }.reject(&:empty?).uniq.sort
        rescue => e
          MH::RegistryApp.dbg("[DCImportPipeline] project_material_types error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        # Đọc dynamic_attributes của DC đang chọn — cho helper "Học tham số".
      end
    end
  end
end
