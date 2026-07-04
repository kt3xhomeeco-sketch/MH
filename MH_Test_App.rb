require 'sketchup.rb'

unless file_loaded?(__FILE__)
  # Thêm menu vào phần Extensions (Plugins)
  menu = UI.menu('Plugins').add_submenu('Test App Của Mình')
  
  menu.add_item('Bật ABF Master Tool V11') {
    # Lệnh load sẽ lấy code mới nhất từ ổ cứng mỗi lần click
    load 'c:/Users/mhngu/AppData/Roaming/SketchUp/SketchUp 2025/SketchUp/Plugins/vbo_sk_agent/bridge/command.rb'
  }

  file_loaded(__FILE__)
end
