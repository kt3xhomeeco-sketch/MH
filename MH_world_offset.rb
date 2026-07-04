# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module MH
  module WorldOffset
    EXTENSION_NAME = 'MH World Offset'.freeze
    EXTENSION_VERSION = '1.1.1'.freeze
    EXTENSION_DESCRIPTION = 'Resize 2 hoac 4 canh theo kich thuoc world, ho tro object xoay.'.freeze

    unless file_loaded?(__FILE__)
      loader = File.join('MH_world_offset', 'main')
      extension = SketchupExtension.new(EXTENSION_NAME, loader)
      extension.version = EXTENSION_VERSION
      extension.description = EXTENSION_DESCRIPTION
      extension.creator = 'MH'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
