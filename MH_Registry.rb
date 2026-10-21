# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module MH
  module RegistryApp
    unless defined?(@loaded) && @loaded
      ext = SketchupExtension.new('MH Registry', File.join('MH_Registry', 'main'))
      ext.version     = '1.0.0'
      ext.creator     = 'MH'
      ext.description = 'Trung tâm quản lý dữ liệu sản phẩm / modul / vật liệu cho hệ plugin MH_*'
      Sketchup.register_extension(ext, true)
      @loaded = true
    end
  end
end
