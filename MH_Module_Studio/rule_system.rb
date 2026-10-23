# encoding: UTF-8
require_relative 'plane_solver'
require_relative 'position_rules'
require_relative 'parametric'

module MH
  module ModuleStudio
    module RuleSystem
      extend self
      KIND = 'module_rule_system'.freeze
      TYPES = %w[thickness fix contact offset align between center formula position].freeze

      def face(key, axis, side)
        { 'part' => key, 'axis' => axis, 'side' => side }
      end

      def constraint(type, source, **fields)
        { 'id' => Core::Ids.uuid, 'type' => type, 'source' => source, 'enabled' => true,
          'drive' => true }.merge(fields.transform_keys(&:to_s))
      end

      def build(snapshot, engine = nil, static_geometry: false)
        snapshot = Core.copy_data(snapshot)
        engine = Core.copy_data(engine) if engine
        Core.snapshot!(snapshot)
        parts = snapshot['parts'].map do |part|
          part.merge('base_bounds' => part['bounds'], 'driver' => false)
        end
        parameters = engine ? Marshal.load(Marshal.dump(engine['parameters'])) : []
        constraints = []
        unless engine || static_geometry
          groups = parts.select { |part| part['visible'] != false && part['thickness_axis'] }.group_by do |part|
            (Core.dimensions(part['bounds'])[part['thickness_axis']] * 50).round
          end
          groups.sort_by { |value, _items| -value }.each_with_index do |(_value, items), index|
            key = "thickness_#{index + 1}"
            value = Core.dimensions(items.first['bounds'])[items.first['thickness_axis']]
            parameters << { 'key' => key, 'label' => "Độ dày #{Core.number(value).round(2)} mm", 'unit' => 'mm',
                            'value' => value, 'editable' => true, 'rule_source' => 'geometry', 'input_range' => [0.2, 100.0] }
            items.each do |part|
              axis = part['thickness_axis']
              anchor = if (part['bounds'][0][axis] - snapshot['envelope'][0][axis]).abs <= Core::TOLERANCE
                         'low'
                       elsif (part['bounds'][1][axis] - snapshot['envelope'][1][axis]).abs <= Core::TOLERANCE
                         'high'
                       else
                         'center'
                       end
              constraints << constraint('thickness', 'geometry', face: face(part['key'], axis, 0),
                                        parameter: key, anchor: anchor, label: part['name'])
            end
          end
        end
        parts.select { |part| part['visible'] != false }.combination(2) do |a, b|
          next unless a['box_verified'] && b['box_verified']
          3.times do |axis|
            next unless ((0..2).to_a - [axis]).all? do |other|
              [a['bounds'][1][other], b['bounds'][1][other]].min - [a['bounds'][0][other], b['bounds'][0][other]].max > 0.5
            end
            2.times do |side|
              gap = b['bounds'][1 - side][axis] - a['bounds'][side][axis]
              next if gap.abs > Core::TOLERANCE
              leader, follower, leader_side = a, b, side
              if b['thickness_axis'] == axis && a['thickness_axis'] != axis
                leader, follower, leader_side = b, a, 1 - side
              end
              constraints << constraint('contact', 'geometry', face: face(leader['key'], axis, leader_side),
                                        other: face(follower['key'], axis, 1 - leader_side), gap: 0.0,
                                        drive: !engine, label: "#{leader['name']} → #{follower['name']}")
            end
          end
        end
        if engine
          engine.fetch('attribute_formulas', []).each do |formula|
            constraints << constraint('formula', 'dc_attributes', label: "#{formula['path']} · #{formula['attribute']}",
                                      formula: formula['formula'], translated: formula['translated'], drive: false)
          end
          engine['rules'].each do |key, rule|
            next unless rule['kind'] == 'linear_thickness_rule'
            constraints << constraint('formula', 'observations', label: "So sánh mẫu · #{rule['parameter_label']}",
                                      formula: "Δ mặt = hệ số đã học × Δ #{rule['parameter_label']}; #{rule['sample_count']} trạng thái, #{rule['sample_range'].join('–')} mm.",
                                      engine_key: key, translated: true, drive: false)
          end
        else
          Core.dc_controls(snapshot).sort.each do |key, control|
            symbol=DCCustomAttributes.symbol(key,parameters.map { |param| param['key'] })
            parameters << { 'key' => symbol, 'dc_key' => key, 'label' => control['label'],
                            'options'=>DCOptions.choices(snapshot.fetch('dc_inputs',{}),key,control['unit']),
                            'value' => control['display_value'], 'unit' => control['unit'], 'editable' => false,
                            'rule_source' => 'dc_attributes', 'reason' => 'Đã đọc ATT; chưa có công thức dùng được cho đầu vào này.' }
          end
        end
        bundle = { 'format' => Core::FORMAT, 'version' => 1, 'kind' => KIND, 'id' => engine ? engine['id'] : Core::Ids.uuid,
                   'parts' => parts, 'envelope' => snapshot['envelope'], 'parameters' => parameters,
                   'constraints' => constraints, 'formula_engine' => engine,
                   'exposed_parameter_keys' => engine ? engine['exposed_parameter_keys'] : parameters.select { |p| p['editable'] }.map { |p| p['key'] },
                   'warnings' => engine ? engine['warnings'] : ['Quan hệ từ một trạng thái là đề xuất; kiểm tra hướng và mặt trước khi áp dụng.'],
                   'rules' => engine ? engine['rules'] : {}, 'relations' => [],
                   'attribute_formulas' => engine ? engine.fetch('attribute_formulas', []) : [],
                   'control_context' => engine && engine['control_context'] }
        bundle['static_geometry']=true if static_geometry
        DCCustomAttributes.append!(bundle,snapshot) if snapshot['custom_attributes_version']==1
        validate!(bundle)
      end

      def migrate(snapshot, rule)
        return validate!(rule) if rule['kind'] == KIND
        return build(snapshot, rule) if rule['kind'] == 'module_parameter_set'
        Core.rule!(rule)
        scalar = Marshal.load(Marshal.dump(rule))
        key = scalar.dig('dc_parameter', 'dc_key') || 'thickness'
        scalar['dc_parameter'] ||= { 'dc_key' => key, 'factor' => 1.0 }
        scalar['rule_source'] = 'observations'
        values = scalar['parts'].select { |p| p['driver'] }.map do |driver|
          part = snapshot['parts'].find { |p| p['key'] == driver['key'] }
          raise Core::Error, 'Mẫu không khớp quy tắc cũ.' unless part
          Core.dimensions(part['bounds'])[driver['thickness_axis']]
        end
        parameter = { 'key' => key, 'label' => scalar['parameter_label'], 'unit' => 'mm', 'value' => values.sum / values.length,
                      'editable' => true, 'input_range' => [0.2, 100.0], 'rule_source' => 'observations' }
        engine = { 'format' => Core::FORMAT, 'version' => 1, 'kind' => 'module_parameter_set', 'id' => scalar['id'],
                   'parameter_label' => scalar['parameter_label'], 'parameters' => [parameter], 'rules' => { key => scalar },
                   'control_context' => scalar['control_context'] || {}, 'envelope' => scalar['envelope'],
                   'parts' => scalar['parts'], 'relations' => scalar['relations'], 'warnings' => scalar['warnings'],
                   'observed_parameter_values' => [{ key => scalar['base_parameter'] }] }
        build(snapshot, Core.parameter_set!(engine))
      end

      def validate!(bundle)
        raise Core::Error, 'Không phải hệ quy tắc module v1.' unless bundle.is_a?(Hash) && bundle['format'] == Core::FORMAT && bundle['version'] == 1 && bundle['kind'] == KIND
        DCCopies.upgrade!(bundle)
        Core.snapshot!({ 'parts' => bundle.fetch('parts').map { |part| part.merge('bounds' => part.fetch('base_bounds')) }, 'envelope' => bundle.fetch('envelope') })
        engine = bundle['formula_engine']
        ImportTemplate.validate(bundle['import_template']) if bundle['import_template']
        Core.parameter_set!(engine) if engine
        keys = bundle['parts'].map { |part| part['key'] }
        raise Core::Error, 'Khóa chi tiết phải là chuỗi.' unless keys.all? { |key| key.is_a?(String) }
        raise Core::Error, 'Cây ATT không khớp hệ quy tắc.' if engine && engine['parts'].map { |p| p['key'] }.sort != keys.sort
        params = bundle.fetch('parameters')
        minimum=bundle['static_geometry']==true && !engine ? 0 : 1
        raise Core::Error, 'Danh sách tham số không hợp lệ.' unless params.is_a?(Array) && params.length.between?(minimum, Core::MAX_PARTS) && params.map { |p| p['key'] }.uniq.length == params.length
        raise Core::Error, 'Tham số ATT không khớp hệ quy tắc.' if engine && params.map { |p| p['key'] }.sort != engine['parameters'].map { |p| p['key'] }.sort
        bundle['rules'] = engine ? engine['rules'] : {}
        params.each do |param|
          raise Core::Error, 'Khóa tham số không hợp lệ.' unless param['key'].is_a?(String) && param['key'].length.between?(1, 200)
          raise Core::Error, 'Mô tả tham số không hợp lệ.' unless param['label'].is_a?(String) && [true, false].include?(param['editable']) && param['unit'].is_a?(String)
          next unless param['editable']
          if engine && engine.dig('rules',param['key'],'kind')=='dc_formula_rule'
            param['input_range'] = Core.parameter_range(engine['rules'][param['key']]).dup
          end
          limits = param.fetch('input_range', [0.2, 100.0]).map { |v| Core.number(v) }
          raise Core::Error, 'Phạm vi tham số không hợp lệ.' unless limits.length == 2 && limits[0] <= limits[1] && Core.number(param['value']).between?(*limits)
        end
        Parametric.validate_variables!(bundle) if bundle.key?('parametric_variables')
        Parametric.validate_part_formulas!(bundle)
        exposed = bundle.fetch('exposed_parameter_keys')
        raise Core::Error, 'Lựa chọn tham số không hợp lệ.' unless exposed.is_a?(Array) && exposed.uniq == exposed && (exposed - params.map { |p| p['key'] }).empty?
        PositionRules.install!(bundle)
        constraints = bundle.fetch('constraints')
        raise Core::Error, 'Quá nhiều hoặc trùng quy tắc.' unless constraints.is_a?(Array) && constraints.length <= Core::MAX_PARTS * 32 && constraints.map { |c| c['id'] }.uniq.length == constraints.length
        constraints.each do |entry|
          raise Core::Error, 'Loại quy tắc không hợp lệ.' unless TYPES.include?(entry['type']) && entry['id'].is_a?(String) && !entry['id'].empty?
          raise Core::Error, 'Cờ quy tắc không hợp lệ.' unless [true, false].include?(entry['enabled']) && [true, false].include?(entry['drive'])
          if entry['type'] == 'position'
            refs = [entry['face'], entry['other']]
            unless !entry['drive'] && %w[distance dimension].include?(entry['measure']) && refs.all? do |ref|
              ref.is_a?(Hash) && (keys.include?(ref['part']) || ref['part'] == PositionRules::MODULE) && (0..2).include?(ref['axis']) && [0, 1].include?(ref['side'])
            end
              raise Core::Error, 'Quy tắc vị trí không hợp lệ.'
            end
            raise Core::Error, 'Các mặt vị trí khác trục.' unless entry['face']['axis'] == entry['other']['axis']
            next
          end
          if entry['type'] == 'formula'
            imported = entry['source'] == 'dc_attributes' || (entry['source'] == 'observations' && engine && engine['rules'].key?(entry['engine_key']))
            raise Core::Error, 'Công thức là mục đọc từ bộ máy quy tắc.' unless entry['drive'] == false && imported
            next
          end
          references = [entry.fetch('face')]
          references << entry.fetch('other') if %w[contact offset align between center].include?(entry['type'])
          references << entry.fetch('third') if %w[between center].include?(entry['type'])
          references.each do |ref|
            raise Core::Error, 'Quy tắc tham chiếu sai chi tiết hoặc mặt.' unless ref.is_a?(Hash) && keys.include?(ref['part']) && (0..2).include?(ref['axis']) && [0, 1].include?(ref['side'])
          end
          raise Core::Error, 'Các mặt phải cùng trục.' unless references.map { |ref| ref['axis'] }.uniq.length == 1
          Core.number(entry.fetch('gap', 0))
          Core.number(entry.fetch('gap2', 0))
          if entry['type'] == 'thickness'
            raise Core::Error, 'Tham số/hướng giữ độ dày không hợp lệ.' unless params.any? { |p| p['key'] == entry['parameter'] && p['value'].is_a?(Numeric) && p['unit'] == 'mm' } && %w[low high center].include?(entry['anchor'])
          end
        end
        bundle
      rescue KeyError, NoMethodError, TypeError
        raise Core::Error, 'Hệ quy tắc thiếu dữ liệu hoặc hỏng cấu trúc.'
      end

      def edit(bundle, entry = nil, remove: nil)
        copy = Marshal.load(Marshal.dump(bundle))
        if remove
          original = copy['constraints'].find { |c| c['id'] == remove }
          raise Core::Error, 'Mục đọc từ hình học/ATT; sửa quy tắc điều khiển của nó.' if original && %w[formula position].include?(original['type'])
          copy['constraints'].reject! { |c| c['id'] == remove }
        else
          raise Core::Error, 'Mục đọc từ hình học/ATT; sửa tham số hoặc quy tắc điều khiển.' if %w[formula position].include?(entry['type'])
          existing = copy['constraints'].find { |c| c['id'] == entry['id'] }
          raise Core::Error, 'Không thể đổi một công thức ATT thành quy tắc hình học.' if existing && existing['type'] == 'formula'
          updated = entry.slice('id', 'type', 'face', 'other', 'third', 'parameter', 'anchor', 'gap', 'gap2', 'enabled', 'drive', 'label')
          updated['id'] ||= Core::Ids.uuid
          updated['source'] = 'manual'
          copy['constraints'].reject! { |c| c['id'] == updated['id'] }
          copy['constraints'] << updated
        end
        unless copy['formula_engine']
          copy['parameters'].each do |param|
            param['editable'] = copy['constraints'].any? { |c| c['type'] == 'thickness' && c['enabled'] && c['drive'] && c['parameter'] == param['key'] }
          end
        end
        copy.delete('position_rules_version')
        validate!(copy)
      end

      # validated is an internal call-site proof, never a serialized rule flag.
      def plan(bundle, current, requested, previous_values: nil, validated: false)
        bundle = Core.copy_data(bundle)
        current = Core.copy_data(current)
        validate!(bundle) unless validated
        return DCCopies.plan(bundle,current,requested) if DCCopies.needed?(bundle,current,requested)
        Core.snapshot!(current)
        raise Core::Error, 'Cần nhập bộ tham số.' unless requested.is_a?(Hash)
        requested = Parametric.linked_requests(bundle,requested)
        lookup = current['parts'].to_h { |p| [p['key'], p] }
        raise Core::Error, 'Module không khớp cấu trúc quy tắc.' unless lookup.keys.sort == bundle['parts'].map { |p| p['key'] }.sort
        editable = bundle['parameters'].select { |p| p['editable'] }.map { |p| p['key'] }
        raise Core::Error, 'Thông số không có quy tắc điều khiển.' unless (requested.keys - editable).empty?
        engine = bundle['formula_engine']
        previous = previous_values || (engine ? Core.parameter_values(engine, current) : {})
        bundle['parameters'].select { |p| p['editable'] }.each do |param|
          next if previous.key?(param['key'])
          drivers = bundle['constraints'].select { |c| c['type'] == 'thickness' && c['enabled'] && c['drive'] && c['parameter'] == param['key'] }
          values = drivers.map { |c| Core.dimensions(lookup.fetch(c['face']['part'])['bounds'])[c['face']['axis']] }
          raise Core::Error, "#{param['label']}: các tấm đã khác độ dày." if values.empty? || values.max - values.min > Core::TOLERANCE
          previous[param['key']] = values.sum / values.length
        end
        targets = previous.merge(requested.transform_values { |v| Core.number(v) })
        bundle['parameters'].select { |p| p['editable'] }.each do |param|
          raise Core::Error, "#{param['label']}: giá trị ngoài phạm vi." unless targets.fetch(param['key']).between?(*param.fetch('input_range', [0.2, 100.0]))
        end
        candidate = current['parts']
        expected_envelope = current['envelope']
        visibility_updates = []
        visibility_capable = false
        att_parts = []
        if engine
          working = Marshal.load(Marshal.dump(engine))
          # Only explicitly constrained parts may diverge from ATT after a previous own edit.
          working['own_override_parts'] = bundle['constraints'].select { |c| c['enabled'] && c['drive'] }.flat_map do |c|
            %w[face other third].filter_map { |key| c[key] && c[key]['part'] }
          end.uniq | bundle.fetch('part_formulas', {}).keys | bundle.fetch('part_formula_parts', [])
          working['own_cell_parts'] = bundle.fetch('part_formula_parts', []) | bundle.fetch('part_formulas', {}).keys
          working['exposed_parameter_keys'] = bundle['exposed_parameter_keys']
          working['defer_geometry_validation'] = !working['own_override_parts'].empty?
          engine_plan = Core.plan_parameters(working, current, requested,validated:true)
          candidate = engine_plan['parts']
          expected_envelope = engine_plan['envelope']
          visibility_updates = engine_plan.fetch('visibility_updates',[])
          visibility_capable = engine_plan['visibility_capable']
          if working['attribute_program']
            att_parts = candidate.map { |part| part['key'] } - working['own_override_parts']
          end
        end
        active = bundle['constraints'].select { |c| c['enabled'] && c['drive'] && c['type'] != 'formula' }
        formula_envelope = engine_plan && engine_plan['formula_envelope']
        cell_values = Parametric.part_formula_values(bundle, candidate, targets, formula_envelope || expected_envelope)
        formula_growth = formula_length_growth(bundle, current, cell_values)
        expected_envelope = thickness_envelope(current, active, targets, cell_values) unless engine
        solved = candidate.to_h { |part| [part['key'], part['bounds'].map(&:dup)] }
        3.times do |axis|
          baseline = {}
          candidate.each { |part| 2.times { |side| baseline[[part['key'], side]] = part['bounds'][side][axis] } }
          equations = []
          # ATT already uses the current envelope. A temporary exterior contact
          # must not pin a formula-driven panel after it moves back inside.
          # Own geometric rules retain their exterior anchors.
          current['parts'].each do |part|
            next if att_parts.include?(part['key'])
            2.times do |side|
              next if part['visible'] == false || (part['bounds'][side][axis] - current['envelope'][side][axis]).abs > 0.001
              next if formula_growth[[part['key'], axis, side]]
              exterior = engine ? part['bounds'][side][axis] : expected_envelope[side][axis]
              equations << [{ [part['key'], side] => 1.0 }, exterior, "Phủ bì #{part['name']}"]
            end
          end
          active.select { |c| c['face']['axis'] == axis }.each do |entry|
            length = cell_values.dig(entry['face']['part'], Parametric::PART_FIELDS[axis])
            has_thickness = length || active.any? { |c| c['type'] == 'thickness' && c['face']['part'] == entry['face']['part'] && c['face']['axis'] == axis }
            effective = entry['type'] == 'thickness' && length ? targets.merge(entry['parameter'] => length) : targets
            append_equations(equations, entry, lookup, effective, has_thickness)
          end
          cell_values.each do |key, cells|
            length = cells[Parametric::PART_FIELDS[axis]]
            origin = cells[Parametric::PART_FIELDS[axis + 3]]
            equations << [{ [key, 1] => 1.0, [key, 0] => -1.0 }, length, "Công thức #{lookup[key]['name']} · Len#{%w[X Y Z][axis]}"] if length
            equations << [{ [key, 0] => 1.0 }, origin, "Công thức #{lookup[key]['name']} · #{%w[X Y Z][axis]}"] if origin
          end
          driven = active.select { |c| c['face']['axis'] == axis }.flat_map do |entry|
            case entry['type']
            when 'contact', 'offset', 'align' then [[entry['other']['part'], entry['other']['side']]]
            when 'thickness', 'between', 'center' then [[entry['face']['part'], 0], [entry['face']['part'], 1]]
            else [[entry['face']['part'], entry['face']['side']]]
            end
          end
          active.select { |c| %w[contact offset align].include?(c['type']) && c['face']['axis'] == axis }.each do |entry|
            ref = entry['face']
            variable = [ref['part'], ref['side']]
            equations << [{ variable => 1.0 }, baseline.fetch(variable), entry['label'] || 'Mặt chủ'] unless driven.include?(variable)
          end
          values = PlaneSolver.solve(equations, baseline)
          values.each { |(key, side), value| solved[key][side][axis] = value }
          formula_growth.each do |(key, grown_axis, side), _entry|
            if grown_axis == axis && side == 1
              expected_envelope[side][grown_axis] = [expected_envelope[side][grown_axis], *solved[key].map { |point| point[grown_axis] }].max
            end
          end
        end
        visibility = candidate.to_h { |part| [part['key'],part['visible']!=false] }
        changes = current['parts'].map do |part|
          bounds = solved.fetch(part['key'])
          DCVisibility.part_change(part,bounds,visibility.fetch(part['key']),visibility_updates)
        end
        reference = Array(engine&.dig('attribute_program', 'parts')).select { |part| att_parts.include?(part['key']) }
        reference = (reference+ThicknessSymbols.merge_reference(bundle)).uniq { |part| part['key'] }
        Core.validate_geometry_plan!(changes, current, overlap_reference: reference,expected_envelope:expected_envelope)
        { 'multi_parameter' => true, 'previous' => previous, 'target' => targets,
          'delta' => targets.to_h { |k, v| [k, v - previous[k]] }, 'parts' => changes,
          'parameter_labels' => bundle['parameters'].to_h { |p| [p['key'], p['label']] },
          'changed_count' => changes.count { |p| p['changed'] }, 'envelope' => expected_envelope,
          'formula_envelope'=>formula_envelope,
          'visibility_updates'=>visibility_updates, 'visibility_capable'=>visibility_capable,
          'outside_sample_range' => false, 'combination_unverified' => !engine }
      end

      # A manual length increase on an exterior panel may grow its high envelope
      # edge. The low edge stays anchored; every other envelope side remains fixed.
      def formula_length_growth(bundle, current, cells)
        envelope = current['envelope']
        current['parts'].each_with_object({}) do |part, result|
          next if part['visible'] == false
          3.times do |axis|
            text = bundle.dig('part_formulas', part['key'], Parametric::PART_FIELDS[axis])
            next unless text
            high = part['bounds'][1][axis]
            next unless (high - envelope[1][axis]).abs < 0.001
            length = cells.dig(part['key'], Parametric::PART_FIELDS[axis])
            next unless length && length > Core.dimensions(part['bounds'])[axis] + 0.001
            result[[part['key'], axis, 1]] = true
          end
        end
      end

      # A standalone panel's thickness is also its envelope dimension. Permit an
      # output axis only when every visible part spans it and all explicit
      # thickness drivers predict the same two planes. Cabinet axes stay pinned;
      # ATT and additional fixed constraints keep their existing authority.
      def thickness_envelope(current, active, targets, cells)
        envelope = current['envelope'].map(&:dup)
        parts = current['parts'].reject { |part| part['visible'] == false }
        3.times do |axis|
          predictions = parts.map do |part|
            bounds = part['bounds']
            next unless 2.times.all? { |side| (bounds[side][axis] - current['envelope'][side][axis]).abs < 0.001 }
            drivers = active.select { |entry| entry['type'] == 'thickness' && entry['face']['part'] == part['key'] && entry['face']['axis'] == axis }
            next if drivers.empty?
            planes = drivers.map do |entry|
              length = cells.dig(part['key'], Parametric::PART_FIELDS[axis]) || targets.fetch(entry['parameter'])
              low, high = bounds.map { |point| point[axis] }
              case entry['anchor']
              when 'low' then [low, low + length]
              when 'center' then [(low + high - length) / 2.0, (low + high + length) / 2.0]
              else [high - length, high]
              end
            end
            next unless planes.all? { |pair| pair.zip(planes.first).all? { |a, b| (a - b).abs < 0.001 } }
            planes.first
          end
          next if predictions.empty? || predictions.any?(&:nil?)
          next unless predictions.all? { |pair| pair.zip(predictions.first).all? { |a, b| (a - b).abs < 0.001 } }
          2.times { |side| envelope[side][axis] = predictions.first[side] }
        end
        envelope
      end

      def append_equations(equations, entry, lookup, targets, has_thickness = false)
        ref = entry['face']
        key, side, axis = ref.values_at('part', 'side', 'axis')
        label = entry['label'] || entry['type']
        add = lambda { |terms, rhs| equations << [terms, rhs, label] }
        case entry['type']
        when 'fix'
          add.call({ [key, side] => 1.0 }, lookup[key]['bounds'][side][axis] + Core.number(entry.fetch('gap', 0)))
        when 'thickness'
          add.call({ [key, 1] => 1.0, [key, 0] => -1.0 }, targets.fetch(entry['parameter']))
          bounds = lookup[key]['bounds']
          if entry['anchor'] == 'center'
            add.call({ [key, 0] => 1.0, [key, 1] => 1.0 }, bounds[0][axis] + bounds[1][axis])
          else
            anchor = entry['anchor'] == 'low' ? 0 : 1
            add.call({ [key, anchor] => 1.0 }, bounds[anchor][axis])
          end
        when 'contact', 'offset', 'align'
          other = entry['other']
          raise Core::Error, 'Hai mặt của quan hệ phải khác nhau.' if ref == other
          gap = entry['type'] == 'align' ? 0.0 : Core.number(entry.fetch('gap', 0)) * (side == 1 ? 1 : -1)
          add.call({ [other['part'], other['side']] => 1.0, [key, side] => -1.0 }, gap)
        when 'between', 'center'
          other, third = entry.values_at('other', 'third')
          if entry['type'] == 'between'
            add.call({ [key, 0] => 1.0, [other['part'], other['side']] => -1.0 }, Core.number(entry.fetch('gap', 0)))
            add.call({ [key, 1] => 1.0, [third['part'], third['side']] => -1.0 }, -Core.number(entry.fetch('gap2', 0)))
          else
            terms = Hash.new(0.0)
            terms[[key, 0]] += 1; terms[[key, 1]] += 1
            terms[[other['part'], other['side']]] -= 1; terms[[third['part'], third['side']]] -= 1
            add.call(terms, Core.number(entry.fetch('gap', 0)) * 2)
            add.call({ [key, 1] => 1.0, [key, 0] => -1.0 }, Core.dimensions(lookup[key]['bounds'])[axis]) unless has_thickness
          end
        end
      end
    end
  end
end
