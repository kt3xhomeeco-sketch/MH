# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module CAD2Module
    VERSION = '0.10.1'

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('MH CAD2Module', 'MH_CAD2Module/main')
      extension.version = VERSION
      extension.creator = 'MH'
      extension.description = 'Đọc hình học CAD, tự chia module và dựng theo nhãn SP; lưu kinh nghiệm sửa lỗi.'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
