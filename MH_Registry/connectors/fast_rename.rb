# encoding: UTF-8
#
# MH_Registry / connectors / fast_rename.rb
# ---------------------------------------------------------------------------
# Connector cho MH_fast_rename.
# - Sync prefix config từ Registry Config.xlsx → MH::FastRename.
# - Reload config cho tool đang active khi user lưu config từ MH_Registry UI.
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module FastRename
        module_function

        def available?
          defined?(MH::FastRename) && MH::FastRename.respond_to?(:sync_registry_config)
        end

        def sync_config(config_data = nil)
          ensure_loaded
          return false unless available?

          config_data ||= MH::RegistryApp.load_config
          ok = MH::FastRename.sync_registry_config(config_data)
          reload_active_tool if ok
          module_count = MH::FastRename.respond_to?(:registry_project_modules) ? MH::FastRename.registry_project_modules.length : 0
          MH::RegistryApp.dbg("[FastRename Connector] Config synced — product code from NameGrammar, #{module_count} modul rule") if MH::RegistryApp.respond_to?(:dbg)
          ok
        rescue => e
          MH::RegistryApp.dbg("[FastRename Connector] sync_config error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          false
        end

        def reload
          sync_config
        end

        def on_config_changed(config_data)
          sync_config(config_data)
        end

        def current_config
          ensure_loaded
          return {} unless available?
          {
            'prefix' => [],
            'modules' => (MH::FastRename.respond_to?(:registry_project_modules) ? MH::FastRename.registry_project_modules : []),
            'available' => true
          }
        rescue
          { 'available' => false }
        end

        def ensure_loaded
          return if defined?(MH::FastRename)

          path = File.join(Sketchup.find_support_file('Plugins'), 'MH_fast_rename', 'main.rb')
          load path if File.exist?(path)
        end

        def reload_active_tool
          tool = Sketchup.active_model.tools.active_tool rescue nil
          return unless defined?(MH::FastRename::FastRenameTool)
          return unless tool.is_a?(MH::FastRename::FastRenameTool)
          return unless tool.respond_to?(:load_config)

          tool.load_config
        rescue => e
          MH::RegistryApp.dbg("[FastRename Connector] reload_active_tool error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        end
      end
    end

    Connector.register('fast_rename', Connectors::FastRename)
  end
end
