# encoding: UTF-8

require 'set'

module MH
  module RegistryApp
    module Menu
      @keys ||= Set.new
      @app_menus ||= {}
      @entries ||= []

      module_function

      def root
        @root ||= UI.menu('Extensions').add_submenu('MH')
      end

      def app_menu(app)
        name = app.to_s.strip
        name = 'General' if name.empty?
        @app_menus[name] ||= root.add_submenu(name)
      end

      def add(app:, key:, label:, &block)
        full_key = "#{app}:#{key}"
        if @keys.include?(full_key)
          entry = @entries.find { |e| e[:app].to_s == app.to_s && e[:key].to_s == key.to_s }
          if entry
            entry[:label] = label.to_s
            entry[:block] = block
          end
          return false
        end

        app_name = app.to_s
        entry_key = key.to_s
        cmd = UI::Command.new(label.to_s) { invoke(app_name, entry_key) }
        cmd.menu_text = label.to_s rescue nil
        cmd.tooltip = label.to_s rescue nil
        cmd.status_bar_text = label.to_s rescue nil
        app_menu(app).add_item(cmd)
        @keys << full_key
        @entries << { app: app.to_s, key: key.to_s, label: label.to_s, block: block }
        true
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::Menu] add #{full_key} error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end

      def command(label, &block)
        UI::Command.new(label, &block)
      end

      def clear_session_keys!
        @keys.clear
      end

      def keys
        @keys.to_a
      end

      # ---- Truy cập cho MH Control Panel ----------------------------------

      # Tất cả entry đã đăng ký: [{app:, key:, label:, block:}, ...]
      def entries
        @entries.dup
      end

      # Danh sách tên app (theo thứ tự xuất hiện lần đầu).
      def apps
        @entries.map { |e| e[:app] }.uniq
      end

      # Các entry của 1 app.
      def entries_for(app)
        @entries.select { |e| e[:app].to_s == app.to_s }
      end

      # Gọi block đã đăng ký theo "app:key" hoặc (app, key).
      def invoke(app, key = nil)
        if key.nil? && app.to_s.include?(':')
          app, key = app.to_s.split(':', 2)
        end
        entry = @entries.find { |e| e[:app].to_s == app.to_s && e[:key].to_s == key.to_s }
        return false unless entry && entry[:block]

        entry[:block].call
        true
      rescue => e
        MH::RegistryApp.dbg("[MH_Registry::Menu] invoke #{app}:#{key} error: #{e.class}: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
        false
      end
    end
  end
end
