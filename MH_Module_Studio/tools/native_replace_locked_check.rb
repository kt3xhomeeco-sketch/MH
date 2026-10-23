# encoding: UTF-8
# Focused native diagnostic for Replace with a T1-locked door module.
# Run only through the existing VBO Ruby eval binding:
#   load '<absolute path>/tools/native_replace_locked_check.rb'
#   MH::ModuleStudio::NativeReplaceLockedCheck.run
# It creates independent QA targets far from the model, calls the real
# LibraryPlacement.replace! once per entry, always aborts the QA operation,
# and returns measured diagnostics. It does not touch production files.
module MH
  module ModuleStudio
    module NativeReplaceLockedCheck
      extend self

      ENTRIES = ['Canh/Canh phai.skp', 'Canh/Cánh phải.skp'].freeze
      OFFSET_MM = 400_000.0

      def run
        unless defined?(Sketchup) && defined?(LibraryPlacement) && defined?(LibraryCatalog) && defined?(Assembly)
          raise 'MH Module Studio is not loaded in this Ruby binding.'
        end
        model = Sketchup.active_model
        raise 'No active SketchUp model.' unless model
        report = { 'ok'=>false, 'completed'=>false, 'pid'=>Process.pid, 'entries'=>[], 'cleanup'=>{} }
        unless model.active_path.nil?
          report['fixture'] = 'Active editing context; run with the model root active.'
          return report
        end
        view = model.active_view
        original_camera = view.camera
        original_camera_values = camera_values(original_camera)
        original_entities = model.entities.to_a
        original_definitions = model.definitions.to_a
        original_selection = model.selection.to_a
        previous_busy = Assembly.instance_variable_get(:@busy)
        report['source'] = {
          'replace'=>LibraryPlacement.instance_method(:replace!).source_location,
          'resize'=>LibraryPlacement.instance_method(:resize).source_location
        }
        @operation = false
        @aborted = 0
        @started = 0
        begin
          active = ModuleStudio.instance_variable_get(:@library)&.tool
          if active && active.respond_to?(:pending) && active.pending
            report['fixture'] = 'Active library placement is pending; retry when it finishes.'
            return report
          end
          library = Library.new
          root = library.config['root'].to_s
          unless !root.empty? && File.directory?(root)
            report['fixture'] = 'Library root is not configured.'
            return report
          end
          catalog = LibraryCatalog.scan(root)
          library.instance_variable_set(:@catalog, catalog)
          resolved = ENTRIES.map do |id|
            [id, Array(catalog['entries']).select { |row| row['id'] == id }]
          end
          report['entries'] = resolved.map do |id, rows|
            { 'id'=>id, 'matches'=>rows.length, 'path'=>rows.first && rows.first['path'] }
          end
          ambiguous = resolved.select { |_id, rows| rows.length != 1 }.map(&:first)
          unless ambiguous.empty?
            report['fixture'] = 'Entry is missing or ambiguous: ' + ambiguous.join(', ')
            return report
          end
          resolved.each_with_index do |(id, rows), index|
            report['entries'][index]['trial'] = trial(model, library, id, rows.first, index)
          end
        rescue StandardError => error
          report['errors'] = [error.class.name, error.message, Array(error.backtrace).first(12)]
        ensure
          disable_resize_trace
          if @operation
            model.abort_operation
            @aborted += 1
            @operation = false
          end
          if Assembly.instance_variable_get(:@busy) != previous_busy
            Assembly.instance_variable_set(:@busy, previous_busy)
          end
          if camera_values(model.active_view.camera) != original_camera_values
            begin
              model.active_view.camera = original_camera
            rescue StandardError
              report['camera_restore_failed'] = true
            end
          end
          report['cleanup'] = cleanup(model, original_entities, original_definitions,
            original_selection, original_camera_values, previous_busy, @aborted, @started)
        end
        checks = %w[entities_restored definitions_restored selection_restored camera_restored assembly_busy_restored]
        cleanup_ok = checks.all? { |key| report['cleanup'][key] == true } &&
          report['cleanup']['operations_aborted'] == report['cleanup']['operations_started'] &&
          report['cleanup']['operations_started'] == report['entries'].length
        report['cleanup_ok'] = cleanup_ok
        report['all_replacements_succeeded'] = report['entries'].length == ENTRIES.length &&
          report['entries'].all? { |row| row.dig('trial', 'ok') == true }
        report['completed'] = report['fixture'].nil? && cleanup_ok
        report['ok'] = report['completed'] && report['all_replacements_succeeded']
        report
      end

      def trial(model, library, id, entry, index)
        result = { 'entry_id'=>id, 'path'=>entry['path'], 'mode'=>'replace',
          'actual_locked_axes'=>nil, 'actual_t1'=>nil, 'actual_parameter_values'=>nil,
          'actual_rule_captured'=>false, 'actual_capture'=>'not reached' }
        begin
          data = library.preview(id)
          rule = data['rule']
          template = data['import_template'] || (rule && rule['import_template'])
          result['import_template'] = template && template.slice('role', 'enabled', 'door_face', 'kind')
          result['preview_rule_present'] = !rule.nil?
          result['preview_locked_axes'] = begin
            LibraryPlacement.locked_axes(data.merge('rule'=>rule))
          rescue StandardError => error
            result['locks_error'] = error.message
            nil
          end
          result['preview_t1'] = t1_info(rule)
          result['constraint_axes'] = Array(rule && rule['constraints']).map do |constraint|
            [constraint['type'], constraint['enabled'], constraint['drive'],
             constraint.dig('face', 'part'), constraint.dig('face', 'axis')]
          end
          source = Core.dimensions(data.dig('snapshot', 'envelope')).map { |value| value.to_f }
          size = [source[0] * 1.13, source[1] * 1.21, source[2] * 1.07].map { |value| (value * 1000.0).round / 1000.0 }
          result['source_mm'] = source.map { |value| value.round(3) }
          result['target_size_mm'] = size
        rescue StandardError => error
          result['ok'] = false
          result['fixture_error'] = [error.class.name, error.message, Array(error.backtrace).first(12)]
          return result
        end
        group = nil
        replaced = nil
        @trial_data = data
        @actual_rule = nil
        @actual_values = nil
        @actual_locked_axes = nil
        @actual_t1 = nil
        @actual_error = nil
        @actual_capture_started = false
        @trace_rows = []
        begin
          previous_busy = Assembly.instance_variable_get(:@busy)
          Assembly.instance_variable_set(:@busy, true)
          model.start_operation('MH QA Replace locked check', true)
          @operation = true
          @started += 1
          group = box_target(model, size, index)
          frame = group.transformation
          local = group.definition.bounds
          result['requested_mm'] = [local.min.to_a, local.max.to_a].map { |point| point.map { |value| (value * 25.4).round(3) } }
          enable_resize_trace
          begin
            replaced = LibraryPlacement.replace!(library, data, { 'root'=>group.persistent_id.to_s }, [])
          rescue StandardError => error
            result['ok'] = false
            result['error'] = {
              'class'=>error.class.name,
              'message'=>error.message,
              'backtrace'=>Array(error.backtrace).first(15)
            }
          ensure
            disable_resize_trace
          end
          result['resize'] = @trace_rows
          result['measured_mm'] = trace_value('measured')
          result['expected_mm'] = trace_value('expected')
          result['current_mm'] = trace_value('current')
          result['actual_locked_axes'] = @actual_locked_axes
          result['actual_t1'] = @actual_t1
          result['actual_parameter_values'] = @actual_values
          result['actual_rule_captured'] = !@actual_rule.nil?
          result['actual_capture'] = @actual_capture_started ? 'resize' : 'resize not reached'
          result['actual_capture_error'] = @actual_error
          if replaced
            result['ok'] = true
            result['result_pid'] = replaced.persistent_id.to_s
            result['result_class'] = replaced.class.name
            begin
              box = Frames.box(8.times.map do |corner|
                replaced.definition.bounds.corner(corner).transform(frame.inverse * replaced.transformation).to_a.map { |value| value * 25.4 }
              end)
              result['result_measured_mm'] = box.map { |point| point.map { |value| value.round(3) } }
            rescue StandardError => error
              result['result_measure_error'] = error.message
            end
          end
        rescue StandardError => error
          result['ok'] = false
          result['fixture_error'] = [error.class.name, error.message, Array(error.backtrace).first(12)]
        ensure
          disable_resize_trace
          if @operation
            model.abort_operation
            @aborted += 1
            @operation = false
          end
          Assembly.instance_variable_set(:@busy, previous_busy)
        end
        result
      end

      def box_target(model, size, index)
        group = model.entities.add_group
        group.name = 'MH QA locked replace target'
        points = Frames.corners([[0, 0, 0], size]).map { |point| point.map { |value| value / 25.4 } }
        [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]].each do |ids|
          group.entities.add_face(ids.map { |id| points[id] })
        end
        group.transformation = Geom::Transformation.translation([(OFFSET_MM + index * 5000.0) / 25.4, OFFSET_MM / 25.4, 0])
        group
      end

      def t1_info(rule)
        return nil unless rule.is_a?(Hash)
        rows = Parametric.variables(rule)
        row = rows.find { |entry| entry['symbol'].to_s.casecmp('T1').zero? }
        return unless row
        row.slice('symbol', 'binding', 'value', 'formula', 'editable', 'unit')
      rescue StandardError => error
        { 'error'=>error.message }
      end

      def enable_resize_trace
        path = LibraryPlacement.instance_method(:resize).source_location.first
        @resize_trace = TracePoint.new(:line) do |tp|
          next unless tp.self.equal?(LibraryPlacement) && tp.method_id == :resize && tp.path == path
          binding = tp.binding
          placement = safe_local(binding, :placement)
          next unless placement.is_a?(Hash) && placement['mode'] == 'replace'
          unless @actual_capture_started
            @actual_capture_started = true
            root = safe_local(binding, :root)
            begin
              if root
                actual_rule, actual_values = AssemblyParameters.data(root)
                @actual_rule = actual_rule
                @actual_values = actual_values
                @actual_locked_axes = LibraryPlacement.locked_axes(@trial_data.merge('rule'=>actual_rule))
                @actual_t1 = t1_info(actual_rule)
                if @actual_t1.is_a?(Hash) && !@actual_t1.key?('error') && actual_values.is_a?(Hash)
                  keys = [@actual_t1['binding'], @actual_t1['symbol']].compact.map(&:to_s)
                  @actual_t1 = @actual_t1.merge('saved_values'=>actual_values.select do |key, _value|
                    keys.include?(key.to_s)
                  end)
                end
              else
                @actual_error = ['MissingRoot', 'resize root local was nil']
              end
            rescue StandardError => error
              @actual_error = [error.class.name, error.message]
            end
          end
          row = { 'line'=>tp.lineno }
          row['redraw'] = safe_local(binding, :redraw)
          row['locked_axes'] = safe_local(binding, :locked_axes)
          row['placement'] = summarize(placement)
          %i[current expected measured].each { |name| row[name.to_s] = summarize(safe_local(binding, name)) }
          next if %w[current expected measured].all? { |key| row[key].nil? }
          @trace_rows << row
          @trace_rows.shift while @trace_rows.length > 3
        end
        @resize_trace.enable
      end

      def disable_resize_trace
        @resize_trace&.disable
        @resize_trace = nil
      end

      def safe_local(binding, name)
        binding.local_variable_get(name)
      rescue NameError
        nil
      end

      def summarize(value)
        case value
        when Hash
          value.slice('mode', 'kind', 'bounds')
        when Array
          value
        else
          value
        end
      end

      def trace_value(key)
        row = @trace_rows.reverse.find { |entry| entry[key] }
        row && row[key]
      end

      def camera_values(camera)
        [camera.eye.to_a, camera.target.to_a, camera.up.to_a]
      end

      def cleanup(model, entities_before, definitions_before, selection_before, camera_before, busy_before, aborted, started)
        remaining_entities = model.entities.to_a - entities_before
        remaining_definitions = model.definitions.to_a - definitions_before
        {
          'operations_started'=>started,
          'operations_aborted'=>aborted,
          'entities_restored'=>model.entities.to_a == entities_before,
          'definitions_restored'=>model.definitions.to_a == definitions_before,
          'selection_restored'=>model.selection.to_a == selection_before,
          'camera_restored'=>camera_values(model.active_view.camera) == camera_before,
          'assembly_busy_restored'=>Assembly.instance_variable_get(:@busy) == busy_before,
          'remaining_entities'=>remaining_entities.first(8).map { |entity| entity_label(entity) },
          'remaining_definition_count'=>remaining_definitions.length,
          'remaining_definitions'=>remaining_definitions.first(8).map { |definition| definition_label(definition) }
        }
      end

      def entity_label(entity)
        [entity.respond_to?(:persistent_id) ? entity.persistent_id.to_s : nil,
         entity.respond_to?(:name) ? entity.name.to_s : entity.class.name]
      end

      def definition_label(definition)
        [definition.respond_to?(:guid) ? definition.guid : nil,
         definition.respond_to?(:name) ? definition.name.to_s : nil]
      end
    end
  end
end
