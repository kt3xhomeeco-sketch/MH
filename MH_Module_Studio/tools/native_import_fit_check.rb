# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeImportFitCheck
      extend self
      class Preview < Sketchup::Overlay
        attr_reader :draw_count,:last_error
        def initialize(placement)
          super('mh.module_studio.qa076','MH Import Fit QA');@placement=placement;@draw_count=0
        end
        def draw(view)
          @draw_count+=1;ImportLinks.draw(view,@placement)
        rescue StandardError=>error
          @last_error=error.message
        end
      end
      class Dialog
        attr_reader :state
        def execute_script(script)
          encoded=script.delete_prefix('window.receiveAssembly(JSON.parse(').delete_suffix('));')
          @state=JSON.parse(JSON.parse(encoded))
        end
      end
      def start(host_pid:,source_pid:)
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @original_host=@model.find_entity_by_persistent_id(host_pid);@original_source=@model.find_entity_by_persistent_id(source_pid)
        raise 'Missing real cabinet/drawer sources' unless @original_host && @original_source
        @roots=@model.entities.to_a;@defs=@model.definitions.to_a;@materials=@model.materials.to_a;@selection=@model.selection.to_a;@camera=@model.active_view.camera
        @before=@roots.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
        @source_before=[geometry(@original_host),geometry(@original_source)]
        @links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @folder=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/import-076');FileUtils.mkdir_p(File.join(@folder,'library'))
        @report={'status'=>'running','model'=>@model.title,'checks'=>[],'placements'=>[]}
        @model.start_operation('MH QA 076 source copy',true)
        @source=clone(@original_source,105_000)
        rule,values=AssemblyParameters.data(@source);template=ImportTemplate.defaults.merge('enabled'=>true)
        template['faces'].each { |f| f['enabled']=true;f['gap']=(f['axis']==1 && f['side']==0 || f['axis']==2 && f['side']==1) ? 80.0 : 0.0 }
        rule=ImportTemplate.edit(rule,template)
        _snap,bindings=Reader.live(@source,label:@source.name,parameter:Runtime.read_parameter(rule,values));Runtime.stamp(@source,rule,bindings,values)
        @model.commit_operation;reset
        @library=Library.new;@library.config['root']=File.join(@folder,'library')
        @library.export(@source,File.join(@folder,'library','drawer.skp'));@library.refresh;@data=@library.preview('drawer.skp')
        @steps=[
          -> { prepare_host('scaled');place_and_verify('scaled');@placed_pid=@child.persistent_id;Sketchup.undo;reset },
          -> { check(!@model.find_entity_by_persistent_id(@placed_pid),'One Undo removes the import');check(Assembly.records(@model).none? { |r| r.dig('b','root')==@placed_pid.to_s },'One Undo removes real and envelope contacts');Sketchup.send_action('editRedo:');reset },
          -> { @child=@model.find_entity_by_persistent_id(@placed_pid);verify('Redo');edit_clearance;edit_host(20);verify('Host T=20');edit_host(17.6);verify('Host T=17.6');roundtrip },
          -> { prepare_host('rotated_mirror');place_and_verify('rotated_mirror') },
          -> { prepare_host('unit');place_and_verify('unit');reject_impossible;finish }
        ];later
        puts 'scheduled'
      rescue StandardError=>error
        fail_check(error)
      end
      def clone(source,offset,extra:Geom::Transformation.new)
        root=@model.entities.add_instance(source.definition,Geom::Transformation.translation([offset/25.4,0,0])*extra*source.transformation)
        source.attribute_dictionaries&.each { |dict| dict.each_pair { |key,value| root.set_attribute(dict.name,key,value) } }
        root.name=source.name;Runtime.private_tree(root);ScaleRedraw.apply(@model,[ScaleRedraw.prepare(root)]);root
      end
      def prepare_host(kind)
        @scope=nil;@model.start_operation('MH QA 076 host '+kind,true)
        extra=kind=='rotated_mirror' ? Geom::Transformation.rotation(ORIGIN,Z_AXIS,0.4)*Geom::Transformation.scaling(-1,1,1) : Geom::Transformation.new
        @host=clone(@original_host,kind=='scaled' ? 100_000 : kind=='unit' ? 120_000 : 110_000,extra:extra)
        if kind=='unit'
          scale=Geom::Transformation.new(Frames.scale_frame(@host.transformation.to_a))
          @host.definition.entities.transform_entities(scale,@host.definition.entities.to_a);@host.transformation*=scale.inverse
          ScaleRedraw.apply(@model,[ScaleRedraw.prepare(@host)])
        end
        @model.commit_operation;reset
      end
      def aim
        envelope=AssemblyEnvelope.bounds(@host);_faces,boxes=ImportLinks.face_geometry(@host,{'root'=>@host.persistent_id.to_s})
        seed=3.times.map { |axis| (envelope[0][axis]+envelope[1][axis])/2 };region=PlacementMath.cavity(envelope,boxes,seed,minimum_hits:1)
        raise 'Real cabinet has no central cavity' unless region
        point=3.times.map { |axis| (region[0][axis]+region[1][axis])/2 };point[1]=region[1][1]
        eye=point.dup;eye[1]=envelope[0][1]-500
        frame=@host.transformation;target=Geom::Point3d.new(point.map { |v| v/25.4 }).transform(frame);camera=Geom::Point3d.new(eye.map { |v| v/25.4 }).transform(frame)
        view=@model.active_view;view.camera=Sketchup::Camera.new(camera,target,Z_AXIS);view.refresh;pixel=view.screen_coords(target)
        [view,pixel.x.to_i,pixel.y.to_i]
      end
      def place_and_verify(label)
        @placement=ImportLinks.detect(@data,*aim,cache:{})
        raise 'No actual import preview' unless @placement
        check(@placement['matches'].length==6,label+' has all six configured references')
        virtual=@placement['matches'].select { |r| r['target']['virtual'] }
        check(virtual.length==1 && virtual.first['slot']==[1,0],label+' front uses host envelope; other faces remain real')
        overlay=Preview.new(@placement);@model.overlays.add(overlay);overlay.enabled=true;@model.active_view.invalidate;@model.active_view.refresh
        check(overlay.draw_count.positive? && !overlay.last_error,label+' draws real faces and virtual boundary without native errors')
        @model.overlays.remove(overlay)
        @child=ImportLinks.place(@library,@data,@placement);reset;verify(label,preview:true)
      end
      def measured
        inverse=@host.transformation.inverse
        Frames.box(8.times.map { |i| @child.definition.bounds.corner(i).transform(inverse*@child.transformation).to_a.map { |v| v*25.4 } })
      end
      def verify(label,preview:false)
        box=measured;scales=Frames.scale_frame(@host.transformation.to_a).values_at(0,5,10)
        scope=@scope&.persistent_id&.to_s;ref={'root'=>@host.persistent_id.to_s,'scope'=>scope}.compact
        _faces,panels=ImportLinks.face_geometry(@host,ref);envelope=AssemblyEnvelope.bounds(@host)
        seed=3.times.map { |axis| (envelope[0][axis]+envelope[1][axis])/2 };region=PlacementMath.cavity(envelope,panels,seed,minimum_hits:1)
        front=(box[0][1]-envelope[0][1])*scales[1];top=(region[1][2]-box[1][2])*scales[2]
        check((front-80).abs<0.02 && (top-80).abs<0.02,label+' retains front/top 80 real mm')
        check(Core.bounds_close?(box,@placement['bounds'],0.02),label+' actual bounds match the preview') if preview
        rows=Assembly.records(@model).select { |r| r.dig('b','root')==@child.persistent_id.to_s && r.dig('b','scope')==scope }
        check(rows.length==6,label+' has six persisted contacts');rows.each { |r| Assembly.verify(@model,r) }
        top_panel=Reader.live(@child,label:'QA thickness',parameter:nil).first['parts'].find { |p| p['name']=='đình' }
        check((Core.dimensions(top_panel['bounds'])[2]-17.6).abs<0.02,label+' preserves physical drawer thickness') unless @scope
        @report['placements'] << {label:label,front:front,top:top,size:Core.dimensions(box).each_with_index.map { |v,i| v*scales[i] }}
      end
      def edit_host(value)
        rule,values=AssemblyParameters.data(@host);rows=Parametric.variables(Parametric.with_values(rule,values));row=rows.find { |r| r['symbol']=='T1' };raise 'No T1' unless row
        row['value']=value;rule=Parametric.edit_variables(rule,rows)
        anchor={'root'=>@host.persistent_id.to_s,'scope'=>@scope&.persistent_id&.to_s}.compact
        Assembly.transact(@model,Assembly.records(@model),updates:[[anchor,rule,Parametric.targets(rule)]]);reset
      end
      def edit_clearance
        row=Assembly.records(@model).find { |r| r.dig('b','root')==@child.persistent_id.to_s && r.dig('import_link','boundary')=='envelope' }
        tool=AssemblyTool.new;tool.define_singleton_method(:refresh) {};tool.load_record(row)
        tool.action(:value,['gap',90]);check(!tool.error && tool.record['gap']==-90,'HUD positive 90 mm input updates the inward contact')
        scale=Frames.scale_frame(@host.transformation.to_a)[5]
        check(((measured[0][1]-AssemblyEnvelope.bounds(@host)[0][1])*scale-90).abs<0.02,'HUD edit produces 90 real mm on geometry')
        dialog=Dialog.new;inspector=AssemblyInspector.new(tool);inspector.instance_variable_set(:@dialog,dialog);inspector.publish
        check(dialog.state['gap']==90,'Inspector displays positive clearance for the envelope reference')
        tool.action(:step,['gap',1]);check(!tool.error && tool.record['gap']==-91,'HUD plus step increases the inward clearance')
        tool.onUserText('80',nil);check(!tool.error && tool.record['gap']==-80,'Measurements input restores positive 80 mm clearance');reset
      end
      def roundtrip
        host_key=AssemblyContainers.member_key(@host);child_key=AssemblyContainers.member_key(@child)
        row=Assembly.records(@model).find { |r| r.dig('b','root')==@child.persistent_id.to_s }
        Assembly.group(@model,row);@scope=@model.selection.first;reset
        path=File.join(@folder,'group.skp');AssemblyFile.save(@scope,path);data=ModuleFile.read(path)
        check(data['links'].count { |r| r.dig('import_link','boundary')=='envelope' }==1,'SKP assembly retains the explicit front envelope anchor')
        @model.start_operation('MH QA 076 reopen',true)
        definition=@model.definitions.load(path);copy=@model.entities.add_instance(definition,Geom::Transformation.translation([130_000/25.4,0,0]));AssemblyFile.restore(copy,data);@model.commit_operation;reset
        @scope=copy;members=AssemblyContainers.members(copy);@host=members.find { |r| r.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==host_key };@child=members.find { |r| r.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==child_key }
        verify('SKP reopen');edit_host(20);verify('SKP reopen host T=20')
      end
      def reject_impossible
        data=Core.copy_data(@data);before=@model.entities.to_a;links=JSON.generate(Assembly.records(@model))
        data['import_template']['faces'].find { |f| f['axis']==1 && f['side']==0 }['gap']=1000
        begin
          ImportLinks.detect(data,*aim,cache:{})
          raise 'Nonpositive cavity interval was accepted'
        rescue Core::Error
          check(before==@model.entities.to_a && links==JSON.generate(Assembly.records(@model)),'Impossible gaps fail without geometry or link changes')
        end
        # The drawer's fixed 50 mm columns cannot fit in a 70 mm overall width.
        # A positive preview box must still preserve those original ATT rules.
        small=Core.copy_data(@placement);width=70.0
        small['bounds'][0][0]=small['bounds'][1][0]-width
        left=small['matches'].find { |r| r['slot']==[0,0] }
        left['gap']=small['bounds'][0][0]-left['target']['coordinate']
        state=geometry(@child);definitions=@model.definitions.to_a
        begin
          ImportLinks.place(@library,@data,small)
          raise 'Fixed-column ATT was silently overridden'
        rescue Core::Error=>error
          @report['fixed_att_rejection']=error.message
          check(before==@model.entities.to_a && definitions==@model.definitions.to_a && links==JSON.generate(Assembly.records(@model)) && state==geometry(@child),'Fixed ATT rejection rolls back the full import and all contacts')
        end
      end
      def geometry(root)
        snapshot,_=Reader.live(root,label:'QA unchanged source',parameter:nil)
        [root.transformation.to_a,snapshot['parts'].map { |p| p.slice('key','bounds','visible') },root.get_attribute(Reader::DICT,'rule_json'),root.get_attribute(Reader::DICT,'parameter_values_json')]
      end
      def reset
        ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      end
      def check(condition,label)
        raise label unless condition
        @report['checks'] << label
      end
      def later
        UI.start_timer(0.25,false) do
          begin
            @steps.shift.call;later unless @steps.empty?
          rescue StandardError=>error
            fail_check(error)
          end
        end
      end
      def fail_check(error)
        @report||={'checks'=>[]};@report['error']=[error.message,*error.backtrace.first(7)];finish
      end
      def finish
        @model.start_operation('MH QA 076 cleanup',true)
        (@model.entities.to_a-@roots).each { |e| e.erase! if e.valid? }
        30.times { (@model.definitions.to_a-@defs).each { |d| @model.definitions.remove(d) if d.valid? && d.instances.empty? } }
        (@model.materials.to_a-@materials).each { |m| @model.materials.remove(m) if m.valid? }
        @links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        @model.selection.clear;@selection.each { |e| @model.selection.add(e) if e.valid? };@model.commit_operation;reset;@model.active_view.camera=@camera
        retained=@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }==@before && @model.definitions.to_a==@defs && @model.materials.to_a==@materials && @source_before==[geometry(@original_host),geometry(@original_source)]
        @report['model_retained']=retained;@report['status']=@report['error'] || !retained ? 'failed' : 'passed'
        File.write(File.join(@folder,'native.json'),JSON.pretty_generate(@report))
      end
    end
  end
end
