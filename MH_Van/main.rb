# encoding: UTF-8

require 'sketchup.rb'
require 'json'
require 'digest'
require File.join(__dir__, 'geometry_cache')
begin
  require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
rescue StandardError
end
begin
  require File.join(__dir__, 'native_bridge')
rescue StandardError
end

module MH
  module Van
    PLUGIN_NAME = 'MH Ván'.freeze
    DICT = 'MH_Van'.freeze
    ATTR_CODE = 'material_code'.freeze
    ATTR_ORIGINAL_CODE = 'original_material_code'.freeze
    ATTR_COLOR = 'color'.freeze
    ATTR_TWO_FACE = 'two_face'.freeze
    FAST_VISIBILITY_KEY = 'fast_visibility_tag_mode'.freeze
    FAST_VISIBILITY_STATE_KEY = 'fast_visibility_state'.freeze
    FAST_VISIBILITY_TAG_MARKER_KEY = 'fast_visibility_tag'.freeze
    FAST_VISIBILITY_TAG_PREFIX = '__MH_Van_Hidden__'.freeze
    PROTECTED_VISIBILITY_TAG_NAMES = ['MH_DWG'].freeze
    GROUP_CODE_SHOW_THICKNESS_KEY = 'group_code_show_thickness'.freeze
    GROUP_CODE_SHOW_PAINT_KEY = 'group_code_show_paint'.freeze
    GROUP_CODE_PAINT_TOKEN = 'SON'.freeze
    AUTO_REFRESH_SECONDS = 0.08

    if defined?(Sketchup::EntityObserver)
      class EntityChangeObserver < Sketchup::EntityObserver
        def onChangeEntity(entity)
          MH::Van.mark_dirty_entity(entity)
        end

        def onEraseEntity(entity)
          MH::Van.request_full_refresh
        end
      end
    end

    if defined?(Sketchup::MaterialsObserver)
      class MaterialsChangeObserver < Sketchup::MaterialsObserver
        def onMaterialChange(_materials, material)
          MH::Van.mark_dirty_material(material)
        end

        def onMaterialRemove(_materials, material)
          MH::Van.mark_dirty_material(material)
        end
      end
    end

    if defined?(Sketchup::ModelObserver)
      class ModelChangeObserver < Sketchup::ModelObserver
        def onTransactionCommit(model)
          MH::Van.mark_selected_records_dirty(model)
        end

        def onTransactionUndo(model)
          MH::Van.invalidate_model_caches(model)
        end

        def onTransactionRedo(model)
          MH::Van.invalidate_model_caches(model)
        end
      end
    end

    if defined?(Sketchup::LayersObserver)
      class VisibilityLayersObserver < Sketchup::LayersObserver
        def onLayerChanged(_layers, layer)
          MH::Van.mark_visibility_dirty(layer)
        end

        def onLayerFolderChanged(_layers, _folder)
          MH::Van.mark_visibility_dirty
        end

        def onParentFolderChanged(_layers, layer)
          MH::Van.mark_visibility_dirty(layer)
        end

        def onLayerRemoved(_layers, _layer)
          MH::Van.mark_visibility_dirty
        end
      end
    end

    if defined?(Sketchup::EntitiesObserver)
      class DefinitionEntitiesChangeObserver < Sketchup::EntitiesObserver
        def onElementAdded(*args)
          MH::Van.mark_dirty_definition_entities(args.find { |item| item.is_a?(Sketchup::Entities) })
          MH::Van.request_full_refresh if args.any? { |item| item.is_a?(Sketchup::Group) || item.is_a?(Sketchup::ComponentInstance) }
        end

        def onElementModified(*args)
          MH::Van.mark_dirty_definition_entities(args.find { |item| item.is_a?(Sketchup::Entities) })
          args.each { |item| MH::Van.mark_dirty_entity(item) if item.is_a?(Sketchup::Group) || item.is_a?(Sketchup::ComponentInstance) }
        end

        def onElementRemoved(*args)
          MH::Van.mark_dirty_definition_entities(args.find { |item| item.is_a?(Sketchup::Entities) })
          MH::Van.request_full_refresh
        end

        def onEraseEntities(*args)
          MH::Van.mark_dirty_definition_entities(args.find { |item| item.is_a?(Sketchup::Entities) })
          MH::Van.request_full_refresh
        end
      end
    end

    if defined?(Sketchup::AppObserver)
      class ActiveModelObserver < Sketchup::AppObserver
        def onNewModel(model)
          MH::Van.invalidate_model_caches(model)
        end

        def onOpenModel(model)
          MH::Van.invalidate_model_caches(model)
        end

        def onActivateModel(model)
          MH::Van.invalidate_model_caches(model)
        end
      end
    end

    class << self
      def show
        @tracking_paused = false
        unless @dialog
          @active_scan_scope = :nesting
          build_dialog
        end
        refresh
        @dialog.show
        @dialog.bring_to_front
        start_auto_refresh
      end

      def refresh
        refresh_records(@active_scan_scope || :nesting)
      end

      # Nesting is limited to ABF boards. All group/component is the unfiltered view:
      # every outermost Group/Component in the model, whether or not ABF
      # registered it.
      def refresh_no_nesting
        refresh_records(:no_nesting)
      end

      def refresh_nesting
        refresh_records(:nesting)
      end

      def refresh_records(scope)
        prepare_model_runtime(Sketchup.active_model)
        # A structural change can replace thousands of nesting/label objects.
        # Release observers on the old graph before attaching the current one.
        reset_part_observers if @reattach_part_observers || @full_refresh_requested
        GeometryCache.clear if @full_refresh_requested
        @full_refresh_requested = false
        @dirty_entity_ids = {}
        @dirty_materials = {}
        @visibility_dirty_ids = {}
        invalidate_fast_bindings
        @active_scan_scope = scope.to_sym
        records = @active_scan_scope == :no_nesting ? no_nesting_records : part_records
        sync_material_overrides(records)
        rows = scan_rows(records, include_abf_counts: @active_scan_scope == :nesting)
        @last_rows = rows
        attach_part_observers((@last_records_by_id || {}).values)
        attach_materials_observer
        attach_model_observer
        execute('renderRows', rows)
      end

      def refresh_visibility
        return refresh unless @last_rows && @last_rows.any?

        payload = []
        @last_rows.each do |row|
          state = row_visibility_from_paths(row['paths'])
          next if row['visible'] == state[:visible] && row['all_hidden'] == state[:all_hidden]

          row['visible'] = state[:visible]
          row['all_hidden'] = state[:all_hidden]
          payload << {
            'key' => row['key'],
            'visible' => state[:visible],
            'all_hidden' => state[:all_hidden]
          }
        end
        return if payload.empty?

        execute('updateVisibility', payload)
      end

      def refresh_dirty_rows
        return if @tracking_paused || @suspend_dirty_tracking
        return refresh if @full_refresh_requested

        dirty_entity_ids = @dirty_entity_ids ? @dirty_entity_ids.keys : []
        force_entity_ids = dirty_entity_ids
        dirty_materials = @dirty_materials ? @dirty_materials.values : []
        visibility_ids = @visibility_dirty_ids ? @visibility_dirty_ids.keys : []
        @visibility_dirty_ids = {}
        return if force_entity_ids.empty? && dirty_materials.empty? && visibility_ids.empty?

        dirty_ids = detect_changed_record_ids(force_entity_ids)
        @dirty_entity_ids = {}
        @dirty_materials = {}

        if dirty_materials.any?
          material_ids = cached_ids_for_materials(dirty_materials)
          dirty_ids.concat(material_ids)
        end

        dirty_ids.uniq!
        if dirty_ids.empty?
          update_cached_visibility_for_ids(dirty_entity_ids + visibility_ids)
          return
        end

        patch_cached_rows_for_ids(dirty_ids) || refresh
        update_cached_visibility_for_ids(visibility_ids) unless visibility_ids.empty?
      end

      def mark_visibility_dirty(layer = nil)
        return if @tracking_paused || @suspend_dirty_tracking || @full_refresh_requested

        @visibility_dirty_ids ||= {}
        (@last_records_by_id || {}).each do |id, record|
          targets = [record[:entity]] + record_ancestor_entities(record)
          next if layer && targets.none? { |entity| entity && entity.valid? && entity_layer(entity) == layer }

          @visibility_dirty_ids[id] = true
        end
        invalidate_fast_bindings
        start_auto_refresh
      end

      def mark_dirty_entity(entity)
        return if @tracking_paused || @suspend_dirty_tracking || @full_refresh_requested
        return unless entity && entity.valid?

        invalidate_fast_bindings
        @dirty_entity_ids ||= {}
        id = entity.persistent_id.to_i
        @dirty_entity_ids[id] = true if @last_records_by_id && @last_records_by_id[id]
        Array(@ancestor_record_ids && @ancestor_record_ids[id]).each { |record_id| @dirty_entity_ids[record_id.to_i] = true }
        start_auto_refresh
      rescue StandardError
        nil
      end

      def mark_dirty_material(material)
        return if @tracking_paused || @suspend_dirty_tracking || @full_refresh_requested
        return unless material

        @dirty_materials ||= {}
        @dirty_materials[material.object_id] = material
        start_auto_refresh
      rescue StandardError
        nil
      end

      def mark_dirty_definition_entities(entities)
        return if @tracking_paused || @suspend_dirty_tracking || @full_refresh_requested
        return unless entities && entities.respond_to?(:parent)

        definition = entities.parent
        return unless definition && definition.respond_to?(:entityID)

        GeometryCache.invalidate(definition)
        invalidate_fast_bindings
        ids = @definition_record_ids && @definition_record_ids[definition.entityID]
        return unless ids && ids.any?

        @dirty_entity_ids ||= {}
        ids.each do |id|
          @dirty_entity_ids[id.to_i] = true
          record = @last_records_by_id && @last_records_by_id[id.to_i]
          GeometryCache.invalidate(record[:entity].definition) if record && record[:entity].valid?
        end
        start_auto_refresh
      rescue StandardError
        nil
      end

      def mark_selected_records_dirty(model = Sketchup.active_model)
        return if @tracking_paused || @suspend_dirty_tracking || @full_refresh_requested
        return unless model && @last_records_by_id

        ids = selected_record_ids_for_dirty_check(model)
        return if ids.empty?

        @dirty_entity_ids ||= {}
        ids.each { |id| @dirty_entity_ids[id.to_i] = true }
        start_auto_refresh
      rescue StandardError
        nil
      end

      def request_full_refresh
        return if @tracking_paused || @suspend_dirty_tracking || @full_refresh_requested

        @full_refresh_requested = true
        invalidate_fast_bindings
        start_auto_refresh
      end

      def invalidate_model_caches(model)
        return if @tracking_paused || @suspend_dirty_tracking

        @fast_visibility_runtime = nil
        @reattach_part_observers = true
        GeometryCache.clear
        request_full_refresh
      end

      def selected_record_ids_for_dirty_check(model = Sketchup.active_model, limit = 200)
        return [] unless model && @last_records_by_id

        ids = {}
        model.selection.each do |entity|
          next unless entity && entity.valid? && entity.respond_to?(:persistent_id)

          selected_id = entity.persistent_id.to_i
          ids[selected_id] = true if @last_records_by_id[selected_id]
          Array(@ancestor_record_ids && @ancestor_record_ids[selected_id]).each do |record_id|
            ids[record_id.to_i] = true
            break if limit && ids.length >= limit
          end
          break if limit && ids.length >= limit
        end
        ids.keys
      rescue StandardError
        []
      end

      def clear_dirty_entity_ids(ids)
        return unless @dirty_entity_ids

        Array(ids).each { |id| @dirty_entity_ids.delete(id.to_i) }
      rescue StandardError
        nil
      end

      def scan_rows(records = nil, include_abf_counts: true)
        @abf_sheet_type_rows_cache = nil
        @sheet_type_thickness_cache = nil
        @sheet_type_thickness_candidates_cache = nil
        records ||= part_records
        @last_records_by_id = {}
        @record_signatures = {}
        @record_row_keys = {}
        @definition_record_ids = Hash.new { |hash, key| hash[key] = [] }
        @ancestor_record_ids = Hash.new { |hash, key| hash[key] = [] }
        @bottom_face_counts_cache = nil
        items = scan_items_for_grouping(records)
        buckets = native_group_scan_items(items) || ruby_group_scan_items(items)

        if include_abf_counts
          apply_abf_sheet_type_counts(buckets)
          apply_bottom_face_counts(buckets)
        end
        rows = buckets.values.sort_by { |row| [row['thickness_value'].to_f, row['code'].downcase] }
        rebuild_row_indexes(rows)
        rows
      end

      def scan_items_for_grouping(records)
        items = records.map do |record|
          entity = record[:entity]
          id = entity.persistent_id
          @last_records_by_id[id] = record
          if entity.respond_to?(:definition) && entity.definition
            @definition_record_ids[entity.definition.entityID] << id
          end
          Array(record[:ancestor_ids]).each { |ancestor_id| @ancestor_record_ids[ancestor_id.to_i] << id }

          raw_code = default_material_code(entity)
          thickness = record_thickness_mm(entity, record[:transform], raw_code)
          code = group_material_code_display(raw_code)
          formatted_thickness = format_thickness(thickness)
          key = group_row_key(formatted_thickness, code)
          @record_row_keys[id] = key
          @record_signatures[id] = record_signature(entity, record[:transform], thickness)

          {
            'key' => key,
            'thickness' => formatted_thickness,
            'thickness_value' => thickness,
            'code' => code,
            'default_code' => code,
            'raw_code' => raw_code,
            'color' => entity.get_attribute(DICT, ATTR_COLOR, material_color(entity, raw_code)).to_s,
            'id' => id,
            'ancestor_ids' => record[:ancestor_ids],
            'path' => {
              'id' => id,
              'ancestor_ids' => record[:ancestor_ids]
            },
            'visible' => record_visible?(record)
          }
        end
        @last_group_scan_items = items.map(&:dup)
        items
      end

      def native_group_scan_items(items)
        return nil unless defined?(NativeBridge)
        return nil unless NativeBridge.available?

        buckets = NativeBridge.group_rows(items)
        return nil unless buckets

        items.each { |item| track_group_row_mix(buckets[item['key']], item) if buckets[item['key']] }
        buckets.each_value { |row| finalize_group_row_mix(row) }
        buckets
      rescue StandardError
        nil
      end

      def ruby_group_scan_items(items)
        buckets = {}
        items.each do |item|
          key = item['key']
          buckets[key] ||= {
            'key' => key,
            'thickness' => item['thickness'],
            'thickness_value' => item['thickness_value'],
            'code' => item['code'],
            'default_code' => item['default_code'],
            'count' => 0,
            'two_face' => 0,
            'visible' => false,
            'all_hidden' => true,
            'color' => item['color'],
            'ids' => [],
            'ancestor_ids' => [],
          'paths' => []
          }

          row = buckets[key]
          row['count'] += 1
          row['visible'] ||= !!item['visible']
          row['all_hidden'] &&= !item['visible']
          track_group_row_mix(row, item)
          row['ids'] << item['id']
          row['ancestor_ids'].concat(Array(item['ancestor_ids']))
          row['paths'] << item['path']
        end

        buckets.each_value do |row|
          row['ids'].uniq!
          row['ancestor_ids'].uniq!
          finalize_group_row_mix(row)
        end
        buckets
      end

      def track_group_row_mix(row, item)
          row['_thickness_values'] ||= {}
          row['_color_values'] ||= {}
          row['_raw_code_values'] ||= {}
          row['_thickness_values'][item['thickness'].to_s] = true
          row['_color_values'][item['color'].to_s] = true
          row['_raw_code_values'][(item['raw_code'] || item['code']).to_s] = true
      rescue StandardError
        nil
      end

      def finalize_group_row_mix(row)
        thickness_values = row.delete('_thickness_values') || {}
        color_values = row.delete('_color_values') || {}
        raw_code_values = row.delete('_raw_code_values') || {}
        row['mixed_thickness'] = thickness_values.length > 1
        row['mixed_color'] = color_values.length > 1 || raw_code_values.length > 1
        row['raw_codes'] = raw_code_values.keys
        row['raw_code'] = raw_code_values.keys.first if raw_code_values.length == 1
        row['thickness'] = 'Nhiều' if row['mixed_thickness']
      rescue StandardError
        row['mixed_thickness'] = false
        row['mixed_color'] = false
      end

      def set_visible(payload_json)
        payload = parse_json(payload_json)
        set_visible_rows(JSON.generate('rows' => [payload], 'visible' => !!payload['visible']))
      end

      def set_visible_rows(payload_json)
        payload = parse_json(payload_json)
        visible = !!payload['visible']
        rows = Array(payload['rows'])
        return if rows.empty?

        model = Sketchup.active_model
        return refresh if @runtime_model && !@runtime_model.equal?(model)

        changed_ids = []
        ancestor_ids = []
        tag_visibility = []
        with_visibility_operation(model, visible ? 'MH Van - Hiện dòng ván' : 'MH Van - Ẩn dòng ván') do
          rows.each do |row|
            ids = Array(row['ids'])
            ancestors = visible ? entities_from_ids(row['ancestor_ids']) : []
            if toggle_cached_row_tag(model, row, visible, ancestors)
              tag_visibility << { 'key' => row['key'], 'visible' => visible, 'all_hidden' => !visible }
            else
              entities = entities_from_ids(ids)
              next if entities.empty?

              apply_visible_entities(model, entities, ancestors, visible, row['key'])
            end
            changed_ids.concat(ids)
            ancestor_ids.concat(Array(row['ancestor_ids'])) if visible
          end
        end
        affected_ids = changed_ids + ancestor_ids
        clear_dirty_entity_ids(affected_ids)
        tag_keys = tag_visibility.map { |item| item['key'] }
        tag_visibility.each do |item|
          cached_row = @rows_by_key && @rows_by_key[item['key']]
          cached_row.merge!(item) if cached_row
        end
        execute('updateVisibility', tag_visibility) unless tag_visibility.empty?
        update_cached_visibility_for_ids(affected_ids, except_keys: tag_keys)
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        alert_error(e)
      end

      def apply_visible_entities(model, entities, ancestors, visible, key = nil)
        if visible
          if fast_visibility_mode?
            fast_show_entities(model, entities)
          else
            restore_fast_hidden_entities(model, entities)
          end
          # A parent can itself be on an MH Van temporary Tag.
          fast_show_entities(model, ancestors) if fast_visibility_mode? && ancestors.any?
          show_entity_containers(model, ancestors + entities)
        elsif fast_visibility_mode?
          fast_hide_entities(model, entities, key)
        else
          entities.each { |entity| entity.hidden = true if entity.valid? && !entity.hidden? }
        end
      end

      def set_fast_visibility(payload_json)
        payload = parse_json(payload_json)
        enabled = !!payload['enabled']
        unless enabled
          records = fast_visibility_state(Sketchup.active_model)['records']
          if records.is_a?(Hash) && records.any? && !restore_all_fast_hidden_entities(Sketchup.active_model)
            execute('syncFastVisibility', { 'enabled' => fast_visibility_mode? })
            raise 'Không khôi phục được Tag gốc. Chế độ ẩn nhanh được giữ nguyên.'
          end
        end
        Sketchup.write_default(DICT, FAST_VISIBILITY_KEY, enabled)
        invalidate_fast_bindings
        refresh_visibility
        Sketchup.status_text = "MH Van: Ẩn nhanh bằng Tag #{enabled ? 'ON' : 'OFF'}"
      rescue StandardError => e
        alert_error(e)
      end

      def set_group_code_options(payload_json)
        payload = parse_json(payload_json)
        Sketchup.write_default(DICT, GROUP_CODE_SHOW_THICKNESS_KEY, payload['show_thickness'] != false)
        Sketchup.write_default(DICT, GROUP_CODE_SHOW_PAINT_KEY, payload['show_paint'] != false)
        refresh_group_code_display
      rescue StandardError => e
        alert_error(e)
      end

      def fast_visibility_mode?
        value = Sketchup.read_default(DICT, FAST_VISIBILITY_KEY, false)
        value == true || value.to_s == 'true'
      rescue StandardError
        false
      end

      def group_code_show_thickness?
        setting_enabled?(GROUP_CODE_SHOW_THICKNESS_KEY, true)
      end

      def group_code_show_paint?
        setting_enabled?(GROUP_CODE_SHOW_PAINT_KEY, true)
      end

      def setting_enabled?(key, default)
        value = Sketchup.read_default(DICT, key, default)
        return value if value == true || value == false

        text = value.to_s.strip.downcase
        return false if %w[false 0 no off].include?(text)
        return true if %w[true 1 yes on].include?(text)

        !!default
      rescue StandardError
        !!default
      end

      def fast_hide_entities(model, entities, key = nil)
        targets = Array(entities).select do |entity|
          entity && entity.valid? && !entity.hidden? && entity_layer(entity) &&
            !protected_fast_visibility_entity?(entity)
        end
        return if targets.empty?

        state = fast_visibility_state(model)
        records = state['records'] ||= {}
        temp_layer = fast_visibility_temp_layer(model, state, key || fast_visibility_key_for_entities(targets))
        raise 'Không tạo được Tag ẩn nhanh.' unless temp_layer

        targets.each do |entity|
          id = entity.persistent_id.to_i
          next unless id.positive?

          original_layer = entity_layer(entity)
          if !marked_fast_visibility_layer?(original_layer) || !records[id.to_s]
            records[id.to_s] = fast_visibility_layer_record(original_layer)
          end
          records[id.to_s]['fast_key'] = fast_visibility_layer_key(temp_layer)
          entity.layer = temp_layer unless entity.layer == temp_layer
        end
        temp_layer.visible = false if temp_layer.respond_to?(:visible=)
        save_fast_visibility_state(model, state)
        if key && targets.length == Array(entities).length && targets.all? { |entity| entity_layer(entity) == temp_layer }
          @fast_row_bindings ||= {}
          @fast_row_bindings[key.to_s] = { ids: targets.map(&:persistent_id), layer: temp_layer }
        end
      end

      def fast_show_entities(model, entities)
        state = fast_visibility_state(model)
        records = state['records']
        return false unless records.is_a?(Hash) && records.any?

        keys_to_show = {}
        Array(entities).each do |entity|
          next unless entity && entity.valid?

          record = records[entity.persistent_id.to_i.to_s]
          keys_to_show[record['fast_key']] = true if record && record['fast_key']
        end
        return false if keys_to_show.empty?

        keys_to_show.each_key do |key|
          layer = fast_visibility_temp_layer(model, state, key, create: false)
          layer.visible = true if layer && layer.valid? && layer.respond_to?(:visible=) && !layer.visible?
        end
        true
      end

      def isolate_row_by_fast_tags(model, target_key)
        shared_result = isolate_row_via_shared_cache(model, target_key)
        return shared_result unless shared_result.nil?

        state = fast_visibility_state(model)
        records = state['records'] ||= {}
        target_key = target_key.to_s
        return false if target_key.empty?

        isolated = !(state['isolate_active'] == true && state['isolate_key'].to_s == target_key)
        with_visibility_operation(model, 'MH Van - Cô lập dòng ván') do
          if isolated
            unless fast_visibility_cache_matches_rows?(state)
              @last_rows.each do |row|
                key = row['key'].to_s
                next if key.empty?

                layer = fast_visibility_temp_layer(model, state, key)
                raise 'Không tạo được Tag cô lập.' unless layer

                entities_from_ids(row['ids']).each do |entity|
                  next unless entity && entity.valid?
                  next if protected_fast_visibility_entity?(entity)

                  id = entity.persistent_id.to_i
                  next unless id.positive?

                  original_layer = entity_layer(entity)
                  unless marked_fast_visibility_layer?(original_layer)
                    records[id.to_s] = fast_visibility_layer_record(original_layer)
                  end
                  records[id.to_s] ||= fast_visibility_layer_record(model.layers[0])
                  records[id.to_s]['fast_key'] = fast_visibility_layer_key(layer)
                  entity.hidden = false if entity.hidden?
                  entity.layer = layer unless entity_layer(entity) == layer
                end
              end
            end
            fast_visibility_tag_layers(state, model).each do |key, layer|
              next unless layer && layer.valid?

              visible = key.to_s == fast_visibility_safe_key(target_key)
              layer.visible = visible if layer.visible? != visible
            end
            @fast_isolate_layout = visibility_layout_signature
          else
            fast_show_all_row_tags(model, state)
          end
          state['isolate_active'] = isolated
          state['isolate_key'] = isolated ? target_key : nil
          state['soft_shown'] = false
          save_fast_visibility_state(model, state)
        end
        Sketchup.status_text = isolated ? "MH Van: cô lập dòng #{target_key}." : 'MH Van: đã hiện lại tất cả dòng.'
        isolated
      end

      # MH Van row isolation and MH Isolate must use one physical Tag cache.
      # Delegating avoids two plugins fighting over Entity#layer.
      def isolate_row_via_shared_cache(model, target_key)
        return nil unless defined?(MH::Isolate::Engine)
        return nil unless MH::Isolate::Engine.respond_to?(:isolate_entities)

        row = Array(@last_rows).find { |item| item['key'].to_s == target_key.to_s }
        return nil unless row

        targets = entities_from_ids(row['ids']).select do |entity|
          entity && entity.valid? &&
            (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
        end
        return nil if targets.empty?

        parent = model.active_entities.parent
        return nil unless targets.all? { |entity| entity.parent == parent }

        # One-time migration from the old MH Van per-row temp Tags. After this,
        # MH Isolate is the sole physical visibility-cache owner.
        legacy_state = fast_visibility_state(model)
        legacy_records = legacy_state['records']
        if legacy_records.is_a?(Hash) && legacy_records.any?
          return nil unless restore_all_fast_hidden_entities(model)
        end

        result = MH::Isolate::Engine.isolate_entities(model, targets, preserve_selection: false)
        return false unless result

        @using_shared_isolate = true
        shared_state = MH::Isolate::State.fetch(model)
        shared_state && shared_state['soft_unisolated'] != true
      rescue StandardError => error
        warn("MH Van shared isolate cache failed: #{error.class}: #{error.message}")
        nil
      end

      def fast_show_all_row_tags(model, state = fast_visibility_state(model))
        fast_visibility_tag_layers(state, model).each_value do |layer|
          layer.visible = true if layer && layer.valid? && layer.respond_to?(:visible=) && !layer.visible?
        end
      rescue StandardError
        nil
      end

      # Visual show-all that keeps every MH Van temp Tag and original-Tag map.
      # MH Isolate calls this through its cache coordinator.
      def show_all_fast_visibility_cached(model = Sketchup.active_model)
        return false unless model

        state = fast_visibility_state(model)
        records = state['records']
        return false unless records.is_a?(Hash) && records.any?

        with_visibility_operation(model, 'MH Van - Hiện tất cả bằng cache') do
          fast_show_all_row_tags(model, state)
          state['isolate_active'] = false
          state['isolate_key'] = nil
          state['soft_shown'] = true
          save_fast_visibility_state(model, state)
        end
        model.active_view.invalidate
        true
      rescue StandardError
        false
      end

      def fast_visibility_cache_matches_rows?(state)
        return true if @fast_isolate_layout == visibility_layout_signature

        records = state['records']
        tags = state['tags']
        return false unless records.is_a?(Hash) && tags.is_a?(Hash)

        model = Sketchup.active_model
        Array(@last_rows).all? do |row|
          key = fast_visibility_safe_key(row['key'])
          tag_state = tags[key]
          layer = tag_state && fast_visibility_layer(model, tag_state['temp_tag_pid'], tag_state['temp_tag_name'])
          next false unless layer && layer.valid?

          Array(row['ids']).all? do |id|
            record = records[id.to_i.to_s]
            entity = model.find_entity_by_persistent_id(id.to_i)
            record && entity && entity.valid? &&
              record['fast_key'].to_s == key && entity_layer(entity) == layer
          end
        end
      rescue StandardError
        false
      end

      def fast_visibility_tag_layers(state, model)
        result = {}
        tags = state['tags']
        return result unless tags.is_a?(Hash)

        tags.each do |key, tag_state|
          layer = fast_visibility_layer(model, tag_state['temp_tag_pid'], tag_state['temp_tag_name'])
          result[key] = layer if layer
        end
        result
      rescue StandardError
        {}
      end

      def restore_fast_hidden_entities(model, entities)
        state = fast_visibility_state(model)
        records = state['records']
        return false unless records.is_a?(Hash) && records.any?

        restored = false
        Array(entities).each do |entity|
          next unless entity && entity.valid?

          id = entity.persistent_id.to_i
          record = records[id.to_s]
          next unless record

          target_layer = fast_visibility_layer(model, record['tag_pid'], record['tag_name']) || model.layers[0]
          target_layer.visible = true if target_layer && target_layer.respond_to?(:visible=)
          entity.layer = target_layer if target_layer && entity_layer(entity) != target_layer
          records.delete(id.to_s)
          restored = true
        end

        invalidate_fast_bindings if restored
        if records.empty?
          cleanup_fast_visibility_tag(model, state)
          clear_fast_visibility_state(model)
        else
          save_fast_visibility_state(model, state)
        end
        restored
      end

      def restore_all_fast_hidden_entities(model)
        return false unless model

        state = fast_visibility_state(model)
        records = state['records']
        return false unless records.is_a?(Hash) && records.any?

        with_visibility_operation(model, 'MH Van - Khôi phục Tag ẩn nhanh') do
          records.keys.each do |id|
            entity = model.find_entity_by_persistent_id(id.to_i)
            next unless entity && entity.valid?

            record = records[id]
            target_layer = fast_visibility_layer(model, record['tag_pid'], record['tag_name']) || model.layers[0]
            target_layer.visible = true if target_layer && target_layer.respond_to?(:visible=)
            entity.layer = target_layer if target_layer && entity_layer(entity) != target_layer
          end
          cleanup_fast_visibility_tags(model, state)
          clear_fast_visibility_state(model)
        end
        true
      rescue StandardError
        false
      end

      def fast_visibility_state(model)
        runtime = @fast_visibility_runtime
        return runtime[:state] if runtime && runtime[:model].equal?(model)

        raw = model.get_attribute(DICT, FAST_VISIBILITY_STATE_KEY)
        data = raw.is_a?(String) && !raw.empty? ? JSON.parse(raw) : {}
        state = data.is_a?(Hash) ? data : {}
        @fast_visibility_runtime = { model: model, state: state, raw: raw }
        state
      rescue JSON::ParserError, TypeError
        @fast_visibility_runtime = { model: model, state: {}, raw: raw }
        @fast_visibility_runtime[:state]
      end

      def save_fast_visibility_state(model, state)
        fast_visibility_state(model)
        @fast_visibility_runtime[:state] = state
        if @visibility_batch_model && @visibility_batch_model.equal?(model)
          @visibility_batch_dirty = true
        else
          persist_fast_visibility_state(model)
        end
      end

      def clear_fast_visibility_state(model)
        dictionary = model.attribute_dictionary(DICT, false)
        dictionary.delete_key(FAST_VISIBILITY_STATE_KEY) if dictionary
        @fast_visibility_runtime = { model: model, state: {}, raw: nil }
        @visibility_batch_dirty = false
        invalidate_fast_bindings
      end

      def fast_visibility_layer_record(layer)
        {
          'tag_pid' => layer && layer.respond_to?(:persistent_id) ? layer.persistent_id : nil,
          'tag_name' => layer && layer.respond_to?(:name) ? layer.name.to_s : nil
        }
      end

      def fast_visibility_layer(model, persistent_id, fallback_name = nil)
        found = model.find_entity_by_persistent_id(persistent_id.to_i) if persistent_id
        return found if found.is_a?(Sketchup::Layer)
        return model.layers[fallback_name] if fallback_name && model.layers[fallback_name]

        nil
      rescue StandardError
        nil
      end

      def fast_visibility_temp_layer(model, state, key = nil, create: true)
        tags = state['tags'] ||= {}
        # Existing persisted keys remain readable after the v2 key upgrade.
        key = tags.key?(key.to_s) ? key.to_s : fast_visibility_safe_key(key)
        tag_state = tags[key] ||= {}
        layer = fast_visibility_layer(model, tag_state['temp_tag_pid'], tag_state['temp_tag_name'])
        return layer if layer && layer.valid?
        return nil unless create

        layer = model.layers.add("#{FAST_VISIBILITY_TAG_PREFIX}#{key}_#{Time.now.to_i}_#{rand(1_000_000)}")
        layer.visible = true
        layer.set_attribute(DICT, FAST_VISIBILITY_TAG_MARKER_KEY, true)
        layer.set_attribute(DICT, 'fast_visibility_key', key)
        tag_state['temp_tag_pid'] = layer.persistent_id
        tag_state['temp_tag_name'] = layer.name
        layer
      rescue StandardError
        nil
      end

      def fast_visibility_layer_key(layer)
        layer.get_attribute(DICT, 'fast_visibility_key', nil) if layer
      rescue StandardError
        nil
      end

      def fast_visibility_key_for_entities(entities)
        ids = Array(entities).map { |entity| entity.persistent_id.to_i }.sort
        "ids_#{ids.hash.abs}"
      rescue StandardError
        'batch'
      end

      def fast_visibility_safe_key(key)
        text = key.to_s.strip
        text = 'batch' if text.empty?
        return text if text.match?(/\Av2_[0-9a-f]{24}\z/)

        "v2_#{Digest::SHA256.hexdigest(text)[0, 24]}"
      end

      def cleanup_fast_visibility_tag(model, state)
        tag_states = state['tags'].is_a?(Hash) ? state['tags'].values : [state]
        tag_states.each do |tag_state|
          layer = fast_visibility_layer(model, tag_state['temp_tag_pid'], tag_state['temp_tag_name'])
          next unless layer && layer.valid?
          next unless marked_fast_visibility_layer?(layer)

          layer.visible = true if layer.respond_to?(:visible=)
          model.layers.remove(layer, false)
        end
      rescue StandardError
        nil
      end

      def cleanup_fast_visibility_tags(model, state)
        cleanup_fast_visibility_tag(model, state)
      end

      def marked_fast_visibility_layer?(layer)
        layer && layer.get_attribute(DICT, FAST_VISIBILITY_TAG_MARKER_KEY, false) == true
      rescue StandardError
        false
      end

      def protected_fast_visibility_entity?(entity)
        layer = entity_layer(entity)
        layer && PROTECTED_VISIBILITY_TAG_NAMES.any? do |name|
          layer.name.to_s.casecmp(name).zero?
        end
      rescue StandardError
        false
      end

      def recover_fast_visibility_entity(model, entity)
        layer = entity_layer(entity)
        return unless marked_fast_visibility_layer?(layer)

        entity.layer = model.layers[0] if model.layers[0]
      rescue StandardError
        nil
      end

      def set_code(payload_json)
        payload = parse_json(payload_json)
        input_code = payload['code'].to_s
        code = canonical_material_code(input_code)
        entities = entities_from_ids(payload['ids'])
        return if entities.empty?
        return reset_code(payload_json) if code.empty?

        model = Sketchup.active_model
        code_by_entity = resolved_material_codes_for_entities(entities, input_code)
        change_token = begin_hud_material_change(entities)
        target_materials = []
        old_materials = []
        @suspend_dirty_tracking = true
        begin
          model.start_operation('MH Van - Đổi mã vật liệu', true)
          code_groups = entities.group_by { |entity| code_by_entity[entity.persistent_id] || code }
          code_groups.each do |target_code, group_entities|
            current_materials = group_entities.map { |entity| primary_material(entity) if entity.valid? }.compact.uniq
            old_materials.concat(current_materials)
            target_material = material_for_code_change(target_code, current_materials, group_entities)
            target_materials << target_material
            group_entities.each do |entity|
              next unless entity.valid?

              assign_material_code(entity, target_code, target_material)
            end
          end
          model.commit_operation
        ensure
          @suspend_dirty_tracking = false
        end
        remove_unused_materials(old_materials.compact.uniq - target_materials.compact.uniq)
        affected_ids = entities.map(&:persistent_id)
        clear_dirty_entity_ids(affected_ids)
        clear_dirty_materials(target_materials)
        affected_ids.uniq.each do |id|
          record = @last_records_by_id && @last_records_by_id[id.to_i]
          entity = record && record[:entity]
          entity ||= entities.find { |item| item.persistent_id == id.to_i }
          next unless entity && entity.valid?

          raw_code = default_material_code(entity)
          color = material_color(entity, raw_code)
          update_cached_group_scan_items_code([id], raw_code, group_material_code_display(raw_code), color)
        end
        refresh_group_code_display || patch_cached_rows_for_ids(affected_ids.uniq)
        notify_material_code_change(change_token)
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def strip_paint_codes(payload_json = nil)
        payload = parse_json(payload_json || '{}')
        ids = Array(payload['ids']).map(&:to_i).reject(&:zero?)
        entities = if ids.empty?
          records = @active_scan_scope == :no_nesting ? no_nesting_records : part_records
          records.map { |record| record[:entity] }
        else
          entities_from_ids(ids)
        end
        entities = entities.select do |entity|
          entity && entity.valid? && (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
        end
        return if entities.empty?

        changes = {}
        old_materials = []
        entities.each do |entity|
          old_code = default_material_code(entity)
          new_code = strip_paint_material_code(old_code)
          next if new_code.empty? || new_code == old_code

          changes[entity] = new_code
          old_materials << primary_material(entity)
        end
        return if changes.empty?

        change_token = begin_hud_material_change(changes.keys)
        model = Sketchup.active_model
        @suspend_dirty_tracking = true
        begin
          model.start_operation('MH Van - Bỏ mã sơn', true)
          changes.each do |entity, new_code|
            next unless entity.valid?

            assign_material_code(entity, new_code, material_by_name(new_code, primary_material(entity)))
            entity.delete_attribute(DICT, ATTR_CODE)
            entity.delete_attribute(DICT, ATTR_ORIGINAL_CODE)
            entity.delete_attribute(DICT, ATTR_COLOR)
          end
          model.commit_operation
        ensure
          @suspend_dirty_tracking = false
        end
        changed_ids = changes.keys.map(&:persistent_id)
        changes.group_by { |_entity, new_code| new_code }.each do |new_code, pairs|
          ids_for_code = pairs.map { |entity, _code| entity.persistent_id }
          color = material_color(pairs.first.first, new_code)
          patch_cached_rows_for_ids(ids_for_code) unless update_cached_code_after_set(ids_for_code, new_code, color)
        end
        clear_dirty_entity_ids(changed_ids)
        clear_dirty_materials(old_materials.compact)
        notify_material_code_change(change_token)
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def reset_code(payload_json)
        payload = parse_json(payload_json)
        entities = entities_from_ids(payload['ids'])
        return if entities.empty?

        change_token = begin_hud_material_change(entities)
        model = Sketchup.active_model
        old_materials = []
        @suspend_dirty_tracking = true
        begin
          model.start_operation('MH Van - Về vật liệu Default', true)
          entities.each do |entity|
            next unless entity.valid? && entity.respond_to?(:material=)

            old_materials << primary_material(entity)
            entity.material = nil
            entity.delete_attribute(DICT, ATTR_CODE)
            entity.delete_attribute(DICT, ATTR_ORIGINAL_CODE)
          end
          model.commit_operation
        ensure
          @suspend_dirty_tracking = false
        end
        remove_unused_materials(old_materials)
        affected_ids = entities.map(&:persistent_id)
        clear_dirty_entity_ids(affected_ids)
        color = material_color(entities.find { |entity| entity && entity.valid? }, 'Default')
        if @active_scan_scope == :no_nesting
          patch_cached_rows_for_ids(affected_ids)
        else
          patch_cached_rows_for_ids(affected_ids) unless update_cached_code_after_set(affected_ids, 'Default', color)
        end
        notify_material_code_change(change_token)
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def set_color(payload_json)
        payload = parse_json(payload_json)
        color = normalize_hex(payload['color'])
        entities = entities_from_ids(payload['ids'])
        return if entities.empty?

        change_token = begin_hud_material_change(entities)
        model = Sketchup.active_model
        model.start_operation('MH Van - Đổi màu dòng', true)
        changed_materials = []
        entities.each do |entity|
          next unless entity.valid?

          apply_color_to_entity(entity, color)
          changed_materials << primary_material(entity)
          entity.delete_attribute(DICT, ATTR_COLOR)
        end
        model.commit_operation
        patch_cached_rows_for_ids(cached_ids_for_materials(changed_materials.compact)) || refresh
        notify_material_code_change(change_token)
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def refresh_surface_materials
        execute('renderSurfaceRows', surface_material_rows)
      rescue StandardError => e
        alert_error(e)
      end

      def clear_surface_material(payload_json)
        payload = parse_json(payload_json)
        surface_material_rows unless @surface_material_targets
        target = @surface_material_targets && @surface_material_targets[payload['id'].to_s]
        return unless target

        clear_surface_material_targets([target], 'MH Van - Xoa vat lieu ton du')
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def clear_all_surface_materials
        surface_material_rows unless @surface_material_targets
        targets = (@surface_material_targets || {}).values
        return if targets.empty?

        clear_surface_material_targets(targets, 'MH Van - Xoa tat ca vat lieu ton du')
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def clear_all_face_materials
        clear_surface_material_kind(%i[fronts backs], 'MH Van - Xoa vat lieu Face')
      end

      def clear_all_edge_materials
        clear_surface_material_kind([:edges], 'MH Van - Xoa vat lieu Edge')
      end

      def clear_surface_material_kind(kinds, operation_name)
        surface_material_rows unless @surface_material_targets
        targets = (@surface_material_targets || {}).values
        return if targets.empty?

        clear_surface_material_targets(targets, operation_name, kinds: kinds)
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def select_row(payload_json)
        payload = parse_json(payload_json)
        entities = entities_from_ids(payload['ids'])
        model = Sketchup.active_model
        model.selection.clear
        selected = entities.select { |entity| entity.valid? && entity_visible_in_model?(entity) }
        model.selection.add(selected) unless selected.empty?
        zoom_to_entities(model, model.selection.to_a)
      rescue StandardError => e
        alert_error(e)
      end

      def isolate_row(payload_json)
        payload = parse_json(payload_json)
        key = payload['key'].to_s
        return select_row(payload_json) if key.empty? || !@last_rows || @last_rows.empty?

        model = Sketchup.active_model
        @using_shared_isolate = false
        previous_suspend = @suspend_dirty_tracking
        begin
          @suspend_dirty_tracking = true
          isolate_row_by_fast_tags(model, key)
        ensure
          @suspend_dirty_tracking = previous_suspend
        end
        refresh_visibility
        target_row = @last_rows.find { |row| row['key'].to_s == key }
        if target_row && !@using_shared_isolate
          model.selection.clear
          selected = entities_from_ids(target_row['ids']).select { |entity| entity && entity.valid? && entity_visible_in_model?(entity) }
          model.selection.add(selected) unless selected.empty?
          zoom_to_entities(model, model.selection.to_a)
        end
        model.active_view.invalidate
      rescue StandardError => e
        alert_error(e)
      end

      def zoom_to_entities(model, entities)
        valid = Array(entities).select { |entity| entity && entity.valid? }
        model.active_view.zoom(valid) unless valid.empty?
      rescue StandardError
        nil
      end

      def clear_all_overrides
        entities = part_records.map { |record| record[:entity] }.select do |entity|
          entity.get_attribute(DICT, ATTR_CODE) ||
            entity.get_attribute(DICT, ATTR_ORIGINAL_CODE) ||
            entity.get_attribute(DICT, ATTR_COLOR)
        end
        return if entities.empty?

        change_token = begin_hud_material_change(entities)
        model = Sketchup.active_model
        model.start_operation('MH Van - Reset tất cả mã vật liệu', true)
        entities.each do |entity|
          next unless entity.valid?

          entity.delete_attribute(DICT, ATTR_CODE)
          entity.delete_attribute(DICT, ATTR_ORIGINAL_CODE)
          entity.delete_attribute(DICT, ATTR_COLOR)
        end
        model.commit_operation
        refresh
        notify_material_code_change(change_token)
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def sync_material_overrides(records = nil)
        targets = (records || part_records).map { |record| record[:entity] }.select do |entity|
          next false unless entity.valid?

          code = entity.get_attribute(DICT, ATTR_CODE).to_s.strip
          !code.empty?
        end
        return if targets.empty?

        change_token = begin_hud_material_change(targets)
        model = Sketchup.active_model
        model.start_operation('MH Van - Đồng bộ mã vật liệu', true)
        old_materials = []
        targets.each do |entity|
          next unless entity.valid?

          code = entity.get_attribute(DICT, ATTR_CODE).to_s.strip
          next if code.empty?

          material = primary_material(entity)
          if !material || material_code_name(material) != code
            old_materials << material
            assign_material_code(entity, code)
          end
          entity.delete_attribute(DICT, ATTR_CODE)
          entity.delete_attribute(DICT, ATTR_ORIGINAL_CODE)
          entity.delete_attribute(DICT, ATTR_COLOR)
        end
        model.commit_operation
        model.active_view.invalidate
        notify_material_code_change(change_token)
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      private

      def invalidate_fast_bindings
        @fast_row_bindings = {}
        @fast_isolate_layout = nil
      end

      def visibility_layout_signature
        Array(@last_rows).map { |row| [row['key'], Array(row['ids']).dup] }
      end

      def persist_fast_visibility_state(model)
        runtime = @fast_visibility_runtime
        return unless runtime && runtime[:model].equal?(model)

        raw = JSON.generate(runtime[:state])
        return if raw == runtime[:raw]

        model.set_attribute(DICT, FAST_VISIBILITY_STATE_KEY, raw)
        runtime[:raw] = raw
      end

      def with_visibility_operation(model, name)
        previous_suspend = @suspend_dirty_tracking
        @suspend_dirty_tracking = true
        @visibility_batch_model = model
        @visibility_batch_dirty = false
        started = false
        begin
          model.start_operation(name, true)
          started = true
          yield
          persist_fast_visibility_state(model) if @visibility_batch_dirty
          model.commit_operation
          started = false
        rescue StandardError
          model.abort_operation if started
          @fast_visibility_runtime = nil
          invalidate_fast_bindings
          raise
        ensure
          @visibility_batch_model = nil
          @visibility_batch_dirty = false
          @suspend_dirty_tracking = previous_suspend
          start_auto_refresh
        end
      end

      def toggle_cached_row_tag(model, row, visible, ancestors)
        return false unless fast_visibility_mode?

        binding = @fast_row_bindings && @fast_row_bindings[row['key'].to_s]
        return false unless binding && binding[:ids] == Array(row['ids']).map(&:to_i)

        layer = binding[:layer]
        return false unless layer && layer.valid?

        layer.visible = visible if layer.visible? != visible
        if visible
          fast_show_entities(model, ancestors) if ancestors.any?
          show_entity_containers(model, ancestors)
        end
        true
      end

      def show_entity_containers(model, entities)
        targets = entities.uniq.select { |entity| entity && entity.valid? }
        targets.each { |entity| recover_fast_visibility_entity(model, entity) unless fast_visibility_mode? }
        targets.filter_map { |entity| entity_layer(entity) }.uniq.each do |layer|
          next if marked_fast_visibility_layer?(layer)

          layer.visible = true if !layer.visible? && layer.respond_to?(:visible=)
          folder = layer.folder if layer.respond_to?(:folder)
          while folder
            folder.visible = true unless folder.visible?
            folder = folder.respond_to?(:folder) ? folder.folder : nil
          end
        end
        targets.each { |entity| entity.hidden = false if entity.hidden? }
      end

      def prepare_model_runtime(model)
        return if @runtime_model && @runtime_model.equal?(model)

        stop_auto_refresh
        reset_part_observers
        remove_observer_safely(@observed_model, @model_observer)
        remove_observer_safely(@observed_materials, @materials_observer)
        remove_observer_safely(@observed_layers, @layers_observer)
        @runtime_model = model
        @observed_model = nil
        @observed_materials = nil
        @materials_observer_attached = false
        @observed_entity_ids = {}
        @observed_definition_ids = {}
        @observed_entities = []
        @observed_containers = []
        @fast_visibility_runtime = nil
        invalidate_fast_bindings
        @surface_material_targets = nil
        execute('renderSurfaceRows', [])
        GeometryCache.clear
      end

      def remove_observer_safely(target, observer)
        target.remove_observer(observer) if target && observer
      rescue StandardError
        nil
      end

      def reset_part_observers
        Array(@observed_entities).each { |entity| remove_observer_safely(entity, @entity_observer) }
        Array(@observed_containers).each { |entities| remove_observer_safely(entities, @definition_entities_observer) }
        @observed_entity_ids = {}
        @observed_definition_ids = {}
        @observed_entities = []
        @observed_containers = []
        @root_entities_observed = false
        @reattach_part_observers = false
      end

      def pause_model_tracking
        @tracking_paused = true
        stop_auto_refresh
        reset_part_observers
        remove_observer_safely(@observed_model, @model_observer)
        remove_observer_safely(@observed_materials, @materials_observer)
        remove_observer_safely(@observed_layers, @layers_observer)
        remove_observer_safely(Sketchup, @app_observer)
        @observed_model = @observed_materials = @observed_layers = nil
        @app_observer = nil
        @materials_observer_attached = false
        @runtime_model = nil
        @full_refresh_requested = false
        %i[@dirty_entity_ids @dirty_materials @visibility_dirty_ids @last_records_by_id
           @record_signatures @record_row_keys @definition_record_ids @ancestor_record_ids].each do |key|
          instance_variable_set(key, {})
        end
        @last_rows = []
        @last_group_scan_items = []
        @surface_material_targets = nil
        @abf_sheet_type_rows_cache = @bottom_face_counts_cache = nil
        @sheet_type_thickness_cache = @sheet_type_thickness_candidates_cache = nil
        @abf_sheet_types_tool = nil
        @fast_visibility_runtime = nil
        @material_change_hub_signature = @material_change_hub_model = nil
        invalidate_fast_bindings
        rebuild_row_indexes([])
        GeometryCache.clear
      end

      def build_dialog
        @dialog = UI::HtmlDialog.new(
          dialog_title: 'Loại Ván',
          preferences_key: 'MH_Van',
          scrollable: true,
          resizable: true,
          width: 1200,
          height: 650,
          style: UI::HtmlDialog::STYLE_DIALOG
        )

        @dialog.set_html(html)
        @dialog.add_action_callback('ready') { refresh }
        @dialog.add_action_callback('refresh') { refresh }
        @dialog.add_action_callback('refresh_nesting') { refresh_nesting }
        @dialog.add_action_callback('refresh_no_nesting') { refresh_no_nesting }
        @dialog.add_action_callback('set_visible') { |_ctx, payload| set_visible(payload) }
        @dialog.add_action_callback('set_visible_rows') { |_ctx, payload| set_visible_rows(payload) }
        @dialog.add_action_callback('set_fast_visibility') { |_ctx, payload| set_fast_visibility(payload) }
        @dialog.add_action_callback('set_group_code_options') { |_ctx, payload| set_group_code_options(payload) }
        @dialog.add_action_callback('set_code') { |_ctx, payload| set_code(payload) }
        @dialog.add_action_callback('reset_code') { |_ctx, payload| reset_code(payload) }
        @dialog.add_action_callback('set_color') { |_ctx, payload| set_color(payload) }
        @dialog.add_action_callback('select_row') { |_ctx, payload| select_row(payload) }
        @dialog.add_action_callback('isolate_row') { |_ctx, payload| isolate_row(payload) }
        @dialog.add_action_callback('refresh_surface_materials') { refresh_surface_materials }
        @dialog.add_action_callback('clear_surface_material') { |_ctx, payload| clear_surface_material(payload) }
        @dialog.add_action_callback('clear_all_surface_materials') { clear_all_surface_materials }
        @dialog.add_action_callback('clear_all_face_materials') { clear_all_face_materials }
        @dialog.add_action_callback('clear_all_edge_materials') { clear_all_edge_materials }
        @dialog.add_action_callback('strip_paint_codes') { |_ctx, payload| strip_paint_codes(payload) }
        @dialog.add_action_callback('clear_all_overrides') { clear_all_overrides }
        @dialog.set_on_closed do
          pause_model_tracking
          @dialog = nil
        end
      end

      def start_auto_refresh
        return if @refresh_timer_id
        return unless @dialog && @dialog.visible?
        return unless @full_refresh_requested || (@dirty_entity_ids && @dirty_entity_ids.any?) || (@dirty_materials && @dirty_materials.any?) || (@visibility_dirty_ids && @visibility_dirty_ids.any?)

        @refresh_timer_id = UI.start_timer(AUTO_REFRESH_SECONDS, false) do
          @refresh_timer_id = nil
          if @dialog && @dialog.visible?
            refresh_dirty_rows
            start_auto_refresh
          end
        end
      end

      def stop_auto_refresh
        return unless @refresh_timer_id

        UI.stop_timer(@refresh_timer_id)
        @refresh_timer_id = nil
      rescue StandardError
        @refresh_timer_id = nil
      end

      def execute(function_name, data)
        return unless @dialog && @dialog.visible?

        @dialog.execute_script("#{function_name}(#{JSON.generate(data)})")
      end

      def refresh_cached_records
        records = (@last_records_by_id || {}).values.select do |record|
          entity = record[:entity]
          entity && entity.valid?
        end
        return false if records.empty?

        rows = scan_rows(records, include_abf_counts: @active_scan_scope == :nesting)
        @last_rows = rows
        attach_part_observers((@last_records_by_id || {}).values)
        attach_materials_observer
        execute('renderRows', rows)
        true
      rescue StandardError
        false
      end

      def refresh_group_code_display
        items = Array(@last_group_scan_items)
        return false if items.empty?

        show_thickness = group_code_show_thickness?
        show_paint = group_code_show_paint?
        separator = material_code_separator
        display_code_cache = {}
        display_items = items.map do |item|
          raw_code = (item['raw_code'] || item['code']).to_s
          code = display_code_cache[raw_code] ||= group_material_code_display(raw_code, show_thickness, show_paint, separator)
          copy = item.dup
          copy['code'] = code
          copy['default_code'] = code
          copy['key'] = group_row_key(copy['thickness'], code, show_thickness)
          copy
        end

        buckets = ruby_group_scan_items(display_items)
        display_code = lambda do |raw_code|
          raw = raw_code.to_s
          display_code_cache[raw] ||= group_material_code_display(raw, show_thickness, show_paint, separator)
        end
        if @active_scan_scope == :nesting
          @abf_sheet_type_rows_cache = nil
          abf_sheet_type_rows
          apply_cached_abf_sheet_type_counts(buckets, display_code)
          apply_cached_bottom_face_counts(buckets, display_code)
        end
        rows = buckets.values.sort_by { |row| [row['thickness_value'].to_f, row['code'].downcase] }
        @last_rows = rows
        rebuild_row_indexes(rows)
        execute('renderRows', rows)
        true
      rescue StandardError
        false
      end

      def parse_json(payload_json)
        JSON.parse(payload_json.to_s)
      rescue JSON::ParserError
        {}
      end

      def attach_part_observers(records)
        return if @tracking_paused
        return unless defined?(EntityChangeObserver)

        @entity_observer ||= EntityChangeObserver.new
        @definition_entities_observer ||= DefinitionEntitiesChangeObserver.new if defined?(DefinitionEntitiesChangeObserver)
        @observed_entity_ids ||= {}
        @observed_definition_ids ||= {}
        @observed_entities ||= []
        @observed_containers ||= []
        if @definition_entities_observer && !@root_entities_observed
          root = Sketchup.active_model.entities
          root.add_observer(@definition_entities_observer)
          @observed_containers << root
          @root_entities_observed = true
        end
        records.each do |record|
          entity = record[:entity]
          next unless entity && entity.valid?

          ([entity] + record_ancestor_entities(record)).each do |target|
            next unless target && target.valid?
            id = target.persistent_id
            next if @observed_entity_ids[id]

            target.add_observer(@entity_observer)
            @observed_entity_ids[id] = true
            @observed_entities << target
          end

          next unless @definition_entities_observer
          next unless entity.respond_to?(:definition) && entity.definition

          observe_record_definition(entity.definition, entity.persistent_id, {})
        rescue StandardError
          nil
        end
      end

      def observe_record_definition(definition, record_id, visited)
        id = definition.entityID
        return if visited[id]

        visited[id] = true
        ids = (@definition_record_ids[id] ||= [])
        ids << record_id unless ids.include?(record_id)
        unless @observed_definition_ids[id]
          definition.entities.add_observer(@definition_entities_observer)
          @observed_definition_ids[id] = true
          @observed_containers << definition.entities
        end
        definition.entities.each do |child|
          next unless child.valid? && child.respond_to?(:definition) && child.definition

          observe_record_definition(child.definition, record_id, visited)
        end
      end

      def attach_materials_observer
        return if @tracking_paused
        return if @materials_observer_attached
        return unless defined?(MaterialsChangeObserver)

        @materials_observer ||= MaterialsChangeObserver.new
        @observed_materials = Sketchup.active_model.materials
        @observed_materials.add_observer(@materials_observer)
        @materials_observer_attached = true
      rescue StandardError
        @materials_observer_attached = false
      end

      def attach_model_observer
        return if @tracking_paused
        return unless defined?(ModelChangeObserver)

        model = Sketchup.active_model
        return if @observed_model && @observed_model.equal?(model)

        @model_observer ||= ModelChangeObserver.new
        model.add_observer(@model_observer)
        @observed_model = model
        if defined?(VisibilityLayersObserver)
          @layers_observer ||= VisibilityLayersObserver.new
          @observed_layers = model.layers
          @observed_layers.add_observer(@layers_observer)
        end
        if defined?(ActiveModelObserver) && !@app_observer
          @app_observer = ActiveModelObserver.new
          Sketchup.add_observer(@app_observer)
        end
      rescue StandardError
        nil
      end

      def cached_ids_for_materials(materials)
        return [] unless @last_records_by_id

        material_list = Array(materials).compact
        return [] if material_list.empty?

        @last_records_by_id.each_value.filter_map do |record|
          entity = record[:entity]
          next unless entity && entity.valid?

          material = primary_material(entity)
          entity.persistent_id if material && material_list.any? { |item| material.equal?(item) }
        end
      end

      def clear_dirty_materials(materials)
        return unless @dirty_materials

        Array(materials).compact.each { |material| @dirty_materials.delete(material.object_id) }
      rescue StandardError
        nil
      end

      def detect_changed_record_ids(force_ids = [])
        return [] unless @last_records_by_id && @record_signatures

        force_lookup = {}
        Array(force_ids).each { |id| force_lookup[id.to_i] = true }
        return [] if force_lookup.empty?

        changed = []
        force_lookup.each_key do |id|
          record = @last_records_by_id[id]
          unless record
            changed << id
            next
          end

          entity = record[:entity]
          unless entity && entity.valid?
            changed << id
            next
          end

          refresh_record_transform(record)
          signature = record_signature(entity, record[:transform], record_key_thickness(@record_row_keys && @record_row_keys[id]))
          key = record_row_key(record)
          cached_key = @record_row_keys && @record_row_keys[id]
          next if signature == @record_signatures[id] && key && key == cached_key

          @record_signatures[id] = signature
          @record_row_keys[id] = key if key && @record_row_keys
          changed << id
        end
        changed
      rescue StandardError
        []
      end

      def patch_cached_rows_for_ids(ids)
        return false unless @last_rows && @last_records_by_id

        id_lookup = {}
        Array(ids).each do |id|
          id = id.to_i
          id_lookup[id] = true if id.positive?
        end
        return true if id_lookup.empty?

        touched_keys = []
        remove_keys = []

        @last_rows.each do |row|
          removed = false
          row['ids'] = Array(row['ids']).reject do |id|
            remove = id_lookup[id.to_i]
            removed ||= remove
            remove
          end
          next unless removed

          touched_keys << row['key']
          row['paths'] = Array(row['paths']).reject { |path| id_lookup[path['id'].to_i] }
          refresh_cached_row_state(row)
        end

        @last_rows.reject! do |row|
          empty = Array(row['ids']).empty?
          remove_keys << row['key'] if empty
          empty
        end

        new_buckets = {}
        id_lookup.each_key do |id|
          record = @last_records_by_id[id]
          next unless record

          entity = record[:entity]
          unless record_in_active_scope?(entity)
            @record_signatures.delete(id) if @record_signatures
            @record_row_keys.delete(id) if @record_row_keys
            @last_records_by_id.delete(id)
            @last_group_scan_items.reject! { |item| item['id'].to_i == id } if @last_group_scan_items
            next
          end

          refresh_record_transform(record)
          add_record_to_bucket(new_buckets, record)
        end

        new_buckets.each_value do |new_row|
          finalize_group_row_mix(new_row)
          existing = @last_rows.find { |row| row['key'] == new_row['key'] }
          if existing
            merge_cached_row(existing, new_row)
          else
            @last_rows << new_row
          end
          touched_keys << new_row['key']
        end

        # Recompute mixed thickness/color from all remaining members, rather
        # than retaining flags from a member that has just moved/deleted.
        touched = touched_keys.uniq
        mixed_rows = ruby_group_scan_items(Array(@last_group_scan_items).select { |item| touched.include?(item['key']) })
        @last_rows.each do |row|
          replacement = mixed_rows[row['key']]
          next unless replacement

          %w[thickness thickness_value color mixed_thickness mixed_color raw_codes raw_code].each do |key|
            row.delete(key)
            row[key] = replacement[key] if replacement.key?(key)
          end
        end

        @last_rows.sort_by! { |row| [row['thickness_value'].to_f, row['code'].to_s.downcase] }
        rebuild_row_indexes(@last_rows)
        touched_keys.uniq!
        remove_keys.uniq!

        patch_rows = @last_rows.select { |row| touched_keys.include?(row['key']) }
        execute('patchRows', { 'rows' => patch_rows, 'remove_keys' => remove_keys })
        true
      end

      def add_record_to_bucket(buckets, record)
        entity = record[:entity]
        raw_code = default_material_code(entity)
        thickness = record_thickness_mm(entity, record[:transform], raw_code)
        code = group_material_code_display(raw_code)
        color = material_color(entity, raw_code).to_s
        formatted_thickness = format_thickness(thickness)
        key = group_row_key(formatted_thickness, code)

        buckets[key] ||= {
          'key' => key,
          'thickness' => formatted_thickness,
          'thickness_value' => thickness,
          'code' => code,
          'default_code' => code,
          'raw_code' => raw_code,
          'count' => 0,
          'two_face' => 0,
          'visible' => false,
          'all_hidden' => true,
          'color' => color,
          'ids' => [],
          'ancestor_ids' => [],
          'paths' => []
        }

        row = buckets[key]
        row['count'] += 1
        visible = record_visible?(record)
        row['visible'] ||= visible
        row['all_hidden'] &&= !visible
        track_group_row_mix(
          row,
          'thickness' => formatted_thickness,
          'color' => color,
          'raw_code' => raw_code,
          'code' => code
        )
        row['ids'] << entity.persistent_id
        row['ancestor_ids'].concat(record[:ancestor_ids])
        row['paths'] << {
          'id' => entity.persistent_id,
          'ancestor_ids' => record[:ancestor_ids]
        }
        row['ids'].uniq!
        row['ancestor_ids'].uniq!
        @record_row_keys[entity.persistent_id] = key if @record_row_keys
        @record_signatures[entity.persistent_id] = record_signature(entity, record[:transform], thickness) if @record_signatures
        upsert_cached_group_scan_item(
          'key' => key,
          'thickness' => formatted_thickness,
          'thickness_value' => thickness,
          'code' => code,
          'default_code' => code,
          'raw_code' => raw_code,
          'color' => color,
          'id' => entity.persistent_id,
          'ancestor_ids' => record[:ancestor_ids],
          'path' => {
            'id' => entity.persistent_id,
            'ancestor_ids' => record[:ancestor_ids]
          },
          'visible' => visible
        )
      end

      def upsert_cached_group_scan_item(item)
        return unless @last_group_scan_items

        id = item['id'].to_i
        index = @last_group_scan_items.find_index { |cached| cached['id'].to_i == id }
        if index
          @last_group_scan_items[index] = item
        else
          @last_group_scan_items << item
        end
      rescue StandardError
        nil
      end

      def record_row_key(record)
        entity = record[:entity]
        return nil unless record_in_active_scope?(entity)

        raw_code = default_material_code(entity)
        thickness = record_thickness_mm(entity, record[:transform], raw_code)
        group_row_key(format_thickness(thickness), group_material_code_display(raw_code))
      rescue StandardError
        nil
      end

      def record_in_active_scope?(entity)
        return false unless entity && entity.valid?
        return part_like?(entity) unless @active_scan_scope == :no_nesting

        (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
          !all_group_component_thickness_mm(entity).nil?
      rescue StandardError
        false
      end

      def refresh_record_transform(record)
        transform = Geom::Transformation.new
        record_ancestor_entities(record).each do |ancestor|
          next unless ancestor && ancestor.valid? && ancestor.respond_to?(:transformation)

          transform *= ancestor.transformation
        end

        entity = record[:entity]
        transform *= entity.transformation if entity && entity.valid? && entity.respond_to?(:transformation)
        record[:transform] = transform
      rescue StandardError
        record[:transform] ||= Geom::Transformation.new
      end

      def merge_cached_row(existing, new_row)
        existing['ids'] = (Array(existing['ids']) + Array(new_row['ids'])).uniq
        existing['paths'] = (Array(existing['paths']) + Array(new_row['paths'])).uniq { |path| path['id'].to_i }
        existing['ancestor_ids'] = (Array(existing['ancestor_ids']) + Array(new_row['ancestor_ids'])).uniq
        existing['color'] = new_row['color']
        existing['mixed_thickness'] = existing['mixed_thickness'] || new_row['mixed_thickness']
        existing['mixed_color'] = existing['mixed_color'] || new_row['mixed_color'] || existing['raw_code'].to_s != new_row['raw_code'].to_s
        existing['thickness'] = 'Nhiều' if existing['mixed_thickness']
        refresh_cached_row_state(existing)
      end

      def refresh_cached_row_state(row)
        row['count'] = Array(row['ids']).length
        row['ancestor_ids'] = Array(row['paths']).flat_map { |path| Array(path['ancestor_ids']) }.uniq
        state = row_visibility_from_paths(row['paths'])
        row['visible'] = state[:visible]
        row['all_hidden'] = state[:all_hidden]
      end

      def update_cached_visibility_after_set(ids, visible)
        return refresh_visibility unless @last_rows && @last_rows.any?

        row_lookup = rows_for_entity_ids(ids)
        return if row_lookup.empty?

        payload = []
        row_lookup.each_value do |row|
          row['visible'] = visible
          row['all_hidden'] = !visible
          payload << {
            'key' => row['key'],
            'visible' => row['visible'],
            'all_hidden' => row['all_hidden']
          }
        end
        execute('updateVisibility', payload) unless payload.empty?
      end

      def rebuild_row_indexes(rows = @last_rows)
        @row_keys_by_entity_id = {}
        @rows_by_key = {}
        Array(rows).each do |row|
          key = row['key']
          @rows_by_key[key] = row if key
          Array(row['ids']).each do |id|
            id = id.to_i
            next unless id.positive?

            (@row_keys_by_entity_id[id] ||= []) << key
          end
        end
      rescue StandardError
        @row_keys_by_entity_id = {}
        @rows_by_key = {}
      end

      def rows_for_entity_ids(ids)
        rebuild_row_indexes(@last_rows) unless @row_keys_by_entity_id && @rows_by_key
        rows = {}
        Array(ids).each do |id|
          Array(@row_keys_by_entity_id[id.to_i]).each do |key|
            row = @rows_by_key[key]
            rows[key] = row if row
          end
        end
        rows
      rescue StandardError
        {}
      end

      def update_cached_visibility_for_ids(ids, except_keys: [])
        return unless @last_rows && @last_rows.any?

        row_lookup = rows_for_entity_ids(ids)
        return if row_lookup.empty?

        payload = []
        row_lookup.each_value do |row|
          next if except_keys.include?(row['key'])
          state = row_visibility_from_paths(row['paths'])
          next if row['visible'] == state[:visible] && row['all_hidden'] == state[:all_hidden]

          row['visible'] = state[:visible]
          row['all_hidden'] = state[:all_hidden]
          payload << {
            'key' => row['key'],
            'visible' => state[:visible],
            'all_hidden' => state[:all_hidden]
          }
        end
        execute('updateVisibility', payload) unless payload.empty?
      end

      def update_cached_visibility_for_row_isolate(target_key, isolated)
        return unless @last_rows && @last_rows.any?

        payload = []
        @last_rows.each do |row|
          visible = isolated ? row['key'].to_s == target_key.to_s : true
          next if row['visible'] == visible && row['all_hidden'] == !visible

          row['visible'] = visible
          row['all_hidden'] = !visible
          payload << {
            'key' => row['key'],
            'visible' => visible,
            'all_hidden' => !visible
          }
        end
        execute('updateVisibility', payload) unless payload.empty?
      end

      def update_cached_code_after_set(ids, code, color)
        return false unless @last_rows && @last_rows.any?

        display_code = group_material_code_display(code)
        update_cached_group_scan_items_code(ids, code, display_code, color)
        return true if @last_group_scan_items && refresh_group_code_display

        id_lookup = {}
        Array(ids).each do |id|
          id = id.to_i
          id_lookup[id] = true if id.positive?
        end
        return true if id_lookup.empty?

        rows_to_upsert = []
        remove_keys = []
        moved_rows = []

        @last_rows.dup.each do |row|
          moved_ids = Array(row['ids']).select { |id| id_lookup[id.to_i] }
          next if moved_ids.empty?

          moved_paths = Array(row['paths']).select { |path| id_lookup[path['id'].to_i] }
          row['ids'] = Array(row['ids']).reject { |id| id_lookup[id.to_i] }
          row['paths'] = Array(row['paths']).reject { |path| id_lookup[path['id'].to_i] }

          if row['ids'].empty?
            @last_rows.delete(row)
            remove_keys << row['key']
          else
            refresh_cached_row_state(row)
            rows_to_upsert << row
          end

          moved_row = {
            'key' => group_row_key(row['thickness'], display_code),
            'thickness' => row['thickness'],
            'thickness_value' => row['thickness_value'],
            'code' => display_code,
            'default_code' => display_code,
            'raw_code' => code,
            'count' => moved_ids.length,
            'two_face' => 0,
            'visible' => row['visible'],
            'all_hidden' => row['all_hidden'],
            'color' => color,
            'ids' => moved_ids,
            'ancestor_ids' => moved_paths.flat_map { |path| Array(path['ancestor_ids']) }.uniq,
            'paths' => moved_paths
          }
          moved_rows << moved_row
          moved_ids.each { |id| @record_row_keys[id.to_i] = moved_row['key'] if @record_row_keys }
        end

        moved_rows.each do |moved_row|
          existing = @last_rows.find { |row| row['key'] == moved_row['key'] }
          if existing
            merge_cached_row(existing, moved_row)
            rows_to_upsert << existing
          else
            @last_rows << moved_row
            rows_to_upsert << moved_row
          end
        end

        @last_rows.sort_by! { |row| [row['thickness_value'].to_f, row['code'].to_s.downcase] }
        rebuild_row_indexes(@last_rows)
        execute('patchRows', { 'rows' => rows_to_upsert.uniq { |row| row['key'] }, 'remove_keys' => remove_keys.uniq })
        true
      rescue StandardError
        false
      end

      def update_cached_group_scan_items_code(ids, raw_code, display_code, color = nil)
        items = Array(@last_group_scan_items)
        return if items.empty?

        id_lookup = {}
        Array(ids).each do |id|
          id = id.to_i
          id_lookup[id] = true if id.positive?
        end
        return if id_lookup.empty?

        items.each do |item|
          id = item['id'].to_i
          next unless id_lookup[id]

          item['raw_code'] = raw_code
          item['code'] = display_code
          item['default_code'] = display_code
          item['key'] = group_row_key(item['thickness'], display_code)
          item['color'] = color if color
        end
      rescue StandardError
        nil
      end

      def part_records
        records = []
        walk_entities(Sketchup.active_model.entities, records, [], Geom::Transformation.new)
        seen = {}
        records.select do |record|
          id = record[:entity].persistent_id
          next false if seen[id]

          seen[id] = true
        end
      end

      def no_nesting_records
        records = []
        # All group/component is a top-level inventory. Nested details belong
        # to their outer Group/Component and must not be counted again.
        Sketchup.active_model.entities.each do |entity|
          next unless entity.valid?
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          next unless all_group_component_thickness_mm(entity)

          records << {
            entity: entity,
            ancestors: [],
            ancestor_ids: [],
            transform: entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new
          }
        end
        seen = {}
        records.select do |record|
          id = record[:entity].persistent_id
          next false if seen[id]

          seen[id] = true
        end
      end

      def walk_entities(container, out, ancestors, transform)
        container.each do |entity|
          next unless entity.valid?

          entity_transform = entity.respond_to?(:transformation) ? transform * entity.transformation : transform
          if part_like?(entity)
            out << {
              entity: entity,
              ancestors: ancestors.dup,
              ancestor_ids: ancestors.map(&:persistent_id),
              transform: entity_transform
            }
          elsif entity.respond_to?(:definition)
            walk_entities(entity.definition.entities, out, ancestors + [entity], entity_transform)
          end
        end
      end

      def record_visible?(record)
        return false unless entity_visible_in_model?(record[:entity])

        record_ancestor_entities(record).all? { |ancestor| entity_visible_in_model?(ancestor) }
      end

      def row_visibility_from_paths(paths)
        any_visible = false
        all_hidden = true

        Array(paths).each do |path|
          record = @last_records_by_id && @last_records_by_id[path['id'].to_i]
          entity = record && record[:entity]
          entity ||= Sketchup.active_model.find_entity_by_persistent_id(path['id'].to_i)
          next unless entity && entity.valid?

          visible = entity_visible_in_model?(entity) &&
                    if record
                      record_ancestor_entities(record).all? { |ancestor| entity_visible_in_model?(ancestor) }
                    else
                      Array(path['ancestor_ids']).all? do |id|
                        ancestor = Sketchup.active_model.find_entity_by_persistent_id(id.to_i)
                        ancestor && ancestor.valid? && entity_visible_in_model?(ancestor)
                      end
                    end
          any_visible ||= visible
          all_hidden &&= !visible
        end

        { visible: any_visible, all_hidden: all_hidden }
      end

      def record_ancestor_entities(record)
        cached = record[:ancestors]
        return cached if cached

        record[:ancestors] = Array(record[:ancestor_ids]).filter_map do |id|
          Sketchup.active_model.find_entity_by_persistent_id(id.to_i)
        end
      rescue StandardError
        []
      end

      def entity_visible_in_model?(entity)
        return false unless entity && entity.valid?
        return false if entity.hidden?
        return false unless layer_visible?(entity)
        return entity.visible? if entity.respond_to?(:visible?)

        true
      rescue StandardError
        false
      end

      def layer_visible?(entity)
        layer = entity_layer(entity)
        return true unless layer && layer.respond_to?(:visible?)

        return false unless layer.visible?

        folder = layer.folder if layer.respond_to?(:folder)
        while folder
          return false unless folder.visible?
          folder = folder.respond_to?(:folder) ? folder.folder : nil
        end
        true
      rescue StandardError
        true
      end

      def entity_layer(entity)
        entity.layer if entity && entity.respond_to?(:layer)
      rescue StandardError
        nil
      end

      def part_like?(entity)
        return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        return false unless abf_board?(entity)
        return false unless has_direct_faces?(entity)

        bounds = entity.bounds
        dims = [bounds.width, bounds.height, bounds.depth].map(&:to_f)
        dims.count { |value| value > 0.001 } >= 2
      end

      def abf_board?(entity)
        return true if entity.get_attribute('ABF', 'is-board') == true
        return true unless entity.get_attribute('ABF', 'board-index').nil?
        return true unless entity.get_attribute('ABF', 'edge-band-types').nil?

        false
      end

      def has_direct_faces?(entity)
        container = entity.respond_to?(:definition) ? entity.definition.entities : nil
        return false unless container

        container.any? { |child| child.is_a?(Sketchup::Face) }
      end

      def entities_from_ids(ids)
        model = Sketchup.active_model
        Array(ids).filter_map do |id|
          id = id.to_i
          next if id.zero?

          record = @last_records_by_id && @last_records_by_id[id]
          entity = record && record[:entity]
          if entity && entity.valid?
            entity
          else
            model.find_entity_by_persistent_id(id)
          end
        rescue StandardError
          nil
        end
      end

      def record_signature(entity, transform = nil, expected_thickness = nil)
        material = primary_material(entity)
        [
          material ? material.object_id : nil,
          material ? material.display_name.to_s : nil,
          watched_thickness_signature(entity, transform, expected_thickness)
        ]
      rescue StandardError
        [:invalid]
      end

      def watched_thickness_signature(entity, transform = nil, expected_thickness = nil)
        format_thickness(expected_thickness || record_thickness_mm(entity, transform))
      end

      def record_key_thickness(key)
        key.to_s.split('|', 2).first.to_f
      end

      def thickness_mm(entity, transform = nil, material = nil)
        GeometryCache.thickness(entity, transform) || 0.0
      end

      # Both inventory scopes measure the same physical board thickness.
      def record_thickness_mm(entity, transform = nil, material = nil)
        thickness_mm(entity, transform, material)
      end

      def all_group_component_thickness_mm(entity)
        GeometryCache.thickness(entity)
      rescue StandardError
        nil
      end

      def bounds_thickness_mm(entity, transform = nil)
        bounds = if entity.respond_to?(:definition) && entity.definition
                   entity.definition.bounds
                 else
                   entity.bounds
                 end
        transform ||= entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new
        scales = transformation_scales(transform)
        dims = [bounds.width * scales[0], bounds.height * scales[1], bounds.depth * scales[2]].map { |value| value.to_f.to_mm.abs }
        positive = dims.select { |value| value > 0.1 }
        positive.empty? ? nil : positive.min
      end

      def world_bounds_thickness_mm(entity)
        bounds = entity.bounds
        dims = [bounds.width, bounds.height, bounds.depth].map { |value| value.to_f.to_mm.abs }
        positive = dims.select { |value| value > 0.1 }
        positive.empty? ? nil : positive.min
      rescue StandardError
        nil
      end

      def largest_face_thickness_mm(entity, transform = nil)
        container = entity.respond_to?(:definition) ? entity.definition.entities : nil
        return nil unless container

        faces = container.grep(Sketchup::Face)
        return nil if faces.empty?

        transform ||= entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new
        points = faces.flat_map(&:vertices).uniq.map { |vertex| vertex.position.transform(transform) }
        return nil if points.empty?

        largest = nil
        faces.each do |face|
          data = transformed_face_plane(face, transform)
          next unless data

          largest = data if !largest || data[:area] > largest[:area]
        end
        return nil unless largest

        normal = largest[:normal]
        projections = points.map { |point| point.x * normal.x + point.y * normal.y + point.z * normal.z }
        mm = (projections.max - projections.min).to_f.to_mm.abs
        mm > 0.1 ? mm : nil
      rescue StandardError
        nil
      end

      def transformed_face_plane(face, transform)
        points = face.vertices.map { |vertex| vertex.position.transform(transform) }
        return nil if points.length < 3

        area_vector = Geom::Vector3d.new(0, 0, 0)
        origin = points[0]
        (1...(points.length - 1)).each do |index|
          vector_a = origin.vector_to(points[index])
          vector_b = origin.vector_to(points[index + 1])
          cross = vector_a * vector_b
          area_vector += cross if cross.length > 1.0e-9
        end

        area = area_vector.length * 0.5
        return nil if area <= 1.0e-9

        normal = area_vector.clone
        normal.normalize!
        { normal: normal, area: area }
      rescue StandardError
        nil
      end

      def sheet_type_thickness(material)
        material = material.to_s
        return nil if material.empty?

        sheet_type_thickness_cache[material]
      rescue StandardError
        nil
      end

      def closest_sheet_type_thickness(material, values, tolerance = 0.2)
        candidates = sheet_type_thickness_candidates(material)
        return nil if candidates.empty?

        Array(values).compact.each do |value|
          match = candidates.min_by { |candidate| (candidate - value).abs }
          return match if match && (match - value).abs <= tolerance
        end
        nil
      rescue StandardError
        nil
      end

      def sheet_type_thickness_candidates(material)
        material = material.to_s
        return [] if material.empty?

        sheet_type_thickness_candidates_cache[material] || []
      end

      def sheet_type_thickness_candidates_cache
        @sheet_type_thickness_candidates_cache ||= begin
          abf_sheet_type_rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |item, map|
            material = (item[:material] || item['material']).to_s
            thickness = item[:thickness] || item['thickness']
            next if material.empty? || thickness.nil?

            map[material] << thickness.to_f
          end.transform_values { |values| values.uniq.sort }
        end
      end

      def sheet_type_thickness_cache
        @sheet_type_thickness_cache ||= begin
          sheet_type_thickness_candidates_cache.each_with_object({}) do |(material, values), map|
            uniq_values = values.uniq
            map[material] = uniq_values.first if uniq_values.length == 1
          end
        end
      end

      def transformation_scales(transform)
        axes = GeometryCache.transform_axes(transform)
        return [0.0, 0.0, 0.0] unless axes

        axes.map { |axis| Math.sqrt(axis.sum { |value| value * value }) }
      rescue StandardError
        [1.0, 1.0, 1.0]
      end

      def format_thickness(value)
        # Keep distinct measured thicknesses (17.6 vs 17.64) in separate
        # rows, while suppressing floating-point noise from transformations.
        rounded = value.to_f.round(3)
        rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
      end

      def default_material_code(entity)
        material = entity.respond_to?(:material) ? entity.material : nil
        material ? material_code_name(material) : 'Default'
      end

      # Material#name can be SketchUp's internal identifier while
      # #display_name is what users see and what the other MH apps export.
      # Always use one value here so MH Van, Material HUD and Thongke cannot
      # disagree after a material is renamed.
      def material_code_name(material)
        return '' unless material

        display = material.display_name.to_s.strip if material.respond_to?(:display_name)
        return display unless display.to_s.empty?

        material.name.to_s.strip
      rescue StandardError
        ''
      end

      def group_material_code_display(code, show_thickness = nil, show_paint = nil, separator = nil)
        text = code.to_s
        return 'Default' if text.empty? || text.casecmp('Default').zero?
        show_thickness = group_code_show_thickness? if show_thickness.nil?
        show_paint = group_code_show_paint? if show_paint.nil?
        return text if show_thickness && show_paint

        sep = separator || material_code_separator
        parts = text.split(sep, -1)
        return text if parts.empty?

        unless show_thickness
          parts.delete_at(1) if removable_thickness_code_segment?(parts[1])
        end

        unless show_paint
          index = parts.find_index { |part| comparable_material_code_segment(part) == GROUP_CODE_PAINT_TOKEN }
          parts = parts[0..index] if index
        end

        result = parts.join(sep)
        result.empty? ? text : result
      rescue StandardError
        text
      end

      def resolved_material_codes_for_entities(entities, display_code)
        show_thickness = group_code_show_thickness?
        show_paint = group_code_show_paint?
        entities.each_with_object({}) do |entity, map|
          next unless entity && entity.valid?

          raw_code = default_material_code(entity)
          merged = merge_display_code_with_raw_code(display_code, raw_code, show_thickness, show_paint)
          map[entity.persistent_id] = canonical_material_code(merged)
        end
      end

      def merge_display_code_with_raw_code(display_code, raw_code, show_thickness, show_paint)
        text = display_code.to_s
        return text if text.empty? || text.casecmp('Default').zero?
        return text if show_thickness && show_paint

        sep = material_code_separator
        parts = text.split(sep, -1)
        raw_parts = raw_code.to_s.split(sep, -1)
        return text if parts.empty? || raw_parts.empty?

        unless show_thickness || removable_thickness_code_segment?(parts[1])
          raw_thickness = raw_parts[1]
          parts.insert(1, raw_thickness) if removable_thickness_code_segment?(raw_thickness)
        end

        unless show_paint
          input_son_index = parts.find_index { |part| comparable_material_code_segment(part) == GROUP_CODE_PAINT_TOKEN }
          raw_son_index = raw_parts.find_index { |part| comparable_material_code_segment(part) == GROUP_CODE_PAINT_TOKEN }
          if input_son_index && raw_son_index && parts.length == input_son_index + 1
            hidden_tail = raw_parts[(raw_son_index + 1)..-1].to_a
            parts.concat(hidden_tail)
          end
        end

        parts.join(sep)
      rescue StandardError
        display_code.to_s
      end

      def group_row_key(thickness, code, show_thickness = nil)
        show_thickness = group_code_show_thickness? if show_thickness.nil?
        key_thickness = show_thickness ? thickness.to_s : '*'
        "#{key_thickness}|#{code}"
      end

      def material_code_separator
        if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:rules)
          sep = MH::MaterialCode.rules['segment_separator'].to_s
          return sep unless sep.empty?
        end

        '.'
      rescue StandardError
        '.'
      end

      def comparable_material_code_segment(value)
        value.to_s.strip.upcase.gsub(/\s+/, '')
      end

      def removable_thickness_code_segment?(value)
        text = value.to_s.strip
        return false unless text.match?(/\A\d+(?:[,.]\d+)?\z/)

        number = text.tr(',', '.').to_f
        number >= 3.0 && number <= 80.0
      end

      def canonical_material_code(code)
        code.to_s
      end

      def strip_paint_material_code(code)
        text = code.to_s.strip
        return text if text.empty?

        if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:parse) && MH::MaterialCode.respond_to?(:without_finish)
          parsed = MH::MaterialCode.parse(text)
          return text if parsed[:finish_code].to_s.strip.empty?

          stripped = MH::MaterialCode.without_finish(text).to_s.strip
          return stripped unless stripped.empty?
        end

        text
      rescue StandardError
        text
      end

      def primary_material(entity)
        entity.respond_to?(:material) ? entity.material : nil
      end

      def material_color(entity, code)
        material = primary_material(entity)
        return color_to_hex(material.color) if material

        attr_color = entity.get_attribute(DICT, ATTR_COLOR)
        return normalize_hex(attr_color) if attr_color

        palette_color(code)
      end

      def apply_color_to_entity(entity, hex)
        material = primary_material(entity)
        material ||= entity.material

        unless material
          material = Sketchup.active_model.materials.add(default_material_code(entity))
          entity.material = material if entity.respond_to?(:material=)
        end

        material.color = Sketchup::Color.new(hex[1, 2].to_i(16), hex[3, 2].to_i(16), hex[5, 2].to_i(16))
      end

      def assign_material_code(entity, code, material = nil)
        return unless entity.respond_to?(:material=)

        material ||= material_by_name(code, primary_material(entity))
        return if primary_material(entity).equal?(material)

        entity.material = material
      end

      def material_for_code_change(code, current_materials, target_entities = [])
        name = code.to_s
        return nil if name.empty?

        existing = existing_material_by_code(name)
        return existing if existing

        # A material can be shared by objects from different rows (for
        # example 18.6 mm and 27 mm). Never rename it in place: a row edit
        # must reassign only the objects selected by that row.
        material_by_name(name, current_materials.first)
      rescue StandardError
        material_by_name(name, current_materials.first)
      end

      def material_only_used_by_cached_parts?(material, target_ids)
        return false unless material
        return false unless @last_records_by_id && @last_records_by_id.any?

        target_lookup = {}
        Array(target_ids).each { |id| target_lookup[id.to_i] = true }
        return false if target_lookup.empty?

        @last_records_by_id.each_value do |record|
          entity = record[:entity]
          next unless entity && entity.valid?
          next unless primary_material(entity).equal?(material)

          return false unless target_lookup[entity.persistent_id]
        end
        true
      rescue StandardError
        false
      end

      def material_by_name(name, source_material = nil)
        name = name.to_s
        return nil if name.empty?

        materials = Sketchup.active_model.materials
        material = existing_material_by_code(name, materials)
        return material if material

        material = materials.add(name)
        material.color = source_material.color if source_material
        material
      end

      def existing_material_by_code(name, materials = nil)
        materials ||= Sketchup.active_model.materials
        material = materials[name]
        return material if material

        materials.find { |item| material_code_name(item) == name.to_s }
      rescue StandardError
        nil
      end

      # SketchUp normally notifies the shared hub on commit. Keep an explicit
      # fallback for missed material-only events, and always finish the HUD's
      # targeted edit notification without a second full hub invalidation.
      def begin_hud_material_change(entities)
        # The shared hub normally receives the commit itself. Capture its
        # revision so the explicit fallback below does not invalidate it twice.
        @material_change_hub_model = Sketchup.active_model
        @material_change_hub_signature = if defined?(MH::ModelHub) && MH::ModelHub.respond_to?(:model_signature)
                                           MH::ModelHub.model_signature
                                         end
        return unless defined?(MH::MaterialHUD) && MH::MaterialHUD.respond_to?(:begin_material_change)
        MH::MaterialHUD.begin_material_change(entities)
      end

      def notify_material_code_change(change_token = nil)
        before_signature = @material_change_hub_signature
        same_model = @material_change_hub_model.equal?(Sketchup.active_model)
        @material_change_hub_signature = @material_change_hub_model = nil
        if defined?(MH::ModelHub) && MH::ModelHub.respond_to?(:invalidate!)
          commit_notified = same_model && before_signature && MH::ModelHub.respond_to?(:model_signature) &&
                            MH::ModelHub.model_signature != before_signature
          MH::ModelHub.invalidate!(:model) unless commit_notified
        end
        if defined?(MH::MaterialHUD) && MH::MaterialHUD.respond_to?(:model_materials_changed)
          if change_token && MH::MaterialHUD.respond_to?(:finish_material_change)
            MH::MaterialHUD.finish_material_change(change_token)
          else
            MH::MaterialHUD.model_materials_changed
          end
        end
        true
      rescue StandardError
        false
      end

      def remove_unused_materials(materials)
        materials = Array(materials).compact.uniq
        return if materials.empty?

        collection = Sketchup.active_model.materials
        return unless collection.respond_to?(:remove)

        used = used_candidate_materials(materials)

        materials.each do |material|
          next unless material
          next if used[material.object_id]

          # A material selected in the Materials tray can be retained by
          # SketchUp even after the last Face/Edge assignment is cleared.
          # Deselect it before removing the now-unused collection item.
          if collection.respond_to?(:current) && collection.respond_to?(:current=)
            begin
              collection.current = nil if collection.current.equal?(material)
            rescue StandardError
              nil
            end
          end
          collection.remove(material)
        rescue StandardError
          nil
        end
      end

      # Material removal runs after the Face/Edge bulk actions. A component
      # definition may have hundreds of instances; checking its child geometry
      # for every instance is unnecessary and is what made bulk deletes lag.
      # Direct materials on each instance are still checked, while a shared
      # definition's contents are visited exactly once.
      def used_candidate_materials(materials)
        candidates = Array(materials).compact.each_with_object({}) do |material, map|
          map[material.object_id] = true
        end
        used = {}
        visited_definitions = {}
        walk = nil
        walk = lambda do |container|
          container.each do |entity|
            next unless entity.valid?

            material = entity.material if entity.respond_to?(:material)
            used[material.object_id] = true if material && candidates[material.object_id]
            back_material = entity.back_material if entity.respond_to?(:back_material)
            used[back_material.object_id] = true if back_material && candidates[back_material.object_id]

            if entity.is_a?(Sketchup::Group)
              walk.call(entity.entities)
            elsif entity.is_a?(Sketchup::ComponentInstance) && entity.definition
              definition = entity.definition
              id = definition.entityID
              next if visited_definitions[id]

              visited_definitions[id] = true
              walk.call(definition.entities)
            end
          end
        end
        walk.call(Sketchup.active_model.entities)
        used
      rescue StandardError
        # A failed usage scan must retain materials rather than risk deleting a
        # material that is still assigned somewhere in the model.
        materials.each_with_object({}) { |material, map| map[material.object_id] = true if material }
      end

      def material_used_in_model?(material)
        each_model_entity(Sketchup.active_model.entities) do |entity|
          return true if entity.respond_to?(:material) && entity.material.equal?(material)
          return true if entity.respond_to?(:back_material) && entity.back_material.equal?(material)
        end

        false
      rescue StandardError
        true
      end

      def normalize_hex(value)
        text = value.to_s.strip
        text = "##{text}" unless text.start_with?('#')
        return text if text.match?(/\A#[0-9a-fA-F]{6}\z/)

        '#d8d8d8'
      end

      def color_to_hex(color)
        format('#%02x%02x%02x', color.red, color.green, color.blue)
      end

      def apply_abf_sheet_type_counts(buckets)
        abf_sheet_type_rows.each do |item|
          thickness = item[:thickness] || item['thickness']
          raw_material = (item[:material] || item['material']).to_s
          material = group_material_code_display(raw_material)
          key = group_row_key(format_thickness(thickness), material)
          row = buckets[key]
          next unless row
          next unless row['code'] == row['default_code']

          quantity = (item[:quantity] || item['quantity'] || row['count']).to_i
          row['count'] = [row['count'].to_i, quantity].max
          row['two_face'] = (item[:quantity_2f] || item['quantity_2f'] || row['two_face']).to_i
          color = item[:color] || item['color']
          row['color'] = abf_color_to_hex(color) if color
        end
      rescue StandardError
        nil
      end

      def apply_cached_abf_sheet_type_counts(buckets, display_code = nil)
        Array(@abf_sheet_type_rows_cache).each do |item|
          thickness = item[:thickness] || item['thickness']
          raw_material = (item[:material] || item['material']).to_s
          material = display_code ? display_code.call(raw_material) : group_material_code_display(raw_material)
          key = group_row_key(format_thickness(thickness), material)
          row = buckets[key]
          next unless row
          next unless row['code'] == row['default_code']

          quantity = (item[:quantity] || item['quantity'] || row['count']).to_i
          row['count'] = [row['count'].to_i, quantity].max
          row['two_face'] = (item[:quantity_2f] || item['quantity_2f'] || row['two_face']).to_i
          color = item[:color] || item['color']
          row['color'] = abf_color_to_hex(color) if color
        end
      rescue StandardError
        nil
      end

      def apply_bottom_face_counts(buckets)
        bottom_face_counts.each do |raw_key, count|
          thickness, raw_material = raw_key.to_s.split('|', 2)
          key = group_row_key(thickness, group_material_code_display(raw_material))
          row = buckets[key]
          next unless row
          next unless row['code'] == row['default_code']

          row['two_face'] = count
        end
      rescue StandardError
        nil
      end

      def apply_cached_bottom_face_counts(buckets, display_code = nil)
        return unless @bottom_face_counts_cache

        @bottom_face_counts_cache.each do |raw_key, count|
          thickness, raw_material = raw_key.to_s.split('|', 2)
          material = display_code ? display_code.call(raw_material) : group_material_code_display(raw_material)
          key = group_row_key(thickness, material)
          row = buckets[key]
          next unless row
          next unless row['code'] == row['default_code']

          row['two_face'] = count
        end
      rescue StandardError
        nil
      end

      def bottom_face_counts
        @bottom_face_counts_cache ||= begin
          counts = Hash.new(0)
          each_model_entity(Sketchup.active_model.entities) do |entity|
            next unless entity.respond_to?(:get_attribute)
            next unless entity.respond_to?(:definition)
            next unless entity.get_attribute('ABF', 'is-bottom-sheet') == true

            raw_material = entity.get_attribute('ABF', 'sheet-type').to_s
            thickness = entity.get_attribute('ABF', 'sheet-thickness')
            next if raw_material.empty? || thickness.nil?

            key = "#{format_thickness(thickness)}|#{raw_material}"
            entity.definition.entities.each do |child|
              next unless child.respond_to?(:get_attribute)

              counts[key] += 1 if child.get_attribute('ABF', 'is-bottom-face') == true
            end
          end
          counts
        end
      end

      def each_model_entity(container, &block)
        container.each do |entity|
          next unless entity.valid?

          yield entity
          each_model_entity(entity.definition.entities, &block) if entity.respond_to?(:definition)
        end
      end

      def surface_material_rows
        targets = {}
        definitions = {}
        scan_face_edge_materials(Sketchup.active_model.entities, targets, definitions, {})

        @surface_material_targets = targets
        targets.values.map do |target|
          material = target[:material]
          {
            'id' => target[:id],
            'name' => material.display_name.to_s,
            'color' => color_to_hex(material.color),
            'faces' => target[:fronts].length + target[:backs].length,
            'edges' => target[:edges].length,
            'groups' => target[:outline_groups].length
          }
        end.sort_by { |row| row['name'].downcase }
      end

      # Keep the original Face & Edge table and its delete controls. Unlike
      # the old scan, include loose and nested geometry too: a Face/Edge that
      # is outside an ABF board must still be removable from this table.
      # Component definitions are visited once to avoid double-counting shared
      # geometry; every edge-only Group/Component instance remains listed.
      def scan_face_edge_materials(container, targets, definitions, outline_ids, definition_id = nil)
        container.each do |entity|
          next unless entity.valid?

          if entity.is_a?(Sketchup::Face)
            add_surface_material_target(targets, entity.material, :fronts, entity, definition_id)
            add_surface_material_target(targets, entity.back_material, :backs, entity, definition_id)
            next
          end

          if entity.is_a?(Sketchup::Edge) && entity.respond_to?(:material)
            add_surface_material_target(targets, entity.material, :edges, entity, definition_id)
            next
          end

          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

          if edge_only_group?(entity) && !outline_ids[entity.persistent_id]
            material = primary_material(entity)
            if material
              outline_ids[entity.persistent_id] = true
              parent = entity.parent
              parent_definition_id = parent.entityID if parent.respond_to?(:entityID)
              add_surface_material_target(targets, material, :outline_groups, entity, parent_definition_id)
            end
          end

          definition = entity.definition
          next unless definition

          id = definition.entityID
          next if definitions[id]

          definitions[id] = true
          scan_face_edge_materials(definition.entities, targets, definitions, outline_ids, id)
        end
      rescue StandardError
        nil
      end

      def add_surface_material_target(targets, material, kind, entity, definition_id)
        return unless material

        id = material.object_id.to_s
        target = targets[id] ||= {
          id: id,
          material: material,
          fronts: [],
          backs: [],
          edges: [],
          outline_groups: [],
          definition_ids: {}
        }
        target[kind] << entity
        target[:definition_ids][definition_id] = true if definition_id
      end


      def edge_only_group?(entity)
        return false unless entity.respond_to?(:definition) && entity.definition

        entities = entity.definition.entities
        has_edges = false
        entities.each do |child|
          return false if child.is_a?(Sketchup::Face)

          has_edges = true if child.is_a?(Sketchup::Edge)
        end
        has_edges
      rescue StandardError
        false
      end

      def clear_surface_material_targets(targets, operation_name, kinds: nil)
        model = Sketchup.active_model
        edited = targets.flat_map { |target| [:fronts, :backs, :edges, :outline_groups].flat_map { |key| Array(target[key]) } }
        change_token = begin_hud_material_change(edited)
        materials = targets.map { |target| target[:material] }.compact.uniq
        @suspend_dirty_tracking = true
        begin
          model.start_operation(operation_name, true)
          targets.each do |target|
            target[:fronts].each { |face| face.material = nil if face.valid? } if kinds.nil? || kinds.include?(:fronts)
            target[:backs].each { |face| face.back_material = nil if face.valid? } if kinds.nil? || kinds.include?(:backs)
            target[:edges].each { |edge| edge.material = nil if edge.valid? && edge.respond_to?(:material=) } if kinds.nil? || kinds.include?(:edges)
            target[:outline_groups].each { |entity| entity.material = nil if entity.valid? && entity.respond_to?(:material=) } if kinds.nil? || kinds.include?(:outline_groups)
          end
          model.commit_operation
        ensure
          @suspend_dirty_tracking = false
        end

        # Do this after commit for the same reason as replace_surface_material:
        # collection.remove can fail while SketchUp still has the transaction
        # open, leaving a visually unused material in its Materials tray.
        remove_unused_materials(materials)

        affected_ids = targets.flat_map do |target|
          target[:definition_ids].keys.flat_map { |id| Array(@definition_record_ids && @definition_record_ids[id]) }
        end
        clear_dirty_entity_ids(affected_ids.uniq)
        clear_dirty_materials(materials)
        @surface_material_targets = nil
        notify_material_code_change(change_token)
        refresh_surface_materials
        model.active_view.invalidate
      end

      def abf_sheet_type_rows
        return @abf_sheet_type_rows_cache if @abf_sheet_type_rows_cache

        # Use the inventory already measured by MH Van. Constructing ABF's
        # private UI tool and invoking scan_types repeated its whole-model scan
        # and coupled this reader to another extension's tool lifecycle.
        rows = {}
        Array(@last_group_scan_items).each do |item|
          material = item['raw_code'].to_s
          thickness = item['thickness_value'].to_f
          key = "#{format_thickness(thickness)}|#{material}"
          row = rows[key] ||= { thickness: thickness, material: material, quantity: 0 }
          row[:quantity] += 1
        end
        @abf_sheet_type_rows_cache = rows.values
      rescue StandardError
        []
      end

      def abf_color_to_hex(value)
        color = Array(value)
        return nil unless color.length >= 3

        format('#%02x%02x%02x', color[0].to_i, color[1].to_i, color[2].to_i)
      end

      def palette_color(seed)
        colors = %w[
          #8c7ad9 #b1843e #e7a72c #d8f5c9 #d93c69 #3a96d8
          #d43ab8 #41d73d #41c8d8 #d5b8cd #4c60d7 #efaa35
        ]
        index = seed.to_s.each_byte.reduce(0) { |sum, byte| sum + byte } % colors.length
        colors[index]
      end

      def abort_operation_safely
        Sketchup.active_model.abort_operation
      rescue StandardError
        nil
      end

      def alert_error(error)
        UI.messagebox("MH Ván lỗi: #{error.message}")
      end

      def html
        <<~HTML
          <!doctype html>
          <html lang="vi">
          <head>
            <meta charset="utf-8">
            <style>
              :root {
                --line: #c8c8c8;
                --header: #f1f1f1;
                --text: #111;
                --muted: #666;
                --blue: #0076c9;
              }
              * { box-sizing: border-box; }
              body {
                margin: 0;
                font: 12px "Segoe UI", Arial, sans-serif;
                color: var(--text);
                background: #fff;
                overflow: hidden;
              }
              .tabs {
                height: 34px;
                display: flex;
                align-items: end;
                gap: 2px;
                padding: 4px 10px 0;
                background: #e7e7e7;
                border-bottom: 1px solid #bdbdbd;
              }
              .tab {
                height: 29px;
                border: 1px solid transparent;
                border-bottom: 0;
                background: transparent;
                padding: 0 14px;
                font: inherit;
                cursor: pointer;
              }
              .tab.active {
                background: #fff;
                border-color: #bdbdbd;
                color: var(--blue);
                font-weight: 600;
              }
              .panel[hidden] { display: none; }
              .toolbar {
                height: 52px;
                display: grid;
                grid-template-columns: 28px 72px minmax(0, 1fr) 86px 74px 88px 34px;
                align-items: center;
                gap: 8px;
                padding: 4px 10px;
                background: var(--header);
                border-bottom: 1px solid #bdbdbd;
              }
              .toolbar .sort {
                border: 0;
                background: transparent;
                font: inherit;
                height: 24px;
                cursor: pointer;
                padding: 0 4px;
                text-align: left;
              }
              .toolbar .sort:hover { color: var(--blue); }
              .tool-btn {
                height: 24px;
                border: 1px solid #9a9a9a;
                background: #fff;
                color: #111;
                font: inherit;
                cursor: pointer;
                padding: 0 8px;
              }
              .tool-btn:hover { border-color: var(--blue); color: var(--blue); }
              .material-head {
                display: grid;
                grid-template-columns: max-content minmax(80px, 1fr) max-content max-content;
                align-items: center;
                gap: 8px;
                min-width: 0;
              }
              .code-option {
                display: inline-flex;
                align-items: center;
                gap: 4px;
                height: 24px;
                color: #111;
                white-space: nowrap;
                user-select: none;
              }
              .code-option input { margin: 0; }
              .search {
                width: 100%;
                min-width: 0;
                height: 24px;
                border: 1px solid #a8a8a8;
                padding: 2px 8px;
                font: inherit;
                color: #000;
                background: #fff;
              }
              .toolbar .help {
                color: #004f9e;
                font-weight: 600;
                text-align: center;
              }
              .fast-toggle {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                gap: 4px;
                height: 24px;
                color: #111;
                white-space: nowrap;
                user-select: none;
              }
              .fast-toggle input { margin: 0; }
              .surface-toolbar {
                height: 52px;
                display: flex;
                align-items: center;
                justify-content: space-between;
                padding: 4px 10px;
                background: var(--header);
                border-bottom: 1px solid #bdbdbd;
              }
              .surface-actions {
                display: flex;
                align-items: center;
                justify-content: flex-end;
                gap: 6px;
              }
              .table-wrap {
                height: calc(100vh - 86px);
                overflow: auto;
              }
              table {
                border-collapse: collapse;
                width: 100%;
                min-width: 0;
                table-layout: fixed;
              }
              .col-eye { width: 30px; }
              .col-thickness { width: 78px; }
              .col-code { width: auto; }
              .col-count { width: 54px; }
              .col-two { width: 74px; }
              .col-reset { width: 74px; }
              .col-color { width: 40px; }
              .col-edit { width: 28px; }
              .col-surface-color { width: 44px; }
              .col-surface-name { width: auto; }
              .col-surface-count { width: 76px; }
              .col-surface-delete { width: 58px; }
              .surface-table th {
                height: 30px;
                padding: 2px 6px;
                text-align: left;
                background: #f7f7f7;
                border-bottom: 1px solid var(--line);
                position: sticky;
                top: 0;
                z-index: 1;
              }
              .surface-table th.count-head,
              .surface-count { text-align: right; }
              .surface-name { overflow: hidden; text-overflow: ellipsis; }
              .surface-delete { text-align: center; }
              .color-chip {
                display: inline-block;
                width: 28px;
                height: 17px;
                border: 1px solid #777;
                vertical-align: middle;
              }
              td {
                height: 30px;
                padding: 2px 6px;
                vertical-align: middle;
                white-space: nowrap;
              }
              .eye-cell { width: 30px; text-align: center; }
              .thickness-cell { width: 78px; color: #111; cursor: pointer; }
              .thickness-cell:hover span { text-decoration: underline; }
              .thickness-cell.muted,
              .color-cell.muted { opacity: .35; }
              .thickness-cell.muted { color: #777; }
              .color-cell.muted .swatch {
                filter: grayscale(1);
                cursor: default;
              }
              .code-cell { width: auto; min-width: 0; }
              .count-cell { width: 54px; text-align: right; color: #000; }
              .two-cell { width: 74px; text-align: center; }
              .reset-cell { width: 74px; text-align: center; }
              .color-cell { width: 40px; text-align: center; }
              .edit-cell { width: 28px; text-align: center; }
              .eye {
                width: 18px;
                height: 18px;
                border: 0;
                background: transparent;
                cursor: pointer;
                padding: 0;
                line-height: 18px;
              }
              .eye.off { opacity: .28; }
              .code {
                width: 100%;
                min-width: 0;
                height: 26px;
                border: 1px solid #8e8e8e;
                padding: 3px 20px;
                font: inherit;
                color: #000;
                background: #fff;
              }
              .count {
                display: block;
                height: 26px;
                line-height: 25px;
                border: 1px solid #8e8e8e;
                border-left: 0;
                padding-right: 20px;
                color: #000;
              }
              .two-input {
                width: 40px;
                height: 28px;
                border: 1px solid #888;
                text-align: center;
                font: inherit;
                background: #fff;
              }
              .reset {
                width: 36px;
                height: 18px;
                border: 0;
                color: #fff;
                background: #ddd;
                font-weight: 700;
                cursor: pointer;
              }
              .reset:hover { background: #b8b8b8; }
              .swatch {
                width: 28px;
                height: 17px;
                border: 1px solid #000;
                padding: 0;
                cursor: pointer;
                background: transparent;
                -webkit-appearance: none;
                appearance: none;
              }
              .swatch::-webkit-color-swatch-wrapper { padding: 0; }
              .swatch::-webkit-color-swatch { border: 0; }
              .pencil {
                width: 18px;
                height: 18px;
                border: 0;
                background: transparent;
                color: #aaa;
                cursor: pointer;
                font-size: 16px;
                line-height: 18px;
              }
              .empty {
                padding: 32px;
                color: var(--muted);
              }
              input[type="checkbox"] { width: 14px; height: 14px; }
            </style>
          </head>
          <body>
            <nav class="tabs" aria-label="Loại vật liệu">
              <button class="tab active" data-tab="nesting">Nesting</button>
              <button class="tab" data-tab="no-nesting">All group/component</button>
              <button class="tab" data-tab="surface">Face &amp; Edge</button>
            </nav>

            <section id="groupPanel" class="panel">
              <div class="toolbar">
                <input id="master" type="checkbox" checked title="Ẩn/hiện tất cả dòng">
                <button class="sort" data-sort="thickness">Độ Dày ▲</button>
                <div class="material-head">
                  <button class="sort" data-sort="code">Vật Liệu ▲</button>
                  <input id="search" class="search" type="search" placeholder="Tìm độ dày / vật liệu">
                  <label class="code-option" title="Hiển thị phần độ dày trong mã vật liệu">
                    <input id="showCodeThickness" type="checkbox" #{group_code_show_thickness? ? 'checked' : ''}>
                    <span>Độ dày</span>
                  </label>
                  <label class="code-option" title="Hiển thị mã sơn/mã hoàn thiện trong mã vật liệu">
                    <input id="showCodePaint" type="checkbox" #{group_code_show_paint? ? 'checked' : ''}>
                    <span>Màu sơn</span>
                  </label>
                </div>
                <div style="text-align:center">2 Mặt</div>
                <button id="stripPaint" class="tool-btn" title="Bỏ phần mã sơn của các dòng đang lọc">Bỏ Sơn</button>
                <label class="fast-toggle" title="Bật: ẩn/hiện dòng bằng temp Tag giống MH Isolate. Tắt: dùng hidden bình thường.">
                  <input id="fastVisibility" type="checkbox" #{fast_visibility_mode? ? 'checked' : ''}>
                  <span>Ẩn nhanh</span>
                </label>
                <div class="help">[?]</div>
              </div>
              <div class="table-wrap">
                <table>
                  <colgroup>
                    <col class="col-eye">
                    <col class="col-thickness">
                    <col class="col-code">
                    <col class="col-count">
                    <col class="col-two">
                    <col class="col-reset">
                    <col class="col-color">
                    <col class="col-edit">
                  </colgroup>
                  <tbody id="rows"></tbody>
                </table>
                <div id="empty" class="empty" hidden>Không tìm thấy Group/Component phù hợp trong model.</div>
              </div>
            </section>

            <section id="surfacePanel" class="panel" hidden>
              <div class="surface-toolbar">
                <strong>Vật liệu Face &amp; Edge</strong>
                <div class="surface-actions">
                  <button id="clearAllFaces" class="tool-btn" title="Chuyển toàn bộ vật liệu Face về Default">Xóa Face</button>
                  <button id="clearAllEdges" class="tool-btn" title="Chuyển toàn bộ vật liệu Edge về Default">Xóa Edge</button>
                  <button id="clearAllSurface" class="tool-btn" title="Chuyển toàn bộ vật liệu Face và Edge về Default">Xóa tất cả</button>
                </div>
              </div>
              <div class="table-wrap">
                <table class="surface-table">
                  <colgroup>
                    <col class="col-surface-color">
                    <col class="col-surface-name">
                    <col class="col-surface-count">
                    <col class="col-surface-count">
                    <col class="col-surface-count">
                    <col class="col-surface-delete">
                  </colgroup>
                  <thead><tr><th></th><th>Vật liệu</th><th class="count-head">Face</th><th class="count-head">Edge</th><th class="count-head">Group nét</th><th></th></tr></thead>
                  <tbody id="surfaceRows"></tbody>
                </table>
                <div id="surfaceEmpty" class="empty" hidden>Không có vật liệu trên Face hoặc Edge.</div>
              </div>
            </section>

            <script>
              let rows = [];
              let surfaceRows = [];
              let sortKey = 'thickness';
              let sortDir = 1;
              let filterText = '';
              let groupScope = 'nesting';
              let eyeButtons = new Map();

              function callRuby(name, payload = {}) {
                if (window.sketchup && sketchup[name]) {
                  sketchup[name](JSON.stringify(payload));
                }
              }

              function syncFastVisibility(data) {
                document.getElementById('fastVisibility').checked = !!data.enabled;
              }

              function escapeHtml(value) {
                return String(value ?? '').replace(/[&<>"']/g, (ch) => ({
                  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
                })[ch]);
              }

              function renderRows(data) {
                const active = document.activeElement;
                if (active && active.classList && active.classList.contains('code')) return;
                rows = Array.isArray(data) ? data : [];
                draw();
              }

              function updateVisibility(data) {
                if (!Array.isArray(data)) return;
                const byKey = new Map(rows.map((row) => [row.key, row]));
                data.forEach((item) => {
                  const row = byKey.get(item.key);
                  if (!row) return;
                  row.visible = !!item.visible;
                  row.all_hidden = !!item.all_hidden;
                  const button = eyeButtons.get(item.key);
                  if (button) {
                    button.classList.toggle('off', !row.visible);
                    button.setAttribute('aria-pressed', String(row.visible));
                  }
                });
                syncMasterToggle();
              }

              function patchRows(payload) {
                const active = document.activeElement;
                const editing = active && active.classList && active.classList.contains('code');
                const removeKeys = new Set(Array.isArray(payload?.remove_keys) ? payload.remove_keys : []);
                rows = rows.filter((row) => !removeKeys.has(row.key));

                const incoming = Array.isArray(payload?.rows) ? payload.rows : [];
                const byKey = new Map(rows.map((row, index) => [row.key, index]));
                incoming.forEach((row) => {
                  const index = byKey.get(row.key);
                  if (index === undefined) {
                    byKey.set(row.key, rows.length);
                    rows.push(row);
                  } else {
                    rows[index] = row;
                  }
                });
                if (!editing) draw();
              }

              function renderSurfaceRows(data) {
                surfaceRows = Array.isArray(data) ? data : [];
                const body = document.getElementById('surfaceRows');
                const empty = document.getElementById('surfaceEmpty');
                empty.hidden = surfaceRows.length > 0;
                body.innerHTML = surfaceRows.map((row) => `
                  <tr>
                    <td><span class="color-chip" style="background:${escapeHtml(row.color || '#d8d8d8')}"></span></td>
                    <td class="surface-name" title="${escapeHtml(row.name)}">${escapeHtml(row.name)}</td>
                    <td class="surface-count">${escapeHtml(row.faces || 0)}</td>
                    <td class="surface-count">${escapeHtml(row.edges || 0)}</td>
                    <td class="surface-count">${escapeHtml(row.groups || 0)}</td>
                    <td class="surface-delete"><button class="reset" title="Chuyển material này về Default" data-action="clear-surface" data-surface-id="${escapeHtml(row.id)}">×</button></td>
                  </tr>
                `).join('');
                document.getElementById('clearAllFaces').disabled = !surfaceRows.some((row) => Number(row.faces || 0) > 0);
                document.getElementById('clearAllEdges').disabled = !surfaceRows.some((row) => Number(row.edges || 0) > 0);
                document.getElementById('clearAllSurface').disabled = surfaceRows.length === 0;
              }

              function rowMatches(row) {
                const query = filterText.trim().toLowerCase();
                if (!query) return true;
                const haystack = `${row.thickness || ''} ${row.thickness_value || ''} ${row.code || ''}`.toLowerCase();
                return query.split(/\\s+/).every((part) => haystack.includes(part));
              }

              function visibleRows() {
                return rows.filter(rowMatches);
              }

              function sortedRows() {
                const copy = visibleRows();
                copy.sort((a, b) => {
                  let av = sortKey === 'thickness' ? Number(a.thickness_value || 0) : String(a.code || '').toLowerCase();
                  let bv = sortKey === 'thickness' ? Number(b.thickness_value || 0) : String(b.code || '').toLowerCase();
                  if (av < bv) return -sortDir;
                  if (av > bv) return sortDir;
                  return String(a.code || '').localeCompare(String(b.code || ''));
                });
                return copy;
              }

              function draw() {
                const body = document.getElementById('rows');
                const empty = document.getElementById('empty');
                const displayRows = sortedRows();
                empty.hidden = displayRows.length > 0;
                const scopeText = groupScope === 'no-nesting' ? 'Group/Component lớp ngoài cùng' : 'Group/Component dạng tấm ABF';
                empty.textContent = rows.length === 0 ? `Không tìm thấy ${scopeText} trong model.` : 'Không có dòng phù hợp.';
                body.innerHTML = displayRows.map((row, index) => `
                  <tr data-index="${index}">
                    <td class="eye-cell">
                      <button class="eye ${row.visible ? '' : 'off'}" title="Ẩn/hiện trong model" data-action="visible" data-key="${escapeHtml(row.key)}">●</button>
                    </td>
                    <td class="thickness-cell ${row.mixed_thickness ? 'muted' : ''}" title="Cô lập dòng này" data-action="isolate" data-key="${escapeHtml(row.key)}"><span style="color:#0084d7">${escapeHtml(row.mixed_thickness ? 'Nhiều' : row.thickness)}</span>${row.mixed_thickness ? '' : '&nbsp;&nbsp;mm'}</td>
                    <td class="code-cell">
                      <input class="code" value="${escapeHtml(row.code)}" data-action="code" data-key="${escapeHtml(row.key)}">
                    </td>
                    <td class="count-cell"><span class="count">${escapeHtml(row.count)}</span></td>
                    <td class="two-cell">${Number(row.two_face || 0) > 0 ? `<input class="two-input" readonly value="${escapeHtml(row.two_face)}">` : ''}</td>
                    <td class="reset-cell"><button class="reset" title="Xóa mã nhập tay, về mã mặc định" data-action="reset" data-key="${escapeHtml(row.key)}">×</button></td>
                    <td class="color-cell ${row.mixed_color ? 'muted' : ''}"><input class="swatch" type="color" value="${escapeHtml(row.color || '#d8d8d8')}" data-action="color" data-key="${escapeHtml(row.key)}" ${row.mixed_color ? 'disabled' : ''}></td>
                    <td class="edit-cell"><button class="pencil" title="Chọn các object của dòng" data-action="select" data-key="${escapeHtml(row.key)}">♢</button></td>
                  </tr>
                `).join('');
                eyeButtons = new Map(Array.from(body.querySelectorAll('[data-action="visible"]'), (button) => [button.dataset.key, button]));
                syncMasterToggle();
              }

              function syncMasterToggle() {
                const master = document.getElementById('master');
                const visibleCount = rows.filter((row) => row.visible).length;
                master.checked = rows.length > 0 && visibleCount === rows.length;
                master.indeterminate = visibleCount > 0 && visibleCount < rows.length;
              }

              function rowByKey(key) {
                return rows.find((row) => row.key === key);
              }

              function commitCodeInput(el) {
                const row = rowByKey(el.dataset.key);
                if (!row) return;
                const code = el.value;
                if (code === String(row.code || '')) return;
                if (el.dataset.pendingCode === code) return;
                el.dataset.pendingCode = code;
                row.code = code || 'Default';
                if (!code) el.value = 'Default';
                callRuby('set_code', { ids: row.ids, code });
              }

              document.addEventListener('change', (event) => {
                const el = event.target;
                const action = el.dataset.action;
                if (!action) return;
                const row = rowByKey(el.dataset.key);
                if (!row) return;
                if (action === 'code') commitCodeInput(el);
                if (action === 'color') callRuby('set_color', { ids: row.ids, color: el.value });
              });

              document.addEventListener('blur', (event) => {
                const el = event.target;
                if (el && el.dataset && el.dataset.action === 'code') commitCodeInput(el);
              }, true);

              document.addEventListener('keydown', (event) => {
                const el = event.target;
                if (!el || !el.dataset || el.dataset.action !== 'code') return;
                if (event.key === 'Enter') {
                  event.preventDefault();
                  commitCodeInput(el);
                  el.blur();
                }
              });

              document.addEventListener('click', (event) => {
                const el = event.target.closest('[data-action]');
                if (!el) return;
                if (el.dataset.action === 'clear-surface') {
                  el.disabled = true;
                  callRuby('clear_surface_material', { id: el.dataset.surfaceId });
                  return;
                }
                const row = rowByKey(el.dataset.key);
                if (!row) return;
                if (el.dataset.action === 'visible') callRuby('set_visible', { key: row.key, ids: row.ids, ancestor_ids: row.ancestor_ids || [], visible: !row.visible });
                if (el.dataset.action === 'reset') callRuby('reset_code', { ids: row.ids });
                if (el.dataset.action === 'select') callRuby('select_row', { ids: row.ids });
                if (el.dataset.action === 'isolate') callRuby('isolate_row', { key: row.key, ids: row.ids });
              });

              document.querySelectorAll('.sort').forEach((button) => {
                button.addEventListener('click', () => {
                  const key = button.dataset.sort;
                  sortDir = sortKey === key ? -sortDir : 1;
                  sortKey = key;
                  draw();
                });
              });

              document.getElementById('search').addEventListener('input', (event) => {
                filterText = event.target.value;
                draw();
              });

              document.getElementById('fastVisibility').addEventListener('change', (event) => {
                callRuby('set_fast_visibility', { enabled: event.target.checked });
              });

              function syncGroupCodeOptions() {
                callRuby('set_group_code_options', {
                  show_thickness: document.getElementById('showCodeThickness').checked,
                  show_paint: document.getElementById('showCodePaint').checked
                });
              }

              document.getElementById('showCodeThickness').addEventListener('change', syncGroupCodeOptions);
              document.getElementById('showCodePaint').addEventListener('change', syncGroupCodeOptions);

              document.getElementById('master').addEventListener('change', (event) => {
                const payloadRows = rows.map((row) => ({
                  key: row.key,
                  ids: row.ids || [],
                  ancestor_ids: row.ancestor_ids || []
                }));
                callRuby('set_visible_rows', { rows: payloadRows, visible: event.target.checked });
              });

              document.getElementById('stripPaint').addEventListener('click', () => {
                const ids = visibleRows().flatMap((row) => row.ids);
                callRuby('strip_paint_codes', { ids });
              });

              document.querySelectorAll('.tab').forEach((button) => {
                button.addEventListener('click', () => {
                  const tab = button.dataset.tab;
                  const surfaceActive = tab === 'surface';
                  document.querySelectorAll('.tab').forEach((tab) => tab.classList.toggle('active', tab === button));
                  document.getElementById('groupPanel').hidden = surfaceActive;
                  document.getElementById('surfacePanel').hidden = !surfaceActive;
                  if (surfaceActive) {
                    callRuby('refresh_surface_materials');
                  } else {
                    groupScope = tab;
                    draw();
                    callRuby(tab === 'no-nesting' ? 'refresh_no_nesting' : 'refresh_nesting');
                  }
                });
              });

              document.getElementById('clearAllSurface').addEventListener('click', (event) => {
                event.currentTarget.disabled = true;
                callRuby('clear_all_surface_materials');
              });

              document.getElementById('clearAllFaces').addEventListener('click', () => {
                callRuby('clear_all_face_materials');
              });

              document.getElementById('clearAllEdges').addEventListener('click', () => {
                callRuby('clear_all_edge_materials');
              });

              if (window.sketchup) sketchup.ready();
            </script>
          </body>
          </html>
        HTML
      end
    end

    unless defined?(@menu_loaded) && @menu_loaded
      command = UI::Command.new('MH Ván - Loại Ván') { MH::Van.show }
      command.tooltip = 'MH Ván - Loại Ván'
      command.status_bar_text = 'Mở bảng Loại Ván của model hiện tại'
      UI.menu('Extensions').add_item(command)
      @menu_loaded = true
    end

    if @dialog && @dialog.visible?
      @dialog.set_html(html)
      refresh
      start_auto_refresh
    end
  end
end
