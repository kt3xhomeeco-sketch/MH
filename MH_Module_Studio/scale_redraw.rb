# encoding: UTF-8
require_relative 'runtime'
require_relative 'core'

module MH
  module ModuleStudio
    # Absolute reconstruction is deliberately separate from ordinary parameter
    # edits, whose ATT baseline check must continue rejecting damaged geometry.
    module ScaleRedraw
      extend self

      def plan(rule, current, saved)
        ScalePlan.plan(rule, current, saved)
      end

      def signature(root)
        frame = Frames.scale_frame(root.transformation.to_a)
        [frame[0], frame[5], frame[10]]
      end

      def roots(model)
        entities = model.entities.to_a # rubocop:disable SketchupSuggestions/ModelEntities -- Watch owned roots even while editing another object.
        if defined?(AssemblyContainers)
          entities += AssemblyContainers.containers(model).flat_map { |component| AssemblyContainers.members(component) }
        end
        entities.select do |entity|
          (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && entity.get_attribute(Reader::DICT, 'trial', false)
        end
      end

      def changed?(before, after)
        return !before.nil? if after.nil?
        before && 3.times.any? { |axis| (before[axis] - after[axis]).abs > 1.0e-7 * [before[axis].abs, after[axis].abs, 1].max }
      end

      def prepare(root)
        raise Core::Error, 'Module đang bị khóa.' if root.locked?
        rule = Core.rule!(JSON.parse(root.get_attribute(Reader::DICT, 'rule_json')))
        saved = JSON.parse(root.get_attribute(Reader::DICT, 'parameter_values_json', '{}'))
        current, = Reader.live(root, label: 'Sau Scale', parameter: Runtime.read_parameter(rule, saved))
        [root, rule, plan(rule, current, saved)]
      end

      def apply(model, jobs)
        # Preflight every module before starting the transparent operation. Keep
        # root transforms (including Scale's anchor, rotation and reflection).
        jobs.each do |root, rule, calculation|
          Runtime.private_tree(root)
          _snapshot, bindings = Reader.live(root, label: 'Tính lại sau Scale', parameter: Runtime.read_parameter(rule, calculation['target']))
          Runtime.apply_plan(bindings, calculation)
          Runtime.stamp(root, rule, bindings, calculation['target'])
          Runtime.verify_result(root, calculation)
          # This instance is already repaired inside its caller's transaction.
          # Acknowledge only this root; unrelated pending Scale edits still run.
          @observers&.fetch(model,nil)&.accept_applied(root)
        end
        model.active_view.invalidate
      end

      def install
        return unless defined?(Sketchup::ModelObserver)
        @app_observer ||= ScaleAppObserver.new
        Sketchup.add_observer(@app_observer) unless @installed
        @installed = true
        watch(Sketchup.active_model)
      end

      def watch(model, rebind: false)
        @observers ||= {}
        if rebind && (previous=@observers.delete(model))
          previous.reset
          model.remove_observer(previous)
        end
        @observers[model] ||= begin
          observer = ScaleModelObserver.new(model)
          model.add_observer(observer)
          observer
        end
      end

      if defined?(Sketchup::ModelObserver)
        class ScaleModelObserver < Sketchup::ModelObserver
          attr_reader :last_error

          def initialize(model)
            super()
            @model = model
            @generation = 0
            reset
          end

          def reset
            @generation += 1
            @scales = ScaleRedraw.roots(@model).to_h do |root|
              [root.persistent_id, ScaleRedraw.signature(root)]
            rescue Core::Error
              [root.persistent_id, nil]
            end
          end

          def onTransactionCommit(_model)
            return if @applying
            generation = @generation += 1
            candidates = ScaleRedraw.roots(@model).select do |root|
              after = begin
                ScaleRedraw.signature(root)
              rescue Core::Error
                nil
              end
              ScaleRedraw.changed?(@scales[root.persistent_id], after)
            end
            return reset if candidates.empty?
            # Never mutate geometry from a transaction observer callback.
            UI.start_timer(0, false) { redraw(candidates, generation) }
          end

          def accept_applied(root)
            @scales[root.persistent_id] = ScaleRedraw.signature(root)
          end

          def redraw(candidates, generation)
            return if generation != @generation || !Sketchup.active_model.equal?(@model)
            perform(candidates)
          end

          def perform(candidates)
            @applying = true
            Runtime.ensure_assembly_context(@model)
            jobs = candidates.map { |root| ScaleRedraw.prepare(root) }
            @last_error = nil
            # A successful Redo already contains the repair. Do not add another
            # operation or destroy the remaining Redo history in that case.
            return if jobs.all? { |_root, _rule, calculation| calculation['changed_count'].zero? }
            @model.start_operation('MH Tính Lại Sau Scale', true, false, true)
            operation = true
            ScaleRedraw.apply(@model, jobs)
            @model.commit_operation
            operation = false
            @last_error = nil
            Sketchup.status_text = 'MH: Đã tính lại module sau Scale.'
          rescue StandardError => error
            # Aborting a transparent operation can corrupt its chain. Commit,
            # then undo the combined Scale + redraw, restoring all originals.
            @model.commit_operation if operation
            Sketchup.undo
            @last_error = "Không tính lại được sau Scale; đã hoàn tác Scale. #{error.message}"
            Sketchup.status_text = @last_error
            UI.messagebox(@last_error)
          ensure
            @applying = false
            reset
            MH::ModuleStudio.instance_variable_get(:@module_options)&.schedule_refresh
          end

          def onTransactionRedo(model)
            onTransactionCommit(model)
          end

          %i[onTransactionUndo onTransactionAbort onActivePathChanged].each do |event|
            define_method(event) { |_model| reset unless @applying }
          end
        end

        class ScaleAppObserver < Sketchup::AppObserver
          %i[onNewModel onOpenModel].each do |event|
            define_method(event) { |model| ScaleRedraw.watch(model,rebind:true) }
          end
          def onActivateModel(model)
            ScaleRedraw.watch(model)
          end
        end
      end
    end
  end
end
