# frozen_string_literal: true

module MH
  module DWG
    # Releases the custom tool before queueing geometry creation in a second timer.
    module CustomPlacementHandoff
      def onLButtonDown(flags, x, y, view)
        log_tool('left_button_down', flags: flags, x: x, y: y, current_pos: MH::DWG.point_log(@current_pos),
                                     rot: @rot, finalizing: @finalizing)
        return if @finalizing || !@active || !@current_pos || !context_valid?

        axis = modifier_axis(flags)
        if axis
          rotate_preview(axis, view)
          return
        end

        queue_custom_placement(view)
      end

      private

      def modifier_axis(flags)
        return 2 if flags.anybits?(COPY_MODIFIER_MASK)
        return 1 if flags.anybits?(CONSTRAIN_MODIFIER_MASK)
        return 0 if flags.anybits?(ALT_MODIFIER_MASK)

        nil
      end

      def rotate_preview(axis, view)
        @rot[axis] += 90
        @last_pos = nil
        update_transform
        log_tool("rotate_#{%w[x y z][axis]}", rot: @rot, transform: MH::DWG.transform_log(@preview_transform))
        view.invalidate
      end

      def queue_custom_placement(view)
        prepare_final_transform
        @placement_timer = UI.start_timer(0.0, false) do
          @placement_timer = nil
          handoff_for_placement(view)
        end
      end

      def prepare_final_transform
        @finalizing = true
        @placement_pending = true
        @final_transform = @context_inverse * @preview_transform
        log_tool('finalize_timer_scheduled', transform: MH::DWG.transform_log(@preview_transform),
                                             inst: MH::DWG.entity_log(@inst))
        Sketchup.set_status_text('Đang đặt CAD...', SB_PROMPT)
      end

      def handoff_for_placement(view)
        return cancel_custom_finalization unless @placement_pending && context_valid?

        leave_custom_tool
        @handoff_tool_id = @model.tools.active_tool_id
        schedule_custom_finalize(view) if @placement_pending
      end

      def leave_custom_tool
        @handoff = true
        @model.select_tool(nil)
      ensure
        @handoff = false
      end

      def schedule_custom_finalize(view)
        @placement_timer = UI.start_timer(0.05, false) do
          @placement_timer = nil
          finalize_placement(view)
        end
      end

      def cancel_custom_finalization
        cancel_pending!
        log_tool('finalize_cancelled_context_changed')
      end
    end

    # Owns only the final custom placement operation, including error cleanup.
    module CustomPlacementCommit
      private

      def finalize_placement(view)
        return cancel_custom_finalization unless custom_finalization_ready?

        place_pending_instance
      rescue StandardError => e
        report_finalize_error(e)
      ensure
        view.invalidate if view && Sketchup.active_model == @model && @model.valid?
      end

      def custom_finalization_ready?
        @placement_pending && context_valid? && @model.tools.active_tool_id == @handoff_tool_id
      end

      def place_pending_instance
        @placement_pending = false
        log_tool('finalize_start', inst: MH::DWG.entity_log(@inst), defn: MH::DWG.definition_summary(@defn),
                                   transform: MH::DWG.transform_log(@preview_transform))
        start_custom_operation
        create_custom_instance
        commit_custom_operation
        log_tool('finalize_done')
      end

      def start_custom_operation
        log_tool('finalize_before_start_operation')
        @model.start_operation('Đặt CAD', true)
        @op_open = true
        log_tool('finalize_after_start_operation')
      end

      def create_custom_instance
        log_tool('finalize_before_add_instance')
        @inst = @entities.add_instance(@defn, @final_transform)
        log_tool('finalize_after_add_instance', inst: MH::DWG.entity_log(@inst))
        log_tool('finalize_before_assign_tag')
        MH::DWG.assign_tag(@inst, @model)
        log_tool('finalize_after_assign_tag', inst: MH::DWG.entity_log(@inst))
      end

      def commit_custom_operation
        log_tool('finalize_before_commit')
        @model.commit_operation
        @op_open = false
        @placed = true
        log_tool('finalize_after_commit', inst: MH::DWG.entity_log(@inst))
      end

      def report_finalize_error(error)
        log_tool('finalize_error', error: "#{error.class}: #{error.message}",
                                   backtrace: error.backtrace&.first(8), op_open: @op_open)
        abort_custom_operation
        UI.messagebox("Lỗi đặt CAD: #{error.class}: #{error.message}")
      end

      def abort_custom_operation
        return unless @op_open

        log_tool('finalize_before_abort')
        @model.abort_operation
        @op_open = false
        log_tool('finalize_after_abort')
      rescue StandardError
        nil # Preserve the original placement failure if abort itself fails.
      end
    end
  end
end
