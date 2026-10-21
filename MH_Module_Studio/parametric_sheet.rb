# encoding: UTF-8
require_relative 'parametric_program'

module MH
  module ModuleStudio
    module ParametricSheet
      extend self

      def affine_text(expression, aliases)
        constant, coefficients = expression
        terms = coefficients.reject { |_key, value| value.abs < 1.0e-8 }.sort_by { |key, _value| [key.start_with?('@') ? 0 : 1, key] }.map do |key, value|
          name = aliases.fetch(key, key)
          name = "Module.#{%w[LenX LenY LenZ][%w[@lenx @leny @lenz].index(key)]}" if %w[@lenx @leny @lenz].include?(key)
          factor = value.abs.round(8)
          [value < 0 ? -1 : 1, factor == 1 ? name : "#{factor.to_s.sub(/\.0\z/, '')} * #{name}"]
        end
        terms << [constant < 0 ? -1 : 1, constant.abs.round(8).to_s.sub(/\.0\z/, '')] if constant.abs >= 1.0e-8
        text = terms.each_with_index.map { |(sign, term), index| "#{index.zero? ? (sign < 0 ? '-' : '') : (sign < 0 ? ' - ' : ' + ')}#{term}" }.join
        text.empty? ? '0' : text
      end

      def cell_expressions(bundle, snapshot, plan, parts, rows)
        engine = bundle['formula_engine']
        envelope = plan&.fetch('formula_envelope',nil) || (engine && EnvelopePolicy.inputs(snapshot,engine['attribute_program'],engine['envelope_policy'])) || snapshot['envelope']
        program = engine && engine['attribute_program'] && DCFormulas::ParametricProgram.new(engine['attribute_program'])
        if engine && DCCopies.enabled?(engine)
          inputs = Core.parameter_values(engine,snapshot).merge(plan ? plan['target'] : {})
          expanded, = DCCopies.expanded(engine['attribute_program'],inputs,plan ? plan['envelope'] : snapshot['envelope'])
          program = DCFormulas::ParametricProgram.new(expanded)
        end
        symbolic = program ? program.symbolic_positions : {}
        values = program ? program.controls.transform_values { |control| control['display_value'] } : {}
        values.merge!(bundle['parameters'].to_h { |param| [param['key'], param['value']] })
        values.merge!(Core.parameter_values(engine, snapshot)) if engine
        values.merge!(plan['target']) if plan
        Core.dimensions(envelope).each_with_index { |v, i| values["@#{%w[lenx leny lenz][i]}"] = v }
        aliases = Parametric.binding_rows(bundle,rows).transform_values { |row| row['symbol'] }
        bindings_by_symbol = aliases.to_h { |binding, symbol| [symbol.downcase, binding] }
        full_texts = program ? program.cell_formula_texts(aliases) : {}
        active = bundle['constraints'].select { |entry| entry['enabled'] && entry['drive'] && !%w[formula position].include?(entry['type']) }
        parts.to_h do |part|
          expressions = 6.times.map do |index|
            override = bundle.dig('part_formulas', part['key'], Parametric::PART_FIELDS[index])
            next({ 'text' => override, 'kind' => 'manual', 'variables' => [] }) if override
            axis = index % 3
            relevant = active.select { |entry| %w[face other third].any? { |key| entry[key] && entry[key]['part'] == part['key'] && entry[key]['axis'] == axis } }
            thickness = relevant.find { |entry| index < 3 && entry['type'] == 'thickness' && entry['face']['part'] == part['key'] }
            if thickness
              next({ 'text' => aliases.fetch(thickness['parameter'], thickness['parameter']), 'kind' => 'rule', 'variables' => [thickness['parameter']] })
            end
            next({ 'text' => 'Quy tắc module', 'kind' => 'rule', 'variables' => [] }) unless relevant.empty?
            low = symbolic.dig(part['key'], 0, axis)
            high = symbolic.dig(part['key'], 1, axis)
            expression = index < 3 ? (low && high && AffinePosition.add(high, low, -1)) : low
            if expression
              constant, coefficients = expression
              expected = index < 3 ? Core.dimensions(part['bounds'])[axis] : part['bounds'][0][axis]
              known = coefficients.keys.all? { |key| values[key].is_a?(Numeric) }
              result = known && constant + coefficients.sum { |key, factor| factor * values[key] }
              if known && (result - expected).abs < 0.001
                keys = coefficients.select { |_key, factor| factor.abs >= 1.0e-8 }.keys
                text = keys.empty? && !program.has_cell_formula?(part['key'], index) ? '' : affine_text(expression, aliases)
                next({ 'text' => text, 'kind' => 'att', 'variables' => keys })
              end
            end
            full = full_texts.dig(part['key'], index)
            if full && part['visible'] != false
              begin
                ast = DCFormulas::Parser.new(full.gsub(/\bModule\.(lenx|leny|lenz)\b/i, 'Module!\1')).parse
                calculated = Parametric.numeric_expression(ast) do |scope, key|
                  next Core.dimensions(envelope)[%w[lenx leny lenz].index(key)] if scope == 'module'
                  next key == 'true' ? 1.0 : 0.0 if scope.nil? && %w[true false].include?(key)
                  original = bindings_by_symbol[key]
                  values.fetch(original || key)
                end
                expected = index < 3 ? Core.dimensions(part['bounds'])[axis] : part['bounds'][0][axis]
                next({ 'text' => full, 'kind' => 'att', 'variables' => [] }) if (calculated - expected).abs < 0.001
              rescue Core::Error, KeyError
                # Keep the original ATT diagnostic when an expression cannot be translated.
              end
            end
            { 'text' => '', 'kind' => program ? 'att_raw' : 'measured', 'variables' => [] }
          end
          [part['key'], expressions]
        end
      end

      def sheet(bundle, snapshot, plan = nil)
        rows = Parametric.variables(bundle)
        evaluated = Parametric.evaluate_variables(bundle)
        params = bundle['parameters'].to_h { |p| [p['key'], p] }
        parts = plan ? plan['parts'] : snapshot['parts']
        attrs = describe(bundle, snapshot, plan && plan['target'], envelope: plan && (plan['formula_envelope'] || plan['envelope']))
        attr_index = attrs.to_h { |r| [[r['node_id'], r['key']], r] }
        graph = bundle.dig('formula_engine', 'attribute_program', 'dc_graph', 'nodes') || []
        nodes = graph.to_h { |node| [node['id'] || node['path'].join(' / '), node] }
        part_nodes = graph.select { |node| node['part_key'] }.to_h { |node| [node['part_key'], node] }
        expressions = cell_expressions(bundle, snapshot, plan, parts, rows)
        { 'rule_id' => bundle['id'], 'categories' => Core.copy_data(Parametric::CATEGORIES),
          'variables' => rows.map do |row|
            param = params[row['binding']]
            row.merge('computed_value' => evaluated[row['id']], 'editable' => DCOptions.editable?(bundle,param),
                      'options'=>DCOptions.variable_choices(bundle,param,rows),
                      'source' => param ? (DCOptions.input?(bundle,param) ? 'dc_attributes' : param['rule_source']) : 'manual', 'source_formula'=>param && param.dig('dc_attribute','formula'),
                      'reason' => DCOptions.reason(bundle,param))
          end,
          'parts' => parts.map do |part|
            node = part_nodes[part['key']]
            lineage = []
            while node && lineage.length <= 30
              id = node['id'] || node['path'].join(' / ')
              lineage << id
              node = nodes[node['parent_id'] || node['path'][0...-1].join(' / ')]
            end
            size = Core.dimensions(part['bounds'])
            part.slice('key', 'name', 'path').merge('name'=>bundle.fetch('part_names',{}).fetch(part['key'],part['name']),'values' => size + part['bounds'][0], 'expressions' => expressions.fetch(part['key']),
              'formulas' => %w[lenx leny lenz x y z].map do |key|
                lineage.filter_map do |id|
                  row = attr_index[[id, key]]
                  row && !row['formula'].empty? && "#{row['path']} [#{id}]: #{row['formula']}"
                end.join(' | ')
              end)
          end, 'attributes' => attrs }
      end

      def describe(bundle, snapshot, targets = nil, envelope: nil)
        engine = bundle['formula_engine']
        program = engine && engine['attribute_program']
        return [] unless program
        values = Core.parameter_values(engine, snapshot)
        values = values.merge(targets) if targets
        program = DCFormulas::ParametricProgram.new(program)
        if DCCopies.enabled?(engine)
          expanded, = DCCopies.expanded(engine['attribute_program'],values,envelope || snapshot['envelope'])
          program = DCFormulas::ParametricProgram.new(expanded)
        end
        inputs = bundle['parameters'].map { |p| p['key'] }
        frame = envelope || EnvelopePolicy.inputs(snapshot,engine['attribute_program'],engine['envelope_policy'])
        program.parametric_attributes(values, frame).reject do |row|
          row['node_id'].empty? && inputs.include?(row['key'])
        end
      end
    end
  end
end
