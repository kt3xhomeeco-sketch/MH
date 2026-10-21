# encoding: UTF-8
require_relative 'native_group_options_check'

module MH
  module ModuleStudio
    module NativeLibraryPlacementCheck
      include NativeGroupOptionsCheck
      extend self

      def descriptor(root, scope = nil)
        {'mode'=>'replace','anchor'=>{'root'=>root.persistent_id.to_s,'scope'=>scope}.compact,
          'bounds'=>[root.definition.bounds.min.to_a,root.definition.bounds.max.to_a].map { |p| p.map { |v| v*25.4 } },
          'frame'=>root.transformation.to_a}
      end

      def valid_parametric(root, label)
        rule = Core.rule!(JSON.parse(root.get_attribute(Reader::DICT,'rule_json')))
        values = JSON.parse(root.get_attribute(Reader::DICT,'parameter_values_json'))
        snapshot, = Reader.live(root,label:label,parameter:Runtime.read_parameter(rule,values))
        check(Core.plan(rule,snapshot,values)['changed_count'].zero?,label)
        [snapshot,values]
      end

      def aim(host, point)
        view = @model.active_view
        frame = host.transformation
        target = Geom::Point3d.new(point.map { |v| v/25.4 }).transform(frame)
        eye = Geom::Point3d.new([300,-1400,400].map { |v| v/25.4 }).transform(frame)
        view.camera = Sketchup::Camera.new(eye,target,frame.zaxis,false)
        view.camera.height = 1100.0/25.4
        view.refresh
        screen = view.screen_coords(target)
        [view,screen.x,screen.y]
      end

      def placement_checks
        source = own('MH QA Placement library source')
        library = Library.new
        directory = File.join(@base,'outputs/placement-033/fixture-library')
        FileUtils.mkdir_p(directory)
        library.export(source,File.join(directory,'cabinet.skp'))
        library.instance_variable_get(:@config)['root'] = directory
        library.refresh
        data = library.prepare(library.catalog['entries'].first['id'])
        normal = library.place(data,Geom::Point3d.new(35000.0/25.4,0,0))
        check(normal.is_a?(Sketchup::ComponentInstance) && (normal.transformation.origin.x*25.4-35000).abs<0.02,'Ordinary free library import remains a component at the requested point')
        valid_parametric(normal,'Free import keeps own ATT formulas and values')
        @model.start_operation('MH QA cabinet cavity fixture',true)
        definition = @model.definitions.add('MH QA Placement raw cabinet')
        host = @model.entities.add_instance(definition,Geom::Transformation.translation([30000.0/25.4,0,0]))
        host.name = 'MH QA Placement raw cabinet'
        panels = [[[0,0,0],[18,500,800]],[[582,0,0],[18,500,800]],[[18,0,0],[564,500,18]],
          [[18,0,782],[564,500,18]],[[18,482,18],[564,8,764]],[[18,0,390],[564,482,18]],[[18,0,712],[564,70,70]]]
        panels.each_with_index do |(position,size),index|
          board = box("MH QA cavity board #{index}",position,size)
          definition.entities.add_instance(board.definition,board.transformation)
          board.erase!
        end
        @model.commit_operation
        view,x,y = aim(host,[300,482,600])
        cavity = LibraryPlacement.detect(view,x,y)
        expected = [[18,70,408],[582,482,782]]
        check(cavity && Core.bounds_close?(cavity['bounds'],expected),'Real PickHelper detects an upper compartment bounded by shelf, back, sides and off-centre brace')
        before = state([host])
        inserted = library.place(data,ORIGIN,placement:cavity)
        frame = Geom::Transformation.new(cavity['frame']).inverse*inserted.transformation
        measured = Frames.box(Frames.corners([inserted.definition.bounds.min.to_a,inserted.definition.bounds.max.to_a]).map { |p| Geom::Point3d.new(p).transform(frame).to_a.map { |v| v*25.4 } })
        check(Core.bounds_close?(measured,expected,0.02) && before==state([host]),'Cavity import fits all three measured dimensions and leaves the host untouched')
        snapshot,values = valid_parametric(inserted,'Fitted import satisfies formulas after redraw')
        check((values['dayvan']-18.6).abs<0.000001 && snapshot['parts'].any? { |part| Core.dimensions(part['bounds']).any? { |size| (size-18.6).abs<0.02 } },'Cavity fit preserves actual 18.6 mm board thickness')
        Sketchup.undo
        check(!inserted.valid? && before==state([host]),'One Undo removes the fitted import while retaining its host')
        @model.start_operation('MH QA rotate and mirror cavity host',true)
        host.transformation *= Geom::Transformation.rotation(ORIGIN,Z_AXIS,Math::PI/5)*Geom::Transformation.scaling(-1.2,0.9,1.1)
        @model.commit_operation
        view,x,y = aim(host,[300,482,600])
        rotated = LibraryPlacement.detect(view,x,y)
        check(rotated && Core.bounds_close?(rotated['bounds'],expected),'Rotated mirrored scaled host is measured in its own local axes')
        inserted = library.place(data,ORIGIN,placement:rotated)
        valid_parametric(inserted,'Rotated mirrored cavity import stays parametric')
        view,x,y = aim(inserted,[300,0,400])
        replacement = LibraryPlacement.detect(view,x,y,replace:true)
        check(replacement && replacement['anchor']['root']==inserted.persistent_id.to_s,'Ctrl picking identifies the actual inserted module')
        old = state([inserted]); pid = inserted.persistent_id
        result = library.place(data,ORIGIN,placement:replacement)
        check(result.persistent_id==pid && result.is_a?(Sketchup::ComponentInstance),'Ctrl replace keeps component instance identity')
        valid_parametric(result,'Replacement remains parametric after mirrored scaled fitting')
        Sketchup.undo
        check(old==state([inserted]),'One Undo restores replacement geometry, transform and metadata')
        @model.start_operation('MH QA nonzero origin target',true)
        raw = box('MH QA replacement shifted',[40000,0,0],[450,410,700])
        raw.definition.entities.transform_entities(Geom::Transformation.translation([20.0/25.4,30.0/25.4,40.0/25.4]),raw.definition.entities.to_a)
        raw.transformation *= Geom::Transformation.rotation(ORIGIN,Z_AXIS,Math::PI/6)
        @model.commit_operation
        expected_bounds = [raw.bounds.min.to_a,raw.bounds.max.to_a]
        result = library.place(data,ORIGIN,placement:descriptor(raw))
        measured = [result.bounds.min.to_a,result.bounds.max.to_a]
        check(Core.bounds_close?(measured,expected_bounds,0.001),'Replacement matches rotated target with nonzero definition origin')
        valid_parametric(result,'Nonzero-origin replacement has valid own parametric data')
        linked_placement_checks(library,data)
        hud_placement_checks(library,data)
      end

      def hud_placement_checks(library,data)
        @model.start_operation('MH QA HUD replacement target',true)
        target = box('MH QA HUD target',[50000,0,0],[450,410,700])
        group = @model.entities.add_group
        group.name = 'MH QA replace raw Group'
        group.entities.add_instance(target.definition,Geom::Transformation.new)
        group.transformation = Geom::Transformation.translation([52000.0/25.4,0,0])
        @model.commit_operation
        replaced = library.place(data,ORIGIN,placement:descriptor(group))
        check(replaced.is_a?(Sketchup::ComponentInstance) && !group.valid?,'Replacing a raw Group produces a parent Component with own inner Groups')
        check(replaced.definition.entities.select { |e| Assembly.container?(e) }.all? { |e| e.is_a?(Sketchup::Group) },'Replacement keeps the agreed component-parent group-parts structure')
        view,x,y = aim(target,[225,0,350])
        MH::ModuleStudio.instance_variable_get(:@module_options)&.instance_variable_get(:@dialog)&.close
        hud = LibraryHUD.new(library,data)
        @model.select_tool(hud)
        hud.instance_variable_set(:@query,'cabinet')
        hud.refresh
        before = state(@model.entities.to_a)
        definitions = @model.definitions.to_a
        hud.onMouseMove(COPY_MODIFIER_MASK,x,y,view)
        hud.onKeyDown(27,1,0,view)
        check(hud.active && hud.pending.nil? && hud.query=='cabinet' && HUDInput.active?,'Esc cancels pending replacement and returns to the same filtered Library with keyboard capture retained')
        check(before==state(@model.entities.to_a) && definitions==@model.definitions.to_a && hud.getExtents.empty?,'Canceling import removes the preview without adding geometry or changing the target')
        hud.onKeyDown(27,2,0,view)
        check(hud.active,'Held Escape does not immediately exit the returned Library')
        hud.choose(library.catalog['entries'].first)
        check(hud.pending && hud.active,'A different Library choice can start another import after Escape')
        hud.onCancel(0,view)
        check(hud.active && hud.pending.nil?,'Native SketchUp cancel callback also returns pending import to Library')
        hud.onKeyDown(27,1,0,view)
        check(!hud.active && !HUDInput.active?,'Escape while browsing Library exits and restores SketchUp shortcuts')
        hud = LibraryHUD.new(library,data)
        @model.select_tool(hud)
        hud.onKeyDown(32,1,0,view)
        check(!hud.active && !HUDInput.active?,'Space exits even during a pending import')
        hud = LibraryHUD.new(library,data)
        @model.select_tool(hud)
        hud.onMouseMove(0,x,y,view)
        hud.onKeyDown(17,1,0,view)
        check(hud.instance_variable_get(:@placement)&.fetch('mode')=='replace','Ctrl held without moving the mouse switches HUD preview to replacement')
        hud.draw(view)
        check(hud.error.nil? && hud.instance_variable_get(:@draw_error).nil? && !hud.getExtents.empty?,'Replacement preview draws in the actual HUD and contributes bounds')
        hud.onKeyUp(17,1,0,view)
        check(hud.instance_variable_get(:@placement).nil?,'Releasing Ctrl restores ordinary placement preview')
        pid = target.persistent_id
        hud.onLButtonDown(COPY_MODIFIER_MASK,x,y,view)
        check(hud.error.nil? && hud.pending.nil? && !hud.active && !HUDInput.active? && @model.selection.first&.persistent_id==pid,'Actual Ctrl mouse click replaces the scene module then closes HUD and restores keyboard')
        check(!MH::ModuleStudio.instance_variable_get(:@module_options)&.instance_variable_get(:@dialog)&.visible?,'Replacement does not automatically open Module Options')
        valid_parametric(target,'Module replaced through HUD is parametrically editable')
        hud = LibraryHUD.new(library,data)
        @model.select_tool(hud)
        before = @model.entities.to_a
        hud.onLButtonDown(0,x,y,view)
        check(hud.error.nil? && !hud.active && !HUDInput.active? && (@model.entities.to_a-before).length==1,'Ordinary import also places one module then closes HUD')
        check(!MH::ModuleStudio.instance_variable_get(:@module_options)&.instance_variable_get(:@dialog)&.visible?,'Ordinary import does not automatically open Module Options')
      ensure
        hud&.finish
        MH::ModuleStudio.instance_variable_get(:@module_options)&.instance_variable_get(:@dialog)&.close
      end

      def linked_placement_checks(library,data)
        a = own('MH QA replace linked reference'); b = own('MH QA replace linked target')
        record = Assembly.save(@model,{'mode'=>'contact','a'=>own_anchor(a,'Hông Phải',1),'b'=>own_anchor(b,'Hông Trái',0),'gap'=>5})
        b = Assembly.root(@model,record['b'])
        pid = b.persistent_id
        before = JSON.generate(Assembly.records(@model)); prior = state([b])
        result = library.place(data,ORIGIN,placement:descriptor(b,record['scope']))
        current = Assembly.records(@model).find { |row| row['id']==record['id'] }
        Assembly.verify(@model,current)
        check(result.persistent_id==pid && current['b']['part']==b.definition.entities.find { |e| e.name=='Hông Trái' }.get_attribute(Reader::DICT,'part_key'),'Linked replacement remaps old face anchors to corresponding new panels')
        valid_parametric(result,'Linked replacement retains editable parameters')
        Sketchup.undo
        check(before==JSON.generate(Assembly.records(@model)) && prior==state([b]),'One Undo restores linked replacement and all saved references')
        wrapper = AssemblyContainers.wrapper(@model,record['scope'])
        @model.start_operation('MH QA copied linked replacement',true)
        copy = @model.entities.add_instance(wrapper.definition,Geom::Transformation.translation([0,8000.0/25.4,0]))
        wrapper.attribute_dictionaries.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } }
        @model.commit_operation
        copied = Assembly.records(@model).find { |row| row['scope']==copy.persistent_id.to_s }
        target = Assembly.root(@model,copied['b'])
        source_definition = wrapper.definition
        source_state = state(AssemblyContainers.members(wrapper))
        library.place(data,ORIGIN,placement:descriptor(target,copied['scope']))
        current = Assembly.records(@model).find { |row| row['scope']==copy.persistent_id.to_s }
        Assembly.verify(@model,current)
        check(wrapper.definition==source_definition && copy.definition!=source_definition && source_state==state(AssemblyContainers.members(wrapper)),'Replacing a copied assembly member isolates only the copied instance')
        before = state(AssemblyContainers.members(copy)); links = JSON.generate(Assembly.records(@model))
        bad = Core.copy_data(data); bad['snapshot']['envelope'][1][0] = 0
        begin
          library.place(bad,ORIGIN,placement:descriptor(Assembly.root(@model,current['b']),current['scope']))
          raise 'Invalid fit accepted'
        rescue Core::Error
          check(before==state(AssemblyContainers.members(copy)) && links==JSON.generate(Assembly.records(@model)),'Failed replacement rolls back all old geometry and links')
        end
        @model.start_operation('MH QA ambiguous replacement face',true)
        fixed = box('MH QA ambiguous reference',[60000,0,0],[600,500,800])
        raw = box('MH QA ambiguous target',[60700,0,0],[600,500,800])
        @model.commit_operation
        ambiguous = Assembly.save(@model,{'mode'=>'contact','a'=>anchor(fixed,2,1),'b'=>anchor(raw,2,1),'gap'=>0})
        raw = Assembly.root(@model,ambiguous['b'])
        definition = raw.definition; before = state([raw]); links = JSON.generate(Assembly.records(@model))
        begin
          library.place(data,ORIGIN,placement:descriptor(raw,ambiguous['scope']))
          raise 'Ambiguous panel remapping accepted'
        rescue Core::Error => detail
          check(detail.message.include?('mặt tương ứng') && raw.definition==definition && before==state([raw]) && links==JSON.generate(Assembly.records(@model)),'Ambiguous old panel anchors abort after replacement and restore the original definition and links')
        end
      end

      def additional_checks
        super
        placement_checks
      end
    end
  end
end
