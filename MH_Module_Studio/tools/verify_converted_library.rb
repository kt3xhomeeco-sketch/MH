# encoding: UTF-8
require 'json'
require 'csv'
require 'digest'
require 'time'
require_relative '../library_hud'

module MH
  module ModuleStudio
    class ConvertedLibraryVerification
      DESTINATION = 'D:/Cong viec/Sketchup/DC/Modul_studio'.freeze
      attr_reader :report

      def initialize
        @path = File.join(DESTINATION, '.conversion', 'report.json')
        @report = JSON.parse(File.read(@path, encoding: 'UTF-8'))
        raise Core::Error, 'Chuyển thư viện chưa hoàn tất.' unless @report['status'] == 'complete'
        @rows = @report['files'].select { |row| row['status'] == 'converted' }
        @model = Sketchup.active_model
        Runtime.ensure_top_level(@model)
        raise Core::Error, 'Chỉ kiểm tra trong model thử 1.skp.' unless File.basename(@model.path).downcase == '1.skp'
        @roots = @model.active_entities.to_a
        @definitions = @model.definitions.to_a
        @selection = @model.selection.to_a
        @library = Library.new
        @index = 0
        FileUtils.cp(@path, File.join(DESTINATION, '.conversion', 'report-before-native-verification.json'))
        @report['native_verification_status'] = 'running'
      end

      def start
        @timer = UI.start_timer(0.1, true) { tick }
        self
      end

      def save
        @report['converted'] = @report['files'].count { |row| row['status'] == 'converted' }
        @report['failed'] = @report['files'].count { |row| row['status'] == 'failed' }
        @report['native_verified'] = @rows.count { |row| row['native_edit_round_trip'] }
        File.write(@path, JSON.pretty_generate(@report))
      end

      def check_parameter(root, data, baseline, bindings, param)
        diagnostics = []
        accepted = false
        [0.1, -0.1].each do |delta|
          value = param['value'] + delta
          next unless value.between?(*param.fetch('input_range', [0.2, 100]))
          begin
            plan = Core.plan(data['rule'], baseline, param['key'] => value)
          rescue Core::Error => error
            diagnostics << error.message
            next
          end
          next unless plan['changed_count'].positive?
          Runtime.apply_plan(bindings, plan)
          Runtime.stamp(root, data['rule'], bindings, plan['target'])
          Runtime.verify_result(root, plan)
          actual, = Reader.live(root, label: root.name, parameter: data['snapshot']['parameter'])
          unless Core.plan(data['rule'], actual, {})['changed_count'].zero?
            raise Core::Error, "#{param['label']}: hình học không ổn định sau thay đổi."
          end
          reverse = plan.merge('parts' => plan['parts'].map do |part|
            part.merge('bounds' => part['old_bounds'], 'old_bounds' => part['bounds'])
          end)
          Runtime.apply_plan(bindings, reverse)
          Runtime.stamp(root, data['rule'], bindings, data['values'])
          Runtime.verify_result(root, reverse)
          accepted = true
        end
        { 'key' => param['key'], 'label' => param['label'], 'edit_verified' => accepted,
          'native_edit_verified' => accepted, 'diagnostic' => accepted ? nil : diagnostics.uniq.join(' · ') }
      end

      def verify(row)
        path = File.join(DESTINATION, row['relative'])
        operation = false
        begin
          raise Core::Error, 'File đích đã đổi sau khi chuyển.' unless Digest::SHA256.file(path).hexdigest == row['output_sha256']
          @model.start_operation('MH Kiểm Tra Tham Số Thật', true)
          operation = true
          definition = @model.definitions.load(path)
          data = LibraryCatalog.payload(definition.get_attribute(Reader::DICT, LibraryCatalog::PAYLOAD_KEY))
          root = @model.active_entities.add_instance(definition, Geom::Transformation.new)
          root.name = data['name']
          Runtime.private_tree(root)
          _snapshot, bindings = @library.validate_geometry(root, data)
          Runtime.stamp(root, data['rule'], bindings, data['values'])
          baseline, = Reader.live(root, label: root.name, parameter: data['snapshot']['parameter'])
          row['parameter_checks'] = data['rule']['parameters'].select { |param| param['editable'] }.map do |param|
            check_parameter(root, data, baseline, bindings, param)
          end
          unless row['parameter_checks'].any? { |item| item['native_edit_verified'] }
            raise Core::Error, 'Chưa có đầu vào đổi hình an toàn trong điều kiện giữ phủ bì.'
          end
          row['native_edit_round_trip'] = true
        rescue StandardError => error
          row['status'] = 'failed'
          row['error'] = "Kiểm tra bản xuất: #{error.class}: #{error.message}"
          row['native_edit_round_trip'] = false
        ensure
          @model.abort_operation if operation
          unless @model.active_entities.to_a == @roots && @model.definitions.to_a == @definitions && @model.selection.to_a == @selection
            raise Core::Error, 'Dừng kiểm tra: model thử đã thay đổi.'
          end
        end
        return if row['native_edit_round_trip']
        # Only relocate this job's own, byte-verified export; retain it for diagnosis.
        if File.file?(path) && Digest::SHA256.file(path).hexdigest == row['output_sha256'] && LibraryCatalog.inside?(DESTINATION, path)
          archive = File.expand_path(File.join(DESTINATION, '.conversion', 'needs-review', row['relative']))
          archive = archive.sub(/\.skp\z/i, "--#{row.fetch('output_sha256')[0, 12]}.skp") if File.exist?(archive)
          boundary = File.expand_path(File.join(DESTINATION, '.conversion', 'needs-review')) + '/'
          raise Core::Error, 'Đường dẫn lưu bản kiểm tra không hợp lệ.' unless archive.tr('\\', '/').start_with?(boundary.tr('\\', '/'))
          FileUtils.mkdir_p(File.dirname(archive))
          raise Core::Error, 'Bản kiểm tra đã tồn tại; không ghi đè.' if File.exist?(archive)
          File.rename(path, archive)
          row['review_file'] = archive
        end
      end

      def tick
        return if @busy
        @busy = true
        unless Sketchup.active_model.equal?(@model) && !@model.active_path
          raise Core::Error, 'Model thử đã đổi. Dừng kiểm tra.'
        end
        row = @rows[@index]
        unless row
          finish
          return
        end
        verify(row)
        @index += 1
        @report['native_processed'] = @index
        save
      rescue StandardError => error
        UI.stop_timer(@timer)
        @report['native_verification_status'] = 'stopped'
        @report['native_verification_error'] = "#{error.class}: #{error.message}"
        save
      ensure
        @busy = false
      end

      def finish
        UI.stop_timer(@timer)
        @report['native_verification_status'] = 'complete'
        @report['source_hashes_verified'] = @report['files'].all? do |row|
          Digest::SHA256.file(File.join(@report['source'], row['relative'])).hexdigest == row['source_sha256']
        end
        @report['user_model_retained'] = @model.active_entities.to_a == @roots && @model.definitions.to_a == @definitions && @model.selection.to_a == @selection
        save
        rows = @report['files']
        CSV.open(File.join(DESTINATION, '.conversion', 'report.csv'), 'wb', encoding: 'bom|utf-8') do |csv|
          csv << %w[file status parts editable_parameters native_edit_round_trip source_unchanged diagnostic]
          rows.each { |row| csv << row.values_at('relative', 'status', 'parts', 'editable_parameters', 'native_edit_round_trip', 'source_unchanged', 'error') }
        end
        lines = ['# Thư viện Modul_studio', '', "Nguồn: #{@report['source']}", "Đích: #{DESTINATION}", '',
                 "Tổng #{@report['total']} SKP: #{@report['converted']} module đã chuyển và kiểm tra đổi hình học thật; #{@report['failed']} chưa chuyển được.",
                 "SHA-256 nguồn giữ nguyên: #{@report['source_hashes_verified']}. Model/selection/definitions giữ nguyên: #{@report['user_model_retained']}.", '',
                 'Các đầu vào vẫn chịu kiểm tra phủ bì/giao tấm. Xem parameter_checks trong report.json để biết đầu vào đã thử ±0,1 mm độc lập; có thông số chỉ dùng được khi đổi đồng thời với thông số liên quan.', '',
                 '| File | Kết quả | Tham số | Chi tiết |', '|---|---|---:|---|']
        rows.each { |row| lines << "| #{row['relative'].gsub('|', '/')} | #{row['status']} | #{row['editable_parameters']} | #{row['error'].to_s.gsub('|', '/').gsub(/\s+/, ' ')} |" }
        File.write(File.join(DESTINATION, '.conversion', 'report.md'), lines.join("\n"))
        Sketchup.status_text = "MH: #{@report['converted']} module đã kiểm tra đổi tham số thật."
      end
    end
  end
end
