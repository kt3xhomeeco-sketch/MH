# encoding: UTF-8
require_relative 'core'

module MH
  module ModuleStudio
    module DCFunctionCapture
      extend self

      # The installed ABF loader supplies its generated source to abf_eval.
      # Intercept synchronously BEFORE that boundary: never evaluate imported
      # Ruby, never call its functions, and always restore the existing method.
      def definition_function_source(definition)
        return unless Thread.current == Thread.main && defined?(ABF::DC_Loader) && defined?(DCFunctionsV1)
        return unless definition.get_attribute('abf_object_data', 'dc_data').is_a?(String)
        return unless DCFunctionsV1.respond_to?(:abf_eval)
        singleton = DCFunctionsV1.singleton_class
        own = singleton.instance_methods(false).include?(:abf_eval)
        previous = DCFunctionsV1.method(:abf_eval)
        captured = nil
        stop = Object.new
        begin
          DCFunctionsV1.define_singleton_method(:abf_eval) do |source|
            raise Core::Error, 'Nội dung hàm DC quá lớn.' unless source.is_a?(String) && source.bytesize <= 1024 * 1024
            captured = source.dup
            throw stop
          end
          # Stop before function registration, network calls, or DC redraw.
          catch(stop) { ABF::DC_Loader.instance.load(definition) }
        ensure
          own ? DCFunctionsV1.define_singleton_method(:abf_eval, previous) : singleton.send(:remove_method, :abf_eval)
        end
        captured
      end

      def capture_definition_aliases!(definition, snapshot)
        return snapshot if Core.attribute_inventory(snapshot)['unknown_functions'].empty?
        pending = [definition]
        seen = []
        saved = snapshot.fetch('function_aliases', {}).dup
        until pending.empty?
          current = pending.shift
          next if seen.include?(current)
          seen << current
          raise Core::Error, 'Cây định nghĩa DC quá lớn.' if seen.length > 1200
          source = definition_function_source(current)
          if source
            DCFormulas.source_nominal_aliases(source).each do |name, entry|
              raise Core::Error, 'Hàm DC trùng tên nhưng khác định nghĩa.' if saved.key?(name) && saved[name] != entry
              saved[name] = entry
            end
          end
          current.entities.each do |entity|
            pending << entity.definition if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          end
        end
        snapshot['function_aliases'] = saved unless saved.empty?
        DCFormulas.function_aliases(snapshot)
        snapshot
      rescue StandardError => error
        snapshot['function_diagnostics'] = [error.message]
        snapshot
      end

      def enrich_file_functions!(snapshot, path)
        return snapshot if Core.attribute_inventory(snapshot)['unknown_functions'].empty?
        return snapshot unless Thread.current == Thread.main && defined?(Sketchup) && defined?(ABF::DC_Loader)
        model = Sketchup.active_model
        operation = false
        begin
          model.start_operation('MH Đọc Định Nghĩa DC', true)
          operation = true
          definition = model.definitions.load(path)
          capture_definition_aliases!(definition, snapshot)
        ensure
          model.abort_operation if operation
        end
        snapshot
      end

      def capture_function_aliases!(snapshot)
        functions = Core.attribute_inventory(snapshot,limit:nil)['formulas'].flat_map { |entry| entry['formula'].scan(/\b([a-z_][a-z_0-9]*)\s*\(/i).flatten.map(&:downcase) }.uniq
        saved = snapshot.fetch('function_aliases', {}).dup
        functions.each do |name|
          if DCFormulas::NOMINAL_FUNCTIONS.key?(name)
            saved[name] = { 'kind' => 'parent_nominal', 'attribute' => DCFormulas::NOMINAL_FUNCTIONS[name], 'signature' => DCFormulas::NOMINAL_SIGNATURE }
          elsif !DCFormulas::FUNCTIONS.include?(name) && defined?(DCFunctionsV1) && defined?(RubyVM::InstructionSequence)
            begin
              next unless DCFunctionsV1.method_defined?(name) || DCFunctionsV1.private_method_defined?(name)
              method = DCFunctionsV1.instance_method(name)
              sequence = RubyVM::InstructionSequence.of(method)
              entry = sequence && DCFormulas.verified_nominal_reference(sequence.to_a)
              saved[name] = entry if entry
            rescue NameError, TypeError
              next
            end
          end
        end
        snapshot['function_aliases'] = saved unless saved.empty?
        snapshot
      end
    end
  end
end
