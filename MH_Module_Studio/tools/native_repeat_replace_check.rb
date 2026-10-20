# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeRepeatReplaceCheck
      extend self
      def start
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @before=@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] };@defs=@model.definitions.to_a;@materials=@model.materials.to_a
        @selection=@model.selection.to_a;@camera=@model.active_view.camera;@links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY);@created=[];@tracked=[]
        @folder=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/replace-078');FileUtils.mkdir_p(@folder)
        @library=Library.new;@library.config['root']=File.join(File.dirname(@folder),'direct-links-077/library');@library.refresh;@data=@library.preview('drawer.skp')
        @report={'status'=>'running','checks'=>[]};@model.start_operation('MH QA Replace fixtures',true)
        @boxes=3.times.map { |i| box(120_000+i*1200) };@model.commit_operation;reset
        @model.selection.clear;@model.selection.add(@boxes)
        targets=LibraryPlacement.selected_targets(@model);@original=@boxes.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] }
        began=now;@results=LibraryPlacement.replace_many(@library,@data,targets);@report['batch_seconds']=now-began;@created+=@results;@ids=@results.map(&:persistent_id);@tracked+=@ids
        check(@results.length==3 && @model.selection.to_a.sort_by(&:persistent_id)==@results.sort_by(&:persistent_id),'Batch replaces every selected block and selects the resulting modules')
        @results.each { |root| verify(root) }
        check(Assembly.records(@model).none? { |row| @ids.map(&:to_s).include?(row.dig('b','root')) },'Replace does not activate saved import contacts')
        Sketchup.undo;reset
        @steps=[
          -> { check(@original.all? { |pid,low,high| r=@model.find_entity_by_persistent_id(pid);r && r.valid? && r.bounds.min.to_a==low && r.bounds.max.to_a==high && r.get_attribute('dynamic_attributes','qa')==true },'One Undo restores all original DC-like blocks and their attributes');Sketchup.send_action('editRedo:');reset },
          -> { @results=@ids.map { |pid| @model.find_entity_by_persistent_id(pid) };@created+=@results;@results.each { |root| verify(root) };failure;continuous },
          -> { check(@hud.active && @hud.pending && !@hud.error,'Ctrl replace leaves the same Library tool and sample active');@hud.onLButtonDown(0,*@next_pixel,@model.active_view);@tracked+=@model.selection.map(&:persistent_id);check(@hud.active && @hud.pending && !@hud.error && (@model.selection.first.bounds.min.x*25.4-128000).abs<0.02 && @model.selection.first.get_attribute(Reader::DICT,'trial',false),'Next plain click replaces again without reopening HUD');@hud.onKeyDown(27,1,0,@model.active_view);check(@hud.active && !@hud.pending,'First Esc returns to Library browsing');@hud.onKeyDown(27,1,0,@model.active_view);check(!@hud.active,'Second Esc exits Library');finish }
        ];later;puts 'scheduled'
      rescue StandardError=>error
        fail_check(error)
      end
      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      def box(offset)
        root=@model.entities.add_group;@created << root;@tracked << root.persistent_id
        root.entities.add_face([0,0,0],[600/25.4,0,0],[600/25.4,500/25.4,0],[0,500/25.4,0]).pushpull(150/25.4)
        root.transform!(Geom::Transformation.translation([offset/25.4,0,0]));root.name='QA block';root.set_attribute('dynamic_attributes','qa',true);root
      end
      def verify(root)
        size=Core.dimensions(Reader.live(root,label:'QA',parameter:nil).first['envelope'])
        check(size.zip([600,500,150]).all? { |a,b| (a-b).abs<0.02 },'Replacement retains actual target dimensions')
        check(root.get_attribute(Reader::DICT,'trial') && root.get_attribute(Reader::DICT,'root_pid')==root.persistent_id.to_s,'Replacement has usable own rules and the surviving instance identity')
      end
      def failure
        @model.start_operation('MH QA failure targets',true);@failed=[box(126_000),box(128_000)];@model.commit_operation;reset
        before=@failed.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] };definitions=@model.definitions.to_a
        original=@library.method(:build_instance);count=0
        @library.define_singleton_method(:build_instance) do |*args,**kwargs|
          count+=1;raise Core::Error,'QA second replacement rejected' if count==2
          original.call(*args,**kwargs)
        end
        begin
          LibraryPlacement.replace_many(@library,@data,@failed.map { |r| {'root'=>r.persistent_id.to_s} });raise 'Injected failure accepted'
        rescue Core::Error
          check(before.all? { |pid,low,high| r=@model.find_entity_by_persistent_id(pid);r && r.valid? && r.bounds.min.to_a==low && r.bounds.max.to_a==high } && @model.definitions.to_a==definitions,'Second-target failure rolls back all replacements and new definitions')
        ensure
          @library.define_singleton_method(:build_instance,original)
        end
        @failed=before.map { |pid,*_rest| @model.find_entity_by_persistent_id(pid) }
      end
      def continuous
        @model.selection.clear;@hud=LibraryHUD.new(@library,@data);@model.select_tool(@hud)
        first=@failed.first;other=@failed.last;center=first.bounds.center;eye=center+Geom::Vector3d.new(0,-2000/25.4,600/25.4)
        @model.active_view.camera=Sketchup::Camera.new(eye,center,Z_AXIS);@model.active_view.refresh
        p=@model.active_view.screen_coords(first.bounds.center);@hud.onLButtonDown(8,p.x,p.y,@model.active_view)
        @created+=@model.selection.to_a
        @tracked+=@model.selection.map(&:persistent_id)
        @model.active_view.camera=Sketchup::Camera.new(eye+Geom::Vector3d.new(2000/25.4,0,0),other.bounds.center,Z_AXIS);@model.active_view.refresh
        p=@model.active_view.screen_coords(other.bounds.center);@next_pixel=[p.x,p.y]
      end
      def reset
        ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      end
      def check(condition,label)
        raise label unless condition
        @report['checks'] << label
      end
      def later
        UI.start_timer(0.3,false) do
          begin;@steps.shift.call;later unless @steps.empty?;rescue StandardError=>error;fail_check(error);end
        end
      end
      def fail_check(error)
        @report||={};@report['error']=[error.message,*error.backtrace.first(7)];finish
      end
      def finish
        @hud&.finish
        @model.start_operation('MH QA Replace cleanup',true)
        @created.compact.uniq.each { |r| r.erase! if r.valid? }
        @tracked.uniq.each { |pid| r=@model.find_entity_by_persistent_id(pid);r.erase! if r && r.valid? }
        30.times { (@model.definitions.to_a-@defs).each { |d| @model.definitions.remove(d) if d.valid? && d.instances.empty? } }
        (@model.materials.to_a-@materials).each { |m| @model.materials.remove(m) if m.valid? }
        @links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        @model.selection.clear;@selection.each { |r| @model.selection.add(r) if r.valid? };@model.commit_operation;reset;@model.active_view.camera=@camera
        @report['model_retained']=@before==@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] } && @model.definitions.to_a==@defs
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        File.write(File.join(@folder,'native.json'),JSON.pretty_generate(@report))
      end
    end
  end
end
