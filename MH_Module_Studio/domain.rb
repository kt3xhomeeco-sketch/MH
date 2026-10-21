# encoding: UTF-8
# Portable data / numerical core. No SketchUp API and no evaluation of DC code.
require 'json'
require 'cgi'
require 'random/formatter'

module MH
  module ModuleStudio
    module Core
      extend self
      # Use the OS random source directly; never fall back to OpenSSL in SketchUp.
      module Ids
        extend Random::Formatter

        def self.bytes(size)
          Random.urandom(size)
        end
      end
      FORMAT = 'mh_module_studio'.freeze
      TOLERANCE = 0.15 # mm, measurement / regression residual tolerance
      ENVELOPE_TOLERANCE = 0.001 # mm; edits must not grow the module within the reading tolerance
      MAX_PARTS = 600
      class Error < StandardError; end

      # Calculation boundaries own their data. Never share editable nested
      # hashes/arrays between a saved rule, a sheet and a geometry preview.
      def copy_data(value)
        Marshal.load(Marshal.dump(value))
      end

      def number(value)
        result = Float(value)
        raise Error, 'Có giá trị số không hữu hạn.' unless result.finite?
        result
      rescue ArgumentError, TypeError
        raise Error, 'Giá trị số không hợp lệ.'
      end

      def bounds!(bounds)
        raise Error, 'Thiếu khung hình học.' unless bounds.is_a?(Array) && bounds.length == 2
        result = bounds.map do |point|
          raise Error, 'Điểm hình học phải có 3 tọa độ.' unless point.is_a?(Array) && point.length == 3
          point.map { |v| number(v) }
        end
        raise Error, 'Khung hình học đảo chiều.' if 3.times.any? { |axis| result[1][axis] < result[0][axis] }
        result
      end

      def dimensions(bounds)
        3.times.map { |axis| bounds[1][axis] - bounds[0][axis] }
      end

      def union(parts)
        raise Error, 'Module không có chi tiết hình học.' if parts.empty?
        [3.times.map { |axis| parts.map { |p| p['bounds'][0][axis] }.min },
         3.times.map { |axis| parts.map { |p| p['bounds'][1][axis] }.max }]
      end

      def thickness_axis(bounds)
        dims = dimensions(bounds)
        order = (0..2).sort_by { |axis| dims[axis] }
        return nil if dims[order[0]] < 0.2 || dims[order[0]] > 100
        return nil if dims[order[1]] < dims[order[0]] * 2
        order[0]
      end

      def use_measured_parameter!(snapshot)
        groups = []
        snapshot.fetch('parts').each do |part|
          next if part['visible'] == false
          axis = thickness_axis(part['bounds'])
          next if axis.nil?
          value = dimensions(part['bounds'])[axis]
          group = groups.find { |item| (item['values'].first - value).abs <= 0.02 }
          unless group
            group = { 'values' => [], 'parts' => [] }
            groups << group
          end
          group['values'] << value
          group['parts'] << part
        end
        groups.sort_by! { |group| -group['parts'].length }
        winner = groups.first
        if winner.nil? || winner['parts'].length < 2 || (groups[1] && groups[1]['parts'].length == winner['parts'].length)
          raise Error, 'Chưa xác định được nhóm tấm chính có cùng độ dày. Chọn Nhập thủ công để khai báo độ dày cần học.'
        end
        snapshot['parameter'] = (winner['values'].sum / winner['values'].length).round(6)
        snapshot['parameter_source'] = {
          'kind' => 'geometry_thickness_group',
          'part_keys' => winner['parts'].map { |part| part['key'] }.sort,
          'box_verified' => winner['parts'].all? { |part| part['box_verified'] == true }
        }
        snapshot
      end

      def snapshot!(snapshot)
        raise Error, 'Sai định dạng trạng thái.' unless snapshot.is_a?(Hash) && snapshot['parts'].is_a?(Array)
        parts = snapshot['parts']
        raise Error, 'Module không có chi tiết hoặc vượt 600 chi tiết.' unless parts.length.between?(1, MAX_PARTS)
        keys = parts.map do |part|
          raise Error, 'Chi tiết không hợp lệ.' unless part.is_a?(Hash)
          key = part['key'].to_s
          raise Error, 'Chi tiết thiếu mã nhận diện.' if key.empty? || key.length > 2000
          part['bounds'] = bounds!(part['bounds'])
          key
        end
        duplicates = keys.tally.select { |_key, count| count > 1 }.keys
        unless duplicates.empty?
          raise Error, "Tên/đường dẫn bị trùng: #{duplicates.first(3).join(', ')}. Đặt tên phân biệt rồi đọc lại."
        end
        snapshot['envelope'] = bounds!(snapshot['envelope'])
        snapshot['formula_envelope'] = bounds!(snapshot['formula_envelope']) if snapshot['formula_envelope']
        snapshot
      end

      def fit(xs, ys)
        average_x = xs.sum / xs.length
        average_y = ys.sum / ys.length
        denominator = xs.sum { |x| (x - average_x)**2 }
        raise Error, 'Cần ít nhất hai độ dày khác nhau.' if denominator < 1.0e-9
        slope = xs.zip(ys).sum { |x, y| (x - average_x) * (y - average_y) } / denominator
        intercept = average_y - slope * average_x
        error = xs.zip(ys).map { |x, y| (y - intercept - slope * x).abs }.max
        slope = 0.0 if slope.abs < 0.00001
        { 'slope' => slope, 'intercept' => intercept, 'error' => error }
      end

      def dc_label(value)
        CGI.unescapeHTML(value.to_s.gsub(/<[^>]*>/, ' ')).gsub(/\s+/, ' ').strip[0, 200]
      end

      def dc_value(value)
        number(value)
      rescue Error
        value.to_s
      end

      def same_dc_value?(left, right)
        left.is_a?(Numeric) && right.is_a?(Numeric) ? (left - right).abs <= 0.000001 : left == right
      end

      def dc_controls(snapshot, factor = 25.4)
        attributes = snapshot['dc_inputs'] || {}
        controls = attributes.each_with_object({}) do |(name, access), result|
          key = name[/\A_(.+)_access\z/, 1]
          next unless key && %w[TEXTBOX LIST].include?(access.to_s.upcase) && attributes.key?(key)
          value = dc_value(attributes[key])
          units = attributes["_#{key}_units"].to_s.upcase
          length = %w[MILLIMETERS CENTIMETERS METERS INCHES FEET].include?(units) || DCFrames.typed_length?(attributes,key)
          label = dc_label(attributes["_#{key}_formlabel"])
          result[key] = { 'label' => label.empty? ? key : label, 'value' => value,
                            'display_value' => length && value.is_a?(Numeric) ? (value * factor).round(6) : value,
                            'unit' => length && value.is_a?(Numeric) ? 'mm' : '', 'value_factor'=>length ? factor : 1.0 }
        end
        controls.merge(DCCustomInputs.controls(snapshot))
      end

      def dc_thickness_parameters(snapshots)
        return [] if snapshots.empty?
        attributes = snapshots.first['dc_inputs'] || {}
        return [] if attributes.empty?
        rows = snapshots.map { |snapshot| snapshot['parts'].to_h { |part| [part['key'], part] } }
        attributes.filter_map do |name, text|
          key = name[/\A_(.+)_formlabel\z/, 1]
          label = dc_label(text)
          next unless key && label.match?(/dày|thickness/i)
          begin
            values = snapshots.map { |snapshot| number((snapshot['dc_inputs'] || {}).fetch(key)) }
          rescue Error, KeyError
            next
          end
          matches = [25.4, 1.0, 10.0, 1000.0].filter_map do |factor|
            measured = values.map { |value| value * factor }
            next unless measured.all? { |value| value.between?(0.2, 100) }
            parts = rows.first.keys.select do |part_key|
              rows.each_with_index.all? do |lookup, index|
                part = lookup[part_key]
                next false unless part && part['visible'] != false
                axis = thickness_axis(part['bounds'])
                axis && (dimensions(part['bounds'])[axis] - measured[index]).abs <= 0.02
              end
            end
            next if parts.empty?
            { 'dc_key' => key, 'label' => label, 'factor' => factor, 'part_keys' => parts.sort,
              'values' => snapshots.each_with_index.to_h { |snapshot, index| [snapshot['id'], measured[index].round(6)] } }
          end
          # Ambiguous units need more evidence; never guess from a display label.
          matches.first if matches.length == 1
        end
      end

      def learn_dc_parameter(snapshots, dc_key)
        choice = dc_thickness_parameters(snapshots).find { |item| item['dc_key'] == dc_key }
        raise Error, 'Tham số DC chưa khớp độ dày hình học. Kiểm tra mẫu hoặc dùng chế độ hình học/nhập tay.' unless choice
        groups = []
        snapshots.each_with_index do |snapshot, index|
          controls = dc_controls(snapshot, choice['factor']).reject { |key, _value| key == dc_key }
          group = groups.find do |item|
            item['controls'].keys.sort == controls.keys.sort && controls.all? do |key, control|
              same_dc_value?(control['value'], item['controls'][key]['value'])
            end
          end
          unless group
            group = { 'controls' => controls, 'indices' => [] }
            groups << group
          end
          group['indices'] << index
        end
        eligible = groups.select do |group|
          values = group['indices'].map { |index| choice['values'].fetch(snapshots[index]['id']) }
          values.max - values.min >= 0.05
        end
        group = eligible.max_by { |item| [item['indices'].length, item['indices'].max] }
        unless group
          raise Error, "#{choice['label']}: cần ít nhất 2 mẫu khác độ dày này nhưng giữ nguyên các tham số DC khác (Hậu lùi, Hậu ngậm, kiểu lắp, độ dày nhóm khác…)."
        end
        selected = group['indices'].map do |index|
          snapshot = snapshots[index]
          snapshot.merge('parameter' => choice['values'].fetch(snapshot['id']),
                         'parameter_source' => { 'kind' => 'dc_parameter', 'dc_key' => dc_key },
                         'parts' => snapshot['parts'].map { |part| part.merge('bounds' => part['bounds'].map(&:dup)) },
                         'envelope' => snapshot['envelope'].map(&:dup))
        end
        rule = learn(selected, choice['label'])
        rule['dc_parameter'] = choice.reject { |key, _value| key == 'values' }
        rule['control_context'] = group['controls']
        rule['training_sample_ids'] = selected.map { |snapshot| snapshot['id'] }
        rule['ignored_sample_ids'] = snapshots.map { |snapshot| snapshot['id'] } - rule['training_sample_ids']
        unless rule['ignored_sample_ids'].empty?
          rule['warnings'] << "Dùng #{selected.length}/#{snapshots.length} mẫu; các mẫu còn lại có tham số DC cố định khác nên không ghép vào cùng quy tắc."
        end
        rule
      end

      def check_dc_context!(rule, current)
        attributes = current['dc_inputs'] || {}
        return if attributes.empty?
        (rule['control_context'] || {}).each do |key, control|
          unless attributes.key?(key) && same_dc_value?(dc_value(attributes[key]), control['value'])
            raise Error, "#{control['label']}: tham số DC đang khác điều kiện của mẫu đã học. Đọc lại mẫu với giá trị này trước khi áp dụng."
          end
        end
      end

      def learn(snapshots, parameter_label = 'Độ dày đang khảo sát')
        snapshots = copy_data(snapshots)
        raise Error, 'Đọc từ 2 đến 20 trạng thái của cùng module.' unless snapshots.is_a?(Array) && snapshots.length.between?(2, 20)
        snapshots.each { |snapshot| snapshot!(snapshot) }
        measured_groups = snapshots.filter_map do |snapshot|
          source = snapshot['parameter_source']
          source['part_keys'] if source && source['kind'] == 'geometry_thickness_group'
        end
        if measured_groups.uniq.length > 1
          raise Error, 'Nhóm tấm tự đọc độ dày đã thay đổi giữa các mẫu. Dùng cùng một nhóm tấm hoặc nhập thủ công.'
        end
        xs = snapshots.map { |snapshot| number(snapshot['parameter']) }
        raise Error, 'Độ dày phải trong khoảng 0,2–100 mm.' unless xs.all? { |x| x.between?(0.2, 100) }
        raise Error, 'Cần ít nhất hai độ dày khác nhau.' if xs.max - xs.min < 0.05
        baseline = snapshots.first
        keys = baseline['parts'].map { |part| part['key'] }.sort
        snapshots.each do |snapshot|
          unless snapshot['parts'].map { |part| part['key'] }.sort == keys
            raise Error, 'Cấu trúc/tên chi tiết khác nhau. Bộ mẫu phải là các trạng thái của cùng module.'
          end
          unless 2.times.all? { |side| 3.times.all? { |axis| (snapshot['envelope'][side][axis] - baseline['envelope'][side][axis]).abs <= TOLERANCE } }
            raise Error, 'Phủ bì hoặc gốc trục khác nhau giữa các mẫu. Giữ nguyên khung và chỉ đổi độ dày.'
          end
        end
        lookup = snapshots.map { |snapshot| snapshot['parts'].to_h { |part| [part['key'], part] } }
        learned = baseline['parts'].map do |part|
          observations = lookup.map { |rows| rows.fetch(part['key']) }
          coefficients = 2.times.map do |side|
            3.times.map { |axis| fit(xs, observations.map { |row| row['bounds'][side][axis] }) }
          end
          worst = coefficients.flatten.map { |coefficient| coefficient['error'] }.max
          raise Error, "#{part['name']}: thay đổi không tuyến tính (sai lệch #{worst.round(2)} mm). Cần khảo sát riêng." if worst > TOLERANCE
          axis = part['thickness_axis']
          driver = !axis.nil? && observations.each_with_index.all? do |row, index|
            (dimensions(row['bounds'])[axis] - xs[index]).abs <= TOLERANCE
          end
          { 'key' => part['key'], 'name' => part['name'], 'thickness_axis' => axis,
            'driver' => driver, 'coefficients' => coefficients, 'base_bounds' => part['bounds'],
            'max_error' => worst }
        end
        drivers = learned.select { |part| part['driver'] }
        raise Error, 'Không tìm thấy tấm có độ dày khớp giá trị đã khai báo. Kiểm tra lại tham số đang khảo sát.' if drivers.empty?
        changed = learned.select { |part| part['coefficients'].flatten.any? { |coefficient| coefficient['slope'].abs > 0.00001 } }
        raise Error, 'Không thấy hình học thay đổi giữa các trạng thái.' if changed.empty?
        relations = detect_relations(snapshots, learned)
        { 'format' => FORMAT, 'version' => 1, 'kind' => 'linear_thickness_rule',
          'id' => Ids.uuid, 'parameter_label' => parameter_label.to_s[0, 120],
          'sample_count' => snapshots.length, 'distinct_samples' => xs.uniq.length,
          'sample_range' => [xs.min, xs.max], 'base_parameter' => xs.first,
          'envelope' => baseline['envelope'], 'parts' => learned, 'relations' => relations,
          'status' => xs.uniq.length >= 3 ? 'three_or_more_samples' : 'two_samples_provisional',
          'warnings' => [xs.uniq.length < 3 ? 'Hai mức độ dày chỉ đủ đề xuất quy tắc. Nên thêm mức thứ ba để đối chiếu.' :
                         'Khớp các mẫu đã đọc; chưa chứng minh đúng ngoài phạm vi khảo sát.',
                         'Bản đầu học một biến độ dày, không thực thi công thức DC hoặc hàm ABF.'] }
      end

      def detect_relations(snapshots, learned)
        first = snapshots.first['parts'].to_h { |part| [part['key'], part] }
        all = snapshots.map { |snapshot| snapshot['parts'].to_h { |part| [part['key'], part] } }
        relations = []
        learned.select { |part| part['driver'] }.each do |leader|
          axis = leader['thickness_axis']
          2.times do |side|
            slope = leader['coefficients'][side][axis]['slope']
            next if slope.abs < 0.00001
            other_side = 1 - side
            learned.each do |follower|
              next if leader['key'] == follower['key']
              next if (follower['coefficients'][other_side][axis]['slope'] - slope).abs > 0.01
              gaps = all.map { |rows| rows[follower['key']]['bounds'][other_side][axis] - rows[leader['key']]['bounds'][side][axis] }
              next if gaps.first.abs > 5 || gaps.max - gaps.min > TOLERANCE
              a = first[leader['key']]['bounds']
              b = first[follower['key']]['bounds']
              next unless ((0..2).to_a - [axis]).all? { |dimension| [a[1][dimension], b[1][dimension]].min - [a[0][dimension], b[0][dimension]].max > 0.5 }
              relations << { 'leader' => leader['key'], 'leader_name' => leader['name'], 'leader_side' => side,
                             'follower' => follower['key'], 'follower_name' => follower['name'], 'follower_side' => other_side,
                             'axis' => axis, 'gap_mm' => gaps.first, 'evidence' => 'contact_and_matching_motion' }
            end
          end
        end
        relations
      end

      def rule!(rule, formula_nested: false)
        return RuleSystem.validate!(rule) if rule.is_a?(Hash) && rule['kind'] == RuleSystem::KIND
        return parameter_set!(rule) if rule.is_a?(Hash) && rule['kind'] == 'module_parameter_set'
        unless rule.is_a?(Hash) && rule['format'] == FORMAT && rule['version'] == 1 && %w[linear_thickness_rule dc_formula_rule].include?(rule['kind'])
          raise Error, 'Không phải bộ quy tắc MH Module Studio v1.'
        end
        raise Error, 'Quy tắc ATT cần nằm trong bộ tham số có cây công thức đầy đủ.' if rule['kind'] == 'dc_formula_rule' && !formula_nested
        snapshot!({ 'parts' => rule['parts'].map { |part| { 'key' => part['key'], 'bounds' => part['base_bounds'] } }, 'envelope' => rule['envelope'] })
        rule['parts'].each do |part|
          rows = part['coefficients']
          raise Error, 'Hệ số biến đổi không hợp lệ.' unless rows.is_a?(Array) && rows.length == 2 && rows.all? { |row| row.is_a?(Array) && row.length == 3 }
          rows.flatten.each { |coefficient| %w[slope intercept error].each { |key| coefficient[key] = number(coefficient.fetch(key)) } }
          raise Error, 'Cờ điều khiển độ dày không hợp lệ.' unless [true, false].include?(part['driver'])
          if part['driver'] && !(0..2).include?(part['thickness_axis'])
            raise Error, 'Hướng độ dày không hợp lệ.'
          end
        end
        raise Error, 'Quy tắc thiếu tấm điều khiển độ dày.' unless rule['kind'] == 'dc_formula_rule' || rule['parts'].any? { |part| part['driver'] }
        if rule['kind'] == 'dc_formula_rule'
          range = parameter_range(rule)
          allowed=[[0.2,10_000.0],[0.0,10_000.0]]
          allowed << [-10_000.0,10_000.0] if number(rule['base_parameter']).negative?
          unless range.is_a?(Array) && range.length == 2 && allowed.include?(range.map { |value| number(value) })
            raise Error, 'Phạm vi tham số ATT không hợp lệ.'
          end
          rule['input_range'] = range.dup
        end
        range = rule['sample_range']
        raise Error, 'Thiếu phạm vi độ dày đã khảo sát.' unless range.is_a?(Array) && range.length == 2
        rule['sample_range'] = range.map { |value| number(value) }
        raise Error, 'Phạm vi độ dày không hợp lệ.' if rule['sample_range'][0] > rule['sample_range'][1]
        rule['parameter_label'] = rule['parameter_label'].to_s[0, 120]
        rule['warnings'] = Array(rule['warnings']).first(20).map(&:to_s)
        context = rule['control_context']
        if context
          unless context.is_a?(Hash) && context.length <= MAX_PARTS && context.all? do |key, control|
            key.is_a?(String) && key.length <= 200 && control.is_a?(Hash) && control['label'].is_a?(String) &&
              (control['value'].is_a?(String) || control['value'].is_a?(Numeric))
          end
            raise Error, 'Điều kiện tham số DC không hợp lệ.'
          end
        end
        raise Error, 'Danh sách quan hệ không hợp lệ.' unless rule['relations'].is_a?(Array) && rule['relations'].length <= MAX_PARTS * 12
        valid_keys = rule['parts'].map { |part| part['key'] }
        rule['relations'].each do |relation|
          unless valid_keys.include?(relation['leader']) && valid_keys.include?(relation['follower']) &&
                 (0..2).include?(relation['axis']) && [0, 1].include?(relation['leader_side']) && [0, 1].include?(relation['follower_side'])
            raise Error, 'Quan hệ tham chiếu sai chi tiết hoặc mặt.'
          end
          number(relation['gap_mm'])
        end
        rule
      rescue NoMethodError, KeyError, TypeError
        raise Error, 'Bộ quy tắc thiếu dữ liệu hoặc hỏng cấu trúc.'
      end

      def plan(rule, current, target)
        rule = copy_data(rule)
        current = copy_data(current)
        return RuleSystem.plan(rule, current, target) if rule.is_a?(Hash) && rule['kind'] == RuleSystem::KIND
        return plan_parameters(rule, current, target) if rule.is_a?(Hash) && rule['kind'] == 'module_parameter_set'
        rule!(rule)
        snapshot!(current)
        check_dc_context!(rule, current)
        target = number(target)
        raise Error, 'Độ dày phải trong khoảng 0,2–100 mm.' unless target.between?(0.2, 100)
        lookup = current['parts'].to_h { |part| [part['key'], part] }
        unless lookup.keys.sort == rule['parts'].map { |part| part['key'] }.sort
          raise Error, 'Module đang chọn không khớp cấu trúc của bộ quy tắc.'
        end
        driver_values = rule['parts'].select { |part| part['driver'] }.map do |part|
          dimensions(lookup.fetch(part['key'])['bounds'])[part['thickness_axis']]
        end
        raise Error, 'Các tấm điều khiển có độ dày khác nhau. Bản đầu yêu cầu một biến độ dày chung.' if driver_values.max - driver_values.min > TOLERANCE
        previous = driver_values.sum / driver_values.length
        delta = target - previous
        rule['relations'].each do |relation|
          leader = lookup.fetch(relation['leader'])
          follower = lookup.fetch(relation['follower'])
          gap = follower['bounds'][relation['follower_side']][relation['axis']] - leader['bounds'][relation['leader_side']][relation['axis']]
          if (gap - relation['gap_mm']).abs > 0.5
            raise Error, "Quan hệ #{leader['name']} → #{follower['name']} đã đổi. Cần đọc và kiểm tra lại mẫu."
          end
        end
        changes = rule['parts'].map do |part|
          original = lookup.fetch(part['key'])
          updated = 2.times.map { |side| 3.times.map { |axis| original['bounds'][side][axis] + part['coefficients'][side][axis]['slope'] * delta } }
          moving = 2.times.any? { |side| 3.times.any? { |axis| (updated[side][axis] - original['bounds'][side][axis]).abs > 0.001 } }
          if moving
            raise Error, "#{original['name']}: bản đầu chỉ áp dụng lên tấm hộp đã xác minh." unless original['box_verified']
            raise Error, "#{original['name']}: kích thước mới không hợp lệ." unless dimensions(updated).all? { |size| size > 0.1 }
          end
          original.merge('bounds' => updated, 'old_bounds' => original['bounds'], 'changed' => moving)
        end
        validate_geometry_plan!(changes, current)
        { 'previous' => previous, 'target' => target, 'delta' => delta, 'parts' => changes,
          'changed_count' => changes.count { |part| part['changed'] }, 'envelope' => current['envelope'],
          'outside_sample_range' => target < rule['sample_range'][0] || target > rule['sample_range'][1] }
      end
    end
  end
end
