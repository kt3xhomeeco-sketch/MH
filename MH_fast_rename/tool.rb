# encoding: UTF-8
# FastRenameTool - Interactive zone-based rename tool
require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH_fast_rename::Tool] requires MH_shared" unless defined?(MH::Shared) && defined?(MH::OverlayEngine)

module MH
  module FastRename

    class FastRenameTool
      # Colors
      ZONE_COLORS = [
        Sketchup::Color.new(91, 140, 255, 80),   # Blue
        Sketchup::Color.new(120, 220, 120, 80),  # Green
        Sketchup::Color.new(255, 180, 80, 80),   # Orange
        Sketchup::Color.new(220, 120, 220, 80),  # Purple
        Sketchup::Color.new(255, 255, 120, 80),  # Yellow
        Sketchup::Color.new(120, 255, 255, 80)   # Cyan
      ].freeze
      
      ZONE_EDGE_COLORS = [
        Sketchup::Color.new(0, 0, 150, 255),     # Dark Blue
        Sketchup::Color.new(0, 100, 0, 255),     # Dark Green
        Sketchup::Color.new(150, 60, 0, 255),    # Dark Orange
        Sketchup::Color.new(100, 0, 100, 255),   # Dark Purple
        Sketchup::Color.new(150, 150, 0, 255),   # Dark Yellow
        Sketchup::Color.new(0, 150, 150, 255)    # Dark Cyan
      ].freeze

      ZONE_SEL_COLOR   = Sketchup::Color.new(255, 204, 85, 120)
      ZONE_SEL_EDGE    = Sketchup::Color.new(255, 204, 85, 255)
      SPLIT_COLOR      = Sketchup::Color.new(255, 0, 0, 255)
      SPLIT_PREVIEW    = Sketchup::Color.new(255, 0, 0, 200)
      LABEL_COLOR      = Sketchup::Color.new(255, 255, 255)
      LABEL_BG         = Sketchup::Color.new(30, 30, 50, 200)
      MODUL_COLOR      = Sketchup::Color.new(127, 212, 232, 80)
      MODUL_EDGE_COLOR = Sketchup::Color.new(127, 212, 232, 200)

      EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],
               [0,4],[1,5],[2,6],[3,7]].freeze

      SPLIT_AXES = [:z, :x, :y].freeze

      def initialize
        @zones = []
        @selected_zone = nil
        @mode = :select
        @split_axis = 0
        @hovered_zone = nil
        @prefix_suggestions = []
        @selected_zones = []
        @drag_start = nil
        @drag_current = nil
        @sp_start_num = 1
        @gap_threshold_mm = 1000.0
        @merge_source = nil
        @split_all = false
        @ip = Sketchup::InputPoint.new
        load_config
      end

      def load_config
        begin
          mh_rename_dir = File.join(Sketchup.find_support_file("Plugins"), "MH_Rename")
          xlsx_path = File.join(mh_rename_dir, "Config.xlsx")
          return unless File.exist?(xlsx_path)

          rows = MH::ExcelBridge.read_sheet(xlsx_path, sheet: "prefix")
          @prefix_suggestions = rows.flatten.compact.map { |v| v.to_s.strip }.reject(&:empty?)
        rescue => e
          MH::FastRename.dbg("FastRename config load error: #{e.message}") if MH::FastRename.respond_to?(:dbg)
        end
      end

      # ── Tool lifecycle ──────────────────────────────────
      def activate
        @model = Sketchup.active_model
        @view = @model.active_view
        sel = @model.selection.to_a.select { |e|
          e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        }
        if sel.empty?
          UI.messagebox("Hãy chọn các object trước khi kích hoạt tool!")
          @model.select_tool(nil)
          return
        end

        @all_entities = sel
        @sp_start_num = 1
        recluster_all
        @mode = :select
        update_status
        @view.invalidate
      end

      def recluster_all
        gap_inches = @gap_threshold_mm / 25.4
        @zones = MH::FastRename.cluster_entities(@all_entities, gap_inches)
        @zones = MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num)
        @selected_zones = []
        @hovered_zone = nil
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def suspend(view)
        view.invalidate
      end

      # ── Status bar ──────────────────────────────────────
      def update_status
        case @mode
        when :select
          Sketchup.status_text = "MH Fast Rename | Click/Quét TRÁI: chọn khối | C (hoặc Menu PHẢI): Bật Cắt khối | ↑↓: đổi mã | Enter: Áp dụng"
        when :split
          axis_name = SPLIT_AXES[@split_axis].to_s.upcase
          mode_str = @split_all ? "CẮT XUYÊN KHỐI" : "CẮT 1 KHỐI"
          Sketchup.status_text = "CHẾ ĐỘ CẮT | TRÁI: cắt [#{axis_name} - #{mode_str}] | Ctrl: đổi kiểu | Tab: đổi trục | ESC/PHẢI: Thoát cắt"
        when :merge_target
          Sketchup.status_text = "GỘP KHỐI | Click vào khối khác để gộp vào khối đang chọn | ESC: Hủy"
        end
      end

      # ── Drawing ─────────────────────────────────────────
      def draw(view)
        draw_zones(view)
        draw_split_preview(view) if @mode == :split && @split_preview_pos && @hovered_zone && !@drag_start
        draw_selection_box(view)
        draw_labels(view)
        @ip.draw(view) if @mode == :split && @ip && @ip.valid? && !@drag_start
      end

      def draw_selection_box(view)
        if @drag_start && @drag_current
          x1, y1 = @drag_start
          x2, y2 = @drag_current
          pts = [
            Geom::Point3d.new(x1, y1, 0),
            Geom::Point3d.new(x2, y1, 0),
            Geom::Point3d.new(x2, y2, 0),
            Geom::Point3d.new(x1, y2, 0)
          ]
          MH::OverlayEngine.rect(view, x1, y1, x2 - x1, y2 - y1, Sketchup::Color.new(100, 100, 255, 50), pts)
          MH::OverlayEngine.rect_outline(view, x1, y1, x2 - x1, y2 - y1, Sketchup::Color.new(100, 100, 255, 255), pts)
        end
      end

      def draw_zones(view)
        @zones.each do |zone|
          pts = zone.corners
          is_sel = (@selected_zones.include?(zone) || @hovered_zone == zone || @merge_source == zone)
          is_modul = zone.zone_type == :modul

          base_idx = zone.id % ZONE_COLORS.length
          fill = is_sel ? ZONE_SEL_COLOR : (is_modul ? MODUL_COLOR : ZONE_COLORS[base_idx])
          edge = is_sel ? ZONE_SEL_EDGE : (is_modul ? MODUL_EDGE_COLOR : ZONE_EDGE_COLORS[base_idx])

          view.drawing_color = fill
          view.draw(GL_QUADS, [pts[0], pts[1], pts[2], pts[3]])
          view.draw(GL_QUADS, [pts[4], pts[5], pts[6], pts[7]])
          view.draw(GL_QUADS, [pts[0], pts[1], pts[5], pts[4]])
          view.draw(GL_QUADS, [pts[3], pts[2], pts[6], pts[7]])
          view.draw(GL_QUADS, [pts[0], pts[3], pts[7], pts[4]])
          view.draw(GL_QUADS, [pts[1], pts[2], pts[6], pts[5]])

          view.line_width = is_sel ? 3 : 2
          view.line_stipple = ''
          view.drawing_color = edge
          EDGES.each do |a, b|
            view.draw(GL_LINES, [pts[a], pts[b]])
          end
        end
      end

      def draw_labels(view)
        @zones.each do |zone|
          next if zone.label.empty?
          center = zone.center
          top_pt = Geom::Point3d.new(center.x, center.y, zone.bounds[1].z)
          screen = view.screen_coords(top_pt)

          text = zone.label
          text += " (#{zone.entities.length})" if zone.entities.length > 0

          tw = text.length * 8 + 16
          th = 22
          sx = screen.x - tw / 2
          sy = screen.y - th - 4

          bg_pts = [
            Geom::Point3d.new(sx, sy, 0),
            Geom::Point3d.new(sx + tw, sy, 0),
            Geom::Point3d.new(sx + tw, sy + th, 0),
            Geom::Point3d.new(sx, sy + th, 0)
          ]
          MH::OverlayEngine.rect(view, sx, sy, tw, th, LABEL_BG, bg_pts)

          MH::OverlayEngine.text(view, screen.x, sy + 4, text, size: 14, bold: true, color: LABEL_COLOR, align: 1)
        end
      end

      def draw_split_preview(view)
        zone = @hovered_zone
        return unless zone

        axis = SPLIT_AXES[@split_axis]
        pos  = @split_preview_pos

        if @split_all && !@zones.empty?
          mn_x = @zones.map { |z| z.bounds[0].x }.min
          mn_y = @zones.map { |z| z.bounds[0].y }.min
          mn_z = @zones.map { |z| z.bounds[0].z }.min
          mx_x = @zones.map { |z| z.bounds[1].x }.max
          mx_y = @zones.map { |z| z.bounds[1].y }.max
          mx_z = @zones.map { |z| z.bounds[1].z }.max
          mn = Geom::Point3d.new(mn_x, mn_y, mn_z)
          mx = Geom::Point3d.new(mx_x, mx_y, mx_z)
        else
          mn, mx = zone.bounds
        end

        # Mở rộng 20mm để dễ nhìn
        pad = 20.0 / 25.4
        mn = Geom::Point3d.new(mn.x - pad, mn.y - pad, mn.z - pad)
        mx = Geom::Point3d.new(mx.x + pad, mx.y + pad, mx.z + pad)

        pts = split_plane_pts(mn, mx, axis, pos)
        return unless pts

        view.drawing_color = SPLIT_PREVIEW
        view.draw(GL_QUADS, pts)
        view.line_width = 3
        view.drawing_color = SPLIT_COLOR
        view.draw(GL_LINE_LOOP, pts)
      end

      # ── FIX: dùng <= và >= thay vì < và > để không bị nil khi pos nằm đúng biên ──
      def split_plane_pts(mn, mx, axis, pos)
        case axis
        when :z
          return nil if pos < mn.z || pos > mx.z
          [Geom::Point3d.new(mn.x, mn.y, pos), Geom::Point3d.new(mx.x, mn.y, pos),
           Geom::Point3d.new(mx.x, mx.y, pos), Geom::Point3d.new(mn.x, mx.y, pos)]
        when :x
          return nil if pos < mn.x || pos > mx.x
          [Geom::Point3d.new(pos, mn.y, mn.z), Geom::Point3d.new(pos, mx.y, mn.z),
           Geom::Point3d.new(pos, mx.y, mx.z), Geom::Point3d.new(pos, mn.y, mx.z)]
        when :y
          return nil if pos < mn.y || pos > mx.y
          [Geom::Point3d.new(mn.x, pos, mn.z), Geom::Point3d.new(mx.x, pos, mn.z),
           Geom::Point3d.new(mx.x, pos, mx.z), Geom::Point3d.new(mn.x, pos, mx.z)]
        end
      end

      # ── FIX: tính vị trí cắt trực tiếp từ ray, không snap vào entity bounds ──
      #
      # Logic:
      #   1. Bắn ray từ camera qua pixel (x,y)
      #   2. Giao ray với 6 mặt của bounding box zone
      #   3. Lấy điểm giao gần nhất nằm trong bounds → đó là vị trí chuột trên bề mặt zone
      #   4. Trả về toạ độ theo axis tương ứng
      #   5. Fallback về mặt phẳng đi qua tâm zone nếu ray không trúng mặt nào
      def get_split_pos(zone, axis, ray, ip)
        origin, dir = ray
        mn, mx = zone.bounds
        
        axis_idx = [:x, :y, :z].index(axis)
        mn_val = [mn.x, mn.y, mn.z][axis_idx]
        mx_val = [mx.x, mx.y, mx.z][axis_idx]

        # 1. Ưu tiên bắt điểm (Vertex hoặc Edge) từ SketchUp InputPoint
        if ip && ip.valid? && ip.degrees_of_freedom < 2
          return ip.position.send(axis).clamp(mn_val, mx_val)
        end

        # 2. Tìm giao điểm của ray với 6 mặt AABB của zone (Ray-AABB intersection)
        t_best = Float::INFINITY
        best_pos = nil

        # Mỗi mặt: [normal, d_min_or_max, axis_clamped_1, range_1, axis_clamped_2, range_2]
        faces = [
          # Mặt X
          { n: 0, pos_on_axis: mn.x, c1: 1, r1: [mn.y, mx.y], c2: 2, r2: [mn.z, mx.z] },
          { n: 0, pos_on_axis: mx.x, c1: 1, r1: [mn.y, mx.y], c2: 2, r2: [mn.z, mx.z] },
          # Mặt Y
          { n: 1, pos_on_axis: mn.y, c1: 0, r1: [mn.x, mx.x], c2: 2, r2: [mn.z, mx.z] },
          { n: 1, pos_on_axis: mx.y, c1: 0, r1: [mn.x, mx.x], c2: 2, r2: [mn.z, mx.z] },
          # Mặt Z
          { n: 2, pos_on_axis: mn.z, c1: 0, r1: [mn.x, mx.x], c2: 1, r2: [mn.y, mx.y] },
          { n: 2, pos_on_axis: mx.z, c1: 0, r1: [mn.x, mx.x], c2: 1, r2: [mn.y, mx.y] },
        ]

        axes_methods = [:x, :y, :z]
        dir_components = [dir.x, dir.y, dir.z]
        origin_components = [origin.x, origin.y, origin.z]

        faces.each do |face|
          n      = face[:n]
          d_comp = dir_components[n]
          next if d_comp.abs < 1e-10   # Ray song song với mặt này

          t = (face[:pos_on_axis] - origin_components[n]) / d_comp
          next if t < 0                # Giao điểm phía sau camera

          # Toạ độ giao điểm trên 2 trục còn lại
          c1_val = origin_components[face[:c1]] + t * dir_components[face[:c1]]
          c2_val = origin_components[face[:c2]] + t * dir_components[face[:c2]]

          # Kiểm tra có nằm trong bounds của mặt không
          if c1_val >= face[:r1][0] - 1e-6 && c1_val <= face[:r1][1] + 1e-6 &&
             c2_val >= face[:r2][0] - 1e-6 && c2_val <= face[:r2][1] + 1e-6
            if t < t_best
              t_best = t
              # Tính toạ độ đầy đủ của điểm giao
              pt = [
                origin.x + t * dir.x,
                origin.y + t * dir.y,
                origin.z + t * dir.z
              ]
              best_pos = pt[[:x,:y,:z].index(axis)]
            end
          end
        end

        if best_pos
          return best_pos.clamp(mn_val, mx_val)
        end

        # Fallback: giao với mặt phẳng đi qua tâm zone, vuông góc với trục nhìn được nhất
        center = zone.center
        center_components = [center.x, center.y, center.z]
        
        # Dùng mặt phẳng đi qua tâm zone, pháp tuyến là trục cắt
        d_comp = dir_components[axis_idx]
        if d_comp.abs > 1e-10
          t = (center_components[axis_idx] - origin_components[axis_idx]) / d_comp
          if t > 0
            pt_on_axis = origin_components[axis_idx] + t * d_comp
            return pt_on_axis.clamp(mn_val, mx_val)
          end
        end

        # Last resort: trả về tâm zone
        center_components[axis_idx]
      end

      # ── Input handling ──────────────────────────────────
      def onMouseMove(flags, x, y, view)
        @mouse_x = x
        @mouse_y = y

        if @drag_start
          @drag_current = [x, y]
          view.invalidate
        elsif @mode == :select
          @hovered_zone = pick_zone(x, y, view)
          view.invalidate
        elsif @mode == :split
          @ip.pick(view, x, y)
          @hovered_zone = pick_zone(x, y, view)
          if @hovered_zone && @selected_zones.empty?
            axis = SPLIT_AXES[@split_axis]
            ray  = view.pickray(x, y)
            @split_preview_pos = get_split_pos(@hovered_zone, axis, ray, @ip)
          else
            @split_preview_pos = nil
          end
          view.invalidate
        elsif @mode == :merge_target
          @hovered_zone = pick_zone(x, y, view)
          view.invalidate
        end
      end

      def onLButtonDown(flags, x, y, view)
        if @mode == :select
          @drag_start = [x, y]
          @drag_current = [x, y]
          @selected_zones.clear
          view.invalidate
        elsif @mode == :split
          if @hovered_zone && @split_preview_pos && @selected_zones.empty?
            if @split_all
              split_all_zones(SPLIT_AXES[@split_axis], @split_preview_pos)
            else
              split_zone_immediately(@hovered_zone, SPLIT_AXES[@split_axis], @split_preview_pos)
            end
            view.invalidate
          end
        elsif @mode == :merge_target
          target = pick_zone(x, y, view)
          if target && target != @merge_source
            merged_ents = @merge_source.entities + target.entities
            new_zone = MH::FastRename.create_zone(@merge_source.id, merged_ents)
            new_zone.label = @merge_source.label
            new_zone.zone_type = @merge_source.zone_type
            new_zone.parent_id = @merge_source.parent_id

            @zones.delete(@merge_source)
            @zones.delete(target)
            @zones << new_zone
            @zones = MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num)

            @mode = :select
            @merge_source = nil
            update_status
            view.invalidate
          end
        end
      end

      def onLButtonUp(flags, x, y, view)
        if @drag_start
          x1 = [@drag_start[0], @drag_current[0]].min
          x2 = [@drag_start[0], @drag_current[0]].max
          y1 = [@drag_start[1], @drag_current[1]].min
          y2 = [@drag_start[1], @drag_current[1]].max

          if x2 - x1 > 5 || y2 - y1 > 5
            @selected_zones = @zones.select do |zone|
              sc = view.screen_coords(zone.center)
              sc.x >= x1 && sc.x <= x2 && sc.y >= y1 && sc.y <= y2
            end
          else
            @selected_zones.clear
          end

          @drag_start = nil
          @drag_current = nil
          view.invalidate
        end
      end

      def getMenu(menu, flags, x, y, view)
        if @mode == :split
          menu.add_item("Tắt chế độ Cắt khối (Phím C)") {
            @mode = :select
            @split_preview_pos = nil
            update_status
            view.invalidate
          }
          return true
        end

        if @mode == :select
          menu.add_item("Bật chế độ Cắt khối (Phím C)") {
            @mode = :split
            @selected_zones.clear
            update_status
            view.invalidate
          }
          menu.add_separator

          if @selected_zones.length > 1
            menu.add_item("Gộp #{@selected_zones.length} khối đã chọn") {
              first = @selected_zones.first
              others = @selected_zones[1..-1]
              merged_ents = first.entities.clone
              others.each { |o| merged_ents.concat(o.entities); @zones.delete(o) }

              new_zone = MH::FastRename.create_zone(first.id, merged_ents)
              new_zone.label = first.label
              new_zone.zone_type = first.zone_type
              new_zone.parent_id = first.parent_id

              @zones.delete(first)
              @zones << new_zone
              @zones = MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num)
              @selected_zones.clear
              view.invalidate
            }
            menu.add_item("Chuyển #{@selected_zones.length} khối thành Modul...") {
              default_sp = MH::FastRename.product_base_label(@selected_zones.first.label)
              default_sp = MH::FastRename.format_product_code(1) if default_sp.to_s.empty?
              res = UI.inputbox(["Mã SP gốc:"], [default_sp], "Tạo Modul hàng loạt")
              if res
                parent_sp = res[0].to_s.strip
                sorted_sel = @selected_zones.sort_by { |z| [z.center.x.round(0), z.center.y.round(0)] }
                sorted_sel.each_with_index do |z, i|
                  z.zone_type = :modul
                  z.label = "#{parent_sp}.#{i + 1}"
                  parent_zone = @zones.find { |pz| pz.zone_type == :sp && pz.label == parent_sp }
                  z.parent_id = parent_zone.id if parent_zone
                end
                renumber_zones
                @selected_zones.clear
                view.invalidate
              end
            }
            menu.add_separator
          end

          zone = pick_zone(x, y, view)
          if zone
            menu.add_item("Gán mã SP...") {
              zone.zone_type = :sp
              res = UI.inputbox(["Mã SP:"], [zone.label], "Gán mã SP")
              if res
                zone.label = res[0].to_s.strip
                renumber_zones
                view.invalidate
              end
            }
            menu.add_item("Gán mã Modul...") {
              zone.zone_type = :modul
              parent = @zones.find { |z| z.zone_type == :sp && z.id == zone.parent_id }
              parent_label = parent ? parent.label : MH::FastRename.format_product_code(1)
              res = UI.inputbox(["Mã Modul:"], [zone.label.empty? ? "#{parent_label}.1" : zone.label], "Gán mã Modul")
              if res
                zone.label = res[0].to_s.strip
                renumber_zones
                view.invalidate
              end
            }
            menu.add_separator
            menu.add_item("Gộp với khối khác...") {
              @mode = :merge_target
              @merge_source = zone
              @selected_zones.clear
              update_status
              view.invalidate
            }
          end

          menu.add_separator
          menu.add_item("Chọn số SP bắt đầu...") {
            res = UI.inputbox(["Số bắt đầu:"], [@sp_start_num], "Cài đặt")
            if res
              @sp_start_num = res[0].to_i
              @sp_start_num = 1 if @sp_start_num < 1
              @zones = MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num)
              view.invalidate
            end
          }
          menu.add_item("Khoảng cách gộp khối (mm)...") {
            res = UI.inputbox(["Khoảng cách tối đa (mm):"], [@gap_threshold_mm], "Tự động gộp khối")
            if res && res[0].to_f > 0
              @gap_threshold_mm = res[0].to_f
              recluster_all
              view.invalidate
            end
          }
        elsif @mode == :merge_target
          menu.add_item("Hủy lệnh Gộp") {
            @mode = :select
            @merge_source = nil
            update_status
            view.invalidate
          }
        end
        true
      end

      def onKeyDown(key, repeat, flags, view)
        case key
        when 67 # 'C'
          if @mode == :select
            @mode = :split
            @selected_zones.clear
            update_status
            view.invalidate
            return true
          elsif @mode == :split
            @mode = :select
            @split_preview_pos = nil
            update_status
            view.invalidate
            return true
          end
        when COPY_MODIFIER_KEY, 17 # Ctrl
          if @mode == :split
            @split_all = !@split_all
            update_status
            view.invalidate
            return true
          end
        when 9 # Tab
          if @mode == :split
            @split_axis = (@split_axis + 1) % SPLIT_AXES.length
            update_status
            view.invalidate
            return true
          end
        when 38 # VK_UP
          if @mode == :select && @selected_zones.length == 1
            move_zone_label(@selected_zones.first, 1)
            view.invalidate
            return true
          end
        when 40 # VK_DOWN
          if @mode == :select && @selected_zones.length == 1
            move_zone_label(@selected_zones.first, -1)
            view.invalidate
            return true
          end
        when 13 # Enter
          if @mode == :select || @mode == :split
            apply_rename
            @model.select_tool(nil)
            return true
          end
        when 27 # Escape
          if @mode == :split
            @mode = :select
            @split_preview_pos = nil
            update_status
            view.invalidate
            return true
          elsif @mode != :select
            @mode = :select
            @merge_source = nil
            update_status
            view.invalidate
            return true
          else
            @model.select_tool(nil)
            return true
          end
        end
        false
      end

      def onKeyUp(key, repeat, flags, view)
        false
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @zones.each do |z|
          z.corners.each { |p| bb.add(p) }
        end
        bb
      end

      # ── Zone picking ────────────────────────────────────
      def pick_zone(x, y, view)
        ip = view.inputpoint(x, y)
        pt = ip.position

        best = nil
        best_dist = Float::INFINITY
        @zones.each do |zone|
          mn, mx = zone.bounds
          if pt.x >= mn.x && pt.x <= mx.x &&
             pt.y >= mn.y && pt.y <= mx.y &&
             pt.z >= mn.z && pt.z <= mx.z
            d = pt.distance(zone.center)
            if d < best_dist
              best_dist = d
              best = zone
            end
          end
        end

        unless best
          @zones.each do |zone|
            sc = view.screen_coords(zone.center)
            d = Math.sqrt((sc.x - x)**2 + (sc.y - y)**2)
            if d < 80 && d < best_dist
              best_dist = d
              best = zone
            end
          end
        end
        best
      end

      # ── Zone label operations ───────────────────────────
      def renumber_zones
        @zones = MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num)
      end

      def move_zone_label(zone, direction)
        zone.label_offset ||= 0
        zone.label_offset += direction
        zone.label_offset = 0 if zone.label_offset < 0
        renumber_zones
      end

      # ── Split operations ────────────────────────────────
      def split_zone_immediately(zone, axis, pos)
        new_zones = zone.split(axis, pos)
        if new_zones && new_zones.length > 1
          @zones.delete(zone)
          new_zones.each { |z| z.zone_type = zone.zone_type; z.parent_id = zone.id }
          @zones.concat(new_zones)
          @zones = MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num)
          @hovered_zone = nil
          @split_preview_pos = nil
        else
          UI.beep
          Sketchup.status_text = "Không thể cắt! Khối này không chia làm 2 phần tại đây."
        end
      end

      def split_all_zones(axis, pos)
        new_zones_to_add = []
        zones_to_remove  = []
        split_count = 0

        @zones.each do |z|
          new_zones = z.split(axis, pos)
          if new_zones && new_zones.length > 1
            split_count += 1
            zones_to_remove << z
            new_zones.each { |nz| nz.zone_type = z.zone_type; nz.parent_id = z.id }
            new_zones_to_add.concat(new_zones)
          end
        end

        if split_count > 0
          @zones -= zones_to_remove
          @zones.concat(new_zones_to_add)
          @zones = MH::FastRename.sort_and_label_zones(@zones, MH::FastRename.product_family, @sp_start_num)
          @hovered_zone = nil
          @split_preview_pos = nil
        else
          UI.beep
          Sketchup.status_text = "Không thể cắt! Không có khối nào bị chia tại mặt phẳng này."
        end
      end

      # ── Apply rename to model ───────────────────────────
      def apply_rename
        model = Sketchup.active_model
        model.start_operation('MH Fast Rename', true)

        @zones.each do |zone|
          zone.entities.each do |e|
            next unless e.valid?
            raw_name = e.respond_to?(:name) ? e.name : ''
            clean = raw_name.gsub(/^_+\d+\.?\s*/, '')

            has_prefix = false
            @prefix_suggestions.each do |p|
              if clean.downcase.start_with?(p.downcase)
                sep_match = clean[p.length..-1]&.match(/^[._\s]*/)
                sep  = sep_match ? sep_match[0] : ""
                body = clean[(p.length + sep.length)..-1] || ""
                clean = body
                has_prefix = true
                break
              end
            end

            unless has_prefix
              code = defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product) ? MH::NameGrammar.first_product(clean).to_s : ''
              if !code.empty? && clean.upcase.start_with?(code.upcase)
                clean = clean[code.length..-1].to_s.sub(/\A[._\s]+/, '')
              end
            end

            new_prefix = zone.label
            separator  = new_prefix.empty? ? "" : "_"
            new_name   = clean.empty? ? new_prefix : "#{new_prefix}#{separator}#{clean}"

            sys_match = raw_name.match(/^(_+\d+\.?\s*)/)
            sys = sys_match ? sys_match[1] : ""

            e.name = sys + new_name
          end
        end

        model.commit_operation
        Sketchup.status_text = "Đã đổi tên #{@zones.sum { |z| z.entities.length }} object(s) trong #{@zones.length} zone(s)"
      end

      private

      VK_UP   = 0x26
      VK_DOWN = 0x28
    end

  end
end
