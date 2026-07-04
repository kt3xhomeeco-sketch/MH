# ==========================================================
# MH_Superimp.rb – Extension loader
# Đặt file này TRỰC TIẾP trong thư mục Plugins
# Và tạo folder: Plugins/MH_Superimp/src/main.rb
# ==========================================================

require 'sketchup.rb'
require 'extensions.rb'

module MH
  module Superimp

    PLUGIN_ID   = 'MH_Superimp'.freeze
    PLUGIN_NAME = 'MH Superimp – Multi Import'.freeze
    PLUGIN_VER  = '1.0.0'.freeze

    # File main: nằm trong thư mục con "MH_Superimp/src/main.rb"
    LOADER_FILE = File.join('MH_Superimp', 'src', 'main')

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new(PLUGIN_NAME, LOADER_FILE)
      ex.description = 'Live box preview + multi import + auto scale from config list.'
      ex.version     = PLUGIN_VER
      ex.copyright   = 'MH 2025'
      ex.creator     = 'MH 2025'

      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end

    # ======================================================
    # RELOAD – Load lại toàn bộ file .rb trong thư mục src
    # Dùng cho dev và cho HtmlDialog (bấm Lưu -> reload)
    # ======================================================
    def self.reload
      original_verbose = $VERBOSE
      $VERBOSE = nil

      base = File.join(__dir__, 'MH_Superimp', 'src')
      pattern = File.join(base, '**/*.rb')
      files = Dir.glob(pattern)

      files.each { |f| load f }

      puts "MH::Superimp reloaded #{files.size} file(s) from: #{base}"
    ensure
      $VERBOSE = original_verbose
    end

  end
end
