# encoding: UTF-8
# MH_Rename - Rename Objects Plugin for SketchUp
# Author: MH
# Version: 1.0

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Rename
    EXT_VERSION = "1.0.0"
    EXT_NAME = "MH Rename"
    EXT_DESCRIPTION = "Rename groups and components with prefix, suffix, and numbering"
    EXT_FILE = File.join('MH_Rename', 'main')

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(EXT_NAME, EXT_FILE)
      ext.version = EXT_VERSION
      ext.description = EXT_DESCRIPTION
      ext.creator = "MH"
      ext.copyright = "2024"

      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
