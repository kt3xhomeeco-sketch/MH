module MH::Panel::View
  @_vs = nil

  def self.dpi_offset
    20
  end

  def self.dpi_scale
    2.0
  end

  def self.cache_step(p = 1)
    1
  end

  def self.reload_cache
    fa = MH::Panel::Settings.read("do_dam_mat_xem_truoc", 10, "cai_dat").to_f / 100
    fc = parse_color(MH::Panel::Settings.read("mau_mat_xem_truoc", "60,175,214", "cai_dat"))
    fc.alpha = fa
    mfc = Sketchup::Color.new(fc.red, fc.green, fc.blue)
    mfc.alpha = [fa * 2, 1.0].min
    sfc = Sketchup::Color.new(fc.red, fc.green, fc.blue)
    sfc.alpha = fa / 2
    ec = parse_color(MH::Panel::Settings.read("mau_net_xem_truoc", "74,68,115", "cai_dat"))
    ew = [MH::Panel::Settings.read("do_dam_net_xem_truoc", 2, "cai_dat").to_i, 1].max
    tc = parse_color(MH::Panel::Settings.read("mau_chu_ghi_chu", "74,68,115", "cai_dat"))
    ts = MH::Panel::Settings.read("co_chu_ghi_chu", 8, "cai_dat").to_i
    wc = parse_color(MH::Panel::Settings.read("mau_canh_bao", "210,117,159", "cai_dat"))
    wfc = Sketchup::Color.new(wc.red, wc.green, wc.blue)
    wfc.alpha = [fa * 2, 1.0].min
    @_vs = {
      face_alpha: fa, face_color: fc, main_face_color: mfc, sub_face_color: sfc,
      edge_color: ec, edge_weight: ew,
      text_color: tc, text_size: ts,
      warning_color: wc, warning_face_color: wfc
    }
  end
  def self.vs
    reload_cache unless @_vs
    @_vs
  end
  def self.view
    Sketchup.active_model&.active_view
  end
  def self.parse_color(value)
    rgb = case value
            when String then value.split(',').map { |v| v.strip.to_i }
            when Array then value
            else [128, 128, 128]
          end
    Sketchup::Color.new(*rgb)
  end
  def self.face_alpha
    vs[:face_alpha]
  end
  def self.face_color
    vs[:face_color]
  end
  def self.main_face_color
    vs[:main_face_color]
  end
  def self.sub_face_color
    vs[:sub_face_color]
  end
  def self.edge_color
    vs[:edge_color]
  end
  def self.edge_weight
    vs[:edge_weight]
  end
  def self.set_edge_weight(w)
    vs[:edge_weight] = w
  end
  def self.warning_color
    vs[:warning_color]
  end
  def self.warning_face_color
    vs[:warning_face_color]
  end
  def self.grid_scale
    @_gsc = _resolve_grid_cfg if @_gsc.nil?
    @_gsc
  end
  def self._resolve_grid_cfg
    1.0
  end
  def self.point_in_polygon_2d?(px, py, poly)
    inside = false
    n = poly.length
    j = n - 1
    n.times do |i|
      xi, yi = poly[i].x, poly[i].y
      xj, yj = poly[j].x, poly[j].y
      if ((yi > py) != (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi)
        inside = !inside
      end
      j = i
    end
    inside
  end
  def self.point_in_circle_2d?(px, py, center, radius, ax1, ax2, segments: 24)
    pts = (0...segments).map do |i|
      angle = 2 * Math::PI * i / segments
      center.offset(ax1, Math.cos(angle) * radius).offset(ax2, Math.sin(angle) * radius)
    end
    screen_pts = pts.map { |p| view.screen_coords(p) }
    point_in_polygon_2d?(px, py, screen_pts)
  end
  def self.text_color
    vs[:text_color]
  end
  def self.text_size
    vs[:text_size]
  end
  def self.invalidate
    reload_cache
    view&.invalidate
  end
  def self.setup_draw(color, guide = false)
    view.drawing_color = color
    if guide
      view.line_stipple = "-"
      view.line_width = [(edge_weight / 2).to_i, 1].max
    else
      view.line_stipple = ""
      view.line_width = edge_weight
    end
  end
  def self.in_front_of_camera?(pt)
    cam = view.camera
    cam.direction.dot(cam.eye.vector_to(pt)) > 0
  end
  def self.convert_3d_to_2d(pts)
    return [] unless pts && pts.length > 0
    return [] if pts.any? { |p| !in_front_of_camera?(p) }
    pts.map { |p| view.screen_coords(p) }
  end
  def self.calc_hit_point(face, tr, x, y, view)
    return nil unless face && face.valid? && view
    ray_origin, ray_direction = view.pickray(x, y)
    world_normal = face.normal.transform(tr)
    world_point = face.bounds.center.transform(tr)
    plane = [world_point, world_normal]
    Geom.intersect_line_plane([ray_origin, ray_direction], plane) || world_point
  end
  def self.draw_lines(pts, color: nil, guide: false)
    return unless pts && pts.length >= 2
    setup_draw(color || edge_color, guide)
    view.draw(GL_LINES, pts)
  end
  def self.draw2d_lines(pts, color: nil, guide: false)
    return unless pts && pts.length >= 2
    pts2d = convert_3d_to_2d(pts)
    return unless pts2d.length >= 2
    setup_draw(color || edge_color, guide)
    view.draw2d(GL_LINES, pts2d)
  end
  def self.draw_loop(pts, color: nil, guide: false)
    return unless pts && pts.length >= 3
    setup_draw(color || edge_color, guide)
    view.draw(GL_LINE_LOOP, pts)
  end
  def self.draw2d_loop(pts, color: nil, guide: false)
    return unless pts && pts.length >= 3
    pts2d = convert_3d_to_2d(pts)
    return unless pts2d.length >= 3
    setup_draw(color || edge_color, guide)
    view.draw2d(GL_LINE_LOOP, pts2d)
  end
  def self.draw_polygon(pts, color: nil, line: true)
    return unless pts && pts.length >= 3
    draw_loop(pts) if line
    setup_draw(color || face_color)
    view.draw(GL_TRIANGLES, Geom.tesselate(pts))
  end
  def self.draw2d_polygon(pts, color: nil, line: true, guide: false)
    return unless pts && pts.length >= 3
    draw2d_loop(pts, guide: guide) if line
    pts2d = convert_3d_to_2d(pts)
    return unless pts2d.length >= 3
    setup_draw(color || face_color)
    view.draw2d(GL_TRIANGLES, Geom.tesselate(pts2d))
  end
  def self.draw2d_circle(center, normal, radius, segments: 24, tr: nil, color: nil, guide: false, fill: true)
    arb = normal.parallel?(Geom::Vector3d.new(0, 0, 1)) ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 0, 1)
    u = normal.cross(arb).normalize
    v = normal.cross(u).normalize
    pts = segments.times.map do |i|
      angle = 2 * Math::PI * i / segments
      pt = center.offset(u, radius * Math.cos(angle)).offset(v, radius * Math.sin(angle))
      tr ? pt.transform(tr) : pt
    end
    if fill
      draw2d_polygon(pts, color: color)
    else
      draw2d_loop(pts, guide: guide)
    end
  end
  def self.draw2d_circle_px(center_3d, radius_px, segments: 24, color: nil, guide: false, fill: true)
    return unless in_front_of_camera?(center_3d)
    sc = view.screen_coords(center_3d)
    pts = segments.times.map do |i|
      angle = 2 * Math::PI * i / segments
      Geom::Point3d.new(sc.x + radius_px * Math.cos(angle), sc.y + radius_px * Math.sin(angle), 0)
    end
    if fill
      setup_draw(color || edge_color, guide)
      view.draw2d(GL_LINE_LOOP, pts)
      setup_draw(color || face_color)
      view.draw2d(GL_TRIANGLE_FAN, [Geom::Point3d.new(sc.x, sc.y, 0)] + pts + [pts[0]])
    else
      setup_draw(color || edge_color, guide)
      view.draw2d(GL_LINE_LOOP, pts)
    end
  end
  def self.point_in_circle_px?(mx, my, center_3d, radius_px)
    sc = view.screen_coords(center_3d)
    dx = mx - sc.x
    dy = my - sc.y
    dx * dx + dy * dy <= radius_px * radius_px
  end
  def self.draw2d_point(p, color: nil, radius: 5)
    return unless p
    return unless in_front_of_camera?(p)
    sp = view.screen_coords(p)
    pts = (0...16).map do |i|
      angle = 2 * Math::PI * i / 16
      Geom::Point3d.new(sp.x + radius * Math.cos(angle), sp.y + radius * Math.sin(angle), 0)
    end
    view.drawing_color = "White"
    view.draw2d(GL_POLYGON, pts)
    setup_draw(color || edge_color)
    view.draw2d(GL_LINE_LOOP, pts)
  end
  def self.draw2d_text(text, position, color: nil, ref_p1: nil, ref_p2: nil)
    return unless text && position
    return unless in_front_of_camera?(position)
    pt2d = view.screen_coords(position)
    char_width = text_size * 0.6
    text_width = text.to_s.length * char_width
    padding_x = text_size / 3
    padding_y = text_size / 2
    radius = (text_size / 2) + padding_y
    offset_x, offset_y = calc_text_offset(ref_p1, ref_p2, text_width)
    cx = pt2d.x + offset_x
    cy = pt2d.y + offset_y - padding_y / 4
    half_width = text_width / 2 + padding_x
    pill_pts = build_pill_shape(cx, cy, half_width, radius)
    view.drawing_color = "White"
    view.draw2d(GL_POLYGON, pill_pts)
    view.drawing_color = "Black"
    view.line_width = 1
    view.draw2d(GL_LINE_LOOP, pill_pts)
    text_pt = Geom::Point3d.new(cx, cy + padding_y / 4, 0)
    options = { color: color || text_color, size: text_size, align: TextAlignCenter, vertical_align: TextVerticalAlignCenter }
    view.draw_text(text_pt, text.to_s, options)
  end
  def self.highlight_board(board, color: nil)
    return unless board && board.valid?
    tr = board.transformation
    MH::Panel.grep_ents(board, :face).each do |face|
      pts = face.outer_loop.vertices.map { |v| v.position.transform(tr) }
      draw_polygon(pts, color: color, line: false)
    end
  end
  def self.calc_text_offset(ref_p1, ref_p2, text_width)
    return [0, 0] unless ref_p1 && ref_p2
    p1_2d = view.screen_coords(ref_p1)
    p2_2d = view.screen_coords(ref_p2)
    dx = p2_2d.x - p1_2d.x
    dy = p2_2d.y - p1_2d.y
    len = Math.sqrt(dx * dx + dy * dy)
    return [0, 0] unless len > 0
    offset_dist = text_width * 1.5
    [(-dy / len) * offset_dist, (dx / len) * offset_dist]
  end
  def self.build_pill_shape(cx, cy, half_width, radius, segments: 8)
    pts = []
    (0..segments).each do |i|
      angle = Math::PI / 2 + (Math::PI * i / segments)
      pts << Geom::Point3d.new(cx - half_width + radius * Math.cos(angle), cy + radius * Math.sin(angle), 0)
    end
    (0..segments).each do |i|
      angle = -Math::PI / 2 + (Math::PI * i / segments)
      pts << Geom::Point3d.new(cx + half_width + radius * Math.cos(angle), cy + radius * Math.sin(angle), 0)
    end
    pts
  end
  def self.nearest_point(*points)
    eye = Sketchup.active_model.active_view.camera.eye
    points.min_by { |p| eye.distance(p) }
  end
end
