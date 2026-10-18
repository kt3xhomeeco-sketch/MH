# encoding: UTF-8
# Developer-only: native function extraction, no eval/registration/redraw.
require 'json'
require 'digest'
require_relative '../reader'

module MH
  module ModuleStudio
    class NativeFunctionAudit
      attr_reader :report

      def initialize
        @model = Sketchup.active_model
        raise Core::Error, 'Chỉ dùng phiên thử riêng.' unless @model.path.tr('\\', '/').include?('/outputs/dc-functions-024/1.skp')
        project = File.expand_path('..', __dir__)
        @files = JSON.parse(File.read(File.join(project, 'outputs', 'library-016', 'manifest.json'), encoding: 'UTF-8'))
        @output = File.join(project, 'outputs', 'dc-functions-024', 'native-functions.json')
        @roots = @model.entities.to_a
        @definitions = @model.definitions.to_a
        @selection = @model.selection.to_a
        @eval_method = DCFunctionsV1.method(:abf_eval)
        @methods = (DCFunctionsV1.instance_methods + DCFunctionsV1.private_instance_methods).sort
        @report = { 'status' => 'running', 'total' => @files.length, 'files' => [] }
      end

      def start
        @timer = UI.start_timer(0.1, true) { tick }
        self
      end

      def audit(file)
        row = file.slice('relative', 'sha256')
        operation = false
        begin
          raise Core::Error, 'Nguồn thay đổi sau khi SDK đọc.' unless Digest::SHA256.file(file.fetch('path')).hexdigest == file.fetch('sha256')
          data = JSON.parse(File.read(file.fetch('capture'), encoding: 'bom|utf-8')).fetch('data')
          dc = ->(attrs) { attrs.select { |key, _value| key.start_with?('dynamic_attributes/') }.transform_keys { |key| key.delete_prefix('dynamic_attributes/') } }
          all = data.fetch('definitions').values.flat_map { |definition| [definition.fetch('attributes', {}), *definition.fetch('nodes', []).map { |node| node.fetch('attributes', {}) }] }
          snapshot = { 'parts' => [], 'dc_inputs' => dc.call(data.dig('meta', 'model_attrs') || {}),
                       'dc_graph' => { 'nodes' => all.map { |attrs| { 'path' => [], 'attributes' => dc.call(attrs) } } } }
          DCFunctionCapture.capture_function_aliases!(snapshot)
          @model.start_operation('MH Kiểm Tra Hàm DC', true)
          operation = true
          definition = @model.definitions.load(file.fetch('path'))
          Reader.capture_definition_aliases!(definition, snapshot)
          row['aliases'] = snapshot.fetch('function_aliases', {})
          row['diagnostics'] = snapshot.fetch('function_diagnostics', [])
          formulas = [snapshot['dc_inputs'], *snapshot['dc_graph']['nodes'].map { |node| node['attributes'] }].flat_map do |attrs|
            attrs.filter_map { |key, value| value if key.match?(/\A_.+_formula\z/i) && value.is_a?(String) }
          end
          functions = formulas.flat_map { |text| text.scan(/\b([a-z_][a-z_0-9]*)\s*\(/i).flatten.map(&:downcase) }.uniq
          row['unknown_functions'] = (functions - DCFormulas::FUNCTIONS - DCFormulas.function_aliases(snapshot).keys).sort
        rescue StandardError => error
          row['error'] = "#{error.class}: #{error.message}"
        ensure
          @model.abort_operation if operation
          row['source_unchanged'] = Digest::SHA256.file(file.fetch('path')).hexdigest == file.fetch('sha256')
          unless @model.entities.to_a == @roots && @model.definitions.to_a == @definitions && @model.selection.to_a == @selection && DCFunctionsV1.method(:abf_eval) == @eval_method
            raise Core::Error, 'Model hoặc hàm gốc thay đổi; dừng khảo sát.'
          end
        end
        row
      end

      def tick
        raise Core::Error, 'Phiên model thử đã đổi.' unless Sketchup.active_model.equal?(@model)
        file = @files[@report['files'].length]
        if file
          @report['files'] << audit(file)
        else
          UI.stop_timer(@timer)
          @report['status'] = 'complete'
          @report['source_hashes_verified'] = @report['files'].all? { |row| row['source_unchanged'] }
          @report['no_imported_functions_registered'] = @methods == (DCFunctionsV1.instance_methods + DCFunctionsV1.private_instance_methods).sort
          @report['eval_hook_restored'] = DCFunctionsV1.method(:abf_eval) == @eval_method
          @report['verified_alias_names'] = @report['files'].flat_map { |row| row.fetch('aliases', {}).keys }.uniq.length
          @report['unresolved_names'] = @report['files'].flat_map { |row| row.fetch('unknown_functions', []) }.uniq
        end
        File.write(@output, JSON.pretty_generate(@report))
      rescue StandardError => error
        UI.stop_timer(@timer)
        @report['status'] = 'stopped'
        @report['fatal_error'] = "#{error.class}: #{error.message}"
        File.write(@output, JSON.pretty_generate(@report))
      end
    end
  end
end
