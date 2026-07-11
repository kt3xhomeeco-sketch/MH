# encoding: UTF-8

module MH
  module Isolate
    module Observers
      @model_observers ||= {}
      @entities_observers ||= {}

      class ModelStateObserver < Sketchup::ModelObserver
        def onTransactionUndo(model)
          State.sync(model)
          Engine.invalidate_candidate_cache(model)
        end

        def onTransactionRedo(model)
          State.sync(model)
          Engine.invalidate_candidate_cache(model)
        end

        def onDeleteModel(model)
          State.release(model)
          Observers.release(model)
        end
      end

      class IsolatedEntitiesObserver < Sketchup::EntitiesObserver
        def initialize(model)
          @model = model
        end

        def onElementRemoved(_entities, entity_id)
          State.note_removed(@model, entity_id)
          Engine.invalidate_candidate_cache(@model)
        end

        def onElementAdded(entities, _entity)
          Engine.invalidate_candidate_cache(@model, entities)
        end
      end

      class AppStateObserver < Sketchup::AppObserver
        def expectsStartupModelNotifications
          true
        end

        def onNewModel(model)
          Observers.watch_model(model)
        end

        def onOpenModel(model)
          State.sync(model)
          Observers.watch_model(model)
          Observers.schedule_auto_recovery(model)
        end

        def onActivateModel(model)
          State.sync(model)
          Observers.watch_model(model)
          Observers.report_recovery(model)
        end

        def onQuit
          model = Sketchup.active_model
          Engine.cleanup_all_temp_caches(model, silent: true) if model
        rescue StandardError => error
          warn("MH Isolate quit cleanup failed: #{error.class}: #{error.message}")
        end
      end

      class << self
        def install
          @app_observer ||= AppStateObserver.new
          Sketchup.add_observer(@app_observer)
          model = Sketchup.active_model
          watch_model(model)
          schedule_auto_recovery(model)
        end

        def schedule_auto_recovery(model)
          return unless model
          return unless State.active?(model) || State.recovery_needed?(model) || van_recovery_needed?(model)

          @recovery_scheduled ||= {}
          key = model.object_id
          return if @recovery_scheduled[key]

          @recovery_scheduled[key] = true
          UI.start_timer(0.1, false) do
            begin
              restored = Engine.cleanup_all_temp_caches(model, silent: true)
              Sketchup.status_text = restored ?
                'MH Isolate: đã tự động recover temp Tag khi mở file.' :
                'MH Isolate: auto-recovery chưa hoàn tất; hãy dùng Force Restore / Cleanup.'
            ensure
              @recovery_scheduled.delete(key)
            end
          end
        rescue StandardError => error
          @recovery_scheduled.delete(model.object_id) if @recovery_scheduled
          warn("MH Isolate recovery scheduling failed: #{error.class}: #{error.message}")
        end

        def van_recovery_needed?(model)
          return false unless defined?(MH::Van) && MH::Van.respond_to?(:fast_visibility_state)

          state = MH::Van.fast_visibility_state(model)
          records = state && state['records']
          records.is_a?(Hash) && records.any?
        rescue StandardError
          false
        end

        def watch_model(model)
          return unless model
          key = model.object_id
          return if @model_observers.key?(key)
          observer = ModelStateObserver.new
          model.add_observer(observer)
          @model_observers[key] = observer
        end

        def watch_isolated_entities(model, entities)
          key = model.object_id
          old = @entities_observers[key]
          if old
            begin
              old[:entities].remove_observer(old[:observer])
            rescue StandardError
              nil
            end
          end
          observer = IsolatedEntitiesObserver.new(model)
          entities.add_observer(observer)
          @entities_observers[key] = { entities: entities, observer: observer }
        end

        def report_recovery(model)
          return unless State.recovery_needed?(model)
          Sketchup.status_text = 'MH Isolate: Temporary Tag found. Use Force Restore / Cleanup.'
        end

        def release(model)
          return unless model
          key = model.object_id
          Engine.release_model_cache(model)
          @model_observers.delete(key)
          entry = @entities_observers.delete(key)
          return unless entry
          entry[:entities].remove_observer(entry[:observer])
        rescue StandardError
          nil
        end
      end
    end
  end
end
