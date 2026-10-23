# frozen_string_literal: true

module MH
  module DWG
    # Mouse picking and anchor selection for the legacy custom tool.
    module CustomPlacementInput
      def onMouseMove(flags, x, y, view)
        return unless input_active?

        @ip.pick(view, x, y)
        update_mouse_position(view, x, y)
        update_transform
        maybe_log_mouse(flags, x, y)
        view.invalidate
      rescue StandardError => e
        log_tool('mouse_move_error', error: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(5))
        raise
      end

      def onKeyDown(key, _repeat, _flags, view)
        return false unless input_active? && key == 9
        return if @all_axis_vertices.length <= 1

        advance_anchor
        view.invalidate
        Sketchup.set_status_text("Vertex #{@current_vertex_index + 1}/#{@all_axis_vertices.length}", SB_VCB_VALUE)
        true
      end

      private

      def input_active?
        @active && !@finalizing && context_valid?
      end

      def update_mouse_position(view, x, y)
        free_position = Geom.intersect_line_plane(view.pickray(x, y), [ORIGIN, Z_AXIS])
        if @ip.valid? && @ip.vertex
          update_vertex_position(view, x, y, free_position)
        else
          @current_pos = free_position
          @snapped = false
        end
      end

      def update_vertex_position(view, x, y, free_position)
        if vertex_within_snap_radius?(view, x, y)
          @current_pos = @ip.position
          @snapped = true
        else
          @current_pos = free_position || @ip.position
          @snapped = false
        end
      end

      def vertex_within_snap_radius?(view, x, y)
        screen = view.screen_coords(@ip.position)
        Math.sqrt(((screen.x - x)**2) + ((screen.y - y)**2)) < RotatePlaceTool::SNAP_RADIUS
      end

      def advance_anchor
        @current_vertex_index = (@current_vertex_index + 1) % @all_axis_vertices.length
        @base_offset = @all_axis_vertices[@current_vertex_index]
        @last_pos = nil
        update_transform
        log_tool('tab_vertex', vertex_index: @current_vertex_index, base_offset: MH::DWG.point_log(@base_offset),
                               transform: MH::DWG.transform_log(@preview_transform))
      end
    end
  end
end
