# encoding: UTF-8

module MH
  module RegistryApp
    module Connectors
      module Name
        module_function

        def load_plugin_file(dir, file)
          path = File.join(Sketchup.find_support_file('Plugins'), dir, file)
          load path if File.exist?(path)
        end

        def ensure_preferred_loaded
          return if defined?(MH::Rename::ViewportNameTool)
          load_plugin_file('MH_Rename', 'main.rb')
        end

        def ensure_legacy_loaded
          return if defined?(MH::Name::NameTool)
          load_plugin_file('MH_Name', 'main.rb')
        end

        def available?
          ensure_preferred_loaded
          defined?(MH::Rename::ViewportNameTool) || begin
            ensure_legacy_loaded
            defined?(MH::Name::NameTool)
          end
        rescue
          false
        end

        def show_labels(_entities = nil)
          ensure_preferred_loaded
          if defined?(MH::Rename::ViewportNameTool)
            Sketchup.active_model.select_tool(MH::Rename::ViewportNameTool.new)
            return true
          end

          ensure_legacy_loaded
          return false unless defined?(MH::Name::NameTool)
          Sketchup.active_model.select_tool(MH::Name::NameTool.new)
          true
        end

        def hide_labels
          Sketchup.active_model.select_tool(nil)
          true
        rescue
          false
        end
      end
    end

    Connector.register('name', Connectors::Name) if defined?(Connector)
  end
end
