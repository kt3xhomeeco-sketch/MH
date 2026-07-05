# encoding: UTF-8
#
# MH_Registry / main.rb
# ---------------------------------------------------------------------------
# Trung tâm điều khiển hệ sinh thái MH_*.
# Modules:
#   config_manager.rb  — đọc/ghi Config.xlsx
#   connector.rb       — hệ thống connector cho các app MH_*
#   connectors/*.rb    — connector cụ thể cho từng app
# ---------------------------------------------------------------------------

require 'sketchup.rb'
require 'json'

module MH
  module RegistryApp
    PATH = File.dirname(__FILE__) unless defined?(self::PATH)
    DEFAULTS_KEY = 'MH_Registry' unless defined?(self::DEFAULTS_KEY)
    LAST_MVL_INPUT_KEY = 'LastMVLInputPath' unless defined?(self::LAST_MVL_INPUT_KEY)
    DEBUG = false unless const_defined?(:DEBUG, false)

    def self.dbg(message)
      puts message if DEBUG
    end

    # Nạp hạ tầng dùng chung (idempotent).
    shared_loader = File.join(File.dirname(PATH), 'MH_shared.rb')
    require(shared_loader)
    raise "[MH_Registry] requires MH_shared" unless defined?(MH::Shared)

    # Nạp modules.
    require File.join(PATH, 'config_manager.rb')
    require File.join(PATH, 'connector.rb')
    require File.join(PATH, 'menu_builder.rb')
    require File.join(PATH, 'control_panel.rb')

    module_function

    def ensure_runtime_ready(force = false)
      # QUAN TRỌNG: Connector.load_all phải nằm SAU guard. Mỗi lần `load` lại
      # file connector sẽ chạy lại thân module → reset state (vd
      # @thickness_options_by_type = {}, @bindings = []). Nếu để trước guard,
      # các lần gọi sau (MH_Superimp activate tool) sẽ XÓA config đã nạp mà
      # không push lại → độ dày từ Registry không tới Superimp.
      return true if @runtime_ready && !force

      Connector.load_all
      data = load_config
      Connector.notify_config_changed(data)
      @runtime_ready = true
      true
    rescue => e
      dbg("[MH_Registry] ensure_runtime_ready error: #{e.class}: #{e.message}")
      false
    end

    def show(tab = nil)
      section = tab.to_s.empty? ? 'reg_main' : "reg_#{tab}"
      ControlPanel.open(section)
    end

    def load_app_file(*parts)
      path = File.join(Sketchup.find_support_file('Plugins'), *parts)
      load path if File.exist?(path)
    rescue => e
      dbg("[MH_Registry] load_app_file #{parts.join('/')} error: #{e.class}: #{e.message}")
      false
    end

    def register_default_menu
      # Đăng ký lại các command của MH Panel để SketchUp Preferences > Shortcuts
      # nhìn thấy, nhưng không khôi phục bảng/dialog MH Panel 1.0.0 riêng.
      Menu.add(app: 'Panel', key: 'settings', label: 'MH Panel Settings') do
        load_app_file('MH_panel', 'src', 'main.rb') unless defined?(MH::Panel::Settings)
        MH::Panel.open_settings('cai_dat') if defined?(MH::Panel)
      end
      Menu.add(app: 'Panel', key: 'tao_van', label: 'Dựng Tấm Ván') do
        load_app_file('MH_panel', 'src', 'main.rb') unless defined?(MH::Panel::TaoVan)
        MH::Panel.activate_tao_van if defined?(MH::Panel)
      end
      Menu.add(app: 'Panel', key: 'tao_canh', label: 'Dựng Cánh Tủ') do
        load_app_file('MH_panel', 'src', 'main.rb') unless defined?(MH::Panel::TaoCanh)
        MH::Panel.activate_tao_canh if defined?(MH::Panel)
      end

      Menu.add(app: 'Rename', key: 'rename_selected', label: 'Rename Selected') do
        load_app_file('MH_Rename', 'main.rb') unless defined?(MH::Rename)
        MH::Rename.rename_selected if defined?(MH::Rename)
      end
      Menu.add(app: 'Rename', key: 'quick_prefix', label: 'Quick Prefix') do
        load_app_file('MH_Rename', 'main.rb') unless defined?(MH::Rename)
        MH::Rename.quick_prefix if defined?(MH::Rename)
      end
      Menu.add(app: 'Rename', key: 'quick_rename', label: 'Quick Rename') do
        load_app_file('MH_Rename', 'main.rb') unless defined?(MH::Rename)
        MH::Rename.quick_rename if defined?(MH::Rename)
      end
      Menu.add(app: 'Rename', key: 'viewport_names', label: 'Viewport Names') do
        load_app_file('MH_Rename', 'main.rb') unless defined?(MH::Rename)
        Sketchup.active_model.select_tool(MH::Rename::ViewportNameTool.new) if defined?(MH::Rename::ViewportNameTool)
      end
      Menu.add(app: 'Rename', key: 'rename_shortcut', label: 'Rename Shortcut (1-9)') do
        load_app_file('MH_Rename', 'main.rb') unless defined?(MH::Rename)
        Sketchup.active_model.select_tool(MH::Rename::RenameShortcutTool.new) if defined?(MH::Rename::RenameShortcutTool)
      end
      Menu.add(app: 'Rename', key: 'focus_dialog', label: 'Focus Dialog') do
        load_app_file('MH_Rename', 'main.rb') unless defined?(MH::Rename)
        MH::Rename.focus_active_dialog if defined?(MH::Rename)
      end
      Menu.add(app: 'Rename', key: 'reload_excel', label: 'Reload Excel Config') do
        load_app_file('MH_Rename', 'main.rb') unless defined?(MH::Rename)
        if defined?(MH::Rename)
          MH::Rename.auto_load_suggestions
          if defined?(MH::Rename::ViewportNameTool) && MH::Rename::ViewportNameTool.instance
            MH::Rename::ViewportNameTool.instance.reload_config
          end
          UI.messagebox("Đã tải lại Config (MH_Registry / Excel)")
        end
      end

      Menu.add(app: 'Select Similar', key: 'select_tool', label: 'Select Similar') do
        load_app_file('MH_SelectSimilar', 'main.rb') unless defined?(MH::SelectSimilar)
        Sketchup.active_model.select_tool(MH::SelectSimilar::SelectSimilarTool.new) if defined?(MH::SelectSimilar::SelectSimilarTool)
      end
      Menu.add(app: 'Select Similar', key: 'isolate', label: 'Isolate/Unisolate Selected') do
        load_app_file('MH_SelectSimilar', 'main.rb') unless defined?(MH::SelectSimilar)
        MH::SelectSimilar.toggle_isolate if defined?(MH::SelectSimilar)
        Sketchup.active_model.active_view.invalidate rescue nil
      end

      Menu.add(app: 'Fast Rename', key: 'tool', label: 'Fast Rename Tool') do
        load_app_file('MH_fast_rename', 'main.rb') unless defined?(MH::FastRename)
        MH::FastRename.activate_tool if defined?(MH::FastRename)
      end
      Menu.add(app: 'Fast Rename', key: 'sp_prefix', label: 'Chia theo mã SP gốc') do
        load_app_file('MH_fast_rename', 'main.rb') unless defined?(MH::FastRename)
        MH::FastRename.activate_sp_prefix_tool if defined?(MH::FastRename)
      end
      Menu.add(app: 'Fast Rename', key: 'reload', label: 'Reload') do
        load_app_file('MH_fast_rename', 'main.rb') unless defined?(MH::FastRename)
        MH::FastRename.reload if defined?(MH::FastRename)
      end

      Menu.add(app: 'Thongke', key: 'main', label: 'MH Thongke') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke)
          MH_Thongke.instance_variable_set(:@defer_next_process_selection, true)
          MH_Thongke.process_selection if MH_Thongke.respond_to?(:process_selection)
          MH_Thongke.show_dialog if MH_Thongke.respond_to?(:show_dialog)
        end
      end
      Menu.add(app: 'Thongke', key: 'mini_import', label: 'Mini Import Phu Kien') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        MH_Thongke.force_show_import_mini_dialog if defined?(MH_Thongke) && MH_Thongke.respond_to?(:force_show_import_mini_dialog)
      end
      Menu.add(app: 'Thongke', key: 'mini_import_reset_position', label: 'Reset Mini Import Position') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke)
          MH_Thongke.reset_import_mini_dialog_position if MH_Thongke.respond_to?(:reset_import_mini_dialog_position)
          MH_Thongke.force_show_import_mini_dialog(nil, true) if MH_Thongke.respond_to?(:force_show_import_mini_dialog)
        end
      end
      Menu.add(app: 'Thongke', key: 'material_hud', label: 'Material HUD') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        MH_Thongke.show_import_material_hud if defined?(MH_Thongke) && MH_Thongke.respond_to?(:show_import_material_hud)
      end
      Menu.add(app: 'Thongke', key: 'info_hud', label: 'Info HUD') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        MH_Thongke.toggle_info_hud if defined?(MH_Thongke) && MH_Thongke.respond_to?(:toggle_info_hud)
      end
      Menu.add(app: 'Thongke', key: 'profile_pipeline', label: 'Dev: Profile Pipeline') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke) && MH_Thongke.respond_to?(:profile_pipeline)
          require 'json'
          result = MH_Thongke.profile_pipeline(include_full_pipeline: true)
          puts JSON.pretty_generate(result)
          summary = MH_Thongke.respond_to?(:profile_pipeline_summary) ? MH_Thongke.profile_pipeline_summary(result) : result.to_s
          UI.messagebox(summary)
        end
      end
      Menu.add(app: 'Thongke', key: 'pipeline_audit_log', label: 'Dev: Pipeline Audit Log') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke) && MH_Thongke.respond_to?(:pipeline_profile_events)
          require 'json'
          events = MH_Thongke.pipeline_profile_events(20)
          puts JSON.pretty_generate(events)
          counts = events.each_with_object(Hash.new(0)) { |row, acc| acc[row[:status].to_s] += 1 }
          summary = ["Pipeline Audit Log", "events=#{events.length}"]
          summary.concat(counts.map { |status, count| "#{status}=#{count}" })
          last = events.last
          summary << "last=#{last[:reason]} #{last[:status]} #{last[:duration_ms]}ms" if last
          UI.messagebox(summary.join("\n"))
        end
      end
      Menu.add(app: 'Thongke', key: 'idle_preload_now', label: 'Dev: Idle Preload Now') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke) && MH_Thongke.respond_to?(:run_idle_preload_now)
          require 'json'
          result = MH_Thongke.run_idle_preload_now("idle_preload_menu", require_visible: false)
          puts JSON.pretty_generate(result)
          UI.messagebox([
            "Idle Preload",
            "ran=#{result[:ran]} status=#{result[:process_status]}",
            "duration=#{result[:duration_ms]}ms",
            "mini=#{result[:mini_prewarm]} hud=#{result[:hud_prewarm]}",
            result[:skip_reason] ? "skip=#{result[:skip_reason]}" : nil,
            result[:error] ? "error=#{result[:error]}" : nil
          ].compact.join("\n"))
        end
      end
      Menu.add(app: 'Thongke', key: 'p4_delta_status', label: 'Dev: P4 Delta Status') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke) && MH_Thongke.respond_to?(:p4_delta_status)
          require 'json'
          status = MH_Thongke.p4_delta_status
          events = MH_Thongke.respond_to?(:p4_delta_changed_events) ? MH_Thongke.p4_delta_changed_events(20) : []
          top_keys = MH_Thongke.respond_to?(:p4_delta_changed_top_keys) ? MH_Thongke.p4_delta_changed_top_keys(20) : []
          payload = { status: status, changed_top_keys: top_keys, events: events }
          puts JSON.pretty_generate(payload)
          UI.messagebox([
            "P4 Delta Status",
            "tracked=#{status[:tracked]} snapshot=#{status[:snapshot_tracked]}",
            "events=#{events.length} changed_roots=#{top_keys.length}",
            top_keys.first ? "first_root=#{top_keys.first}" : nil
          ].compact.join("\n"))
        end
      end
      Menu.add(app: 'Thongke', key: 'p4_delta_merge_dry_run', label: 'Dev: P4 Delta Merge Dry Run') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke) && MH_Thongke.respond_to?(:p4_delta_merge_dry_run)
          require 'json'
          result = MH_Thongke.p4_delta_merge_dry_run
          puts JSON.pretty_generate(result)
          UI.messagebox([
            "P4 Delta Merge Dry Run",
            "roots=#{result[:root_count]} scan=#{result[:changed_scan_ms]}ms pipe=#{result[:changed_pipeline_ms]}ms",
            "keys acc/mat=#{result[:changed_data_keys]}/#{result[:changed_mat_keys]}",
            "row_replace_safe=#{result[:row_replace_safe]}",
            "collisions acc/mat=#{result[:data_collision_count]}/#{result[:mat_collision_count]}"
          ].join("\n"))
        end
      end
      Menu.add(app: 'Thongke', key: 'p4_delta_product_dry_run', label: 'Dev: P4 Delta Product Dry Run') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke) && MH_Thongke.respond_to?(:p4_delta_product_dry_run)
          require 'json'
          result = MH_Thongke.p4_delta_product_dry_run
          puts JSON.pretty_generate(result)
          UI.messagebox([
            "P4 Delta Product Dry Run",
            "products=#{Array(result[:affected_product_bases]).join(', ')}",
            "roots=#{result[:root_count]} scan=#{result[:changed_scan_ms]}ms pipe=#{result[:changed_pipeline_ms]}ms",
            "diff_pass=#{result[:product_replace_diff_pass]}"
          ].join("\n"))
        end
      end
      Menu.add(app: 'Thongke', key: 'p4_delta_product_apply', label: 'Dev: P4 Delta Product Apply') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke) && MH_Thongke.respond_to?(:p4_delta_product_apply)
          require 'json'
          result = MH_Thongke.p4_delta_product_apply
          puts JSON.pretty_generate(result)
          UI.messagebox([
            "P4 Delta Product Apply",
            "applied=#{result[:applied]} diff_pass=#{result[:product_replace_diff_pass]}",
            "products=#{Array(result[:affected_product_bases]).join(', ')}",
            "roots=#{result[:root_count]} scan=#{result[:changed_scan_ms]}ms pipe=#{result[:changed_pipeline_ms]}ms"
          ].join("\n"))
        end
      end
      Menu.add(app: 'Thongke', key: 'p4_delta_smoke_real_ops', label: 'Dev: P4 Delta Smoke Real Ops') do
        load_app_file('MH_Thongke', 'main.rb') unless defined?(MH_Thongke)
        if defined?(MH_Thongke) && MH_Thongke.respond_to?(:p4_delta_smoke_real_ops)
          require 'json'
          result = MH_Thongke.p4_delta_smoke_real_ops
          puts JSON.pretty_generate(result)
          rows = Array(result[:results])
          pass_count = rows.count { |row| row[:diff_inc_full_pass] && row[:diff_restore_full_pass] && row[:diff_restore_baseline_pass] }
          UI.messagebox([
            "P4 Delta Smoke Real Ops",
            "ok=#{result[:ok]} root=#{result[:root_key]}",
            "pass=#{pass_count}/#{rows.length}",
            "final_baseline=#{result[:final_baseline_pass]}",
            "cleanup=#{result[:cleanup]}"
          ].join("\n"))
        end
      end

      Menu.add(app: 'Material', key: 'import', label: 'Import Excel/CSV/JSON') do
        load_app_file('MH_Material_Assign', 'main.rb') unless defined?(MH::MaterialApp)
        MH::MaterialApp.import_excel_data if defined?(MH::MaterialApp)
      end
      Menu.add(app: 'Material', key: 'assign_selection', label: 'Assign Selection') do
        load_app_file('MH_Material_Assign', 'main.rb') unless defined?(MH::MaterialApp)
        MH::MaterialApp.assign_to_selection if defined?(MH::MaterialApp)
      end
      Menu.add(app: 'Material', key: 'assign_all', label: 'Assign All') do
        load_app_file('MH_Material_Assign', 'main.rb') unless defined?(MH::MaterialApp)
        MH::MaterialApp.assign_to_all if defined?(MH::MaterialApp)
      end

      Menu.add(app: 'Name', key: 'show_labels', label: 'Hiển thị tên đối tượng') do
        load_app_file('MH_Rename', 'main.rb') unless defined?(MH::Rename::ViewportNameTool)
        result = Connector.dispatch('name', :show_labels)
        unless result
          load_app_file('MH_Name', 'main.rb') unless defined?(MH::Name::NameTool)
          Sketchup.active_model.select_tool(MH::Name::NameTool.new) if defined?(MH::Name::NameTool)
        end
      end

      Menu.add(app: 'Assemble', key: 'dashboard', label: 'MH Assemble') do
        load_app_file('MH_assemble', 'main.rb') unless defined?(MH::Assemble)
        MH::Assemble.dashboard if defined?(MH::Assemble) && MH::Assemble.respond_to?(:dashboard)
      end
      Menu.add(app: 'PK Addon', key: 'show', label: 'Mở bảng tạo PK') do
        load_app_file('MH_PK_Addon', 'main.rb') unless defined?(MH_PK_Addon)
        MH_PK_Addon.show_dialog if defined?(MH_PK_Addon) && MH_PK_Addon.respond_to?(:show_dialog)
      end
      Menu.add(app: 'PK Addon', key: 'settings', label: 'Setting') do
        load_app_file('MH_PK_Addon', 'main.rb') unless defined?(MH_PK_Addon)
        MH_PK_Addon.show_settings_input if defined?(MH_PK_Addon) && MH_PK_Addon.respond_to?(:show_settings_input)
      end
      Menu.add(app: 'PK Addon', key: 'fix_lost_abf', label: 'Fix PK mất thống kê ABF') do
        load_app_file('MH_PK_Addon', 'main.rb') unless defined?(MH_PK_Addon)
        if defined?(MH_PK_Addon) && MH_PK_Addon.respond_to?(:fix_lost_abf_statistics)
          count = MH_PK_Addon.fix_lost_abf_statistics
          UI.messagebox("Da fix #{count} PK bi mat thong ke ABF.")
        end
      end
      Menu.add(app: 'PK Addon', key: 'exclude_nesting', label: 'Bỏ nesting PK đang chọn') do
        load_app_file('MH_PK_Addon', 'main.rb') unless defined?(MH_PK_Addon)
        if defined?(MH_PK_Addon) && MH_PK_Addon.respond_to?(:exclude_selected_accessories_from_nesting)
          count = MH_PK_Addon.exclude_selected_accessories_from_nesting
          UI.messagebox("Da bo nesting cho #{count} phu kien dang chon.")
        end
      end
      Menu.add(app: 'PK Addon', key: 'quick_add', label: 'Thêm nhanh PK') do
        load_app_file('MH_PK_Addon', 'main.rb') unless defined?(MH_PK_Addon)
        MH_PK_Addon.quick_add if defined?(MH_PK_Addon) && MH_PK_Addon.respond_to?(:quick_add)
      end

      Menu.add(app: 'Superimp', key: 'manager', label: 'Quản lý danh sách') do
        load_app_file('MH_Superimp', 'src', 'main.rb') unless defined?(MH::Superimp)
        MH::Superimp.show_config_dialog if defined?(MH::Superimp)
      end
      Menu.add(app: 'Superimp', key: 'reload', label: 'Reload xlsx') do
        load_app_file('MH_Superimp', 'src', 'main.rb') unless defined?(MH::Superimp)
        if defined?(MH::Superimp)
          MH::Superimp.reload_import_list
          UI.messagebox("Đã reload #{MH::Superimp.import_list.length} items!")
        end
      end
    end

    # ---- Bridge callbacks --------------------------------------------------

    def attach_callbacks(dlg)
      attach_registry_callbacks(dlg)
      attach_config_callbacks(dlg)
      attach_mvl_callbacks(dlg)
      attach_connector_callbacks(dlg)
    end

    # -- Registry (global/project JSON) --
    def attach_registry_callbacks(dlg)
      dlg.on('get_data') do |deferred|
        deferred.resolve(bootstrap_data)
      end

      dlg.on('save_global') do |deferred, data|
        MH::Registry.save_global!(symbolize_safe(data))
        deferred.resolve({ 'ok' => true })
      end

      dlg.on('save_project') do |deferred, data|
        MH::Registry.save_project!(symbolize_safe(data))
        deferred.resolve({ 'ok' => true, 'path' => MH::Registry.project_path })
      end

      dlg.on('merge_dc_thickness_options_to_config') do |deferred, data|
        begin
          result = merge_dc_thickness_options_to_config(symbolize_safe(data))
          deferred.resolve(result)
        rescue => e
          deferred.resolve({ 'ok' => false, 'error' => e.message })
        end
      end

      dlg.on('import_xlsx') do |deferred|
        path = UI.openpanel('Chọn file Excel (.xlsx)', '', 'Excel|*.xlsx||')
        if path.nil?
          deferred.resolve({ 'ok' => false, 'cancelled' => true })
        else
          begin
            sheets = MH::ExcelBridge.read_all(path)
            deferred.resolve({ 'ok' => true, 'path' => path, 'sheets' => sheets })
          rescue => e
            deferred.resolve({ 'ok' => false, 'error' => e.message })
          end
        end
      end

      dlg.on('export_xlsx') do |deferred, payload|
        default_name = (payload['filename'] || 'MH_Registry_export.xlsx').to_s
        path = UI.savepanel('Lưu file Excel', '', default_name)
        if path.nil?
          deferred.resolve({ 'ok' => false, 'cancelled' => true })
        else
          path += '.xlsx' unless path.downcase.end_with?('.xlsx')
          begin
            MH::ExcelBridge.write(path, sheets: payload['sheets'] || {})
            deferred.resolve({ 'ok' => true, 'path' => path })
          rescue => e
            deferred.resolve({ 'ok' => false, 'error' => e.message })
          end
        end
      end

      dlg.on('scan_model_products') do |deferred|
        deferred.resolve({ 'ok' => true, 'codes' => scan_model_sp_codes })
      end
    end

    # -- Config.xlsx (naming + mapping) --
    def attach_config_callbacks(dlg)
      dlg.on('load_config') do |deferred|
        data = load_config
        deferred.resolve({ 'ok' => true, 'data' => data, 'path' => config_path })
      end

      dlg.on('save_config') do |deferred, data|
        begin
          save_config(symbolize_safe(data))
          proj = MH::Registry.project
          # Product-code structure now lives in global product_code_rules.
          # Keep legacy project suggestions empty so older prefix/module lists
          # cannot shadow the rule edited in Control Panel.
          proj['sub_prefix_suggestions'] = []
          proj['prefix_suggestions']     = []
          proj['suffix_suggestions']     = data['suffix'] || []
          proj['modul_suggestions']      = []
          proj['name_separators']        = data['separators'] || {}
          proj.delete('ma_vat_lieu_project')
          proj.delete('ma_vat_lieu_rules')
          MH::Registry.save_project!(proj)
          Connector.notify_config_changed(load_config)
          refresh_superimp_material_runtime
          deferred.resolve({ 'ok' => true, 'path' => config_path })
        rescue => e
          deferred.resolve({ 'ok' => false, 'error' => e.message })
        end
      end

      dlg.on('open_config_folder') do |deferred|
        path = config_path
        create_default_config unless File.exist?(path)
        UI.openURL("file:///#{File.dirname(path).tr('\\', '/')}")
        deferred.resolve({ 'ok' => true })
      end
    end

    # -- Tổng hợp: chọn file, đánh dấu SP, tạo mã vật liệu --
    def attach_mvl_callbacks(dlg)
      dlg.on('get_mvl_input_path') do |deferred|
        path = last_mvl_input_path
        deferred.resolve({
          'ok' => !path.empty?,
          'path' => path,
          'exists' => !path.empty? && File.exist?(path)
        })
      end

      dlg.on('choose_mvl_input') do |deferred|
        path = UI.openpanel('Chọn file Excel thống kê', '', 'Excel|*.xlsx;*.xlsm||')
        if path
          remember_mvl_input_path(path)
          deferred.resolve({ 'ok' => true, 'path' => path })
        else
          deferred.resolve({ 'ok' => false, 'cancelled' => true })
        end
      end

      dlg.on('list_sp_codes') do |deferred, input_path|
        input_path = resolve_mvl_input_path(input_path)

        begin
          source = mark_product_codes_source(input_path)
          if Array(source['codes']).empty?
            deferred.resolve({ 'ok' => false, 'error' => 'Khong tim thay ma SP trong Excel du an hoac file thong ke.', 'codes' => [], 'source' => source['source'], 'path' => source['path'] })
            next
          end
          deferred.resolve({
            'ok' => true,
            'codes' => source['codes'],
            'path' => source['path'],
            'source' => source['source']
          })
        rescue => e
          deferred.resolve({ 'ok' => false, 'error' => e.message, 'codes' => [] })
        end
      end

      # Đánh dấu sản phẩm — đọc Excel lấy mã SP → tạo CURIC::Text objects
      dlg.on('mark_products') do |deferred, payload|
        params = payload.is_a?(Hash) ? payload : { 'input' => payload }
        input_path = params['input'] || params[:input]
        input_path = resolve_mvl_input_path(input_path)

        begin
          start_param = params['start'] || params[:start]
          end_param = params['end'] || params[:end]

          # Uu tien: go tay so Dau-Cuoi -> tu sinh ma SP (khong can Excel).
          sp_codes = expand_sp_code_range(start_param, end_param)
          source_label = 'range'
          source_path = ''

          # Fallback tuong thich nguoc: start/end khong phai so -> cat tren
          # danh sach ma SP doc tu Excel/du an.
          if sp_codes.empty?
            remember_mvl_input_path(input_path) if !input_path.to_s.empty? && File.exist?(input_path.to_s)
            source = mark_product_codes_source(input_path)
            sp_codes = slice_sp_codes(source['codes'], start_param, end_param)
            source_label = source['source']
            source_path = source['path']
          end

          # Ghep prefix nguyen van vao truoc moi ma (vd 'A-' -> 'A-SP05').
          prefix = (params['prefix'] || params[:prefix]).to_s
          sp_codes = sp_codes.map { |code| "#{prefix}#{code}" } unless prefix.empty?

          spacing_mm = (params['spacing'] || params[:spacing]).to_f
          spacing_mm = 5000.0 if spacing_mm <= 0

          if sp_codes.empty?
            deferred.resolve({ 'ok' => false, 'error' => 'Khong sinh duoc ma SP (kiem tra so Dau-Cuoi).' })
            next
          end

          # Tạo CURIC::Text objects trong SketchUp
          unless defined?(CURIC::Text) && CURIC::Text.respond_to?(:place)
            deferred.resolve({ 'ok' => false, 'error' => 'CURIC Text chua duoc cai dat.' })
            next
          end

          # Resolve trước để UI không bị block
          count = sp_codes.length
          deferred.resolve({
            'ok' => true,
            'count' => count,
            'codes' => sp_codes,
            'spacing' => spacing_mm,
            'source' => source_label,
            'path' => source_path
          })

          # Tạo objects sau khi dialog callback xong
          UI.start_timer(0.1) do
            begin
              model = Sketchup.active_model
              model.start_operation("Mark SP (#{count})", true)
              opts = CURIC::Text.default_text_options.dup
              opts[:size] = 19.68503937007874
              opts[:border] = true
              opts[:border_type] = "Rounded Rectangle"
              opts[:border_radius] = 11.811023622047244
              opts[:border_padding] = 0.1
              opts[:align] = 1
              opts[:vertical_align] = 1

              sp_codes.each_with_index do |code, i|
                opts[:position] = Geom::Point3d.new((1000 + spacing_mm * i).mm, -1000.mm, 0)
                CURIC::Text.place(model.active_entities, code, **opts)
              end
              model.commit_operation
            rescue => e
              model.abort_operation rescue nil
              dbg("[MH_Registry] mark_products error: #{e.message}")
            end
          end
        rescue => e
          deferred.resolve({ 'ok' => false, 'error' => e.message })
        end
      end

      # Đánh dấu tự động — lấy nguyên danh sách mã SP theo thứ tự trong JSON dự án.
      dlg.on('mark_products_auto') do |deferred, payload|
        params = payload.is_a?(Hash) ? payload : { 'input' => payload }
        input_path = resolve_mvl_input_path(params['input'] || params[:input])

        begin
          source = project_json_product_codes_source(input_path)
          sp_codes = Array(source['codes'])
          if sp_codes.empty?
            deferred.resolve({
              'ok' => false,
              'error' => 'Khong tim thay ma SP trong file JSON cua du an.',
              'path' => source['path']
            })
            next
          end

          unless defined?(CURIC::Text) && CURIC::Text.respond_to?(:place)
            deferred.resolve({ 'ok' => false, 'error' => 'CURIC Text chua duoc cai dat.' })
            next
          end

          spacing_mm = (params['spacing'] || params[:spacing]).to_f
          spacing_mm = 5000.0 if spacing_mm <= 0
          count = sp_codes.length

          deferred.resolve({
            'ok' => true,
            'count' => count,
            'codes' => sp_codes,
            'spacing' => spacing_mm,
            'source' => 'project_json',
            'path' => source['path']
          })

          UI.start_timer(0.1) do
            begin
              model = Sketchup.active_model
              model.start_operation("Mark SP Auto (#{count})", true)
              opts = CURIC::Text.default_text_options.dup
              opts[:size] = 19.68503937007874
              opts[:border] = true
              opts[:border_type] = "Rounded Rectangle"
              opts[:border_radius] = 11.811023622047244
              opts[:border_padding] = 0.1
              opts[:align] = 1
              opts[:vertical_align] = 1

              sp_codes.each_with_index do |code, i|
                opts[:position] = Geom::Point3d.new((1000 + spacing_mm * i).mm, -1000.mm, 0)
                CURIC::Text.place(model.active_entities, code, **opts)
              end
              model.commit_operation
            rescue => e
              model.abort_operation rescue nil
              dbg("[MH_Registry] mark_products_auto error: #{e.message}")
            end
          end
        rescue => e
          deferred.resolve({ 'ok' => false, 'error' => e.message })
        end
      end

      dlg.on('run_mvl') do |deferred, payload|
        deferred.resolve(run_mvl_pipeline(payload))
      rescue => e
        deferred.resolve({ 'ok' => false, 'error' => e.message })
      end

      dlg.on('reload_mvl_excel') do |deferred, payload|
        deferred.resolve(reload_mvl_excel_pipeline(payload))
      rescue => e
        deferred.resolve({ 'ok' => false, 'error' => e.message })
      end

      dlg.on('open_mvl_output') do |deferred, path|
        if path && File.exist?(path)
          UI.openURL("file:///#{path.tr('\\', '/')}")
          deferred.resolve({ 'ok' => true })
        else
          deferred.resolve({ 'ok' => false, 'error' => 'File khong ton tai.' })
        end
      end
    end

    # -- Connector callbacks (Material Assign, etc.) --
    def attach_connector_callbacks(dlg)
      dlg.on('load_into_material_assign') do |deferred, file_path|
        result = Connector.dispatch('material_assign', :load_data, file_path)
        deferred.resolve(result || { 'ok' => false, 'error' => 'Connector khong kha dung' })
      end

      dlg.on('assign_material_selection') do |deferred|
        result = Connector.dispatch('material_assign', :assign_selection)
        deferred.resolve(result || { 'ok' => false, 'error' => 'Connector khong kha dung' })
      end

      dlg.on('assign_material_all') do |deferred|
        result = Connector.dispatch('material_assign', :assign_all)
        deferred.resolve(result || { 'ok' => false, 'error' => 'Connector khong kha dung' })
      end

      # Rename connector
      dlg.on('reload_rename_config') do |deferred|
        result = Connector.dispatch('rename', :reload)
        config = Connector.dispatch('rename', :current_config)
        deferred.resolve({ 'ok' => !!result, 'config' => config })
      end

      dlg.on('connector_status') do |deferred|
        status = {}
        Connector.all.each do |name, c|
          status[name] = {
            'available' => (c.respond_to?(:available?) ? c.available? : true),
            'data_count' => (c.respond_to?(:data_count) ? c.data_count : nil)
          }
        end
        deferred.resolve({ 'ok' => true, 'connectors' => status })
      end

      dlg.on('material_profile_names') do |deferred|
        names = registry_material_names
        source = 'registry'
        if names.empty?
          names = Array(Connector.dispatch('material_assign', :material_names))
          source = 'material_assign'
        end
        if names.empty?
          names = Array(Connector.dispatch('thongke', :material_names))
          source = 'thongke'
        end
        deferred.resolve({ 'ok' => true, 'source' => source, 'names' => names })
      end

      # Danh sách LOẠI vật liệu trong dự án (qua type_key) — cho bảng độ dày DC tự sinh.
      dlg.on('dc_thickness_types') do |deferred|
        begin
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = config_material_types_preview
          if result.is_a?(Hash) && result['ok'] == false
            deferred.resolve({ 'ok' => false, 'error' => result['error'].to_s })
          else
            types = Array(result['types'] || result[:types] || result)
            elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
            deferred.resolve({
              'ok' => true,
              'types' => types,
              'duration_ms' => elapsed,
              'source' => result['source'] || result[:source],
              'parse_count' => result['parse_count'] || result[:parse_count]
            })
          end
        rescue => e
          deferred.resolve({ 'ok' => false, 'error' => "#{e.class}: #{e.message}" })
        end
      end

      # Đọc dynamic_attributes của DC đang chọn — cho helper "Học tham số".
      dlg.on('dc_dynamic_attrs') do |deferred|
        result = Connector.dispatch('dc_import_pipeline', :dynamic_attrs_for_selection)
        deferred.resolve(result || { 'ok' => false, 'error' => 'Pipeline không khả dụng.' })
      end
    end

    # ---- Helpers -----------------------------------------------------------

    def merge_dc_thickness_options_to_config(data)
      config = load_config
      incoming = Array(data['dc_thickness_options'] || data[:dc_thickness_options] ||
                       data['dc_thickness_options_project'] || data[:dc_thickness_options_project])
      incoming = Array(data['rows'] || data[:rows]) if incoming.empty?
      incoming = incoming.select { |row| row.is_a?(Hash) && !row['material_type'].to_s.strip.empty? }
      replace_project = data.key?('dc_thickness_options') || data.key?(:dc_thickness_options) ||
                        data.key?('dc_thickness_options_project') || data.key?(:dc_thickness_options_project) ||
                        data.key?('rows') || data.key?(:rows)

      library_rows = Array(config['dc_thickness_options_library'])
      library_keys = {}
      library_rows.each do |row|
        key = row['material_type'].to_s.strip.upcase
        library_keys[key] = true unless key.empty?
      end

      current = replace_project ? [] : Array(config['dc_thickness_options_project'])
      by_key = {}
      current.each_with_index do |row, index|
        key = row['material_type'].to_s.strip.upcase
        by_key[key] = index unless key.empty?
      end
      added = []
      updated = []
      skipped_library = []
      unchanged = 0

      incoming.each do |row|
        type = row['material_type'].to_s.strip
        key = type.upcase
        if library_keys[key]
          skipped_library << type
          next
        end

        normalized = {
          'material_type' => type,
          'options' => normalize_thickness_options(row['options'])
        }

        if by_key.key?(key)
          index = by_key[key]
          if normalize_thickness_options(current[index]['options']) == normalized['options']
            unchanged += 1
          else
            current[index] = normalized
            updated << type
          end
        else
          current << normalized
          by_key[key] = current.length - 1
          added << type
        end
      end

      config['dc_thickness_options_project'] = current
      config['dc_thickness_options'] = merge_thickness_options(library_rows, current)

      incoming_manual = data['dc_manual_materials'] || data[:dc_manual_materials]
      manual_merge = nil
      if incoming_manual.nil?
        manual_merge = overwrite_manual_materials_from_thickness_options(config['dc_manual_materials'], config['dc_thickness_options'])
        config['dc_manual_materials'] = manual_merge['rows']
      else
        manual_rows = filter_manual_material_rows_by_thickness_options(incoming_manual, config['dc_thickness_options'])
        manual_merge = { 'rows' => manual_rows, 'added' => 0 }
        config['dc_manual_materials'] = manual_merge['rows']
      end

      incoming_bindings = data['dc_thickness_bindings'] || data[:dc_thickness_bindings]
      unless incoming_bindings.nil?
        config['dc_thickness_bindings'] = Array(incoming_bindings).select do |row|
          row.is_a?(Hash) && !(row['match'] || row[:match]).to_s.strip.empty?
        end
      end
      save_config(config)
      Connector.notify_config_changed(config)
      refresh_superimp_material_runtime

      {
        'ok' => true,
        'added' => added.length,
        'updated' => updated.length,
        'unchanged' => unchanged,
        'skipped_library' => skipped_library.length,
        'bindings' => Array(config['dc_thickness_bindings']).length,
        'manual_overwritten' => false,
        'manual_added' => manual_merge['added'].to_i,
        'manual_total' => manual_merge['rows'].length,
        'added_types' => added,
        'updated_types' => updated,
        'skipped_library_types' => skipped_library,
        'path' => config_path
      }
    end

    def refresh_superimp_material_runtime
      unless defined?(MH::Superimp)
        load_app_file('MH_Superimp', 'src', 'main.rb') rescue nil
      end
      return false unless defined?(MH::Superimp)

      MH::Superimp.reload_import_list if MH::Superimp.respond_to?(:reload_import_list)
      MH::Superimp.sync_registry_menu! if MH::Superimp.respond_to?(:sync_registry_menu!)
      MH::Superimp.refresh_material_runtime if MH::Superimp.respond_to?(:refresh_material_runtime)
      Sketchup.active_model.active_view.invalidate if Sketchup.active_model
      true
    rescue => e
      dbg("[MH_Registry] refresh Superimp HUD error: #{e.class}: #{e.message}")
      false
    end

    def reload_registry_excel_runtime
      data = load_config(force_excel: true)
      Connector.notify_config_changed(data)
      refresh_superimp_material_runtime
      data
    end

    def excel_material_types_preview(input_path = nil)
      path = resolve_mvl_input_path(input_path.to_s)
      return { 'ok' => false, 'error' => 'Chưa chọn file Excel thống kê.' } if path.empty?
      return { 'ok' => false, 'error' => "Không tìm thấy file Excel: #{path}" } unless File.exist?(path)

      result = material_types_from_excel_file(path)
      if result['parse_count'].to_i <= 0
        return {
          'ok' => false,
          'error' => "Excel parse được 0 dòng vật liệu. Không cập nhật list. File: #{File.basename(path)}",
          'path' => path,
          'parse_count' => 0
        }
      end

      result.merge('ok' => true, 'source' => 'xlsx', 'path' => path)
    rescue => e
      { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
    end

    def config_material_types_preview
      data = load_config
      types = material_types_from_config(data)
      {
        'ok' => true,
        'types' => types,
        'source' => 'config',
        'parse_count' => types.length,
        'path' => superimp_library_path
      }
    rescue => e
      { 'ok' => false, 'error' => "#{e.class}: #{e.message}" }
    end

    def material_types_from_config(data)
      types = []
      add_type = lambda do |value|
        split_material_codes(value).each do |code|
          type = registry_material_code_without_thickness(code)
          next if type.empty?
          types << type unless types.include?(type)
        end
      end

      Array(data['dc_manual_materials']).each do |row|
        add_type.call(row['material_code'] || row[:material_code]) if row.is_a?(Hash)
      end
      Array(data['dc_material_options']).each do |row|
        add_type.call(row['material_code'] || row[:material_code]) if row.is_a?(Hash)
      end
      Array(data['material_profile_choices']).each do |row|
        add_type.call(row['material_name'] || row[:material_name]) if row.is_a?(Hash)
      end
      Array(data['dc_thickness_options']).each do |row|
        add_type.call(row['material_type'] || row[:material_type]) if row.is_a?(Hash)
      end

      types.sort
    end

    def material_types_from_excel_file(path)
      sheets = MH::ExcelBridge.read_all(path)
      rows_with_material = 0
      types = []

      sheets.each do |_sheet_name, rows|
        header_index, headers = detect_material_excel_header(rows)
        next if header_index.nil?

        Array(rows).drop(header_index + 1).each do |row|
          material = material_code_from_excel_row(row, headers)
          next if material.empty?

          rows_with_material += 1
          split_material_codes(material).each do |code|
            type = registry_material_code_without_thickness(code)
            types << type unless type.empty? || types.include?(type)
          end
        end
      end

      { 'types' => types.sort, 'parse_count' => rows_with_material }
    end

    def detect_material_excel_header(rows)
      Array(rows).first(30).each_with_index do |row, index|
        headers = {}
        Array(row).each_with_index do |value, col_index|
          normalized = normalize_excel_header(value)
          next if normalized.empty?

          headers['material'] ||= col_index if material_header?(normalized)
          headers['detail'] ||= col_index if detail_header?(normalized)
          headers['product'] ||= col_index if product_header?(normalized)
        end
        return [index, headers] if headers['material'] || headers['detail'] || headers['product']
      end
      nil
    end

    def material_code_from_excel_row(row, headers)
      material_index = headers && headers['material']
      value = Array(row)[material_index].to_s.strip if material_index
      value = Array(row)[10].to_s.strip if value.to_s.empty?
      value.to_s.strip
    end

    def split_material_codes(value)
      if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:split)
        return MH::MaterialCode.split(value)
      end

      value.to_s.split(/\s*&\s*/).map(&:strip).reject(&:empty?)
    end

    def normalize_excel_header(value)
      value.to_s.strip.downcase
           .tr('àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ',
               'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd')
           .gsub(/\s+/, ' ')
    end

    def material_header?(text)
      ['ma vat lieu', 'ma vl', 'mavl', 'material code', 'material', 'vl'].include?(text)
    end

    def detail_header?(text)
      text.include?('ten chi tiet') || text.include?('quy cach vat lieu') || text == 'detail'
    end

    def product_header?(text)
      ['ma sp', 'ma san pham', 'masp', 'product code', 'sp'].include?(text)
    end

    def overwrite_manual_materials_from_thickness_options(manual_rows, thickness_rows)
      codes = Array(thickness_rows).filter_map do |row|
        next unless row.is_a?(Hash)

        (row['material_type'] || row[:material_type] ||
         row['material_code'] || row[:material_code]).to_s.strip
      end
      overwrite_manual_materials_from_codes(manual_rows, codes)
    end

    def overwrite_manual_materials_from_codes(manual_rows, material_codes)
      order_by_key = {}
      enabled_by_key = {}
      Array(manual_rows).each do |row|
        next unless row.is_a?(Hash)

        code = (row['material_code'] || row[:material_code] ||
                row['material_type'] || row[:material_type]).to_s.strip
        next if code.empty?

        key = code.upcase
        raw_order = row['sort_order'] || row[:sort_order] || row['order'] || row[:order] ||
                    row['thu_tu'] || row[:thu_tu]
        order_by_key[key] = numeric_manual_sort_order(raw_order)
        enabled_by_key[key] = (row.key?('enabled') ? row['enabled'] : row[:enabled]).to_s
      end

      rows = []
      seen = {}
      Array(material_codes).each do |value|
        code = value.to_s.strip
        next if code.empty?

        key = code.upcase
        next if seen[key]

        rows << {
          'enabled' => enabled_by_key.key?(key) ? enabled_by_key[key].to_s : '1',
          'material_code' => code,
          'sort_order' => order_by_key.fetch(key, '')
        }
        seen[key] = true
      end

      { 'rows' => rows, 'added' => [rows.length - order_by_key.length, 0].max }
    end
    alias merge_manual_materials_from_thickness_options overwrite_manual_materials_from_thickness_options

    def normalize_manual_material_rows(rows)
      seen = {}
      Array(rows).filter_map do |row|
        next unless row.is_a?(Hash)

        code = (row['material_code'] || row[:material_code] ||
                row['material_type'] || row[:material_type]).to_s.strip
        next if code.empty?

        key = code.upcase
        next if seen[key]

        enabled = if row.key?('enabled')
                    row['enabled']
                  elsif row.key?(:enabled)
                    row[:enabled]
                  else
                    '1'
                  end
        seen[key] = true
        {
          'enabled' => enabled.to_s.strip.empty? ? '1' : enabled.to_s.strip,
          'material_code' => code,
          'sort_order' => numeric_manual_sort_order(
            row['sort_order'] || row[:sort_order] || row['order'] || row[:order] ||
              row['thu_tu'] || row[:thu_tu]
          )
        }
      end
    end

    def filter_manual_material_rows_by_thickness_options(manual_rows, thickness_rows)
      valid = {}
      Array(thickness_rows).each do |row|
        next unless row.is_a?(Hash)

        code = (row['material_type'] || row[:material_type] ||
                row['material_code'] || row[:material_code]).to_s.strip.upcase
        valid[code] = true unless code.empty?
      end

      normalize_manual_material_rows(manual_rows).select do |row|
        valid[row['material_code'].to_s.strip.upcase]
      end
    end

    def numeric_manual_sort_order(value)
      text = value.to_s.strip
      return '' if text.empty?

      number = Float(text)
      number.finite? ? number : ''
    rescue ArgumentError, TypeError
      ''
    end

    def merge_manual_material_rows(current_rows, incoming_rows)
      rows = []
      index_by_key = {}

      normalize_manual_material_rows(current_rows).each do |row|
        key = row['material_code'].to_s.strip.upcase
        next if key.empty? || index_by_key.key?(key)

        index_by_key[key] = rows.length
        rows << row
      end

      added = 0
      normalize_manual_material_rows(incoming_rows).each do |incoming|
        key = incoming['material_code'].to_s.strip.upcase
        next if key.empty?

        if index_by_key.key?(key)
          rows[index_by_key[key]] = rows[index_by_key[key]].merge(incoming)
        else
          index_by_key[key] = rows.length
          rows << incoming
          added += 1
        end
      end

      { 'rows' => rows, 'added' => added }
    end

    def normalize_thickness_options(options)
      Array(options).map do |opt|
        next nil unless opt.is_a?(Hash)
        panel = opt['panel'].to_s.strip
        back = opt['back'].to_s.strip
        next nil if panel.empty? && back.empty?
        { 'panel' => panel, 'back' => back }
      end.compact
    end

    def registry_material_names
      rows = begin
        MH::Registry.global['materials']
      rescue
        []
      end
      Array(rows).filter_map do |row|
        next row.to_s.strip unless row.is_a?(Hash)

        name = row['name'].to_s.strip
        code = row['code'].to_s.strip
        registry_material_code_without_thickness(name.empty? ? code : name)
      end.reject(&:empty?).uniq
    end

    def registry_material_code_without_thickness(value)
      if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:without_thickness)
        return MH::MaterialCode.without_thickness(value)
      end

      parts = value.to_s.split('.').map(&:strip).reject(&:empty?)
      return '' if parts.empty?
      return parts.first if parts.length == 1

      if parts[1].to_s =~ /\A\d+(?:[,.]\d+)?\z/
        ([parts.first] + parts[2..-1]).join('.')
      else
        parts.join('.')
      end
    end

    def bootstrap_data
      model = (Sketchup.active_model rescue nil)
      mpath = (model && model.path).to_s
      mvl_input_path = last_mvl_input_path
      {
        'global'        => MH::Registry.global,
        'project'       => MH::Registry.project,
        'model_saved'   => !mpath.empty?,
        'model_name'    => mpath.empty? ? '(chưa lưu)' : File.basename(mpath),
        'project_path'  => MH::Registry.project_path,
        'mvl_input_path' => mvl_input_path,
        'mvl_input_exists' => !mvl_input_path.empty? && File.exist?(mvl_input_path),
        'module_templates' => MH::Registry.module_templates
      }
    end

    def remember_mvl_input_path(path)
      path = path.to_s.strip
      return '' if path.empty?

      begin
        # write_default lưu chuỗi rồi read_default EVAL lại → path Windows có
        # backslash (vd "D:\Cong viec\...") sẽ lỗi "Invalid escape character".
        # Lưu dạng forward-slash cho eval an toàn (Ruby/Windows đọc được như nhau).
        Sketchup.write_default(DEFAULTS_KEY, LAST_MVL_INPUT_KEY, path.tr('\\', '/'))
      rescue
      end

      # Cập nhật memo để last_mvl_input_path không phải eval lại read_default.
      @mvl_default_memo = path.tr('\\', '/')

      begin
        project = MH::Registry.project
        project['last_mvl_input_path'] = path
        MH::Registry.save_project!(project)
      rescue
      end

      path
    end

    def last_mvl_input_path
      project_path = begin
        MH::Registry.project['last_mvl_input_path'].to_s.strip
      rescue
        ''
      end

      # Project (JSON, không eval) đã nhớ path → ưu tiên, TRẢ LUÔN.
      # KHÔNG gọi read_default ở đây: read_default EVAL lại chuỗi đã lưu; nếu giá
      # trị cũ là path Windows backslash ("D:\Cong viec\...") thì raise SyntaxError
      # ("Invalid escape") — và hàm này bị gọi MỖI group khi đặt DC, nên mỗi lần
      # rơi xuống read_default là một exception (TracePoint bắt cả khi đã rescue)
      # → lag/noise. Heal default về forward-slash 1 lần rồi thôi.
      if !project_path.empty? && mvl_input_path_for_current_project?(project_path)
        Sketchup.write_default(DEFAULTS_KEY, LAST_MVL_INPUT_KEY, project_path.tr('\\', '/')) rescue nil
        @mvl_default_memo = project_path.tr('\\', '/')
        return project_path
      end

      # Project rỗng → đọc default. Memoize để chỉ đụng read_default 1 lần/session
      # (tối đa 1 raise nếu giá trị cũ còn backslash, sau đó dùng cache).
      mvl_input_default
    end

    # Đọc LAST_MVL_INPUT_KEY từ Sketchup defaults, memoized. read_default EVAL chuỗi
    # đã lưu nên giá trị backslash cũ raise SyntaxError; tự lành về '' và cache lại.
    def mvl_input_default
      if defined?(@mvl_default_memo) && @mvl_default_memo
        return mvl_input_path_for_current_project?(@mvl_default_memo) ? @mvl_default_memo : ''
      end

      @mvl_default_memo = begin
        Sketchup.read_default(DEFAULTS_KEY, LAST_MVL_INPUT_KEY).to_s.strip
      rescue Exception
        Sketchup.write_default(DEFAULTS_KEY, LAST_MVL_INPUT_KEY, '') rescue nil
        ''
      end
      @mvl_default_memo = '' unless mvl_input_path_for_current_project?(@mvl_default_memo)
      @mvl_default_memo
    end

    def mvl_input_path_for_current_project?(path)
      path = path.to_s.strip
      return true if path.empty?

      root = project_root rescue nil
      return true if root.to_s.strip.empty?

      full = File.expand_path(path).tr('\\', '/').downcase
      root_full = File.expand_path(root).tr('\\', '/').downcase
      in_project = full.start_with?(root_full + '/') || full == root_full
      in_project && mvl_input_path_matches_current_model?(path)
    rescue
      true
    end

    def mvl_input_path_matches_current_model?(path)
      model_path = (Sketchup.active_model.path rescue '').to_s
      model_token = File.basename(model_path).upcase[/[A-Z]{2}\d{6,}/].to_s
      return true if model_token.empty?

      path_token = File.basename(path.to_s).upcase[/[A-Z]{2}\d{6,}/].to_s
      path_token.empty? || path_token == model_token
    rescue
      true
    end

    def resolve_mvl_input_path(path)
      path = path.to_s.strip
      path.empty? ? last_mvl_input_path : path
    end

    def run_mvl_pipeline(payload = {})
      payload = payload.is_a?(Hash) ? payload : {}
      input_path = resolve_mvl_input_path(payload['input'])
      include_son = payload['include_son'] != false

      unless !input_path.empty? && File.exist?(input_path)
        return { 'ok' => false, 'error' => 'File input khong ton tai.' }
      end

      remember_mvl_input_path(input_path)
      if payload['config']
        config_payload = symbolize_safe(payload['config'])
        save_config(config_payload)
        dbg("[MH_Registry] Config auto-saved before run_mvl")
      end

      data = load_config
      mvl = data['ma_vat_lieu'] || []
      if mvl.empty?
        return { 'ok' => false, 'error' => 'Bang mapping ma vat lieu trong. Them du lieu truoc.' }
      end

      lib_rows = [['gia_tri', 'gia_tri_map', 'nhom', 'thu_tu']] + mvl.map { |r|
        [r['gia_tri'], r['gia_tri_map'], r['nhom'], r['thu_tu']]
      }
      temp_lib = File.join(PATH, '_temp_library.xlsx')
      safe_write_xlsx(temp_lib, { 'mapping' => lib_rows })

      if project_xlsx_path(input_path)
        ensure_spec_dirs
        output_path = project_xlsx_path(input_path)
      else
        output_path = File.join(File.dirname(input_path), File.basename(input_path))
      end

      py_script = File.join(Sketchup.find_support_file('Plugins'), 'MH_Thongke', 'tools', 'fill_sp', 'generate_output.py')
      son_flag = include_son ? '--include-son-code' : '--no-son-code'
      python_exe = find_python
      unless python_exe
        File.delete(temp_lib) if File.exist?(temp_lib)
        return { 'ok' => false, 'error' => 'Khong tim thay Python. Cai Python 3.' }
      end
      cmd = %("#{python_exe}" "#{py_script}" --input "#{input_path}" --output "#{output_path}" --library "#{temp_lib}" #{son_flag})

      result = `#{cmd} 2>&1`
      exit_code = $?.exitstatus
      File.delete(temp_lib) if File.exist?(temp_lib)

      unless exit_code == 0 || File.exist?(output_path)
        return { 'ok' => false, 'error' => "Python exit #{exit_code}", 'log' => result.to_s.strip }
      end

      json_path = project_json_path(input_path)
      if json_path
        ensure_spec_dirs
        export_xlsx_to_json(output_path, json_path)
        if defined?(MH::ProjectData) && File.exist?(json_path)
          MH::ProjectData.load_json(json_path, source_path: output_path, force: true, reason: 'registry_generate')
        end
      end

      project_data = nil
      if json_path && defined?(MH::ProjectData)
        project_data = MH::ProjectData.snapshot
        project_data = nil unless project_data && project_data[:ok]
      end

      thongke_payload = build_thongke_import_payload(output_path, project_thongke_import_json_path(input_path))
      # Sau khi generate_output.py ghi Ma_vat_lieu vào Excel, bắt buộc đọc lại
      # trực tiếp file .xlsx vừa sinh để MaterialAssign/HUD dùng dữ liệu mới,
      # không lấy lại ProjectData/cache cũ.
      ma_result = Connector.dispatch('material_assign', :force_reload_excel, output_path)
      thongke_result = if thongke_payload['ok'] && Array(thongke_payload['rows']).any?
        Connector.dispatch('thongke', :load_import_excel_payload, thongke_payload['rows'], output_path, true, {
          'json_path' => thongke_payload['json_path'],
          'fallback_to_xlsx' => false,
          'source' => 'registry_thongke_payload'
        })
      else
        {
          'ok' => false,
          'mode' => 'payload_error',
          'path' => output_path,
          'json_path' => thongke_payload['json_path'],
          'fallback_used' => false,
          'error' => thongke_payload['error'].to_s.empty? ? 'Thongke payload rows empty.' : thongke_payload['error']
        }
      end
      reload_registry_excel_runtime

      {
        'ok' => true,
        'output' => output_path,
        'json' => json_path,
        'project_data' => project_data ? {
          'ok' => true,
          'version' => project_data[:version],
          'rows_count' => project_data[:rows_count],
          'source_path' => project_data[:source_path],
          'json_path' => project_data[:json_path]
        } : nil,
        'thongke_payload' => thongke_payload.reject { |key, _| key == 'rows' },
        'log' => result.to_s.strip,
        'material_assign' => ma_result,
        'thongke' => thongke_result
      }
    rescue => e
      File.delete(temp_lib) if defined?(temp_lib) && File.exist?(temp_lib)
      { 'ok' => false, 'error' => e.message, 'backtrace' => e.backtrace }
    end

    def reload_mvl_excel_pipeline(payload = {})
      payload = payload.is_a?(Hash) ? payload : {}
      input_path = resolve_mvl_input_path(payload['input'] || payload[:input])
      output_path = (payload['output'] || payload[:output]).to_s.strip

      if output_path.empty? || !File.exist?(output_path)
        generated_path = project_xlsx_path(input_path) rescue nil
        output_path = generated_path.to_s if generated_path && File.exist?(generated_path)
      end
      output_path = input_path if output_path.empty?

      return { 'ok' => false, 'error' => 'Chua co file Excel de reload.' } if output_path.to_s.empty?
      return { 'ok' => false, 'error' => "File Excel khong ton tai: #{output_path}" } unless File.exist?(output_path)

      remember_mvl_input_path(input_path) if !input_path.to_s.empty? && File.exist?(input_path)

      json_path = project_json_path(input_path)
      if json_path
        ensure_spec_dirs
        export_xlsx_to_json(output_path, json_path)
        if defined?(MH::ProjectData) && File.exist?(json_path)
          MH::ProjectData.load_json(json_path, source_path: output_path, force: true, reason: 'registry_reload_excel')
        end
      end

      project_data = nil
      if json_path && defined?(MH::ProjectData)
        project_data = MH::ProjectData.snapshot
        project_data = nil unless project_data && project_data[:ok]
      end

      thongke_payload = build_thongke_import_payload(output_path, project_thongke_import_json_path(input_path))
      ma_result = Connector.dispatch('material_assign', :force_reload_excel, output_path)
      thongke_result = if thongke_payload['ok'] && Array(thongke_payload['rows']).any?
        Connector.dispatch('thongke', :load_import_excel_payload, thongke_payload['rows'], output_path, true, {
          'json_path' => thongke_payload['json_path'],
          'fallback_to_xlsx' => false,
          'source' => 'registry_reload_excel'
        })
      else
        {
          'ok' => false,
          'mode' => 'payload_error',
          'path' => output_path,
          'json_path' => thongke_payload['json_path'],
          'fallback_used' => false,
          'error' => thongke_payload['error'].to_s.empty? ? 'Thongke payload rows empty.' : thongke_payload['error']
        }
      end
      reload_registry_excel_runtime

      {
        'ok' => true,
        'path' => output_path,
        'json' => json_path,
        'project_data' => project_data ? {
          'ok' => true,
          'version' => project_data[:version],
          'rows_count' => project_data[:rows_count],
          'source_path' => project_data[:source_path],
          'json_path' => project_data[:json_path]
        } : nil,
        'thongke_payload' => thongke_payload.reject { |key, _| key == 'rows' },
        'material_assign' => ma_result,
        'thongke' => thongke_result
      }
    rescue => e
      { 'ok' => false, 'error' => e.message, 'backtrace' => e.backtrace }
    end

    def project_thongke_import_json_path(input_path = nil)
      raw_json = project_json_path(input_path)
      return nil if raw_json.to_s.empty?

      ext = File.extname(raw_json)
      base = ext.empty? ? raw_json : raw_json[0...-ext.length]
      "#{base}.thongke_import.json"
    rescue
      nil
    end

    def build_thongke_import_payload(xlsx_path, json_path = nil)
      xlsx_path = xlsx_path.to_s
      return { 'ok' => false, 'error' => 'Thongke source xlsx not found.', 'json_path' => json_path.to_s } unless File.exist?(xlsx_path)

      helper_exe = File.join(Sketchup.find_support_file('Plugins'), 'MH_Thongke', 'engine', 'dist', 'excel_helper.exe')
      return { 'ok' => false, 'error' => "Excel helper not found: #{helper_exe}", 'json_path' => json_path.to_s } unless File.exist?(helper_exe)

      temp_json = File.join(PATH, "_temp_thongke_payload_#{Time.now.to_i}_#{rand(1_000_000)}.json")
      system(helper_exe, xlsx_path, temp_json)
      return { 'ok' => false, 'error' => 'Excel helper failed to generate Thongke payload JSON.', 'json_path' => json_path.to_s } unless File.exist?(temp_json)

      rows = JSON.parse(File.read(temp_json, encoding: 'UTF-8'))
      rows = [] unless rows.is_a?(Array)
      if json_path && !json_path.to_s.empty?
        FileUtils.mkdir_p(File.dirname(json_path)) rescue nil
        File.write(json_path, JSON.pretty_generate(rows))
      end
      {
        'ok' => !rows.empty?,
        'rows' => rows,
        'rows_count' => rows.length,
        'json_path' => json_path.to_s,
        'source_path' => xlsx_path,
        'source' => 'registry_excel_helper'
      }
    rescue => e
      { 'ok' => false, 'error' => e.message, 'json_path' => json_path.to_s, 'source_path' => xlsx_path }
    ensure
      File.delete(temp_json) if defined?(temp_json) && File.exist?(temp_json)
    end

    def scan_model_sp_codes
      model = (Sketchup.active_model rescue nil)
      return [] unless model
      codes = {}
      collect = lambda do |entities|
        entities.each do |e|
          next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
          nm = (e.name.to_s + ' ' + (e.respond_to?(:definition) ? e.definition.name.to_s : ''))
          products = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:scan_products)
            MH::NameGrammar.scan_products(nm)
          else
            nm.scan(/[A-Z]+\d+[A-Z]?(?:\.\d+)?/i)
          end
          products.each do |m|
            base = defined?(MH::ProductContext) ? MH::ProductContext.base(m) : m.to_s.upcase.split('.').first
            codes[base] = true unless base.to_s.empty?
          end
        end
      end
      collect.call(model.active_entities)
      sort_sp_codes(codes.keys)
    end

    def symbolize_safe(data)
      data.is_a?(Hash) ? data : {}
    end

    def mark_product_codes_source(input_path = nil)
      project_source = project_data_sp_codes(input_path)
      return project_source if Array(project_source['codes']).any?

      thongke_source = thongke_import_sp_codes
      return thongke_source if Array(thongke_source['codes']).any?

      spec_path = project_xlsx_path(input_path) rescue nil
      spec_path = spec_path.to_s
      if !spec_path.empty? && File.exist?(spec_path)
        codes = extract_sp_codes_from_xlsx(spec_path)
        return { 'codes' => codes, 'source' => 'project_xlsx', 'path' => spec_path } if codes.any?
      end

      raw_path = resolve_mvl_input_path(input_path.to_s)
      if !raw_path.empty? && File.exist?(raw_path)
        codes = extract_sp_codes_from_xlsx(raw_path)
        return { 'codes' => codes, 'source' => 'raw_excel', 'path' => raw_path }
      end

      { 'codes' => [], 'source' => 'none', 'path' => raw_path.to_s }
    end

    def project_data_sp_codes(input_path = nil)
      return { 'codes' => [], 'source' => 'project_data', 'path' => '' } unless defined?(MH::ProjectData)

      json_path = project_json_path(input_path) rescue nil
      xlsx_path = project_xlsx_path(input_path) rescue nil
      snap = if json_path && File.exist?(json_path)
               MH::ProjectData.ensure_loaded(json_path, source_path: xlsx_path)
             else
               MH::ProjectData.ensure_loaded
             end
      return { 'codes' => [], 'source' => 'project_data', 'path' => '' } unless snap && snap[:ok]

      codes = extract_sp_codes_from_hash_rows(snap[:rows])
      {
        'codes' => codes,
        'source' => 'project_data',
        'path' => snap[:source_path].to_s.empty? ? snap[:json_path].to_s : snap[:source_path].to_s
      }
    rescue
      { 'codes' => [], 'source' => 'project_data', 'path' => '' }
    end

    def project_json_product_codes_source(input_path = nil)
      json_path = project_json_path(input_path) rescue nil
      json_path = json_path.to_s

      if json_path.empty? || !File.exist?(json_path)
        snap = MH::ProjectData.snapshot if defined?(MH::ProjectData)
        remembered_path = snap && snap[:model_key].to_s == MH::ProjectData.current_model_key.to_s ? snap[:json_path].to_s : ''
        json_path = remembered_path if !remembered_path.empty? && File.exist?(remembered_path)
      end

      return { 'codes' => [], 'source' => 'project_json', 'path' => json_path } if json_path.empty? || !File.exist?(json_path)

      data = JSON.parse(File.read(json_path, encoding: 'UTF-8'))
      rows = data.is_a?(Array) ? data : []
      {
        'codes' => extract_sp_codes_from_hash_rows_in_order(rows),
        'source' => 'project_json',
        'path' => json_path
      }
    rescue => e
      { 'codes' => [], 'source' => 'project_json', 'path' => json_path.to_s, 'error' => e.message }
    end

    def extract_sp_codes_from_hash_rows_in_order(rows)
      seen = {}
      codes = []
      Array(rows).each do |row|
        next unless row.is_a?(Hash)
        code = if defined?(MH::ProjectData) && MH::ProjectData.respond_to?(:product_value)
                 normalized_row = row.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value }
                 MH::ProjectData.product_value(normalized_row)
               else
                 row['ma_sp'] || row[:ma_sp] || row['Ma_SP'] || row[:Ma_SP] || row['product'] || row[:product] || row['product_code'] || row[:product_code] || row['actual_product'] || row[:actual_product]
               end
        normalize_sp_code(code).each do |sp|
          next if seen[sp]
          seen[sp] = true
          codes << sp
        end
      end
      codes
    end

    def thongke_import_sp_codes
      return { 'codes' => [], 'source' => 'thongke_import', 'path' => '' } unless defined?(::MH_Thongke)

      codes = if ::MH_Thongke.respond_to?(:import_excel_product_codes)
                ::MH_Thongke.import_excel_product_codes('product')
              else
                []
              end
      path = if ::MH_Thongke.respond_to?(:import_excel_loaded_path)
               ::MH_Thongke.import_excel_loaded_path.to_s
             elsif ::MH_Thongke.respond_to?(:import_excel_path)
               ::MH_Thongke.import_excel_path.to_s
             else
               ''
             end
      { 'codes' => sort_sp_codes(codes), 'source' => 'thongke_import', 'path' => path }
    rescue
      { 'codes' => [], 'source' => 'thongke_import', 'path' => '' }
    end

    def extract_sp_codes_from_xlsx(path)
      extract_sp_codes_from_sheets(MH::ExcelBridge.read_all(path))
    end

    def extract_sp_codes_from_sheets(sheets)
      return [] unless sheets.respond_to?(:values)

      codes = {}
      sheets.values.each do |rows|
        extract_sp_codes(rows).each { |code| codes[code] = true }
      end
      sort_sp_codes(codes.keys)
    end

    def extract_sp_codes_from_hash_rows(rows)
      codes = {}
      Array(rows).each do |row|
        next unless row.is_a?(Hash)
        if defined?(MH::ProjectData) && MH::ProjectData.respond_to?(:product_value)
          code = MH::ProjectData.product_value(row)
        else
          code = row['ma_sp'] || row[:ma_sp] || row['Ma_SP'] || row[:Ma_SP] || row['product'] || row[:product] || row['product_code'] || row[:product_code] || row['actual_product'] || row[:actual_product]
        end
        normalize_sp_code(code).each { |sp| codes[sp] = true }
      end
      sort_sp_codes(codes.keys)
    end

    def normalize_sp_code(value)
      products = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:scan_products)
        MH::NameGrammar.scan_products(value.to_s)
      else
        value.to_s.scan(/\b[A-Z]+\d+[A-Z]?(?:\.\d+)?\b/i)
      end
      products.map { |code| defined?(MH::ProductContext) ? MH::ProductContext.exact(code) : code.to_s.upcase }.uniq
    end

    def sort_sp_codes(codes)
      Array(codes).sort_by do |code|
        text = code.to_s.upcase
        match = text.match(/\A([A-Z]+)(\d+)([A-Z]?)(?:\.(\d+))?\z/)
        match ? [match[1], match[2].to_i, match[4].to_i, match[3].to_s, text] : ['ZZZ', 999_999, 0, '', text]
      end
    end

    # Đọc rows từ Excel, tìm mã sản phẩm unique theo NameGrammar/ProductContext.
    # Tìm trong tất cả cột để không phụ thuộc tên header của file thống kê.
    def extract_sp_codes(rows)
      return [] if rows.nil? || rows.length < 2
      codes = {}
      rows.drop(1).each do |row|
        next unless row.is_a?(Array)
        row.each do |cell|
          normalize_sp_code(cell).each { |sp| codes[sp] = true }
        end
      end
      sort_sp_codes(codes.keys)
    end

    # Sinh dai ma san pham truc tiep tu so Dau-Cuoi go tay,
    # khong phu thuoc danh sach Excel. Tra [] neu khong doc duoc so de caller
    # fallback sang slice_sp_codes tren danh sach co san.
    def expand_sp_code_range(start_value, end_value, max_count = 500)
      s = start_value.to_s[/\d+/]
      e = end_value.to_s[/\d+/]
      return [] if s.nil? || e.nil?

      s = s.to_i
      e = e.to_i
      s, e = e, s if s > e
      s = 1 if s < 1
      e = s + max_count - 1 if (e - s + 1) > max_count
      (s..e).map do |n|
        if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:format_code)
          MH::ProductContext.format_code(n)
        else
          prefix = (MH::NameGrammar.default_prefix rescue nil).to_s
          prefix = 'SP' if prefix.empty?
          format('%s%02d', prefix, n)
        end
      end
    end

    def slice_sp_codes(codes, start_code = nil, end_code = nil)
      list = Array(codes)
      return list if list.empty?

      start_text = start_code.to_s.strip.upcase
      end_text = end_code.to_s.strip.upcase
      start_index = start_text.empty? ? 0 : list.index { |code| code.to_s.upcase == start_text }
      end_index = end_text.empty? ? (list.length - 1) : list.index { |code| code.to_s.upcase == end_text }
      start_index ||= 0
      end_index ||= list.length - 1
      start_index, end_index = end_index, start_index if start_index > end_index
      list[start_index..end_index] || []
    end

    # ---- Menu & Toolbar (chỉ chạy 1 lần) ----------------------------------

    unless file_loaded?(__FILE__)
      register_default_menu

      tb = UI::Toolbar.new('MH Control Panel')
      cmd_cp = UI::Command.new('MH Control Panel') { ControlPanel.open }
      cmd_cp.tooltip = 'MH Control Panel'
      cmd_cp.status_bar_text = 'Mở bảng điều khiển hợp nhất tất cả app MH'
      cp_icon = File.join(PATH, 'control_panel', 'html', 'icons', 'control_panel.svg')
      if File.exist?(cp_icon)
        cmd_cp.small_icon = cp_icon
        cmd_cp.large_icon = cp_icon
      end
      tb.add_item(cmd_cp)
      tb.restore

      # Load tất cả connectors
      Connector.load_all
      ensure_runtime_ready

      # Mục menu mở Control Panel (đặt đầu menu MH).
      begin
        Menu.root.add_item('★ MH Control Panel') { ControlPanel.open }
      rescue => e
        dbg("[MH_Registry] add control panel menu error: #{e.message}")
      end

      file_loaded(__FILE__)
    end
  end
end
