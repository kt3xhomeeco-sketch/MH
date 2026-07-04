require 'sketchup.rb'
require 'extensions.rb'

module MH_Thongke
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('MH Thongke', 'MH_Thongke/main')
    ex.description = 'Công cụ thống kê vật tư, linh kiện, đo đạc LED cho sản xuất ABF.'
    ex.version     = '11.0.0'
    ex.copyright   = '2026'
    ex.creator     = 'MH'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end

