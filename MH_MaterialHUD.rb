# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new('MH Material HUD', 'MH_MaterialHUD/main')
  extension.description = 'Material HUD độc lập: JSON dùng chung, Tab đổi View / Select.'
  extension.version = '1.0.0'
  extension.creator = 'MH'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
