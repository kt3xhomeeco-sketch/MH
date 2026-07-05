# encoding: UTF-8

module MH
  module RegistryApp
    module Connectors
      module Panel
        module_function

        SHEET = 'panel_defaults'.freeze

        def ensure_loaded
          return if defined?(MH::Panel::TaoVan) && defined?(MH::Panel::TaoCanh)

          path = File.join(Sketchup.find_support_file('Plugins'), 'MH_panel', 'src', 'main.rb')
          load path if File.exist?(path)
        end

        def available?
          ensure_loaded
          !!(defined?(MH::Panel::TaoVan) && defined?(MH::Panel::TaoCanh))
        rescue
          false
        end

        def activate(tool)
          ensure_loaded
          case tool.to_s
          when 'tao_van'
            MH::Panel.activate_tao_van
          when 'tao_canh'
            MH::Panel.activate_tao_canh
          else
            false
          end
        end

        def defaults(tool)
          rows = panel_rows
          out = {}
          rows.each do |row|
            next unless row['tool'].to_s == tool.to_s

            out[row['key'].to_s] = row['value']
          end
          out
        rescue => e
          MH::RegistryApp.dbg("[MH_Registry::Panel] defaults error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          {}
        end

        def save_defaults(tool, hash)
          config = MH::RegistryApp.load_config
          current = panel_rows(config).reject { |row| row['tool'].to_s == tool.to_s }
          hash.each { |key, value| current << { 'tool' => tool.to_s, 'key' => key.to_s, 'value' => value } }
          config[SHEET] = current
          if MH::RegistryApp.respond_to?(:save_config)
            MH::RegistryApp.save_config(config)
            MH::RegistryApp::Connector.notify_config_changed(config) if defined?(MH::RegistryApp::Connector)
          end
          { 'ok' => true, 'count' => current.length }
        rescue => e
          { 'ok' => false, 'error' => e.message }
        end

        def on_config_changed(_config_data)
          MH::Panel::Preset.reload_display_cache if defined?(MH::Panel::Preset)
        rescue => e
          MH::RegistryApp.dbg("[MH_Registry::Panel] on_config_changed error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        end

        def panel_rows(config = nil)
          config ||= MH::RegistryApp.load_config
          normalize_rows(config[SHEET] || [])
        end

        def normalize_rows(rows)
          Array(rows).filter_map do |row|
            h = row.is_a?(Hash) ? row.transform_keys(&:to_s) : {
              'tool' => row[0],
              'key' => row[1],
              'value' => row[2]
            }
            next if h['tool'].to_s.strip.empty? || h['key'].to_s.strip.empty?

            { 'tool' => h['tool'].to_s.strip, 'key' => h['key'].to_s.strip, 'value' => h['value'] }
          end
        end
      end
    end

    Connector.register('panel', Connectors::Panel) if defined?(Connector)
  end
end
