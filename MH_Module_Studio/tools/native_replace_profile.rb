# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeReplaceProfile
      extend self
      def run(varied: false)
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        active=ModuleStudio.instance_variable_get(:@library)&.tool
        raise 'User placement active' if active&.pending
        before=@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
        definitions=@model.definitions.to_a;selection=@model.selection.to_a
        @library=Library.new;@library.instance_variable_set(:@catalog,LibraryCatalog.scan(@library.config['root']))
        @data=@library.preview('Khung/Khung noc lot.skp')
        @model.start_operation('MH QA Replace timing',true);operation=true
        @previous_busy=Assembly.instance_variable_get(:@busy);Assembly.instance_variable_set(:@busy,true)
        @times=[];@results=[]
        3.times do |index|
          definition=@model.definitions.add('MH QA 084 placeholder')
          box=Core.copy_data(@data['snapshot']['envelope'])
          box[1]=box[1].each_with_index.map { |v,axis| v+index*[100,50,70][axis] } if varied
          points=Frames.corners(box).map { |p| p.map { |v| v/25.4 } }
          [[0,1,2,3],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each { |ids| definition.entities.add_face(ids.map { |id| points[id] }) }
          root=@model.entities.add_instance(definition,Geom::Transformation.translation([100_000/25.4,index*1000/25.4,0]))
          start=Process.clock_gettime(Process::CLOCK_MONOTONIC)
          root=LibraryPlacement.replace!(@library,@data,{'root'=>root.persistent_id.to_s},[])
          @times << ((Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)*1000).round(2)
          actual,=Reader.live(root,label:'QA',parameter:nil)
          raise 'Target dimensions changed' unless Core.bounds_close?(actual['envelope'],box,0.02)
          @results << root
          Runtime.verify_result(root,ScalePlan.plan(*plan_inputs(root))) if index==2
        end
        ids=@results.map { |r| r.get_attribute(Reader::DICT,'instance_id') }
        raise 'Shared instance identity' unless ids.uniq.length==3 && ids.all? { |id| id.is_a?(String) && !id.empty? }
        first=@results.first;other=@results.last
        before_other=Reader.live(other,label:'QA',parameter:nil).first['parts'].map { |p| p['bounds'] }
        rule,_values=AssemblyParameters.data(first);rows=Parametric.variables(rule);thick=rows.find { |r| r['symbol']=='T1' }
        raise 'Missing T1' unless thick
        thick['value']+=1;edited=Parametric.edit_variables(rule,rows);targets=Parametric.targets(edited)
        snapshot,bindings=Reader.live(first,label:'QA',parameter:Runtime.read_parameter(edited,targets));plan=Core.plan(edited,snapshot,targets)
        Runtime.apply_plan(bindings,plan);Runtime.stamp(first,edited,bindings,targets);Runtime.verify_result(first,plan)
        raise 'Other replacement changed with first T' unless before_other==Reader.live(other,label:'QA',parameter:nil).first['parts'].map { |p| p['bounds'] }
        @events=Hash.new { |h,k| h[k]=[0,0.0] };stack=[]
        trace=TracePoint.new(:call,:return,:c_call,:c_return) do |event|
          selected=[:replace!,:build_instance,:validate_geometry,:resize,:private_tree,:stamp,:stamp_redraw,:verify_result,:live,:apply_plan,:apply,:payload,:resize_plan,:load,:plan,:rule!,:targets,:ensure_native,:copy_data].include?(event.method_id)
          next unless selected
          key=event.defined_class.to_s+'.'+event.method_id.to_s
          if [:call,:c_call].include?(event.event)
            stack << [key,Process.clock_gettime(Process::CLOCK_MONOTONIC)]
          elsif stack.last && stack.last[0]==key
            _name,start=stack.pop;@events[key][0]+=1;@events[key][1]+=(Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)*1000
          end
        end
        definition=@model.definitions.add('MH QA 084 profile');definition.entities.add_line([0,0,0],[1,1,1])
        root=@model.entities.add_instance(definition,Geom::Transformation.new)
        # Use a valid repeat target with exactly the verified source dimensions.
        definition.entities.clear!
        box=@data['snapshot']['envelope'];points=Frames.corners(box).map { |p| p.map { |v| v/25.4 } }
        [[0,1,2,3],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each { |ids| definition.entities.add_face(ids.map { |id| points[id] }) }
        trace.enable { LibraryPlacement.replace!(@library,@data,{'root'=>root.persistent_id.to_s},[]) }
        raise 'Replacing reloaded a mutated source' if @events.keys.any? { |key| key=='MH::ModuleStudio::ImportRecovery.plan' }
        {pid:Process.pid,recovery_calls:0,varied:varied,independent:true,model_retained:true,milliseconds:@times,profile:@events.sort_by { |_k,v| -v[1] }.first(30)}
      ensure
        trace&.disable
        @model.abort_operation if operation
        Assembly.instance_variable_set(:@busy,@previous_busy) if operation
        if before
          raise 'Model changed' unless before==@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
          raise 'Definitions changed' unless definitions==@model.definitions.to_a
          raise 'Selection changed' unless selection==@model.selection.to_a
        end
      end
      def plan_inputs(root)
        rule,values=AssemblyParameters.data(root)
        current,=Reader.live(root,label:'QA',parameter:Runtime.read_parameter(rule,values))
        [rule,current,values]
      end
    end
  end
end
