# encoding: UTF-8
require 'json'
require 'fileutils'

module MH
  module MaterialHUD
    # Keep the user's saved VL approvals without loading the old application.
    # One-time copy: the new runtime reads only its own file afterwards.
    def self.migrate_acceptances
      target = File.join(__dir__, 'data', 'accept_rules.json')
      return if File.exist?(target)
      legacy = File.expand_path('../MH_Thongke/data/match_rules_global.json', __dir__)
      return unless File.file?(legacy)
      payload = JSON.parse(File.read(legacy, encoding: 'UTF-8'))
      rules = (payload['mini_accept_rules'] || {}).select { |key, _| key.split('|')[1] == 'VL' }
      FileUtils.mkdir_p(File.dirname(target))
      File.open(target, 'wx:UTF-8') { |file| file.write(JSON.pretty_generate(rules)) }
    rescue => e
      puts "[MH Material HUD] Không nhập được xác nhận vật liệu cũ: #{e.message}"
    end

    class Acceptances
      def self.load
        path = File.join(__dir__, 'data', 'accept_rules.json')
        new(File.file?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')) : {})
      end

      def initialize(rules = {})
        @rules = Hash.new { |hash, key| hash[key] = [] }
        rules.each do |key, value|
          product, kind, model, target, spec = key.split('|', 5)
          next unless kind == 'VL'
          action = value.is_a?(Hash) ? value['action'].to_s : value.to_s
          next unless ['', 'accept', 'update', 'keep', 'add', 'manual_add', 'manual_match', 'rename_update', 'accept_no_spec'].include?(action)
          @rules[ProductContext.base(product)] << [Catalog.material_key(model), Catalog.material_key(target), Text.fold(spec)]
        end
      end

      def accepted?(product, model, target, spec = '')
        query_spec = Text.fold(spec)
        @rules.fetch(product, []).any? do |stored_model, stored_target, stored_spec|
          spec_ok = query_spec.empty? || stored_spec.empty? || query_spec == stored_spec
          # Empty target is an approval for model-only, NOT a wildcard match.
          spec_ok && stored_model == model && stored_target == target
        end
      end
    end
  end
end
