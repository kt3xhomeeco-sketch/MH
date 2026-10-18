# encoding: UTF-8
require_relative 'native_assembly_scale_check'

module MH
  module ModuleStudio
    module NativeFacePickerCheck
      extend self

      def check(value,message)
        raise message unless value
        @report['checks'] << message
      end

      def reset
        Assembly.watch(@model).reset; ScaleRedraw.watch(@model).reset
      end

      def panel(entities,name,low,size)
        group = entities.add_group; group.name = name
        high = low.zip(size).map(&:sum)
        points = Frames.corners([low,high]).map { |point| point.map { |value| value/25.4 } }
        [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]].each { |indices| group.entities.add_face(indices.map { |index| points[index] }) }
        group
      end

      def module_box(entities,name,x,width)
        definition = @model.definitions.add(name)
        root = entities.add_instance(definition,Geom::Transformation.translation([x/25.4,0,0]))
        root.name = name; root.set_attribute(Reader::DICT,AssemblyContainers::MEMBER,Core::Ids.uuid)
        [[0,0,0,18.6,500,800],[width-18.6,0,0,18.6,500,800],
         [18.6,0,0,width-37.2,500,18.6],[18.6,0,781.4,width-37.2,500,18.6],
         [18.6,492,18.6,width-37.2,8,762.8]].each_with_index do |values,index|
          panel(definition.entities,"Panel #{index}",values.first(3),values.last(3))
        end
        root
      end

      def anchor(entity,axis,side,level,scope = nil)
        {'root'=>entity.persistent_id.to_s,'scope'=>scope,'path'=>[],'axis'=>axis,'side'=>side,'level'=>level}.compact
      end

      def build
        @model.start_operation('MH QA face picking fixtures',true)
        definition = @model.definitions.add('MH QA Picker Assembly')
        wrapper = @model.entities.add_instance(definition,Geom::Transformation.translation([40000/25.4,40000/25.4,0]))
        wrapper.name = 'MH QA Picker Assembly'
        wrapper.set_attribute(Reader::DICT,AssemblyContainers::FLAG,true)
        a = module_box(definition.entities,'MH QA Module A',0,600)
        b = module_box(definition.entities,'MH QA Module B',800,400)
        row = {'id'=>'inside','mode'=>'contact','gap'=>200,'a'=>anchor(a,0,1,'module'),'b'=>anchor(b,0,0,'module')}
        wrapper.set_attribute(Reader::DICT,AssemblyContainers::KEY,JSON.generate([row]))
        @model.commit_operation; reset
        [wrapper,a,b]
      end

      def look(frame,box,axis,side)
        point = 3.times.map { |index| (box[0][index]+box[1][index])/2 }
        point[axis] = box[side][axis]
        target = Geom::Point3d.new(point).transform(frame)
        normal = [0,0,0]; normal[axis] = side.zero? ? -1 : 1
        vector = Geom::Vector3d.new(normal).transform(frame).normalize
        distance = Core.dimensions(box).max*3
        eye = target+vector.tap { |direction| direction.length = distance }
        up = Geom::Vector3d.new(axis==2 ? [0,1,0] : [0,0,1]).transform(frame)
        @view.camera = Sketchup::Camera.new(eye,target,up,false)
        @view.camera.height = Core.dimensions(box).max*1.6
        @view.refresh
        screen = @view.screen_coords(target)
        [screen.x,screen.y]
      end

      def picking(wrapper,a,b)
        picker = AssemblyFacePicker.new(@model)
        @model.start_operation('MH QA hide sibling for six-sided picking',true)
        b.hidden = true
        @model.commit_operation; reset
        [false,true].each do |rotated|
          if rotated
            @model.start_operation('MH QA rotated reflected picker',true)
            wrapper.transformation *= Geom::Transformation.rotation(ORIGIN,Z_AXIS,30.degrees)*Geom::Transformation.scaling(-1,1,1)
            @model.commit_operation; reset
          end
          [[a,wrapper.transformation*a.transformation,4,'module'],[wrapper,wrapper.transformation,8,'assembly']].each do |entity,frame,flags,level|
            box = [entity.definition.bounds.min.to_a,entity.definition.bounds.max.to_a]
            3.times do |axis|
              2.times do |side|
                x,y = look(frame,box,axis,side)
                hit = picker.hit(flags,x,y,@view)
                check(hit && hit['anchor']['root']==entity.persistent_id.to_s && hit['anchor']['axis']==axis && hit['anchor']['side']==side,
                  "#{level} face #{axis}/#{side} picked in #{rotated ? 'rotated/reflected' : 'ordinary'} frame")
              end
            end
          end
        end
        frame = wrapper.transformation*a.transformation
        box = [a.definition.bounds.min.to_a,a.definition.bounds.max.to_a]
        x,y = look(frame,box,1,0)
        actual = picker.hit(0,x,y,@view)
        virtual = picker.hit(4,x,y,@view)
        check(actual && actual['mesh'] && actual['anchor'].fetch('path',[]).length>0,'Click picks the real back-panel face through an open front')
        check(virtual && virtual['anchor']['path']==[] && virtual['anchor']['axis']==1 && virtual['anchor']['side']==0,'Shift picks virtual front envelope across an empty cabinet opening')
        [3,9].each do |pixels|
          point = Geom::Point3d.new(box[0][0],box[0][1],box.sum { |bound| bound[2] }/2)
          point.x -= @view.pixels_to_model(pixels,point.transform(frame))/frame.xaxis.length
          screen = @view.screen_coords(point.transform(frame))
          near = picker.hit(4,screen.x,screen.y,@view)
          check(pixels==3 ? near && near['anchor']['root']==a.persistent_id.to_s : near.nil?,
            "Envelope edge tolerance #{pixels==3 ? 'accepts a nearby' : 'rejects a distant'} pointer")
        end
        tool = AssemblyTool.new
        before = NativeDrawerCheck.fingerprint(wrapper)
        tool.onMouseMove(0,x,y,@view)
        check(tool.instance_variable_get(:@hover)['level']=='part','Hover starts at actual panel level')
        tool.onKeyDown(16,0,0,@view)
        check(tool.instance_variable_get(:@hover)['level']=='module','Shift updates hover without moving the pointer')
        tool.onKeyDown(17,0,4,@view)
        check(tool.instance_variable_get(:@hover)['level']=='assembly','Ctrl takes precedence over Shift')
        tool.onKeyUp(17,0,4,@view)
        check(tool.instance_variable_get(:@hover)['level']=='module','Releasing Ctrl returns to Shift module picking')
        tool.onKeyUp(16,0,0,@view)
        check(tool.instance_variable_get(:@hover)['level']=='part','Releasing Shift restores real-face picking')
        tool.onLButtonDown(4,x,y,@view)
        check(tool.record.dig('a','level')=='module' && tool.record.dig('a','root')==a.persistent_id.to_s,'Shift click commits exactly the previewed module face')
        tool.fresh
        tool.onLButtonDown(8,x,y,@view)
        check(tool.record.dig('a','level')=='assembly' && tool.record.dig('a','root')==wrapper.persistent_id.to_s,'Ctrl click commits the whole-assembly envelope face')
        tool.onMouseLeave(@view)
        check(tool.instance_variable_get(:@hover).nil? && before==NativeDrawerCheck.fingerprint(wrapper),'Hover/draft picking never modifies model geometry or saved data')
        @model.start_operation('MH QA restore fixture orientation',true)
        wrapper.transformation = Geom::Transformation.translation([40000/25.4,40000/25.4,0])
        b.hidden = false
        @model.commit_operation; reset
      end

      def linking(wrapper)
        helper = NativeAssemblyScaleCheck; helper.instance_variable_set(:@model,@model)
        copy = helper.clone_wrapper(wrapper)
        local = AssemblyContainers.members(copy).map(&:persistent_id)
        internal = AssemblyContainers.read(copy)
        first = Assembly.save(@model,{'mode'=>'contact','gap'=>-10,'a'=>anchor(wrapper,0,0,'assembly'),'b'=>anchor(copy,0,0,'assembly')})
        check(first['external'] && !first['scope'] && copy.valid? && wrapper.valid?,'Whole-assembly link keeps both existing assembly components intact')
        check(local==AssemblyContainers.members(copy).map(&:persistent_id) && internal==AssemblyContainers.read(copy),'Whole-assembly translation preserves member identities and internal links')
        second = Assembly.save(@model,{'mode'=>'contact','gap'=>-10,'a'=>anchor(wrapper,0,1,'assembly'),'b'=>anchor(copy,0,1,'assembly')})
        check((Core.dimensions(AssemblyEnvelope.bounds(copy))[0]-1180).abs<0.02,'Two whole-assembly contacts resize B and preserve internal spacing')
        Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
        check(true,'All prior internal and new external links verify together')
        before = NativeDrawerCheck.fingerprint(copy)
        member = AssemblyContainers.members(copy).first
        begin
          Assembly.save(@model,{'mode'=>'contact','gap'=>0,'a'=>anchor(copy,0,0,'assembly'),'b'=>anchor(member,0,0,'module',copy.persistent_id.to_s)})
          raise 'Self-containing relationship accepted'
        rescue Core::Error
          check(before==NativeDrawerCheck.fingerprint(copy),'Self-containing assembly dependency is rejected atomically')
        end
        second['gap'] = -20
        Assembly.save(@model,second)
        check((Core.dimensions(AssemblyEnvelope.bounds(copy))[0]-1170).abs<0.02,'Saved external envelope anchors remain editable after redraw')
        Sketchup.undo; reset
        check((Core.dimensions(AssemblyEnvelope.bounds(copy))[0]-1180).abs<0.02,'One Undo restores assembly envelope and the external relationship')
        third = helper.clone_wrapper(wrapper)
        @model.start_operation('MH QA mixed-space target',true)
        third.transformation = Geom::Transformation.translation([50000/25.4,40000/25.4,0])*Geom::Transformation.rotation(ORIGIN,Z_AXIS,90.degrees)*Geom::Transformation.scaling(-1,1,1)
        @model.commit_operation; reset
        member = AssemblyContainers.members(third).first
        mixed = Assembly.save(@model,{'mode'=>'contact','gap'=>30,'a'=>anchor(wrapper,0,1,'assembly'),
          'b'=>anchor(member,1,0,'module',third.persistent_id.to_s)})
        Assembly.verify(@model,mixed)
        Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
        check(true,'Assembly-to-module link resolves a rotated/reflected parent coordinate frame and retains internal contacts')
        check(Assembly.fingerprint(@model).is_a?(String),'Observer fingerprint resolves the actual parent scope of an external module target')
        source = @model.find_entity_by_persistent_id(450543)
        if AssemblyContainers.managed?(source)
          live = helper.clone_wrapper(source)
          before = AssemblyContainers.members(live).to_h { |entity| [entity.persistent_id,entity.get_attribute(Reader::DICT,'parameter_values_json')] }
          low = Assembly.save(@model,{'mode'=>'contact','gap'=>-10,'a'=>anchor(wrapper,0,0,'assembly'),'b'=>anchor(live,0,0,'assembly')})
          Assembly.save(@model,{'mode'=>'contact','gap'=>-10,'a'=>anchor(wrapper,0,1,'assembly'),'b'=>anchor(live,0,1,'assembly')})
          check((Core.dimensions(AssemblyEnvelope.bounds(live))[0]-1180).abs<0.02,'Whole-assembly contacts fit an independent copy of the actual formula-driven cabinet/door assembly')
          check(before.all? { |pid,values| @model.find_entity_by_persistent_id(pid).get_attribute(Reader::DICT,'parameter_values_json')==values },'Whole-assembly fitting retains all actual T1/T2 parameter values')
          Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
          AssemblyContainers.members(live).each do |entity|
            rule,values,current, = NativeDrawerCheck.current(entity)
            raise 'Live member formula state drifted' unless Core.plan(rule,current,values)['changed_count'].zero?
          end
          check(!!low['external'],'Real owned formulas remain idempotent after whole-assembly fitting')
        else
          @report['live_source_skipped'] = true
        end
        first
      end

      def other_modes(wrapper)
        helper = NativeAssemblyScaleCheck; helper.instance_variable_set(:@model,@model)
        %w[center fit angle].each do |mode|
          copy = helper.clone_wrapper(wrapper)
          record = {'mode'=>mode,'gap'=>5,'a'=>anchor(wrapper,0,0,'assembly'),'b'=>anchor(copy,0,0,'assembly')}
          record['c'] = anchor(wrapper,0,1,'assembly') unless mode=='angle'
          record['angle'] = 90 if mode=='angle'
          saved = Assembly.save(@model,record)
          Assembly.verify(@model,saved)
          Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
          check(true,"Whole-assembly #{mode} uses model-space planes and preserves internal links")
        end
        @model.start_operation('MH QA standalone Shift targets',true)
        a = module_box(@model.entities,'MH QA Standalone A',60000,600)
        b = module_box(@model.entities,'MH QA Standalone B',61000,400)
        @model.commit_operation; reset
        link = Assembly.save(@model,{'mode'=>'contact','gap'=>0,'a'=>anchor(a,0,1,'module'),'b'=>anchor(b,0,0,'module')})
        check(!link['scope'] && a.valid? && b.valid?,'Saving a Shift module link keeps the actual instances ungrouped')
        link = Assembly.group(@model,link)
        Assembly.verify(@model,link)
        check(link['scope'] && !link['external'] && link.dig('a','level')=='module' && link.dig('b','level')=='module',
          'Explicit grouping preserves Shift module envelope metadata')
        @model.start_operation('MH QA module beside referenced assembly',true)
        extra = module_box(@model.entities,'MH QA Extra Module',62000,400)
        @model.commit_operation; reset
        member = AssemblyContainers.members(wrapper).first
        connected = Assembly.save(@model,{'mode'=>'contact','gap'=>25,'a'=>anchor(member,2,1,'module',wrapper.persistent_id.to_s),'b'=>anchor(extra,2,0,'module')})
        Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
        check(connected['external'] && wrapper.valid?,'Adding another relationship preserves an assembly already referenced by an external link')
      end

      def run(expected_pid:)
        @model = Sketchup.active_model; @view = @model.active_view
        raise 'Pinned model 1 only' unless Process.pid==expected_pid && @model.title=='1' && !@model.active_path
        roots = @model.entities.to_a; defs = @model.definitions.to_a; selected = @model.selection.to_a; camera = @view.camera.clone
        global = @model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        fingerprints = roots.select { |root| Assembly.container?(root) }.to_h { |root| [root,NativeDrawerCheck.fingerprint(root)] }
        @report = {'ok'=>false,'checks'=>[]}
        begin
          wrapper,a,b = build
          picking(wrapper,a,b)
          linking(wrapper)
          other_modes(wrapper)
          @report['ok'] = true
        rescue StandardError => error
          @report['error'] = [error.message,*error.backtrace.first(7)]
        ensure
          Assembly.instance_variable_set(:@busy,true)
          @model.start_operation('MH QA face picker cleanup',true)
          if global
            @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,global)
          else
            @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
          end
          added = @model.entities.to_a-roots; @model.entities.erase_entities(added) unless added.empty?
          loop do
            unused = (@model.definitions.to_a-defs).select { |definition| definition.instances.empty? }
            break if unused.empty?
            unused.each { |definition| @model.definitions.remove(definition) }
          end
          @model.selection.clear; @model.selection.add(selected.select(&:valid?)); @view.camera = camera
          @model.commit_operation
          Assembly.instance_variable_set(:@busy,false); reset
          @report['originals_retained'] = roots==@model.entities.to_a && defs==@model.definitions.to_a && selected==@model.selection.to_a && global==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY) && fingerprints.all? { |root,sha| NativeDrawerCheck.fingerprint(root)==sha }
          @report['ok'] &&= @report['originals_retained']
          base = File.dirname(Panel.instance_method(:request).source_location.first)
          File.write(File.join(base,'outputs/face-picking-042/native.json'),JSON.pretty_generate(@report))
        end
        @report
      end
    end
  end
end
