# encoding: UTF-8
module MH
  module ModuleStudio
    # Private fixture only. Never Undo while user geometry differs from the
    # captured source signature, or while a different native Tool is running.
    module NativeUpdateUndoCheck
      extend self
      def start
        @model=Sketchup.active_model;Runtime.ensure_top_level(@model)
        raise 'Another QA/update is running' if @running || UpdateWork.pending?(@model)
        raise 'Return to Select before QA' unless @model.tools.active_tool_name=='SelectionTool'
        @running=true;@report={checks:[]};@root=nil;@definitions=@model.definitions.to_a
        @selection=@model.selection.to_a;@prefs=Sketchup.read_default('MH_Module_Studio','library_v1','');@before=signature
        @links=@model.get_attribute(Reader::DICT,Assembly::KEY)
        @roots_method=ImportLinks.method(:roots);previous=@roots_method
        ImportLinks.define_singleton_method(:roots) { |model| previous.call(model).select { |root,_| NativeUpdateUndoCheck.owned?(root) } }
        source=@model.find_entity_by_persistent_id(1007786);raise 'Missing private-fixture source' unless source&.valid?
        @model.start_operation('MH QA responsive Undo fixture',true)
        @root=@model.entities.add_instance(source.definition,Geom::Transformation.translation([200_000/25.4,0,0])*source.transformation)
        source.attribute_dictionaries.each { |d| d.each_pair { |k,v| @root.set_attribute(d.name,k,v) } }
        @root.delete_attribute(Reader::DICT,ImportLinks::RESERVATIONS)
        @model.set_attribute(Reader::DICT,Assembly::KEY,'[]')
        ScaleRedraw.apply(@model,[ScaleRedraw.prepare(@root)])
        @model.commit_operation
        @frame=@root.transformation.to_a;@sizes=sizes
        reset;scale
        later { check('Scale restores exact physical T',sizes[1],@sizes[1]);undo_repaired }
        {scheduled:true}
      rescue StandardError=>error
        fail_check(error)
      end

      def signature
        @model.entities.reject { |entity| entity==@root }.map { |e| [e.persistent_id,e.bounds.min.to_a,e.bounds.max.to_a] }
      end

      def owned?(root)
        root==@root
      end

      def sizes
        snapshot,=Reader.live(@root,label:'QA Undo result',parameter:nil)
        Core.dimensions(snapshot['envelope'])
      end

      def reset
        ScaleRedraw.watch(@model).reset;Assembly.watch(@model).reset
      end

      def scale
        @model.start_operation('MH QA native Scale',true)
        @root.transformation*=Geom::Transformation.scaling(ORIGIN,1,2,1)
        @model.commit_operation
      end

      def undo_repaired
        Sketchup.undo
        later do
          check('One Undo restores original frame',frame_error,0)
          @sizes.zip(sizes).each_with_index { |(expected,actual),axis| check("Undo restores axis #{axis}",actual,expected) }
          Sketchup.redo
          later do
            check('Redo restores exact T',sizes[1],@sizes[1])
            check('Redo restores scaled root frame',@root.transformation.to_a[5],@frame[5]*2)
            pending_undo
          end
        end
      end

      def pending_undo
        reset;scale
        # Undo before the Scale observer debounce finishes. Its stale job must
        # not later recreate geometry that the user has already undone.
        Sketchup.undo
        later do
          check('Cancelled Scale does not reapply',@root.transformation.to_a[5],@frame[5]*2)
          check('Cancelled Scale keeps T',sizes[1],@sizes[1])
          finish
        end
      end

      def frame_error
        @root.transformation.to_a.zip(@frame).map { |a,b| (a-b).abs }.max
      end

      def later(attempt=0,&action)
        UI.start_timer(0.2,false) do
          begin
            raise 'User geometry/selection changed; stop QA' unless signature==@before && @model.selection.to_a==@selection
            raise 'User started another Tool; stop QA' unless @model.tools.active_tool_name=='SelectionTool'
            if UpdateWork.pending?(@model) || ScaleRedraw.pending?(@model) || Assembly.watch(@model).instance_variable_get(:@pending)
              raise 'Observers did not settle' if attempt>120
              later(attempt+1,&action)
            else
              action.call
            end
          rescue StandardError=>error
            fail_check(error)
          end
        end
      end

      def check(label,actual,expected)
        raise "#{label}: #{actual} != #{expected}" unless (actual-expected).abs<0.02
        @report[:checks] << label
      end

      def fail_check(error)
        @report ||= {checks:[]};@report[:error]=[error.message,*error.backtrace.first(5)]
        finish if @running
        @report
      end

      def finish
        UpdateWork.cancel(@model);@running=false
        @model.start_operation('MH QA responsive Undo cleanup',true)
        @root.erase! if @root&.valid?
        @links ? @model.set_attribute(Reader::DICT,Assembly::KEY,@links) : @model.delete_attribute(Reader::DICT,Assembly::KEY)
        8.times { (@model.definitions.to_a-@definitions).each { |d| @model.definitions.remove(d) if d.valid? && d.instances.empty? } }
        @model.commit_operation
        ImportLinks.define_singleton_method(:roots,@roots_method) if @roots_method
        reset
        @report[:model_retained]=signature==@before && @links==@model.get_attribute(Reader::DICT,Assembly::KEY)
        @report[:selection_retained]=@model.selection.to_a==@selection
        @report[:preferences_retained]=@prefs==Sketchup.read_default('MH_Module_Studio','library_v1','')
        @report[:status]=@report[:error] || !@report[:model_retained] || !@report[:selection_retained] || !@report[:preferences_retained] ? 'failed' : 'passed'
        path=File.join(File.dirname(__dir__),'outputs/update089');FileUtils.mkdir_p(path)
        File.write(File.join(path,'undo.json'),JSON.pretty_generate(@report));@report
      end
    end
  end
end
