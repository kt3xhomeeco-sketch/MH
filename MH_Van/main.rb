# encoding: UTF-8

require 'sketchup.rb'
require 'json'
begin
  require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
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
    AUTO_REFRESH_SECONDS = 1.0

    if defined?(Sketchup::EntityObserver)
      class EntityChangeObserver < Sketchup::EntityObserver
        def onChangeEntity(entity)
          MH::Van.mark_dirty_entity(entity)
        end

        def onEraseEntity(entity)
          MH::Van.mark_dirty_entity(entity)
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

    if defined?(Sketchup::EntitiesObserver)
      class DefinitionEntitiesChangeObserver < Sketchup::EntitiesObserver
        def onElementAdded(*args)
          MH::Van.mark_dirty_definition_entities(args.find { |item| item.is_a?(Sketchup::Entities) })
        end

        def onElementModified(*args)
          MH::Van.mark_dirty_definition_entities(args.find { |item| item.is_a?(Sketchup::Entities) })
        end

        def onElementRemoved(*args)
          MH::Van.mark_dirty_definition_entities(args.find { |item| item.is_a?(Sketchup::Entities) })
        end

        def onEraseEntities(*args)
          MH::Van.mark_dirty_definition_entities(args.find { |item| item.is_a?(Sketchup::Entities) })
        end
      end
    end

    class << self
      def show
        build_dialog unless @dialog
        refresh
        @dialog.show
        @dialog.bring_to_front
        start_auto_refresh
      end

      def refresh
        sync_material_overrides
        rows = scan_rows
        @last_rows = rows
        attach_part_observers((@last_records_by_id || {}).values)
        attach_materials_observer
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
        dirty_entity_ids = @dirty_entity_ids ? @dirty_entity_ids.keys : []
        dirty_ids = detect_changed_record_ids(dirty_entity_ids)
        dirty_materials = @dirty_materials ? @dirty_materials.values : []
        @dirty_entity_ids = {}
        @dirty_materials = {}

        if dirty_materials.any?
          material_ids = cached_ids_for_materials(dirty_materials)
          dirty_ids.concat(material_ids)
        end

        dirty_ids.uniq!
        return if dirty_ids.empty?

        patch_cached_rows_for_ids(dirty_ids) || refresh
      end

      def mark_dirty_entity(entity)
        return unless entity && entity.valid?

        @dirty_entity_ids ||= {}
        @dirty_entity_ids[entity.persistent_id] = true
      rescue StandardError
        nil
      end

      def mark_dirty_material(material)
        return unless material

        @dirty_materials ||= {}
        @dirty_materials[material.object_id] = material
      rescue StandardError
        nil
      end

      def mark_dirty_definition_entities(entities)
        return unless entities && entities.respond_to?(:parent)

        definition = entities.parent
        return unless definition && definition.respond_to?(:entityID)

        ids = @definition_record_ids && @definition_record_ids[definition.entityID]
        return unless ids && ids.any?

        @dirty_entity_ids ||= {}
        ids.each { |id| @dirty_entity_ids[id.to_i] = true }
      rescue StandardError
        nil
      end

      def clear_dirty_entity_ids(ids)
        return unless @dirty_entity_ids

        Array(ids).each { |id| @dirty_entity_ids.delete(id.to_i) }
      rescue StandardError
        nil
      end

      def scan_rows
        @abf_sheet_type_rows_cache = nil
        @sheet_type_thickness_cache = nil
        @sheet_type_thickness_candidates_cache = nil
        records = part_records
        @last_records_by_id = {}
        @record_signatures = {}
        @record_row_keys = {}
        @definition_record_ids = Hash.new { |hash, key| hash[key] = [] }
        buckets = {}

        records.each do |record|
          entity = record[:entity]
          @last_records_by_id[entity.persistent_id] = record
          if entity.respond_to?(:definition) && entity.definition
            @definition_record_ids[entity.definition.entityID] << entity.persistent_id
          end
          default_code = default_material_code(entity)
          thickness = thickness_mm(entity, record[:transform], default_code)
          code = default_code
          color = entity.get_attribute(DICT, ATTR_COLOR, material_color(entity, code)).to_s
          key = "#{format_thickness(thickness)}|#{code}"
          @record_row_keys[entity.persistent_id] = key
          @record_signatures[entity.persistent_id] = record_signature(entity, record[:transform], thickness)

          buckets[key] ||= {
            'key' => key,
            'thickness' => format_thickness(thickness),
            'thickness_value' => thickness,
            'code' => code,
            'default_code' => default_code,
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
          record_visible = record_visible?(record)
          row['visible'] ||= record_visible
          row['all_hidden'] &&= !record_visible
          row['ids'] << entity.persistent_id
          row['ancestor_ids'].concat(record[:ancestor_ids])
          row['paths'] << {
            'id' => entity.persistent_id,
            'ancestor_ids' => record[:ancestor_ids]
          }
        end

        buckets.each_value do |row|
          row['ids'].uniq!
          row['ancestor_ids'].uniq!
        end

        apply_abf_sheet_type_counts(buckets)
        apply_bottom_face_counts(buckets)
        buckets.values.sort_by { |row| [row['thickness_value'].to_f, row['code'].downcase] }
      end

      def set_visible(payload_json)
        payload = parse_json(payload_json)
        visible = !!payload['visible']
        entities = entities_from_ids(payload['ids'])
        ancestors = entities_from_ids(payload['ancestor_ids'])
        return if entities.empty?

        model = Sketchup.active_model
        model.start_operation(visible ? 'MH Van - Hiện dòng' : 'MH Van - Ẩn dòng', true)
        if visible
          (ancestors + entities).uniq.each do |entity|
            next unless entity.valid?

            entity.hidden = false
            entity.layer.visible = true if entity.respond_to?(:layer) && entity.layer.respond_to?(:visible=)
          end
        else
          entities.each { |entity| entity.hidden = true if entity.valid? }
        end
        model.commit_operation
        refresh_visibility
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def set_code(payload_json)
        payload = parse_json(payload_json)
        code = canonical_material_code(payload['code'].to_s.strip)
        entities = entities_from_ids(payload['ids'])
        return if entities.empty?
        return reset_code(payload_json) if code.empty?

        model = Sketchup.active_model
        model.start_operation('MH Van - Đổi mã vật liệu', true)
        current_materials = entities.map { |entity| primary_material(entity) if entity.valid? }.compact.uniq
        target_material = material_for_code_change(code, current_materials, entities)
        entities.each do |entity|
          next unless entity.valid?

          assign_material_code(entity, code, target_material)
          entity.delete_attribute(DICT, ATTR_CODE)
          entity.delete_attribute(DICT, ATTR_ORIGINAL_CODE)
        end
        remove_unused_materials(current_materials - [target_material])
        model.commit_operation
        affected_ids = entities.map(&:persistent_id)
        clear_dirty_entity_ids(affected_ids)
        patch_cached_rows_for_ids(affected_ids.uniq) || refresh
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def strip_paint_codes(payload_json = nil)
        payload = parse_json(payload_json || '{}')
        ids = Array(payload['ids']).map(&:to_i).reject(&:zero?)
        entities = if ids.empty?
          part_records.map { |record| record[:entity] }
        else
          entities_from_ids(ids)
        end
        entities = entities.select { |entity| entity && entity.valid? && part_like?(entity) }
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

        model = Sketchup.active_model
        model.start_operation('MH Van - Bỏ mã sơn', true)
        changes.each do |entity, new_code|
          next unless entity.valid?

          assign_material_code(entity, new_code, material_by_name(new_code, primary_material(entity)))
          entity.delete_attribute(DICT, ATTR_CODE)
          entity.delete_attribute(DICT, ATTR_ORIGINAL_CODE)
          entity.delete_attribute(DICT, ATTR_COLOR)
        end
        remove_unused_materials(old_materials)
        model.commit_operation
        refresh
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def reset_code(payload_json)
        payload = parse_json(payload_json)
        entities = entities_from_ids(payload['ids'])
        return if entities.empty?

        model = Sketchup.active_model
        model.start_operation('MH Van - Reset mã vật liệu', true)
        entities.each do |entity|
          next unless entity.valid?

          entity.delete_attribute(DICT, ATTR_CODE)
          entity.delete_attribute(DICT, ATTR_ORIGINAL_CODE)
        end
        model.commit_operation
        patch_cached_rows_for_ids(entities.map(&:persistent_id)) || refresh
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
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def select_row(payload_json)
        payload = parse_json(payload_json)
        entities = entities_from_ids(payload['ids'])
        model = Sketchup.active_model
        model.selection.clear
        entities.each { |entity| model.selection.add(entity) if entity.valid? && entity_visible_in_model?(entity) }
        model.active_view.zoom(model.selection) unless model.selection.empty?
      rescue StandardError => e
        alert_error(e)
      end

      def clear_all_overrides
        entities = part_records.map { |record| record[:entity] }.select do |entity|
          entity.get_attribute(DICT, ATTR_CODE) ||
            entity.get_attribute(DICT, ATTR_ORIGINAL_CODE) ||
            entity.get_attribute(DICT, ATTR_COLOR)
        end
        return if entities.empty?

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
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      def sync_material_overrides
        targets = part_records.map { |record| record[:entity] }.select do |entity|
          next false unless entity.valid?

          code = entity.get_attribute(DICT, ATTR_CODE).to_s.strip
          !code.empty?
        end
        return if targets.empty?

        model = Sketchup.active_model
        model.start_operation('MH Van - Đồng bộ mã vật liệu', true)
        old_materials = []
        targets.each do |entity|
          next unless entity.valid?

          code = entity.get_attribute(DICT, ATTR_CODE).to_s.strip
          next if code.empty?

          material = primary_material(entity)
          if !material || material.display_name.to_s != code
            old_materials << material
            assign_material_code(entity, code)
          end
          entity.delete_attribute(DICT, ATTR_CODE)
          entity.delete_attribute(DICT, ATTR_ORIGINAL_CODE)
          entity.delete_attribute(DICT, ATTR_COLOR)
        end
        remove_unused_materials(old_materials)
        model.commit_operation
        model.active_view.invalidate
      rescue StandardError => e
        abort_operation_safely
        alert_error(e)
      end

      private

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
        @dialog.add_action_callback('set_visible') { |_ctx, payload| set_visible(payload) }
        @dialog.add_action_callback('set_code') { |_ctx, payload| set_code(payload) }
        @dialog.add_action_callback('reset_code') { |_ctx, payload| reset_code(payload) }
        @dialog.add_action_callback('set_color') { |_ctx, payload| set_color(payload) }
        @dialog.add_action_callback('select_row') { |_ctx, payload| select_row(payload) }
        @dialog.add_action_callback('strip_paint_codes') { |_ctx, payload| strip_paint_codes(payload) }
        @dialog.add_action_callback('clear_all_overrides') { clear_all_overrides }
        @dialog.set_on_closed do
          stop_auto_refresh
          @dialog = nil
        end
      end

      def start_auto_refresh
        return if @refresh_timer_id

        @refresh_timer_id = UI.start_timer(AUTO_REFRESH_SECONDS, true) do
          if @dialog && @dialog.visible?
            refresh_dirty_rows
            refresh_visibility
          else
            stop_auto_refresh
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

      def parse_json(payload_json)
        JSON.parse(payload_json.to_s)
      rescue JSON::ParserError
        {}
      end

      def attach_part_observers(records)
        return unless defined?(EntityChangeObserver)

        @entity_observer ||= EntityChangeObserver.new
        @definition_entities_observer ||= DefinitionEntitiesChangeObserver.new if defined?(DefinitionEntitiesChangeObserver)
        @observed_entity_ids ||= {}
        @observed_definition_ids ||= {}
        records.each do |record|
          entity = record[:entity]
          next unless entity && entity.valid?

          id = entity.persistent_id
          unless @observed_entity_ids[id]
            entity.add_observer(@entity_observer)
            @observed_entity_ids[id] = true
          end

          next unless @definition_entities_observer
          next unless entity.respond_to?(:definition) && entity.definition

          definition_id = entity.definition.entityID
          next if @observed_definition_ids[definition_id]

          entity.definition.entities.add_observer(@definition_entities_observer)
          @observed_definition_ids[definition_id] = true
        rescue StandardError
          nil
        end
      end

      def attach_materials_observer
        return if @materials_observer_attached
        return unless defined?(MaterialsChangeObserver)

        Sketchup.active_model.materials.add_observer(MaterialsChangeObserver.new)
        @materials_observer_attached = true
      rescue StandardError
        @materials_observer_attached = true
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

      def detect_changed_record_ids(force_ids = [])
        return [] unless @last_records_by_id && @record_signatures

        force_lookup = {}
        Array(force_ids).each { |id| force_lookup[id.to_i] = true }
        changed = []
        @last_records_by_id.each do |id, record|
          next if force_lookup.any? && !force_lookup[id.to_i]

          entity = record[:entity]
          unless entity && entity.valid?
            changed << id
            next
          end

          refresh_record_transform(record)
          signature = record_signature(entity, record[:transform], record_key_thickness(@record_row_keys && @record_row_keys[id]))
          next if signature == @record_signatures[id]

          @record_signatures[id] = signature
          key = record_row_key(record)
          next if key && key == (@record_row_keys && @record_row_keys[id])

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
          unless entity && entity.valid? && part_like?(entity)
            @record_signatures.delete(id) if @record_signatures
            @record_row_keys.delete(id) if @record_row_keys
            next
          end

          refresh_record_transform(record)
          add_record_to_bucket(new_buckets, record)
        end

        new_buckets.each_value do |new_row|
          existing = @last_rows.find { |row| row['key'] == new_row['key'] }
          if existing
            merge_cached_row(existing, new_row)
          else
            @last_rows << new_row
          end
          touched_keys << new_row['key']
        end

        @last_rows.sort_by! { |row| [row['thickness_value'].to_f, row['code'].to_s.downcase] }
        touched_keys.uniq!
        remove_keys.uniq!

        patch_rows = @last_rows.select { |row| touched_keys.include?(row['key']) }
        execute('patchRows', { 'rows' => patch_rows, 'remove_keys' => remove_keys })
        true
      end

      def add_record_to_bucket(buckets, record)
        entity = record[:entity]
        default_code = default_material_code(entity)
        thickness = thickness_mm(entity, record[:transform], default_code)
        code = default_code
        color = material_color(entity, code).to_s
        key = "#{format_thickness(thickness)}|#{code}"

        buckets[key] ||= {
          'key' => key,
          'thickness' => format_thickness(thickness),
          'thickness_value' => thickness,
          'code' => code,
          'default_code' => default_code,
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
      end

      def record_row_key(record)
        entity = record[:entity]
        return nil unless entity && entity.valid? && part_like?(entity)

        default_code = default_material_code(entity)
        thickness = thickness_mm(entity, record[:transform], default_code)
        "#{format_thickness(thickness)}|#{default_code}"
      rescue StandardError
        nil
      end

      def refresh_record_transform(record)
        transform = Geom::Transformation.new
        Array(record[:ancestor_ids]).each do |id|
          ancestor = Sketchup.active_model.find_entity_by_persistent_id(id.to_i)
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
        refresh_cached_row_state(existing)
      end

      def refresh_cached_row_state(row)
        row['count'] = Array(row['ids']).length
        row['ancestor_ids'] = Array(row['paths']).flat_map { |path| Array(path['ancestor_ids']) }.uniq
        state = row_visibility_from_paths(row['paths'])
        row['visible'] = state[:visible]
        row['all_hidden'] = state[:all_hidden]
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

      def walk_entities(container, out, ancestors, transform)
        container.each do |entity|
          next unless entity.valid?

          entity_transform = entity.respond_to?(:transformation) ? transform * entity.transformation : transform
          if part_like?(entity)
            out << {
              entity: entity,
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

        record[:ancestor_ids].all? do |id|
          ancestor = Sketchup.active_model.find_entity_by_persistent_id(id.to_i)
          ancestor && ancestor.valid? && entity_visible_in_model?(ancestor)
        end
      end

      def row_visibility_from_paths(paths)
        any_visible = false
        all_hidden = true

        Array(paths).each do |path|
          entity = Sketchup.active_model.find_entity_by_persistent_id(path['id'].to_i)
          next unless entity && entity.valid?

          visible = entity_visible_in_model?(entity) &&
                    Array(path['ancestor_ids']).all? do |id|
                      ancestor = Sketchup.active_model.find_entity_by_persistent_id(id.to_i)
                      ancestor && ancestor.valid? && entity_visible_in_model?(ancestor)
                    end
          any_visible ||= visible
          all_hidden &&= !visible
        end

        { visible: any_visible, all_hidden: all_hidden }
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
        return true unless entity.respond_to?(:layer)

        layer = entity.layer
        return true unless layer && layer.respond_to?(:visible?)

        layer.visible?
      rescue StandardError
        true
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
        Array(ids).map { |id| Sketchup.active_model.find_entity_by_persistent_id(id.to_i) }.compact
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
        transform ||= entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new
        candidates = [
          bounds_thickness_mm(entity, transform),
          world_bounds_thickness_mm(entity)
        ].compact
        return nil if candidates.empty?

        expected = expected_thickness.to_f if expected_thickness
        value = if expected && expected.positive?
                  candidates.min_by { |candidate| (candidate - expected).abs }
                else
                  candidates.min
                end
        value.round(1)
      end

      def record_key_thickness(key)
        key.to_s.split('|', 2).first.to_f
      end

      def thickness_mm(entity, transform = nil, material = nil)
        local_thickness = bounds_thickness_mm(entity, transform)
        world_thickness = world_bounds_thickness_mm(entity)

        candidate = closest_sheet_type_thickness(material, [local_thickness, world_thickness])
        return candidate if candidate

        return local_thickness if local_thickness && world_thickness && (local_thickness - world_thickness).abs <= 0.2

        geometry_thickness = largest_face_thickness_mm(entity, transform)
        return geometry_thickness if geometry_thickness

        local_thickness || world_thickness || 0.0
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

      def closest_sheet_type_thickness(material, values)
        candidates = sheet_type_thickness_candidates(material)
        return nil if candidates.empty?

        Array(values).compact.each do |value|
          match = candidates.min_by { |candidate| (candidate - value).abs }
          return match if match && (match - value).abs <= 1.0
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
        [
          transform.xaxis.length,
          transform.yaxis.length,
          transform.zaxis.length
        ]
      rescue StandardError
        [1.0, 1.0, 1.0]
      end

      def format_thickness(value)
        rounded = value.to_f.round(1)
        if (rounded - rounded.round).abs < 0.05
          rounded.round.to_s
        else
          rounded.to_s
        end
      end

      def default_material_code(entity)
        material = entity.respond_to?(:material) ? entity.material : nil
        material ? material.display_name.to_s : 'Default'
      end

      def canonical_material_code(code)
        text = code.to_s.strip
        return text if text.empty?

        if defined?(MH::MaterialCode) && MH::MaterialCode.respond_to?(:parse) && MH::MaterialCode.respond_to?(:canonical)
          parsed = MH::MaterialCode.parse(text)
          return text if parsed[:finish_code].to_s.strip.empty?

          canonical = MH::MaterialCode.canonical(text).to_s.strip
          return canonical unless canonical.empty?
        end

        text
      rescue StandardError
        text
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

      def original_or_default_material_code(entity)
        original = entity.get_attribute(DICT, ATTR_ORIGINAL_CODE).to_s.strip
        original.empty? ? default_material_code(entity) : original
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

      def remember_original_material(entity)
        return if entity.get_attribute(DICT, ATTR_ORIGINAL_CODE)

        material = primary_material(entity)
        entity.set_attribute(DICT, ATTR_ORIGINAL_CODE, material.display_name.to_s) if material
      end

      def assign_material_code(entity, code, material = nil)
        return unless entity.respond_to?(:material=)

        material ||= material_by_name(code, primary_material(entity))
        entity.material = material
      end

      def reset_material_code(entity, original_code)
        original_code = original_code.to_s.strip
        return if original_code.empty?

        current = primary_material(entity)
        existing = Sketchup.active_model.materials[original_code]
        if existing
          entity.material = existing if entity.respond_to?(:material=)
        elsif current
          current.name = original_code
          entity.material = current if entity.respond_to?(:material=)
        else
          assign_material_code(entity, original_code)
        end
      rescue StandardError
        assign_material_code(entity, original_code)
      end

      def material_for_code_change(code, current_materials, target_entities = [])
        name = code.to_s.strip
        return nil if name.empty?

        existing = Sketchup.active_model.materials[name]
        return existing if existing

        target_ids = Array(target_entities).select { |entity| entity && entity.valid? }.map(&:persistent_id)
        if current_materials.length == 1 && material_only_used_by_cached_parts?(current_materials.first, target_ids)
          material = current_materials.first
          material.name = name
          return material
        end

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
        name = name.to_s.strip
        return nil if name.empty?

        materials = Sketchup.active_model.materials
        material = materials[name]
        return material if material

        material = materials.add(name)
        material.color = source_material.color if source_material
        material
      end

      def remove_unused_materials(materials)
        materials = Array(materials).compact.uniq
        return if materials.empty?

        collection = Sketchup.active_model.materials
        return unless collection.respond_to?(:remove)

        materials.each do |material|
          next unless material
          next if material_used_in_model?(material)

          collection.remove(material)
        rescue StandardError
          nil
        end
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

      def two_face?(entity, transform = nil)
        attr = entity.get_attribute(DICT, ATTR_TWO_FACE)
        return attr == true || attr.to_s == 'true' if !attr.nil?

        return false unless defined?(ABF::SheetTypesTool)
        return false unless defined?(ABF::NestingUtil)
        return false unless ABF::NestingUtil.respond_to?(:get_b2_faces)

        tool = abf_sheet_types_tool
        group_transform = transform || (entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new)
        b2_faces = ABF::NestingUtil.get_b2_faces(entity, group_transform)
        tool.check_if_2faces_cnc(entity, group_transform, b2_faces) == true
      rescue StandardError
        false
      end

      def abf_sheet_types_tool
        @abf_sheet_types_tool ||= ABF::SheetTypesTool.send(:new)
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
          material = (item[:material] || item['material']).to_s
          key = "#{format_thickness(thickness)}|#{material}"
          row = buckets[key]
          next unless row
          next unless row['code'] == row['default_code']

          row['count'] = (item[:quantity] || item['quantity'] || row['count']).to_i
          row['two_face'] = (item[:quantity_2f] || item['quantity_2f'] || row['two_face']).to_i
          color = item[:color] || item['color']
          row['color'] = abf_color_to_hex(color) if color
        end
      rescue StandardError
        nil
      end

      def apply_bottom_face_counts(buckets)
        bottom_face_counts.each do |key, count|
          row = buckets[key]
          next unless row
          next unless row['code'] == row['default_code']

          row['two_face'] = count
        end
      rescue StandardError
        nil
      end

      def bottom_face_counts
        counts = Hash.new(0)
        each_model_entity(Sketchup.active_model.entities) do |entity|
          next unless entity.respond_to?(:get_attribute)
          next unless entity.respond_to?(:definition)
          next unless entity.get_attribute('ABF', 'is-bottom-sheet') == true

          material = entity.get_attribute('ABF', 'sheet-type').to_s
          thickness = entity.get_attribute('ABF', 'sheet-thickness')
          next if material.empty? || thickness.nil?

          key = "#{format_thickness(thickness)}|#{material}"
          entity.definition.entities.each do |child|
            next unless child.respond_to?(:get_attribute)

            counts[key] += 1 if child.get_attribute('ABF', 'is-bottom-face') == true
          end
        end
        counts
      end

      def each_model_entity(container, &block)
        container.each do |entity|
          next unless entity.valid?

          yield entity
          each_model_entity(entity.definition.entities, &block) if entity.respond_to?(:definition)
        end
      end

      def abf_sheet_type_rows
        return @abf_sheet_type_rows_cache if @abf_sheet_type_rows_cache
        return [] unless defined?(ABF::SheetTypesTool)

        tool = ABF::SheetTypesTool.send(:new)
        captured = []
        tool.define_singleton_method(:post_scan_types) { |obj| captured = Array(obj) }
        tool.scan_types
        @abf_sheet_type_rows_cache = captured
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
              .toolbar {
                height: 52px;
                display: grid;
                grid-template-columns: 28px 72px minmax(0, 1fr) 86px 74px 72px 34px;
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
                grid-template-columns: max-content minmax(80px, 1fr);
                align-items: center;
                gap: 10px;
                min-width: 0;
              }
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
              .table-wrap {
                height: calc(100vh - 52px);
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
              td {
                height: 30px;
                padding: 2px 6px;
                vertical-align: middle;
                white-space: nowrap;
              }
              .eye-cell { width: 30px; text-align: center; }
              .thickness-cell { width: 78px; color: #111; cursor: pointer; }
              .thickness-cell:hover span { text-decoration: underline; }
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
            <div class="toolbar">
              <input id="master" type="checkbox" checked title="Ẩn/hiện tất cả dòng">
              <button class="sort" data-sort="thickness">Độ Dày ▲</button>
              <div class="material-head">
                <button class="sort" data-sort="code">Vật Liệu ▲</button>
                <input id="search" class="search" type="search" placeholder="Tìm độ dày / vật liệu">
              </div>
              <div style="text-align:center">2 Mặt</div>
              <button id="stripPaint" class="tool-btn" title="Bỏ phần mã sơn của các dòng đang lọc">Bỏ Sơn</button>
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
              <div id="empty" class="empty" hidden>Không tìm thấy group/component dạng tấm trong model.</div>
            </div>

            <script>
              let rows = [];
              let sortKey = 'thickness';
              let sortDir = 1;
              let filterText = '';

              function callRuby(name, payload = {}) {
                if (window.sketchup && sketchup[name]) {
                  sketchup[name](JSON.stringify(payload));
                }
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
                const active = document.activeElement;
                const editing = active && active.classList && active.classList.contains('code');
                const byKey = new Map(rows.map((row) => [row.key, row]));
                data.forEach((item) => {
                  const row = byKey.get(item.key);
                  if (!row) return;
                  row.visible = !!item.visible;
                  row.all_hidden = !!item.all_hidden;
                });
                if (!editing) draw();
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
                empty.textContent = rows.length === 0 ? 'Không tìm thấy group/component dạng tấm trong model.' : 'Không có dòng phù hợp.';
                body.innerHTML = displayRows.map((row, index) => `
                  <tr data-index="${index}">
                    <td class="eye-cell">
                      <button class="eye ${row.visible ? '' : 'off'}" title="Ẩn/hiện trong model" data-action="visible" data-key="${escapeHtml(row.key)}">●</button>
                    </td>
                    <td class="thickness-cell" title="Chọn các object của dòng" data-action="select" data-key="${escapeHtml(row.key)}"><span style="color:#0084d7">${escapeHtml(row.thickness)}</span>&nbsp;&nbsp;mm</td>
                    <td class="code-cell">
                      <input class="code" value="${escapeHtml(row.code)}" data-action="code" data-key="${escapeHtml(row.key)}">
                    </td>
                    <td class="count-cell"><span class="count">${escapeHtml(row.count)}</span></td>
                    <td class="two-cell">${Number(row.two_face || 0) > 0 ? `<input class="two-input" readonly value="${escapeHtml(row.two_face)}">` : ''}</td>
                    <td class="reset-cell"><button class="reset" title="Xóa mã nhập tay, về mã mặc định" data-action="reset" data-key="${escapeHtml(row.key)}">×</button></td>
                    <td class="color-cell"><input class="swatch" type="color" value="${escapeHtml(row.color || '#d8d8d8')}" data-action="color" data-key="${escapeHtml(row.key)}"></td>
                    <td class="edit-cell"><button class="pencil" title="Chọn các object của dòng" data-action="select" data-key="${escapeHtml(row.key)}">♢</button></td>
                  </tr>
                `).join('');
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
                const code = el.value.trim();
                if (code === String(row.code || '').trim()) return;
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
                const row = rowByKey(el.dataset.key);
                if (!row) return;
                if (el.dataset.action === 'visible') callRuby('set_visible', { ids: row.ids, ancestor_ids: row.ancestor_ids || [], visible: !row.visible });
                if (el.dataset.action === 'reset') callRuby('reset_code', { ids: row.ids });
                if (el.dataset.action === 'select') callRuby('select_row', { ids: row.ids });
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

              document.getElementById('master').addEventListener('change', (event) => {
                const ids = rows.flatMap((row) => row.ids);
                const ancestor_ids = rows.flatMap((row) => row.ancestor_ids || []);
                callRuby('set_visible', { ids, ancestor_ids, visible: event.target.checked });
              });

              document.getElementById('stripPaint').addEventListener('click', () => {
                const ids = visibleRows().flatMap((row) => row.ids);
                callRuby('strip_paint_codes', { ids });
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
