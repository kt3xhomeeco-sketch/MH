require 'sketchup.rb'
require 'extensions.rb'

module MH_PK_Addon
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('MH PK Addon', 'MH_PK_Addon/main')
    ex.description = 'Standalone tool to create and add accessory marker objects into selected SketchUp objects.'
    ex.version     = '1.0.0'
    ex.copyright   = '2026'
    ex.creator     = 'MH'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end

