# encoding: UTF-8

require 'set'

module MH
  module Isolate
    module Engine
      PREFS = 'MH_isolate'.freeze
      INCLUDE_LOOSE_KEY = 'include_loose_geometry'.freeze
      ZOOM_ON_ISOLATE_KEY = 'zoom_on_isolate'.freeze
      TEMP_PREFIX = '__MH_ISOLATE_TMP__'.freeze
      TOGGLE_DEBOUNCE_SECONDS = 0.12

      class << self
        def include_loose_geometry?
          Sketchup.read_default(PREFS, INCLUDE_LOOSE_KEY, false) == true
        end

        def toggle_include_loose_geometry
          value = !include_loose_geometry?
          Sketchup.write_default(PREFS, INCLUDE_LOOSE_KEY, value)
          Sketchup.status_text = "MH Isolate: Include loose geometry #{value ? 'ON (slower)' : 'OFF'}"
          value
        end

        def zoom_on_isolate?
          Sketchup.read_default(PREFS, ZOOM_ON_ISOLATE_KEY, true) == true
        end

        def toggle_zoom_on_isolate
          value = !zoom_on_isolate?
          Sketchup.write_default(PREFS, ZOOM_ON_ISOLATE_KEY, value)
          Sketchup.status_text = "MH Isolate: Zoom on isolate #{value ? 'ON' : 'OFF'}"
          value
        end

        def isolate(model = Sketchup.active_model)
          return false unless model
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          selected = model.selection.to_a.select { |entity| container?(entity) }

          if State.active?(model)
            current_selection = selected.map { |entity| entity.persistent_id.to_i }.to_set
            isolated_selection = State.isolated_selection_set(model)

            if current_selection.empty? || current_selection == isolated_selection
              return unisolate(model)
            end

            restored = unisolate(model, silent: true)
            unless restored
              Sketchup.status_text = 'MH Isolate: Could not fully restore the previous isolation.'
              return false
            end
            selected.select!(&:valid?)
          end

          if selected.empty?
            Sketchup.status_text = 'MH Isolate: Select at least one Group or Component.'
            return false
          end

          selected_set = selected.to_set
          objects = []
          loose = []
          skipped_locked = 0
          skipped_hidden = 0
          temp_layer = nil

          model.start_operation('MH Isolate Objects', true)
          begin
            candidates = model.active_entities.select do |entity|
              container?(entity) && !selected_set.include?(entity)
            end

            movable = candidates.reject do |entity|
              if locked?(entity)
                skipped_locked += 1
                true
              elsif pre_hidden?(entity)
                skipped_hidden += 1
                true
              else
                false
              end
            end

            unless movable.empty?
              temp_layer = create_temp_layer(model)
              movable.each do |entity|
                original = entity.layer
                begin
                  entity.layer = temp_layer
                  objects << entity_record(entity, original)
                rescue StandardError
                  skipped_locked += 1
                end
              end
              temp_layer.visible = false unless objects.empty?
            end

            if include_loose_geometry?
              model.active_entities.each do |entity|
                next unless loose_geometry?(entity)
                next if model.selection.include?(entity)
                next if pre_hidden?(entity)
                begin
                  entity.hidden = true
                  loose << basic_record(entity)
                rescue StandardError
                  # Some special/locked drawing elements cannot be changed safely.
                end
              end
            end

            if objects.empty? && loose.empty?
              remove_layer_if_safe(model, temp_layer)
              model.abort_operation
              Sketchup.status_text = status_noop(skipped_locked, skipped_hidden)
              return false
            end

            data = {
              'active' => true,
              'started_at' => Time.now.to_i,
              'temp_tag_pid' => temp_layer && temp_layer.persistent_id,
              'temp_tag_name' => temp_layer && temp_layer.name,
              'selected_pids' => selected.map { |entity| entity.persistent_id.to_i },
              'objects' => objects,
              'loose' => loose
            }
            State.save(model, data)
            model.commit_operation
            restore_selection(model, selected)
            Observers.watch_isolated_entities(model, model.active_entities)
            zoom_to_entities(model, selected) if zoom_on_isolate?
            model.active_view.refresh
            elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            Sketchup.status_text = status_isolated(selected.length, objects.length, loose.length, skipped_locked, skipped_hidden, elapsed_ms)
            true
          rescue StandardError => error
            model.abort_operation
            State.sync(model)
            warn("MH Isolate failed: #{error.class}: #{error.message}")
            Sketchup.status_text = "MH Isolate error: #{error.message}"
            false
          end
        end

        def unisolate(model = Sketchup.active_model, force: false, silent: false)
          return false unless model
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = State.fetch(model, reload: true)
          unless data
            cleanup_orphan_tags(model) if force
            Sketchup.status_text = 'MH Isolate: Nothing to restore.' unless silent
            return false
          end


          selection_to_restore = if silent
                                   model.selection.to_a
                                 else
                                   Array(data['selected_pids']).filter_map do |persistent_id|
                                     State.entity(model, persistent_id)
                                   end
                                 end

          restored = 0
          deleted = 0
          pending = []
          loose_pending = []
          temp_layer = State.temp_layer(model, data)

          model.start_operation(force ? 'MH Force Restore' : 'MH Unisolate Objects', true)
          begin
            temp_layer.visible = true if temp_layer && temp_layer.valid?

            Array(data['objects']).each do |record|
              entity = State.entity(model, record['entity_pid'])
              unless entity
                deleted += 1
                next
              end

              target_layer = State.layer(model, record['tag_pid'], record['tag_name']) || model.layers[0]
              begin
                if locked?(entity)
                  pending << record
                else
                  entity.layer = target_layer
                  restored += 1
                end
              rescue StandardError
                pending << record
              end
            end

            Array(data['loose']).each do |record|
              entity = State.entity(model, record['entity_pid'])
              unless entity
                deleted += 1
                next
              end
              begin
                entity.hidden = false
                restored += 1
              rescue StandardError
                loose_pending << record
              end
            end

            if pending.empty? && loose_pending.empty?
              State.clear(model)
              remove_layer_if_safe(model, temp_layer)
            else
              data['objects'] = pending
              data['loose'] = loose_pending
              State.save(model, data)
            end

            cleanup_orphan_tags(model, except: temp_layer) if force
            model.commit_operation
            restore_selection(model, selection_to_restore)
            model.active_view.refresh unless silent
            elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            unless silent
              Sketchup.status_text = status_restored(restored, deleted, pending.length + loose_pending.length, elapsed_ms)
            end
            pending.empty? && loose_pending.empty?
          rescue StandardError => error
            model.abort_operation
            State.sync(model)
            warn("MH Unisolate failed: #{error.class}: #{error.message}")
            Sketchup.status_text = "MH Unisolate error: #{error.message}"
            false
          end
        end

        def toggle(model = Sketchup.active_model)
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          last = @last_toggle_monotonic
          if last && now >= last && (now - last) < TOGGLE_DEBOUNCE_SECONDS
            return false
          end

          @last_toggle_monotonic = now
          isolate(model)
        end

        def force_restore(model = Sketchup.active_model)
          unisolate(model, force: true)
        end

        def cleanup_orphan_tags(model, except: nil)
          State.orphan_temp_layers(model).each do |layer|
            next if except && layer == except
            begin
              layer.visible = true
              remove_layer_if_safe(model, layer)
            rescue StandardError
              # Leave it visible; this is safer than hiding user geometry forever.
            end
          end
        end

        private

        def restore_selection(model, entities)
          valid = Array(entities).select { |entity| entity && entity.valid? }
          model.selection.clear
          model.selection.add(valid) unless valid.empty?
        rescue StandardError
          nil
        end

        def zoom_to_entities(model, entities)
          valid = Array(entities).select { |entity| entity && entity.valid? }
          model.active_view.zoom(valid) unless valid.empty?
        rescue StandardError => error
          warn("MH Isolate zoom failed: #{error.class}: #{error.message}")
        end

        def container?(entity)
          entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end

        def loose_geometry?(entity)
          entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::Face)
        end

        def locked?(entity)
          entity.respond_to?(:locked?) && entity.locked?
        rescue StandardError
          true
        end

        def pre_hidden?(entity)
          entity.hidden? || !layer_effectively_visible?(entity.layer)
        rescue StandardError
          true
        end

        def layer_effectively_visible?(layer)
          return true unless layer
          return false unless layer.visible?

          folder = layer.respond_to?(:folder) ? layer.folder : nil
          while folder
            return false unless folder.visible?
            parent = folder.respond_to?(:parent) ? folder.parent : nil
            folder = parent.is_a?(Sketchup::LayerFolder) ? parent : nil
          end
          true
        end

        def basic_record(entity)
          {
            'entity_pid' => entity.persistent_id,
            'entity_id' => entity.entityID
          }
        end

        def entity_record(entity, layer)
          basic_record(entity).merge(
            'tag_pid' => layer.persistent_id,
            'tag_name' => layer.name
          )
        end

        def create_temp_layer(model)
          name = "#{TEMP_PREFIX}#{Time.now.to_i}_#{rand(1_000_000)}"
          layer = model.layers.add(name)
          layer.visible = true
          layer.set_attribute(State::DICT, State::TAG_MARKER_KEY, true)
          layer
        end

        def remove_layer_if_safe(model, layer)
          return unless layer && layer.valid?
          return unless State.marked_temp_layer?(layer)
          # Never delete geometry during cleanup. If a failed restore left an
          # entity on this Tag, SketchUp safely moves it to Untagged.
          model.layers.remove(layer, false)
        rescue StandardError
          layer.visible = true if layer && layer.valid?
        end

        def status_noop(locked, hidden)
          "MH Isolate: No visible sibling objects to hide (locked #{locked}, already hidden #{hidden})."
        end

        def status_isolated(selected, hidden, loose, locked, already_hidden, elapsed_ms)
          suffix = []
          suffix << "#{loose} loose" if loose.positive?
          suffix << "#{locked} locked skipped" if locked.positive?
          suffix << "#{already_hidden} pre-hidden preserved" if already_hidden.positive?
          extra = suffix.empty? ? '' : " | #{suffix.join(', ')}"
          "MH Isolate: #{selected} selected, #{hidden} objects hidden in #{elapsed_ms} ms#{extra}"
        end

        def status_restored(restored, deleted, pending, elapsed_ms)
          text = "MH Isolate: restored #{restored} in #{elapsed_ms} ms"
          text += ", ignored #{deleted} deleted" if deleted.positive?
          text += ", #{pending} locked/failed still pending" if pending.positive?
          text
        end
      end
    end
  end
end
