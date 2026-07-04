# encoding: utf-8
# MH_Thongke — Core Matcher (Phase 2 & 3 Incremental Bridge)
# Tạm thời đóng vai trò là cầu nối xuất kết quả cuối cùng (Final Stamped Report)
# sau khi quá trình process_selection hoàn tất. Khi toàn bộ UI chuyển sang Stateless,
# file này sẽ được refactor để tính toán trực tiếp từ 3 file JSON đầu vào.

module MH_Thongke
  module Engine
    module CoreMatcher
      FINAL_REPORT_JSON = File.join(MH_Thongke::DATA_DIR, "final_stamped_report.json") unless defined?(FINAL_REPORT_JSON)

      # Trích xuất dữ liệu từ các mảng RAM đã được tính toán xong và ghi ra JSON
      def self.export_final_stamped_report(accessories, materials)
        return FINAL_REPORT_JSON

        accessories ||= []
        materials ||= []

        # Chỉ serialize những trường cần thiết cho UI, loại bỏ các SketchUp object
        serialize_item = ->(item) {
          h = {}
          item.each do |k, v|
            next if [:entities, :stat_entities].include?(k) # Bỏ qua SketchUp object
            if k == :length_items
              h[k] = Array(v).map do |li|
                serialized = {}
                li.each do |lk, lv|
                  next if lk == :top
                  serialized[lk] = lv
                end
                serialized
              end
            else
              h[k] = v
            end
          end
          h
        }

          excel_data = MH_Thongke.respond_to?(:mini_excel_items) ? (MH_Thongke.instance_variable_get(:@imported_excel_data) || []) : []
        
        payload = {
          version: "1.0",
          timestamp: Time.now.iso8601,
          summary: {
            total_accessories: accessories.size,
            total_materials: materials.size
          },
          accessories: accessories.map { |item| serialize_item.call(item) },
          materials: materials.map { |item| serialize_item.call(item) },
          excel_data: excel_data
        }

        json_str = JSON.pretty_generate(payload)
        File.write(FINAL_REPORT_JSON, json_str, encoding: "UTF-8")
        puts "[CoreMatcher] Saved final_stamped_report.json (#{json_str.bytesize} bytes)"
        FINAL_REPORT_JSON
      rescue => e
        puts "[CoreMatcher] Error saving final_stamped_report.json: #{e.message}"
        nil
      end

      # Load tệp report cuối cùng cho UI sử dụng (dành cho Phase 3)
      def self.load_final_stamped_report
        return nil unless File.exist?(FINAL_REPORT_JSON)
        JSON.parse(File.read(FINAL_REPORT_JSON, encoding: "UTF-8"))
      rescue => e
        puts "[CoreMatcher] Error loading final_stamped_report.json: #{e.message}"
        nil
      end

    end
  end
end
