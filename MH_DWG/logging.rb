# frozen_string_literal: true

module MH
  # CAD clipboard import and placement for SketchUp.
  module DWG
    def self.log_definition_imported(model, definition, duration_ms)
      log_event('paste.after_definition_import', defn: definition_summary(definition),
                                                 active_entities: model.active_entities.length,
                                                 duration_ms: duration_ms)
    end

    LOG_FILE = File.join(__dir__.dup.force_encoding('UTF-8'), 'mh_dwg_debug.log')

    # Diagnostic metadata must never prevent import, placement or cleanup.
    def self.diagnostic_value
      yield
    rescue StandardError
      nil
    end

    def self.log_event(event, data = {})
      payload = {
        time: Time.now.strftime('%Y-%m-%d %H:%M:%S.%L'),
        event: event,
        pid: Process.pid,
        sketchup_version: diagnostic_value { Sketchup.version },
        ruby_version: RUBY_VERSION,
        data: data
      }

      File.open(LOG_FILE, 'a:UTF-8') do |file|
        file.sync = true
        file.puts(JSON.generate(payload))
      end
    rescue StandardError => e
      puts "[MH_DWG LOG ERROR] #{e.class}: #{e.message}"
    end

    def self.point_log(point)
      return nil unless point

      [point.x.to_f.round(4), point.y.to_f.round(4), point.z.to_f.round(4)]
    rescue StandardError
      nil
    end

    def self.transform_log(transform)
      return nil unless transform

      transform.to_a.map { |value| value.to_f.round(6) }
    rescue StandardError
      nil
    end

    def self.entity_log(ent)
      return nil unless ent

      entity_identity(ent).merge(entity_labels(ent))
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    def self.entity_identity(ent)
      {
        class: ent.class.name,
        valid: diagnostic_value { ent.valid? },
        persistent_id: diagnostic_value { ent.persistent_id },
        entity_id: diagnostic_value { ent.entityID }
      }
    end

    def self.entity_labels(ent)
      {
        name: (ent.respond_to?(:name) ? ent.name.to_s : nil),
        definition: (ent.respond_to?(:definition) && ent.definition ? ent.definition.name.to_s : nil),
        visible: (ent.respond_to?(:visible?) ? ent.visible? : nil)
      }
    end

    def self.entities_summary(entities)
      counts = Hash.new(0)
      total = 0
      entities.each do |ent|
        total += 1
        counts[ent.class.name] += 1
      end
      { total: total, counts: counts }
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    def self.definition_summary(defn)
      return nil unless defn

      definition_status(defn).merge(definition_bounds_log(defn))
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    def self.definition_status(defn)
      {
        name: defn.name.to_s,
        valid: diagnostic_value { defn.valid? },
        count_entities: diagnostic_value { defn.entities.length },
        bounds_empty: diagnostic_value { defn.bounds.empty? }
      }
    end

    def self.definition_bounds_log(defn)
      {
        bounds_min: diagnostic_value { point_log(defn.bounds.min) },
        bounds_max: diagnostic_value { point_log(defn.bounds.max) }
      }
    end
  end
end
