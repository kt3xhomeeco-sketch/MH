# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeFreeFitDrawersCheck
      extend self
      def start
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @before=@model.entities.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] }
        @selection=@model.selection.to_a;@camera=@model.active_view.camera;@created=[];@tracked=[];@definitions=@model.definitions.to_a;@materials=@model.materials.to_a
        @links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY);@report={'checks'=>[]}
        @preferences=%w[library_v1 hud_catalog_v1].to_h { |key| [key,Sketchup.read_default('MH_Module_Studio',key,'')] }
        @folder=File.join(File.dirname(__dir__),'outputs/free-fit-080');FileUtils.mkdir_p(@folder)
        @library=Library.new;@library.config['root']='D:/Cong viec/Sketchup/DC/Modul_studio';@library.refresh
        @seed=@library.preview('Ngan keo/Ngan keo am 1 tang 250.skp')
        @seed['import_template']=ImportTemplate.defaults.merge('enabled'=>true,'mode'=>'inside')
        @ball=@library.preview('Ngan keo/Ngan keo 1 tang 250.skp')
        @model.start_operation('MH QA080 fixtures',true)
        @host=host(565,160_000)
        @scaled=host(565,163_000,extra:Geom::Transformation.rotation(ORIGIN,Z_AXIS,0.35)*Geom::Transformation.scaling(-1.1,1.2,1.3))
        @targets=[block(510,166_000),block(580,169_000)]
        @model.commit_operation;reset
        free_fit(@host,@seed,550);free_fit(@scaled,@seed,550);free_fit(@host,@ball,550)
        generic_fit
        linked_fit
        @model.selection.clear;@model.selection.add(@targets)
        @old=@targets.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] }
        @results=LibraryPlacement.replace_many(@library,@seed,LibraryPlacement.selected_targets(@model));@created+=@results;@tracked+=@results.map(&:persistent_id)
        [450,550].each_with_index do |size,index|
          root=@results[index];actual=Core.dimensions([root.bounds.min.to_a,root.bounds.max.to_a]).map { |v| v*25.4 }
          check(actual.zip([600,size,250]).all? { |a,b| (a-b).abs<0.02 },"Batch target #{index+1}: picks its own #{size} mm rail, fits width/height")
          check(root.get_attribute(Reader::DICT,'library_source_path').end_with?(" #{size}.skp"),'Result carries the selected variant source')
        end
        Sketchup.undo;reset
        UI.start_timer(0.3,false) do
          begin
            check(@old.all? { |pid,low,high| r=@model.find_entity_by_persistent_id(pid);r && r.valid? && r.bounds.min.to_a==low && r.bounds.max.to_a==high },'One Undo restores both replacement targets')
            reject_too_short
            finish
          rescue StandardError=>error
            fail_check(error)
          end
        end
        puts 'scheduled'
      rescue StandardError=>error
        fail_check(error)
      end
      def box(entities,low,high)
        root=entities.add_group
        a,b=low.map { |v| v/25.4 },high.map { |v| v/25.4 }
        face=root.entities.add_face([a[0],a[1],a[2]],[b[0],a[1],a[2]],[b[0],b[1],a[2]],[a[0],b[1],a[2]])
        face.reverse! if face.normal.z.negative?
        face.pushpull(b[2]-a[2]);root
      end
      def host(depth,offset,extra:Geom::Transformation.new)
        root=@model.entities.add_group;@created << root;@tracked << root.persistent_id
        root.name='QA080 cabinet'
        [[[0,0,0],[18,depth+18,286]],[[618,0,0],[636,depth+18,286]],[[18,0,0],[618,depth+18,18]],[[18,0,268],[618,depth+18,286]],[[18,depth,18],[618,depth+18,268]]].each { |low,high| box(root.entities,low,high) }
        root.transformation=Geom::Transformation.translation([offset/25.4,0,0])*extra;root
      end
      def block(depth,offset)
        root=box(@model.entities,[0,0,0],[600,depth,250]);@created << root;@tracked << root.persistent_id
        root.name='QA080 target';root.transformation=Geom::Transformation.translation([offset/25.4,0,0]);root
      end
      def aim(root)
        target=Geom::Point3d.new([318/25.4,565/25.4,143/25.4]).transform(root.transformation)
        eye=Geom::Point3d.new([318/25.4,-500/25.4,143/25.4]).transform(root.transformation)
        view=@model.active_view;view.camera=Sketchup::Camera.new(eye,target,Z_AXIS);view.refresh
        pixel=view.screen_coords(target);[view,pixel.x.to_i,pixel.y.to_i]
      end
      def free_fit(host,seed,size)
        hud=LibraryHUD.new(@library,seed);hud.update_placement(*aim(host),CONSTRAIN_MODIFIER_MASK)
        placement=hud.instance_variable_get(:@placement);data=hud.instance_variable_get(:@placement_data)
        raise(hud.instance_variable_get(:@placement_error) || 'No free Fit cavity') unless placement
        check(placement['mode']=='cavity' && !placement['matches'],'Shift detects a cavity and disables saved contacts')
        check(data.dig('drawer_fit','size')==size && seed['entry_id'].end_with?('250.skp'),'Hover selects variant without changing the chosen seed')
        root=@library.place(data,ORIGIN,placement:placement);@created << root;@tracked << root.persistent_id;reset
        matrix=host.transformation.inverse*root.transformation
        bounds=Frames.box(Frames.corners([root.definition.bounds.min.to_a,root.definition.bounds.max.to_a]).map { |p| Geom::Point3d.new(p).transform(matrix).to_a.map { |v| v*25.4 } })
        scale=Frames.scale_frame(host.transformation.to_a)[5]
        (@report['measurements']||=[]) << {'bounds'=>bounds,'placement'=>placement,'source'=>data['entry_id'],'expected'=>[[18,0,18],[618,size/scale,268]]}
        check(Core.bounds_close?(bounds,[[18,0,18],[618,size/scale,268]],0.02),'Actual drawer fits width/height, front aligns and preserves nominal rail depth under rotated/mirrored Scale')
        check(@links==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY),'Free Fit creates no link records')
        rule=JSON.parse(root.get_attribute(Reader::DICT,'rule_json'));values=JSON.parse(root.get_attribute(Reader::DICT,'parameter_values_json'))
        row=Parametric.variables(rule).find { |r| r['symbol']=='T1' }
        check((values.fetch(row['binding'],row['value'])-17.6).abs<0.001,'Real source T1 stays 17.6 mm')
        @model.start_operation('MH QA080 remove placed',true);root.erase!;@model.commit_operation;reset
      end
      def reject_too_short
        @model.start_operation('MH QA080 short target',true);short=block(200,172_000);@model.commit_operation;reset
        targets=[@model.find_entity_by_persistent_id(@old.first.first),short]
        before=targets.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] };definitions=@model.definitions.to_a
        begin
          LibraryPlacement.replace_many(@library,@seed,targets.map { |r| {'root'=>r.persistent_id.to_s} });raise 'Too-short rail accepted'
        rescue Core::Error=>error
          @report['short_error']=error.message
          check(before.all? { |pid,low,high| r=@model.find_entity_by_persistent_id(pid);r && r.valid? && r.bounds.min.to_a==low && r.bounds.max.to_a==high } && definitions==@model.definitions.to_a,'Second too-short target rolls back the entire batch and its definitions')
        end
      end
      def linked_fit
        hud=LibraryHUD.new(@library,@seed);hud.update_placement(*aim(@host),0)
        placement=hud.instance_variable_get(:@placement);data=hud.instance_variable_get(:@placement_data)
        raise(hud.instance_variable_get(:@placement_error) || 'No linked variant placement') unless placement
        check(data.dig('drawer_fit','size')==550 && placement['matches'].length==5,'Normal placement selects a ray variant and retains the five checked contacts')
        root=@library.place(data,ORIGIN,placement:placement);@created << root;@tracked << root.persistent_id;reset
        size=Core.dimensions([root.bounds.min.to_a,root.bounds.max.to_a]).map { |v| v*25.4 }
        check(size.zip([600,550,250]).all? { |a,b| (a-b).abs<0.02 },'Normal linked drawer keeps nominal depth and resizes only between opposing contacts')
        check(JSON.parse(root.get_attribute(Reader::DICT,'rule_json')).dig('import_template','enabled'),'Chosen variant retains the selected sample import intent')
        @model.start_operation('MH QA080 remove linked fixture',true);root.erase!
        @links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        @model.commit_operation;reset
        state=@model.entities.to_a;links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY);definitions=@model.definitions.to_a
        conflicting=Core.copy_data(@seed);conflicting['import_template']['faces'].each { |face| face['enabled']=true }
        bad=LibraryHUD.new(@library,conflicting);bad.update_placement(*aim(@host),0)
        raise(bad.instance_variable_get(:@placement_error) || 'No conflicting preview') unless bad.instance_variable_get(:@placement)
        begin
          unwanted=@library.place(bad.instance_variable_get(:@placement_data),ORIGIN,placement:bad.instance_variable_get(:@placement))
          @created << unwanted;@tracked << unwanted.persistent_id
          raise 'Incompatible opposing fixed-depth contacts accepted'
        rescue Core::Error
          check(state==@model.entities.to_a && links==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY) && definitions==@model.definitions.to_a,'Incompatible fixed-depth opposing links fail atomically without dropping contacts')
        end
      end
      def generic_fit
        library=Library.new;library.config['root']=File.join(File.dirname(@folder),'direct-links-077/library');library.refresh
        seed=library.preview('drawer.skp');hud=LibraryHUD.new(library,seed);hud.update_placement(*aim(@host),CONSTRAIN_MODIFIER_MASK)
        placement=hud.instance_variable_get(:@placement);raise 'No generic Fit cavity' unless placement
        root=library.place(hud.instance_variable_get(:@placement_data),ORIGIN,placement:placement);@created << root;@tracked << root.persistent_id;reset
        bounds=[root.bounds.min.to_a,root.bounds.max.to_a].map { |p| p.map { |v| v*25.4 } }
        check(Core.dimensions(bounds).zip([600,565,250]).all? { |a,b| (a-b).abs<0.02 } && !hud.instance_variable_get(:@placement_data)['drawer_fit'],'Ordinary modules fit all three cavity dimensions without rail policy')
        check(@links==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY),'Ordinary free Fit creates no links')
        @model.start_operation('MH QA080 remove generic Fit',true);root.erase!;@model.commit_operation;reset
      end
      def check(value,label)
        raise label unless value
        @report['checks'] << label
      end
      def reset
        ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      end
      def fail_check(error)
        @report||={'checks'=>[]};@report['error']=[error.message,*error.backtrace.first(8)];finish
      end
      def finish
        @model.start_operation('MH QA080 cleanup',true)
        @created.compact.uniq.each { |r| r.erase! if r.valid? }
        @tracked.uniq.each { |pid| r=@model.find_entity_by_persistent_id(pid);r.erase! if r && r.valid? }
        30.times { (@model.definitions.to_a-@definitions).each { |d| @model.definitions.remove(d) if d.valid? && d.instances.empty? } }
        (@model.materials.to_a-@materials).each { |m| @model.materials.remove(m) if m.valid? }
        @links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        @model.selection.clear;@selection.each { |r| @model.selection.add(r) if r.valid? };@model.commit_operation;reset;@model.active_view.camera=@camera
        @preferences.each { |key,value| Sketchup.write_default('MH_Module_Studio',key,value) }
        @report['model_retained']=@before==@model.entities.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] } && @definitions==@model.definitions.to_a && @links==@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        File.write(File.join(@folder,'native.json'),JSON.pretty_generate(@report));puts @report['status']
      end
    end
  end
end
