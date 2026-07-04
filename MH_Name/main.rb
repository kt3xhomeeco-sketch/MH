# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH_Name] requires MH_shared" unless defined?(MH::Shared)

module MH
  module Name

    PLUGIN_DIR = File.dirname(__FILE__)

    class NameTool
      FONT_NAME    = "Segoe UI"
      FONT_SIZE    = 10
      CHAR_WIDTH   = 6.5
      LABEL_PAD_X  = 4
      LABEL_PAD_Y  = 3
      LABEL_HEIGHT = FONT_SIZE + LABEL_PAD_Y * 2 + 2

      COL_LABEL_BG       = Sketchup::Color.new(22, 27, 44, 230)
      COL_LABEL_BG_HOVER = Sketchup::Color.new(40, 75, 160, 240)
      COL_LABEL_BG_SEL   = Sketchup::Color.new(200, 70, 50, 240)
      COL_LABEL_BORDER   = Sketchup::Color.new(70, 90, 140, 160)
      COL_TEXT            = Sketchup::Color.new(60, 60, 80)
      COL_TEXT_HOVER      = Sketchup::Color.new(40, 100, 220)
      COL_TEXT_SEL        = Sketchup::Color.new(220, 60, 40)
      COL_LEADER          = Sketchup::Color.new(0, 0, 0, 255)
      COL_LEADER_HOVER    = Sketchup::Color.new(0, 0, 0, 255)
      COL_LEADER_SEL      = Sketchup::Color.new(0, 0, 0, 255)
      COL_DOT             = Sketchup::Color.new(255, 0, 0, 255)
      COL_DOT_SEL         = Sketchup::Color.new(255, 0, 0, 255)
      COL_SEL_EDGE        = Sketchup::Color.new(255, 120, 80, 220)
      COL_HIGHLIGHT_EDGE  = Sketchup::Color.new(91, 140, 255, 180)

      def initialize
        @entities = []
        @line_spacing = 28       # thay vì 10, để row_h = @line_spacing (mặc định 28)
        @text_gap = 150          # khoảng cách text-object (thay leader_extension)
        @hover_index = nil
        @selected_indices = []
        @label_rects = []
        @entity_names = {}
        @original_transparency = nil
        @dialog = nil
        @opaque_cache = {}       # cache triangulated faces cho selected entities
        @text_display_mode = :all # mode hiển thị text
      end

      def activate
        model = Sketchup.active_model
        @entities = collect_entities(model)
        if @entities.empty?
          UI.messagebox("Không có Group/Component nào.\nHãy chọn các đối tượng trước.")
          model.select_tool(nil)
          return
        end
        refresh_name_cache
        enable_xray(model)
        show_controls
        Sketchup.set_status_text("MH_Name: Click tên → Select | Double-click → Sửa tên | ESC → Thoát")
        model.active_view.invalidate
      end

      def deactivate(view)
        restore_xray(view.model)
        @dialog.close if @dialog && @dialog.visible?
        view.invalidate
      end

      def suspend(view); view.invalidate; end
      def resume(view)
        view.invalidate
        @dialog.bring_to_front if @dialog && @dialog.visible?
      end

      def onSetCursor
        UI.set_cursor(@hover_index ? 632 : 0)
      end

      # ===================== DRAW =====================
      def draw(view)
        return if @entities.empty?

        # 1) Vẽ NON-selected entities với opacity 10% bằng 3D (tạo Z-buffer)
        @entities.each_with_index do |e, idx|
          next unless e && e.valid?
          next if @selected_indices.include?(idx)
          draw_entity_translucent(view, e, 26)  # 10% of 255
        end

        # 2) Vẽ selected entities: Mặt cafe bằng 2D (nhìn xuyên thấu opacity 180)
        @selected_indices.each do |idx|
          next if idx >= @entities.length
          e = @entities[idx]
          next unless e && e.valid?
          draw_entity_faces_2d(view, e)
        end

        # 3) Vẽ ALL selected edges dashed bằng draw2d (xuyên thấu MỌI thứ)
        all_edge_pts = []
        @selected_indices.each do |idx|
          next if idx >= @entities.length
          e = @entities[idx]
          next unless e && e.valid?
          all_edge_pts.concat(get_edge_screen_pts(view, e))
        end
        unless all_edge_pts.empty?
          MH::OverlayEngine.line2d(view, all_edge_pts, color: "black", stipple: "-", width: 2)
        end

        # 4) Vẽ ALL selected edges solid bằng 3D (Z-buffer tự ẩn phần bị che)
        all_edge_3d = []
        @selected_indices.each do |idx|
          next if idx >= @entities.length
          e = @entities[idx]
          next unless e && e.valid?
          all_edge_3d.concat(get_edge_3d_pts(e))
        end
        unless all_edge_3d.empty?
          view.line_width = 2
          view.drawing_color = "black"
          view.line_stipple = ""
          view.draw(GL_LINES, all_edge_3d)
        end

        # 5) Tính layout + vẽ labels/leaders
        layout = calculate_layout(view)
        @label_rects = []
        layout[:left].each  { |item| draw_item(view, item) }
        layout[:right].each { |item| draw_item(view, item) }
      end

      # ===================== MOUSE =====================
      def onMouseMove(flags, x, y, view)
        old = @hover_index
        @hover_index = find_label_at(x, y)
        if old != @hover_index
          view.invalidate
          if @hover_index
            name = @entity_names[@entities[@hover_index]] || "?"
            Sketchup.set_status_text("MH_Name: [#{name}] — Click select, Dbl-click sửa tên")
          else
            Sketchup.set_status_text("MH_Name: Click tên → Select | Double-click → Sửa tên | ESC → Thoát")
          end
        end
      end

      def onLButtonDown(flags, x, y, view)
        idx = find_label_at(x, y)
        if idx.nil?
          ph = view.pick_helper
          ph.do_pick(x, y)
          best = ph.best_picked
          idx = @entities.index(best) if best
        end
        return unless idx
        
        entity = @entities[idx]
        return unless entity && entity.valid?
        model = view.model
        if flags & 0x04 != 0
          # Toggle
          if @selected_indices.include?(idx)
            @selected_indices.delete(idx)
            model.selection.remove(entity)
          else
            @selected_indices << idx
            model.selection.add(entity)
          end
        else
          @selected_indices = [idx]
          model.selection.clear
          model.selection.add(entity)
        end
        @opaque_cache.clear
        view.invalidate
      end

      def onLButtonDoubleClick(flags, x, y, view)
        idx = find_label_at(x, y)
        return unless idx
        edit_name(idx, view)
      end

      def onKeyDown(key, repeat, flags, view)
        if key == 27
          view.model.select_tool(nil)
          return true
        end
        if key == 46 && !@selected_indices.empty?
          delete_selected(view)
          return true
        end
        false
      end

      def getMenu(menu)
        menu.add_item("Đóng MH_Name") { Sketchup.active_model.select_tool(nil) }
        menu.add_separator
        
        if @hover_index && @selected_indices.include?(@hover_index) && @selected_indices.length > 1
          menu.add_item("Sửa tên (#{@selected_indices.length} chi tiết)") { edit_name(@hover_index, Sketchup.active_model.active_view) }
          menu.add_separator
        elsif @hover_index
          name = @entity_names[@entities[@hover_index]] || "?"
          menu.add_item("Sửa tên: #{name}") { edit_name(@hover_index, Sketchup.active_model.active_view) }
          menu.add_separator
        elsif @selected_indices.length > 0
          menu.add_item("Sửa tên (#{@selected_indices.length} chi tiết)") { edit_name(@selected_indices.first, Sketchup.active_model.active_view) }
          menu.add_separator
        end
        
        menu.add_item("Chọn tất cả") do
          @selected_indices = (0...@entities.length).to_a
          m = Sketchup.active_model; m.selection.clear
          @entities.each { |e| m.selection.add(e) if e.valid? }
          @opaque_cache.clear; m.active_view.invalidate
        end
        menu.add_item("Bỏ chọn") do
          @selected_indices.clear; @opaque_cache.clear
          Sketchup.active_model.selection.clear
          Sketchup.active_model.active_view.invalidate
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @entities.each { |e| bb.add(e.bounds) if e.valid? }
        bb
      end

      private

      # ===================== ENTITY HELPERS =====================
      def collect_entities(model)
        sel = model.selection.to_a
        src = sel.empty? ? model.active_entities.to_a : sel
        src.select { |e| (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.valid? }
      end

      def refresh_name_cache
        @entity_names = {}
        @entities.each { |e| @entity_names[e] = get_entity_name(e) }
      end

      def get_entity_name(entity)
        if entity.is_a?(Sketchup::Group)
          entity.name.empty? ? "<Group>" : entity.name
        elsif entity.is_a?(Sketchup::ComponentInstance)
          entity.name.empty? ? entity.definition.name : entity.name
        else
          "<Unknown>"
        end
      end

      # ===================== X-RAY =====================
      def enable_xray(model)
        @original_transparency = model.rendering_options["ModelTransparency"]
        model.rendering_options["ModelTransparency"] = true
      end

      def restore_xray(model)
        return if @original_transparency.nil?
        model.rendering_options["ModelTransparency"] = @original_transparency
      end

      # ===================== OPAQUE RENDERING =====================
      # Thu thập tất cả triangulated faces từ entity → vẽ đặc 100%
      def collect_triangles(entity)
        triangles = []  # [[pt1,pt2,pt3, color], ...]
        tr = entity.transformation
        ents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        collect_faces_recursive(ents, tr, triangles)
        triangles
      end

      # Kiểm tra transformation có bị mirror (lật gương) không
      def tr_flipped?(tr)
        xa = tr.xaxis; ya = tr.yaxis; za = tr.zaxis
        det = xa.x * (ya.y * za.z - ya.z * za.y) -
              xa.y * (ya.x * za.z - ya.z * za.x) +
              xa.z * (ya.x * za.y - ya.y * za.x)
        det < 0
      end

      def collect_faces_recursive(entities, parent_tr, result)
        flipped = tr_flipped?(parent_tr)
        entities.each do |e|
          if e.is_a?(Sketchup::Face)
            mesh = e.mesh
            # Transform normal sang world space
            n_world = e.normal.transform(parent_tr)
            # Nếu transformation bị mirror → lật ngược normal
            n_world = n_world.reverse if flipped
            pt_world = e.vertices.first.position.transform(parent_tr)
            (1..mesh.count_polygons).each do |pi|
              pts = mesh.polygon_points_at(pi)
              next unless pts && pts.length >= 3
              tpts = pts.map { |p| p.transform(parent_tr) }
              result << { pts: tpts, n_world: n_world, pt_world: pt_world }
            end
          elsif e.is_a?(Sketchup::Group)
            collect_faces_recursive(e.entities, parent_tr * e.transformation, result)
          elsif e.is_a?(Sketchup::ComponentInstance)
            collect_faces_recursive(e.definition.entities, parent_tr * e.transformation, result)
          end
        end
      end

      def face_color(face)
        mat = face.material
        if mat && mat.color
          c = mat.color
          Sketchup::Color.new(c.red, c.green, c.blue, 255)
        else
          Sketchup::Color.new(180, 180, 180, 255)
        end
      end

      # Vẽ mặt cafe bằng 2D (nhìn xuyên thấu với opacity 180)
      def draw_entity_faces_2d(view, entity)
        eid = entity.entityID
        tris = @opaque_cache[eid]
        if tris.nil?
          tris = collect_triangles(entity)
          @opaque_cache[eid] = tris
        end
        return if tris.empty?

        eye = view.camera.eye
        screen_pts = []
        tris.each do |tri|
          v = tri[:pt_world] - eye
          if (v % tri[:n_world]) < 0 # backface culling
            screen_pts << view.screen_coords(tri[:pts][0])
            screen_pts << view.screen_coords(tri[:pts][1])
            screen_pts << view.screen_coords(tri[:pts][2])
          end
        end
        view.drawing_color = Sketchup::Color.new(120, 70, 40, 180) # Opacity 180 (khoảng 70%) để nhìn xuyên qua non-select
        view.draw2d(GL_TRIANGLES, screen_pts) unless screen_pts.empty?
      end

      # Lấy edge points ở screen space (cho draw2d)
      def get_edge_screen_pts(view, entity)
        lines = get_edge_3d_pts(entity)
        lines.map { |p| view.screen_coords(p) }
      end

      # Lấy edge points ở 3D world space
      def get_edge_3d_pts(entity)
        @line_cache ||= {}
        eid = entity.entityID
        unless @line_cache[eid]
          pts = []
          ents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
          collect_edges_simple(ents, entity.transformation, pts)
          @line_cache[eid] = pts
        end
        @line_cache[eid]
      end

      def collect_edges_simple(entities, parent_tr, result)
        entities.each do |e|
          if e.is_a?(Sketchup::Edge)
            result << e.start.position.transform(parent_tr)
            result << e.end.position.transform(parent_tr)
          elsif e.is_a?(Sketchup::Group)
            collect_edges_simple(e.entities, parent_tr * e.transformation, result)
          elsif e.is_a?(Sketchup::ComponentInstance)
            collect_edges_simple(e.definition.entities, parent_tr * e.transformation, result)
          end
        end
      end

      def update_lines_cache(entity)
        @line_cache ||= {}
        eid = entity.entityID
        unless @line_cache[eid]
          data = []
          collect_lines_recursive(entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities, entity.transformation, data)
          @line_cache[eid] = data
        end
        @line_cache[eid]
      end

      def collect_lines_recursive(entities, parent_tr, result)
        flipped = tr_flipped?(parent_tr)
        entities.each do |e|
          if e.is_a?(Sketchup::Edge)
            p1 = e.start.position.transform(parent_tr)
            p2 = e.end.position.transform(parent_tr)
            pt_world = p1
            faces_info = e.faces.map do |f|
              n_world = f.normal.transform(parent_tr)
              n_world = n_world.reverse if flipped
              { n_world: n_world, pt_world: pt_world }
            end
            result << { p1: p1, p2: p2, faces: faces_info }
          elsif e.is_a?(Sketchup::Group)
            collect_lines_recursive(e.entities, parent_tr * e.transformation, result)
          elsif e.is_a?(Sketchup::ComponentInstance)
            collect_lines_recursive(e.definition.entities, parent_tr * e.transformation, result)
          end
        end
      end

      # Vẽ entity với opacity tùy chỉnh (translucent)
      def draw_entity_translucent(view, entity, alpha)
        eid = entity.entityID
        @opaque_cache[eid] ||= collect_triangles(entity)
        tris = @opaque_cache[eid]
        return if tris.empty?

        all_pts = []
        tris.each { |tri| all_pts.concat(tri[:pts]) }

        view.drawing_color = Sketchup::Color.new(128, 128, 128, alpha)
        view.draw(GL_TRIANGLES, all_pts)
      end

      # ===================== LAYOUT =====================
      def calculate_layout(view)
        return { left: [], right: [] } if @entities.empty?

        ents_to_draw = @text_display_mode == :selected ? @selected_indices.map { |i| @entities[i] } : @entities
        
        items = ents_to_draw.each_with_index.map { |e, i|
          next nil unless e && e.valid?
          center = e.bounds.center
          screen = view.screen_coords(center)
          # Preserve original index for selection clicking
          orig_index = @entities.index(e) || i
          { entity: e, index: orig_index, center3d: center,
            screen_x: screen.x, screen_y: screen.y,
            name: @entity_names[e] || get_entity_name(e) }
        }.compact
        return { left: [], right: [] } if items.empty?

        # Centroid screen
        avg_x = items.sum { |i| i[:screen_x] } / items.length.to_f

        left  = items.select { |i| i[:screen_x] <= avg_x }.sort_by { |i| i[:screen_y] }
        right = items.select { |i| i[:screen_x] > avg_x  }.sort_by { |i| i[:screen_y] }

        if left.empty? && !right.empty?
          half = (right.length / 2.0).ceil
          left = right[0...half]; right = right[half..-1] || []
        elsif right.empty? && !left.empty?
          half = (left.length / 2.0).ceil
          right = left[half..-1] || []; left = left[0...half]
        end

        vp_w = view.vpwidth
        vp_h = view.vpheight
        row_h = @line_spacing

        if !left.empty?
          avg_y_left = left.sum { |i| i[:screen_y] } / left.length.to_f
          left_total_h = left.length * row_h
          left_start_y = avg_y_left - left_total_h / 2.0

          left.each_with_index do |item, i|
            tw = calc_text_width(item[:name])
            lw = tw + LABEL_PAD_X * 2
            lx = [avg_x - @text_gap - lw, 8].max
            item[:label_x] = lx
            item[:label_y] = left_start_y + i * row_h
            item[:label_w] = lw
            item[:side] = :left
          end
        end

        if !right.empty?
          avg_y_right = right.sum { |i| i[:screen_y] } / right.length.to_f
          right_total_h = right.length * row_h
          right_start_y = avg_y_right - right_total_h / 2.0

          right.each_with_index do |item, i|
            tw = calc_text_width(item[:name])
            lw = tw + LABEL_PAD_X * 2
            lx = [avg_x + @text_gap, vp_w - lw - 8].min
            item[:label_x] = lx
            item[:label_y] = right_start_y + i * row_h
            item[:label_w] = lw
            item[:side] = :right
          end
        end

        { left: left, right: right }
      end

      def calc_text_width(text)
        [text.to_s.length * CHAR_WIDTH + 4, 60].max
      end

      # ===================== DRAW HELPERS =====================
      def draw_item(view, item)
        idx = item[:index]
        name = item[:name]
        side = item[:side]
        
        is_hover = (@hover_index == idx)
        is_sel = @selected_indices.include?(idx)

        lx = item[:label_x]; ly = item[:label_y]
        lw = item[:label_w]; lh = LABEL_HEIGHT

        # Text only — không nền, không border
        tc = is_sel ? COL_TEXT_SEL : (is_hover ? COL_TEXT_HOVER : COL_TEXT)
        MH::OverlayEngine.text(view, lx + LABEL_PAD_X, ly + LABEL_PAD_Y,
                               name.to_s.gsub(/[\r\n]/, ' '),
                               font: FONT_NAME, size: FONT_SIZE, color: tc, bold: false)

        # Hit-test rect (invisible)
        @label_rects << { x: lx, y: ly, w: lw, h: lh, index: idx }

        leader_start = if side == :left
          Geom::Point3d.new(lx + lw, ly + lh / 2.0, 0)
        else
          Geom::Point3d.new(lx, ly + lh / 2.0, 0)
        end

        elbow = if side == :left
          Geom::Point3d.new(leader_start.x + 20, leader_start.y, 0)
        else
          Geom::Point3d.new(leader_start.x - 20, leader_start.y, 0)
        end

        lcol = is_sel ? COL_LEADER_SEL : (is_hover ? COL_LEADER_HOVER : COL_LEADER)
        
        entity_scr = Geom::Point3d.new(item[:screen_x], item[:screen_y], 0)
        MH::OverlayEngine.line2d(view, [leader_start, elbow, entity_scr], color: lcol, mode: GL_LINE_STRIP, stipple: "", width: (is_sel || is_hover) ? 2 : 1)

        # Dot tại entity (chấm tròn)
        dc = is_sel ? COL_DOT_SEL : COL_DOT
        ds = (is_sel || is_hover) ? 1.75 : 1.25
        circle_pts = []
        8.times do |i|
          angle = i * Math::PI / 4.0
          circle_pts << Geom::Point3d.new(entity_scr.x + ds * Math.cos(angle), entity_scr.y + ds * Math.sin(angle), 0)
        end
        MH::OverlayEngine.polygon2d(view, circle_pts, color: dc)
      end



      def find_label_at(x, y)
        @label_rects.each do |r|
          return r[:index] if x >= r[:x] && x <= r[:x]+r[:w] && y >= r[:y] && y <= r[:y]+r[:h]
        end
        nil
      end

      # ===================== ACTIONS =====================
      def edit_name(index, view)
        target = @entities[index]
        return unless target && target.valid?
        
        # Xác định danh sách cần đổi tên
        to_rename = []
        if @selected_indices.include?(index) && @selected_indices.length > 1
          to_rename = @selected_indices.map { |i| @entities[i] }.compact.select(&:valid?)
          prompt_title = "Sửa tên (#{@selected_indices.length} chi tiết)"
        else
          to_rename = [target]
          prompt_title = "Sửa tên"
        end

        cur = @entity_names[target] || ""
        cur = "" if cur.start_with?("<")
        
        results = UI.inputbox(["Tên mới:"], [cur], prompt_title)
        if results
          nn = results[0].to_s.strip
          model = view.model
          model.start_operation('MH_Name: Rename', true)
          to_rename.each do |ent|
            ent.name = nn
            @entity_names[ent] = nn.empty? ? get_entity_name(ent) : nn
          end
          model.commit_operation
          view.invalidate; update_control_info
        end
      end

      def delete_selected(view)
        return if @selected_indices.empty?
        model = view.model
        to_del = @selected_indices.map { |i| @entities[i] }.compact.select(&:valid?)
        return if to_del.empty?
        model.start_operation('MH_Name: Delete', true)
        to_del.each(&:erase!)
        model.commit_operation
        @entities.reject! { |e| !e.valid? }
        @selected_indices.clear; @opaque_cache.clear
        refresh_name_cache; model.selection.clear
        view.invalidate; update_control_info
      end

      # ===================== CONTROL PANEL =====================
      def show_controls
        return if @dialog && @dialog.visible?
        @dialog = UI::HtmlDialog.new(
          dialog_title: "MH_Name", preferences_key: "mh_name_ctrl_v3",
          width: 300, height: 450, left: 100, top: 120,
          resizable: false, style: UI::HtmlDialog::STYLE_UTILITY
        )
        @dialog.set_html(build_control_html)
        @dialog.add_action_callback("setSpacing") { |_,v| @line_spacing = v.to_i; Sketchup.active_model.active_view.invalidate }
        @dialog.add_action_callback("setGap")     { |_,v| @text_gap = v.to_i; Sketchup.active_model.active_view.invalidate }
        
        @dialog.add_action_callback("setTextMode") do |_, mode|
          @text_display_mode = mode.to_sym
          Sketchup.active_model.active_view.invalidate
        end
        
        @dialog.add_action_callback("updateSelection") do |_, indices_str|
          @selected_indices.clear
          @opaque_cache.clear
          m = Sketchup.active_model
          m.selection.clear
          
          unless indices_str.empty?
            indices_str.split(',').map(&:to_i).each do |idx|
              @selected_indices << idx
              m.selection.add(@entities[idx]) if @entities[idx] && @entities[idx].valid?
            end
          end
          m.active_view.invalidate
          update_control_info
        end
        
        @dialog.add_action_callback("closeTool") { |_| Sketchup.active_model.select_tool(nil) }
        @dialog.show
      end

      def build_control_html
        <<~HTML
          <!DOCTYPE html><html><head><meta charset="UTF-8">
          <style>
            :root{--bg0:#0d0f18;--bg1:#13162a;--bg2:#1c2040;--bg3:#232848;
              --acc:#5b8cff;--acc2:#7fd4e8;--ok:#55e5a0;--danger:#ff5f5f;
              --txt:#d8dff0;--txt2:#7a8ab0;--border:rgba(91,140,255,.2);--r:6px}
            *{box-sizing:border-box;margin:0;padding:0}
            body{font-family:'Segoe UI',sans-serif;background:var(--bg0);color:var(--txt);
              font-size:12px;padding:12px;user-select:none}
            .header{display:flex;align-items:center;justify-content:space-between;
              margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid var(--border)}
            .title{font-family:monospace;font-size:13px;font-weight:700;color:var(--acc)}
            .count{font-size:10px;color:var(--txt2);background:var(--bg2);padding:2px 8px;border-radius:20px}
            .control{margin-bottom:12px}
            .control label{display:flex;align-items:center;justify-content:space-between;
              font-size:11px;margin-bottom:4px;color:var(--txt2)}
            .val{font-family:monospace;font-size:10px;color:var(--acc);min-width:28px;text-align:right}
            input[type="range"]{width:100%;height:6px;-webkit-appearance:none;
              background:var(--bg2);border-radius:3px;outline:none}
            input[type="range"]::-webkit-slider-thumb{-webkit-appearance:none;width:14px;height:14px;
              background:var(--acc);border-radius:50%;cursor:pointer;border:2px solid var(--bg0)}
            .actions{display:flex;gap:6px;margin-top:10px;padding-top:8px;border-top:1px solid var(--border)}
            .btn{flex:1;padding:5px 0;border:1px solid var(--border);border-radius:var(--r);
              background:var(--bg2);color:var(--txt2);font-size:10px;font-weight:600;cursor:pointer;text-align:center}
            .btn:hover{background:var(--bg3);color:var(--txt)}
            .btn.danger{background:rgba(255,95,95,.12);border-color:rgba(255,95,95,.3);color:var(--danger)}
            .btn.danger:hover{background:rgba(255,95,95,.25)}
            .item-row { padding: 4px; border-bottom: 1px solid rgba(255,255,255,0.05); }
            .item-row:hover { background: var(--bg2); }
            ::-webkit-scrollbar{width:6px}
            ::-webkit-scrollbar-track{background:var(--bg1)}
            ::-webkit-scrollbar-thumb{background:var(--bg3);border-radius:3px}
          </style>
          <script>
            let sketchup = window.sketchup;
            function updateSelection() {
              let checked = [];
              document.querySelectorAll('.ent-cb:checked').forEach(cb => checked.push(cb.value));
              sketchup.updateSelection(checked.join(','));
            }
            function filterList(term) {
              term = term.toLowerCase().trim();
              document.querySelectorAll('.item-row').forEach(row => {
                if (term === "" || row.getAttribute('data-name').includes(term)) {
                  row.style.display = "block";
                } else {
                  row.style.display = "none";
                }
              });
            }
            function toggleAll(selectAll) {
              let cbs = document.querySelectorAll('.ent-cb');
              cbs.forEach(cb => {
                if (cb.closest('.item-row').style.display !== "none") cb.checked = selectAll;
              });
              updateSelection();
            }
            // Khởi tạo script - load lại selection state
            function setCheckboxes(indices) {
              document.querySelectorAll('.ent-cb').forEach(cb => cb.checked = false);
              indices.split(',').forEach(i => {
                if (i !== "") {
                  let el = document.querySelector('.ent-cb[value="'+i+'"]');
                  if (el) el.checked = true;
                }
              });
            }
          </script>
          </head><body>
            <div class="header">
              <span class="title">⬡ MH_Name</span>
              <span class="count" id="countBadge">#{@entities.length} objects</span>
            </div>
            <div class="control" style="margin-bottom:8px">
              <input type="text" id="searchInput" placeholder="Tìm kiếm chi tiết..." style="width:100%; padding: 6px; border-radius: var(--r); border: 1px solid var(--border); background: var(--bg2); color: var(--txt); outline:none"
                oninput="filterList(this.value)">
            </div>
            
            <div style="display:flex; gap:4px; margin-bottom:4px">
              <button class="btn" style="flex:1" onclick="toggleAll(true)">Tick hết (lọc)</button>
              <button class="btn" style="flex:1" onclick="toggleAll(false)">Bỏ tick hết</button>
            </div>
            
            <div id="entityList" style="max-height: 140px; overflow-y: auto; border: 1px solid var(--border); border-radius: var(--r); padding: 4px; margin-bottom: 12px; background: rgba(0,0,0,0.2);">
              #{@entities.each_with_index.map { |e, i| 
                name = @entity_names[e] || "Unknown"
                sel = @selected_indices.include?(i) ? "checked" : ""
                "<div class='item-row' data-name='#{name.downcase}'><label style='display:flex; align-items:center; cursor:pointer'><input type='checkbox' class='ent-cb' value='#{i}' #{sel} onchange='updateSelection()'> <span style='margin-left:6px; font-size:11px'>#{name}</span></label></div>"
              }.join("\n")}
            </div>

            <div class="control" style="margin-bottom:12px; font-size:11px; background: var(--bg1); padding: 8px; border-radius: var(--r);">
              <div style="font-weight:bold; margin-bottom:6px; color: var(--acc2);">Chế độ hiển thị Text:</div>
              <label style="display:flex; align-items:center; justify-content:flex-start; margin-bottom:4px; cursor:pointer"><input type="radio" name="txtMode" value="all" #{@text_display_mode == :all ? 'checked' : ''} onchange="sketchup.setTextMode('all')"> <span style="margin-left:6px">Hiện tên tất cả chi tiết</span></label>
              <label style="display:flex; align-items:center; justify-content:flex-start; cursor:pointer"><input type="radio" name="txtMode" value="selected" #{@text_display_mode == :selected ? 'checked' : ''} onchange="sketchup.setTextMode('selected')"> <span style="margin-left:6px">Chỉ hiện tên chi tiết được chọn</span></label>
            </div>

            <div class="control">
              <label>Khoảng cách dòng <span class="val" id="sV">#{@line_spacing}</span></label>
              <input type="range" min="0" max="80" value="#{@line_spacing}"
                oninput="document.getElementById('sV').textContent=this.value;sketchup.setSpacing(+this.value)">
            </div>
            <div class="control">
              <label>Khoảng cách Text ↔ Object <span class="val" id="gV">#{@text_gap}</span></label>
              <input type="range" min="30" max="500" value="#{@text_gap}"
                oninput="document.getElementById('gV').textContent=this.value;sketchup.setGap(+this.value)">
            </div>
            <div class="actions">
              <button class="btn danger" onclick="sketchup.closeTool()">Đóng</button>
            </div>
          </body></html>
        HTML
      end

      def update_control_info
        return unless @dialog && @dialog.visible?
        @dialog.execute_script("document.getElementById('countBadge').textContent='#{@entities.length} objects';")
        @dialog.execute_script("if(typeof setCheckboxes === 'function') setCheckboxes('#{@selected_indices.join(',')}');")
      rescue
      end
    end

    @loaded = true unless @loaded

  end
end
