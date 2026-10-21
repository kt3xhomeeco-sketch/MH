# frozen_string_literal: true

module MH
  module CAD2Module
    # Only a small status file is read on SketchUp's main thread. Training is a worker job.
    module PlanRules
      module_function

      def status(root)
        path = File.join(Settings.resolve_library(root), 'rules', 'plan-v1', 'status.json')
        data = File.file?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')) : {}
        data.merge('error' => (@errors || {})[root])
      rescue JSON::ParserError, SystemCallError
        { 'error' => 'Chưa đọc được trạng thái quy tắc; lần quét tiếp theo sẽ kiểm tra lại.' }
      end

      def enqueue(event)
        return unless event.dig('analysis', 'build_stages', 'elevation') == false
        root = Settings.resolve_library(File.dirname(File.dirname(event.fetch('path'))))
        @pending ||= []
        @pending << root unless @pending.include?(root)
        @timer ||= UI.start_timer(0.5, true) { drain }
      rescue StandardError => error
        warn("CAD2Module: Đã lưu box; chưa xếp được tác vụ học: #{error.message}")
      end

      def drain
        return if Jobs.busy?
        root = (@pending || []).shift
        unless root
          UI.stop_timer(@timer) if @timer
          @timer = nil
          return
        end
        Jobs.start('learn_plan', 'learning_library' => root) do |result, _job|
          @errors ||= {}
          @errors[root] = result['ok'] ? nil : result.fetch('error', 'Chưa cập nhật được quy tắc tự học.')
          CAD2Module.publish
        end
      rescue StandardError => error
        @errors ||= {}
        @errors[root] = "Chưa chạy được bước học: #{error.message}"
        CAD2Module.publish
      end
    end
  end
end
