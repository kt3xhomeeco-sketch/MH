# encoding: UTF-8
# Restricted DC evaluator. No model, UI or runtime function discovery.
require_relative 'formula_parser'
require_relative 'dc_frames'
require_relative 'dc_visibility'
require_relative 'dc_dependencies'
require_relative 'dc_custom_inputs'
require_relative 'inactive_geometry'
require_relative 'construction_frame'

module MH
  module ModuleStudio
    module DCFormulas
      LENGTHS = %w[x y z lenx leny lenz].freeze
      UNITS = { 'MILLIMETERS' => 1.0, 'CENTIMETERS' => 10.0, 'METERS' => 1000.0, 'INCHES' => 25.4, 'FEET' => 304.8 }.freeze
      class Program
        attr_reader :controls, :formulas, :visibility, :node_visibility, :root_outputs, :construction_inputs

        def initialize(snapshot)
          snapshot = Core.copy_data(snapshot)
          Core.snapshot!(snapshot)
          @snapshot = snapshot
          @construction_inputs=ConstructionFrame.metadata(snapshot)
          @aliases = DCFormulas.function_aliases(snapshot)
          @parts = snapshot['parts'].to_h { |part| [part['key'], part] }
          graph = snapshot['dc_graph']
          unless graph.is_a?(Hash) && graph['nodes'].is_a?(Array) && graph['nodes'].length.between?(1, 1200)
            raise Core::Error, 'Mẫu chưa lưu cây ATT đầy đủ. Đọc lại module để ưu tiên công thức ATT.'
          end
          @controls = Core.dc_controls(snapshot)
          @nodes = { '' => { 'attributes' => snapshot['dc_inputs'] || {}, 'path' => [], 'name' => 'Module' } }
          @formulas = []
          @asts = {}
          check_frame!(graph['root_frame'], root: true)
          graph['nodes'].each do |node|
            unless node.is_a?(Hash) && node['path'].is_a?(Array) && node['path'].length.between?(1, 30) &&
                   node['path'].all? { |name| name.is_a?(String) && name.length <= 300 } && node['attributes'].is_a?(Hash)
              raise Core::Error, 'Cây ATT không hợp lệ.'
            end
            path = node.key?('parent_id') ? node['id'] : node['path'].join(' / ')
            raise Core::Error, 'ID group trong cây ATT bị trùng/hỏng.' unless path.is_a?(String) && !path.empty? && !@nodes.key?(path)
            check_frame!(node['transform'])
            bounds = node['local_bounds']
            unless bounds.is_a?(Array) && bounds.length == 2 && bounds.all? { |point| point.is_a?(Array) && point.length == 3 && point.all? { |value| value.is_a?(Numeric) && Core.number(value).finite? } }
              raise Core::Error, 'Cây ATT thiếu kích thước group.'
            end
            @nodes[path] = node.merge('attributes' => node['attributes'].transform_keys { |key| key.to_s.downcase })
          end
          @nodes.each_key do |path|
            next if path.empty?
            raise Core::Error, 'Cây ATT thiếu group cha.' unless @nodes.key?(parent_path(path))
          end
          @nodes['']['attributes'] = @nodes['']['attributes'].transform_keys { |key| key.to_s.downcase }
          # Only explicit readonly dimensions independent of every measured root
          # length are outputs. Parent!LenY can then carry thickness through an
          # arbitrary number of child containers without freezing its old value.
          @root_outputs = %w[lenx leny lenz].select do |key|
            attrs = @nodes['']['attributes']
            next false unless ['', 'NONE', 'VIEW'].include?(attrs["_#{key}_access"].to_s.upcase) && !attrs["_#{key}_formula"].to_s.strip.empty?
            dependencies = declared_dimension_dependencies(%w[lenx leny lenz].index(key))
            (dependencies.keys & %w[@lenx @leny @lenz]).empty?
          rescue Core::Error
            false
          end
          keys = @nodes.values.filter_map { |node| node['part_key'] }
          unless keys.sort == snapshot['parts'].map { |part| part['key'] }.sort
            raise Core::Error, 'Cây ATT không khớp các tấm trong module.'
          end
        end

        def check_frame!(frame, root: false)
          unless frame.is_a?(Array) && frame.length == 16 && frame.all? { |value| value.is_a?(Numeric) && Core.number(value).finite? } &&
                 frame.each_with_index.all? do |value, index|
                   [12, 13, 14].include?(index) || ([0, 5, 10].include?(index) && !root ? value.abs > 1.0e-8 : (value - ([0, 5, 10, 15].include?(index) ? 1 : 0)).abs < 1.0e-7)
                 end
            raise Core::Error, 'Dịch ATT hỗ trợ group cùng phương trục, kể cả lật; chưa hỗ trợ xoay lệch trục hoặc scale ở module cha.'
          end
        end

        def parent_path(path)
          node = @nodes.fetch(path)
          node.key?('parent_id') ? node['parent_id'] : node['path'][0...-1].join(' / ')
        end

        # Reflections are captured geometry, never inferred from component names.
        # Supported plans keep rotation guards unchanged, so these signs are fixed.
        def axis_direction(path, axis)
          direction = 1.0
          31.times do
            return direction if path.empty?
            direction *= -1 if @nodes.fetch(path)['transform'][[0, 5, 10][axis]].negative?
            path = parent_path(path)
          end
          raise Core::Error, 'Cây ATT tham chiếu cha vòng hoặc quá sâu.'
        end

        def authored_scale(path,axis)
          value = 1.0
          31.times do
            return value if path.empty?
            value *= DCFrames.captured_scale(@nodes.fetch(path),axis)
            path = parent_path(path)
          end
          raise Core::Error,'Cây hệ tọa độ ATT quá sâu.'
        end

        def authored_frames?
          @snapshot['formula_frame_version']==2
        end

        def unit(path, key)
          attributes = @nodes.fetch(path)['attributes']
          name = attributes["_#{key}_units"].to_s.upcase
          name = attributes["_#{key}_formulaunits"].to_s.upcase if DCFrames.typed_length?(attributes,key)
          name = attributes['_lengthunits'].to_s.upcase if LENGTHS.include?(key) && !UNITS.key?(name)
          LENGTHS.include?(key) ? (UNITS[name] || 25.4) : UNITS[name]
        end

        def formula_unit(path, key)
          attributes = @nodes.fetch(path)['attributes']
          named = attributes["_#{key}_formulaunits"].to_s.upcase
          # FLOAT/STRING results are scalar, but their length references use
          # the declared authoring unit. They do not consume millimeters merely
          # because our internal length values are stored in millimeters.
          if %w[FLOAT STRING].include?(named) && !unit(path, key)
            return UNITS[attributes['_lengthunits'].to_s.upcase] || 1.0
          end
          if !named.empty? && !UNITS.key?(named) && named != 'FLOAT'
            raise Core::Error, "Đơn vị công thức ATT chưa hỗ trợ: #{named}"
          end
          fallback=@snapshot['scalar_formula_units_version']==1 ? UNITS[attributes['_lengthunits'].to_s.upcase] : nil
          UNITS[named] || unit(path, key) || fallback || 1.0
        end

        def flat_axis?(node,path,axis)
          DCFrames.flat_axis?(node,axis) ||
            (Core.dimensions(node['local_bounds'])[axis].abs<=1.0e-8 && attribute(path,%w[lenx leny lenz][axis]).abs<=1.0e-8)
        end

        def prepare_values(values, envelope = nil)
          @values = values
          @envelope = envelope || @snapshot.dig('construction_inputs','envelope') || @snapshot['envelope']
          @cache = {}
          @stack = []
          @formulas = []
          @guards = {}
          @frames = {}
        end

        def evaluate(values, envelope = nil, frozen_parts: nil)
          prepare_values(values,envelope)
          result = {}
          frozen = frozen_parts ? frozen_parts.to_h { |part| [part['key'], part] } : @parts
          @visibility, @node_visibility = if DCVisibility.enabled?(@snapshot)
                                          DCVisibility.states(@snapshot) { |path,key| attribute(path,key) }
                                        else
                                          [@parts.transform_values { |part| part['visible']!=false },[]]
                                        end
          @nodes.each do |path, node|
            next if path.empty?
            %w[hidden copies rotx roty rotz].each do |key|
              next unless node['attributes'].key?("_#{key}_formula")
              @guards[[path, key].join('!')] = attribute(path, key)
            end
            # Intermediate dimensions must agree with the resulting child geometry;
            # they must never implicitly stretch descendants a second time.
            if node['part_key']
              if path=='root:mesh' && node['attributes'].empty? && @parts[node['part_key']]['face_count']==0
                result[node['part_key']]=Core.bounds!(frozen.fetch(node['part_key'])['bounds'])
                next
              end
              # Inactive geometry follows native Scale and is otherwise kept as
              # it currently exists. Restoring its template bounds would enlarge
              # a shrunken module. Guards still reject unsupported activation.
              if @visibility.fetch(node['part_key']) == false
                part = frozen.fetch(node['part_key'])
                unless DCVisibility.enabled?(@snapshot) || part['visible']==false
                  raise Core::Error, 'Chi tiết ẩn đã đổi trạng thái; cần đọc lại module.'
                end
                result[node['part_key']] = Core.bounds!(part['bounds'])
                next
              end
              # DC X/Y/Z locate the entity's axes, which need not coincide with
              # its minimum vertex. Transform the actual local bounds as well;
              # attribute_rules still verifies every resulting bound against the
              # captured geometry before accepting the program.
              origin,scale=world_frame(path)
              endpoints=node['local_bounds'].map do |point|
                point.each_with_index.map { |value,axis| origin[axis]+value*25.4*scale[axis] }
              end
              result[node['part_key']]=[3.times.map { |axis| endpoints.map { |point| point[axis] }.min },
                                       3.times.map { |axis| endpoints.map { |point| point[axis] }.max }]
            end
          end
          outputs=@root_outputs.to_h { |key| [key,declared_dimension(%w[lenx leny lenz].index(key))] }
          InactiveGeometry.align!(result,frozen,@visibility,outputs)
          guides=root_guides
          solid=result.keys.reject { |key| guides.include?(key) || @visibility[key]==false || @parts[key]['face_count']==0 }
          unless guides.empty? || solid.empty?
            union=Core.union(solid.map { |key| {'bounds'=>result.fetch(key)} })
            3.times do |axis|
              key=%w[lenx leny lenz][axis];attrs=@nodes['']['attributes']
              next unless ['', 'NONE', 'VIEW'].include?(attrs["_#{key}_access"].to_s.upcase) && !envelope_dependencies(axis).key?("@#{key}")
              guides.each { |part| result[part]=Core.copy_data(result[part]);2.times { |side| result[part][side][axis]=union[side][axis] } }
            end
          end
          [result, @guards.dup]
        end

        def input_dependencies
          Dependencies.new(@nodes,@aliases,@controls,method(:formula_unit),root_outputs:@root_outputs) { |path,qualifier| reference_path(path,qualifier) }.outputs
        end

        def structural_dependencies(key)
          Dependencies.new(@nodes,@aliases,@controls,method(:formula_unit),root_outputs:@root_outputs) { |path,qualifier| reference_path(path,qualifier) }.outputs(keys:[key])
        end

        def envelope_dependencies(axis)
          guides=root_guides
          nodes=@nodes.reject { |_path,node| guides.include?(node['part_key']) }
          Dependencies.new(nodes,@aliases,@controls,method(:formula_unit),envelope:true,root_outputs:@root_outputs) { |path,qualifier| reference_path(path,qualifier) }
                      .outputs(keys:[LENGTHS[axis],LENGTHS[axis+3],'hidden'])
        end

        def root_guides
          @nodes.values.filter_map do |node|
            key=node['part_key']
            key if node['virtual_root_mesh'] && key && @parts.fetch(key)['face_count']==0
          end
        end

        def declared_dimension_dependencies(axis)
          Dependencies.new(@nodes,@aliases,@controls,method(:formula_unit),envelope:true) { |path,qualifier| reference_path(path,qualifier) }
                      .declared_inputs('',LENGTHS[axis+3])
        end

        def declared_dimension(axis)
          key = LENGTHS[axis+3]
          formula = @nodes.fetch('')['attributes']["_#{key}_formula"].to_s.strip
          return nil if formula.empty?
          ast = Parser.new(formula,aliases:@aliases).parse
          expression(ast,'',formula_unit('',key))*formula_unit('',key)
        end

        def world_frame(path, depth = 0)
          return [@snapshot['construction_inputs'] ? @envelope[0] : [0,0,0], [1, 1, 1]] if path.empty?
          return @frames[path] if @frames.key?(path)
          raise Core::Error, 'Cây ATT tham chiếu cha vòng hoặc quá sâu.' if depth > 30
          node = @nodes.fetch(path)
          parent_origin, parent_scale = world_frame(parent_path(path), depth + 1)
          multipliers = parent_scale.each_with_index.map do |value, axis|
            key = %w[lenx leny lenz][axis]
            formula = node['attributes']["_#{key}_formula"].to_s.strip
            next value if formula.empty?
            ast = Parser.new(formula, aliases: @aliases).parse
            if authored_frames?
              next nominal_length?(ast,path,key) ? axis_direction(parent_path(path),axis) : authored_scale(parent_path(path),axis)
            end
            next value if (value.abs - 1).abs <= 1.0e-7
            next value unless nominal_length?(ast, path, key)
            # This child explicitly requests the parent's physical nominal span.
            # Applying the container's resize again would square that change.
            value.negative? ? -1.0 : 1.0
          end
          origin = %w[x y z].each_with_index.map do |key, axis|
            explicit = !node['attributes']["_#{key}_formula"].to_s.strip.empty?
            multiplier = explicit ? multipliers[axis] : parent_scale[axis]
            if explicit && authored_frames? && node['attributes']["_#{%w[lenx leny lenz][axis]}_formula"].to_s.strip.empty?
              multiplier = authored_scale(parent_path(path),axis)
            end
            parent_origin[axis] + multiplier * attribute(path, key)
          end
          local_size = Core.dimensions(node['local_bounds']).map { |value| value * 25.4 }
          scale = %w[lenx leny lenz].each_with_index.map do |key, axis|
            next parent_scale[axis]*DCFrames.captured_scale(node,axis) if flat_axis?(node,path,axis)
            unless local_size[axis]>1.0e-8
              raise Core::Error, "#{node['name']}: group ATT có kích thước suy biến ở #{key} (công thức yêu cầu #{attribute(path,key).round(6)} mm)."
            end
            direction = node['transform'][[0, 5, 10][axis]].negative? ? -1.0 : 1.0
            span = attribute(path, key)
            raise Core::Error, 'Kích thước ATT phải dương.' unless span.positive?
            multipliers[axis] * direction * span / local_size[axis]
          end
          @frames[path] = [origin, scale]
        end

        def nominal_length?(ast, path, key, &condition)
          type, name, args, right = ast
          return name == 'parent' && args == key if type == :nominal
          return name == 'parent' && args == key if type == :reference
          if type == :binary && %w[+ -].include?(name)
            return nominal_length?(args, path, key, &condition) || nominal_length?(right, path, key, &condition)
          end
          if type == :call && name == 'if'
            return false unless args.drop(1).any? { |branch| possible_nominal_length?(branch, key) }
            value = condition ? condition.call(args.first) : expression(args.first, path, 1.0)
            branch = value.zero? ? 2 : 1
            return nominal_length?(args[branch], path, key, &condition)
          end
          false
        end

        def possible_nominal_length?(ast, key)
          type, name, args, right = ast
          return name == 'parent' && args == key if type == :nominal
          return name == 'parent' && args == key if type == :reference
          return possible_nominal_length?(args, key) || possible_nominal_length?(right, key) if type == :binary && %w[+ -].include?(name)
          type == :call && name == 'if' && args.drop(1).any? { |branch| possible_nominal_length?(branch, key) }
        end

        # Native Scale retains a mirrored direct child's captured right-edge
        # anchor when its length explicitly follows that same parent axis.
        def native_edge_axis(path,key)
          axis=%w[x y z].index(key)
          return unless axis && !path.empty? && authored_frames? && !@construction_inputs && parent_path(path).empty?
          node=@nodes.fetch(path);attrs=node['attributes']
          reversed=node['transform'][axis*5].negative? || (node['local_bounds'][1][axis].abs<0.000001 && node['local_bounds'][0][axis]<-0.000001)
          return unless attrs["_#{key}_formula"].to_s.strip.empty? && reversed &&
                        @snapshot['envelope'][0][axis].abs<0.001 &&
                        (node['transform'][12+axis]*25.4-@snapshot['envelope'][1][axis]).abs<0.001
          length=%w[lenx leny lenz][axis]
          ast=Parser.new(attrs["_#{length}_formula"],aliases:@aliases).parse
          axis if %i[reference nominal].include?(ast[0]) && ast[1]=='parent' && ast[2]==length
        rescue Core::Error
          nil
        end

        def attribute(path, key)
          token = [path, key]
          return @cache[token] if @cache.key?(token)
          raise Core::Error, "ATT tham chiếu vòng: #{path}!#{key}" if @stack.include?(token) || @stack.length >= 80
          @stack << token
          node = @nodes.fetch(path)
          attrs = node['attributes']
          formula = attrs["_#{key}_formula"]
          value = if path.empty? && %w[lenx leny lenz].include?(key) && !@root_outputs.include?(key)
                    Core.dimensions(@envelope)[%w[lenx leny lenz].index(key)]
                  elsif path.empty? && @values.key?(key)
                    Core.number(@values.fetch(key)) / @controls.fetch(key,{}).fetch('override_factor',1.0)
                  elsif formula && !formula.to_s.strip.empty?
                    @asts[token] ||= Parser.new(formula, aliases: @aliases).parse
                    @formulas << { 'path' => node['path'].join(' / '), 'node_id' => path, 'attribute' => key, 'formula' => formula.to_s }
                    evaluated = expression(@asts[token], path, formula_unit(path, key))
                    evaluated * (unit(path, key) ? formula_unit(path, key) : 1.0)
                  elsif !path.empty? && key == 'copy' && !attrs.key?(key)
                    # SketchUp omits COPY on the original instance (index zero).
                    # Explicit instance attributes retain their captured index.
                    0.0
                  elsif !path.empty? && LENGTHS.include?(key)
                    index = %w[x y z].index(key)
                    anchor=native_edge_axis(path,key)
                    anchor ? @envelope[1][anchor] : index ? node['transform'][12 + index] * 25.4 : Core.dimensions(node['local_bounds'])[%w[lenx leny lenz].index(key)] * node['transform'][[0, 5, 10][%w[lenx leny lenz].index(key)]].abs * 25.4
                  elsif attrs.key?(key)
                    Core.number(attrs[key]) * (unit(path, key) ? 25.4 : 1.0)
                  else
                    raise Core::Error, "Thiếu ATT #{node['name']}!#{key}."
                  end
          @cache[token] = Core.number(value)
        rescue KeyError
          raise Core::Error, "Tham chiếu ATT không tồn tại: #{path}!#{key}"
        ensure
          @stack.pop if @stack.last == token
        end

        def expression(ast, path, scale)
          type, name, left, right = ast
          case type
          when :number then name
          when :unary then (name == '-' ? -1 : 1) * expression(left, path, scale)
          when :reference
            return 1.0 if !name && left == 'true'
            return 0.0 if !name && left == 'false'
            target = reference_path(path, name)
            attribute(target, left) / (unit(target, left) ? scale : 1.0)
          when :nominal
            target = reference_path(path, name)
            attribute(target, left) / nominal_unit(target)
          when :binary
            a = expression(left, path, scale)
            b = expression(right, path, scale)
            binary(name, a, b)
          when :call
            if name == 'if'
              return expression(left[expression(left[0], path, scale).zero? ? 2 : 1], path, scale)
            end
            if name == 'choose'
              index = DCFormulas.choice_index(expression(left.first, path, scale), left.length - 1)
              return expression(left[index], path, scale)
            end
            values = left.map { |argument| expression(argument, path, scale) }
            DCFormulas.numeric_function(name, values)
          end
        end

        def nominal_unit(path)
          name = @nodes.fetch(path)['attributes']['_lengthunits'].to_s.upcase
          return 10.0 if name.empty? || name == 'CENTIMETERS'
          return 25.4 if name == 'INCHES'
          raise Core::Error, "Hàm kích thước danh nghĩa chưa hỗ trợ đơn vị #{name}."
        end

        def reference_path(path, qualifier)
          return path unless qualifier
          return parent_path(path) if qualifier == 'parent' && !path.empty?
          # A child can name its own container even when another branch has the
          # same DC name. Prefer the current ancestor chain, never a random copy.
          scope = path
          loop do
            node = @nodes.fetch(scope)
            return scope if [node['name'], node['attributes']['_name']].any? { |name| name.to_s.downcase == qualifier }
            break if scope.empty?
            scope = parent_path(scope)
          end
          matches = @nodes.select do |_key, node|
            [node['name'], node['attributes']['_name']].any? { |name| name.to_s.downcase == qualifier }
          end.keys
          raise Core::Error, "Tham chiếu ATT không rõ group: #{qualifier}" unless matches.length == 1
          matches.first
        end

        def binary(operator, a, b)
          DCFormulas.binary(operator, a, b)
        end
      end

    end
  end
end
