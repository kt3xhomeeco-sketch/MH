# encoding: UTF-8
require_relative 'thickness_symbols'

module MH
  module ModuleStudio
    # Portable display/grouping data. Native roots and transactions stay outside.
    module OptionsParameters
      extend self

      def rows(rule, values)
        rule = Core.copy_data(rule)
        definitions = Parametric.variables(rule)
        definitions.each { |row| row['value'] = values.fetch(row['binding'],row['value']) if row['binding'] && row['formula'].empty? }
        rule['parametric_variables'] = definitions
        evaluated = Parametric.evaluate_variables(rule)
        params = rule['parameters'].to_h { |param| [param['key'],param] }
        definitions.select { |row| row['exported'] }.map do |row|
          param = params[row['binding']]
          choices=DCOptions.variable_choices(rule,param,definitions)
          choice=DCOptions.selected(choices,row)
          source=choice && definitions.find { |entry| entry['id']==choice['input_id'] }
          input=source && source.slice('id','name','category','unit').merge('value'=>evaluated.fetch(source['id']),
            'editable'=>source['formula'].empty?,'range'=>DCOptions.range(params.fetch(source['binding'])))
          row.slice('id','name','symbol','category','unit','formula').merge(
            'value'=>evaluated.fetch(row['id']),
            'editable'=>(row['formula'].empty? || !!choice) && DCOptions.editable?(rule,param),
            'options'=>choices,'selection'=>choice ? choice['value'] : evaluated.fetch(row['id']),
            'manual_input'=>source && !source['exported'] ? input : nil,'reason'=>DCOptions.reason(rule,param),
            'range'=>param && param['input_range'],
            'thickness_role'=>rule.fetch('thickness_symbol_roles',{})[row['id']])
        end
      end

      def merge_rows(matching,id,name)
        values=matching.map { |row| row['value'] };first=values.first
        mixed=values.any? { |value| value.is_a?(Numeric) && first.is_a?(Numeric) ? (value-first).abs>0.000001 : value!=first }
        limits=matching.filter_map { |row| row['range'] }
        range=limits.empty? ? nil : [limits.map(&:first).max,limits.map(&:last).min]
        matching.first.merge('id'=>id,'name'=>name,'section'=>'Tham số chung','section_id'=>'common',
          'value'=>mixed ? nil : first,'selection'=>mixed ? nil : matching.first['selection'],'mixed'=>mixed,'range'=>range,
          'editable'=>matching.all? { |row| row['editable'] } && (!range || range[0]<=range[1]),
          'targets'=>matching.flat_map { |row| row['targets'] })
      end

      def grouped(modules)
        all = modules.flat_map do |item|
          rows(item['rule'],item['values']).map do |row|
            if row['manual_input']
              input=row['manual_input']
              row=row.merge('manual_input'=>input.merge('id'=>"#{item['pid']}:#{input['id']}",
                'targets'=>[{'pid'=>item['pid'],'variable_id'=>input['id']}]))
            end
            row.merge('id'=>"#{item['pid']}:#{row['id']}",'section'=>item['name'],
              'section_id'=>item['pid'],'targets'=>[{'pid'=>item['pid'],'variable_id'=>row['id']}])
          end
        end
        shared = []
        all.group_by { |row| row['symbol'].to_s.strip.downcase }.each do |symbol,matching|
          next if symbol.empty? || symbol.match?(/\Aatt_\d+\z/) || matching.map { |row| row['section_id'] }.uniq.length<2
          shapes=matching.map do |row|
            [row['category'],row['unit'],Array(row['options']).map { |choice| choice.reject { |key,_value| key=='input_id' } },
             row['manual_input'] && row['manual_input'].values_at('category','unit')]
          end
          next unless shapes.uniq.length==1
          canonical=%w[t1 t2].include?(symbol) ? symbol.upcase : symbol
          common=merge_rows(matching,"common:#{canonical}",%w[T1 T2].include?(canonical) ? "Độ dày #{canonical}" : matching.first['name'])
          if matching.first['manual_input']
            common['manual_input']=merge_rows(matching.map { |row| row['manual_input'] },"common:#{canonical}:manual",matching.first['manual_input']['name'])
          end
          shared << common
          all -= matching
        end
        shared+all
      end
    end
  end
end
