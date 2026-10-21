# encoding: UTF-8
module MH
  module ModuleStudio
    module VerifyDrawerExports
      extend self

      def start(expected_pid:)
        raise 'Pinned process only' unless Process.pid==expected_pid
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @model = Sketchup.active_model
        @roots = @model.entities.to_a; @definitions = @model.definitions.to_a; @selection = @model.selection.to_a
        @library = Library.new
        @library.instance_variable_get(:@config)['root'] = LibraryConversion::DESTINATION
        @library.refresh
        rows = %w[pilot-conversion.json retry-round1.json retry.json].flat_map do |file|
          data = JSON.parse(File.read(File.join(@base,'outputs/drawer-036',file),encoding:'UTF-8'))
          data['files'] || [data]
        end
        @names = rows.select { |row| row['status']=='converted' }.map { |row| row['relative'] }.uniq
        @report = {'status'=>'running','total'=>@names.length,'files'=>[]}
        @timer = UI.start_timer(0.2,true) { tick }
      end

      def tick
        return if @busy
        @busy = true
        raise 'Model context changed' unless Sketchup.active_model.equal?(@model) && @model.active_path.nil?
        name = @names[@report['files'].length]
        unless name
          UI.stop_timer(@timer)
          @report['status'] = 'complete'
          write
          return
        end
        row = {'relative'=>name,'ok'=>false}
        begin
          item = @library.catalog['entries'].find { |entry| entry['id']==name }
          original_hash = Digest::SHA256.file(item['path']).hexdigest
          data = @library.prepare(item['id'])
          @model.start_operation('MH Xác minh ngăn kéo đã xuất',true)
          operation = true
          root = @library.build_instance(data,Geom::Transformation.new)
          rule,values,snapshot, = NativeDrawerCheck.current(root)
          raise 'Imported formulas not idempotent' unless Core.plan(rule,snapshot,{})['changed_count'].zero?
          param = rule['parameters'].find { |p| p['editable'] && p['label'].match?(/Panel Thickness|Dày Tấm|dày ván/i) }
          raise 'No panel thickness control' unless param
          Runtime.apply_trial_update(root,rule,{param['key']=>values[param['key']]+0.1})
          _rule,_values,changed, = NativeDrawerCheck.current(root)
          raise 'Envelope changed after edit' unless Core.bounds_close?(changed['envelope'],snapshot['envelope'],0.001)
          row.merge!('ok'=>true,'parts'=>changed['parts'].length,'tested_parameter'=>param['label'])
        rescue StandardError => error
          row['error'] = error.message
        ensure
          @model.abort_operation if operation
          row['file_unchanged'] = original_hash==Digest::SHA256.file(item['path']).hexdigest if item
          raise 'Verification altered the user model' unless @roots==@model.entities.to_a && @definitions==@model.definitions.to_a && @selection==@model.selection.to_a
        end
        @report['files'] << row
        write
      rescue StandardError => error
        UI.stop_timer(@timer)
        @report['status'] = 'stopped'; @report['error'] = error.message
        write
      ensure
        @busy = false
      end

      def write
        @report['passed'] = @report['files'].count { |row| row['ok'] && row['file_unchanged'] }
        File.write(File.join(@base,'outputs/drawer-036/reimport.json'),JSON.pretty_generate(@report))
      end
    end
  end
end
