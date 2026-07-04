# encoding: utf-8

module MH_Thongke
  module P4DeltaTracker
    module_function

    def observer
      @observer ||= begin
        if defined?(Sketchup::EntityObserver)
          Class.new(Sketchup::EntityObserver) do
            def onChangeEntity(entity)
              MH_Thongke.p4_delta_record_entity(entity, :change) if defined?(MH_Thongke)
            end

            def onEraseEntity(entity)
              MH_Thongke.p4_delta_record_entity(entity, :erase) if defined?(MH_Thongke)
            end
          end.new
        end
      end
    rescue
      nil
    end

    def entity_key(entity)
      return nil unless entity
      return "pid:#{entity.persistent_id}" if entity.respond_to?(:persistent_id)
      return "eid:#{entity.entityID}" if entity.respond_to?(:entityID)
      "oid:#{entity.object_id}"
    rescue
      "oid:#{entity.object_id}" rescue nil
    end

    def valid_entity?(entity)
      entity && (!entity.respond_to?(:valid?) || entity.valid?)
    rescue
      false
    end

    def detach_all
      obs = observer
      Array(@tracked_entities).each do |entity|
        begin
          entity.remove_observer(obs) if obs && entity && entity.respond_to?(:remove_observer)
        rescue
        end
      end
      @tracked_entities = []
      @entity_to_top_key = {}
      true
    rescue
      false
    end

    def row_pairs(row)
      pairs = []
      Array(row[:stat_entities]).each do |item|
        entity = item.is_a?(Array) ? item[0] : item
        top = item.is_a?(Array) ? item[1] : entity
        pairs << [entity, top]
      end
      Array(row[:entities]).each do |entity|
        pairs << [entity, entity]
      end
      pairs
    rescue
      []
    end

    def rebuild(rows)
      detach_all
      obs = observer

      @tracked_entities = []
      @entity_to_top_key = {}
      @top_key_to_entity = {}
      @entity_snapshot = {}
      seen = {}
      top_keys = {}

      Array(rows).each do |row|
        next unless row.is_a?(Hash)

        row_pairs(row).each do |entity, top|
          next unless valid_entity?(entity)

          key = entity_key(entity)
          top_key = entity_key(top) || key
          next if key.to_s.empty?

          @entity_to_top_key[key] = top_key
          @top_key_to_entity[top_key] = top if valid_entity?(top) && !top_key.to_s.empty?
          top_keys[top_key] = true unless top_key.to_s.empty?
          [entity, top].each do |candidate|
            next unless valid_entity?(candidate)

            candidate_key = entity_key(candidate)
            next if candidate_key.to_s.empty? || seen[candidate_key]

            begin
              candidate.add_observer(obs) if obs && candidate.respond_to?(:add_observer)
              @tracked_entities << candidate
              @entity_snapshot[candidate_key] = entity_signature(candidate)
              seen[candidate_key] = true
            rescue
            end
          end
        end
      end

      @changed_events ||= []
      @structure_snapshot = model_structure_signature
      { enabled: true, tracked: @tracked_entities.length, top_roots: top_keys.length, observer: !!obs, snapshot: true }
    rescue => e
      { enabled: false, tracked: 0, top_roots: 0, error: "#{e.class}: #{e.message}" }
    end

    def model_structure_signature
      model = Sketchup.active_model
      model.active_entities.map do |entity|
        [
          entity_key(entity),
          entity.respond_to?(:typename) ? entity.typename.to_s : entity.class.to_s
        ].join(":")
      end.sort.join("|")
    rescue
      ""
    end

    def attr_sig(entity, dict, key)
      entity.get_attribute(dict, key).to_s
    rescue
      ""
    end

    def transform_sig(entity)
      return "" unless entity.respond_to?(:transformation)
      entity.transformation.to_a.map { |v| v.to_f.round(6) }.join(",")
    rescue
      ""
    end

    def entity_signature(entity)
      return "invalid" unless valid_entity?(entity)

      definition = entity.respond_to?(:definition) ? entity.definition : nil
      material = entity.respond_to?(:material) && entity.material ? entity.material.display_name.to_s : ""
      layer = entity.respond_to?(:layer) ? entity.layer : nil
      [
        entity.respond_to?(:name) ? entity.name.to_s : "",
        definition ? definition.name.to_s : "",
        definition && definition.respond_to?(:persistent_id) ? definition.persistent_id.to_s : "",
        layer ? layer.name.to_s : "",
        layer && layer.respond_to?(:visible?) ? layer.visible?.to_s : "",
        entity.respond_to?(:hidden?) ? entity.hidden?.to_s : "",
        material,
        transform_sig(entity),
        attr_sig(entity, "ABF", "statistical-name"),
        attr_sig(entity, "ABF", "setting-name"),
        attr_sig(entity, "ABF", "statistical-type"),
        attr_sig(entity, "ABF", "is-statistical-object"),
        attr_sig(entity, "ABF", "is-intersect"),
        attr_sig(entity, "ZSU_LED", "ten_hien_thi"),
        attr_sig(entity, "MH_Thongke", "generated_pk"),
        attr_sig(entity, "MH_Thongke", "pk_name"),
        attr_sig(entity, "MH_Thongke", "product_code"),
        attr_sig(entity, "MH_Thongke", "ten_sp"),
        attr_sig(entity, "MH_Thongke", "mat_ten_sp"),
        attr_sig(entity, "MH_Thongke", "ngay_dat"),
        attr_sig(entity, "MH_Thongke", "mat_ngay_dat")
      ].join("|")
    rescue
      "error"
    end

    def detect_snapshot_changes
      changed = []
      current_structure = model_structure_signature
      if !@structure_snapshot.nil? && @structure_snapshot.to_s != current_structure.to_s
        event = record_structure_change
        changed << event if event
        @structure_snapshot = current_structure
      end

      snapshots = @entity_snapshot || {}
      Array(@tracked_entities).each do |entity|
        key = entity_key(entity)
        next if key.to_s.empty?

        old_sig = snapshots[key]
        new_sig = entity_signature(entity)
        next if old_sig == new_sig

        kind = valid_entity?(entity) ? :snapshot_change : :snapshot_erase
        event = record_entity(entity, kind)
        changed << event if event
        snapshots[key] = new_sig
      end
      changed
    rescue
      []
    end

    def record_structure_change
      @changed_events ||= []
      event = {
        time: Time.now.strftime("%H:%M:%S"),
        kind: "structure_change",
        entity_key: "__STRUCTURE__",
        top_key: "__STRUCTURE__",
        valid: true
      }
      @changed_events << event
      @changed_events.shift while @changed_events.length > 200
      event
    rescue
      nil
    end

    def record_entity(entity, kind)
      key = entity_key(entity)
      return nil if key.to_s.empty?

      @changed_events ||= []
      event = {
        time: Time.now.strftime("%H:%M:%S"),
        kind: kind.to_s,
        entity_key: key,
        top_key: (@entity_to_top_key || {})[key] || key,
        valid: valid_entity?(entity)
      }
      @changed_events << event
      @changed_events.shift while @changed_events.length > 200
      event
    rescue
      nil
    end

    def changed_events(limit = 50)
      Array(@changed_events).last(limit.to_i)
    rescue
      []
    end

    def changed_top_keys(limit = 80)
      changed_events(200).map { |event| event[:top_key] }.compact.uniq.first(limit.to_i)
    rescue
      []
    end

    def top_entity_for_key(top_key)
      entity = (@top_key_to_entity || {})[top_key.to_s]
      valid_entity?(entity) ? entity : nil
    rescue
      nil
    end

    def root_entities_for_keys(top_keys)
      Array(top_keys).map { |key| top_entity_for_key(key) }.compact.uniq
    rescue
      []
    end

    def tracked_top_keys(limit = 2000)
      (@top_key_to_entity || {}).keys.first(limit.to_i)
    rescue
      []
    end

    def clear_changed
      @changed_events = []
      true
    rescue
      false
    end

    def status
      {
        enabled: !!observer,
        tracked: Array(@tracked_entities).length,
        snapshot_tracked: (@entity_snapshot || {}).length,
        top_roots: (@top_key_to_entity || {}).length,
        changed_events: Array(@changed_events).length,
        changed_top_keys: changed_top_keys.length
      }
    rescue
      { enabled: false, tracked: 0, changed_events: 0, changed_top_keys: 0 }
    end
  end

  def self.p4_delta_rebuild_watchers
    rows = []
    rows.concat(Array(@current_report_items)) if @current_report_items
    rows.concat(Array(@current_mat_items)) if @current_mat_items
    rows.concat(@data_map.values) if @data_map.respond_to?(:values)
    rows.concat(@mat_data_map.values) if @mat_data_map.respond_to?(:values)
    P4DeltaTracker.rebuild(rows)
  end

  def self.p4_delta_record_entity(entity, kind)
    P4DeltaTracker.record_entity(entity, kind)
  end

  def self.p4_delta_changed_events(limit = 50)
    P4DeltaTracker.changed_events(limit)
  end

  def self.p4_delta_changed_top_keys(limit = 80)
    P4DeltaTracker.changed_top_keys(limit)
  end

  def self.p4_delta_clear_changed
    P4DeltaTracker.clear_changed
  end

  def self.p4_delta_status
    P4DeltaTracker.status
  end

  def self.p4_delta_detect_snapshot_changes
    P4DeltaTracker.detect_snapshot_changes
  end

  def self.p4_delta_root_entities_for_keys(top_keys)
    P4DeltaTracker.root_entities_for_keys(top_keys)
  end

  def self.p4_delta_tracked_top_keys(limit = 2000)
    P4DeltaTracker.tracked_top_keys(limit)
  end
end
