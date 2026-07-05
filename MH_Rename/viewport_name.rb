# encoding: UTF-8
require 'sketchup.rb'
require 'json'
require File.join(__dir__, 'name_parser.rb') unless defined?(MH::Rename::NameParser)

module MH
  module Rename

    PLUGIN_DIR = File.dirname(__FILE__) unless defined?(PLUGIN_DIR)

    class ViewportNameTool
      def self.instance; @@instance rescue nil; end
      FONT_NAME    = "Segoe UI"
      FONT_SIZE    = 10
      CHAR_WIDTH   = 6.5
      LABEL_PAD_X  = 4
      LABEL_PAD_Y  = 3
      LABEL_HEIGHT = FONT_SIZE + LABEL_PAD_Y * 2 + 2
      MAX_TRANSLUCENT_ENTITIES = 100
      MAX_LAYOUT_ITEMS = 350
      LAYOUT_VIEWPORT_MARGIN = 180
      MAX_DIALOG_ROWS = 350

      COL_LABEL_BG       = Sketchup::Color.new(210, 230, 255, 220)
      COL_LABEL_BG_HOVER = Sketchup::Color.new(180, 210, 255, 240)
      COL_LABEL_BORDER   = Sketchup::Color.new(100, 150, 255, 120)
      COL_TEXT            = Sketchup::Color.new(0, 0, 0)
      COL_TEXT_HOVER      = Sketchup::Color.new(40, 100, 220)
      COL_TEXT_SEL        = Sketchup::Color.new(180, 0, 0)
      COL_LEADER          = Sketchup::Color.new(0, 0, 0, 255)
      COL_LEADER_HOVER    = Sketchup::Color.new(0, 0, 0, 255)
      COL_LEADER_SEL      = Sketchup::Color.new(0, 0, 0, 255)
      COL_DOT             = Sketchup::Color.new(255, 0, 0, 255)
      COL_DOT_SEL         = Sketchup::Color.new(255, 0, 0, 255)
      COL_GROUP_BOX       = Sketchup::Color.new(60, 140, 255, 36)
      COL_GROUP_BOX_HOVER = Sketchup::Color.new(255, 170, 40, 52)
      COL_GROUP_EDGE      = Sketchup::Color.new(40, 90, 170, 220)
      COL_GROUP_EDGE_HOVER = Sketchup::Color.new(220, 130, 30, 255)
      MODULE_COLOR_RGB = [
        [255, 80, 80], [65, 145, 255], [60, 190, 115], [255, 185, 55],
        [180, 105, 255], [35, 195, 210], [255, 125, 55], [145, 175, 55],
        [235, 80, 170], [80, 210, 150]
      ].freeze
      MODULE_FILL_ALPHA = 205
      MODULE_FILL_HOVER_ALPHA = 235
      MODULE_EDGE_ALPHA = 255
      GROUP_BOX_PAD = 0.8 / 25.4
      BOX_EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].freeze
      BOX_FACES = [[0,1,2,3],[4,5,6,7],[0,1,5,4],[3,2,6,7],[0,3,7,4],[1,2,6,5]].freeze

      # Pre-allocate reusable color objects to avoid GC pressure
      COL_TRANSLUCENT_GRAY = Sketchup::Color.new(128, 128, 128, 26)
      COL_SEL_FACE         = Sketchup::Color.new(120, 70, 40, 130)
      COL_SEL_EDGE_HIDDEN  = Sketchup::Color.new(0, 0, 0, 150)
      COL_WHITE_LABEL      = Sketchup::Color.new(255, 255, 255, 220)

      # Circle points lookup table (precomputed, avoids Math trig every frame)
      CIRCLE_PTS_SMALL = 8.times.map { |i| a = i * Math::PI / 4.0; [Math.cos(a) * 1.25, Math.sin(a) * 1.25] }.freeze
      CIRCLE_PTS_LARGE = 8.times.map { |i| a = i * Math::PI / 4.0; [Math.cos(a) * 1.75, Math.sin(a) * 1.75] }.freeze

      def ensure_settings_facade
        return true if defined?(MH::Settings)
        path = File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
        load path if File.exist?(path)
        defined?(MH::Settings)
      rescue => e
        MH::Rename.dbg "[ViewportNameTool] settings facade error: #{e.message}" if MH::Rename.respond_to?(:dbg)
        false
      end

      def viewport_setting(key, fallback)
        return fallback unless ensure_settings_facade
        MH::Settings.read('viewport_names', key.to_s, fallback, scope: :global)
      rescue
        fallback
      end

      def bool_setting(key, fallback)
        value = viewport_setting(key, fallback)
        return value if value == true || value == false
        text = value.to_s.strip.downcase
        return true if %w[true 1 yes on].include?(text)
        return false if %w[false 0 no off].include?(text)
        fallback
      end

      def load_control_panel_settings
        @line_spacing = viewport_setting('line_spacing', 28).to_i
        @text_gap = viewport_setting('text_gap', 150).to_i
        @text_display_mode = viewport_setting('text_display_mode', 'all').to_s.to_sym
        @show_hidden_lines = bool_setting('show_hidden_lines', true)
        @label_style = viewport_setting('label_style', 'leader').to_s.to_sym
        @show_part_id = bool_setting('show_part_id', true)
        @show_part_prefix = bool_setting('show_part_prefix', true)
        @show_part_suffix = bool_setting('show_part_suffix', true)
        @show_label_bg = bool_setting('show_label_bg', false)
        @hidden_layers = Array(viewport_setting('hidden_layers', [])).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def initialize
        @@instance = self
        @entities = []
        load_control_panel_settings
        @hover_index = nil
        @drill_hover_key = nil
        @selected_indices = []
        @label_rects = []
        @drill_label_rects = []
        @entity_names = {}
        @entity_index_by_id = {}
        @original_transparency = nil
        @dialog = nil
        @view_mode = :products # :products -> :modules -> :suffix
        @product_groups = []
        @module_groups = []
        @active_product = nil
        @active_module = nil
        @active_module_entity_ids = {}
        @product_index_by_eid = {}
        @module_index_by_eid = {}
        @hidden_by_drill_isolate = []

        # === PERFORMANCE CACHES ===
        @triangle_cache = {}      # entityID => flat array of 3D pts (for GL_TRIANGLES)
        @edge_3d_cache = {}       # entityID => flat array of 3D pts (for GL_LINES)
        @module_overlay_cache = {}
        @name_width_cache = {}    # name string => pixel width
        @display_name_cache = {}  # cache formatted display text
        @layout_cache = nil       # cached layout result
        @layout_cache_key = nil   # key: [vpw, vph, camera_eye, selected, hover, entities_sig]
        @names_version = 0
        @translucent_pts_all = [] # flat pts for non-selected translucent batch
        @translucent_dirty = true
        @sel_faces_dirty = true
        @sel_face_pts_cache = {}  # entityID => screen pts array (2D)
        @sel_edge_3d_cache = {}   # entityID => 3D edge pts
        @dialog_update_pending = false

        @initial_scope = []
        @original_layer_visibility = {}

        # === RENAME SHORTCUT (ch?y ng?m) ===
        @sc_buffer = ""
        @sc_timer = nil
        @sc_last_result = nil
      end

      def reload_config
        load_control_panel_settings
        invalidate_all_caches
        refresh_name_cache
        rebuild_drilldown_groups
        reset_drilldown_to_products
        update_drilldown_status_text
        Sketchup.active_model.active_view.invalidate
        schedule_dialog_update
      end

      def activate
        model = Sketchup.active_model
        
        has_selection = !model.selection.empty?
        @initial_scope = has_selection ? model.selection.to_a.dup : model.active_entities.to_a.dup

        @original_layer_visibility = {}
        model.layers.each { |l| @original_layer_visibility[l.name] = l.visible? }
        apply_hidden_layers(model)
        
        @entities = collect_entities(model)
        if @entities.empty?
          UI.messagebox("Không có Group/Component nào.\nHãy chọn các đối tượng trước.")
          model.select_tool(nil)
          return
        end
        
        @selected_indices.clear
        rebuild_entity_index
        if has_selection
          model.selection.each do |ent|
            idx = @entity_index_by_id[ent.entityID]
            @selected_indices << idx if idx
          end
        end
        
        refresh_name_cache
        rebuild_drilldown_groups
        reset_drilldown_to_products
        enable_xray(model)
        show_controls
        update_drilldown_status_text
        model.active_view.invalidate
      end

      def deactivate(view)
        clear_drill_isolation
        restore_xray(view.model)
        restore_layer_visibility(view.model)
        @dialog.close if @dialog && @dialog.visible?
        @rename_dialog.close if @rename_dialog && @rename_dialog.visible? rescue nil
        view.invalidate
      end

      def apply_hidden_layers(model)
        @hidden_layers.each do |ln|
          layer = model.layers.find { |l| l.name.strip.downcase == ln.strip.downcase }
          layer.visible = false if layer
        end
      end

      def restore_layer_visibility(model)
        return if @original_layer_visibility.empty?
        @original_layer_visibility.each do |name, vis|
          layer = model.layers[name]
          layer.visible = vis if layer
        end
        @original_layer_visibility = {}
      end

      def suspend(view); view.invalidate; end
      def resume(view)
        view.invalidate
        @dialog.bring_to_front if @dialog && @dialog.visible?
      end

      def onSetCursor
        UI.set_cursor((@hover_index || @drill_hover_key) ? 632 : 0)
      end

      def entity_visible?(e)
        return false unless e && e.valid?
        return false if e.hidden?
        return false if e.layer && !e.layer.visible?
        true
      end

      # ===================== DRAW (OPTIMIZED) =====================
      def draw(view)
        return if @entities.empty?

        if @view_mode == :products
          draw_product_mode(view)
          draw_shortcut_hud(view)
          return
        elsif @view_mode == :modules
          draw_module_mode(view)
          draw_shortcut_hud(view)
          return
        end

        # �?m b?o layout cache v� c�c screen-space point cache du?c c?p nh?t
        # TRU?C khi v? d? tr�nh vi?c v? b?ng d? li?u cu g�y ra '?nh ?o' (ghost image)
        get_cached_layout(view)

        # --- 1. Translucent pass (non-selected, batched into one draw call) ---
        if draw_translucent_overlay?
          if @translucent_dirty
            build_translucent_cache
          end
          unless @translucent_pts_all.empty?
            view.drawing_color = COL_TRANSLUCENT_GRAY
            view.draw(GL_TRIANGLES, @translucent_pts_all)
          end
        else
          @translucent_pts_all = []
          @translucent_dirty = false
        end

        # --- 2. Selected entity faces (2D screen-space highlight) ---
        draw_selected_faces(view)

        # --- 3. Selected entity edges ---
        draw_selected_edges(view)

        # --- 4. Labels ---
        draw_labels(view)

        # --- 5. Shortcut HUD (g�c du?i tr�i) ---
        draw_shortcut_hud(view)
      end

      def draw_translucent_overlay?
        @entities.length <= MAX_TRANSLUCENT_ENTITIES
      end

      def draw_shortcut_hud(view)
        shortcut_map = MH::Rename.shortcut_map
        return if shortcut_map.nil? || shortcut_map.empty?

        x = 10
        y = 20  # Góc trên bên trái

        # Hiện trạng thái buffer / kết quả
        if !@sc_buffer.empty?
          MH::OverlayEngine.text(view, x, y, "Đang nhập: #{@sc_buffer}_ ...", color: "Black", size: 12, bold: true)
          y += 18
        elsif @sc_last_result
          MH::OverlayEngine.text(view, x, y, @sc_last_result, color: "Black", size: 11)
          y += 18
        end

        # Danh s�ch shortcut
        shortcut_map.sort_by { |k, _| k.to_i }.each do |k, v|
          MH::OverlayEngine.text(view, x, y, "#{k} => #{v}", color: "Black", size: 10)
          y += 16
        end
      end

      def draw_product_mode(view)
        return if @product_groups.empty?
        draw_drill_labels(view, @product_groups)
      end

      def draw_module_mode(view)
        return if @module_groups.empty?
        draw_module_group_boxes(view, @module_groups)
        draw_drill_labels(view, @module_groups)
      end

      def draw_drill_labels(view, entries)
        @drill_label_rects = []
        drill_layout_entries(entries, view).each do |item|
          draw_drill_item(view, item)
        end
      end

      def drill_layout_entries(entries, view)
        return [] if entries.empty?
        items = []
        entries.each do |entry|
          center = entry[:center]
          next unless center
          screen = view.screen_coords(center)
          next unless screen_point_in_viewport?(screen, view)
          name = entry[:label].to_s
          next if name.empty?
          items << {
            key: entry[:key],
            name: name,
            screen_x: screen.x,
            screen_y: screen.y,
            label_w: calc_text_width(name)
          }
        end
        return [] if items.empty?

        avg_x = items.sum { |i| i[:screen_x] } / items.length.to_f
        left  = items.select { |i| i[:screen_x] <= avg_x }.sort_by { |i| i[:screen_y] }
        right = items.select { |i| i[:screen_x] > avg_x }.sort_by { |i| i[:screen_y] }

        if left.empty? && !right.empty?
          half = (right.length / 2.0).ceil
          left = right[0...half]
          right = right[half..-1] || []
        elsif right.empty? && !left.empty?
          half = (left.length / 2.0).ceil
          right = left[half..-1] || []
          left = left[0...half]
        end

        row_h = @line_spacing > 0 ? @line_spacing : LABEL_HEIGHT + 4
        gap = @text_gap > 0 ? @text_gap : 150
        vp_w = view.vpwidth

        unless left.empty?
          avg_y_left = left.sum { |i| i[:screen_y] } / left.length.to_f
          left_start_y = avg_y_left - left.length * row_h / 2.0
          left.each_with_index do |item, idx|
            lw = item[:label_w]
            lx = [avg_x - gap - lw, 8].max
            item[:label_x] = lx
            item[:label_y] = left_start_y + idx * row_h
            item[:side] = :left
          end
        end

        unless right.empty?
          avg_y_right = right.sum { |i| i[:screen_y] } / right.length.to_f
          right_start_y = avg_y_right - right.length * row_h / 2.0
          right.each_with_index do |item, idx|
            lw = item[:label_w]
            lx = [avg_x + gap, vp_w - lw - 8].min
            item[:label_x] = lx
            item[:label_y] = right_start_y + idx * row_h
            item[:side] = :right
          end
        end

        left + right
      end

      def draw_drill_item(view, item)
        key = item[:key]
        name = item[:name]
        is_hover = (@drill_hover_key == key)

        lx = item[:label_x]
        ly = item[:label_y]
        lw = item[:label_w]
        lh = LABEL_HEIGHT

        if @show_label_bg
          pts = [[lx, ly, 0], [lx + lw, ly, 0], [lx + lw, ly + lh, 0], [lx, ly + lh, 0]]
          MH::OverlayEngine.rect(view, lx, ly, lw, lh, is_hover ? COL_LABEL_BG_HOVER : COL_LABEL_BG, pts)
          MH::OverlayEngine.rect_outline(view, lx, ly, lw, lh, COL_LABEL_BORDER, pts)
        end

        tc = is_hover ? COL_TEXT_HOVER : COL_TEXT
        MH::OverlayEngine.text(
          view, lx + LABEL_PAD_X, ly + LABEL_PAD_Y,
          name.gsub(/[\r\n]/, ' '),
          font: FONT_NAME, size: FONT_SIZE, color: tc, bold: is_hover
        )

        @drill_label_rects << { x: lx, y: ly, w: lw, h: lh, key: key }

        leader_start, elbow = if item[:side] == :left
          ls = Geom::Point3d.new(lx + lw, ly + lh / 2.0, 0)
          [ls, Geom::Point3d.new(ls.x + 20, ls.y, 0)]
        else
          ls = Geom::Point3d.new(lx, ly + lh / 2.0, 0)
          [ls, Geom::Point3d.new(ls.x - 20, ls.y, 0)]
        end

        entity_scr = Geom::Point3d.new(item[:screen_x], item[:screen_y], 0)
        MH::OverlayEngine.line2d(view, [leader_start, elbow, entity_scr], color: is_hover ? COL_LEADER_HOVER : COL_LEADER, mode: GL_LINE_STRIP, stipple: "", width: is_hover ? 2 : 1)

        tbl = is_hover ? CIRCLE_PTS_LARGE : CIRCLE_PTS_SMALL
        MH::OverlayEngine.polygon2d(view, tbl.map { |dx, dy| Geom::Point3d.new(entity_scr.x + dx, entity_scr.y + dy, 0) }, color: COL_DOT)
      end

      def draw_module_group_boxes(view, groups)
        lightweight = groups.length > 240
        groups.each do |group|
          overlay = cached_module_overlay(group)
          next if overlay[:faces].empty? && overlay[:edges].empty?

          is_hover = (@drill_hover_key == group[:key])
          unless lightweight
            view.drawing_color = module_fill_color(group, is_hover)
            overlay[:faces].each { |face_pts| view.draw(GL_QUADS, face_pts) }
          end

          edge_pts = []
          overlay[:edges].each { |edge| edge.each { |point| edge_pts << view.screen_coords(point) } }
          MH::OverlayEngine.line2d(view, edge_pts, color: module_edge_color(group, is_hover), stipple: "-", width: 1) unless edge_pts.empty?
        end
      rescue => e
        MH::Rename.dbg "MH_Rename module overlay error: #{e.class}: #{e.message}" if MH::Rename.respond_to?(:dbg)
      end

      def module_fill_color(group, hover = false)
        r, g, b = module_rgb(group)
        Sketchup::Color.new(r, g, b, hover ? MODULE_FILL_HOVER_ALPHA : MODULE_FILL_ALPHA)
      end

      def module_edge_color(group, hover = false)
        r, g, b = module_rgb(group)
        factor = hover ? 0.42 : 0.55
        Sketchup::Color.new((r * factor).round, (g * factor).round, (b * factor).round, hover ? 255 : MODULE_EDGE_ALPHA)
      end

      def module_rgb(group)
        idx = group[:color_index].to_i
        MODULE_COLOR_RGB[idx % MODULE_COLOR_RGB.length]
      end

      def bounds_corners(bounds, pad = 0.0)
        return [] unless bounds && bounds.length == 2
        mn, mx = bounds
        return [] unless mn && mx
        minp = Geom::Point3d.new(mn.x - pad, mn.y - pad, mn.z - pad)
        maxp = Geom::Point3d.new(mx.x + pad, mx.y + pad, mx.z + pad)
        [
          Geom::Point3d.new(minp.x, minp.y, minp.z),
          Geom::Point3d.new(maxp.x, minp.y, minp.z),
          Geom::Point3d.new(maxp.x, maxp.y, minp.z),
          Geom::Point3d.new(minp.x, maxp.y, minp.z),
          Geom::Point3d.new(minp.x, minp.y, maxp.z),
          Geom::Point3d.new(maxp.x, minp.y, maxp.z),
          Geom::Point3d.new(maxp.x, maxp.y, maxp.z),
          Geom::Point3d.new(minp.x, maxp.y, maxp.z)
        ]
      rescue
        []
      end

      def cached_module_overlay(group)
        @module_overlay_cache ||= {}
        signature = module_overlay_signature(group)
        cached = @module_overlay_cache[signature]
        return cached if cached

        boxes = module_entity_boxes(group)
        face_records = outer_envelope_face_records(boxes)
        faces = face_records.map { |rec| rec[:points] }.compact
        edges = union_face_outline_edges(face_records)
        edges = outer_boundary_edges(edges, boxes) if edges.length > 12
        edges = simple_module_edges(group) if edges.empty? && !boxes.empty?

        @module_overlay_cache.clear if @module_overlay_cache.length > 300
        @module_overlay_cache[signature] = { faces: faces, edges: edges }
      end

      def module_overlay_signature(group)
        entity_ids = (group[:entities] || []).select { |entity|
          entity.respond_to?(:valid?) && entity.valid?
        }.map { |entity| entity.respond_to?(:entityID) ? entity.entityID : entity.object_id }.sort
        [group[:key], entity_ids]
      end

      def module_entity_boxes(group)
        drawn = {}
        boxes = []
        (group[:entities] || []).each do |entity|
          next unless entity.respond_to?(:valid?) && entity.valid?
          key = entity.entityID rescue entity.object_id
          next if drawn[key]
          drawn[key] = true
          boxes << padded_bounds_points(effective_bounds_for_overlay(entity), GROUP_BOX_PAD)
        end
        boxes
      end

      def effective_bounds_for_overlay(entity)
        if defined?(MH::FastRename) && MH::FastRename.respond_to?(:effective_entity_bounds)
          MH::FastRename.effective_entity_bounds(entity)
        else
          [entity.bounds.min, entity.bounds.max]
        end
      rescue
        [entity.bounds.min, entity.bounds.max]
      end

      def padded_bounds_points(bounds, pad)
        mn, mx = bounds
        [
          Geom::Point3d.new(mn.x - pad, mn.y - pad, mn.z - pad),
          Geom::Point3d.new(mx.x + pad, mx.y + pad, mx.z + pad)
        ]
      end

      def simple_module_edges(group)
        corners = bounds_corners(group[:bounds], GROUP_BOX_PAD)
        return [] if corners.empty?
        BOX_EDGES.map { |a, b| [corners[a], corners[b]] }
      end

      def outer_envelope_face_records(boxes)
        return [] if boxes.empty?

        records = []
        [:x, :y, :z].each do |axis|
          axis_records = axis_outer_envelope_records(boxes, axis)
          return simple_box_face_records(boxes) if axis_records == :too_many_cells
          records.concat(axis_records)
        end
        records
      end

      def axis_outer_envelope_records(boxes, axis)
        specs = boxes.map { |box| box_axis_projection(box, axis) }.select { |spec|
          (spec[:u1] - spec[:u0]).abs > 1e-8 &&
            (spec[:v1] - spec[:v0]).abs > 1e-8 &&
            (spec[:c1] - spec[:c0]).abs > 1e-8
        }
        return [] if specs.empty?

        u_values = specs.flat_map { |spec| [rounded_coord(spec[:u0]), rounded_coord(spec[:u1])] }.uniq.sort
        v_values = specs.flat_map { |spec| [rounded_coord(spec[:v0]), rounded_coord(spec[:v1])] }.uniq.sort
        return [] if u_values.length < 2 || v_values.length < 2

        cell_count = (u_values.length - 1) * (v_values.length - 1)
        return :too_many_cells if cell_count > 250_000

        u_idx = {}
        v_idx = {}
        u_values.each_with_index { |value, idx| u_idx[value] = idx }
        v_values.each_with_index { |value, idx| v_idx[value] = idx }
        min_cells = {}
        max_cells = {}

        specs.each do |spec|
          u0 = rounded_coord(spec[:u0])
          u1 = rounded_coord(spec[:u1])
          v0 = rounded_coord(spec[:v0])
          v1 = rounded_coord(spec[:v1])
          c0 = rounded_coord(spec[:c0])
          c1 = rounded_coord(spec[:c1])
          (u_idx[u0]...u_idx[u1]).each do |ui|
            (v_idx[v0]...v_idx[v1]).each do |vi|
              key = [ui, vi]
              min_cells[key] = c0 if !min_cells.key?(key) || c0 < min_cells[key]
              max_cells[key] = c1 if !max_cells.key?(key) || c1 > max_cells[key]
            end
          end
        end

        records = []
        [min_cells, max_cells].each do |cells|
          cell_records = cells.map { |(ui, vi), coord|
            envelope_face_record(axis, coord, u_values[ui], u_values[ui + 1], v_values[vi], v_values[vi + 1])
          }
          records.concat(merge_face_records(cell_records))
        end
        records
      end

      def box_axis_projection(box, axis)
        mn, mx = box
        case axis
        when :z
          { c0: mn.z, c1: mx.z, u0: mn.x, u1: mx.x, v0: mn.y, v1: mx.y }
        when :y
          { c0: mn.y, c1: mx.y, u0: mn.x, u1: mx.x, v0: mn.z, v1: mx.z }
        else
          { c0: mn.x, c1: mx.x, u0: mn.y, u1: mx.y, v0: mn.z, v1: mx.z }
        end
      end

      def merge_face_records(records)
        merged = []
        records.group_by { |rec| [rec[:axis], rounded_coord(rec[:coord])] }.each_value do |plane_records|
          strips = []
          plane_records.group_by { |rec| [rounded_coord(rec[:v0]), rounded_coord(rec[:v1])] }.each_value do |row|
            current = nil
            row.sort_by { |rec| [rec[:u0], rec[:u1]] }.each do |rec|
              if current && (current[:u1] - rec[:u0]).abs < 1e-6
                current[:u1] = rec[:u1]
              else
                strips << current if current
                current = rec.dup
              end
            end
            strips << current if current
          end

          strips.group_by { |rec| [rounded_coord(rec[:u0]), rounded_coord(rec[:u1])] }.each_value do |column|
            current = nil
            column.sort_by { |rec| [rec[:v0], rec[:v1]] }.each do |rec|
              if current && (current[:v1] - rec[:v0]).abs < 1e-6
                current[:v1] = rec[:v1]
              else
                merged << refresh_face_record_points(current) if current
                current = rec.dup
              end
            end
            merged << refresh_face_record_points(current) if current
          end
        end
        merged
      end

      def simple_box_face_records(boxes)
        bb = Geom::BoundingBox.new
        boxes.each { |mn, mx| bb.add(mn); bb.add(mx) }
        mn = bb.min
        mx = bb.max
        return [] unless mn && mx

        [
          envelope_face_record(:z, mn.z, mn.x, mx.x, mn.y, mx.y),
          envelope_face_record(:z, mx.z, mn.x, mx.x, mn.y, mx.y),
          envelope_face_record(:y, mn.y, mn.x, mx.x, mn.z, mx.z),
          envelope_face_record(:y, mx.y, mn.x, mx.x, mn.z, mx.z),
          envelope_face_record(:x, mn.x, mn.y, mx.y, mn.z, mx.z),
          envelope_face_record(:x, mx.x, mn.y, mx.y, mn.z, mx.z)
        ]
      end

      def envelope_face_record(axis, coord, u0, u1, v0, v1)
        refresh_face_record_points({
          axis: axis,
          coord: rounded_coord(coord),
          u0: rounded_coord(u0),
          u1: rounded_coord(u1),
          v0: rounded_coord(v0),
          v1: rounded_coord(v1)
        })
      end

      def refresh_face_record_points(rec)
        rec[:points] = face_record_points(rec[:axis], rec[:coord], rec[:u0], rec[:u1], rec[:v0], rec[:v1])
        rec
      end

      def face_record_points(axis, coord, u0, u1, v0, v1)
        case axis
        when :z
          [
            Geom::Point3d.new(u0, v0, coord), Geom::Point3d.new(u1, v0, coord),
            Geom::Point3d.new(u1, v1, coord), Geom::Point3d.new(u0, v1, coord)
          ]
        when :y
          [
            Geom::Point3d.new(u0, coord, v0), Geom::Point3d.new(u1, coord, v0),
            Geom::Point3d.new(u1, coord, v1), Geom::Point3d.new(u0, coord, v1)
          ]
        else
          [
            Geom::Point3d.new(coord, u0, v0), Geom::Point3d.new(coord, u1, v0),
            Geom::Point3d.new(coord, u1, v1), Geom::Point3d.new(coord, u0, v1)
          ]
        end
      end

      def outer_boundary_edges(edges, boxes)
        filtered = edges.select { |edge| outer_boundary_edge?(edge, boxes) }
        filtered.empty? ? edges : filtered
      end

      def outer_boundary_edge?(edge, boxes)
        p1, p2 = edge
        mid = Geom::Point3d.new((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0, (p1.z + p2.z) / 2.0)
        dx = (p1.x - p2.x).abs
        dy = (p1.y - p2.y).abs
        dz = (p1.z - p2.z).abs

        if dx >= dy && dx >= dz
          local_axis_extreme?(:y, mid.y, :x, mid.x, :z, mid.z, boxes)
        elsif dy >= dx && dy >= dz
          local_axis_extreme?(:x, mid.x, :y, mid.y, :z, mid.z, boxes)
        else
          local_axis_extreme?(:x, mid.x, :y, mid.y, :z, mid.z, boxes) ||
            local_axis_extreme?(:y, mid.y, :x, mid.x, :z, mid.z, boxes)
        end
      rescue
        true
      end

      def local_axis_extreme?(axis, value, cover_axis_a, cover_value_a, cover_axis_b, cover_value_b, boxes)
        tol = 0.05 / 25.4
        min_value = nil
        max_value = nil
        boxes.each do |box|
          next unless box_covers_axis_value?(box, cover_axis_a, cover_value_a, tol)
          next unless box_covers_axis_value?(box, cover_axis_b, cover_value_b, tol)
          mn, mx = box_axis_range(box, axis)
          min_value = mn if min_value.nil? || mn < min_value
          max_value = mx if max_value.nil? || mx > max_value
        end
        return false if min_value.nil? || max_value.nil?
        (value - min_value).abs <= tol || (value - max_value).abs <= tol
      end

      def box_covers_axis_value?(box, axis, value, tol)
        mn, mx = box_axis_range(box, axis)
        value >= mn - tol && value <= mx + tol
      end

      def box_axis_range(box, axis)
        mn, mx = box
        case axis
        when :x
          [mn.x, mx.x]
        when :y
          [mn.y, mx.y]
        else
          [mn.z, mx.z]
        end
      end

      def rounded_coord(value)
        value.round(6)
      end

      def union_face_outline_edges(face_records)
        edges = []
        seen = {}
        face_records.group_by { |rec| [rec[:axis], rounded_coord(rec[:coord])] }.each_value do |records|
          records.each do |rec|
            rec[:u0], rec[:u1] = [rounded_coord(rec[:u0]), rounded_coord(rec[:u1])].sort
            rec[:v0], rec[:v1] = [rounded_coord(rec[:v0]), rounded_coord(rec[:v1])].sort
          end
          u_values = records.flat_map { |rec| [rec[:u0], rec[:u1]] }.uniq.sort
          v_values = records.flat_map { |rec| [rec[:v0], rec[:v1]] }.uniq.sort
          next if u_values.length < 2 || v_values.length < 2

          u_idx = {}
          v_idx = {}
          u_values.each_with_index { |value, idx| u_idx[value] = idx }
          v_values.each_with_index { |value, idx| v_idx[value] = idx }
          covered = {}

          records.each do |rec|
            (u_idx[rec[:u0]]...u_idx[rec[:u1]]).each do |ui|
              (v_idx[rec[:v0]]...v_idx[rec[:v1]]).each do |vi|
                covered[[ui, vi]] = true
              end
            end
          end

          raw_segments = []
          covered.each_key do |ui, vi|
            raw_segments << [:h, v_values[vi], u_values[ui], u_values[ui + 1]] unless covered[[ui, vi - 1]]
            raw_segments << [:h, v_values[vi + 1], u_values[ui], u_values[ui + 1]] unless covered[[ui, vi + 1]]
            raw_segments << [:v, u_values[ui], v_values[vi], v_values[vi + 1]] unless covered[[ui - 1, vi]]
            raw_segments << [:v, u_values[ui + 1], v_values[vi], v_values[vi + 1]] unless covered[[ui + 1, vi]]
          end

          merge_outline_segments(raw_segments).each do |seg|
            p1, p2 = segment_to_points(records.first[:axis], records.first[:coord], seg)
            key = edge_signature(p1, p2)
            next if seen[key]
            seen[key] = true
            edges << [p1, p2]
          end
        end
        edges
      end

      def merge_outline_segments(segments)
        merged = []
        segments.group_by { |seg| [seg[0], seg[1]] }.each_value do |group|
          group.sort_by { |seg| seg[2] }.each do |seg|
            if merged.last && merged.last[0] == seg[0] && merged.last[1] == seg[1] &&
               (merged.last[3] - seg[2]).abs < 1e-6
              merged.last[3] = seg[3]
            else
              merged << seg.dup
            end
          end
        end
        merged
      end

      def segment_to_points(axis, coord, segment)
        kind, fixed, a, b = segment
        if kind == :h
          u1 = a
          v1 = fixed
          u2 = b
          v2 = fixed
        else
          u1 = fixed
          v1 = a
          u2 = fixed
          v2 = b
        end
        case axis
        when :z
          [Geom::Point3d.new(u1, v1, coord), Geom::Point3d.new(u2, v2, coord)]
        when :y
          [Geom::Point3d.new(u1, coord, v1), Geom::Point3d.new(u2, coord, v2)]
        else
          [Geom::Point3d.new(coord, u1, v1), Geom::Point3d.new(coord, u2, v2)]
        end
      end

      def edge_signature(p1, p2)
        a = [rounded_coord(p1.x), rounded_coord(p1.y), rounded_coord(p1.z)]
        b = [rounded_coord(p2.x), rounded_coord(p2.y), rounded_coord(p2.z)]
        (a <=> b) == 1 ? [b, a] : [a, b]
      end

      def find_drill_key_at(x, y, view)
        @drill_label_rects.each do |rect|
          if x >= rect[:x] && x <= rect[:x] + rect[:w] && y >= rect[:y] && y <= rect[:y] + rect[:h]
            return rect[:key]
          end
        end

        if @view_mode == :modules
          key = module_key_at_screen_point(x, y, view)
          return key if key
        end

        idx = pick_entity_index_at(x, y, view)
        return nil unless idx
        entity = @entities[idx]
        return nil unless entity

        if @view_mode == :products
          @product_index_by_eid[entity.entityID]
        elsif @view_mode == :modules
          @module_index_by_eid[entity.entityID]
        else
          nil
        end
      end

      def module_key_at_screen_point(x, y, view)
        candidates = []
        @module_groups.each do |group|
          rect = screen_rect_for_bounds(group[:bounds], view, 14)
          next unless rect
          next unless point_in_screen_rect?(x, y, rect)
          center = view.screen_coords(group[:center] || center_from_bounds(group[:bounds]))
          dist = ((center.x - x) ** 2) + ((center.y - y) ** 2)
          area = (rect[:max_x] - rect[:min_x]).abs * (rect[:max_y] - rect[:min_y]).abs
          candidates << [dist, area, group[:key]]
        end
        candidates.sort_by { |dist, area, _| [dist, area] }.first&.last
      rescue
        nil
      end

      def screen_point_inside_group_bounds?(x, y, group, view, margin = 28)
        return false unless group && group[:bounds]
        rect = screen_rect_for_bounds(group[:bounds], view, margin)
        rect && point_in_screen_rect?(x, y, rect)
      rescue
        false
      end

      def screen_rect_for_bounds(bounds, view, margin = 0)
        pts = bounds_corners(bounds, GROUP_BOX_PAD).map { |point| view.screen_coords(point) }
        return nil if pts.empty?
        xs = pts.map(&:x)
        ys = pts.map(&:y)
        {
          min_x: xs.min - margin,
          max_x: xs.max + margin,
          min_y: ys.min - margin,
          max_y: ys.max + margin
        }
      rescue
        nil
      end

      def point_in_screen_rect?(x, y, rect)
        x >= rect[:min_x] && x <= rect[:max_x] &&
          y >= rect[:min_y] && y <= rect[:max_y]
      end

      def pick_entity_index_at(x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        (0...ph.count).each do |pi|
          path = ph.path_at(pi)
          next unless path
          path.reverse.each do |e|
            next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
            idx = @entity_index_by_id[e.entityID]
            return idx if idx && entity_visible?(@entities[idx])
          end
        end
        nil
      rescue
        nil
      end

      # ---- Translucent geometry cache (pre-allocated array) ----
      def build_translucent_cache
        sel_set = @selected_indices
        # Estimate total size to pre-allocate
        total_est = 0
        @entities.each_with_index do |e, idx|
          next unless entity_visible?(e)
          next if sel_set.include?(idx)
          eid = e.entityID
          @triangle_cache[eid] ||= collect_triangles_flat(e)
          total_est += @triangle_cache[eid].length
        end
        @translucent_pts_all = Array.new(total_est)
        pos = 0
        @entities.each_with_index do |e, idx|
          next unless entity_visible?(e)
          next if sel_set.include?(idx)
          pts = @triangle_cache[e.entityID]
          next if pts.empty?
          pts.each { |pt| @translucent_pts_all[pos] = pt; pos += 1 }
        end
        @translucent_pts_all.slice!(pos..-1) if pos < total_est
        @translucent_dirty = false
      end

      # ---- Selected faces (3D direct draw � no screen_coords loop) ----
      def draw_selected_faces(view)
        # X�y d?ng m?ng 3D pts cho t?t c? selected entities (back-face culled)
        @sel_face_pts_cache[:_combined_3d] ||= build_sel_face_pts_3d(view)
        pts = @sel_face_pts_cache[:_combined_3d]
        unless pts.empty?
          view.drawing_color = COL_SEL_FACE
          view.draw(GL_TRIANGLES, pts)
        end
      end

      # Build culled 3D triangle pts cho t?t c? selected (1 l?n duy nh?t m?i khi selection/camera thay d?i)
      def build_sel_face_pts_3d(view)
        eye = view.camera.eye
        result = []
        @selected_indices.each do |idx|
          next if idx >= @entities.length
          e = @entities[idx]
          next unless entity_visible?(e)
          eid = e.entityID
          @triangle_cache_with_normals ||= {}
          @triangle_cache_with_normals[eid] ||= collect_triangles_with_normals(e)
          tris = @triangle_cache_with_normals[eid]
          next if tris.empty?
          tris.each do |tri|
            v = tri[:pt_world] - eye
            if (v % tri[:n_world]) < 0
              result << tri[:pts][0]
              result << tri[:pts][1]
              result << tri[:pts][2]
            end
          end
        end
        result
      end

      # ---- Selected edges ----
      def draw_selected_edges(view)
        all_3d = []
        @selected_indices.each do |idx|
          next if idx >= @entities.length
          e = @entities[idx]
          next unless entity_visible?(e)
          eid = e.entityID
          @edge_3d_cache[eid] ||= collect_edges_flat(e)
          all_3d.concat(@edge_3d_cache[eid])
        end
        return if all_3d.empty?

        if @show_hidden_lines
          all_2d = all_3d.map { |pt| view.screen_coords(pt) }
          MH::OverlayEngine.line2d(view, all_2d, color: COL_SEL_EDGE_HIDDEN, stipple: "-", width: 1)
        end

        profile_w = view.model.rendering_options["SilhouetteWidth"] || 2
        view.line_width = [(profile_w * 3.0).round, 3].max
        view.drawing_color = "black"
        view.line_stipple = ""
        view.draw(GL_LINES, all_3d)
      end

      # ---- Labels ----
      def draw_labels(view)
        layout = get_cached_layout(view)
        @label_rects = []
        layout[:left].each  { |item| draw_item(view, item) }
        layout[:right].each { |item| draw_item(view, item) }
      end

      # ===================== LAYOUT CACHE =====================
      # Layout only recalculates when camera/viewport/selection/entities actually change
      def get_cached_layout(view)
        cam = view.camera
        # Camera key ri�ng � ch? clear sel_face_pts khi camera th?t s? d?i
        cam_key = [
          cam.eye.x.round(1), cam.eye.y.round(1), cam.eye.z.round(1),
          cam.target.x.round(1), cam.target.y.round(1), cam.target.z.round(1)
        ]
        if @last_cam_key != cam_key
          @sel_face_pts_cache.clear
          @last_cam_key = cam_key
        end

        key = [
          view.vpwidth, view.vpheight,
          cam_key,
          @selected_indices.hash,
          @hover_index,
          @text_display_mode,
          @label_style,
          @view_mode,
          (@active_module && @active_module[:key]),
          @entities.length,
          @show_part_id, @show_part_prefix, @show_part_suffix,
          @names_version
        ]
        if @layout_cache_key != key
          @layout_cache = calculate_layout(view)
          @layout_cache_key = key
        end
        @layout_cache
      end

      def onMouseMove(flags, x, y, view)
        if @view_mode == :products || @view_mode == :modules
          old_key = @drill_hover_key
          @drill_hover_key = nil
          @drill_label_rects.each do |rect|
            if x >= rect[:x] && x <= rect[:x] + rect[:w] && y >= rect[:y] && y <= rect[:y] + rect[:h]
              @drill_hover_key = rect[:key]
              break
            end
          end
          @drill_hover_key ||= module_key_at_screen_point(x, y, view) if @view_mode == :modules
          if old_key != @drill_hover_key
            view.invalidate
            if @drill_hover_key
              if @view_mode == :products
                Sketchup.set_status_text("Viewport Name: Click #{@drill_hover_key} để isolate sản phẩm")
              else
                Sketchup.set_status_text("Viewport Name: Click #{@drill_hover_key} để isolate khối")
              end
            else
              update_drilldown_status_text
            end
          end
          return
        end

        old = @hover_index
        @hover_index = find_label_at(x, y)
        if old != @hover_index
          @layout_cache_key = nil  # force layout refresh for hover color change
          view.invalidate
          if @hover_index
            name = @entity_names[@entities[@hover_index]] || "?"
            Sketchup.set_status_text("MH_Rename: [#{name}] -> Click Chọn, Dbl-click Sửa tên")
          else
            update_drilldown_status_text
          end
        end
      end

      def onLButtonDown(flags, x, y, view)
        if @view_mode == :products
          key = find_drill_key_at(x, y, view)
          if key
            enter_product_mode(key, view)
          end
          return
        elsif @view_mode == :modules
          key = find_drill_key_at(x, y, view)
          if key
            enter_suffix_mode(key, view)
          elsif screen_point_inside_group_bounds?(x, y, @active_product, view)
            view.invalidate
          else
            back_to_product_mode(view)
          end
          return
        end

        idx = find_label_at(x, y)
        if idx.nil?
          ph = view.pick_helper
          ph.do_pick(x, y)
          found_idx = nil
          (0...ph.count).each do |pi|
            path = ph.path_at(pi)
            next unless path
            path.reverse.each do |e|
              if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
                i = @entity_index_by_id[e.entityID]
                if i && entity_visible?(@entities[i])
                  found_idx = i
                  break
                end
              end
            end
            break if found_idx
          end
          idx = found_idx
        end
        
        # Ghi nh?n multi-selection tru?c khi b?t k? thay d?i n�o x?y ra
        if @selected_indices.length > 1
          @last_multi_selection = @selected_indices.dup
          @last_multi_time = Time.now.to_f
        end

        if idx.nil?
          if @view_mode == :suffix && @active_product
            back_to_module_mode(view)
            return
          end
          @selected_indices.clear
          view.model.selection.clear
          invalidate_selection_caches
          view.invalidate
          update_control_info
          schedule_dialog_update
          return
        end

        entity = @entities[idx]
        return unless entity_visible?(entity)
        model = view.model
        
        is_shift = (flags & CONSTRAIN_MODIFIER_MASK) != 0
        is_ctrl  = (flags & COPY_MODIFIER_MASK) != 0

        if is_shift || is_ctrl || (flags & 0x04 != 0)
          if @selected_indices.include?(idx)
            @selected_indices.delete(idx)
            model.selection.remove(entity)
          else
            @selected_indices << idx
          end
        else
          @selected_indices = [idx]
          model.selection.clear
        end
        invalidate_selection_caches
        view.invalidate
        update_control_info
      end

      def onLButtonDoubleClick(flags, x, y, view)
        if @view_mode == :products || @view_mode == :modules
          onLButtonDown(flags, x, y, view)
          return
        end

        idx = find_label_at(x, y)
        if idx.nil?
          ph = view.pick_helper
          ph.do_pick(x, y)
          found_idx = nil
          (0...ph.count).each do |pi|
            path = ph.path_at(pi)
            next unless path
            path.reverse.each do |e|
              if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
                i = @entity_index_by_id[e.entityID]
                if i && entity_visible?(@entities[i])
                  found_idx = i
                  break
                end
              end
            end
            break if found_idx
          end
          idx = found_idx
        end
        return unless idx
        
        # Ph?c h?i multi-selection n?u thao t�c double click di?n ra nhanh (< 1.0s)
        # sau khi dang c� nh�m chi ti?t du?c ch?n.
        if @last_multi_selection && @last_multi_selection.include?(idx)
          if @last_multi_time && (Time.now.to_f - @last_multi_time) < 1.0
            @selected_indices = @last_multi_selection.dup
          end
        elsif !@selected_indices.include?(idx)
          # �?m b?o idx du?c ch?n n?u l? b?m nh?m ph�m modifier
          @selected_indices << idx
        end
        
        edit_name(idx, view)
      end

      def onKeyDown(key, repeat, flags, view)
        if key == 27
          if @view_mode == :suffix
            back_to_module_mode(view)
            return true
          elsif @view_mode == :modules
            back_to_product_mode(view)
            return true
          end
          view.model.select_tool(nil)
          return true
        end
        if key == 46 && !@selected_indices.empty?
          delete_selected(view)
          return true
        end
        if key == 115
          hide_selected(view)
          return true
        end
        if key == 88
          if (flags & CONSTRAIN_MODIFIER_MASK) != 0 && (flags & COPY_MODIFIER_MASK) != 0
            unhide_all(view)
          elsif flags == 0
            hide_selected(view)
          end
          return true
        end

        # === RENAME SHORTCUT: ph�m s? 0-9 (key 48-57) ===
        if key >= 48 && key <= 57 && (!@selected_indices.empty? || @hover_index)
          digit = (key - 48).to_s
          return false if digit == "0" && @sc_buffer.empty?
          
          @sc_buffer += digit
          UI.stop_timer(@sc_timer) if @sc_timer
          @sc_timer = UI.start_timer(0.7, false) do
            @sc_timer = nil
            sc_try_apply(view)
          end
          @sc_last_result = "Đang nhập: #{@sc_buffer}_ ..."
          view.invalidate
          return true
        end

        false
      end

      def getMenu(menu)
        menu.add_item("Đóng Viewport Names") { Sketchup.active_model.select_tool(nil) }
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

        if !@selected_indices.empty?
          menu.add_item("Ẩn đối tượng đang chọn (F4)") { hide_selected(Sketchup.active_model.active_view) }
        end
        menu.add_item("Hiện tất cả đối tượng đang ẩn (Ctrl+Shift+X)") { unhide_all(Sketchup.active_model.active_view) }
        menu.add_separator

        menu.add_item("Chọn tất cả") do
          @selected_indices = []
          @entities.each_with_index { |e, i| @selected_indices << i if entity_visible?(e) }
          m = Sketchup.active_model; m.selection.clear
          invalidate_selection_caches; m.active_view.invalidate
        end
        menu.add_item("Bỏ chọn") do
          @selected_indices.clear
          invalidate_selection_caches
          Sketchup.active_model.selection.clear
          Sketchup.active_model.active_view.invalidate
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @entities.each { |e| bb.add(e.bounds) if e.valid? }
        bb
      end

      # === RENAME SHORTCUT: apply logic ===
      def sc_try_apply(view)
        return if @sc_buffer.empty?
        code = @sc_buffer
        @sc_buffer = ""
        
        shortcut_map = MH::Rename.shortcut_map
        suffix = shortcut_map[code]
        
        if suffix.nil?
          @sc_last_result = "Không tìm thấy: #{code}"
          view.invalidate
          return
        end
        
        model = Sketchup.active_model
        
        entities = []
        if !@selected_indices.empty?
          entities = @selected_indices.map { |i| @entities[i] }.compact.select { |e| e.valid? && entity_visible?(e) }
        elsif @hover_index
          e = @entities[@hover_index]
          entities = [e] if e && e.valid? && entity_visible?(e)
        end
        
        if entities.empty?
          @sc_last_result = "Chưa chọn/chỉ vào obj"
          view.invalidate
          return
        end
        
        result = MH::Rename.apply_shortcut_suffix(entities, suffix)
        
        @sc_last_result = "[#{code}] #{suffix} (#{result[:renamed]} obj)"
        refresh_name_cache
        rebuild_drilldown_groups
        reset_drilldown_to_products
        invalidate_all_caches
        schedule_dialog_update
        update_drilldown_status_text
        view.invalidate
      end

      private

      # ===================== CACHE INVALIDATION =====================
      def invalidate_all_caches
        @triangle_cache.clear
        @triangle_cache_with_normals ||= {}
        @triangle_cache_with_normals.clear
        @edge_3d_cache.clear
        @module_overlay_cache ||= {}
        @module_overlay_cache.clear
        @translucent_dirty = true
        @sel_face_pts_cache.clear
        @layout_cache_key = nil
        @name_width_cache.clear
        @display_name_cache ||= {}
        @display_name_cache.clear
        @parse_name_cache ||= {}
        @parse_name_cache.clear
      end

      def invalidate_selection_caches
        @translucent_dirty = true
        @sel_face_pts_cache.clear
        # GI? L?I @triangle_cache_with_normals � geometry 3D l� b?t bi?n khi entity kh�ng d?i
        # Ch? clear screen-space / combined cache
        @layout_cache_key = nil
      end

      # ===================== GEOMETRY COLLECTORS (flat arrays = faster GL) =====================

      # Returns flat array of Geom::Point3d for GL_TRIANGLES (no normals needed for translucent)
      def collect_triangles_flat(entity)
        pts = []
        tr = entity.transformation
        ents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        collect_faces_flat_recursive(ents, tr, pts)
        pts
      end

      def collect_faces_flat_recursive(entities, parent_tr, result)
        entities.each do |e|
          next if e.hidden? || (e.layer && !e.layer.visible?)
          if e.is_a?(Sketchup::Face)
            mesh = e.mesh
            (1..mesh.count_polygons).each do |pi|
              pts = mesh.polygon_points_at(pi)
              next unless pts && pts.length >= 3
              result << pts[0].transform(parent_tr)
              result << pts[1].transform(parent_tr)
              result << pts[2].transform(parent_tr)
            end
          elsif e.is_a?(Sketchup::Group)
            collect_faces_flat_recursive(e.entities, parent_tr * e.transformation, result)
          elsif e.is_a?(Sketchup::ComponentInstance)
            collect_faces_flat_recursive(e.definition.entities, parent_tr * e.transformation, result)
          end
        end
      end

      # Returns array of {pts, n_world, pt_world} hashes (needed for back-face culling on selected)
      def collect_triangles_with_normals(entity)
        triangles = []
        tr = entity.transformation
        ents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        collect_faces_with_normals_recursive(ents, tr, triangles, tr_flipped?(tr))
        triangles
      end

      def collect_faces_with_normals_recursive(entities, parent_tr, result, flipped)
        entities.each do |e|
          next if e.hidden? || (e.layer && !e.layer.visible?)
          if e.is_a?(Sketchup::Face)
            mesh = e.mesh
            n_world = e.normal.transform(parent_tr)
            n_world.normalize!
            n_world = n_world.reverse if flipped
            pt_world = e.vertices.first.position.transform(parent_tr)
            (1..mesh.count_polygons).each do |pi|
              pts = mesh.polygon_points_at(pi)
              next unless pts && pts.length >= 3
              tpts = [pts[0].transform(parent_tr), pts[1].transform(parent_tr), pts[2].transform(parent_tr)]
              result << { pts: tpts, n_world: n_world, pt_world: pt_world }
            end
          elsif e.is_a?(Sketchup::Group)
            child_flipped = flipped ^ tr_flipped?(e.transformation)
            collect_faces_with_normals_recursive(e.entities, parent_tr * e.transformation, result, child_flipped)
          elsif e.is_a?(Sketchup::ComponentInstance)
            child_flipped = flipped ^ tr_flipped?(e.transformation)
            collect_faces_with_normals_recursive(e.definition.entities, parent_tr * e.transformation, result, child_flipped)
          end
        end
      end

      # Returns flat array of Geom::Point3d for GL_LINES
      def collect_edges_flat(entity)
        pts = []
        ents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        collect_edges_flat_recursive(ents, entity.transformation, pts)
        pts
      end

      def collect_edges_flat_recursive(entities, parent_tr, result)
        entities.each do |e|
          next if e.hidden? || (e.layer && !e.layer.visible?)
          if e.is_a?(Sketchup::Edge)
            result << e.start.position.transform(parent_tr)
            result << e.end.position.transform(parent_tr)
          elsif e.is_a?(Sketchup::Group)
            collect_edges_flat_recursive(e.entities, parent_tr * e.transformation, result)
          elsif e.is_a?(Sketchup::ComponentInstance)
            collect_edges_flat_recursive(e.definition.entities, parent_tr * e.transformation, result)
          end
        end
      end

      def tr_flipped?(tr)
        xa = tr.xaxis; ya = tr.yaxis; za = tr.zaxis
        det = xa.x * (ya.y * za.z - ya.z * za.y) -
              xa.y * (ya.x * za.z - ya.z * za.x) +
              xa.z * (ya.x * za.y - ya.y * za.x)
        det < 0
      end

      # ===================== NAME / LAYOUT =====================

      def collect_entities(model)
        @initial_scope.select { |e|
          (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) &&
          e.valid? &&
          !e.hidden? &&
          (e.layer.nil? || e.layer.visible?)
        }
      end

      def rebuild_entity_index
        @entity_index_by_id = {}
        @entities.each_with_index do |e, idx|
          @entity_index_by_id[e.entityID] = idx if e && e.valid?
        end
      end

      def refresh_name_cache
        @entity_names = {}
        @name_width_cache.clear
        @display_name_cache ||= {}
        @display_name_cache.clear
        rebuild_entity_index
        @entities.each { |e| @entity_names[e] = get_entity_name(e) }
        @names_version = @names_version.to_i + 1
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

      def suffix_name_for_entity(entity, raw_name = nil)
        raw_name ||= @entity_names[entity] || get_entity_name(entity)
        _, _, sfx = parse_name(raw_name.to_s)
        return sfx unless sfx.to_s.strip.empty?
        clean = (MH::Rename.clean_name(raw_name.to_s) rescue raw_name.to_s).strip
        base_code, module_code = extract_sp_codes(raw_name.to_s)
        if module_code
          remain = clean.sub(/#{Regexp.escape(module_code)}[\s._-]*/i, '').strip
          return remain unless remain.empty?
        elsif base_code
          remain = clean.sub(/#{Regexp.escape(base_code)}[\s._-]*/i, '').strip
          return remain unless remain.empty?
        end
        clean
      rescue
        raw_name.to_s
      end

      def extract_sp_codes(raw_name)
        raw = raw_name.to_s
        clean = (MH::Rename.clean_name(raw) rescue raw).to_s
        _, pfx, _ = parse_name(raw)
        candidates = [pfx.to_s, clean]

        candidates.each do |txt|
          next if txt.to_s.empty?
          normalized = txt.to_s.gsub(/[_\s]/, '')
          product = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
            MH::NameGrammar.first_product(normalized)
          else
            normalized[/([A-Z]+\d+[A-Z]?(?:\.\d+)?)/i, 1]
          end
          next if product.to_s.empty?
          base = defined?(MH::ProductContext) ? MH::ProductContext.base(product) : product.to_s.upcase.split('.').first
          module_code = product.to_s.include?('.') ? product.to_s.upcase : nil
          return [base, module_code]
        end
        [nil, nil]
      rescue
        [nil, nil]
      end

      def rebuild_drilldown_groups
        @product_groups = []
        @module_groups = []
        @active_product = nil
        @active_module = nil
        @active_module_entity_ids = {}
        @product_index_by_eid = {}
        @module_index_by_eid = {}

        grouped = Hash.new { |h, k| h[k] = [] }
        @entities.each do |entity|
          next unless entity && entity.valid?
          raw_name = @entity_names[entity] || get_entity_name(entity)
          base_code, = extract_sp_codes(raw_name)
          next unless base_code
          grouped[base_code] << entity
        end

        @product_groups = grouped.keys.sort_by { |key| sort_sp_product_key(key) }.map do |key|
          ents = grouped[key]
          bounds = bounds_from_entities(ents)
          {
            key: key,
            label: key,
            entities: ents,
            bounds: bounds,
            center: center_from_bounds(bounds)
          }
        end

        @product_groups.each do |product|
          product[:entities].each { |ent| @product_index_by_eid[ent.entityID] = product[:key] if ent&.valid? }
        end
      end

      def build_modules_for_product(product)
        ents = (product[:entities] || []).select { |e| e && e.valid? }
        return [] if ents.empty?

        by_module = Hash.new { |h, k| h[k] = [] }
        remainder = []

        ents.each do |entity|
          raw_name = @entity_names[entity] || get_entity_name(entity)
          base_code, module_code = extract_sp_codes(raw_name)
          if base_code == product[:key] && module_code
            by_module[module_code] << entity
          else
            remainder << entity
          end
        end

        if by_module.empty?
          fallback_groups = []
          if defined?(MH::FastRename) && MH::FastRename.respond_to?(:split_entities_into_groups)
            begin
              split = MH::FastRename.split_entities_into_groups(ents, product[:bounds])
              fallback_groups = split.map { |rec| (rec[:ents] || []).select { |e| e && e.valid? } }.reject(&:empty?)
            rescue
              fallback_groups = []
            end
          end
          fallback_groups = ents.map { |entity| [entity] } if fallback_groups.empty?
          fallback_groups.each_with_index do |gents, idx|
            by_module["#{product[:key]}.#{idx + 1}"] = gents
          end
        elsif !remainder.empty?
          first_key = by_module.keys.sort_by { |k| sort_sp_module_key(k) }.first
          by_module[first_key].concat(remainder) if first_key
        end

        by_module.keys.sort_by { |key| sort_sp_module_key(key) }.each_with_index.map do |key, idx|
          module_ents = by_module[key].uniq
          bounds = bounds_from_entities(module_ents)
          {
            key: key,
            label: key,
            color_index: idx,
            entities: module_ents,
            bounds: bounds,
            center: center_from_bounds(bounds)
          }
        end
      end

      def bounds_from_entities(entities)
        bb = Geom::BoundingBox.new
        entities.each do |entity|
          next unless entity && entity.valid?
          bb.add(entity.bounds)
        end
        return nil if bb.empty?
        [bb.min, bb.max]
      rescue
        nil
      end

      def center_from_bounds(bounds)
        return nil unless bounds && bounds.length == 2
        mn, mx = bounds
        Geom::Point3d.new(
          (mn.x + mx.x) * 0.5,
          (mn.y + mx.y) * 0.5,
          (mn.z + mx.z) * 0.5
        )
      rescue
        nil
      end

      def sort_sp_product_key(key)
        m = key.to_s.match(/^SP(\d+)$/i)
        m ? m[1].to_i : key.to_s
      end

      def sort_sp_module_key(key)
        m = key.to_s.match(/^SP(\d+)\.(\d+)$/i)
        m ? [m[1].to_i, m[2].to_i] : [9_999_999, key.to_s]
      end

      def reset_drilldown_to_products
        clear_drill_isolation
        @view_mode = @product_groups.empty? ? :suffix : :products
        @active_product = nil
        @active_module = nil
        @active_module_entity_ids = {}
        @module_groups = []
        @module_index_by_eid = {}
        @selected_indices.clear
        @hover_index = nil
        @drill_hover_key = nil
        invalidate_selection_caches
        @layout_cache_key = nil
      end

      def enter_product_mode(product_key, view)
        product = @product_groups.find { |rec| rec[:key] == product_key }
        return unless product
        @active_product = product
        @module_groups = build_modules_for_product(product)
        if @module_groups.empty?
          @module_groups = [{
            key: "#{product[:key]}.1",
            label: "#{product[:key]}.1",
            color_index: 0,
            entities: product[:entities],
            bounds: product[:bounds],
            center: product[:center]
          }]
        end
        @module_index_by_eid = {}
        @module_groups.each do |group|
          group[:entities].each { |entity| @module_index_by_eid[entity.entityID] = group[:key] if entity&.valid? }
        end
        isolate_drill_entities(product[:entities])
        @view_mode = :modules
        @drill_hover_key = nil
        @hover_index = nil
        @selected_indices.clear
        invalidate_selection_caches
        @layout_cache_key = nil
        update_drilldown_status_text
        view.invalidate
        update_control_info
      end

      def enter_suffix_mode(module_key, view)
        mod = @module_groups.find { |rec| rec[:key] == module_key }
        return unless mod
        @active_module = mod
        @active_module_entity_ids = {}
        mod[:entities].each { |entity| @active_module_entity_ids[entity.entityID] = true if entity && entity.valid? }
        isolate_drill_entities(mod[:entities])
        @view_mode = :suffix
        @drill_hover_key = nil
        @hover_index = nil
        @selected_indices = mod[:entities].map { |entity| @entity_index_by_id[entity.entityID] }.compact
        invalidate_selection_caches
        @layout_cache_key = nil
        update_drilldown_status_text
        view.invalidate
        update_control_info
      end

      def back_to_module_mode(view)
        return unless @active_product
        @view_mode = :modules
        isolate_drill_entities(@active_product[:entities])
        @active_module = nil
        @active_module_entity_ids = {}
        @selected_indices.clear
        @hover_index = nil
        @drill_hover_key = nil
        invalidate_selection_caches
        @layout_cache_key = nil
        update_drilldown_status_text
        view.invalidate
        update_control_info
      end

      def back_to_product_mode(view)
        reset_drilldown_to_products
        update_drilldown_status_text
        view.invalidate
        update_control_info
      end

      def isolate_drill_entities(entities)
        clear_drill_isolation
        keep = {}
        entities.each { |entity| keep[entity.entityID] = true if entity && entity.valid? }
        model = Sketchup.active_model
        model.active_entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          next unless entity.valid?
          next if entity.hidden?
          next if keep[entity.entityID]
          entity.hidden = true
          @hidden_by_drill_isolate << entity
        end
      end

      def clear_drill_isolation
        @hidden_by_drill_isolate ||= []
        @hidden_by_drill_isolate.each do |entity|
          entity.hidden = false if entity && entity.valid?
        end
        @hidden_by_drill_isolate.clear
      end

      def update_drilldown_status_text
        case @view_mode
        when :products
          Sketchup.set_status_text("Viewport Name: Chọn mã sản phẩm để isolate sản phẩm")
        when :modules
          product_key = @active_product ? @active_product[:key] : "mã sản phẩm"
          Sketchup.set_status_text("Viewport Name: [#{product_key}] chọn khối module | ESC quay lại danh sách sản phẩm")
        when :suffix
          module_key = @active_module ? @active_module[:key] : "module"
          Sketchup.set_status_text("Viewport Name: [#{module_key}] đang isolate | hiển thị suffix | ESC quay lại module")
        else
          Sketchup.set_status_text("MH_Rename: Click tên để Chọn | Double-click để Sửa tên | ESC để Thoát")
        end
      end

      def enable_xray(model)
        ro = model.rendering_options
        @original_ro = {
          'ModelTransparency' => ro['ModelTransparency'],
          'DrawBackEdges' => ro['DrawBackEdges'],
          'RenderMode' => ro['RenderMode'],
          'Texture' => ro['Texture'],
          'DisplayColorByLayer' => ro['DisplayColorByLayer'],
          'EdgeColorMode' => ro['EdgeColorMode']
        }

        ro['ModelTransparency'] = true
        ro['DrawBackEdges'] = @show_hidden_lines
        ro['RenderMode'] = 5
        ro['DisplayColorByLayer'] = false
      end

      def restore_xray(model)
        return unless @original_ro
        ro = model.rendering_options
        @original_ro.each { |key, val| ro[key] = val unless val.nil? }
        @original_ro = nil
      end

      def parse_name(raw_name)
        prefixes = (MH::Rename.prefix_suggestions rescue []) || []
        @parse_name_cache ||= {}
        key = [raw_name.to_s, prefixes.join("\0")]
        parsed = @parse_name_cache[key] ||= MH::Rename::NameParser.parse_name(raw_name, prefixes: prefixes)
        [parsed[:sys], parsed[:prefix], parsed[:suffix]]
      end

      def format_display_name(entity, raw_name)
        return raw_name if @show_part_id && @show_part_prefix && @show_part_suffix

        prefixes = (MH::Rename.prefix_suggestions rescue []) || []
        @parse_name_cache ||= {}
        key = [raw_name.to_s, prefixes.join("\0")]
        parsed = @parse_name_cache[key] ||= MH::Rename::NameParser.parse_name(raw_name, prefixes: prefixes)
        MH::Rename::NameParser.format_display(
          parsed,
          show_id: @show_part_id,
          show_prefix: @show_part_prefix,
          show_suffix: @show_part_suffix
        )
      end

      def display_name_for(entity, raw_name)
        if @view_mode == :suffix && @active_module_entity_ids && @active_module_entity_ids[entity.entityID]
          return suffix_name_for_entity(entity, raw_name)
        end
        @display_name_cache ||= {}
        key = [
          entity.entityID,
          raw_name.to_s,
          @view_mode,
          @show_part_id,
          @show_part_prefix,
          @show_part_suffix
        ]
        @display_name_cache[key] ||= format_display_name(entity, raw_name)
      rescue
        raw_name.to_s
      end

      def screen_point_in_viewport?(screen, view)
        margin = LAYOUT_VIEWPORT_MARGIN
        screen.x >= -margin && screen.x <= view.vpwidth + margin &&
          screen.y >= -margin && screen.y <= view.vpheight + margin
      rescue
        false
      end

      def build_item_grid(items, cell_size)
        grid = Hash.new { |h, k| h[k] = [] }
        items.each do |item|
          key = [(item[:screen_x] / cell_size).floor, (item[:screen_y] / cell_size).floor]
          grid[key] << item
        end
        grid
      end

      def nearby_items(grid, x, y, cell_size)
        cx = (x / cell_size).floor
        cy = (y / cell_size).floor
        found = []
        (cx - 1).upto(cx + 1) do |gx|
          (cy - 1).upto(cy + 1) { |gy| found.concat(grid[[gx, gy]]) }
        end
        found
      end

      def add_rect_to_grid(grid, rect, cell_size)
        x, y, w, h = rect
        min_x = (x / cell_size).floor
        max_x = ((x + w) / cell_size).floor
        min_y = (y / cell_size).floor
        max_y = ((y + h) / cell_size).floor
        min_x.upto(max_x) do |gx|
          min_y.upto(max_y) { |gy| grid[[gx, gy]] << rect }
        end
      end

      def rect_collision?(grid, x, y, w, h, cell_size)
        min_x = (x / cell_size).floor
        max_x = ((x + w) / cell_size).floor
        min_y = (y / cell_size).floor
        max_y = ((y + h) / cell_size).floor
        min_x.upto(max_x) do |gx|
          min_y.upto(max_y) do |gy|
            grid[[gx, gy]].each do |r|
              return r if x < r[0] + r[2] && x + w > r[0] && y < r[1] + r[3] && y + h > r[1]
            end
          end
        end
        nil
      end

      def calculate_layout(view)
        return { left: [], right: [] } if @entities.empty?

        source = if @view_mode == :suffix && @active_module && @active_module[:entities]
          @active_module[:entities].map { |ent| [ent, @entity_index_by_id[ent.entityID]] }.select { |rec| rec[1] }
        elsif @text_display_mode == :selected
          @selected_indices.map { |idx| [@entities[idx], idx] }
        else
          @entities.each_with_index
        end

        source_count = if @view_mode == :suffix && @active_module && @active_module[:entities]
          source.length
        elsif @text_display_mode == :selected
          source.length
        else
          @entities.length
        end
        large_layout = source_count > MAX_LAYOUT_ITEMS
        items = []
        source.each do |e, orig_index|
          next unless e && entity_visible?(e)
          center = e.bounds.center
          screen = view.screen_coords(center)
          next if large_layout && !screen_point_in_viewport?(screen, view)

          raw_name = @entity_names[e] || get_entity_name(e)

          is_valid = true
          unless @view_mode == :suffix
            if raw_name.empty? || raw_name.start_with?("<")
              is_valid = false
            else
              _, _, sfx = parse_name(raw_name)
              suggs = (MH::Rename.suffix_suggestions rescue []) || []
              is_valid = suggs.any? { |s| s.downcase == sfx.downcase } unless sfx.empty?
              is_valid = false if sfx.empty?
            end
          end

          items << { entity: e, index: orig_index, center3d: center,
            screen_x: screen.x, screen_y: screen.y,
            name: display_name_for(e, raw_name),
            invalid_name: !is_valid }
          break if large_layout && items.length >= MAX_LAYOUT_ITEMS
        end
        return { left: [], right: [] } if items.empty?

        item_grid_cell = 320.0
        item_grid = build_item_grid(items, item_grid_cell)
        rect_grid_cell = 96.0

        if @label_style == :direct
          items = items.sort_by { |i| i[:screen_y] }
          row_h = @line_spacing > 0 ? @line_spacing : LABEL_HEIGHT + 4

          items.each do |item|
            item[:label_w] = calc_text_width(item[:name])
          end

          items.each do |item|
            nearest = nil
            nearest_dist = 999_999
            lw = item[:label_w]
            sx = item[:screen_x]; sy = item[:screen_y]
            nearby_items(item_grid, sx, sy, item_grid_cell).each do |other|
              next if other.equal?(item)
              next if (other[:screen_y] - sy).abs > LABEL_HEIGHT * 2.0
              d = Math.sqrt((other[:screen_x] - sx)**2 + (other[:screen_y] - sy)**2)
              if d < nearest_dist; nearest_dist = d; nearest = other; end
            end
            if nearest && nearest_dist < (lw + nearest[:label_w]) / 1.5
              item[:align] = sx < nearest[:screen_x] ? :left : :right
            else
              item[:align] = :center
            end
          end

          placed_rects = Hash.new { |h, k| h[k] = [] }
          items.each do |item|
            lw = item[:label_w]
            ideal_y = item[:screen_y] - LABEL_HEIGHT / 2.0
            lx = case item[:align]
                 when :left  then item[:screen_x] - lw
                 when :right then item[:screen_x]
                 else             item[:screen_x] - lw / 2.0
                 end
            ly = ideal_y
            loop do
              hit = rect_collision?(placed_rects, lx, ly, lw, LABEL_HEIGHT, rect_grid_cell)
              break unless hit
              ly = hit[1] + row_h
            end
            item[:label_x] = lx; item[:label_y] = ly; item[:side] = :direct
            add_rect_to_grid(placed_rects, [lx, ly, lw, row_h], rect_grid_cell)
          end
          return { left: items, right: [] }

        elsif @label_style == :scatter
          avg_x = items.sum { |i| i[:screen_x] } / items.length.to_f
          items = items.sort_by { |i| i[:screen_y] }
          dist = @text_gap > 0 ? @text_gap : 0
          row_h = @line_spacing > 0 ? @line_spacing : LABEL_HEIGHT + 4

          items.each do |item|
            nearest = nil; nearest_dist = 999_999
            sx = item[:screen_x]; sy = item[:screen_y]; sz = item[:center3d].z
            nearby_items(item_grid, sx, sy, item_grid_cell).each do |other|
              next if other.equal?(item)
              next unless (other[:center3d].z - sz).abs < 5.0
              d = Math.sqrt((other[:screen_x] - sx)**2 + (other[:screen_y] - sy)**2)
              if d < nearest_dist; nearest_dist = d; nearest = other; end
            end
            item[:prefer_left] = nearest && nearest_dist < 300 ? sx < nearest[:screen_x] : sx <= avg_x
          end

          placed_rects = Hash.new { |h, k| h[k] = [] }
          items.each do |item|
            lw = calc_text_width(item[:name])
            ideal_y = item[:screen_y] - LABEL_HEIGHT / 2.0
            lx = item[:prefer_left] ? item[:screen_x] - dist - lw : item[:screen_x] + dist
            ly = ideal_y
            loop do
              hit = rect_collision?(placed_rects, lx, ly, lw, LABEL_HEIGHT, rect_grid_cell)
              break unless hit
              ly = hit[1] + row_h
            end
            item[:label_x] = lx; item[:label_y] = ly; item[:label_w] = lw
            item[:side] = item[:prefer_left] ? :left_scatter : :right_scatter
            add_rect_to_grid(placed_rects, [lx, ly, lw, row_h], rect_grid_cell)
          end
          return { left: items, right: [] }
        end

        # Leader mode (default)
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
        row_h = @line_spacing

        unless left.empty?
          avg_y_left = left.sum { |i| i[:screen_y] } / left.length.to_f
          left_start_y = avg_y_left - left.length * row_h / 2.0
          left.each_with_index do |item, i|
            lw = calc_text_width(item[:name])
            lx = [avg_x - @text_gap - lw, 8].max
            item[:label_x] = lx; item[:label_y] = left_start_y + i * row_h
            item[:label_w] = lw; item[:side] = :left
          end
        end

        unless right.empty?
          avg_y_right = right.sum { |i| i[:screen_y] } / right.length.to_f
          right_start_y = avg_y_right - right.length * row_h / 2.0
          right.each_with_index do |item, i|
            lw = calc_text_width(item[:name])
            lx = [avg_x + @text_gap, vp_w - lw - 8].min
            item[:label_x] = lx; item[:label_y] = right_start_y + i * row_h
            item[:label_w] = lw; item[:side] = :right
          end
        end

        { left: left, right: right }
      end

      # Memoized text width (avoids re-computing per-frame)
      def calc_text_width(text)
        @name_width_cache[text] ||= [[text.to_s.length * CHAR_WIDTH + 4, 60].max, 60].max
      end

      # ===================== DRAW ITEM =====================
      def draw_item(view, item)
        idx   = item[:index]
        name  = item[:name]
        side  = item[:side]
        is_hover = (@hover_index == idx)
        is_sel   = @selected_indices.include?(idx)

        lx = item[:label_x]; ly = item[:label_y]
        lw = item[:label_w]; lh = LABEL_HEIGHT

        if is_sel
          MH::OverlayEngine.rect(view, lx, ly, lw, lh, COL_WHITE_LABEL)
        elsif @show_label_bg
          pts = [[lx, ly, 0], [lx + lw, ly, 0], [lx + lw, ly + lh, 0], [lx, ly + lh, 0]]
          MH::OverlayEngine.rect(view, lx, ly, lw, lh, is_hover ? COL_LABEL_BG_HOVER : COL_LABEL_BG, pts)
          MH::OverlayEngine.rect_outline(view, lx, ly, lw, lh, COL_LABEL_BORDER, pts)
        end

        tc = is_sel ? COL_TEXT_SEL : (is_hover ? COL_TEXT_HOVER : COL_TEXT)
        MH::OverlayEngine.text(
          view, lx + LABEL_PAD_X, ly + LABEL_PAD_Y,
          name.to_s.gsub(/[\r\n]/, ' '),
          font: FONT_NAME, size: FONT_SIZE, color: tc, bold: is_sel
        )

        if item[:invalid_name]
          MH::OverlayEngine.rect_outline(view, lx, ly, lw, lh, "red")
        end

        @label_rects << { x: lx, y: ly, w: lw, h: lh, index: idx }

        return if side == :direct
        return if @text_gap <= 0 && [:left_scatter, :right_scatter].include?(side)

        leader_start, elbow = if side == :left || side == :left_scatter
          ls = Geom::Point3d.new(lx + lw, ly + lh / 2.0, 0)
          [ls, Geom::Point3d.new(ls.x + 20, ls.y, 0)]
        else
          ls = Geom::Point3d.new(lx, ly + lh / 2.0, 0)
          [ls, Geom::Point3d.new(ls.x - 20, ls.y, 0)]
        end

        lcol = is_sel ? COL_LEADER_SEL : (is_hover ? COL_LEADER_HOVER : COL_LEADER)

        entity_scr = Geom::Point3d.new(item[:screen_x], item[:screen_y], 0)
        MH::OverlayEngine.line2d(view, [leader_start, elbow, entity_scr], color: lcol, mode: GL_LINE_STRIP, stipple: "", width: (is_sel || is_hover) ? 2 : 1)

        # Dot � use precomputed circle lookup table
        dc = is_sel ? COL_DOT_SEL : COL_DOT
        tbl = (is_sel || is_hover) ? CIRCLE_PTS_LARGE : CIRCLE_PTS_SMALL
        MH::OverlayEngine.polygon2d(view, tbl.map { |dx, dy| Geom::Point3d.new(entity_scr.x + dx, entity_scr.y + dy, 0) }, color: dc)
      end

      def find_label_at(x, y)
        @label_rects.each do |r|
          return r[:index] if x >= r[:x] && x <= r[:x] + r[:w] && y >= r[:y] && y <= r[:y] + r[:h]
        end
        nil
      end

      # ===================== ACTIONS =====================
      def edit_name(index, view)
        target = @entities[index]
        return unless target && target.valid?

        to_rename = if @selected_indices.include?(index) && @selected_indices.length > 1
          @selected_indices.map { |i| @entities[i] }.compact.select(&:valid?)
        else
          [target]
        end

        cur = @entity_names[target] || ""
        cur = "" if cur.start_with?("<")

        sys_id = cur.match(/^(_+\d+)\.?\s*/) ? cur.match(/^(_+\d+)\.?\s*/)[0] : ""
        clean = cur.sub(/^(_+\d+)\.?\s*/, '')

        cfg_prefixes = (MH::Rename.prefix_suggestions rescue [])
        cfg_suffixes = (MH::Rename.suffix_suggestions rescue [])

        remaining = clean
        pfx = ""
        cfg_prefixes.sort_by { |p| -p.length }.each do |p|
          if remaining.length >= p.length && remaining[0, p.length].downcase == p.downcase
            pfx = remaining[0, p.length]
            remaining = remaining[p.length..-1] || ""
            sm = remaining.match(/^[._\s]*/)
            remaining = remaining[sm[0].length..-1] || "" if sm && sm[0].length > 0
            break
          end
        end
        if pfx.empty?
          m = remaining.match(/^([A-Za-z]+\d+(?:\.\d+)?)([._\s]*)/)
          if m
            pfx = m[1]
            remaining = remaining[m[0].length..-1] || ""
          end
        end
        pfx = pfx.sub(/[._\s]+$/, '').strip
        sfx = remaining.strip

        display_id  = @show_part_id
        display_pfx = @show_part_prefix
        display_sfx = @show_part_suffix
        display_sfx = true if !display_id && !display_pfx && !display_sfx

        w = 20
        w += 60  if display_id
        w += 140 if display_pfx
        w += 200 if display_sfx

        html = build_rename_html(sys_id, pfx, sfx, cfg_prefixes, cfg_suffixes, display_id, display_pfx, display_sfx)

        @rename_dialog.close if @rename_dialog && @rename_dialog.visible? rescue nil
        @rename_dialog = UI::HtmlDialog.new(
          dialog_title: "",
          preferences_key: "mh_viewport_rename_v8",
          width: w + 20, height: 160,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @rename_dialog.set_html(html)

        @rename_dialog.add_action_callback("applyRename") do |_, p, s|
          p = p.strip; s = s.strip
          new_clean = if p != "" && s != ""
            p.end_with?("_") ? "#{p}#{s}" : "#{p}_#{s}"
          elsif p != ""
            p
          else
            s
          end

          model = view.model
          model.start_operation('MH_Rename: Viewport Rename', true)
          to_rename.each do |ent|
            ent_name  = ent.name || ""
            ent_sys_id = ent_name.match(/^(_+\d+)\.?\s*/) ? ent_name.match(/^(_+\d+)\.?\s*/)[0] : ""
            nn = ent_sys_id + new_clean
            ent.name = nn
            new_display = nn.empty? ? get_entity_name(ent) : nn
            old_name = @entity_names[ent]
            @name_width_cache.delete(old_name) if old_name
            @name_width_cache.delete(new_display)
            @entity_names[ent] = new_display
          end
          @display_name_cache.clear
          @names_version = @names_version.to_i + 1
          model.commit_operation

          rebuild_drilldown_groups
          reset_drilldown_to_products
          @layout_cache_key = nil
          update_drilldown_status_text
          view.invalidate
          schedule_dialog_update
          @rename_dialog.close
        end
        @rename_dialog.add_action_callback("closeDialog") { |_| @rename_dialog.close }
        @rename_dialog.show
      end

      def build_rename_html(sys_id, pfx, sfx, cfg_prefixes, cfg_suffixes, display_id, display_pfx, display_sfx)
        <<-HTML
          <!DOCTYPE html><html><head><meta charset="UTF-8"><style>
            body { font-family: 'Segoe UI', sans-serif; background: #232848; color: #d8dff0; padding: 8px; margin: 0; font-size: 12px; overflow:hidden; }
            .row { display: flex; gap: 8px; align-items: flex-start; }
            .col { display: flex; flex-direction: column; position: relative; }
            input { padding: 6px; border: 1px solid rgba(91,140,255,.2); border-radius: 4px; background: #1c2040; color: #fff; outline: none; width: 100%; box-sizing: border-box; font-size: 12px;}
            input:focus { border-color: #5b8cff; box-shadow: 0 0 0 2px rgba(91,140,255,.15); }
            input:disabled { color: #7a8ab0; background: #13162a; border-color: transparent; }
            .dropdown { position: absolute; top: 100%; left: 0; right: 0; max-height: 150px; overflow-y: auto; background: #1c2040; border: 1px solid #5b8cff; border-radius: 4px; z-index: 10; display: none; margin-top:2px; }
            .dropdown.show { display: block; }
            .dd-item { padding: 5px 8px; cursor: pointer; font-size: 11px; color: #d8dff0; }
            .dd-item:hover, .dd-item.active { background: #5b8cff; color: #fff; }
            ::-webkit-scrollbar{width:5px} ::-webkit-scrollbar-track{background:#13162a} ::-webkit-scrollbar-thumb{background:#5b8cff;border-radius:3px}
          </style></head><body>
            <div class="row">
              #{display_id ? "<div class='col' style='width:50px'><input type='text' id='id' value='#{sys_id.strip}' disabled></div>" : ""}
              #{display_pfx ? "<div class='col' style='flex:1'><input type='text' id='pfx' value='#{pfx.gsub('"', '&quot;')}' autocomplete='off' placeholder='Prefix'><div class='dropdown' id='pfx_dd'></div></div>" : ""}
              #{display_sfx ? "<div class='col' style='flex:1.5'><input type='text' id='sfx' value='#{sfx.gsub('"', '&quot;')}' autocomplete='off' placeholder='Suffix'><div class='dropdown' id='sfx_dd'></div></div>" : ""}
            </div>
            <script>
              const pfxSuggs = #{cfg_prefixes.to_json};
              const sfxSuggs = #{cfg_suffixes.to_json};
              function setupDD(inputId, suggs) {
                const inp = document.getElementById(inputId); if(!inp) return;
                const dd = document.getElementById(inputId + '_dd');
                let selIdx = -1, filtered = [];
                function render() {
                  const term = inp.value.toLowerCase().trim();
                  filtered = term === '' ? suggs : suggs.filter(s => s.toLowerCase().includes(term));
                  dd.innerHTML = '';
                  if(!filtered.length) { dd.classList.remove('show'); return; }
                  filtered.forEach((s,i) => {
                    let d = document.createElement('div');
                    d.className = 'dd-item' + (i===selIdx?' active':'');
                    d.textContent = s;
                    d.onmousedown = e => e.preventDefault();
                    d.onclick = () => { inp.value = s; dd.classList.remove('show'); inp.focus(); }
                    dd.appendChild(d);
                  });
                  dd.classList.add('show');
                  if(selIdx>=0 && dd.children[selIdx]) dd.children[selIdx].scrollIntoView({block:'nearest'});
                }
                inp.addEventListener('focus', () => { selIdx=-1; render(); });
                inp.addEventListener('input', () => { selIdx=-1; render(); });
                inp.addEventListener('blur', () => { setTimeout(()=>dd.classList.remove('show'),150); });
                inp.addEventListener('keydown', e => {
                  if(e.key==='ArrowDown'){e.preventDefault(); if(selIdx<filtered.length-1){selIdx++;render();}}
                  else if(e.key==='ArrowUp'){e.preventDefault(); if(selIdx>0){selIdx--;render();}}
                  else if(e.key==='Tab'){
                    if(dd.classList.contains('show')&&filtered.length>0){
                      e.preventDefault();
                      selIdx = e.shiftKey ? (selIdx<=0?filtered.length-1:selIdx-1) : (selIdx>=filtered.length-1?0:selIdx+1);
                      render();
                    }
                  } else if(e.key==='Enter'){
                    if(dd.classList.contains('show')&&selIdx>=0&&selIdx<filtered.length){e.preventDefault();inp.value=filtered[selIdx];dd.classList.remove('show');}
                    else{e.preventDefault();apply();}
                  } else if(e.key==='Escape'){e.preventDefault(); dd.classList.contains('show')?dd.classList.remove('show'):sketchup.closeDialog();}
                });
              }
              setupDD('pfx',pfxSuggs); setupDD('sfx',sfxSuggs);
              function apply() {
                let p = document.getElementById('pfx') ? document.getElementById('pfx').value : "#{pfx.gsub('"', '&quot;')}";
                let s = document.getElementById('sfx') ? document.getElementById('sfx').value : "#{sfx.gsub('"', '&quot;')}";
                sketchup.applyRename(p, s);
              }
              const sfxInp = document.getElementById('sfx');
              if(sfxInp){sfxInp.focus();sfxInp.select();}
              else if(document.getElementById('pfx')){document.getElementById('pfx').focus();}
              window.addEventListener('keydown', e => {
                if(e.key==='Tab'){
                  const a = document.activeElement;
                  if(a&&(a.id==='pfx'||a.id==='sfx')){
                    const dd=document.getElementById(a.id+'_dd');
                    if(dd&&dd.classList.contains('show')) e.preventDefault();
                  }
                }
              }, true);
            </script>
          </body></html>
        HTML
      end

      def delete_selected(view)
        return if @selected_indices.empty?
        model = view.model
        to_del = @selected_indices.map { |i| @entities[i] }.compact.select(&:valid?)
        return if to_del.empty?
        eids_to_del = to_del.map(&:entityID)
        model.start_operation('MH_Rename: Delete', true)
        to_del.each(&:erase!)
        model.commit_operation
        @entities.reject! { |e| !e.valid? }
        eids_to_del.each do |eid|
          @triangle_cache.delete(eid)
          @edge_3d_cache.delete(eid)
          @triangle_cache_with_normals&.delete(eid)
        end
        @selected_indices.clear
        invalidate_selection_caches
        refresh_name_cache
        rebuild_drilldown_groups
        reset_drilldown_to_products
        model.selection.clear
        update_drilldown_status_text
        view.invalidate
        update_control_info
        schedule_dialog_update
      end

      def hide_selected(view)
        model = view.model
        to_hide = if @selected_indices.empty?
          model.selection.to_a.select { |e|
            (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.valid?
          }
        else
          @selected_indices.map { |i| @entities[i] }.compact.select(&:valid?)
        end
        return if to_hide.empty?

        model.start_operation('MH_Rename: Hide', true)
        to_hide.each { |e| e.hidden = true }
        model.commit_operation

        @entities = collect_entities(model)
        @selected_indices.clear
        invalidate_all_caches
        refresh_name_cache
        rebuild_drilldown_groups
        reset_drilldown_to_products
        model.selection.clear
        update_drilldown_status_text
        view.invalidate
        update_control_info
        schedule_dialog_update
      end

      def unhide_all(view)
        model = view.model
        hidden_ents = model.active_entities.select { |e|
          (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.hidden?
        }
        return if hidden_ents.empty?

        model.start_operation('MH_Rename: Unhide All', true)
        hidden_ents.each { |e| e.hidden = false }
        model.commit_operation

        @entities = collect_entities(model)
        @selected_indices.clear
        invalidate_all_caches
        refresh_name_cache
        rebuild_drilldown_groups
        reset_drilldown_to_products
        update_drilldown_status_text
        view.invalidate
        update_control_info
        schedule_dialog_update
      end

      # ===================== CONTROL PANEL =====================

      # Throttled dialog update � debounce 80ms, 1 l?n execute_script duy nh?t (JSON)
      def schedule_dialog_update
        return unless @dialog && @dialog.visible?
        return if @dialog_update_pending
        @dialog_update_pending = true
        UI.start_timer(0.08, false) do
          @dialog_update_pending = false
          update_entity_list_html
        end
      end

      def show_controls
        return if @dialog && @dialog.visible?
        @dialog = UI::HtmlDialog.new(
          dialog_title: "Viewport Names", preferences_key: "mh_rename_viewport_ctrl",
          width: 300, height: 450, left: 100, top: 120,
          resizable: false, style: UI::HtmlDialog::STYLE_UTILITY
        )
        @dialog.set_html(build_control_html)

        @dialog.add_action_callback("setSpacing") do |_, v|
          @line_spacing = v.to_i
          Sketchup.write_default("MH_Rename_Viewport", "line_spacing", @line_spacing)
          @layout_cache_key = nil
          Sketchup.active_model.active_view.invalidate
        end
        @dialog.add_action_callback("setGap") do |_, v|
          @text_gap = v.to_i
          Sketchup.write_default("MH_Rename_Viewport", "text_gap", @text_gap)
          @layout_cache_key = nil
          Sketchup.active_model.active_view.invalidate
        end
        @dialog.add_action_callback("setTextMode") do |_, mode|
          @text_display_mode = mode.to_sym
          Sketchup.write_default("MH_Rename_Viewport", "text_display_mode", mode.to_s)
          @layout_cache_key = nil
          Sketchup.active_model.active_view.invalidate
        end
        @dialog.add_action_callback("setHiddenLines") do |_, val|
          @show_hidden_lines = (val.to_s == "true")
          Sketchup.write_default("MH_Rename_Viewport", "show_hidden_lines", @show_hidden_lines)
          Sketchup.active_model.rendering_options["DrawBackEdges"] = @show_hidden_lines
          Sketchup.active_model.active_view.invalidate
        end
        @dialog.add_action_callback("updateSelection") do |_, ids_str|
          @selected_indices.clear
          m = Sketchup.active_model; m.selection.clear
          unless ids_str.empty?
            eids = ids_str.split(',').map(&:to_i)
            eids.each do |eid|
              idx = @entity_index_by_id[eid]
              e = idx && @entities[idx]
              @selected_indices << idx if e && entity_visible?(e)
            end
          end
          invalidate_selection_caches
          m.active_view.invalidate
          update_control_info
        end
        @dialog.add_action_callback("setLabelStyle") do |_, val|
          @label_style = val.to_sym
          Sketchup.write_default("MH_Rename_Viewport", "label_style", val.to_s)
          @layout_cache_key = nil
          Sketchup.active_model.active_view.invalidate
        end
        @dialog.add_action_callback("setPart") do |_, part, state|
          val = (state.to_s == "true")
          case part
          when "id"     then @show_part_id = val;     Sketchup.write_default("MH_Rename_Viewport", "show_part_id", val)
          when "prefix" then @show_part_prefix = val;  Sketchup.write_default("MH_Rename_Viewport", "show_part_prefix", val)
          when "suffix" then @show_part_suffix = val;  Sketchup.write_default("MH_Rename_Viewport", "show_part_suffix", val)
          end
          @name_width_cache.clear; @display_name_cache.clear; @layout_cache_key = nil
          Sketchup.active_model.active_view.invalidate
          schedule_dialog_update
        end
        @dialog.add_action_callback("setLabelBg") do |_, val|
          @show_label_bg = (val.to_s == "true")
          Sketchup.write_default("MH_Rename_Viewport", "show_label_bg", @show_label_bg)
          Sketchup.active_model.active_view.invalidate
        end
        @dialog.add_action_callback("toggleLayer") do |_, param|
          parts = param.to_s.split('|', 2)
          lname = parts[0].to_s.strip; is_show = (parts[1].to_s.strip == "true")
          next if lname.empty?
          model = Sketchup.active_model
          layer = model.layers.find { |l| l.name.strip == lname }
          layer.visible = is_show if layer
          if is_show
            @hidden_layers.reject! { |hl| hl.to_s.strip.downcase == lname.downcase }
          else
            @hidden_layers << lname unless @hidden_layers.any? { |hl| hl.to_s.strip.downcase == lname.downcase }
          end
          Sketchup.write_default("MH_Rename_Viewport", "hidden_layers", @hidden_layers.join(";;"))
          @entities = collect_entities(model)
          @selected_indices.clear
          invalidate_all_caches
          refresh_name_cache
          rebuild_drilldown_groups
          reset_drilldown_to_products
          update_drilldown_status_text
          model.active_view.invalidate
          update_control_info
          schedule_dialog_update
        end
        @dialog.add_action_callback("closeTool") { |_| Sketchup.active_model.select_tool(nil) }
        @dialog.add_action_callback("hideSelected")   { |_| hide_selected(Sketchup.active_model.active_view) }
        @dialog.add_action_callback("unhideAll")      { |_| unhide_all(Sketchup.active_model.active_view) }
        @dialog.add_action_callback("deleteSelected") { |_| delete_selected(Sketchup.active_model.active_view) }
        @dialog.add_action_callback("hoverItem") do |_, eid_str|
          eid = eid_str.to_i
          if @view_mode == :products
            new_key = eid > 0 ? @product_index_by_eid[eid] : nil
            if @drill_hover_key != new_key
              @drill_hover_key = new_key
              Sketchup.active_model.active_view.invalidate
            end
          elsif @view_mode == :modules
            new_key = eid > 0 ? @module_index_by_eid[eid] : nil
            if @drill_hover_key != new_key
              @drill_hover_key = new_key
              Sketchup.active_model.active_view.invalidate
            end
          else
            new_hover = eid > 0 ? @entity_index_by_id[eid] : nil
            if @hover_index != new_hover
              @hover_index = new_hover
              @layout_cache_key = nil
              Sketchup.active_model.active_view.invalidate
            end
          end
        end
        @dialog.show
      end

      def html_escape(value)
        value.to_s
             .gsub('&', '&amp;')
             .gsub('<', '&lt;')
             .gsub('>', '&gt;')
             .gsub('"', '&quot;')
             .gsub("'", '&#39;')
      end

      def entity_list_payload(limit = MAX_DIALOG_ROWS)
        selected = {}
        @selected_indices.each { |idx| selected[idx] = true }
        ordered_indices = []
        @selected_indices.each do |idx|
          next if idx.nil? || idx < 0 || idx >= @entities.length
          ordered_indices << idx unless ordered_indices.include?(idx)
        end
        @entities.each_index do |idx|
          break if limit && ordered_indices.length >= limit
          ordered_indices << idx unless selected.key?(idx)
        end

        rows = []
        ordered_indices.each do |i|
          e = @entities[i]
          next unless e && e.valid?
          raw_name = @entity_names[e] || get_entity_name(e)
          rows << {
            eid: e.entityID,
            name: display_name_for(e, raw_name).to_s,
            checked: selected.key?(i)
          }
          break if limit && rows.length >= limit
        end
        rows
      end

      def entity_list_rows_html
        entity_list_payload.map do |item|
          name = html_escape(item[:name])
          checked = item[:checked] ? "checked" : ""
          "<div class='item-row' data-name='#{html_escape(item[:name].downcase)}' onmouseenter='sketchup.hoverItem(#{item[:eid]})' onmouseleave='sketchup.hoverItem(-1)'><label style='display:flex;align-items:center;cursor:pointer'><input type='checkbox' class='ent-cb' value='#{item[:eid]}' #{checked} onchange='updateSelection()'> <span style='margin-left:6px;font-size:11px'>#{name}</span></label></div>"
        end.join("")
      end

      def entity_count_text
        if @entities.length > MAX_DIALOG_ROWS
          "#{MAX_DIALOG_ROWS}/#{@entities.length} objects"
        else
          "#{@entities.length} objects"
        end
      end

      def build_control_html
        m = Sketchup.active_model
        layer_names = m.layers.map(&:name).sort
        layer_html = layer_names.map do |ln|
          layer = m.layers[ln]
          checked = layer && layer.visible? ? "checked" : ""
          ln_esc = ln.gsub("'", "&#39;").gsub('"', '&quot;')
          "<label style='display:flex;align-items:center;margin-bottom:4px;cursor:pointer'><input type='checkbox' data-layer='#{ln_esc}' #{checked} onchange='toggleLayerCb(this)'> <span style='margin-left:6px'>#{ln}</span></label>"
        end.join("\n")

        <<~HTML
          <!DOCTYPE html><html><head><meta charset="UTF-8">
          <style>
            :root{--bg0:#0d0f18;--bg1:#13162a;--bg2:#1c2040;--bg3:#232848;
              --acc:#5b8cff;--acc2:#7fd4e8;--ok:#55e5a0;--danger:#ff5f5f;
              --txt:#d8dff0;--txt2:#7a8ab0;--border:rgba(91,140,255,.2);--r:6px}
            *{box-sizing:border-box;margin:0;padding:0}
            body{font-family:'Segoe UI',sans-serif;background:var(--bg0);color:var(--txt);
              font-size:12px;padding:12px;user-select:none}
            .header{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;padding-bottom:8px;}
            .tab-btn{padding:6px 12px;cursor:pointer;border-bottom:2px solid transparent;color:var(--txt2);font-weight:600;font-size:11px;flex:1;text-align:center}
            .tab-btn.active{border-bottom:2px solid var(--acc);color:var(--acc)}
            .tab-content{display:none}.tab-content.active{display:block}
            .title{font-family:monospace;font-size:13px;font-weight:700;color:var(--acc)}
            .count{font-size:10px;color:var(--txt2);background:var(--bg2);padding:2px 8px;border-radius:20px}
            .control{margin-bottom:12px}
            .control label{display:flex;align-items:center;justify-content:space-between;font-size:11px;margin-bottom:4px;color:var(--txt2)}
            .val{font-family:monospace;font-size:10px;color:var(--acc);min-width:28px;text-align:right}
            input[type="range"]{width:100%;height:6px;-webkit-appearance:none;background:var(--bg2);border-radius:3px;outline:none}
            input[type="range"]::-webkit-slider-thumb{-webkit-appearance:none;width:14px;height:14px;background:var(--acc);border-radius:50%;cursor:pointer;border:2px solid var(--bg0)}
            .actions{display:flex;gap:6px;margin-top:10px;padding-top:8px;border-top:1px solid var(--border)}
            .btn{flex:1;padding:5px 0;border:1px solid var(--border);border-radius:var(--r);background:var(--bg2);color:var(--txt2);font-size:10px;font-weight:600;cursor:pointer;text-align:center}
            .btn:hover{background:var(--bg3);color:var(--txt)}
            .btn.danger{background:rgba(255,95,95,.12);border-color:rgba(255,95,95,.3);color:var(--danger)}
            .btn.danger:hover{background:rgba(255,95,95,.25)}
            .item-row{padding:4px;border-bottom:1px solid rgba(255,255,255,0.05)}
            .item-row:hover{background:var(--bg2)}
            ::-webkit-scrollbar{width:6px}::-webkit-scrollbar-track{background:var(--bg1)}::-webkit-scrollbar-thumb{background:var(--bg3);border-radius:3px}
          </style>
          <script>
            function switchTab(tabId){
              document.querySelectorAll('.tab-content').forEach(el=>el.classList.remove('active'));
              document.querySelectorAll('.tab-btn').forEach(el=>el.classList.remove('active'));
              document.getElementById(tabId).classList.add('active');
              document.getElementById('btn-'+tabId).classList.add('active');
            }
            function updateSelection(){
              let checked=[];
              document.querySelectorAll('.ent-cb:checked').forEach(cb=>checked.push(cb.value));
              sketchup.updateSelection(checked.join(','));
            }
            function filterList(term){
              term=term.toLowerCase().trim();
              document.querySelectorAll('.item-row').forEach(row=>{
                row.style.display=(term===""||row.getAttribute('data-name').includes(term))?"block":"none";
              });
            }
            function toggleAll(selectAll){
              document.querySelectorAll('.item-row').forEach(row=>{
                if(row.style.display!=="none"){
                  const cb=row.querySelector('.ent-cb');
                  if(cb) cb.checked=selectAll;
                }
              });
              updateSelection();
            }
            function setCheckboxes(eids){
              document.querySelectorAll('.ent-cb').forEach(cb=>cb.checked=false);
              eids.split(',').forEach(id=>{
                if(id!==""){const el=document.querySelector('.ent-cb[value="'+id+'"]');if(el)el.checked=true;}
              });
            }
            function rebuildEntityList(data){
              const container=document.getElementById('entityList');
              const badge=document.getElementById('countBadge');
              if(!container) return;
              if(badge) badge.textContent=(data.shown&&data.shown<data.count ? data.shown+'/'+data.count : data.count)+' objects';
              const term=(document.getElementById('searchInput')?.value||'').toLowerCase().trim();
              container.innerHTML=data.items.map(function(item){
                const name=item.name.replace(/'/g,"&#39;");
                const checked=item.checked?'checked':'';
                const hidden=term&&!name.toLowerCase().includes(term)?'style="display:none"':'';
                return '<div class="item-row" data-name="'+name.toLowerCase()+'" '+hidden+' onmouseenter="sketchup.hoverItem('+item.eid+')" onmouseleave="sketchup.hoverItem(-1)"><label style="display:flex;align-items:center;cursor:pointer"><input type="checkbox" class="ent-cb" value="'+item.eid+'" '+checked+' onchange="updateSelection()"><span style="margin-left:6px;font-size:11px">'+name+'</span></label></div>';
              }).join('');
            }
            function toggleLayerCb(el){sketchup.toggleLayer(el.getAttribute('data-layer')+'|'+el.checked);}
            document.addEventListener('keydown',function(e){
              if(e.key==='F4'){e.preventDefault();sketchup.hideSelected();return;}
              if((e.key==='x'||e.key==='X')&&e.ctrlKey&&e.shiftKey){e.preventDefault();sketchup.unhideAll();return;}
              if(e.target.tagName==='INPUT'||e.target.tagName==='TEXTAREA') return;
              if(e.key==='x'||e.key==='X'){e.preventDefault();sketchup.hideSelected();return;}
              if(e.key==='Delete'){e.preventDefault();sketchup.deleteSelected();}
            });
          </script>
          </head><body>
            <div class="header">
              <span class="title">Viewport Names</span>
              <span class="count" id="countBadge">#{entity_count_text}</span>
            </div>
            <div style="display:flex;margin-bottom:12px;border-bottom:1px solid var(--border);">
              <div id="btn-tab-main" class="tab-btn active" onclick="switchTab('tab-main')">Cài đặt chung</div>
              <div id="btn-tab-layers" class="tab-btn" onclick="switchTab('tab-layers')">Lọc Layer/Tag</div>
            </div>

            <div id="tab-main" class="tab-content active">
              <div class="control" style="margin-bottom:8px">
                <input type="text" id="searchInput" placeholder="Tìm kiếm chi tiết..." style="width:100%;padding:6px;border-radius:var(--r);border:1px solid var(--border);background:var(--bg2);color:var(--txt);outline:none" oninput="filterList(this.value)">
              </div>
              <div style="display:flex;gap:4px;margin-bottom:4px">
                <button class="btn" style="flex:1" onclick="toggleAll(true)">Tick hết (lọc)</button>
                <button class="btn" style="flex:1" onclick="toggleAll(false)">Bỏ tick hết</button>
              </div>
              <div id="entityList" style="max-height:140px;overflow-y:auto;border:1px solid var(--border);border-radius:var(--r);padding:4px;margin-bottom:12px;background:rgba(0,0,0,0.2);">
                #{entity_list_rows_html}
              </div>

              <div class="control" style="margin-bottom:12px;font-size:11px;background:var(--bg1);padding:8px;border-radius:var(--r);">
                <div style="font-weight:bold;margin-bottom:6px;color:var(--acc2);">Kiểu ghi tên (Label style):</div>
                <label style="display:flex;align-items:center;justify-content:flex-start;margin-bottom:4px;cursor:pointer"><input type="radio" name="lblStyle" value="leader" #{@label_style == :leader ? 'checked' : ''} onchange="sketchup.setLabelStyle('leader')"> <span style="margin-left:6px">Đường dóng 2 bên</span></label>
                <label style="display:flex;align-items:center;justify-content:flex-start;margin-bottom:4px;cursor:pointer"><input type="radio" name="lblStyle" value="scatter" #{@label_style == :scatter ? 'checked' : ''} onchange="sketchup.setLabelStyle('scatter')"> <span style="margin-left:6px">Tự do (Nối text với object)</span></label>
                <label style="display:flex;align-items:center;justify-content:flex-start;cursor:pointer"><input type="radio" name="lblStyle" value="direct" #{@label_style == :direct ? 'checked' : ''} onchange="sketchup.setLabelStyle('direct')"> <span style="margin-left:6px">Ghi đè lên đối tượng</span></label>
              </div>

              <div class="control" style="margin-bottom:12px;font-size:11px;background:var(--bg1);padding:8px;border-radius:var(--r);">
                <div style="font-weight:bold;margin-bottom:6px;color:var(--acc2);">Thành phần tên:</div>
                <label style="display:flex;align-items:center;justify-content:flex-start;margin-bottom:4px;cursor:pointer"><input type="checkbox" #{@show_part_id ? 'checked' : ''} onchange="sketchup.setPart('id', this.checked)"> <span style="margin-left:6px">ID (VD: __1.)</span></label>
                <label style="display:flex;align-items:center;justify-content:flex-start;margin-bottom:4px;cursor:pointer"><input type="checkbox" #{@show_part_prefix ? 'checked' : ''} onchange="sketchup.setPart('prefix', this.checked)"> <span style="margin-left:6px">Prefix / mã sản phẩm</span></label>
                <label style="display:flex;align-items:center;justify-content:flex-start;margin-bottom:4px;cursor:pointer"><input type="checkbox" #{@show_part_suffix ? 'checked' : ''} onchange="sketchup.setPart('suffix', this.checked)"> <span style="margin-left:6px">Suffix (Tên chi tiết)</span></label>
                <label style="display:flex;align-items:center;justify-content:flex-start;cursor:pointer"><input type="checkbox" #{@show_label_bg ? 'checked' : ''} onchange="sketchup.setLabelBg(this.checked)"> <span style="margin-left:6px;font-weight:bold;color:var(--ok)">Hiện nền văn bản</span></label>
              </div>

              <div class="control" style="margin-bottom:12px;font-size:11px;background:var(--bg1);padding:8px;border-radius:var(--r);">
                <div style="font-weight:bold;margin-bottom:6px;color:var(--acc2);">Chế độ hiển thị Text:</div>
                <label style="display:flex;align-items:center;justify-content:flex-start;margin-bottom:4px;cursor:pointer"><input type="radio" name="txtMode" value="all" #{@text_display_mode == :all ? 'checked' : ''} onchange="sketchup.setTextMode('all')"> <span style="margin-left:6px">Hiện tên tất cả chi tiết</span></label>
                <label style="display:flex;align-items:center;justify-content:flex-start;cursor:pointer"><input type="radio" name="txtMode" value="selected" #{@text_display_mode == :selected ? 'checked' : ''} onchange="sketchup.setTextMode('selected')"> <span style="margin-left:6px">Chỉ hiện tên chi tiết được chọn</span></label>
              </div>

              <div class="control" style="margin-bottom:12px;font-size:11px;background:var(--bg1);padding:8px;border-radius:var(--r);">
                <div style="font-weight:bold;margin-bottom:6px;color:var(--acc2);">Đường nét bị che khuất:</div>
                <label style="display:flex;align-items:center;justify-content:flex-start;margin-bottom:4px;cursor:pointer"><input type="radio" name="hlMode" value="true" #{@show_hidden_lines ? 'checked' : ''} onchange="sketchup.setHiddenLines('true')"> <span style="margin-left:6px">Hiện nét đứt (bị che)</span></label>
                <label style="display:flex;align-items:center;justify-content:flex-start;cursor:pointer"><input type="radio" name="hlMode" value="false" #{!@show_hidden_lines ? 'checked' : ''} onchange="sketchup.setHiddenLines('false')"> <span style="margin-left:6px">Ẩn nét đứt</span></label>
              </div>

              <div class="control">
                <label>Khoảng cách dòng <span class="val" id="sV">#{@line_spacing}</span></label>
                <input type="range" min="0" max="80" value="#{@line_spacing}" oninput="document.getElementById('sV').textContent=this.value;sketchup.setSpacing(+this.value)">
              </div>
              <div class="control">
                <label>Khoảng cách Text -> Object <span class="val" id="gV">#{@text_gap}</span></label>
                <input type="range" min="0" max="500" value="#{@text_gap}" oninput="document.getElementById('gV').textContent=this.value;sketchup.setGap(+this.value)">
              </div>
            </div>

            <div id="tab-layers" class="tab-content">
              <div class="control" style="margin-bottom:12px;font-size:11px;background:var(--bg1);padding:8px;border-radius:var(--r);">
                <div style="font-weight:bold;margin-bottom:6px;color:var(--acc2);">Tắt tick để KHÔNG hiển thị layer đó:</div>
                <div style="max-height:400px;overflow-y:auto;">#{layer_html}</div>
              </div>
            </div>

            <div class="actions">
              <button class="btn danger" onclick="sketchup.closeTool()">Đóng</button>
            </div>
          </body></html>
        HTML
      end

      def update_control_info
        return unless @dialog && @dialog.visible?
        schedule_dialog_update
      rescue; end

      def update_entity_list_html
        return unless @dialog && @dialog.visible?
        items = entity_list_payload
        data = { count: @entities.length, shown: items.length, items: items }
        json = data.to_json
        @dialog.execute_script("rebuildEntityList(#{json});")
      rescue; end
    end

  end
end
