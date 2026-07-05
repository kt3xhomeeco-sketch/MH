require 'sketchup.rb'

module ABF_Ring_OverlayTool
  class << self
    attr_accessor :dialog
  end

  def self.run_agent
    self.activate
  end

  def self.activate
    Sketchup.active_model.select_tool(Tool.new)
  end

  class Tool
    def activate
      @model  = Sketchup.active_model
      @root   = @model.selection.first
      unless @root
        UI.messagebox("Vui lòng chọn bảng Nesting trước khi bật tool!")
        Sketchup.active_model.select_tool(nil)
        return
      end

      # Chuyển sang view Top và tắt phối cảnh
      set_top_view

      @sheets          = @root.entities.grep(Sketchup::Group)
      @selected_board  = nil

      rebuild_ring_groups

      # Cập nhật lại callback nếu bảng đang mở từ lần chạy trước
      if ABF_Ring_OverlayTool.dialog
        setup_callbacks(ABF_Ring_OverlayTool.dialog)
        hide_dialog_info
      end
    end

    def deactivate(view)
      @selected_board = nil
      if ABF_Ring_OverlayTool.dialog
        ABF_Ring_OverlayTool.dialog.close
        ABF_Ring_OverlayTool.dialog = nil
      end
      view.invalidate
    end

    def onCancel(reason, view)
      @selected_board = nil
      if ABF_Ring_OverlayTool.dialog
        ABF_Ring_OverlayTool.dialog.close
        ABF_Ring_OverlayTool.dialog = nil
      end
      view.invalidate
    end

    def onMButtonDown(flags, x, y, view)
      # Kiểm tra phím Shift: 1 = CONSTRAIN_MODIFIER_MASK, 4 = MK_SHIFT trên Windows
      if (flags & 1) != 0 || (flags & 4) != 0 || (flags & 8) != 0
        @panning = true
        @pan_start_x = x
        @pan_start_y = y
        @pan_start_target = view.camera.target.clone
        @pan_start_eye = view.camera.eye.clone
      end
      true # Khóa Orbit mặc định
    end

    def onMButtonUp(flags, x, y, view)
      @panning = false
      true
    end

    def onMButtonDoubleClick(flags, x, y, view)
      true
    end

    def onMouseMove(flags, x, y, view)
      if @panning
        dx = x - @pan_start_x
        dy = y - @pan_start_y
        scale = view.pixels_to_model(1, @pan_start_target)
        shift_x = -dx * scale
        shift_y = dy * scale
        vec = Geom::Vector3d.new(shift_x, shift_y, 0)
        view.camera.set(@pan_start_eye + vec, @pan_start_target + vec, Geom::Vector3d.new(0, 1, 0))
      end
    end

    def resume(view)
      view.invalidate
    end

    def set_top_view
      view = Sketchup.active_model.active_view
      cam = view.camera
      cam.perspective = false
      target = cam.target
      eye = Geom::Point3d.new(target.x, target.y, target.z + 1000)
      up = Geom::Vector3d.new(0, 1, 0)
      cam.set(eye, target, up)
      Sketchup.send_action("viewTop:")
    end

    # =====================
    # REBUILD DATA
    # =====================
    def rebuild_ring_groups
      @ring_groups = {}
      @sheets.each do |sheet|
        get_boards(sheet).each do |board|
          ring = read_ring_layer(board)
          next unless ring && ring != "0"
          @ring_groups[ring] ||= []
          @ring_groups[ring] << { board: board, sheet: sheet }
        end
      end
    end

    # =====================
    # DRAW
    # =====================
    def draw(view)
      return unless @ring_groups

      @ring_groups.each do |ring_label, items|
        dir   = ring_label[0].to_sym
        index = ring_label[1..].to_i - 1

        color        = color_for(dir, index)
        border_color = darken(color)

        items.each do |item|
          board = item[:board]
          sheet = item[:sheet]

          pts, cutting_tr = get_polygon(board)
          next if pts.empty?

          combined = @root.transformation * sheet.transformation *
                     board.transformation * cutting_tr
          pts.map! { |p| p.transform(combined) }

          pts_above = pts.map { |p| Geom::Point3d.new(p.x, p.y, p.z + 0.1) }

          view.drawing_color = color
          view.draw(GL_POLYGON, pts_above)

          view.drawing_color = border_color
          view.line_width = 1
          view.draw(GL_LINE_LOOP, pts_above)

          if @selected_board && board == @selected_board
            pts_sel = pts.map { |p| Geom::Point3d.new(p.x, p.y, p.z + 0.15) }

            view.drawing_color = Sketchup::Color.new(0, 0, 0, 255)
            view.line_width = 5
            view.draw(GL_LINE_LOOP, pts_sel)

            view.drawing_color = Sketchup::Color.new(255, 220, 0, 255)
            view.line_width = 2
            view.draw(GL_LINE_LOOP, pts_sel)

            view.line_width = 1
          end

          cx = pts.sum(&:x) / pts.size
          cy = pts.sum(&:y) / pts.size
          cz = pts.sum(&:z) / pts.size
          centroid_3d = Geom::Point3d.new(cx, cy, cz + 0.2)

          screen_pt = view.screen_coords(centroid_3d)
          screen_2d = Geom::Point3d.new(screen_pt.x, screen_pt.y, 0)

          screen_pts = pts.map { |p| view.screen_coords(p) }
          xs = screen_pts.map(&:x)
          ys = screen_pts.map(&:y)
          board_w = xs.max - xs.min
          board_h = ys.max - ys.min
          board_px = [board_w, board_h].min
          font_size = (board_px * 0.25).round.clamp(8, 48)

          view.drawing_color = Sketchup::Color.new(15, 15, 15, 255)
          begin
            view.draw_text(screen_2d, ring_label,
                           size: font_size, bold: true, align: TextAlignCenter)
          rescue
            view.draw_text(screen_2d, ring_label)
          end
        end
      end
    end

    # =====================
    # CLICK
    # =====================
    def onLButtonDown(flags, x, y, view)
      return unless @sheets

      clicked_board = nil

      @sheets.each do |sheet|
        get_boards(sheet).each do |board|
          pts, cutting_tr = get_polygon(board)
          next if pts.empty?

          combined = @root.transformation * sheet.transformation *
                     board.transformation * cutting_tr
          world_pts  = pts.map { |p| p.transform(combined) }
          screen_pts = world_pts.map { |p| view.screen_coords(p) }

          if point_in_polygon_2d?(x, y, screen_pts)
            clicked_board = board
            break
          end
        end
        break if clicked_board
      end

      if clicked_board
        @selected_board = clicked_board
        view.invalidate
        open_input_dialog
      else
        @selected_board = nil
        hide_dialog_info
        view.invalidate
      end
    end

    # =====================
    # HTML DIALOG
    # =====================
    def setup_callbacks(dialog)
      dialog.add_action_callback("confirm") do |_ctx, value|
        if @selected_board && (value =~ /\A[RLTB]\d+\z/ || value == "0" || value == "ABF_cuttingLines")
          tag_to_apply = (value == "0") ? "ABF_cuttingLines" : value
          apply_ring_tag(@selected_board, tag_to_apply)
          rebuild_ring_groups
        end
        @selected_board = nil
        hide_dialog_info
        Sketchup.active_model.active_view.invalidate
      end

      dialog.add_action_callback("cancel") do |_ctx|
        @selected_board = nil
        if ABF_Ring_OverlayTool.dialog
          ABF_Ring_OverlayTool.dialog.close
          ABF_Ring_OverlayTool.dialog = nil
        end
        Sketchup.active_model.active_view.invalidate
      end

      dialog.set_on_closed do
        ABF_Ring_OverlayTool.dialog = nil
        @selected_board = nil
        Sketchup.active_model.active_view.invalidate
      end
    end

    def hide_dialog_info
      if ABF_Ring_OverlayTool.dialog
        ABF_Ring_OverlayTool.dialog.execute_script("setEmpty();")
      end
    end

    def open_input_dialog
      board_to_tag = @selected_board
      return unless board_to_tag

      current_tag = read_ring_layer(board_to_tag) || ""

      if ABF_Ring_OverlayTool.dialog
        d = ABF_Ring_OverlayTool.dialog
        setup_callbacks(d)
        d.execute_script("updateTag('#{current_tag.empty? ? "(chua co)" : current_tag}');")
        d.bring_to_front
        return
      end

      d = UI::HtmlDialog.new(
        dialog_title:    "Ring Tag",
        preferences_key: "ABF_Ring_OverlayTool_Dialog",
        scrollable:      false,
        resizable:       false,
        width:           300,
        height:          140,
        min_width:       300,
        min_height:      140,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )

      html = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            font-family: Arial, sans-serif;
            background: #1e1e1e;
            color: #eee;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            gap: 10px;
            padding: 16px;
          }
          .label { font-size: 12px; color: #aaa; }
          .tag-current { font-size: 13px; color: #f0c040; font-weight: bold; }
          input {
            width: 100%;
            padding: 8px 12px;
            font-size: 22px;
            font-weight: bold;
            text-align: center;
            background: #2d2d2d;
            color: #ffe050;
            border: 2px solid #555;
            border-radius: 6px;
            outline: none;
            letter-spacing: 4px;
            text-transform: uppercase;
          }
          input:focus { border-color: #f0c040; }
          input:disabled { opacity: 0.5; }
          .hint { font-size: 11px; color: #666; }
          .hint kbd {
            background: #333;
            border: 1px solid #555;
            border-radius: 3px;
            padding: 1px 5px;
            font-size: 11px;
            color: #ccc;
          }
        </style>
        </head>
        <body>
          <div class="label" id="tag-label">Tag hien tai: <span class="tag-current" id="tag-val">#{current_tag.empty? ? "(chua co)" : current_tag}</span></div>
          <input id="inp" type="text" maxlength="6"
                 placeholder="VD: R1, L3, T2..."
                 autocomplete="off" spellcheck="false" />
          <div class="hint"><kbd>Enter</kbd> xac nhan &nbsp;·&nbsp; <kbd>Esc</kbd> huy</div>
          <script>
            // Canh giua man hinh
            window.moveTo((screen.width - 300) / 2, (screen.height - 140) / 2);

            const inp = document.getElementById('inp');
            const tagVal = document.getElementById('tag-val');

            function updateTag(val) {
              tagVal.innerText = val;
              inp.value = '';
              inp.disabled = false;
              inp.focus();
            }

            function setEmpty() {
              tagVal.innerText = '(chua chon board)';
              inp.value = '';
              inp.disabled = true;
            }

            inp.focus();
            inp.addEventListener('input', () => {
              inp.value = inp.value.toUpperCase().replace(/[^RLTB0-9]/g, '');
            });
            inp.addEventListener('keydown', (e) => {
              const arrowMap = { 'ArrowUp': 'T', 'ArrowDown': 'B', 'ArrowLeft': 'L', 'ArrowRight': 'R' };
              if (arrowMap[e.key]) {
                e.preventDefault();
                let char = arrowMap[e.key];
                let start = inp.selectionStart;
                let end = inp.selectionEnd;
                inp.value = inp.value.substring(0, start) + char + inp.value.substring(end);
                inp.setSelectionRange(start + 1, start + 1);
                inp.dispatchEvent(new Event('input'));
              } else if (e.key === 'Enter') {
                e.preventDefault();
                if (inp.value.trim() !== '') {
                  sketchup.confirm(inp.value.trim().toUpperCase());
                }
              } else if (e.key === 'Escape') {
                e.preventDefault();
                sketchup.cancel();
              }
            });
          </script>
        </body>
        </html>
      HTML

      d.set_html(html)
      setup_callbacks(d)
      ABF_Ring_OverlayTool.dialog = d
      d.show
    end

    # =====================
    # ÁP DỤNG TAG
    # =====================
    def apply_ring_tag(board, new_tag)
      layers = @model.layers
      layers.add(new_tag) unless layers[new_tag]
      layer = layers[new_tag]

      @model.start_operation("Doi Ring Tag", true)
      board.entities.each do |g|
        next unless g.is_a?(Sketchup::Group)
        next unless g.get_attribute("ABF", "is-cutting-lines")
        g.entities.grep(Sketchup::Edge).each do |e|
          if e.layer.name =~ /\A[RLTB]\d+\z/ || e.layer.name == "ABF_cuttingLines"
            e.layer = layer
          end
        end
      end
      @model.commit_operation
    end

    # =====================
    # ĐỌC RING LAYER
    # =====================
    def read_ring_layer(board)
      board.entities.each do |g|
        next unless g.is_a?(Sketchup::Group)
        next unless g.get_attribute("ABF", "is-cutting-lines")
        g.entities.grep(Sketchup::Edge).each do |e|
          name = e.layer.name
          if name =~ /\A[RLTB]\d+\z/
            return name
          elsif name == "ABF_cuttingLines"
            return "0"
          end
        end
      end
      nil
    end

    # =====================
    # DATA
    # =====================
    def get_boards(sheet)
      sheet.entities.select do |ent|
        dict = ent.attribute_dictionary("ABF")
        ent.is_a?(Sketchup::Group) && dict && dict["is-board"]
      end
    end

    def get_polygon(board)
      board.entities.each do |g|
        next unless g.is_a?(Sketchup::Group)
        next unless g.get_attribute("ABF", "is-cutting-lines")
        edges = g.entities.grep(Sketchup::Edge)
        return [ordered_points(edges), g.transformation]
      end
      [[], Geom::Transformation.new]
    end

    def ordered_points(edges)
      return [] if edges.empty?
      pts     = []
      used    = {}
      edge    = edges.first
      pts    << edge.start.position
      current = edge.end
      used[edge] = true

      while pts.length < edges.length
        next_edge = edges.find { |e| !used[e] && (e.start == current || e.end == current) }
        break unless next_edge
        used[next_edge] = true
        if next_edge.start == current
          pts << next_edge.start.position
          current = next_edge.end
        else
          pts << next_edge.end.position
          current = next_edge.start
        end
      end
      pts
    end

    # =====================
    # COLOR
    # =====================
    BASE_LCH = {
      R: [40, 80,  30],
      L: [65, 75,  85],
      T: [45, 65, 140],
      B: [35, 80, 300]
    }

    def color_for(dir, index)
      l0, c0, h = BASE_LCH[dir] || [50, 50, 0]
      index  = index.clamp(0, 24)
      t      = index.to_f / 24.0
      curved = t ** (1.0 / 3.0)
      l2 = l0 + (100.0 - l0) * curved
      c2 = c0 * (1.0 - curved)
      r, g, b = lch_to_rgb(l2, c2, h)
      Sketchup::Color.new(r, g, b, 255)
    end

    def lch_to_rgb(l, c, h)
      h_rad = h * Math::PI / 180.0
      a = c * Math.cos(h_rad)
      b = c * Math.sin(h_rad)

      fy = (l + 16.0) / 116.0
      fx = a / 500.0 + fy
      fz = fy - b / 200.0

      xn, yn, zn = 0.95047, 1.00000, 1.08883
      epsilon    = 0.206897
      x = xn * (fx > epsilon ? fx**3 : (fx - 16.0 / 116.0) / 7.787)
      y = yn * (fy > epsilon ? fy**3 : (fy - 16.0 / 116.0) / 7.787)
      z = zn * (fz > epsilon ? fz**3 : (fz - 16.0 / 116.0) / 7.787)

      r =  3.2406 * x - 1.5372 * y - 0.4986 * z
      g = -0.9689 * x + 1.8758 * y + 0.0415 * z
      b =  0.0557 * x - 0.2040 * y + 1.0570 * z

      srgb = ->(v) {
        v = v.clamp(0.0, 1.0)
        v <= 0.0031308 ? 12.92 * v : 1.055 * v**(1.0 / 2.4) - 0.055
      }

      [
        (srgb.(r) * 255).round.clamp(0, 255),
        (srgb.(g) * 255).round.clamp(0, 255),
        (srgb.(b) * 255).round.clamp(0, 255)
      ]
    end

    def darken(color)
      r = (color.red   * 0.6).round.clamp(0, 255)
      g = (color.green * 0.6).round.clamp(0, 255)
      b = (color.blue  * 0.6).round.clamp(0, 255)
      Sketchup::Color.new(r, g, b, 255)
    end

    def point_in_polygon_2d?(px, py, screen_pts)
      n      = screen_pts.size
      inside = false
      j      = n - 1
      n.times do |i|
        xi, yi = screen_pts[i].x, screen_pts[i].y
        xj, yj = screen_pts[j].x, screen_pts[j].y
        if ((yi > py) != (yj > py)) &&
           (px < (xj - xi) * (py - yi) / (yj - yi).to_f + xi)
          inside = !inside
        end
        j = i
      end
      inside
    end
  end
end

unless file_loaded?(__FILE__)
  menu = UI.menu("Plugins").add_submenu("MH Fix Nesting")
  menu.add_item("Sửa Ring Tag") {
    ABF_Ring_OverlayTool.run_agent
  }
  file_loaded(__FILE__)
end
