# encoding: UTF-8
module MH
  module ModuleStudio
    # Contact fitting owns native measurements and redraw. The linear solve stays
    # in AssemblyMath; internal module dimensions remain owned by ScaleRedraw.
    module AssemblyContacts
      extend self

      def rows(model, group, space: Assembly)
        group.filter_map do |record|
          next if %w[angle repeat].include?(record['mode'])
          a = space.plane(model,record.fetch('a'))
          normal = a['normal']
          value = if record['mode']=='contact'
                    AssemblyMath.dot(AssemblyMath.offset(a,space.plane(model,record['b']),space.distance(model,record)),normal)
                  else
                    AssemblyMath.centered(a,space.plane(model,record['c']),space.projection(space.root(model,record['b']),normal))['delta']
                  end
          { 'normal'=>normal,'delta'=>value,'name'=>record.dig('b','name').to_s }
        end
      end

      def axes(model, group, entity, space: Assembly)
        faces = group.select { |record| record['mode']=='contact' }.map { |record| space.plane(model,record['b']) }
        frame = space.transformation(entity)
        [frame.xaxis,frame.yaxis,frame.zaxis].filter_map do |axis|
          normal = axis.normalize.to_a
          parallel = faces.select { |face| AssemblyMath.dot(normal,face['normal']).abs>0.999999 }
          paired = parallel.combination(2).any? do |a,b|
            AssemblyMath.dot(AssemblyMath.sub(a['point'],b['point']),normal).abs>0.02
          end
          normal if paired
        end
      end

      def probe_seed(group,entity)
        return unless entity.get_attribute(Reader::DICT,'trial',false) && group.all? { |record| %w[contact angle].include?(record['mode']) }
        rule = UpdateWork.rule(entity.get_attribute(Reader::DICT,'rule_json'))
        saved = JSON.parse(entity.get_attribute(Reader::DICT,'parameter_values_json','{}'))
        current,bindings = Reader.live(entity,label:'Thăm dò liên kết',parameter:Runtime.read_parameter(rule,saved))
        surfaces = group.reject { |record| record['mode']=='angle' }.map do |record|
          anchor = record['b']
          if anchor['part']
            binding = bindings[anchor['part']]
            return nil unless binding && binding[:entity].definition.entities.none? { |item| Assembly.container?(item) }
            vector = [0.0,0.0,0.0]; vector[anchor['axis']] = 1.0
            direction = Geom::Vector3d.new(vector).transform(Geom::Transformation.new(binding[:frame])).to_a
            axis = direction.each_index.max_by { |index| direction[index].abs }
            return nil unless direction.each_with_index.all? { |value,index| index==axis || value.abs<0.000001 }
            side = direction[axis].negative? ? 1-anchor['side'] : anchor['side']
          else
            return nil if anchor['panel'] || !anchor.fetch('path',[]).empty?
            axis = anchor['axis']; side = anchor['side']
          end
          [anchor['part'],axis,side]
        end
        frame = entity.transformation*Geom::Transformation.new(current.dig('dc_graph','root_frame')).inverse
        [rule,saved,current,surfaces,frame]
      end

      def probe_rows(seed,normal,factor,baseline)
        rule,saved,current,surfaces,frame = seed
        axes = [frame.xaxis,frame.yaxis,frame.zaxis]
        axis = axes.each_index.max_by { |index| AssemblyMath.dot(axes[index].normalize.to_a,normal).abs }
        factors = [1.0,1.0,1.0]; factors[axis] = factor
        plan = ScaleRedraw.plan(rule,ScalePlan.scaled_snapshot(current,factors),saved,validated:true)
        old = current['parts'].to_h { |part| [part['key'],part['bounds']] }
        fresh = plan['parts'].to_h { |part| [part['key'],part['bounds']] }
        surfaces.zip(baseline).map do |(key,dimension,side),row|
          boxes = [old,fresh].map { |parts| key ? parts.fetch(key) : Frames.box(parts.values.flatten(1)) }
          points = boxes.map do |box|
            point = 3.times.map { |index| box.sum { |bound| bound[index] }/2 }
            point[dimension] = box[side][dimension]
            point
          end
          delta = Geom::Vector3d.new(AssemblyMath.sub(points[1],points[0])).transform(frame).to_a
          row.merge('delta'=>row['delta']-AssemblyMath.dot(delta,row['normal']))
        end
      end

      def solve(model, group)
        space = group.first['external'] ? AssemblyExternal.new(model,group.first['b']) : Assembly
        entity = space.root(model,group.first['b'])
        begin
          correction = AssemblyMath.contact_solution(rows(model,group,space:space))
          space.translate(entity,correction['move'])
          return
        rescue Core::Error
          unless group.all? { |record| %w[contact angle].include?(record['mode']) }
            raise Core::Error,'Các liên kết chưa thể cùng thỏa mãn. Kiểm tra mặt đã chọn và khoảng cách.'
          end
        end
        directions = axes(model,group,entity,space:space)
        if directions.empty?
          raise Core::Error,'Hai liên kết đang giữ cùng một mặt hoặc không có hai mặt đối diện để tự đổi kích thước.'
        end
        4.times do
          baseline = rows(model,group,space:space)
          return if baseline.all? { |row| row['delta'].abs<0.0001 }
          sizes = directions.map { |normal| space.projection(entity,normal).then { |low,high| high-low } }
          seed = probe_seed(group,entity) if space.equal?(Assembly)
          responses = directions.each_with_index.map do |normal,index|
            # Measure actual ATT response: an inset face can stay a fixed distance
            # from the outer edge, unlike a plain geometrically scaled group.
            probe = [sizes[index]*0.001,0.5].max
            if seed
              sample = probe_rows(seed,normal,1+probe/sizes[index],baseline)
            else
              space.resize(entity,normal,sizes[index]+probe)
              sample = rows(model,group,space:space)
              space.resize(entity,normal,sizes[index])
            end
            baseline.zip(sample).map { |before,after| (before['delta']-after['delta'])/probe }
          end
          correction = AssemblyMath.contact_solution(baseline,responses)
          targets = sizes.zip(correction['sizes']).map(&:sum)
          unless targets.all? { |size| size.finite? && size>0.01 }
            raise Core::Error,'Khoảng cách hai mặt không tạo được kích thước module hợp lệ.'
          end
          directions.zip(targets).each { |normal,size| space.resize(entity,normal,size) }
          space.translate(entity,correction['move'])
        end
        unless rows(model,group,space:space).all? { |row| row['delta'].abs<0.02 }
          raise Core::Error,'Không thể đổi kích thước để thỏa các mặt này với quy tắc nội thất hiện tại.'
        end
      rescue Core::Error => detail
        if detail.message.start_with?('Quy tắc xung đột:')
          raise Core::Error,'Các mặt đã chọn yêu cầu kích thước không tương thích. Kiểm tra mặt và khoảng cách.'
        end
        raise
      end
    end
  end
end
