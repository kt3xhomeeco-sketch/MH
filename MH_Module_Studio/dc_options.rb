# encoding: UTF-8
module MH
  module ModuleStudio
    module DCOptions
      extend self

      # DC uses JavaScript escape(): mixed %uXXXX and Latin-1 %XX, while newer
      # libraries can contain percent-encoded UTF-8. Do not turn literal + into space.
      def decode(text)
        text.to_s.gsub(/(?:%u[0-9a-f]{4})+/i) do |sequence|
          sequence.scan(/%u([0-9a-f]{4})/i).flatten.map { |hex| hex.to_i(16) }.pack('n*').force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8,invalid: :replace,undef: :replace)
        end.gsub(/(?:%[0-9a-f]{2})+/i) do |sequence|
          bytes = sequence.scan(/%([0-9a-f]{2})/i).flatten.map { |hex| hex.to_i(16) }
          utf8 = bytes.pack('C*').force_encoding(Encoding::UTF_8)
          utf8.valid_encoding? ? utf8 : bytes.pack('U*')
        end
      end

      def choices(attributes,key,unit = '')
        return [] unless attributes["_#{key}_access"].to_s.upcase=='LIST'
        raw = attributes["_#{key}_options"].to_s
        return [] if raw.bytesize>16_384
        CGI.unescapeHTML(raw).split('&').filter_map do |pair|
          next if pair.empty? || !pair.include?('=')
          label,value = pair.split('=',2).map { |item| decode(item) }
          numeric = Float(value,exception:false)
          supported = numeric && numeric.finite?
          converted = supported ? (unit=='mm' ? (numeric*25.4).round(6) : numeric) : value
          {'label'=>Core.dc_label(label),'value'=>converted,'supported'=>!!supported}
        end.first(200)
      end

      def for_parameter(bundle,param)
        return [] unless param
        attrs = bundle.dig('formula_engine','attribute_program','dc_inputs') || {}
        rows=choices(attrs,param['dc_key'] || param['key'],param['unit'])
        rows=Core.copy_data(param.fetch('options',[])) if rows.empty?
        rows.map do |choice|
          key=choice['value'].to_s[/\A=\s*([a-z_][a-z_0-9]*)\s*\z/i,1]&.downcase
          source=key && bundle['parameters'].find { |entry| (entry['dc_key'] || entry['key']).downcase==key }
          next choice unless param['editable'] && source && source['key']!=param['key'] &&
                             source['value'].is_a?(Numeric) && source['unit']==param['unit'] &&
                             attrs["_#{key}_access"].to_s.upcase=='TEXTBOX' && attrs["_#{key}_formula"].to_s.strip.empty?
          choice.merge('supported'=>true,'input_binding'=>source['key'])
        end
      end

      # The referenced value is own variable data, not a new geometry override.
      # The selected LIST variable feeds its evaluated number to the existing ATT.
      def input?(bundle,param)
        param && bundle['parameters'].any? do |owner|
          for_parameter(bundle,owner).any? { |choice| choice['input_binding']==param['key'] }
        end
      end

      def editable?(bundle,param)
        !param || param['editable'] || input?(bundle,param)
      end

      def reason(bundle,param)
        return unless param
        !param['editable'] && input?(bundle,param) ? 'Đầu vào số cho LIST tự nhập; chọn chế độ này để điều khiển hình học.' : param['reason']
      end

      def range(param)
        param['input_range'] || [param['value'].is_a?(Numeric) && param['value'].negative? ? -10_000.0 : 0.0,10_000.0]
      end

      def variable_choices(bundle,param,rows)
        for_parameter(bundle,param).map do |choice|
          source=rows.find { |row| row['binding']==choice['input_binding'] } if choice['input_binding']
          source ? choice.merge('formula'=>source['symbol'],'input_id'=>source['id']) : choice
        end
      end

      def selected(choices,row)
        formula=row['formula'].to_s.sub(/\A\s*=/,'').strip
        return choices.find { |choice| choice['formula']&.casecmp?(formula) } unless formula.empty?
        nil
      end

      def assign!(bundle,rows,id,value)
        row=rows.find { |entry| entry['id']==id }
        raise Core::Error,'Tham số không còn trong module.' unless row
        param=bundle['parameters'].find { |entry| entry['key']==row['binding'] }
        choices=variable_choices(bundle,param,rows)
        if value.is_a?(String) && value.start_with?('=')
          choice=choices.find { |entry| entry['value']==value && entry['supported'] && entry['formula'] }
          raise Core::Error,'Lựa chọn LIST chưa có đầu vào số được hỗ trợ.' unless choice
          row['formula']=choice['formula']
        else
          row['formula']='' unless choices.empty?
          row['value']=Parametric::TEXT_TYPES.include?(row['category']) ? value.to_s : Core.number(value)
        end
        row
      end

      def initial_formulas(bundle,rows)
        attrs=bundle.dig('formula_engine','attribute_program','dc_inputs') || {}
        rows.each do |row|
          param=bundle['parameters'].find { |entry| entry['key']==row['binding'] }
          next unless param
          original=attrs["_#{param['dc_key'] || param['key']}_formula"].to_s.sub(/\A\s*=/,'').strip
          choice=variable_choices(bundle,param,rows).find { |entry| entry['input_binding'] && entry['value'].to_s.sub(/\A=/,'').strip.casecmp?(original) }
          source=choice && rows.find { |entry| entry['id']==choice['input_id'] }
          row['formula']=choice['formula'] if source && Core.same_dc_value?(row['value'],source['value'])
        end
        rows
      end

      # Some DC selectors are labelled mm but store integer option IDs, with
      # STRING formula units. Correct only a complete, geometry-verified scalar
      # interpretation; genuine length lists retain their inch-to-mm values.
      def scalar_lists(snapshot)
        data=Core.copy_data(snapshot);attrs=data.fetch('dc_inputs',{})
        keys=attrs.keys.select do |key|
          next false unless attrs["_#{key}_access"].to_s.upcase=='LIST' &&
                            attrs["_#{key}_formulaunits"].to_s.upcase=='STRING' &&
                            DCFrames::LENGTH_UNITS.include?(attrs["_#{key}_units"].to_s.upcase)
          options=choices(attrs,key)
          values=options.map { |row| row['value'] }
          !options.empty? && options.all? { |row| row['supported'] && row['value']==row['value'].to_i } &&
            values.include?(Core.dc_value(attrs[key]))
        end
        return data if keys.empty?
        program=DCFormulas::Program.new(data)
        begin
          bounds,=program.evaluate(Core.formula_values(data,program.controls))
          return data if ConstructionFrame.matches?(data,bounds)
        rescue Core::Error
          # A wrong selector unit can make CHOOSE invalid before any geometry.
        end
        keys.each { |key| attrs["_#{key}_units"]='FLOAT' }
        program=DCFormulas::Program.new(data)
        bounds,=program.evaluate(Core.formula_values(data,program.controls))
        return Core.copy_data(snapshot) unless ConstructionFrame.matches?(data,bounds)
        data['scalar_list_inputs']=keys
        data
      rescue Core::Error
        Core.copy_data(snapshot)
      end
    end
  end
end
