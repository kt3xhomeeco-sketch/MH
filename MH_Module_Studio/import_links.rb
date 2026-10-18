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
        root=Assembly.root(view.model,anchor)
        frame=Assembly.world_transform(view.model,anchor)
        Frames.scale_frame(frame.to_a)
        signature=[anchor,revision(view.model),root.definition.object_id,root.get_attribute(Reader::DICT,'parameter_values_json'),
          root.definition.bounds.min.to_a,root.definition.bounds.max.to_a]
        if cache && cache['signature']==signature
          faces,boxes=cache.values_at('faces','boxes')
        else
          faces,boxes=face_geometry(root,anchor)
          cache&.replace('signature'=>signature,'faces'=>faces,'boxes'=>boxes)
        end
        polygon=face.vertices.map { |vertex| vertex.position.transform(face_frame) }
        normal=face.normal.transform(face_frame).normalize
        hit=Geom.intersect_line_plane(view.pickray(x,y),[polygon.first,normal]);return unless hit
        normal.reverse! if normal.dot(view.camera.eye-hit)<0
        vector=normal.clone;vector.length=2.0/25.4
        seed=(hit+vector).transform(frame.inverse).to_a.map { |value| value*25.4 }
        point=hit.transform(frame.inverse).to_a.map { |value| value*25.4 }
        envelope=AssemblyEnvelope.bounds(root)
        local=normal.transform(frame.inverse).normalize.to_a
        axis=local.each_index.max_by { |index| local[index].abs }
        side=(point[axis]-envelope[0][axis]).abs<(point[axis]-envelope[1][axis]).abs ? 0 : 1
        cavity=PlacementMath.cavity(envelope,boxes,seed,minimum_hits:1)
        {'anchor'=>anchor,'frame'=>frame.to_a,'faces'=>faces,'envelope'=>envelope,'cavity'=>cavity,'seed'=>seed,'mount'=>[axis,side],'name'=>root.name}
      end

      def detect(data,view,x,y,cache:nil)
        template=ImportTemplate.validate(data['import_template'] || data.dig('rule','import_template'))
        host=capture(view,x,y,cache);return unless host
        frame=Geom::Transformation.new(host['frame'])
        scales=[frame.xaxis.length.to_f,frame.yaxis.length.to_f,frame.zaxis.length.to_f]
        source=data['snapshot']['envelope'].map { |point| point.each_with_index.map { |value,axis| value/scales[axis] } }
        inside=template['mode']=='inside' || template['mode']=='auto' && host['cavity']
        return unless !inside || host['cavity']
        mode=inside ? 'inside' : 'outside'
        region=Core.copy_data(inside ? host['cavity'] : host['envelope'])
        faces=host['faces'];reserve=nil
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
        result.merge('mode'=>'template','anchor'=>host['anchor'],'frame'=>host['frame'],'name'=>host['name'],'reserve'=>reserve)
      end

      def records(placement,root)
        placement['matches'].map do |match|
          axis,side=match['slot']
          a=Core.copy_data(match['target']['anchor'])
          b={'root'=>root.persistent_id.to_s,'path'=>[],'axis'=>axis,'side'=>side,'level'=>'module','name'=>root.name}
          row={'id'=>Core::Ids.uuid,'mode'=>'contact','a'=>a,'b'=>b,'gap'=>match['gap'],
               'import_link'=>{'version'=>1,'slot'=>match['slot'],'kind'=>placement['kind'],'role'=>placement['template']['role']}}
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
          view.drawing_color=color;view.draw(GL_TRIANGLES,convert.call(target['triangles']))
          view.drawing_color='#005c63';view.line_width=1;view.draw(GL_LINE_LOOP,convert.call(target['points']))
        end
      end

      def apply_reservations(model,records)
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
            target=span+prior['reserved'] if prior && (scale-prior['scale']).abs>0.000001
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
