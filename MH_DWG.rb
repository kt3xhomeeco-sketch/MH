# Loader for MH_DWG
require 'sketchup.rb'
require 'extensions.rb'

module MH
  module DWG
    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('MH DWG Clipboard Import', 'MH_DWG/main')
      ex.version     = '1.0.0'
      ex.description = 'Paste CAD (DWG) from clipboard with rotate placement.'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
