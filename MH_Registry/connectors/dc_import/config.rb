# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / config.rb
# ---------------------------------------------------------------------------
# Config parsing and defaults for DCImportPipeline.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module DCImportPipeline
        @selected_by_group = {}
        @selected_by_path = {}
        @profiles_cache = nil
        @material_options = nil
        @product_profiles_cache = {}
        @thickness_profile_entries_cache = {}
        @hud_detail_finish_cache = {}
        @hud_material_excel_row_cache = {}
        @hud_material_rows_cache = {}
        @manual_material_profiles_cache = nil
        @manual_entry_groups_cache = nil
        @ordered_material_codes_cache = {}
        @material_code_key_cache = {}

        PANEL_THICKNESS_KEY = 'ba4ulq2qnw'
        BACK_THICKNESS_KEY = 'ikqikbwfw7'
        DEFAULT_THICKNESS_MAP = [
          { 'min' => 7.5, 'max' => 8.5, 'value' => '8' },
          { 'min' => 10.5, 'max' => 11.5, 'value' => '11' },
          { 'min' => 16.5, 'max' => 17.9, 'value' => '17' },
          { 'min' => 18.0, 'max' => 18.9, 'value' => '18' },
          { 'min' => 19.0, 'max' => 19.9, 'value' => '19' },
          { 'min' => 20.0, 'max' => 20.9, 'value' => '20' },
          { 'min' => 24.0, 'max' => 25.9, 'value' => '25' }
        ].freeze
        DEFAULT_PROFILE = {
          'profile_id' => 'MDFCA_AC_BACK8',
          'profile_name' => 'MDFCA.AC | Hau 8',
          'material_code' => 'MDFCA.AC',
          'panel_thickness_mm' => 18.6,
          'back_thickness_mm' => 8.0,
          'panel_material' => '',
          'back_material' => ''
        }.freeze
        DEFAULT_PROFILES = [
          DEFAULT_PROFILE,
          {
            'profile_id' => 'MDFCA_AC_BACK11',
            'profile_name' => 'MDFCA.AC | Hau 11',
            'material_code' => 'MDFCA.AC',
            'panel_thickness_mm' => 18.6,
            'back_thickness_mm' => 11.0,
            'panel_material' => '',
            'back_material' => ''
          },
        ].freeze
        DEFAULT_MATERIAL_OPTIONS = [
          {
            'enabled' => '1',
            'material_code' => 'PLY.AC.30YY-68/024-30',
            'panel_thickness_mm' => 17.6,
            'back_thickness_mm' => 8.0
          },
          {
            'enabled' => '1',
            'material_code' => 'PLY.AC.30YY-68/024-30',
            'panel_thickness_mm' => 17.6,
            'back_thickness_mm' => 11.0
          },
          {
            'enabled' => '1',
            'material_code' => 'GOSOI',
            'panel_thickness_mm' => 20.0,
            'back_thickness_mm' => ''
          }
        ].freeze
        @thickness_map = DEFAULT_THICKNESS_MAP.map(&:dup)

        @thickness_options_by_type = {}
        @thickness_options_library_by_type = {}
        @thickness_options_project_by_type = {}
        @bindings = []
        @selected_thickness_index = {}
        @global_material_code_keys = []
        @global_material_parent_keys = []

        PROFILE_COLUMNS = %w[
          profile_id profile_name material_code panel_thickness_mm back_thickness_mm panel_material back_material
        ].freeze

        LEGACY_DEFAULT_PROFILE = {
          'profile_id' => 'PROJECT_DEFAULT',
          'profile_name' => 'Project Default',
          'material_code' => '',
          'panel_thickness_mm' => 20.6,
          'back_thickness_mm' => 25.0,
          'panel_material' => 'MH_DC_PANEL_20_6',
          'back_material' => 'MH_DC_BACK_25'
        }.freeze

        module_function

        def value_for(row, *keys)
          keys.each do |key|
            return row[key] if row.key?(key)
            sym = key.to_sym
            return row[sym] if row.key?(sym)
          end
          nil
        end

        def number_for(row, *keys)
          raw = value_for(row, *keys)
          text = raw.to_s.strip.tr(',', '.')
          return nil if text.empty?
          text.to_f
        end

        def profiles(_force_reload = false)
          @profiles_cache ||= DEFAULT_PROFILES.map { |row| normalize_profile(row) }
        end

        def profiles_for_context(context = nil)
          product = context_value(context || {}, :product_code, 'product_code').to_s.strip
          dynamic = product.empty? ? [] : product_profiles(product, context)
          dynamic.empty? ? profiles : dynamic
        end

        def clear_runtime_caches
          @product_profiles_cache = {}
          @thickness_profile_entries_cache = {}
          @hud_detail_finish_cache = {}
          @hud_material_excel_row_cache = {}
          @hud_material_rows_cache = {}
          @manual_material_profiles_cache = nil
          @manual_entry_groups_cache = nil
          @ordered_material_codes_cache = {}
          @material_code_key_cache = {}
        end

        def profiles_from_config(data)
          data ||= {}
          @thickness_map = parse_thickness_map(data)
          @material_options = parse_material_options(data)
          rows = data['dc_material_profiles'] || data[:dc_material_profiles] || []
          parsed = rows.map do |row|
            id = row['profile_id'] || row[:profile_id] || row['id'] || row[:id]
            name = row['profile_name'] || row[:profile_name] || row['name'] || row[:name]
            material_code = value_for(row, 'material_code', 'ma_vat_lieu', 'Ma_vat_lieu', 'Mã vật liệu', 'vat_lieu', 'material_code_base')
            next if id.to_s.strip.empty?

            {
              'profile_id' => id.to_s.strip,
              'profile_name' => name.to_s.strip.empty? ? id.to_s.strip : name.to_s.strip,
              'material_code' => material_code.to_s.strip,
              'panel_thickness_mm' => number_for(row, 'panel_thickness_mm', 'panel_mm', 'panel', 'Panel', 'Tam', 'Tấm'),
              'back_thickness_mm' => number_for(row, 'back_thickness_mm', 'back_mm', 'back', 'Back', 'Hau', 'Hậu'),
              'panel_material' => value_for(row, 'panel_material', 'panel_mat', 'material_panel', 'VL_Tam', 'VL Tấm').to_s.strip,
              'back_material' => value_for(row, 'back_material', 'back_mat', 'material_back', 'VL_Hau', 'VL Hậu').to_s.strip
            }
          end.compact
          parsed = DEFAULT_PROFILES.map(&:dup) if parsed.empty?
          parsed.map { |row| normalize_profile(row) }
        end

        def parse_material_options(data)
          rows = data['dc_material_options'] || data[:dc_material_options] || []
          parsed = rows.filter_map do |row|
            enabled = value_for(row, 'enabled', 'Enable', 'bat', 'bật').to_s.strip
            next if enabled == '0' || enabled.downcase == 'false' || enabled.downcase == 'no'
            code = value_for(row, 'material_code', 'ma_vat_lieu', 'Ma_vat_lieu', 'Mã vật liệu').to_s.strip
            panel = number_for(row, 'panel_thickness_mm', 'panel_mm', 'panel', 'Panel')
            back_raw = value_for(row, 'back_thickness_mm', 'back_mm', 'back', 'Back').to_s.strip
            next if code.empty? || panel.nil? || panel <= 0
            {
              'enabled' => '1',
              'material_code' => code,
              'panel_thickness_mm' => panel,
              'back_thickness_mm' => back_raw.empty? ? '' : back_raw.tr(',', '.').to_f
            }
          end
          parsed.empty? ? DEFAULT_MATERIAL_OPTIONS.map(&:dup) : parsed
        end

        # ---- Che do MANUAL: danh sach ma VL nhap tay (sheet dc_manual_materials) ----
        def parse_manual_materials(data)
          rows = (data && (data['dc_manual_materials'] || data[:dc_manual_materials])) || []
          parsed = rows.each_with_index.filter_map do |row, index|
            enabled = value_for(row, 'enabled', 'Enable', 'bat', 'bật').to_s.strip
            next if enabled == '0' || enabled.downcase == 'false' || enabled.downcase == 'no'
            code = value_for(row, 'material_code', 'ma_vat_lieu', 'Ma_vat_lieu', 'Mã vật liệu').to_s.strip
            next if code.empty?
            raw_order = value_for(row, 'sort_order', 'order', 'thu_tu', 'Thứ tự', 'Số thứ tự').to_s.strip
            sort_order =
              if raw_order.empty?
                nil
              else
                begin
                  number = Float(raw_order)
                  number.finite? ? number : nil
                rescue ArgumentError, TypeError
                  nil
                end
              end
            {
              'material_code' => code,
              'sort_order' => sort_order,
              '_source_index' => index
            }
          end
          parsed.sort_by do |row|
            order = row['sort_order']
            [order.nil? ? 1 : 0, order || 0, row['_source_index']]
          end.each { |row| row.delete('_source_index') }
        end

        # Bat che do manual khi context (tu HUD Superimp) bao material_source=manual.
        def manual_mode?(context)
          context_value(context || {}, :material_source, 'material_source').to_s.strip.downcase == 'manual'
        end

        # Dung profile tu danh sach ma VL thu cong x option do day cua tung ma.
        # Khong tra Excel. HUD Tab xoay vong qua cac profile nay.
        def manual_material_profiles(context = nil)
          return @manual_material_profiles_cache.map(&:dup) if @manual_material_profiles_cache

          Array(@manual_material_codes).flat_map do |entry|
            code = entry['material_code'].to_s.strip
            next [] if code.empty?
            opts = thickness_options_for_material_code(code)
            if opts.empty?
              panel = DEFAULT_PROFILE['panel_thickness_mm']
              back = DEFAULT_PROFILE['back_thickness_mm']
              [normalize_profile({
                'profile_id' => "manual::#{code}",
                'profile_name' => code,
                'material_code' => code,
                'panel_thickness_mm' => panel,
                'back_thickness_mm' => back,
                'panel_material' => lightweight_material_name_from_code(code, panel),
                'back_material' => lightweight_material_name_from_code(code, back),
                'sort_order' => entry['sort_order']
              })]
            else
              opts.each_with_index.map do |opt, i|
                prof = thickness_profile_from_option(opt)
                prof['material_code'] = code
                prof['profile_id'] = "manual::#{code}::#{i}"
                prof['profile_name'] = "#{code} | #{prof['profile_name']}"
                prof['panel_material'] = lightweight_material_name_from_code(code, prof['panel_thickness_mm'])
                prof['back_material'] = lightweight_material_name_from_code(code, prof['back_thickness_mm'])
                prof['sort_order'] = entry['sort_order']
                normalize_profile(prof)
              end
            end
          end.tap do |profiles|
            @manual_material_profiles_cache = profiles.map(&:dup)
          end
        end

        def lightweight_material_name_from_code(material_code, actual_thickness)
          code = material_code.to_s.strip
          return '' if code.empty?
          return code.sub(/^MH_/i, '') if code =~ /^MH_/i

          thickness_code = map_thickness(actual_thickness)
          parts = code.split('.').map(&:strip).reject(&:empty?)
          if parts.length >= 2
            ([parts[0], thickness_code] + parts[1..-1]).join('.')
          else
            "#{code}.#{thickness_code}"
          end
        rescue
          code
        end

        def parse_thickness_map(data)
          rows = data['ma_thickness'] || data[:ma_thickness] || []
          parsed = rows.filter_map do |row|
            min_v = value_for(row, 'min').to_s.strip.tr(',', '.')
            max_v = value_for(row, 'max').to_s.strip.tr(',', '.')
            val = value_for(row, 'value').to_s.strip
            next if min_v.empty? || max_v.empty? || val.empty?
            { 'min' => min_v.to_f, 'max' => max_v.to_f, 'value' => val.gsub(/\.0$/, '') }
          end
          parsed.empty? ? DEFAULT_THICKNESS_MAP.map(&:dup) : parsed
        end

        def parse_global_material_codes(data)
          rows = (data && (data['ma_vat_lieu_global'] || data[:ma_vat_lieu_global] || data['ma_vat_lieu'] || data[:ma_vat_lieu])) || []
          rows.flat_map do |row|
            [
              value_for(row, 'gia_tri_map', 'material_code', 'ma_vat_lieu', 'Mã map'),
              value_for(row, 'gia_tri', 'value', 'Giá trị')
            ]
          end.map { |value| material_code_key(value) }
             .reject(&:empty?)
             .uniq
        rescue
          []
        end

        def parse_global_material_parent_codes(data)
          rules = data && (data['material_code_rules'] || data[:material_code_rules])
          if (!rules || rules.empty?) && defined?(MH::Registry) && MH::Registry.respond_to?(:material_code_rules)
            rules = MH::Registry.material_code_rules
          end
          parent_codes = Array((rules || {})['parent_codes'] || (rules || {})[:parent_codes])
          return parent_codes.map { |value| material_code_key(value) }.reject(&:empty?).uniq unless parent_codes.empty?

          rows = (data && (data['ma_vat_lieu_global'] || data[:ma_vat_lieu_global] || data['ma_vat_lieu'] || data[:ma_vat_lieu])) || []
          rows.select do |row|
            value_for(row, 'nhom', 'layer', 'key', 'group').to_s.strip.upcase == 'VL_PARENT'
          end.flat_map do |row|
            [
              value_for(row, 'gia_tri_map', 'material_code', 'ma_vat_lieu', 'Mã map'),
              value_for(row, 'gia_tri', 'value', 'Giá trị')
            ]
          end.map { |value| material_code_key(value) }
             .reject(&:empty?)
             .uniq
        rescue
          []
        end

        def parse_thickness_rows(rows)
          map = {}
          Array(rows).each do |row|
            type = value_for(row, 'material_type', 'type').to_s.strip
            next if type.empty?
            opts = Array(row['options'] || row[:options])
            parsed = opts.filter_map do |o|
              panel = number_or_nil(o['panel'] || o[:panel])
              back  = number_or_nil(o['back'] || o[:back])
              next if panel.nil? && back.nil?
              { 'panel_mm' => panel, 'back_mm' => back }
            end
            key = material_code_key(type)
            key = type.upcase if key.empty?
            map[key] = parsed unless parsed.empty?
          end
          map
        end

        def parse_thickness_options(data)
          data ||= {}
          library_rows = data['dc_thickness_options_library'] || data[:dc_thickness_options_library] || []
          legacy_rows = data['dc_thickness_options'] || data[:dc_thickness_options] || []

          @thickness_options_library_by_type = parse_thickness_rows(library_rows)
          @thickness_options_project_by_type = {}
          if @thickness_options_library_by_type.empty?
            @thickness_options_by_type = parse_thickness_rows(legacy_rows)
          else
            @thickness_options_by_type = @thickness_options_library_by_type
          end
        end

        def on_config_changed(config_data)
          @selected_by_group.clear
          @selected_by_path.clear
          clear_runtime_caches
          @profiles_cache = profiles_from_config(config_data)
          @material_options = parse_material_options(config_data)
          @thickness_options_by_type = parse_thickness_options(config_data)
          @bindings = parse_bindings(config_data)
          @manual_material_codes = parse_manual_materials(config_data)
          @global_material_code_keys = parse_global_material_codes(config_data)
          @global_material_parent_keys = parse_global_material_parent_codes(config_data)
          # Config/Excel mới phải bỏ lựa chọn phẳng cũ; index cũ có thể trỏ
          # sang option khác hoặc profile mặc định sau khi danh sách thay đổi.
          @selected_thickness_index = {}
        end
      end
    end
  end
end
