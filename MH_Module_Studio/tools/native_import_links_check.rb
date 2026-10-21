module MH::ModuleStudio
  module NativeImportLinksCheck
    extend self
    class Preview < Sketchup::Overlay
      attr_reader :draw_count,:last_error
      def initialize(placement)
        super('mh.module-studio.qa072','MH Import Links QA')
        @placement=placement;@draw_count=0
      end
      def draw(view)
        @draw_count+=1
        ImportLinks.draw(view,@placement)
      rescue StandardError=>error
        @last_error=error.message
      end
    end
    def start
      @base=File.dirname(Panel.instance_method(:show).source_location.first)
      %w[import_template placement_math rule_system assembly_parameters import_links assembly_containers assembly_file assembly library_import library_placement library_hud main].each { |name| load File.join(@base,name+'.rb') }
      require File.join(@base,'test/formula_fixtures')
      @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
      @group=nil;@door_root=nil;@body_root=nil
      @roots=@model.entities.to_a;@defs=@model.definitions.to_a;@selection=@model.selection.to_a
      @before=@roots.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }
      @links=AssemblyContainers.read(@model);@camera=@model.active_view.camera
      @report={'status'=>'running','checks'=>[]};@folder=File.join(@base,'outputs/import-072');FileUtils.mkdir_p(@folder)
      @library_folder=File.join(@folder,'library');FileUtils.mkdir_p(@library_folder)
      @model.start_operation('MH QA 072 setup',true)
      snapshot=host_snapshot
      @host_rule=ThicknessSymbols.normalize(RuleSystem.build(snapshot,Core.learn_module([snapshot])))
      @host=build(snapshot,@host_rule,100_000)
      @body_snapshot=box_snapshot('body',[350,100,350]);@body_rule=StaticGeometry.build(@body_snapshot)
      @body_rule=ImportTemplate.edit(@body_rule,ImportTemplate.defaults.merge('enabled'=>true))
      @body_source=build(@body_snapshot,@body_rule,103_000)
      @door_snapshot=box_snapshot('door',[400,18.6,400]);@door_rule=ThicknessSymbols.normalize(RuleSystem.build(@door_snapshot))
      @door_rule=ImportTemplate.edit(@door_rule,ImportTemplate.defaults.merge('enabled'=>true,'role'=>'door'))
      @door_source=build(@door_snapshot,@door_rule,105_000)
      partial=Core.copy_data(snapshot);partial['parts']=snapshot['parts'].select { |part| %w[left bottom].include?(part['key']) };partial['dc_inputs']={};partial.delete('dc_graph');partial['envelope']=Core.union(partial['parts'])
      @partial=build(partial,StaticGeometry.build(partial),107_000)
      @model.commit_operation;reset
      @library=Library.new;@library.config['root']=@library_folder
      @steps=[
        -> { @library.export(@body_source,File.join(@library_folder,'body.skp'));@library.export(@door_source,File.join(@library_folder,'door.skp'));@library.refresh;@body=@library.preview('body.skp');@door=@library.preview('door.skp');check(@door['import_template']['role']=='door','Door role comes from SKP metadata, independent of names/folders') },
        -> { hover_inside },
        -> { capture_preview },
        -> { place_body },
        -> { delete_body },
        -> { hover_partial },
        -> { hover_and_place_door },
        -> { verify_door(18.6);@report['checks'] << 'Opposed import reserves T + 1, preserving combined extent' },
        -> { @door_pid=@door_root.persistent_id;Sketchup.undo;reset },
        -> { check(!@door_root.valid? && Assembly.records(@model).empty?,'One Undo removes import and all automatic contacts');check((Core.dimensions(AssemblyEnvelope.bounds(@host))[1]-200).abs<0.02,'Undo restores original host depth');Sketchup.send_action('editRedo:');reset },
        -> { @door_root=@model.find_entity_by_persistent_id(@door_pid);verify_door(18.6);check(@door_root && @door_root.valid?,'Redo restores import, contacts and reservation') },
        -> { test_clearance },
        -> { test_delete_restore },
        -> { test_two_doors },
        -> { test_door_thickness },
        -> { group_door },
        -> { edit_master(20);verify_door(20);check(thickness(@door_root)==20,'Grouped master T1 propagates to child T1') },
        -> { edit_master(17.6);verify_door(17.6);edit_master(20);verify_door(20);@report['checks'] << 'Repeated T changes do not subtract door reserve cumulatively' },
        -> { save_group },
        -> { regroup },
        -> { test_inset },
        -> { nested_setup },
        -> { nested_verify(18);nested_change(20,observer:true) },
        -> { nested_verify(20);nested_change(17.6,observer:true) },
        -> { nested_verify(17.6);nested_group },
        -> { nested_verify(17.6);nested_change(40) },
        -> { nested_verify(40);nested_change(18.6) },
        -> { nested_verify(18.6);nested_scale },
        -> { nested_verify(18.6);nested_reopen },
        -> { nested_verify(18.6);nested_change(20) },
        -> { nested_verify(20);nested_change(17.6) },
        -> { nested_verify(17.6);nested_change(20) },
        -> { nested_verify(20);@report['checks'] << 'Inset child tracks host thickness and size before/after Group, Scale and SKP reopen' },
        -> { finish }
      ]
      later
      puts JSON.generate(scheduled:true,pid:Process.pid)
    rescue StandardError=>error
      @model.abort_operation if @model
      fail_check(error)
    end
    def box_snapshot(name,size)
      part={'key'=>name,'name'=>name,'bounds'=>[[0,0,0],size],'box_verified'=>true,'visible'=>true,'thickness_axis'=>Core.thickness_axis([[0,0,0],size]),'face_count'=>6,'edge_count'=>12,'dc_attributes'=>{}}
      Core.snapshot!({'id'=>Core::Ids.uuid,'label'=>name,'source'=>{'kind'=>'native-qa'},'parameter'=>size.min,'parts'=>[part],'envelope'=>part['bounds'],'dc_inputs'=>{}})
    end
    def host_snapshot
      data=FormulaFixtures.snapshot
      data['dc_graph']['nodes'].each do |node|
        next unless %w[left right].include?(node['part_key'])
        node['attributes']['_leny_formula']='parent!leny'
        node['attributes']['_lenz_formula']='parent!lenz'
      end
      data
    end
    def build(snapshot,rule,x)
      values=Parametric.targets(rule);plan=Core.plan(rule,snapshot,values)
      definition=@model.definitions.add('MH QA 072 '+snapshot['label'])
      Runtime.populate_parts(definition,plan)
      root=@model.entities.add_instance(definition,Geom::Transformation.translation([x/25.4,0,0]))
      root.set_attribute(Reader::DICT,'parameter_values_json',JSON.generate(values))
      _current,bindings=Reader.live(root,label:snapshot['label'],parameter:Runtime.read_parameter(rule,values))
      Runtime.stamp(root,rule,bindings,values);root.set_attribute(Reader::DICT,'generated',true)
      root
    end
    def check(condition,label)
      raise label unless condition
      @report['checks'] << label
    end
    def reset
      ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
    end
    def aim(root,point,eye:[300,-1000,350])
      frame=root.transformation
      target=Geom::Point3d.new(point.map { |value| value/25.4 }).transform(frame)
      camera=Geom::Point3d.new(eye.map { |value| value/25.4 }).transform(frame)
      view=@model.active_view;view.camera=Sketchup::Camera.new(camera,target,Z_AXIS);view.refresh
      pixel=view.screen_coords(target)
      [view,pixel.x.to_i,pixel.y.to_i]
    end
    def hover_inside
      args=aim(@host,[300,174,250])
      snapshot=Reader.live(@host,label:'before hover',parameter:18).first
      @inside=ImportLinks.detect(@body,*args,cache:{})
      unless @inside
        captured=ImportLinks.capture(*args,{})
        helper=args[0].pick_helper;helper.do_pick(args[1],args[2])
        @report['hover_debug']={'picked'=>helper.count,'paths'=>helper.count.times.map { |i| helper.path_at(i).map { |entity| entity.respond_to?(:name) ? entity.name : entity.typename } },'capture'=>captured}
      end
      raise 'No inside placement' unless @inside
      check(@inside['kind']=='inside' && @inside['matches'].length==5,'Native hover finds five real inner faces')
      check(@inside['matches'].all? { |match| match['target']['anchor']['root']==@host.persistent_id.to_s },'Highlights reference only the host, never the imported module')
      after=Reader.live(@host,label:'after hover',parameter:18).first
      check(snapshot['parts'].map { |part| part['bounds'] }==after['parts'].map { |part| part['bounds'] },'Hover is read-only')
      one=Core.copy_data(@body);one['import_template']['faces'].each { |slot| slot['enabled']=slot['axis']==0 && slot['side']==0 }
      check(ImportLinks.detect(one,*args,cache:{})['matches'].length==1,'One configured face is accepted')
      @overlay=Preview.new(@inside);@model.overlays.add(@overlay);@overlay.enabled=true;args[0].invalidate
    end
    def capture_preview
      view=@model.active_view;view.refresh
      check(@overlay.draw_count>0 && !@overlay.last_error,"Native highlight draw executes without error (#{@overlay.last_error})")
      check(view.write_image(filename:File.join(@folder,'host-highlight.png'),width:1200,height:900,antialias:true),'Native host-only highlight image captured')
      @model.overlays.remove(@overlay);@overlay=nil
    end
    def place_body
      @body_root=ImportLinks.place(@library,@body,@inside)
      rows=Assembly.records(@model).select { |row| row.dig('b','root')==@body_root.persistent_id.to_s }
      check(rows.length==5,'Place commits exactly the five highlighted contacts')
      rows.each { |row| Assembly.verify(@model,row) }
      @model.start_operation('MH QA host T',true)
      rule=Core.rule!(JSON.parse(@host.get_attribute(Reader::DICT,'rule_json')))
      rows=Parametric.variables(rule);rows.find { |row| row['symbol']=='T1' }['value']=20
      rule=Parametric.edit_variables(rule,rows)
      Runtime.apply_trial_update(@host,rule,Parametric.targets(rule))
      @model.commit_operation
      Assembly.transact(@model,Assembly.records(@model));reset
      Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
      @report['checks'] << 'Inner panel contacts survive host T change and resize the imported body'
    end
    def delete_body
      rows=Assembly.records(@model).reject { |row| row.dig('b','root')==@body_root.persistent_id.to_s }
      Assembly.transact(@model,rows) { @body_root.erase! }
      edit=Core.rule!(JSON.parse(@host.get_attribute(Reader::DICT,'rule_json')))
      vars=Parametric.variables(edit);vars.find { |row| row['symbol']=='T1' }['value']=18
      edit=Parametric.edit_variables(edit,vars)
      Assembly.transact(@model,rows,updates:[[{'root'=>@host.persistent_id.to_s},edit,Parametric.targets(edit)]])
      reset
    end
    def hover_partial
      args=aim(@partial,[18,90,250],eye:[250,-600,350])
      result=ImportLinks.detect(@body,*args,cache:{})
      check(result && result['kind']=='inside' && result['matches'].length==5,'Open host accepts configured real and envelope references')
      check(result['matches'].count { |match| !match['target']['virtual'] }==2,'Partial host has two filled real faces and three distinct envelope boundaries')
    end
    def hover_and_place_door
      args=aim(@host,[300,0,9])
      @outside=ImportLinks.detect(@door,*args,cache:{})
      check(@outside && @outside['kind']=='outside' && @outside['matches'].any? { |match| match['mount'] },'Front outer face triggers opposed door preview')
      @door_root=ImportLinks.place(@library,@door,@outside);reset
    end
    def verify_door(value,clearance:1)
      box=Frames.box([@host,@door_root].flat_map { |root| 8.times.map { |i| root.definition.bounds.corner(i).transform(root.transformation).to_a.map { |v| v*25.4 } } })
      check((Core.dimensions(box)[1]-200).abs<0.02,"Combined depth remains 200 at T=#{value}")
      check((Assembly.projection(@host,[0,1,0]).then { |a,b| b-a }-(200-value-clearance)).abs<0.02,"Host reserves #{value+clearance} mm")
      Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
    end
    def thickness(root)
      rule=Core.rule!(JSON.parse(root.get_attribute(Reader::DICT,'rule_json')))
      ImportTemplate.thickness_values(rule,JSON.parse(root.get_attribute(Reader::DICT,'parameter_values_json')))['t1']
    end
    def test_clearance
      row=Assembly.records(@model).find { |entry| entry.dig('import_link','door_mount') }
      row['gap']=3;Assembly.save(@model,row);reset
      check((Assembly.projection(@host,[0,1,0]).then { |a,b| b-a }-178.4).abs<0.02,'Editing mounting clearance recomputes depth from original target')
      row=Assembly.records(@model).find { |entry| entry.dig('import_link','door_mount') };row['gap']=1;Assembly.save(@model,row);reset
      verify_door(18.6)
      Assembly.remove(@model,row['id']);reset
      check(ImportLinks.states(@host).empty? && (Assembly.projection(@host,[0,1,0]).then { |a,b| b-a }-200).abs<0.02,'Removing the mounting link releases host reservation immediately')
      Assembly.save(@model,row);reset;verify_door(18.6)
    end
    def test_delete_restore
      @model.start_operation('MH QA delete door',true);@door_root.erase!;@model.commit_operation
      Assembly.transact(@model,Assembly.records(@model));reset
      check(ImportLinks.states(@host).empty? && (Assembly.projection(@host,[0,1,0]).then { |a,b| b-a }-200).abs<0.02,'Deleting the last door restores the host depth')
      hover_and_place_door;verify_door(18.6)
    end
    def test_two_doors
      placement=Core.copy_data(@outside)
      # Reuse the already measured real mounting face; the first door now
      # covers it. This checks shared reservation independently of picking.
      placement['matches'].select! { |match| match['mount'] }
      second=ImportLinks.place(@library,@door,placement);reset
      check((Assembly.projection(@host,[0,1,0]).then { |a,b| b-a }-180.4).abs<0.02,'Two doors on one mounting plane reserve the maximum once')
      rows=Assembly.records(@model).reject { |row| row.dig('b','root')==second.persistent_id.to_s }
      Assembly.transact(@model,rows) { second.erase! };reset
      verify_door(18.6)
      check((thickness(@door_source)-18.6).abs<0.001,'Library source remains independent from placed doors')
    end
    def test_door_thickness
      row=Assembly.records(@model).find { |entry| entry.dig('import_link','door_mount') }
      row['gap']=3;Assembly.save(@model,row);reset
      [20,40,17.6,18.6].each do |value|
        rule,values=AssemblyParameters.data(@door_root)
        rows=Parametric.variables(Parametric.with_values(rule,values));rows.find { |entry| entry['symbol']=='T1' }['value']=value
        rule=Parametric.edit_variables(rule,rows)
        Assembly.transact(@model,Assembly.records(@model),updates:[[{'root'=>@door_root.persistent_id.to_s},rule,Parametric.targets(rule)]]);reset
        verify_door(value,clearance:3)
        check((thickness(@host)-18).abs<0.001,'Changing door T alone does not change host physical panel T')
      end
      row=Assembly.records(@model).find { |entry| entry.dig('import_link','door_mount') };row['gap']=1
      Assembly.save(@model,row);reset;verify_door(18.6)
      @report['checks'] << 'Independent door T edits with configurable 3 mm gap preserve the 200 mm combined envelope'
    end
    def group_door
      rows=Assembly.records(@model);seed=rows.find { |row| row.dig('b','root')==@door_root.persistent_id.to_s }
      @host_key=AssemblyContainers.member_key(@host);@door_key=AssemblyContainers.member_key(@door_root)
      Assembly.group(@model,seed)
      @group=@model.selection.first;locate_members
      check(@group.get_attribute(Reader::DICT,AssemblyParameters::KEY)==@host_key,'Explicit Group assigns host as master')
      check(thickness(@door_root)==18,'Grouping synchronizes the same T1 symbol to master')
      verify_door(18)
    end
    def locate_members
      members=AssemblyContainers.members(@group)
      @host=members.find { |root| root.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==@host_key }
      @door_root=members.find { |root| root.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==@door_key }
    end
    def edit_master(value)
      own=Core.rule!(JSON.parse(@host.get_attribute(Reader::DICT,'rule_json')))
      vars=Parametric.variables(own);vars.find { |row| row['symbol']=='T1' }['value']=value
      own=Parametric.edit_variables(own,vars)
      anchor={'root'=>@host.persistent_id.to_s,'scope'=>@group&.persistent_id&.to_s}.compact
      Assembly.transact(@model,Assembly.records(@model),updates:[[anchor,own,Parametric.targets(own)]])
      reset
    end
    def save_group
      path=File.join(@folder,'group.skp');AssemblyFile.save(@group,path)
      payload=ModuleFile.read(path)
      check(payload['master_member']==@host_key,'Assembly SKP retains master member identity')
      check(payload['links'].any? { |row| row.dig('import_link','door_mount') },'Assembly SKP retains automatic door contacts')
      @model.start_operation('MH QA reopen group',true)
      definition=@model.definitions.load(path);copy=@model.entities.add_instance(definition,Geom::Transformation.translation([115_000/25.4,0,0]))
      AssemblyFile.restore(copy,payload)
      @model.commit_operation;reset
      saved_group=@group;@group=copy;locate_members
      edit_master(17.6);verify_door(17.6)
      check((thickness(@door_root)-17.6).abs<0.001,'Reopened SKP still synchronizes thickness and reservation')
      original=AssemblyContainers.members(saved_group).find { |member| member.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==@door_key }
      check(thickness(original)==20,'Editing reopened assembly leaves original assembly thickness unchanged')
      rows=Assembly.records(@model).reject { |row| row['scope']==copy.persistent_id.to_s }
      Assembly.transact(@model,rows) { copy.erase! };reset
      @group=saved_group;locate_members
    end
    def regroup
      # Add a new connected raw module, then use the same explicit Group action.
      @model.start_operation('MH QA additional module',true)
      extra=build(@body_snapshot,@body_rule,109_000);extra_key=AssemblyContainers.member_key(extra)
      @model.commit_operation
      seed={'id'=>Core::Ids.uuid,'mode'=>'contact','external'=>true,
        'a'=>{'root'=>@host.persistent_id.to_s,'scope'=>@group.persistent_id.to_s,'axis'=>0,'side'=>1},
        'b'=>{'root'=>extra.persistent_id.to_s,'axis'=>0,'side'=>0},'gap'=>0}
      Assembly.save(@model,seed);Assembly.group(@model,seed)
      @group=@model.selection.first;locate_members
      check(AssemblyContainers.members(@group).any? { |root| root.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==extra_key },'Regrouping adds a third module')
      check(@group.get_attribute(Reader::DICT,AssemblyParameters::KEY)==@host_key,'Regrouping preserves the original host master')
      edit_master(18);verify_door(18)
    end
    def test_inset
      @model.start_operation('MH QA separate inset host',true)
      snapshot=host_snapshot
      host=build(snapshot,@host_rule,111_000)
      @model.commit_operation;reset
      body=Core.copy_data(@door);body['import_template']['mode']='inside'
      args=aim(host,[300,174,250]);placement=ImportLinks.detect(body,*args,cache:{})
      original=Core.dimensions(AssemblyEnvelope.bounds(host))
      child=ImportLinks.place(@library,body,placement)
      check(ImportLinks.states(host).empty?,'Inset door does not reserve host depth')
      check(Core.dimensions(AssemblyEnvelope.bounds(host))==original,'Inset door retains host dimensions')
      check(placement['matches'].length==4,'Inset door binds available inner edge faces and leaves its rear unbound')
      @report['inset_child']=child.persistent_id
    end
    def nested_setup
      @model.start_operation('MH QA nested ATT modules',true)
      @nested_host=build(host_snapshot,@host_rule,117_000)
      own=ImportTemplate.defaults.merge('enabled'=>true);own['faces'].each { |slot| slot['gap']=2 }
      rule=ImportTemplate.edit(@host_rule,own)
      source=build(host_snapshot,rule,119_000)
      [[0,350],[1,100],[2,350]].each do |axis,size|
        normal=[0,0,0];normal[axis]=1;Assembly.resize(source,normal,size)
      end
      @model.commit_operation;reset
      @library.export(source,File.join(@library_folder,'nested.skp'));@library.refresh
      data=@library.preview('nested.skp');args=aim(@nested_host,[300,174,250])
      placement=ImportLinks.detect(data,*args,cache:{})
      check(placement && placement['matches'].length==5,'Nested ATT module matches five actual host inner faces with 2 mm clearances')
      @nested_child=ImportLinks.place(@library,data,placement)
      @nested_size=[600,200,500];@nested_group=nil;reset
    end
    def nested_verify(value)
      size=3.times.map do |axis|
        normal=[0,0,0];normal[axis]=1
        Assembly.projection(@nested_child,normal).then { |low,high| high-low }
      end
      check((size[0]-(@nested_size[0]-2*value-4)).abs<0.02 && (size[2]-(@nested_size[2]-2*value-4)).abs<0.02,"Inset child fits changed inner width/height at host T=#{value}: #{size.map { |n| n.round(3) }}")
      check((size[1]-100).abs<0.02,'Unbound child depth retains its source size of 100 mm')
      expected=@nested_group ? value : 18
      check((thickness(@nested_child)-expected).abs<0.001,'Child physical T stays exact while its free dimensions resize')
      rows=Assembly.records(@model).select { |row| row.dig('b','root')==@nested_child.persistent_id.to_s }
      check(rows.length==5 && rows.all? { |row| (row['gap']-2).abs<0.001 },'Five saved 2 mm inner contacts remain present')
      rows.each { |row| Assembly.verify(@model,row) }
      check(!Assembly.last_error,'Automatic dependency redraw reports no error')
      @report['nested_values']||=[]
      @report['nested_values'] << {'host_t'=>value,'child_size'=>size,'grouped'=>!!@nested_group,'host_size'=>@nested_size.dup}
    end
    def nested_change(value,observer:false)
      rule,values=AssemblyParameters.data(@nested_host)
      rows=Parametric.variables(Parametric.with_values(rule,values));rows.find { |row| row['symbol']=='T1' }['value']=value
      rule=Parametric.edit_variables(rule,rows)
      if observer
        @model.start_operation('MH QA host T observer',true)
        Runtime.apply_trial_update(@nested_host,rule,Parametric.targets(rule));@model.commit_operation
        # Leave observers active: the next timer verifies their actual redraw.
      else
        anchor={'root'=>@nested_host.persistent_id.to_s,'scope'=>@nested_group.persistent_id.to_s}
        Assembly.transact(@model,Assembly.records(@model),updates:[[anchor,rule,Parametric.targets(rule)]]);reset
      end
    end
    def nested_group
      seed=Assembly.records(@model).find { |row| row.dig('b','root')==@nested_child.persistent_id.to_s }
      @nested_host_key=AssemblyContainers.member_key(@nested_host);@nested_child_key=AssemblyContainers.member_key(@nested_child)
      Assembly.group(@model,seed);@nested_group=@model.selection.first
      nested_locate;reset
    end
    def nested_locate
      members=AssemblyContainers.members(@nested_group)
      @nested_host=members.find { |member| member.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==@nested_host_key }
      @nested_child=members.find { |member| member.get_attribute(Reader::DICT,AssemblyContainers::MEMBER)==@nested_child_key }
    end
    def nested_scale
      @model.start_operation('MH QA Scale nested host assembly',true)
      @nested_group.transformation*=Geom::Transformation.scaling(ORIGIN,1.2,1,1.2)
      @model.commit_operation
      @nested_size=[720,200,600]
    end
    def nested_reopen
      path=File.join(@folder,'nested-group.skp');AssemblyFile.save(@nested_group,path)
      @model.start_operation('MH QA reopen inset assembly',true)
      definition=@model.definitions.load(path)
      @nested_group=@model.entities.add_instance(definition,Geom::Transformation.translation([122_000/25.4,0,0]))
      AssemblyFile.restore(@nested_group,ModuleFile.read(path));@model.commit_operation
      nested_locate;reset
    end
    def later
      UI.start_timer(0.18,false) do
        begin
          @steps.shift&.call
          later if @report['status']=='running'
        rescue StandardError=>error
          fail_check(error)
        end
      end
    end
    def fail_check(error)
      @report||={'checks'=>[]};@report['status']='failed';@report['error']="#{error.class}: #{error.message}";@report['backtrace']=error.backtrace.first(8)
      finish
    end
    def finish
      @model.overlays.remove(@overlay) if @overlay;@overlay=nil
      @model.start_operation('MH QA 072 cleanup',true)
      (@model.entities.to_a-@roots).each { |root| root.erase! if root.valid? }
      30.times { (@model.definitions.to_a-@defs).each { |definition| @model.definitions.remove(definition) if definition.valid? && definition.instances.empty? } }
      @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,JSON.generate(@links))
      @model.selection.clear;@selection.each { |root| @model.selection.add(root) if root.valid? }
      @model.commit_operation;reset;@model.active_view.camera=@camera
      @report['model_retained']=@model.entities.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }==@before && @model.definitions.to_a==@defs && @model.selection.to_a==@selection
      @report['status']=@report['model_retained'] ? 'passed' : 'failed' if @report['status']=='running'
      File.write(File.join(@folder,'native.json'),JSON.pretty_generate(@report))
    end
  end
end
MH::ModuleStudio::NativeImportLinksCheck.start
