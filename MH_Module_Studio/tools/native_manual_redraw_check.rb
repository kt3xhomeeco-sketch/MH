# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeManualRedrawCheck
      extend self
      class Dialog
        def execute_script(_script);end
        def set_size(*);end
      end

      def start(source_pid:)
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        @source=@model.find_entity_by_persistent_id(source_pid)
        @roots=@model.entities.to_a;@defs=@model.definitions.to_a;@selection=@model.selection.to_a
        @source_before=geometry(@source)
        @links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @before=@roots.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }
        @report={'status'=>'running','checks'=>[],'timings'=>[]}
        @model.start_operation('MH QA Manual Redraw setup',true)
        @copy=clone(@source,4000);ScaleRedraw.apply(@model,[ScaleRedraw.prepare(@copy)])
        @model.selection.clear;@model.selection.add(@copy);@model.commit_operation;reset
        @options=ModuleOptions.new;@options.instance_variable_set(:@dialog,Dialog.new)
        @options.define_singleton_method(:thumbnail) { |_root| nil }
        @options.refresh
        @steps=[
          -> { damage(@copy);@damaged=geometry(@copy);option_redraw;verify(@copy,'Options button');@repaired=geometry(@copy);Sketchup.undo },
          -> { check(geometry(@copy)==@damaged,'One Undo restores pre-Redraw geometry without undoing the Scale');Sketchup.send_action('editRedo:') },
          -> { check(geometry(@copy)==@repaired,'Redo restores manual reconstruction');damage(@copy);timed('shortcut') { MH::ModuleStudio.instance_variable_get(:@redraw_command).proc.call };verify(@copy,'Registered shortcut');check(MH::ModuleStudio.instance_variable_get(:@redraw_command).menu_text=='MH Module Studio · Redraw','Shortcut has its assignable Preferences name');timed('correct_module') { Assembly.redraw(@copy) };verify(@copy,'Repeated no-op command') },
          -> { grouped },
          -> { failure_is_atomic;finish }
        ];later
        puts 'scheduled'
      rescue StandardError=>error
        @report['error']=[error.message,*error.backtrace.first(6)];finish
      end

      def clone(source,offset)
        root=@model.entities.add_instance(source.definition,Geom::Transformation.translation([offset,0,0])*source.transformation)
        source.attribute_dictionaries&.each { |dict| dict.each_pair { |key,value| root.set_attribute(dict.name,key,value) } }
        root.name=source.name;Runtime.private_tree(root);root
      end

      def reset
        ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      end

      def damage(root)
        @model.start_operation('MH QA Unrepaired Scale',true)
        root.transformation*=Geom::Transformation.scaling(1,1.1,1)
        @model.commit_operation
        # Exercise the explicit command even when the watcher acknowledged a
        # previously missed Scale, rather than allowing its queued auto repair.
        reset
      end

      def timed(name)
        start=Process.clock_gettime(Process::CLOCK_MONOTONIC);result=yield
        @report['timings'] << {'step'=>name,'ms'=>((Process.clock_gettime(Process::CLOCK_MONOTONIC)-start)*1000).round(2)}
        result
      end

      def option_redraw
        @options.refresh
        2.times { timed('unchanged_options_refresh') { @options.refresh } }
        token=@options.instance_variable_get(:@token)
        before=geometry(@copy)
        begin
          @options.request('action'=>'redraw','root_pid'=>@copy.persistent_id.to_s,'token'=>'stale')
          raise 'Stale request was accepted'
        rescue Core::Error
          check(geometry(@copy)==before,'Stale button token leaves geometry unchanged')
        end
        timed('options_button') { @options.request('action'=>'redraw','root_pid'=>@copy.persistent_id.to_s,'token'=>token) }
      end

      def geometry(root)
        return AssemblyContainers.members(root).map { |member| geometry(member) } if AssemblyContainers.managed?(root)
        snapshot,=Reader.live(root,label:root.name,parameter:nil)
        {'frame'=>root.transformation.to_a,'parts'=>snapshot['parts'].map { |part| part.slice('key','bounds','visible') },
         'values'=>root.get_attribute(Reader::DICT,'parameter_values_json'),'rule'=>root.get_attribute(Reader::DICT,'rule_json')}
      end

      def verify(root,label)
        members=AssemblyContainers.managed?(root) ? AssemblyContainers.members(root) : [root]
        members.each do |member|
          check(ScaleRedraw.prepare(member)[2]['changed_count'].zero?,label+' leaves no pending geometry changes')
          snapshot,=Reader.live(member,label:'QA',parameter:nil)
          back=snapshot['parts'].find { |part| part['name']=='Hậu' }
          check((Core.dimensions(back['bounds'])[1]-8).abs<0.001,label+' keeps physical back thickness 8 mm')
        end
        Assembly.records(@model).each { |row| Assembly.verify(@model,row) }
      end

      def grouped
        @model.start_operation('MH QA Linked partner',true)
        partner=clone(@source,5000);ScaleRedraw.apply(@model,[ScaleRedraw.prepare(partner)]);@model.commit_operation;reset
        row={'mode'=>'contact','a'=>{'root'=>@copy.persistent_id.to_s,'axis'=>0,'side'=>1},'b'=>{'root'=>partner.persistent_id.to_s,'axis'=>0,'side'=>0},'gap'=>3}
        saved=Assembly.save(@model,row);Assembly.group(@model,saved)
        wrapper=@model.selection.first;original=geometry(wrapper)
        @model.start_operation('MH QA Shared assembly copy',true)
        copy=@model.entities.add_instance(wrapper.definition,Geom::Transformation.translation([0,4000,0])*wrapper.transformation)
        wrapper.attribute_dictionaries.each { |dict| dict.each_pair { |key,value| copy.set_attribute(dict.name,key,value) } }
        copy.name=wrapper.name;@model.selection.clear;@model.selection.add(copy);@model.commit_operation;reset
        damage(copy)
        timed('group_redraw') { Assembly.redraw(copy) }
        verify(copy,'Grouped Redraw')
        check(geometry(wrapper)==original,'Redrawing a copied linked assembly leaves the original assembly unchanged')
        check(Assembly.records(@model).select { |link| link['scope']==copy.persistent_id.to_s }.all? { |link| (link['gap']-3).abs<0.001 },'Grouped Redraw retains 3 mm saved contacts')
        @failure_root=AssemblyContainers.members(copy).first
        @failure_wrapper=copy
      end

      def failure_is_atomic
        damage(@failure_root);before=geometry(@failure_wrapper)
        original=Runtime.method(:verify_result)
        Runtime.define_singleton_method(:verify_result) { |*_args| raise Core::Error,'QA rejected native result' }
        begin
          Assembly.redraw(@failure_wrapper)
          raise 'Invalid native result was accepted'
        rescue Core::Error=>error
          check(error.message=='QA rejected native result','Invalid native geometry is reported')
        ensure
          Runtime.define_singleton_method(:verify_result,original)
        end
        check(geometry(@failure_wrapper)==before,'Failed manual Redraw aborts its geometry and metadata changes')
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
            @report['error']=[error.message,*error.backtrace.first(6)];finish
          end
        end
      end

      def finish
        @options&.instance_variable_set(:@dialog,nil)
        @options&.instance_variable_set(:@refresh_scheduled,nil)
        @options&.detach
        @model.start_operation('MH QA Redraw cleanup',true)
        (@model.entities.to_a-@roots).each { |entity| entity.erase! if entity.valid? }
        25.times { (@model.definitions.to_a-@defs).each { |definition| @model.definitions.remove(definition) if definition.valid? && definition.instances.empty? } }
        @links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        @model.selection.clear;@selection.each { |entity| @model.selection.add(entity) if entity.valid? };@model.commit_operation;reset
        @report['model_retained']=@model.entities.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }==@before && @model.definitions.to_a==@defs && geometry(@source)==@source_before
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        base=File.dirname(Panel.instance_method(:show).source_location.first)
        File.write(File.join(base,'outputs/redraw-074/native.json'),JSON.pretty_generate(@report))
      end
    end
  end
end
