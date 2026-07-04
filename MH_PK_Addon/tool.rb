# encoding: utf-8
# MH_PK_Addon — PKHudTool: tool tuong tac trong viewport.
# Click dong PK (excel/thu vien) de arm → hover highlight mat (Tab lat mat) → click de add.
# Click vao PK marker co san khi dang arm PK khac → doi ten marker.
# Click o giua-duoi → go ten truc tiep (hoac go vao o Measurements roi Enter cho tieng Viet co dau).

module MH_PK_Addon
  class PKHudModelObserver < Sketchup::ModelObserver
    def initialize(tool)
      @tool = tool
    end

    def onTransactionCommit(_model)
      @tool.external_change
    end

    def onTransactionUndo(_model)
      @tool.external_change
    end

    def onTransactionRedo(_model)
      @tool.external_change
    end
  end

  class PKHudTool
    HIGHLIGHT_ARMED = Sketchup::Color.new(25, 170, 80, 135)
    HIGHLIGHT_IDLE = Sketchup::Color.new(30, 105, 230, 130)
    HIGHLIGHT_MULTI = Sketchup::Color.new(235, 120, 20, 135)
    HIGHLIGHT_MULTI_EDGE = Sketchup::Color.new(235, 150, 30, 255)

    @@last_product = ''

    def activate
      @hud = Hud.new
      @leaders = Leaders.new
      @armed = nil
      @hover = nil
      @cycle = nil
      @flip_index = 0
      @length_mode = false
      @product_code = ''
      @ticks_dirty = false
      @editing = false
      @edit_text = ''
      @session_ops = 0
      @multi_faces = {}
      @multi_markers = {}
      @label_faces = []
      @label_pk_items = []
      @label_cluster_key = nil
      @edit_markers = nil
      @edit_rect = nil
      @drag_start = nil
      @drag_cur = nil
      Picker.clear_cache

      detect_or_reuse_product
      @leaders.product_filter = @product_code
      load_panels
      attach_observer
      set_status
      view = MH_PK_Addon.model.active_view
      view.invalidate if view
    end

    def deactivate(view)
      detach_observer
      Picker.clear_cache
      Sketchup.status_text = ''
      view.invalidate if view
    end

    def suspend(view)
      view.invalidate if view
    end

    def resume(view)
      set_status
      view.invalidate if view
    end

    def enableVCB?
      true
    end

    def onMouseMove(_flags, x, y, view)
      if @drag_start
        @drag_cur = [x, y]
        view.invalidate
        return
      end

      changed = @hud.update_hover(view, x, y)
      changed = @leaders.update_hover(x, y) || changed

      if @hud.over_hud?(view, x, y) || @leaders.over_label?(x, y)
        if @hover
          @hover = nil
          @cycle = nil
          changed = true
        end
      else
        ctx = Picker.pick(view, x, y)
        if hover_sig(ctx) != hover_sig(@hover)
          @hover = ctx
          @cycle = nil
          @flip_index = 0
          Picker.clear_cache
          changed = true
        end
      end
      view.invalidate if changed
    end

    def onLButtonDown(flags, x, y, view)
      commit_edit(view) if @editing && !@hud.hit_test(view, x, y).is_a?(Hash)

      ctrl = modifier?(flags, :ctrl)
      shift = modifier?(flags, :shift)

      if @hud.over_hud?(view, x, y)
        action = @hud.click(view, x, y)
        handle_hud_action(action, view) if action
        view.invalidate
        return
      end

      if shift
        # shift co the quet chon bo: ghi diem bat dau, xu ly o onLButtonUp
        @drag_start = [x, y]
        @drag_cur = nil
        return
      end

      if ctrl
        handle_ctrl_click(x, y, view)
        view.invalidate
        return
      end

      cluster = @leaders.cluster_at_label(x, y)
      if cluster
        # click nhan: highlight obj PK (vang, xuyen che) + mat cha chua PK (mau vien).
        # Click lai CUNG nhan → giu nguyen bo highlight da prune bang shift-quet.
        key = cluster[:label].to_s
        if @label_cluster_key != key
          @label_faces = @leaders.host_faces_for_cluster(cluster)
          @label_pk_items = cluster[:items].first(60)
          @label_cluster_key = key
        end
        targets = label_rename_targets(cluster)
        if @armed && !targets.empty?
          perform_rename_list(targets, view)
        elsif targets.empty?
          Sketchup.status_text = "#{cluster[:label]} — nhan nay khong co phu kien doi ten duoc."
        else
          Sketchup.status_text = "#{cluster[:label]} — #{targets.length} obj dang chon. Double-click de sua ten (chi ap dung obj con highlight)."
        end
        view.invalidate
        return
      end
      @label_faces = [] unless @label_faces.empty?
      @label_pk_items = [] unless @label_pk_items.empty?
      @label_cluster_key = nil

      ctx = Picker.pick(view, x, y)
      if ctx.nil?
        # click ra ngoai (khong vao bang/nhan/obj) → huy chon PK dang arm
        if @armed
          disarm
          Sketchup.status_text = 'Da bo chon phu kien.'
        end
        view.invalidate
        return
      end

      if ctx[:kind] == :marker
        perform_rename(ctx[:marker], view)
      elsif ctx[:kind] == :face
        if hover_sig(ctx) != hover_sig(@hover)
          @hover = ctx
          @cycle = nil
          @flip_index = 0
        end
        if @armed
          perform_add(view)
        else
          adopt_product_from(ctx[:target], view)
        end
      end
      view.invalidate
    end

    # Double-click vao nhan → go vao CHINH O NHAN do; ban phim bi khoa boi o nhap
    # (HtmlDialog bat phim → khong dinh shortcut SketchUp, go duoc tieng Viet).
    def onLButtonDoubleClick(_flags, x, y, view)
      cluster = @leaders.cluster_at_label(x, y)
      return unless cluster

      targets = label_rename_targets(cluster)
      if targets.empty?
        Sketchup.status_text = 'Nhan nay khong co phu kien sua ten duoc.'
        return
      end

      start_edit(view,
                 markers: targets,
                 rect: cluster[:label_rect],
                 initial: MH_PK_Addon.accessory_label(targets.first))
      Sketchup.status_text = "Sua ten #{targets.length} phu kien dang highlight (Enter = ap dung, Esc = huy)."
    end

    # Doi ten ap dung cho: obj CON highlight cua nhan nay (sau shift-quet bo bot)
    # + moi PK da Ctrl-chon o cac nhan khac (rename nhieu nhan 1 luc).
    def label_rename_targets(cluster)
      all = @leaders.renameable_markers_in(cluster)
      ids = @label_pk_items.map { |item| item[:marker].entityID rescue nil }.compact
      base =
        if ids.empty? || @label_cluster_key != cluster[:label].to_s
          all
        else
          subset = all.select { |m| ids.include?(m.entityID) }
          subset.empty? ? all : subset
        end

      extra = @multi_markers.values.select { |m| MH_PK_Addon.live_entity?(m) }
      (base + extra).uniq(&:entityID)
    rescue
      all || []
    end

    # Quet shift: tha chuot → bo chon vung; click ngan → bo chon 1 chi tiet.
    def onLButtonUp(_flags, x, y, view)
      return unless @drag_start

      x0, y0 = @drag_start
      moved = (x - x0).abs + (y - y0).abs
      if moved < 6
        handle_shift_click(x0, y0, view)
      else
        region_deselect(x0, y0, x, y, view)
      end
      @drag_start = nil
      @drag_cur = nil
      view.invalidate
    end

    # Bo chon moi mat/PK co tam man hinh nam trong vung quet.
    def region_deselect(x0, y0, x1, y1, view)
      rx0, rx1 = [x0, x1].minmax
      ry0, ry1 = [y0, y1].minmax
      removed = 0

      face_ids = @multi_faces.select do |_id, ctx|
        face = ctx[:face]
        next false unless face && face.valid?

        sp = view.screen_coords(face.bounds.center.transform(ctx[:transform]))
        sp.x >= rx0 && sp.x <= rx1 && sp.y >= ry0 && sp.y <= ry1
      end.keys
      face_ids.each { |id| @multi_faces.delete(id); removed += 1 }

      unless @multi_markers.empty?
        centers = {}
        @leaders.markers.each { |m| centers[m[:marker].entityID] = m[:world_center] }
        marker_ids = @multi_markers.keys.select do |id|
          center = centers[id]
          next false unless center

          sp = view.screen_coords(center)
          sp.x >= rx0 && sp.x <= rx1 && sp.y >= ry0 && sp.y <= ry1
        end
        marker_ids.each { |id| @multi_markers.delete(id); removed += 1 }
      end

      # bo ca highlight tu nhan (obj PK vang + mat xanh) trong vung quet
      unless @label_pk_items.empty?
        @label_pk_items = @label_pk_items.reject do |item|
          center = item[:world_center]
          center ||= item[:local_center].transform(item[:parent_tr]) rescue nil
          next false unless center

          sp = view.screen_coords(center)
          inside = sp.x >= rx0 && sp.x <= rx1 && sp.y >= ry0 && sp.y <= ry1
          removed += 1 if inside
          inside
        end
      end
      unless @label_faces.empty?
        @label_faces = @label_faces.reject do |item|
          face = item[:face]
          next true unless face && face.valid?

          sp = view.screen_coords(face.bounds.center.transform(item[:transform]))
          inside = sp.x >= rx0 && sp.x <= rx1 && sp.y >= ry0 && sp.y <= ry1
          removed += 1 if inside
          inside
        end
      end

      Sketchup.status_text = "Da bo #{removed} chi tiet khoi bo chon (con #{@multi_faces.length + @multi_markers.length + @label_pk_items.length})."
    rescue
      nil
    end

    def modifier?(flags, kind)
      mask = kind == :ctrl ? COPY_MODIFIER_MASK : CONSTRAIN_MODIFIER_MASK
      (flags & mask) != 0
    rescue
      false
    end

    # Shift+click: BO chi tiet khoi bo chon (mat hoac nhan).
    def handle_shift_click(x, y, view)
      pks = @leaders.renameable_markers_at_label(x, y)
      unless pks.empty?
        removed = 0
        pks.each do |marker|
          removed += 1 if @multi_markers.delete(marker.entityID)
        end
        Sketchup.status_text = "Da bo #{removed} PK khoi bo chon (con #{@multi_markers.length})."
        return
      end

      ctx = Picker.pick(view, x, y)
      if ctx && ctx[:kind] == :face
        if @multi_faces.delete(ctx[:face].entityID)
          Sketchup.status_text = "Da bo mat khoi bo chon (con #{@multi_faces.length})."
        end
      elsif ctx && ctx[:kind] == :marker
        if @multi_markers.delete(ctx[:marker].entityID)
          Sketchup.status_text = "Da bo PK khoi bo chon (con #{@multi_markers.length})."
        end
      end
    end

    # Ctrl+click: chon them mat obj hoac nhan (toggle). Chon duoc ca phu kien ABF co ten.
    def handle_ctrl_click(x, y, view)
      pks = @leaders.renameable_markers_at_label(x, y)
      unless pks.empty?
        pks.each do |marker|
          id = marker.entityID
          if @multi_markers.key?(id)
            @multi_markers.delete(id)
          else
            @multi_markers[id] = marker
          end
        end
        Sketchup.status_text = "Da chon #{@multi_markers.length} PK — click PK/nhan khac de doi ten ca loat."
        return
      end
      if @leaders.over_label?(x, y)
        Sketchup.status_text = 'Nhan nay khong co phu kien doi ten duoc.'
        return
      end

      ctx = Picker.pick(view, x, y)
      if ctx && ctx[:kind] == :marker
        marker = ctx[:marker]
        return unless MH_PK_Addon.pk_marker?(marker)

        id = marker.entityID
        @multi_markers.key?(id) ? @multi_markers.delete(id) : @multi_markers[id] = marker
        Sketchup.status_text = "Da chon #{@multi_markers.length} PK — click PK/nhan khac de doi ten ca loat."
      elsif ctx && ctx[:kind] == :face
        face = ctx[:face]
        id = face.entityID
        if @multi_faces.key?(id)
          @multi_faces.delete(id)
        else
          @multi_faces[id] = ctx.merge(face_center: face.bounds.center, face_normal: face.normal)
        end
        Sketchup.status_text = "Da chon #{@multi_faces.length} mat — click 1 mat (khong Ctrl) de add PK vao tat ca."
      end
    end

    def onKeyDown(key, _repeat, flags, view)
      if @editing
        return handle_edit_key(key, flags, view)
      end

      if key == 9 # Tab
        flip_face(view)
        return true
      end
      false
    end

    # Go tu o Measurements (ho tro tieng Viet co dau qua IME).
    def onUserText(text, view)
      str = text.to_s.strip
      return if str.empty?

      @edit_text = str
      @editing = true
      commit_edit(view)
    end

    def onCancel(_reason, view)
      if @editing
        cancel_edit(view)
      elsif !@multi_faces.empty? || !@multi_markers.empty? || !@label_faces.empty? || !@label_pk_items.empty?
        @multi_faces.clear
        @multi_markers.clear
        @label_faces = []
        @label_pk_items = []
        @label_cluster_key = nil
        set_status
        view.invalidate
      elsif @armed
        disarm
        view.invalidate
      else
        view.model.select_tool(nil)
      end
    end

    def onMouseLeave(view)
      return unless @hover

      @hover = nil
      @cycle = nil
      view.invalidate
    end

    def draw(view)
      refresh_ticks if @ticks_dirty

      if @hover && @hover[:kind] == :face
        face = current_face
        if face && face.valid?
          color = @armed ? HIGHLIGHT_ARMED : HIGHLIGHT_IDLE
          Picker.draw_highlight(view, face, @hover[:transform], color)
        end
      end
      draw_multi_faces(view)
      draw_label_faces(view)

      selected_ids = @multi_markers.empty? ? nil : @multi_markers.keys
      @leaders.draw(view, @hud.panel_rects(view), selected_ids)
      @hud.draw(view, hud_state)
      draw_edit_overlay(view)
      draw_drag_rect(view)
    rescue
      nil
    end

    EDIT_FILL = Sketchup::Color.new(255, 252, 235, 250)
    EDIT_BORDER = Sketchup::Color.new(235, 150, 30, 255)
    DRAG_FILL = Sketchup::Color.new(235, 80, 60, 35)
    DRAG_BORDER = Sketchup::Color.new(235, 80, 60, 255)

    # O dang sua ve de len chinh nhan duoc double-click (preview live tu o nhap).
    def draw_edit_overlay(view)
      return unless @editing && @edit_rect

      text = "#{@edit_text}|"
      w = [text.length * 6.0 + 18, @edit_rect[:w]].max
      r = { x: @edit_rect[:x], y: @edit_rect[:y], w: w, h: @edit_rect[:h] }
      pts = [
        Geom::Point3d.new(r[:x], r[:y], 0),
        Geom::Point3d.new(r[:x] + r[:w], r[:y], 0),
        Geom::Point3d.new(r[:x] + r[:w], r[:y] + r[:h], 0),
        Geom::Point3d.new(r[:x], r[:y] + r[:h], 0)
      ]
      view.drawing_color = EDIT_FILL
      view.draw2d(GL_POLYGON, pts)
      view.line_width = 2
      view.drawing_color = EDIT_BORDER
      view.draw2d(GL_LINE_LOOP, pts)
      options = { size: 7, color: Sketchup::Color.new(30, 30, 36, 255), font: 'Arial' }
      view.draw_text(Geom::Point3d.new(r[:x] + 9, r[:y] + 4, 0), text, options)
    rescue
      nil
    end

    # Khung quet shift de bo chon vung.
    def draw_drag_rect(view)
      return unless @drag_start && @drag_cur

      x0, y0 = @drag_start
      x1, y1 = @drag_cur
      pts = [
        Geom::Point3d.new(x0, y0, 0),
        Geom::Point3d.new(x1, y0, 0),
        Geom::Point3d.new(x1, y1, 0),
        Geom::Point3d.new(x0, y1, 0)
      ]
      view.drawing_color = DRAG_FILL
      view.draw2d(GL_POLYGON, pts)
      view.line_width = 1
      view.drawing_color = DRAG_BORDER
      view.draw2d(GL_LINE_LOOP, pts)
    rescue
      nil
    end

    HIGHLIGHT_HOST = Sketchup::Color.new(20, 95, 230, 140)
    HIGHLIGHT_HOST_EDGE = Sketchup::Color.new(0, 65, 210, 255)
    BBOX_EDGES = [
      [0, 1], [1, 3], [3, 2], [2, 0], # day
      [4, 5], [5, 7], [7, 6], [6, 4], # noc
      [0, 4], [1, 5], [2, 6], [3, 7]  # canh dung
    ].freeze

    HIGHLIGHT_PK = Sketchup::Color.new(255, 190, 0, 255) # obj PK chua att: VANG, xuyen che

    def draw_face_overlay(view, face, world_tr, fill_color, edge_color, line_width = 4)
      return unless face && face.valid?

      pts = face.outer_loop.vertices.map { |v| v.position.transform(world_tr) }
      tessellated = true
      fill =
        begin
          Geom.tesselate(pts)
        rescue
          tessellated = false
          pts
        end
      fill2d = fill.map do |pt|
        sp = view.screen_coords(pt)
        Geom::Point3d.new(sp.x, sp.y, 0)
      end
      loop2d = pts.map do |pt|
        sp = view.screen_coords(pt)
        Geom::Point3d.new(sp.x, sp.y, 0)
      end

      view.drawing_color = fill_color
      if fill2d.length >= 3
        view.draw2d(tessellated ? GL_TRIANGLES : GL_POLYGON, fill2d)
      end
      view.line_width = line_width
      view.drawing_color = edge_color
      view.draw2d(GL_LINE_LOOP, loop2d) if loop2d.length >= 2
    rescue
      nil
    end

    # Mat cha chua PK (mau theo vien xanh) + chinh obj PK (vang, ve 2D → xuyen vat che).
    def draw_label_faces(view)
      @label_faces.each do |item|
        draw_face_overlay(view, item[:face], item[:transform], HIGHLIGHT_HOST, HIGHLIGHT_HOST_EDGE, 4)
      end

      draw_label_pk_objects(view)
    rescue
      nil
    end

    # Bbox cua CHINH obj PK mang attribute — mau vang, draw2d nen bi che van thay.
    def draw_label_pk_objects(view)
      @label_pk_items.each do |item|
        marker = item[:marker]
        next unless marker && MH_PK_Addon.live_entity?(marker)

        bb = marker.bounds
        corners2d = (0..7).map do |i|
          pt = bb.corner(i).transform(item[:parent_tr])
          sp = view.screen_coords(pt)
          Geom::Point3d.new(sp.x, sp.y, 0)
        end

        segments = []
        BBOX_EDGES.each do |a, b|
          segments << corners2d[a]
          segments << corners2d[b]
        end
        view.line_width = 4
        view.drawing_color = HIGHLIGHT_PK
        view.draw2d(GL_LINES, segments)
      end
    rescue
      nil
    end

    def draw_multi_faces(view)
      @multi_faces.each_value do |ctx|
        face = ctx[:face]
        next unless face && face.valid?

        draw_face_overlay(view, face, ctx[:transform], HIGHLIGHT_MULTI, HIGHLIGHT_MULTI_EDGE, 4)
      end
    rescue
      nil
    end

    def getExtents
      MH_PK_Addon.model.bounds
    end

    # Goi tu ModelObserver sau commit/undo/redo.
    def external_change
      @leaders.invalidate!
      @ticks_dirty = true
      view = MH_PK_Addon.model.active_view
      view.invalidate if view
    rescue
      nil
    end

    # ---------- callbacks tu o nhap HtmlDialog ----------

    def edit_text_changed(value)
      return unless @editing

      @edit_text = value.to_s
      view = MH_PK_Addon.model.active_view
      view.invalidate if view
    rescue
      nil
    end

    def edit_text_committed(value)
      return unless @editing

      @edit_text = value.to_s
      view = MH_PK_Addon.model.active_view
      commit_edit(view) if view
    rescue
      nil
    end

    def edit_box_cancelled
      return unless @editing

      view = MH_PK_Addon.model.active_view
      cancel_edit(view) if view
    rescue
      nil
    end

    private

    def hud_state
      {
        armed: @armed, length_mode: @length_mode, product_code: @product_code,
        editing: @editing && @edit_markers.nil?, edit_text: @edit_text,
        session_ops: @session_ops
      }
    end

    def hover_sig(ctx)
      return nil unless ctx

      if ctx[:kind] == :marker
        [:marker, ctx[:marker].entityID]
      else
        [:face, ctx[:face].entityID, ctx[:target] ? ctx[:target].entityID : 0]
      end
    rescue
      nil
    end

    def current_face
      return nil unless @hover && @hover[:kind] == :face
      return @hover[:face] unless @cycle

      @cycle[@flip_index % @cycle.length]
    end

    def flip_face(view)
      return unless @hover && @hover[:kind] == :face

      @cycle ||= Picker.face_cycle(@hover)
      return if @cycle.length <= 1

      @flip_index = (@flip_index + 1) % @cycle.length
      Picker.clear_cache
      set_status
      view.invalidate
    end

    # ---------- inline edit ----------

    # markers: nil = sua thong tin PK dang arm (o giua-duoi); co markers = sua ten nhan.
    # O nhap HtmlDialog bat tron ban phim (khong dinh shortcut SketchUp) va live-sync de
    # ve preview ngay tren o/nhan dang sua.
    def start_edit(view, markers: nil, rect: nil, initial: nil)
      @editing = true
      @edit_markers = markers
      @edit_rect = rect
      @edit_text = initial || (@armed ? @hud.display_label_for_armed(@armed) : '')

      tool = self
      MH_PK_Addon.show_edit_box(
        @edit_text,
        on_change: proc { |value| tool.edit_text_changed(value) },
        on_commit: proc { |value| tool.edit_text_committed(value) },
        on_cancel: proc { tool.edit_box_cancelled }
      )
      Sketchup.status_text = 'Go ten PK vao o nhap (Enter = xong, Esc = huy).'
      view.invalidate
    end

    def handle_edit_key(key, flags, view)
      case key
      when 13 # Enter
        commit_edit(view)
        return true
      when 27 # Esc
        cancel_edit(view)
        return true
      when 8 # Backspace
        @edit_text = @edit_text[0...-1].to_s
        view.invalidate
        return true
      end

      char = key_to_char(key, flags)
      if char
        @edit_text += char
        view.invalidate
        return true
      end
      true # nuot het phim khi dang edit
    end

    def key_to_char(key, flags)
      shift =
        begin
          (flags & CONSTRAIN_MODIFIER_MASK) != 0
        rescue
          false
        end

      case key
      when 32 then ' '
      when 48..57 then (key - 48).to_s
      when 96..105 then (key - 96).to_s
      when 65..90
        ch = (key).chr
        shift ? ch : ch.downcase
      when 109, 189 then '-'
      when 110, 190 then '.'
      when 188 then ','
      when 191 then '/'
      when 111 then '/'
      when 106 then '*'
      when 107 then '+'
      else
        nil
      end
    rescue
      nil
    end

    def commit_edit(view)
      text = @edit_text.to_s.strip
      @editing = false
      markers = @edit_markers
      @edit_markers = nil
      @edit_rect = nil
      MH_PK_Addon.close_edit_box
      if text.empty?
        set_status
        view.invalidate
        return
      end

      parts = text.split(' - ')
      name = parts[0].to_s.strip
      spec = parts.length > 1 ? parts[1..-1].join(' - ').strip : ''

      if markers && !markers.empty?
        rename_markers_with(markers, name, spec)
      elsif @armed
        @armed[:name] = name
        @armed[:spec] = spec
      else
        @armed = {
          name: name, spec: spec, note: '', section: '', excel_key: '',
          product_code: @product_code, length_mm: 0.0, source: :manual, row_index: -1
        }
      end
      set_status
      view.invalidate
    end

    # Doi ten truc tiep tu double-click nhan (khong can arm).
    def rename_markers_with(markers, name, spec)
      data = {
        name: name, spec: spec, note: '', section: '', excel_key: '', qty: 1,
        shape: MH_PK_Addon.default_shape, size_mm: MH_PK_Addon.default_size_mm,
        product_code: @product_code, length_mode: false, length_mm: 0
      }
      to_label = MH_PK_Addon.display_name(name, spec)
      renamed = 0
      Array(markers).each do |m|
        next unless MH_PK_Addon.live_entity?(m)
        next if MH_PK_Addon.accessory_label(m) == to_label

        MH_PK_Addon.rename_accessory(m, data) rescue next
        renamed += 1
        @session_ops += 1
      end
      @label_faces = []
      @label_pk_items = []
      @label_cluster_key = nil
      @leaders.invalidate!
      @ticks_dirty = true
      Sketchup.status_text = "Da doi ten #{renamed} phu kien → #{to_label}"
    rescue => e
      UI.messagebox(e.message)
    end

    def cancel_edit(view)
      @editing = false
      @edit_text = ''
      @edit_markers = nil
      @edit_rect = nil
      MH_PK_Addon.close_edit_box
      set_status
      view.invalidate
    end

    # ---------- product / panels ----------

    def detect_or_reuse_product
      target = MH_PK_Addon.selected_target
      code = target ? MH_PK_Addon.detect_product_code(target) : ''
      code = @@last_product if code.to_s.empty?
      @product_code = MH_PK_Addon.product_code_base(code)
      @@last_product = @product_code unless @product_code.empty?
    end

    def adopt_product_from(target, view)
      code = MH_PK_Addon.product_code_base(MH_PK_Addon.detect_product_code(target))
      if code.empty?
        Sketchup.status_text = 'Object nay khong co ma SP — chon object khac hoac arm PK tu thu vien.'
        return
      end
      return if code == @product_code

      @product_code = code
      @@last_product = code
      @leaders.product_filter = @product_code
      load_panels
      set_status
      view.invalidate
    end

    def load_panels
      rows = @product_code.empty? ? [] : MH_PK_Addon.thongke_all_excel_pk_rows(@product_code)
      @hud.excel_rows = Array(rows).map { |row| build_panel_row(row) }
      @hud.lib_names = MH_PK_Addon.accessory_names_from_file(MH_PK_Addon.default_xlsx_path)
      @hud.reset_scroll
      refresh_ticks
    end

    def build_panel_row(row)
      raw = row[:raw].is_a?(Hash) ? row[:raw] : row
      section = (raw[:section] || raw['section']).to_s.strip
      spec = row[:spec].to_s.strip
      spec = (raw[:spec] || raw['spec']).to_s.strip if spec.empty?
      {
        name: row[:name].to_s.strip,
        spec: spec,
        note: row[:note].to_s.strip,
        qty: row[:qty].to_i,
        section: section,
        ten_sp: row[:ten_sp].to_s.strip.empty? ? MH_PK_Addon.row_value(raw, :ten_sp, 'ten_sp').to_s.strip : row[:ten_sp].to_s.strip,
        raw: raw,
        length: MH_PK_Addon.length_excel_row?(raw),
        excel_key: MH_PK_Addon.trace_build_excel_match_key(
          product_code: @product_code, kind: 'PK',
          excel_name: row[:name].to_s, spec: spec, section: section
        ),
        ticked: false
      }
    end

    def refresh_ticks
      # them phu kien ABF (ray, ban le...) vao nguon tick — de dong excel van tick
      # khi doi ten object ABF sang ten excel
      extra = @leaders.markers.select do |m|
        m[:abf] && (@product_code.empty? || m[:sp].to_s.empty? || m[:sp].to_s == @product_code)
      end
      MH_PK_Addon.apply_tick_state(@hud.excel_rows, @product_code, extra)
      @ticks_dirty = false
    rescue
      @ticks_dirty = false
    end

    # ---------- arm / actions ----------

    def handle_hud_action(action, view)
      case action[:type]
      when :arm_excel
        commit_edit(view) if @editing
        arm_excel_row(action[:index])
      when :arm_lib
        commit_edit(view) if @editing
        arm_lib_row(action[:index])
      when :toggle_length
        @length_mode = !@length_mode
      when :open_settings
        open_settings(view)
      when :cancel_session
        cancel_session(view)
        return
      when :edit_armed
        @editing ? commit_edit(view) : start_edit(view)
        return
      end
      set_status
    end

    def open_settings(view)
      tool = self
      MH_PK_Addon.show_hud_settings_dialog do
        tool.external_change
        view.invalidate
      end
    rescue => e
      UI.messagebox(e.message)
    end

    # Huy bo moi thay doi (add/doi ten) cua phien dang dung: undo dung so operation da commit.
    def cancel_session(view)
      if @session_ops <= 0
        Sketchup.status_text = 'Khong co thay doi nao trong phien nay de huy.'
        return
      end

      answer = UI.messagebox("Huy bo #{@session_ops} thay doi cua phien nay?", MB_YESNO)
      return unless answer == IDYES

      n = @session_ops
      @session_ops = 0
      n.times { Sketchup.undo }
      @armed = nil
      @multi_faces.clear
      @multi_markers.clear
      @label_faces = []
      @label_pk_items = []
      @label_cluster_key = nil
      @leaders.invalidate!
      load_panels
      set_status
      Sketchup.status_text = "Da huy #{n} thay doi cua phien."
      view.invalidate
    rescue => e
      UI.messagebox(e.message)
    end

    def arm_excel_row(index)
      row = @hud.excel_rows[index]
      return unless row

      if @armed && @armed[:source] == :excel && @armed[:row_index] == index
        disarm
        return
      end

      @armed = {
        name: row[:name],
        spec: row[:spec],
        note: row[:note],
        section: row[:section],
        ten_sp: row[:ten_sp],
        excel_key: row[:excel_key],
        product_code: @product_code,
        length_mm: MH_PK_Addon.excel_row_length_mm(row[:raw]),
        source: :excel,
        row_index: index
      }
      @length_mode = true if row[:length]
    end

    def arm_lib_row(index)
      name = @hud.lib_names[index]
      return unless name

      if @armed && @armed[:source] == :lib && @armed[:row_index] == index
        disarm
        return
      end

      @armed = {
        name: name.to_s,
        spec: '',
        note: '',
        section: '',
        ten_sp: '',
        excel_key: '',
        product_code: @product_code,
        length_mm: 0.0,
        source: :lib,
        row_index: index
      }
    end

    def disarm
      @armed = nil
      set_status
    end

    # ---------- add / rename ----------

    def armed_data
      {
        name: @armed[:name],
        spec: @armed[:spec],
        note: @armed[:note],
        section: @armed[:section],
        ten_sp: @armed[:ten_sp],
        excel_key: @armed[:excel_key],
        qty: 1,
        shape: MH_PK_Addon.default_shape,
        size_mm: MH_PK_Addon.default_size_mm,
        product_code: @armed[:product_code].to_s.empty? ? @product_code : @armed[:product_code],
        length_mode: @length_mode,
        length_mm: @armed[:length_mm].to_f
      }
    end

    # Ctx Ctrl-chon co the mat face sau make_unique → tim lai theo tam/phap tuyen da luu.
    def resolve_ctx_face(ctx)
      face = ctx[:face]
      return ctx if face && face.valid?
      return nil unless ctx[:face_center]

      ents = MH_PK_Addon.target_entities(ctx[:target])
      return nil unless ents

      found = MH_PK_Addon.refind_face(ents, ctx[:face_center], ctx[:face_normal])
      found ? ctx.merge(face: found) : nil
    rescue
      nil
    end

    def perform_add(view)
      return unless @armed && @hover && @hover[:kind] == :face

      face = current_face
      return unless face && face.valid?

      contexts = [@hover.merge(face: face)]
      @multi_faces.each_value do |ctx|
        next if ctx[:face] && ctx[:face].entityID == face.entityID

        resolved = resolve_ctx_face(ctx)
        contexts << resolved if resolved
      end

      added = 0
      contexts.each do |ctx|
        marker = MH_PK_Addon.add_armed_pk_to_face(ctx, armed_data) rescue nil
        if marker
          added += 1
          @session_ops += 1
        end
      end
      return if added.zero?

      @multi_faces.clear
      @leaders.invalidate!
      @ticks_dirty = true
      adopt_product_from(@hover[:target], view) if @product_code.empty?
      Sketchup.status_text = "Da add #{added} PK: #{@armed[:name]} — click tiep de add nua, Esc de bo chon."
    rescue => e
      UI.messagebox(e.message)
    end

    def perform_rename(marker, view)
      unless @armed
        label = MH_PK_Addon.accessory_label(marker)
        Sketchup.status_text = "PK: #{label} — arm 1 dong PK khac roi click vao day de doi ten."
        return
      end

      targets = @multi_markers.values.select { |m| MH_PK_Addon.live_entity?(m) }
      targets << marker unless targets.any? { |m| m.entityID == marker.entityID }
      perform_rename_list(targets, view)
    end

    def perform_rename_list(markers, view)
      unless @armed
        Sketchup.status_text = 'Arm 1 dong PK (excel/thu vien) truoc roi click nhan/PK de doi ten.'
        return
      end

      to_label = MH_PK_Addon.display_name(@armed[:name], @armed[:spec])
      renamed = 0
      Array(markers).each do |m|
        next unless MH_PK_Addon.live_entity?(m)
        next if MH_PK_Addon.accessory_label(m) == to_label

        MH_PK_Addon.rename_accessory(m, armed_data) rescue next
        renamed += 1
        @session_ops += 1
      end

      if renamed.zero?
        Sketchup.status_text = "PK da dung ten: #{to_label}."
        return
      end

      @multi_markers.clear
      @label_faces = []
      @label_pk_items = []
      @label_cluster_key = nil
      @leaders.invalidate!
      @ticks_dirty = true
      Sketchup.status_text = "Da doi ten #{renamed} PK → #{to_label}"
      view.invalidate
    rescue => e
      UI.messagebox(e.message)
    end

    def set_status
      Sketchup.status_text =
        if @editing
          'Dang go ten PK — Enter: xong, Esc: huy.'
        elsif @armed
          mode = @length_mode ? 'md' : 'SL'
          "[#{mode}] Click mat: add #{@armed[:name]} | Ctrl+click: chon them mat/nhan | Tab: lat mat | Esc: bo chon"
        elsif @product_code.empty?
          'Click vao object co ma SP de load PK excel, hoac chon PK tu thu vien (trai duoi).'
        else
          "SP #{@product_code} — chon PK tu bang duoi de bat dau."
        end
    rescue
      nil
    end

    # ---------- observer ----------

    def attach_observer
      @observer = PKHudModelObserver.new(self)
      MH_PK_Addon.model.add_observer(@observer)
    rescue
      @observer = nil
    end

    def detach_observer
      MH_PK_Addon.model.remove_observer(@observer) if @observer
      @observer = nil
    rescue
      @observer = nil
    end
  end

  def self.activate_hud_tool
    model.select_tool(PKHudTool.new)
  rescue => e
    UI.messagebox("Khong mo duoc MH PK HUD: #{e.message}")
  end
end
