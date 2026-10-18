# encoding: UTF-8

module MH
  module ModuleStudio
    module ScalePlan
      extend self

      # A positive Scale probe is calculation data only; never mutate the
      # caller's snapshot or temporarily deform native model geometry.
      def scaled_snapshot(current,factors)
        unless factors.is_a?(Array) && factors.length==3 && factors.all? { |value| Core.number(value)>0 }
          raise Core::Error,'Tỉ lệ thăm dò kích thước không hợp lệ.'
        end
        factors = factors.map { |value| Core.number(value) }
        result = Core.copy_data(current)
        result['parts'].each do |part|
          part['bounds'].each { |point| 3.times { |axis| point[axis] *= factors[axis] } }
        end
        result['envelope'].each { |point| 3.times { |axis| point[axis] *= factors[axis] } }
        if result['dc_graph']
          [0,5,10].each_with_index { |index,axis| result['dc_graph']['root_frame'][index] *= factors[axis] }
        end
        result
      end

      def plan(rule, current, saved)
        rule = Core.copy_data(rule)
        current = Core.copy_data(current)
        RuleSystem.validate!(rule)
        return DCCopies.plan(rule,current,saved,absolute:true) if DCCopies.needed?(rule,current,saved)
        Core.snapshot!(current)
        values = rule['parameters'].select { |param| param['editable'] }.to_h do |param|
          [param['key'], Core.number(saved.fetch(param['key']))]
        end
        seed = Marshal.load(Marshal.dump(current))
        seed['dc_inputs'] = {}
        seed['parameter_values'] = values
        # Native Scale supplies a new explicit construction frame.
        seed.delete('formula_envelope')
        engine = rule['formula_engine']
        if engine
          program_data = engine['attribute_program']
          raise Core::Error, 'Quy tắc so sánh mẫu chưa đủ công thức để tính lại sau Scale.' unless program_data
          program = DCFormulas::Program.new(program_data)
          inputs = Core.formula_values(program_data, program.controls).merge(values)
          frame=ConstructionFrame.fit(program_data,current,inputs)
          seed['formula_envelope']=frame if frame
          _original, old_guards = program.evaluate(inputs)
          bounds, new_guards = program.evaluate(inputs, frame || current['envelope'], frozen_parts: current['parts'])
          DCVisibility.compatible_guards!(old_guards,new_guards,DCVisibility.enabled?(program_data))
          visibility_updates = DCVisibility.pending(current,program.node_visibility)
          seed['parts'].each do |part|
            part['bounds'] = bounds.fetch(part['key'])
            part['visible'] = program.visibility.fetch(part['key'])
          end
          DCVisibility.apply_metadata!(seed,program.node_visibility)
        end
        result = RuleSystem.plan(rule, seed, values, previous_values: values)
        if engine
          EnvelopePolicy.input_axes(engine['attribute_program'],engine['envelope_policy']).each do |axis|
            unless 2.times.all? { |side| (result['envelope'][side][axis]-current['envelope'][side][axis]).abs<=Core::ENVELOPE_TOLERANCE }
              raise Core::Error,'Kích thước Scale nhỏ hơn độ dày / chi tiết cố định. Đã hủy thao tác.'
            end
          end
        end
        result['visibility_updates'] = (result.fetch('visibility_updates',[])+Array(visibility_updates)).uniq { |entry| [entry['part'],entry['depth']] }
        lookup = current['parts'].to_h { |part| [part['key'], part] }
        result['parts'] = result['parts'].map do |part|
          original = lookup.fetch(part['key'])
          DCVisibility.part_change(original,part['bounds'],part['visible']!=false,result['visibility_updates'])
        end
        reference = Array(engine&.dig('attribute_program', 'parts')).reject do |part|
          rule.fetch('part_formulas', {}).key?(part['key']) || rule.fetch('part_formula_parts', []).include?(part['key']) ||
            rule['constraints'].any? { |entry| entry['enabled'] && entry['drive'] && %w[face other third].any? { |key| entry.dig(key, 'part') == part['key'] } }
        end
        reference = (reference+ThicknessSymbols.merge_reference(rule)).uniq { |part| part['key'] }
        Core.validate_geometry_plan!(result['parts'], current, overlap_reference: reference,expected_envelope:result['envelope'])
        result['changed_count'] = result['parts'].count { |part| part['changed'] }
        result
      rescue KeyError
        raise Core::Error, 'Module thiếu thông số hoặc chi tiết để tính lại sau Scale.'
      end

    end
  end
end
