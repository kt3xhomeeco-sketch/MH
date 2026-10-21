# encoding: UTF-8
#
# MH_shared / vendor_loader.rb
# ---------------------------------------------------------------------------
# Nạp các thư viện vendored (pure Ruby) vào $LOAD_PATH một cách an toàn.
#
#   - rubyzip (v2.3.2)  -> module ::Zip   (nén/giải nén container .xlsx)
#   - sketchup-bridge   -> MH::Shared::Bridge (giao tiếp Ruby <-> JS trong HtmlDialog)
#
# Nguyên tắc:
#   * KHÔNG nạp lại nếu một plugin khác đã nạp cùng thư viện (tránh clobber version).
#   * Idempotent: gọi nhiều lần không gây lỗi.
# ---------------------------------------------------------------------------

module MH
  module Shared
    module VendorLoader
      VENDOR_DIR = File.join(__dir__, 'vendor').freeze

      module_function

      # Thêm 1 đường dẫn lib vào đầu $LOAD_PATH nếu chưa có.
      def add_load_path(path)
        return false unless File.directory?(path)
        $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path)
        true
      end

      # rubyzip: chỉ nạp nếu chưa có ::Zip (một plugin khác có thể đã vendor rubyzip).
      def load_rubyzip
        if defined?(::Zip)
          @rubyzip_source ||= :external
          return true
        end
        add_load_path(File.join(VENDOR_DIR, 'rubyzip', 'lib'))
        require 'zip'
        @rubyzip_source = :vendored
        true
      rescue LoadError => e
        warn "[MH_shared] Khong nap duoc rubyzip: #{e.message}"
        false
      end

      # sketchup-bridge: nạp file đã được namespace sang MH::Shared::Bridge.
      def load_bridge
        return true if defined?(MH::Shared::Bridge)
        require File.join(VENDOR_DIR, 'bridge', 'bridge.rb')
        true
      rescue LoadError => e
        warn "[MH_shared] Khong nap duoc bridge: #{e.message}"
        false
      end

      # Đường dẫn tới bridge.js để nhúng vào HtmlDialog.
      def bridge_js_path
        File.join(VENDOR_DIR, 'bridge', 'js', 'bridge.js')
      end

      def rubyzip_source
        @rubyzip_source
      end

      def load_all
        load_rubyzip
        load_bridge
      end
    end
  end
end
