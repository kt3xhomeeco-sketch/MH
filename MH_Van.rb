# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Van
    EXTENSION_NAME = 'MH Van'.freeze
    EXTENSION_VERSION = '1.3.5'.freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(
        EXTENSION_NAME,
        File.join('MH_Van', 'main')
      )
      extension.description = 'Bảng Loại Ván: gom theo độ dày và mã vật liệu, ẩn/hiện trong model.'
      extension.version = EXTENSION_VERSION
      extension.creator = 'MH'
      extension.copyright = '2026'

      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
