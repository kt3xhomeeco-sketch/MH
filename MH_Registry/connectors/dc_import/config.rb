# encoding: UTF-8
#
# MH_Registry / connectors / dc_import / config.rb
# ---------------------------------------------------------------------------
# Config parsing and defaults for DCImportPipeline.
# ---------------------------------------------------------------------------

require_relative '../../../MH_shared/material_library'

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
        @thickness_map = []

        @thickness_options_by_type = {}
        @thickness_options_library_by_type = {}
        @thickness_options_project_by_type = {}
        @thickness_group_layers = []
        @bindings = []
        @selected_thickness_index = {}
        # Dòng HUD và mã vật liệu không phải lúc nào cũng là quan hệ 1-1:
        # cùng một mã có thể xuất hiện ở hai nhóm Excel khác nhau. Lưu khóa
        # dòng riêng để Tab vẫn đi qua từng dòng hiển thị.
        @selected_hud_row_key = {}
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
          @hud_material_excel_rows_cache = {}
          @hud_material_excel_product_rows_cache = {}
          @hud_source_groups_cache = {}
          @hud_material_rows_cache = {}
          @hud_material_row_codes_cache = {}
          @preferred_material_code_cache = {}
          @manual_material_profiles_cache = nil
          @manual_entry_groups_cache = nil
          @ordered_material_codes_cache = {}
          @material_code_key_cache = {}
          @material_name_from_code_cache = {}
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
          ensure_thickness_library_current
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
          MH::MaterialCode.material_name(
            material_code,
            actual_thickness,
            mappings: @thickness_map,
            fallback_to_actual: true
          ).to_s
        rescue
          material_code.to_s
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
          parsed
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
          parse_rows = lambda do
            Array(rows).each do |row|
              type = value_for(row, 'material_type', 'type').to_s.strip
              next if type.empty?
              opts = Array(row['options'] || row[:options])
              options = opts.filter_map do |o|
                panel = number_or_nil(o['panel'] || o[:panel])
                back  = number_or_nil(o['back'] || o[:back])
                next if panel.nil? && back.nil?
                { 'panel_mm' => panel, 'back_mm' => back }
              end
              # Chuẩn hóa khi mọi token của dòng thư viện đã có mapping, hoặc
              # khi có bề mặt/mã hoàn thiện. Mã viết tắt chưa được map (vd.
              # WPB.LK) phải giữ nguyên để không đè nhầm nhóm cha WPB. Lớp
              # finish_code được xét riêng: SON là mã sơn lớp 6, không phải
              # be_mat.
              material_parsed = MH::MaterialCode.parse(type)
              layers = material_parsed[:layers] || material_parsed['layers'] || {}
              grouped_layers = thickness_group_layer_values(type, layers)
              surface = (grouped_layers['be_mat'] || grouped_layers[:be_mat]).to_s.strip
              finish = (grouped_layers['finish_code'] || grouped_layers[:finish_code]).to_s.strip
              mapped_tokens = Array(MH::MaterialCode.rules['mappings']).filter_map do |row|
                row = row.is_a?(Hash) ? row : {}
                value = (row['gia_tri_map'] || row[:gia_tri_map] || row['mapped'] || row[:mapped]).to_s.strip.upcase
                value unless value.empty?
              end.uniq
              code_tokens = type.split('.').map { |value| value.to_s.strip.upcase }.reject(&:empty?)
              all_tokens_mapped = !code_tokens.empty? && code_tokens.all? { |token| mapped_tokens.include?(token) }
              key = !surface.empty? || !finish.empty? || all_tokens_mapped ? thickness_material_code_key(type) : type.upcase
              key = type.upcase if key.empty?
              map[key] = options unless options.empty?
            end
          end
          # MaterialCode.parse truy xuất rule trong Registry. Khi thêm một
          # option mới, phải parse cả bảng; snapshot giúp đọc rule đúng một
          # lần thay vì lặp lại cho từng dòng độ dày.
          if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:with_rules_snapshot)
            MH::MaterialCode.with_rules_snapshot { parse_rows.call }
          else
            parse_rows.call
          end
          map
        end

        def parse_thickness_options(data)
          data ||= {}
          library_rows = data['dc_thickness_options_library'] || data[:dc_thickness_options_library] || []

          @thickness_options_library_by_type = parse_thickness_rows(library_rows)
          @thickness_options_project_by_type = {}
          @thickness_options_by_type = @thickness_options_library_by_type
        end

        # Bảng dc_thickness_group_layers là nguồn duy nhất xác định lớp nào
        # được giữ khi tạo nhóm cha độ dày.  Các lớp không tick sẽ không ảnh
        # hưởng đến việc chọn độ dày.
        def parse_thickness_group_layers(data)
          rows = data && (data['dc_thickness_group_layers'] || data[:dc_thickness_group_layers])
          Array(rows).filter_map do |row|
            key = value_for(row, 'layer_key', 'layer', 'key').to_s.strip
            next if key.empty?

            include_value = value_for(row, 'include_in_thickness_parent', 'include', 'enabled')
            included = %w[1 true yes y x co có].include?(include_value.to_s.strip.downcase)
            order = value_for(row, 'parent_order', 'order', 'sort_order').to_s.strip.to_i
            {
              'layer_key' => key,
              'include_in_thickness_parent' => included,
              'parent_order' => order
            }
          end.sort_by { |row| [row['parent_order'], row['layer_key']] }
        end

        # An already-open SketchUp session can still hold an empty snapshot
        # from before the library moved. Check the actual shared workbook,
        # without reloading project JSON or writing any configuration.
        def ensure_thickness_library_current(force: false)
          return false unless defined?(MH::ExcelBridge) &&
                              MH::RegistryApp.respond_to?(:load_thickness_options)

          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return false if !force && @thickness_library_checked_at &&
                          now - @thickness_library_checked_at < 1.0

          @thickness_library_checked_at = now
          path = MH::MaterialLibrary.path
          stat = File.stat(path)
          # Excel/Registry replace the file atomically. On Windows mtime may
          # have whole-second precision, so include the file identity too.
          signature = [path, stat.mtime.to_f, stat.size, stat.ino]
          return false if !force && @thickness_library_signature == signature

          all = MH::ExcelBridge.read_all(path)
          raise "Thiếu sheet dc_thickness_options trong #{path}" unless all.key?('dc_thickness_options')

          data = {
            'dc_thickness_options_library' => MH::RegistryApp.load_thickness_options(all, 'dc_thickness_options'),
            'dc_thickness_group_layers' => MH::RegistryApp.load_rows(
              all, 'dc_thickness_group_layers', MH::RegistryApp.dc_thickness_group_layer_columns
            ),
            'ma_thickness' => MH::RegistryApp.load_rows(all, 'ma_thickness', %w[min max value])
          }
          @thickness_group_layers = parse_thickness_group_layers(data)
          @thickness_map = parse_thickness_map(data)
          @thickness_options_by_type = parse_thickness_options(data)
          @thickness_library_signature = signature
          @thickness_library_error = nil
          clear_runtime_caches
          true
        rescue => error
          message = "Không nạp được thư viện độ dày #{path}: #{error.message}"
          warn "[MH Registry] #{message}" if @thickness_library_error != message
          @thickness_library_error = message
          false
        end

        def on_config_changed(config_data)
          # A later fast JSON save may deliver an older library snapshot.
          # The next HUD access must check the workbook again.
          @thickness_library_signature = nil
          @thickness_library_checked_at = nil
          @selected_by_group.clear
          @selected_by_path.clear
          clear_runtime_caches
          @profiles_cache = profiles_from_config(config_data)
          @material_options = parse_material_options(config_data)
          @thickness_group_layers = parse_thickness_group_layers(config_data)
          @thickness_options_by_type = parse_thickness_options(config_data)
          @bindings = parse_bindings(config_data)
          @manual_material_codes = parse_manual_materials(config_data)
          @global_material_code_keys = parse_global_material_codes(config_data)
          @global_material_parent_keys = parse_global_material_parent_codes(config_data)
          # Config/Excel mới phải bỏ lựa chọn phẳng cũ; index cũ có thể trỏ
          # sang option khác hoặc profile mặc định sau khi danh sách thay đổi.
          @selected_thickness_index = {}
          @selected_hud_row_key = {}
          @superimp_config_signature = superimp_config_signature(config_data)
        end

        # Save ở tab Superimp thường chỉ sửa danh sách import. Không cần parse
        # lại toàn bộ bảng độ dày/mã vật liệu trong trường hợp đó; riêng khi các
        # field pipeline thật sự thay đổi thì vẫn chạy on_config_changed đầy đủ.
        def on_superimp_config_changed(config_data)
          signature = superimp_config_signature(config_data)
          # Không skip nếu runtime vừa bị reload và bảng option chưa được dựng;
          # nếu không HUD sẽ rơi về profile mặc định (vd chỉ 18.6/8).
          options_ready = @thickness_options_by_type.is_a?(Hash) && !@thickness_options_by_type.empty?
          return true if options_ready && !@superimp_config_signature.nil? && @superimp_config_signature == signature

          on_config_changed(config_data)
          true
        end

        def superimp_config_signature(data)
          src = data || {}
          %w[
            dc_material_profiles dc_material_options material_profile_choices
            dc_thickness_options_library dc_thickness_group_layers
            dc_thickness_bindings dc_manual_materials
          ].map { |key| Marshal.dump(src[key] || src[key.to_sym]).hash }.join('|')
        rescue
          ''
        end
      end
    end
  end
end
