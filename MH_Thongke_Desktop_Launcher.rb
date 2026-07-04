# encoding: UTF-8
require 'sketchup.rb'

module MH
  module ThongkeDesktopLauncher
    APP_DIR = File.expand_path(
      File.join(ENV.fetch('USERPROFILE', ''), 'Documents', 'MH_Apps', 'MH_Thongke_Desktop')
    ).freeze
    START_FILE = File.join(APP_DIR, 'start_desktop.bat').freeze

    module_function

    def open
      unless File.exist?(START_FILE)
        UI.messagebox("Khong tim thay MH Thongke Desktop:\n#{START_FILE}")
        return false
      end

      UI.openURL(START_FILE)
      true
    end

    unless file_loaded?(__FILE__)
      if defined?(MH::RegistryApp::Menu)
        MH::RegistryApp::Menu.add(app: 'Thongke', key: 'desktop_launcher', label: 'MH Thongke Desktop') { open }
      else
        UI.menu('Extensions').add_item('MH Thongke Desktop') { open }
      end
      file_loaded(__FILE__)
    end
  end
end
