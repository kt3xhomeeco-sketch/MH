# encoding: UTF-8
require_relative 'runtime'
require_relative 'core'
require_relative 'library_import'

module MH
  module ModuleStudio
    # Absolute reconstruction is deliberately separate from ordinary parameter
    # edits, whose ATT baseline check must continue rejecting damaged geometry.
    module ScaleRedraw
      extend self

      def plan(rule, current, saved,validated: false)
        return UpdateWork.calculate(:scale,rule,UpdateWork.snapshot(current),saved) if UpdateWork.active? && validated
        if @calculations
          @calculations.resize_plan(rule,current,saved,validated:validated)
        else
          validated ? ScalePlan.plan(rule,current,saved,validated:true) : ScalePlan.plan(rule,current,saved)
        end
      end

      # Reuse only portable plans with the exact same rule, fresh geometry and
      # values during one repair. Native bindings are always captured again.
      def with_calculations
        previous=@calculations
        @calculations ||= LibraryImport.new
        yield
      ensure
        @calculations=previous
      end

      def signature(root)
        frame = Frames.scale_frame(root.transformation.to_a)
        [frame[0], frame[5], frame[10]]
      end

      # Stretch edits definitions/child frames without changing the root Scale.
      # Native cached bounds avoid traversing every vertex on every commit.
      def geometry_signature(root, depth=0, cache={})
        return nil unless root.respond_to?(:definition)
        raise Core::Error,'Cấu trúc module quá sâu.' if depth>30
        definition=root.definition
        cache[definition] ||= begin
          box=definition.bounds
          children=definition.entities.select { |child| child.respond_to?(:definition) }.map do |child|
            [child.transformation.to_a.map { |value| value.round(8) },geometry_signature(child,depth+1,cache)]
          end
          [box.min.to_a.map { |value| value.round(8) },box.max.to_a.map { |value| value.round(8) },children]
        end
      end

      def acknowledge(root)
        return if UpdateWork.probing?
        @observers&.fetch(root.model,nil)&.accept_applied(root)
      end

      def pending?(model)
        observer=@observers&.fetch(model,nil)
        observer && observer.pending?
      end

      def roots(model)
        entities = model.entities.to_a # rubocop:disable SketchupSuggestions/ModelEntities -- Watch owned roots even while editing another object.
        if defined?(AssemblyContainers)
          entities += AssemblyContainers.containers(model).flat_map { |component| AssemblyContainers.members(component) }
        end
        entities.select do |entity|
          (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && entity.get_attribute(Reader::DICT, 'trial', false) && !ComponentMetadata.pending?(entity)
        end
      end

      def changed?(before, after)
        return !before.nil? if after.nil?
        before && 3.times.any? { |axis| (before[axis] - after[axis]).abs > 1.0e-7 * [before[axis].abs, after[axis].abs, 1].max }
      end

      def prepare(root)
        raise Core::Error, 'Module đang bị khóa.' if root.locked?
        raw=root.get_attribute(Reader::DICT,'rule_json')
        rule = UpdateWork.active? ? UpdateWork.rule(raw) : @calculations ? @calculations.validated_rule(raw) : Core.rule!(JSON.parse(raw))
        saved = JSON.parse(root.get_attribute(Reader::DICT, 'parameter_values_json', '{}'))
        current, = Reader.live(root, label: 'Sau Scale', parameter: Runtime.read_parameter(rule, saved))
        [root, rule, plan(rule, current, saved,validated:true)]
      end

      def apply(model, jobs)
        # Preflight every module before starting the transparent operation. Keep
        # root transforms (including Scale's anchor, rotation and reflection).
        jobs.each do |root, rule, calculation|
          Runtime.private_tree(root)
          _snapshot, bindings = Reader.live(root, label: 'Tính lại sau Scale', parameter: Runtime.read_parameter(rule, calculation['target']))
          Runtime.apply_plan(bindings, calculation,rule:rule)
          Runtime.stamp_redraw(root, rule, bindings, calculation['target'])
          Runtime.verify_result(root, calculation)
          # This instance is already repaired inside its caller's transaction.
          # Acknowledge only this root; unrelated pending Scale edits still run.
          acknowledge(root)
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

          def pending?
            !Array(@pending).empty?
          end

          def initialize(model)
            super()
            @model = model
            @generation = 0
            reset
          end

          def reset
            @generation += 1
            @pending = []
            @active_path = @model.active_path&.map(&:persistent_id)
            @geometry = {}
            @scales = ScaleRedraw.roots(@model).to_h do |root|
              @geometry[root.persistent_id] = ScaleRedraw.geometry_signature(root)
              [root.persistent_id, ScaleRedraw.signature(root)]
            rescue Core::Error
              [root.persistent_id, nil]
            end
          end

          def onTransactionCommit(_model)
            return if @applying || UpdateWork.active?
            generation = @generation += 1
            candidates = ScaleRedraw.roots(@model).select do |root|
              after = begin
                ScaleRedraw.signature(root)
              rescue Core::Error
                nil
              end
              ScaleRedraw.changed?(@scales[root.persistent_id], after) ||
                @geometry.key?(root.persistent_id) && @geometry[root.persistent_id]!=ScaleRedraw.geometry_signature(root)
            end
            return reset if candidates.empty?
            @pending = candidates
            # Never mutate geometry from a transaction observer callback.
            # MH_stretch may commit Scale, synchronize DC dimensions, then
            # redraw DCs in follow-up operations. Wait for that burst to settle
            # before reconstructing ATT from intermediate geometry.
            UI.start_timer(0.12, false) { redraw(candidates, generation) }
          end

          def accept_applied(root)
            @scales[root.persistent_id] = ScaleRedraw.signature(root)
            @geometry[root.persistent_id] = ScaleRedraw.geometry_signature(root)
          end

          def redraw(candidates, generation)
            return if generation != @generation || !Sketchup.active_model.equal?(@model)
            return unless UpdateWork.valid_context?(candidates)
            done=lambda do |status,error|
              @last_error=error&.message if status==:error
              Sketchup.status_text="MH: #{error.message}" if error
              reset if %i[done error].include?(status)
              MH::ModuleStudio.instance_variable_get(:@module_options)&.schedule_refresh
            end
            UpdateWork.submit(@model,key: :scale,complete:done) { perform(candidates) }
          end

          def perform(candidates)
            ScaleRedraw.with_calculations { perform_update(candidates) }
          end

          def perform_update(candidates)
            @applying = true
            Runtime.ensure_assembly_context(@model)
            jobs = candidates.map { |root| ScaleRedraw.prepare(root) }
            @last_error = nil
            # A successful Redo already contains the repair. Do not add another
            # operation or destroy the remaining Redo history in that case.
            return if jobs.all? { |root, _rule, calculation| calculation['changed_count'].zero? && !GuideGeometry.pending?(root,calculation) }
            if defined?(Assembly) && (!Assembly.records(@model).empty? || !ImportLinks.reservation_fingerprint(@model).empty?)
              coordinated=true
              Assembly.watch(@model).repair_scaled(candidates)
              @last_error=nil
              return
            end
            @model.start_operation('MH Tính Lại Sau Scale', true, false, !UpdateWork.probing?)
            operation = true
            ScaleRedraw.apply(@model, jobs)
            UpdateWork.commit(@model)
            operation = false
            @last_error = nil
            Sketchup.status_text = 'MH: Đã tính lại module sau Scale.'
          rescue UpdateWork::Deferred,UpdateWork::Prepared
            @model.abort_operation if operation
            raise
          rescue StandardError => error
            if UpdateWork.probing?
              @model.abort_operation if operation
              raise
            end
            # Aborting a transparent operation can corrupt its chain. Commit,
            # then undo the combined Scale + redraw, restoring all originals.
            @model.commit_operation if operation
            Sketchup.undo unless coordinated
            @last_error = "Không tính lại được sau Scale; đã hoàn tác Scale. #{error.message}"
            Sketchup.status_text = @last_error
            UI.messagebox(@last_error)
          ensure
            @applying = false
            reset unless UpdateWork.active?
            MH::ModuleStudio.instance_variable_get(:@module_options)&.schedule_refresh unless UpdateWork.active?
          end

          def onTransactionRedo(model)
            onTransactionCommit(model)
          end

          def onTransactionAbort(model)
            # A cancelled temporary operation can follow an already committed
            # Scale before its timer runs. Only acknowledge restored transforms;
            # keep the earlier Scale pending against the previous baseline.
            return if @applying || UpdateWork.active?
            Array(@pending).empty? ? reset : onTransactionCommit(model)
          end

          def onTransactionUndo(model)
            return if @applying || UpdateWork.active?
            # abort_operation also reports Undo in SketchUp. Recheck only if a
            # committed Scale was already waiting; completed Undo keeps its
            # original geometry and Redo chain untouched.
            Array(@pending).empty? ? reset : onTransactionCommit(model)
          end

          def onActivePathChanged(model)
            return if @applying || UpdateWork.active?
            # SketchUp also emits this while aborting a temporary operation,
            # even if the edit context did not change at all.
            if !Array(@pending).empty? && model.active_path&.map(&:persistent_id) == @active_path
              onTransactionCommit(model)
            else
              reset
            end
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
