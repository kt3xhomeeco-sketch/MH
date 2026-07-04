# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Scale
    EXTENSION_NAME = 'MH Scale'.freeze
    EXTENSION_VERSION = '0.4.1'.freeze
    FILENAMESPACE = File.basename(__FILE__, '.*')
    PATH_ROOT = File.dirname(__FILE__).freeze
    PATH = File.join(PATH_ROOT, FILENAMESPACE).freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(
        EXTENSION_NAME,
        File.join('MH_scale', 'main')
      )
      extension.description = 'MH Scale - SmartScale UI with MH stretch engine integration.'
      extension.version = EXTENSION_VERSION
      extension.creator = 'MH'
      extension.copyright = '2026'

      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
