# encoding: UTF-8
require_relative 'assembly'
require_relative 'placement_math'

module MH
  module ModuleStudio
    # Own importer adapter. No calls to MH_Superimp or its shared geometry code.
    module LibraryPlacement
      extend self

      def pick(view, x, y, replace: false, visible_only: false)
        helper = view.pick_helper
        # The normal one-pixel pick loses an inside panel edge easily. Keep the
        # nearest returned face, but let SketchUp collect a small face aperture.
        helper.do_pick(x,y,10)
        indices=helper.count.times.to_a
        indices.select! { |i| helper.path_at(i).none? { |item| item.respond_to?(:hidden?) && (item.hidden? || !item.layer.visible?) } } if visible_only
        face = helper.picked_face
        index = indices.find { |i| helper.leaf_at(i)==face } if face
        index ||= indices.find { |i| Array(helper.path_at(i)).any? { |item| item.is_a?(Sketchup::Face) } } if visible_only
        index ||= indices.find { |i| helper.path_at(i).any? { |item| Assembly.container?(item) } }
        return unless index
        path = Array(helper.path_at(index))
        face=helper.leaf_at(index)
        face=nil unless face.is_a?(Sketchup::Face)
        face ||= path.reverse.find { |item| item.is_a?(Sketchup::Face) } if visible_only
        chain=path.select { |item| Assembly.container?(item) }
        face_in_edit_context=!replace && face && face.parent==view.model.active_entities
        if face_in_edit_context
          anchor=nil
        else
          scope=nil
          if AssemblyContainers.managed?(chain.first) && chain.length>1 && !(replace && view.model.selection.include?(chain.first))
            scope=chain.shift.persistent_id.to_s
          end
          if chain.first && Assembly.container?(chain.first)
            anchor = {'root'=>chain.first.persistent_id.to_s,'scope'=>scope}.compact
          else
            return if replace || !face
            anchor=nil
          end
        end
        [anchor,face,helper.transformation_at(index) || Geom::Transformation.new]
      end

      def boxes(root)
        result = []
        walk = lambda do |item,frame,ancestors|
          definition=item.definition
          raise Core::Error,'Cấu trúc khoang quá sâu hoặc lặp vòng.' if ancestors.include?(definition) || ancestors.length>30
          faces = definition.entities.grep(Sketchup::Face).reject { |face| face.hidden? || !face.layer.visible? }
          # A loose open shell is not a solid panel. Its aggregate bounds must
          # not mark the entire empty cabinet opening as occupied material.
          if !faces.empty? && item.manifold?
            points = faces.flat_map(&:vertices).uniq.map { |vertex| vertex.position.transform(frame).to_a.map { |v| v*25.4 } }
            result << Frames.box(points)
          end
          definition.entities.each do |child|
            next unless Assembly.container?(child) && !child.hidden? && child.layer.visible?
            walk.call(child,frame*child.transformation,ancestors+[definition])
          end
          raise Core::Error,'Khoang vượt 600 chi tiết.' if result.length>Core::MAX_PARTS
        end
        walk.call(root,Geom::Transformation.new,[])
        result
      end

      # World-space body bounds of visible top-level siblings on the picked
      # panel's layer. Hidden items are not candidate cabinet panels.
      def sibling_bounds(model, panel, cache=nil)
        return [] unless model.active_path.nil? && panel.parent==model
        entities=model.active_entities
        signature=[ImportLinks.revision(model),panel.layer.object_id,entities.length]
        if cache && cache['fit_siblings_signature']==signature
          return cache['fit_siblings']
        end
        items=entities.grep(Sketchup::Group)+entities.grep(Sketchup::ComponentInstance)
        approved=[panel]+items.select do |item|
          item.valid? && !item.hidden? && item.layer.visible? && item.parent==model && item.layer==panel.layer
        end
        rows=approved.uniq.filter_map do |item|
          next unless item.valid? && !item.hidden? && item.layer.visible?
          points=8.times.map { |corner| item.definition.bounds.corner(corner).transform(item.transformation).to_a.map { |value| value*25.4 } }
          [item,Frames.box(points)]
        end
        cache&.merge!('fit_siblings_signature'=>signature,'fit_siblings'=>rows)
        rows
      end

      def connected_region(model, panel, cache=nil)
        rows=sibling_bounds(model,panel,cache)
        picked=rows.find { |item,_box| item==panel }&.last
        return unless picked
        host=PlacementMath.exploded_envelope(rows.map(&:last),picked)
        return unless host
        frame=Geom::Transformation.new.to_a
        {'mode'=>'free_fit','target_kind'=>'container','anchor'=>{'root'=>panel.persistent_id.to_s},
         'bounds'=>host,'frame'=>frame,'name'=>panel.name.empty? ? 'Cụm tủ' : panel.name}
      rescue Core::Error
        nil
      end

      def detect(view, x, y, replace: false, cache: nil, source: nil)
        model = view.model
        picked = pick(view,x,y,replace:replace,visible_only:!replace)
        return unless picked
        anchor = picked.first
        face = picked[1]
        face_frame = picked[2]
        unless replace
          if anchor && face
            host=ImportLinks.capture(view,x,y,cache,picked:picked)
            if host && PlacementMath.open_cavity?(host['envelope'],host['cavity'])
              return {'mode'=>'cavity','anchor'=>host['anchor'],'bounds'=>host['cavity'],'frame'=>host['frame'],'name'=>host['name']}
            end
          end
          if anchor && !anchor['scope'] &&
             (panel=model.find_entity_by_persistent_id(anchor['root'].to_i)) && Assembly.container?(panel) &&
             !AssemblyContainers.managed?(panel)
            region=connected_region(model,panel,cache)
            return region if region
          end
          region=container_region(model,anchor) if anchor
          return region if region
          return face_region(view,face,face_frame,source) if face && source
          return
        end
        root = Assembly.root(model,anchor)
        frame = Assembly.world_transform(model,anchor)
        Frames.scale_frame(frame.to_a)
        envelope = [root.definition.bounds.min.to_a,root.definition.bounds.max.to_a].map { |point| point.map { |v| v*25.4 } }
        {'mode'=>'replace','anchor'=>anchor,'bounds'=>envelope,'frame'=>frame.to_a,'name'=>root.name}
      end

      def container_region(model,anchor)
        root=Assembly.root(model,anchor)
        frame=Assembly.world_transform(model,anchor)
        Frames.scale_frame(frame.to_a)
        bounds=[root.definition.bounds.min.to_a,root.definition.bounds.max.to_a].map { |point| point.map { |value| value*25.4 } }
        return unless Core.dimensions(bounds).all? { |value| value>0.1 && value.finite? }
        {'mode'=>'free_fit','target_kind'=>'container','anchor'=>anchor,'bounds'=>bounds,'frame'=>frame.to_a,'name'=>root.name}
      end

      def face_region(view,face,face_frame,source)
        return unless face && face_frame && source['snapshot']
        envelope=source.dig('snapshot','envelope')
        depth=Core.dimensions(envelope)[1]
        points=face.outer_loop.vertices.map do |vertex|
          vertex.position.transform(face_frame).to_a.map { |value| value*25.4 }
        end
        toward=view.camera.eye.to_a.map { |value| value*25.4 }
        region=PlacementMath.face_fit_region(points,depth,toward:toward)
        origin=Geom::Point3d.new(region['origin'].map { |value| value/25.4 })
        axes=region['axes'].map { |axis| Geom::Vector3d.new(axis) }
        frame=Geom::Transformation.axes(origin,*axes)
        {'mode'=>'free_fit','target_kind'=>'face','bounds'=>region['bounds'],'frame'=>frame.to_a,'name'=>'Mặt chọn'}
      end

      def transform(data, placement)
        Geom::Transformation.new(placement['frame'])*Geom::Transformation.new(PlacementMath.fit(data['snapshot']['envelope'],placement['bounds']))
      end

      # Free fit uses the definition SketchUp actually built, not the serialized
      # snapshot. SketchUp bounds are inches; placement bounds are millimetres
      # in the placement frame, and Frames.bounds_delta applies that conversion.
      def fit_built(root, placement, locked_axes: nil)
        bounds=root.definition.bounds
        source=[bounds.min.to_a,bounds.max.to_a].map { |point| point.map { |value| value*25.4 } }
        scales=Frames.scale_frame(placement['frame']).values_at(0,5,10)
        fit=PlacementMath.fit(source,free_fit_bounds(source,placement['bounds'],locked_axes:locked_axes,scales:scales))
        Geom::Transformation.new(placement['frame'])*Geom::Transformation.new(fit)
      end

      # Free Fit keeps only axes that the saved module rule physically locks.
      # Without explicit evidence all target axes are fitted. A locked axis
      # retains the built source span, including its target low coordinate.
      def free_fit_bounds(source, target, locked_axes: nil, scales: [1,1,1])
        size=Core.dimensions(source)
        target=Core.copy_data(target)
        Array(locked_axes).uniq.each do |axis|
          next unless axis.is_a?(Integer) && axis.between?(0, 2)
          target[1][axis]=target[0][axis]+size[axis]/scales[axis]
        end
        target
      end

      # Preview payloads deliberately omit the full rule. Resolve locks from
      # the built instance and use its actual definition dimensions, never a
      # stale library snapshot. Locked physical lengths are in world mm.
      def fitted_placement(root,data,placement)
        rule=data['rule'] || AssemblyParameters.data(root)&.first
        locks=locked_axes(data.merge('rule'=>rule))
        bounds=root.definition.bounds
        source=[bounds.min.to_a,bounds.max.to_a].map { |point| point.map { |value| value*25.4 } }
        result=Core.copy_data(placement)
        scales=Frames.scale_frame(result['frame']).values_at(0,5,10)
        result['bounds']=free_fit_bounds(source,result['bounds'],locked_axes:locks,scales:scales)
        result
      end

      def locked_axes(data)
        parts=Array(data.dig('snapshot','parts')).to_h { |part| [part['key'],part] }
        constraints=Array(data.dig('rule','constraints')).select do |entry|
          %w[thickness fix].include?(entry['type']) && entry['enabled'] && entry['drive']
        end
        axes=constraints.filter_map do |entry|
          face=entry['face']
          axis=face['axis'] if face.is_a?(Hash) && parts.key?(face['part'])
          axis if axis.is_a?(Integer) && axis.between?(0, 2)
        end.uniq
        return axes unless axes.empty?

        # ATT-backed panels can carry a physical thickness axis without an
        # editable geometric constraint. Infer a root lock only when every
        # visible detail agrees on that same saved axis.
        return [] unless data.dig('rule','formula_engine')
        visible=parts.values.reject { |part| part['visible']==false }
        inferred=visible.map { |part| part['thickness_axis'] }.uniq
        inferred.length==1 && inferred.first.is_a?(Integer) && inferred.first.between?(0,2) ? inferred : []
      end

      def resize(root, placement, imports: nil, locked_axes: nil)
        # Reconstruction can change the definition's local minimum. Re-align it
        # after redraw, including rotated, mirrored and nonzero-origin sources.
        redraw = placement['mode']!='free_fit'
        if !redraw
          nil
        elsif AssemblyContainers.managed?(root)
          AssemblyExternal.resize_assembly(root)
        elsif imports
          rule=imports.validated_rule(root.get_attribute(Reader::DICT,'rule_json'))
          saved=JSON.parse(root.get_attribute(Reader::DICT,'parameter_values_json','{}'))
          current,=Reader.live(root,label:'Replace',parameter:Runtime.read_parameter(rule,saved))
          ScaleRedraw.apply(root.model,[[root,rule,imports.resize_plan(rule,current,saved)]])
        else
          ScaleRedraw.apply(root.model,[ScaleRedraw.prepare(root)])
        end
        current = [root.definition.bounds.min.to_a,root.definition.bounds.max.to_a].map { |p| p.map { |v| v*25.4 } }
        # Keep actual post-redraw local dimensions; only translation corrects the
        # minimum so thickness-preserving redraw is not scaled a second time.
        target = Geom::Point3d.new(placement['bounds'][0].map { |v| v/25.4 }).transform(Geom::Transformation.new(placement['frame']))
        actual = root.definition.bounds.min.transform(root.transformation)
        root.transform!(Geom::Transformation.translation(target-actual))
        inverse = Geom::Transformation.new(placement['frame']).inverse
        measured = Frames.box(Frames.corners(current).map { |p| Geom::Point3d.new(p.map { |v| v/25.4 }).transform(inverse*root.transformation).to_a.map { |v| v*25.4 } })
        expected=placement['bounds']
        if placement['mode']=='free_fit'
          scales=Frames.scale_frame(placement['frame']).values_at(0,5,10)
          expected=free_fit_bounds(current,expected,locked_axes:locked_axes,scales:scales)
        end
        unless Core.bounds_close?(measured,expected,0.02)
          if placement['mode']=='template'
            scales=Frames.scale_frame(placement['frame']).values_at(0,5,10)
            wanted=Core.dimensions(expected);actual=Core.dimensions(measured)
            differences=3.times.filter_map do |axis|
              next if (wanted[axis]-actual[axis]).abs*scales[axis]<=0.02
              "#{%w[X Y Z][axis]} cần #{(wanted[axis]*scales[axis]).round(3)} mm, công thức cho #{(actual[axis]*scales[axis]).round(3)} mm"
            end
            raise Core::Error,'Không thể Fit và giữ quy tắc T / ATT: '+differences.join('; ') unless differences.empty?
          end
          raise Core::Error,'Module mới chưa khớp kích thước vùng đặt.'
        end
      rescue Core::Error=>error
        raise unless placement['mode']=='template'
        scales=Frames.scale_frame(placement['frame']).values_at(0,5,10)
        size=Core.dimensions(placement['bounds']).each_with_index.map { |value,axis| (value*scales[axis]).round(3) }
        raise Core::Error,"Không thể Fit #{root.name} vào #{size.join(' × ')} mm và giữ T / ATT: #{error.message}"
      end

      def place(library, data, point, placement)
        return library.place(data,point) unless placement
        return ImportLinks.place(library,data,placement) if placement['mode']=='template'
        model = Sketchup.active_model
        if placement['mode']=='replace'
          target = Core.copy_data(placement['anchor'])
          if detached_target?(model,target)
            result=replace_detached(library,data,target)
          else
            old=Assembly.root(model,target)
            records=Assembly.records(model,except:target['scope'] ? [] : [old])
            result = nil
            Assembly.transact(model,records,mutable_anchors:[target],replacement:target) do |rows|
              result = replace!(library,data,target,rows)
            end
          end
          unless model.selection.length==1 && model.selection.first==result
            model.selection.clear;model.selection.add(result)
          end
          return result
        end
        operation_name=placement['mode']=='free_fit' ? 'MH Fit Module Vào Vùng' : 'MH Đặt Module Vừa Khoang'
        model.start_operation(operation_name,true)
        operation = true
        root = library.build_instance(data,Geom::Transformation.new)
        placement=fitted_placement(root,data,placement)
        root.transformation = fit_built(root,placement)
        resize(root,placement)
        model.selection.clear; model.selection.add(root)
        model.commit_operation
        operation = false
        root
      rescue StandardError
        model.abort_operation if operation
        raise
      end

      def detached_target?(model,target)
        return false if target['scope']
        AssemblyContainers.read(model).none? do |row|
          AssemblyContainers.references(row).any? { |ref| ref['root']==target['root'] || ref['scope']==target['root'] }
        end
      rescue Core::Error, JSON::ParserError, TypeError, NoMethodError
        # Malformed existing link metadata is not a geometric input. Leave the
        # model's raw records untouched and replace only the selected object.
        true
      end

      def selected_targets(model)
        Runtime.ensure_top_level(model)
        roots=model.selection.to_a
        raise Core::Error,'Chọn các group/component cần Replace trước.' if roots.empty? || roots.length>Core::MAX_PARTS
        unless roots.all? { |root| Assembly.container?(root) && root.valid? && !root.locked? }
          raise Core::Error,'Vùng chọn chỉ được gồm group/component không bị khóa.'
        end
        roots.map { |root| {'root'=>root.persistent_id.to_s} }
      end

      def replace_many(library,data,targets)
        model=Sketchup.active_model;Runtime.ensure_top_level(model)
        targets=Core.copy_data(targets)
        raise Core::Error,'Danh sách Replace không hợp lệ.' unless targets.is_a?(Array) && targets.length.between?(1,Core::MAX_PARTS) && targets.uniq.length==targets.length
        targets.each { |anchor| raise Core::Error,'Đối tượng cần Replace đang bị khóa.' if Assembly.root(model,anchor).locked? }
        result=[]
        if targets.all? { |target| detached_target?(model,target) }
          isolated=true;previous_busy=Assembly.instance_variable_get(:@busy);Assembly.instance_variable_set(:@busy,true)
          model.start_operation('MH Replace Vùng Chọn',true);operation=true
          targets.each { |target| result << replace!(library,data,target,[]) }
          model.selection.clear;model.selection.add(result)
          model.commit_operation;operation=false
        else
          Assembly.transact(model,Assembly.records(model),mutable_anchors:targets,replacement:targets) do |records|
            targets.each { |target| result << replace!(library,data,target,records) }
            model.selection.clear;model.selection.add(result)
          end
        end
        result
      ensure
        model.abort_operation if operation
        Assembly.instance_variable_set(:@busy,previous_busy) if isolated
        if model
          Assembly.watch(model).reset;ScaleRedraw.watch(model).reset
        end
      end

      def replace_detached(library,data,target)
        model=Sketchup.active_model
        previous_busy=Assembly.instance_variable_get(:@busy)
        Runtime.ensure_top_level(model)
        Assembly.instance_variable_set(:@busy,true)
        model.start_operation('MH Thay Theo Phủ Bì',true)
        operation=true
        result=replace!(library,data,target,[])
        model.commit_operation;operation=false
        result
      ensure
        model.abort_operation if operation
        Assembly.instance_variable_set(:@busy,previous_busy)
        Assembly.watch(model).reset
        ScaleRedraw.watch(model).reset
      end

      def references(model, target, records)
        records.flat_map do |record|
          AssemblyContainers::REFS.filter_map do |key|
            ref = record[key]
            next unless ref && AssemblyContainers.identity(ref)==AssemblyContainers.identity(target)
            item,_frame = Assembly.panel(model,ref)
            [ref,{'name'=>LibraryCatalog.fold(item.name),'plane'=>Assembly.plane(model,ref)}]
          end
        end
      end

      def remap(model, target, references)
        return if references.empty?
        candidates = []
        visit = lambda do |parent,path|
          parent.definition.entities.each do |child|
            next unless Assembly.container?(child)
            part = child.get_attribute(Reader::DICT,'part_key')
            if part
              3.times do |axis|
                2.times do |side|
                  ref = target.merge('part'=>part,'path'=>[],'axis'=>axis,'side'=>side)
                  candidates << [ref,LibraryCatalog.fold(child.name),Assembly.plane(model,ref)]
                end
              end
            end
            raise Core::Error,'Module mới có cấu trúc quá sâu.' if path.length>30
            visit.call(child,path+[child])
          end
        end
        visit.call(Assembly.root(model,target),[])
        references.each do |ref,old|
          if !ref['part'] && !ref['panel'] && ref.fetch('path',[]).empty?
            ref['root']=target['root']
            next
          end
          parallel = candidates.select { |_anchor,_name,plane| AssemblyMath.dot(plane['normal'],old['plane']['normal'])>0.999999 }
          named = parallel.select { |_anchor,name,_plane| name==old['name'] && !name.empty? }
          exact = parallel.select { |_anchor,_name,plane| AssemblyMath.dot(AssemblyMath.sub(plane['point'],old['plane']['point']),plane['normal']).abs<0.02 }
          options = named.empty? ? exact : named
          raise Core::Error,'Module mới chưa có mặt tương ứng rõ ràng với liên kết cũ; chưa thay module.' unless options.length==1
          replacement = options.first.first
          ref.replace(ref.slice('name').merge(replacement))
        end
      end

      def replace!(library, data, target, records)
        raise Core::Error,'Đặt cụm thành đối tượng riêng; chọn module đơn để thay thế module con.' if data['format']==AssemblyFile::FORMAT
        model = Sketchup.active_model
        old = Assembly.root(model,target)
        raise Core::Error,'Đối tượng cần Replace đang bị khóa.' if old.locked?
        if AssemblyContainers.managed?(old)
          scope=old.persistent_id.to_s
          outside=records.reject { |row| row['scope']==scope }
          if outside.any? { |row| AssemblyContainers.references(row).any? { |ref| ref['scope']==scope } }
            raise Core::Error,'Cụm có mặt module con liên kết ra ngoài; chọn module con cần thay để giữ các liên kết đó.'
          end
          # Internal links belong to the replaced contents. Whole-envelope
          # external links retain the existing parent instance and are remapped.
          records.reject! { |row| row['scope']==scope }
        end
        refs = references(model,target,records)
        frame = old.transformation
        bounds = [old.definition.bounds.min.to_a,old.definition.bounds.max.to_a].map { |point| point.map { |v| v*25.4 } }
        placement = {'mode'=>'replace','bounds'=>bounds,'frame'=>frame.to_a}
        data,placement=library.resolve_fit(data,placement,within_operation:true)
        parent = old.parent==model ? model.active_entities : old.parent.entities
        # Build at identity so fit_built can measure the actual native rule,
        # including a locked physical span, before fitting the target envelope.
        fresh = library.build_instance(data,Geom::Transformation.new,entities:parent)
        placement=fitted_placement(fresh,data,placement)
        fresh.transformation=fit_built(fresh,placement)
        resize(fresh,placement,imports:library.imports)
        old_pid = old.persistent_id.to_s
        keep = old.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)
        if old.is_a?(Sketchup::Group)
          old = old.to_component
          records.each do |record|
            AssemblyContainers::REFS.each { |key| record[key]['root']=old.persistent_id.to_s if record[key] && AssemblyContainers.identity(record[key])==AssemblyContainers.identity(target) }
            record['copies']&.map! { |pid| pid==old_pid && record['scope']==target['scope'] ? old.persistent_id.to_s : pid }
          end
          target['root']=old.persistent_id.to_s
        end
        old.definition=fresh.definition
        old.transformation=fresh.transformation
        old.name=fresh.name
        %w[dynamic_attributes abf_object_data].each { |name| old.delete_attribute(name) if old.attribute_dictionary(name,false) }
        old.delete_attribute(Reader::DICT)
        fresh.attribute_dictionary(Reader::DICT).each_pair { |key,value| old.set_attribute(Reader::DICT,key,value) }
        old.set_attribute(Reader::DICT,AssemblyContainers::MEMBER,keep) if keep
        # Definition, transform and all owned metadata already came from the
        # fully validated fresh instance. Its unique identity also belongs to
        # these exact children; only the surviving parent PID changes.
        old.set_attribute(Reader::DICT,'root_pid',old.persistent_id.to_s)
        fresh.erase!
        remap(model,target,refs)
        old
      end
    end
  end
end
