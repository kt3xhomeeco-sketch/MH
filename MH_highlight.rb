# encoding: UTF-8
# MH Highlight - persistent viewport highlighting for tagged instances.

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Highlight
    EXTENSION_NAME = 'MH Highlight'.freeze
    EXTENSION_FILE = File.join('MH_highlight', 'main').freeze
    EXTENSION_VERSION = '1.7.0'.freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(EXTENSION_NAME, EXTENSION_FILE)
      extension.version = EXTENSION_VERSION
      extension.description = 'X-ray highlight edges inside tagged groups and components.'
      extension.creator = 'MH'
      extension.copyright = '2026 MH'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
