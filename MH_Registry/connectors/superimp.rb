# encoding: UTF-8

module MH
  module RegistryApp
    module Connectors
      module Superimp
        module_function

        IMPORT_LIST_SHEET = 'superimp_import_list'.freeze

        def ensure_loaded
          return if defined?(MH::Superimp)
          path = File.join(Sketchup.find_support_file('Plugins'), 'MH_Superimp', 'src', 'main.rb')
          load path if File.exist?(path)
        end

        def available?
          ensure_loaded
          defined?(MH::Superimp)
        rescue
          false
        end

        def import_list
          rows = registry_import_list
          rows.empty? ? legacy_import_list : rows
        end

        def import_item(name)
          ensure_loaded
          return false unless available?
          item = import_list.find { |row| row[:name].to_s == name.to_s }
          return false unless item && item[:path]
          MH::Superimp.import_or_replace(item[:path])
        end

        def reload
          ensure_loaded
          MH::Superimp.reload_import_list if available? && MH::Superimp.respond_to?(:reload_import_list)
        end

        def save_import_list(rows_data, merge: true)
          current = merge ? registry_import_list : []
          rows = merge_import_list(current, rows_data)
          config = MH::RegistryApp.load_config
          config['superimp_import_list'] = rows
          MH::RegistryApp.save_config(config)
          MH::RegistryApp::Connector.notify_config_changed(config) if defined?(MH::RegistryApp::Connector)
          ensure_loaded
          if defined?(MH::Superimp)
            MH::Superimp.reload_import_list if MH::Superimp.respond_to?(:reload_import_list)
            MH::Superimp.sync_registry_menu! if MH::Superimp.respond_to?(:sync_registry_menu!)
          end
          { 'ok' => true, 'count' => rows.length, 'source' => 'registry' }
        rescue => e
          { 'ok' => false, 'error' => e.message }
        end

        def migrate_legacy_import_list(xlsx_path = nil)
          legacy = legacy_import_list(xlsx_path)
          return { 'ok' => true, 'count' => registry_import_list.length, 'migrated' => 0 } if legacy.empty?

          before = registry_import_list.length
          result = save_import_list(legacy, merge: true)
          result['migrated'] = [result['count'].to_i - before, 0].max if result['ok']
          result
        end

        def registry_import_list
          config = MH::RegistryApp.load_config
          normalize_rows(config['superimp_import_list'])
        rescue => e
          MH::RegistryApp.dbg("[MH_Registry::Superimp] registry import_list error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def legacy_import_list(xlsx_path = nil)
          path = xlsx_path.to_s.strip
          if path.empty?
            path = File.join(Sketchup.find_support_file('Plugins'), 'MH_Superimp', 'src', 'import_list.xlsx')
          end
          return [] unless File.exist?(path)

          rows = MH::ExcelBridge.read_sheet(path, sheet: 'ImportList')
          normalize_rows(rows.drop(1).map do |row|
            {
              'name' => row[0],
              'path' => row[1],
              'shortcut' => row[2],
              'group' => row[3],
              'swap_key' => row[4]
            }
          end)
        rescue => e
          MH::RegistryApp.dbg("[MH_Registry::Superimp] legacy import_list error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          []
        end

        def merge_import_list(current_rows, incoming_rows)
          merged = {}
          normalize_rows(current_rows).each do |row|
            key = import_row_key(row)
            merged[key] = row unless key.empty?
          end

          normalize_rows(incoming_rows).each do |row|
            key = import_row_key(row)
            next if key.empty?

            existing = merged[key] || {}
            merged[key] = merge_import_row(existing, row)
          end
          merged.values
        end

        def merge_import_row(existing, incoming)
          result = existing.dup
          %w[name path shortcut group swap_key].each do |key|
            value = incoming[key].to_s.strip
            next if value.empty? && !existing[key].to_s.empty?

            result[key] = value
          end
          result['swap_key'] = result['swap_key'].to_i > 0 ? result['swap_key'].to_i.to_s : ''
          result
        end

        def normalize_rows(rows)
          Array(rows).filter_map do |row|
            h = row_hash(row)
            name = h['name'].to_s.strip
            path = h['path'].to_s.strip
            next if name.empty? && path.empty?

            group = h['group'].to_s.strip
            group = group.sub(/\.0$/, '') if group.end_with?('.0')
            swap_key = h['swap_key'].to_s.strip
            swap_key = swap_key.sub(/\.0$/, '') if swap_key.end_with?('.0')
            swap_int = swap_key.to_i
            {
              'name' => name,
              'path' => path,
              'shortcut' => h['shortcut'].to_s.strip,
              'group' => group,
              'swap_key' => swap_int > 0 ? swap_int.to_s : ''
            }
          end
        end

        def row_hash(row)
          return row.transform_keys(&:to_s) if row.is_a?(Hash)

          arr = Array(row)
          {
            'name' => arr[0],
            'path' => arr[1],
            'shortcut' => arr[2],
            'group' => arr[3],
            'swap_key' => arr[4]
          }
        end

        def import_row_key(row)
          path = row['path'].to_s.tr('\\', '/').strip.downcase
          return "path:#{path}" unless path.empty?

          name = row['name'].to_s.strip.downcase
          name.empty? ? '' : "name:#{name}"
        end
      end
    end

    Connector.register('superimp', Connectors::Superimp) if defined?(Connector)
  end
end
