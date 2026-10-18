# encoding: UTF-8
require_relative 'native_auto_contacts_check'

module MH
  module ModuleStudio
    module NativeReplaceRecoveryCheck
      include NativeAutoContactsCheck
      extend self

      class UndoTrace < Sketchup::ModelObserver
        def initialize(state)
          super();@state=state
        end
        %i[onTransactionStart onTransactionCommit onTransactionUndo onTransactionAbort].each do |event|
          define_method(event) do |model|
            @state[:events] << {event:event,name:model.respond_to?(:active_operation_name) ? model.active_operation_name : nil,root_name:@state[:root].valid? ? @state[:root].name : nil,caller:caller.first(5)}
          end
        end
      end

      def descriptor(root)
        {'mode'=>'replace','anchor'=>{'root'=>root.persistent_id.to_s},
         'bounds'=>[root.definition.bounds.min.to_a,root.definition.bounds.max.to_a].map { |point| point.map { |v| v*25.4 } },'frame'=>root.transformation.to_a}
      end

      def world_bounds(root,frame)
        Frames.box(8.times.map { |i| root.definition.bounds.corner(i).transform(frame.inverse*root.transformation).to_a.map { |v| v*25.4 } })
      end

      def run(expected_pid:,output:)
        @model=Sketchup.active_model
        raise 'Wrong session/context' unless Process.pid==expected_pid && @model.active_path.nil?
        @base=File.dirname(Panel.instance_method(:request).source_location.first)
        @report={'ok'=>false,'checks'=>[]};@owned=[]
        originals=@model.entities.to_a;definitions=@model.definitions.to_a;selected=@model.selection.to_a
        original_links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        original_states=originals.select { |root| Assembly.container?(root) }.to_h { |root| [root,[root.transformation.to_a,root.definition.guid]] }
        library=Library.new;library.config['root']='D:/Cong viec/Sketchup/DC/Modul_studio';library.refresh
        source=library.entry('Khung/Khung noc lot.skp');target=library.entry('Khung/Khung noc lot LC50.skp')
        hashes=[source,target].to_h { |item| [item['path'],Digest::SHA256.file(item['path']).hexdigest] }
        begin
          begin
            library.verify_file(source['path'])
            check(true,'The actual source loads consistently in the current native definition cache')
          rescue Core::Error=>error
            check(error.message.include?('Hình học SKP'),'Actual source reproduces the reported strict geometry mismatch')
          end
          data=library.prepare(source['id'])
          check(data['snapshot']['parts'].length==7,'Private import restores the source from its seven saved formula parts')
          target_preview=library.preview(target['id'])
          @model.start_operation('MH QA062 fixtures',true)
          @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,'[]')
          loaded=library.build_instance(target_preview,Geom::Transformation.translation([60000/25.4,60000/25.4,0]))
          @owned << loaded
          loaded.transformation*=Geom::Transformation.rotation(ORIGIN,Z_AXIS,Math::PI/7)*Geom::Transformation.scaling(-1.2,0.85,1.1)
          shared=@model.entities.add_instance(loaded.definition,Geom::Transformation.translation([63000/25.4,60000/25.4,0]));@owned << shared
          @model.commit_operation;reset
          shared_before=NativeDrawerCheck.fingerprint(shared)
          desired=descriptor(loaded);frame=Geom::Transformation.new(desired['frame']);pid=loaded.persistent_id
          result=library.place(data,ORIGIN,placement:desired)
          check(result.persistent_id==pid && Core.bounds_close?(world_bounds(result,frame),desired['bounds'],0.02),'Khung noc lot replaces scaled mirrored rotated LC50 at its actual current oriented dimensions')
          check(NativeDrawerCheck.fingerprint(shared)==shared_before,'Replacing one shared instance leaves the other instance unchanged')
          rule=Core.rule!(JSON.parse(result.get_attribute(Reader::DICT,'rule_json')))
          values=JSON.parse(result.get_attribute(Reader::DICT,'parameter_values_json'))
          snapshot,=Reader.live(result,label:result.name,parameter:Runtime.read_parameter(rule,values))
          check(Core.plan(rule,snapshot,values)['changed_count'].zero?,'Replaced geometry remains parametrically valid')
          check(snapshot['parts'].any? { |part| Core.dimensions(part['bounds']).any? { |size| (size-17.6).abs<0.02 } },'Replacement retains the source physical 17.6 mm T after fitting')
          @model.start_operation('MH QA062 raw targets',true)
          raw=@model.entities.add_group;raw.name='MH QA062 raw group';@owned << raw
          box(raw.entities,'Mesh',[0,0,0],[450,350,700]);raw.transformation=Geom::Transformation.translation([65000/25.4,60000/25.4,0])
          dc=module_root('MH QA062 ordinary DC',67000);box(dc.definition.entities,'Panel',[20,30,40],[520,430,740]);dc.set_attribute('dynamic_attributes','lenx',500/25.4)
          wrapper=module_root('MH QA062 assembly target',69000)
          left=box(wrapper.definition.entities,'Left',[0,0,0],[250,400,700]);right=box(wrapper.definition.entities,'Right',[250,0,0],[500,400,700])
          wrapper.set_attribute(Reader::DICT,AssemblyContainers::FLAG,true)
          link={'id'=>'qa062-internal','mode'=>'contact','gap'=>0,'a'=>{'root'=>left.persistent_id.to_s,'axis'=>0,'side'=>1,'level'=>'module'},'b'=>{'root'=>right.persistent_id.to_s,'axis'=>0,'side'=>0,'level'=>'module'}}
          wrapper.set_attribute(Reader::DICT,AssemblyContainers::KEY,JSON.generate([link]))
          @model.commit_operation;reset
          pick_wrapper(wrapper,left)
          [raw,dc,wrapper].each do |old|
            desired=descriptor(old);frame=Geom::Transformation.new(desired['frame'])
            fresh=library.place(data,ORIGIN,placement:desired)
            @owned << fresh
            check(fresh.is_a?(Sketchup::ComponentInstance) && Core.bounds_close?(world_bounds(fresh,frame),desired['bounds'],0.02),'Replace accepts a raw Group, DC or assembly, retaining measured target dimensions')
          end
          saved=File.join(@base,'outputs/recovered-062.skp')
          library.export(@owned.last,saved)
          check(library.verify_file(saved)['snapshot']['parts'].length==7,'Export opens and strictly verifies serialized geometry before accepting the saved SKP')
          recovery_fixture(library,saved)
          check(hashes.all? { |path,digest| Digest::SHA256.file(path).hexdigest==digest },'Both original library SKPs retain their source bytes')
          @report['ok']=true
        rescue StandardError=>error
          @report['error']=[error.message,*error.backtrace.first(9)]
        ensure
          @model.start_operation('MH QA062 cleanup',true)
          (@model.entities.to_a-originals).each { |entity| entity.erase! if entity.valid? }
          original_links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,original_links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
          30.times do
            empty=(@model.definitions.to_a-definitions).select { |definition| definition.valid? && definition.instances.empty? };break if empty.empty?
            empty.each { |definition| @model.definitions.remove(definition) }
          end
          @model.commit_operation
          @model.selection.clear;selected.each { |entity| @model.selection.add(entity) if entity.valid? };reset
          retained=original_states.all? { |root,state| root.valid? && [root.transformation.to_a,root.definition.guid]==state }
          @report['user_objects_retained']=retained;@report['ok'] &&= retained
          File.write(output,JSON.pretty_generate(@report))
        end
        @report
      end

      def pick_wrapper(wrapper,child)
        face=child.definition.entities.grep(Sketchup::Face).first
        helper=Object.new
        helper.define_singleton_method(:do_pick) { |_x,_y| nil }
        helper.define_singleton_method(:picked_face) { face }
        helper.define_singleton_method(:count) { 1 }
        helper.define_singleton_method(:leaf_at) { |_index| face }
        helper.define_singleton_method(:path_at) { |_index| [wrapper,child,face] }
        helper.define_singleton_method(:transformation_at) { |_index| wrapper.transformation*child.transformation }
        view=Struct.new(:model,:pick_helper).new(@model,helper)
        @model.selection.clear;@model.selection.add(wrapper)
        picked=LibraryPlacement.pick(view,0,0,replace:true).first
        check(picked['root']==wrapper.persistent_id.to_s && !picked['scope'],'Ctrl replacement can select the explicitly selected whole assembly')
        picked=LibraryPlacement.pick(view,0,0).first
        check(picked['root']==child.persistent_id.to_s && picked['scope']==wrapper.persistent_id.to_s,'Ordinary cavity picking still resolves the assembly member')
        @model.selection.clear
      end

      def start_undo(output:)
        model=Sketchup.active_model
        library=Library.new;library.config['root']='D:/Cong viec/Sketchup/DC/Modul_studio';library.refresh
        data=library.prepare('Khung/Khung noc lot.skp')
        selected=model.selection.to_a
        model.start_operation('MH QA062 Undo fixture',true)
        definition=model.definitions.add('MH QA062 Undo target')
        root=model.entities.add_instance(definition,Geom::Transformation.translation([75000/25.4,60000/25.4,0]))
        root.name='MH QA062 Undo target';box(definition.entities,'Panel',[0,0,0],[450,350,700])
        model.selection.clear;model.selection.add(root)
        model.commit_operation;Assembly.watch(model).reset;ScaleRedraw.watch(model).reset
        before=[geometry(root),root.name]
        state={model:model,library:library,data:data,root:root,before:before,selected:selected,output:output,checks:[],events:[]}
        state[:observer]=UndoTrace.new(state);model.add_observer(state[:observer])
        UI.start_timer(0.4,false) do
          begin
            library.place(data,ORIGIN,placement:descriptor(root))
            state[:checks] << 'Replacement committed on the raw component fixture'
            UI.start_timer(0.2,false) do
              Sketchup.undo
              UI.start_timer(0.25,false) { finish_undo(state) }
            end
          rescue StandardError=>error
            state[:error]=error.message;finish_undo(state)
          end
        end
        {scheduled:true,output:output}
      end

      def finish_undo(state)
        root=state[:root];model=state[:model]
        ok=!state[:error] && root.valid? && [geometry(root),root.name]==state[:before] && !root.attribute_dictionary(Reader::DICT,false)
        detail={valid:root.valid?,before:state[:before],after:root.valid? ? [geometry(root),root.name] : nil,mh_dictionary:root.valid? ? root.attribute_dictionary(Reader::DICT,false)&.keys : nil}
        state[:checks] << 'One native Undo restores original geometry, name and absence of MH metadata' if ok
        model.remove_observer(state[:observer])
        model.start_operation('MH QA062 Undo cleanup',true);root.erase! if root.valid?;model.commit_operation
        model.selection.clear;state[:selected].each { |entity| model.selection.add(entity) if entity.valid? }
        Assembly.watch(model).reset;ScaleRedraw.watch(model).reset
        File.write(state[:output],JSON.pretty_generate({ok:ok,checks:state[:checks],error:state[:error],detail:detail,events:state[:events]}))
      end

      def recovery_fixture(library,saved)
        directory=File.join(@base,'outputs/recovery-062');FileUtils.mkdir_p(directory)
        broken=File.join(directory,'stale.skp')
        @model.start_operation('MH QA062 stale geometry fixture',true)
        definition=@model.definitions.load(saved)
        root=@model.entities.add_instance(definition,Geom::Transformation.new)
        Runtime.private_tree(root)
        part=root.definition.entities.find { |entity| Assembly.container?(entity) && entity.get_attribute(Reader::DICT,'part_key') }
        mesh=part.definition.entities.to_a.select { |entity| entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge) }
        part.definition.entities.transform_entities(Geom::Transformation.scaling(1.1,1,1),mesh)
        part.definition.invalidate_bounds;root.definition.invalidate_bounds
        raise 'Cannot save stale fixture' unless root.definition.save_copy(broken)
        @model.abort_operation
        begin
          library.verify_file(broken)
          raise 'Stale serialized geometry was accepted'
        rescue Core::Error=>error
          check(error.message.include?('Hình học SKP'),'Strict serialized-file verification rejects inconsistent saved geometry')
        end
        own=Library.new;own.config['root']=directory;own.refresh
        data=own.preview('stale.skp')
        desired=descriptor(@owned.last);frame=Geom::Transformation.new(desired['frame'])
        fresh=own.place(data,ORIGIN,placement:desired);@owned << fresh
        rule=Core.rule!(JSON.parse(fresh.get_attribute(Reader::DICT,'rule_json')))
        values=JSON.parse(fresh.get_attribute(Reader::DICT,'parameter_values_json'))
        current,=Reader.live(fresh,label:fresh.name,parameter:Runtime.read_parameter(rule,values))
        check(Core.plan(rule,current,values)['changed_count'].zero? && Core.bounds_close?(world_bounds(fresh,frame),desired['bounds'],0.02),'A stale native geometry baseline is restored privately, fitted and remains editable')
      end
    end
  end
end
