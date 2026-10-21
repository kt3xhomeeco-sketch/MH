# encoding: UTF-8
require 'digest'
require_relative 'native_drawer_check'

module MH
  module ModuleStudio
    # Opt-in live checks. Private fixtures only; never runs on require/load.
    module NativeAutoContactsCheck
      extend self

      def check(value,label)
        raise label unless value
        @report['checks'] << label
      end

      def box(entities,name,low,high)
        group = entities.add_group; group.name = name
        corners = Frames.corners([low,high]).map { |point| point.map { |value| value/25.4 } }
        [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]].each do |indices|
          group.entities.add_face(indices.map { |index| corners[index] })
        end
        group
      end

      def module_root(name,x)
        definition = @model.definitions.add(name)
        root = @model.entities.add_instance(definition,Geom::Transformation.translation([x/25.4,60000/25.4,0]))
        root.name = name
        @owned << root
        root
      end

      def pair
        outer = module_root('MH QA045 Khung',60000)
        [[[0,0,0],[18,500,800]],[[582,0,0],[600,500,800]],[[18,0,0],[582,500,18]],
         [[18,0,782],[582,500,800]],[[18,492,18],[582,500,782]]].each_with_index do |(low,high),index|
          box(outer.definition.entities,"Panel #{index}",low,high)
        end
        inner = module_root('MH QA045 Lọt',60000)
        box(inner.definition.entities,'Lọt', [21,10,21],[579,489,779])
        [outer,inner]
      end

      def geometry(root)
        data = []
        visit = lambda do |item|
          data << [item.transformation.to_a.map { |v| v.round(9) },item.hidden?,item.layer.name]
          item.definition.entities.each do |child|
            if Assembly.container?(child)
              visit.call(child)
            elsif child.is_a?(Sketchup::Edge)
              data << [child.start.position.to_a.map { |v| v.round(9) },child.end.position.to_a.map { |v| v.round(9) }]
            end
          end
        end
        visit.call(root)
        Digest::SHA256.hexdigest(JSON.generate(data))
      end

      def reset
        Assembly.watch(@model).reset
        ScaleRedraw.watch(@model).reset
      end

      def select(*entities)
        @model.selection.clear; @model.selection.add(entities)
      end

      def picking(outer,inner)
        view = @model.active_view
        target = Geom::Point3d.new([60300,60250,400].map { |v| v/25.4 })
        eye = Geom::Point3d.new([60300,58000,400].map { |v| v/25.4 })
        view.camera = Sketchup::Camera.new(eye,target,Z_AXIS,false)
        view.camera.height = 1100/25.4; view.refresh
        screen = view.screen_coords(target); x = screen.x; y = screen.y
        picker = AssemblyFacePicker.new(@model)
        hit = picker.hit(0,x,y,view)
        check(hit && hit['anchor']['root']==inner.persistent_id.to_s,'Native first real-face pick sees fitted module')
        tool = AssemblyTool.new
        tool.define_singleton_method(:refresh) { nil }
        tool.pick(hit['anchor'])
        before = [geometry(outer),geometry(inner)]
        filtered = picker.hit(0,x,y,view,accept:tool.method(:pick_allowed?))
        check(filtered && filtered['anchor']['root']==outer.persistent_id.to_s && filtered['mesh'], 'Excluded inner module allows picking physical surrounding back face')
        tool.hover(0,x,y,view)
        check(tool.instance_variable_get(:@hover)['anchor']==filtered['anchor'],'Hover uses the same exclusion as commit')
        tool.onLButtonDown(0,x,y,view)
        check(tool.record.dig('b','root')==outer.persistent_id.to_s,'Click commits the deeper surrounding face')
        check(before==[geometry(outer),geometry(inner)],'Picking does not hide, move or modify either module')
        tool.fresh
        tool.pick('root'=>outer.persistent_id.to_s,'axis'=>0,'side'=>1,'level'=>'module')
        envelope = picker.hit(CONSTRAIN_MODIFIER_MASK,x,y,view,accept:tool.method(:pick_allowed?))
        check(envelope && envelope['anchor']['root']==inner.persistent_id.to_s,'Shift envelope picking excludes the already chosen surrounding module')
      end

      def run(expected_pid:)
        @model = Sketchup.active_model
        raise 'Wrong native session' unless Process.pid==expected_pid && @model.title.empty? && @model.active_path.nil?
        @report = {'ok'=>false,'checks'=>[]}; @owned = []
        originals = @model.entities.to_a.select { |entity| Assembly.container?(entity) }
        fingerprints = originals.to_h { |entity| [entity.persistent_id,NativeDrawerCheck.fingerprint(entity)] }
        definitions = @model.definitions.to_a
        selection = @model.selection.to_a; camera = @model.active_view.camera
        original_links = @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        begin
          @model.start_operation('MH QA045 Fixtures',true)
          outer,inner = pair
          @model.commit_operation; reset
          picking(outer,inner)
          select(outer,inner)
          before = [geometry(outer),geometry(inner)]
          result = AssemblyAutoLinks.create(@model,max_gap:3)
          links = result['links']
          @report['links'] = links
          check(links.length==5,'Detect five physical opposing cabinet faces at the current 3 mm gaps')
          check(links.all? { |row| (row['gap']-3).abs<0.000001 },'Preserve exact measured current gap')
          check(before==[geometry(outer),geometry(inner)],'Batch discovery preserves transforms, vertices and visibility')
          check(outer.parent==@model && inner.parent==@model,'Discovery does not group modules')
          check(AssemblyAutoLinks.create(@model,max_gap:3)['links'].empty?,'Repeated discovery creates no duplicates')
          links.each { |row| Assembly.verify(@model,row) }
          @model.start_operation('MH QA045 Reflected rotation',true)
          original_frame = outer.transformation
          rotated = original_frame*Geom::Transformation.rotation(ORIGIN,Z_AXIS,30.degrees)*Geom::Transformation.scaling(-1,1,1)
          outer.transformation = rotated; inner.transformation = rotated
          @model.commit_operation; reset
          links.each { |row| Assembly.verify(@model,row) }
          check(AssemblyAutoLinks.create(@model,max_gap:3)['links'].empty?,'Rotated reflected modules preserve physical contacts and duplicate detection')
          @model.start_operation('MH QA045 Restore frame',true)
          outer.transformation = original_frame; inner.transformation = original_frame
          @model.commit_operation; reset
          revised = Assembly.records(@model).map do |row|
            links.any? { |link| link['id']==row['id'] } && row.dig('a','axis')==0 ? row.merge('gap'=>4) : row
          end
          a_before = geometry(outer)
          Assembly.transact(@model,revised)
          revised.each { |row| Assembly.verify(@model,row) }
          width = Assembly.projection(inner,[1,0,0]).then { |low,high| high-low }
          check((width-556).abs<0.00001 && geometry(outer)==a_before,'Opposite inferred contacts resize B to fit both boundaries and retain A')
          Assembly.transact(@model,Assembly.records(@model).map do |row|
            links.any? { |link| link['id']==row['id'] } && row.dig('a','axis')==0 ? row.merge('gap'=>3) : row
          end)
          # With only one contact retained, editing the gap demonstrates B follows A.
          chosen = links.find { |row| row.dig('a','axis')==1 }
          keep = Assembly.records(@model).reject { |row| links.any? { |item| item['id']==row['id'] } }
          @model.start_operation('MH QA045 Isolate editable link',true)
          AssemblyContainers.store(@model,keep+[chosen]); @model.commit_operation; reset
          a_before = geometry(outer)
          changed = Core.copy_data(chosen).merge('gap'=>8)
          Assembly.save(@model,changed)
          check((Assembly.distance(@model,changed)-8).abs<0.000001 && geometry(outer)==a_before && geometry(inner)!=before[1], 'Generated contact is editable and moves B while A stays fixed')
          check(AssemblyMath.offset(Assembly.plane(@model,changed['a']),Assembly.plane(@model,changed['b']),8).all? { |v| v.abs<0.000001 },'Edited physical planes satisfy the new 8 mm gap')
          @model.start_operation('MH QA045 Clear own links',true)
          AssemblyContainers.store(@model,keep)
          @model.commit_operation; reset
          # A third physical object in the gap must block a candidate.
          @model.start_operation('MH QA045 Obstruction',true)
          blocker = module_root('MH QA045 Blocker',60000)
          box(blocker.definition.entities,'Block',[18.5,10,21],[20.5,489,779])
          @model.commit_operation; reset
          captured = AssemblyAutoLinks.capture(@model,[[outer,nil],[inner,nil]])
          candidates = AssemblyInference.candidates(captured,max_gap:20)
          blocked = candidates.find { |row| row['normal']==[1.0,0.0,0.0] }
          check(blocked && !AssemblyAutoLinks.unobstructed?(@model,blocked),'Intervening unselected solid blocks automatic contact')
          @model.start_operation('MH QA045 Shared managed fixture',true)
          wrapper = @model.entities.add_group([outer,inner]).to_component
          wrapper.name = 'MH QA045 Shared'; wrapper.set_attribute(Reader::DICT,AssemblyContainers::FLAG,true)
          @owned << wrapper
          clone = @model.entities.add_instance(wrapper.definition,wrapper.transformation*Geom::Transformation.translation([2000/25.4,0,0]))
          clone.set_attribute(Reader::DICT,AssemblyContainers::FLAG,true); @owned << clone
          @model.commit_operation; reset
          select(wrapper)
          clone_before = NativeDrawerCheck.fingerprint(clone)
          children_before = AssemblyContainers.members(wrapper).map { |item| geometry(item) }
          scoped = AssemblyAutoLinks.create(@model,max_gap:20)['links']
          check(!scoped.empty? && scoped.all? { |row| row['scope']==wrapper.persistent_id.to_s },'Selected assembly discovery stores scoped child links')
          check(wrapper.definition!=clone.definition && AssemblyContainers.read(clone).empty? && NativeDrawerCheck.fingerprint(clone)==clone_before,'Only selected shared assembly becomes private; other copy remains unchanged')
          check(children_before==AssemblyContainers.members(wrapper).map { |item| geometry(item) },'Shared-scope discovery preserves child geometry')
          scoped.each { |row| Assembly.verify(@model,row) }
          @report['ok'] = true
        rescue StandardError => detail
          @report['error'] = [detail.message,*detail.backtrace.first(8)]
        ensure
          @model.start_operation('MH QA045 Cleanup',true)
          @owned.reverse_each { |entity| entity.erase! if entity.valid? }
          original_links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,original_links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
          40.times do
            added = @model.definitions.to_a-definitions
            empty = added.select { |definition| definition.instances.empty? }
            break if empty.empty?
            empty.each { |definition| @model.definitions.remove(definition) }
          end
          @model.selection.clear; @model.selection.add(selection.select(&:valid?))
          @model.commit_operation
          @model.active_view.camera = camera; @model.active_view.refresh; reset
          check(originals.all? { |entity| entity.valid? && NativeDrawerCheck.fingerprint(entity)==fingerprints[entity.persistent_id] },'All user modules remain unchanged')
        end
        @report
      end

      def undo_stage
        Sketchup.undo
        UI.start_timer(0.25,false) do
          begin
            ids = Assembly.records(@model).map { |row| row['id'] }
            check((ids & @undo_ids).empty?,'One Undo removes the entire generated batch')
            check(@undo_geometry==@owned.map { |root| geometry(root) },'Undo retains original module geometry')
            Sketchup.send_action('editRedo:')
            UI.start_timer(0.25,false) do
              begin
                ids = Assembly.records(@model).map { |row| row['id'] }
                check((@undo_ids-ids).empty?,'One Redo restores every contact with stable IDs')
                check(@undo_geometry==@owned.map { |root| geometry(root) },'Redo retains original module geometry')
                Assembly.records(@model).select { |row| @undo_ids.include?(row['id']) }.each { |row| Assembly.verify(@model,row) }
                @report['ok'] = true
              rescue StandardError => detail
                @report['error'] = detail.message
              ensure
                undo_cleanup
              end
            end
          rescue StandardError => detail
            @report['error'] = detail.message
            undo_cleanup
          end
        end
      end

      def undo_cleanup
        @model.start_operation('MH QA045 Undo cleanup',true)
        @owned.each { |root| root.erase! if root.valid? }
        @undo_raw ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@undo_raw) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        40.times do
          empty = (@model.definitions.to_a-@undo_definitions).select { |definition| definition.instances.empty? }
          break if empty.empty?
          empty.each { |definition| @model.definitions.remove(definition) }
        end
        @model.selection.clear; @model.selection.add(@undo_selection.select(&:valid?))
        @model.commit_operation; reset
        check(@undo_originals.all? { |root,hash| root.valid? && NativeDrawerCheck.fingerprint(root)==hash },'Undo/Redo leaves all user modules unchanged')
        File.write(@undo_output,JSON.pretty_generate(@report))
      end

      def start_undo(expected_pid:,output:)
        @model = Sketchup.active_model
        raise 'Wrong native session' unless Process.pid==expected_pid && @model.title.empty? && @model.active_path.nil?
        @report = {'ok'=>false,'checks'=>[]}; @owned = []; @undo_output = output
        @undo_raw = @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @undo_definitions = @model.definitions.to_a; @undo_selection = @model.selection.to_a
        @undo_originals = @model.entities.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        @model.start_operation('MH QA045 Undo fixtures',true)
        outer,inner = pair
        @model.commit_operation; reset
        select(outer,inner)
        @undo_geometry = @owned.map { |root| geometry(root) }
        links = AssemblyAutoLinks.create(@model,max_gap:3)['links']
        @undo_ids = links.map { |row| row['id'] }
        check(links.length==5,'Undo fixture creates five contacts in one batch')
        UI.start_timer(0.25,false) { undo_stage }
        {'scheduled'=>true}
      end
    end
  end
end
