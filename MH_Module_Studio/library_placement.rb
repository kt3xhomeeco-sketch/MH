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
        helper.do_pick(x,y)
        indices=helper.count.times.to_a
        indices.select! { |i| helper.path_at(i).none? { |item| item.respond_to?(:hidden?) && (item.hidden? || !item.layer.visible?) } } if visible_only
        face = helper.picked_face
        index = indices.find { |i| helper.leaf_at(i)==face } if face
        index ||= indices.find { |i| helper.leaf_at(i).is_a?(Sketchup::Face) } if visible_only
        index ||= indices.find { |i| helper.path_at(i).any? { |item| Assembly.container?(item) } }
        return unless index
        face=helper.leaf_at(index) if visible_only && helper.leaf_at(index).is_a?(Sketchup::Face)
        face = nil unless helper.leaf_at(index)==face
        path = helper.path_at(index)
        chain=path.select { |item| Assembly.container?(item) }
        scope=nil
        if AssemblyContainers.managed?(chain.first) && chain.length>1 && !(replace && view.model.selection.include?(chain.first))
          scope=chain.shift.persistent_id.to_s
        end
        return unless chain.first && Assembly.container?(chain.first)
        anchor = {'root'=>chain.first.persistent_id.to_s,'scope'=>scope}.compact
        [anchor,face,helper.transformation_at(index)]
      end

      def boxes(root)
        result = []
        walk = lambda do |definition,frame,ancestors|
          raise Core::Error,'Cấu trúc khoang quá sâu hoặc lặp vòng.' if ancestors.include?(definition) || ancestors.length>30
          faces = definition.entities.grep(Sketchup::Face).reject { |face| face.hidden? || !face.layer.visible? }
          unless faces.empty?
            points = faces.flat_map(&:vertices).uniq.map { |vertex| vertex.position.transform(frame).to_a.map { |v| v*25.4 } }
            result << Frames.box(points)
          end
          definition.entities.each do |child|
            next unless Assembly.container?(child) && !child.hidden? && child.layer.visible?
            walk.call(child.definition,frame*child.transformation,ancestors+[definition])
          end
          raise Core::Error,'Khoang vượt 600 chi tiết.' if result.length>Core::MAX_PARTS
        end
        walk.call(root.definition,Geom::Transformation.new,[])
        result
      end

      def detect(view, x, y, replace: false, cache: nil)
        unless replace
          host=ImportLinks.capture(view,x,y,cache)
          return unless host && host['cavity']
          return {'mode'=>'cavity','anchor'=>host['anchor'],'bounds'=>host['cavity'],'frame'=>host['frame'],'name'=>host['name']}
        end
        model = view.model
        picked = pick(view,x,y,replace:replace)
        return unless picked
        anchor = picked.first
        root = Assembly.root(model,anchor)
        frame = Assembly.world_transform(model,anchor)
        Frames.scale_frame(frame.to_a)
        envelope = [root.definition.bounds.min.to_a,root.definition.bounds.max.to_a].map { |point| point.map { |v| v*25.4 } }
        {'mode'=>'replace','anchor'=>anchor,'bounds'=>envelope,'frame'=>frame.to_a,'name'=>root.name}
      end

      def transform(data, placement)
        Geom::Transformation.new(placement['frame'])*Geom::Transformation.new(PlacementMath.fit(data['snapshot']['envelope'],placement['bounds']))
      end

      def resize(root, placement, imports: nil)
        # Reconstruction can change the definition's local minimum. Re-align it
        # after redraw, including rotated, mirrored and nonzero-origin sources.
        if AssemblyContainers.managed?(root)
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
        unless Core.bounds_close?(measured,placement['bounds'],0.02)
          if placement['mode']=='template'
            scales=Frames.scale_frame(placement['frame']).values_at(0,5,10)
            wanted=Core.dimensions(placement['bounds']);actual=Core.dimensions(measured)
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
        model.start_operation('MH Đặt Module Vừa Khoang',true)
        operation = true
        root = library.build_instance(data,transform(data,placement))
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
        fresh = library.build_instance(data,transform(data,placement),entities:parent)
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
