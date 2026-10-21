# encoding: UTF-8
module MH
  module ModuleStudio
    # Display custom data without promoting a computed/unsupported attribute to
    # an input override. Geometry continues to use the verified ATT program.
    module DCCustomAttributes
      extend self
      STANDARD=(DCCustomInputs::RESERVED+%w[name description summary itemcode dialogheight dialogwidth image]).freeze

      def symbol(key, used)
        base=key.each_char.map { |char| char.match?(/[a-zA-Z_0-9]/) ? char : 'u'+char.ord.to_s(16) }.join
        base='dc_'+base unless base.match?(/\A[a-zA-Z_]/)
        base='dc_'+base if (DCFormulas::FUNCTIONS+%w[true false parent]).include?(base.downcase)
        base=base[0,56];name=base;index=1
        while used.map(&:downcase).include?(name.downcase)
          name=base+"_#{index}";index+=1
        end
        name
      end

      def append!(bundle,snapshot)
        attrs=snapshot.fetch('dc_inputs',{})
        known=bundle['parameters'].flat_map { |param| [param['key'],param['dc_key']] }.compact
        attrs.each do |key,raw|
          next if key.start_with?('_') || STANDARD.include?(key.downcase) || known.include?(key)
          label=Core.dc_label(attrs["_#{key}_formlabel"])
          label=Core.dc_label(attrs["_#{key}_label"]) if label.empty?
          length=DCFrames::LENGTH_UNITS.include?(attrs["_#{key}_units"].to_s.upcase) || DCFrames.typed_length?(attrs,key)
          value=Core.dc_value(raw)
          value=value*25.4 if length && value.is_a?(Numeric)
          value=value.to_s unless value.is_a?(Numeric)
          name=symbol(key,bundle['parameters'].map { |param| param['key'] }+Array(bundle['parametric_variables']).map { |row| row['symbol'] })
          param={'key'=>name,'dc_key'=>key,'label'=>label.empty? ? key : label,'unit'=>length && value.is_a?(Numeric) ? 'mm' : '',
            'value'=>value,'editable'=>false,'rule_source'=>'dc_custom_attribute',
            'dc_attribute'=>{'key'=>key,'formula'=>attrs["_#{key}_formula"].to_s},
            'reason'=>'Custom ATT · chỉ đọc; không ghi đè công thức hoặc tự nhận là đầu vào hình học.'}
          bundle['parameters'] << param
          if bundle['formula_engine']
            bundle['formula_engine']['parameters'] << Core.copy_data(param)
          end
          if bundle['parametric_variables']
            bundle['parametric_variables'] << {'id'=>'input:'+name,'binding'=>name,'name'=>param['label'],'symbol'=>name,
              'category'=>param['unit']=='mm' ? 'dimension' : value.is_a?(Numeric) ? 'number' : 'information',
              'unit'=>param['unit'],'value'=>value,'formula'=>'','exported'=>false}
          end
          known << key
        end
        bundle
      end

      def upgrade(bundle)
        copy=Core.copy_data(bundle)
        source=copy.dig('formula_engine','attribute_program')
        return copy unless source && copy['kind']==RuleSystem::KIND
        append!(copy,source)
        RuleSystem.validate!(copy)
      end

      def value(bundle,param,programs: nil)
        source=bundle.dig('formula_engine','attribute_program')
        return param['value'] unless source && param['value'].is_a?(Numeric) && !param.dig('dc_attribute','formula').to_s.empty?
        program=programs ? (programs[source] ||= DCFormulas::Program.new(source)) : DCFormulas::Program.new(source)
        values=Core.formula_values(source,program.controls)
        program.controls.each_key do |key|
          resolved=yield(key)
          values[key]=resolved if resolved.is_a?(Numeric)
        end
        program.prepare_values(values)
        program.attribute('',param.fetch('dc_attribute').fetch('key'))
      rescue Core::Error
        param['value']
      end
    end
  end
end
