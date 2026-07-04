# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Assemble
    unless defined?(@loaded) && @loaded
      ext = SketchupExtension.new('MH Assemble', File.join('MH_assemble', 'main'))
      ext.version     = '0.1.0'
      ext.creator     = 'MH'
      ext.description = 'Tạo bản vẽ tủ/module → PDF (A3). Phase 1: scanner.'
      Sketchup.register_extension(ext, true)
      @loaded = true
    end
  end
end
