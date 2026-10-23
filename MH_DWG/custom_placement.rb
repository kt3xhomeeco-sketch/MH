# frozen_string_literal: true

module MH
  module DWG
    # Legacy wireframe tool; default Paste still uses native SketchUp placement.
    class RotatePlaceTool
      DWG.load_tool_helpers(self, CustomPlacementState, CustomPreviewGeometry, CustomPreviewTransform,
                            CustomPlacementInput, CustomPlacementHandoff, CustomPlacementCommit)

      SNAP_RADIUS = 20

      def initialize(source, base_offset = ORIGIN, all_axis_vertices = nil)
        remember_model_context
        @defn = source
        initialize_anchors(base_offset, all_axis_vertices)
        initialize_cursor
        initialize_placement
        initialize_diagnostics(source)
      end

      def activate
        log_tool('activate_start')
        return reject_invalid_definition unless @defn&.valid?

        @active = true
        prepare_custom_preview
        show_custom_prompt
      end

      def deactivate(view)
        log_tool('deactivate', placed: @placed, finalizing: @finalizing, op_open: @op_open)
        @active = false
        cancel_pending! unless @handoff
        @preview_segments = []
        view.invalidate
      end

      def cancel_pending!
        UI.stop_timer(@placement_timer) if @placement_timer
        @placement_timer = nil
        @placement_pending = false
        @finalizing = false unless @placed
      end

      def suspend(view)
        view.invalidate
      end

      def getExtents
        bounds = Geom::BoundingBox.new
        return bounds unless @active && @current_pos && context_valid?

        @preview_segments.flatten.each do |point|
          transformed = point.transform(@preview_transform)
          bounds.add(transformed) if drawable_point?(transformed)
        end
        bounds.add(@current_pos) if drawable_point?(@current_pos)
        bounds
      end

      def draw(view)
        return unless @active && @current_pos && context_valid?

        draw_preview(view)
        if @snapped
          view.draw_points([@current_pos], 10, 2, 'blue')
          @ip.draw(view)
        else
          view.draw_points([@current_pos], 8, 3, 'green')
        end
      end

      def onCancel(reason, _view)
        log_tool('cancel', reason: reason, placed: @placed, finalizing: @finalizing)
        cancel_pending!
        @model.select_tool(nil) if Sketchup.active_model == @model
      end

      private

      def context_valid?
        Sketchup.active_model == @model && @model.valid? && @model.active_entities == @entities &&
          Array(@model.active_path) == @active_path && @defn&.valid?
      rescue StandardError
        false
      end

      def log_tool(event, data = {})
        MH::DWG.log_event("tool.#{event}", data.merge(log_id: @log_id))
      end

      def maybe_log_mouse(flags, x, y)
        now = Time.now.to_f
        return if now - @last_mouse_log_at < 0.5

        @last_mouse_log_at = now
        log_tool('mouse_move', flags: flags, x: x, y: y, current_pos: MH::DWG.point_log(@current_pos),
                               snapped: @snapped, rot: @rot, preview_segments: @preview_segments.length,
                               transform: MH::DWG.transform_log(@preview_transform))
      end
    end
  end
end
