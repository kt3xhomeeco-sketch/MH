# encoding: UTF-8
#
# MH_Registry / connectors / rename.rb
# ---------------------------------------------------------------------------
# Connector cho MH_Rename.
# - Sync naming config (prefix, suffix, modul, sub_prefix, separators)
#   từ Registry Config.xlsx → MH::Rename
# - Reload config khi user thay đổi từ MH_Registry UI
# ---------------------------------------------------------------------------

module MH
  module RegistryApp
    module Connectors
      module Rename
        module_function

        def available?
          defined?(MH::Rename) && MH::Rename.respond_to?(:auto_load_suggestions)
        end

        # Sync config từ Registry → MH::Rename class variables.
        def sync_config(config_data = nil)
          return false unless available?
          config_data ||= MH::RegistryApp.load_config

          sfx  = config_data['suffix'] || []
          mod  = config_data['modul'] || []
          spfx = config_data['sub_prefix'] || []
          seps = config_data['separators'] || {}

          # Không sync prefix cũ làm mã sản phẩm nữa; product code lấy từ MH::NameGrammar.
          pfx = []
          MH::Rename.prefix_suggestions = []
          MH::Rename.modul_suggestions  = mod
          MH::Rename.sub_prefix_suggestions = spfx
          # all_* = tất cả variants gộp lại, cho detection/parsing
          MH::Rename.instance_variable_set(:@all_prefix, [])
          MH::Rename.instance_variable_set(:@all_modul, config_data['all_modul'] || mod)
          MH::Rename.instance_variable_set(:@all_sub_prefix, config_data['all_sub_prefix'] || spfx)
          MH::Rename.name_separators = seps

          unless sfx.empty?
            MH::Rename.suffix_suggestions = []
            MH::Rename.shortcut_map = {}
            sfx.each do |s|
              if s.is_a?(Hash)
                val = s['value'].to_s
                sc  = s['shortcut']
                next if val.empty?
                MH::Rename.suffix_suggestions << val
                MH::Rename.shortcut_map[sc.to_s] = val if sc && sc.to_i > 0
              else
                MH::Rename.suffix_suggestions << s.to_s unless s.to_s.empty?
              end
            end
          end

          # Reset các dialog để tạo lại với config mới
          MH::Rename.instance_variable_set(:@qp_dialog, nil) rescue nil
          MH::Rename.instance_variable_set(:@qr_dialog, nil) rescue nil
          # Dialog rename chính sẽ dùng giá trị mới lần mở tiếp theo

          # Reload ViewportNameTool nếu đang active
          if defined?(MH::Rename::ViewportNameTool) && MH::Rename::ViewportNameTool.respond_to?(:instance)
            vpt = MH::Rename::ViewportNameTool.instance
            vpt.reload_config if vpt && vpt.respond_to?(:reload_config)
          end

          MH::RegistryApp.dbg("[Rename Connector] Config synced — product code from NameGrammar, #{sfx.length} suffix, #{mod.length} modul") if MH::RegistryApp.respond_to?(:dbg)
          true
        rescue => e
          MH::RegistryApp.dbg("[Rename Connector] sync_config error: #{e.message}") if MH::RegistryApp.respond_to?(:dbg)
          false
        end

        # Reload toàn bộ (gọi auto_load_suggestions gốc).
        def reload
          return false unless available?
          MH::Rename.auto_load_suggestions
          # Reset Quick Prefix/Rename dialogs để tạo lại với config mới
          MH::Rename.instance_variable_set(:@qp_dialog, nil) rescue nil
          MH::Rename.instance_variable_set(:@qr_dialog, nil) rescue nil
          true
        end

        # Callback khi config thay đổi từ MH_Registry.
        def on_config_changed(config_data)
          sync_config(config_data)
        end

        # Trả về config hiện tại của MH_Rename.
        def current_config
          return {} unless available?
          {
            'prefix' => [],
            'suffix' => MH::Rename.suffix_suggestions,
            'modul'  => MH::Rename.modul_suggestions,
            'shortcut_map' => MH::Rename.shortcut_map,
            'sub_prefix' => (MH::Rename.respond_to?(:sub_prefix_suggestions) ? MH::Rename.sub_prefix_suggestions : []),
            'separators' => (MH::Rename.respond_to?(:name_separators) ? MH::Rename.name_separators : {})
          }
        end
      end
    end

    Connector.register('rename', Connectors::Rename)
  end
end
