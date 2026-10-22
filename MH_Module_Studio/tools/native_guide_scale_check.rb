# encoding: UTF-8
module MH
  module ModuleStudio
    module NativeGuideScaleCheck
      extend self
      def start(source_pid:,verify: false,guide_only: false)
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model);@source=@model.find_entity_by_persistent_id(source_pid)
        raise 'Source missing' unless Assembly.container?(@source)
        @before=@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] };@definitions=@model.definitions.to_a
        @source_before=signature(@source);@verify=verify;@guide_only=guide_only;@report={'status'=>'running','states'=>[]}
        @model.start_operation('MH QA Guide Scale copy',true)
        @copy=@model.entities.add_instance(@source.definition,Geom::Transformation.translation([100_000/25.4,0,0])*@source.transformation)
        @source.attribute_dictionaries.each { |d| d.each_pair { |k,v| @copy.set_attribute(d.name,k,v) } }
        Runtime.private_tree(@copy)
        if guide_only
          rule=JSON.parse(@copy.get_attribute(Reader::DICT,'rule_json'));values=JSON.parse(@copy.get_attribute(Reader::DICT,'parameter_values_json'))
          _snapshot,bindings=Reader.live(@copy,label:'QA',parameter:Runtime.read_parameter(rule,values));Runtime.stamp(@copy,rule,bindings,values)
        else
          ScaleRedraw.apply(@model,[ScaleRedraw.prepare(@copy)])
        end
        @owned_definitions=@model.definitions.to_a-@definitions
        @model.commit_operation
        ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
        state(@guide_only ? 'legacy baseline' : 'baseline')
        scale(@guide_only ? 1.1 : 2.0,axis:@guide_only ? 0 : 1)
        UI.start_timer(0.4,false) do
          begin
            state(@guide_only ? 'after automatic X guide-only repair' : 'after automatic Y x2')
            if @verify && !@guide_only
              scale(0.7)
              UI.start_timer(0.4,false) do
                begin
                  state('after automatic Y x0.7');edit_T;finish
                rescue StandardError=>error
                  @report['error']=[error.message,*error.backtrace.first(6)];finish
                end
              end
            else
              finish
            end
          rescue StandardError=>error
            @report['error']=[error.message,*error.backtrace.first(6)];finish
          end
        end
        {scheduled:true,pid:Process.pid}
      rescue StandardError=>error
        @report||={};@report['error']=[error.message,*error.backtrace.first(6)];finish
      end
      def signature(root)
        rule=JSON.parse(root.get_attribute(Reader::DICT,'rule_json'));values=JSON.parse(root.get_attribute(Reader::DICT,'parameter_values_json'))
        snapshot,bindings=Reader.live(root,label:'QA',parameter:Runtime.read_parameter(rule,values))
        guides=bindings.flat_map { |key,b| b[:entity].definition.entities.grep(Sketchup::ConstructionPoint).map { |p| [key,p.position.to_a] } }
        [root.transformation.to_a,snapshot['parts'].map { |p| [p['key'],p['bounds']] },guides]
      end
      def scale(factor,axis: 1)
        @model.start_operation('MH QA Scale Y',true)
        factors=[1,1,1];factors[axis]=factor
        @copy.transformation*=Geom::Transformation.scaling(*factors)
        @model.commit_operation
      end
      def state(label)
        rule=JSON.parse(@copy.get_attribute(Reader::DICT,'rule_json'));values=JSON.parse(@copy.get_attribute(Reader::DICT,'parameter_values_json'))
        snapshot,=Reader.live(@copy,label:'QA',parameter:Runtime.read_parameter(rule,values))
        box=AssemblyEnvelope.bounds(@copy);frame=Frames.scale_frame(@copy.transformation.to_a)
        native=Core.dimensions(box).each_with_index.map { |v,i| v*frame[[0,5,10][i]] }
        solid=Core.dimensions(snapshot['parts'].find { |p| p['face_count']>0 }['bounds'])
        @report['states'] << {label:label,native_bounds:native,solid:solid,pending:ScaleRedraw.watch(@model).instance_variable_get(:@pending)&.map(&:persistent_id),error:ScaleRedraw.watch(@model).last_error}
        raise 'Automatic T is incorrect' unless (solid[1]-values['a0van']).abs<0.02
        raise 'Guide extends native Y bounds' if @verify && label!='legacy baseline' && (native[1]-values['a0van']).abs>0.02
      end
      def edit_T
        rule=JSON.parse(@copy.get_attribute(Reader::DICT,'rule_json'));rows=Parametric.variables(rule)
        rows.find { |row| row['binding']=='a0van' }['value']=20
        rule=Parametric.edit_variables(rule,rows)
        @model.start_operation('MH QA T1 edit',true);Runtime.apply_trial_update(@copy,rule,Parametric.targets(rule));@model.commit_operation
        state('T1=20 with guide points')
        guides=signature(@copy)[2]
        2.times do
          @model.start_operation('MH QA Redraw repeat',true);ScaleRedraw.apply(@model,[ScaleRedraw.prepare(@copy)]);@model.commit_operation
        end
        raise 'Guide moves again on unchanged redraw' unless guides==signature(@copy)[2]
        state('two unchanged redraws')
      end
      def finish
        @model.start_operation('MH QA Guide cleanup',true)
        @copy.erase! if @copy && @copy.valid?
        10.times { Array(@owned_definitions).each { |d| @model.definitions.remove(d) if d.valid? && d.instances.empty? } }
        @model.commit_operation;ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
        @report['source_retained']=signature(@source)==@source_before
        @report['model_retained']=@before==@model.entities.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
        @report['status']=@report['error'] || !@report['source_retained'] || !@report['model_retained'] ? 'failed' : 'passed'
        directory=File.join(File.dirname(Panel.instance_method(:show).source_location.first),'outputs/guide086');FileUtils.mkdir_p(directory)
        File.write(File.join(directory,@guide_only ? 'guide-only.json' : @verify ? 'fixed.json' : 'baseline.json'),JSON.pretty_generate(@report))
      end
    end
  end
end
