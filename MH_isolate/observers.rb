# encoding: UTF-8

module MH
  module Isolate
    module Observers
      @model_observers = {}
      @entities_observers = {}

      class ModelStateObserver < Sketchup::ModelObserver
        def onTransactionUndo(model)
          State.sync(model)
        end

        def onTransactionRedo(model)
          State.sync(model)
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
          Observers.report_recovery(model)
        end

        def onActivateModel(model)
          State.sync(model)
          Observers.watch_model(model)
          Observers.report_recovery(model)
        end
      end

      class << self
        def install
          @app_observer ||= AppStateObserver.new
          Sketchup.add_observer(@app_observer)
          watch_model(Sketchup.active_model)
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
