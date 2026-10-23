# frozen_string_literal: true

module MH
  # Imports definitions outside operations, retaining the original edit context.
  module DWG
    def self.import_context_valid?(model, active_path, entities)
      return true if model.valid? && Sketchup.active_model == model &&
                     model.active_path == active_path && model.active_entities.equal?(entities)

      log_event('paste.import_context_changed')
      UI.messagebox('Model hoặc ngữ cảnh group/component đã đổi trong lúc import CAD. ' \
                    'Đã dừng đặt; hãy Paste lại trong ngữ cảnh cần dùng.')
      false
    end

    def self.paste_from_clipboard(placement_mode = :native)
      return if @importing
      raise ArgumentError, 'Unknown CAD placement mode' unless %i[native custom].include?(placement_mode)

      import_owned = true
      @importing = true
      paste_in_context(Sketchup.active_model, placement_mode)
    rescue StandardError => e
      report_import_error(e, import_owned)
    ensure
      finish_import if import_owned
    end

    def self.paste_in_context(model, placement_mode)
      active_path = model.active_path&.dup
      entities = model.active_entities
      log_import_start(model, placement_mode)
      dwg = clipboard_dwg_path
      return unless dwg

      prepare_import(model)
      import_in_context(model, active_path, entities, dwg, placement_mode)
    end

    def self.import_in_context(model, active_path, entities, dwg, placement_mode)
      return unless import_context_valid?(model, active_path, entities)

      definition = import_dwg_definition(model, dwg)
      return unless definition && import_context_valid?(model, active_path, entities)

      normalize_definition_origin(definition, model)
      return unless import_context_valid?(model, active_path, entities) && definition.valid?

      start_imported_placement(model, definition, placement_mode)
    end

    def self.log_import_start(model, placement_mode)
      pipeline = placement_mode == :native ? 'definition_native_placement' : 'definition_preview_then_place'
      log_event('paste.start', pipeline: pipeline,
                               active_path: diagnostic_value { model.path },
                               entities_before: diagnostic_value { model.active_entities.length })
    end

    def self.prepare_import(model)
      @placement_tool&.cancel_pending!
      @placement_tool = nil
      defer_native_tagging
      @native_rotation&.cancel!
      @native_rotation = nil
      log_event('paste.before_select_tool_nil')
      model.select_tool(nil)
      log_event('paste.after_select_tool_nil')
    end

    def self.import_dwg_definition(model, dwg)
      # The importer owns its transaction; never enclose it in an operation.
      options = import_options
      log_event('paste.before_definition_import', options: options)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      definition = model.definitions.import(dwg, options)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      # Sketchup::Entities has length but does not implement empty?.
      return report_invalid_definition unless definition&.valid? && definition.entities.length >= 1

      log_definition_imported(model, definition, duration_ms)
      definition
    end

    def self.report_invalid_definition
      log_event('paste.definition_import_failed')
      UI.messagebox('Import DWG lỗi!')
      nil
    end

    def self.start_imported_placement(model, definition, placement_mode)
      return start_custom_placement(model, definition) if placement_mode == :custom

      log_event('paste.before_native_placement', defn: definition_summary(definition),
                                                 anchor_mode: 'bounds_min', repeat: false)
      start_native_placement(model, definition)
      start_native_rotation(model, definition)
      log_event('paste.native_placement_started')
    end

    def self.start_custom_placement(model, definition)
      vertices = placement_anchor_points(definition)
      base_point = vertices.first
      log_event('paste.definition_ready', defn: definition_summary(definition), base_point: point_log(base_point),
                                          anchor_mode: 'bounds_min', axis_vertices: vertices.length)
      @placement_tool = RotatePlaceTool.new(definition, base_point, vertices)
      log_event('paste.before_select_rotate_tool', defn: definition_summary(definition))
      model.select_tool(@placement_tool)
      log_event('paste.after_select_rotate_tool')
    end

    def self.report_import_error(error, import_owned)
      if import_owned
        @native_tagger&.cancel!
        @native_rotation&.cancel!
      end
      log_event('paste.error', error: "#{error.class}: #{error.message}", backtrace: error.backtrace&.first(8))
      UI.messagebox("Lỗi import CAD: #{error.class}: #{error.message}")
    end

    def self.finish_import
      @importing = false
      @pending_native_taggers.dup.each(&:schedule_check)
    end
  end
end
