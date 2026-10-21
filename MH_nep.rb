# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Nep
    EXTENSION_NAME = 'MH Nep'.freeze
    EXTENSION_VERSION = '1.0.0'.freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(
        EXTENSION_NAME,
        File.join('MH_nep', 'main')
      )
      extension.description = 'Dán nẹp ABF theo hướng nhìn hoặc dán 4 cạnh nhỏ.'
      extension.version = EXTENSION_VERSION
      extension.creator = 'MH'
      extension.copyright = '2026'

      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
