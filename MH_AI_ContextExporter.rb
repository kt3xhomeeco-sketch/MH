# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module AIContextExporter
    VERSION = '1.0.0'

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('MH AI Context Exporter', 'MH_AI_ContextExporter/main')
      extension.version = VERSION
      extension.creator = 'MH'
      extension.description = 'Xuất gói ngữ cảnh lỗi đã chọn từ SketchUp để AI phân tích.'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
