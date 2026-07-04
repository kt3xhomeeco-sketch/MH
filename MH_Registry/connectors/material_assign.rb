# encoding: UTF-8
#
# MH_Registry / connectors / material_assign.rb
# ---------------------------------------------------------------------------
# Connector cho MH_Material_Assign.
# - Đọc config từ Registry Config.xlsx (sheets ma_*) → feed vào MaterialApp
# - Load data, gán vật liệu qua API chung
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module MaterialAssign
        module_function

        # Kiểm tra MH_Material_Assign đã load chưa.
        def available?
          defined?(MH::MaterialApp) && MH::MaterialApp.respond_to?(:do_import)
        end

        # Một số app (đặc biệt MH_panel) gọi connector trước khi người dùng từng
        # mở Material Assign. Tự nạp engine để quy luật độ dày và .1M/.2M không
        # phụ thuộc thứ tự mở app trong phiên SketchUp.
        def ensure_available
          return true if available?

          path = File.join(
            Sketchup.find_support_file('Plugins'),
            'MH_Material_Assign',
            'main.rb'
          )
          load path if File.exist?(path)
          return false unless available?

          sync_config
          true
        rescue => e
          puts "[MaterialAssign Connector] ensure_available error: #{e.class}: #{e.message}"
          false
        end

        # ---- Config sync: Registry → MaterialApp ----

        # Đọc các sheet ma_* từ Config.xlsx rồi feed vào MH::MaterialApp.
        def sync_config(config_data = nil)
          return false unless available?
          config_data ||= MH::RegistryApp.load_config

          # thickness_mappings
          tm = (config_data['ma_thickness'] || []).filter_map do |r|
            min_v = r['min'].to_s.strip
            max_v = r['max'].to_s.strip
            val   = r['value'].to_s.strip
            next if min_v.empty? || max_v.empty? || val.empty?
            { min: min_v.to_f, max: max_v.to_f, value: val }
          end
          MH::MaterialApp.thickness_mappings = tm unless tm.empty?

          # detail_aliases
          da = {}
          (config_data['ma_detail_aliases'] || []).each do |r|
            p = r['pattern'].to_s.strip.downcase
            t = r['target'].to_s.strip.downcase
            da[p] = t unless p.empty? || t.empty?
          end
          MH::MaterialApp.detail_aliases = da unless da.empty?

          # tag_material_map
          tmap = MH::MaterialApp.tag_material_map.dup
          (config_data['ma_tag_materials'] || []).each do |r|
            tn = r['tag_name'].to_s.strip
            mn = r['material_name'].to_s.strip
            tmap[tn] = mn unless tn.empty? || mn.empty?
          end
          MH::MaterialApp.tag_material_map = tmap

          # valid_materials: whitelist theo ma vat lieu. Cac cot thickness/actual_thickness
          # trong ma_valid chi la ghi chu cho UI/Excel, khong tham gia validate.
          valid = (config_data['ma_valid'] || []).filter_map do |r|
            mat = r['material'].to_s.strip
            thk = r['thickness'].to_s.strip
            next if mat.empty?
            { material: mat, thickness: thk }
          end
          MH::MaterialApp.valid_materials = valid

          # invalid_materials: legacy blacklist, chỉ có tác dụng khi valid_materials trống.
          inv = (config_data['ma_invalid'] || []).filter_map do |r|
            mat = r['material'].to_s.strip
            thk = r['thickness'].to_s.strip
            next if mat.empty?
            { material: mat, thickness: thk }
          end
          MH::MaterialApp.invalid_materials = inv

          # surface face rules (.1M/.2M cho Laminate/Veneer...)
          sfr = (config_data['ma_surface_face_rules'] || []).filter_map do |r|
            tokens = r['surface_tokens'].to_s.strip
            next if tokens.empty?
            {
              'enabled' => r['enabled'].to_s.strip,
              'surface_tokens' => tokens,
              'max_one_side_thickness' => r['max_one_side_thickness'].to_s.strip,
              'one_side_suffix' => r['one_side_suffix'].to_s.strip,
              'two_side_details' => r['two_side_details'].to_s.strip,
              'two_side_suffix' => r['two_side_suffix'].to_s.strip,
              'default_suffix' => r['default_suffix'].to_s.strip,
              'finish_suffix_overrides' => r['finish_suffix_overrides'].to_s.strip
            }
          end
          MH::MaterialApp.surface_face_rules = sfr unless sfr.empty?

          # column_aliases (merge với defaults)
          ca_data = config_data['ma_column_aliases'] || []
          unless ca_data.empty?
            ca = MH::MaterialApp.column_aliases.each_with_object({}) { |(k, v), h| h[k] = v.dup }
            ca_data.each do |r|
              internal = r['internal_name'].to_s.strip
              al = r['alias'].to_s.strip
              next if internal.empty? || al.empty?
              ca[internal] ||= []
              ca[internal] << al unless ca[internal].any? { |a| a.casecmp(al) == 0 }
            end
            MH::MaterialApp.column_aliases = ca
          end

          # module_names vẫn lấy từ Registry; product_codes không lấy từ prefix cũ nữa.
          # Mã sản phẩm được hiểu tập trung qua MH::NameGrammar/MH::ProductContext.
          mod = config_data['modul'] || []
          MH::MaterialApp.module_names = mod unless mod.empty?

          puts "[MaterialAssign Connector] Config synced from Registry"
          true
        rescue => e
          puts "[MaterialAssign Connector] sync_config error: #{e.message}"
          false
        end

        # ---- Data & Assign API ----

        # Load data vào MH_Material_Assign.
        # Primary: JSON từ SPEC/Data/ (nhanh, pure Ruby)
        # Fallback: xlsx từ SPEC/ hoặc file_path truyền vào
        def load_data(file_path = nil)
          return { 'ok' => false, 'error' => 'MH_Material_Assign chua duoc load.' } unless available?

          sync_config

          # Thử shared ProjectData trước; nếu cache hợp lệ thì không đọc/parse JSON lại ở connector.
          json_path = file_path ? MH::RegistryApp.project_json_path(file_path) : nil
          if json_path && defined?(MH::ProjectData)
            project_data = MH::ProjectData.ensure_loaded(json_path, source_path: file_path)
            if project_data && project_data[:ok]
              load_from_rows(project_data[:rows])
              mark_loaded_data(json_path)
              clear_material_names_cache
              MH::MaterialApp.remember_excel_path(file_path || '')
              count = MH::MaterialApp.excel_data.length
              puts "[MaterialAssign Connector] Loaded #{count} rows from ProjectData: #{File.basename(json_path)}"
              return {
                'ok' => true,
                'count' => count,
                'source' => 'project_data',
                'version' => project_data[:version],
                'json_path' => json_path
              }
            end
          end

          # Fallback JSON file (tên theo file_path)
          if json_path && File.exist?(json_path)
            load_from_json(json_path)
            mark_loaded_data(json_path)
            clear_material_names_cache
            MH::MaterialApp.remember_excel_path(file_path || '')
            count = MH::MaterialApp.excel_data.length
            puts "[MaterialAssign Connector] Loaded #{count} rows from JSON: #{File.basename(json_path)}"
            return { 'ok' => true, 'count' => count, 'source' => 'json' }
          end

          # Fallback xlsx
          xlsx = file_path
          if xlsx && File.exist?(xlsx)
            MH::MaterialApp.do_import(xlsx)
            mark_loaded_data(xlsx)
            clear_material_names_cache
            MH::MaterialApp.remember_excel_path(xlsx)
            count = MH::MaterialApp.excel_data.length
            puts "[MaterialAssign Connector] Loaded #{count} rows from XLSX: #{File.basename(xlsx)}"
            return { 'ok' => true, 'count' => count, 'source' => 'xlsx' }
          end

          { 'ok' => false, 'error' => 'Khong tim thay file data (JSON hoac XLSX).' }
        rescue => e
          { 'ok' => false, 'error' => e.message }
        end

        def force_reload_excel(file_path = nil)
          reset_data_load_throttle
          return { 'ok' => false, 'error' => 'MH_Material_Assign chua duoc load.' } unless available?

          path = file_path.to_s.strip
          path = MH::RegistryApp.last_mvl_input_path.to_s.strip if path.empty? && MH::RegistryApp.respond_to?(:last_mvl_input_path)
          return { 'ok' => false, 'error' => 'Chua co file Excel thong ke.' } if path.empty?
          return { 'ok' => false, 'error' => "Khong tim thay file Excel: #{path}" } unless File.exist?(path)

          sync_config
          MH::MaterialApp.do_import(path)
          mark_loaded_data(path)
          clear_material_names_cache
          MH::MaterialApp.remember_excel_path(path)
          MH::RegistryApp.remember_mvl_input_path(path) if MH::RegistryApp.respond_to?(:remember_mvl_input_path)
          count = MH::MaterialApp.excel_data.length
          puts "[MaterialAssign Connector] Force reloaded #{count} rows from XLSX: #{File.basename(path)}"
          { 'ok' => true, 'count' => count, 'source' => 'xlsx', 'path' => path }
        rescue => e
          { 'ok' => false, 'error' => e.message }
        end

        # Gán vật liệu cho selection.
        def assign_selection
          return { 'ok' => false, 'error' => 'MH_Material_Assign chua duoc load.' } unless available?
          ensure_data_loaded
          result = MH::MaterialApp.assign_to_selection(true)
          normalize_result(result)
        rescue => e
          { 'ok' => false, 'error' => e.message }
        end

        # Gán vật liệu toàn bộ model.
        def assign_all
          return { 'ok' => false, 'error' => 'MH_Material_Assign chua duoc load.' } unless available?
          ensure_data_loaded
          result = MH::MaterialApp.assign_to_all(true)
          normalize_result(result)
        rescue => e
          { 'ok' => false, 'error' => e.message }
        end

        # Số dòng data đã load.
        def data_count
          available? ? MH::MaterialApp.excel_data.length : 0
        end

        def material_names
          return [] unless available?
          ensure_material_names_data_loaded
          material_names_from_current_data
        rescue => e
          puts "[MaterialAssign Connector] material_names error: #{e.message}"
          []
        end

        def material_names_from_current_data
          return [] unless available?
          cache_key = material_names_cache_key
          if @material_names_cache_key == cache_key && @material_names_cache
            return @material_names_cache.dup
          end

          names = []
          Array(MH::MaterialApp.excel_data).each do |row|
            code = row.is_a?(Hash) ? row['Ma_vat_lieu'].to_s.strip : ''
            split_material_codes(code).each do |part|
              name = material_code_without_thickness(part)
              names << name unless name.empty? || names.include?(name)
            end
          end
          @material_names_cache_key = cache_key
          @material_names_cache = names
          names.dup
        rescue => e
          puts "[MaterialAssign Connector] material_names_from_current_data error: #{e.message}"
          []
        end

        def material_codes_for_product(product_code)
          return [] unless available?

          product = product_code.to_s.strip.upcase
          return [] if product.empty?
          ensure_data_loaded
          cache_key = [material_names_cache_key, product]
          @material_codes_by_product_cache ||= {}
          cached = @material_codes_by_product_cache[cache_key]
          return cached.dup if cached

          codes = []
          rows =
            if defined?(MH::MaterialApp::MaterialMatcher) &&
               MH::MaterialApp::MaterialMatcher.respond_to?(:rows_for_product_code)
              MH::MaterialApp::MaterialMatcher.rows_for_product_code(product)
            else
              []
            end
          rows = Array(MH::MaterialApp.excel_data).select do |row|
            next unless row.is_a?(Hash)
            row_product = first_present_value(row, ['Ma_SP', 'Mã SP', 'ma_sp', 'product_code']).to_s.strip.upcase
            row_product == product || row_product.split('.').first == product.split('.').first
          end if rows.empty?

          Array(rows).each do |row|
            next unless row.is_a?(Hash)
            split_material_codes(row['Ma_vat_lieu'].to_s.strip).each do |code|
              clean = material_code_without_thickness(code)
              codes << clean unless clean.empty? || codes.include?(clean)
            end
          end
          @material_codes_by_product_cache[cache_key] = codes.map(&:to_s)
          codes
        rescue => e
          puts "[MaterialAssign Connector] material_codes_for_product error: #{e.message}"
          []
        end

        def material_spec_for_product(product_code, detail_name = nil)
          return { 'ok' => false, 'error' => 'MH_Material_Assign chua duoc load.' } unless available?
          ensure_data_loaded

          product = product_code.to_s.strip
          detail = detail_name.to_s.strip
          detail = 'khung' if detail.empty?
          cache_key = [material_names_cache_key, product.upcase, match_key(detail)]
          @material_spec_by_product_detail_cache ||= {}
          cached = @material_spec_by_product_detail_cache[cache_key]
          return cached.dup if cached

          parsed = { product_code: product, detail_name: detail, raw_name: "#{product}_#{detail}" }
          row = MH::MaterialApp::MaterialMatcher.find_matching_row(parsed)
          return { 'ok' => false, 'error' => 'Khong tim thay vat lieu cho SP.', 'product_code' => product } unless row

          result = {
            'ok' => true,
            'product_code' => product,
            'detail_name' => detail,
            'row' => row,
            'material_code' => row['Ma_vat_lieu'].to_s.strip,
            'excel_detail' => row['Ten_chi_tiet'].to_s.strip
          }
          @material_spec_by_product_detail_cache[cache_key] = result.dup
          result
        rescue => e
          { 'ok' => false, 'error' => e.message, 'product_code' => product_code.to_s }
        end

        def material_row_for_product(product_code, detail_name = nil)
          material_spec_for_product(product_code, detail_name)
        end

        def material_name_for_code(raw_code, thickness_mm)
          base = material_code_without_thickness(raw_code)
          material_name_for_thickness(base, thickness_mm).to_s
        rescue => e
          puts "[MaterialAssign Connector] material_name_for_code error: #{e.message}"
          ''
        end

        # Mã vật liệu đầy đủ cho 1 chi tiết: lấy base từ raw_code (bỏ token độ
        # dày + hậu tố mặt phủ cũ), gắn lại token độ dày theo thickness_mm, rồi
        # thêm hậu tố .1M/.2M theo TÊN chi tiết (detail_name) — dùng đúng luật
        # surface_face của Material Assign. Trả {ok, material, base}.
        # Dùng cho app khác (vd MH_panel) gán mã VL khi tạo part.
        def coded_material(raw_code, thickness_mm, detail_name = nil)
          code = raw_code.to_s.strip
          return { 'ok' => false, 'error' => 'Ma vat lieu rong.' } if code.empty?
          return { 'ok' => false, 'error' => 'Khong nap duoc MH_Material_Assign.' } unless ensure_available

          asg = (defined?(MH::MaterialApp::MaterialAssigner) ? MH::MaterialApp::MaterialAssigner : nil)
          base = material_code_without_thickness(code)
          base = asg.base_surface_face_code(base) if asg && asg.respond_to?(:base_surface_face_code)
          name = material_name_for_thickness(base, thickness_mm).to_s
          name = code if name.empty?   # không map được độ dày → giữ mã gốc
          if asg && asg.respond_to?(:apply_surface_face_suffix) && !detail_name.to_s.strip.empty?
            name = asg.apply_surface_face_suffix(name, nil, thickness_mm, { detail_name: detail_name.to_s }) rescue name
          end
          { 'ok' => true, 'material' => name.to_s, 'base' => base.to_s }
        rescue => e
          { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
        end

        def match_key(text)
          if defined?(MH::MaterialApp::MaterialMatcher) &&
             MH::MaterialApp::MaterialMatcher.respond_to?(:match_key)
            MH::MaterialApp::MaterialMatcher.match_key(text)
          elsif defined?(MH::Text) && MH::Text.respond_to?(:fold)
            MH::Text.fold(text).gsub(/[#]+/, ' ').gsub(/\s+/, ' ').strip
          else
            text.to_s.downcase.gsub(/[#]+/, ' ').gsub(/\s+/, ' ').strip
          end
        end

        def material_names_for_product(product_code, panel_thickness_mm, back_thickness_mm, detail_name = nil)
          spec = material_spec_for_product(product_code, detail_name)
          return spec unless spec['ok']

          raw_code = spec['material_code'].to_s.strip
          names = material_names_for_code(raw_code, panel_thickness_mm, back_thickness_mm)
          panel_name = names['panel_material']
          back_name = names['back_material']
          return spec.merge('ok' => false, 'error' => 'Khong build duoc ten vat lieu theo do day.') if panel_name.to_s.empty? || back_name.to_s.empty?

          spec.merge(
            'ok' => true,
            'panel_material' => panel_name,
            'back_material' => back_name,
            'panel_source_material' => names['panel_source_material'].to_s,
            'back_source_material' => names['back_source_material'].to_s,
            'panel_code' => names['panel_code'].to_s,
            'back_code' => names['back_code'].to_s,
            'panel_thickness_mm' => panel_thickness_mm.to_f,
            'back_thickness_mm' => back_thickness_mm.to_f
          )
        rescue => e
          { 'ok' => false, 'error' => e.message, 'product_code' => product_code.to_s }
        end

        def material_names_for_code(raw_code, panel_thickness_mm, back_thickness_mm = nil)
          code = raw_code.to_s.strip
          return { 'ok' => false, 'error' => 'Ma vat lieu rong.' } if code.empty?
          base_code = material_code_without_thickness(code)

          panel_mm = panel_thickness_mm.to_f
          back_raw = back_thickness_mm.to_s.strip
          back_mm = back_raw.empty? ? panel_mm : back_raw.to_f
          cache_key = [
            material_names_cache_key,
            base_code.to_s.upcase,
            panel_mm.round(4),
            back_mm.round(4)
          ]
          @material_names_for_code_cache ||= {}
          cached = @material_names_for_code_cache[cache_key]
          return cached.dup if cached

          panel_name = material_name_for_thickness(base_code, panel_mm)
          back_name = material_name_for_thickness(base_code, back_mm)
          result = {
            'ok' => !panel_name.to_s.empty? && !back_name.to_s.empty?,
            'material_code' => base_code,
            'panel_material' => panel_name.to_s,
            'back_material' => back_name.to_s,
            'panel_source_material' => '',
            'back_source_material' => '',
            'panel_thickness_mm' => panel_mm,
            'back_thickness_mm' => back_mm,
            'panel_code' => material_thickness_code(panel_name, code, panel_mm),
            'back_code' => material_thickness_code(back_name, code, back_mm)
          }
          @material_names_for_code_cache[cache_key] = result.dup
          result
        rescue => e
          { 'ok' => false, 'error' => e.message, 'material_code' => code }
        end

        # Callback khi config thay đổi từ MH_Registry.
        def on_config_changed(config_data)
          reset_data_load_throttle
          sync_config(config_data)
        end

        private

        def self.material_name_for_thickness(raw_code, thickness_mm)
          if defined?(MH::MaterialApp::MaterialAssigner) &&
             MH::MaterialApp::MaterialAssigner.respond_to?(:material_name_for_multi_code)
            name = MH::MaterialApp::MaterialAssigner.material_name_for_multi_code(raw_code, thickness_mm.to_f)
            return name if name
          end

          if defined?(MH::MaterialApp::MaterialCodeBuilder) &&
             MH::MaterialApp::MaterialCodeBuilder.respond_to?(:material_name_from_code)
            return MH::MaterialApp::MaterialCodeBuilder.material_name_from_code(raw_code, thickness_mm.to_f)
          end

          nil
        end

        def self.material_thickness_code(material_name, raw_code, thickness_mm)
          name_parts = material_name.to_s.split('.')
          raw_parts = raw_code.to_s.split('.')
          return name_parts[1].to_s if raw_parts.length >= 2 && name_parts.length >= 2
          if defined?(MH::MaterialApp::MaterialCodeBuilder) &&
             MH::MaterialApp::MaterialCodeBuilder.respond_to?(:map_thickness)
            mapped = MH::MaterialApp::MaterialCodeBuilder.map_thickness(thickness_mm.to_f)
            return mapped.to_s.gsub(/\.0$/, '') unless mapped.to_s.empty?
          end
          thickness_mm.to_f.round(1).to_s.gsub(/\.0$/, '')
        end

        def self.split_material_codes(value)
          if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:split)
            return MH::MaterialCode.split(value)
          end

          value.to_s.split(/\s*&\s*/).map(&:strip).reject(&:empty?)
        end

        def self.material_code_without_thickness(value)
          if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:without_thickness)
            return MH::MaterialCode.without_thickness(value)
          end

          value = normalize_logical_material_code(value)
          parts = value.to_s.split('.').map(&:strip).reject(&:empty?)
          return '' if parts.empty?
          return parts.first if parts.length == 1

          if parts[1].to_s =~ /\A\d+(?:[,.]\d+)?\z/
            remove_count = 1
            if parts[2].to_s =~ /\A\d+\z/
              decimal_thickness = "#{parts[1]}.#{parts[2]}".to_f
              mapped = if defined?(MH::MaterialApp::MaterialCodeBuilder) &&
                          MH::MaterialApp::MaterialCodeBuilder.respond_to?(:map_thickness)
                         MH::MaterialApp::MaterialCodeBuilder.map_thickness(decimal_thickness)
                       end
              remove_count = 2 unless mapped.to_s.empty?
            end
            ([parts.first] + parts[(1 + remove_count)..-1].to_a).join('.')
          else
            parts.join('.')
          end
        end

        def self.normalize_logical_material_code(value)
          if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:display)
            return MH::MaterialCode.display(value)
          end

          if defined?(MH::MaterialApp::MaterialCodeBuilder) &&
             MH::MaterialApp::MaterialCodeBuilder.respond_to?(:normalize_logical_material_code)
            return MH::MaterialApp::MaterialCodeBuilder.normalize_logical_material_code(value)
          end

          code = value.to_s.strip.gsub(/\s+/, '')
          code.split('.').map(&:strip).reject(&:empty?).join('.')
        rescue
          value.to_s.strip
        end

        def self.load_from_json(json_path)
          raw = File.read(json_path, encoding: 'UTF-8')
          data = JSON.parse(raw)
          rows = data.is_a?(Array) ? data : []
          load_from_rows(rows)
          mark_loaded_data(json_path)
        end

        def self.load_from_rows(rows)
          MH::MaterialApp.excel_data = rows.map { |row| normalize_material_row(row) }
        end

        def self.normalize_material_row(row)
          return row unless row.is_a?(Hash)

          normalized = row.dup
          normalized['Ma_SP'] = first_present_value(normalized, [
            'Ma_SP', 'Mã SP', 'MÃ SP', 'Ma SP', 'MASP'
          ]) if normalized['Ma_SP'].to_s.strip.empty?
          normalized['Ten_SP'] = first_present_value(normalized, [
            'Ten_SP', 'Tên SP', 'TÊN SP', 'Ten SP'
          ]) if normalized['Ten_SP'].to_s.strip.empty?
          normalized['Ma_vat_lieu'] = first_present_value(normalized, [
            'Ma_vat_lieu', 'Mã vật liệu', 'MÃ VẬT LIỆU', 'Ma vat lieu', 'Material'
          ]) if normalized['Ma_vat_lieu'].to_s.strip.empty?
          normalized['Ten_chi_tiet'] = first_present_value(normalized, [
            'Ten_chi_tiet', 'Tên chi tiết', 'TÊN CHI TIẾT',
            'Quy cách vật liệu', 'QUY CÁCH VẬT LIỆU', 'Quy cach vat lieu'
          ]) if normalized['Ten_chi_tiet'].to_s.strip.empty?
          normalized
        end

        def self.first_present_value(row, keys)
          keys.each do |key|
            value = row[key]
            return value.to_s.strip unless value.to_s.strip.empty?
          end
          ''
        end

        def self.clear_material_names_cache
          @material_names_cache_key = nil
          @material_names_cache = nil
          @material_names_for_code_cache = {}
          @material_codes_by_product_cache = {}
          @material_spec_by_product_detail_cache = {}
        end

        def self.material_names_cache_key
          data = MH::MaterialApp.excel_data
          [data.object_id, data.length]
        end

        # Khi KHÔNG có Excel/project JSON, excel_data luôn rỗng → mỗi lần giải mã
        # VL (HUD Superimp vẽ mỗi frame) sẽ thử load lại: read_default + Dir.glob
        # quét đĩa + ném exception (model chưa lưu) → LAG. Throttle: vừa thử mà
        # vẫn rỗng thì bỏ qua trong DATA_LOAD_RETRY_TTL giây. Reset khi có
        # load_data/force_reload/on_config_changed để dữ liệu mới nhận ngay.
        remove_const(:DATA_LOAD_RETRY_TTL) if const_defined?(:DATA_LOAD_RETRY_TTL, false)
        DATA_LOAD_RETRY_TTL = 30.0

        def self.data_load_throttled?
          @data_load_attempt_at ||= 0.0
          now = Time.now.to_f
          return true if (now - @data_load_attempt_at) < DATA_LOAD_RETRY_TTL
          @data_load_attempt_at = now
          false
        end

        def self.reset_data_load_throttle
          @data_load_attempt_at = 0.0
          @latest_project_json_cache = nil
        end

        def self.current_model_key
          model = defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil
          return 'model:none' unless model

          path = (model.path rescue '').to_s.strip
          return "path:#{File.expand_path(path).tr('\\', '/').downcase}" unless path.empty?

          guid = (model.guid rescue '').to_s.strip
          guid.empty? ? "object:#{model.object_id}" : "guid:#{guid}"
        rescue
          'model:unknown'
        end

        def self.mark_loaded_data(source_path = nil)
          @loaded_data_model_key = current_model_key
          @loaded_data_source_path = source_path.to_s
          true
        rescue
          false
        end

        def self.loaded_data_current_for_model?
          !MH::MaterialApp.excel_data.empty? &&
            @loaded_data_model_key.to_s == current_model_key.to_s
        rescue
          false
        end

        def self.clear_loaded_data(reason = nil)
          MH::MaterialApp.excel_data = [] if available?
          @loaded_data_model_key = nil
          @loaded_data_source_path = nil
          clear_material_names_cache
          MH::ProjectData.invalidate!(reason: reason) if defined?(MH::ProjectData) && MH::ProjectData.respond_to?(:invalidate!)
          true
        rescue
          false
        end

        def self.ensure_material_names_data_loaded
          if !MH::MaterialApp.excel_data.empty?
            return true if loaded_data_current_for_model?
            clear_loaded_data('material_assign_model_changed')
          end
          return true unless MH::MaterialApp.excel_data.empty?
          return false if data_load_throttled?

          if MH::RegistryApp.respond_to?(:last_mvl_input_path)
            remembered_path = MH::RegistryApp.last_mvl_input_path.to_s.strip
            if !remembered_path.empty? && File.exist?(remembered_path)
              json_path = MH::RegistryApp.project_json_path(remembered_path) rescue nil
              if json_path && File.exist?(json_path)
                load_from_json(json_path)
                clear_material_names_cache
                return true unless MH::MaterialApp.excel_data.empty?
              end
            end
          end

          load_latest_project_json
        end

        def self.ensure_data_loaded
          if !MH::MaterialApp.excel_data.empty?
            return if loaded_data_current_for_model?
            clear_loaded_data('material_assign_model_changed')
          end
          return unless MH::MaterialApp.excel_data.empty?
          return if data_load_throttled?

          if MH::RegistryApp.respond_to?(:last_mvl_input_path)
            remembered_path = MH::RegistryApp.last_mvl_input_path.to_s.strip
            result = load_data(remembered_path) if !remembered_path.empty? && File.exist?(remembered_path)
            return if result && result['ok'] && !MH::MaterialApp.excel_data.empty?
          end

          return if load_latest_project_json

          MH::MaterialApp.ensure_excel_data_loaded

          if MH::MaterialApp.excel_data.empty? && MH::RegistryApp.respond_to?(:last_mvl_input_path)
            remembered_path = MH::RegistryApp.last_mvl_input_path.to_s.strip
            load_data(remembered_path) if !remembered_path.empty? && File.exist?(remembered_path)
          end
        end

        def self.load_latest_project_json
          spec_data = MH::RegistryApp.spec_data_dir rescue nil
          return false unless spec_data && Dir.exist?(spec_data)

          now = Time.now.to_f
          cached = @latest_project_json_cache
          if cached && cached[:dir] == spec_data && (now - cached[:checked_at].to_f) < DATA_LOAD_RETRY_TTL
            json_path = cached[:path]
          else
            json_path = Dir.glob(File.join(spec_data, '*.json')).sort_by { |f| File.mtime(f) }.last
            @latest_project_json_cache = { dir: spec_data, path: json_path, checked_at: now }
          end
          return false unless json_path && File.exist?(json_path)

          load_from_json(json_path)
          mark_loaded_data(json_path)
          clear_material_names_cache
          xlsx_path = File.join(MH::RegistryApp.spec_dir, File.basename(json_path, '.json') + '.xlsx') rescue nil
          MH::MaterialApp.remember_excel_path(xlsx_path) if xlsx_path && File.exist?(xlsx_path)
          puts "[MaterialAssign Connector] Loaded #{MH::MaterialApp.excel_data.length} rows from latest project JSON: #{File.basename(json_path)}"
          !MH::MaterialApp.excel_data.empty?
        rescue => e
          puts "[MaterialAssign Connector] load_latest_project_json error: #{e.message}"
          false
        end

        def self.normalize_result(result)
          return { 'ok' => false, 'error' => result[:error] } if result.is_a?(Hash) && result[:error]
          if result.is_a?(Hash)
            { 'ok' => true,
              'success' => result[:success].to_i,
              'processed' => result[:processed].to_i,
              'skipped' => (result[:processed].to_i - result[:success].to_i) }
          else
            { 'ok' => true }
          end
        end
      end
    end

    Connector.register('material_assign', Connectors::MaterialAssign)
  end
end
