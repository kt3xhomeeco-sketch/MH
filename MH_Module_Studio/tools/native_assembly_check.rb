# encoding: UTF-8
# Isolated saved fixture only; never run against the user's active model.
module MH
  module ModuleStudio
    module NativeAssemblyCheck
      extend self

      def check(condition, label)
        raise label unless condition
        @report['checks'] << label
      end

      def close(a, b)
        (a-b).abs < 0.025
      end

      def anchor(root, name, axis, side)
        part = root.definition.entities.find { |item| Assembly.container?(item) && item.name == name }
        raise "Missing fixture part #{name}" unless part
        bounds = part.definition.bounds
        coordinate = side.zero? ? bounds.min.to_a[axis] : bounds.max.to_a[axis]
        face = part.definition.entities.grep(Sketchup::Face).find do |item|
          item.normal.to_a[axis].abs > 0.999 && item.vertices.all? { |vertex| (vertex.position.to_a[axis]-coordinate).abs < 0.001 }
        end
        Assembly.anchor([root,part,face])
      end

      def create_owned(name)
        snapshot = JSON.parse(File.read(File.join(@base,'test/fixtures/readable_nested_dc.json'),encoding:'UTF-8'))
        rule = StudioCalculation.build_system([snapshot])
        Runtime.create_model(snapshot,rule,Parametric.targets(rule))
        entity = @model.selection.first
        entity.name = name
        entity
      end

      def create_box(name, xyz, size)
        definition = @model.definitions.add(name)
        entity = @model.active_entities.add_instance(definition,Geom::Transformation.translation(xyz.map { |value| value/25.4 }))
        entity.name = name
        group = definition.entities.add_group
        group.name = name+' panel'
        w,d,h = size.map { |value| value/25.4 }
        points = [[0,0,0],[w,0,0],[w,d,0],[0,d,0],[0,0,h],[w,0,h],[w,d,h],[0,d,h]]
        [[3,2,1,0],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each { |ids| group.entities.add_face(ids.map { |i| points[i] }) }
        entity
      end

      def width(entity)
        low, high = Assembly.projection(entity,[1,0,0])
        high-low
      end

      def queue(label, &block)
        @queue << [label,block]
      end

      def start
        @base = File.dirname(Panel.instance_method(:request).source_location.first)
        @model = Sketchup.active_model
        expected = File.join(@base,'outputs/assembly-028/1.skp')
        raise 'Only the isolated assembly fixture is permitted' unless File.expand_path(@model.path).casecmp?(expected)
        @report = { 'pid'=>Process.pid, 'checks'=>[], 'ok'=>false }
        @done = false
        @originals = @model.entities.to_a
        @original_states = @originals.map { |entity| [entity.persistent_id,entity.transformation.to_a,entity.attribute_dictionaries&.map { |dict| [dict.name,dict.to_a] }] }
        @queue = []
        Assembly.install
        @a = create_owned('QA A Cabinet')
        @b = create_owned('QA B Insert')
        @model.start_operation('QA Assembly Fixture',true)
        @shelf = create_box('QA Shelf',[1000,0,0],[100,80,18])
        @measure = create_box('QA Measured offset',[1500,0,0],[80,80,80])
        @angled = create_box('QA Angled',[1800,0,0],[100,80,100])
        @model.commit_operation
        @left = anchor(@a,'Hông Trái',0,1)
        @right = anchor(@a,'Hông Phải',0,0)
        @bleft = anchor(@b,'Hông Trái',0,0)
        queue('contact and update') do
          @contact = Assembly.save(@model,{'mode'=>'contact','a'=>@left,'b'=>@bleft,'gap'=>3})
          check(close(Assembly.plane(@model,@bleft)['point'][0],21.6),'Native contact on actual inside panel face')
          @contact['gap'] = 7
          @contact = Assembly.save(@model,@contact)
          check(close(Assembly.plane(@model,@bleft)['point'][0],25.6),'Saved offset edits move B and keep A fixed')
          Assembly.remove(@model,@contact['id'])
          @fit = Assembly.save(@model,{'mode'=>'fit','a'=>@left,'b'=>@bleft,'c'=>@right,'gap'=>3})
          check(close(width(@b),556.8),'Owned ATT module fits 556.8 mm without scaling panel thickness')
          rule = Core.rule!(JSON.parse(@b.get_attribute(Reader::DICT,'rule_json')))
          snapshot, = Reader.live(@b,label:'fit verification',parameter:nil)
          check(Core.plan(rule,snapshot,{})['changed_count'].zero?,'Owned ATT remains editable and idempotent after fit')
        end
        queue('parameter driven reference change') do
          rule = Core.rule!(JSON.parse(@a.get_attribute(Reader::DICT,'rule_json')))
          Runtime.update_trial(@a,rule,'dayvan'=>25)
        end
        queue('automatic fit and direct manipulation') do
          check(close(width(@a),600) && close(width(@b),544),'Deferred observer follows 25 mm panel change and preserves reference envelope')
          tool = AssemblyTool.new
          @model.selection.clear; @model.selection.add(@b)
          @model.select_tool(tool)
          tool.load_record(Assembly.records(@model).find { |row| row['id']==@fit['id'] })
          tool.draw(@model.active_view)
          check(tool.error.nil?,'Actual HUD draws controls and handles')
          tool.action(:field,'gap')
          tool.onUserText('5mm',@model.active_view)
          @fit = Core.copy_data(tool.record)
          check(tool.error.nil? && close(width(@b),540),'HUD numeric field applies immediately without Studio')
          before = @b.transformation.origin.to_a
          links,delta = Assembly.move(@model,@bleft,[100,30,40])
          check(delta==[0.0,30.0,40.0],'Handle motion removes constrained normal and retains two tangential directions')
          Assembly.transact(@model,links,motion:[@bleft,delta])
          check(close(@b.transformation.origin.y*25.4,before[1]*25.4+30),'Tangential manual movement commits to actual geometry')
          Assembly.verify(@model,@fit)
          raw = @model.get_attribute(Reader::DICT,Assembly::KEY)
          frame = @b.transformation.to_a
          begin
            Assembly.save(@model,{'mode'=>'contact','a'=>@left,'b'=>@bleft,'gap'=>90})
            raise 'Conflicting constraint accepted'
          rescue Core::Error
            check(raw==@model.get_attribute(Reader::DICT,Assembly::KEY) && frame==@b.transformation.to_a,'Conflicting link aborts geometry and stored rules atomically')
          end
          @model.select_tool(nil)
        end
        queue('repetition directions') do
          ref = anchor(@shelf,'QA Shelf panel',0,0)
          @repeat = Assembly.save(@model,{'mode'=>'repeat','b'=>ref,'count'=>3,'gap'=>100,'direction'=>'up','equal'=>false,'ends'=>true})
          instances = [@shelf,*@repeat['copies'].map { |pid| Assembly.root(@model,'root'=>pid) }]
          check(instances.zip([0,118,236]).all? { |entity,z| close(Assembly.projection(entity,[0,0,1])[0],z) },'Three shelves use 100 mm clear gaps upward')
          @repeat['direction'] = 'down'
          @repeat = Assembly.save(@model,@repeat)
          copies = @repeat['copies'].map { |pid| Assembly.root(@model,'root'=>pid) }
          check(close(Assembly.projection(copies.first,[0,0,1])[0],-118),'Repeat downward reverses placement without changing clear gap')
          %w[right left].each do |direction|
            @repeat['direction'] = direction
            @repeat = Assembly.save(@model,@repeat)
            Assembly.verify(@model,@repeat)
          end
          check(true,'Repeat left and right both verified')
          @repeat['count'] = 4
          @repeat = Assembly.save(@model,@repeat)
          @array_four = @model.get_attribute(Reader::DICT,Assembly::KEY)
          check(@repeat['copies'].length==3,'HUD repeat count includes source and adds only required copies')
          Sketchup.undo
        end
        queue('Undo Redo') do
          restored = Assembly.records(@model).find { |row| row['id']==@repeat['id'] }
          check(restored['count']==3 && restored['copies'].length==2,'One Undo restores repeat count, instances and rules')
          Sketchup.send_action('editRedo:')
        end
        queue('equal intervals and reference gap') do
          check(@array_four==@model.get_attribute(Reader::DICT,Assembly::KEY),'Redo restores complete array operation')
          @repeat = Assembly.records(@model).find { |row| row['id']==@repeat['id'] }
          @repeat.merge!('a'=>anchor(@a,'Đáy',2,1),'c'=>anchor(@a,'Hông Trái',2,1),'count'=>3,'direction'=>'up','equal'=>true)
          @repeat = Assembly.save(@model,@repeat)
          normal, _bounds, result = Assembly.repeat_plan(@model,@repeat)
          check(normal==[0.0,0.0,1.0] && result['gap']>0,'Equal shelf gaps derive from actual bottom/top planes')
          Assembly.verify(@model,@repeat)
          target = anchor(@measure,'QA Measured offset panel',0,0)
          @measured = Assembly.save(@model,{'mode'=>'contact','a'=>@left,'b'=>target,'gap'=>0,'r1'=>@left,'r2'=>@right})
          check(close(Assembly.distance(@model,@measured),550),'Measured clearance is a live two-face reference')
          angled = anchor(@angled,'QA Angled panel',0,0)
          @angle = Assembly.save(@model,{'mode'=>'angle','a'=>@left,'b'=>angled,'angle'=>45})
          Assembly.verify(@model,@angle)
          check(true,'Arbitrary 45 degree face angle verified on native module')
          rule = Core.rule!(JSON.parse(@a.get_attribute(Reader::DICT,'rule_json')))
          Runtime.update_trial(@a,rule,'dayvan'=>22)
        end
        queue('saved rules and HUD gestures') do
          check(close(Assembly.distance(@model,@measured),556),'Measured reference updates after panel thickness changes')
          Assembly.records(@model).each { |record| Assembly.verify(@model,record) }
          @model.selection.clear; @model.selection.add(@b)
          MH::ModuleStudio.open_assembly
          tool = MH::ModuleStudio.instance_variable_get(:@assembly_tool)
          tool.draw(@model.active_view)
          view = @model.active_view
          view.zoom_extents
          view.camera = Sketchup::Camera.new([90,-150,110],[15,0,15],Z_AXIS)
          tool.draw(view)
          handle = tool.instance_variable_get(:@handles).find { |item| item['kind']=='gap' }
          old_gap = tool.record['gap']
          x,y = handle['screen']
          tool.start_drag(handle,x,y,view)
          tool.onMouseMove(0,x+30,y,view)
          check(tool.record['gap']!=old_gap,'Mouse normal handle updates the preview value')
          tool.onKeyDown(27,1,0,view)
          check(tool.record['gap']==old_gap,'Escape cancels drag without altering geometry')
          tool.start_drag(handle,x,y,view)
          tool.onMouseMove(0,x+20,y,view)
          tool.onLButtonUp(0,x+20,y,view)
          check(tool.error.nil? && tool.record['gap']!=old_gap,'Mouse release commits normal handle edit')
          Assembly.records(@model).each { |record| Assembly.verify(@model,record) }
          view.refresh
          view.write_image(filename:File.join(@base,'outputs/assembly-028/hud-native.png'),width:1440,height:900,antialias:true)
          check(@original_states==@originals.map { |entity| [entity.persistent_id,entity.transformation.to_a,entity.attribute_dictionaries&.map { |dict| [dict.name,dict.to_a] }] },'Pre-existing isolated fixture modules retained')
          @report['saved_links'] = Assembly.records(@model).length
          @model.save
          @report['ok'] = true
          finish
        end
        tick
      rescue StandardError => detail
        fail_check(detail)
      end

      def tick
        return unless (job=@queue.shift)
        UI.start_timer(0.5,false) do
          begin
            @report['current'] = job[0]
            job[1].call
            tick unless @done
          rescue StandardError => detail
            fail_check(detail)
          end
        end
      end

      def fail_check(detail)
        @report ||= {'checks'=>[]}
        @report['error'] = detail.full_message
        finish
      end

      def finish
        @done = true
        File.write(File.join(@base,'outputs/assembly-028/native-check.json'),JSON.pretty_generate(@report))
      end
    end
  end
end
MH::ModuleStudio::NativeAssemblyCheck.start
puts 'Isolated native assembly checks scheduled'
