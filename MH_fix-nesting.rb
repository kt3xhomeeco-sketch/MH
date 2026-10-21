require 'sketchup.rb'
require 'extensions.rb'

module MH_FixNesting
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('MH Fix Nesting', 'MH_fix-nesting/main')
    ex.description = 'Công cụ hỗ trợ thiết lập tag (Ring Tag) cho mặt cắt CNC Nesting'
    ex.version     = '1.0.0'
    ex.creator     = 'MH'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end
