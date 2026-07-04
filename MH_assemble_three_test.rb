# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module MH
  module AssembleThreeTest
    unless defined?(@loaded) && @loaded
      ext = SketchupExtension.new('MH Assemble Three Test', File.join('MH_assemble_three_test', 'main'))
      ext.version     = '0.1.0'
      ext.creator     = 'MH'
      ext.description = 'Nhánh test Three.js export cho MH Assemble, không sửa plugin chính.'
      Sketchup.register_extension(ext, true)
      @loaded = true
    end
  end
end
