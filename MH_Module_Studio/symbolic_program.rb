# encoding: UTF-8
require_relative 'formulas'

module MH
  module ModuleStudio
    module AffinePosition
      extend self
      def constant(value)
        [Core.number(value), {}]
      end

      def variable(key)
        [0.0, { key => 1.0 }]
      end

      def add(a, b, factor = 1.0)
        terms = a[1].dup
        b[1].each { |key, value| terms[key] = terms.fetch(key, 0.0) + value * factor }
        terms.delete_if { |_key, value| value.abs < 1.0e-9 }
        [a[0] + b[0] * factor, terms]
      end

      def scale(a, value)
        [a[0] * value, a[1].transform_values { |coefficient| coefficient * value }]
      end

      def multiply(a, b)
        return scale(b, a[0]) if a[1].empty?
        return scale(a, b[0]) if b[1].empty?
        raise Core::Error, 'Biểu thức vị trí không tuyến tính; giữ công thức ATT gốc.'
      end

      def divide(a, b)
        raise Core::Error, 'Biểu thức vị trí có mẫu số thay đổi; giữ công thức ATT gốc.' unless b[1].empty? && b[0].abs > 1.0e-12
        scale(a, 1.0 / b[0])
      end
    end

    module DCFormulas
      class SymbolicProgram < Program
        def symbolic_positions
          evaluate(Core.formula_values(@snapshot, @controls))
          @position_cache = {}
          @position_frames = {}
          @position_stack = []
          @nodes.values.filter_map do |node|
            next unless node['part_key']
            path = node.key?('parent_id') ? node['id'] : node['path'].join(' / ')
            coordinates = 2.times.map do |side|
              3.times.map do |axis|
                begin
                  origin, scale = symbolic_frame(path, axis)
                  local_side = axis_direction(path, axis).negative? ? 1 - side : side
                  AffinePosition.add(origin, AffinePosition.scale(scale, node['local_bounds'][local_side][axis] * 25.4))
                rescue Core::Error
                  nil
                end
              end
            end
            [node['part_key'], coordinates]
          end.to_h
        end

        def symbolic_frame(path, axis, depth = 0)
          return [AffinePosition.constant(0), AffinePosition.constant(1)] if path.empty?
          raise Core::Error, 'Cây vị trí ATT vòng hoặc quá sâu.' if depth > 30
          token = [path, axis]
          return @position_frames[token] if @position_frames.key?(token)
          node = @nodes.fetch(path)
          parent_origin, parent_scale = symbolic_frame(parent_path(path), axis, depth + 1)
          length_key = %w[lenx leny lenz][axis]
          formula = node['attributes']["_#{length_key}_formula"].to_s.strip
          unit_scale = parent_scale[1].empty? && (parent_scale[0].abs - 1).abs <= 1.0e-7
          physical_nominal = (authored_frames? || !unit_scale) && !formula.empty? && nominal_length?(Parser.new(formula, aliases: @aliases).parse, path, length_key) do |condition|
            test = symbolic_expression(condition, path, 1.0)
            raise Core::Error, 'Nhánh ATT phụ thuộc tham số; giữ công thức gốc.' unless test[1].empty?
            test[0]
          end
          multiplier = physical_nominal ? AffinePosition.constant(axis_direction(parent_path(path), axis)) : parent_scale
          multiplier = AffinePosition.constant(authored_scale(parent_path(path),axis)) if authored_frames? && !formula.empty? && !physical_nominal
          origin_key = %w[x y z][axis]
          origin_scale = node['attributes']["_#{origin_key}_formula"].to_s.strip.empty? ? parent_scale : multiplier
          if authored_frames? && formula.empty? && !node['attributes']["_#{origin_key}_formula"].to_s.strip.empty?
            origin_scale = AffinePosition.constant(authored_scale(parent_path(path),axis))
          end
          origin = AffinePosition.add(parent_origin, AffinePosition.multiply(origin_scale, symbolic_attribute(path, origin_key)))
          span = Core.dimensions(node['local_bounds'])[axis] * 25.4
          direction = node['transform'][[0, 5, 10][axis]].negative? ? -1.0 : 1.0
          scale = if flat_axis?(node,path,axis)
                    AffinePosition.scale(parent_scale,DCFrames.captured_scale(node,axis))
                  else
                    AffinePosition.scale(AffinePosition.multiply(multiplier, symbolic_attribute(path, length_key)), direction / span)
                  end
          @position_frames[token] = [origin, scale]
        end

        def symbolic_attribute(path, key)
          token = [path, key]
          return @position_cache[token] if @position_cache.key?(token)
          raise Core::Error, 'Tham chiếu vị trí ATT vòng.' if @position_stack.include?(token) || @position_stack.length >= 80
          @position_stack << token
          attrs = @nodes.fetch(path)['attributes']
          formula = attrs["_#{key}_formula"]
          guard = [path, key].join('!')
          # Accepted plans already require these topology/rotation guards to
          # stay unchanged. Their branch is fixed within the compiled rule.
          result = if @guards.key?(guard)
                     AffinePosition.constant(@guards.fetch(guard))
                   elsif path.empty? && %w[lenx leny lenz].include?(key) && !@root_outputs.include?(key)
                     AffinePosition.variable("@#{key}")
                   elsif path.empty? && @controls[key] && (@controls[key]['unit'] == 'mm' || @controls[key]['source']=='custom_constant') && @controls[key]['display_value'].is_a?(Numeric)
                     AffinePosition.scale(AffinePosition.variable(key),1.0/@controls[key].fetch('override_factor',1.0))
                   elsif formula && !formula.to_s.strip.empty?
                     result = symbolic_expression(Parser.new(formula, aliases: @aliases).parse, path, formula_unit(path, key))
                     AffinePosition.scale(result, unit(path, key) ? formula_unit(path, key) : 1.0)
                   elsif !path.empty? && LENGTHS.include?(key)
                     node = @nodes.fetch(path)
                     axis = %w[x y z].index(key)
                     value = axis ? node['transform'][12 + axis] * 25.4 : Core.dimensions(node['local_bounds'])[%w[lenx leny lenz].index(key)] * node['transform'][[0, 5, 10][%w[lenx leny lenz].index(key)]].abs * 25.4
                     anchor=native_edge_axis(path,key)
                     anchor ? AffinePosition.variable("@#{%w[lenx leny lenz][anchor]}") : AffinePosition.constant(value)
                   elsif !path.empty? && key == 'copy' && !attrs.key?(key)
                     AffinePosition.constant(0)
                   elsif attrs.key?(key)
                     AffinePosition.constant(Core.number(attrs[key]) * (unit(path, key) ? 25.4 : 1.0))
                   else
                     raise Core::Error, 'Thiếu thuộc tính vị trí ATT.'
                   end
          @position_cache[token] = result
        ensure
          @position_stack.pop if @position_stack.last == token
        end

        def symbolic_expression(ast, path, scale)
          type, name, left, right = ast
          case type
          when :number then AffinePosition.constant(name)
          when :unary then AffinePosition.scale(symbolic_expression(left, path, scale), name == '-' ? -1 : 1)
          when :reference
            return AffinePosition.constant(left == 'true' ? 1 : 0) if !name && %w[true false].include?(left)
            target = reference_path(path, name)
            AffinePosition.scale(symbolic_attribute(target, left), unit(target, left) ? 1.0 / scale : 1.0)
          when :nominal
            target = reference_path(path, name)
            AffinePosition.scale(symbolic_attribute(target, left), 1.0 / nominal_unit(target))
          when :binary
            a = symbolic_expression(left, path, scale)
            b = symbolic_expression(right, path, scale)
            case name
            when '+' then AffinePosition.add(a, b)
            when '-' then AffinePosition.add(a, b, -1)
            when '*' then AffinePosition.multiply(a, b)
            when '/' then AffinePosition.divide(a, b)
            else
              raise Core::Error, 'Điều kiện vị trí phụ thuộc tham số; giữ ATT gốc.' unless a[1].empty? && b[1].empty?
              AffinePosition.constant(binary(name, a[0], b[0]))
            end
          when :call
            if name == 'if' || name == 'choose'
              selector = symbolic_expression(left.first, path, scale)
              raise Core::Error, 'Nhánh vị trí phụ thuộc tham số; giữ ATT gốc.' unless selector[1].empty?
              index = name == 'if' ? (selector[0].zero? ? 2 : 1) : DCFormulas.choice_index(selector[0], left.length - 1)
              return symbolic_expression(left[index], path, scale)
            end
            arguments = left.map { |argument| symbolic_expression(argument, path, scale) }
            raise Core::Error, 'Hàm vị trí phụ thuộc tham số; giữ ATT gốc.' unless arguments.all? { |argument| argument[1].empty? }
            AffinePosition.constant(DCFormulas.numeric_function(name, arguments.map(&:first)))
          else
            raise Core::Error, 'Biểu thức vị trí có hàm/điều kiện; giữ ATT gốc.'
          end
        end
      end
    end

  end
end
