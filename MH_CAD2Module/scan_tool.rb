# frozen_string_literal: true

module MH
  module CAD2Module
    # Rectangle selection reads geometry only; it never trims or changes the imported CAD.
    class ScanTool
      def activate
        Sketchup.status_text = 'CAD2Module: kéo khung bao các hình CAD của một SP. Esc để hủy.'
      end

      def onLButtonDown(_flags, x, y, view)
        @start = [x, y]
        @finish = @start
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        return unless @start
        @finish = [x, y]
        view.invalidate
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @start
        @finish = [x, y]
        if Math.hypot(@finish[0] - @start[0], @finish[1] - @start[1]) < 8
          Sketchup.status_text = 'Kéo một vùng bao đầy đủ các hình chiếu cần đọc.'
          @start = nil
          return
        end
        helper = view.pick_helper
        helper.window_pick(Geom::Point3d.new(*@start, 0), Geom::Point3d.new(*@finish, 0), Sketchup::PickHelper::PICK_CROSSING)
        selected = helper.all_picked.uniq
        raise ArgumentError, 'Vùng quét chưa có nét CAD.' if selected.empty?
        view.model.selection.clear
        view.model.selection.add(selected)
        window = [[@start[0], x].min, [@start[1], y].min, [@start[0], x].max, [@start[1], y].max]
        CAD2Module.selection_ready(window)
        view.model.select_tool(nil)
      rescue StandardError => error
        @start = nil
        CAD2Module.report_error(error.message)
      ensure
        view.invalidate
      end

      def draw(view)
        return unless @start && @finish
        x0, y0 = @start
        x1, y1 = @finish
        view.drawing_color = Sketchup::Color.new(37, 99, 235)
        view.line_width = 2
        view.draw2d(GL_LINE_LOOP, [[x0, y0, 0], [x1, y0, 0], [x1, y1, 0], [x0, y1, 0]])
      end

      def onCancel(_reason, view)
        @start = nil
        view.model.select_tool(nil)
        view.invalidate
      end

      def deactivate(view)
        Sketchup.status_text = '' unless Jobs.busy?
        view.invalidate
      end

      def suspend(view)
        view.invalidate
      end

      def getExtents
        Sketchup.active_model.bounds
      end
    end
  end
end
