# encoding: UTF-8
# Developer compatibility entry point; production conversion lives in the adapter.
require_relative '../library_hud'
require_relative '../dc_library_conversion'
module MH
  module ModuleStudio
    class LibraryConversion < DCLibraryConversion
      SOURCE='D:/Cong viec/Sketchup/DC/MH'.freeze
      DESTINATION='D:/Cong viec/Sketchup/DC/Modul_studio'.freeze
      def initialize(paths: nil, allow_current_model: false)
        unless allow_current_model || File.basename(Sketchup.active_model.path).downcase=='1.skp'
          raise Core::Error,'Chỉ chạy trong model thử 1.skp.'
        end
        super(source:SOURCE,destination:DESTINATION,paths:paths)
      end
    end
  end
end
