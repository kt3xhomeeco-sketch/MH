module MH::ModuleStudio
  module NativeRedrawAbortCheck
    extend self
    def start(source_pid:)
      @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
      @source=@model.find_entity_by_persistent_id(source_pid)
      @source_before=geometry(@source)
      @roots=@model.entities.to_a;@defs=@model.definitions.to_a;@selection=@model.selection.to_a
      @before=@roots.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }
      @report={'status'=>'running','states'=>[],'checks'=>[]}
      @folder=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/redraw-073')
      @model.start_operation('MH QA Redraw private copy',true)
      @copy=@model.entities.add_instance(@source.definition,Geom::Transformation.translation([4000,0,0])*@source.transformation)
      @source.attribute_dictionary(Reader::DICT).each_pair { |key,value| @copy.set_attribute(Reader::DICT,key,value) }
      Runtime.private_tree(@copy)
      ScaleRedraw.apply(@model,[ScaleRedraw.prepare(@copy)])
      @other=@model.entities.add_instance(@copy.definition,Geom::Transformation.translation([100,0,0])*@copy.transformation)
      @copy.attribute_dictionary(Reader::DICT).each_pair { |key,value| @other.set_attribute(Reader::DICT,key,value) }
      @other_before=geometry(@other)
      @model.commit_operation
      ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      @observer=ScaleRedraw.watch(@model)
      @steps=[
        -> { state('repaired baseline');scale([1,1.2,1]) },
        -> { state('simple scale');scale([1.1,1,1]);@model.start_operation('MH QA unrelated attribute',true);@model.set_attribute(Reader::DICT,'qa073',1);@model.commit_operation },
        -> { state('scale followed by commit');@before_abort=geometry(@copy);scale([1,1.1,1]);@model.start_operation('MH QA cancelled inspection',true);@model.abort_operation },
        -> { state('scale followed by unrelated abort');@after_abort=geometry(@copy);Sketchup.undo },
        -> { check(geometry(@copy)==@before_abort,'One Undo restores the preceding Scale geometry and values');Sketchup.send_action('editRedo:') },
        -> { check(geometry(@copy)==@after_abort,'Redo restores the repaired Scale geometry');@cancelled=geometry(@copy);@model.start_operation('MH QA Cancel native Scale',true);@copy.transformation*=Geom::Transformation.scaling(1.1,1.1,1.1);@model.abort_operation },
        -> { check(geometry(@copy)==@cancelled,'Cancelled Scale is not applied or redrawn');state('cancelled Scale');scale([0.9,0.9,0.9]);2.times { @model.start_operation('MH QA repeated cancelled read',true);@model.abort_operation } },
        -> { state('shrink with two unrelated aborts');check(geometry(@other)==@other_before,'Shared definition sibling is unchanged');finish }
      ];later
      puts 'scheduled'
    rescue StandardError=>error
      @report['error']=[error.message,*error.backtrace.first(5)];finish
    end
    def scale(factors)
      @model.start_operation('MH QA Scale',true)
      @copy.transformation*=Geom::Transformation.scaling(ORIGIN,*factors)
      @model.commit_operation
    end
    def state(label)
      job=ScaleRedraw.prepare(@copy)
      snapshot,=Reader.live(@copy,label:'QA',parameter:nil)
      @report['states'] << {'label'=>label,'changed'=>job[2]['changed_count'],'size'=>Core.dimensions(snapshot['envelope']),
        'back'=>snapshot['parts'].find { |part| part['name']=='Hậu' }['bounds'].then { |box| Core.dimensions(box)[1] },'error'=>@observer.last_error}
      check(job[2]['changed_count'].zero? && !@observer.last_error,label+' redraw is complete')
      check((@report['states'].last['back']-8).abs<0.001,label+' retains 8 mm back thickness')
    end
    def geometry(root)
      snapshot,=Reader.live(root,label:'QA geometry',parameter:nil)
      {'frame'=>root.transformation.to_a,'parts'=>snapshot['parts'].map { |part| part.slice('key','bounds','visible') },
        'rule'=>root.get_attribute(Reader::DICT,'rule_json'),'values'=>root.get_attribute(Reader::DICT,'parameter_values_json')}
    end
    def check(condition,label)
      raise label unless condition
      @report['checks'] << label
    end
    def later
      UI.start_timer(0.35,false) do
        begin
          @steps.shift.call;later unless @steps.empty?
        rescue StandardError=>error
          @report['error']=[error.message,*error.backtrace.first(6)];finish
        end
      end
    end
    def finish
      @model.abort_operation
      @model.start_operation('MH QA Redraw cleanup',true)
      (@model.entities.to_a-@roots).each { |entity| entity.erase! if entity.valid? }
      25.times { (@model.definitions.to_a-@defs).each { |definition| @model.definitions.remove(definition) if definition.valid? && definition.instances.empty? } }
      @model.delete_attribute(Reader::DICT,'qa073')
      @model.selection.clear;@selection.each { |entity| @model.selection.add(entity) if entity.valid? }
      @model.commit_operation
      ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      @report['model_retained']=@model.entities.map { |entity| [entity.persistent_id,entity.bounds.min.to_a,entity.bounds.max.to_a] }==@before && @model.definitions.to_a==@defs && geometry(@source)==@source_before
      @report['status']=@report['error'] || !@report['model_retained'] ? 'failed' : 'passed'
      File.write(File.join(@folder,'native.json'),JSON.pretty_generate(@report))
    end
  end
end
