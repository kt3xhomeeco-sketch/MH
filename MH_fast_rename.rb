# encoding: UTF-8
# MH_fast_rename - Fast Zone-based Rename Tool for SketchUp
# Author: MH
# Version: 1.0
# Sub-plugin of MH_Rename

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module FastRename
    EXT_VERSION = "1.0.0"
    EXT_NAME = "MH Fast Rename"
    EXT_DESCRIPTION = "Fast zone-based rename: auto-group objects into zones, split zones, assign SP codes"
    EXT_FILE = File.join('MH_fast_rename', 'main')

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
