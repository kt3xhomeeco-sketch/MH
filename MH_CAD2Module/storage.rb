# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'
require_relative 'ids'

module MH
  module CAD2Module
    module Storage
      module_function

      def write_json(path, value)
        FileUtils.mkdir_p(File.dirname(path))
        temporary = "#{path}.#{Ids.hex(6)}.tmp"
        File.write(temporary, JSON.pretty_generate(value), encoding: 'UTF-8')
        File.rename(temporary, path)
        path
      ensure
        File.delete(temporary) if temporary && File.file?(temporary)
      end

      def event(root, data)
        data = { 'schema' => 1, 'id' => Ids.uuid, 'time' => Time.now.utc.iso8601(6) }.merge(data)
        stamp = Time.now.utc.strftime('%Y%m%dT%H%M%S%6N')
        path = File.join(root, 'history', "#{stamp}-#{data['id']}.json")
        write_json(path, data)
        summary = data.slice('id', 'time', 'kind', 'status', 'reason', 'error', 'code', 'skp', 'activity_id', 'product_id', 'session', 'job_id')
        summary['code'] ||= data.dig('analysis', 'code')
        summary['activity_id'] ||= data.dig('analysis', 'activity_id')
        summary['automatic_scan'] = data.dig('analysis', 'automatic_scan')
        summary['plan_title'] = data.dig('analysis', 'plan_title') if data.dig('analysis', 'plan_title')
        summary['error'] ||= data.dig('analysis', 'error')
        summary['file'] = File.basename(path)
        write_json(File.join(root, 'history', 'index', "#{stamp}-#{data['id']}.json"), summary)
        data.merge('path' => path)
      end

      def history(root)
        Dir.glob(File.join(root, 'history', 'index', '*.json')).sort.last(30).reverse.filter_map do |path|
          JSON.parse(File.read(path, encoding: 'UTF-8'))
        rescue JSON::ParserError, SystemCallError
          nil
        end
      end

      def snapshot(root, instance, id)
        path = File.join(root, 'skp', "#{id}.skp")
        FileUtils.mkdir_p(File.dirname(path))
        saved = instance.definition.save_as(path)
        raise IOError, 'Không lưu được bản SKP độc lập vào thư viện.' unless saved && File.file?(path)
        path
      end

      def experience(root, event)
        return unless event['status'] == 'accepted'
        signature = event.fetch('signature')
        raise ArgumentError, 'Chữ ký hình học không hợp lệ.' unless signature.match?(/\A[0-9a-f]{64}\z/)
        stamp = Time.now.utc.strftime('%Y%m%dT%H%M%S%6N')
        write_json(File.join(root, 'experiences', signature, "#{stamp}-#{event.fetch('id')}.json"), event)
      end
    end
  end
end
