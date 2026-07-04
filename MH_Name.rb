# encoding: UTF-8
# MH_Name - Live Object Name Display Plugin for SketchUp
# Author: MH
# Version: 1.0

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Name
    EXT_VERSION = "1.0.0"
    EXT_NAME = "MH Name"
    EXT_DESCRIPTION = "Live display object names with leaders, x-ray view, inline editing"
    EXT_FILE = File.join('MH_Name', 'main')

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(EXT_NAME, EXT_FILE)
      ext.version = EXT_VERSION
      ext.description = EXT_DESCRIPTION
      ext.creator = "MH"
      ext.copyright = "2025"

      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
