# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Stretch
    PLUGIN_NAME = 'MH Stretch'.freeze
    PLUGIN_VERSION = '1.2.0'.freeze

    FILENAMESPACE = 'MH_stretch'.freeze
    PATH_ROOT = File.dirname(__FILE__).freeze
    PATH = File.join(PATH_ROOT, FILENAMESPACE).freeze

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new(PLUGIN_NAME, File.join(FILENAMESPACE, 'main'))
      ex.version = PLUGIN_VERSION
      ex.creator = 'MH'
      ex.description = 'Grip, plane, dimension UI with MH backup stretch engine. No scale/DC engine.'
      Sketchup.register_extension(ex, true)
    end
  end
end

file_loaded(__FILE__)
