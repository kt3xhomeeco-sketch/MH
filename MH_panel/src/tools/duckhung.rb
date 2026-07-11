require 'set'

class MH::Panel::DucKhung
  include MH::Panel::Preset
  settings_section "duc_khung"
  def initialize
    MH::Panel.init_undo
    init_var
    reset
  end
  def activate
    reset
    @selection = collect_selection
    load_active_preset
    update_status
  end
  def deactivate(view)
    save_active_preset
    reset
    @selection = nil
    view.invalidate
  end
  def collect_selection
    Sketchup.active_model.selection.select { |e| e.valid? && MH::Panel.is_container?(e) }
  end
  def resume(view)
    @cached_parent = nil
    view.invalidate
    update_status
  end
  def init_var
    @su_dung_tiet_dien = read("su_dung_tiet_dien", false)
    @instance_tiet_dien = read("instance_tiet_dien", "ABF_DK")
    @layer_tiet_dien = read("layer_tiet_dien", "ABF_DK")
    @van_day_toi_thieu = read("van_day_toi_thieu", 15.0).to_f.mm
    @he_so_vien_kinh = 1.0
    @chieu_rong_toi_thieu = read("chieu_rong_toi_thieu", 0).to_f.mm
    @chieu_rong_khung = read("chieu_rong_khung", 80.0).to_f.mm
    @bo_dem_vien = 1
    @bo_goc_trong = read("bo_goc_trong", false)
    @bo_goc_kinh = read("bo_goc_kinh", true)
    @kieu_bo_goc = read("kieu_bo_goc", "cung_loi")
    @ban_kinh_bo_goc = read("ban_kinh_bo_goc", 100.0).to_f.mm
    @cap_do_min = read("cap_do_min", 7).to_i.clamp(1, 10)
    @tao_hem_kinh = read("tao_hem_kinh", true)
    @khu_dao_hem = read("khu_dao_hem", false)
    @chan_dan_canh_goc_khu = read("chan_dan_canh_goc_khu", false)
    @ty_le_khung = 1.0
    @view_dpi = read("view_dpi", 0, true).to_f.mm
    @chieu_rong_hem_kinh = read("chieu_rong_hem_kinh", 10.0).to_f.mm
    @instance_hem_kinh = read("instance_hem_kinh", "ABF_HK")
    @layer_hem_kinh = read("layer_hem_kinh", "ABF_HK")
    @mau_sac_hem_kinh = read("mau_sac_hem_kinh", "210,117,159")
    @mau_sac_hem_kinh = @mau_sac_hem_kinh.join(',') if @mau_sac_hem_kinh.is_a?(Array)
    @mo_phong_kinh = read("mo_phong_kinh", true)
    @do_day_kinh = read("do_day_kinh", 3.0).to_f.mm
    @can_bang_vien = 0.0.mm
    @offset_kinh = read("offset_kinh", -3.0).to_f.mm
    @sai_so_vien = 0.0.mm
    @instance_kinh = read("instance_kinh", "ABF_GL")
    @layer_kinh = read("layer_kinh", "ABF_GL")
    @mau_sac_kinh = read("mau_sac_kinh", "60,175,214")
    @mau_sac_kinh = @mau_sac_kinh.join(',') if @mau_sac_kinh.is_a?(Array)
    @presets = read("presets", nil)
    init_preset_buttons(@presets)
    init_setting_buttons(
      "Tiết diện" => {
        su_dung_tiet_dien: [:switch, "Sử dụng tiết diện"],
      },
      "Điều kiện đục khung" => {
        van_day_toi_thieu: [:mm, "Ván dày tối thiểu", nil, 0],
        chieu_rong_toi_thieu: [:mm, "Chiều rộng tối thiểu", nil, 0],
      },
      "Chiều rộng khung" => {
        chieu_rong_khung: [:mm, "Chiều rộng khung"],
      },
      "Bo góc trong" => {
        bo_goc_trong: [:switch, "Bo góc trong"],
        bo_goc_kinh: [:switch, "Bo góc kính",
          -> { @bo_goc_trong && (@tao_hem_kinh || @mo_phong_kinh) }],
        kieu_bo_goc: [:select, "Kiểu bo góc",
          {"cung_loi" => "Cung lồi", "cung_lom" => "Cung lõm",
           "vat_cheo" => "Vát chéo"}, :bo_goc_trong],
        ban_kinh_bo_goc: [:mm, "Bán kính", :bo_goc_trong],
        cap_do_min: [:raw, "Cấp độ mịn", :bo_goc_trong, 1, 10],
      },
      "Tạo hèm kính" => {
        tao_hem_kinh: [:switch, "Tạo hèm kính"],
        khu_dao_hem: [:switch, "Khử dao hèm", :tao_hem_kinh],
        chan_dan_canh_goc_khu: [:switch, "Chặn dán cạnh góc khử", -> { @tao_hem_kinh && @khu_dao_hem }],
        chieu_rong_hem_kinh: [:mm, "Chiều rộng", :tao_hem_kinh],
      },
      "Mô phỏng kính" => {
        mo_phong_kinh: [:switch, "Mô phỏng kính"],
        do_day_kinh: [:mm, "Độ dày", :mo_phong_kinh, 0],
        offset_kinh: [:mm, "Offset", :mo_phong_kinh],
      }
    )
    @offset_cache = {}
    recalc_inner_pts
  end
  def load_preset(s)
    init_preset(:su_dung_tiet_dien, s)
    init_preset(:instance_tiet_dien, s)
    init_preset(:layer_tiet_dien, s)
    init_preset(:van_day_toi_thieu, s) { |v| v.to_f.mm }
    init_preset(:chieu_rong_toi_thieu, s) { |v| v.to_f.mm }
    init_preset(:chieu_rong_khung, s) { |v| v.to_f.mm }
    init_preset(:bo_goc_trong, s)
    init_preset(:bo_goc_kinh, s)
    init_preset(:kieu_bo_goc, s)
    init_preset(:ban_kinh_bo_goc, s) { |v| v.to_f.mm }
    init_preset(:cap_do_min, s) { |v| v.to_i.clamp(1, 10) }
    init_preset(:tao_hem_kinh, s)
    init_preset(:khu_dao_hem, s)
    init_preset(:chan_dan_canh_goc_khu, s)
    init_preset(:chieu_rong_hem_kinh, s) { |v| v.to_f.mm }
    init_preset(:instance_hem_kinh, s)
    init_preset(:layer_hem_kinh, s)
    init_preset(:mau_sac_hem_kinh, s)
    init_preset(:mo_phong_kinh, s)
    init_preset(:do_day_kinh, s) { |v| v.to_f.mm }
    init_preset(:offset_kinh, s) { |v| v.to_f.mm }
    init_preset(:instance_kinh, s)
    init_preset(:layer_kinh, s)
    init_preset(:mau_sac_kinh, s)
  end
  def reset
    @cached_parent = nil
    @cached_face = nil
    @cached_pts = nil
    @cached_thickness = nil
    @cached_inner_pts = nil
    @cached_inner_pts_world = nil
    @cached_hem_pts_world = nil
    @shift_mode = false
    @original_face = nil
    @offset_cache = {}
    @cached_bo_goc_segments = nil
    @cached_bo_goc_segments_world = nil
    @cached_arc_centers = nil
    @cached_circle_pts_world = nil
    @hovered_arc_idx = nil
    @disabled_arc_indices = Set.new
    @batch_previews = nil
  end
  def update_preview
    recalc_inner_pts
  end
  def update_status
    MH::Panel.vcb("Chiều rộng khung", Sketchup.format_length(@chieu_rong_khung))
    MH::Panel.status("Giữ Shift để đảo mặt tạo hèm.")
  end
  def enableVCB?
    true
  end
  def onUserText(text, view)
    val = text.to_l.to_mm.to_f
    return if val <= 0
    @chieu_rong_khung = val.mm
    write("chieu_rong_khung", val)
    recalc_inner_pts
    update_status
    view.invalidate
  end
  def onMouseMove(flags, x, y, view)
    handle_ui_mouse_move(x, y, view)
    @mouse_x = x
    @mouse_y = y
    @shift_mode = (flags & CONSTRAIN_MODIFIER_MASK) != 0
    ph = view.pick_helper
    ph.do_pick(x, y)
    f = ph.picked_face
    tr = ph.transformation_at(0)
    parent = ph.best_picked
    unless parent && f && MH::Panel.is_container?(parent) && parent.transformation.to_a == tr.to_a
      clear_highlight
      view.invalidate
      return
    end
    cache_parent(parent)
    f = current_parent_face(f, parent)
    unless f
      clear_highlight
      view.invalidate
      return
    end
    face_pair = opposite_face_pair(f)
    unless face_pair
      clear_highlight
      view.invalidate
      return
    end
    @cached_thickness = face_pair[:thickness]
    if @van_day_toi_thieu > 0 && @cached_thickness < @van_day_toi_thieu &&
       (@cached_thickness - @van_day_toi_thieu).abs > 0.01.mm
      clear_highlight
      view.invalidate
      return
    end
    if @chieu_rong_toi_thieu > 0 && @cached_width < @chieu_rong_toi_thieu &&
       (@cached_width - @chieu_rong_toi_thieu).abs > 0.01.mm
      clear_highlight
      view.invalidate
      return
    end
    if f.loops.length >= 2 || face_pair[:opposite].loops.length >= 2
      clear_highlight
      view.invalidate
      return
    end
    @original_face = f
    picked = @shift_mode ? face_pair[:opposite] : f
    @cached_thickness = opposite_face_pair(picked)[:thickness]
    prev_face = @cached_face
    update_cached_face(picked, tr)
    prev_hover = @hovered_arc_idx
    @hovered_arc_idx = find_hover_arc_center
    view.invalidate if @cached_face != prev_face || @hovered_arc_idx != prev_hover
  end
  def onLButtonDown(flags, x, y, view)
    return if handle_setting_click(x, y, view)
    if id = handle_preset_click(x, y)
      unless id == :deselected
        index = id.to_s.split('_').last.to_i
        load_preset(@presets[index]["settings"])
      end
      view.invalidate
      return
    end
    if @hovered_arc_idx
      if @disabled_arc_indices.include?(@hovered_arc_idx)
        @disabled_arc_indices.delete(@hovered_arc_idx)
      else
        @disabled_arc_indices.add(@hovered_arc_idx)
      end
      @offset_cache = {}
      recalc_inner_pts
      view.invalidate
      return
    end
    return unless @cached_face && @cached_parent && @cached_thickness
    execute
  end

  def onKeyDown(key, repeat, flags, view)
    if key == MH::Panel::Settings.key_mo_cai_dat
      MH::Panel::Settings.open_settings('duc_khung')
      init_var
      view.invalidate
    elsif key == VK_SHIFT
      unless @shift_mode
        @shift_mode = true
        update_picked_face
        view.invalidate
      end
    end
  end

  def onKeyUp(key, repeat, flags, view)
    if key == VK_SHIFT
      if @shift_mode
        @shift_mode = false
        update_picked_face
        view.invalidate
      end
    end
  end
  def draw(view)
    draw_preset_buttons(view)
    draw_setting_buttons(view)
    return unless @cached_pts && @cached_pts.length >= 3 &&
                  @cached_inner_pts_world && @cached_inner_pts_world.length >= 3
    if @view_dpi != 0
      dpi_vec = [0, 0, @view_dpi]
      @cached_pts = @cached_pts.map { |p| p.offset(dpi_vec) }
      @cached_inner_pts_world = @cached_inner_pts_world.map { |p| p.offset(dpi_vec) }
    end
    if @cached_bo_goc_segments_world
      n = @cached_pts.length
      n.times do |i|
        j = (i + 1) % n
        MH::Panel::View.draw2d_polygon(
          [@cached_pts[i], @cached_pts[j],
           @cached_bo_goc_segments_world[j].first, @cached_bo_goc_segments_world[i].last],
          line: false
        )
      end
      @cached_bo_goc_segments_world.each_with_index do |seg, i|
        next if seg.length <= 1
        (seg.length - 1).times do |k|
          MH::Panel::View.draw2d_polygon([@cached_pts[i], seg[k], seg[k + 1]], line: false)
        end
      end
    else
      n = @cached_pts.length
      n.times do |i|
        j = (i + 1) % n
        MH::Panel::View.draw2d_polygon(
          [@cached_pts[i], @cached_pts[j], @cached_inner_pts_world[j], @cached_inner_pts_world[i]],
          line: false
        )
      end
    end
    MH::Panel::View.draw2d_loop(@cached_pts)
    MH::Panel::View.draw2d_loop(@cached_inner_pts_world)
    if @cached_circle_pts_world && @cached_normal_world
      @cached_circle_pts_world.each_with_index do |c, i|
        next unless c
        disabled = @disabled_arc_indices.include?(i)
        if i == @hovered_arc_idx
          old_weight = MH::Panel::View.edge_weight
          MH::Panel::View.set_edge_weight(old_weight + 1)
        end
        r = @chieu_rong_khung / 6.0
        if disabled && i != @hovered_arc_idx
          MH::Panel::View.draw2d_circle(c, @cached_normal_world, r, guide: true, fill: false)
        else
          MH::Panel::View.draw2d_circle(c, @cached_normal_world, r, fill: false)
        end
        MH::Panel::View.set_edge_weight(old_weight) if i == @hovered_arc_idx
      end
    end
    if @cached_hem_pts_world && @cached_hem_pts_world.length >= 3
      MH::Panel::View.draw2d_loop(@cached_hem_pts_world, guide: true)
    end
    @batch_previews&.each { |bp| draw_batch_preview(bp) }
  end
  def draw_batch_preview(bp)
    pts = bp[:pts]
    inner = bp[:inner_pts_world]
    hem = bp[:hem_pts_world]
    segments = bp[:bo_goc_segments_world]
    return unless pts && pts.length >= 3 && inner && inner.length >= 3
    if @view_dpi != 0
      dpi_vec = [0, 0, @view_dpi]
      pts = pts.map { |p| p.offset(dpi_vec) }
      inner = inner.map { |p| p.offset(dpi_vec) }
      hem = hem&.map { |p| p.offset(dpi_vec) }
      segments = segments&.map { |seg| seg.map { |p| p.offset(dpi_vec) } }
    end
    if segments
      n = pts.length
      n.times do |i|
        j = (i + 1) % n
        MH::Panel::View.draw2d_polygon(
          [pts[i], pts[j], segments[j].first, segments[i].last],
          line: false
        )
      end
      segments.each_with_index do |seg, i|
        next if seg.length <= 1
        (seg.length - 1).times do |k|
          MH::Panel::View.draw2d_polygon([pts[i], seg[k], seg[k + 1]], line: false)
        end
      end
    else
      n = pts.length
      n.times do |i|
        j = (i + 1) % n
        MH::Panel::View.draw2d_polygon([pts[i], pts[j], inner[j], inner[i]], line: false)
      end
    end
    MH::Panel::View.draw2d_loop(pts)
    MH::Panel::View.draw2d_loop(inner)
    MH::Panel::View.draw2d_loop(hem, guide: true) if hem && hem.length >= 3
  end
  def getExtents
    bb = Geom::BoundingBox.new
    bb.add(@cached_pts) if @cached_pts
    bb
  end
  private
  def cache_parent(parent)
    stale = @cached_largest_faces&.any? { |f| !f.valid? }
    return if @cached_parent == parent && !stale
    @cached_parent = parent
    parent = parent.make_unique
    @cached_parent = parent
    MH::Panel::Group.fix_scale(parent)
    @cached_largest_faces = MH::Panel::Board.get_cnc_faces(parent)
    @cached_thickness = MH::Panel::Board.calc_thickness(parent)
    @cached_face_pairs = {}
    bb = parent.definition.bounds
    @cached_width = [bb.width, bb.height, bb.depth].sort[1]
    @cached_face = nil
    @cached_pts = nil
    @cached_inner_pts = nil
    @cached_inner_pts_world = nil
    @cached_hem_pts_world = nil
    @offset_cache = {}
  end
  def clear_highlight
    @cached_face = nil
    @cached_pts = nil
    @cached_normal_world = nil
    @cached_inner_pts = nil
    @cached_inner_pts_world = nil
    @cached_hem_pts_world = nil
    @original_face = nil
    @cached_bo_goc_segments = nil
    @cached_bo_goc_segments_world = nil
    @cached_arc_centers = nil
    @cached_circle_pts_world = nil
    @hovered_arc_idx = nil
    @batch_previews = nil
  end
  def recalc_inner_pts
    return unless @cached_face && @cached_parent
    @offset_cache = {}
    old_face = @cached_face
    @cached_face = nil
    update_cached_face(old_face, @cached_parent.transformation)
  end
  def update_picked_face
    return unless @original_face && @cached_parent
    face_pair = opposite_face_pair(@original_face)
    return unless face_pair
    f = @original_face
    picked = @shift_mode ? face_pair[:opposite] : f
    @cached_thickness = opposite_face_pair(picked)[:thickness]
    update_cached_face(picked, @cached_parent.transformation)
  end
  def update_cached_face(f, tr)
    return unless f
    return if @cached_face == f
    @cached_face = f
    @offset_cache ||= {}
    verts = f.outer_loop.vertices.map { |v| v.position }
    @cached_pts = verts.map { |v| v.transform(tr) }
    @cached_normal_world = f.normal.transform(tr).normalize
    cache_key = f.entityID
    cached = @offset_cache[cache_key]
    if cached &&
       cached[:chieu_rong] == @chieu_rong_khung &&
       cached[:hem_rong] == @chieu_rong_hem_kinh &&
       cached[:gia_cong] == @tao_hem_kinh &&
       cached[:bo_goc_trong] == @bo_goc_trong &&
       cached[:kieu_bo_goc] == @kieu_bo_goc &&
       cached[:ban_kinh_bo_goc] == @ban_kinh_bo_goc &&
       cached[:cap_do_min] == @cap_do_min &&
       cached[:bo_goc_kinh] == @bo_goc_kinh
      @cached_inner_pts = cached[:inner]
      @cached_hem_pts_local = cached[:hem]
      @cached_bo_goc_segments = cached[:segments]
      @cached_arc_centers = cached[:arc_centers]
    else
      @cached_inner_pts = offset_pts_with_exact_arcs(verts, f.normal, -@chieu_rong_khung)
      if @bo_goc_trong && @ban_kinh_bo_goc > 0 && @cached_inner_pts
        @cached_inner_pts, @cached_bo_goc_segments, @cached_arc_centers =
          apply_bo_goc_to_pts(@cached_inner_pts, f.normal, @disabled_arc_indices)
      else
        @cached_bo_goc_segments = nil
        @cached_arc_centers = nil
      end
      if @tao_hem_kinh && @cached_inner_pts
        if @bo_goc_trong && @ban_kinh_bo_goc > 0 && !@bo_goc_kinh
          hem_offset = @chieu_rong_khung - @chieu_rong_hem_kinh
          @cached_hem_pts_local = offset_pts_with_exact_arcs(verts, f.normal, -hem_offset)
        else
          @cached_hem_pts_local = offset_pts_with_exact_arcs(
            @cached_inner_pts, f.normal, @chieu_rong_hem_kinh
          )
        end
      else
        @cached_hem_pts_local = nil
      end
      @offset_cache[cache_key] = {
        chieu_rong: @chieu_rong_khung, hem_rong: @chieu_rong_hem_kinh,
        gia_cong: @tao_hem_kinh,
        bo_goc_trong: @bo_goc_trong, kieu_bo_goc: @kieu_bo_goc,
        ban_kinh_bo_goc: @ban_kinh_bo_goc, cap_do_min: @cap_do_min,
        bo_goc_kinh: @bo_goc_kinh,
        inner: @cached_inner_pts, hem: @cached_hem_pts_local,
        segments: @cached_bo_goc_segments, arc_centers: @cached_arc_centers
      }
    end
    @cached_inner_pts_world = @cached_inner_pts.map { |p| p.transform(tr) } if @cached_inner_pts
    @cached_hem_pts_world = @cached_hem_pts_local&.map { |p| p.transform(tr) }
    @cached_bo_goc_segments_world = @cached_bo_goc_segments&.map { |seg|
      seg.map { |p| p.transform(tr) }
    }
    if @cached_arc_centers && @bo_goc_trong && @ban_kinh_bo_goc > 0
      c2 = offset_pts_with_exact_arcs(verts, f.normal, -@chieu_rong_khung / 2.0)
      @cached_circle_pts_world = c2 ? @cached_arc_centers.each_with_index.map { |ac, i|
        ac ? c2[i].transform(tr) : nil
      } : nil
    else
      @cached_circle_pts_world = nil
    end
    ssm = detect_soft_smooth_vertices(f)
    @cached_soft_vertices = @cached_pts.map.with_index { |_, i| ssm.key?(i) }
    compute_batch_previews
  end
  def batch_active?
    @selection && @cached_parent && @selection.length > 1 &&
      @selection.include?(@cached_parent)
  end
  def matching_disabled_arcs(target_face)
    return nil unless @cached_face && target_face
    ref_n = @cached_face.outer_loop.vertices.length
    tgt_n = target_face.outer_loop.vertices.length
    ref_n == tgt_n ? @disabled_arc_indices : nil
  end
  def compute_batch_previews
    unless batch_active? && @cached_normal_world
      @batch_previews = nil
      return
    end
    @batch_previews = []
    @selection.each do |p|
      next unless p && p.valid? && p != @cached_parent
      preview = compute_preview_for(p, @cached_normal_world)
      @batch_previews << preview if preview
    end
  end
  def compute_preview_for(parent, ref_normal_world)
    face_pair = face_pair_for_normal(parent, ref_normal_world)
    return nil unless face_pair
    target_face = face_pair[:face]
    return nil if target_face.loops.length >= 2 || face_pair[:opposite].loops.length >= 2
    thickness = face_pair[:thickness]
    if @van_day_toi_thieu > 0 && thickness < @van_day_toi_thieu &&
       (thickness - @van_day_toi_thieu).abs > 0.01.mm
      return nil
    end
    bb = parent.definition.bounds
    width = [bb.width, bb.height, bb.depth].sort[1]
    if @chieu_rong_toi_thieu > 0 && width < @chieu_rong_toi_thieu &&
       (width - @chieu_rong_toi_thieu).abs > 0.01.mm
      return nil
    end
    tr = parent.transformation
    verts = target_face.outer_loop.vertices.map { |v| v.position }
    pts_world = verts.map { |v| v.transform(tr) }
    inner_pts = offset_pts_with_exact_arcs(verts, target_face.normal, -@chieu_rong_khung)
    return nil unless inner_pts && inner_pts.length >= 3
    disabled_arcs = matching_disabled_arcs(target_face)
    bo_goc_segments = nil
    if @bo_goc_trong && @ban_kinh_bo_goc > 0
      inner_pts, bo_goc_segments, _ =
        apply_bo_goc_to_pts(inner_pts, target_face.normal, disabled_arcs)
    end
    hem_pts_local = nil
    if @tao_hem_kinh
      if @bo_goc_trong && @ban_kinh_bo_goc > 0 && !@bo_goc_kinh
        hem_offset = @chieu_rong_khung - @chieu_rong_hem_kinh
        hem_pts_local = offset_pts_with_exact_arcs(verts, target_face.normal, -hem_offset)
      else
        hem_pts_local = offset_pts_with_exact_arcs(
          inner_pts, target_face.normal, @chieu_rong_hem_kinh
        )
      end
    end
    {
      pts: pts_world,
      inner_pts_world: inner_pts.map { |p| p.transform(tr) },
      hem_pts_world: hem_pts_local&.map { |p| p.transform(tr) },
      bo_goc_segments_world: bo_goc_segments&.map { |seg|
        seg.map { |p| p.transform(tr) }
      }
    }
  end
  def execute
    parent = @cached_parent
    face = @cached_face
    thickness = @cached_thickness
    return unless parent && face && thickness
    batch_mode = @selection && @selection.any? { |e| e == parent } && @selection.length > 1
    ref_normal_world = face.normal.transform(parent.transformation).normalize
    targets = []
    if batch_mode
      @selection.each do |p|
        next unless p && p.valid?
        if p == parent
          targets << [parent, face, thickness, @disabled_arc_indices]
        else
          target = p.make_unique
          MH::Panel::Group.fix_scale(target)
          face_pair = face_pair_for_normal(target, ref_normal_world)
          next unless face_pair
          target_face = face_pair[:face]
          next if target_face.loops.length >= 2 || face_pair[:opposite].loops.length >= 2
          targets << [target, target_face, face_pair[:thickness], matching_disabled_arcs(target_face)]
        end
      end
    else
      targets << [parent, face, thickness, @disabled_arc_indices]
    end
    MH::Panel.start(false)
    begin
      targets.each { |p, f, t, d| execute_one(p, f, t, d) }
      MH::Panel.commit
    rescue => e
      MH::Panel.commit
      puts "MH::Panel::DucKhung error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
    reset
    Sketchup.active_model.active_view.invalidate
  end
  def execute_one(parent, face, thickness, disabled_arcs)
    return unless parent && parent.valid? && face && face.valid? && thickness
    if @van_day_toi_thieu > 0 && thickness < @van_day_toi_thieu &&
       (thickness - @van_day_toi_thieu).abs > 0.01.mm
      return
    end
    bb = parent.definition.bounds
    width = [bb.width, bb.height, bb.depth].sort[1]
    if @chieu_rong_toi_thieu > 0 && width < @chieu_rong_toi_thieu &&
       (width - @chieu_rong_toi_thieu).abs > 0.01.mm
      return
    end
    return if face.loops.length >= 2
    ents = parent.definition.entities
    if @su_dung_tiet_dien
      build_tiet_dien(ents, face, parent, disabled_arcs)
    else
      soft_smooth_map = detect_soft_smooth_vertices(face)
      edges_of_kept = face.edges.to_a
      faces_to_erase = ents.grep(Sketchup::Face) - [face]
      faces_to_erase.each { |f| f.erase! if f.valid? }
      ents.grep(Sketchup::Edge).each do |e|
        next if edges_of_kept.include?(e)
        e.erase! if e.valid? && e.faces.empty?
      end
      remaining_face = ents.grep(Sketchup::Face).first
      build_glass_frame(ents, remaining_face, thickness, soft_smooth_map, parent, disabled_arcs) if remaining_face&.valid?
      repair_panel_profile_curves(ents, parent)
    end
  end
  # Use the face under the cursor rather than the largest pair of faces.  A
  # thick board can have side faces larger than its intended CNC face.
  def current_parent_face(face, parent)
    return face if parent.definition.entities.include?(face)
    return nil unless face && face.valid?

    source_area = face.area
    source_center = face.bounds.center
    candidates = parent.definition.entities.grep(Sketchup::Face).select do |candidate|
      candidate.normal.dot(face.normal) > 0.999 &&
        (candidate.area - source_area).abs / [source_area, 0.001].max < 0.002
    end
    candidates.min_by { |candidate| candidate.bounds.center.distance(source_center) }
  end
  def opposite_face_pair(face, parent = @cached_parent)
    return nil unless face && face.valid? && parent && parent.valid?

    @cached_face_pairs ||= {}
    cache_key = [parent.entityID, face.entityID]
    cached = @cached_face_pairs[cache_key]
    return cached if cached && cached[:face].valid? && cached[:opposite].valid?

    source_area = face.area
    return nil if source_area <= 0

    candidates = parent.definition.entities.grep(Sketchup::Face).filter_map do |other|
      next unless other != face && other.valid?
      next unless other.normal.dot(face.normal) < -0.999

      area_delta = (other.area - source_area).abs / source_area
      next if area_delta > 0.002

      depth = face.vertices.first.position.vector_to(other.vertices.first.position).dot(face.normal)
      next if depth.abs <= 0.01.mm

      { face: face, opposite: other, thickness: depth.abs, area_delta: area_delta }
    end
    pair = candidates.min_by { |candidate| candidate[:area_delta] }
    @cached_face_pairs[cache_key] = pair if pair
    pair
  end
  def face_pair_for_normal(parent, ref_normal_world)
    return nil unless parent && parent.valid? && ref_normal_world

    candidates = parent.definition.entities.grep(Sketchup::Face).filter_map do |face|
      pair = opposite_face_pair(face, parent)
      next unless pair

      normal = face.normal.transform(parent.transformation).normalize
      { pair: pair, alignment: normal.dot(ref_normal_world) }
    end
    candidates.max_by { |candidate| candidate[:alignment] }&.fetch(:pair)
  end
  def offset_face_pts_with_exact_arcs(face, distance)
    return nil unless face && face.valid?

    points = MH::Geo::Offset.offset_face_pts(face, distance)
    return points unless points && points.length >= 3

    source_points = face.outer_loop.vertices.map(&:position)
    snap_offset_arc_runs(points, source_points, face.normal, distance)
  rescue => e
    MH::Panel.dbg("[MH::Panel::DucKhung] offset face curve error: #{e.class}: #{e.message}")
    nil
  end
  def offset_pts_with_exact_arcs(points, normal, distance)
    return nil unless points && points.length >= 3 && normal

    offset_points = MH::Geo::Offset.offset_pts(points, normal, distance)
    return offset_points unless offset_points && offset_points.length >= 3

    snap_offset_arc_runs(offset_points, points, normal, distance)
  rescue => e
    MH::Panel.dbg("[MH::Panel::DucKhung] offset curve error: #{e.class}: #{e.message}")
    nil
  end
  def snap_offset_arc_runs(offset_points, source_points, normal, distance)
    return offset_points unless source_points && source_points.length >= 3 &&
                               offset_points.length == source_points.length

    snapped = offset_points.map(&:clone)
    count = source_points.length
    MH::Geo::Offset.detect_arc_like_runs(source_points, normal).each do |start_index, edge_count|
      arc = if edge_count >= count
              MH::Geo::Offset.fit_circle_from_points(source_points, normal)
            else
              MH::Geo::Offset.fit_arc_from_points(source_points, start_index, edge_count, normal)
            end
      next unless arc

      target_radius = arc[:radius] + distance
      next if target_radius <= 0.001.mm

      offsets = edge_count >= count ? (0...edge_count) : (0..edge_count)
      offsets.each do |offset|
        index = (start_index + offset) % count
        radial = arc[:center].vector_to(source_points[index])
        next if radial.length <= 0.001.mm

        radial.normalize!
        snapped[index] = arc[:center].offset(radial, target_radius)
      end
    end
    snapped
  rescue => e
    MH::Panel.dbg("[MH::Panel::DucKhung] snap offset curve error: #{e.class}: #{e.message}")
    offset_points
  end
  def build_tiet_dien(ents, frame_face, parent, disabled_arcs)
    inner_pts = offset_face_pts_with_exact_arcs(frame_face, -@chieu_rong_khung)
    return unless inner_pts && inner_pts.length >= 3
    if @bo_goc_trong && @ban_kinh_bo_goc > 0
      inner_pts, inner_segments =
        apply_bo_goc_to_pts(inner_pts, frame_face.normal, disabled_arcs)
    else
      inner_segments = nil
    end
    layer = MH::Panel.ensure_tag(@layer_tiet_dien)
    group = ents.add_group
    group.name = @instance_tiet_dien
    group.layer = layer
    group.entities.add_curve(inner_pts + [inner_pts.first])
    group.entities.each { |e| e.layer = layer }
    MH::Panel.commit
    MH::Panel::Group.center_origin(group)
    MH::Panel.start
    if @tao_hem_kinh
      if @bo_goc_trong && @ban_kinh_bo_goc > 0 && !@bo_goc_kinh
        hem_offset = @chieu_rong_khung - @chieu_rong_hem_kinh
        hem_pts = offset_face_pts_with_exact_arcs(frame_face, -hem_offset)
      else
        hem_pts = offset_pts_with_exact_arcs(inner_pts, frame_face.normal, @chieu_rong_hem_kinh)
      end
      hem_segments = (@bo_goc_kinh || !@bo_goc_trong) ? inner_segments : nil
      build_hem(ents, inner_pts, hem_pts, hem_segments, frame_face.normal) if hem_pts && hem_pts.length >= 3
    end
    if @mo_phong_kinh
      parent_tr = parent.transformation
      if @bo_goc_trong && @ban_kinh_bo_goc > 0 && !@bo_goc_kinh
        hem_offset = @chieu_rong_khung - @chieu_rong_hem_kinh
        glass_pts = offset_face_pts_with_exact_arcs(frame_face, -hem_offset)
      else
        glass_pts = offset_pts_with_exact_arcs(
          inner_pts, frame_face.normal, @chieu_rong_hem_kinh
        )
      end
      glass_pts = inner_pts unless glass_pts && glass_pts.length >= 3
      if @offset_kinh != 0 && glass_pts.length >= 3
        offset_glass = offset_pts_with_exact_arcs(glass_pts, frame_face.normal, -@offset_kinh)
        glass_pts = offset_glass if offset_glass && offset_glass.length >= 3
      end
      world_glass_pts = glass_pts.map { |p| p.transform(parent_tr) }
      glass_layer = MH::Panel.ensure_tag(@layer_kinh)
      glass_group = MH::Panel::Model.active_entities.add_group
      glass_group.name = @instance_kinh
      glass_group.layer = glass_layer
      glass_segments = (@bo_goc_kinh || !@bo_goc_trong) ? inner_segments : nil
      draw_loop(glass_group.entities, world_glass_pts, glass_segments, nil, frame_face.normal.transform(parent_tr))
      glass_face = glass_group.entities.grep(Sketchup::Face).first
      glass_face ||= glass_group.entities.add_face(world_glass_pts)
      if glass_face
        glass_face.pushpull(-@do_day_kinh * @ty_le_khung + @sai_so_vien + @can_bang_vien) if @do_day_kinh > 0
        material = MH::Panel.create_color_mat(@mau_sac_kinh, 0.25)
        glass_group.material = material
        glass_group.entities.grep(Sketchup::Face).each do |f|
          f.material = nil
          f.back_material = nil
        end
      end
      repair_glass_profile_curves(glass_group, world_glass_pts)
      MH::Panel.commit
      MH::Panel::Group.center_origin(glass_group)
      MH::Panel.start
    end
  end
  def build_glass_frame(ents, frame_face, thickness, soft_smooth_map, parent, disabled_arcs)
    inner_pts = offset_face_pts_with_exact_arcs(frame_face, -@chieu_rong_khung)
    return unless inner_pts && inner_pts.length >= 3
    if @bo_goc_trong && @ban_kinh_bo_goc > 0
      inner_pts, inner_segments =
        apply_bo_goc_to_pts(inner_pts, frame_face.normal, disabled_arcs)
    else
      inner_segments = nil
    end
    largest_verts = frame_face.outer_loop.vertices.map { |v| v.position }
    drawn_inner_face = draw_loop(ents, inner_pts, inner_segments, nil, frame_face.normal)
    inner_face = find_inner_profile_face(ents, frame_face, inner_pts, drawn_inner_face)
    unless inner_face
      MH::Panel.intersect_fix(ents)
      inner_face = find_inner_profile_face(ents, frame_face, inner_pts)
    end
    if @mo_phong_kinh
      parent_tr = parent.transformation
      if @bo_goc_trong && @ban_kinh_bo_goc > 0 && !@bo_goc_kinh
        hem_offset = @chieu_rong_khung - @chieu_rong_hem_kinh
        glass_pts = offset_face_pts_with_exact_arcs(frame_face, -hem_offset)
      else
        glass_pts = offset_pts_with_exact_arcs(
          inner_pts, frame_face.normal, @chieu_rong_hem_kinh
        )
      end
      glass_pts = inner_pts unless glass_pts && glass_pts.length >= 3
      if @offset_kinh != 0 && glass_pts.length >= 3
        offset_glass = offset_pts_with_exact_arcs(glass_pts, frame_face.normal, -@offset_kinh)
        glass_pts = offset_glass if offset_glass && offset_glass.length >= 3
      end
      world_glass_pts = glass_pts.map { |p| p.transform(parent_tr) }
      glass_layer = MH::Panel.ensure_tag(@layer_kinh)
      glass_group = MH::Panel::Model.active_entities.add_group
      glass_group.name = @instance_kinh
      glass_group.layer = glass_layer
      glass_segments = (@bo_goc_kinh || !@bo_goc_trong) ? inner_segments : nil
      draw_loop(glass_group.entities, world_glass_pts, glass_segments, nil, frame_face.normal.transform(parent_tr))
      glass_face = glass_group.entities.grep(Sketchup::Face).first
      glass_face ||= glass_group.entities.add_face(world_glass_pts)
      if glass_face
        glass_face.pushpull(-@do_day_kinh * @ty_le_khung + @sai_so_vien + @can_bang_vien) if @do_day_kinh > 0
        material = MH::Panel.create_color_mat(@mau_sac_kinh, 0.25)
        glass_group.material = material
        glass_group.entities.grep(Sketchup::Face).each do |f|
          f.material = nil
          f.back_material = nil
        end
      end
      repair_glass_profile_curves(glass_group, world_glass_pts)
      apply_soft_smooth_at_offsets(
        glass_group.entities, soft_smooth_map, largest_verts, world_glass_pts
      )
      MH::Panel.commit
      MH::Panel::Group.center_origin(glass_group)
      MH::Panel.start
    end
    inner_face.erase! if inner_face && inner_face.valid?
    remaining_face = frame_face.valid? ? frame_face : ents.grep(Sketchup::Face).max_by(&:area)
    remaining_face.pushpull(-thickness * @ty_le_khung + @sai_so_vien) if remaining_face && remaining_face.valid?
    apply_soft_smooth_at_offsets(ents, soft_smooth_map, largest_verts, inner_pts)
    apply_soft_smooth_at_offsets(ents, soft_smooth_map, largest_verts, largest_verts)
    if @tao_hem_kinh
      if @bo_goc_trong && @ban_kinh_bo_goc > 0 && !@bo_goc_kinh
        hem_offset = @chieu_rong_khung - @chieu_rong_hem_kinh
        hem_pts = offset_face_pts_with_exact_arcs(frame_face, -hem_offset)
      else
        hem_pts = offset_pts_with_exact_arcs(inner_pts, frame_face.normal, @chieu_rong_hem_kinh)
      end
      hem_segments = (@bo_goc_kinh || !@bo_goc_trong) ? inner_segments : nil
      build_hem(ents, inner_pts, hem_pts, hem_segments, frame_face.normal) if hem_pts && hem_pts.length >= 3
    end
  end
  def repair_panel_profile_curves(ents, parent)
    profile_faces = ents.grep(Sketchup::Face).select { |face| face.valid? && face.loops.length == 2 }
    return unless profile_faces.length >= 2
    return unless profile_curve_repair_needed?(profile_faces)

    source = profile_faces.max_by(&:area)
    opposite = profile_faces.find { |face| face != source && face.normal.dot(source.normal) < -0.99 }
    return unless source && opposite

    outer_pts = source.outer_loop.vertices.map(&:position)
    inner_loop = source.loops.find { |loop| !loop.outer? }
    return unless inner_loop

    inner_pts = inner_loop.vertices.map(&:position)
    source_normal = source.normal.clone
    depth = source.vertices.first.position.vector_to(opposite.vertices.first.position).dot(source_normal)
    return if depth.abs <= 0.001.mm

    front_material = source.material
    back_material = source.back_material
    ents.grep(Sketchup::Face).each { |face| face.erase! if face.valid? }
    ents.grep(Sketchup::Edge).each { |edge| edge.erase! if edge.valid? }

    outer_face = MH::Geo::Offset.create_face_preserving_curves(ents, outer_pts, nil, nil, source_normal)
    raise 'Khong the tao lai bien ngoai co curve' unless outer_face && outer_face.valid?

    outer_face.reverse! if outer_face.normal.dot(source_normal) < 0
    outer_face.material = front_material if front_material
    outer_face.back_material = back_material if back_material

    inner_face = MH::Geo::Offset.create_face_preserving_curves(ents, inner_pts, nil, nil, source_normal)
    raise 'Khong the tao lai bien trong co curve' unless inner_face && inner_face.valid?

    inner_face.erase!
    rebuilt_face = ents.grep(Sketchup::Face).max_by(&:area)
    raise 'Khong the tao lai mat khung' unless rebuilt_face && rebuilt_face.valid?

    rebuilt_face.pushpull(depth)
    raise 'Chi tiet sau khi phuc hoi curve khong phai solid' unless MH::Geo::Solid.solid?(parent)
  end
  def find_inner_profile_face(ents, frame_face, profile_points, preferred_face = nil)
    return nil unless ents && profile_points && profile_points.length >= 3

    sample = profile_center_point(profile_points, frame_face.normal)
    return nil unless sample
    faces = ents.grep(Sketchup::Face).select { |face| face.valid? && face != frame_face }
    if preferred_face && preferred_face.valid? && faces.include?(preferred_face)
      classification = preferred_face.classify_point(sample)
      return preferred_face if classification == Sketchup::Face::PointInside ||
                               classification == Sketchup::Face::PointOnFace
    end
    faces.select do |face|
      classification = face.classify_point(sample)
      classification == Sketchup::Face::PointInside || classification == Sketchup::Face::PointOnFace
    end.min_by(&:area)
  rescue => e
    MH::Panel.dbg("[MH::Panel::DucKhung] find inner profile face error: #{e.class}: #{e.message}")
    nil
  end
  def profile_center_point(points, normal)
    circle = MH::Geo::Offset.fit_circle_from_points(points, normal) rescue nil
    return circle[:center] if circle && circle[:center]

    sum = Geom::Vector3d.new(0, 0, 0)
    points.each { |point| sum += ORIGIN.vector_to(point) }
    Geom::Point3d.new(sum.x / points.length, sum.y / points.length, sum.z / points.length)
  rescue
    nil
  end
  def repair_glass_profile_curves(glass_group, world_profile_points)
    return unless glass_group && glass_group.valid? && world_profile_points && world_profile_points.length >= 3

    ents = glass_group.entities
    source = ents.grep(Sketchup::Face).max_by(&:area)
    return unless source && source.valid?

    source_points = source.outer_loop.vertices.map(&:position)
    source_curves = source.outer_loop.edges.map(&:curve).compact.uniq
    has_generic_curve = source_curves.any? { |curve| curve.class == Sketchup::Curve rescue false }
    has_arc_run = MH::Geo::Offset.detect_arc_like_runs(source_points, source.normal).any?
    has_arc_curve = source_curves.any? { |curve| curve.is_a?(Sketchup::ArcCurve) rescue false }
    return unless has_generic_curve || (has_arc_run && !has_arc_curve)

    opposite = ents.grep(Sketchup::Face).find { |face| face != source && face.normal.dot(source.normal) < -0.99 }
    return unless opposite

    source_normal = source.normal.clone
    depth = source.vertices.first.position.vector_to(opposite.vertices.first.position).dot(source_normal)
    return if depth.abs <= 0.001.mm

    front_material = source.material
    back_material = source.back_material
    local_profile_points = world_profile_points.map { |point| point.transform(glass_group.transformation.inverse) }
    ents.grep(Sketchup::Face).each { |face| face.erase! if face.valid? }
    ents.grep(Sketchup::Edge).each { |edge| edge.erase! if edge.valid? }

    rebuilt_face = MH::Geo::Offset.create_face_preserving_curves(
      ents, local_profile_points, nil, nil, source_normal
    )
    raise 'Khong the tao lai curve kinh' unless rebuilt_face && rebuilt_face.valid?

    rebuilt_face.reverse! if rebuilt_face.normal.dot(source_normal) < 0
    rebuilt_face.material = front_material if front_material
    rebuilt_face.back_material = back_material if back_material
    rebuilt_face.pushpull(depth)
    raise 'Kinh sau khi phuc hoi curve khong phai solid' unless MH::Geo::Solid.solid?(glass_group)
  end
  def profile_curve_repair_needed?(profile_faces)
    generic_curve = profile_faces.any? do |face|
      face.loops.any? do |loop|
        loop.edges.any? { |edge| edge.curve.class == Sketchup::Curve rescue false }
      end
    end
    return true if generic_curve

    profile_faces.any? do |face|
      face.loops.any? do |loop|
        points = loop.vertices.map(&:position)
        next false if points.length < 4

        runs = MH::Geo::Offset.detect_arc_like_runs(points, face.normal)
        runs.any? && loop.edges.none? { |edge| edge.curve.is_a?(Sketchup::ArcCurve) rescue false }
      end
    end
  end
  def build_hem(frame_ents, inner_pts, hem_pts, segments = nil, normal = nil)
    hem_layer = MH::Panel.ensure_tag(@layer_hem_kinh)
    hem_group = frame_ents.add_group
    hem_group.name = @instance_hem_kinh
    ents = hem_group.entities
    draw_loop(ents, inner_pts, segments, nil, normal)
    draw_loop(ents, hem_pts, segments, nil, normal)
    longest_idx = (0...inner_pts.length).max_by { |i|
      inner_pts[i].distance(inner_pts[(i + 1) % inner_pts.length])
    }
    v1 = inner_pts[longest_idx]
    v2 = inner_pts[(longest_idx + 1) % inner_pts.length]
    v3 = hem_pts.min_by { |p| p.distance(v1) }
    v4 = hem_pts.min_by { |p| p.distance(v2) }
    e1 = ents.add_line(v1, v3)
    e2 = ents.add_line(v2, v4)
    e1.set_attribute("WPS", "temp_edge", true) if e1
    e2.set_attribute("WPS", "temp_edge", true) if e2
    e1.find_faces if e1
    e2.find_faces if e2
    ents.grep(Sketchup::Edge).each do |e|
      e.erase! if e.valid? && e.get_attribute("WPS", "temp_edge")
    end
    add_khu_dao_circles(hem_group) if @khu_dao_hem
    material = MH::Panel.create_color_mat(@mau_sac_hem_kinh, 1.0)
    ents.grep(Sketchup::Face).each { |f| f.material = material; f.back_material = material }
    ents.each { |e| e.layer = hem_layer }
    hem_group.layer = hem_layer
    MH::Panel.commit
    MH::Panel::Group.center_origin(hem_group)
    MH::Panel.start
  end
  def add_khu_dao_circles(hem_group)
    ents = hem_group.entities
    hem_face = ents.grep(Sketchup::Face).first
    return unless hem_face && hem_face.valid?
    normal = hem_face.normal
    d_dao = 6.mm
    r_dao = d_dao / 2.0
    outer_verts = hem_face.outer_loop.vertices
    n = outer_verts.size
    centers = []
    outer_verts.each_with_index do |v, i|
      prev_v = outer_verts[(i - 1) % n]
      next_v = outer_verts[(i + 1) % n]
      pos = v.position
      to_prev = pos.vector_to(prev_v.position)
      to_next = pos.vector_to(next_v.position)
      next if to_prev.length < 0.001 || to_next.length < 0.001
      angle = to_prev.angle_between(to_next)
      next unless angle > 0.001 && angle < 140.degrees
      d = to_prev.normalize + to_next.normalize
      next if d.length < 0.001
      d = d.normalize
      test_pt = pos.offset(d, 0.1.mm)
      next unless hem_face.classify_point(test_pt) == Sketchup::Face::PointInside
      vx = pos.offset(d, d_dao - 0.1.mm)
      centers << Geom.linear_combination(0.5, pos, 0.5, vx)
    end
    return if centers.empty?
    faces_before = ents.grep(Sketchup::Face)
    centers.each { |c| ents.add_circle(c, normal, r_dao, 24) }
    MH::Panel.intersect_fix(ents)
    ents.grep(Sketchup::Edge).each do |e|
      next unless e.valid?
      next unless (e.curve.is_a?(Sketchup::ArcCurve) rescue false)
      e.find_faces
    end
    if @chan_dan_canh_goc_khu
      new_faces = ents.grep(Sketchup::Face) - faces_before
      new_faces.each do |f|
        f.set_attribute("WPS", "chan_dan_canh", true) if f.valid?
      end
    end
    MH::Panel::Purge.process_coplanar_edge(ents)
  end
  def detect_soft_smooth_vertices(face)
    result = {}
    face_edges = face.edges
    face.outer_loop.vertices.each_with_index do |v, i|
      v.edges.each do |e|
        next if face_edges.include?(e)
        if e.soft? || e.smooth? || e.hidden?
          result[i] = { soft: e.soft?, smooth: e.smooth?, hidden: e.hidden? }
          break
        end
      end
    end
    result
  end
  def apply_soft_smooth_at_offsets(ents, soft_smooth_map, largest_verts, inner_pts)
    return if soft_smooth_map.empty?
    inner_edge_set = Set.new
    inner_pts.each_with_index do |_, i|
      j = (i + 1) % inner_pts.length
      inner_edge_set << [inner_pts[i], inner_pts[j]]
    end
    soft_smooth_map.each do |idx, flags|
      offset_pt = inner_pts[idx]
      next unless offset_pt
      ents.grep(Sketchup::Edge).each do |e|
        verts = e.vertices.map { |v| v.position }
        next unless verts.any? { |v| v.distance(offset_pt) < 0.1.mm }
        on_inner = inner_edge_set.any? do |a, b|
          (verts[0].distance(a) < 0.1.mm && verts[1].distance(b) < 0.1.mm) ||
          (verts[0].distance(b) < 0.1.mm && verts[1].distance(a) < 0.1.mm)
        end
        next if on_inner
        e.soft = flags[:soft] if flags[:soft]
        e.smooth = flags[:smooth] if flags[:smooth]
        e.hidden = flags[:hidden] if flags[:hidden]
      end
    end
  end
  def calc_arc_center(center, dir1, dir2, inward, face_normal, x_axis, y_axis, radius)
    case @kieu_bo_goc
    when "vat_cheo", "cung_lom"
      center
    when "cung_loi"
      e1x = center.offset(dir1, radius)
      e2x = center.offset(dir2, radius)
      bisector = Geom::Vector3d.linear_combination(0.5, dir1, 0.5, dir2).normalize
      perp1 = face_normal.cross(dir1).normalize
      perp1 = perp1.reverse if (perp1 % bisector) < 0
      perp2 = face_normal.cross(dir2).normalize
      perp2 = perp2.reverse if (perp2 % bisector) < 0
      denominator = 1 - (perp1 % perp2)
      return nil if denominator.abs < 0.001
      arc_r = (perp1 % (e2x - e1x)) / denominator
      e1x.offset(perp1, arc_r)
    end
  end
  def find_hover_arc_center
    return nil unless @mouse_x && @mouse_y && @cached_circle_pts_world && @cached_normal_world
    n = @cached_normal_world
    arb = n.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
    u = n.cross(arb).normalize
    v = n.cross(u).normalize
    @cached_circle_pts_world.each_with_index do |c, i|
      next unless c
      r = @chieu_rong_khung / 6.0
      return i if MH::Panel::View.point_in_circle_2d?(@mouse_x, @mouse_y, c, r, u, v)
    end
    nil
  end
  def draw_loop(ents, pts, segments = nil, layer = nil, normal = nil)
    if segments.nil? && normal && defined?(MH::Geo::Offset) &&
       MH::Geo::Offset.respond_to?(:create_face_preserving_curves)
      face = MH::Geo::Offset.create_face_preserving_curves(ents, pts, nil, nil, normal)
      return face if face && face.valid?
    end

    if segments
      runs = []
      idx = 0
      segments.each do |seg|
        slice = pts.slice(idx, seg.length)
        if runs.last && runs.last.last.distance(slice.first) < 0.001.mm
          runs.last.concat(slice[1..])
        else
          runs << slice.dup
        end
        idx += seg.length
      end
      if runs.length > 1 && runs.last.last.distance(runs.first.first) < 0.001.mm
        runs[0] = runs.last + runs.first[1..]
        runs.pop
      end
      runs.each_with_index do |run, ri|
        if run.length > 2
          edges = add_arc_run(ents, run, normal)
          edges ||= ents.add_curve(run)
          edges.each { |e| e.layer = layer } if layer && edges
        elsif run.length == 2
          e = ents.add_line(run[0], run[1])
          e.layer = layer if layer && e
        end
        next_run = runs[(ri + 1) % runs.length]
        p1 = run.last
        p2 = next_run.first
        next if p1.distance(p2) < 0.001.mm
        e = ents.add_line(p1, p2)
        e.layer = layer if layer && e
      end
    else
      pts.each_with_index do |p, i|
        e = ents.add_line(p, pts[(i + 1) % pts.length])
        e.layer = layer if layer && e
      end
    end
  end
  def add_arc_run(ents, run, normal)
    return nil unless normal && run && run.length >= 3

    plane_normal = normal.clone
    plane_normal.normalize!
    arc = MH::Geo::Offset.fit_arc_from_points(run, 0, run.length - 1, plane_normal)
    return nil unless arc

    arc_normal = arc[:normal]
    sweep = arc[:sweep]
    if sweep.negative?
      # SketchUp can split a negatively swept add_arc into one-edge curves.
      # Reversing the plane normal preserves the same points with a positive
      # sweep and keeps the whole corner as one ArcCurve.
      arc_normal = arc_normal.reverse
      sweep = -sweep
    end
    ents.add_arc(
      arc[:center], arc[:xaxis], arc_normal, arc[:radius],
      0.0, sweep, arc[:edge_count]
    )
  rescue => e
    MH::Panel.dbg("[MH::Panel::DucKhung] add arc run error: #{e.class}: #{e.message}")
    nil
  end
  def apply_bo_goc_to_pts(pts, face_normal, skip_indices = nil)
    n = pts.length
    return [pts, nil] if n < 3
    radius = @ban_kinh_bo_goc
    edge_lens = Array.new(n) { |i| pts[i].distance(pts[(i + 1) % n]) }
    arb = face_normal.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
    x_axis = face_normal.cross(arb).normalize
    y_axis = face_normal.cross(x_axis).normalize
    per_radius = Array.new(n, radius)
    n.times do |i|
      next if skip_indices&.include?(i)
      prev_i = (i - 1) % n
      next_i = (i + 1) % n
      if skip_indices&.include?(prev_i)
        per_radius[i] = [per_radius[i], edge_lens[prev_i]].min
      else
        per_radius[i] = [per_radius[i], edge_lens[prev_i] / 2.0].min
      end
      if skip_indices&.include?(next_i)
        per_radius[i] = [per_radius[i], edge_lens[i]].min
      else
        per_radius[i] = [per_radius[i], edge_lens[i] / 2.0].min
      end
    end
    segments = []
    arc_centers = []
    n.times do |i|
      prev_i = (i - 1) % n
      next_i = (i + 1) % n
      center = pts[i]
      r = per_radius[i]
      if r < 0.01.mm || edge_lens[prev_i] < 0.01.mm || edge_lens[i] < 0.01.mm
        segments << [pts[i]]
        arc_centers << nil
        next
      end
      dir1 = center.vector_to(pts[prev_i]).normalize
      dir2 = center.vector_to(pts[next_i]).normalize
      outgoing = pts[i].vector_to(pts[next_i])
      inward = face_normal.cross(outgoing).normalize
      if skip_indices && skip_indices.include?(i)
        segments << [pts[i]]
        arc_centers << calc_arc_center(
          center, dir1, dir2, inward, face_normal, x_axis, y_axis, r
        )
        next
      end
      case @kieu_bo_goc
      when "vat_cheo"
        segments << [center.offset(dir1, r), center.offset(dir2, r)]
        arc_centers << center
      when "cung_lom"
        a1 = Math.atan2(dir1 % y_axis, dir1 % x_axis)
        a2 = Math.atan2(dir2 % y_axis, dir2 % x_axis)
        diff = a2 - a1
        diff += 2 * Math::PI while diff < -Math::PI
        diff -= 2 * Math::PI while diff > Math::PI
        so_canh = arc_segment_count(r, diff.abs, @cap_do_min)
        segments << build_arc_points(
          center, a1, a1 + diff, r, x_axis, y_axis, so_canh
        )
        arc_centers << center
      when "cung_loi"
        e1x = center.offset(dir1, r)
        e2x = center.offset(dir2, r)
        bisector = Geom::Vector3d.linear_combination(0.5, dir1, 0.5, dir2).normalize
        perp1 = face_normal.cross(dir1).normalize
        perp1 = perp1.reverse if (perp1 % bisector) < 0
        perp2 = face_normal.cross(dir2).normalize
        perp2 = perp2.reverse if (perp2 % bisector) < 0
        denominator = 1 - (perp1 % perp2)
        if denominator.abs < 0.001
          segments << [pts[i]]
          arc_centers << nil
          next
        end
        arc_r = (perp1 % (e2x - e1x)) / denominator
        arc_c = e1x.offset(perp1, arc_r)
        mid_pt = Geom.linear_combination(0.5, e1x, 0.5, e2x)
        test_pt = arc_c.offset(arc_c.vector_to(mid_pt).normalize, arc_r.abs)
        pts_order = (test_pt - center) % inward > 0 ? [e1x, e2x] : [e2x, e1x]
        angles_arc = pts_order.map { |p| Math.atan2((p - arc_c) % y_axis, (p - arc_c) % x_axis) }
        angle_diff = angles_arc[1] - angles_arc[0]
        angle_diff += 2 * Math::PI if angle_diff < 0
        angle_diff = -(2 * Math::PI - angle_diff) if angle_diff > Math::PI
        so_canh = arc_segment_count(arc_r.abs, angle_diff.abs, @cap_do_min)
        segments << build_arc_points(arc_c, angles_arc[0], angles_arc[0] + angle_diff,
                                                arc_r.abs, x_axis, y_axis, so_canh)
        arc_centers << arc_c
      end
    end
    [segments.inject([], :+), segments, arc_centers]
  end
  def arc_segment_count(radius, angle, level)
    target_chord = (11 - level.to_i.clamp(1, 10)).mm
    [(angle.to_f * radius / target_chord).ceil, 3].max.clamp(3, 240)
  end
  def build_arc_points(center, start_angle, end_angle, radius, x_axis, y_axis, segments)
    count = [segments.to_i, 1].max
    delta = (end_angle.to_f - start_angle.to_f) / count
    (0..count).map do |index|
      angle = start_angle + delta * index
      center.offset(x_axis, Math.cos(angle) * radius).offset(y_axis, Math.sin(angle) * radius)
    end
  end
end
