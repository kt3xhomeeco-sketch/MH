# encoding: UTF-8
module MH
  module ModuleStudio
    # Portable import intent. Native faces, IDs, transactions and drawing are
    # captured/applied by ImportLinks; internal resizing still uses ScalePlan.
    module ImportTemplate
      extend self
      SIDES=[['Trái','Phải'],['Trước','Sau'],['Dưới','Trên']].freeze

      def defaults
        {'version'=>1,'enabled'=>false,'role'=>'module','mode'=>'auto','door_face'=>'1:1','door_gap'=>1.0,
         'faces'=>3.times.flat_map { |axis| 2.times.map { |side| {'axis'=>axis,'side'=>side,'enabled'=>!(axis==1 && side.zero?),'gap'=>0.0} } }}
      end

      def validate(data)
        data=Core.copy_data(data || defaults)
        unless data.is_a?(Hash) && data['version']==1 && [true,false].include?(data['enabled']) &&
               %w[module door].include?(data['role']) && %w[auto inside outside].include?(data['mode']) &&
               data['door_face'].is_a?(String) && data['door_face'].match?(/\A[0-2]:[01]\z/) &&
               data['faces'].is_a?(Array) && data['faces'].length==6
          raise Core::Error,'Bộ liên kết khi import không hợp lệ.'
        end
        data['door_gap']=Core.number(data['door_gap'])
        raise Core::Error,'Khe cánh phải từ 0 đến 100 mm.' unless data['door_gap'].between?(0,100)
        keys=data['faces'].map do |face|
          unless face.is_a?(Hash) && [0,1,2].include?(face['axis']) && [0,1].include?(face['side']) && [true,false].include?(face['enabled'])
            raise Core::Error,'Mặt trong bộ liên kết không hợp lệ.'
          end
          face['gap']=Core.number(face['gap'])
          raise Core::Error,'Khoảng hở mặt phải từ 0 đến 1000 mm.' unless face['gap'].between?(0,1000)
          [face['axis'],face['side']]
        end
        raise Core::Error,'Bộ liên kết có mặt trùng.' unless keys.uniq.length==6
        data
      end

      def enabled?(rule)
        rule && rule['import_template'] && validate(rule['import_template'])['enabled']
      end

      def edit(rule,data)
        result=Core.copy_data(rule);result['import_template']=validate(data)
        Core.rule!(result)
      end

      def mounting_face(template)
        template['door_face'].split(':').map(&:to_i)
      end

      def door_thickness(rule,values,bounds)
        rows=Parametric.variables(rule)
        physical=rows.select { |row| row['binding'] && row['unit']=='mm' && ThicknessSymbols.thickness?(rule,row['binding']) }
        row=physical.find { |entry| entry['symbol'].casecmp?('T1') } || physical.first
        row ? Core.number(values.fetch(row['binding'],row['value'])) : Core.dimensions(bounds)[mounting_face(validate(rule['import_template']))[0]]
      end

      # region is the empty compartment or host outer box. A candidate exists
      # only for an actual captured boundary face, never an invented open side.
      def match(template,source,region,candidates,mode:,mount:nil,origin:nil,scales:[1,1,1])
        template=validate(template)
        return unless template['enabled']
        Core.bounds!(source);Core.bounds!(region)
        sizes=Core.dimensions(source)
        low=(origin || region[0]).dup
        box=[low,3.times.map { |axis| low[axis]+sizes[axis] }]
        door=mounting_face(template)
        matches=template['faces'].filter_map do |slot|
          next unless slot['enabled']
          axis=slot['axis'];side=slot['side']
          next if template['role']=='door' && mode=='inside' && axis==door[0]
          is_mount=mode=='outside' && mount && axis==mount[0] && side==1-mount[1]
          next if mode=='outside' && mount && axis==mount[0] && !is_mount
          boundary=region[is_mount ? mount[1] : side][axis]
          wanted_normal=mode=='inside' || is_mount ? 1-side : side
          options=candidates.select do |face|
            face['axis']==axis && face['side']==wanted_normal && (face['coordinate']-boundary).abs<0.02 &&
              ([0,1,2]-[axis]).all? { |other| [face['bounds'][1][other],region[1][other]].min-[face['bounds'][0][other],region[0][other]].max>0.001 }
          end
          next if options.empty?
          target=options.max_by do |face|
            ([0,1,2]-[axis]).map { |other| Core.dimensions(face['bounds'])[other] }.reduce(:*)
          end
          gap=(slot['gap']+(is_mount && template['role']=='door' ? template['door_gap'] : 0.0))/scales[axis]
          coordinate=boundary+(is_mount ? (mount[1].zero? ? -gap : gap) : (side.zero? ? gap : -gap))
          {'slot'=>[axis,side],'target'=>target,'coordinate'=>coordinate,'gap'=>mode=='inside' || is_mount ? gap : -gap,'mount'=>!!is_mount}
        end
        return if matches.empty?
        3.times do |axis|
          sides=matches.select { |row| row['slot'][0]==axis }.to_h { |row| [row['slot'][1],row['coordinate']] }
          if sides.length==2
            box[0][axis]=sides[0];box[1][axis]=sides[1]
          elsif sides.key?(0)
            box[0][axis]=sides[0];box[1][axis]=sides[0]+sizes[axis]
          elsif sides.key?(1)
            box[1][axis]=sides[1];box[0][axis]=sides[1]-sizes[axis]
          end
        end
        raise Core::Error,'Khoảng hở không tạo được kích thước module dương.' unless Core.dimensions(box).all? { |size| size>0.01 }
        {'bounds'=>box,'matches'=>matches,'kind'=>mode,'template'=>template}
      end

      def thickness_values(rule,values={})
        evaluated=Parametric.evaluate_variables(Parametric.with_values(rule,values))
        Parametric.variables(rule).filter_map do |row|
          next unless row['binding'] && row['unit']=='mm' && ThicknessSymbols.thickness?(rule,row['binding'])
          [row['symbol'].downcase,evaluated.fetch(row['id'])]
        end.to_h
      end

      def synchronize(rule,values,master)
        own=Parametric.with_values(rule,values);rows=Parametric.variables(own);changed=false
        rows.each do |row|
          value=master[row['symbol'].downcase]
          next unless value && row['binding'] && row['unit']=='mm' && ThicknessSymbols.thickness?(own,row['binding'])
          next if Core.same_dc_value?(Parametric.evaluate_variables(own)[row['id']],value)
          row['value']=value;row['formula']='';changed=true
        end
        changed ? Parametric.edit_variables(own,rows) : nil
      end
    end
  end
end
