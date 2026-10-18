# encoding: UTF-8
raise 'Wrong test process' unless Process.pid == 26424
raise 'Wrong test model' unless File.basename(Sketchup.active_model.path).downcase == '1.skp'
module MH
 module ModuleStudio
  module NativeScaleCheck
   extend self
   def start
    @model=Sketchup.active_model
    Runtime.ensure_top_level(@model)
    @roots=@model.entities.to_a; @defs=@model.definitions.to_a; @selection=@model.selection.to_a
    @done=false; @created=[]; @report={'pid'=>Process.pid,'checks'=>[]}; @queue=[]
    source=JSON.parse(File.read(File.join(__dir__,'..','test','fixtures','readable_nested_dc.json'),encoding:'UTF-8'))
    @rule=RuleSystem.build(source,Core.learn_module([source]))
    Runtime.create_model(source,@rule,{})
    @first=@model.selection.first; @created << @first
    @model.start_operation('MH QA Shared Copy',true)
    @second=@model.active_entities.add_instance(@first.definition,Geom::Transformation.translation([100,0,0]))
    @first.attribute_dictionary(Reader::DICT).each_pair { |key,value| @second.set_attribute(Reader::DICT,key,value) }
    @created << @second; @model.commit_operation
    @original=state(@first); @other=state(@second)
    @queue << lambda { scale([@first],[1.4,1,1]) }
    @queue << lambda do
     check(@first,[840,500,850]); same(@other,state(@second),'Shared copy changed')
     @scaled=state(@first); Sketchup.undo
    end
    @queue << lambda do
     same(@original,state(@first),'One Undo did not restore pre-Scale')
     @report['checks'] << 'single_undo'; Sketchup.send_action('editRedo:')
    end
    @queue << lambda do
     same(@scaled,state(@first),'Redo did not restore repaired geometry')
     @report['checks'] << 'single_redo'
     Runtime.update_trial(@first,@rule,'dayvan'=>20)
    end
    @queue << lambda do
     check(@first,[840,500,850]); @report['checks'] << 'post_scale_parameter_edit'
     @model.start_operation('MH QA Move Rotate',true)
     @first.transformation=Geom::Transformation.translation([20,30,40])*Geom::Transformation.rotation(ORIGIN,Z_AXIS,0.4)*@first.transformation
     @position=@first.transformation.to_a; @definition=@first.definition
     @model.commit_operation
    end
    @queue << lambda do
     raise 'Move/rotate redrew geometry' unless @first.definition==@definition && @first.transformation.to_a==@position
     @report['checks'] << 'move_rotate_ignored'; scale([@first],[1,1.2,0.8])
    end
    @queue << lambda do
     check(@first,[840,600,680]); @report['checks'] << 'rotated_nonuniform_scale'
     scale([@first],[-1.1,1.1,1.1])
    end
    @queue << lambda do
     check(@first,[924,660,748]); @report['checks'] << 'mirrored_uniform_scale'
     scale([@first,@second],[1.1,1.1,1.1])
    end
    @queue << lambda do
     check(@first,[1016.4,726,822.8]); check(@second,[660,550,935])
     raise 'Instance identity shared' if @first.get_attribute(Reader::DICT,'instance_id')==@second.get_attribute(Reader::DICT,'instance_id')
     @report['checks'] << 'multiple_modules_independent'
     Sketchup.undo
    end
    @queue << lambda do
     check(@first,[924,660,748]); check(@second,[600,500,850]); @report['checks'] << 'batch_single_undo'
     @library_data=MH::ModuleStudio.library.prepare('1.1 CC Khung Hậu Phủ.skp')
     @library_root=MH::ModuleStudio.library.place(@library_data,Geom::Point3d.new(250,0,0)); @created << @library_root
     @library_size=Core.dimensions(state(@library_root)['envelope']).map { |value| value*1.1 }
    end
    @queue << lambda { scale([@library_root],[1.1,1.1,1.1]) }
    @queue << lambda do
     check(@library_root,@library_size); @report['checks'] << 'converted_library_module'
     @redo_before=state(@first); scale([@first],[1.05,1,1])
    end
    @queue << lambda { @redo_first=state(@first); scale([@first],[1.05,1,1]) }
    @queue << lambda { @redo_second=state(@first); Sketchup.undo }
    @queue << lambda { same(@redo_first,state(@first),'First of two Undo failed'); Sketchup.undo }
    @queue << lambda { same(@redo_before,state(@first),'Second Undo failed'); Sketchup.send_action('editRedo:') }
    @queue << lambda { same(@redo_first,state(@first),'First of two Redo failed'); Sketchup.send_action('editRedo:') }
    @queue << lambda do
     same(@redo_second,state(@first),'Second Redo was lost after first redraw')
     @report['checks'] << 'redo_history_preserved'
     failure_case(false); failure_case(true)
     cleanup
    end
    later
   rescue StandardError=>error
    fail_check(error)
   end
   def state(root)
    snapshot,=Reader.live(root,label:'QA Scale',parameter:nil)
    {'parts'=>snapshot['parts'].map { |part| part.slice('key','bounds','visible') },'envelope'=>snapshot['envelope'],'values'=>root.get_attribute(Reader::DICT,'parameter_values_json')}
   end
   def same(expected,actual,message)
    raise message unless expected['values']==actual['values'] && expected['parts'].zip(actual['parts']).all? { |a,b| a['key']==b['key'] && Core.bounds_close?(a['bounds'],b['bounds'],0.001) }
   end
   def check(root,size)
    snapshot,=Reader.live(root,label:'QA after Scale',parameter:nil)
    actual=Core.dimensions(snapshot['envelope'])
    raise "Wrong envelope: #{actual.inspect}, expected #{size.inspect}" unless actual.zip(size).all? { |a,b| (a-b).abs<0.001 }
    rule=JSON.parse(root.get_attribute(Reader::DICT,'rule_json'))
    raise 'Post-Scale formula baseline invalid' unless Core.plan(rule,snapshot,{})['changed_count']==0
    raise 'Root is not component' unless root.is_a?(Sketchup::ComponentInstance)
    raise 'Child is not group' unless root.definition.entities.all? { |child| child.is_a?(Sketchup::Group) }
    @report['checks'] << 'geometry_and_idempotence'
   end
   def scale(roots,factors)
    @model.start_operation('MH QA Scale',true)
    roots.each { |root| root.transformation=root.transformation*Geom::Transformation.scaling(*factors) }
    @model.commit_operation
   end
   def failure_case(injected)
    before=state(@first); transform=@first.transformation.to_a; definition=@first.definition
    observer=ScaleRedraw.instance_variable_get(:@observers).fetch(@model)
    observer.instance_variable_set(:@applying,true)
    scale([@first],injected ? [1.1,1.1,1.1] : [0.001,1,1])
    observer.instance_variable_set(:@applying,false)
    message_method=UI.method(:messagebox); verify_method=Runtime.method(:verify_result); messages=[]
    begin
     UI.define_singleton_method(:messagebox) { |message,*_args| messages << message; IDOK }
     Runtime.define_singleton_method(:verify_result) { |_root,_plan| raise Core::Error,'Injected verification failure' } if injected
     observer.perform([@first])
    ensure
     UI.define_singleton_method(:messagebox,message_method)
     Runtime.define_singleton_method(:verify_result,verify_method)
    end
    same(before,state(@first),'Rejected Scale did not restore geometry/values')
    raise 'Rejected Scale left transform/definition changed' unless @first.transformation.to_a==transform && @first.definition==definition
    raise 'Missing Scale rejection diagnostic' unless messages.length==1 && observer.last_error
    @report['checks'] << (injected ? 'partial_apply_failure_rolled_back' : 'unsafe_shrink_rolled_back')
   end
   def later
    UI.start_timer(0.2,false) do
     begin
      job=@queue.shift
      job.call if job
      later unless @done
     rescue StandardError=>error
      fail_check(error)
     end
    end
   end
   def fail_check(error)
    @report['error']="#{error.class}: #{error.message}"; @report['backtrace']=error.backtrace.first(6)
    cleanup
   end
   def cleanup
    @done=true
    @model.start_operation('MH QA Cleanup Scale',true)
    @created.each { |root| root.erase! if root.valid? }
    added=@model.definitions.to_a-@defs
    15.times { added.each { |definition| @model.definitions.remove(definition) if definition.valid? && definition.instances.empty? } }
    @model.selection.clear; @selection.each { |entity| @model.selection.add(entity) if entity.valid? }
    @model.commit_operation
    @report['cleanup']=@model.entities.to_a==@roots && added.none?(&:valid?) && @model.selection.to_a==@selection
    @report['ok']=!@report['error'] && @report['cleanup']
    File.write(File.join(__dir__,'..','outputs','native-scale-019.json'),JSON.pretty_generate(@report))
   end
  end
 end
end
MH::ModuleStudio::NativeScaleCheck.start
puts 'Native Scale QA scheduled'
