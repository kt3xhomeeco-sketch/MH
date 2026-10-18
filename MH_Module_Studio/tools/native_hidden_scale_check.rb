# encoding: UTF-8
raise 'Wrong native test process' unless Process.pid==26424
raise 'Wrong native test model' unless File.basename(Sketchup.active_model.path).downcase=='1.skp'
module MH
 module ModuleStudio
  module NativeHiddenScaleCheck
   extend self
   def start
    @model=Sketchup.active_model; Runtime.ensure_top_level(@model)
    @originals=ScaleRedraw.roots(@model)
    @source=@originals.find { |root| root.name=='Khung' }
    raise 'Actual Khung module missing' unless @source
    @roots=@model.entities.to_a; @defs=@model.definitions.to_a; @selection=@model.selection.to_a
    @original_states=@originals.to_h { |root| [root,state(root)] }
    @created=[]; @done=false; @report={'pid'=>Process.pid,'source_pid'=>@source.persistent_id,'steps'=>[]}
    @model.start_operation('MH QA Copy For Scale Regression',true)
    @copy=@model.active_entities.add_instance(@source.definition,Geom::Transformation.translation([200,0,0])*@source.transformation)
    @source.attribute_dictionary(Reader::DICT).each_pair { |key,value| @copy.set_attribute(Reader::DICT,key,value) }
    @copy.name='QA Scale 020'; @created << @copy
    @model.commit_operation
    @initial=state(@copy); @values=@copy.get_attribute(Reader::DICT,'parameter_values_json')
    @queue=[]
    [[1.1,1,1],[0.5,1,1],[1,0.5,1],[1,1,0.5],[1.8,1.7,1.6],[0.7,0.7,0.7]].each do |factors|
     @queue << lambda { scale(factors) }
     @queue << lambda { verify(factors) }
    end
    @queue << lambda { @scaled=state(@copy); Sketchup.undo }
    @queue << lambda do
     same(@previous,state(@copy),'Single Undo failed')
     Sketchup.send_action('editRedo:')
    end
    @queue << lambda do
     same(@scaled,state(@copy),'Single Redo failed')
     @report['undo_redo']=true
     rule=JSON.parse(@copy.get_attribute(Reader::DICT,'rule_json'))
     Runtime.update_trial(@copy,rule,'abh13iq2kv'=>20)
     actual=snapshot(@copy)
     raise 'Parameter edit after shrink not stable' unless Core.plan(rule,actual,{})['changed_count']==0
     @report['post_scale_parameter_edit']=true
     cleanup
    end
    later
   rescue StandardError=>error
    fail_check(error)
   end
   def snapshot(root)
    rule=JSON.parse(root.get_attribute(Reader::DICT,'rule_json'))
    result,=Reader.live(root,label:'Native repeated shrink',parameter:Runtime.read_parameter(rule,{}))
    result
   end
   def state(root)
    {'snapshot'=>snapshot(root),'transform'=>root.transformation.to_a,'rule'=>root.get_attribute(Reader::DICT,'rule_json'),'values'=>root.get_attribute(Reader::DICT,'parameter_values_json'),'definition'=>root.definition}
   end
   def same(expected,actual,message)
    a=expected['snapshot']; b=actual['snapshot']
    raise message unless expected['rule']==actual['rule'] && expected['values']==actual['values'] && expected['transform']==actual['transform'] && a['parts'].zip(b['parts']).all? { |x,y| x['key']==y['key'] && x['visible']==y['visible'] && Core.bounds_close?(x['bounds'],y['bounds'],0.000001) }
   end
   def scale(factors)
    @previous=state(@copy)
    @model.start_operation('MH QA Repeated Shrink',true)
    @copy.transformation=@copy.transformation*Geom::Transformation.scaling(*factors)
    @model.commit_operation
    @expected=snapshot(@copy)
   end
   def verify(factors)
    actual=snapshot(@copy)
    raise 'Envelope changed' unless Core.bounds_close?(@expected['envelope'],actual['envelope'],0.001)
    hidden=@expected['parts'].select { |part| part['visible']==false }
    raise 'Hidden test coverage missing' unless hidden.length>=2
    hidden.each do |part|
     found=actual['parts'].find { |entry| entry['key']==part['key'] }
     raise "Inactive geometry reset: #{part['name']}" unless found['visible']==false && Core.bounds_close?(part['bounds'],found['bounds'],0.000001)
    end
    rule=JSON.parse(@copy.get_attribute(Reader::DICT,'rule_json'))
    raise 'ATT no longer stable' unless Core.plan(rule,actual,{})['changed_count']==0
    raise 'Saved inputs changed' unless @copy.get_attribute(Reader::DICT,'parameter_values_json')==@values
    @report['steps'] << {'scale'=>factors,'envelope'=>actual['envelope'],'hidden_geometry_retained'=>true,'stable'=>true}
   end
   def later
    UI.start_timer(0.2,false) do
     begin
      @queue.shift&.call
      later unless @done
     rescue StandardError=>error
      fail_check(error)
     end
    end
   end
   def fail_check(error)
    @report||={}; @report['error']="#{error.class}: #{error.message}"; @report['backtrace']=error.backtrace.first(6)
    cleanup
   end
   def cleanup
    @done=true
    @model.start_operation('MH QA Cleanup Repeated Shrink',true)
    @created.each { |root| root.erase! if root.valid? }
    added=@model.definitions.to_a-@defs
    15.times { added.each { |definition| @model.definitions.remove(definition) if definition.valid? && definition.instances.empty? } }
    @model.selection.clear; @selection.each { |entity| @model.selection.add(entity) if entity.valid? }
    @model.commit_operation
    begin
     @original_states.each { |root,original| same(original,state(root),'Original user module modified'); raise 'Original definition changed' unless original['definition']==root.definition }
     @report['originals_unchanged']=true
    rescue StandardError=>error
     @report['error']||=error.message
    end
    @report['cleanup']=@model.entities.to_a==@roots && added.none?(&:valid?) && @model.selection.to_a==@selection
    @report['ok']=!@report['error'] && @report['cleanup'] && @report['originals_unchanged']
    File.write(File.join(__dir__,'..','outputs','native-hidden-scale-020.json'),JSON.pretty_generate(@report))
   end
  end
 end
end
MH::ModuleStudio::NativeHiddenScaleCheck.start
puts 'Actual module copy: repeated shrink regression scheduled'
