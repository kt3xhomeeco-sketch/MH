# encoding: UTF-8
require_relative 'component_metadata'
module MH
  module ModuleStudio
    # Adopt native Replace Component results without depending on another plugin.
    module LibraryAdoption
      extend self
      attr_reader :last_error
      def apply(root)
        seed=ComponentMetadata.source(root)
        raise Core::Error,'Component thiếu quy tắc nguồn.' unless seed
        rule=ThicknessSymbols.normalize(DCCustomAttributes.upgrade(Core.rule!(seed[0])))
        values=seed[1];Runtime.private_tree(root)
        root.delete_attribute(Reader::DICT)
        root.set_attribute(Reader::DICT,'parameter_values_json',JSON.generate(values))
        root.set_attribute(Reader::DICT,'formula_envelope_json',seed[2]) if seed[2]
        current,bindings=Reader.live(root,label:'Replace Component',parameter:Runtime.read_parameter(rule,values))
        plan=ScalePlan.plan(rule,current,values)
        Runtime.apply_plan(bindings,plan,rule:rule);Runtime.stamp(root,rule,bindings,plan['target']);Runtime.verify_result(root,plan)
      end
      def watch(model)
        return unless model
        @observers||={}
        @observers[model]||=begin
          observer=Observer.new(model);model.add_observer(observer);observer
        end
      end
      def install
        return unless defined?(Sketchup::ModelObserver)
        unless @installed
          @app=AppObserver.new;Sketchup.add_observer(@app);@installed=true
        end
        watch(Sketchup.active_model)
      end
      if defined?(Sketchup::ModelObserver)
        class Observer < Sketchup::ModelObserver
          def initialize(model)
            super();@model=model;@generation=0;@seen={}
          end
          def candidates
            seen={}
            roots=@model.entities.grep(Sketchup::ComponentInstance).select do |root| # rubocop:disable SketchupSuggestions/ModelEntities -- Observe external replacements at model level.
              key=[root.definition.persistent_id,root.get_attribute(Reader::DICT,'definition_pid'),root.get_attribute(Reader::DICT,'trial',false)]
              changed=@seen[root.persistent_id]!=key;seen[root.persistent_id]=key
              changed && !root.locked? && !AssemblyContainers.managed?(root) && ComponentMetadata.pending?(root)
            end
            @seen=seen;roots
          end
          def onTransactionCommit(_model)
            return if @busy || UpdateWork.active?
            generation=@generation+=1
            UI.start_timer(0,false) { adopt if generation==@generation && Sketchup.active_model.equal?(@model) }
          end
          def adopt
            return unless @model.active_path.nil? || @model.active_path.empty?
            roots=candidates;return if roots.empty?
            @busy=true;@model.start_operation('MH Nhận Quy Tắc Component',true,false,true);operation=true
            roots.each { |root| LibraryAdoption.apply(root) }
            @model.commit_operation;operation=false
            LibraryAdoption.instance_variable_set(:@last_error,nil)
          rescue StandardError=>error
            if operation
              @model.commit_operation;Sketchup.undo
            end
            LibraryAdoption.instance_variable_set(:@last_error,error.message)
            Sketchup.status_text="MH Replace Component: #{error.message}"
          ensure
            @busy=false
            # Runtime.stamp acknowledges each adopted instance. Resetting every
            # root here would lose another module's still-pending Scale/Stretch.
            MH::ModuleStudio.instance_variable_get(:@module_options)&.schedule_refresh unless roots.nil? || roots.empty?
          end
          %i[onTransactionUndo onTransactionRedo onTransactionAbort].each do |event|
            define_method(event) { |_model| @generation+=1;@seen={} unless @busy || UpdateWork.active? }
          end
        end
        class AppObserver < Sketchup::AppObserver
          %i[onNewModel onOpenModel onActivateModel].each do |event|
            define_method(event) { |model| LibraryAdoption.watch(model) }
          end
        end
      end
    end
  end
end
