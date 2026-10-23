# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Isolate
    PLUGIN_NAME = 'MH Isolate'.freeze unless const_defined?(:PLUGIN_NAME, false)
    VERSION = '1.5.3'.freeze unless const_defined?(:VERSION, false)

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(PLUGIN_NAME, 'MH_isolate/main')
      extension.description = 'Fast object-only isolate/unisolate for SketchUp.'
      extension.version = VERSION
      extension.creator = 'MH'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
