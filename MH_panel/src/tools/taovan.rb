class MH::Panel::TaoVan
  include MH::Panel::Preset
  settings_section "tao_van"
  def initialize
    MH::Panel.init_undo
    @faces_arr = nil
    @ip = Sketchup::InputPoint.new
    @last_face = @last_tr = @last_parent = @last_hit_point = nil
    @material = nil
    update_status
  end
  def resume(view)
    update_status
  end
  def suspend(view)
    update_status
  end
  def init_var
    @tinh_theo_khong_gian = read("tinh_theo_khong_gian", true)
    @chon_mat_mo_rong = read("chon_mat_mo_rong", true)
    @bo_dem_gop = 1
    @do_day_tu_dong = read("do_day_tu_dong", true)
    @do_day = read("do_day", 17.5).to_f.mm
    @do_day_khong_gian = @do_day
    @tao_component = read("tao_component", false)
    @bo_dem_bat = 1
    @bo_qua_xem_truoc = read("bo_qua_xem_truoc", false)
    @ti_so_van_do = 1.0
    @instance = read("instance", "")
    @layer = read("layer", "")
    @tu_dong_xoay_van = read("tu_dong_xoay_van", false)
    @tao_van_nhanh = read("tao_van_nhanh", false)
    @gop_dong_phang = read("gop_dong_phang", false)
    @sai_so_gop = 0.0.mm
    @ty_le_van = 1.0
    @view_dpi = read("view_dpi", 0, true).to_f.mm
    @mo_rong_bien = read("mo_rong_bien", 0.0).to_f.mm
    @tut_hoi = read("tut_hoi", 0.0).to_f.mm
    @can_chinh_van = 0.0.mm
    @che_do = read("che_do", "lot_long")
    @do_lech_cat = 0
    @so_khoang_cach = 1
    @khoang_cach = 0
    @do_lech_bat = 0.0.mm
    @che_do_mo_rong = 2
    @hieu_chinh_cat = 0.0
    @presets = read("presets", nil)
    init_preset_buttons(@presets)
    update_mode_buttons
    init_setting_buttons(
      nil => {
        tinh_theo_khong_gian: [:switch, "Tính theo không gian"],
        chon_mat_mo_rong: [:switch, "Chọn mặt mở rộng", -> { @tinh_theo_khong_gian }],
      },
      "Độ dày" => {
        do_day_tu_dong: [:switch, "Độ dày tự động"],
        do_day: [:mm, "Độ dày ván", -> { !@do_day_tu_dong }],
      },
      "Kích thước" => {
        mo_rong_bien: [:mm, "Mở rộng biên"],
        tut_hoi: [:mm, "Tụt hồi"],
      },
      "Component" => {
        tao_component: [:switch, "Tạo component"],
        tu_dong_xoay_van: [:switch, "Tự động xoay vân"],
      },
      "Xem trước" => {
        bo_qua_xem_truoc: [:switch, "Bỏ qua xem trước"],
      }
    )
    update_preview
    update_status
  end
  def update_preview
    if @locked
      calc_all_box_points
    elsif @last_face && @last_tr && @last_parent && @last_hit_point
      if !@tinh_theo_khong_gian
        find_polygon_points(@last_face, @last_tr, @last_parent, @last_hit_point)
      elsif @chon_mat_mo_rong
        find_rect_points(@last_face, @last_tr, @last_parent, @last_hit_point)
      elsif @last_path
        find_advanced_rect_points(@last_face, @last_tr, @last_parent, @last_hit_point, @last_path)
      end
      find_depth_point(@last_face, @last_tr, @last_parent, @last_hit_point)
    end
  end
  def load_preset(s)
    init_preset(:tinh_theo_khong_gian, s)
    init_preset(:chon_mat_mo_rong, s)
    init_preset(:do_day_tu_dong, s)
    init_preset(:do_day, s) { |v| v.to_f.mm }
    init_preset(:mo_rong_bien, s) { |v| v.to_f.mm }
    init_preset(:tut_hoi, s) { |v| v.to_f.mm }
    init_preset(:instance, s)
    init_preset(:layer, s)
    init_preset(:tu_dong_xoay_van, s)
  end
  def onKeyDown(key, repeat, flags, view)
    if key == MH::Panel::Settings.key_chuyen_che_do
      if @locked
        if @so_khoang_cach > 1
          @che_do_mo_rong = (@che_do_mo_rong + 1) % 3
        else
          @che_do = case @che_do
                    when "lot_long" then "chinh_giua"
                    when "chinh_giua" then "phu_bi"
                    else "lot_long"
                    end
          write("che_do", @che_do)
        end
        calc_all_box_points
        view.invalidate
        update_status
      else
        @tinh_theo_khong_gian = !@tinh_theo_khong_gian
        write("tinh_theo_khong_gian", @tinh_theo_khong_gian)
        @adv_cache_face = @adv_cache_parent = nil
        @adv_cache_cells = nil
        update_preview
        view.invalidate
        update_status
      end
      return true
    end
    if key == MH::Panel::Settings.key_mo_cai_dat
      MH::Panel::Settings.open_settings('tao_van')
      return true
    end
    if key == ALT_MODIFIER_KEY
      if !@locked && @tinh_theo_khong_gian
        @chon_mat_mo_rong = !@chon_mat_mo_rong
        write("chon_mat_mo_rong", @chon_mat_mo_rong)
        @adv_cache_face = @adv_cache_parent = nil
        @adv_cache_cells = nil
        update_preview
        view.invalidate
        update_status
      end
      return true
    end
  end
  def onKeyUp(key, repeat, flags, view)
    return if @sb_selected_item
    return true if key == ALT_MODIFIER_KEY
  end
  def enableVCB?
    true
  end
  def onUserText(text, view)
    if text.start_with?("/")
      num = text[1..-1].to_i
      return if num < 1
      @so_khoang_cach = num
      @khoang_cach = 0 unless @free
      if @locked && @so_khoang_cach == 1 && @p1 && @normal && @last_ray && !@free
        @p3 = closest_point_on_line(@p1, @p2, @last_ray)
      end
    else
      len = text.to_l.to_mm.to_f
      return if len < 0
      @khoang_cach = len.mm
      if @khoang_cach >= 0 && @locked && @p1 && @normal && @last_ray
        @so_khoang_cach = 1
        pt = nearest_point_at_distance(@khoang_cach)
        @free ? @p2 = pt : @p3 = pt
      end
    end
    calc_all_box_points if @locked
    update_mode_buttons
    start_create_box if @bo_qua_xem_truoc && !text.start_with?(":")
    view.invalidate
    update_status
  end
  def update_mode_buttons
    mo_rong_order = [2, 0, 1]
    if @locked && @so_khoang_cach > 1
      init_mode_buttons(
        ["Thông thủy", "Cánh lọt", "Cánh phủ"],
        active_proc: -> { mo_rong_order.index(@che_do_mo_rong) },
        on_click: -> (i) {
          @che_do_mo_rong = mo_rong_order[i]
          calc_all_box_points if @locked
          Sketchup.active_model.active_view.invalidate
          update_status
        }
      )
    else
      @mb_labels = nil
    end
  end
  def update_status
    if @locked
      text = ""
      text += "Nhấn Tab để đổi chế độ tính toán. " if @so_khoang_cach > 1
      text += "Nhấn Tab để chuyển vị trí bắt điểm. " if @so_khoang_cach <= 1
      text += "Nhấn Enter hoặc nhấn chuột để tạo ván."
      MH::Panel.status(text)
    else
      if @has_selected_faces
        MH::Panel.status("Nhấn Enter để tạo ván từ những mặt đang chọn.")
      else
        text = "Nhấn Tab để chuyển chế độ chọn mặt."
        text += " Nhấn Alt để chuyển chế độ chọn mặt mở rộng." if @tinh_theo_khong_gian
        MH::Panel.status(text)
      end
    end
    if @locked && @khoang_cach <= 0 && @p1
      if @free
        kc = @p2 ? @p1.distance(@p2) : 0
      else
        kc = @p3 ? diem_neo.distance(@p3) : 0
      end
    else
      kc = @khoang_cach || 0
    end
    MH::Panel.vcb(
      "Số khoảng [/x]: #{@so_khoang_cach || 1} | Khoảng cách",
      Sketchup.format_length(kc)
    )
  end
  def draw(view)
    draw_preset_buttons(view)
    draw_setting_buttons(view)
    draw_mode_buttons(view)
    @ip.draw(view) if @ip_valid
    if @locked
      draw_boxes(view) if @all_box_points && !@all_box_points.empty?
      draw_guides(view) if @p1 && @p2
      draw_texts(view) if @p1 && @p2
    elsif @rect_points && @rect_points.length >= 3
      if !@tinh_theo_khong_gian && @last_face && @last_tr
        pts = @last_face.outer_loop.vertices.map { |v| v.position.transform(@last_tr) }
        pts = pts.map { |p| p.offset([0, 0, @view_dpi]) } if @view_dpi != 0
        MH::Panel::View.draw2d_polygon(pts)
      else
        rpts = @view_dpi != 0 ? @rect_points.map { |p| p.offset([0, 0, @view_dpi]) } : @rect_points
        MH::Panel::View.draw2d_polygon(rpts)
      end
    end
  end
  def activate
    init_var
    load_active_preset
    reset_state
    @has_selected_faces = Sketchup.active_model.selection.any? { |e|
      e.is_a?(Sketchup::Face) || MH::Panel.is_container?(e)
    }
    if @tao_van_nhanh && @has_selected_faces
      quick_make_face
      return
    end
    update_status
  end
  def deactivate(view)
    save_active_preset
    view.invalidate
  end
  def onMouseMove(flags, x, y, view)
    handle_ui_mouse_move(x, y, view)
    if @locked && @khoang_cach <= 0
      @ip.pick(view, x, y)
      @ip_valid = @ip.valid? && (@ip.vertex || @ip.edge || @ip.face)
    else
      @ip_valid = false
    end
    ph = view.pick_helper
    ph.do_pick(x, y)
    @last_ray = view.pickray(x, y)
    if @locked
      return unless @p1 && @normal
      if @khoang_cach <= 0
        update_dynamic_point
        update_status
      end
      calc_all_box_points
      view.invalidate
      return
    end
    face = ph.picked_face
    unless face
      clear_preview
      view.invalidate
      return
    end
    path = ph.path_at(0)
    return unless path && !path.empty?
    tr = ph.transformation_at(0)
    parent = path.reverse.find do |e|
      MH::Panel.is_container?(e) && e.definition.entities.include?(face) && entity_visible?(e)
    end
    return unless parent
    @material = effective_source_material(face, path, parent)
    @material_name = MH::Panel.material_name_from_face_path(face, path, parent)
    hit_point = MH::Panel::View.calc_hit_point(face, tr, x, y, view)
    return unless hit_point
    @p1 = hit_point
    @parent = parent
    @face = face
    @tr = tr
    @last_path = path
    if !@tinh_theo_khong_gian
      find_polygon_points(face, tr, parent, hit_point)
    elsif @chon_mat_mo_rong
      find_rect_points(face, tr, parent, hit_point)
    else
      find_advanced_rect_points(face, tr, parent, hit_point, path)
    end
    find_depth_point(face, tr, parent, hit_point)
    view.invalidate
  end
  def onReturn(view)
    if !@locked
      @faces_arr = build_faces_arr
      make_face unless @faces_arr.empty?
    else
      onLButtonDown(0, 0, 0, view)
    end
  end
  def start_create_box
    return unless @all_box_points && !@all_box_points.empty?
    create_box
    reset_state
  end
  def onLButtonDown(flags, x, y, view)
    return if handle_setting_click(x, y, view)
    if id = handle_preset_click(x, y)
      unless id == :deselected
        index = id.to_s.split('_').last.to_i
        load_preset(@presets[index]["settings"])
      end
      view.invalidate
    else
      return if handle_mode_click(x, y, view)
      if @locked
        start_create_box
      else
        return unless @p1 && @p2 && @rect_points
        @locked = true
        @locked_rect = @rect_points.dup
        @locked_soft_vertices = @soft_vertices&.dup
        @p3 = @p1.clone if @so_khoang_cach == 1 && !@free
        update_mode_buttons
        calc_all_box_points
      end
      view.invalidate
      update_status
    end
  end
  def reset_state
    @locked = false
    @free = false
    @p1 = @p2 = @p3 = nil
    @rect_points = @locked_rect = @all_box_points = nil
    @soft_vertices = @locked_soft_vertices = nil
    @last_path = nil
    @khoang_cach = 0
    @last_face = @last_tr = @last_parent = @last_hit_point = nil
    @adv_cache_face = @adv_cache_parent = nil
    @adv_cache_cells = nil
    @material = nil
    @material_name = nil
    update_mode_buttons
  end
  def calc_all_box_points
    return unless @locked_rect && @p1 && @p2 && @normal
    @all_box_points = []
    profile_rect = adjusted_panel_profile_rect
    n = @so_khoang_cach - 1
    if n == 0
      point = @free ? @p2 : @p3
      vector = point - @p1
      base_rect = profile_rect.map { |pt| pt.offset(vector) }
      case @che_do
      when "lot_long"
        vec = @normal.clone
        vec.length = @do_day_khong_gian
        bottom = base_rect
        top = base_rect.map { |pt| pt.offset(vec) }
      when "chinh_giua"
        half = @do_day_khong_gian / 2
        v1 = @normal.clone; v1.length = half
        v2 = @normal.reverse; v2.length = half
        bottom = base_rect.map { |pt| pt.offset(v1) }
        top = base_rect.map { |pt| pt.offset(v2) }
      when "phu_bi"
        vec = @normal.reverse
        vec.length = @do_day_khong_gian
        bottom = base_rect
        top = base_rect.map { |pt| pt.offset(vec) }
      end
      @all_box_points << { bottom: bottom, top: top }
    else
      thickness = @do_day_khong_gian / 2.0
      vec_down = @normal.clone
      vec_down.length = thickness
      vec_up = @normal.reverse
      vec_up.length = thickness
      case @che_do_mo_rong
      when 0
        p1_offset = @p1
        p2_offset = @p2
      when 1
        p1_offset = @p1.offset(@normal.reverse, @do_day_khong_gian)
        p2_offset = @p2.offset(@normal, @do_day_khong_gian)
      when 2
        p1_offset = @p1.offset(@normal.reverse, @do_day_khong_gian / 2)
        p2_offset = @p2.offset(@normal, @do_day_khong_gian / 2)
      end
      (1..n).each do |i|
        t = i.to_f / (n + 1)
        point = Geom.linear_combination(1 - t, p1_offset, t, p2_offset)
        add_box_at_point(point, vec_down, vec_up)
      end
    end
  end
  def adjusted_panel_profile_rect
    points = @locked_rect.map(&:clone)
    points = offset_profile_points(points, @mo_rong_bien) if @mo_rong_bien && @mo_rong_bien != 0
    points = setback_profile_points(points, @tut_hoi) if @tut_hoi && @tut_hoi > 0
    points
  end
  def offset_profile_points(points, distance)
    return points unless points && points.length >= 3 && @normal
    offset_points = MH::Geo::Offset.offset_pts(points, @normal, distance)
    offset_points && offset_points.length >= 3 ? offset_points : points
  rescue => e
    puts "[MH::Panel::TaoVan] offset_profile_points error: #{e.class}: #{e.message}"
    points
  end
  def setback_profile_points(points, distance)
    setback_edge = setback_edge_for_profile(points)
    return points unless setback_edge

    edge_index, inward = setback_edge
    moved = points.map(&:clone)
    moved[edge_index] = moved[edge_index].offset(inward, distance)
    next_index = (edge_index + 1) % moved.length
    moved[next_index] = moved[next_index].offset(inward, distance)
    moved
  rescue => e
    puts "[MH::Panel::TaoVan] setback_profile_points error: #{e.class}: #{e.message}"
    points
  end
  def setback_edge_for_profile(points)
    inward = view_inward_vector_for_profile(points)
    return nil unless inward && inward.length > 0.001.mm

    normal = @normal.clone
    normal.normalize!
    candidates = []
    points.each_with_index do |pt, index|
      next_pt = points[(index + 1) % points.length]
      edge = pt.vector_to(next_pt)
      next if edge.length <= 0.001.mm

      edge.normalize!
      edge_normals = [edge.cross(normal), normal.cross(edge)]
      edge_normals.each do |candidate|
        next if candidate.length <= 0.001.mm

        candidate.normalize!
        score = candidate.dot(inward)
        next if score <= 0

        center = Geom.linear_combination(0.5, pt, 0.5, next_pt)
        candidates << [index, candidate, score, (center - ORIGIN).dot(candidate)]
      end
    end
    return nil if candidates.empty?

    best_score = candidates.map { |candidate| candidate[2] }.max
    best = candidates.select { |candidate| (best_score - candidate[2]).abs <= 0.001 }
                     .min_by { |candidate| candidate[3] }
    [best[0], best[1]]
  end
  def view_inward_vector_for_profile(points)
    view = Sketchup.active_model.active_view
    direction = view.camera.direction.clone
    normal = @normal.clone
    normal.normalize!
    dot = direction.dot(normal)
    normal_component = Geom::Vector3d.new(normal.x * dot, normal.y * dot, normal.z * dot)
    projected = direction - normal_component
    if projected.length <= 0.001.mm && points && points.length >= 2
      edges = points.each_with_index.map { |pt, i| pt.vector_to(points[(i + 1) % points.length]) }
      projected = edges.max_by(&:length)
    end
    return nil unless projected && projected.length > 0.001.mm

    projected.normalize!
    projected
  end
  def create_box
    return unless @all_box_points && !@all_box_points.empty?
    detail_name = current_instance_setting
    entities = MH::Panel::Model.active_entities
    layer = if @layer && !@layer.empty?
              MH::Panel.ensure_tag(@layer)
            elsif @parent.respond_to?(:layer)
              @parent.layer
            end
    material = @material
    MH::Panel.start
    boards = []
    @all_box_points.each do |box|
      group = entities.add_group
      group.name = detail_name unless detail_name.empty?
      group.layer = layer if layer
      group.material = material if material
      bottom = box[:bottom]
      top = box[:top]
      if !@tinh_theo_khong_gian && @last_face && @last_tr
        face = copy_face_to_entities(@last_face, @last_tr, group.entities, bottom, top)
      else
        face = group.entities.add_face(bottom)
      end
      if face
        vec = top[0] - bottom[0]
        direction = face.normal.dot(vec) > 0 ? 1 : -1
        face.pushpull(direction * vec.length)
        group.entities.grep(Sketchup::Face).each do |f|
          f.material = nil
          f.back_material = nil
        end
        if @tinh_theo_khong_gian && @last_face && @last_tr
          smooth_advanced_edges(group.entities, bottom, @last_face, @last_tr)
        end
        boards << group if group.valid?
      end
    end
    boards = MH::Panel::Group.group_to_component(boards) if @tao_component && boards.length > 1
    MH::Panel::Purge.fix_all(boards)
    boards.each { |b| MH::Panel::Material.align_texture(b) }
    boards.each do |b|
      MH::Panel.apply_mh_codes(
        b,
        detail_name: detail_name,
        thickness_mm: (@do_day_khong_gian.to_mm rescue nil),
        material_name: (@material_name || (material.respond_to?(:name) ? material.name : nil)),
        source: source_for_detail_codes(@parent, detail_name),
        product_code: product_code_for_detail_codes(@parent, detail_name)
      )
      sync_material_appearance(b.material, material) if material && b.material
      apply_material_to_board(b, material) if material && !b.material
    end
    MH::Panel.commit
    boards.each { |b| MH::Panel::Group.reset_axes(b, @tu_dong_xoay_van) }
  end
  def current_instance_setting
    preset = active_instance_preset
    if preset
      preset_instance = preset.dig("settings", "instance").to_s.strip
      value = preset_instance.empty? ? preset["name"].to_s.strip : preset_instance
      @instance = value unless value.empty?
      return value
    end

    @instance = read("instance", @instance.to_s)
    @instance.to_s.strip
  rescue
    @instance.to_s.strip
  end
  def active_instance_preset
    return nil unless @presets

    if @button_config && @button_config[:selected]
      index = @button_config[:selected].to_s.split('_').last.to_i
      return @presets[index]
    end

    preset_name = read("cai_dat_mau", nil)
    return nil if preset_name.to_s.strip.empty?

    @presets.find { |preset| preset["name"].to_s == preset_name.to_s }
  rescue
    nil
  end
  def source_for_detail_codes(source, detail_name)
    detail_name.to_s.strip.empty? ? source : nil
  end
  def product_code_for_detail_codes(source, detail_name)
    return nil if detail_name.to_s.strip.empty?

    MH::Panel.product_code_from_source(source)
  rescue
    nil
  end
  def effective_source_material(face, path = nil, source = nil)
    material = nil
    if face && face.respond_to?(:material)
      material = face.material
      material ||= face.back_material if face.respond_to?(:back_material)
    end
    material ||= Array(path)[0..-2].reverse.find do |entity|
      entity.respond_to?(:material) && entity.material
    end&.material
    material ||= source.material if source && source.respond_to?(:material)
    material
  rescue
    nil
  end
  def apply_material_to_board(board, material)
    return unless board && board.valid? && material

    board.material = material
    board.entities.grep(Sketchup::Face).each do |face|
      face.material = nil
      face.back_material = nil
    end
  rescue => e
    puts "[MH::Panel::TaoVan] apply material error: #{e.class}: #{e.message}"
  end
  def sync_material_appearance(target, source)
    return unless target

    return unless source && target == source
    target.alpha = source.alpha if source.respond_to?(:alpha) && target.respond_to?(:alpha=)
  rescue => e
    puts "[MH::Panel::TaoVan] sync material error: #{e.class}: #{e.message}"
  end
  def copy_face_to_entities(source_face, source_tr, target_entities, bottom, top)
    original_vertices = source_face.outer_loop.vertices.map { |v| v.position.transform(source_tr) }
    return target_entities.add_face(bottom) if original_vertices.empty? || bottom.empty?
    offset_vec = bottom[0] - original_vertices[0]
    return target_entities.add_face(bottom) unless MH::Panel.is_container?(@parent)
    temp_instance = target_entities.add_instance(@parent.definition, IDENTITY)
    temp_group = temp_instance.make_unique
    all_faces = temp_group.entities.grep(Sketchup::Face)
    target_face = all_faces.find do |f|
      next false unless f.vertices.length == source_face.vertices.length
      f.vertices.each_with_index.all? { |v, i|
        v.position.distance(source_face.vertices[i].position) <= 0.001
      }
    end
    (all_faces - [target_face]).each { |f| f.erase! if f.valid? }
    temp_group.entities.grep(Sketchup::Edge).each { |e| e.erase! if e.valid? && e.faces.empty? }
    temp_group.transform!(Geom::Transformation.translation(offset_vec) * source_tr)
    result_face = temp_group.explode.find { |e| e.is_a?(Sketchup::Face) && e.valid? }
    result_face || target_entities.add_face(bottom)
  end
  def smooth_advanced_edges(ents, bottom_pts, source_face, source_tr)
    face_edges = source_face.edges
    smooth_map = {}
    source_face.outer_loop.vertices.each_with_index do |v, i|
      v.edges.each do |e|
        next if face_edges.include?(e)
        if e.soft? || e.smooth? || e.hidden?
          smooth_map[i] = { soft: e.soft?, smooth: e.smooth?, hidden: e.hidden? }
          break
        end
      end
    end
    return if smooth_map.empty?
    source_pts = source_face.outer_loop.vertices.map { |v| v.position.transform(source_tr) }
    face_normal = source_face.normal.transform(source_tr)
    face_normal.normalize!
    face_origin = source_pts.first
    smooth_bottom = {}
    bottom_pts.each_with_index do |bp, bi|
      d = (bp - face_origin) % face_normal
      pp = bp.offset(face_normal, -d)
      smooth_map.each do |si, flags|
        if pp.distance(source_pts[si]) < 0.1.mm
          smooth_bottom[bi] = flags
          break
        end
      end
    end
    return if smooth_bottom.empty?
    bottom_edge_set = Set.new
    bottom_pts.each_with_index do |_, i|
      j = (i + 1) % bottom_pts.length
      bottom_edge_set << [bottom_pts[i], bottom_pts[j]]
    end
    smooth_bottom.each do |idx, flags|
      pt = bottom_pts[idx]
      ents.grep(Sketchup::Edge).each do |e|
        verts = e.vertices.map { |v| v.position }
        next unless verts.any? { |v| v.distance(pt) < 0.1.mm }
        on_bottom = bottom_edge_set.any? do |a, b|
          (verts[0].distance(a) < 0.1.mm && verts[1].distance(b) < 0.1.mm) ||
          (verts[0].distance(b) < 0.1.mm && verts[1].distance(a) < 0.1.mm)
        end
        next if on_bottom
        e.soft = flags[:soft] if flags[:soft]
        e.smooth = flags[:smooth] if flags[:smooth]
        e.hidden = flags[:hidden] if flags[:hidden]
      end
    end
  end
  def closest_point_on_line(p1, p2, ray)
    pt = Geom.closest_points([p1, @normal], ray)[0]
    dir = p2 - p1
    return pt unless dir.length > 0
    t = ((pt - p1) % dir) / (dir % dir)
    t = [[t, 0.0].max, 1.0].min
    Geom.linear_combination(1 - t, p1, t, p2)
  end
  def entity_visible?(entity)
    return false if entity.nil?
    return false if entity.respond_to?(:hidden?) && entity.hidden?
    return false if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?
    true
  end
  def find_depth_point(face, tr, parent, hit_point)
    @normal = face.normal.transform(tr)
    @normal.normalize!
    current_point = hit_point
    100.times do
      result = Sketchup.active_model.raytest([current_point, @normal], false)
      break unless result
      hit_pt, path = result
      board = path.find { |e| MH::Panel.is_container?(e) }
      if board && entity_visible?(board)
        @p2 = hit_pt
        @free = false
        cap_nhat_do_day(parent)
        return
      end
      current_point = hit_pt.offset(@normal, 0.1.mm)
    end
    @free = true
    cap_nhat_do_day(parent)
    return unless @last_ray
    @p2 = Geom.closest_points([hit_point, @normal], @last_ray)[0]
  end
  def cap_nhat_do_day(parent)
    MH::Panel::Group.fix_scale(parent)
    do_day = MH::Panel::Board.calc_thickness(parent)
    if @do_day_tu_dong && parent && do_day
      @do_day_khong_gian = do_day
    else
      @do_day_khong_gian = @do_day
    end
  end
  def getExtents
    return unless @all_box_points
    bounds = Geom::BoundingBox.new
    @all_box_points.each do |box|
      bounds.add(box[:bottom])
      bounds.add(box[:top])
    end
    bounds
  end
  def find_rect_points(face, tr, parent, hit_point)
    normal = face.normal.transform(tr)
    normal.normalize!
    axes = [tr.xaxis, tr.yaxis, tr.zaxis]
    perp_axes = axes.reject { |axis| axis.parallel?(normal) }
    return unless perp_axes.length == 2
    model = Sketchup.active_model
    hit_points = {}
    directions = [
      [perp_axes[0], :pos1],
      [perp_axes[0].reverse, :neg1],
      [perp_axes[1], :pos2],
      [perp_axes[1].reverse, :neg2]
    ]
    directions.each do |dir, key|
      result = model.raytest([hit_point, dir], true)
      if result
        hit_pt, path = result
        hit_points[key] = hit_pt if path.all? { |e| entity_visible?(e) }
      end
    end
    return unless hit_points.length == 4
    v1_pos = hit_points[:pos1] - hit_point
    v1_neg = hit_points[:neg1] - hit_point
    v2_pos = hit_points[:pos2] - hit_point
    v2_neg = hit_points[:neg2] - hit_point
    @rect_points = [
      hit_point.offset(v1_pos).offset(v2_pos),
      hit_point.offset(v1_neg).offset(v2_pos),
      hit_point.offset(v1_neg).offset(v2_neg),
      hit_point.offset(v1_pos).offset(v2_neg)
    ]
    @last_face = face
    @last_tr = tr
    @last_parent = parent
    @last_hit_point = hit_point
  end
  def find_polygon_points(face, tr, parent, hit_point)
    vertices = face.outer_loop.vertices
    @rect_points = vertices.map { |v| v.position.transform(tr) }
    @soft_vertices = calc_soft_vertices(face)
    @last_face = face
    @last_tr = tr
    @last_parent = parent
    @last_hit_point = hit_point
  end
  def find_advanced_rect_points(face, tr, parent, hit_point, path)
    if face != @adv_cache_face || parent != @adv_cache_parent
      compute_advanced_cells(face, tr, parent, path)
      @adv_cache_face = face
      @adv_cache_parent = parent
      sv = calc_soft_vertices(face)
      face_pts = face.outer_loop.vertices.map { |v|
        v.position.transform(tr)
      }
      @adv_soft_pts = []
      face_pts.each_with_index do |pt, i|
        @adv_soft_pts << pt if sv[i]
      end
    end
    if @adv_cache_cells && @adv_cache_origin
      cursor_1 = (hit_point - @adv_cache_origin) % @adv_cache_axis1
      cursor_2 = (hit_point - @adv_cache_origin) % @adv_cache_axis2
      @rect_points = nil
      @soft_vertices = nil
      @adv_cache_cells.each do |cell|
        if cursor_1 >= cell[0] && cursor_1 <= cell[1] &&
           cursor_2 >= cell[2] && cursor_2 <= cell[3]
          @rect_points = cell[4]
          tol = 0.1.mm
          @soft_vertices = cell[4].map { |pt|
            @adv_soft_pts.any? { |sp| pt.distance(sp) < tol }
          }
          break
        end
      end
    end
    @last_face = face
    @last_tr = tr
    @last_parent = parent
    @last_hit_point = hit_point
  end
  def compute_advanced_cells(face, tr, parent, path)
    @adv_cache_cells = nil
    @adv_cache_origin = nil
    normal = face.normal.transform(tr)
    normal.normalize!
    axes = [tr.xaxis, tr.yaxis, tr.zaxis]
    perp_axes = axes.reject { |axis| axis.parallel?(normal) }
    return unless perp_axes.length == 2
    axis1, axis2 = perp_axes
    @adv_cache_axis1 = axis1
    @adv_cache_axis2 = axis2
    face_pts = face.outer_loop.vertices.map { |v| v.position.transform(tr) }
    origin = face_pts[0]
    @adv_cache_origin = origin
    d1_vals = face_pts.map { |pt| (pt - origin) % axis1 }
    d2_vals = face_pts.map { |pt| (pt - origin) % axis2 }
    d1_min, d1_max = d1_vals.minmax
    d2_min, d2_max = d2_vals.minmax
    context_tr = tr * parent.transformation.inverse
    parent_idx = path.index(parent)
    container_ents = if parent_idx && parent_idx > 0
                       path[parent_idx - 1].definition.entities
                     else
                       MH::Panel::Model.active_entities
                     end
    siblings = container_ents.select { |e|
      MH::Panel.is_container?(e) && e != parent && entity_visible?(e)
    }
    tol = 0.5.mm
    strips = []
    siblings.each do |sibling|
      s_tr = context_tr * sibling.transformation
      bb = sibling.definition.bounds
      bb_dists = (0..7).map { |i| (bb.corner(i).transform(s_tr) - origin) % normal }
      next if bb_dists.min > tol || bb_dists.max < -tol
      edge_pts = []
      sibling.definition.entities.grep(Sketchup::Edge).each do |edge|
        ep1 = edge.start.position.transform(s_tr)
        ep2 = edge.end.position.transform(s_tr)
        d1 = (ep1 - origin) % normal
        d2 = (ep2 - origin) % normal
        if d1.abs < tol && d2.abs < tol
          edge_pts << ep1 << ep2
        elsif d1 * d2 < 0
          pt = Geom.intersect_line_plane([ep1, ep2], [origin, normal])
          edge_pts << pt if pt
        end
      end
      next if edge_pts.length < 2
      p1 = edge_pts.map { |c| (c - origin) % axis1 }
      p2 = edge_pts.map { |c| (c - origin) % axis2 }
      s1_min = [p1.min, d1_min].max
      s1_max = [p1.max, d1_max].min
      s2_min = [p2.min, d2_min].max
      s2_max = [p2.max, d2_max].min
      next if s1_max - s1_min < 0.1.mm || s2_max - s2_min < 0.1.mm
      strips << [s1_min, s1_max, s2_min, s2_max]
    end
    face_2d = face_pts.map { |pt| [(pt - origin) % axis1, (pt - origin) % axis2] }
    x_coords = [d1_min, d1_max]
    y_coords = [d2_min, d2_max]
    strips.each do |s|
      x_coords.push(s[0], s[1])
      y_coords.push(s[2], s[3])
    end
    x_coords = x_coords.sort.uniq
    y_coords = y_coords.sort.uniq
    @adv_cache_cells = []
    (0...x_coords.length - 1).each do |i|
      (0...y_coords.length - 1).each do |j|
        cx_min, cx_max = x_coords[i], x_coords[i + 1]
        cy_min, cy_max = y_coords[j], y_coords[j + 1]
        next if cx_max - cx_min < 0.1.mm || cy_max - cy_min < 0.1.mm
        cx_mid = (cx_min + cx_max) / 2.0
        cy_mid = (cy_min + cy_max) / 2.0
        occupied = strips.any? { |s|
          cx_mid > s[0] && cx_mid < s[1] && cy_mid > s[2] && cy_mid < s[3]
        }
        next if occupied
        clipped = clip_cell_to_face(cx_min, cx_max, cy_min, cy_max, face_2d, axis1, axis2, origin)
        next unless clipped && clipped.length >= 3
        @adv_cache_cells << [cx_min, cx_max, cy_min, cy_max, clipped]
      end
    end
  end
  def clip_cell_to_face(cx_min, cx_max, cy_min, cy_max, face_2d, axis1, axis2, origin)
    polygon = clip_polygon_edge(face_2d, 0, cx_min, true)
    return nil if polygon.length < 3
    polygon = clip_polygon_edge(polygon, 0, cx_max, false)
    return nil if polygon.length < 3
    polygon = clip_polygon_edge(polygon, 1, cy_min, true)
    return nil if polygon.length < 3
    polygon = clip_polygon_edge(polygon, 1, cy_max, false)
    return nil if polygon.length < 3
    polygon.map { |p| origin.offset(axis1, p[0]).offset(axis2, p[1]) }
  end
  def clip_polygon_edge(polygon, axis, value, keep_greater)
    result = []
    n = polygon.length
    n.times do |i|
      curr = polygon[i]
      nxt = polygon[(i + 1) % n]
      c_in = keep_greater ? curr[axis] >= value : curr[axis] <= value
      n_in = keep_greater ? nxt[axis] >= value : nxt[axis] <= value
      result << curr if c_in
      result << clip_intersect(curr, nxt, axis, value) if c_in != n_in
    end
    result
  end
  def clip_intersect(p1, p2, axis, value)
    t = (value - p1[axis]).to_f / (p2[axis] - p1[axis])
    other = 1 - axis
    result = [0.0, 0.0]
    result[axis] = value
    result[other] = p1[other] + t * (p2[other] - p1[other])
    result
  end
  def open_settings
    prompts = ["Gộp đồng phẳng:", "Mở rộng biên:", "Độ dày ván:"]
    lists = ["Có|Không", "", ""]
    defaults = [
      @gop_dong_phang ? "Có" : "Không",
      format("%.2f", @mo_rong_bien.to_mm),
      format("%.2f", @do_day.to_mm)
    ]
    values = UI.inputbox(prompts, defaults, lists, "Cài đặt")
    return false unless values
    @gop_dong_phang = values[0] == "Có"
    @mo_rong_bien = values[1].to_f.mm
    @do_day = values[2].to_f.mm
    write("gop_dong_phang", @gop_dong_phang)
    write("mo_rong_bien", format("%.2f", @mo_rong_bien.to_mm))
    write("do_day", format("%.2f", @do_day.to_mm))
    true
  end
  def build_faces_arr(entities = nil, tr = IDENTITY, faces = [], source = nil)
    entities ||= Sketchup.active_model.selection
    entities.each do |e|
      if e.is_a?(Sketchup::Face)
        material = effective_source_material(e, nil, source)
        faces << [e, tr, source, MH::Panel.material_name_from_face_path(e, nil, source), material]
      elsif MH::Panel.is_container?(e)
        e.make_unique if tr == IDENTITY
        build_faces_arr(e.definition.entities, tr * e.transformation, faces, e)
      end
    end
    faces
  end
  def quick_make_face
    @faces_arr = build_faces_arr
    return MH::Panel.select_tool(nil) if @faces_arr.empty?
    do_day = read("do_day_nhanh", 17.5).to_f.mm
    create_boards(@faces_arr, @gop_dong_phang, @mo_rong_bien, do_day)
  end
  def make_face
    return unless open_settings
    create_boards(@faces_arr, @gop_dong_phang, @mo_rong_bien, @do_day)
  end
  def create_boards(faces_arr, gop_dong_phang, mo_rong_bien, do_day)
    detail_name = current_instance_setting
    entities = MH::Panel::Model.active_entities
    MH::Panel.start
    to_erase = []
    new_boards = []
    src_mats = []
    faces_arr = MH::Panel::Face.merge_coplanar(faces_arr) if gop_dong_phang
    faces_arr.each do |f, tr, source, material_name, source_material|
      next unless f.valid?
      new_board = MH::Panel::Board.make(f, entities, mo_rong_bien, do_day)
      new_board.transform!(tr) unless tr.identity?
      new_boards << new_board
      source_material ||= effective_source_material(f, nil, source)
      mat_name = material_name || (source_material.respond_to?(:name) ? source_material.name : nil) ||
                 (f.material && f.material.respond_to?(:name) ? f.material.name : nil)
      src_mats << [mat_name, source, source_material]
      to_erase.concat(f.edges)
    end
    new_boards = MH::Panel::Group.group_to_component(new_boards) if @tao_component
    entities.erase_entities(to_erase.uniq)
    MH::Panel.commit
    MH::Panel.start
    if @tao_component
      MH::Panel::Group.reset_axes(new_boards.first, @tu_dong_xoay_van)
      MH::Panel::Group.center_origin(new_boards.first)
    else
      new_boards.each do |b|
        MH::Panel::Group.reset_axes(b, @tu_dong_xoay_van)
        MH::Panel::Group.center_origin(b)
      end
    end
    dmm = (do_day.to_mm rescue nil)
    if @tao_component
      mat_name, source, source_material = src_mats.first
      MH::Panel.apply_mh_codes(
        new_boards.first,
        detail_name: detail_name,
        thickness_mm: dmm,
        material_name: mat_name,
        source: source_for_detail_codes(source, detail_name),
        product_code: product_code_for_detail_codes(source, detail_name)
      )
      sync_material_appearance(new_boards.first.material, source_material) if source_material && new_boards.first.material
      apply_material_to_board(new_boards.first, source_material) if source_material && !new_boards.first.material
    else
      new_boards.each_with_index do |b, i|
        mat_name, source, source_material = src_mats[i]
        MH::Panel.apply_mh_codes(
          b,
          detail_name: detail_name,
          thickness_mm: dmm,
          material_name: mat_name,
          source: source_for_detail_codes(source, detail_name),
          product_code: product_code_for_detail_codes(source, detail_name)
        )
        sync_material_appearance(b.material, source_material) if source_material && b.material
        apply_material_to_board(b, source_material) if source_material && !b.material
      end
    end
    MH::Panel.select(new_boards)
    MH::Panel.commit
    MH::Panel.select_tool(nil)
  end
  private
  def calc_soft_vertices(face)
    face_edges = face.edges
    face.outer_loop.vertices.map { |v|
      (v.edges - face_edges).any? { |e|
        e.soft? || e.smooth? || e.hidden?
      }
    }
  end
  def draw_preview_box(bot, top, sv)
    n = bot.length
    MH::Panel::View.draw2d_polygon(bot)
    MH::Panel::View.draw2d_polygon(top)
    n.times { |i|
      MH::Panel::View.draw2d_polygon(
        [bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]],
        line: false
      )
    }
    n.times do |i|
      next if sv && sv[i]
      MH::Panel::View.draw2d_lines([bot[i], top[i]])
    end
  end
  def draw_boxes(view)
    sv = @locked_soft_vertices
    if @so_khoang_cach > 1 && !@tinh_theo_khong_gian && @last_face && @last_tr
      thickness = @do_day_khong_gian / 2.0
      vec_bot = @normal.clone; vec_bot.length = thickness
      vec_top = @normal.reverse; vec_top.length = thickness
      @all_box_points.each do |b|
        offset_tr = Geom::Transformation.translation(b[:bottom][0] - @locked_rect[0])
        base_tr = offset_tr * @last_tr
        bot_pts = @last_face.outer_loop.vertices.map { |v|
          v.position.transform(
            Geom::Transformation.translation(vec_bot) * base_tr
          )
        }
        top_pts = @last_face.outer_loop.vertices.map { |v|
          v.position.transform(
            Geom::Transformation.translation(vec_top) * base_tr
          )
        }
        draw_preview_box(bot_pts, top_pts, sv)
      end
      return
    end
    @all_box_points.each do |box|
      top = box[:top]
      bot = box[:bottom]
      if @so_khoang_cach == 1
        if !@tinh_theo_khong_gian && @last_face && @last_tr
          offset_tr = Geom::Transformation.translation(
            (@free ? @p2 : @p3) - @p1
          )
          new_tr = offset_tr * @last_tr
          @last_face.loops.each do |loop|
            pts = loop.vertices.map { |v|
              v.position.transform(new_tr)
            }
            MH::Panel::View.draw2d_polygon(pts)
          end
        elsif @che_do == "chinh_giua"
          vec = @normal.reverse
          vec.length = @do_day_khong_gian / 2.0
          MH::Panel::View.draw2d_polygon(bot.map { |pt| pt.offset(vec) })
        else
          MH::Panel::View.draw2d_polygon(bot)
        end
        MH::Panel::View.draw2d_loop(bot, guide: true)
        MH::Panel::View.draw2d_loop(top, guide: true)
        bot.length.times do |i|
          next if sv && sv[i]
          MH::Panel::View.draw2d_lines([bot[i], top[i]], guide: true)
        end
      else
        draw_preview_box(bot, top, sv)
      end
    end
  end
  def diem_neo
    eye = Sketchup.active_model.active_view.camera.eye
    eye.distance(@p1) >= eye.distance(@p2) ? @p1 : @p2
  end
  def draw_guides(view)
    MH::Panel::View.draw2d_lines([@p2, @p1], guide: true)
    if @so_khoang_cach == 1
      if @free
        MH::Panel::View.draw2d_lines([@p1, @p2])
      elsif @p3
        MH::Panel::View.draw2d_lines([diem_neo, @p3])
      end
    end
    if @so_khoang_cach > 1 && @all_box_points && !@all_box_points.empty?
      dir_n = @normal.normalize
      line = [@p1, dir_n]
      if @che_do_mo_rong == 1
        MH::Panel::View.draw2d_point(@p1.offset(@normal.reverse, @do_day_khong_gian))
        MH::Panel::View.draw2d_point(@p2.offset(@normal, @do_day_khong_gian))
      else
        MH::Panel::View.draw2d_point(@p1)
        MH::Panel::View.draw2d_point(@p2)
      end
      if @che_do_mo_rong == 2
        @all_box_points.each do |box|
          MH::Panel::View.draw2d_point(box[:bottom][0].project_to_line(line))
          MH::Panel::View.draw2d_point(box[:top][0].project_to_line(line))
        end
      else
        @all_box_points.each do |box|
          center = Geom.linear_combination(0.5, box[:bottom][0], 0.5, box[:top][0])
          MH::Panel::View.draw2d_point(center.project_to_line(line))
        end
      end
    else
      MH::Panel::View.draw2d_point(@p1)
      MH::Panel::View.draw2d_point(@p2)
      MH::Panel::View.draw2d_point(@p3) if @p3 && @so_khoang_cach == 1 && !@free
    end
  end
  def draw_texts(view)
    precision = MH::Panel::Model.get_unit_precision
    if @so_khoang_cach == 1
      anchor = @free ? @p1 : diem_neo
      ref = @free ? @p2 : @p3
      return unless ref
      MH::Panel::View.draw2d_text(
        format("%.#{precision}f", anchor.distance(ref).to_mm),
        Geom.linear_combination(0.5, anchor, 0.5, ref)
      )
    else
      draw_distances_text(view, precision)
    end
  end
  def draw_distances_text(view, precision)
    return unless @so_khoang_cach > 1 && @all_box_points && !@all_box_points.empty?
    dir_n = @normal.normalize
    line = [@p1, dir_n]
    fmt = -> (a, b) {
      mid = Geom.linear_combination(0.5, a, 0.5, b)
      MH::Panel::View.draw2d_text(format("%.#{precision}f", a.distance(b).to_mm), mid)
    }
    board_centers = @all_box_points
      .map { |box|
        Geom.linear_combination(0.5, box[:bottom][0], 0.5, box[:top][0]).project_to_line(line)
      }
      .sort_by { |c| (c - @p1) % dir_n }
    case @che_do_mo_rong
    when 0
      ([@p1] + board_centers + [@p2]).each_cons(2) { |a, b| fmt.(a, b) }
    when 1
      p1e = @p1.offset(@normal.reverse, @do_day_khong_gian)
      p2e = @p2.offset(@normal, @do_day_khong_gian)
      ([p1e] + board_centers + [p2e]).each_cons(2) { |a, b| fmt.(a, b) }
    when 2
      board_edges = @all_box_points.map { |box|
        b = box[:bottom][0].project_to_line(line)
        t = box[:top][0].project_to_line(line)
        (b - @p1) % dir_n < (t - @p1) % dir_n ? [b, t] : [t, b]
      }.sort_by { |pair| (pair[0] - @p1) % dir_n }
      sections = [[@p1, board_edges[0][0]]]
      (0...board_edges.length - 1).each { |i|
        sections << [board_edges[i][1], board_edges[i + 1][0]]
      }
      sections << [board_edges[-1][1], @p2]
      sections.each { |a, b| fmt.(a, b) }
    end
  end
  def clear_preview
    @rect_points = nil
    @soft_vertices = nil
    @adv_cache_face = @adv_cache_parent = nil
    @adv_cache_cells = nil
    @last_path = nil
    @p1 = nil
    @p2 = nil
    @last_face = @last_tr = @last_parent = @last_hit_point = nil
    @material = nil
  end
  def update_dynamic_point
    pt = if @ip_valid
           @ip.position.project_to_line([@p1, @normal])
         else
           Geom.closest_points([@p1, @normal], @last_ray)[0]
         end
    if @free
      @p2 = pt
    elsif @so_khoang_cach == 1
      dir = @p2 - @p1
      if dir.length > 0
        t = ((pt - @p1) % dir) / (dir % dir)
        t = [[t, 0.0].max, 1.0].min
        @p3 = Geom.linear_combination(1 - t, @p1, t, @p2)
      else
        @p3 = pt
      end
    end
  end
  def nearest_point_at_distance(distance)
    if @free
      c1 = @p1.offset(@normal, distance)
      c2 = @p1.offset(@normal.reverse, distance)
      c1.distance(@last_ray[0]) < c2.distance(@last_ray[0]) ? c1 : c2
    else
      anchor = diem_neo
      huong = anchor.distance(@p1) < anchor.distance(@p2) ? @normal : @normal.reverse
      distance = [distance, @p1.distance(@p2)].min
      anchor.offset(huong, distance)
    end
  end
  def add_box_at_point(point, vec_down, vec_up)
    vec_to_point = point - @p1
    center_rect = @locked_rect.map { |pt| pt.offset(vec_to_point) }
    bottom = center_rect.map { |pt| pt.offset(vec_down) }
    top = center_rect.map { |pt| pt.offset(vec_up) }
    @all_box_points << { bottom: bottom, top: top }
  end
end

