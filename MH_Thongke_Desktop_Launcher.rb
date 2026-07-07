# encoding: UTF-8
require 'sketchup.rb'

module MH
  module ThongkeDesktopLauncher
    DEV_DIR = File.expand_path(
      File.join(ENV.fetch('USERPROFILE', ''), 'Documents', 'MH_Apps', 'MH_Thongke_Desktop')
    ).freeze
    INSTALLED_EXE = File.expand_path(
      File.join(ENV.fetch('LOCALAPPDATA', ''), 'Programs', 'MH Thongke Desktop', 'MH Thongke Desktop.exe')
    ).freeze

    module_function

    def launch_candidates
      custom = ENV.fetch('MH_THONGKE_DESKTOP_HOME', '').to_s.strip
      candidates = []
      unless custom.empty?
        root = File.expand_path(custom)
        candidates << File.join(root, 'MH Thongke Desktop.exe')
        candidates << File.join(root, 'start_desktop.bat')
      end
      candidates << INSTALLED_EXE
      candidates << File.join(DEV_DIR, 'start_desktop.bat')
      candidates.uniq
    end

    def launch_file
      launch_candidates.find { |candidate| File.file?(candidate) }
    end

    def open
      target = launch_file
      unless target
        UI.messagebox("Khong tim thay MH Thongke Desktop. Da kiem tra:\n#{launch_candidates.join("\n")}")
        return false
      end

      UI.openURL(target)
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
