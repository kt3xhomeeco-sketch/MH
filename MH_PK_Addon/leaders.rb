# encoding: utf-8
# MH_PK_Addon — nhan phu kien: PK marker + phu kien ABF (ban le, ray, minifix, den led, suot ao...).
# Khong ve duong leader — nhan dat ngay BEN CANH cum obj (trai/phai tuy nua man hinh).
# 2 che do theo zoom: xa = group theo TEN (du tat ca loai), gan = tach tung cai.
# Click nhan → highlight mat dang chua phu kien; hover/Ctrl-chon co highlight.

module MH_PK_Addon
  class Leaders
    CLUSTER_PX = 60          # gom cum khong gian o che do chi tiet
    MAX_PER_SIDE_DETAIL = 14
    DETAIL_MM_PER_PX = 0.6   # 1px <= 0.6mm → che do chi tiet
    DETAIL_MAX_ONSCREEN = 8
    FONT_SIZE = 7
    CHAR_W = 6.0
    LABEL_PAD = 18
    LABEL_H = FONT_SIZE + 10
    LABEL_LINE_H = FONT_SIZE + 5
    LABEL_OFFSET = 10        # khoang cach nhan ↔ bien obj
    LABEL_GAP = 6
    LABEL_MIN_W = 72
    LABEL_MAX_W = 220
    LABEL_MAX_LINES = 2
    MAX_HOST_FACES = 40

    COL_LABEL_FILL = Sketchup::Color.new(255, 255, 255, 240)
    COL_LABEL_BORDER = Sketchup::Color.new(90, 90, 95, 255)
    COL_LABEL_TEXT = Sketchup::Color.new(40, 40, 45, 255)
    COL_LABEL_HOVER = Sketchup::Color.new(214, 226, 248, 250)
    COL_LABEL_HOVER_BORDER = Sketchup::Color.new(60, 110, 200, 255)
    COL_LABEL_SELECTED = Sketchup::Color.new(255, 240, 215, 250)
    COL_LABEL_SELECTED_BORDER = Sketchup::Color.new(235, 150, 30, 255)

    # Cac attr ABF danh dau phu kien (tu FittingsTool cua ABF)
    ABF_FITTING_KEYS = %w[
      is-minifix-part-a is-minifix-part-b
      is-hinge-part-a is-hinge-part-b
      is-screw is-side-drill is-side-drill-depth
      is-lockdowel-line-1-red is-lockdowel-line-2-blue
      is-spring-dowel-pin-profile-on-red is-spring-dowel-pin-profile-on-blue
      is-if-openline
    ].freeze

    ABF_LABEL_FALLBACKS = {
      'is-minifix-part-a' => 'Minifix', 'is-minifix-part-b' => 'Minifix',
      'is-hinge-part-a' => 'Ban le', 'is-hinge-part-b' => 'Ban le',
      'is-screw' => 'Vit', 'is-side-drill' => 'Khoan hong', 'is-side-drill-depth' => 'Khoan hong',
      'is-lockdowel-line-1-red' => 'Lockdowel', 'is-lockdowel-line-2-blue' => 'Lockdowel',
      'is-spring-dowel-pin-profile-on-red' => 'Chot lo xo', 'is-spring-dowel-pin-profile-on-blue' => 'Chot lo xo',
      'is-if-openline' => 'IF Peanut'
    }.freeze

    # Chi hien nhan cua obj thuoc ma SP nay (rong = hien tat ca).
    attr_accessor :product_filter

    def initialize
      @markers = nil
      @dirty = true
      @last_cam_sig = nil
      @clusters = []
      @hover_index = nil
      @product_filter = ''
    end

    def product_filter=(value)
      normalized = MH_PK_Addon.product_code_base(value)
      return if normalized == @product_filter

      @product_filter = normalized
      invalidate_layout!
    end

    # Ma SP nhanh tu ten entity/definition (khong quet attr de giu toc do).
    def quick_sp_code(entity)
      text = entity.name.to_s
      text += " #{entity.definition.name}" if entity.respond_to?(:definition) && entity.definition
      code = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
        MH::NameGrammar.first_product(text)
      else
        text[/([A-Z]+\d+[A-Z]?(?:\.\d+)?)/i, 1]
      end
      code.to_s.empty? ? nil : MH_PK_Addon.product_code_base(code)
    rescue
      nil
    end

    def invalidate!
      @dirty = true
      @markers = nil
    end

    def invalidate_layout!
      @last_cam_sig = nil
    end

    # ---------- marker inventory ----------

    def markers
      return @markers if @markers && !@dirty

      @markers = collect_markers
      @dirty = false
      @markers
    end

    def abf_fitting_key(entity)
      ABF_FITTING_KEYS.find { |key| entity.get_attribute('ABF', key) }
    rescue
      nil
    end

    # Object ABF co ten thong ke (gom ca intersect: den led, suot ao, nep...).
    def abf_named?(entity)
      return true unless entity.get_attribute('ABF', 'statistical-name').to_s.strip.empty?
      return true unless entity.get_attribute('ABF', 'setting-name').to_s.strip.empty?
      entity.get_attribute('ABF', 'is-intersect') == true
    rescue
      false
    end

    def abf_fitting_label(entity, fitting_key)
      value = entity.get_attribute('ABF', 'setting-name').to_s.strip rescue ''
      value = entity.get_attribute('ABF', 'statistical-name').to_s.strip if value.empty?
      value = ABF_LABEL_FALLBACKS[fitting_key].to_s if value.empty? && fitting_key
      value.empty? ? 'Phu kien ABF' : value
    rescue
      'Phu kien ABF'
    end

    def abf_statistical_object?(entity)
      entity.get_attribute('ABF', 'is-statistical-object') == true
    rescue
      false
    end

    # Gom PK marker cua minh + phu kien ABF (fitting / statistical / intersect nhu den led, suot ao).
    # Moi item mang theo: ma SP gan nhat tren chuoi cha (sp), transform NGOAI parent (parent_outer_tr)
    # de ve bbox cua obj chua xuyen qua vat che.
    def collect_markers
      found = []
      visited = {}
      walk = lambda do |ents, parent_tr, parent, parent_outer_tr, sp_code|
        ents.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          next unless MH_PK_Addon.live_entity?(entity)

          if MH_PK_Addon.pk_marker?(entity)
            marker_sp = MH_PK_Addon.product_code_base(entity.get_attribute('MH_Thongke', 'product_code'))
            found << {
              marker: entity, parent: parent, parent_tr: parent_tr, parent_outer_tr: parent_outer_tr,
              local_center: entity.bounds.center,
              world_center: entity.bounds.center.transform(parent_tr),
              label: MH_PK_Addon.accessory_label(entity), abf: false,
              sp: marker_sp.empty? ? sp_code : marker_sp
            }
            next
          end

          fitting_key = abf_fitting_key(entity)
          if fitting_key || abf_statistical_object?(entity) || abf_named?(entity)
            found << {
              marker: entity, parent: parent, parent_tr: parent_tr, parent_outer_tr: parent_outer_tr,
              local_center: entity.bounds.center,
              world_center: entity.bounds.center.transform(parent_tr),
              label: abf_fitting_label(entity, fitting_key), abf: true,
              sp: sp_code
            }
            next
          end

          child = MH_PK_Addon.target_entities(entity)
          next unless child

          key = child.object_id
          next if visited[key]

          visited[key] = true
          child_sp = quick_sp_code(entity) || sp_code
          walk.call(child, parent_tr * entity.transformation, entity, parent_tr, child_sp)
        end
      end
      walk.call(MH_PK_Addon.model.entities, Geom::Transformation.new, nil, Geom::Transformation.new, nil)
      append_virtual_markers(found)
      found
    rescue
      []
    end

    # Nhan VIRTUAL (Nguon LED, Thanh nhom LED, Bas treo suot ao...) bam theo object that:
    # nguon/thanh nhom → bam obj co ten LED; bas treo → bam obj Suot ao. Khong doi ten duoc.
    def append_virtual_markers(found)
      rows = MH_PK_Addon.thongke_virtual_rows_cached(nil) rescue []
      return found if rows.empty?

      led_anchor = {}
      suot_anchor = {}
      found.each do |m|
        next if m[:virtual]

        sp = m[:sp].to_s
        norm = MH_PK_Addon.search_text(m[:label])
        led_anchor[sp] ||= m if norm.include?('led')
        suot_anchor[sp] ||= m if norm.include?('suot ao')
      end
      return found if led_anchor.empty? && suot_anchor.empty?

      rows.each do |row|
        norm = MH_PK_Addon.search_text(row[:name])
        sp = row[:product].to_s
        anchor =
          if norm.include?('suot ao') || norm.include?('bas treo')
            suot_anchor[sp] || suot_anchor.values.first
          else
            led_anchor[sp] || led_anchor.values.first
          end
        next unless anchor

        found << anchor.merge(label: row[:name], virtual: true)
      end
      found
    rescue
      found
    end

    # ---------- clustering ----------

    def camera_signature(view)
      cam = view.camera
      [cam.eye.to_a, cam.direction.to_a, cam.up.to_a, view.vpwidth, view.vpheight].hash
    rescue
      rand(1_000_000)
    end

    def clusters_for(view, avoid_rects = [])
      sig = camera_signature(view)
      return @clusters if sig == @last_cam_sig && @markers && !@dirty

      @last_cam_sig = sig
      @clusters = compute_clusters(view)
      layout_labels(view, @clusters, avoid_rects)
      @hover_index = nil
      @clusters
    end

    def onscreen_markers(view)
      cam = view.camera
      eye = cam.eye
      dir = cam.direction
      vpw = view.vpwidth
      vph = view.vpheight

      result = []
      markers.each do |m|
        next unless MH_PK_Addon.live_entity?(m[:marker])
        next if MH_PK_Addon.hud_hidden_label?(m[:label])
        # chi hien obj thuoc ma SP dang chon; obj KHONG truy duoc SP van hien
        next if !@product_filter.to_s.empty? && !m[:sp].to_s.empty? && m[:sp].to_s != @product_filter
        next if eye.vector_to(m[:world_center]).dot(dir) <= 0

        sp = view.screen_coords(m[:world_center])
        next if sp.x < -50 || sp.x > vpw + 50 || sp.y < -50 || sp.y > vph + 50

        result << m.merge(sx: sp.x, sy: sp.y)
      end
      result
    rescue
      []
    end

    def detail_mode?(view, onscreen)
      return true if onscreen.length <= DETAIL_MAX_ONSCREEN

      cx = onscreen.sum { |m| m[:world_center].x } / onscreen.length
      cy = onscreen.sum { |m| m[:world_center].y } / onscreen.length
      cz = onscreen.sum { |m| m[:world_center].z } / onscreen.length
      center = Geom::Point3d.new(cx, cy, cz)
      mm_per_px = view.pixels_to_model(1, center) * 25.4
      mm_per_px <= DETAIL_MM_PER_PX
    rescue
      false
    end

    def compute_clusters(view)
      onscreen = onscreen_markers(view)
      return [] if onscreen.empty?

      if detail_mode?(view, onscreen)
        cap_clusters(spatial_clusters(onscreen), view.vpwidth)
      else
        name_clusters(onscreen)
      end
    rescue
      []
    end

    # Zoom xa: group theo TEN — hien du tat ca loai.
    def name_clusters(onscreen)
      onscreen.group_by { |m| m[:label] }.map do |label, list|
        cx = list.sum { |m| m[:sx] } / list.length
        cy = list.sum { |m| m[:sy] } / list.length
        anchor = list.min_by { |m| (m[:sx] - cx)**2 + (m[:sy] - cy)**2 }
        text = list.length > 1 ? "#{label} (x#{list.length})" : label.to_s
        { items: list, sx: anchor[:sx], sy: anchor[:sy], label: text }
      end
    end

    # Zoom gan: gom cum khong gian nho.
    def spatial_clusters(onscreen)
      buckets = Hash.new { |h, k| h[k] = [] }
      onscreen.each do |m|
        buckets[[(m[:sx] / CLUSTER_PX).to_i, (m[:sy] / CLUSTER_PX).to_i]] << m
      end

      clusters = buckets.values.map { |list| build_cluster(list) }

      merged = []
      clusters.sort_by! { |c| [c[:sx], c[:sy]] }
      clusters.each do |cluster|
        near = merged.find { |c| (c[:sx] - cluster[:sx]).abs < CLUSTER_PX && (c[:sy] - cluster[:sy]).abs < CLUSTER_PX }
        if near
          merged[merged.index(near)] = merge_clusters(near, cluster)
        else
          merged << cluster
        end
      end
      merged
    end

    def cap_clusters(clusters, vpw)
      %i[left right].flat_map do |side|
        group = clusters.select { |c| (c[:sx] < vpw / 2) == (side == :left) }
        next group if group.length <= MAX_PER_SIDE_DETAIL

        group = group.sort_by { |c| [c[:items].any? { |m| !m[:abf] } ? 0 : 1, -c[:items].length] }
        visible = group.first(MAX_PER_SIDE_DETAIL - 1)
        rest = group - visible
        summary = build_cluster(rest.flat_map { |c| c[:items] })
        summary[:label] = "+#{rest.length} cum PK khac (zoom gan)"
        summary[:summary] = true
        visible + [summary]
      end
    rescue
      clusters
    end

    def build_cluster(list)
      sx = list.sum { |m| m[:sx] } / list.length
      sy = list.sum { |m| m[:sy] } / list.length
      { items: list, sx: sx, sy: sy, label: cluster_label(list) }
    end

    def merge_clusters(a, b)
      build_cluster(a[:items] + b[:items])
    end

    def cluster_label(list)
      counts = Hash.new(0)
      list.each { |m| counts[m[:label]] += 1 }
      top = counts.max_by { |_, count| count }
      label = top ? top[0].to_s : 'Phu kien'
      others = counts.length - 1
      label = "#{label} +#{others}" if others > 0
      label = "#{label} (x#{list.length})" if list.length > 1 && others <= 0
      label
    end

    # ---------- label layout: 2 cot nhan dat NGOAI bien trai/phai cua nhom obj ----------

    def layout_labels(view, clusters, avoid_rects)
      return if clusters.empty?

      vpw = view.vpwidth
      vph = view.vpheight

      # vung bien cua nhom obj = khoang sx min/max cua moi phu kien tren man hinh
      all_sx = clusters.flat_map { |c| c[:items].map { |m| m[:sx] } }
      bound_left = all_sx.min - 30
      bound_right = all_sx.max + 30
      mid = (bound_left + bound_right) / 2.0

      top_rects = avoid_rects.select { |r| r[:y] < vph / 2 }
      bottom_rects = avoid_rects.select { |r| r[:y] >= vph / 2 }
      top_limit = top_rects.map { |r| r[:y] + r[:h] }.max.to_f + 8
      top_limit = 8 if top_limit < 8
      bottom_limit = bottom_rects.map { |r| r[:y] }.min
      bottom_limit = vph - 8 if bottom_limit.nil?
      bottom_limit -= 4

      left = clusters.select { |c| c[:sx] <= mid }
      right = clusters - left
      stack_column(left, :left, bound_left, bound_right, vpw, top_limit, bottom_limit)
      stack_column(right, :right, bound_left, bound_right, vpw, top_limit, bottom_limit)
    end

    # Cot doc: ben trai → can phai nhan vao mep bound_left; ben phai → can trai vao bound_right.
    def stack_column(clusters, side, bound_left, bound_right, vpw, top_limit, bottom_limit)
      return if clusters.empty?

      clusters.sort_by! { |c| c[:sy] }
      last_bottom = top_limit - LABEL_GAP
      clusters.each do |cluster|
        metrics = label_metrics(cluster[:label])
        w = metrics[:w]
        h = metrics[:h]
        cluster[:label_lines] = metrics[:lines]
        x =
          if side == :left
            bound_left - LABEL_OFFSET - w
          else
            bound_right + LABEL_OFFSET
          end
        x = [[x, 4].max, vpw - w - 4].min

        y = [cluster[:sy] - h / 2.0, last_bottom + LABEL_GAP].max
        y = [y, top_limit].max
        cluster[:label_rect] = { x: x, y: y, w: w, h: h }
        last_bottom = y + h
      end

      # Neu cot tran xuong day viewport, day nguoc tu duoi len.
      # Cach cu clamp tung nhan ve bottom_limit lam cac nhan cuoi de len nhau.
      if last_bottom > bottom_limit
        next_top = bottom_limit
        clusters.reverse_each do |cluster|
          rect = cluster[:label_rect]
          next unless rect

          y = [rect[:y], next_top - rect[:h]].min
          rect[:y] = y
          next_top = y - LABEL_GAP
        end
      end
    end

    def label_metrics(label)
      lines = wrap_label_lines(label)
      longest = lines.map { |line| line.to_s.length }.max || 1
      w = longest * CHAR_W + LABEL_PAD
      w = [[w, LABEL_MIN_W].max, LABEL_MAX_W].min
      h = LABEL_LINE_H * lines.length + 8
      { lines: lines, w: w, h: h }
    end

    def wrap_label_lines(label)
      text = label.to_s.gsub(/\s+/, ' ').strip
      text = 'Phu kien' if text.empty?
      max_chars = [((LABEL_MAX_W - LABEL_PAD) / CHAR_W).floor, 12].max
      return [text] if text.length <= max_chars

      words = text.split(' ')
      lines = []
      current = ''
      words.each do |word|
        candidate = current.empty? ? word : "#{current} #{word}"
        if candidate.length <= max_chars
          current = candidate
        else
          lines << current unless current.empty?
          current = word
        end
        break if lines.length >= LABEL_MAX_LINES
      end
      lines << current unless current.empty? || lines.length >= LABEL_MAX_LINES

      if lines.empty?
        lines = [text[0, max_chars]]
      elsif lines.length >= LABEL_MAX_LINES && lines.join(' ').length < text.length
        limit = [max_chars - 3, 4].max
        lines[-1] = "#{lines[-1][0, limit].rstrip}..."
      end
      lines.map do |line|
        line = line.to_s
        next line if line.length <= max_chars

        "#{line[0, [max_chars - 3, 4].max].rstrip}..."
      end
    end

    def rects_overlap?(a, b)
      ax2 = a[:x] + a[:w]
      ay2 = a[:y] + a[:h]
      bx2 = b[:x] + b[:w]
      by2 = b[:y] + b[:h]
      a[:x] < bx2 && ax2 > b[:x] && a[:y] < by2 && ay2 > b[:y]
    end

    # ---------- hover ----------

    def update_hover(x, y)
      index = nil
      @clusters.each_with_index do |cluster, i|
        rect = cluster[:label_rect]
        next unless rect
        if x >= rect[:x] && x <= rect[:x] + rect[:w] && y >= rect[:y] && y <= rect[:y] + rect[:h]
          index = i
          break
        end
      end
      changed = index != @hover_index
      @hover_index = index
      changed
    end

    def hovered_cluster
      @hover_index ? @clusters[@hover_index] : nil
    end

    # ---------- host faces (mat dang chua phu kien) ----------

    # Tim mat cua parent ma phu kien nam tren (theo khoang cach toi mat phang).
    def host_faces_for_cluster(cluster)
      return cluster[:host_faces] if cluster[:host_faces]

      faces = []
      seen = {}
      tolerance = 10.0 / 25.4
      cluster[:items].each do |item|
        break if faces.length >= MAX_HOST_FACES

        parent = item[:parent]
        next unless parent && MH_PK_Addon.live_entity?(parent)

        ents = MH_PK_Addon.target_entities(parent)
        next unless ents

        center = item[:local_center]
        best = nil
        best_d = tolerance
        MH_PK_Addon.faces_for_placement(ents).each do |face|
          d = center.distance_to_plane(face.plane).to_f.abs rescue next
          if d < best_d
            best = face
            best_d = d
          end
        end
        next unless best

        key = best.entityID
        next if seen[key]

        seen[key] = true
        faces << { face: best, transform: item[:parent_tr] }
      end
      cluster[:host_faces] = faces
    rescue
      []
    end

    # Cac obj chua phu kien cua nhan (de highlight bbox xuyen vat che).
    def host_parents_for_cluster(cluster)
      return cluster[:host_parents] if cluster[:host_parents]

      parents = []
      seen = {}
      cluster[:items].each do |item|
        break if parents.length >= MAX_HOST_FACES

        parent = item[:parent]
        next unless parent && MH_PK_Addon.live_entity?(parent)

        key = parent.entityID
        next if seen[key]

        seen[key] = true
        parents << { parent: parent, outer_tr: item[:parent_outer_tr] }
      end
      cluster[:host_parents] = parents
    rescue
      []
    end

    # ---------- drawing ----------

    # selected_ids: Array entityID cua marker dang duoc Ctrl-chon.
    def draw(view, avoid_rects = [], selected_ids = nil)
      clusters_for(view, avoid_rects)
      @clusters.each_with_index do |cluster, i|
        selected = selected_ids && cluster[:items].any? { |m| selected_ids.include?(m[:marker].entityID) }
        draw_cluster(view, cluster, i == @hover_index, selected)
      end
    rescue
      nil
    end

    # Nhan chu nhat ben canh cum — khong co duong leader.
    def draw_cluster(view, cluster, hovered, selected = false)
      rect = cluster[:label_rect]
      return unless rect

      pts = [
        Geom::Point3d.new(rect[:x], rect[:y], 0),
        Geom::Point3d.new(rect[:x] + rect[:w], rect[:y], 0),
        Geom::Point3d.new(rect[:x] + rect[:w], rect[:y] + rect[:h], 0),
        Geom::Point3d.new(rect[:x], rect[:y] + rect[:h], 0)
      ]
      label_color = MH_PK_Addon.hud_label_color_for(cluster[:label]) rescue nil
      fill = selected ? COL_LABEL_SELECTED : (hovered ? COL_LABEL_HOVER : (label_color && label_color[:fill] ? label_color[:fill] : COL_LABEL_FILL))
      border = selected ? COL_LABEL_SELECTED_BORDER : (hovered ? COL_LABEL_HOVER_BORDER : (label_color && label_color[:border] ? label_color[:border] : COL_LABEL_BORDER))
      view.drawing_color = fill
      view.draw2d(GL_POLYGON, pts)
      view.line_width = (hovered || selected) ? 2 : 1
      view.drawing_color = border
      view.draw2d(GL_LINE_LOOP, pts)

      text_color = label_color && label_color[:text] ? label_color[:text] : COL_LABEL_TEXT
      options = { size: FONT_SIZE, color: text_color, font: 'Arial' }
      lines = cluster[:label_lines] || wrap_label_lines(cluster[:label])
      lines.each_with_index do |line, index|
        y = rect[:y] + 4 + index * LABEL_LINE_H
        view.draw_text(Geom::Point3d.new(rect[:x] + LABEL_PAD / 2, y, 0), line.to_s, options)
      end
    rescue
      nil
    end

    # ---------- hit test ----------

    def cluster_at_label(x, y)
      @clusters.find do |cluster|
        rect = cluster[:label_rect]
        rect && x >= rect[:x] && x <= rect[:x] + rect[:w] && y >= rect[:y] && y <= rect[:y] + rect[:h]
      end
    rescue
      nil
    end

    def marker_at_label(x, y)
      cluster = cluster_at_label(x, y)
      return nil unless cluster

      return cluster[:items].first[:marker] if cluster[:items].length == 1
      :cluster
    rescue
      nil
    end

    # Cac marker doi ten duoc trong nhan: PK cua minh + object ABF co ten thong ke.
    def renameable_markers_at_label(x, y)
      cluster = cluster_at_label(x, y)
      return [] unless cluster

      renameable_markers_in(cluster)
    rescue
      []
    end

    def renameable_markers_in(cluster)
      cluster[:items].select { |m| !m[:virtual] && (!m[:abf] || abf_named?(m[:marker])) }.map { |m| m[:marker] }
    rescue
      []
    end

    def over_label?(x, y)
      !cluster_at_label(x, y).nil?
    end
  end
end
