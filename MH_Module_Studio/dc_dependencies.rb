# encoding: UTF-8
module MH
  module ModuleStudio
    module DCFormulas
      class Dependencies
        def initialize(nodes, aliases, controls, units, envelope: false, root_outputs: [], &resolve)
          @nodes = nodes; @aliases = aliases; @controls = controls
          @units = units; @resolve = resolve; @cache = {}; @stack = []
          @envelope = envelope
          @root_outputs = root_outputs
        end

        def outputs(keys: LENGTHS+%w[hidden copies rotx roty rotz])
          result = {}
          @nodes.each_key do |path|
            next if path.empty?
            keys.each do |key|
              type = key=='hidden' ? 'visibility' : %w[copies rotx roty rotz].include?(key) ? 'structure' : 'geometry'
              begin
                dependencies = inputs(path,key)
              rescue Core::Error
                raise if @envelope
                # Inactive geometry can contain unsupported formulas. Its
                # activation still goes through the numeric evaluator/guards.
                next
              end
              dependencies.each do |input,probes|
                entry = result[input] ||= {'types'=>[],'probes'=>[]}
                entry['types'] |= [type]
                entry['probes'] = (entry['probes']+probes).uniq.first(64)
              end
            end
          end
          result
        end

        def inputs(path,key)
          token = [path,key]
          root_length = path.empty? && LENGTHS.include?(key) && !@root_outputs.include?(key)
          return {"@#{key}"=>[]} if @envelope && root_length
          return {key=>[]} if path.empty? && @controls[key]&.dig('display_value').is_a?(Numeric) && !LENGTHS.include?(key)
          return @cache[token] if @cache.key?(token)
          raise Core::Error,'Phụ thuộc ATT vòng hoặc quá sâu.' if @stack.include?(token) || @stack.length>=80
          formula = @nodes.fetch(path)['attributes']["_#{key}_formula"].to_s.strip
          return @cache[token]={} if formula.empty? || root_length
          @stack << token
          ast = Parser.new(formula,aliases:@aliases).parse
          dependencies = walk(ast,path)
          hints = literals(ast).map { |value| value*@units.call(path,key) }
          @cache[token] = dependencies.transform_values { |values| (values+hints).uniq.first(64) }
        ensure
          @stack.pop if @stack.last==token
        end

        def walk(ast,path)
          type,name,left,right = ast
          return inputs(@resolve.call(path,name),left) if (type==:reference && !(!name && %w[true false].include?(left))) || (type==:nominal && @envelope)
          return {} if %i[number reference nominal].include?(type)
          children = type==:call ? left : type==:binary ? [left,right] : [left]
          children.each_with_object({}) do |child,result|
            walk(child,path).each { |key,values| result[key] = (result.fetch(key,[])+values).uniq.first(64) }
          end
        end

        # Root dimensions normally resolve to measured envelope inputs. Inspect
        # a declared root formula separately without replacing that input rule.
        def declared_inputs(path,key)
          formula = @nodes.fetch(path)['attributes']["_#{key}_formula"].to_s.strip
          formula.empty? ? {} : walk(Parser.new(formula,aliases:@aliases).parse,path)
        end

        def literals(ast)
          type,name,left,right = ast
          return [name] if type==:number
          return [] if %i[reference nominal].include?(type)
          children = type==:call ? left : type==:binary ? [left,right] : [left]
          values = children.flat_map { |child| literals(child) }
          type==:unary && name=='-' ? values.map { |value| -value } : values
        end

        def self.probes(value, hints, range)
          step = [1.0,value.abs*0.1].max
          candidates = [value+0.1,value-0.1]
          candidates += hints.flat_map { |hint| [hint,hint-0.001,hint+0.001] }
          candidates += [value+step,value-step,value*2,value*0.5,0,1]
          candidates.select { |candidate| candidate.finite? && candidate.between?(*range) && (candidate-value).abs>1.0e-8 }.uniq.first(8)
        end
      end
    end
  end
end
