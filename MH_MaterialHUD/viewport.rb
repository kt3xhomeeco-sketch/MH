# encoding: UTF-8
module MH
  module MaterialHUD
    class ViewportOverlay < Sketchup::Overlay
      def initialize
        super('mh.material_hud', 'MH Material HUD')
        @colors = {
          panel: Sketchup::Color.new(188, 188, 194, 235),
          header: Sketchup::Color.new(74, 79, 148, 240),
          row: Sketchup::Color.new(238, 238, 240, 235),
          product: Sketchup::Color.new(218, 220, 232, 240),
          text: Sketchup::Color.new(20, 20, 24),
          white: Sketchup::Color.new(255, 255, 255),
          'OK' => Sketchup::Color.new(0, 86, 168),
          'SPEC' => Sketchup::Color.new(175, 125, 0),
          'NO SPEC' => Sketchup::Color.new(192, 57, 43)
        }
      end

      def start
        # Also works when enabled directly in SketchUp's Overlays tray.
        UI.start_timer(0.01, false) { MaterialHUD.schedule_refresh }
      end

      def stop
        MaterialHUD.stop_timers
      end

      def draw(view)
        data = MaterialHUD.data || {}
        rows = Array(data[:rows])
        width = [460, view.vpwidth.to_i].min
        row_height = 38
        capacity = [[(view.vpheight.to_i - 70) / row_height, 1].max, 12].min
        offset = MaterialHUD.scroll_offset(rows.size, capacity)
        shown = rows.drop(offset).first(capacity)
        height = 51 + [shown.size, 1].max * row_height
        x, y = OverlayEngine.panel_origin(view, width, height, anchor: :bottom_right)
        MaterialHUD.panel_rect = [x, y, width, height]
        rect(view, x, y, width, height, :panel)
        rect(view, x + 10, y + 10, width - 20, 20, :header)
        text(view, x + 16, y + 14, 'MÃ VẬT LIỆU', color: :white, bold: true)
        text(view, x + 190, y + 14, 'QUY CÁCH VẬT LIỆU', color: :white, size: 6)
        text(view, x + 366, y + 14, 'TRẠNG THÁI', color: :white, size: 7)
        row_y = y + 30
        if shown.empty?
          text(view, x + 16, row_y + 6, truncate(data[:message], 60))
        else
          shown.each do |row|
            rect(view, x + 10, row_y, width - 20, row_height, row[:type] == :product ? :product : :row)
            text(view, x + 16, row_y + 10, truncate(row[:name], 25), bold: row[:type] == :product)
            unless row[:type] == :product
              lines = wrap(row[:note], 38, 2)
              text(view, x + 190, row_y + 5, lines[0], size: 6)
              text(view, x + 190, row_y + 18, lines[1], size: 6) if lines[1]
              status = row[:status].to_s
              rect(view, x + 365, row_y + 10, 74, 18, @colors.key?(status) ? status : :header)
              text(view, x + 371, row_y + 13, status, color: :white, size: 7, bold: true)
            end
            row_y += row_height
          end
        end
        footer = rows.size > capacity ? "#{offset + 1}–#{offset + shown.size} / #{rows.size} | Lăn chuột trên bảng để xem tiếp" : 'Click chọn đối tượng | Chuột phải: JSON / chế độ'
        text(view, x + 10, y + height - 15, footer, size: 7)
      rescue => e
        puts "[MH Material HUD draw] #{e.message}"
      end

      def truncate(value, length)
        value = value.to_s
        value.size > length ? value[0, length - 1] + '…' : value
      end

      def wrap(value, length, limit)
        words = value.to_s.gsub('|', ' | ').split
        return [''] if words.empty?

        lines = ['']
        words.each do |word|
          candidate = lines.last.empty? ? word : "#{lines.last} #{word}"
          if candidate.length <= length || lines.length >= limit
            lines[-1] = candidate
          else
            lines << word
          end
        end
        lines[-1] = truncate(lines[-1], length) if lines[-1].length > length
        lines
      end

      def rect(view, x, y, width, height, color)
        OverlayEngine.rect(view, x, y, width, height, @colors.fetch(color))
      end

      def text(view, x, y, value, size: 8, color: :text, bold: false)
        OverlayEngine.text(view, x, y, value, color: @colors.fetch(color), size: size, bold: bold)
      end
    end

    class InteractionTool
      def activate
        MaterialHUD.tool_active = true
        MaterialHUD.set_mode(MaterialHUD.mode)
      end

      def deactivate(view)
        @tab_down = false
        MaterialHUD.tool_active = false
        view.invalidate
      end

      def suspend(_view)
        @tab_down = false
      end

      def resume(_view)
        @tab_down = false
        MaterialHUD.schedule_refresh
      end

      def onKeyDown(key, _repeat, _flags, _view)
        return false unless key == 9
        MaterialHUD.toggle_mode unless @tab_down
        @tab_down = true
        true
      end

      def onKeyUp(key, _repeat, _flags, _view)
        return false unless key == 9
        @tab_down = false
        true
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def onLButtonDown(flags, x, y, view)
        return if MaterialHUD.over_panel?(x, y)
        picker = view.pick_helper
        picker.do_pick(x, y)
        entity = picker.best_picked
        selection = Sketchup.active_model.selection
        if (flags & CONSTRAIN_MODIFIER_MASK) != 0
          if entity && entity.valid?
            selection.contains?(entity) ? selection.remove(entity) : selection.add(entity)
          end
        else
          selection.clear
          selection.add(entity) if entity && entity.valid?
        end
        MaterialHUD.schedule_refresh
      end

      def onMouseWheel(_flags, delta, x, y, view)
        return false unless MaterialHUD.over_panel?(x, y)
        MaterialHUD.scroll(delta > 0 ? -3 : 3)
        view.invalidate
        true
      end

      def getMenu(menu)
        menu.add_item('View / Select (Tab)') { MaterialHUD.toggle_mode }
        menu.add_item('Chọn JSON dùng chung...') { MaterialHUD.choose_json }
        menu.add_item('Reload JSON') { MaterialHUD.reload_json }
        menu.add_item('Tắt Material HUD') { MaterialHUD.hide }
      end
    end

    class << self
      attr_writer :panel_rect

      def over_panel?(x, y)
        return false unless @panel_rect
        left, top, width, height = @panel_rect
        x >= left && x <= left + width && y >= top && y <= top + height
      end

      def scroll(delta)
        @scroll = [@scroll.to_i + delta, 0].max
      end

      def scroll_offset(count, capacity)
        @scroll = [[@scroll.to_i, count - capacity].min, 0].max
      end
    end
  end
end
