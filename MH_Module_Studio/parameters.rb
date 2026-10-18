# encoding: UTF-8
# One parent module owns all learned scalar rules and captured settings.
module MH
  module ModuleStudio
    module Core
      def learn_module(snapshots)
        raise Error, 'Đọc từ 1 đến 20 trạng thái của cùng module.' unless snapshots.is_a?(Array) && snapshots.length.between?(1, 20)
        snapshots = copy_data(snapshots)
        snapshots.each { |snapshot| snapshot!(snapshot) }
        choices = dc_thickness_parameters(snapshots)
        inventory = attribute_inventory(snapshots.last)
        rules = {}
        failures = {}
        attributes = nil
        attribute_error = nil
        begin
          attributes = attribute_rules(snapshots.last, choices)
          rules.merge!(attributes['rules'])
          failures.merge!(attributes['failures'])
        rescue Error => error
          attribute_error = error.message
          unless inventory['unknown_functions'].empty?
            attribute_error += " Hàm ATT chưa có định nghĩa được hỗ trợ: #{inventory['unknown_functions'].first(3).join(', ')}."
          end
        end
        choices.each do |choice|
          next if rules.key?(choice['dc_key'])
          begin
            rules[choice['dc_key']] = learn_dc_parameter(snapshots, choice['dc_key'])
            rules[choice['dc_key']]['rule_source'] = 'observations'
            rules[choice['dc_key']]['fallback_reason'] = failures[choice['dc_key']] || attribute_error || 'ATT chưa xác định được tác động đầy đủ của tham số này; dùng so sánh mẫu.'
          rescue Error => error
            failures[choice['dc_key']] = [failures[choice['dc_key']] || attribute_error, error.message].compact.join(' · ')
          end
        end
        if rules.empty?
          reason=attribute_error || failures.values.first || 'Không có đầu vào ATT điều khiển hình học đã xác minh.'
          raise Error,"Chưa tạo được quy tắc từ ATT: #{reason}. So sánh là phương án bổ sung; cần ít nhất hai trạng thái phù hợp."
        end
        context = {}
        rules.each_value do |rule|
          rule['control_context'].each do |key, control|
            next if rules.key?(key)
            if context[key] && !same_dc_value?(context[key]['value'], control['value'])
              raise Error, "#{control['label']}: các quy tắc có điều kiện cố định khác nhau, chưa thể gộp thành một module."
            end
            context[key] = control
          end
        end
        latest = snapshots.last
        controls = dc_controls(latest, choices.empty? ? 25.4 : choices.first['factor'])
        choices.each do |choice|
          controls[choice['dc_key']] ||= { 'label' => choice['label'], 'display_value' => choice['values'][latest['id']], 'unit' => 'mm' }
        end
        parameters = controls.map do |key, control|
          known = choices.any? { |choice| choice['dc_key'] == key }
          { 'key' => key, 'label' => control['label'], 'value' => control['display_value'], 'unit' => control['unit'],
            'options'=>DCOptions.choices(latest.fetch('dc_inputs',{}),key,control['unit']),
            'editable' => rules.key?(key), 'status' => rules.key?(key) ? 'learned' : known ? 'needs_samples' : 'fixed',
            'rule_source' => rules[key] && rules[key]['rule_source'],
            'input_range' => rules[key] && parameter_range(rules[key]),
            'reason' => rules[key] ? (rules[key]['fallback_reason'] || (rules[key]['recognition']=='conditional_dependency' ? ['Đã tìm thấy phụ thuộc ATT theo điều kiện; chưa xác minh được tác động ở các giá trị thăm dò.',rules[key]['recognition_diagnostic'],'Giá trị mới luôn được kiểm tra trước khi áp dụng.'].compact.join(' ') : 'Quy tắc lấy trực tiếp từ công thức ATT.')) : failures[key] || attribute_error || 'ATT chưa có công thức hình học cho thông số này.' }
        end
        control_order = controls.keys.each_with_index.to_h
        parameters.sort_by! { |parameter| [parameter['editable'] ? 0 : parameter['label'].match?(/hậu|back/i) ? 1 : 2, control_order.fetch(parameter['key'])] }
        parts = rules.values.first['parts'].map do |part|
          owner = rules.find { |_key, rule| rule['parts'].any? { |entry| entry['key'] == part['key'] && entry['driver'] } }
          owner ? owner[1]['parts'].find { |entry| entry['key'] == part['key'] }.merge('parameter_key' => owner[0]) : part
        end
        relations = rules.flat_map do |key, rule|
          rule['relations'].map { |relation| relation.merge('parameter_key' => key, 'parameter_label' => rule['parameter_label']) }
        end
        bundle = { 'format' => FORMAT, 'version' => 1, 'kind' => 'module_parameter_set', 'id' => Ids.uuid,
                   'parameter_label' => dc_label(latest.dig('dc_inputs', '_name') || 'Module'),
                   'parameters' => parameters, 'rules' => rules, 'control_context' => context,
                   'parts' => parts, 'relations' => relations, 'sample_count' => snapshots.length,
                   'envelope' => latest['envelope'], 'warnings' => [
                     'Ưu tiên công thức ATT. Chỉ dùng so sánh mẫu khi ATT thiếu hoặc chưa dịch được.',
                     attribute_error || 'Công thức ATT được tính lại cho giá trị mới; chỉ tác động hình học sau khi kiểm tra phủ bì và giao tấm.'
                   ] }
        if attributes
          bundle['attribute_program'] = attributes['program']
          bundle['attribute_formulas'] = attributes['formulas']
          bundle['envelope_policy'] = attributes['envelope_policy']
        else
          bundle['attribute_formulas'] = inventory['formulas']
        end
        bundle['attribute_formula_count'] = inventory['count']
        bundle['attribute_unsupported_functions'] = inventory['unknown_functions']
        bundle['attribute_diagnostic'] = attribute_error
        validate_module_evidence!(bundle, snapshots, choices)
        parameter_set!(bundle)
      end

      def validate_module_evidence!(bundle, snapshots, choices)
        usable = snapshots.select do |snapshot|
          attributes = snapshot['dc_inputs'] || {}
          bundle['control_context'].all? { |key, control| attributes.key?(key) && same_dc_value?(dc_value(attributes[key]), control['value']) }
        end
        baseline = usable.first
        raise Error, 'Không có mẫu khớp các điều kiện cố định của module.' unless baseline
        choices = choices.to_h { |choice| [choice['dc_key'], choice] }
        base_parts = baseline['parts'].to_h { |part| [part['key'], part] }
        coefficients = bundle['rules'].transform_values { |rule| rule['parts'].to_h { |part| [part['key'], part] } }
        observed = []
        usable.each do |snapshot|
          values = bundle['rules'].keys.to_h do |key|
            factor = dc_controls(snapshot).dig(key,'value_factor') || 1.0
            [key, choices.key?(key) ? choices[key]['values'].fetch(snapshot['id']) : number(snapshot.fetch('dc_inputs').fetch(key)) * factor]
          end
          base_values = values.keys.to_h do |key|
            factor = dc_controls(baseline).dig(key,'value_factor') || 1.0
            [key, choices.key?(key) ? choices[key]['values'].fetch(baseline['id']) : number(baseline.fetch('dc_inputs').fetch(key)) * factor]
          end
          deltas = values.to_h { |key, value| [key, value - base_values.fetch(key)] }
          formula_changes = formula_delta(bundle, baseline, base_values, values)
          unless snapshot['parts'].map { |part| part['key'] }.sort == base_parts.keys.sort
            raise Error, 'Các mẫu không cùng cấu trúc module.'
          end
          snapshot['parts'].each do |part|
            2.times do |side|
              3.times do |axis|
                prediction = base_parts[part['key']]['bounds'][side][axis] + (formula_changes.dig(part['key'], side, axis) || 0) + deltas.sum do |key, delta|
                  bundle['rules'][key]['kind'] == 'dc_formula_rule' ? 0 : coefficients[key].fetch(part['key'])['coefficients'][side][axis]['slope'] * delta
                end
                if (prediction - part['bounds'][side][axis]).abs > TOLERANCE
                  raise Error, "#{part['name']}: tổ hợp tham số chưa khớp các mẫu. Có tương tác hoặc nhánh điều kiện cần khảo sát thêm."
                end
              end
            end
          end
          observed << values
        end
        bundle['observed_parameter_values'] = observed
        bundle['training_sample_ids'] = usable.map { |snapshot| snapshot['id'] }
      end

      def parameter_set!(bundle)
        unless bundle['format'] == FORMAT && bundle['version'] == 1 && bundle['rules'].is_a?(Hash) && bundle['rules'].length.between?(1, MAX_PARTS)
          raise Error, 'Bộ tham số module không hợp lệ.'
        end
        unless bundle['parameters'].is_a?(Array) && bundle['parameters'].length.between?(1, MAX_PARTS)
          raise Error, 'Danh sách tham số module không hợp lệ.'
        end
        keys = bundle['parameters'].map do |parameter|
          unless parameter.is_a?(Hash) && parameter['key'].is_a?(String) && parameter['key'].length.between?(1, 200) &&
                 parameter['label'].is_a?(String) && [true, false].include?(parameter['editable'])
            raise Error, 'Thông số module bị hỏng.'
          end
          if parameter['editable']
            parameter['value'] = number(parameter['value'])
            limits = parameter_range(bundle['rules'].fetch(parameter['key']))
            parameter['input_range'] = limits.dup if bundle['rules'][parameter['key']]['kind']=='dc_formula_rule'
            raise Error, 'Giá trị mẫu trong bộ tham số không hợp lệ.' unless parameter['value'].between?(*limits)
          end
          parameter['key']
        end
        raise Error, 'Thông số module bị trùng.' unless keys.uniq.length == keys.length
        editable = bundle['parameters'].select { |parameter| parameter['editable'] }.map { |parameter| parameter['key'] }.sort
        raise Error, 'Thông số điều khiển không khớp quy tắc.' unless editable == bundle['rules'].keys.sort
        bundle['exposed_parameter_keys'] = editable.dup unless bundle.key?('exposed_parameter_keys')
        exposed = bundle['exposed_parameter_keys']
        unless exposed.is_a?(Array) && exposed.all? { |key| key.is_a?(String) && keys.include?(key) } && exposed.uniq.length == exposed.length
          raise Error, 'Lựa chọn tham số đi cùng module không hợp lệ.'
        end
        reference_keys = nil
        policy_program = nil
        bundle['rules'].each do |key, rule|
          raise Error, 'Không được lồng một bộ module khác vào quy tắc.' unless rule.is_a?(Hash) && %w[linear_thickness_rule dc_formula_rule].include?(rule['kind'])
          raise Error, 'Mã tham số DC không khớp quy tắc.' unless rule.dig('dc_parameter', 'dc_key') == key
          rule!(rule, formula_nested: true)
          part_keys = rule['parts'].map { |part| part['key'] }.sort
          reference_keys ||= part_keys
          raise Error, 'Các quy tắc không cùng cấu trúc module.' unless part_keys == reference_keys
          if rule['kind'] == 'dc_formula_rule'
            program = policy_program ||= DCFormulas::Program.new(bundle.fetch('attribute_program'))
            unless reference_keys == bundle['attribute_program']['parts'].map { |part| part['key'] }.sort && program.controls[key] && (program.controls[key]['unit'] == 'mm' || DCVisibility.enabled?(bundle['attribute_program']) || bundle['attribute_program']['copies_version']==1)
              raise Error, 'Chương trình ATT không khớp tham số module.'
            end
          end
        end
        if policy_program
          bundle['envelope_policy'] = EnvelopePolicy.reconcile(bundle['envelope_policy'],EnvelopePolicy.derive(bundle['attribute_program'],policy_program))
        elsif bundle['envelope_policy']
          raise Error,'Kích thước phụ thuộc thiếu chương trình ATT.'
        end
        context = bundle['control_context']
        unless context.is_a?(Hash) && context.length <= MAX_PARTS && context.all? do |key, control|
          key.is_a?(String) && control.is_a?(Hash) && control['label'].is_a?(String) &&
            (control['value'].is_a?(String) || control['value'].is_a?(Numeric)) && !editable.include?(key)
        end
          raise Error, 'Điều kiện cố định của module không hợp lệ.'
        end
        bundle['warnings'] = Array(bundle['warnings']).first(20).map(&:to_s)
        bundle['parameter_label'] = bundle['parameter_label'].to_s[0, 120]
        bundle['parts'] = bundle['rules'].values.first['parts'].map do |part|
          owner = bundle['rules'].find { |_key, rule| rule['parts'].any? { |entry| entry['key'] == part['key'] && entry['driver'] } }
          owner ? owner[1]['parts'].find { |entry| entry['key'] == part['key'] }.merge('parameter_key' => owner[0]) : part
        end
        bundle['relations'] = bundle['rules'].flat_map do |key, rule|
          rule['relations'].map { |relation| relation.merge('parameter_key' => key, 'parameter_label' => rule['parameter_label']) }
        end
        observed = bundle['observed_parameter_values']
        unless observed.is_a?(Array) && observed.length.between?(1, 20) && observed.all? do |values|
          values.is_a?(Hash) && values.keys.sort == editable && values.all? { |key, value| number(value).between?(*parameter_range(bundle['rules'][key])) }
        end
          raise Error, 'Các tổ hợp tham số đã khảo sát không hợp lệ.'
        end
        bundle
      rescue NoMethodError, KeyError, TypeError
        raise Error, 'Bộ tham số module thiếu dữ liệu hoặc hỏng cấu trúc.'
      end

      def parameter_values(bundle, current)
        return DCCopies.values(bundle,current) if DCCopies.enabled?(bundle)
        lookup = current['parts'].to_h { |part| [part['key'], part] }
        bundle['rules'].to_h do |key, rule|
          unless lookup.keys.sort == rule['parts'].map { |part| part['key'] }.sort
            raise Error, 'Module đang chọn không khớp bộ tham số.'
          end
          if rule['kind'] == 'dc_formula_rule'
            saved = current['parameter_values'] || {}
            value = if current.fetch('dc_inputs', {}).key?(key)
                      number(current['dc_inputs'][key]) * dc_controls(bundle['attribute_program']).fetch(key,{}).fetch('value_factor',1.0)
                    elsif saved.key?(key)
                      number(saved[key])
                    else
                      raise Error, "#{rule['parameter_label']}: bản thường chưa có giá trị ATT. Tạo bản thử từ module nguồn trước."
                    end
            next [key, value]
          end
          values = rule['parts'].select { |part| part['driver'] }.map do |part|
            dimensions(lookup.fetch(part['key'])['bounds'])[part['thickness_axis']]
          end
          raise Error, "#{rule['parameter_label']}: các tấm điều khiển có độ dày khác nhau." if values.max - values.min > TOLERANCE
          [key, values.sum / values.length]
        end
      end

      def set_exposed_parameters!(bundle, keys)
        rule!(bundle)
        valid_keys = bundle['parameters'].map { |parameter| parameter['key'] }
        unless keys.is_a?(Array) && keys.all? { |key| key.is_a?(String) && valid_keys.include?(key) } && keys.uniq.length == keys.length
          raise Error, 'Lựa chọn tham số đi cùng module không hợp lệ.'
        end
        bundle['exposed_parameter_keys'] = valid_keys.select { |key| keys.include?(key) }
        bundle.fetch('parametric_variables', []).each do |row|
          row['exported'] = keys.include?(row['binding']) if row['binding']
        end
        bundle
      end

      def exposed_parameters(bundle, values = {})
        rule!(bundle)
        definitions = bundle.key?('parametric_variables') ? Parametric.variables(bundle).select { |r| r['binding'] }.to_h { |r| [r['binding'], r] } : {}
        rows = bundle['parameters'].select { |parameter| bundle['exposed_parameter_keys'].include?(parameter['key']) }.map do |parameter|
          own = definitions[parameter['key']]
          entry = parameter.slice('key', 'label', 'unit').merge(
            'value' => values.fetch(parameter['key'], parameter['value']),
            'can_edit' => parameter['editable'] && (!own || own['formula'].empty?),
            'rule_key' => parameter['editable'] ? parameter['key'] : nil,
            'status' => parameter['editable'] ? 'ready' : 'needs_rule'
          )
          entry.merge!('label' => own['name'], 'symbol' => own['symbol'], 'category' => own['category'], 'formula' => own['formula']) if own
          entry
        end
        rows += Parametric.exposed_custom_variables(bundle) if bundle.key?('parametric_variables')
        rows
      end

      def plan_parameters(bundle, current, requested)
        return DCCopies.plan(bundle,current,requested) if DCCopies.needed?(bundle,current,requested)
        parameter_set!(bundle)
        snapshot!(current)
        check_dc_context!(bundle, current)
        raise Error, 'Cần nhập các giá trị của bộ tham số module.' unless requested.is_a?(Hash)
        unknown = requested.keys - bundle['rules'].keys
        raise Error, 'Có thông số chưa được học hoặc không thuộc module.' unless unknown.empty?
        previous = parameter_values(bundle, current)
        targets = previous.merge(requested.transform_values { |value| number(value) })
        targets.each do |key, value|
          limits = parameter_range(bundle['rules'][key])
          raise Error, "#{bundle['rules'][key]['parameter_label']}: giá trị phải trong khoảng #{limits.join('–')} mm." unless value.between?(*limits)
        end
        delta = targets.to_h { |key, value| [key, value - previous.fetch(key)] }
        coefficients = bundle['rules'].transform_values { |rule| rule['parts'].to_h { |part| [part['key'], part] } }
        lookup = current['parts'].to_h { |part| [part['key'], part] }
        formula_state = formula_result(bundle, current, previous, targets)
        formula_changes = formula_state['delta']
        expected_envelope = formula_state.fetch('envelope',current['envelope'])
        bundle['rules'].each_value do |rule|
          rule['relations'].each do |relation|
            gap = lookup[relation['follower']]['bounds'][relation['follower_side']][relation['axis']] - lookup[relation['leader']]['bounds'][relation['leader_side']][relation['axis']]
            raise Error, 'Quan hệ lắp ghép đã khác mẫu. Đọc lại module trước khi áp dụng.' if (gap - relation['gap_mm']).abs > 0.5
          end
        end
        changes = current['parts'].map do |part|
          bounds = 2.times.map do |side|
            3.times.map do |axis|
              part['bounds'][side][axis] + (formula_changes.dig(part['key'], side, axis) || 0) + delta.sum do |key, value|
                bundle['rules'][key]['kind'] == 'dc_formula_rule' ? 0 : coefficients[key][part['key']]['coefficients'][side][axis]['slope'] * value
              end
            end
          end
          DCVisibility.part_change(part,bounds,formula_state['visibility'].fetch(part['key'],part['visible']!=false),formula_state['visibility_updates'])
        end
        reference = Array(bundle.dig('attribute_program', 'parts')).reject { |part| Array(bundle['own_override_parts']).include?(part['key']) }
        validate_geometry_plan!(changes, current, overlap_reference: reference,expected_envelope:expected_envelope) unless bundle['defer_geometry_validation']
        outside = targets.any? { |key, value| value < bundle['rules'][key]['sample_range'][0] || value > bundle['rules'][key]['sample_range'][1] }
        observed = Array(bundle['observed_parameter_values']).any? do |values|
          targets.all? { |key, value| values.key?(key) && (number(values[key]) - value).abs <= 0.02 }
        end
        { 'multi_parameter' => true, 'previous' => previous, 'target' => targets, 'delta' => delta,
          'parameter_labels' => bundle['rules'].transform_values { |rule| rule['parameter_label'] },
          'parts' => changes, 'changed_count' => changes.count { |part| part['changed'] }, 'envelope' => expected_envelope,
          'formula_envelope'=>formula_state['formula_envelope'],
          'visibility_updates'=>formula_state['visibility_updates'], 'visibility_capable'=>DCVisibility.enabled?(bundle.fetch('attribute_program',{})),
          'outside_sample_range' => outside, 'combination_unverified' => delta.values.count { |value| value.abs > 0.001 } > 1 && !observed }
      end

      def validate_geometry_plan!(changes, current, overlap_reference: [],expected_envelope: nil)
        new_bounds = union(changes)
        old_bounds = expected_envelope || union(current['parts'])
        unless 2.times.all? { |side| 3.times.all? { |axis| (new_bounds[side][axis] - old_bounds[side][axis]).abs <= ENVELOPE_TOLERANCE } }
          raise Error, 'Kết quả làm thay đổi phủ bì. Không áp dụng bộ quy tắc này.'
        end
        reference = overlap_reference.to_h { |part| [part['key'], part] }
        changes.combination(2) do |a, b|
          next unless (a['changed'] || b['changed']) && a['box_verified'] && b['box_verified'] && a['visible'] != false && b['visible'] != false
          overlap = lambda { |left, right| 3.times.map { |axis| [left[1][axis], right[1][axis]].min - [left[0][axis], right[0][axis]].max } }
          # A verified ATT groove joint can disappear at depth zero and return.
          # Only pairs intersecting in the imported geometry qualify; own edits
          # and previously unrelated pairs keep the existing collision check.
          source_a, source_b = reference.values_at(a['key'], b['key'])
          next if source_a && source_b && source_a['visible'] != false && source_b['visible'] != false && overlap.call(source_a['bounds'], source_b['bounds']).all? { |size| size > TOLERANCE }
          previous_overlap = a['old_visible']!=false && b['old_visible']!=false && overlap.call(a['old_bounds'], b['old_bounds']).all? { |size| size > TOLERANCE }
          if overlap.call(a['bounds'], b['bounds']).all? { |size| size > TOLERANCE } && !previous_overlap
            raise Error, "Kết quả làm #{a['name']} giao vào #{b['name']}. Cần kiểm tra lại quan hệ."
          end
        end
      end
    end
  end
end
