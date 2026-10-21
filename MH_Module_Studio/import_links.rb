# encoding: UTF-8
require_relative 'import_template'

module MH
  module ModuleStudio
    # Native adapter for opt-in import templates. Preview capture is read-only;
    # only place/apply_reservations write inside Assembly's existing transaction.
    module ImportLinks
      extend self
      RESERVATIONS='import_door_reservations_v1'.freeze

      if defined?(Sketchup::ModelObserver)
        class Revision < Sketchup::ModelObserver
          attr_reader :value
          def initialize
            super()
            @value=0
          end
          %i[onTransactionCommit onTransactionUndo onTransactionRedo onTransactionAbort].each do |event|
            define_method(event) { |_model| @value+=1 }
          end
        end
      end

      def revision(model)
        return unless defined?(Revision)
        @revisions||={}
        @revisions[model] ||= begin
          observer=Revision.new
          model.add_observer(observer)
          observer
        end
        @revisions[model].value
      end

      def states(root)
        raw=root.get_attribute(Reader::DICT,RESERVATIONS,'{}')
        raise Core::Error,'Dữ liệu chừa cánh quá lớn.' unless raw.is_a?(String) && raw.bytesize<16_384
        value=JSON.parse(raw)
        unless value.is_a?(Hash) && value.length<=6 && value.all? do |key,row|
                 key.match?(/\A[0-2]:[01]\z/) && row.is_a?(Hash) && %w[target reserved applied scale].all? { |field| row[field].is_a?(Numeric) && row[field].finite? && row[field]>=0 }
               end
          raise Core::Error,'Dữ liệu kích thước chừa cánh không hợp lệ.'
        end
        value
      end

      def roots(model)
        top=model.entities.select { |entity| Assembly.container?(entity) } # rubocop:disable SketchupSuggestions/ModelEntities -- Import hosts are model-level roots and direct assembly members.
        top.reject { |entity| AssemblyContainers.managed?(entity) }.map { |entity| [entity,{'root'=>entity.persistent_id.to_s}] }+
          top.select { |entity| AssemblyContainers.managed?(entity) }.flat_map do |owner|
            AssemblyContainers.members(owner).map { |entity| [entity,{'root'=>entity.persistent_id.to_s,'scope'=>owner.persistent_id.to_s}] }
          end
      end

      def reservation_fingerprint(model)
        roots(model).filter_map do |root,anchor|
          raw=root.get_attribute(Reader::DICT,RESERVATIONS)
          [anchor,raw,root.transformation.to_a,root.definition.bounds.min.to_a,root.definition.bounds.max.to_a] if raw && raw!='{}'
        end
      end

      def reservation_identity(host,anchor,key)
        [anchor['scope'],anchor['scope'] ? host.get_attribute(Reader::DICT,AssemblyContainers::MEMBER) : anchor['root'],key]
      end

      def root_frames(model)
        roots(model).to_h { |_root,anchor| [AssemblyContainers.identity(anchor),Assembly.world_transform(model,anchor).to_a] }
      end

      def frame_axes(frame)
        matrix=frame.respond_to?(:to_a) ? frame.to_a : frame
        [0,4,8].map { |offset| Geom::Vector3d.new(matrix[offset,3]) }
      end

      # Scaling a host and its opposed door together supplies the total depth,
      # including T and the gap. Restoring T must shorten the host accordingly.
      def scaled_reservation_targets(model,records,before)
        records.select { |row| row.dig('import_link','door_mount') }.group_by do |row|
          [AssemblyContainers.identity(row['a']),row['import_link']['host_face'].join(':')]
        end.filter_map do |(identity,key),rows|
          anchor=rows.first['a'];host=Assembly.root(model,anchor);prior=states(host)[key]
          old=before[identity];next unless prior && old
          axis=key.split(':').first.to_i;old_axes=frame_axes(old);old_axis=old_axes[axis]
          current=Assembly.world_transform(model,anchor)
          factor=frame_axes(current)[axis].length/old_axis.length
          next if (factor-1).abs<0.000001
          paired=rows.all? do |row|
            previous=before[AssemblyContainers.identity(row['b'])];next false unless previous
            axes=frame_axes(previous)
            index=axes.each_index.max_by { |i| axes[i].normalize.dot(old_axis.normalize).abs }
            next false unless axes[index].normalize.dot(old_axis.normalize).abs>0.999999
            fresh=Assembly.world_transform(model,row['b'])
            ratio=frame_axes(fresh)[index].length/axes[index].length
            (ratio-factor).abs<0.000001
          end
          [reservation_identity(host,anchor,key),prior['target']*factor] if paired
        end.to_h
      end

      def face_geometry(root,anchor)
        faces=[];boxes=[]
        walk=lambda do |item,frame,path,depth|
          raise Core::Error,'Cấu trúc mặt chủ quá sâu.' if depth>30
          next if item.hidden? || !item.layer.visible?
          native=item.definition.entities.grep(Sketchup::Face).reject { |face| face.hidden? || !face.layer.visible? }
          unless native.empty?
            points=native.flat_map(&:vertices).uniq.map { |vertex| vertex.position.transform(frame).to_a.map { |value| value*25.4 } }
            boxes << Frames.box(points)
          end
          native.each do |face|
            local=face.normal.to_a;axis=local.each_index.max_by { |index| local[index].abs }
            next unless local[axis].abs>0.999999
            limits=[item.definition.bounds.min.to_a,item.definition.bounds.max.to_a]
            coordinate=face.vertices.first.position.to_a[axis]
            side=(coordinate-limits[0][axis]).abs<(coordinate-limits[1][axis]).abs ? 0 : 1
            next unless (coordinate-limits[side][axis]).abs<0.00001
            normal=Geom::Vector3d.new(3.times.map { |index| index==axis ? (side.zero? ? -1 : 1) : 0 }).transform(frame).normalize.to_a
            dimension=normal.each_index.max_by { |index| normal[index].abs }
            next unless normal[dimension].abs>0.999999
            polygon=face.outer_loop.vertices.map { |vertex| vertex.position.transform(frame).to_a.map { |value| value*25.4 } }
            mesh=face.mesh
            triangles=mesh.polygons.flat_map { |indices| (1...indices.length-1).flat_map { |index| [indices[0],indices[index],indices[index+1]].map { |id| mesh.point_at(id.abs).transform(frame).to_a.map { |value| value*25.4 } } } }
            ref=anchor.merge('path'=>path,'axis'=>axis,'side'=>side,'name'=>[root.name,item.name].reject(&:empty?).uniq.join(' / '))
            if item!=root
              part=item.get_attribute(Reader::DICT,'part_key');panel=item.get_attribute(Reader::DICT,AssemblyContainers::PANEL)
              ref['part']=part if part;ref['panel']=panel if panel
            end
            box=Frames.box(polygon)
            faces << {'axis'=>dimension,'side'=>normal[dimension].positive? ? 1 : 0,'coordinate'=>box[0][dimension],
                      'bounds'=>box,'anchor'=>ref,'points'=>polygon,'triangles'=>triangles}
          end
          item.definition.entities.each do |child|
            walk.call(child,frame*child.transformation,path+[child.persistent_id.to_s],depth+1) if Assembly.container?(child)
          end
          raise Core::Error,'Module chủ vượt giới hạn mặt.' if faces.length>3600 || boxes.length>Core::MAX_PARTS
        end
        walk.call(root,Geom::Transformation.new,[],0)
        [faces,boxes]
      end

      def capture(view,x,y,cache=nil)
        picked=LibraryPlacement.pick(view,x,y,visible_only:true);return unless picked
        anchor,face,face_frame=picked;return unless face
        host=host_geometry(view.model,anchor,cache)
        frame=Geom::Transformation.new(host['frame'])
        boxes=host['boxes']
        polygon=face.vertices.map { |vertex| vertex.position.transform(face_frame) }
        normal=face.normal.transform(face_frame).normalize
        hit=Geom.intersect_line_plane(view.pickray(x,y),[polygon.first,normal]);return unless hit
        normal.reverse! if normal.dot(view.camera.eye-hit)<0
        vector=normal.clone;vector.length=2.0/25.4
        seed=(hit+vector).transform(frame.inverse).to_a.map { |value| value*25.4 }
        point=hit.transform(frame.inverse).to_a.map { |value| value*25.4 }
        envelope=host['envelope']
        local=normal.transform(frame.inverse).normalize.to_a
        axis=local.each_index.max_by { |index| local[index].abs }
        side=(point[axis]-envelope[0][axis]).abs<(point[axis]-envelope[1][axis]).abs ? 0 : 1
        cavity=PlacementMath.cavity(envelope,boxes,seed,minimum_hits:1)
        host.merge('cavity'=>cavity,'seed'=>seed,'mount'=>[axis,side])
      end

      def host_geometry(model,anchor,cache)
        root=Assembly.root(model,anchor);frame=Assembly.world_transform(model,anchor)
        Frames.scale_frame(frame.to_a)
        signature=[anchor,revision(model),root.definition.object_id,root.get_attribute(Reader::DICT,'parameter_values_json'),
          root.definition.bounds.min.to_a,root.definition.bounds.max.to_a]
        if cache && cache['signature']==signature
          faces,boxes=cache.values_at('faces','boxes')
        else
          faces,boxes=face_geometry(root,anchor)
          cache&.replace('signature'=>signature,'faces'=>faces,'boxes'=>boxes)
        end
        {'anchor'=>anchor,'frame'=>frame.to_a,'faces'=>faces,'boxes'=>boxes,'envelope'=>AssemblyEnvelope.bounds(root),'name'=>root.name}
      end

      def mounting_point(template,envelope,frame,view,x,y)
        axis,source_side=ImportTemplate.mounting_face(template);side=1-source_side
        plane=ImportTemplate.envelope_faces({},envelope).find { |face| face['axis']==axis && face['side']==side }
        world=plane['points'].map { |point| Geom::Point3d.new(point.map { |v| v/25.4 }).transform(frame) }
        normal=Geom::Vector3d.new(3.times.map { |i| i==axis ? (side.zero? ? -1 : 1) : 0 }).transform(frame).normalize
        ray=view.pickray(x,y)
        return unless normal.dot(ray[1]) < -0.000001
        projected=world.map { |point| view.screen_coords(point).to_a.first(2) }
        return if ImportTemplate.screen_distance2([x,y],projected)>144
        hit=Geom.intersect_line_plane(ray,[world.first,normal])
        return unless hit && (hit-ray[0]).dot(ray[1])>=0
        hit.transform(frame.inverse).to_a.map { |v| v*25.4 }
      end

      def front_mount(host,template,view,x,y)
        axis,source_side=ImportTemplate.mounting_face(template);side=1-source_side
        return unless template['faces'].any? { |slot| slot['enabled'] && slot['axis']==axis && slot['side']==source_side }
        frame=Geom::Transformation.new(host['frame'])
        point=mounting_point(template,host['envelope'],frame,view,x,y);return unless point
        near=host['faces'].any? do |face|
          next false unless face['axis']==axis && face['side']==side && (face['coordinate']-host['envelope'][side][axis]).abs<0.02
          polygons=face['triangles'] ? face['triangles'].each_slice(3) : [face['points']]
          polygons.any? do |polygon|
            screen=polygon.map { |p| view.screen_coords(Geom::Point3d.new(p.map { |v| v/25.4 }).transform(frame)).to_a.first(2) }
            ImportTemplate.screen_distance2([x,y],screen)<=144
          end
        end
        host.merge('mount'=>[axis,side],'seed'=>point,'front_mount'=>true) if near
      end

      def front_fallback(template,view,x,y,cache)
        candidates=roots(view.model).filter_map do |root,anchor|
          next if root.hidden? || !root.layer.visible? || root.locked?
          owner=view.model.find_entity_by_persistent_id(anchor['scope'].to_i) if anchor['scope']
          next if owner && (owner.hidden? || !owner.layer.visible? || owner.locked?)
          envelope=AssemblyEnvelope.bounds(root)
          next unless Core.dimensions(envelope).all? { |size| size>0.01 }
          frame=Assembly.world_transform(view.model,anchor)
          point=mounting_point(template,envelope,frame,view,x,y);next unless point
          distance=Geom::Point3d.new(point.map { |v| v/25.4 }).transform(frame).distance(view.camera.eye)
          [distance,anchor]
        end
        candidates.sort_by(&:first).each do |_distance,anchor|
          host=front_mount(host_geometry(view.model,anchor,cache),template,view,x,y)
          return host if host
        end
        nil
      end

      def detect(data,view,x,y,cache:nil)
        template=ImportTemplate.validate(data['import_template'] || data.dig('rule','import_template'))
        host=capture(view,x,y,cache)
        if template['enabled'] && template['role']=='door' && template['mode']!='inside'
          host=host ? front_mount(host,template,view,x,y) || host : front_fallback(template,view,x,y,cache)
        end
        return unless host
        frame=Geom::Transformation.new(host['frame'])
        scales=Frames.scale_frame(frame.to_a).values_at(0,5,10)
        source=data['snapshot']['envelope'].map { |point| point.each_with_index.map { |value,axis| value/scales[axis] } }
        inside=template['mode']=='inside' || template['mode']=='auto' && host['cavity'] && !host['front_mount']
        return unless !inside || host['cavity']
        mode=inside ? 'inside' : 'outside'
        region=Core.copy_data(inside ? host['cavity'] : host['envelope'])
        faces=host['faces'];reserve=nil
        faces=faces+ImportTemplate.envelope_faces(host['anchor'],host['envelope']) if inside
        if template['role']=='door' && !inside
          axis,source_side=ImportTemplate.mounting_face(template)
          return unless host['mount']==[axis,1-source_side]
          root=Assembly.root(view.model,host['anchor'])
          scale=scales[axis]
          thickness=(data['door_thickness'] || (data['rule'] && ImportTemplate.door_thickness(data['rule'],data.fetch('values',{}),data['snapshot']['envelope'])) || Core.dimensions(data['snapshot']['envelope'])[axis])/scale
          state=states(root)[host['mount'].join(':')]
          total=state ? state['target']/scale : Core.dimensions(region)[axis]
          slot=template['faces'].find { |face| face['axis']==axis && face['side']==source_side && face['enabled'] }
          return unless slot
          clearance=(template['door_gap']+slot['gap'])/scale
          reserve=[state ? state['reserved']/scale : 0,thickness+clearance].max
          delta=reserve-(state ? state['reserved']/scale : 0)
          side=host['mount'][1];region[side][axis]+=(side.zero? ? delta : -delta)
          raise Core::Error,'Cánh và khe hở lớn hơn chiều sâu khung.' unless total-reserve>0.01
          faces=faces.map do |face|
            next face unless face['axis']==axis && face['side']==side && (face['coordinate']-host['envelope'][side][axis]).abs<0.02
            face.merge('coordinate'=>region[side][axis])
          end
        end
        origin=host['seed'].dup
        if template['role']=='door' && inside
          axis,source_side=ImportTemplate.mounting_face(template)
          origin[axis]=host['envelope'][1-source_side][axis]
          origin[axis]-=Core.dimensions(source)[axis] if source_side.zero?
        end
        result=ImportTemplate.match(template,source,region,faces,mode:mode,mount:inside ? nil : host['mount'],origin:origin,scales:scales)
        return unless result
        result['template']=template
        result['matches'].each { |match| match['gap']*=scales[match['slot'][0]] }
        depth=Core.dimensions(region)[1]*scales[1]-template['faces'].select { |slot| slot['enabled'] && slot['axis']==1 }.sum { |slot| slot['gap'] }
        result.merge('mode'=>'template','anchor'=>host['anchor'],'frame'=>host['frame'],'name'=>host['name'],'reserve'=>reserve,'fit_depth_mm'=>depth)
      end

      def records(placement,root)
        placement['matches'].map do |match|
          axis,side=match['slot']
          a=Core.copy_data(match['target']['anchor'])
          b={'root'=>root.persistent_id.to_s,'path'=>[],'axis'=>axis,'side'=>side,'level'=>'module','name'=>root.name}
          row={'id'=>Core::Ids.uuid,'mode'=>'contact','a'=>a,'b'=>b,'gap'=>match['gap'],
               'import_link'=>{'version'=>1,'slot'=>match['slot'],'kind'=>placement['kind'],'role'=>placement['template']['role']}}
          row['import_link']['boundary']='envelope' if match['target']['virtual']
          row['import_link']['front_datum']='host_front' if placement['kind']=='inside' && match['slot']==[1,0]
          row['external']=true if a['scope']
          if placement['template']['role']=='door' && placement['kind']=='outside' && match['mount']
            row['import_link']['door_mount']=true
            row['import_link']['host_face']=[axis,1-side]
          end
          row
        end
      end

      def place(library,data,placement)
        model=Sketchup.active_model;proposed=Assembly.records(model);root=nil
        anchors=[placement['anchor']]+placement['matches'].map { |match| match['target']['anchor'] }
        Assembly.transact(model,proposed,mutable_anchors:anchors) do |links|
          root=library.build_instance(data,LibraryPlacement.transform(data,placement))
          LibraryPlacement.resize(root,placement)
          links.concat(records(placement,root))
          model.selection.clear;model.selection.add(root)
        end
        root
      end

      # Older import records can still point to the back of a brace (including
      # a tiny dormant DC part). Front clearance now uses the host front datum,
      # just like a new placement; manual face constraints retain their meaning.
      def normalize_front_datums(model,records)
        records.select do |row|
          next false unless row['mode']=='contact' && row.dig('import_link','kind')=='inside' && row.dig('import_link','slot')==[1,0]
          next false if row['r1'] || row['r2'] || row.dig('import_link','boundary')=='envelope' || row.dig('import_link','front_datum')=='host_front'
          old=row.fetch('a')
          front=old.slice('root','scope').merge('path'=>[],'axis'=>1,'side'=>0,'level'=>'module')
          prior=Assembly.world_plane(model,old);plane=Assembly.world_plane(model,front)
          next false unless AssemblyMath.dot(prior['normal'],plane['normal']).abs>0.999999
          value=Core.number(row.fetch('gap',0))
          front['name']=Assembly.module_name(model,front)+' / Mặt trước phủ bì'
          row['a']=front;row['gap']=-value
          row['import_link']=row['import_link'].merge('boundary'=>'envelope','front_datum'=>'host_front')
          true
        end
      end

      def draw(view,placement)
        frame=Geom::Transformation.new(placement['frame'])
        color=Sketchup::Color.new(0,145,150,210)
        placement['matches'].each do |match|
          target=match['target']
          convert=lambda do |points|
            world=points.map { |point| Geom::Point3d.new(point.map { |value| value/25.4 }).transform(frame) }
            lift=view.camera.direction.reverse
            lift.length=view.pixels_to_model(0.5,world.first)
            world.map { |point| point+lift }
          end
          view.drawing_color=color;view.draw(GL_TRIANGLES,convert.call(target['triangles'])) unless target['virtual']
          view.line_stipple=target['virtual'] ? '-' : ''
          view.drawing_color='#005c63';view.line_width=1;view.draw(GL_LINE_LOOP,convert.call(target['points']))
        end
        view.line_stipple=''
      end

      def apply_reservations(model,records,external_geometry: false,targets: {})
        groups=records.select { |row| row['mode']=='contact' && row.dig('import_link','door_mount') }.group_by do |row|
          [AssemblyContainers.identity(row['a']),row['import_link']['host_face'].join(':')]
        end
        roots(model).each do |host,anchor|
          saved=states(host);identity=AssemblyContainers.identity(anchor)
          keys=(saved.keys+groups.keys.filter_map { |owner,key| key if owner==identity }).uniq
          keys.each do |key|
            rows=groups.fetch([identity,key],[])
            axis,side=key.split(':').map(&:to_i)
            vector=Geom::Vector3d.new(3.times.map { |index| index==axis ? (side.zero? ? -1 : 1) : 0 }).transform(host.transformation)
            scale=vector.length.to_f;normal=vector.normalize.to_a
            low,high=Assembly.projection(host,normal);span=high-low
            prior=saved[key]
            target=prior ? prior['target'] : span
            # Definition edits from Stretch supply a new explicit host span,
            # just as a root Scale does. Parameter edits keep the saved target.
            if prior && ((scale-prior['scale']).abs>0.000001 || external_geometry && (span-prior['applied']).abs>0.001)
              target=span+prior['reserved']
            end
            target=targets.fetch(reservation_identity(host,anchor,key),target)
            reserve=rows.map do |row|
              child=Assembly.root(model,row['b'])
              child_frame=AssemblyContainers.frame(model,row['b']);host_frame=AssemblyContainers.frame(model,anchor)
              world=Geom::Vector3d.new(normal).transform(host_frame).normalize
              local=world.transform(child_frame.inverse).normalize.to_a
              own=AssemblyParameters.data(child)
              depth=own ? ImportTemplate.door_thickness(*own,AssemblyEnvelope.bounds(child)) : Assembly.projection(child,local).then { |a,b| b-a }
              clearance=Core.number(row.fetch('gap',0))
              raise Core::Error,'Khe cánh đối mặt phải từ 0 mm.' if clearance.negative?
              depth+clearance
            end.max || 0.0
            wanted=target-reserve
            raise Core::Error,'Cánh và khe hở lớn hơn chiều sâu khung.' unless wanted>0.01
            if (wanted-span).abs>0.001
              Assembly.resize(host,normal,wanted)
              measured=Assembly.projection(host,normal)
              raise Core::Error,'Quy tắc khung chưa cho phép chừa chiều dày cánh.' unless (measured[1]-measured[0]-wanted).abs<0.02
              Assembly.translate(host,AssemblyMath.mul(normal,low-measured[0]))
            end
            if rows.empty?
              saved.delete(key)
            else
              saved[key]={'target'=>target,'reserved'=>reserve,'applied'=>wanted,'scale'=>scale}
            end
          end
          next if keys.empty?
          saved.empty? ? host.delete_attribute(Reader::DICT,RESERVATIONS) : host.set_attribute(Reader::DICT,RESERVATIONS,JSON.generate(saved))
        end
      end

      def remember_reservations(model)
        roots(model).each do |host,_anchor|
          saved=states(host);next if saved.empty?
          saved.each do |key,row|
            axis,side=key.split(':').map(&:to_i)
            normal=Geom::Vector3d.new(3.times.map { |index| index==axis ? (side.zero? ? -1 : 1) : 0 }).transform(host.transformation).normalize.to_a
            span=Assembly.projection(host,normal).then { |a,b| b-a }
            row['applied']=span;row['target']=span+row['reserved']
          end
          host.set_attribute(Reader::DICT,RESERVATIONS,JSON.generate(saved))
        end
      end
    end
  end
end
