# encoding: UTF-8

module MH
  module RegistryApp
    module Connectors
      module Assemble
        module_function

        def ensure_loaded
          return if defined?(MH::Assemble)
          path = File.join(Sketchup.find_support_file('Plugins'), 'MH_assemble', 'main.rb')
          load path if File.exist?(path)
        end

        def available?
          ensure_loaded
          defined?(MH::Assemble) && MH::Assemble.respond_to?(:scan)
        rescue
          false
        end

        def scan_tree
          ensure_loaded
          return {} unless available?
          MH::Assemble.scan
        end

        def tree_for_product(code)
          tree = scan_tree
          tree[code.to_s] || {}
        end

        def reload
          ensure_loaded
          MH::Assemble.scan_reset if available? && MH::Assemble.respond_to?(:scan_reset)
          true
        end
      end
    end

    Connector.register('assemble', Connectors::Assemble) if defined?(Connector)
  end
end
