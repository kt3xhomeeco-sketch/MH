# encoding: UTF-8
module MH
  module ModuleStudio
    # New reads promote referenced numeric root constants to own inputs. Saved
    # legacy programs keep their original controls until explicitly read again.
    module DCCustomInputs
      extend self
      RESERVED=%w[x y z lenx leny lenz rotx roty rotz hidden copies copy material onclick scaletool].freeze

      def candidate?(attrs,key)
        !key.start_with?('_') && !RESERVED.include?(key) &&
          !%w[TEXTBOX LIST].include?(attrs["_#{key}_access"].to_s.upcase) &&
          attrs["_#{key}_formula"].to_s.strip.empty? && Core.dc_value(attrs[key]).is_a?(Numeric)
      end

      def enable(snapshot)
        data=Core.copy_data(snapshot)
        data.delete('custom_numeric_inputs')
        attrs=data.fetch('dc_inputs',{})
        candidates=attrs.keys.select { |key| candidate?(attrs,key) }
        return data if candidates.empty? || !data['dc_graph']
        program=DCFormulas::Program.new(data)
        aliases=DCFormulas.function_aliases(data)
        nodes={''=>{'attributes'=>attrs}}
        data['dc_graph']['nodes'].each { |node| nodes[node.key?('parent_id') ? node['id'] : node['path'].join(' / ')]=node }
        uses=Hash.new { |hash,key| hash[key]=[] }
        cache={};trace=nil
        trace=lambda do |path,key,stack|
          token=[path,key]
          next cache[token] if cache.key?(token)
          next [] if stack.include?(token) || stack.length>=80
          next [key] if path.empty? && candidates.include?(key)
          formula=nodes.fetch(path)['attributes']["_#{key}_formula"].to_s.strip
          next [] if formula.empty?
          ast=DCFormulas::Parser.new(formula,aliases:aliases).parse
          refs=references(ast)
          cache[token]=refs.flat_map { |scope,name| trace.call(program.reference_path(path,scope),name,stack+[token]) }.uniq
        rescue Core::Error,KeyError
          []
        end
        virtual=data['dc_graph']['nodes'].any? { |entry| entry['virtual_root_mesh'] }
        nodes.each do |path,node|
          next if node['virtual_root_mesh'] || (path.empty? && !virtual)
          (DCFormulas::LENGTHS+%w[hidden copies rotx roty rotz]).each do |key|
            formula=node['attributes']["_#{key}_formula"].to_s.strip
            next if formula.empty?
            found=trace.call(path,key,[])
            next if found.empty?
            ast=DCFormulas::Parser.new(formula,aliases:aliases).parse
            direct=ast[0]==:reference && program.reference_path(path,ast[1]).empty? && candidates.include?(ast[2])
            # Infer mm only from unambiguous direct length consumers. Counts,
            # ratios and mixed uses retain their numeric scalar meaning.
            factor=direct && DCFormulas::LENGTHS.include?(key) ? program.formula_unit(path,key) : nil
            found.each { |name| uses[name] << factor }
          rescue Core::Error
            next
          end
        end
        rows=uses.to_h do |key,factors|
          length=DCFrames::LENGTH_UNITS.include?(attrs["_#{key}_units"].to_s.upcase) || DCFrames.typed_length?(attrs,key)
          inferred=!length && factors.none?(&:nil?) && factors.uniq.length==1 && factors.first.positive?
          factor=length ? 25.4 : inferred ? factors.first : 1.0
          [key,{'unit'=>length || inferred ? 'mm' : '', 'value_factor'=>factor,'override_factor'=>inferred ? factor : 1.0}]
        end
        data['custom_numeric_inputs']={'version'=>1,'inputs'=>rows} unless rows.empty?
        data
      rescue Core::Error
        data
      end

      def references(ast)
        type,name,left,right=ast
        return [[name,left]] if %i[reference nominal].include?(type) && !(name.nil? && %w[true false].include?(left))
        return [] if %i[number reference nominal].include?(type)
        (type==:call ? left : type==:binary ? [left,right] : [left]).flat_map { |child| references(child) }
      end

      def controls(snapshot)
        data=snapshot['custom_numeric_inputs']
        return {} unless data
        unless data.is_a?(Hash) && data['version']==1 && data['inputs'].is_a?(Hash) && data['inputs'].length<=Core::MAX_PARTS
          raise Core::Error,'Khai báo custom ATT số không hợp lệ.'
        end
        attrs=snapshot.fetch('dc_inputs',{})
        data['inputs'].to_h do |key,row|
          unless key.is_a?(String) && attrs.key?(key) && candidate?(attrs,key) && row.is_a?(Hash) &&
                 ['', 'mm'].include?(row['unit']) && %w[value_factor override_factor].all? { |field| row[field].is_a?(Numeric) && row[field].finite? && row[field]>0 }
            raise Core::Error,'Đơn vị hoặc nguồn custom ATT số không hợp lệ.'
          end
          label=Core.dc_label(attrs["_#{key}_formlabel"])
          label=Core.dc_label(attrs["_#{key}_label"]) if label.empty?
          value=Core.number(attrs[key])
          [key,row.merge('label'=>label.empty? ? key : label,'value'=>value,'display_value'=>value*row['value_factor'],'source'=>'custom_constant')]
        end
      end
    end
  end
end
