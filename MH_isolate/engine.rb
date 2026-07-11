# encoding: UTF-8

require 'set'

module MH
  module Isolate
    module Engine
      PREFS = 'MH_isolate'.freeze
      INCLUDE_LOOSE_KEY = 'include_loose_geometry'.freeze
      ZOOM_ON_ISOLATE_KEY = 'zoom_on_isolate'.freeze
      FAST_TOGGLE_CACHE_KEY = 'fast_toggle_cache'.freeze
      TEMP_PREFIX = '__MH_ISOLATE_TMP__'.freeze
      PROTECTED_TAG_NAMES = ['MH_DWG'].freeze
      TOGGLE_DEBOUNCE_SECONDS = 0.12

      @candidate_cache ||= {}

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

        def fast_toggle_cache?
          Sketchup.read_default(PREFS, FAST_TOGGLE_CACHE_KEY, true) == true
        end

        def toggle_fast_toggle_cache
          value = !fast_toggle_cache?
          Sketchup.write_default(PREFS, FAST_TOGGLE_CACHE_KEY, value)
          Sketchup.status_text = "MH Isolate: Fast repeated toggle cache #{value ? 'ON' : 'OFF'}"
          value
        end

        def isolate(model = Sketchup.active_model, selected_entities: nil, ui_selection: nil)
          return false unless model
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          ui_selection = model.selection.to_a if ui_selection.nil?
          selection_to_keep = Array(ui_selection).select { |entity| entity && entity.valid? }
          source_selection = selected_entities.nil? ? model.selection.to_a : Array(selected_entities)
          selected = source_selection.select { |entity| entity && entity.valid? && container?(entity) }

          if State.active?(model)
            data = State.fetch(model)
            current_selection = selected.map { |entity| entity.persistent_id.to_i }.to_set
            isolated_selection = State.isolated_selection_set(model)

            if current_selection.empty? || current_selection == isolated_selection
              if fast_toggle_cache? && Array(data['loose']).empty?
                return true if toggle_cached_isolation(model, data, selection_to_keep)
                if data['soft_unisolated'] == true
                  restored = unisolate(model, silent: true)
                  return false unless restored
                  return isolate(model, selected_entities: selected, ui_selection: selection_to_keep)
                else
                  return unisolate(model)
                end
              else
                return unisolate(model)
              end
            end

            if fast_toggle_cache? && Array(data['loose']).empty?
              switched = switch_cached_target(model, data, selected, selection_to_keep)
              return true if switched
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
          restore_entity_refs = {}
          restore_layer_refs = {}
          selected_records = selected.map do |entity|
            original = entity.layer
            restore_entity_refs[entity.persistent_id.to_i] = entity
            restore_layer_refs[original.persistent_id.to_i] = original if original
            entity_record(entity, original)
          end
          skipped_locked = 0
          skipped_hidden = 0
          skipped_protected = 0
          temp_layer = nil

          model.start_operation('MH Isolate Objects', true)
          begin
            active_entities = model.active_entities
            candidates = container_candidates(model, active_entities).reject { |entity| selected_set.include?(entity) }

            movable = candidates.reject do |entity|
              if protected_tag?(entity)
                skipped_protected += 1
                true
              elsif locked?(entity)
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
                  restore_entity_refs[entity.persistent_id.to_i] = entity
                  restore_layer_refs[original.persistent_id.to_i] = original if original
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
                next if protected_tag?(entity)
                next if pre_hidden?(entity)
                begin
                  entity.hidden = true
                  loose << basic_record(entity)
                  restore_entity_refs[entity.persistent_id.to_i] = entity
                rescue StandardError
                  # Some special/locked drawing elements cannot be changed safely.
                end
              end
            end

            if objects.empty? && loose.empty?
              remove_layer_if_safe(model, temp_layer)
              model.abort_operation
              Sketchup.status_text = status_noop(skipped_locked, skipped_hidden, skipped_protected)
              return false
            end

            data = {
              'active' => true,
              'started_at' => Time.now.to_i,
              'temp_tag_pid' => temp_layer && temp_layer.persistent_id,
              'temp_tag_name' => temp_layer && temp_layer.name,
              'selected_pids' => selected.map { |entity| entity.persistent_id.to_i },
              'ui_selection_pids' => selection_to_keep.map { |entity| entity.persistent_id.to_i },
              'selected_records' => selected_records,
              'soft_unisolated' => false,
              'objects' => objects,
              'loose' => loose
            }
            State.save(model, data)
            selected.each { |entity| restore_entity_refs[entity.persistent_id.to_i] = entity }
            State.cache_restore_refs(model, restore_entity_refs, restore_layer_refs)
            model.commit_operation
            restore_selection(model, selection_to_keep)
            Observers.watch_isolated_entities(model, model.active_entities)
            zoom_to_entities(model, selected) if zoom_on_isolate?
            model.active_view.invalidate
            elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            Sketchup.status_text = status_isolated(selected.length, objects.length, loose.length, skipped_locked, skipped_hidden, skipped_protected, elapsed_ms)
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
                                   Array(data['ui_selection_pids'] || data['selected_pids']).filter_map do |persistent_id|
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

              # If the user reassigned this object while the fast cache was
              # visually unisolated, its current Tag is now authoritative.
              if temp_layer && entity.layer != temp_layer
                restored += 1
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
            model.active_view.invalidate unless silent
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

        # Shared entry point for MH Van and other MH tools. It isolates an
        # explicit entity set without replacing the user's current selection.
        def isolate_entities(model, entities, preserve_selection: true)
          ui_selection = preserve_selection ? model.selection.to_a : Array(entities)
          isolate(model, selected_entities: entities, ui_selection: ui_selection)
        end

        def force_restore(model = Sketchup.active_model)
          unisolate(model, force: true)
        end

        # Used only when SketchUp exits or when a saved model containing temp
        # Tags is opened again. Closing the MH Van dialog does not call this.
        def cleanup_all_temp_caches(model = Sketchup.active_model, silent: true)
          return false unless model

          success = true
          if State.active?(model)
            success = false unless unisolate(model, force: true, silent: silent)
          else
            cleanup_orphan_tags(model)
          end

          if defined?(MH::Van) && MH::Van.respond_to?(:restore_all_fast_hidden_entities)
            van_state = MH::Van.fast_visibility_state(model) if MH::Van.respond_to?(:fast_visibility_state)
            van_records = van_state && van_state['records']
            if van_records.is_a?(Hash) && van_records.any?
              success = false unless MH::Van.restore_all_fast_hidden_entities(model)
            end
          end

          model.active_view.invalidate if model.respond_to?(:active_view)
          Sketchup.status_text = 'MH Isolate: đã tự động restore và xóa temp Tag.' unless silent
          success
        rescue StandardError => error
          warn("MH exit/recovery cleanup failed: #{error.class}: #{error.message}")
          false
        end

        def show_all_tags(model = Sketchup.active_model)
          return false unless model

          # Keep MH Isolate's expensive entity-to-Tag mapping alive. Showing its
          # temp Tag is visually equivalent to unisolate and costs one Tag write.
          cache_retained = false
          active_temp_layer = nil
          if State.active?(model)
            data = State.fetch(model)
            if fast_toggle_cache? && Array(data['loose']).empty?
              cache_retained = show_cached_isolation(model, data)
              active_temp_layer = State.temp_layer(model, data) if cache_retained
            end
            unless cache_retained
              unisolate(model, force: true, silent: true)
              active_temp_layer = nil
            end
          end
          external_cache = coordinate_external_temp_tags(model)

          visible_tags = 0
          visible_folders = 0
          changed_tags = 0
          changed_folders = 0
          skipped_temp_tags = 0

          model.start_operation('MH Show All Tags', true)
          begin
            each_layer_folder(model) do |folder|
              visible_folders += 1
              next if folder.visible?

              folder.visible = true
              changed_folders += 1
            rescue StandardError
              # Some API objects can become invalid while model state changes.
            end

            model.layers.each do |layer|
              if foreign_temp_layer?(layer)
                skipped_temp_tags += 1
                next
              end

              visible_tags += 1
              next if layer.visible?

              layer.visible = true
              changed_tags += 1
            rescue StandardError
              # Keep going; this command should be safe even on odd imported models.
            end

            cleanup_orphan_tags(model, except: active_temp_layer)
            model.commit_operation
            model.active_view.refresh

            external_text = case external_cache
                            when :cached then ', MH Van cache retained'
                            when :restored then ', restored MH Van temp Tags'
                            else ''
                            end
            cache_text = cache_retained ? ', MH Isolate cache retained' : ''
            skipped_text = skipped_temp_tags.positive? ? ", skipped #{skipped_temp_tags} active temp Tags" : ''
            Sketchup.status_text = "MH Isolate: showed all Tags (#{changed_tags}/#{visible_tags} tags, #{changed_folders}/#{visible_folders} folders changed#{cache_text}#{external_text}#{skipped_text})."
            true
          rescue StandardError => error
            model.abort_operation
            warn("MH Show All Tags failed: #{error.class}: #{error.message}")
            Sketchup.status_text = "MH Show All Tags error: #{error.message}"
            false
          end
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

        def invalidate_candidate_cache(model, entities = nil)
          return unless model

          key = model.object_id
          entry = @candidate_cache[key]
          return unless entry
          return if entities && !entry[:entities].equal?(entities)

          @candidate_cache.delete(key)
        end

        def release_model_cache(model)
          @candidate_cache.delete(model.object_id) if model
        end

        def toggle_cached_isolation(model, data, selection_to_keep)
          temp_layer = State.temp_layer(model, data)
          return false unless temp_layer && temp_layer.valid?
          return false unless cached_layout_valid?(model, data, temp_layer)

          showing_all = data['soft_unisolated'] != true
          model.start_operation(showing_all ? 'MH Fast Unisolate' : 'MH Fast Re-Isolate', true)
          begin
            temp_layer.visible = showing_all
            data['soft_unisolated'] = showing_all
            State.save(model, data)
            model.commit_operation
            restore_selection(model, selection_to_keep)
            model.active_view.invalidate
            Sketchup.status_text = showing_all ?
              'MH Isolate: fast unisolate (Tag mapping cached).' :
              'MH Isolate: fast re-isolate from cache.'
            true
          rescue StandardError => error
            model.abort_operation
            State.sync(model)
            warn("MH cached toggle failed: #{error.class}: #{error.message}")
            false
          end
        end

        def show_cached_isolation(model, data)
          temp_layer = State.temp_layer(model, data)
          return false unless temp_layer && temp_layer.valid?
          return true if data['soft_unisolated'] == true && temp_layer.visible?

          model.start_operation('MH Show Cached Isolation', true)
          begin
            temp_layer.visible = true
            data['soft_unisolated'] = true
            State.save(model, data)
            model.commit_operation
            true
          rescue StandardError => error
            model.abort_operation
            State.sync(model)
            warn("MH show cached isolation failed: #{error.class}: #{error.message}")
            false
          end
        end

        def switch_cached_target(model, data, selected, selection_to_keep)
          temp_layer = State.temp_layer(model, data)
          return false unless temp_layer && temp_layer.valid?
          return false unless cached_layout_valid?(model, data, temp_layer)

          hidden_records = Array(data['objects'])
          visible_records = Array(data['selected_records'])
          return false if visible_records.empty?

          hidden_by_pid = hidden_records.to_h { |record| [record['entity_pid'].to_i, record] }
          visible_by_pid = visible_records.to_h { |record| [record['entity_pid'].to_i, record] }
          new_pids = selected.map { |entity| entity.persistent_id.to_i }
          new_pid_set = new_pids.to_set
          old_pid_set = visible_by_pid.keys.to_set
          hide_pids = old_pid_set - new_pid_set
          show_pids = new_pid_set - old_pid_set

          return false unless show_pids.all? { |pid| hidden_by_pid.key?(pid) }
          return false unless new_pids.all? { |pid| hidden_by_pid.key?(pid) || visible_by_pid.key?(pid) }

          hide_items = hide_pids.map do |pid|
            entity = State.entity(model, pid)
            record = visible_by_pid[pid]
            return false unless entity && !locked?(entity)
            return false if protected_tag?(entity) || protected_record?(model, record)
            [entity, record]
          end
          show_items = show_pids.map do |pid|
            entity = State.entity(model, pid)
            record = hidden_by_pid[pid]
            layer = State.layer(model, record['tag_pid'], record['tag_name']) || model.layers[0]
            return false unless entity && layer && !locked?(entity)
            [entity, record, layer]
          end

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          model.start_operation('MH Switch Cached Isolate Target', true)
          begin
            hide_items.each { |entity, _record| entity.layer = temp_layer }
            show_items.each { |entity, _record, layer| entity.layer = layer }
            temp_layer.visible = false

            data['objects'] = hidden_records.reject { |record| show_pids.include?(record['entity_pid'].to_i) } +
                              hide_items.map { |_entity, record| record }
            selected_record_map = visible_by_pid.merge(hidden_by_pid)
            data['selected_records'] = new_pids.filter_map { |pid| selected_record_map[pid] }
            data['selected_pids'] = new_pids
            data['ui_selection_pids'] = selection_to_keep.map { |entity| entity.persistent_id.to_i }
            data['soft_unisolated'] = false
            State.save(model, data)
            model.commit_operation
            restore_selection(model, selection_to_keep)
            zoom_to_entities(model, selected) if zoom_on_isolate?
            model.active_view.invalidate
            elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            Sketchup.status_text = "MH Isolate: switched cached target in #{elapsed} ms."
            true
          rescue StandardError => error
            model.abort_operation
            State.sync(model)
            warn("MH cached target switch failed: #{error.class}: #{error.message}")
            false
          end
        end

        private

        def cached_layout_valid?(model, data, temp_layer)
          return false unless release_protected_cached_objects(model, data, temp_layer)

          hidden_records = Array(data['objects'])
          visible_records = Array(data['selected_records'])
          return false if visible_records.empty?

          mapped_pids = Set.new
          hidden_records.each do |record|
            pid = record['entity_pid'].to_i
            entity = State.entity(model, pid)
            next unless entity
            return false unless entity.layer == temp_layer
            mapped_pids.add(pid)
          end
          visible_records.each { |record| mapped_pids.add(record['entity_pid'].to_i) }

          container_candidates(model, model.active_entities).each do |entity|
            next if mapped_pids.include?(entity.persistent_id.to_i)
            next if protected_tag?(entity) || locked?(entity) || pre_hidden?(entity)
            return false
          end
          true
        rescue StandardError
          false
        end

        def release_protected_cached_objects(model, data, temp_layer)
          hidden_records = Array(data['objects'])
          protected, keep = hidden_records.partition { |record| protected_record?(model, record) }
          return true if protected.empty?

          failed = []
          model.start_operation('MH Release Protected Tags', true)
          begin
            protected.each do |record|
              entity = State.entity(model, record['entity_pid'])
              next unless entity

              target_layer = State.layer(model, record['tag_pid'], record['tag_name'])
              if entity.layer != temp_layer
                next
              elsif locked?(entity) || !target_layer
                failed << record
              else
                entity.layer = target_layer
              end
            rescue StandardError
              failed << record
            end
            data['objects'] = keep + failed
            State.save(model, data)
            model.commit_operation
            failed.empty?
          rescue StandardError
            model.abort_operation
            State.sync(model)
            false
          end
        end

        def container_candidates(model, entities)
          key = model.object_id
          cached = @candidate_cache[key]
          if cached && cached[:entities].equal?(entities)
            return cached[:containers]
          end

          containers = entities.select { |entity| container?(entity) }
          @candidate_cache[key] = { entities: entities, containers: containers }
          containers
        end

        # MH Van also uses temporary Tags for fast row visibility. Restore its
        # persisted entity-to-Tag map before showing normal Tags. If MH Van is
        # unavailable or restoration fails, foreign_temp_layer? keeps those
        # temporary Tags hidden so Show All Tags cannot corrupt its isolation.
        def coordinate_external_temp_tags(model)
          return false unless defined?(MH::Van)

          if MH::Van.respond_to?(:show_all_fast_visibility_cached) &&
             MH::Van.show_all_fast_visibility_cached(model) == true
            return :cached
          end
          if MH::Van.respond_to?(:restore_all_fast_hidden_entities) &&
             MH::Van.restore_all_fast_hidden_entities(model) == true
            return :restored
          end
          false
        rescue StandardError => error
          warn("MH Show All Tags: external cache coordination failed: #{error.class}: #{error.message}")
          false
        end

        def foreign_temp_layer?(layer)
          return false unless layer

          mh_van_marker = layer.get_attribute('MH_Van', 'fast_visibility_tag', false) == true
          mh_van_name = layer.respond_to?(:name) && layer.name.to_s.start_with?('__MH_Van_Hidden__')
          mh_van_marker || mh_van_name
        rescue StandardError
          false
        end

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

        def each_layer_folder(model, &block)
          return enum_for(:each_layer_folder, model) unless block
          layers = model.layers
          return unless layers.respond_to?(:folders)

          each_folder_collection(layers.folders, &block)
        rescue StandardError
          nil
        end

        def each_folder_collection(folders, &block)
          return unless folders

          folders.each do |folder|
            block.call(folder)
            child_folders = if folder.respond_to?(:folders)
                              folder.folders
                            elsif folder.respond_to?(:children)
                              folder.children.select { |child| child.is_a?(Sketchup::LayerFolder) }
                            end
            each_folder_collection(child_folders, &block)
          end
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

        def protected_tag?(entity)
          layer = entity.respond_to?(:layer) ? entity.layer : entity
          protected_layer?(layer)
        rescue StandardError
          false
        end

        def protected_record?(model, record)
          return false unless record
          return true if PROTECTED_TAG_NAMES.any? { |name| record['tag_name'].to_s.casecmp(name).zero? }

          protected_layer?(State.layer(model, record['tag_pid'], record['tag_name']))
        rescue StandardError
          false
        end

        def protected_layer?(layer)
          layer && PROTECTED_TAG_NAMES.any? { |name| layer.name.to_s.casecmp(name).zero? }
        rescue StandardError
          false
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

        def status_noop(locked, hidden, protected)
          "MH Isolate: No visible sibling objects to hide (locked #{locked}, already hidden #{hidden}, protected #{protected})."
        end

        def status_isolated(selected, hidden, loose, locked, already_hidden, protected, elapsed_ms)
          suffix = []
          suffix << "#{loose} loose" if loose.positive?
          suffix << "#{locked} locked skipped" if locked.positive?
          suffix << "#{already_hidden} pre-hidden preserved" if already_hidden.positive?
          suffix << "#{protected} protected Tag skipped" if protected.positive?
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
