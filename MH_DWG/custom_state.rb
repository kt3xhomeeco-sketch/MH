# frozen_string_literal: true

module MH
  module DWG
    # Keeps the legacy tool's context, cursor and placement state separate.
    module CustomPlacementState
      private

      def remember_model_context
        @model = Sketchup.active_model
        @entities = @model.active_entities
        @active_path = Array(@model.active_path).dup
        @context_inverse = @model.edit_transform.inverse
      end

      def initialize_anchors(base_offset, vertices)
        @all_axis_vertices = vertices || [base_offset]
        @current_vertex_index = 0
        @base_offset = @all_axis_vertices[@current_vertex_index]
      end

      def initialize_cursor
        @ip = Sketchup::InputPoint.new
        @rot = [0, 0, 0]
        @current_pos = @last_pos = @last_rot = nil
        @snapped = false
        @preview_transform = IDENTITY
        @preview_segments = []
      end

      def initialize_placement
        @inst = nil
        @active = @handoff = @placement_pending = false
        @placed = @op_open = @finalizing = false
        @placement_timer = nil
      end

      def initialize_diagnostics(source)
        @log_id = "#{Time.now.to_i}-#{object_id}"
        @last_mouse_log_at = 0.0
        log_tool('init', source: MH::DWG.entity_log(source), defn: MH::DWG.definition_summary(@defn),
                         base_offset: MH::DWG.point_log(@base_offset), axis_vertices: @all_axis_vertices.length)
      end

      def reject_invalid_definition
        log_tool('activate_invalid_definition')
        UI.messagebox('Definition CAD không còn hợp lệ.')
        @model.select_tool(nil)
      end

      def prepare_custom_preview
        @preview_segments = collect_preview_segments(@defn.entities)
        @preview_segments = bounds_preview_segments(@defn) if @preview_segments.empty?
      end

      def show_custom_prompt
        vertex_count = @all_axis_vertices.length
        log_tool('activate_ready', inst: MH::DWG.entity_log(@inst), preview_segments: @preview_segments.length,
                                   vertex_count: vertex_count)
        Sketchup.set_status_text("Click đặt | Tab: vertex tiếp (#{vertex_count} điểm) | " \
                                 'Ctrl+Click: xoay Z | Shift: xoay Y | Alt: xoay X', SB_PROMPT)
      end
    end
  end
end
