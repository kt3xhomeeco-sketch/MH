# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Redraw
    EXTENSION_NAME = 'MH Redraw'.freeze
    EXTENSION_VERSION = '1.0.0'.freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(
        EXTENSION_NAME,
        File.join('MH_redraw', 'main')
      )
      extension.description = 'Redraw nhiều Dynamic Component đang được chọn.'
      extension.version = EXTENSION_VERSION
      extension.creator = 'MH'
      extension.copyright = '2026'

      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
