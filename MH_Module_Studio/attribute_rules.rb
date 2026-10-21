# encoding: UTF-8
require_relative 'formulas'
require_relative 'envelope_policy'

module MH
  module ModuleStudio
    module Core
      def capture_parameter!(snapshot, multiple: false)
        choices = dc_thickness_parameters([snapshot])
        if choices.empty?
          begin
            use_measured_parameter!(snapshot)
          rescue Error
            raise unless multiple
            measured = snapshot['parts'].select { |part| part['visible'] != false && part['thickness_axis'] }.map do |part|
              dimensions(part['bounds'])[part['thickness_axis']]
            end
            raise Error, 'Không tìm thấy tấm có độ dày để tạo tham số.' if measured.empty?
            snapshot['parameter'] = measured.max
            snapshot['parameter_source'] = { 'kind' => 'geometry_parameter_set', 'values' => measured.uniq.sort }
            snapshot
          end
        else
          representative = choices.max_by { |choice| choice['part_keys'].length }
          snapshot['parameter'] = representative['values'].fetch(snapshot['id'])
          snapshot['parameter_source'] = { 'kind' => 'dc_parameter_set', 'dc_keys' => choices.map { |choice| choice['dc_key'] } }
          snapshot
        end
      end

      def attribute_inventory(snapshot, limit: 120)
        nodes = [{ 'path' => [], 'attributes' => snapshot['dc_inputs'] || {} }]
        nodes += snapshot.dig('dc_graph', 'nodes') || snapshot['parts'].map { |part| { 'path' => [part['key']], 'attributes' => part['dc_attributes'] || {} } }
        formulas = nodes.flat_map do |node|
          node.fetch('attributes', {}).filter_map do |key, value|
            attribute = key.to_s[/\A_(.+)_formula\z/i, 1]
            next unless attribute && value.is_a?(String) && !value.strip.empty?
            { 'path' => node.fetch('path', []).join(' / '), 'attribute' => attribute, 'formula' => value[0, 4096], 'translated' => false }
          end
        end
        unknown = formulas.flat_map { |entry| entry['formula'].scan(/\b([a-z_][a-z_0-9]*)\s*\(/i).flatten.map(&:downcase) }.uniq - DCFormulas::FUNCTIONS - DCFormulas.function_aliases(snapshot).keys
        { 'formulas' => limit ? formulas.first(limit) : formulas, 'count' => formulas.length, 'unknown_functions' => unknown.sort.first(20) }
      end

      def formula_values(snapshot, controls)
        controls.select { |_key, control| (control['unit'] == 'mm' || control['source']=='custom_constant' || DCVisibility.enabled?(snapshot) || snapshot['copies_version']==1) && control['display_value'].is_a?(Numeric) }
                .transform_values { |control| control['display_value'] }
      end

      def attribute_rules(snapshot, choices)
        snapshot = DCCopies.enable(snapshot)
        program = DCFormulas::Program.new(snapshot)
        controls = program.controls
        values = formula_values(snapshot, controls)
        baseline, guards = program.evaluate(values)
        baseline_visible = program.visibility.dup
        unless snapshot['parts'].all? { |part| baseline_visible[part['key']]==(part['visible']!=false) }
          raise Error,'Trạng thái ẩn/hiện hiện tại khác công thức ATT; đọc lại DC đã cập nhật.'
        end
        snapshot['parts'].each do |part|
          unless bounds_close?(baseline.fetch(part['key']), part['bounds'])
            raise Error, "#{part['name']}: công thức ATT chưa khớp hình học hiện tại; không dùng giá trị cache để đoán."
          end
        end
        formulas = program.formulas.uniq.map { |entry| entry.merge('translated' => true) }
        raise Error, 'ATT chưa có công thức hình học dùng được.' if formulas.empty?
        rules = {}
        failures = {}
        dependencies = program.input_dependencies
        values.each do |key, value|
          next if DCFormulas::LENGTHS.include?(key)
          begin
            choice = choices.find { |entry| entry['dc_key'] == key }
            range = choice ? [0.2, 10_000.0] : [value.negative? ? -10_000.0 : 0.0, 10_000.0]
            dependency = dependencies[key] || {'types'=>[],'probes'=>[]}
            copy_input = snapshot['copies_version']==1 && DCCopies.input_keys(snapshot).include?(key)
            potential = (dependency['types'] & %w[geometry visibility]).any? || copy_input
            unless potential
              failures[key] = dependency['types'].include?('structure') ? 'Tham số chỉ đổi số lượng hoặc góc xoay; chưa hỗ trợ.' : 'Không tìm thấy phụ thuộc hình học/ẩn hiện trong công thức ATT.'
              next
            end
            after = nil; probe = nil; activated = false; error_message = nil
            probes = DCFormulas::Dependencies.probes(value,dependency['probes'],range)
            probes = [value+1,value-1]+probes if copy_input
            probes.select { |candidate| candidate.between?(*range) }.each do |candidate|
              begin
                trial, new_guards = program.evaluate(values.merge(key=>candidate))
                DCCopies.compatible!(snapshot,guards,new_guards)
                after ||= trial; probe ||= candidate
                activated = snapshot['parts'].any? do |part|
                  baseline_visible[part['key']]!=program.visibility[part['key']] || !bounds_close?(baseline.fetch(part['key']),trial.fetch(part['key']),0.00001)
                end
                if activated
                  after = trial; probe = candidate; break
                end
              rescue Error => error
                error_message = error.message
              end
            end
            verified_probe = !after.nil?
            if after.nil? && DCVisibility.enabled?(snapshot) && !dependency['types'].include?('structure')
              # A visibility selector may require another input first (for
              # example a positive foot height). Retain its AST dependency,
              # disclose unverified activation and validate the actual request.
              after = baseline; probe = value+1.0
            end
            unless after && (activated || potential)
              failures[key] = error_message || 'Không tìm thấy phụ thuộc hình học/ẩn hiện trong công thức ATT.'
              next
            end
            parts = snapshot['parts'].map do |part|
              coefficients = 2.times.map do |side|
                3.times.map do |axis|
                  slope = (after[part['key']][side][axis] - baseline[part['key']][side][axis]) / (probe-value)
                  { 'slope' => slope, 'intercept' => part['bounds'][side][axis] - slope * value, 'error' => 0.0 }
                end
              end
              { 'key' => part['key'], 'name' => part['name'], 'thickness_axis' => part['thickness_axis'],
                'driver' => !!(choice && choice['part_keys'].include?(part['key'])), 'coefficients' => coefficients,
                'base_bounds' => part['bounds'], 'max_error' => 0.0 }
            end
            rules[key] = { 'format' => FORMAT, 'version' => 1, 'kind' => 'dc_formula_rule', 'id' => Ids.uuid,
                           'rule_source' => 'dc_attributes', 'parameter_label' => controls[key]['label'],
                           'sample_count' => 1, 'distinct_samples' => 1, 'sample_range' => range, 'input_range' => range,
                           'base_parameter' => value, 'envelope' => snapshot['envelope'], 'parts' => parts,
                           'recognition'=>activated ? 'probed_dependency' : 'conditional_dependency', 'probe_value'=>verified_probe ? probe : nil,
                           'recognition_diagnostic'=>activated ? nil : error_message,
                           'relations' => [], 'status' => 'dc_attributes', 'warnings' => [],
                           'dc_parameter' => { 'dc_key' => key, 'factor' => 25.4 },
                           'control_context' => controls.reject { |name, _control| name == key } }
          rescue Error => error
            failures[key] = error.message
          end
        end
        raise Error, 'ATT chưa xác định được tham số chiều dài có tác động lên hình học.' if rules.empty?
        { 'rules' => rules, 'failures' => failures, 'program' => snapshot, 'formulas' => formulas,
          'envelope_policy'=>EnvelopePolicy.derive(snapshot,program) }
      end

      def bounds_close?(a, b, tolerance = TOLERANCE)
        2.times.all? { |side| 3.times.all? { |axis| (a[side][axis] - b[side][axis]).abs <= tolerance } }
      end

      def formula_delta(bundle, current, previous, targets)
        formula_result(bundle,current,previous,targets)['delta']
      end

      def formula_result(bundle, current, previous, targets)
        keys = bundle['rules'].select { |_key, rule| rule['kind'] == 'dc_formula_rule' }.keys
        return {'delta'=>{},'visibility'=>{},'visibility_updates'=>[]} if keys.empty?
        program = DCFormulas::Program.new(bundle.fetch('attribute_program'))
        input_envelope = EnvelopePolicy.inputs(current,bundle['attribute_program'],bundle['envelope_policy'])
        values = formula_values(bundle['attribute_program'], program.controls).merge(previous)
        before, guards = program.evaluate(values, input_envelope, frozen_parts: current['parts'])
        old_visible = program.visibility.dup
        after, target_guards = program.evaluate(values.merge(targets.slice(*keys)), input_envelope, frozen_parts: current['parts'])
        DCVisibility.compatible_guards!(guards,target_guards,DCVisibility.enabled?(bundle['attribute_program']))
        current['parts'].each do |part|
          next if Array(bundle['own_override_parts']).include?(part['key'])
          raise Error,"#{part['name']}: trạng thái ẩn/hiện khác quy tắc; đọc lại module." unless old_visible[part['key']]==(part['visible']!=false)
          unless bounds_close?(before.fetch(part['key']), part['bounds'])
            raise Error, "#{part['name']}: hình học hiện tại khác công thức ATT. Đọc lại module trước khi sửa."
          end
        end
        root_meshes=Array(bundle.dig('attribute_program','dc_graph','nodes')).select { |node| node['virtual_root_mesh'] }.map { |node| node['part_key'] }
        delta = after.to_h do |key, bounds|
          exact = Array(bundle['own_cell_parts']).include?(key) || (root_meshes.include?(key) && !Array(bundle['own_override_parts']).include?(key))
          origin = exact ? current['parts'].find { |part| part['key'] == key }['bounds'] : before[key]
          [key, 2.times.map { |side| 3.times.map { |axis| bounds[side][axis] - origin[side][axis] } }]
        end
        target_parts = after.map { |key,bounds| {'key'=>key,'bounds'=>bounds} }
        axes = EnvelopePolicy.input_axes(bundle['attribute_program'],bundle['envelope_policy'])
        envelope = EnvelopePolicy.target(current['envelope'],target_parts,bundle['envelope_policy'],program,
          input_axes:axes,inputs:input_envelope,drivers:EnvelopePolicy.thickness_parts(bundle))
        logical = Core.copy_data(program.construction_inputs ? input_envelope : envelope)
        axes.each { |axis| 2.times { |side| logical[side][axis] = input_envelope[side][axis] } }
        {'delta'=>delta,'visibility'=>program.visibility.dup,'visibility_updates'=>DCVisibility.pending(current,program.node_visibility),
          'formula_envelope'=>logical,'envelope'=>envelope}
      end

      def parameter_range(rule)
        return [0.2,100.0] unless rule['kind']=='dc_formula_rule'
        range = rule.fetch('input_range')
        range==[0.2,100.0] ? [0.2,10_000.0] : range
      end
    end
  end
end
