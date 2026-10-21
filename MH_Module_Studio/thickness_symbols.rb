# encoding: UTF-8
require_relative 'parametric'

module MH
  module ModuleStudio
    module ThicknessSymbols
      extend self

      def thickness?(bundle, key)
        # Rail clearance is represented by a box-shaped marker in some DCs; its
        # explicit hardware label must not merge it into the board thickness T2.
        parameter = bundle['parameters'].find { |entry| entry['key']==key }
        return false if parameter && parameter['label'].to_s.match?(/\Aray\b/i)
        bundle.fetch('constraints',[]).any? { |entry| entry['type']=='thickness' && entry['parameter']==key } ||
          bundle.fetch('rules',{}).fetch(key,{}).fetch('parts',[]).any? { |part| part['driver'] }
      end

      def role(value)
        return unless value.is_a?(Numeric) && value.finite?
        value = value.round(6)
        return 'T1' if value.between?(17,18.6)
        'T2' if value.positive? && value<17
      end

      def normalize(bundle)
        return Core.copy_data(bundle) if bundle['thickness_symbols_version']==2
        bundle = Core.copy_data(bundle)
        rows = Parametric.variables(bundle)
        params = bundle['parameters'].to_h { |param| [param['key'],param] }
        assignments = rows.filter_map do |row|
          param = params[row['binding']]
          next unless param && param['unit']=='mm' && thickness?(bundle,param['key'])
          name = role(param['value'])
          [row['id'],name] if name
        end.to_h
        roles = {}
        aliases = bundle.fetch('parameter_binding_aliases',{}).dup
        renames = {}
        removed = []
        assignments.group_by { |_id,name| name }.each do |symbol,entries|
          ids = entries.map(&:first)
          members = rows.select { |row| ids.include?(row['id']) }
          primary = members.min_by { |row| params[row['binding']]['label'].match?(/ván|panel/i) ? 0 : 1 }
          members.each do |row|
            renames[row['symbol'].downcase] = symbol
            renames[row['binding'].downcase] = symbol
            next if row.equal?(primary)
            unless params[row['binding']]['editable'] && params[primary['binding']]['editable']
              raise Core::Error,'Chưa thể gộp tham số độ dày không có quy tắc điều khiển.'
            end
            aliases[row['binding']] = primary['binding']
            anchor_merged_parts!(bundle,row['binding'],symbol,params[primary['binding']]['value'],params[row['binding']]['value'])
            removed << row['id']
          end
          primary['exported'] = members.any? { |row| row['exported'] }
          primary['symbol'] = symbol
          roles[primary['id']] = symbol
        end
        rows.reject! { |row| removed.include?(row['id']) }
        rows.each { |row| row['formula'] = ParameterRename.expression(row['formula'],renames) }
        bundle.fetch('part_formulas',{}).each_value { |cells| cells.transform_values! { |text| ParameterRename.expression(text,renames,detail:true) } }
        bundle['parameter_binding_aliases'] = aliases
        bundle['parametric_variables'] = Core.copy_data(rows)
        result = Parametric.edit_variables(bundle,rows)
        result['thickness_symbols_version'] = 2
        result['thickness_symbol_roles'] = roles
        result
      end

      def anchor_merged_parts!(bundle, key, symbol, shared_value, old_value)
        return if (shared_value-old_value).abs<0.000001
        drivers = bundle.fetch('rules',{}).fetch(key,{}).fetch('parts',[]).select { |part| part['driver'] }.map { |part| part['key'] }
        drivers |= bundle.fetch('constraints',[]).select { |entry| entry['type']=='thickness' && entry['parameter']==key }.map { |entry| entry['face']['part'] }
        bundle['parts'].each do |part|
          next unless drivers.include?(part['key']) && part['thickness_axis']
          axis = part['thickness_axis']
          next if Array(bundle.dig('formula_engine','envelope_policy','axes')).include?(axis)
          bounds = part['base_bounds'] || part['bounds']
          next unless (bounds[1][axis]-bundle['envelope'][1][axis]).abs<0.02 && (bounds[0][axis]-bundle['envelope'][0][axis]).abs>0.02
          field = %w[x y z][axis]
          cells = (bundle['part_formulas'] ||= {})[part['key']] ||= {}
          next if cells[field]
          text = "Module.#{%w[X Y Z][axis]} + Module.#{%w[LenX LenY LenZ][axis]} - #{symbol}"
          cells[field] = text
          (bundle['thickness_merge_anchors'] ||= []) << {'part'=>part['key'],'field'=>field,'formula'=>text}
        end
      end

      def merge_reference(bundle)
        anchors = bundle.fetch('thickness_merge_anchors',[]).select do |entry|
          cells = bundle.dig('part_formulas',entry['part'])
          cells && cells.keys==[entry['field']] && cells[entry['field']]==entry['formula'] &&
            !bundle.fetch('part_formula_parts',[]).include?(entry['part'])
        end.map { |entry| entry['part'] }
        return [] if anchors.empty?
        source = bundle.dig('formula_engine','attribute_program','parts') || bundle['parts'].map { |part| part.merge('bounds'=>part['base_bounds']) }
        source.select do |part|
          anchors.include?(part['key']) || (!bundle.fetch('part_formulas',{}).key?(part['key']) &&
            !bundle.fetch('part_formula_parts',[]).include?(part['key']) && bundle.fetch('constraints',[]).none? do |entry|
              entry['enabled'] && entry['drive'] && entry['type']!='thickness' && %w[face other third].any? { |key| entry.dig(key,'part')==part['key'] }
            end)
        end
      end
    end
  end
end
