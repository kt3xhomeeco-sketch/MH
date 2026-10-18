# encoding: UTF-8
require_relative 'symbolic_program'

module MH
  module ModuleStudio
    module DCFormulas
      class ParametricProgram < SymbolicProgram
        def parametric_attributes(values, envelope)
          evaluate(values, envelope)
          @nodes.flat_map do |id, node|
            attrs = node['attributes']
            keys = attrs.keys.reject { |key| key.start_with?('_') } + attrs.keys.filter_map { |key| key[/\A_(.+)_formula\z/, 1] }
            keys.uniq.sort.map do |key|
              formula = attrs["_#{key}_formula"].to_s
              raw = attrs[key]
              dimension = unit(id, key)
              status = formula.empty? ? 'fixed' : 'computed'
              diagnostic = nil
              begin
                value = if raw.is_a?(String) && !raw.match?(/\A[-+]?\d+(?:\.\d*)?(?:e[-+]?\d+)?\z/i)
                          if formula.match?(/\A"[^"]*"\z/)
                            formula[1...-1]
                          elsif formula.empty?
                            raw
                          else
                            raise Core::Error, 'Công thức chuỗi chưa hỗ trợ; giữ giá trị DC đã đọc.'
                          end
                        else
                          attribute(id, key)
                        end
              rescue Core::Error => error
                value = raw
                status = 'unsupported'
                diagnostic = error.message
                # Cached length attributes are stored in inches, irrespective of display units.
                begin
                  value = Core.number(raw) * 25.4 if dimension
                rescue Core::Error
                  value = raw.to_s
                end
              end
              path = node['path'].join(' / ')
              label = Core.dc_label(attrs["_#{key}_formlabel"])
              label = Core.dc_label(attrs["_#{key}_label"]) if label.empty?
              label = key if label.empty?
              { 'id' => "#{id}!#{key}", 'node_id' => id, 'path' => path.empty? ? 'Module' : path,
                'node_name' => node['name'].to_s, 'part_key' => node['part_key'], 'key' => key,
                'label' => label, 'value' => value, 'unit' => dimension ? 'mm' : '',
                'raw_value' => raw, 'formula' => formula, 'formula_units' => attrs["_#{key}_formulaunits"],
                'access' => attrs["_#{key}_access"], 'options' => attrs["_#{key}_options"],
                'status' => status, 'diagnostic' => diagnostic, 'editable' => false }
            end
          end
        end

        # Preserve supported nonlinear/conditional ATT as editable mm expressions.
        # Inline intermediate scopes so the sheet never mistakes Parent for Module.
        def cell_formula_texts(aliases)
          cache = {}; stack = []; frames = {}; attribute_text = nil; frame_text = nil; ast_text = nil
          literal = ->(value) { Core.number(value).round(10).to_s.sub(/\.0\z/, '') }
          multiply = ->(a, b) { b == '1' ? a : a == '1' ? b : a == '0' || b == '0' ? '0' : "(#{a}) * (#{b})" }
          add = ->(a, b) { b == '0' ? a : a == '0' ? b : "(#{a}) + (#{b})" }
          divide = ->(a, b) { b == '1' ? a : "(#{a}) / (#{b})" }
          ast_text = lambda do |ast, path, scale|
            kind, name, left, right = ast
            case kind
            when :number then literal.call(name)
            when :unary then "#{name}(#{ast_text.call(left, path, scale)})"
            when :reference
              next left if !name && %w[true false].include?(left)
              target = reference_path(path, name)
              divide.call(attribute_text.call(target, left), literal.call(unit(target, left) ? scale : 1))
            when :nominal
              target = reference_path(path, name)
              divide.call(attribute_text.call(target, left), literal.call(nominal_unit(target)))
            when :binary then "(#{ast_text.call(left, path, scale)}) #{name} (#{ast_text.call(right, path, scale)})"
            when :call then "#{name}(#{left.map { |arg| ast_text.call(arg, path, scale) }.join(', ')})"
            else raise Core::Error, 'Chưa chuyển được công thức ô ATT.'
            end
          end
          attribute_text = lambda do |path, key|
            token = [path, key]
            next cache[token] if cache.key?(token)
            raise Core::Error, 'Tham chiếu công thức ô ATT vòng.' if stack.include?(token) || stack.length >= 80
            stack << token
            attrs = @nodes.fetch(path)['attributes']
            formula = attrs["_#{key}_formula"].to_s.strip
            text = if path.empty? && %w[lenx leny lenz].include?(key) && !@root_outputs.include?(key)
                     "Module.#{%w[LenX LenY LenZ][%w[lenx leny lenz].index(key)]}"
                   elsif path.empty? && aliases.key?(key)
                     divide.call(aliases.fetch(key),literal.call(@controls.fetch(key,{}).fetch('override_factor',1.0)))
                   elsif !formula.empty?
                     factor = formula_unit(path, key)
                     multiply.call(ast_text.call(Parser.new(formula, aliases: @aliases).parse, path, factor), literal.call(unit(path, key) ? factor : 1))
                   elsif (axis=native_edge_axis(path,key))
                     "Module.#{%w[LenX LenY LenZ][axis]}"
                   else
                     literal.call(attribute(path, key))
                   end
            raise Core::Error, 'Công thức ô ATT vượt 4096 ký tự.' if text.length > 4096
            cache[token] = text
          ensure
            stack.pop if stack.last == token
          end
          frame_text = lambda do |path, axis, depth|
            next [@construction_inputs ? "Module.#{%w[X Y Z][axis]}" : '0', '1'] if path.empty?
            raise Core::Error, 'Cây công thức vị trí quá sâu.' if depth > 30
            token = [path, axis]
            next frames[token] if frames.key?(token)
            node = @nodes.fetch(path)
            origin, parent_scale = frame_text.call(parent_path(path), axis, depth + 1)
            key = %w[lenx leny lenz][axis]
            formula = node['attributes']["_#{key}_formula"].to_s.strip
            nominal = (authored_frames? || !%w[1 -1].include?(parent_scale)) && !formula.empty? && nominal_length?(Parser.new(formula, aliases: @aliases).parse, path, key) do |condition|
              result = symbolic_expression(condition, path, 1.0)
              raise Core::Error, 'Nhánh đổi hệ tọa độ phụ thuộc tham số.' unless result[1].empty?
              result[0]
            end
            multiplier = nominal ? literal.call(axis_direction(parent_path(path), axis)) : parent_scale
            multiplier = literal.call(authored_scale(parent_path(path),axis)) if authored_frames? && !formula.empty? && !nominal
            origin_key = %w[x y z][axis]
            origin_scale = node['attributes']["_#{origin_key}_formula"].to_s.strip.empty? ? parent_scale : multiplier
            if authored_frames? && formula.empty? && !node['attributes']["_#{origin_key}_formula"].to_s.strip.empty?
              origin_scale = literal.call(authored_scale(parent_path(path),axis))
            end
            origin = add.call(origin, multiply.call(attribute_text.call(path, origin_key), origin_scale))
            span = literal.call(Core.dimensions(node['local_bounds'])[axis] * 25.4)
            direction = node['transform'][[0, 5, 10][axis]].negative? ? '-1' : '1'
            scale = if flat_axis?(node,path,axis)
                      multiply.call(parent_scale,literal.call(DCFrames.captured_scale(node,axis)))
                    else
                      multiply.call(direction, multiply.call(multiplier, divide.call(attribute_text.call(path, key), span)))
                    end
            frames[token] = [origin, scale]
          end
          @nodes.values.select { |node| node['part_key'] }.to_h do |node|
            path = node.key?('parent_id') ? node['id'] : node['path'].join(' / ')
            cells = 6.times.map do |index|
              begin
                axis = index % 3
                origin, scale = frame_text.call(path, axis, 0)
                sign = axis_direction(path, axis)
                length = index < 3 ? Core.dimensions(node['local_bounds'])[axis] * sign : node['local_bounds'][sign.negative? ? 1 : 0][axis]
                text = multiply.call(scale, literal.call(length * 25.4))
                text = add.call(origin, text) if index >= 3
                raise Core::Error, 'Công thức quá dài.' if text.length > 4096
                text
              rescue Core::Error
                nil
              end
            end
            [node['part_key'], cells]
          end
        end

        def has_cell_formula?(part_key, index)
          node = @nodes.values.find { |entry| entry['part_key'] == part_key }
          return false unless node
          axis = index % 3
          key = index < 3 ? %w[lenx leny lenz][axis] : %w[x y z][axis]
          30.times do
            return true unless node['attributes']["_#{key}_formula"].to_s.strip.empty?
            # Nonzero local origins also move when that panel is resized.
            path = node.key?('parent_id') ? node['id'] : node['path'].join(' / ')
            local_side = axis_direction(path, axis).negative? ? 1 : 0
            if index >= 3 && node['local_bounds'][local_side][axis].abs > 1.0e-9 &&
               !node['attributes']["_#{%w[lenx leny lenz][axis]}_formula"].to_s.strip.empty?
              return true
            end
            parent = parent_path(path)
            return false if parent.empty?
            node = @nodes.fetch(parent)
          end
          false
        end
      end
    end

  end
end
