# encoding: UTF-8
module MH
  module ModuleStudio
    # Developer-only native interoperability check. Real MH_stretch operations
    # run on private fixtures; selection is restored before returning to the UI.
    module NativeExternalStretchCheck
      extend self
      class CommitTrace < Sketchup::ModelObserver
        def onTransactionCommit(_model)
          NativeExternalStretchCheck.trace_commit
        end
      end
      def start(source_pid: 1007786, host_pid: 801845, door_pid: 802010)
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        raise 'Another check is running' if @running
        @running=true;@report={'status'=>'running','checks'=>[]};@copies=[];@wrapper=nil
        @observer=Assembly.watch(@model);reset_method=@observer.method(:reset)
        @observer.define_singleton_method(:reset) { NativeExternalStretchCheck.trace_reset(reset_method) }
        @selection=@model.selection.to_a;@definitions=@model.definitions.to_a
        @links=@model.get_attribute(Reader::DICT,Assembly::KEY)
        @preferences=Sketchup.read_default('MH_Module_Studio','library_v1','')
        @before=model_signature
        @roots_method=ImportLinks.method(:roots);previous=@roots_method
        ImportLinks.define_singleton_method(:roots) { |model| previous.call(model).select { |root,_| NativeExternalStretchCheck.owned?(root) } }
        @model.start_operation('MH QA external geometry fixtures',true)
        @single=copy(source_pid);@host=copy(host_pid);@door=copy(door_pid)
        original=JSON.parse(@links || '[]')
        ids={host_pid.to_s=>@host.persistent_id.to_s,door_pid.to_s=>@door.persistent_id.to_s}
        records=original.select { |row| AssemblyContainers.references(row).all? { |ref| ids.key?(ref['root']) } }.map do |row|
          data=Core.copy_data(row);AssemblyContainers.references(data).each { |ref| ref['root']=ids.fetch(ref['root']) };data
        end
        raise 'Expected linked host and door fixture' unless records.any? { |row| row.dig('import_link','door_mount') }
        @model.set_attribute(Reader::DICT,Assembly::KEY,JSON.generate(records));@model.commit_operation
        Assembly.transact(@model,records)
        reset
        scale([@single],1,Core.dimensions(world_box(@single))[1]+200)
        later { exact('MH_stretch Scale restores T',mesh_sizes(@single)[1],17.6);stretch_single_T }
        {scheduled:true,pid:Process.pid}
      rescue StandardError=>error
        fail_check(error)
      end

      def copy(pid)
        source=@model.find_entity_by_persistent_id(pid);raise "Missing source #{pid}" unless Assembly.container?(source)
        transform=Geom::Transformation.translation([(100_000+@copies.length*6000)/25.4,0,0])*source.transformation
        root=@model.entities.add_instance(source.definition,transform);@copies << root
        source.attribute_dictionaries.each { |dictionary| dictionary.each_pair { |key,value| root.set_attribute(dictionary.name,key,value) } }
        root.delete_attribute(Reader::DICT,ImportLinks::RESERVATIONS)
        ScaleRedraw.apply(@model,[ScaleRedraw.prepare(root)])
        root
      end

      def owned?(root)
        @copies.include?(root)
      end

      def model_signature
        @model.entities.reject { |entity| @copies.include?(entity) || entity==@wrapper }.map do |entity|
          [entity.persistent_id,entity.bounds.min.to_a.map { |v| v.round(7) },entity.bounds.max.to_a.map { |v| v.round(7) }]
        end
      end

      def reset
        ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      end

      def later(attempt=0,&action)
        UI.start_timer(0.45,false) do
          begin
            raise 'User geometry changed during QA' unless model_signature==@before
            raise 'User selection changed during QA' unless @model.selection.to_a==@selection
            pending=Assembly.watch(@model).instance_variable_get(:@pending) || !Array(ScaleRedraw.watch(@model).instance_variable_get(:@pending)).empty?
            if pending
              raise 'Observers did not settle' if attempt>=90
              later(attempt+1,&action)
              next
            end
            action.call
          rescue StandardError=>error
            fail_check(error)
          end
        end
      end

      def with_selection(roots)
        previous=@model.selection.to_a;@model.selection.clear;@model.selection.add(roots)
        yield
      ensure
        @model.selection.clear;@model.selection.add(previous.select(&:valid?))
      end

      def world_box(root)
        root.definition.invalidate_bounds
        Frames.box(8.times.map { |index| root.definition.bounds.corner(index).transform(root.transformation).to_a.map { |v| v*25.4 } })
      end

      def total_box
        Frames.box([@host,@door].flat_map { |root| Frames.corners(world_box(root)) })
      end

      def mesh_sizes(root)
        snapshot,=Reader.live(root,label:'QA current geometry',parameter:nil)
        Core.dimensions(snapshot['envelope'])
      end

      def scale(roots,axis,target)
        with_selection(roots) do
          box=Geom::BoundingBox.new;roots.each { |root| box.add(root.bounds) }
          current=[box.width,box.height,box.depth][axis]
          tool=MH::Stretch::BoxTool.new;tool.instance_variable_set(:@bb,box)
          result=tool.send(:scale_selection_without_cut,%i[x y z][axis],target/25.4-current)
          raise result[:message] unless result[:ok]
          tool.send(:finish_model_change,result,@model.active_view)
        end
      end

      def stretch(roots,axis,amount)
        with_selection(roots) do
          box=Geom::BoundingBox.new;roots.each { |root| box.add(root.bounds) }
          result=MH::Stretch::StretchOperation.commit(@model,axis:%i[x y z][axis],side: :plus,plane_pos:box.center.to_a[axis],amount:amount/25.4)
          raise result[:message] unless result[:ok]
        end
      end

      def exact(label,actual,expected)
        @report['checks'] << {'label'=>label,'actual'=>actual,'expected'=>expected}
        raise "#{label}: #{actual} != #{expected}" unless (actual-expected).abs<=0.02
      end

      def stretch_single_T
        stretch([@single],1,100)
        later do
          exact('MH_stretch vertex edit restores T',mesh_sizes(@single)[1],17.6)
          @width=mesh_sizes(@single)[0];stretch([@single],0,100)
          later do
            exact('Stretch increases free width',mesh_sizes(@single)[0],@width+100)
            stretch([@single],0,-140)
            later do
              exact('Repeated Stretch shrinks free width',mesh_sizes(@single)[0],@width-40)
              paired_scale
            end
          end
        end
      end

      def paired_scale
        # Move both fixtures together without altering their relative positions.
        Assembly.transact(@model,Assembly.records(@model))
        @report['paired_before']=pair_state
        reset;@trace=true
        @commit_trace=CommitTrace.new;@model.add_observer(@commit_trace)
        @report['frames_before']=Assembly.watch(@model).instance_variable_get(:@frames)
        scale([@host,@door],1,600)
        records=Assembly.records(@model)
        @report['raw_targets']=ImportLinks.scaled_reservation_targets(@model,records,@report['frames_before'])
        later do
          @report['paired_after']=pair_state
          exact('Paired Scale keeps total depth 600',Core.dimensions(total_box)[1],600)
          exact('Paired Scale keeps door T',mesh_sizes(@door)[1],17.6)
          repairs=Array(@report['commit_trace']).select { |row| row['assembly'] || row['redraw'] }
          exact('Paired Scale has one atomic Studio repair',repairs.length,1)
          repairs.each { |row| exact('No intermediate committed depth',row['total'],600) }
          @depth=Core.dimensions(total_box)[1];stretch([@host],1,100)
          later do
            exact('Host Stretch supplies new total depth',Core.dimensions(total_box)[1],@depth+100)
            edit_door_T
          end
        end
      end

      def trace_reset(original)
        if @trace
          (@report['resets'] ||= []) << {'callers'=>caller.first(5),'before'=>@observer.instance_variable_get(:@frames),'current'=>ImportLinks.root_frames(@model)}
        end
        original.call
      end

      def trace_commit
        return unless @trace && @host.valid? && @door.valid?
        (@report['commit_trace'] ||= []) << {
          'total'=>Core.dimensions(total_box)[1],
          'assembly'=>Assembly.instance_variable_get(:@busy)==true,
          'redraw'=>ScaleRedraw.watch(@model).instance_variable_get(:@applying)==true
        }
      end

      def pair_state
        {'total'=>total_box,'host'=>world_box(@host),'door'=>world_box(@door),
         'reservation'=>ImportLinks.states(@host),'frames'=>ImportLinks.root_frames(@model),
         'planes'=>Assembly.records(@model).map { |row| [Assembly.world_plane(@model,row['a']),Assembly.world_plane(@model,row['b'])] },
         'error'=>Assembly.last_error}
      end

      def edit_door_T
        rule=JSON.parse(@door.get_attribute(Reader::DICT,'rule_json'));variables=Parametric.variables(rule)
        variables.find { |row| row['binding']=='a0van' }['value']=20
        rule=Parametric.edit_variables(rule,variables)
        Assembly.transact(@model,Assembly.records(@model),updates:[[{'root'=>@door.persistent_id.to_s},rule,Parametric.targets(rule)]])
        exact('T edit keeps stretched total',Core.dimensions(total_box)[1],@depth+100)
        exact('Door T changes exactly',mesh_sizes(@door)[1],20)
        @host_width=mesh_sizes(@host)[0];stretch([@host],0,-80)
        later do
          exact('Host width shrinks',mesh_sizes(@host)[0],@host_width-80)
          exact('Linked door follows current host faces',mesh_sizes(@door)[0],@host_width-80)
          Assembly.records(@model).each { |record| Assembly.verify(@model,record) }
          finish
        end
      end

      def fail_check(error)
        @report||={};@report['error']=[error.message,*error.backtrace.first(8)]
        @model.abort_operation if @model
        finish
      end

      def finish
        return unless @running
        @running=false
        @model.remove_observer(@commit_trace) if @commit_trace
        @trace=false;@observer.singleton_class.remove_method(:reset) if @observer&.singleton_class&.instance_methods(false)&.include?(:reset)
        ImportLinks.define_singleton_method(:roots,@roots_method) if @roots_method
        @model.start_operation('MH QA external geometry cleanup',true)
        @wrapper.erase! if @wrapper&.valid?
        @copies.each { |root| root.erase! if root.valid? }
        @links ? @model.set_attribute(Reader::DICT,Assembly::KEY,@links) : @model.delete_attribute(Reader::DICT,Assembly::KEY)
        12.times { (@model.definitions.to_a-@definitions).each { |definition| @model.definitions.remove(definition) if definition.valid? && definition.instances.empty? } }
        @model.commit_operation;reset
        @report['model_retained']=model_signature==@before
        @report['selection_retained']=@model.selection.to_a==@selection
        @report['preferences_retained']=Sketchup.read_default('MH_Module_Studio','library_v1','')==@preferences
        @report['status']=@report['error'] || !@report['model_retained'] || !@report['selection_retained'] || !@report['preferences_retained'] ? 'failed' : 'passed'
        path=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/stretch087/native.json')
        File.write(path,JSON.pretty_generate(@report))
        @report
      end
    end
  end
end
