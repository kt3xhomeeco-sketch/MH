# encoding: UTF-8
#
# MH_Registry / connector.rb
# ---------------------------------------------------------------------------
# Hệ thống connector — cho phép các app MH_* đăng ký và giao tiếp qua
# MH_Registry. Thêm app mới chỉ cần tạo file trong connectors/ folder.
#
# Usage:
#   MH::RegistryApp::Connector.register('material_assign', MyModule)
#   MH::RegistryApp::Connector.dispatch('material_assign', :load_data, path)
#   MH::RegistryApp::Connector.notify_config_changed(data)
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connector
      @registered ||= {}

      module_function

      # Đăng ký 1 connector module.
      def register(name, mod)
        @registered[name.to_s] = mod
        puts "[MH_Registry] Connector registered: #{name}"
      end

      # Lấy connector theo tên.
      def get(name)
        @registered[name.to_s]
      end

      def available?(name)
        c = get(name)
        return false unless c
        return c.available? if c.respond_to?(:available?)
        true
      rescue
        false
      end

      def supports?(name, method)
        c = get(name)
        c && c.respond_to?(method)
      rescue
        false
      end

      # Tất cả connectors đã đăng ký.
      def all
        @registered.dup
      end

      # Gọi method trên connector. Trả nil nếu connector/method không tồn tại.
      def dispatch(name, method, *args)
        c = @registered[name.to_s]
        return nil unless c && c.respond_to?(method)
        c.send(method, *args)
      rescue => e
        puts "[MH_Registry] Connector #{name}.#{method} error: #{e.message}"
        nil
      end

      def call(name, method, *args)
        c = @registered[name.to_s]
        return { ok: false, value: nil, reason: :no_app, error: nil } unless c
        return { ok: false, value: nil, reason: :no_method, error: nil } unless c.respond_to?(method)

        { ok: true, value: c.send(method, *args), reason: :ok, error: nil }
      rescue => e
        puts "[MH_Registry] Connector #{name}.#{method} error: #{e.message}"
        { ok: false, value: nil, reason: :raised, error: e.message }
      end

      # Notify tất cả connectors khi config thay đổi.
      def notify_config_changed(config_data)
        MH::NameGrammar.configure(config_data) if defined?(MH::NameGrammar)
        @registered.each do |name, c|
          next unless c.respond_to?(:on_config_changed)
          c.on_config_changed(config_data)
        rescue => e
          puts "[MH_Registry] #{name}.on_config_changed error: #{e.message}"
        end
      end

      # Auto-load tất cả file .rb trong connectors/ folder.
      def load_all
        dir = File.join(MH::RegistryApp::PATH, 'connectors')
        return unless Dir.exist?(dir)
        Dir.glob(File.join(dir, '*.rb')).sort.each do |f|
          begin
            load f
          rescue => e
            puts "[MH_Registry] Error loading connector #{File.basename(f)}: #{e.message}"
          end
        end
      end
    end
  end
end
