# encoding: UTF-8
# Developer-only. Run New only from a clean, empty, unsaved model.
module MH
  module ModuleStudio
    module NativeSessionCheck
      extend self

      def write
        File.write(File.join(@folder,'native-check.json'),JSON.pretty_generate(@report))
      end

      def start
        @report=nil
        model=Sketchup.active_model
        raise 'New-model QA requires a clean empty Untitled model' unless model.entities.length==0 && model.path.empty? && !model.modified?
        existing=MH::ModuleStudio.instance_variable_get(:@panel)
        raise 'Keep the existing draft' if existing && (!existing.instance_variable_get(:@snapshots).empty? || existing.instance_variable_get(:@rule))
        base=File.expand_path('..',__dir__);@folder=File.join(base,'outputs/session-068');FileUtils.mkdir_p(@folder)
        @report={'status'=>'running','checks'=>[]}
        library_folder='D:/Cong viec/Sketchup/DC/Modul_studio/New folder'
        @library=Library.new
        @library.instance_variable_set(:@config,LibraryCatalog.settings('root'=>library_folder))
        @library.instance_variable_set(:@catalog,LibraryCatalog.scan(library_folder))
        entry=@library.catalog['entries'].find { |item| File.basename(item['path'])=='2.CC Vach giua.skp' }
        @preview=@library.preview(entry['id'])
        @report['checks'] << 'Existing verified SKP preview/cache prepared before New; no preferences or files changed'
        @prior_panel=existing;@panel=existing || Panel.new
        MH::ModuleStudio.instance_variable_set(:@panel,@panel)
        @panel.instance_variable_set(:@captured_root_pid,123)
        @panel.instance_variable_set(:@captured_model,model)
        @panel.instance_variable_set(:@busy,true)
        @prior_options=MH::ModuleStudio.instance_variable_get(:@module_options)
        @options=ModuleOptions.new;@options.attach
        @old_session_token=@options.instance_variable_get(:@session_token)
        @options.instance_variable_set(:@thumbnail_key,['old-session'])
        MH::ModuleStudio.instance_variable_set(:@module_options,@options)
        @old=model
        write
        raise 'New failed' unless Sketchup.file_new
        UI.start_timer(0.1,false) { after_new }
      rescue StandardError=>error
        if @report
          @report['status']='failed';@report['error']="#{error.class}: #{error.message}";write
        end
        raise
      end

      def after_new
        model=Sketchup.active_model
        raise 'Stale panel state survived New' unless @panel.instance_variable_get(:@captured_root_pid).nil? && !@panel.instance_variable_get(:@busy) && @panel.instance_variable_get(:@snapshots).empty?
        raise 'Panel still points to old model' unless @panel.instance_variable_get(:@model_context).equal?(model)
        raise 'Old thumbnail survived New' unless @options.instance_variable_get(:@thumbnail_key).nil?
        @report['model_object_reused']=model.equal?(@old)
        @report['checks'] << 'Real File New clears old PID/draft/busy state and rebinds model sessions'
        check_links(model)
        model.start_operation('MH QA Load Rules After New',true)
        operation=true
        root=@library.build_instance(@preview,Geom::Transformation.new)
        rule=Core.rule!(JSON.parse(root.get_attribute(Reader::DICT,'rule_json')))
        model.selection.clear;model.selection.add(root)
        @panel.capture_parametric_root(root)
        raise 'Parametric did not load the new model rule' unless @panel.instance_variable_get(:@rule)['id']==rule['id'] && @panel.captured_root!.equal?(root)
        @options.instance_variable_set(:@dialog,Object.new)
        @options.define_singleton_method(:send_state) { |payload| @test_payload=payload }
        @options.refresh
        raise 'Options session token was reused' if @old_session_token==@options.instance_variable_get(:@session_token)
        payload=@options.instance_variable_get(:@test_payload)
        raise 'Module Options failed after New' unless payload && !payload['error'] && payload['root_pid']==root.persistent_id.to_s
        @report['checks'] << 'Cached preview imports into the new model; Parametric and Module Options load its own rule'
        drawer_definition=model.definitions.load('D:/Cong viec/Sketchup/DC/MH/1.CA Mat ngan keo.skp')
        drawer=model.entities.add_instance(drawer_definition,Geom::Transformation.new)
        converter=DCLibraryConversion.allocate
        drawer=converter.unwrap(drawer);drawer=drawer.to_component if drawer.is_a?(Sketchup::Group)
        converter.normalize(drawer);converter.assign_part_keys(drawer)
        snapshot,bindings=Reader.live(drawer,label:'1.CA Mat ngan keo',parameter:nil)
        rule=StudioCalculation.build_system([snapshot])
        expected=snapshot['dc_inputs'].keys.reject { |key| key.start_with?('_') || DCCustomAttributes::STANDARD.include?(key.downcase) }
        known=rule['parameters'].flat_map { |param| [param['key'],param['dc_key']] }
        raise 'Drawer custom attributes missing' unless (expected-known).empty?
        @report['custom_attributes']=expected.length;@report['missing_custom_attributes']=expected-known
        Runtime.private_tree(drawer)
        variable=Parametric.variables(rule).find { |item| item['symbol']=='T1' }
        value=variable['value']
        [20,value].each do |thickness|
          plan=Core.plan(rule,snapshot,variable['binding']=>thickness)
          Runtime.apply_plan(bindings,plan);Runtime.stamp(drawer,rule,bindings,plan['target']);Runtime.verify_result(drawer,plan)
          snapshot,bindings=Reader.live(drawer,label:drawer.name,parameter:nil)
        end
        @report['checks'] << 'Drawer thickness changes to 20 mm and restores after New, with native mesh verification'
        @report['status']='passed'
      rescue StandardError=>error
        @report['status']='failed';@report['error']="#{error.class}: #{error.message}"
      ensure
        @options.instance_variable_set(:@dialog,nil)
        model.abort_operation if operation
        @options.detach
        @panel.model_changed(model,force:true)
        MH::ModuleStudio.instance_variable_set(:@panel,@prior_panel)
        MH::ModuleStudio.instance_variable_set(:@module_options,@prior_options)
        @report['final_entities']=model.entities.length
        write
      end

      def check_links(model)
        raise 'New model is not empty' unless model.entities.length==0
        model.start_operation('MH QA Link Fixtures',true)
        a=model.entities.add_group;b=model.entities.add_group
        [a,b].each { |group| group.entities.add_face([[0,0,0],[1,0,0],[1,1,0],[0,1,0]]).pushpull(1) }
        b.transformation=Geom::Transformation.translation([1,0,0])
        row={'id'=>'qa-068','mode'=>'contact','gap'=>0,'a'=>{'root'=>a.persistent_id.to_s,'axis'=>0,'side'=>1},'b'=>{'root'=>b.persistent_id.to_s,'axis'=>0,'side'=>0}}
        AssemblyContainers.store(model,[row]);model.commit_operation
        raise 'Live link hidden' unless Assembly.records(model).length==1
        model.start_operation('MH QA Delete Module',true);b.erase!;model.commit_operation
        raise 'Deleted link still shown' unless Assembly.records(model).empty? && AssemblyContainers.read(model).length==1
        Sketchup.undo
        raise 'Undo did not restore the link' unless Assembly.records(model).length==1
        Sketchup.undo
        raise 'Fixture cleanup failed' unless model.entities.length==0 && AssemblyContainers.read(model).empty?
        @report['checks'] << 'Delete hides native module link; real Undo restores it; Undo fixture creation removes all QA geometry'
      end
    end
  end
end
