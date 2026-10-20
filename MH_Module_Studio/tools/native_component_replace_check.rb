# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeComponentReplaceCheck
      extend self
      def start
        @model=Sketchup.active_model;@before=@model.entities.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] };@defs=@model.definitions.to_a;@materials=@model.materials.to_a;@selection=@model.selection.to_a;@links=@model.get_attribute(Reader::DICT,AssemblyContainers::KEY)
        @created=[];@report={'status'=>'running','checks'=>[]};@folder=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/replace-078')
        @library=Library.new;@library.config['root']=File.join(File.dirname(@folder),'direct-links-077/library');@library.refresh;@data=@library.preview('drawer.skp')
        @model.start_operation('MH QA component seed',true)
        @source=@library.build_instance(@data,Geom::Transformation.translation([132000/25.4,0,0]));@created << @source.persistent_id
        @model.commit_operation;ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
        @model.start_operation('QA native Replace Component equivalent',true)
        @external=@model.entities.add_instance(@source.definition,Geom::Transformation.translation([134000/25.4,0,0])*Geom::Transformation.scaling(1.1,1.2,1.1));@external.name='Native replacement';@created << @external.persistent_id
        @model.commit_operation
        @steps=[
          -> { verify_external;@external_pid=@external.persistent_id;Sketchup.undo },
          -> { check(!@model.find_entity_by_persistent_id(@external_pid),'One Undo removes native replacement and its automatic rule adoption');Sketchup.send_action('editRedo:') },
          -> { @external=@model.find_entity_by_persistent_id(@external_pid);check(@external && @external.get_attribute(Reader::DICT,'trial',false),'Redo restores native replacement with usable own properties');reassign },
          -> { @report['adoption']={'source'=>thickness(@source),'external'=>thickness(@external),'error'=>LibraryAdoption.last_error,'pending'=>ComponentMetadata.pending?(@external),'marker'=>@external.get_attribute(Reader::DICT,'definition_pid'),'definition'=>@external.definition.persistent_id};check((thickness(@external)-24).abs<0.0001,'Native definition reassignment replaces stale T with the new component source T');check((thickness(@source)-24).abs<0.0001,'Adoption never mutates source parameters');check(@external.get_attribute(Reader::DICT,'instance_id')!=@source.get_attribute(Reader::DICT,'instance_id'),'Replaced component and source have independent identities');edit_external },
          -> { check((thickness(@external)-26).abs<0.0001 && (thickness(@source)-24).abs<0.0001,'Adopted component edits remain independent of the source');legacy_payload },
          -> { check(@legacy.get_attribute(Reader::DICT,'trial',false) && (thickness(@legacy)-22).abs<0.0001,'Native import of an older Library SKP receives rules from its embedded payload');scale_external(1.15) },
          -> { verify_scale('Native Scale still redraws adopted modules and retains exact T');scale_external(0.9) },
          -> { verify_scale('A second native Scale is not consumed by the adoption observer');finish }
        ];later;puts 'scheduled'
      rescue StandardError=>error
        fail_check(error)
      end
      def verify_external
        check(!LibraryAdoption.last_error && @external.get_attribute(Reader::DICT,'trial',false),'Native-created instance automatically receives source module rules')
        size=Core.dimensions(Reader.live(@external,label:'QA external',parameter:nil).first['envelope']);wanted=Core.dimensions(@data['snapshot']['envelope']).zip([1.1,1.2,1.1]).map { |a,b| a*b }
        check(size.zip(wanted).all? { |a,b| (a-b).abs<0.02 },'Adoption redraws the native replacement to its actual scaled envelope')
        check(ComponentMetadata.pending?(@external)==false,'Adopted identity is acknowledged and does not trigger repeated adoption')
      end
      def thickness(root)
        rule,values=AssemblyParameters.data(root);rule=Parametric.with_values(rule,values);row=Parametric.variables(rule).find { |r| r['symbol']=='T1' };Parametric.evaluate_variables(rule).fetch(row['id'])
      end
      def change(root,value)
        rule,values=AssemblyParameters.data(root);rows=Parametric.variables(Parametric.with_values(rule,values));rows.find { |r| r['symbol']=='T1' }['value']=value
        edited=Parametric.edit_variables(rule,rows);Runtime.update_trial(root,edited,Parametric.targets(edited))
      end
      def reassign
        change(@source,24)
        @model.start_operation('QA Replace existing definition',true)
        @external.definition=@source.definition
        @model.commit_operation
      end
      def edit_external
        change(@external,26)
      end
      def legacy_payload
        @model.start_operation('QA native old Library import',true)
        definition=@model.definitions.load(File.join(@library.config['root'],'drawer.skp'))
        @legacy=@model.entities.add_instance(definition,Geom::Transformation.translation([136000/25.4,0,0]));@created << @legacy.persistent_id
        @legacy.make_unique;@legacy.definition.delete_attribute(Reader::DICT,ComponentMetadata::KEY)
        @model.commit_operation
      end
      def scale_external(factor)
        size=Core.dimensions(Reader.live(@external,label:'QA Scale before',parameter:nil).first['envelope']);@scaled_width=size[0]*factor
        @model.start_operation('QA native Scale after Replace',true)
        @external.transform!(Geom::Transformation.scaling(@external.bounds.center,factor,1,1));@model.commit_operation
      end
      def verify_scale(label)
        rule,values=AssemblyParameters.data(@external);current,=Reader.live(@external,label:'QA Scale after',parameter:Runtime.read_parameter(rule,values))
        check(!ScaleRedraw.watch(@model).last_error && (Core.dimensions(current['envelope'])[0]-@scaled_width).abs<0.02 && (thickness(@external)-26).abs<0.0001 && Core.plan(rule,current,values)['changed_count'].zero?,label)
      end
      def check(condition,label)
        raise label unless condition
        @report['checks'] << label
      end
      def later
        UI.start_timer(0.4,false) do
          begin;@steps.shift.call;later unless @steps.empty?;rescue StandardError=>error;fail_check(error);end
        end
      end
      def fail_check(error)
        @report||={};@report['error']=[error.message,*error.backtrace.first(7)];finish
      end
      def finish
        @model.start_operation('MH QA external cleanup',true)
        @created.each { |pid| r=@model.find_entity_by_persistent_id(pid);r.erase! if r && r.valid? }
        30.times { (@model.definitions.to_a-@defs).each { |d| @model.definitions.remove(d) if d.valid? && d.instances.empty? } }
        (@model.materials.to_a-@materials).each { |m| @model.materials.remove(m) if m.valid? }
        @links ? @model.set_attribute(Reader::DICT,AssemblyContainers::KEY,@links) : @model.delete_attribute(Reader::DICT,AssemblyContainers::KEY)
        @model.selection.clear;@selection.each { |r| @model.selection.add(r) if r.valid? };@model.commit_operation;ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
        @report['model_retained']=@before==@model.entities.map { |r| [r.persistent_id,r.bounds.min.to_a,r.bounds.max.to_a] } && @model.definitions.to_a==@defs
        @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
        File.write(File.join(@folder,'external.json'),JSON.pretty_generate(@report))
      end
    end
  end
end
