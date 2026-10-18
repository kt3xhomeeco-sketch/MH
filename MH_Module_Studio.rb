# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module MH
  module ModuleStudio
    VERSION = '0.1.0'.freeze
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('MH Module Studio', File.join('MH_Module_Studio', 'main'))
      extension.version = VERSION
      extension.creator = 'MH'
      extension.description = 'Học thay đổi độ dày từ nhiều trạng thái module và kiểm chứng trên bản sao.'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
