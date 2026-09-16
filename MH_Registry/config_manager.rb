# encoding: UTF-8
#
# MH_Registry / config_manager.rb
# ---------------------------------------------------------------------------
# JSON là nguồn cấu hình chạy chính; Config.xlsx chỉ dùng để nhập/xuất thủ công.
# Được require từ main.rb.
# ---------------------------------------------------------------------------

require 'json'
require 'fileutils'
require 'digest'
require 'time'

module MH
  module RegistryApp
    CONFIG_FILE = 'Config.xlsx'.freeze
    SUPERIMP_LIBRARY_FILE = 'superimp_library.xlsx'.freeze
    CONFIG_JSON_FILE = 'mh_registry_config.json'.freeze
    CONFIG_MANIFEST_FILE = 'mh_registry_config_manifest.json'.freeze
    SUPERIMP_LIBRARY_SHEETS = %w[
      superimp_import_list
      dc_manual_materials
      dc_thickness_options
      dc_thickness_bindings
      dc_material_profiles
      dc_material_options
      material_profile_choices
    ].freeze

    module_function

    def config_path
      File.join(PATH, CONFIG_FILE)
    end

    def superimp_library_path
      File.join(PATH, SUPERIMP_LIBRARY_FILE)
    end

    def registry_json_dir
      if defined?(MH::Settings) && MH::Settings.respond_to?(:global_dir)
        MH::Settings.global_dir
      else
        File.join(PATH, 'json_config')
      end
    end

    def config_json_path
      File.join(registry_json_dir, CONFIG_JSON_FILE)
    end

    def config_manifest_path
      File.join(registry_json_dir, CONFIG_MANIFEST_FILE)
    end

    def write_registry_json(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp_#{$$}_#{rand(1_000_000)}"
      File.write(tmp, JSON.pretty_generate(data), encoding: 'UTF-8')
      FileUtils.mv(tmp, path)
      path
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    end

    def read_registry_json(path)
      JSON.parse(File.read(path, encoding: 'UTF-8'))
    end

    def file_sha256(path)
      return '' unless path && File.exist?(path)
      Digest::SHA256.file(path).hexdigest
    rescue
      ''
    end

    def write_config_json(data, source: 'runtime')
      data = scrub_removed_config_keys(data)
      payload = {
        'schema_version' => 1,
        'source' => source.to_s,
        'updated_at' => Time.now.utc.iso8601,
        'data' => data || {}
      }
      backup = "#{config_json_path}.bak_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
      FileUtils.cp(config_json_path, backup) if File.exist?(config_json_path)
      write_registry_json(config_json_path, payload)
      write_registry_manifest(source)
      config_json_path
    end

    # Lưu nháp tức thì từ UI: chỉ cập nhật JSON, không tạo backup/manifest
    # và không chạm vào workbook Excel. Workbook chỉ được ghi khi bấm Lưu.
    def autosave_config_json(data)
      data = scrub_removed_config_keys(data || {})
      synchronize_suffix_sources!(data)
      persist_project_settings!(data)
      apply_project_settings!(data)
      write_registry_json(config_json_path, {
        'schema_version' => 1,
        'source' => 'autosave_json',
        'updated_at' => Time.now.utc.iso8601,
        'data' => data
      })
      MH::NameGrammar.configure(data) if defined?(MH::NameGrammar)
      config_json_path
    end

    def load_config_json
      payload = read_registry_json(config_json_path)
      data = payload['data'].is_a?(Hash) ? payload['data'] : payload
      scrub_removed_config_keys(data)
      synchronize_suffix_sources!(data)
      apply_project_settings!(data)
      MH::NameGrammar.configure(data) if defined?(MH::NameGrammar)
      data
    end

    def scrub_removed_config_keys(data)
      return data unless data.is_a?(Hash)
      %w[ma_finish_groups ma_finish_group dc_type_groups].each do |key|
        data.delete(key)
        data.delete(key.to_sym)
      end
      data
    end

    def write_registry_manifest(source)
      manifest = {
        'version' => 1,
        'source' => source.to_s,
        'migrated_at' => Time.now.utc.iso8601,
        'json_path' => config_json_path,
        'source_files' => {
          CONFIG_FILE => {
            'path' => config_path,
            'mtime' => (File.mtime(config_path).utc.iso8601 rescue ''),
            'sha256' => file_sha256(config_path)
          },
          SUPERIMP_LIBRARY_FILE => {
            'path' => superimp_library_path,
            'mtime' => (File.mtime(superimp_library_path).utc.iso8601 rescue ''),
            'sha256' => file_sha256(superimp_library_path)
          }
        }
      }
      write_registry_json(config_manifest_path, manifest)
    rescue => e
      dbg("[MH_Registry] write manifest error: #{e.message}") if respond_to?(:dbg)
    end

    def json_clone(value)
      JSON.parse(JSON.generate(value))
    rescue
      value
    end

    def config_hash_value(data, key)
      return nil unless data.is_a?(Hash)
      data[key.to_s] || data[key.to_sym]
    end

    def product_family_token(value)
      text = value.to_s.strip.upcase
      match = text.match(/\A([A-Z]+)(?:\d+[A-Z]?|\.\.\.|\*)?\z/)
      match ? match[1] : ''
    end

    def product_rule_families_from_config(data)
      seps = config_hash_value(data, 'separators') || {}
      default_prefix = (seps['default_prefix'] || seps[:default_prefix] || 'SP').to_s.strip.upcase
      values = []
      Array(config_hash_value(data, 'prefix')).each { |value| values << product_family_token(value) }
      Hash(config_hash_value(data, 'prefix_columns') || {}).each_value do |rows|
        Array(rows).each { |value| values << product_family_token(value) }
      end
      Array(config_hash_value(data, 'all_prefix')).each { |value| values << product_family_token(value) }
      values << product_family_token(default_prefix)
      values = values.map(&:to_s).map(&:strip).reject(&:empty?).uniq
      values.empty? ? ['SP'] : values
    end

    def normalize_suffix_rule_entries(rows)
      Array(rows).map do |item|
        if item.is_a?(Hash)
          value = (item['value'] || item[:value] || item['text'] || item[:text]).to_s.strip
          shortcut = item['shortcut'] || item[:shortcut] || item['sc'] || item[:sc]
        else
          parts = item.to_s.split('|', 2).map(&:strip)
          value = parts[0].to_s
          shortcut = parts[1]
        end
        next if value.empty?
        sc = shortcut.to_s.strip
        { 'value' => value, 'shortcut' => sc.empty? ? nil : sc.to_i }
      end.compact.uniq { |row| row['value'] }
    end

    # Keep the legacy top-level suffix list and the virtual suffix layer in
    # product_code_rules identical. Both are still consumed by MH apps.
    def synchronize_suffix_sources!(data)
      return data unless data.is_a?(Hash)

      suffix = normalize_suffix_rule_entries(config_hash_value(data, 'suffix'))
      rules = config_hash_value(data, 'product_code_rules')
      layers = rules.is_a?(Hash) ? Array(config_hash_value(rules, 'layers')) : []
      layer = layers.find do |row|
        row.is_a?(Hash) && config_hash_value(row, 'key').to_s == 'suffix'
      end
      layer_suffix = normalize_suffix_rule_entries(config_hash_value(layer, 'values')) if layer

      suffix = layer_suffix if suffix.empty? && layer_suffix && !layer_suffix.empty?
      data['suffix'] = suffix
      layer['values'] = json_clone(suffix) if layer
      data
    end

    def default_product_code_rules_from_config(data)
      {
        'segment_separator' => '_',
        'uppercase' => true,
        'trim_segments' => true,
        'layers' => [
          {
            'key' => 'product_code',
            'label' => 'Mã sản phẩm',
            'type' => 'text_number',
            'source' => 'pattern',
            'required' => true,
            'values' => product_rule_families_from_config(data)
          },
          {
            'key' => 'module_no',
            'label' => 'Số module',
            'type' => 'number',
            'source' => 'number',
            'optional' => true,
            'values' => ['number']
          },
          {
            'key' => 'suffix',
            'label' => 'Tên suffix',
            'type' => 'text',
            'source' => 'dictionary',
            'required' => false,
            'optional' => true,
            'virtual' => true,
            'values' => normalize_suffix_rule_entries(config_hash_value(data, 'suffix'))
          }
        ]
      }
    end

    def sync_registry_rules_from_config!(data)
      return false unless data.is_a?(Hash)
      return false unless defined?(MH::Registry) && MH::Registry.respond_to?(:save_global!)

      product_rules = config_hash_value(data, 'product_code_rules')
      product_rules = default_product_code_rules_from_config(data) unless product_rules.is_a?(Hash) && !product_rules.empty?
      material_rules = config_hash_value(data, 'material_code_rules')
      changed = false
      global = MH::Registry.global

      if product_rules.is_a?(Hash) && !product_rules.empty?
        global['product_code_rules'] = json_clone(product_rules)
        changed = true
      end
      read_rules = config_hash_value(data, 'name_read_rules')
      if read_rules.is_a?(Array)
        global['name_read_rules'] = json_clone(read_rules)
        changed = true
      end
      if material_rules.is_a?(Hash) && !material_rules.empty?
        material_rules = json_clone(material_rules)
        # Mapping đã có nguồn duy nhất là material_code_library.xlsx.  Registry
        # chỉ giữ ngữ pháp/nhóm bề mặt cần cho Material Assign và các app cũ.
        material_rules.delete('mappings')
        sync_material_surface_groups!(material_rules)
        global['material_code_rules'] = material_rules
        # Migrate away the legacy parallel source on every normal save.
        global.delete('material_code_mappings')
        changed = true
      end

      MH::Registry.save_global!(global) if changed
      changed
    rescue => e
      dbg("[MH_Registry] sync registry rules error: #{e.class}: #{e.message}") if respond_to?(:dbg)
      false
    end

    # A surface token is a semantic rule, not merely a dictionary value.  The
    # mapping board supplies its canonical token; align the matching surface
    # group with that token so Melamine -> MEL cannot still be classified as MS.
    def sync_material_surface_groups!(rules)
      mappings = Array(rules['mappings'])
      groups = rules['surface_groups']
      return rules unless groups.is_a?(Hash)

      grouped_members = Hash.new { |hash, key| hash[key] = [] }
      mappings.each do |row|
        row = row.is_a?(Hash) ? row : {}
        next unless comparable_config_token(row['nhom'] || row['layer'] || row['key'] || row['group']) == 'BE_MAT'

        source = row['gia_tri'].to_s.strip
        canonical = row['gia_tri_map'].to_s.strip.upcase
        next if canonical.empty?

        matched_key = groups.keys.find do |key|
          rule = groups[key].is_a?(Hash) ? groups[key] : {}
          members = Array(rule['members']).map { |member| comparable_config_token(member) }
          comparable_config_token(key) == comparable_config_token(canonical) ||
            members.include?(comparable_config_token(canonical)) ||
            members.include?(comparable_config_token(source)) ||
            comparable_config_token(rule['label']) == comparable_config_token(source)
        end
        next unless matched_key

        grouped_members[matched_key] << canonical
      end

      grouped_members.each do |old_key, members|
        rule = groups.delete(old_key)
        next unless rule.is_a?(Hash)

        members = members.uniq
        # Keep the old key only when it remains the canonical token.  This is
        # what turns the legacy MS card into MEL after the user changes it.
        new_key = members.include?(old_key.to_s.upcase) ? old_key.to_s.upcase : members.first
        rule['members'] = members
        groups[new_key] = rule
      end
      rules['surface_groups'] = groups
      rules
    end

    def comparable_config_token(value)
      value.to_s.strip.upcase.gsub(/\s+/, ' ')
    end

    def settings_facade_available?
      defined?(MH::Settings) && MH::Settings.respond_to?(:read)
    end

    def apply_project_settings!(data)
      return data unless settings_facade_available? && data.is_a?(Hash)
      project_section = MH::Settings.section('registry', scope: :project)
      unless project_section.key?('dc_thickness_options_project')
        MH::Settings.write('registry', 'dc_thickness_options_project', Array(data['dc_thickness_options_project'] || []), scope: :project)
      end
      project_rows = MH::Settings.read('registry', 'dc_thickness_options_project', data['dc_thickness_options_project'] || [], scope: :project)
      data['dc_thickness_options_project'] = Array(project_rows)
      data['dc_thickness_options'] = merge_thickness_options(
        data['dc_thickness_options_library'] || [],
        data['dc_thickness_options_project'] || []
      )
      data
    rescue => e
      dbg("[MH_Registry] apply project settings error: #{e.message}") if respond_to?(:dbg)
      data
    end

    def persist_project_settings!(data)
      return false unless settings_facade_available? && data.is_a?(Hash)
      MH::Settings.write('registry', 'dc_thickness_options_project', Array(data['dc_thickness_options_project'] || []), scope: :project)
      true
    rescue => e
      dbg("[MH_Registry] persist project settings error: #{e.message}") if respond_to?(:dbg)
      false
    end

    def create_default_config
      path = config_path
      return path if File.exist?(path)
      sheets = {
        'settings' => [
          ['key', 'value'],
          ['sep_sub_prefix', '-'],
          ['sep_prefix', '_'],
          ['sep_suffix', '_'],
          ['default_prefix', 'SP']
        ],
        'sub_prefix' => [['value']],
        'prefix' => [['value']],
        'suffix' => [['value', 'shortcut'], ['L', '1'], ['R', '2'], ['A', ''], ['B', ''], ['Top', ''], ['Bot', ''], ['NEW', '']],
        'modul'  => [['value']],
        'ma_vat_lieu' => [['gia_tri', 'gia_tri_map', 'nhom', 'thu_tu']],
        'ma_thickness' => [['min', 'max', 'value']],
        'ma_detail_aliases' => [['pattern', 'target']],
        'ma_tag_materials' => [['tag_name', 'material_name']],
        'ma_column_aliases' => [['internal_name', 'alias']],
        'ma_surface_face_rules' => default_surface_face_rule_rows,
        'dc_thickness_options_project' => save_thickness_options_rows([]),
        'dc_thickness_bindings' => save_rows(default_dc_thickness_bindings, dc_thickness_binding_columns),
        'dc_manual_materials' => default_dc_manual_material_rows,
        'superimp_import_list' => save_rows([], superimp_import_list_columns),
        'panel_defaults' => save_rows([], %w[tool key value])
      }
      safe_write_xlsx(path, sheets)
      path
    end

    def load_config(force_excel: false)
      path = config_path
      return load_config_json if File.exist?(config_json_path) && !force_excel
      # Chỉ cần workbook khi đang nhập/migrate từ Excel.  Các lần mở app sau
      # sẽ quay về ngay từ JSON ở trên, không tạo hay đọc Excel nữa.
      create_default_config unless File.exist?(path)

      sub_prefix = []
      prefix = []
      suffix = []
      modul  = []
      settings = {
        'sep_sub_prefix' => '-', 'sep_prefix' => '_', 'sep_suffix' => '_',
        'default_prefix' => 'SP',
        'active_sub_prefix' => '', 'active_prefix' => '', 'active_modul' => ''
      }
      ma_vat_lieu = []

      begin
        all = MH::ExcelBridge.read_all(path)
        library_all = load_superimp_library_sheets(all)

        if all['settings']
          all['settings'].drop(1).each do |row|
            k = (row[0] || '').to_s.strip
            v = (row[1] || '').to_s
            settings[k] = v if settings.key?(k)
          end
        end

        # Đọc multi-column cho sub_prefix, prefix, modul
        sub_prefix_cols = load_multi_column(all, 'sub_prefix')
        prefix_cols     = load_multi_column(all, 'prefix')
        modul_cols      = load_multi_column(all, 'modul')

        if all['suffix']
          all['suffix'].drop(1).each do |row|
            v  = (row[0] || '').to_s.strip
            sc = (row[1] || '').to_s.strip
            next if v.empty?
            sc_int = sc.empty? ? nil : sc.to_i
            suffix << { 'value' => v, 'shortcut' => (sc_int && sc_int > 0 ? sc_int : nil) }
          end
        end

        if all['ma_vat_lieu']
          all['ma_vat_lieu'].drop(1).each do |row|
            gt  = (row[0] || '').to_s.strip
            gtm = (row[1] || '').to_s.strip
            # Keep canonical-only rows created from the material-code
            # structure. The user can fill gia_tri (input alias) later in
            # MH Control Panel; discard only completely empty rows.
            next if gt.empty? && gtm.empty?
            ma_vat_lieu << {
              'gia_tri'     => gt,
              'gia_tri_map' => gtm,
              'nhom'        => (row[2] || '').to_s.strip,
              'thu_tu'      => (row[3] || '').to_s.strip
            }
          end
        end
        # ---- Material Assign sheets (ma_*) ----
        ma_thickness = load_rows(all, 'ma_thickness', %w[min max value])
        ma_detail_aliases = load_rows(all, 'ma_detail_aliases', %w[pattern target])
        ma_tag_materials = load_rows(all, 'ma_tag_materials', %w[tag_name material_name])
        ma_column_aliases = load_rows(all, 'ma_column_aliases', %w[internal_name alias])
        ma_surface_face_rules =
          if all['ma_surface_face_rules']
            load_rows(all, 'ma_surface_face_rules', surface_face_rule_columns)
          else
            default_surface_face_rules
          end
        dc_material_profiles = load_rows(library_all, 'dc_material_profiles', dc_material_profile_columns)
        dc_material_options = load_rows(library_all, 'dc_material_options', dc_material_option_columns)
        dc_material_options = default_dc_material_options if dc_material_options.nil? || dc_material_options.empty?
        material_profile_choices = load_rows(library_all, 'material_profile_choices', material_profile_choice_columns)
        dc_thickness_options_library = load_thickness_options(library_all, 'dc_thickness_options')
        dc_thickness_options_project = load_thickness_options(all, 'dc_thickness_options_project')
        # Migrate 1 lần từ material_profile_choices (1 option) nếu library chưa có dữ liệu mới.
        if (dc_thickness_options_library.nil? || dc_thickness_options_library.empty?) &&
           material_profile_choices && !material_profile_choices.empty?
          dc_thickness_options_library = material_profile_choices.map do |r|
            {
              'material_type' => r['material_name'].to_s,
              'options' => [{ 'panel' => r['thickness_1'].to_s, 'back' => r['thickness_2'].to_s }]
            }
          end
        end
        dc_thickness_options = merge_thickness_options(dc_thickness_options_library, dc_thickness_options_project)
        dc_thickness_bindings = load_rows(library_all, 'dc_thickness_bindings', dc_thickness_binding_columns)
        dc_manual_materials = load_rows(library_all, 'dc_manual_materials', dc_manual_material_columns)
        dc_manual_materials = default_dc_manual_materials if dc_manual_materials.nil? || dc_manual_materials.empty?
        superimp_import_list = load_rows(library_all, 'superimp_import_list', superimp_import_list_columns)
        panel_defaults = load_rows(all, 'panel_defaults', %w[tool key value])
      rescue => e
        dbg("[MH_Registry] Error loading #{CONFIG_FILE}: #{e.message}") if respond_to?(:dbg)
      end

      # Active column values (cho MH_Rename dùng)
      active_spfx = settings['active_sub_prefix']
      active_pfx  = settings['active_prefix']
      active_mod  = settings['active_modul']

      data = {
        'sub_prefix_columns' => sub_prefix_cols,
        'prefix_columns'     => prefix_cols,
        'modul_columns'      => modul_cols,
        'sub_prefix' => active_values(sub_prefix_cols, active_spfx),
        'prefix'     => active_values(prefix_cols, active_pfx),
        'modul'      => active_values(modul_cols, active_mod),
        'all_sub_prefix' => all_values(sub_prefix_cols),
        'all_prefix'     => all_values(prefix_cols),
        'all_modul'      => all_values(modul_cols),
        'suffix' => suffix,
        'separators' => settings,
        'ma_vat_lieu' => ma_vat_lieu,
        'ma_vat_lieu_global' => ma_vat_lieu,
        'ma_thickness' => (ma_thickness || []),
        'ma_detail_aliases' => (ma_detail_aliases || []),
        'ma_tag_materials' => (ma_tag_materials || []),
        'ma_column_aliases' => (ma_column_aliases || []),
        'ma_surface_face_rules' => (ma_surface_face_rules || []),
        'dc_material_profiles' => (dc_material_profiles || []),
        'dc_material_options' => (dc_material_options || []),
        'material_profile_choices' => (material_profile_choices || []),
        'dc_thickness_options' => (dc_thickness_options || []),
        'dc_thickness_options_library' => (dc_thickness_options_library || []),
        'dc_thickness_options_project' => (dc_thickness_options_project || []),
        'dc_thickness_bindings' => (dc_thickness_bindings || []),
        'dc_manual_materials' => (dc_manual_materials || []),
        'superimp_import_list' => (superimp_import_list || []),
        'panel_defaults' => (panel_defaults || [])
      }
      if force_excel
        # "Tải từ Excel" phải coi Excel là nguồn mới nhất, ghi đè cả project
        # settings và JSON cache; không được để cache cũ phủ ngược dữ liệu vừa đọc.
        persist_project_settings!(data)
      else
        apply_project_settings!(data)
        persist_project_settings!(data)
      end
      MH::NameGrammar.configure(data) if defined?(MH::NameGrammar)
      if force_excel || !File.exist?(config_json_path)
        write_config_json(data, source: force_excel ? 'xlsx_reload' : 'xlsx_migration')
      end
      data
    end

    # Lưu cấu hình khi dùng app: chỉ JSON.  Ghi hai workbook XLSX rất tốn thời
    # gian vì ExcelBridge phải đóng gói lại toàn bộ sheet/XML; chỉ làm việc đó
    # khi người dùng yêu cầu xuất Excel.
    def save_config(data, export_excel: false)
      scrub_removed_config_keys(data)
      synchronize_suffix_sources!(data)
      sync_registry_rules_from_config!(data)
      persist_project_settings!(data)
      apply_project_settings!(data)
      if export_excel
        write_config_json(data, source: 'excel_export')
      else
        write_registry_json(config_json_path, {
          'schema_version' => 1,
          'source' => 'save_json',
          'updated_at' => Time.now.utc.iso8601,
          'data' => data
        })
      end
      return config_json_path unless export_excel

      save_superimp_library(data)

      seps = data['separators'] || {}
      settings_rows = [['key', 'value'],
        ['sep_sub_prefix',    seps['sep_sub_prefix']    || '-'],
        ['sep_prefix',        seps['sep_prefix']        || '_'],
        ['sep_suffix',        seps['sep_suffix']        || '_'],
        ['default_prefix',    seps['default_prefix']    || 'SP'],
        ['active_sub_prefix', seps['active_sub_prefix'] || ''],
        ['active_prefix',     seps['active_prefix']     || ''],
        ['active_modul',      seps['active_modul']      || '']
      ]
      spfx_rows = save_multi_column(data, 'sub_prefix')
      pfx_rows  = save_multi_column(data, 'prefix')
      sfx_rows  = [['value', 'shortcut']] + (data['suffix'] || []).map { |s|
        if s.is_a?(Hash)
          [s['value'].to_s, s['shortcut'] ? s['shortcut'].to_s : '']
        else
          [s.to_s, '']
        end
      }
      mod_rows = save_multi_column(data, 'modul')
      global_mvl = data['ma_vat_lieu_global'] || data['ma_vat_lieu'] || []
      mvl_rows = [['gia_tri', 'gia_tri_map', 'nhom', 'thu_tu']] + global_mvl.map { |r|
        if r.is_a?(Hash)
          [r['gia_tri'].to_s, r['gia_tri_map'].to_s, r['nhom'].to_s, r['thu_tu'].to_s]
        else
          [r.to_s, '', '', '']
        end
      }
      safe_write_xlsx(config_path, {
        'settings' => settings_rows,
        'sub_prefix' => spfx_rows, 'prefix' => pfx_rows, 'suffix' => sfx_rows, 'modul' => mod_rows,
        'ma_vat_lieu' => mvl_rows,
        'ma_thickness' => save_rows(data['ma_thickness'], %w[min max value]),
        'ma_detail_aliases' => save_rows(data['ma_detail_aliases'], %w[pattern target]),
        'ma_tag_materials' => save_rows(data['ma_tag_materials'], %w[tag_name material_name]),
        'ma_column_aliases' => save_rows(data['ma_column_aliases'], %w[internal_name alias]),
        'ma_surface_face_rules' => save_rows(data['ma_surface_face_rules'], surface_face_rule_columns),
        'panel_defaults' => save_rows(data['panel_defaults'], %w[tool key value]),
        'dc_thickness_options_project' => save_thickness_options_rows(
          data['dc_thickness_options_project'] || data['dc_thickness_options']
        )
      })
      config_path
    end

    # Xuất bản snapshot XLSX tương thích cho người cần chỉnh/sao lưu bằng
    # Excel. Đây là thao tác chủ động, không được gọi trên luồng Save thường.
    def export_config_excel(data)
      save_config(data, export_excel: true)
      {
        'config_path' => config_path,
        'superimp_library_path' => superimp_library_path
      }
    end

    def load_superimp_library_sheets(config_sheets = nil)
      ensure_superimp_library(config_sheets)
      MH::ExcelBridge.read_all(superimp_library_path)
    rescue => e
      dbg("[MH_Registry] Error loading #{SUPERIMP_LIBRARY_FILE}: #{e.message}") if respond_to?(:dbg)
      config_sheets || {}
    end

    def ensure_superimp_library(config_sheets = nil)
      if File.exist?(superimp_library_path)
        existing = MH::ExcelBridge.read_all(superimp_library_path) rescue {}
        missing = SUPERIMP_LIBRARY_SHEETS.reject { |name| existing.key?(name) }
        return superimp_library_path if missing.empty?

        defaults = default_superimp_library_sheets(config_sheets)
        missing.each { |name| existing[name] = defaults[name] }
        safe_write_xlsx(superimp_library_path, existing)
        dbg("[MH_Registry] Added missing sheets to #{SUPERIMP_LIBRARY_FILE}: #{missing.join(', ')}") if respond_to?(:dbg)
        return superimp_library_path
      end

      sheets = default_superimp_library_sheets(config_sheets)
      safe_write_xlsx(superimp_library_path, sheets)
      dbg("[MH_Registry] Created #{SUPERIMP_LIBRARY_FILE} from #{CONFIG_FILE}") if respond_to?(:dbg)
      superimp_library_path
    end

    def save_superimp_library(data)
      existing = File.exist?(superimp_library_path) ? (MH::ExcelBridge.read_all(superimp_library_path) rescue {}) : {}
      existing.delete('dc_type_groups')
      # Danh sách vật liệu là nguồn độc lập với bảng độ dày.  enabled=1
      # mới là mã được dùng cho chế độ Manual của Superimp.
      manual_rows = Array(data['dc_manual_materials'])
      sheets = existing.merge(
        'superimp_import_list' => save_rows(data['superimp_import_list'], superimp_import_list_columns),
        'dc_manual_materials' => save_rows(manual_rows, dc_manual_material_columns),
        'dc_thickness_options' => save_thickness_options_rows(
          data['dc_thickness_options_library'] || data['dc_thickness_options']
        ),
        'dc_thickness_bindings' => save_rows(data['dc_thickness_bindings'], dc_thickness_binding_columns),
        'dc_material_profiles' => save_rows(data['dc_material_profiles'], dc_material_profile_columns),
        'dc_material_options' => save_rows(data['dc_material_options'], dc_material_option_columns),
        'material_profile_choices' => save_rows(data['material_profile_choices'], material_profile_choice_columns)
      )
      safe_write_xlsx(superimp_library_path, sheets)
      superimp_library_path
    end

    def filter_manual_materials_by_thickness_library(manual_rows, thickness_rows)
      valid = {}
      Array(thickness_rows).each do |row|
        next unless row.is_a?(Hash)

        code = (row['material_type'] || row[:material_type] ||
                row['material_code'] || row[:material_code]).to_s.strip.upcase
        valid[code] = true unless code.empty?
      end

      Array(manual_rows).select do |row|
        next false unless row.is_a?(Hash)

        code = (row['material_code'] || row[:material_code] ||
                row['material_type'] || row[:material_type]).to_s.strip.upcase
        !code.empty? && valid[code]
      end
    end

    def ensure_superimp_library_data!(data)
      library = load_superimp_library_sheets
      unless data.key?('superimp_import_list') || data.key?(:superimp_import_list)
        data['superimp_import_list'] = load_rows(library, 'superimp_import_list', superimp_import_list_columns)
      end
      unless data.key?('dc_manual_materials') || data.key?(:dc_manual_materials)
        data['dc_manual_materials'] = load_rows(library, 'dc_manual_materials', dc_manual_material_columns)
      end
      unless data.key?('dc_thickness_options_library') || data.key?(:dc_thickness_options_library)
        data['dc_thickness_options_library'] = load_thickness_options(library, 'dc_thickness_options')
      end
      unless data.key?('dc_thickness_bindings') || data.key?(:dc_thickness_bindings)
        data['dc_thickness_bindings'] = load_rows(library, 'dc_thickness_bindings', dc_thickness_binding_columns)
      end
      unless data.key?('dc_material_profiles') || data.key?(:dc_material_profiles)
        data['dc_material_profiles'] = load_rows(library, 'dc_material_profiles', dc_material_profile_columns)
      end
      unless data.key?('dc_material_options') || data.key?(:dc_material_options)
        data['dc_material_options'] = load_rows(library, 'dc_material_options', dc_material_option_columns)
      end
      unless data.key?('material_profile_choices') || data.key?(:material_profile_choices)
        data['material_profile_choices'] = load_rows(library, 'material_profile_choices', material_profile_choice_columns)
      end
      data
    end

    def default_superimp_library_sheets(config_sheets = nil)
      source = config_sheets || {}
      {
        'superimp_import_list' =>
          sheet_or_default(source, 'superimp_import_list', save_rows([], superimp_import_list_columns)),
        'dc_manual_materials' =>
          sheet_or_default(source, 'dc_manual_materials', default_dc_manual_material_rows),
        'dc_thickness_options' =>
          sheet_or_default(source, 'dc_thickness_options', save_thickness_options_rows([])),
        'dc_thickness_bindings' =>
          sheet_or_default(source, 'dc_thickness_bindings', save_rows(default_dc_thickness_bindings, dc_thickness_binding_columns)),
        'dc_material_profiles' =>
          sheet_or_default(source, 'dc_material_profiles', default_dc_material_profile_rows),
        'dc_material_options' =>
          sheet_or_default(source, 'dc_material_options', default_dc_material_option_rows),
        'material_profile_choices' =>
          sheet_or_default(source, 'material_profile_choices', default_material_profile_choice_rows)
      }
    end

    def sheet_or_default(sheets, sheet_name, default_rows)
      rows = sheets && sheets[sheet_name]
      rows && !rows.empty? ? rows : default_rows
    end

    def superimp_import_list_columns
      %w[name path shortcut group swap_key]
    end

    # ---- Project paths (SPEC folder cùng cấp với SU) ----

    # Từ .skp path → thư mục dự án (lên 1 cấp từ folder chứa .skp)
    def project_root
      model = (defined?(Sketchup) ? Sketchup.active_model : nil)
      return nil unless model && !model.path.to_s.empty?
      File.dirname(File.dirname(model.path))  # SU/model.skp → lên 1 cấp
    end

    def spec_dir
      root = project_root
      return nil unless root
      File.join(root, 'SPEC')
    end

    def spec_data_dir
      s = spec_dir
      return nil unless s
      File.join(s, 'Data')
    end

    # Đường dẫn output xlsx: SPEC/{tên_file_input}.xlsx
    def project_xlsx_path(input_path = nil)
      s = spec_dir
      return nil unless s && input_path
      name = File.basename(input_path, '.*')
      File.join(s, "#{name}.xlsx")
    end

    # Đường dẫn output json: SPEC/Data/{tên_file_input}.json
    def project_json_path(input_path = nil)
      s = spec_data_dir
      return nil unless s && input_path
      name = File.basename(input_path, '.*')
      File.join(s, "#{name}.json")
    end

    # Tạo thư mục SPEC và SPEC/Data nếu chưa có
    def ensure_spec_dirs
      [spec_dir, spec_data_dir].each do |d|
        next unless d
        Dir.mkdir(d) unless Dir.exist?(d)
      end
    end

    # Đọc xlsx output (có header) → ghi JSON (Array<Hash>).
    # JSON là nguồn chạy của SuperImp/Material Assign, nên phải giữ key chuẩn
    # cho SP và VL ngay tại điểm chuyển đổi, không phụ thuộc vào tên cột Excel.
    PROJECT_JSON_HEADER_ALIASES = {
      'Ma_SP' => [
        'Ma_SP', 'ma_sp', 'Mã SP', 'MÃ SP', 'Ma SP', 'MASP',
        'Mã sản phẩm', 'MÃ SẢN PHẨM', 'Ma san pham', 'Product Code', 'SP'
      ],
      'Ten_SP' => [
        'Ten_SP', 'ten_sp', 'Tên SP', 'TÊN SP', 'Ten SP',
        'Tên sản phẩm', 'Ten san pham', 'Product Name'
      ],
      'Ma_vat_lieu' => [
        'Ma_vat_lieu', 'ma_vat_lieu', 'ma_vl', 'Mã vật liệu', 'MÃ VẬT LIỆU',
        'Ma vat lieu', 'Mã VL', 'Ma VL', 'MaVL', 'Material Code', 'Material', 'VL'
      ],
      'Ten_chi_tiet' => [
        'Ten_chi_tiet', 'ten_chi_tiet', 'Tên chi tiết', 'TÊN CHI TIẾT',
        'Quy cách vật liệu', 'QUY CÁCH VẬT LIỆU', 'Quy cach vat lieu',
        'Detail Name', 'Detail'
      ]
    }.freeze

    def export_xlsx_to_json(xlsx_path, json_path)
      selected = MH::XlsxIO.read_first_sheet_selected_columns(
        xlsx_path,
        {
          'Ma_SP' => PROJECT_JSON_HEADER_ALIASES['Ma_SP'],
          'Ma_vat_lieu' => PROJECT_JSON_HEADER_ALIASES['Ma_vat_lieu']
        },
        header_normalizer: method(:project_json_header_normalize)
      )
      return { 'ok' => false, 'error' => 'Khong tim thay cot Ma SP va Ma vat lieu trong file Excel.' } unless selected['header_row']

      # JSON runtime cố ý chỉ giữ dữ liệu cần cho chọn/gán vật liệu theo SP.
      # Không copy mọi cột từ Excel để tránh file dữ liệu lớn và parse thừa.
      current_product = ''
      data = Array(selected['rows']).filter_map do |row|
        ma_sp = row['Ma_SP'].to_s.strip
        ma_vl = row['Ma_vat_lieu'].to_s.strip
        next if ma_sp.empty? && ma_vl.empty?

        # Excel thường merge ô Ma_SP: các dòng chi tiết phía dưới có VL nhưng SP
        # trống. Fill-down ở JSON để cả SuperImp lẫn Material Assign chọn được
        # danh sách vật liệu theo đúng SP.
        current_product = ma_sp unless ma_sp.empty?
        ma_sp = current_product if ma_sp.empty? && !current_product.empty?
        product_ok = if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:valid?)
          MH::ProductContext.valid?(ma_sp)
        else
          ma_sp =~ /\A[A-Z]+\d+[A-Z]?(?:\.\d+)?\z/i
        end
        next unless product_ok || !ma_vl.empty?
        { 'Ma_SP' => ma_sp, 'Ma_vat_lieu' => ma_vl }
      end

      require 'fileutils'
      FileUtils.mkdir_p(File.dirname(json_path))
      File.write(json_path, JSON.pretty_generate(data), encoding: 'UTF-8')
      dbg("[MH_Registry] Exported #{data.length} rows to #{json_path}") if respond_to?(:dbg)
      { 'ok' => true, 'path' => json_path, 'rows_count' => data.length, 'sheet' => selected['sheet'].to_s }
    rescue => e
      dbg("[MH_Registry] export_xlsx_to_json error: #{e.message}") if respond_to?(:dbg)
      { 'ok' => false, 'error' => e.message }
    end

    def find_header_row(rows)
      rows.each_with_index do |row, i|
        if row.any? { |cell| project_json_header_key(cell) == 'Ma_SP' }
          return i
        end
      end
      nil
    end

    def project_json_header_key(value)
      text = value.to_s.strip
      return nil if text.empty?

      normalized = project_json_header_normalize(text)
      PROJECT_JSON_HEADER_ALIASES.each do |key, aliases|
        return key if aliases.any? { |item| project_json_header_normalize(item) == normalized }
      end
      nil
    end

    def project_json_header_normalize(value)
      text = value.to_s.strip
      text = MH::Text.fold(text) if defined?(MH::Text) && MH::Text.respond_to?(:fold)
      text.downcase.gsub(/[^a-z0-9]+/, '')
    rescue
      value.to_s.strip.downcase.gsub(/[^a-z0-9]+/, '')
    end

    def find_python
      candidates = [
        'C:/Program Files/Python312/python.exe',
        'C:/Program Files/Python311/python.exe',
        'C:/Program Files/Python310/python.exe',
        'C:/Program Files/Python39/python.exe',
      ]
      ['python', 'python3', 'py'].each do |cmd|
        p = `where #{cmd} 2>NUL`.strip.split("\n").first
        candidates.unshift(p) if p && !p.empty? && File.exist?(p)
      end
      candidates.detect { |p| p && File.exist?(p) }
    end

    # Đọc sheet multi-column → { 'col_name' => [values], ... }
    # Header row = tên cột. Mỗi cột = 1 bộ giá trị.
    def load_multi_column(all_sheets, sheet_name)
      return {} unless all_sheets[sheet_name]
      rows = all_sheets[sheet_name]
      return {} if rows.empty?
      headers = rows.first.map { |h| h.to_s.strip }
      result = {}
      headers.each_with_index do |h, col_i|
        next if h.empty?
        vals = []
        rows.drop(1).each do |row|
          v = (row[col_i] || '').to_s.strip
          vals << v unless v.empty?
        end
        result[h] = vals
      end
      result
    end

    # Ghi lại sheet nhiều cột. UI gửi *_columns là toàn bộ cột đã đọc từ Excel,
    # và gửi key chính là giá trị của cột active vừa chỉnh.
    def save_multi_column(data, key)
      columns = data["#{key}_columns"]
      active_name = (data.dig('separators', "active_#{key}") || '').to_s.strip
      active_values = Array(data[key]).map(&:to_s)

      unless columns.is_a?(Hash) && !columns.empty?
        header = active_name.empty? ? 'value' : active_name
        return [[header]] + active_values.map { |v| [v] }
      end

      normalized = {}
      columns.each do |name, values|
        col_name = name.to_s.strip
        next if col_name.empty?
        normalized[col_name] = Array(values).map(&:to_s)
      end

      active_name = normalized.keys.first if active_name.empty? || !normalized.key?(active_name)
      normalized[active_name] = active_values

      headers = normalized.keys
      max_len = normalized.values.map(&:length).max || 0
      rows = [headers]
      max_len.times do |i|
        rows << headers.map { |h| normalized[h][i].to_s }
      end
      rows
    end

    # Lấy values của active column. Fallback: cột đầu tiên.
    def active_values(cols, active_name)
      return [] if cols.empty?
      active_name = active_name.to_s.strip
      if !active_name.empty? && cols.key?(active_name)
        cols[active_name]
      else
        cols.values.first || []
      end
    end

    # Gộp tất cả values từ mọi cột (cho detection/parsing).
    def all_values(cols)
      cols.values.flatten.uniq
    end

    # Generic: đọc sheet thành Array<Hash> từ header row.
    def load_rows(all_sheets, sheet_name, columns)
      return [] unless all_sheets[sheet_name]
      all_sheets[sheet_name].drop(1).filter_map do |row|
        h = {}
        empty = true
        columns.each_with_index do |col, i|
          v = (row[i] || '').to_s.strip
          h[col] = v
          empty = false unless v.empty?
        end
        empty ? nil : h
      end
    end

    # Generic: ghi Array<Hash> thành sheet rows (header + data).
    def save_rows(data, columns)
      [columns] + (data || []).map { |r|
        if r.is_a?(Hash)
          columns.map { |c| r[c].to_s }
        else
          [r.to_s] + [''] * (columns.length - 1)
        end
      }
    end

    def surface_face_rule_columns
      %w[enabled surface_tokens max_one_side_thickness one_side_suffix two_side_details two_side_suffix default_suffix finish_suffix_overrides]
    end

    def default_surface_face_rules
      [{
        'enabled' => '1',
        'surface_tokens' => 'LAM,LAMINATE,LK,VENE,VER',
        'max_one_side_thickness' => '9',
        'one_side_suffix' => '.1M',
        'two_side_details' => 'Đợt|Đợt Cố Định|Hông Giữa|Cánh',
        'two_side_suffix' => '.2M',
        'default_suffix' => '.1M',
        'finish_suffix_overrides' => 'LK:.1M-BCT,.2M-BCT'
      }]
    end

    def default_surface_face_rule_rows
      save_rows(default_surface_face_rules, surface_face_rule_columns)
    end

    def dc_material_profile_columns
      %w[profile_id profile_name material_code panel_thickness_mm back_thickness_mm panel_material back_material]
    end

    def default_dc_material_profiles
      [
        {
          'profile_id' => 'MDFCA_AC_BACK8',
          'profile_name' => 'MDFCA.AC | Hau 8',
          'material_code' => 'MDFCA.AC',
          'panel_thickness_mm' => '18.6',
          'back_thickness_mm' => '8',
          'panel_material' => '',
          'back_material' => ''
        },
        {
          'profile_id' => 'MDFCA_AC_BACK11',
          'profile_name' => 'MDFCA.AC | Hau 11',
          'material_code' => 'MDFCA.AC',
          'panel_thickness_mm' => '18.6',
          'back_thickness_mm' => '11',
          'panel_material' => '',
          'back_material' => ''
        }
      ]
    end

    def default_dc_material_profile_rows
      save_rows(default_dc_material_profiles, dc_material_profile_columns)
    end

    def dc_material_option_columns
      %w[enabled material_code panel_thickness_mm back_thickness_mm]
    end

    def default_dc_material_options
      [
        {
          'enabled' => '1',
          'material_code' => 'PLY.AC.30YY-68/024-30',
          'panel_thickness_mm' => '17.6',
          'back_thickness_mm' => '8'
        },
        {
          'enabled' => '1',
          'material_code' => 'PLY.AC.30YY-68/024-30',
          'panel_thickness_mm' => '17.6',
          'back_thickness_mm' => '11'
        },
        {
          'enabled' => '1',
          'material_code' => 'GOSOI',
          'panel_thickness_mm' => '20',
          'back_thickness_mm' => ''
        }
      ]
    end

    def default_dc_material_option_rows
      save_rows(default_dc_material_options, dc_material_option_columns)
    end

    # ---- dc_manual_materials: danh sach vat lieu; enabled=1 dung cho Manual HUD ----
    def dc_manual_material_columns
      %w[enabled material_code sort_order]
    end

    def default_dc_manual_materials
      [
        { 'enabled' => '1', 'material_code' => 'HDFCA.AC.VERSOI', 'sort_order' => '1' },
        { 'enabled' => '1', 'material_code' => 'MDFCA.AC.MS',     'sort_order' => '2' }
      ]
    end

    def default_dc_manual_material_rows
      save_rows(default_dc_manual_materials, dc_manual_material_columns)
    end

    def material_profile_choice_columns
      %w[material_name thickness_1 thickness_2]
    end

    def default_material_profile_choices
      []
    end

    def default_material_profile_choice_rows
      save_rows(default_material_profile_choices, material_profile_choice_columns)
    end

    # ---- dc_thickness_options: bảng độ dày DC dạng RỘNG ----
    # Cột 0 = material_type; các cột sau theo cặp (opt*_panel, opt*_back) = mm thực tế.
    # Trả: [{ 'material_type' => 'MDFCA', 'options' => [{'panel'=>'17.6','back'=>'8'}, ...] }]
    def load_thickness_options(all_sheets, sheet_name = 'dc_thickness_options')
      rows = all_sheets[sheet_name]
      return [] unless rows && !rows.empty?
      rows.drop(1).filter_map do |row|
        next unless row.is_a?(Array)
        type = (row[0] || '').to_s.strip
        next if type.empty?
        options = []
        idx = 1
        while idx < row.length
          panel = (row[idx] || '').to_s.strip
          back  = (row[idx + 1] || '').to_s.strip
          options << { 'panel' => panel, 'back' => back } unless panel.empty? && back.empty?
          idx += 2
        end
        { 'material_type' => type, 'options' => options }
      end
    end

    def merge_thickness_options(library_rows, project_rows)
      result = []
      seen = {}
      Array(library_rows).each do |row|
        key = row['material_type'].to_s.strip.upcase
        next if key.empty? || seen[key]
        result << row
        seen[key] = true
      end
      Array(project_rows).each do |row|
        key = row['material_type'].to_s.strip.upcase
        next if key.empty? || seen[key]
        result << row
        seen[key] = true
      end
      result
    end

    # ---- dc_thickness_bindings: áp độ dày vào tham số TỪNG file DC ----
    # match: đường dẫn .skp (chứa chuỗi) | "group:<Nhóm>" ; unit: mm|length|none.
    # modul_only: tick dòng này thì Superimp mới tự cấp modul SP47.1, SP47.2...
    def dc_thickness_binding_columns
      # `label`: ten Custom (formlabel) — tu fill khi "Tao binding" tu bang hoc.
      %w[match label param_panel param_back param_extra product_only unit enabled modul_only]
    end

    def default_dc_thickness_bindings
      []
    end

    def save_thickness_options_rows(data)
      data = data || []
      max_opts = data.map { |r| Array(r['options'] || r[:options]).length }.max || 0
      max_opts = 2 if max_opts < 2 # luôn chừa tối thiểu 2 option cho dễ nhập
      header = ['material_type']
      (1..max_opts).each { |i| header.push("opt#{i}_panel", "opt#{i}_back") }
      rows = [header]
      data.each do |r|
        type = (r['material_type'] || r[:material_type]).to_s.strip
        next if type.empty?
        opts = Array(r['options'] || r[:options])
        line = [type]
        (0...max_opts).each do |i|
          o = opts[i] || {}
          line.push((o['panel'] || o[:panel]).to_s, (o['back'] || o[:back]).to_s)
        end
        rows << line
      end
      rows
    end

    def safe_write_xlsx(path, sheets)
      tmp = path + '.tmp'
      begin
        File.delete(tmp) if File.exist?(tmp)
        MH::ExcelBridge.write(tmp, sheets: sheets)
        File.delete(path) if File.exist?(path)
        File.rename(tmp, path)
      rescue Errno::EACCES, Errno::EPERM => e
        File.delete(tmp) if File.exist?(tmp) rescue nil
        filename = File.basename(path.to_s)
        raise "#{filename} đang bị Excel hoặc tiến trình khác khóa. Đóng file #{filename} rồi lưu lại. Chi tiết: #{e.message}"
      rescue => e
        File.delete(tmp) if File.exist?(tmp) rescue nil
        raise e
      end
    end
  end
end
