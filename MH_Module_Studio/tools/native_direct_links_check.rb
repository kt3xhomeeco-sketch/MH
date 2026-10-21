# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeDirectLinksCheck
      extend self
      class Dialog
        attr_reader :state
        def execute_script(script)
          encoded=script.delete_prefix('window.receive(JSON.parse(').delete_suffix('));');@state=JSON.parse(JSON.parse(encoded))
        end
        def set_size(*);end
      end
      def start
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @folder=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/direct-links-077');FileUtils.mkdir_p(File.join(@folder,'library'))
        File.delete(File.join(@folder,'capture-ready')) if File.exist?(File.join(@folder,'capture-ready'))
        @original=@model.entities.to_a;@defs=@model.definitions.to_a;@materials=@model.materials.to_a;@selection=@model.selection.to_a;@camera=@model.active_view.camera
        @before=@original.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] };@links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @created=[];@report={'status'=>'running','checks'=>[]}
        @model.start_operation('MH QA 077 fixtures',true)
        @host=load_fixture('D:/Cong viec/Sketchup/DC/Modul_studio/CC Khung bếp dưới.skp',100_000)
        @source=load_fixture('D:/Cong viec/Sketchup/DC/Modul_studio/Khung ngăn kéo.skp',104_000)
        Assembly.resize(@host,[0,1,0],600);Assembly.resize(@source,[0,0,1],150)
        template=ImportTemplate.defaults.merge('enabled'=>true)
        template['faces'].each { |f| f['enabled']=!(f['axis']==2 && f['side']==1);f['gap']=f['axis']==1 && f['side']==0 ? 80 : 0 }
        rule,values=AssemblyParameters.data(@source);rule=ImportTemplate.edit(rule,template)
        _snapshot,bindings=Reader.live(@source,label:@source.name,parameter:Runtime.read_parameter(rule,values));Runtime.stamp(@source,rule,bindings,values)
        set_t(@source,20)
        @model.commit_operation;reset
        @options=ModuleOptions.new;@options.instance_variable_set(:@dialog,Dialog.new);@options.define_singleton_method(:thumbnail) { |_root| nil }
        @model.selection.clear;@model.selection.add([@host,@source]);@options.refresh
        common=@options.instance_variable_get(:@display_rows).find { |r| r['id']=='common:T1' }
        check(common && common['mixed'] && common['targets'].length==2,'Unmerged multi-selection shows one mixed T1 row with two targets')
        @initial=[t(@host),t(@source)];request_t(22)
        @report['batch_values']=[t(@host),t(@source)]
        check([t(@host),t(@source)].all? { |value| (value-22).abs<0.00001 },'One common T1 edit updates both real modules')
        Sketchup.undo;reset
        @steps=[
          -> { check([t(@host),t(@source)]==@initial,'One Undo restores both modules after the batch edit');Sketchup.send_action('editRedo:');reset },
          -> { check([t(@host),t(@source)].all? { |value| (value-22).abs<0.00001 },'Redo restores both selected modules');batch_failure;prepare_library;place_modes;open_contacts },
          -> { @model.active_view.refresh;File.write(File.join(@folder,'capture-ready'),Process.pid.to_s);@capture_pause=8 },
          -> { inspect_dimensions },
          -> { settings },
          -> { close_settings },
          -> { check(@tool.hud && @hud.visible?,'Closing settings leaves direct dimensions active');@model.select_tool(nil) },
          -> { check(!@tool.active && !AssemblyHUDInput.active?,'Native Select/Move/Scale retain pointer priority without the old HUD mouse hook');finish }
        ];later
        puts 'scheduled'
      rescue StandardError=>error
        fail_check(error)
      end
      def load_fixture(path,offset)
        target=File.join(@folder,'input-'+Core::Ids.hex(4)+'.skp');FileUtils.cp(path,target)
        definition=@model.definitions.load(target);root=@model.entities.add_instance(definition,Geom::Transformation.new);@created << root
        data=LibraryCatalog.payload(definition.get_attribute(Reader::DICT,LibraryCatalog::PAYLOAD_KEY));root.name=data['name'];Runtime.private_tree(root)
        _snapshot,bindings,plan=Library.new.validate_geometry(root,data,recover:true)
        Runtime.apply_plan(bindings,plan);Runtime.stamp(root,data['rule'],bindings,plan['target']);Runtime.verify_result(root,plan)
        root.transformation=Geom::Transformation.translation([offset/25.4,0,0]);root
      end
      def t(root)
        rule,values=AssemblyParameters.data(root);own=Parametric.with_values(rule,values);row=Parametric.variables(own).find { |r| r['symbol'].casecmp?('T1') };Parametric.evaluate_variables(own).fetch(row['id'])
      end
      def set_t(root,value)
        rule,values=AssemblyParameters.data(root);rows=Parametric.variables(Parametric.with_values(rule,values));rows.find { |r| r['symbol']=='T1' }['value']=value
        rule=Parametric.edit_variables(rule,rows);Runtime.apply_trial_update(root,rule,Parametric.targets(rule))
      end
      def request_t(value)
        @options.refresh;state=@options.instance_variable_get(:@dialog).state
        @options.request('action'=>'change','root_pid'=>state['root_pid'],'token'=>state['token'],'variable_id'=>'common:T1','value'=>value)
      end
      def batch_failure
        before=[geometry(@host),geometry(@source)];original=Runtime.method(:apply_trial_update)
        failure=@source
        Runtime.define_singleton_method(:apply_trial_update) do |root,*args,**kwargs|
          raise Core::Error,'QA second module rejected' if root==failure
          original.call(root,*args,**kwargs)
        end
        begin
          request_t(24);raise 'Batch failure was accepted'
        rescue Core::Error
          check(before==[geometry(@host),geometry(@source)],'A failure on the second module rolls back the entire shared edit')
        ensure
          Runtime.define_singleton_method(:apply_trial_update,original)
        end
        @options.refresh
      end
      def geometry(root)
        snapshot,_=Reader.live(root,label:'QA',parameter:nil)
        [root.transformation.to_a,snapshot['parts'].map { |p| p.slice('key','bounds','visible') },root.get_attribute(Reader::DICT,'rule_json'),root.get_attribute(Reader::DICT,'parameter_values_json')]
      end
      def prepare_library
        @library=Library.new;@library.config['root']=File.join(@folder,'library');@library.export(@source,File.join(@folder,'library','drawer.skp'));@library.refresh
        @data=@library.preview('drawer.skp')
      end
      def aim
        bounds=AssemblyEnvelope.bounds(@host);point=[(bounds[0][0]+bounds[1][0])/2,bounds[1][1]-30,(bounds[0][2]+bounds[1][2])/2]
        frame=@host.transformation;target=Geom::Point3d.new(point.map { |v| v/25.4 }).transform(frame);eye=Geom::Point3d.new([point[0]+300,-900,point[2]+150].map { |v| v/25.4 }).transform(frame)
        view=@model.active_view;view.camera=Sketchup::Camera.new(eye,target,Z_AXIS);view.refresh;pixel=view.screen_coords(target)
        [view,pixel.x.to_i,pixel.y.to_i]
      end
      def place_modes
        args=aim;hud=LibraryHUD.new(@library,@data)
        hud.update_placement(*args,4);check(hud.instance_variable_get(:@placement).nil?,'Shift at placement disables all automatic links and cavity sizing')
        before=Core.dimensions(@data['snapshot']['envelope']);@free=@library.place(@data,Geom::Point3d.new(106_000/25.4,0,0),placement:nil);@created << @free
        measured=Core.dimensions(Reader.live(@free,label:'QA free',parameter:nil).first['envelope'])
        check(before.zip(measured).all? { |a,b| (a-b).abs<0.02 },'Free placement preserves all original physical dimensions')
        check(Assembly.records(@model).none? { |r| r.dig('b','root')==@free.persistent_id.to_s },'Free placement does not create host contacts')
        hud.update_placement(*args,0);placement=hud.instance_variable_get(:@placement);raise 'No linked placement' unless placement
        check(placement['matches'].none? { |m| m['slot']==[2,1] },'Unchecked top is not added as a hidden contact')
        @placed=ImportLinks.place(@library,@data,placement);@created << @placed;reset
        size=Core.dimensions(Reader.live(@placed,label:'QA linked',parameter:nil).first['envelope'])
        check((size[2]-before[2]).abs<0.02,'One bottom contact preserves source height instead of filling the top')
        front=Assembly.records(@model).find { |r| r.dig('b','root')==@placed.persistent_id.to_s && r.dig('import_link','slot')==[1,0] }
        check(front.dig('import_link','boundary')=='envelope','Upper front brace is not mistaken for the front datum')
        check((front_distance-80).abs<0.02,'Real front offset is 80 mm from the host envelope')
        none=Core.copy_data(@data);none['import_template']['enabled']=false;hud.instance_variable_set(:@pending,none);hud.update_placement(*args,0)
        check(hud.instance_variable_get(:@placement).nil?,'A sample without linking properties keeps original-size placement')
      end
      def front_distance
        host=Assembly.world_plane(@model,{'root'=>@host.persistent_id.to_s,'axis'=>1,'side'=>0})
        child=Assembly.world_plane(@model,{'root'=>@placed.persistent_id.to_s,'axis'=>1,'side'=>0})
        -AssemblyMath.dot(AssemblyMath.sub(child['point'],host['point']),host['normal'])
      end
      def open_contacts
        @options.instance_variable_set(:@dialog,nil);@options.detach
        @model.selection.clear;@model.selection.add(@placed);MH::ModuleStudio.open_assembly
        @tool=MH::ModuleStudio.instance_variable_get(:@assembly_tool);@hud=@tool.hud;@model.active_view.invalidate
      end
      def inspect_dimensions
        check(@hud.inspector.instance_variable_get(:@dialog).nil?,'Old inspector and tree do not open automatically')
        check(!@hud.contacts.last_error && @hud.contacts.items.length==5,'Native overlay draws five contact dimensions')
        item=@hud.contacts.items.find { |r| r['record'].dig('import_link','slot')==[1,0] }
        check(item && item['volume'],'Nonzero front clearance is displayed as a 3D contact box')
        child_size=Core.dimensions(Reader.live(@placed,label:'QA area',parameter:nil).first['envelope'])
        check((item['area']-child_size[0]*child_size[2]).abs<0.1,'Contact box uses the smaller front face dimensions')
        @report['item']=item.slice('id','rect','area','volume')
        original=UI.method(:inputbox);messages=UI.method(:messagebox);errors=[]
        UI.define_singleton_method(:inputbox) { |*_args| ['90'] };UI.define_singleton_method(:messagebox) { |message| errors << message;1 }
        begin
          rect=item['rect'];@tool.onLButtonDown(0,(rect[0]+rect[2])/2,(rect[1]+rect[3])/2,@model.active_view)
          check(errors.empty? && (front_distance-90).abs<0.02,'Clicking the dimension edits actual contact distance to 90 mm')
        ensure
          UI.define_singleton_method(:inputbox,original);UI.define_singleton_method(:messagebox,messages)
        end
      end
      def settings
        @model.active_view.write_image(filename:File.join(@folder,'contacts.png'),width:1200,height:900,antialias:true)
        item=@hud.contacts.items.find { |r| r['record'].dig('import_link','slot')==[1,0] }
        center=item['ends'].transpose.map { |values| values.sum/values.length }
        point=@model.active_view.screen_coords(Geom::Point3d.new(center.map { |v| v/25.4 }))
        hit=@hud.contacts.hit(point.x,point.y);check(hit && hit[0]=='settings','Click inside the box selects advanced settings rather than a dimension')
        @tool.onLButtonDown(0,point.x,point.y,@model.active_view)
      end
      def close_settings
        dialog=@hud.inspector.instance_variable_get(:@dialog);check(dialog && dialog.visible?,'Box click opens advanced link settings on demand')
        dialog.close
      end
      def reset
        ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      end
      def check(condition,label)
        raise label unless condition
        @report['checks'] << label
      end
      def later
        delay=@capture_pause || 0.3;@capture_pause=nil
        UI.start_timer(delay,false) do
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
        @hud&.close;@options&.instance_variable_set(:@dialog,nil);@options&.detach
        @model.start_operation('MH QA 077 cleanup',true)
        @created.each { |root| root.erase! if root.valid? }
        30.times { (@model.definitions.to_a-@defs).each { |d| @model.definitions.remove(d) if d.valid? && d.instances.empty? } }
        (@model.materials.to_a-@materials).each { |m| @model.materials.remove(m) if m.valid? }
        @links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        @model.selection.clear;@selection.each { |e| @model.selection.add(e) if e.valid? };@model.commit_operation;reset;@model.active_view.camera=@camera
        @report['model_retained']=@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }==@before && @model.definitions.to_a==@defs && @model.materials.to_a==@materials
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        File.write(File.join(@folder,'native.json'),JSON.pretty_generate(@report))
      end
    end
  end
end
