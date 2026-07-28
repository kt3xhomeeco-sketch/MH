# encoding: UTF-8

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Export
    EXTENSION_NAME = 'MH Export'.freeze
    EXTENSION_VERSION = '1.1.0'.freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(
        EXTENSION_NAME,
        File.join('MH_EXPORT', 'main')
      )
      extension.description = 'Xuất định mức ván/nẹp từ dữ liệu ABF sang Excel DMVT.'
      extension.version = EXTENSION_VERSION
      extension.creator = 'MH'
      extension.copyright = '2026'

      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
