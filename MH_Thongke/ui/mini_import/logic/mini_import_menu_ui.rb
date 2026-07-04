# encoding: utf-8
# MH_Thongke — mini import menu ui
# UI/render/dialog cho Mini Import. Không chứa logic xử lý thống kê lõi.
module MH_Thongke

  # === mini_import_menu.rb ===
  # --- mini_import_menu.rb ---
# MH_Thongke - Mini Import menu commands.


  def self.register_mini_import_menu
    return false unless defined?(MH::RegistryApp::Menu)

    unless @mini_import_menu_registered
      MH::RegistryApp::Menu.add(app: 'Thongke', key: 'mini_import_runtime', label: 'Mini Import') {
        MH_Thongke.reload_latest! if MH_Thongke.respond_to?(:reload_latest!)
        MH_Thongke.force_show_import_mini_dialog
      }
      @mini_import_menu_registered = true
    end

    unless @mini_import_reset_position_menu_registered
      MH::RegistryApp::Menu.add(app: 'Thongke', key: 'mini_import_reset_position', label: 'Reset Mini Import Position') {
        MH_Thongke.reload_latest! if MH_Thongke.respond_to?(:reload_latest!)
        MH_Thongke.reset_import_mini_dialog_position if MH_Thongke.respond_to?(:reset_import_mini_dialog_position)
        MH_Thongke.force_show_import_mini_dialog(nil, true)
      }
      @mini_import_reset_position_menu_registered = true
    end

    unless @mini_material_hud_menu_registered
      MH::RegistryApp::Menu.add(app: 'Thongke', key: 'material_hud', label: 'Material HUD') {
        MH_Thongke.reload_latest! if MH_Thongke.respond_to?(:reload_latest!)
        MH_Thongke.show_import_material_hud
      }
      @mini_material_hud_menu_registered = true
    end

    unless @mini_info_hud_menu_registered
      MH::RegistryApp::Menu.add(app: 'Thongke', key: 'info_hud', label: 'Info HUD') {
        MH_Thongke.toggle_info_hud if MH_Thongke.respond_to?(:toggle_info_hud)
      }
      @mini_info_hud_menu_registered = true
    end

    true
  end


end
