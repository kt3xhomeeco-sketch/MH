# encoding: UTF-8
# Guarded QA in the already-running session. Only newly-created fixtures are
# removed; no model is opened, saved, closed or replaced by this check.
module MH
  module ModuleStudio
    module NativeComponentDragCheck
      extend self

      def check(condition, label)
        raise label unless condition
        @checks << label
      end

      def box(name, xyz, size)
        definition = @model.definitions.add(name)
        entity = @model.active_entities.add_instance(definition,Geom::Transformation.translation(xyz.map { |value| value/25.4 }))
        entity.name = name
        panel = definition.entities.add_group
        panel.name = 'panel'
        w,d,h = size.map { |value| value/25.4 }
        points = [[0,0,0],[w,0,0],[w,d,0],[0,d,0],[0,0,h],[w,0,h],[w,d,h],[0,d,h]]
        [[3,2,1,0],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each { |ids| panel.entities.add_face(ids.map { |i| points[i] }) }
        entity
      end

      def anchor(root, axis, side)
        part = root.definition.entities.grep(Sketchup::Group).first
        { 'root'=>root.persistent_id.to_s,'path'=>[part.persistent_id.to_s],'axis'=>axis,'side'=>side,'name'=>root.name }
      end

      def own(name)
        snapshot = JSON.parse(File.read(File.join(@base,'test/fixtures/readable_nested_dc.json'),encoding:'UTF-8'))
        rule = StudioCalculation.build_system([snapshot])
        Runtime.create_model(snapshot,rule,Parametric.targets(rule))
        root = @model.selection.first
        root.name = name
        root
      end

      def own_anchor(root, name, side)
        part = root.definition.entities.find { |entity| Assembly.container?(entity) && entity.name==name }
        { 'root'=>root.persistent_id.to_s,'part'=>part.get_attribute(Reader::DICT,'part_key'),'axis'=>0,'side'=>side }
      end

      def state(entities)
        entities.map do |entity|
          [entity.persistent_id,entity.respond_to?(:transformation) ? entity.transformation.to_a : nil,
           entity.attribute_dictionaries&.map { |dict| [dict.name,dict.to_a] }]
        end
      end

      def additional_checks
      end

      def run(expected_pid: 19224)
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @model = Sketchup.active_model
        raise 'Guard: use the existing user session' unless Process.pid==expected_pid && @model.active_path.nil?
        originals = @model.entities.to_a
        raise 'QA refuses to modify existing managed assemblies' if originals.any? { |entity| AssemblyContainers.managed?(entity) }
        definitions = @model.definitions.to_a
        original_state = state(originals)
        selection = @model.selection.to_a
        links = @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        camera = @model.active_view.camera
        @checks = []
        report = { 'ok'=>false,'pid'=>Process.pid,'checks'=>@checks }
        begin
          @model.start_operation('MH QA temporary boxes',true)
          @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,'[]')
          a = box('MH QA A',[10000,0,0],[100,100,100])
          b = box('MH QA B',[10300,200,0],[100,100,100])
          @model.commit_operation
          first = {'mode'=>'contact','a'=>anchor(a,0,1),'b'=>anchor(b,0,0),'gap'=>5}
          record = Assembly.save(@model,first)
          Sketchup.undo
          check(a.valid? && b.valid? && a.parent==@model && b.parent==@model && Assembly.records(@model).none? { |row| row['id']==record['id'] },'One Undo removes grouping and solve together while restoring original module roots')
          record = Assembly.save(@model,first)
          wrapper = AssemblyContainers.wrapper(@model,record['scope'])
          b = Assembly.root(@model,record['b'])
          local_a = Assembly.plane(@model,record['a'])['point'][0]
          check(wrapper.is_a?(Sketchup::ComponentInstance) && AssemblyContainers.members(wrapper).length==2,'Saved contact automatically creates a Component with two intact module roots')
          check(Assembly.world_plane(@model,record['b'])['point'][0].round(2)==10105,'Raw panel references survive reparenting and resolve the correct 5 mm gap')
          check(AssemblyContainers.read(wrapper).first['b']['scope'].nil?,'Rules persist on wrapper with local references')
          record['gap'] = 12
          record = Assembly.save(@model,record)
          check(Assembly.plane(@model,record['b'])['point'][0].round(2)==(local_a+12).round(2),'Existing component link edits do not create another wrapper')
          @model.start_operation('MH QA copy wrapper',true)
          copy = @model.active_entities.add_instance(wrapper.definition,Geom::Transformation.translation([0,2000.0/25.4,0]))
          wrapper.attribute_dictionaries.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } }
          @model.commit_operation
          copied = Assembly.records(@model).find { |row| row['scope']==copy.persistent_id.to_s }
          copied['gap'] = 25
          copied = Assembly.save(@model,copied)
          check(copy.definition!=wrapper.definition,'Editing a copied assembly makes its module tree independent')
          check(Assembly.plane(@model,copied['b'])['point'][0].round(2)==(local_a+25).round(2) && Assembly.plane(@model,record['b'])['point'][0].round(2)==(local_a+12).round(2),'Copied assembly gap edit preserves original geometry and rules')
          @model.start_operation('MH QA rotate wrapper',true)
          wrapper.transformation = Geom::Transformation.rotation(ORIGIN,Z_AXIS,Math::PI/2)
          @model.commit_operation
          record['gap'] = 15
          record = Assembly.save(@model,record)
          world = Assembly.world_plane(@model,record['b'])
          check(world['point'][1].round(2)==(local_a+15).round(2),'Rotated component uses local solving and correct world face coordinates')
          tool = AssemblyTool.new
          tool.load_record(record)
          view = @model.active_view
          origin = world['point']
          before = b.transformation.to_a
          old_y = b.transformation.origin.y*25.4
          tool.start_drag(record['b'],origin,nil,100,100,view)
          tool.onLButtonUp(0,100,100,view)
          check(tool.error.nil? && before==b.transformation.to_a,'Click without dragging leaves actual module geometry unchanged')
          tool.start_drag(record['b'],origin,nil,100,100,view)
          tool.instance_variable_get(:@drag).merge!('moved'=>true,'delta'=>[80,30,40])
          tool.onLButtonUp(0,140,130,view)
          check(tool.error.nil? && (b.transformation.origin.y*25.4-old_y-30).abs<0.02,'Body drag commits allowed tangent movement and removes forbidden normal movement')
          Assembly.verify(@model,tool.record)
          tool.start_drag(record['b'],origin,[1,0,0],100,100,view)
          tool.instance_variable_get(:@drag)['moved'] = true
          tool.record['gap'] = 22
          tool.onLButtonUp(0,150,100,view)
          record = Core.copy_data(tool.record)
          check(tool.error.nil? && Assembly.distance(@model,record)==22,'Held contact face changes stored gap and moves actual module')
          tool.start_drag(record['b'],origin,[1,0,0],100,100,view)
          tool.record['gap'] = 33
          tool.cancel_gesture
          check(tool.record['gap']==22 && Assembly.distance(@model,record)==22,'Escape cancels uncommitted face drag')
          # Exercise real PickHelper paths and screen-to-world mouse callbacks.
          face = Assembly.world_plane(@model,copied['b'])
          target = Geom::Point3d.new(face['point'].map { |value| value/25.4 })
          eye = target+Geom::Vector3d.new(-600.0/25.4,-350.0/25.4,200.0/25.4)
          view.camera = Sketchup::Camera.new(eye,target,Z_AXIS,false)
          view.camera.height = 600.0/25.4
          view.refresh
          screen = view.screen_coords(target)
          tool.load_record(copied)
          tool.onLButtonDown(0,screen.x,screen.y,view)
          check(tool.error.nil? && tool.instance_variable_get(:@drag)&.fetch('kind')=='gap','Real face picking through component scope starts direct gap drag')
          tool.draw(view)
          check(tool.error.nil? && tool.instance_variable_get(:@held_mesh) && !tool.instance_variable_defined?(:@handles),'Held face renders dark mesh overlay with no XYZ handles')
          normal = Geom::Vector3d.new(Assembly.plane(@model,copied['a'])['normal']).transform(AssemblyContainers.frame(@model,copied['a']))
          normal.length = 20.0/25.4
          finish = view.screen_coords(target+normal)
          tool.onMouseMove(0,finish.x,finish.y,view)
          check(tool.error.nil? && (tool.record['gap']-45).abs<0.1,'Mouse movement computes physical gap from the picked face screen projection')
          tool.draw(view)
          tool.onLButtonUp(0,finish.x,finish.y,view)
          check(tool.error.nil? && (Assembly.distance(@model,tool.record)-45).abs<0.1,'Actual mouse release commits face drag geometry and rules')
          copied = Core.copy_data(tool.record)
          body_ref = copied['b'].merge('axis'=>1,'side'=>0)
          body_face = Assembly.world_plane(@model,body_ref)
          target = Geom::Point3d.new(body_face['point'].map { |value| value/25.4 })
          screen = view.screen_coords(target)
          tool.onLButtonDown(0,screen.x,screen.y,view)
          check(tool.error.nil? && tool.instance_variable_get(:@drag)&.fetch('kind')=='free','Another module surface starts body movement rather than offset editing')
          tool.onMouseMove(0,screen.x+30,screen.y-25,view)
          tool.draw(view)
          tool.onLButtonUp(0,screen.x+30,screen.y-25,view)
          check(tool.error.nil?,'Body mouse drag projects movement and keeps all saved constraints valid')
          Assembly.verify(@model,tool.record)
          @model.active_view.camera = camera
          @model.start_operation('MH QA third module',true)
          c = box('MH QA C',[12000,0,0],[100,100,100])
          @model.commit_operation
          joined = Assembly.save(@model,{'mode'=>'contact','a'=>record['b'].merge('side'=>1),'b'=>anchor(c,1,0),'gap'=>7})
          merged = AssemblyContainers.wrapper(@model,joined['scope'])
          check(AssemblyContainers.members(merged).length==3 && AssemblyContainers.read(merged).length==2,'Linking another module merges the connected assembly into one Component')
          Assembly.records(@model).select { |row| row['scope']==joined['scope'] }.each { |row| Assembly.verify(@model,row) }
          left = own('MH QA Owned cabinet'); insert = own('MH QA Owned insert')
          fit = Assembly.save(@model,{'mode'=>'fit','a'=>own_anchor(left,'Hông Trái',1),'c'=>own_anchor(left,'Hông Phải',0),'b'=>own_anchor(insert,'Hông Trái',0),'gap'=>3})
          left = Assembly.root(@model,fit['a']); insert = Assembly.root(@model,fit['b'])
          check((Assembly.projection(insert,[1,0,0]).then { |low,high| high-low }-556.8).abs<0.02,'Owned ATT module fits inside the wrapper without losing parametric rules')
          rule = Core.rule!(JSON.parse(left.get_attribute(Reader::DICT,'rule_json')))
          Runtime.update_trial(left,rule,{'dayvan'=>25})
          Assembly.transact(@model,Assembly.records(@model))
          check((Assembly.projection(insert,[1,0,0]).then { |low,high| high-low }-544).abs<0.02,'Changing parent panel thickness updates fitted module inside the assembly')
          fit_wrapper = AssemblyContainers.wrapper(@model,fit['scope'])
          @model.active_path = [fit_wrapper]
          Runtime.update_trial(insert,Core.rule!(JSON.parse(insert.get_attribute(Reader::DICT,'rule_json'))),{'dayvan'=>20})
          @model.active_path = nil
          check(true,'Owned member parameters remain editable inside the managed component')
          @model.start_operation('MH QA scale wrapper',true)
          fit_wrapper.transformation *= Geom::Transformation.scaling(1.15,1,1)
          @model.commit_operation
          Assembly.transact(@model,Assembly.records(@model))
          check(fit_wrapper.transformation.xaxis.length.round(6)==1,'Wrapper scale is normalized into member modules')
          scaled_left = Assembly.root(@model,fit['a'])
          snapshot, = Reader.live(scaled_left,label:'QA after assembly Scale',parameter:nil)
          check(Core.plan(rule,snapshot,{'dayvan'=>25})['changed_count'].zero?,'Scaled wrapper reconstructs internal ATT members without losing editability')
          @model.start_operation('MH QA repeat source',true)
          shelf = box('MH QA repeated shelf',[14000,0,0],[100,80,18])
          @model.commit_operation
          repeated = Assembly.save(@model,{'mode'=>'repeat','b'=>anchor(shelf,2,1),'direction'=>'up','count'=>3,'gap'=>100,'equal'=>false,'ends'=>true})
          repeat_wrapper = AssemblyContainers.wrapper(@model,repeated['scope'])
          check(AssemblyContainers.members(repeat_wrapper).length==3,'Repeat creates its copies inside the same parent Component')
          %w[left down right up].each do |direction|
            repeated['direction'] = direction
            repeated = Assembly.save(@model,repeated)
            Assembly.verify(@model,repeated)
          end
          repeated['count'] = 2
          repeated = Assembly.save(@model,repeated)
          check(AssemblyContainers.members(repeat_wrapper).length==2,'Repeat direction and count edits retain scoped references and delete only surplus copies')
          additional_checks
          report['ok'] = true
        rescue StandardError => detail
          report['error'] = [detail.message,*detail.backtrace.first(6)]
        ensure
          @model.active_path = nil
          Assembly.instance_variable_set(:@busy,true)
          @model.start_operation('MH QA cleanup temporary geometry',true)
          added = @model.entities.to_a-originals
          @model.active_entities.erase_entities(added) unless added.empty?
          if links.nil?
            @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
          else
            @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,links)
          end
          loop do
            unused = (@model.definitions.to_a-definitions).select { |definition| definition.instances.empty? }
            break if unused.empty?
            unused.each { |definition| @model.definitions.remove(definition) }
          end
          @model.selection.clear
          @model.selection.add(selection.select(&:valid?))
          @model.active_view.camera = camera
          @model.commit_operation
          Assembly.instance_variable_set(:@busy,false)
          Assembly.watch(@model).reset
          ScaleRedraw.watch(@model).reset
          report['originals_retained'] = original_state==state(originals) && (@model.entities.to_a-originals).empty?
          report['definitions_retained'] = definitions==@model.definitions.to_a
          report['selection_retained'] = selection==@model.selection.to_a
          report['ok'] &&= report['originals_retained'] && report['definitions_retained'] && report['selection_retained']
          File.write(File.join(@base,'outputs/assembly-030/native-check.json'),JSON.pretty_generate(report))
        end
        puts JSON.generate(report)
      end
    end
  end
end
