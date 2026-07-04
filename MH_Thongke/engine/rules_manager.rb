# encoding: utf-8
# MH_Thongke — RulesManager (Phase 2)
# Quản lý rules và xuất rules_data.json cho Core Matcher

module MH_Thongke
  module Engine
    module RulesManager
      RULES_DATA_JSON = File.join(MH_Thongke::DATA_DIR, "rules_data.json") unless defined?(RULES_DATA_JSON)

      # Trích xuất toàn bộ rules và lineage từ RAM/Attribute và serialize thành rules_data.json
      # File này sẽ được Core Matcher tiêu thụ hoàn toàn độc lập với SketchUp API.
      def self.export_rules_data_json(model = nil)
        model ||= Sketchup.active_model
        
        rules = MH_Thongke.respond_to?(:ensure_mini_accept_rules) ? MH_Thongke.ensure_mini_accept_rules : {}
        lineage = MH_Thongke.instance_variable_get(:@mini_name_lineage) || {}
        
        payload = {
          version: "1.0",
          timestamp: Time.now.iso8601,
          model_path: (model.respond_to?(:path) ? model.path : ""),
          accept_rules: rules.is_a?(Hash) ? rules : {},
          lineage: lineage.is_a?(Hash) ? lineage : {}
        }
        
        json_str = JSON.pretty_generate(payload)
        File.write(RULES_DATA_JSON, json_str, encoding: "UTF-8")
        puts "[RulesManager] Saved rules_data.json (#{json_str.bytesize} bytes)"
        RULES_DATA_JSON
      rescue => e
        puts "[RulesManager] Error saving rules_data.json: #{e.message}"
        nil
      end

      def self.load_rules_data_json
        return nil unless File.exist?(RULES_DATA_JSON)
        JSON.parse(File.read(RULES_DATA_JSON, encoding: "UTF-8"))
      rescue => e
        puts "[RulesManager] Error loading rules_data.json: #{e.message}"
        nil
      end
    end
  end
end
