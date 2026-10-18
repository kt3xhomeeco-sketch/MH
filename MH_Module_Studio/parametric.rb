# encoding: UTF-8
require_relative 'formulas'
require_relative 'parameter_rename'

module MH
  module ModuleStudio
    module Parametric
      extend self
      CATEGORIES = {
        'dimension' => 'Kích thước', 'position' => 'Vị trí', 'rotation' => 'Góc xoay',
        'copies' => 'Số bản sao (Copies)', 'copy' => 'Chỉ số bản sao (Copy)',
        'hidden' => 'Ẩn / hiện', 'material' => 'Vật liệu', 'information' => 'Thông tin',
        'behavior' => 'Tương tác (onClick)', 'number' => 'Số', 'text' => 'Chuỗi',
        'boolean' => 'Đúng / sai'
      }.freeze
      TEXT_TYPES = %w[material information behavior text].freeze
      PART_FIELDS = %w[lenx leny lenz x y z].freeze

      def display_name(value)
        name = value.to_s.strip
        raise Core::Error,'Tên cần từ 1 đến 120 ký tự, không chứa ký tự điều khiển.' if name.empty? || name.length>120 || name.match?(/[\x00-\x1f]/)
        name
      end

      # A capture label identifies an observation, not the source module.
      def module_title(snapshot,rule: nil,fallback: nil)
        snapshot ||= {}
        stored=rule && rule['module_name']
        return stored.to_s.strip[0,120] if rule && rule['module_name_source']=='user' && !stored.to_s.strip.empty?
        path=snapshot.dig('source','path').to_s.tr('\\','/').split('/').last.to_s.sub(/\.skp\z/i,'')
        candidates=[stored,snapshot['module_name'],Core.dc_label(snapshot.dig('dc_inputs','_name')),path,
                    Core.dc_label(rule && rule.dig('formula_engine','attribute_program','dc_inputs','_name')),fallback,snapshot['label']]
        name=candidates.map { |value| value.to_s.strip }.find do |value|
          !value.empty? && !capture_label?(value) && !value.match?(/\A(?:MH (?:File )?)?Module\z/i)
        end
        (name || 'Module')[0,120]
      end

      def capture_label?(value)
        value.to_s.strip.match?(/\ATrạng thái\s+\d+\z/i)
      end

      def filename(value)
        name = display_name(value).gsub(/[\\\/:*?"<>|]/,'_').sub(/[. ]+\z/,'')
        raise Core::Error,'Tên file không hợp lệ.' if name.empty? || name.match?(/\A(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|\z)/i)
        name+'.skp'
      end

      def rename_display(bundle,name,part_key: nil)
        copy = Core.copy_data(bundle)
        name = display_name(name)
        if part_key
          raise Core::Error,'Chi tiết đã đổi; đọc lại module.' unless copy['parts'].any? { |part| part['key']==part_key }
          (copy['part_names'] ||= {})[part_key] = name
        else
          copy['module_name'] = name
          copy['module_name_source'] = 'user'
        end
        # Canonical ATT node names are intentionally retained: name!attribute
        # references still resolve through their original verified program.
        copy
      end

      def with_values(bundle,values)
        copy = Core.copy_data(bundle)
        copy['parameters'].each { |param| param['value']=values.fetch(param['key'],param['value']) if param['editable'] }
        copy.fetch('parametric_variables',[]).each do |row|
          row['value']=values.fetch(row['binding'],row['value']) if row['binding'] && row['formula'].empty?
        end
        Core.rule!(copy)
      end

      def category(key, unit = '')
        return 'position' if %w[x y z].include?(key)
        return 'dimension' if %w[lenx leny lenz].include?(key) || unit == 'mm'
        return 'rotation' if %w[rotx roty rotz].include?(key)
        return key if %w[copies copy hidden material].include?(key)
        return 'behavior' if key == 'onclick'
        'information'
      end

      def variables(bundle)
        return Marshal.load(Marshal.dump(bundle['parametric_variables'])) if bundle['parametric_variables']
        copy_keys = DCCopies.enabled?(bundle) ? DCCopies.count_keys(DCCopies.engine(bundle)['attribute_program']) : []
        rows = bundle['parameters'].map do |param|
          type = category(param['dc_key'] || param['key'], param['unit'])
          type = 'number' if type == 'information' && param['value'].is_a?(Numeric)
          type = 'copies' if param['editable'] && param['unit'].empty? && copy_keys.include?(param['key'])
          { 'id' => "input:#{param['key']}", 'binding' => param['key'], 'name' => param['label'],
            'symbol' => param['key'], 'category' => type,
            'unit' => param['unit'], 'value' => param['value'], 'formula' => '',
            'exported' => bundle['exposed_parameter_keys'].include?(param['key']) }
        end
        DCOptions.initial_formulas(bundle,Core.copy_data(rows))
      end

      def validate_variables!(bundle)
        rows = bundle['parametric_variables']
        minimum=bundle['static_geometry']==true && !bundle['formula_engine'] ? 0 : 1
        unless rows.is_a?(Array) && rows.length.between?(minimum, Core::MAX_PARTS) && rows.all? { |r| r.is_a?(Hash) }
          raise Core::Error, 'Danh sách biến không hợp lệ.'
        end
        bindings = bundle['parameters'].to_h { |p| [p['key'], p] }
        root_keys = bundle.dig('formula_engine', 'attribute_program', 'dc_inputs')&.keys || []
        aliases = bundle.fetch('parameter_binding_aliases',{})
        primary = rows.filter_map { |row| row['binding'] }
        unless aliases.is_a?(Hash) && aliases.all? do |key,target|
                 key.is_a?(String) && target.is_a?(String) && key!=target && !primary.include?(key) && primary.include?(target) &&
                   bindings[key] && bindings[target] && bindings[key]['editable'] && bindings[target]['editable'] &&
                   bindings[key]['unit']=='mm' && bindings[target]['unit']=='mm'
               end
          raise Core::Error,'Liên kết các đầu vào của biến chung không hợp lệ.'
        end
        unless (primary+aliases.keys).sort == bindings.keys.sort
          raise Core::Error, 'Không thể bỏ biến ATT đang được hệ quy tắc sử dụng.'
        end
        symbols = rows.map { |r| r['symbol'].to_s.downcase }
        ids = rows.map { |r| r['id'] }
        unless symbols.uniq == symbols && ids.uniq == ids
          raise Core::Error, 'Tên ký hiệu hoặc ID biến bị trùng.'
        end
        rows.each do |row|
          unless row['id'].is_a?(String) && row['id'].length.between?(1, 200) &&
                 row['name'].is_a?(String) && row['name'].strip.length.between?(1, 160) &&
                 row['symbol'].is_a?(String) && row['symbol'].match?(/\A[a-zA-Z_][a-zA-Z_0-9]{0,63}\z/) &&
                 !(%w[true false parent] + DCFormulas::FUNCTIONS).include?(row['symbol'].downcase) &&
                 CATEGORIES.key?(row['category']) && row['unit'].is_a?(String) && row['unit'].length <= 20 &&
                 row['formula'].is_a?(String) && row['formula'].length <= 4096 && [true, false].include?(row['exported'])
            raise Core::Error, 'Tên, ký hiệu, loại hoặc công thức biến không hợp lệ.'
          end
          # Original keys remain available to formulas; a different alias cannot steal one.
          owner = bindings.keys.find { |key| key.downcase == row['symbol'].downcase }
          raise Core::Error, 'Ký hiệu trùng khóa ATT của biến khác.' if owner && owner != row['binding'] && !(aliases.key?(owner) && aliases[owner]==row['binding'])
          if root_keys.any? { |key| !key.start_with?('_') && key.downcase == row['symbol'].downcase && key != row['binding'] && !(aliases.key?(key) && aliases[key]==row['binding']) }
            raise Core::Error, 'Ký hiệu trùng thuộc tính ATT gốc; dùng ký hiệu riêng cho biến mới.'
          end
          if row['binding']
            param = bindings.fetch(row['binding'])
            unless DCOptions.editable?(bundle,param) || (row['value'] == param['value'] && row['formula'].empty?)
              raise Core::Error, "#{param['label']}: thông số chưa có quy tắc điều khiển; giữ giá trị gốc."
            end
            raise Core::Error, 'Đơn vị biến ATT phải giữ nguyên.' unless row['unit'] == param['unit']
            categories = param['unit'].empty? ? %w[dimension position number copies copy] : %w[dimension position number]
            if param['editable'] && !categories.include?(row['category'])
              raise Core::Error, 'Biến điều khiển kích thước/vị trí phải giữ loại số, kích thước hoặc vị trí.'
            end
          end
          if TEXT_TYPES.include?(row['category'])
            raise Core::Error, 'Biến chuỗi quá dài.' unless row['value'].to_s.length <= 4096
            raise Core::Error, 'Công thức chuỗi/tương tác hiện chỉ lưu dữ liệu, chưa thực thi.' unless row['formula'].empty?
          else
            Core.number(row['value'])
          end
          if !row['binding'] && %w[dimension position].include?(row['category']) && row['unit'] != 'mm'
            raise Core::Error, 'Biến kích thước/vị trí riêng dùng mm; đổi giá trị về mm trước khi nhập.'
          end
        end
        evaluated = evaluate_variables(bundle)
        binding_rows(bundle,rows).each do |key,row|
          param = bindings.fetch(key)
          if param['editable'] && !Core.number(evaluated.fetch(row['id'])).between?(*param.fetch('input_range',[0.2,100.0]))
            raise Core::Error,"#{param['label']}: giá trị ngoài phạm vi."
          end
        end
        rows.each do |row|
          value = evaluated.fetch(row['id'])
          if %w[copies copy].include?(row['category']) && (!value.is_a?(Numeric) || value < 0 || value != value.floor)
            raise Core::Error, 'Copy/Copies phải là số nguyên không âm.'
          end
          if %w[hidden boolean].include?(row['category']) && ![0, 1].include?(value)
            raise Core::Error, 'Biến đúng/sai hoặc ẩn/hiện chỉ nhận 0 hoặc 1.'
          end
          param = bindings[row['binding']]
          if param && DCOptions.editable?(bundle,param) && !Core.number(value).between?(*DCOptions.range(param))
            raise Core::Error, "#{param['label']}: giá trị ngoài phạm vi."
          end
        end
        bundle
      end

      # All arithmetic is interpreted by the existing restricted DC parser.
      # References here are own symbols, never imported code or model methods.
      def evaluate_variables(bundle)
        rows = bundle.fetch('parametric_variables', nil) || variables(bundle)
        lookup = {}
        rows.each do |row|
          lookup[row['symbol'].downcase] = row
          lookup[row['binding'].downcase] = row if row['binding']
        end
        binding_rows(bundle,rows).each { |key,row| lookup[key.downcase] = row }
        cache = {}
        stack = []
        parameters=bundle['parameters'].to_h { |param| [param['key'],param] }
        resolve = nil
        ast_value = nil
        arithmetic = DCFormulas
        ast_value = lambda do |ast|
          kind, name, left, right = ast
          case kind
          when :number then name
          when :unary then (name == '-' ? -1 : 1) * ast_value.call(left)
          when :reference
            raise Core::Error, 'Công thức biến chỉ dùng ký hiệu biến trong bảng.' if name
            next 1.0 if left == 'true'
            next 0.0 if left == 'false'
            row = lookup[left]
            raise Core::Error, "Biến không tồn tại hoặc đã bị xóa: #{left}." unless row
            Core.number(resolve.call(row))
          when :binary then arithmetic.binary(name, ast_value.call(left), ast_value.call(right))
          when :call
            next ast_value.call(left[ast_value.call(left.first).zero? ? 2 : 1]) if name == 'if'
            if name == 'choose'
              index = DCFormulas.choice_index(ast_value.call(left.first), left.length - 1)
              next ast_value.call(left[index])
            end
            values = left.map { |node| ast_value.call(node) }
            DCFormulas.numeric_function(name, values)
          else
            raise Core::Error, 'Công thức biến không hỗ trợ tham chiếu hàm riêng của DC.'
          end
        end
        resolve = lambda do |row|
          id = row['id']
          next cache[id] if cache.key?(id)
          raise Core::Error, "Công thức biến vòng lặp: #{row['symbol']}." if stack.include?(id) || stack.length >= 40
          stack << id
          param=parameters[row['binding']]
          result = if param && param['rule_source']=='dc_custom_attribute'
                     DCCustomAttributes.value(bundle,param) { |key| lookup[key] && resolve.call(lookup[key]) }
                   else
                     row['formula'].empty? ? row['value'] : ast_value.call(DCFormulas::Parser.new(row['formula']).parse)
                   end
          result = Core.number(result) unless TEXT_TYPES.include?(row['category'])
          stack.pop
          cache[id] = result
        end
        rows.each { |row| resolve.call(row) }
        cache
      end

      def edit_variables(bundle, rows)
        copy = Marshal.load(Marshal.dump(bundle))
        Core.rule!(copy)
        rows = Core.copy_data(rows)
        copy['parametric_variables'] = rows.map do |row|
          row.slice('id', 'binding', 'name', 'symbol', 'category', 'unit', 'value', 'formula', 'exported')
        end
        ParameterRename.apply!(copy, variables(bundle), copy['parametric_variables'])
        validate_variables!(copy)
        validate_part_formulas!(copy)
        Core.set_exposed_parameters!(copy, rows.select { |r| r['binding'] && r['exported'] }.map { |r| r['binding'] })
        copy
      rescue NoMethodError, TypeError
        raise Core::Error, 'Danh sách biến không hợp lệ.'
      end

      def numeric_expression(ast, &reference)
        kind, name, left, right = ast
        case kind
        when :number then name
        when :reference then Core.number(reference.call(name, left))
        when :unary then (name == '-' ? -1 : 1) * numeric_expression(left, &reference)
        when :binary
          DCFormulas.binary(name, numeric_expression(left, &reference), numeric_expression(right, &reference))
        when :call
          return numeric_expression(left[numeric_expression(left.first, &reference).zero? ? 2 : 1], &reference) if name == 'if'
          if name == 'choose'
            index = DCFormulas.choice_index(numeric_expression(left.first, &reference), left.length - 1)
            return numeric_expression(left[index], &reference)
          end
          values = left.map { |node| numeric_expression(node, &reference) }
          DCFormulas.numeric_function(name, values)
        else
          raise Core::Error, 'Công thức chi tiết cần ký hiệu biến hoặc kích thước module.'
        end
      end

      def part_formula_values(bundle, parts, targets, envelope)
        rows = Marshal.load(Marshal.dump(variables(bundle)))
        rows.each do |row|
          next unless row['binding'] && targets.key?(row['binding'])
          row.merge!('value' => targets[row['binding']], 'formula' => '')
        end
        evaluated = evaluate_variables(bundle.merge('parametric_variables' => rows))
        values = {}
        rows.each do |row|
          values[row['symbol'].downcase] = evaluated[row['id']]
          values[row['binding'].downcase] = evaluated[row['id']] if row['binding']
        end
        binding_rows(bundle,rows).each { |key,row| values[key.downcase] = evaluated.fetch(row['id']) }
        dimensions = Core.dimensions(envelope)
        formulas = bundle.fetch('part_formulas', {})
        lookup = parts.to_h { |part| [part['key'], part] }
        formulas.to_h do |key, cells|
          baseline = PART_FIELDS.zip(Core.dimensions(lookup.fetch(key)['bounds']) + lookup.fetch(key)['bounds'][0]).to_h
          cache = {}; stack = []; resolve = nil
          resolve = lambda do |field|
            next cache[field] if cache.key?(field)
            next baseline.fetch(field) unless cells.key?(field)
            raise Core::Error, "Công thức chi tiết vòng lặp: #{lookup[key]['name']} · #{field}." if stack.include?(field)
            stack << field
            text = cells[field].gsub(/\bModule\.(lenx|leny|lenz|x|y|z)\b/i, 'Module!\1')
            value = numeric_expression(DCFormulas::Parser.new(text).parse) do |scope, attribute|
              if %w[module parent].include?(scope)
                index = PART_FIELDS.index(attribute)
                next index < 3 ? dimensions[index] : envelope[0][index - 3] if index
                next values.fetch(attribute) { raise Core::Error, "Biến không tồn tại: #{attribute}." }
              end
              raise Core::Error, 'Công thức chi tiết dùng biến module, Module.LenX hoặc thuộc tính của chính chi tiết.' if scope && scope != 'self'
              next 1.0 if attribute == 'true'
              next 0.0 if attribute == 'false'
              next values[attribute] if scope.nil? && values.key?(attribute)
              next resolve.call(attribute) if PART_FIELDS.include?(attribute)
              raise Core::Error, "Biến hoặc thuộc tính không tồn tại: #{attribute}."
            end
            stack.pop
            cache[field] = Core.number(value)
          end
          [key, cells.to_h { |field, _text| [field, resolve.call(field)] }]
        end
      end

      def validate_part_formulas!(bundle)
        formulas = bundle.fetch('part_formulas', {})
        keys = bundle['parts'].map { |part| part['key'] }
        touched = bundle.fetch('part_formula_parts', [])
        raise Core::Error, 'Danh sách chi tiết đã sửa công thức không hợp lệ.' unless touched.is_a?(Array) && touched.uniq == touched && (touched - keys).empty?
        unless formulas.is_a?(Hash) && formulas.length <= keys.length && formulas.all? do |key, cells|
          keys.include?(key) && cells.is_a?(Hash) && cells.length <= 6 && cells.all? do |field, text|
            PART_FIELDS.include?(field) && text.is_a?(String) && text.strip.length.between?(1, 4096)
          end
        end
          raise Core::Error, 'Công thức chi tiết không hợp lệ.'
        end
        parts = bundle['parts'].map { |part| part.merge('bounds' => part['base_bounds']) }
        part_formula_values(bundle, parts, {}, bundle['envelope']) unless formulas.empty?
        bundle
      end

      def edit_part_formula(bundle, part_key, field, text)
        raise Core::Error, 'Ô công thức chi tiết không hợp lệ.' unless PART_FIELDS.include?(field) && text.is_a?(String) && text.length <= 4096 && bundle['parts'].any? { |part| part['key'] == part_key }
        copy = Marshal.load(Marshal.dump(bundle))
        copy['part_formulas'] ||= {}
        copy['part_formula_parts'] = (copy.fetch('part_formula_parts', []) + [part_key]).uniq
        cells = (copy['part_formulas'][part_key] ||= {})
        text.strip.empty? ? cells.delete(field) : cells[field] = text.strip
        copy['part_formulas'].delete(part_key) if cells.empty?
        RuleSystem.validate!(copy)
      end

      def targets(bundle)
        rows = variables(bundle)
        values = evaluate_variables(bundle)
        editable = bundle['parameters'].select { |p| p['editable'] }.map { |p| p['key'] }
        # The legacy exported flag is now visibility only; every input still calculates.
        binding_rows(bundle,rows).select { |key,_row| editable.include?(key) }.to_h do |key,row|
          [key, Core.number(values.fetch(row['id']))]
        end
      end

      def binding_rows(bundle, rows = variables(bundle))
        result = rows.select { |row| row['binding'] }.to_h { |row| [row['binding'],row] }
        bundle.fetch('parameter_binding_aliases',{}).each { |key,target| result[key] = result.fetch(target) }
        result
      end

      def linked_requests(bundle, requested)
        result = requested.dup
        bundle.fetch('parameter_binding_aliases',{}).group_by { |_key,target| target }.each do |target,entries|
          keys = [target,*entries.map(&:first)]
          explicit = keys.select { |key| result.key?(key) }.map { |key| Core.number(result[key]) }
          next if explicit.empty?
          raise Core::Error,'Các đầu vào của cùng một biến độ dày phải có cùng giá trị.' if explicit.max-explicit.min>0.000001
          keys.each { |key| result[key] = explicit.first }
        end
        result
      end

      def exposed_custom_variables(bundle)
        evaluated = evaluate_variables(bundle)
        variables(bundle).select { |row| !row['binding'] && row['exported'] }.map do |row|
          { 'key' => row['symbol'], 'variable_id' => row['id'], 'label' => row['name'],
            'symbol' => row['symbol'], 'category' => row['category'], 'unit' => row['unit'],
            'value' => evaluated.fetch(row['id']), 'formula' => row['formula'],
            'can_edit' => row['formula'].empty?, 'rule_key' => nil, 'status' => 'data' }
        end
      end

      # Compatibility entry points; sheet construction owns no variable logic.
      def sheet(bundle, snapshot, plan = nil)
        ParametricSheet.sheet(Core.copy_data(bundle), Core.copy_data(snapshot), plan && Core.copy_data(plan))
      end

      def describe(bundle, snapshot, targets = nil, envelope: nil)
        ParametricSheet.describe(Core.copy_data(bundle), Core.copy_data(snapshot), targets, envelope: envelope)
      end
    end
  end
end
