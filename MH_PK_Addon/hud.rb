# encoding: utf-8
# MH_PK_Addon — HUD ve bang view.draw2d (style sang theo preset.rb):
# bang excel duoi-phai (tick + ten, ghi chu thanh dong chu nho duoi ten),
# thu vien duoi-trai, o giua-duoi (ten PK dang chon, click de go truc tiep),
# nut gat SL/md + banh rang setting o goc tren-phai.

module MH_PK_Addon
  class Hud
    EXCEL_ROW_H = 28
    LIB_ROW_H = 17
    HEADER_H = 20
    MAX_VISIBLE_ROWS = 10
    MARGIN = 10
    EXCEL_W = 360
    LIB_W = 280
    CENTER_W = 380
    CENTER_H = 32
    TOGGLE_W = 64
    TOGGLE_H = 22
    GEAR_W = 24
    CANCEL_W = 66
    FONT = 'Arial'.freeze
    FONT_SIZE = 7
    TICK_COL_W = 26
    TICK_SIZE = (FONT_SIZE * 1.5).round + 4 # to them 50% so voi chu

    # Style sang (tham khao preset.rb): nen trang mo, header dam hon dong duoi
    COL_PANEL = Sketchup::Color.new(255, 255, 255, 215)
    COL_HEADER = Sketchup::Color.new(178, 182, 192, 245)
    COL_BORDER = Sketchup::Color.new(150, 150, 150, 255)
    COL_GRID = Sketchup::Color.new(205, 205, 210, 255)
    COL_ROW_HOVER = Sketchup::Color.new(214, 226, 248, 235)
    COL_ROW_ARMED = Sketchup::Color.new(73, 73, 140, 225)
    COL_TEXT = Sketchup::Color.new(60, 60, 60, 255)
    COL_TEXT_HEAD = Sketchup::Color.new(30, 30, 36, 255)
    COL_TEXT_DIM = Sketchup::Color.new(135, 135, 140, 255)
    COL_TEXT_ARMED = Sketchup::Color.new(255, 255, 255, 255)
    COL_TEXT_TICKED = Sketchup::Color.new(0, 0, 205, 255)
    COL_TICK = Sketchup::Color.new(8, 120, 45, 255)
    COL_CENTER_ARMED = Sketchup::Color.new(73, 73, 140, 230)
    COL_CENTER_IDLE = Sketchup::Color.new(255, 255, 255, 215)
    COL_CENTER_EDIT = Sketchup::Color.new(255, 252, 235, 245)
    COL_EDIT_BORDER = Sketchup::Color.new(235, 150, 30, 255)
    COL_TOGGLE_ON = Sketchup::Color.new(80, 180, 110, 240)
    COL_TOGGLE_OFF = Sketchup::Color.new(200, 202, 208, 240)
    COL_CANCEL = Sketchup::Color.new(210, 80, 70, 240)
    COL_CANCEL_OFF = Sketchup::Color.new(205, 205, 210, 235)

    attr_accessor :excel_rows, :lib_names
    attr_reader :hover_key

    def initialize
      @excel_rows = []
      @lib_names = []
      @excel_scroll = 0
      @lib_scroll = 0
      @hover_key = nil
    end

    def reset_scroll
      @excel_scroll = 0
      @lib_scroll = 0
    end

    def row_height(panel)
      panel == :excel ? EXCEL_ROW_H : LIB_ROW_H
    end

    # ---------- layout ----------

    def layout(view)
      vpw = view.vpwidth
      vph = view.vpheight

      excel_visible = [[@excel_rows.length, 1].max, MAX_VISIBLE_ROWS].min
      lib_visible = [[@lib_names.length, 1].max, MAX_VISIBLE_ROWS].min
      excel_h = HEADER_H + excel_visible * EXCEL_ROW_H
      lib_h = HEADER_H + lib_visible * LIB_ROW_H

      excel = { x: vpw - EXCEL_W - MARGIN, y: vph - excel_h - MARGIN, w: EXCEL_W, h: excel_h }
      lib = { x: MARGIN, y: vph - lib_h - MARGIN, w: LIB_W, h: lib_h }
      center = { x: (vpw - CENTER_W) / 2, y: vph - CENTER_H - MARGIN, w: CENTER_W, h: CENTER_H }
      toggle = { x: vpw - TOGGLE_W - MARGIN, y: MARGIN, w: TOGGLE_W, h: TOGGLE_H }
      gear = { x: toggle[:x] - GEAR_W - 6, y: MARGIN, w: GEAR_W, h: TOGGLE_H }
      cancel = { x: gear[:x] - CANCEL_W - 6, y: MARGIN, w: CANCEL_W, h: TOGGLE_H }

      { excel: excel, lib: lib, center: center, toggle: toggle, gear: gear, cancel: cancel }
    end

    def panel_rects(view)
      layout(view).values
    end

    def point_in?(x, y, r)
      x >= r[:x] && x <= r[:x] + r[:w] && y >= r[:y] && y <= r[:y] + r[:h]
    end

    def over_hud?(view, x, y)
      layout(view).values.any? { |r| point_in?(x, y, r) }
    end

    # ---------- hover / click ----------

    def update_hover(view, x, y)
      hit = hit_test(view, x, y)
      key = hit ? hit.values_at(:type, :panel, :index).join(':') : nil
      changed = key != @hover_key
      @hover_key = key
      changed
    end

    def hit_test(view, x, y)
      rects = layout(view)

      return { type: :toggle } if point_in?(x, y, rects[:toggle])
      return { type: :gear } if point_in?(x, y, rects[:gear])
      return { type: :cancel } if point_in?(x, y, rects[:cancel])
      return { type: :center } if point_in?(x, y, rects[:center])

      %i[excel lib].each do |panel|
        r = rects[panel]
        next unless point_in?(x, y, r)

        rows = panel == :excel ? @excel_rows : @lib_names
        scroll = panel == :excel ? @excel_scroll : @lib_scroll
        if y <= r[:y] + HEADER_H
          arrow_w = 18
          up_x = r[:x] + r[:w] - arrow_w * 2
          down_x = r[:x] + r[:w] - arrow_w
          return { type: :scroll, panel: panel, dir: -1 } if x >= up_x && x < down_x
          return { type: :scroll, panel: panel, dir: 1 } if x >= down_x
          return { type: :header, panel: panel }
        end

        index = scroll + ((y - r[:y] - HEADER_H) / row_height(panel)).to_i
        return { type: :row, panel: panel, index: index } if index >= 0 && index < rows.length

        return { type: :panel, panel: panel }
      end
      nil
    end

    def click(view, x, y)
      hit = hit_test(view, x, y)
      return nil unless hit

      case hit[:type]
      when :scroll
        scroll_panel(hit[:panel], hit[:dir])
        { type: :scrolled }
      when :row
        { type: hit[:panel] == :excel ? :arm_excel : :arm_lib, index: hit[:index] }
      when :toggle
        { type: :toggle_length }
      when :gear
        { type: :open_settings }
      when :cancel
        { type: :cancel_session }
      when :center
        { type: :edit_armed }
      else
        { type: :noop }
      end
    end

    def scroll_panel(panel, dir)
      rows = panel == :excel ? @excel_rows : @lib_names
      max_scroll = [rows.length - MAX_VISIBLE_ROWS, 0].max
      if panel == :excel
        @excel_scroll = [[@excel_scroll + dir, 0].max, max_scroll].min
      else
        @lib_scroll = [[@lib_scroll + dir, 0].max, max_scroll].min
      end
    end

    # ---------- draw ----------

    # state: {armed:, length_mode:, product_code:, editing:, edit_text:}
    def draw(view, state)
      rects = layout(view)
      draw_excel_panel(view, rects[:excel], state)
      draw_lib_panel(view, rects[:lib], state)
      draw_center(view, rects[:center], state)
      draw_toggle(view, rects[:toggle], state)
      draw_gear(view, rects[:gear])
      draw_cancel(view, rects[:cancel], state)
    rescue
      nil
    end

    def draw_excel_panel(view, r, state)
      title = state[:product_code].to_s.empty? ? 'PK Excel (chua co SP)' : "PK Excel — #{state[:product_code]}"
      draw_panel_frame(view, r, title, :excel, @excel_rows.length)

      visible_rows(:excel).each_with_index do |row, vi|
        idx = @excel_scroll + vi
        ry = r[:y] + HEADER_H + vi * EXCEL_ROW_H
        armed = armed_row?(state, :excel, idx)
        draw_row_bg(view, r, ry, EXCEL_ROW_H, hover_row?(:excel, idx), armed)

        if row[:ticked]
          draw_tick(view, r[:x] + 6, ry + (EXCEL_ROW_H - TICK_SIZE) / 2 - 1)
        end

        text_col =
          if armed
            COL_TEXT_ARMED
          elsif row[:ticked]
            COL_TEXT_TICKED
          else
            COL_TEXT
          end
        name = truncate_text(row_display_name(row), 44)
        note = truncate_text(row[:note].to_s, 48)
        if note.empty?
          draw_text_at(view, r[:x] + TICK_COL_W + 6, ry + (EXCEL_ROW_H - FONT_SIZE) / 2 - 3, name, text_col)
        else
          draw_text_at(view, r[:x] + TICK_COL_W + 6, ry + 3, name, text_col)
          note_col = armed ? COL_TEXT_ARMED : (row[:ticked] ? COL_TEXT_TICKED : COL_TEXT_DIM)
          draw_text_at(view, r[:x] + TICK_COL_W + 12, ry + EXCEL_ROW_H / 2 + 2, note, note_col)
        end
      end

      draw_column_grid(view, r, [r[:x] + TICK_COL_W])
    end

    def draw_lib_panel(view, r, state)
      draw_panel_frame(view, r, 'Thu vien PK', :lib, @lib_names.length)

      visible_rows(:lib).each_with_index do |name, vi|
        idx = @lib_scroll + vi
        ry = r[:y] + HEADER_H + vi * LIB_ROW_H
        armed = armed_row?(state, :lib, idx)
        draw_row_bg(view, r, ry, LIB_ROW_H, hover_row?(:lib, idx), armed)
        draw_text_at(view, r[:x] + 10, ry + 3, truncate_text(name.to_s, 42), armed ? COL_TEXT_ARMED : COL_TEXT)
      end
    end

    def draw_center(view, r, state)
      editing = state[:editing]
      armed = state[:armed]
      fill = editing ? COL_CENTER_EDIT : (armed ? COL_CENTER_ARMED : COL_CENTER_IDLE)
      border = editing ? COL_EDIT_BORDER : COL_BORDER
      draw_rect(view, r, fill, border, editing ? 2 : 1)

      if editing
        text = "#{state[:edit_text]}|"
        draw_text_centered(view, r, truncate_text(text, 54), COL_TEXT_HEAD)
      elsif armed
        text = display_label_for_armed(armed)
        text = "#{text}  [md]" if state[:length_mode]
        draw_text_centered(view, r, truncate_text(text, 52), COL_TEXT_ARMED)
      else
        draw_text_centered(view, r, 'Chua chon PK — click dong ben duoi hoac click vao day de go ten', COL_TEXT_DIM)
      end
    end

    def draw_toggle(view, r, state)
      on = !!state[:length_mode]
      draw_rect(view, r, on ? COL_TOGGLE_ON : COL_TOGGLE_OFF, COL_BORDER)
      knob_w = r[:w] / 2 - 3
      knob_x = on ? r[:x] + r[:w] / 2 : r[:x] + 3
      knob = { x: knob_x, y: r[:y] + 3, w: knob_w, h: r[:h] - 6 }
      draw_rect(view, knob, Sketchup::Color.new(255, 255, 255, 250), nil)
      label = on ? 'md' : 'SL'
      lx = on ? r[:x] + 9 : r[:x] + r[:w] - 23
      draw_text_at(view, lx, r[:y] + 5, label, on ? COL_TEXT_ARMED : COL_TEXT, true)
    end

    def draw_gear(view, r)
      hovered = @hover_key == 'gear::'
      draw_rect(view, r, hovered ? COL_ROW_HOVER : COL_TOGGLE_OFF, COL_BORDER)
      options = { size: 12, color: COL_TEXT_HEAD, font: FONT }
      view.draw_text(Geom::Point3d.new(r[:x] + 5, r[:y] + 2, 0), '⚙', options)
    rescue
      nil
    end

    # Nut Cancel: huy bo moi thay doi cua phien dang dung. Sang khi co thay doi.
    def draw_cancel(view, r, state)
      ops = state[:session_ops].to_i
      active = ops > 0
      draw_rect(view, r, active ? COL_CANCEL : COL_CANCEL_OFF, COL_BORDER)
      label = active ? "✕ Hủy #{ops}" : '✕ Hủy'
      color = active ? COL_TEXT_ARMED : COL_TEXT_DIM
      draw_text_at(view, r[:x] + 7, r[:y] + 5, label, color, true)
    rescue
      nil
    end

    # ---------- helpers ----------

    def visible_rows(panel)
      rows = panel == :excel ? @excel_rows : @lib_names
      scroll = panel == :excel ? @excel_scroll : @lib_scroll
      rows[scroll, MAX_VISIBLE_ROWS] || []
    end

    def hover_row?(panel, index)
      @hover_key == "row:#{panel}:#{index}"
    end

    def armed_row?(state, panel, index)
      armed = state[:armed]
      return false unless armed
      armed[:source] == panel && armed[:row_index] == index
    end

    def row_display_name(row)
      name = row[:name].to_s.strip
      qty = row[:qty].to_i
      qty > 1 ? "#{name} (x#{qty})" : name
    end

    def display_label_for_armed(armed)
      MH_PK_Addon.display_name(armed[:name], armed[:spec])
    end

    def truncate_text(text, max_chars)
      str = text.to_s
      str.length > max_chars ? "#{str[0, max_chars - 1]}…" : str
    end

    def draw_tick(view, x, y)
      options = { size: TICK_SIZE, color: COL_TICK, font: 'Arial Bold' }
      view.draw_text(Geom::Point3d.new(x, y, 0), '✓', options)
    rescue
      nil
    end

    def draw_panel_frame(view, r, title, panel, total)
      draw_rect(view, r, COL_PANEL, COL_BORDER)
      header = { x: r[:x], y: r[:y], w: r[:w], h: HEADER_H }
      draw_rect(view, header, COL_HEADER, nil)
      scroll = panel == :excel ? @excel_scroll : @lib_scroll
      suffix = total > MAX_VISIBLE_ROWS ? "  (#{scroll + 1}-#{[scroll + MAX_VISIBLE_ROWS, total].min}/#{total})" : ''
      draw_text_at(view, r[:x] + 8, r[:y] + 5, "#{title}#{suffix}", COL_TEXT_HEAD, true)

      if total > MAX_VISIBLE_ROWS
        arrow_w = 18
        draw_text_at(view, r[:x] + r[:w] - arrow_w * 2 + 4, r[:y] + 5, '▲', COL_TEXT_HEAD)
        draw_text_at(view, r[:x] + r[:w] - arrow_w + 4, r[:y] + 5, '▼', COL_TEXT_HEAD)
      end
    end

    # Ke duong doc chia cot (tu duoi header den day panel).
    def draw_column_grid(view, r, xs)
      view.line_width = 1
      view.drawing_color = COL_GRID
      segments = []
      xs.each do |x|
        segments << Geom::Point3d.new(x, r[:y] + HEADER_H, 0)
        segments << Geom::Point3d.new(x, r[:y] + r[:h], 0)
      end
      view.draw2d(GL_LINES, segments) unless segments.empty?
    rescue
      nil
    end

    def draw_row_bg(view, r, ry, row_h, hovered, armed)
      return unless hovered || armed

      row_rect = { x: r[:x] + 1, y: ry, w: r[:w] - 2, h: row_h }
      draw_rect(view, row_rect, armed ? COL_ROW_ARMED : COL_ROW_HOVER, nil)
    end

    def draw_rect(view, r, fill, border, line_width = 1)
      pts = [
        Geom::Point3d.new(r[:x], r[:y], 0),
        Geom::Point3d.new(r[:x] + r[:w], r[:y], 0),
        Geom::Point3d.new(r[:x] + r[:w], r[:y] + r[:h], 0),
        Geom::Point3d.new(r[:x], r[:y] + r[:h], 0)
      ]
      if fill
        view.drawing_color = fill
        view.draw2d(GL_POLYGON, pts)
      end
      if border
        view.line_width = line_width
        view.drawing_color = border
        view.draw2d(GL_LINE_LOOP, pts)
      end
    rescue
      nil
    end

    def draw_text_at(view, x, y, text, color, bold = false)
      options = { size: FONT_SIZE, color: color, font: bold ? 'Arial Bold' : FONT }
      view.draw_text(Geom::Point3d.new(x, y, 0), text.to_s, options)
    rescue
      view.draw_text(Geom::Point3d.new(x, y, 0), text.to_s) rescue nil
    end

    def draw_text_centered(view, r, text, color)
      pt = Geom::Point3d.new(r[:x] + r[:w] / 2, r[:y] + r[:h] / 2 - FONT_SIZE / 2 - 2, 0)
      options = { size: FONT_SIZE, color: color, font: 'Arial Bold', align: TextAlignCenter }
      view.draw_text(pt, text.to_s, options)
    rescue
      view.draw_text(Geom::Point3d.new(r[:x] + 10, r[:y] + 8, 0), text.to_s) rescue nil
    end
  end
end
