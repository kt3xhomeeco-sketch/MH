class MH::Panel::TaoCanh
  include MH::Panel::Preset
  settings_section "tao_canh"
  VK_LEFT = 37
  VK_UP = 38
  VK_RIGHT = 39
  VK_DOWN = 40
  def initialize
    MH::Panel.init_undo
    @ip = Sketchup::InputPoint.new
    @ip1 = Sketchup::InputPoint.new
    init_var
    reset
  end
  def activate
    reset
    load_active_preset
  end
  def resume(view)
    update_status
    view.invalidate
  end
  def enableVCB?
    true
  end
  def deactivate(view)
    view.lock_inference if view.inference_locked?
    save_active_preset
    view.invalidate
  end
  def init_var
    @phuong_phap_ve = read("phuong_phap_ve", "2_diem")
    @tao_component = read("tao_component", false)
    @do_day = read("do_day", 17.5).to_f.mm
    @bo_dem_canh = 1
    @instance = read("instance", "")
    @layer = read("layer", "")
    @ho_deu_bien_ngoai = read("ho_deu_bien_ngoai", true)
    @ho_bien_ngoai = read("ho_bien_ngoai", 2.0).to_f.mm
    @ho_trai = read("ho_trai", 2.0).to_f.mm
    @ho_phai = read("ho_phai", 2.0).to_f.mm
    @ho_tren = read("ho_tren", 2.0).to_f.mm
    @ho_duoi = read("ho_duoi", 2.0).to_f.mm
    @ho_giua_cac_canh = read("ho_giua_cac_canh", 2.0).to_f.mm
    @do_chinh_canh_do = 1.0
    @sai_so_canh = 0.0.mm
    @ty_le_canh = 1.0
    @view_dpi = read("view_dpi", 0, true).to_f.mm
    @canh_cach_mat_goc = read("canh_cach_mat_goc", 0.0).to_f.mm
    @bu_sai_canh = 0.0.mm
    @hien_thi_kich_thuoc = read("hien_thi_kich_thuoc", false)
    @dao_chieu = read("dao_chieu", false)
    @presets = read("presets", nil)
    init_preset_buttons(@presets)
    init_setting_buttons(
      "Phương pháp" => {
        phuong_phap_ve: [:select, "Phương pháp vẽ",
          {"2_diem" => "2 điểm", "3_diem" => "3 điểm",
           "tu_do" => "Tự do", "chon_theo_canh" => "Chọn theo cạnh",
           "chon_theo_mat" => "Chọn theo mặt",
           "tam" => "Tấm",
           "bounding_box" => "Bounding Box"}],
      },
      "Tạo component" => {
        tao_component: [:switch, "Tạo component"],
      },
      "Độ dày" => {
        do_day: [:mm, "Độ dày ván"],
      },
      "Khoảng hở" => {
        ho_deu_bien_ngoai: [:switch, "Hở đều biên ngoài"],
        ho_bien_ngoai: [:mm, "Hở biên ngoài", :ho_deu_bien_ngoai],
        ho_trai: [:mm, "Hở trái", -> { !@ho_deu_bien_ngoai }],
        ho_phai: [:mm, "Hở phải", -> { !@ho_deu_bien_ngoai }],
        ho_tren: [:mm, "Hở trên", -> { !@ho_deu_bien_ngoai }],
        ho_duoi: [:mm, "Hở dưới", -> { !@ho_deu_bien_ngoai }],
        ho_giua_cac_canh: [:mm, "Hở giữa các cánh"],
      },
      "Cách mặt gốc" => {
        canh_cach_mat_goc: [:mm, "Cánh cách mặt gốc"],
      },
      "Kích thước" => {
        hien_thi_kich_thuoc: [:switch, "Hiển thị kích thước"],
      }
    )
    @che_do_tool = read("che_do_tool", "tao_canh")
    update_mode_buttons
  end
  def load_preset(s)
    init_preset(:phuong_phap_ve, s)
    init_preset(:tao_component, s)
    init_preset(:do_day, s) { |v| v.to_f.mm }
    init_preset(:instance, s)
    init_preset(:layer, s)
    init_preset(:ho_deu_bien_ngoai, s)
    init_preset(:ho_bien_ngoai, s) { |v| v.to_f.mm }
    init_preset(:ho_trai, s) { |v| v.to_f.mm }
    init_preset(:ho_phai, s) { |v| v.to_f.mm }
    init_preset(:ho_tren, s) { |v| v.to_f.mm }
    init_preset(:ho_duoi, s) { |v| v.to_f.mm }
    init_preset(:ho_giua_cac_canh, s) { |v| v.to_f.mm }
    init_preset(:canh_cach_mat_goc, s) { |v| v.to_f.mm }
    init_preset(:hien_thi_kich_thuoc, s)
  end
  def reset
    @pts = []
    @state = 0
    @ip1.clear
    @da_ve = false
    @dao_chieu = false if @dao_chieu.nil?
    @diem_chia_tang = []
    @diem_chia_khoang = []
    @tang_ho = []
    @khoang_ho = []
    @che_do_chia = :khoang
    @diem_chia_ht = nil
    @diem_neo = nil
    @ip_valid = false
    @last_ray = nil
    @locked_normal = nil
    @normal_2_diem = nil
    @noi_bo = false
    @ds_o = nil
    @o_hover = nil
    @o_hover_item = nil
    @lich_su_chia = []
    @pts_tu_do = []
    @normal_tu_do = nil
    @pt_tu_do_ht = nil
    @che_do_tool ||= "tao_canh"
    @mat_noi_bat = nil
    @pts_noi_bat = nil
    @chia_pts = nil
    @chia_truc = nil
    @chia_truc_chon = nil
    @chia_do_sau = nil
    @chia_normal = nil
    @chia_parent = nil
    @chia_ds_mat = nil
    @chia_so_luong = nil
    @edge_pick_hover = nil
    @edge_pick_first = nil
    @edge_pick_error = nil
    @face_pick_hover = nil
    @face_pick_first = nil
    @face_pick_second = nil
    @face_pick_info = nil
    @face_pick_error = nil
    @box_pick_hover = nil
    @box_pick_error = nil
    @tam_error = nil
    @box_selected_picks = []
    @box_dragging = false
    @box_drag_start = nil
    @box_drag_end = nil
    @box_ctrl_down = false
    @box_batch_preview = nil
    @batch_stage = nil
    @tam_pick_hover = nil
    @tam_selected_entities = []
    @source_entity = nil
    @source_material = nil
    @source_material_name = nil
    @chia_canh_le ||= :giua
    update_mode_buttons
    update_status
  end
  def onMouseMove(flags, x, y, view)
    handle_ui_mouse_move(x, y, view)
    if tam_mode? && @state == 0 && tam_selection_ready?
      prepare_tam_selection_preview(view)
      return
    end
    if bounding_box_mode? && @state == 0 && @box_dragging
      @box_drag_end = [x, y]
      view.invalidate
    elsif @che_do_tool == "chia_canh" && @state == 0
      unless @chia_ds_mat
        @ip.pick(view, x, y)
        chon_mat_chia(x, y, view)
      end
    elsif edge_pick_mode? && @state < 2
      update_edge_pick_hover(x, y, view)
    elsif face_pick_mode? && @state < 2
      update_face_pick_hover(x, y, view)
    elsif tam_mode? && @state == 0
      update_tam_pick_hover(x, y, view)
    elsif bounding_box_mode? && @state == 0
      update_bounding_box_hover(x, y, view)
    else
      set_current_point(x, y, view)
    end
  end
  def onLButtonDown(flags, x, y, view)
    return if handle_setting_click(x, y, view)
    return if handle_mode_click(x, y, view)
    if id = handle_preset_click(x, y)
      unless id == :deselected
        index = id.to_s.split('_').last.to_i
        load_preset(@presets[index]["settings"])
      end
      view.invalidate
      return
    else
      if bounding_box_mode? && @state == 0 && ctrl_pressed?(flags)
        @box_dragging = true
        @box_drag_start = [x, y]
        @box_drag_end = [x, y]
        update_bounding_box_hover(x, y, view)
        view.invalidate
        return
      end
      if bounding_box_mode? && @state == 0 && @box_batch_preview && !@box_batch_preview.empty?
        return
      end
      if @che_do_tool == "chia_canh" && @state == 0
        if @chia_ds_mat
          xac_nhan_chia(view)
        elsif @chia_pts
          thuc_hien_chia(view)
        end
        return
      end
      if edge_pick_mode? && @state < 2
        handle_edge_pick_click(view)
        return
      end
      if face_pick_mode?
        if @state < 2
          handle_face_pick_click(view)
          return
        end
      end
      if bounding_box_mode? && @state == 0
        handle_bounding_box_click(view)
        return
      end
      if tam_mode? && @state == 0
        if @tam_pick_hover
          toggle_tam_entity(@tam_pick_hover, view)
          return
        end
        prepare_tam_selection_preview(view)
        return
      end
      if pick_pair_inout_stage?
        enter_pick_pair_divide_stage(view) if pick_pair_inout_hit?(x, y, view)
        return
      end
      if @state == 0 && @ip.valid? && @phuong_phap_ve == "3_diem"
        return if snap_to_edge(x, y, view)
      end
      picked = set_current_point(x, y, view)
      if @state == 3
        return if pick_pair_inout_stage?
        add_division_point(view) if @diem_chia_ht
      elsif picked
        if @phuong_phap_ve == "2_diem" && @state == 1
          @ip1.copy!(@ip)
          @state = 3
          @che_do_chia = :khoang
          @ds_o = compute_global_cells if @noi_bo
          @diem_neo = @pts[1] if @pts[1]
          update_mode_buttons
          update_status
        else
          increment_state
        end
      end
    end
  end
  def onLButtonUp(flags, x, y, view)
    return unless bounding_box_mode? && @state == 0 && @box_dragging

    @box_drag_end = [x, y]
    if drag_distance(@box_drag_start, @box_drag_end) < 4
      toggle_bounding_box_pick(@box_pick_hover)
    else
      select_bounding_boxes_in_rect(view, @box_drag_start, @box_drag_end)
    end
    @box_dragging = false
    @box_drag_start = nil
    @box_drag_end = nil
    update_status
    view.invalidate
  end
  def onReturn(view)
    if pick_pair_inout_stage?
      enter_pick_pair_divide_stage(view)
      return
    end
    if batch_pair_mode? && @state == 3 && batch_preview_active?
      create_bounding_box_batch(view)
      return
    end
    if tam_mode? && @state == 0
      prepare_tam_selection_preview(view)
      return
    end
    if bounding_box_mode? && @state == 0 && bounding_box_selection_count(view) > 0
      prepare_bounding_box_batch_preview(view)
      return
    end
    if @che_do_tool == "chia_canh" && @state == 0 && @chia_ds_mat
      xac_nhan_chia(view)
      return
    end
    if @state == 4 && @phuong_phap_ve == "tu_do" && @pts_tu_do.length >= 3
      compute_free_bounding_rect
      @state = 3
      @che_do_chia = :khoang
      @ds_o = compute_global_cells if @noi_bo
      update_anchor_for_mode
      update_mode_buttons
      update_status
      view.invalidate
    elsif @state == 3
      create_rectangle
      MH::Panel.select_tool(nil)
    end
  end
  def onCancel(flag, view)
    if pick_pair_inout_stage?
      reset
      view.invalidate
      return
    end
    if batch_pair_mode? && batch_preview_active?
      @box_batch_preview = nil
      @batch_stage = nil
      @state = 0
      @pts = []
      @diem_chia_tang.clear
      @diem_chia_khoang.clear
      @tang_ho.clear
      @khoang_ho.clear
      @ds_o = nil
      @o_hover_item = nil
      update_mode_buttons
      update_status
      view.invalidate
      return
    end
    if @che_do_tool == "chia_canh" && @state == 0 && @chia_ds_mat
      @chia_ds_mat = nil
      update_status
      view.invalidate
      return
    end
    if @state == 3 && @phuong_phap_ve == "tu_do" && @pts_tu_do && @pts_tu_do.length >= 3
      @state = 4
      @diem_chia_tang.clear
      @diem_chia_khoang.clear
      @tang_ho.clear
      @khoang_ho.clear
      @ds_o = nil
      update_mode_buttons
      update_status
      view.invalidate
      return
    end
    if @state == 4 && @pts_tu_do && @pts_tu_do.length > 2
      @pts_tu_do.pop
      @normal_tu_do = nil if @pts_tu_do.length < 3
      update_status
      view.invalidate
      return
    end
    view.invalidate if @da_ve
    view.lock_inference if view.inference_locked?
    reset
  end
  def onUserText(text, view)
    if text.start_with?('/')
      num = text[1..-1].to_i
      return nil if num < 1
      if @che_do_tool == "chia_canh" && @state == 0
        preview_chia_deu(num, view)
        return
      end
      return nil unless @state == 3
      handle_division_command(num, view)
      return
    end
    if @che_do_tool == "chia_canh" && @state == 0
      begin
        val = text.to_f
        @ho_giua_cac_canh = val.mm
        write("ho_giua_cac_canh", val)
        preview_chia_deu(@chia_so_luong, view) if @chia_so_luong
        update_status
        view.invalidate
      rescue
      end
      return
    end
    handle_dimension_input(text, view)
  end

  def onKeyDown(key, rpt, flags, view)
    if key == MH::Panel::Settings.key_chuyen_che_do
      handle_tab(view)
      return true
    end
    if key == MH::Panel::Settings.key_mo_cai_dat
      MH::Panel::Settings.open_settings('tao_canh')
      return true
    end
    if key == ALT_MODIFIER_KEY
      if (@che_do_tool == "chia_canh" && @state == 0) || @state == 3
        chuyen_canh_le_chia(view)
      end
      return true
    end
    if key == COPY_MODIFIER_KEY && bounding_box_mode? && @state == 0
      @box_ctrl_down = true
      update_status
      view.invalidate
      return true
    end
    if key == 8 && @state == 3 && rpt == 1
      if undo_last_division
        update_status
        view.invalidate
      end
      return true
    end
    if @che_do_tool == "chia_canh" && @state == 0 && rpt == 1
      if key == 17
        doi_truc_chia(view)
        return true
      end
    end
    if @state == 3 && rpt == 1
      if key == 17
        return true if pick_pair_inout_stage?
        @che_do_chia = (@che_do_chia == :tang) ? :khoang : :tang
        pt_end = @che_do_chia == :khoang ? @pts[1] : @pts[3]
        if @pts[0] && pt_end
          result = project_point_to_axis(@pts[0], pt_end)
          @diem_chia_ht = (result == :no_ray) ? nil : result
        end
        update_anchor_for_mode
        update_mode_buttons
        update_status
        view.invalidate
        return true
      end
    end
    handle_arrow_lock(key, rpt, view) if @state < 3 && @che_do_tool != "chia_canh" && !measurement_pick_mode? && rpt == 1
    handle_inference_lock(key, rpt, view) if key == CONSTRAIN_MODIFIER_KEY && rpt == 1
  end
  def onKeyUp(key, rpt, flags, view)
    return if @sb_selected_item
    return true if key == ALT_MODIFIER_KEY
    if key == COPY_MODIFIER_KEY && bounding_box_mode? && @state == 0
      @box_ctrl_down = false
      update_status
      view.invalidate
      return true
    end
    if key == CONSTRAIN_MODIFIER_KEY && view.inference_locked?
      view.lock_inference
      return true
    elsif key == CONSTRAIN_MODIFIER_KEY && @state > 2
      @dao_chieu = !@dao_chieu
      write("dao_chieu", @dao_chieu)
      update_status
      view.invalidate
      return true
    end
  end

  def getExtents
    bb = Geom::BoundingBox.new
    case @state
    when 0
      bb.add(@ip.position) if @ip_valid && @ip.display?
      Array(@pts_noi_bat).each { |point| bb.add(point) }
      preview_items = @state == 3 ? bounding_box_batch_grid_items : Array(@box_batch_preview)
      Array(preview_items).each do |item|
        Array(item[:cell]).each { |point| bb.add(point) }
        vec = make_depth_vec(item[:normal], item[:depth]) rescue nil
        Array(item[:cell]).each { |point| bb.add(point.offset(vec)) } if vec
      end
      add_tam_selection_extents(bb) if tam_mode?
      add_edge_pick_extents(bb)
      add_face_pick_extents(bb)
      add_bounding_box_extents(bb)
    when 1, 2, 3
      @pts.compact.each { |pt| bb.add(pt) }
      if @state == 1
        Array(measurement_live_preview_rect(Sketchup.active_model.active_view)).each { |point| bb.add(point) }
      end
      preview_items = @state == 3 ? bounding_box_batch_grid_items : Array(@box_batch_preview)
      Array(preview_items).each do |item|
        Array(item[:cell]).each { |point| bb.add(point) }
        vec = make_depth_vec(item[:normal], item[:depth]) rescue nil
        Array(item[:cell]).each { |point| bb.add(point.offset(vec)) } if vec
      end
      add_tam_selection_extents(bb) if tam_mode?
      add_edge_pick_extents(bb)
      add_face_pick_extents(bb)
      add_bounding_box_extents(bb)
    when 4
      @pts_tu_do.each { |pt| bb.add(pt) } if @pts_tu_do
      bb.add(@pt_tu_do_ht) if @pt_tu_do_ht
    end
    bb
  end
  def draw(view)
    draw_preset_buttons(view)
    draw_setting_buttons(view)
    draw_mode_buttons(view)
    @da_ve = false
    if @che_do_tool == "chia_canh" && @state == 0
      if @ip.valid? && @ip.display? && !@chia_ds_mat
        @ip.draw(view)
        @da_ve = true
      end
      if @chia_ds_mat && @chia_normal && @chia_do_sau
        vec = make_depth_vec(@chia_normal, @chia_do_sau)
        dpi_vec = [0, 0, @view_dpi]
        @chia_ds_mat.each do |cp|
          cp = cp.map { |pt| pt.offset(dpi_vec) } if @view_dpi != 0
          top = cp.map { |pt| pt.offset(vec) }
          MH::Panel::View.draw_polygon(cp, line: false)
          MH::Panel::View.draw_polygon(top, line: false)
          cp.length.times do |i|
            j = (i + 1) % cp.length
            MH::Panel::View.draw_polygon([cp[i], cp[j], top[j], top[i]], line: false)
          end
        end
        @chia_ds_mat.each do |cp|
          top = cp.map { |pt| pt.offset(vec) }
          MH::Panel::View.draw_loop(cp, guide: true)
          MH::Panel::View.draw_loop(top, guide: true)
          cp.length.times do |i|
            MH::Panel::View.draw_lines([cp[i], top[i]], guide: true)
          end
        end
        ve_duong_chia(view) if @chia_ds_mat.length > 1
        ve_kich_thuoc_chia(@chia_ds_mat)
        @da_ve = true
      elsif @pts_noi_bat && @chia_normal && @chia_do_sau && @chia_do_sau.abs > 0.001
        draw_box(@pts_noi_bat, @chia_normal, @chia_do_sau, view, faded: true)
        if @chia_pts
          gap_dir = @chia_truc == :a \
            ? (@pts_noi_bat[1] - @pts_noi_bat[0]) \
            : (@pts_noi_bat[3] - @pts_noi_bat[0])
          ve_khe_chia(@chia_pts, gap_dir, @chia_normal, @chia_do_sau)
          draw_distance_plane(@chia_pts[0], @chia_pts[1], @chia_normal, @chia_do_sau)
          ve_kich_thuoc_chia(tinh_face_chia)
        end
        @da_ve = true
      elsif @pts_noi_bat
        MH::Panel::View.draw2d_polygon(@pts_noi_bat)
        @da_ve = true
      end
      return
    end
    if @ip_valid && @ip.display?
      @ip.draw(view)
      @da_ve = true
    end
    if edge_pick_mode?
      draw_edge_pick(view)
      if @state < 2
        @da_ve = true
        return
      end
    end
    if face_pick_mode?
      draw_face_pick(view)
      if @state < 2
        @da_ve = true
        return
      end
    end
      if bounding_box_mode?
        draw_bounding_box_pick(view)
        draw_bounding_box_selection(view)
        if @state == 0
          @da_ve = true
          return
        end
      end
    if tam_mode?
      draw_tam_selection(view)
      draw_bounding_box_selection(view)
      if @state == 0
        @da_ve = true
        return
      end
    end
    if @state == 0 && @ip_valid && @ip.edge &&
       @ip.degrees_of_freedom == 1 && @phuong_phap_ve == "3_diem"
      tr = @ip.transformation
      v1 = @ip.edge.start.position.transform(tr)
      v2 = @ip.edge.end.position.transform(tr)
      MH::Panel::View.draw_lines([v1, v2])
      @da_ve = true
    end
    if @phuong_phap_ve == "tu_do" && @state == 4
      draw_free_polygon(view)
      @da_ve = true
      return
    end
    show_rect = (@phuong_phap_ve == "2_diem" && @state == 1 &&
                 @pts[0] && @pts[1] && @pts[2] && @pts[3])
    if @phuong_phap_ve == "tu_do" && @state == 1 && @pts_tu_do.length == 1 && @pts[1]
      MH::Panel::View.draw_lines([@pts_tu_do[0], @pts[1]])
      @da_ve = true
    elsif @state == 1 && @pts[0] && @pts[1] && !show_rect
      MH::Panel::View.draw_lines([@pts[0], @pts[1]])
      @da_ve = true
    elsif show_rect || (@state >= 2 && @pts[0] && @pts[1] && @pts[2] && @pts[3])
      if batch_pair_mode? && @box_batch_preview && !@box_batch_preview.empty?
        draw_batch_division_overlay(view)
      else
        draw_grid_preview(view)
      end
      @da_ve = true
    end
  end
  def update_status
    case @state
    when 0
      if @che_do_tool == "chia_canh"
        MH::Panel.vcb("Số lượng [/x] | Khoảng hở",
                 Sketchup.format_length(@ho_giua_cac_canh))
        if @chia_ds_mat
          text = "Nhấn Tab để chuyển chế độ. " \
                 "Nhấn Enter để xác nhận. " \
                 "Nhấn Ctrl để đổi chiều chia. " \
                 "Nhấn Alt để chuyển vị trí căn khe hở."
        else
          text = "Nhấn Tab để chuyển chế độ. " \
                 "Nhấn Ctrl để đổi chiều chia. " \
                 "Nhấn Alt để chuyển vị trí căn khe hở."
        end
      else
        MH::Panel.vcb("Độ dày ván", Sketchup.format_length(@do_day))
        text = if edge_pick_mode?
                 "Chọn cạnh thứ nhất để lấy chiều dài cánh."
               elsif face_pick_mode?
                 "Chọn mặt thứ nhất."
               elsif bounding_box_mode?
                 count = bounding_box_selection_count(Sketchup.active_model.active_view)
                 if count > 0
                   preview_count = Array(@box_batch_preview).length
                   if preview_count > 0
                     "Đang xem trước #{preview_count} cánh. Enter để tạo cánh thật, Esc để quay lại chọn."
                   else
                     "Đã chọn #{count} khối. Giữ Ctrl click/quét để chọn thêm, Enter để xem trước cánh."
                   end
                 else
                   "Chọn DC hoặc Group để lấy Bounding Box phía view. Giữ Ctrl để chọn/quét nhiều khối."
                 end
               elsif tam_mode?
                 count = selected_panel_pair_entities.length
                 if count >= 2
                   "Đã chọn #{count} obj. Click thêm obj để chọn/bỏ chọn."
                 else
                   "Click chọn số lượng obj chẵn, tối thiểu 2 obj."
                 end
               else
                 "Nhấn Tab để chuyển chế độ. Chọn điểm đầu."
               end
      end
    when 1
      MH::Panel.vcb("Độ dày ván", Sketchup.format_length(@do_day))
      text = if edge_pick_mode?
               "Nhấn Tab để đảo mặt. Chọn cạnh thứ hai để lấy khoảng cách."
             elsif face_pick_mode?
               "Nhấn Tab để đảo mặt. Chọn mặt thứ hai để lấy khoảng rộng cánh."
             else
               "Nhấn Tab để đảo mặt."
             end
    when 2
      MH::Panel.vcb("Độ dày ván", Sketchup.format_length(@do_day))
      text = "Nhấn Tab để đảo mặt."
    when 3
      if pick_pair_inout_stage?
        MH::Panel.vcb("Độ dày ván", Sketchup.format_length(@do_day))
        label = tam_mode? ? "Đang xem trước cánh Tấm." : "Đang xem trước cánh Bounding Box."
        text = "#{label} " \
               "Nhấn Tab để chọn Cánh trong / Cánh ngoài. " \
               "Nhấn Enter hoặc click trái vào cánh ảo để sang bước chia cánh."
      else
        MH::Panel.vcb("Số lượng [/x] | Khoảng hở",
                 Sketchup.format_length(@ho_giua_cac_canh))
        prefix = if batch_preview_active?
                   label = tam_mode? ? "Tấm" : "Bounding Box"
                   "Đang chia #{Array(@box_batch_preview).length} cánh #{label}. "
                 else
                   ""
                 end
        text = prefix +
               "Nhấn Tab để chuyển chế độ. " \
               "Nhấn Ctrl để đổi chiều chia. " \
               "Nhấn Shift để đảo mặt. " \
               "Nhấn Alt để chuyển vị trí căn khe hở. " \
               "Nhấn Backspace để hoàn tác. " \
               "Nhấn Enter để tạo cánh thật."
      end
    when 4
      MH::Panel.vcb("Độ dày ván", Sketchup.format_length(@do_day))
      text = "Nhấn Enter để hoàn thành. Nhấn Shift để đảo mặt."
    end
    text = "#{text} #{@edge_pick_error}" if @edge_pick_error && !@edge_pick_error.empty?
    text = "#{text} #{@face_pick_error}" if @face_pick_error && !@face_pick_error.empty?
    text = "#{text} #{@box_pick_error}" if @box_pick_error && !@box_pick_error.empty?
    text = "#{text} #{@tam_error}" if @tam_error && !@tam_error.empty?
    MH::Panel.status(text)
  end
  private
  def chon_mat_chia(x, y, view)
    @chia_pts = nil
    ph = view.pick_helper
    ph.do_pick(x, y)
    face = ph.picked_face
    unless face
      @mat_noi_bat = nil
      @pts_noi_bat = nil
      view.invalidate
      return
    end
    path = ph.path_at(0)
    return unless path && !path.empty?
    tr = ph.transformation_at(0)
    parent = path.reverse.find { |e| MH::Panel.is_container?(e) }
    return unless parent
    faces = parent.definition.entities.grep(Sketchup::Face)
    largest = faces.max_by(2) { |f| f.area }
    return unless largest && largest.size == 2
    local_face = largest.find { |f| f == face }
    unless local_face
      hit_point = MH::Panel::View.calc_hit_point(face, tr, x, y, view)
      return unless hit_point
      normal = face.normal.transform(tr)
      normal.normalize!
      local_face = largest.find { |f|
        fn = f.normal.transform(tr)
        fn.normalize!
        fn.parallel?(normal)
      }
    end
    if local_face
      @mat_noi_bat = local_face
      @pts_noi_bat = local_face.outer_loop.vertices.map { |v| v.position.transform(tr) }
      if @pts_noi_bat.length == 4
        fn = local_face.normal.transform(tr)
        fn.normalize!
        if @ip.valid?
          v = @ip.position - @pts_noi_bat[0]
          hit = @ip.position.offset(fn, -(v % fn))
        else
          ray = view.pickray(x, y)
          hit = ray_hit_plane(ray, @pts_noi_bat[0], fn)
        end
        if hit
          edge_a = @pts_noi_bat[1] - @pts_noi_bat[0]
          edge_b = @pts_noi_bat[3] - @pts_noi_bat[0]
          return if edge_a.length < 0.001 || edge_b.length < 0.001
          axis = @chia_truc_chon || (edge_a.length >= edge_b.length ? :a : :b)
          edge = axis == :a ? edge_a : edge_b
          t = ((hit - @pts_noi_bat[0]) % edge.normalize) / edge.length
          t = [[t, 0.02].max, 0.98].min
          @chia_truc = axis
          if axis == :a
            @chia_pts = [
              Geom.linear_combination(1 - t, @pts_noi_bat[0], t, @pts_noi_bat[1]),
              Geom.linear_combination(1 - t, @pts_noi_bat[3], t, @pts_noi_bat[2])
            ]
          else
            @chia_pts = [
              Geom.linear_combination(1 - t, @pts_noi_bat[0], t, @pts_noi_bat[3]),
              Geom.linear_combination(1 - t, @pts_noi_bat[1], t, @pts_noi_bat[2])
            ]
          end
          other_face = largest.find { |f| f != local_face }
          if other_face
            pt_other = other_face.vertices[0].position.transform(tr)
            @chia_do_sau = (pt_other - @pts_noi_bat[0]) % fn
          end
          @chia_normal = fn
          @chia_parent = parent
        end
      end
    else
      @mat_noi_bat = nil
      @pts_noi_bat = nil
    end
    view.invalidate
  end
  def chuyen_canh_le_chia(key_or_view = nil, view = nil)
    if key_or_view.is_a?(Numeric)
      idx_offset = (key_or_view == VK_RIGHT) ? 1 : -1
    else
      view = key_or_view
      idx_offset = 1
    end
    order = [:dau, :giua, :cuoi]
    idx = order.index(@chia_canh_le) || 1
    @chia_canh_le = order[(idx + idx_offset) % 3]
    preview_chia_deu(@chia_so_luong, view) if @chia_so_luong
    update_status
    view.invalidate
  end
  def ve_khe_chia(split_pts, gap_dir, normal, depth)
    gap = @ho_giua_cac_canh
    return if gap.abs < 0.001
    return unless normal && depth != 0
    axis = gap_dir.length > 0 ? gap_dir.normalize : return
    depth_vec = make_depth_vec(normal, depth)
    p1, p2 = split_pts[0], split_pts[1]
    case @chia_canh_le
    when :dau  then ve_rect_khe(p1, p2, axis,  gap, depth_vec)
    when :cuoi then ve_rect_khe(p1, p2, axis, -gap, depth_vec)
    else
      half = gap / 2.0
      ve_rect_khe(p1, p2, axis,  half, depth_vec)
      ve_rect_khe(p1, p2, axis, -half, depth_vec)
    end
  end
  def ve_rect_khe(p1, p2, axis, dist, depth_vec)
    v = Geom::Vector3d.new(axis.x * dist, axis.y * dist, axis.z * dist)
    g1, g2 = p1.offset(v), p2.offset(v)
    MH::Panel::View.draw2d_loop([g1, g2, g2.offset(depth_vec), g1.offset(depth_vec)], guide: true)
  end
  def tinh_do_lech(gap)
    case @chia_canh_le
    when :dau  then [0, gap]
    when :cuoi then [gap, 0]
    else [gap / 2.0, gap / 2.0]
    end
  end
  def do_lech_khe
    tinh_do_lech(@ho_giua_cac_canh)
  end
  def doi_truc_chia(view)
    return unless @pts_noi_bat && @pts_noi_bat.length == 4 && @chia_pts
    sp1, sp2 = @chia_pts
    mid = Geom.linear_combination(0.5, sp1, 0.5, sp2)
    if @chia_truc == :a
      edge = @pts_noi_bat[3] - @pts_noi_bat[0]
      t = ((mid - @pts_noi_bat[0]) % edge.normalize) / edge.length
      t = [[t, 0.02].max, 0.98].min
      @chia_pts = [
        Geom.linear_combination(1 - t, @pts_noi_bat[0], t, @pts_noi_bat[3]),
        Geom.linear_combination(1 - t, @pts_noi_bat[1], t, @pts_noi_bat[2])
      ]
      @chia_truc = @chia_truc_chon = :b
    else
      edge = @pts_noi_bat[1] - @pts_noi_bat[0]
      t = ((mid - @pts_noi_bat[0]) % edge.normalize) / edge.length
      t = [[t, 0.02].max, 0.98].min
      @chia_pts = [
        Geom.linear_combination(1 - t, @pts_noi_bat[0], t, @pts_noi_bat[1]),
        Geom.linear_combination(1 - t, @pts_noi_bat[3], t, @pts_noi_bat[2])
      ]
      @chia_truc = @chia_truc_chon = :a
    end
    view.invalidate
  end
  def thuc_hien_chia(view)
    return unless @chia_parent && @chia_pts && @pts_noi_bat
    return unless @pts_noi_bat.length == 4 && @chia_do_sau && @chia_do_sau.abs > 0.001
    parent = @chia_parent
    return unless parent.valid?
    sp1, sp2 = @chia_pts
    off_a, off_b = do_lech_khe
    if @chia_truc == :a
      gap_vec = (@pts_noi_bat[1] - @pts_noi_bat[0]).normalize
      sp1a = sp1.offset(gap_vec, -off_a); sp2a = sp2.offset(gap_vec, -off_a)
      sp1b = sp1.offset(gap_vec,  off_b); sp2b = sp2.offset(gap_vec,  off_b)
      face_pts_list = [
        [@pts_noi_bat[0], sp1a, sp2a, @pts_noi_bat[3]],
        [sp1b, @pts_noi_bat[1], @pts_noi_bat[2], sp2b]
      ]
    else
      gap_vec = (@pts_noi_bat[3] - @pts_noi_bat[0]).normalize
      sp1a = sp1.offset(gap_vec, -off_a); sp2a = sp2.offset(gap_vec, -off_a)
      sp1b = sp1.offset(gap_vec,  off_b); sp2b = sp2.offset(gap_vec,  off_b)
      face_pts_list = [
        [@pts_noi_bat[0], @pts_noi_bat[1], sp2a, sp1a],
        [sp1b, sp2b, @pts_noi_bat[2], @pts_noi_bat[3]]
      ]
    end
    tao_van_chia(face_pts_list, parent, view)
  end
  def ve_duong_chia(view)
    faces = @chia_ds_mat
    axis = @chia_truc || @chia_truc_chon || :a
    (0...faces.length - 1).each do |i|
      if axis == :a
        ea1, ea2 = faces[i][1], faces[i][2]
        sb1, sb2 = faces[i + 1][0], faces[i + 1][3]
      else
        ea1, ea2 = faces[i][3], faces[i][2]
        sb1, sb2 = faces[i + 1][0], faces[i + 1][1]
      end
      case @chia_canh_le
      when :dau
        p1, p2 = ea1, ea2
      when :cuoi
        p1, p2 = sb1, sb2
      else
        p1 = Geom.linear_combination(0.5, ea1, 0.5, sb1)
        p2 = Geom.linear_combination(0.5, ea2, 0.5, sb2)
      end
      draw_distance_plane(p1, p2, @chia_normal, @chia_do_sau)
    end
  end
  def preview_chia_deu(num, view)
    return unless @chia_parent && @pts_noi_bat && @pts_noi_bat.length == 4
    return unless @chia_do_sau && @chia_do_sau.abs > 0.001
    edge_a = @pts_noi_bat[1] - @pts_noi_bat[0]
    edge_b = @pts_noi_bat[3] - @pts_noi_bat[0]
    axis = @chia_truc_chon || (edge_a.length >= edge_b.length ? :a : :b)
    total = axis == :a ? edge_a.length : edge_b.length
    gap = @ho_giua_cac_canh
    available = total - (num - 1) * gap
    return if available <= 0
    sub_size = available / num.to_f
    face_pts_list = []
    num.times do |i|
      t_start = (i * sub_size + i * gap) / total
      t_end = ((i + 1) * sub_size + i * gap) / total
      if axis == :a
        p0 = Geom.linear_combination(1 - t_start, @pts_noi_bat[0], t_start, @pts_noi_bat[1])
        p1 = Geom.linear_combination(1 - t_end, @pts_noi_bat[0], t_end, @pts_noi_bat[1])
        p2 = Geom.linear_combination(1 - t_end, @pts_noi_bat[3], t_end, @pts_noi_bat[2])
        p3 = Geom.linear_combination(1 - t_start, @pts_noi_bat[3], t_start, @pts_noi_bat[2])
      else
        p0 = Geom.linear_combination(1 - t_start, @pts_noi_bat[0], t_start, @pts_noi_bat[3])
        p1 = Geom.linear_combination(1 - t_start, @pts_noi_bat[1], t_start, @pts_noi_bat[2])
        p2 = Geom.linear_combination(1 - t_end, @pts_noi_bat[1], t_end, @pts_noi_bat[2])
        p3 = Geom.linear_combination(1 - t_end, @pts_noi_bat[0], t_end, @pts_noi_bat[3])
      end
      face_pts_list << [p0, p1, p2, p3]
    end
    @chia_ds_mat = face_pts_list
    @chia_so_luong = num
    update_status
    view.invalidate
  end
  def xac_nhan_chia(view)
    return unless @chia_parent && @chia_ds_mat && !@chia_ds_mat.empty?
    return unless @chia_do_sau && @chia_do_sau.abs > 0.001
    parent = @chia_parent
    return unless parent.valid?
    tao_van_chia(@chia_ds_mat, parent, view)
  end
  def tao_van_chia(face_pts_list, parent, view)
    ents = MH::Panel::Model.active_entities
    orig_name = parent.name
    orig_layer = parent.layer
    orig_material = parent.material
    orig_sp = (defined?(MH::ProductContext) ? MH::ProductContext.code_from_entity(parent).to_s : '') rescue ''
    MH::Panel.start
    boards = []
    face_pts_list.each do |pts|
      g = ents.add_group
      f = g.entities.add_face(pts)
      next unless f
      board = MH::Panel::Board.make(f, ents, 0, @chia_do_sau)
      tr = g.transformation
      board.transform!(tr) unless tr.identity?
      boards << board
      f.edges.each { |e| e.erase! if e.valid? }
      g.erase! if g.valid?
    end
    parent.erase! if parent.valid?
    MH::Panel.commit
    boards.each do |b|
      MH::Panel.start
      b.name = orig_name
      b.layer = orig_layer
      if orig_material
        b.material = orig_material
        b.entities.grep(Sketchup::Face).each do |f|
          f.material = nil
          f.back_material = nil
        end
      end
      MH::Panel.apply_mh_codes(
        b,
        detail_name: orig_name,
        thickness_mm: (@chia_do_sau.abs.to_mm rescue nil),
        material_name: (orig_material.respond_to?(:name) ? orig_material.name : nil),
        product_code: orig_sp
      )
      MH::Panel::Group.reset_axes(b)
      MH::Panel::Group.center_origin(b)
      MH::Panel.commit
    end
    MH::Panel.select(boards)
    reset
    view.invalidate
  end
  def set_current_point(x, y, view)
    @ip.pick(view, x, y, @ip1)
    @ip_valid = @ip.valid?
    @last_ray = view.pickray(x, y)
    remember_source_context(x, y, view) if @state == 0 && @ip_valid
    update_tooltip(view)
    result = case @state
             when 0 then pick_state0
             when 1 then pick_state1(view)
             when 2 then pick_state2(x, y, view)
             when 3 then pick_state3(x, y, view)
             when 4 then pick_state4
             end
    return result if result == false
    view.invalidate
    true
  end
  def update_tooltip(view)
    if @locked_normal
      axis_name = if @locked_normal.x.abs > 0.9 then "Normal: Red Axis"
                  elsif @locked_normal.y.abs > 0.9 then "Normal: Green Axis"
                  elsif @locked_normal.z.abs > 0.9 then "Normal: Blue Axis"
                  else "Normal: Locked"
                  end
      view.tooltip = axis_name
    elsif @ip.valid?
      view.tooltip = @ip.tooltip
    end
  end
  def pick_state0
    if @ip.valid?
      @pts[0] = @ip.position
    elsif @locked_normal && @last_ray
      pt = ray_hit_plane(@last_ray, ORIGIN, @locked_normal)
      return false unless pt
      @pts[0] = pt
    else
      return false
    end
  end
  def remember_source_context(x, y, view)
    ph = view.pick_helper
    ph.do_pick(x, y)
    face = ph.picked_face
    path = ph.path_at(0)
    source = Array(path).reverse.find { |e| MH::Panel.is_container?(e) }
    remember_source_reference(source, face, path, ph.transformation_at(0))
  rescue
    @source_entity = nil
    @source_material = nil
    @source_material_name = nil
  end
  def pick_state1(view)
    return false unless @pts[0] && @last_ray
    pt = pick_point_with_lock(@pts[0])
    return false unless pt
    pt = flatten_to_plane(pt, @pts[0]) if @locked_normal
    if @phuong_phap_ve == "2_diem"
      @normal_2_diem = @locked_normal || determine_2point_normal(@pts[0], pt)
      compute_rectangle_from_2points(@pts[0], pt, @normal_2_diem)
    else
      @pts[1] = pt
    end
  end
  def pick_state2(x, y, view)
    return false unless @pts[0] && @pts[1] && @last_ray
    pt1 = pick_point_with_lock(@pts[1])
    return false unless pt1
    if @locked_normal
      edge_vec = @pts[1] - @pts[0]
      if edge_vec.length > 0
        height_dir = @locked_normal.cross(edge_vec)
        if height_dir.length > 0
          height_dir.normalize!
          pt1 = pt1.project_to_line([@pts[1], height_dir])
        end
      end
    end
    compute_state2_rect(pt1, x, y, view)
  end
  def pick_state3(x, y, view)
    return true if pick_pair_inout_stage?

    return update_batch_noi_bo_hover(x, y, view) if @noi_bo && batch_preview_active?
    pt_end = @che_do_chia == :khoang ? @pts[1] : @pts[3]
    return false unless @pts[0] && pt_end
    if free_mode? && @normal_tu_do
      hit = pick_on_free_plane
      return false unless hit
      @diem_chia_ht = project_to_line_clamped(hit, @pts[0], pt_end)
    else
      result = project_point_to_axis(@pts[0], pt_end)
      return true if result == :no_ray
      @diem_chia_ht = result
    end
    @o_hover = find_hover_cell_idx(x, y, view) if @noi_bo
  end
  def enter_pick_pair_divide_stage(view)
    @batch_stage = :divide
    @che_do_chia = :khoang
    update_anchor_for_mode
    update_mode_buttons
    update_status
    view.invalidate
  end
  def pick_pair_inout_hit?(x, y, view)
    ray = view.pickray(x, y)
    if batch_preview_active?
      return bounding_box_batch_grid_items.any? do |item|
        cell = item[:cell]
        normal = item[:normal]
        next false unless cell && normal
        hit = ray_hit_plane(ray, cell[0], normal)
        hit && point_in_cell?(hit, cell, normal)
      end
    end
    return false unless @pts && @pts.length >= 4
    normal = get_normal
    return false unless normal && normal.length > 0

    hit = ray_hit_plane(ray, @pts[0], normal)
    hit && point_in_cell?(hit, @pts, normal)
  rescue
    false
  end
  # Nội bộ + batch: chia độc lập từng cánh. Tìm ô đang hover (box nào, ô nào),
  # tính điểm chia trong hệ trục của chính box đó.
  def update_batch_noi_bo_hover(x, y, view)
    ray = view.pickray(x, y)
    bounding_box_batch_grid_items.each do |gi|
      cell = gi[:cell]
      normal = gi[:normal]
      next unless cell && normal
      hit = ray_hit_plane(ray, cell[0], normal)
      next unless hit && point_in_cell?(hit, cell, normal)

      base = @box_batch_preview[gi[:src_idx]][:cell]
      axis_vec = (@che_do_chia == :khoang) ? (base[1] - base[0]) : (base[3] - base[0])
      next if axis_vec.length < 0.001
      t = (hit - base[0]) % axis_vec.normalize
      @o_hover_item = { src_idx: gi[:src_idx], cell_idx: gi[:cell_idx], cell: cell, base: base, dist: t }
      @diem_chia_ht = base[0].offset(axis_vec.normalize, t)
      return true
    end
    @o_hover_item = nil
    @diem_chia_ht = nil
    true
  end
  def pick_state4
    return false unless @last_ray
    if @normal_tu_do
      pt = pick_on_free_plane
    elsif @ip.valid?
      pt = @ip.position
    else
      camera_pos = view_camera_eye
      distance = camera_pos.distance(@pts_tu_do.last)
      pt = @last_ray[0].offset(@last_ray[1], distance)
    end
    return false unless pt
    @pt_tu_do_ht = pt
  end
  def pick_point_with_lock(ref_pt)
    if @ip.valid? && (!@locked_normal || @ip.face || @ip.edge)
      @ip.position
    elsif @locked_normal
      ray_hit_plane(@last_ray, ref_pt, @locked_normal) || fallback_point(ref_pt)
    else
      fallback_point(ref_pt)
    end
  end
  def fallback_point(ref_pt)
    camera_pos = view_camera_eye
    distance = camera_pos.distance(ref_pt)
    @last_ray[0].offset(@last_ray[1], distance)
  end
  def flatten_to_plane(pt, origin)
    v = pt - origin
    dist = v % @locked_normal
    pt.offset(@locked_normal, -dist)
  end
  def pick_on_free_plane
    if @ip.valid?
      v = @ip.position - @pts_tu_do[0]
      dist = (v % @normal_tu_do).abs
      if dist < 0.1.mm
        return project_to_free_plane(@ip.position)
      end
    end
    ray_hit_plane(@last_ray, @pts_tu_do[0], @normal_tu_do)
  end
  def project_to_line_clamped(hit, pt_start, pt_end)
    vec = pt_end - pt_start
    projected = hit.project_to_line([pt_start, vec])
    if vec.length > 0
      vp = projected - pt_start
      t = (vp % vec) / (vec % vec)
      t = [[t, 0.0].max, 1.0].min
      Geom.linear_combination(1 - t, pt_start, t, pt_end)
    else
      pt_start
    end
  end
  def view_camera_eye
    Sketchup.active_model.active_view.camera.eye
  end
  def increment_state
    if free_mode?
      increment_free_state
      return
    end
    @ip1.copy!(@ip) if @state < 2
    @state += 1
    if @state == 3
      @che_do_chia = :khoang
      @ds_o = compute_global_cells if @noi_bo
      update_anchor_for_mode
    end
    update_mode_buttons
    update_status
  end
  def increment_free_state
    case @state
    when 0
      @pts_tu_do = [@pts[0].clone]
      @state = 1
    when 1
      pt = @ip.valid? ? @ip.position : return
      @pts_tu_do << pt.clone
      @state = 4
    when 4
      return unless @pt_tu_do_ht
      pt = @normal_tu_do ? project_to_free_plane(@pt_tu_do_ht) : @pt_tu_do_ht.clone
      @pts_tu_do << pt
      establish_free_plane if @pts_tu_do.length == 3
    end
    @ip1.copy!(@ip) if @ip.valid?
    update_mode_buttons
    update_status
  end
  def establish_free_plane
    v1 = @pts_tu_do[1] - @pts_tu_do[0]
    v2 = @pts_tu_do[2] - @pts_tu_do[0]
    normal = v1.cross(v2)
    if normal.length > 0.001
      normal.normalize!
      @normal_tu_do = normal
    else
      @pts_tu_do.pop
    end
  end
  def snap_to_edge(x, y, view)
    return false unless @ip.edge && @ip.degrees_of_freedom == 1
    ph = view.pick_helper
    ph.do_pick(x, y)
    tr = ph.transformation_at(0)
    edge = @ip.edge
    v1 = edge.start.position.transform(tr)
    v2 = edge.end.position.transform(tr)
    mouse_pt = @ip.position
    if mouse_pt.distance(v1) < mouse_pt.distance(v2)
      @pts[0] = v1
      @pts[1] = v2
    else
      @pts[0] = v2
      @pts[1] = v1
    end
    @ip1.clear
    @state = 2
    update_mode_buttons
    update_status
    view.invalidate
    true
  end
  def update_edge_pick_hover(x, y, view)
    edge, transform, path = MH::Geo::Box.pick_edge(view, x, y)
    if edge && edge.valid?
      edges = MH::Geo::Box.connected_collinear_edges(edge)
      axis = MH::Geo::Box.edge_axis(edge, transform)
      span = MH::Geo::Box.edge_span(edges, transform)
      @edge_pick_hover = {
        edge: edge,
        edges: edges,
        transform: transform,
        path: path,
        axis: axis,
        span: span,
        length: span ? span[:length].abs : MH::Geo::Box.edges_length(edges, transform)
      }
      view.tooltip = axis == :OTHER ? "Cạnh không song song trục tọa độ" : "Chọn cạnh"
      @edge_pick_error = nil if axis != :OTHER
    else
      @edge_pick_hover = nil
      view.tooltip = nil
    end
    update_status
    view.invalidate
  end
  def handle_edge_pick_click(view)
    return unless @edge_pick_hover && @edge_pick_hover[:span]
    @che_do_tool = "tao_canh"
    unless axis_aligned_edge_pick?(@edge_pick_hover)
      @edge_pick_error = "Cạnh phải song song trục tọa độ."
      update_status
      view.invalidate
      return
    end

    if @state == 0
      @edge_pick_first = @edge_pick_hover.dup
      remember_source_context_from_path(
        @edge_pick_first[:path],
        nil,
        @edge_pick_first[:transform]
      )
      @state = 1
      @edge_pick_error = nil
      update_mode_buttons
      update_status
      view.invalidate
    elsif @state == 1
      second = @edge_pick_hover.dup
      if build_rect_from_edge_picks(@edge_pick_first, second)
        @state = 3
        @batch_stage = nil
        @che_do_chia = :khoang
        clear_division_preview_state
        @diem_neo = @pts[1]
        @ds_o = compute_global_cells if @noi_bo
        @edge_pick_error = nil
        update_mode_buttons
      end
      update_status
      view.invalidate
    end
  end
  def remember_source_context_from_path(path, face = nil, transform = nil)
    source = Array(path).reverse.find { |entity| MH::Panel.is_container?(entity) }
    remember_source_reference(source, face, path, transform)
  rescue
    @source_entity = nil
    @source_material = nil
    @source_material_name = nil
  end
  def remember_source_reference(source, face = nil, path = nil, transform = nil, inherit_thickness: true)
    @source_entity = source
    @source_material = effective_source_material(face, path, source)
    @source_material_name = MH::Panel.material_name_from_face_path(face, path, source)
    if @source_material_name.to_s.empty? && @source_material.respond_to?(:name)
      @source_material_name = @source_material.name
    end
    if inherit_thickness
      thickness = source_reference_thickness(source, transform)
      @do_day = thickness if thickness && thickness > 0.001.mm
    end
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
  def source_reference_thickness(source, transform = nil)
    return nil unless source && source.valid?
    local_thickness = MH::Panel::Board.calc_thickness(source)
    return nil unless local_thickness && local_thickness > 0

    faces = source.definition.entities.grep(Sketchup::Face)
    thickness_face = faces.max_by(&:area)
    return local_thickness unless thickness_face

    tr = transform || source.transformation
    scaled_normal = thickness_face.normal.transform(tr)
    scale = scaled_normal.length
    scale > 0 ? local_thickness * scale : local_thickness
  rescue
    nil
  end
  def remember_bounding_box_reference(pick)
    source = pick[:source]
    remember_source_reference(
      source,
      pick[:face],
      pick[:path],
      pick[:transform],
      inherit_thickness: false
    )

    profile = nested_panel_profile(source, pick[:transform])
    @source_material ||= profile[:material]
    if @source_material_name.to_s.empty? && @source_material.respond_to?(:name)
      @source_material_name = @source_material.name
    end
    thickness = profile[:thickness] || source_reference_thickness(source, pick[:transform])
    @do_day = thickness if thickness && thickness > 0.001.mm
  end
  def nested_panel_profile(source, source_transform)
    candidates = []
    collect_nested_panel_candidates(source, source_transform, candidates, 0, true)
    return {} if candidates.empty?

    material_counts = Hash.new(0)
    candidates.each do |candidate|
      material_counts[candidate[:material]] += candidate[:weight] if candidate[:material]
    end
    material = material_counts.max_by { |_material, weight| weight }&.first

    thicknesses = candidates.filter_map do |candidate|
      next unless candidate[:thickness]
      next if material && candidate[:material] && candidate[:material] != material
      candidate[:thickness]
    end
    thickness = dominant_panel_thickness(thicknesses)
    { material: material, thickness: thickness }
  rescue => e
    puts "[MH::Panel::TaoCanh] nested panel profile error: #{e.class}: #{e.message}"
    {}
  end
  def collect_nested_panel_candidates(entity, transform, candidates, depth, root = false)
    return if depth > 8 || !entity || (entity.respond_to?(:valid?) && !entity.valid?)

    material = entity.material if entity.respond_to?(:material)
    unless root
      thickness = source_reference_thickness(entity, transform) if MH::Panel.is_container?(entity)
      if material || thickness
        candidates << {
          material: material,
          thickness: thickness,
          weight: thickness ? 10 : 2
        }
      end
    end

    entities = if entity.is_a?(Sketchup::Group)
                 entity.entities
               elsif entity.is_a?(Sketchup::ComponentInstance)
                 entity.definition.entities
               else
                 nil
               end
    return unless entities

    entities.each do |child|
      if MH::Panel.is_container?(child)
        collect_nested_panel_candidates(
          child,
          transform * child.transformation,
          candidates,
          depth + 1
        )
      elsif child.is_a?(Sketchup::Face)
        face_material = child.material || child.back_material
        candidates << { material: face_material, thickness: nil, weight: 1 } if face_material
      end
    end
  end
  def dominant_panel_thickness(thicknesses)
    valid = Array(thicknesses).select { |value|
      value && value > 2.mm && value < 80.mm
    }
    return nil if valid.empty?

    groups = valid.group_by { |value| (value.to_mm * 10).round }
    groups.max_by { |_key, values| values.length }&.last&.first
  end
  def axis_aligned_edge_pick?(pick)
    pick && pick[:axis] && pick[:axis] != :OTHER && pick[:span] && pick[:length].to_f > 0.001.mm
  end
  def build_rect_from_edge_picks(first, second)
    rect = edge_rect_from_picks(first, second, set_error: true)
    return false unless rect

    @pts[0], @pts[1], @pts[2], @pts[3] = rect
    true
  end
  def edge_rect_from_picks(first, second, set_error: false)
    unless axis_aligned_edge_pick?(first) && axis_aligned_edge_pick?(second)
      @edge_pick_error = "Cạnh phải song song trục tọa độ." if set_error
      return nil
    end
    unless first[:axis] == second[:axis]
      @edge_pick_error = "Hai cạnh phải song song nhau." if set_error
      return nil
    end

    base = first
    other = second
    base_span = base[:span]
    other_span = other[:span]
    axis = base_span[:axis].clone
    axis.normalize!
    offset_vec = projected_axis_offset_between_lines(base_span[:line], other_span[:line], axis)
    unless offset_vec && offset_vec.length > 0.001.mm
      @edge_pick_error = "Không đo được hình chiếu khoảng cách giữa 2 cạnh." if set_error
      return nil
    end

    length = [first[:length].abs, second[:length].abs].min
    p0 = base_span[:start]
    p1 = p0.offset(axis, length)
    p3 = p0.offset(offset_vec)
    p2 = p1.offset(offset_vec)
    [p0, p1, p2, p3]
  rescue => e
    @edge_pick_error = "Không dựng được cánh từ cạnh: #{e.message}" if set_error
    nil
  end
  def projected_axis_offset_between_lines(base_line, other_line, axis)
    base_pt, = base_line
    other_pt, = other_line
    raw = base_pt.vector_to(other_pt)
    along = raw.dot(axis)
    axis_component = Geom::Vector3d.new(axis.x * along, axis.y * along, axis.z * along)
    perpendicular = raw - axis_component
    projection_axis = best_world_projection_axis(perpendicular, axis)
    return nil unless projection_axis

    distance = perpendicular.dot(projection_axis)
    return nil if distance.abs <= 0.001.mm

    Geom::Vector3d.new(
      projection_axis.x * distance,
      projection_axis.y * distance,
      projection_axis.z * distance
    )
  end
  def best_world_projection_axis(vector, edge_axis)
    return nil unless vector && vector.length > 0.001.mm

    candidates = [X_AXIS, Y_AXIS, Z_AXIS].reject do |candidate|
      candidate.parallel?(edge_axis) || candidate.reverse.parallel?(edge_axis)
    end
    candidates.max_by { |candidate| (vector.dot(candidate)).abs }
  end
  def draw_edge_pick(view)
    draw_edge_pick_group(view, @edge_pick_first, Sketchup::Color.new(0, 180, 255, 255), 4)
    draw_edge_pick_group(view, @edge_pick_hover, Sketchup::Color.new(255, 200, 0, 255), 3)
    draw_edge_pick_live_preview(view)
  end
  def draw_edge_pick_live_preview(view)
    return unless @state == 1 && @edge_pick_first && @edge_pick_hover
    rect = edge_rect_from_picks(@edge_pick_first, @edge_pick_hover)
    return unless rect

    normal = normal_from_points(rect)
    return unless normal && normal.length > 0

    depth = @dao_chieu ? @do_day : -@do_day
    draw_box(rect, normal, depth, view, faded: true)
  end
  def draw_edge_pick_group(view, pick, color, width)
    return unless pick && pick[:edges] && pick[:transform]

    view.line_stipple = ''
    view.line_width = width
    view.drawing_color = color
    pick[:edges].each do |edge|
      next unless edge && edge.valid?

      view.draw(GL_LINES, [
        edge.start.position.transform(pick[:transform]),
        edge.end.position.transform(pick[:transform])
      ])
    end
  end
  def add_edge_pick_extents(bb)
    [@edge_pick_hover, @edge_pick_first].compact.each do |pick|
      MH::Geo::Box.edge_endpoints(pick[:edges], pick[:transform]).each { |point| bb.add(point) }
    end
  end
  def update_face_pick_hover(x, y, view)
    face, transform, path = MH::Geo::Box.pick_face(view, x, y)
    if face && face.valid?
      @face_pick_hover = build_face_pick(face, transform, path)
      view.tooltip = @face_pick_hover[:axis] == :OTHER ? "Mặt không song song trục tọa độ" : "Chọn mặt"
      @face_pick_error = nil if @face_pick_hover[:axis] != :OTHER
    else
      @face_pick_hover = nil
      view.tooltip = nil
    end
    update_status
    view.invalidate
  end
  def build_face_pick(face, transform, path)
    points = MH::Geo::Box.face_points(face, transform)
    normal = MH::Geo::Box.face_normal(face, transform)
    {
      face: face,
      transform: transform,
      path: path,
      points: points,
      normal: normal,
      axis: vector_axis(normal),
      bounds: bounds_from_points(points)
    }
  end
  def handle_face_pick_click(view)
    return unless @face_pick_hover && @face_pick_hover[:points]&.length.to_i >= 3
    @che_do_tool = "tao_canh"
    unless axis_aligned_face_pick?(@face_pick_hover)
      @face_pick_error = "Mặt phải song song trục tọa độ."
      update_status
      view.invalidate
      return
    end

    if @state == 0
      @face_pick_first = @face_pick_hover.dup
      remember_source_context_from_path(
        @face_pick_first[:path],
        @face_pick_first[:face],
        @face_pick_first[:transform]
      )
      @state = 1
      @face_pick_error = nil
      update_mode_buttons
      update_status
      view.invalidate
    elsif @state == 1
      second = @face_pick_hover.dup
      if build_face_pair_info(@face_pick_first, second, view) && build_rect_from_face_view_boundary(view)
        @face_pick_second = second
        @state = 3
        @batch_stage = nil
        @che_do_chia = :khoang
        clear_division_preview_state
        @diem_neo = @pts[1]
        @ds_o = compute_global_cells if @noi_bo
        @face_pick_error = nil
        update_mode_buttons
      end
      update_status
      view.invalidate
    end
  end
  def axis_aligned_face_pick?(pick)
    pick && pick[:axis] && pick[:axis] != :OTHER && pick[:points]&.length.to_i >= 3
  end
  def build_face_pair_info(first, second, view = Sketchup.active_model.active_view)
    info = face_pair_info(first, second, view, set_error: true)
    return false unless info

    @face_pick_info = info
    true
  end
  def face_pair_info(first, second, view = Sketchup.active_model.active_view, set_error: false)
    unless axis_aligned_face_pick?(first) && axis_aligned_face_pick?(second)
      @face_pick_error = "Mặt phải song song trục tọa độ." if set_error
      return nil
    end
    unless first[:axis] == second[:axis]
      @face_pick_error = "Hai mặt phải song song nhau." if set_error
      return nil
    end

    gap_axis = signed_axis_vector(first[:normal])
    center1 = points_center(first[:points])
    center2 = points_center(second[:points])
    gap = center1.vector_to(center2).dot(gap_axis)
    if gap.abs <= 0.001.mm
      @face_pick_error = "Không đo được khoảng cách giữa 2 mặt." if set_error
      return nil
    end
    gap_axis.reverse! if gap < 0
    gap = gap.abs

    length_axis, length = face_pick_length_axis(first, gap_axis)
    unless length_axis && length && length > 0.001.mm
      @face_pick_error = "Không đo được chiều dài cánh từ mặt." if set_error
      return nil
    end
    placement_axis = remaining_world_axis(gap_axis, length_axis)
    unless placement_axis
      @face_pick_error = "Không xác định được mặt phẳng đặt cánh." if set_error
      return nil
    end
    {
      first: first,
      gap_axis: gap_axis,
      gap: gap,
      length_axis: length_axis,
      length: length,
      placement_axis: placement_axis,
      camera_eye: view.camera.eye
    }
  rescue => e
    @face_pick_error = "Không dựng được cánh từ mặt: #{e.message}" if set_error
    nil
  end
  def build_rect_from_face_view_boundary(view = Sketchup.active_model.active_view)
    info = @face_pick_info
    rect = face_rect_from_info(info, view, set_error: true)
    return false unless rect

    @pts[0], @pts[1], @pts[2], @pts[3] = rect
    true
  end
  def face_rect_from_info(info, view = Sketchup.active_model.active_view, set_error: false)
    return nil unless info && info[:first]

    points = info[:first][:points]
    gap_coord = points.map { |point| (point - ORIGIN).dot(info[:gap_axis]) }.sum / points.length
    length_coords = points.map { |point| (point - ORIGIN).dot(info[:length_axis]) }
    placement_coords = points.map { |point| (point - ORIGIN).dot(info[:placement_axis]) }
    camera_coord = (view.camera.eye - ORIGIN).dot(info[:placement_axis])
    boundary_coord = placement_coords.minmax.min_by { |coord| (camera_coord - coord).abs }
    p0 = ORIGIN.offset(info[:gap_axis], gap_coord)
               .offset(info[:length_axis], length_coords.min)
               .offset(info[:placement_axis], boundary_coord)
    p1 = p0.offset(info[:gap_axis], info[:gap])
    p3 = p0.offset(info[:length_axis], info[:length])
    p2 = p1.offset(info[:length_axis], info[:length])
    [p0, p1, p2, p3]
  rescue => e
    @face_pick_error = "Không xác định được biên phía view: #{e.message}" if set_error
    nil
  end
  def face_pick_length_axis(face_pick, gap_axis)
    bounds = face_pick[:bounds]
    candidates = [
      [X_AXIS, bounds.max.x - bounds.min.x],
      [Y_AXIS, bounds.max.y - bounds.min.y],
      [Z_AXIS, bounds.max.z - bounds.min.z]
    ].reject { |axis, _| axis.parallel?(gap_axis) || axis.reverse.parallel?(gap_axis) }
    axis, length = candidates.max_by { |_, len| len.abs }
    return nil unless axis && length && length.abs > 0.001.mm

    [axis.clone, length.abs]
  end
  def remaining_world_axis(first_axis, second_axis)
    [X_AXIS, Y_AXIS, Z_AXIS].find do |axis|
      !axis.parallel?(first_axis) && !axis.reverse.parallel?(first_axis) &&
        !axis.parallel?(second_axis) && !axis.reverse.parallel?(second_axis)
    end&.clone
  end
  def vector_axis(vector)
    return :OTHER unless vector && vector.length > 0.001.mm

    dir = vector.clone
    dir.normalize!
    return :X if dir.parallel?(X_AXIS) || dir.parallel?(X_AXIS.reverse)
    return :Y if dir.parallel?(Y_AXIS) || dir.parallel?(Y_AXIS.reverse)
    return :Z if dir.parallel?(Z_AXIS) || dir.parallel?(Z_AXIS.reverse)

    :OTHER
  end
  def signed_axis_vector(vector)
    axis = case vector_axis(vector)
           when :X then X_AXIS.clone
           when :Y then Y_AXIS.clone
           when :Z then Z_AXIS.clone
           else nil
           end
    return nil unless axis

    axis.reverse! if vector.dot(axis) < 0
    axis
  end
  def bounds_from_points(points)
    bounds = Geom::BoundingBox.new
    points.each { |point| bounds.add(point) }
    bounds
  end
  def points_center(points)
    Geom::Point3d.new(
      points.map(&:x).sum / points.length,
      points.map(&:y).sum / points.length,
      points.map(&:z).sum / points.length
    )
  end
  def draw_face_pick(view)
    draw_face_pick_group(view, @face_pick_first, Sketchup::Color.new(0, 180, 255, 80), Sketchup::Color.new(0, 180, 255, 255))
    draw_face_pick_group(view, @face_pick_second, Sketchup::Color.new(0, 255, 120, 80), Sketchup::Color.new(0, 180, 90, 255))
    draw_face_pick_group(view, @face_pick_hover, Sketchup::Color.new(255, 200, 0, 80), Sketchup::Color.new(255, 200, 0, 255))
    draw_face_pick_live_preview(view)
  end
  def draw_face_pick_live_preview(view)
    return unless @state == 1 && @face_pick_first && @face_pick_hover

    info = face_pair_info(@face_pick_first, @face_pick_hover, view)
    rect = face_rect_from_info(info, view)
    return unless rect

    normal = normal_from_points(rect)
    return unless normal && normal.length > 0

    depth = @dao_chieu ? @do_day : -@do_day
    draw_box(rect, normal, depth, view, faded: true)
  end
  def draw_face_pick_group(view, pick, fill_color, line_color)
    return unless pick && pick[:points] && pick[:points].length >= 3

    view.drawing_color = fill_color
    view.draw(GL_POLYGON, pick[:points])
    view.line_width = 3
    view.drawing_color = line_color
    view.draw(GL_LINE_LOOP, pick[:points])
  end
  def add_face_pick_extents(bb)
    [@face_pick_hover, @face_pick_first, @face_pick_second].compact.each do |pick|
      Array(pick[:points]).each { |point| bb.add(point) }
    end
  end
  def measurement_live_preview_rect(view)
    if edge_pick_mode? && @state == 1 && @edge_pick_first && @edge_pick_hover
      edge_rect_from_picks(@edge_pick_first, @edge_pick_hover)
    elsif face_pick_mode? && @state == 1 && @face_pick_first && @face_pick_hover
      info = face_pair_info(@face_pick_first, @face_pick_hover, view)
      face_rect_from_info(info, view)
    end
  rescue
    nil
  end
  def update_bounding_box_hover(x, y, view)
    pick_helper = view.pick_helper
    pick_helper.do_pick(x, y, 10)
    path = nil
    source = nil
    face = nil
    (0...pick_helper.count).each do |index|
      candidate_path = pick_helper.path_at(index)
      candidate = Array(candidate_path).find { |entity| MH::Panel.is_container?(entity) }
      next unless candidate && candidate.valid?

      path = candidate_path
      source = candidate
      face = Array(candidate_path).find { |entity| entity.is_a?(Sketchup::Face) }
      break
    end
    unless source
      @box_pick_hover = nil
      @box_pick_error = nil
      view.tooltip = nil
      view.invalidate
      return
    end

    transform = transform_to_path_entity(path, source)
    @box_pick_hover = build_bounding_box_pick(source, transform, view, path, face)
    @box_pick_error = @box_pick_hover ? nil : "Không xác định được Bounding Box."
    view.tooltip = @box_pick_hover ? "Bounding Box phía view" : @box_pick_error
    update_status
    view.invalidate
  rescue => e
    @box_pick_hover = nil
    @box_pick_error = "Lỗi Bounding Box: #{e.message}"
    view.invalidate
  end
  def handle_bounding_box_click(view)
    sync_bounding_box_selection_from_model(view)
    if bounding_box_selection_count(view) > 1
      prepare_bounding_box_batch_preview(view)
      return
    end

    pick = @box_pick_hover
    return unless pick && pick[:points]&.length == 4

    remember_bounding_box_reference(pick)
    @pts = pick[:points].map(&:clone)
    @state = 3
    @batch_stage = :inout
    @noi_bo = false
    @che_do_chia = :khoang
    @diem_neo = @pts[1]
    clear_division_preview_state
    @box_pick_hover = nil
    @box_pick_error = nil
    update_mode_buttons
    update_status
    view.invalidate
  end
  def build_bounding_box_pick(source, transform, view, path = nil, face = nil)
    bounds = if source.is_a?(Sketchup::ComponentInstance)
               source.definition.bounds
             elsif source.is_a?(Sketchup::Group) && source.respond_to?(:local_bounds)
               source.local_bounds
             else
               source.bounds
             end
    return nil unless bounds && !bounds.empty?

    local_corners = MH::Geo::Box.corners_from_bounds(bounds)
    corners = local_corners.map { |point| point.transform(transform) }
    faces = [
      [0, 3, 7, 4], [1, 5, 6, 2],
      [0, 4, 5, 1], [3, 2, 6, 7],
      [0, 1, 2, 3], [4, 7, 6, 5]
    ].map do |indices|
      points = indices.map { |index| corners[index] }
      {
        points: points,
        screen_area: projected_polygon_area(points, view),
        center: points_center(points)
      }
    end
    max_area = faces.map { |candidate| candidate[:screen_area] }.max
    return nil unless max_area && max_area > 0.01

    candidates = faces.select { |candidate| candidate[:screen_area] >= max_area * 0.999 }
    selected = candidates.min_by { |candidate| candidate[:center].distance(view.camera.eye) }
    points = selected[:points]
    normal = (points[1] - points[0]).cross(points[3] - points[0])
    to_camera = points_center(points).vector_to(view.camera.eye)
    points = [points[0], points[3], points[2], points[1]] if normal.dot(to_camera) < 0
    {
      source: source,
      transform: transform,
      path: path,
      face: face,
      points: points,
      corners: corners
    }
  end
  def projected_polygon_area(points, view)
    screen = points.map { |point| view.screen_coords(point) }
    sum = 0.0
    screen.each_index do |index|
      current = screen[index]
      following = screen[(index + 1) % screen.length]
      sum += current.x * following.y - following.x * current.y
    end
    sum.abs * 0.5
  end
  def transform_to_path_entity(path, source)
    transform = IDENTITY
    Array(path).each do |entity|
      transform *= entity.transformation if entity.respond_to?(:transformation)
      break if entity.equal?(source)
    end
    transform
  end
  def draw_bounding_box_pick(view)
    pick = @box_pick_hover
    return unless pick

    if pick[:corners]&.length == 8
      edges = [
        0, 1, 1, 2, 2, 3, 3, 0,
        4, 5, 5, 6, 6, 7, 7, 4,
        0, 4, 1, 5, 2, 6, 3, 7
      ].map { |index| pick[:corners][index] }
      view.line_width = 1
      view.line_stipple = '-'
      view.drawing_color = Sketchup::Color.new(80, 160, 255, 180)
      view.draw(GL_LINES, edges)
      view.line_stipple = ''
    end
    draw_face_pick_group(
      view,
      pick,
      Sketchup::Color.new(255, 190, 0, 75),
      Sketchup::Color.new(255, 150, 0, 255)
    )
  end
  def add_bounding_box_extents(bb)
    return unless @box_pick_hover
    Array(@box_pick_hover[:corners]).each { |point| bb.add(point) }
    Array(@box_selected_picks).each do |pick|
      Array(pick[:corners]).each { |point| bb.add(point) }
    end
  end
  def ctrl_pressed?(flags = 0)
    @box_ctrl_down || ((flags.to_i & COPY_MODIFIER_MASK) != 0)
  rescue
    @box_ctrl_down
  end
  def drag_distance(a, b)
    return 0 unless a && b
    dx = a[0].to_f - b[0].to_f
    dy = a[1].to_f - b[1].to_f
    Math.sqrt(dx * dx + dy * dy)
  end
  def toggle_bounding_box_pick(pick)
    return unless pick && pick[:source] && pick[:source].valid?
    @box_selected_picks ||= []
    @box_batch_preview = nil
    existing = @box_selected_picks.index { |item| item[:source].equal?(pick[:source]) }
    if existing
      @box_selected_picks.delete_at(existing)
    else
      @box_selected_picks << pick.dup
    end
  end
  def sync_bounding_box_selection_from_model(view)
    return unless view

    @box_selected_picks ||= []
    Sketchup.active_model.selection.to_a.each do |entity|
      next unless MH::Panel.is_container?(entity) &&
                  entity.respond_to?(:valid?) && entity.valid? &&
                  entity_visible?(entity)
      next if @box_selected_picks.any? { |item| same_entity?(item[:source], entity) }

      transform = entity.respond_to?(:transformation) ? entity.transformation : IDENTITY
      pick = build_bounding_box_pick(entity, transform, view, [entity], nil)
      @box_selected_picks << pick if pick
    end
  rescue => e
    puts "[MH::Panel::TaoCanh] sync bbox selection error: #{e.class}: #{e.message}"
  end
  def bounding_box_selection_picks(view = nil)
    view ||= Sketchup.active_model.active_view rescue nil
    sync_bounding_box_selection_from_model(view) if view
    seen = {}
    Array(@box_selected_picks).select do |pick|
      source = pick[:source]
      next false unless source && source.respond_to?(:valid?) && source.valid? && entity_visible?(source)

      key = source.respond_to?(:entityID) ? source.entityID : source.object_id
      next false if seen[key]

      seen[key] = true
      true
    end
  rescue
    Array(@box_selected_picks)
  end
  def bounding_box_selection_count(view = nil)
    bounding_box_selection_picks(view).length
  rescue
    Array(@box_selected_picks).length
  end
  def select_bounding_boxes_in_rect(view, start_pt, end_pt)
    return unless start_pt && end_pt
    @box_selected_picks ||= []
    @box_batch_preview = nil
    x1, y1 = start_pt
    x2, y2 = end_pt
    min_x, max_x = [x1, x2].minmax
    min_y, max_y = [y1, y2].minmax
    window_mode = x2 >= x1

    MH::Panel::Model.active_entities.each do |entity|
      next unless MH::Panel.is_container?(entity)
      next if entity.respond_to?(:hidden?) && entity.hidden?
      next if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?

      pick = build_bounding_box_pick(entity, entity.transformation, view, [entity], nil)
      next unless pick
      inside = bounding_pick_in_screen_rect?(pick, view, min_x, min_y, max_x, max_y, window_mode)
      next unless inside
      next if @box_selected_picks.any? { |item| item[:source].equal?(entity) }

      @box_selected_picks << pick
    end
  rescue => e
    puts "[MH::Panel::TaoCanh] select bbox rect error: #{e.class}: #{e.message}"
  end
  def bounding_pick_in_screen_rect?(pick, view, min_x, min_y, max_x, max_y, window_mode)
    points = Array(pick[:corners])
    return false if points.empty?
    checks = points.map do |point|
      screen = view.screen_coords(point)
      screen.x >= min_x && screen.x <= max_x && screen.y >= min_y && screen.y <= max_y
    end
    window_mode ? checks.all? : checks.any?
  end
  def draw_bounding_box_selection(view)
    sync_bounding_box_selection_from_model(view)
    bounding_box_selection_picks(view).each do |pick|
      next unless pick[:source] && pick[:source].valid?
      draw_face_pick_group(
        view,
        pick,
        Sketchup::Color.new(40, 200, 110, 70),
        Sketchup::Color.new(30, 190, 100, 255)
      )
    end
    Array(@box_batch_preview).each do |item|
      if @state == 3
        draw_bounding_box_batch_grid(view)
        break
      else
        draw_bounding_box_preview_item(item, view)
      end
    end
    draw_box_drag_rect(view)
  end
  def draw_box_drag_rect(view)
    return unless @box_dragging && @box_drag_start && @box_drag_end
    x1, y1 = @box_drag_start
    x2, y2 = @box_drag_end
    window_mode = x2 >= x1
    pts = [[x1, y1, 0], [x2, y1, 0], [x2, y2, 0], [x1, y2, 0]]
    view.line_width = 1
    view.line_stipple = window_mode ? '' : '-'
    view.drawing_color = window_mode ? Sketchup::Color.new(0, 120, 255, 45) : Sketchup::Color.new(0, 190, 90, 45)
    view.draw2d(GL_QUADS, pts)
    view.drawing_color = window_mode ? Sketchup::Color.new(0, 120, 255, 220) : Sketchup::Color.new(0, 190, 90, 220)
    view.draw2d(GL_LINE_LOOP, pts)
    view.line_stipple = ''
  end
  def draw_bounding_box_preview_item(item, view, faded: false)
    return unless item && item[:cell] && item[:normal] && item[:depth]

    cell = item[:cell]
    normal = item[:normal]
    draw_cell = cell
    if normal && normal.length > 0
      lift = normal.clone
      lift.length = 0.7.mm
      draw_cell = cell.map { |point| point.offset(lift) }
    end
    draw_box(draw_cell, normal, item[:depth], view, faded: faded)
  end
  def current_instance_setting
    if tam_mode?
      value = MH::Panel::Settings.read("instance", "", "tao_van").to_s.strip
      value = read("instance", @instance.to_s).to_s.strip if value.empty?
      @instance = value unless value.empty?
      return value
    end

    @instance = read("instance", @instance.to_s)
    @instance.to_s.strip
  rescue
    @instance.to_s.strip
  end
  def create_bounding_box_batch(view)
    current_instance_setting if tam_mode?
    preview = Array(@box_batch_preview)
    preview = build_bounding_box_batch_preview(view) if preview.empty?
    return if preview.empty?

    ents = MH::Panel::Model.active_entities
    boards = []
    board_items = (@state == 3) ? bounding_box_batch_grid_items : preview
    board_items.each do |item|
      cell = item[:cell]
      depth = item[:depth]
      source = item[:source]
      material = item[:material]
      material_name = item[:material_name]
      thickness = item[:thickness]
      detail_name = item[:detail_name]
      strict_detail_name = item[:strict_detail_name]
      detail_name = current_instance_setting if strict_detail_name
      next unless cell && depth

      MH::Panel.start
      temp = ents.add_group
      face = temp.entities.add_face(cell)
      unless face
        temp.erase! if temp.valid?
        Sketchup.active_model.abort_operation
        next
      end
      board = MH::Panel::Board.make(face, ents, 0, depth)
      board.transform!(temp.transformation) unless temp.transformation.identity?
      face.edges.each { |edge| edge.erase! if edge.valid? }
      temp.erase! if temp.valid?
      MH::Panel.commit
      finalize_bounding_box_board(board, source, material, material_name, thickness, detail_name, strict_detail_name)
      boards << board if board && board.valid?
    end

    MH::Panel.select(boards)
    reset
    view.invalidate
  rescue => e
    Sketchup.active_model.abort_operation rescue nil
    puts "[MH::Panel::TaoCanh] tạo cánh Bounding Box batch error: #{e.class}: #{e.message}"
  end
  def prepare_bounding_box_batch_preview(view)
    @box_batch_preview = build_bounding_box_batch_preview(view)
    if @box_batch_preview && !@box_batch_preview.empty?
      first = @box_batch_preview.first
      @pts = first[:cell].map(&:clone)
      @state = 3
      @batch_stage = :inout
      @noi_bo = false
      @ds_o = nil
      @che_do_chia = :khoang
      @diem_neo = @pts[1]
      clear_division_preview_state
      @batch_stage = :inout
      @box_pick_hover = nil
      update_mode_buttons
    end
    update_status
    view.invalidate
  end
  def prepare_tam_selection_preview(view)
    current_instance_setting
    @box_batch_preview = build_tam_selection_preview(view)
    if @box_batch_preview && !@box_batch_preview.empty?
      first = @box_batch_preview.first
      @pts = first[:cell].map(&:clone)
      @do_day = first[:thickness] if tam_valid_thickness?(first[:thickness])
      @state = 3
      @batch_stage = :divide
      @noi_bo = false
      @che_do_chia = :khoang
      @diem_neo = @pts[1]
      clear_division_preview_state
      @batch_stage = :divide
      update_mode_buttons
    end
    update_status
    view.invalidate
  end
  def build_tam_selection_preview(view)
    entities = selected_panel_pair_entities
    if entities.length < 2
      @tam_error = "Cần chọn tối thiểu 2 obj."
      return []
    end
    if entities.length.odd?
      @tam_error = "Số obj phải chẵn để ghép từng cặp 2 obj."
      return []
    end

    @tam_error = nil
    tam_entity_pairs(entities, view).filter_map do |pair|
      build_tam_pair_preview_item(pair[0], pair[1], view)
    end
  rescue => e
    @tam_error = "Lỗi tạo Tấm: #{e.message}"
    []
  end
  def tam_entity_pairs(entities, view)
    remaining = Array(entities).dup
    pairs = []
    axis = tam_pairing_axis(remaining, view)
    while remaining.length >= 2
      first = remaining.min_by { |entity| tam_entity_axis_interval(entity, axis)[0] }
      remaining.delete(first)
      second = remaining.min_by do |entity|
        [
          tam_outer_boundary_distance(first, entity),
          tam_entity_center(first).distance(tam_entity_center(entity))
        ]
      end
      break unless second

      remaining.delete(second)
      pairs << [first, second]
    end
    pairs << [remaining.first] if remaining.length == 1
    pairs
  rescue
    Array(entities).each_slice(2).to_a
  end
  def tam_pairing_axis(entities, view)
    centers = Array(entities).map { |entity| tam_entity_center(entity) }
    farthest = centers.combination(2).max_by { |first, second| first.distance(second) }
    if farthest
      delta = farthest[1] - farthest[0]
      axis = Geom::Vector3d.new(delta.x, delta.y, 0)
      return tam_orient_pairing_axis(axis, view) if axis.length > 0.001
    end

    normals = Array(entities).filter_map { |entity| tam_entity_panel_normal(entity) }
    unless normals.empty?
      base = normals.first.clone
      normals.drop(1).each do |normal|
        normal = normal.clone
        normal.reverse! if base.dot(normal) < 0
        base = base + normal
      end
      if base.length > 0.001
        base.normalize!
        axis = Z_AXIS.cross(base)
        return tam_orient_pairing_axis(axis, view) if axis.length > 0.001
      end
    end

    camera_axis = view.camera.xaxis
    axis = Geom::Vector3d.new(camera_axis.x, camera_axis.y, 0)
    axis.length > 0.001 ? tam_orient_pairing_axis(axis, view) : X_AXIS.clone
  rescue
    X_AXIS.clone
  end
  def tam_orient_pairing_axis(axis, view)
    axis = axis.clone
    axis.normalize!
    camera_axis = view.camera.xaxis
    camera_axis = Geom::Vector3d.new(camera_axis.x, camera_axis.y, 0)
    axis.reverse! if camera_axis.length > 0.001 && axis.dot(camera_axis) < 0
    axis
  end
  def tam_entity_axis_interval(entity, axis)
    values = entity_world_corners(entity).map { |point| (point - ORIGIN).dot(axis) }
    values.minmax
  rescue
    center = tam_entity_center(entity)
    value = (center - ORIGIN).dot(axis)
    [value, value]
  end
  def tam_outer_boundary_distance(first, second)
    first_center = tam_entity_center(first)
    second_center = tam_entity_center(second)
    direction = second_center - first_center
    direction = Geom::Vector3d.new(direction.x, direction.y, 0)
    return first_center.distance(second_center) if direction.length <= 0.001

    direction.normalize!
    side_axis = Z_AXIS.cross(direction)
    side_axis.normalize! if side_axis.length > 0.001
    first_main = tam_entity_axis_interval(first, direction)
    second_main = tam_entity_axis_interval(second, direction)
    first_side = tam_entity_axis_interval(first, side_axis)
    second_side = tam_entity_axis_interval(second, side_axis)
    main_gap = tam_interval_gap(first_main, second_main)
    side_gap = tam_interval_gap(first_side, second_side)
    Math.sqrt((main_gap * main_gap) + (side_gap * side_gap))
  rescue
    tam_entity_center(first).distance(tam_entity_center(second))
  end
  def tam_interval_gap(first, second)
    return second[0] - first[1] if first[1] < second[0]
    return first[0] - second[1] if second[1] < first[0]

    0.0
  end
  def selected_panel_pair_entities
    candidates = []
    candidates.concat(Array(@tam_selected_entities))
    candidates.concat(Sketchup.active_model.selection.to_a)
    seen = {}
    candidates.select do |entity|
      next false unless MH::Panel.is_container?(entity) &&
                        entity.respond_to?(:valid?) && entity.valid? &&
                        entity_visible?(entity)

      key = entity.respond_to?(:entityID) ? entity.entityID : entity.object_id
      next false if seen[key]

      seen[key] = true
      true
    end
  rescue
    []
  end
  def update_tam_pick_hover(x, y, view)
    old_hover = @tam_pick_hover
    @tam_pick_hover = nil
    ph = view.pick_helper
    ph.do_pick(x, y)
    path = ph.path_at(0)
    entity = Array(path).reverse.find do |candidate|
      MH::Panel.is_container?(candidate) &&
        candidate.respond_to?(:valid?) && candidate.valid? &&
        entity_visible?(candidate)
    end
    @tam_pick_hover = entity
    view.tooltip = entity ? "Chọn Tấm" : nil
    view.invalidate if old_hover != @tam_pick_hover
  rescue => e
    @tam_pick_hover = nil
    @tam_error = "Lỗi chọn Tấm: #{e.message}"
    view.invalidate
  end
  def toggle_tam_entity(entity, view)
    return unless entity && entity.respond_to?(:valid?) && entity.valid?

    @tam_selected_entities ||= []
    existing = @tam_selected_entities.index { |item| same_entity?(item, entity) }
    selection = Sketchup.active_model.selection
    if existing
      removed = @tam_selected_entities.delete_at(existing)
      begin
        selection.remove(removed) if removed && removed.valid?
      rescue
      end
    else
      @tam_selected_entities << entity
      begin
        selection.add(entity)
      rescue
      end
    end
    @tam_error = nil
    if tam_selection_ready?
      prepare_tam_selection_preview(view)
    else
      update_status
      view.invalidate
    end
  end
  def tam_selection_ready?
    count = selected_panel_pair_entities.length
    count >= 2 && count.even?
  rescue
    false
  end
  def same_entity?(first, second)
    return false unless first && second
    return true if first.equal?(second)
    return first.entityID == second.entityID if first.respond_to?(:entityID) && second.respond_to?(:entityID)

    false
  end
  def build_tam_pair_preview_item(first, second, view)
    cell = tam_pair_vertical_rect(first, second, view)
    return nil unless cell && cell.length == 4

    normal = normal_from_points(cell)
    return nil unless normal && normal.length > 0

    source = first
    transform = source.respond_to?(:transformation) ? source.transformation : IDENTITY
    material = tam_pair_material(first, second)
    material_name = tam_pair_material_name(first, second, material)
    thickness = tam_pair_thickness(first, second, transform)
    thickness = @do_day unless thickness && thickness > 0.001.mm
    {
      pick: { source: source, transform: transform, path: [source], face: nil },
      cell: offset_cell_by_normal(cell, normal),
      normal: normal,
      depth: @dao_chieu ? thickness : -thickness,
      source: source,
      material: material,
      material_name: material_name,
      thickness: thickness,
      detail_name: current_instance_setting,
      strict_detail_name: true
    }
  end
  def tam_pair_vertical_rect(first, second, view)
    corners1 = entity_world_corners(first)
    corners2 = entity_world_corners(second)
    corners = corners1 + corners2
    return nil unless corners.length >= 8

    axes = tam_view_axes(view, first, second)
    return nil unless axes
    x_axis = axes[:x_axis]
    z_axis = axes[:z_axis]
    normal = axes[:normal]

    x_min, x_max = corners.map { |point| (point - ORIGIN).dot(x_axis) }.minmax
    length = [tam_entity_length(first, corners1), tam_entity_length(second, corners2)].compact.max
    z_min = corners.map(&:z).min
    z_max = z_min + length
    return nil if (x_max - x_min).abs <= 0.001.mm || length <= 0.001.mm

    n_values = corners.map { |point| (point - ORIGIN).dot(normal) }
    camera_coord = (view.camera.eye - ORIGIN).dot(normal)
    n_coord = n_values.min_by { |value| (camera_coord - value).abs }
    return nil unless n_coord

    p0 = ORIGIN.offset(x_axis, x_min).offset(z_axis, z_min).offset(normal, n_coord)
    p1 = ORIGIN.offset(x_axis, x_max).offset(z_axis, z_min).offset(normal, n_coord)
    p2 = ORIGIN.offset(x_axis, x_max).offset(z_axis, z_max).offset(normal, n_coord)
    p3 = ORIGIN.offset(x_axis, x_min).offset(z_axis, z_max).offset(normal, n_coord)
    [p0, p1, p2, p3]
  rescue => e
    @tam_error = "Không dựng được cánh Tấm: #{e.message}"
    nil
  end
  def tam_view_axes(view, first = nil, second = nil)
    z_axis = Z_AXIS.clone
    normal = tam_pair_span_normal(first, second) || tam_pair_entity_normal(first, second)
    unless normal && normal.length > 0.001
      direction = view.camera.direction
      normal = Geom::Vector3d.new(-direction.x, -direction.y, 0)
    end
    if normal.length <= 0.001
      y_axis = view.camera.yaxis
      normal = Geom::Vector3d.new(y_axis.x, y_axis.y, 0)
    end
    return nil if normal.length <= 0.001

    normal.normalize!
    x_axis = z_axis.cross(normal)
    return nil if x_axis.length <= 0.001
    x_axis.normalize!
    { x_axis: x_axis, z_axis: z_axis, normal: normal }
  end
  def tam_pair_entity_normal(first, second = nil)
    normals = [tam_entity_panel_normal(first), tam_entity_panel_normal(second)].compact
    return nil if normals.empty?

    base = normals.first.clone
    normals[1..-1].to_a.each do |normal|
      normal = normal.clone
      normal.reverse! if base.dot(normal) < 0
      base = base + normal
    end
    return nil if base.length <= 0.001

    base.normalize!
    base
  rescue
    nil
  end
  def tam_pair_span_normal(first, second)
    return nil unless first && second

    pair_vec = tam_entity_center(second) - tam_entity_center(first)
    pair_axis = Geom::Vector3d.new(pair_vec.x, pair_vec.y, 0)
    return nil if pair_axis.length <= 0.001

    pair_axis.normalize!
    candidates = (tam_entity_panel_normal_candidates(first) + tam_entity_panel_normal_candidates(second))
    best = nil
    candidates.each do |normal|
      next unless normal && normal.length > 0.001

      n = normal.clone
      n.normalize!
      span_axis = Z_AXIS.cross(n)
      next if span_axis.length <= 0.001

      span_axis.normalize!
      score = pair_axis.dot(span_axis).abs
      best = { normal: n, score: score } if best.nil? || score > best[:score]
    end
    return nil unless best && best[:score] > 0.35

    best[:normal]
  rescue
    nil
  end
  def tam_entity_center(entity)
    points = entity_world_corners(entity)
    return ORIGIN unless points && !points.empty?

    sx = points.map(&:x).sum / points.length.to_f
    sy = points.map(&:y).sum / points.length.to_f
    sz = points.map(&:z).sum / points.length.to_f
    Geom::Point3d.new(sx, sy, sz)
  rescue
    ORIGIN
  end
  def tam_entity_panel_normal_candidates(entity)
    candidates = []
    face_normal = tam_largest_vertical_face_normal(entity)
    candidates << face_normal if face_normal
    candidates.concat(tam_vertical_face_normals(entity))
    candidates.concat(tam_entity_axis_normals(entity))
    seen = {}
    candidates.filter_map do |normal|
      next unless normal && normal.length > 0.001

      n = Geom::Vector3d.new(normal.x, normal.y, 0)
      next if n.length <= 0.001

      n.normalize!
      key = [n.x.round(4).abs, n.y.round(4).abs]
      next if seen[key]

      seen[key] = true
      n
    end
  rescue
    []
  end
  def tam_entity_panel_normal(entity)
    return nil unless entity && entity.respond_to?(:transformation)

    face_normal = tam_largest_vertical_face_normal(entity)
    return face_normal if face_normal && face_normal.length > 0.001

    bounds = tam_entity_local_bounds(entity)
    transform = entity.transformation
    axes = [
      { axis: transform.xaxis, size: bounds.width },
      { axis: transform.yaxis, size: bounds.height },
      { axis: transform.zaxis, size: bounds.depth }
    ].filter_map do |item|
      axis = item[:axis].clone
      next if axis.length <= 0.001

      world_size = item[:size].to_f * axis.length
      axis.normalize!
      horizontal = Geom::Vector3d.new(axis.x, axis.y, 0)
      next if horizontal.length <= 0.001

      horizontal.normalize!
      { axis: horizontal, size: world_size.abs }
    end
    return nil if axes.empty?

    axes.min_by { |item| item[:size] }[:axis]
  rescue
    nil
  end
  def tam_vertical_face_normals(entity)
    transform = entity.respond_to?(:transformation) ? entity.transformation : IDENTITY
    entities = if entity.is_a?(Sketchup::ComponentInstance)
                 entity.definition.entities
               elsif entity.is_a?(Sketchup::Group)
                 entity.entities
               end
    return [] unless entities

    entities.grep(Sketchup::Face).filter_map do |face|
      normal = tam_world_face_normal(face, transform)
      next unless normal && normal.length > 0.001

      horizontal = Geom::Vector3d.new(normal.x, normal.y, 0)
      next if horizontal.length <= 0.001

      horizontal.normalize!
      horizontal
    end
  rescue
    []
  end
  def tam_entity_axis_normals(entity)
    return [] unless entity && entity.respond_to?(:transformation)

    [entity.transformation.xaxis, entity.transformation.yaxis, entity.transformation.zaxis].filter_map do |axis|
      horizontal = Geom::Vector3d.new(axis.x, axis.y, 0)
      next if horizontal.length <= 0.001

      horizontal.normalize!
      horizontal
    end
  rescue
    []
  end
  def tam_largest_vertical_face_normal(entity)
    transform = entity.respond_to?(:transformation) ? entity.transformation : IDENTITY
    entities = if entity.is_a?(Sketchup::ComponentInstance)
                 entity.definition.entities
               elsif entity.is_a?(Sketchup::Group)
                 entity.entities
               end
    return nil unless entities

    best = nil
    entities.grep(Sketchup::Face).each do |face|
      normal = tam_world_face_normal(face, transform)
      next unless normal && normal.length > 0.001

      horizontal = Geom::Vector3d.new(normal.x, normal.y, 0)
      next if horizontal.length <= 0.001

      horizontal.normalize!
      area = (face.area(transform) rescue face.area.to_f)
      next if area <= 0.001
      best = { normal: horizontal, area: area } if best.nil? || area > best[:area]
    end
    best && best[:normal]
  rescue
    nil
  end
  def tam_world_face_normal(face, transform)
    points = face.vertices.map { |vertex| vertex.position.transform(transform) }
    return nil if points.length < 3

    origin = points.first
    normal = nil
    (1...points.length - 1).each do |index|
      candidate = (points[index] - origin).cross(points[index + 1] - origin)
      if candidate.length > 0.001
        normal = candidate
        break
      end
    end
    return nil unless normal && normal.length > 0.001

    normal.normalize!
    normal
  rescue
    nil
  end
  def tam_entity_local_bounds(entity)
    if entity.is_a?(Sketchup::ComponentInstance)
      entity.definition.bounds
    elsif entity.is_a?(Sketchup::Group) && entity.respond_to?(:local_bounds)
      entity.local_bounds
    else
      entity.bounds
    end
  end
  def tam_entity_length(entity, corners = nil)
    corners ||= entity_world_corners(entity)
    return nil unless corners && !corners.empty?
    xs = corners.map(&:x)
    ys = corners.map(&:y)
    zs = corners.map(&:z)
    [xs.max - xs.min, ys.max - ys.min, zs.max - zs.min].map(&:abs).max
  end
  def draw_tam_selection(view)
    selected = selected_panel_pair_entities
    ordered = tam_entity_pairs(selected, view).flatten
    ordered.each_with_index do |entity, index|
      draw_tam_entity_highlight(view, entity, index)
    end
    if @tam_pick_hover && !selected.any? { |entity| same_entity?(entity, @tam_pick_hover) }
      draw_tam_entity_highlight(view, @tam_pick_hover, selected.length)
    end
  rescue => e
    puts "[MH::Panel::TaoCanh] draw Tấm selection error: #{e.class}: #{e.message}"
  end
  def draw_tam_entity_highlight(view, entity, index)
    corners = entity_world_corners(entity)
    return unless corners && corners.length == 8

    pair_index = index / 2
    palette = [
      [Sketchup::Color.new(40, 190, 255, 52), Sketchup::Color.new(0, 145, 255, 255)],
      [Sketchup::Color.new(255, 200, 40, 52), Sketchup::Color.new(255, 150, 0, 255)],
      [Sketchup::Color.new(80, 230, 120, 52), Sketchup::Color.new(30, 180, 80, 255)]
    ]
    fill_color, edge_color = palette[pair_index % palette.length]
    face = tam_single_entity_vertical_rect(entity, view) ||
           view_outer_rect_from_corners(corners, view) ||
           visible_outer_face_from_corners(corners, view)
    if face
      view.drawing_color = fill_color
      view.draw(GL_POLYGON, face)
      view.line_width = 5
      view.drawing_color = edge_color
      view.draw(GL_LINE_LOOP, face)
    end

    edges = bbox_edge_points(corners)
    view.line_width = 4
    view.line_stipple = ''
    view.drawing_color = edge_color
    view.draw(GL_LINES, edges)
  end
  def tam_single_entity_vertical_rect(entity, view)
    corners = entity_world_corners(entity)
    axes = tam_view_axes(view, entity)
    return nil unless corners && axes
    x_axis = axes[:x_axis]
    z_axis = axes[:z_axis]
    normal = axes[:normal]
    x_min, x_max = corners.map { |point| (point - ORIGIN).dot(x_axis) }.minmax
    length = tam_entity_length(entity, corners)
    z_min = corners.map(&:z).min
    z_max = z_min + length
    n_values = corners.map { |point| (point - ORIGIN).dot(normal) }
    camera_coord = (view.camera.eye - ORIGIN).dot(normal)
    n_coord = n_values.min_by { |value| (camera_coord - value).abs }
    return nil unless x_min && x_max && length && n_coord
    return nil if (x_max - x_min).abs <= 0.001.mm || length <= 0.001.mm

    [
      ORIGIN.offset(x_axis, x_min).offset(z_axis, z_min).offset(normal, n_coord),
      ORIGIN.offset(x_axis, x_max).offset(z_axis, z_min).offset(normal, n_coord),
      ORIGIN.offset(x_axis, x_max).offset(z_axis, z_max).offset(normal, n_coord),
      ORIGIN.offset(x_axis, x_min).offset(z_axis, z_max).offset(normal, n_coord)
    ]
  rescue
    nil
  end
  def add_tam_selection_extents(bb)
    selected_panel_pair_entities.each do |entity|
      entity_world_corners(entity).each { |point| bb.add(point) }
    end
  rescue
  end
  def entity_world_corners(entity)
    bounds = if entity.is_a?(Sketchup::ComponentInstance)
               entity.definition.bounds
             elsif entity.is_a?(Sketchup::Group) && entity.respond_to?(:local_bounds)
               entity.local_bounds
             else
               entity.bounds
             end
    corners = MH::Geo::Box.corners_from_bounds(bounds)
    if entity.respond_to?(:transformation) && !entity.transformation.identity?
      corners.map { |point| point.transform(entity.transformation) }
    else
      corners
    end
  end
  def bbox_edge_points(corners)
    [
      0, 1, 1, 2, 2, 3, 3, 0,
      4, 5, 5, 6, 6, 7, 7, 4,
      0, 4, 1, 5, 2, 6, 3, 7
    ].map { |index| corners[index] }
  end
  def view_outer_rect_from_corners(corners, view)
    return nil unless corners && corners.length >= 2
    camera = view.camera
    x_axis = camera.xaxis.clone
    y_axis = camera.yaxis.clone
    normal = camera.direction.clone
    normal.reverse!
    [x_axis, y_axis, normal].each { |axis| axis.normalize! if axis.length > 0 }
    return nil if x_axis.length <= 0 || y_axis.length <= 0 || normal.length <= 0

    x_min, x_max = corners.map { |point| (point - ORIGIN).dot(x_axis) }.minmax
    y_min, y_max = corners.map { |point| (point - ORIGIN).dot(y_axis) }.minmax
    n_values = corners.map { |point| (point - ORIGIN).dot(normal) }
    camera_coord = (camera.eye - ORIGIN).dot(normal)
    n_coord = n_values.min_by { |value| (camera_coord - value).abs }
    return nil unless x_min && x_max && y_min && y_max && n_coord
    return nil if (x_max - x_min).abs <= 0.001.mm || (y_max - y_min).abs <= 0.001.mm

    p0 = ORIGIN.offset(x_axis, x_min).offset(y_axis, y_min).offset(normal, n_coord)
    p1 = ORIGIN.offset(x_axis, x_max).offset(y_axis, y_min).offset(normal, n_coord)
    p2 = ORIGIN.offset(x_axis, x_max).offset(y_axis, y_max).offset(normal, n_coord)
    p3 = ORIGIN.offset(x_axis, x_min).offset(y_axis, y_max).offset(normal, n_coord)
    points = [p0, p1, p2, p3]
    face_normal = normal_from_points(points)
    to_camera = points_center(points).vector_to(camera.eye)
    face_normal && face_normal.dot(to_camera) < 0 ? [p0, p3, p2, p1] : points
  rescue
    nil
  end
  def visible_outer_face_from_corners(corners, view)
    return nil unless corners && corners.length >= 8
    bounds = Geom::BoundingBox.new
    corners.each { |point| bounds.add(point) }
    return nil if bounds.empty?

    union = MH::Geo::Box.corners_from_bounds(bounds)
    faces = [
      [0, 3, 7, 4], [1, 5, 6, 2],
      [0, 4, 5, 1], [3, 2, 6, 7],
      [0, 1, 2, 3], [4, 7, 6, 5]
    ].map do |indices|
      points = indices.map { |index| union[index] }
      { points: points, screen_area: projected_polygon_area(points, view), center: points_center(points) }
    end
    max_area = faces.map { |candidate| candidate[:screen_area] }.max
    return nil unless max_area && max_area > 0.01

    selected = faces.select { |candidate| candidate[:screen_area] >= max_area * 0.999 }
                    .min_by { |candidate| candidate[:center].distance(view.camera.eye) }
    points = selected[:points]
    normal = (points[1] - points[0]).cross(points[3] - points[0])
    to_camera = points_center(points).vector_to(view.camera.eye)
    normal.dot(to_camera) < 0 ? [points[0], points[3], points[2], points[1]] : points
  end
  def tam_pair_material(first, second)
    first_material_in_container(first) ||
      (first.material if first.respond_to?(:material)) ||
      first_material_in_container(second) ||
      (second.material if second.respond_to?(:material))
  rescue
    nil
  end
  def tam_pair_material_name(first, second, material)
    name = begin
      MH::Panel.material_name_from_source(first, material).to_s.strip
    rescue
      ''
    end
    if name.empty?
      name = begin
        MH::Panel.material_name_from_source(second, material).to_s.strip
      rescue
        name
      end
    end
    name = material.name.to_s if name.empty? && material.respond_to?(:name)
    name
  rescue
    material.respond_to?(:name) ? material.name.to_s : ''
  end
  def tam_pair_thickness(first, second, transform)
    candidates = [
      [first, transform],
      [second, second.respond_to?(:transformation) ? second.transformation : nil]
    ]
    candidates.each do |entity, tr|
      direct = source_reference_thickness(entity, tr)
      return direct if tam_valid_thickness?(direct)

      nested = nested_panel_profile(entity, tr)[:thickness]
      return nested if tam_valid_thickness?(nested)
    end

    dominant_panel_thickness(candidates.flat_map do |entity, tr|
      [source_reference_thickness(entity, tr), nested_panel_profile(entity, tr)[:thickness]]
    end)
  rescue
    nil
  end
  def tam_valid_thickness?(value)
    value && value > 2.mm && value < 80.mm
  rescue
    false
  end
  def build_bounding_box_batch_preview(view = nil)
    picks = bounding_box_selection_picks(view).select { |pick| pick[:source] && pick[:source].valid? && pick[:points]&.length == 4 }
    picks.filter_map do |pick|
      remember_bounding_box_reference(pick)
      # Dùng mặt đầy đủ của từng box (chưa trừ hở) để mỗi cánh giữ đúng kích
      # thước riêng của object. Hở/đường chia được tính lại theo từng box.
      cell = pick[:points].map(&:clone)
      next unless cell.length == 4

      normal = normal_from_points(cell)
      next unless normal && normal.length > 0

      cell = offset_cell_by_normal(cell, normal)
      depth = @dao_chieu ? @do_day : -@do_day
      material = stable_bounding_box_material(pick)
      material_name = stable_bounding_box_material_name(pick, material)
      {
        pick: pick,
        cell: cell,
        normal: normal,
        depth: depth,
        source: @source_entity,
        material: material,
        material_name: material_name,
        thickness: @do_day
      }
    end
  end
  def stable_bounding_box_material(pick)
    material = @source_material
    source = pick[:source]
    material ||= source.material if source && source.respond_to?(:material)
    material ||= nested_panel_profile(source, pick[:transform])[:material] if source
    material ||= first_material_in_container(source)
    material
  rescue
    @source_material
  end
  def stable_bounding_box_material_name(pick, material)
    name = @source_material_name.to_s.strip
    name = MH::Panel.material_name_from_source(pick[:source], material).to_s.strip if name.empty?
    name = material.name.to_s if name.empty? && material.respond_to?(:name)
    name
  rescue
    material.respond_to?(:name) ? material.name.to_s : ''
  end
  def first_material_in_container(entity, depth = 0)
    return nil if depth > 8 || !entity || (entity.respond_to?(:valid?) && !entity.valid?)
    return entity.material if entity.respond_to?(:material) && entity.material

    entities = if entity.is_a?(Sketchup::Group)
                 entity.entities
               elsif entity.is_a?(Sketchup::ComponentInstance)
                 entity.definition.entities
               end
    return nil unless entities

    entities.each do |child|
      if child.is_a?(Sketchup::Face)
        material = child.material || child.back_material
        return material if material
      elsif MH::Panel.is_container?(child)
        material = first_material_in_container(child, depth + 1)
        return material if material
      end
    end
    nil
  end
  def draw_bounding_box_batch_grid(view)
    items = bounding_box_batch_grid_items
    hover_idx = detect_hover_batch_item(items) if @state == 3
    items.each_with_index do |item, index|
      draw_bounding_box_preview_item(item, view, faded: @noi_bo && hover_idx && hover_idx != index)
    end
    draw_active_batch_item(items[hover_idx], view) if hover_idx
    ve_kich_thuoc_chia(items.map { |item| item[:cell] }) if items.length > 1
  rescue => e
    puts "[MH::Panel::TaoCanh] draw bbox batch grid error: #{e.class}: #{e.message}"
  end
  def detect_hover_batch_item(items)
    return nil unless @last_ray
    Array(items).each_with_index do |item, index|
      cell = item[:cell]
      normal = item[:normal]
      next unless cell && normal

      hit = ray_hit_plane(@last_ray, cell[0], normal)
      return index if hit && point_in_cell?(hit, cell, normal)
    end
    nil
  end
  def draw_active_batch_item(item, view)
    return unless item && item[:cell] && item[:normal] && item[:depth]

    cell = item[:cell]
    normal = item[:normal]
    vec = make_depth_vec(normal, item[:depth])
    top = cell.map { |point| point.offset(vec) }
    active_face = Sketchup::Color.new(255, 210, 40, 95)
    active_edge = Sketchup::Color.new(255, 160, 0, 255)
    MH::Panel::View.draw_polygon(cell, color: active_face, line: false)
    MH::Panel::View.draw_polygon(top, color: active_face, line: false)
    cell.length.times do |index|
      following = (index + 1) % cell.length
      MH::Panel::View.draw_polygon(
        [cell[index], cell[following], top[following], top[index]],
        color: active_face,
        line: false
      )
    end
    MH::Panel::View.draw_loop(cell, color: active_edge, guide: false)
    MH::Panel::View.draw_loop(top, color: active_edge, guide: false)
    MH::Panel::View.draw2d_loop(cell, guide: false)
    MH::Panel::View.draw2d_loop(top, guide: false)
    cell.length.times do |index|
      following = (index + 1) % cell.length
      MH::Panel::View.draw2d_loop(
        [cell[index], cell[following], top[following], top[index]], guide: false
      )
    end
  end
  def bounding_box_batch_grid_items
    preview = Array(@box_batch_preview)
    return [] if preview.empty?

    result = []
    preview.each_with_index do |item, src_idx|
      thickness = item[:thickness] || @do_day
      depth = @dao_chieu ? thickness : -thickness
      batch_item_cells(item).each_with_index do |(cx_s, cx_e, cy_s, cy_e), cell_idx|
        cell = bounding_box_rect_from_bounds(item[:cell], cx_s, cx_e, cy_s, cy_e)
        next unless cell

        result << item.merge(cell: cell, depth: depth, src_idx: src_idx, cell_idx: cell_idx)
      end
    end
    result
  end
  def batch_preview_active?
    @box_batch_preview && !@box_batch_preview.empty?
  end
  def item_local_extents(item)
    base = item[:cell]
    [(base[1] - base[0]).length, (base[3] - base[0]).length]
  end
  def default_item_cells(item)
    w, h = item_local_extents(item)
    [[margin_left, w - margin_right, margin_top, h - margin_bottom]]
  end
  # Ô lưới của TỪNG box, tính theo kích thước RIÊNG của box đó.
  def batch_item_cells(item)
    if @noi_bo
      Array(item[:cells]).empty? ? default_item_cells(item) : item[:cells]
    else
      tong_the_cells_for(item)
    end
  end
  # Tổng thể: đường chia toàn cục lưu theo tỉ lệ trên khung master, áp vào từng
  # box theo kích thước riêng -> mỗi cánh giữ đúng size của object.
  def tong_the_cells_for(item)
    w, h = item_local_extents(item)
    return [] if w < 0.001 || h < 0.001
    col = batch_axis_bounds(w, master_division_fractions(:khoang), @khoang_ho, margin_left, margin_right)
    row = batch_axis_bounds(h, master_division_fractions(:tang), @tang_ho, margin_top, margin_bottom)
    cells = []
    col.each { |xs, xe| row.each { |ys, ye| cells << [xs, xe, ys, ye] } }
    cells
  end
  def master_division_fractions(mode)
    points = (mode == :khoang) ? @diem_chia_khoang : @diem_chia_tang
    pt_end = (mode == :khoang) ? (@pts[1] if @pts) : (@pts[3] if @pts)
    return [] unless @pts && @pts[0] && pt_end
    axis = pt_end - @pts[0]
    total = axis.length
    return [] if total < 0.001
    u = axis.normalize
    Array(points).map { |p| ((p - @pts[0]) % u) / total }
  end
  def batch_axis_bounds(total, fractions, gaps, m_start, m_end)
    return [[m_start, total - m_end]] if Array(fractions).empty?
    sorted = fractions.each_with_index.map { |f, i|
      d = [[f * total, 0.0].max, total].min
      { dist: d, gap: gaps[i] || @ho_giua_cac_canh }
    }.sort_by { |hh| hh[:dist] }
    bounds = []
    pos = m_start
    sorted.each do |hh|
      off_a, off_b = tinh_do_lech(hh[:gap])
      cell_end = hh[:dist] - off_a
      bounds << [pos, cell_end] if cell_end > pos + 0.001
      pos = hh[:dist] + off_b
    end
    cell_end = total - m_end
    bounds << [pos, cell_end] if cell_end > pos + 0.001
    bounds
  end
  def seed_batch_noi_bo_cells
    Array(@box_batch_preview).each { |item| item[:cells] = tong_the_cells_for(item) }
  end
  def master_width
    return 0 unless @pts && @pts[0] && @pts[1]
    @pts[0].distance(@pts[1])
  end
  def master_height
    return 0 unless @pts && @pts[0] && @pts[3]
    @pts[0].distance(@pts[3])
  end
  def bounding_box_rect_from_bounds(base_cell, ax_start, ax_end, ay_start, ay_end)
    p0, p1, _p2, p3 = base_cell
    vec_x = p1 - p0
    vec_y = p3 - p0
    return nil if vec_x.length < 0.001 || vec_y.length < 0.001

    x_axis = vec_x.normalize
    y_axis = vec_y.normalize
    max_x = vec_x.length
    max_y = vec_y.length
    sx = [[ax_start, 0.0].max, max_x].min
    ex = [[ax_end, 0.0].max, max_x].min
    sy = [[ay_start, 0.0].max, max_y].min
    ey = [[ay_end, 0.0].max, max_y].min
    return nil if ex <= sx + 0.001 || ey <= sy + 0.001

    [
      p0.offset(x_axis, sx).offset(y_axis, sy),
      p0.offset(x_axis, ex).offset(y_axis, sy),
      p0.offset(x_axis, ex).offset(y_axis, ey),
      p0.offset(x_axis, sx).offset(y_axis, ey)
    ]
  end
  def bounding_box_single_cell(points)
    p0, p1, _p2, p3 = points
    vec_x = p1 - p0
    vec_y = p3 - p0
    return nil if vec_x.length < 0.001 || vec_y.length < 0.001
    total_x = vec_x.length
    total_y = vec_y.length
    x_start = margin_left
    x_end = total_x - margin_right
    y_start = margin_top
    y_end = total_y - margin_bottom
    return nil if x_end <= x_start || y_end <= y_start

    x_axis = vec_x.normalize
    y_axis = vec_y.normalize
    [
      p0.offset(x_axis, x_start).offset(y_axis, y_start),
      p0.offset(x_axis, x_end).offset(y_axis, y_start),
      p0.offset(x_axis, x_end).offset(y_axis, y_end),
      p0.offset(x_axis, x_start).offset(y_axis, y_end)
    ]
  end
  def normal_from_points(points)
    return nil unless points && points.length >= 4
    normal = (points[1] - points[0]).cross(points[3] - points[0])
    normal.normalize! if normal.length > 0
    normal
  end
  def offset_cell_by_normal(cell, normal)
    return cell unless @canh_cach_mat_goc != 0 && normal && normal.length > 0
    vec = normal.clone
    vec.length = @canh_cach_mat_goc.abs
    vec.reverse! if @canh_cach_mat_goc > 0
    vec.reverse! if @dao_chieu
    cell.map { |point| point.offset(vec) }
  end
  def finalize_bounding_box_board(board, source, material, material_name, thickness = nil, detail_name = nil, strict_detail_name = false)
    return unless board && board.valid?
    layer = MH::Panel.ensure_tag(@layer)
    resolved_detail = strict_detail_name ? current_instance_setting : (detail_name.nil? ? @instance.to_s : detail_name.to_s)
    source_for_codes = strict_detail_name ? nil : source
    product_code = nil
    if strict_detail_name && source
      product_code = MH::Panel.product_code_from_source(source) rescue nil
    end
    MH::Panel.start
    board.name = resolved_detail
    board.layer = layer
    apply_material_to_board(board, material)
    MH::Panel.apply_mh_codes(
      board,
      detail_name: resolved_detail,
      thickness_mm: ((thickness || @do_day).abs.to_mm rescue nil),
      material_name: material_name,
      source: source_for_codes,
      product_code: product_code
    )
    apply_material_to_board(board, material) if material && !board.material
    sync_material_appearance(board.material, material) if material && board.material
    MH::Panel::Group.reset_axes(board)
    MH::Panel::Group.center_origin(board)
    MH::Panel.commit
  end
  def sync_material_appearance(target, source)
    return unless target

    return unless source && target == source
    target.alpha = source.alpha if source.respond_to?(:alpha) && target.respond_to?(:alpha=)
  rescue => e
    puts "[MH::Panel::TaoCanh] sync material error: #{e.class}: #{e.message}"
  end
  def add_division_point(view)
    save_division_state
    if @noi_bo && batch_preview_active?
      subdivide_batch_cell if @o_hover_item
    elsif @noi_bo && @o_hover != nil && @ds_o
      vec = @che_do_chia == :khoang ? (@pts[1] - @pts[0]) : (@pts[3] - @pts[0])
      dist = (@diem_chia_ht - @pts[0]) % vec.normalize
      split_cell_at_dist(@o_hover, dist)
    else
      if @che_do_chia == :khoang
        @diem_chia_khoang << @diem_chia_ht
        @khoang_ho << @ho_giua_cac_canh
      else
        @diem_chia_tang << @diem_chia_ht
        @tang_ho << @ho_giua_cac_canh
      end
    end
    @diem_neo = @diem_chia_ht
    @diem_chia_ht = nil
    update_status
    view.invalidate
  end
  def handle_arrow_lock(key, rpt, view)
    new_normal = case key
                 when VK_LEFT  then Geom::Vector3d.new(0, 1, 0)
                 when VK_RIGHT then Geom::Vector3d.new(1, 0, 0)
                 when VK_UP, VK_DOWN then Geom::Vector3d.new(0, 0, 1)
                 end
    return unless new_normal
    same = @locked_normal && (
      (@locked_normal.x.abs == new_normal.x.abs && new_normal.x.abs > 0.9) ||
        (@locked_normal.y.abs == new_normal.y.abs && new_normal.y.abs > 0.9) ||
        (@locked_normal.z.abs == new_normal.z.abs && new_normal.z.abs > 0.9)
    )
    @locked_normal = same ? nil : new_normal
    view.invalidate
  end
  def handle_inference_lock(key, rpt, view)
    if view.inference_locked?
      view.lock_inference
    elsif @state == 0 && @ip.valid?
      view.lock_inference(@ip)
    elsif @state == 1 && @ip.valid?
      view.lock_inference(@ip, @ip1)
    elsif @state == 2 && @ip.valid?
      view.lock_inference(@ip)
    end
  end
  def toggle_noi_bo(view)
    @noi_bo = !@noi_bo
    if batch_preview_active?
      if @noi_bo
        seed_batch_noi_bo_cells
      else
        Array(@box_batch_preview).each { |item| item[:cells] = nil }
      end
      @ds_o = nil
    elsif @noi_bo
      @ds_o = compute_global_cells
    else
      convert_cells_to_divisions
      @ds_o = nil
    end
    @o_hover = nil
    @o_hover_item = nil
    @lich_su_chia.clear
    update_mode_buttons
    update_status
    view.invalidate
  end
  def convert_cells_to_divisions
    return unless @ds_o && @ds_o.length > 1
    return unless @pts[0] && @pts[1] && @pts[3]
    vec_x = @pts[1] - @pts[0]
    vec_y = @pts[3] - @pts[0]
    return if vec_x.length < 0.001 || vec_y.length < 0.001
    @diem_chia_khoang, @khoang_ho = extract_cell_gaps(0, 1, vec_x.normalize)
    @diem_chia_tang, @tang_ho = extract_cell_gaps(2, 3, vec_y.normalize)
  end
  def extract_cell_gaps(idx_s, idx_e, axis)
    vals = @ds_o.flat_map { |c| [c[idx_s], c[idx_e]] }.uniq.sort
    ends = @ds_o.map { |c| c[idx_e].round(3) }.uniq
    starts = @ds_o.map { |c| c[idx_s].round(3) }.uniq
    points = []
    gaps = []
    (0...vals.length - 1).each do |i|
      gap_size = vals[i + 1] - vals[i]
      next if gap_size < 0.001
      if ends.include?(vals[i].round(3)) && starts.include?(vals[i + 1].round(3))
        off_a, _ = tinh_do_lech(gap_size)
        points << @pts[0].offset(axis, vals[i] + off_a)
        gaps << gap_size
      end
    end
    [points, gaps]
  end
  def handle_tab(view)
    if @state == 0
      if tam_mode? && selected_panel_pair_entities.length >= 2
        prepare_tam_selection_preview(view)
        return
      end
      if bounding_box_mode? && bounding_box_selection_count(view) > 0
        prepare_bounding_box_batch_preview(view)
        return
      end
      @che_do_tool = @che_do_tool == "tao_canh" ? "chia_canh" : "tao_canh"
      write("che_do_tool", @che_do_tool)
      @mat_noi_bat = nil
      @pts_noi_bat = nil
      update_mode_buttons
    elsif (@state == 1 || @state == 2) && !bounding_box_mode?
      @dao_chieu = !@dao_chieu
      write("dao_chieu", @dao_chieu)
    elsif pick_pair_inout_stage?
      @dao_chieu = !@dao_chieu
      write("dao_chieu", @dao_chieu)
    elsif @state == 3
      toggle_noi_bo(view)
      return
    else
      return
    end
    update_status
    view.invalidate
  end
  def handle_dimension_input(text, view)
    case @state
    when 0
      begin
        @do_day = text.to_l
        write("do_day", @do_day.to_mm)
        @button_config[:modified] = true if @button_config
        update_status
        view.invalidate
      rescue
      end
    when 1
      handle_dim_state1(text, view)
    when 2
      handle_dim_state2(text, view)
    when 3
      return if pick_pair_inout_stage?

      begin
        num = text.to_f
        @ho_giua_cac_canh = num.mm
        update_status
        view.invalidate
      rescue
      end
    end
  end
  def handle_dim_state1(text, view)
    if @phuong_phap_ve == "2_diem"
      begin
        normal = @locked_normal || @normal_2_diem || Geom::Vector3d.new(0, 0, 1)
        u_dir = @pts[1] && @pts[0].distance(@pts[1]) > 0.001 \
          ? (@pts[1] - @pts[0]).normalize : compute_plane_directions(normal)[0]
        v_dir = @pts[3] && @pts[0].distance(@pts[3]) > 0.001 \
          ? (@pts[3] - @pts[0]).normalize : compute_plane_directions(normal)[1]
        if text.start_with?(',') || text.start_with?(';')
          @pts[3] = @pts[0].offset(v_dir, text[1..-1].to_l)
        elsif text =~ /[,;x]/
          parts = text.split(/[,;x]/)
          return unless parts.length >= 2
          @pts[1] = @pts[0].offset(u_dir, parts[0].to_l)
          @pts[3] = @pts[0].offset(v_dir, parts[1].to_l)
        else
          @pts[1] = @pts[0].offset(u_dir, text.to_l)
        end
        @pts[2] = @pts[1].offset(v_dir, @pts[0].distance(@pts[3]))
        @ip1.copy!(@ip)
        @state = 3
        @che_do_chia = :khoang
        @diem_neo = @pts[1]
        update_status
        view.invalidate
      rescue
      end
    else
      begin
        vec = @pts[1] - @pts[0]
        if vec.length > 0.0
          vec.length = text.to_l
          @pts[1] = @pts[0].offset(vec)
          view.invalidate
          increment_state
        end
      rescue
      end
    end
  end
  def handle_dim_state2(text, view)
    begin
      parts = text.split(/[,;x]/)
      if parts.length >= 2
        vec_w = @pts[1] - @pts[0]
        vec_w.length = parts[0].to_l if vec_w.length > 0.0
        @pts[1] = @pts[0].offset(vec_w)
        vec_h = @pts[3] - @pts[0]
        if vec_h.length > 0.0
          vec_h.length = parts[1].to_l
          @pts[2] = @pts[1].offset(vec_h)
          @pts[3] = @pts[0].offset(vec_h)
        end
      else
        vec = @pts[3] - @pts[0]
        if vec.length > 0.0
          vec.length = text.to_l
          @pts[2] = @pts[1].offset(vec)
          @pts[3] = @pts[0].offset(vec)
        end
      end
      increment_state
    rescue
    end
  end
  def margin(side)
    @ho_deu_bien_ngoai ? @ho_bien_ngoai : instance_variable_get(:"@ho_#{side}")
  end
  def margin_left;   margin(:trai); end
  def margin_right;  margin(:phai); end
  def margin_top;    margin(:tren); end
  def margin_bottom; margin(:duoi); end
  def compute_cell_bounds(total, division_points, gaps, pt_start, pt_end, margin_start, margin_end)
    vec = pt_end - pt_start
    return [[margin_start, total - margin_end]] if vec.length < 0.001 || division_points.empty?
    axis = vec.normalize
    sorted = division_points.each_with_index.map { |pt, i|
      dist = (pt - pt_start) % axis
      dist = [[dist, 0.0].max, total].min
      { dist: dist, gap: gaps[i] || @ho_giua_cac_canh }
    }.sort_by { |h| h[:dist] }
    boundaries = []
    pos = margin_start
    sorted.each do |h|
      off_a, off_b = tinh_do_lech(h[:gap])
      cell_end = h[:dist] - off_a
      boundaries << [pos, cell_end] if cell_end > pos + 0.001
      pos = h[:dist] + off_b
    end
    cell_end = total - margin_end
    boundaries << [pos, cell_end] if cell_end > pos + 0.001
    boundaries
  end
  def compute_global_cells
    return [] unless @pts.length >= 4 && @pts[0] && @pts[1] && @pts[2] && @pts[3]
    vec_x = @pts[0].vector_to(@pts[1])
    vec_y = @pts[0].vector_to(@pts[3])
    return [] if vec_x.length < 0.001 || vec_y.length < 0.001
    total_x = vec_x.length
    total_y = vec_y.length
    col_bounds = compute_cell_bounds(
      total_x, @diem_chia_khoang, @khoang_ho, @pts[0], @pts[1], margin_left, margin_right
    )
    row_bounds = compute_cell_bounds(
      total_y, @diem_chia_tang, @tang_ho, @pts[0], @pts[3], margin_top, margin_bottom
    )
    cells = []
    col_bounds.each do |gx_s, gx_e|
      next if gx_e <= gx_s
      row_bounds.each do |gy_s, gy_e|
        next if gy_e <= gy_s
        cells << [gx_s, gx_e, gy_s, gy_e]
      end
    end
    cells
  end
  def each_grid_cell
    return unless @pts.length >= 4 && @pts[0] && @pts[1] && @pts[2] && @pts[3]
    return if @pts[0] == @pts[3]
    vec_x = @pts[0].vector_to(@pts[1])
    vec_y = @pts[0].vector_to(@pts[3])
    return if vec_x.length < 0.001 || vec_y.length < 0.001
    cells = @ds_o || compute_global_cells
    cells.each { |cx_s, cx_e, cy_s, cy_e| yield cx_s, cx_e, cy_s, cy_e }
  end
  def bounds_to_rect(ax_start, ax_end, ay_start, ay_end)
    vec_x_n = @pts[0].vector_to(@pts[1]).normalize
    vec_y_n = @pts[0].vector_to(@pts[3]).normalize
    p0 = @pts[0].offset(vec_x_n, ax_start).offset(vec_y_n, ay_start)
    p1 = @pts[0].offset(vec_x_n, ax_end).offset(vec_y_n, ay_start)
    p2 = @pts[0].offset(vec_x_n, ax_end).offset(vec_y_n, ay_end)
    p3 = @pts[0].offset(vec_x_n, ax_start).offset(vec_y_n, ay_end)
    [p0, p1, p2, p3]
  end
  def get_grid_cells
    if free_mode? && @pts_tu_do && @pts_tu_do.length >= 3
      return [@pts_tu_do.dup] unless @state == 3
      return get_free_grid_cells
    end
    cells = []
    each_grid_cell { |*bounds| cells << bounds_to_rect(*bounds) }
    cells
  end
  def get_free_grid_cells
    rect_cells = []
    each_grid_cell do |*bounds|
      rect = bounds_to_rect(*bounds)
      clipped = clip_polygon_to_rect(@pts_tu_do, rect, @normal_tu_do)
      rect_cells << clipped if clipped && clipped.length >= 3
    end
    rect_cells.empty? ? [@pts_tu_do.dup] : rect_cells
  end
  def subdivide_cell_equal(cell_idx, num)
    return unless @ds_o && cell_idx && cell_idx < @ds_o.length
    cell = @ds_o[cell_idx]
    cx_s, cx_e, cy_s, cy_e = cell
    if @che_do_chia == :khoang
      sub_bounds = equal_sub_bounds(num, cx_s, cx_e)
      new_cells = sub_bounds.map { |s, e| [s, e, cy_s, cy_e] }
    else
      sub_bounds = equal_sub_bounds(num, cy_s, cy_e)
      new_cells = sub_bounds.map { |s, e| [cx_s, cx_e, s, e] }
    end
    @ds_o.delete_at(cell_idx)
    @ds_o.insert(cell_idx, *new_cells)
  end
  def equal_sub_bounds(num, range_s, range_e)
    return [[range_s, range_e]] if num < 2
    total = range_e - range_s
    available = total - (num - 1) * @ho_giua_cac_canh
    return [[range_s, range_e]] if available <= 0
    sub_size = available / num.to_f
    bounds = []
    pos = range_s
    num.times do
      bounds << [pos, pos + sub_size]
      pos += sub_size + @ho_giua_cac_canh
    end
    bounds
  end
  def split_cell_at_dist(cell_idx, dist)
    return unless @ds_o && cell_idx && cell_idx < @ds_o.length
    cell = @ds_o[cell_idx]
    cx_s, cx_e, cy_s, cy_e = cell
    off_a, off_b = tinh_do_lech(@ho_giua_cac_canh)
    new_cells = []
    if @che_do_chia == :khoang
      return unless dist > cx_s + 0.001 && dist < cx_e - 0.001
      left_end = dist - off_a
      right_start = dist + off_b
      new_cells << [cx_s, left_end, cy_s, cy_e] if left_end > cx_s + 0.001
      new_cells << [right_start, cx_e, cy_s, cy_e] if cx_e > right_start + 0.001
    else
      return unless dist > cy_s + 0.001 && dist < cy_e - 0.001
      bottom_end = dist - off_a
      top_start = dist + off_b
      new_cells << [cx_s, cx_e, cy_s, bottom_end] if bottom_end > cy_s + 0.001
      new_cells << [cx_s, cx_e, top_start, cy_e] if cy_e > top_start + 0.001
    end
    return if new_cells.empty?
    @ds_o.delete_at(cell_idx)
    @ds_o.insert(cell_idx, *new_cells)
  end
  def subdivide_batch_cell
    info = @o_hover_item
    return unless info
    item = @box_batch_preview[info[:src_idx]]
    return unless item
    item[:cells] = default_item_cells(item) if Array(item[:cells]).empty?
    cells = item[:cells]
    idx = info[:cell_idx]
    return unless idx && idx < cells.length
    cx_s, cx_e, cy_s, cy_e = cells[idx]
    dist = info[:dist]
    off_a, off_b = tinh_do_lech(@ho_giua_cac_canh)
    new_cells = []
    if @che_do_chia == :khoang
      return unless dist > cx_s + 0.001 && dist < cx_e - 0.001
      left_end = dist - off_a
      right_start = dist + off_b
      new_cells << [cx_s, left_end, cy_s, cy_e] if left_end > cx_s + 0.001
      new_cells << [right_start, cx_e, cy_s, cy_e] if cx_e > right_start + 0.001
    else
      return unless dist > cy_s + 0.001 && dist < cy_e - 0.001
      bottom_end = dist - off_a
      top_start = dist + off_b
      new_cells << [cx_s, cx_e, cy_s, bottom_end] if bottom_end > cy_s + 0.001
      new_cells << [cx_s, cx_e, top_start, cy_e] if cy_e > top_start + 0.001
    end
    return if new_cells.empty?
    cells.delete_at(idx)
    cells.insert(idx, *new_cells)
  end
  def subdivide_batch_cell_equal(num)
    info = @o_hover_item
    return unless info
    item = @box_batch_preview[info[:src_idx]]
    return unless item
    item[:cells] = default_item_cells(item) if Array(item[:cells]).empty?
    cells = item[:cells]
    idx = info[:cell_idx]
    return unless idx && idx < cells.length
    cx_s, cx_e, cy_s, cy_e = cells[idx]
    sub = if @che_do_chia == :khoang
            equal_sub_bounds(num, cx_s, cx_e).map { |s, e| [s, e, cy_s, cy_e] }
          else
            equal_sub_bounds(num, cy_s, cy_e).map { |s, e| [cx_s, cx_e, s, e] }
          end
    cells.delete_at(idx)
    cells.insert(idx, *sub)
  end
  def update_anchor_for_mode
    @diem_neo = if @che_do_chia == :khoang
                      @diem_chia_khoang.empty? ? @pts[1] : @diem_chia_khoang.last
                    else
                      @diem_chia_tang.empty? ? @pts[3] : @diem_chia_tang.last
                    end
  end
  def save_division_state
    @lich_su_chia << {
      dp: @diem_chia_tang.dup,
      dpk: @diem_chia_khoang.dup,
      th: @tang_ho.dup,
      kh: @khoang_ho.dup,
      cl: @ds_o ? @ds_o.map(&:dup) : nil,
      bc: batch_preview_active? ? @box_batch_preview.map { |it| it[:cells] && it[:cells].map(&:dup) } : nil,
      anchor: @diem_neo
    }
  end
  def undo_last_division
    return false if @lich_su_chia.empty?
    s = @lich_su_chia.pop
    @diem_chia_tang = s[:dp]
    @diem_chia_khoang = s[:dpk]
    @tang_ho = s[:th]
    @khoang_ho = s[:kh]
    @ds_o = s[:cl]
    if s[:bc] && batch_preview_active?
      @box_batch_preview.each_with_index { |it, i| it[:cells] = s[:bc][i] }
    end
    @diem_neo = s[:anchor]
    true
  end
  def generate_equal_divisions(num, cell_start, cell_end, total, pt_start, pt_end)
    return [] if total < 0.001
    num_divisions = num - 1
    return [] if num_divisions < 1
    available = (cell_end - cell_start) - (num - 1) * @ho_giua_cac_canh
    return [] if available <= 0
    sub_size = available / num.to_f
    he_so = case @chia_canh_le
            when :dau  then -1
            when :cuoi then 0
            else -0.5
            end
    (1..num_divisions).map do |i|
      dist = cell_start + i * sub_size + (i + he_so) * @ho_giua_cac_canh
      t = dist / total
      t = [[t, 0.0].max, 1.0].min
      Geom.linear_combination(1 - t, pt_start, t, pt_end)
    end
  end
  def handle_division_command(num, view)
    return if pick_pair_inout_stage?

    save_division_state
    if @noi_bo && batch_preview_active?
      subdivide_batch_cell_equal(num) if @o_hover_item
    elsif @noi_bo && @ds_o
      subdivide_cell_equal(@o_hover, num) if @o_hover
    elsif @che_do_chia == :khoang
      @diem_chia_khoang.clear; @khoang_ho.clear
      total = @pts[0].distance(@pts[1])
      pts = generate_equal_divisions(
        num, margin_left, total - margin_right, total, @pts[0], @pts[1]
      )
      pts.each { |pt| @diem_chia_khoang << pt; @khoang_ho << @ho_giua_cac_canh }
      @diem_neo = @diem_chia_khoang.last || @pts[1]
    else
      @diem_chia_tang.clear; @tang_ho.clear
      total = @pts[0].distance(@pts[3])
      pts = generate_equal_divisions(
        num, margin_top, total - margin_bottom, total, @pts[0], @pts[3]
      )
      pts.each { |pt| @diem_chia_tang << pt; @tang_ho << @ho_giua_cac_canh }
      @diem_neo = @diem_chia_tang.last || @pts[3]
    end
    update_status
    view.invalidate
  end
  def create_rectangle
    cells = get_grid_cells
    return reset if cells.empty?
    cells = offset_cells(cells) if @canh_cach_mat_goc != 0
    ents = MH::Panel::Model.active_entities
    MH::Panel.start
    new_boards = []
    do_day = @dao_chieu ? @do_day : -@do_day
    cells.each do |cell_pts|
      g = ents.add_group
      f = g.entities.add_face(cell_pts)
      next unless f
      board = MH::Panel::Board.make(f, ents, 0, do_day)
      tr = g.transformation
      board.transform!(tr) unless tr.identity?
      new_boards << board
      f.edges.each { |e| e.erase! if e.valid? }
      g.erase! if g.valid?
    end
    new_boards = componentize_boards(new_boards) if @tao_component && new_boards.length > 0
    MH::Panel.commit
    finalize_boards(new_boards)
    MH::Panel.select(new_boards)
    reset
  end
  def componentize_boards(new_boards)
    num_cols = @diem_chia_khoang.length + 1
    num_rows = @diem_chia_tang.length + 1
    all_components = []
    num_rows.times do |row_idx|
      start_idx = row_idx * num_cols
      row_boards = new_boards[start_idx, num_cols]
      if row_boards && row_boards.length > 0
        row_component = MH::Panel::Group.group_to_component(row_boards)
        all_components.concat(row_component.is_a?(Array) ? row_component : [row_component])
      end
    end
    all_components
  end
  def finalize_boards(new_boards)
    return unless new_boards.length > 0
    layer = MH::Panel.ensure_tag(@layer)
    new_boards.each do |b|
      MH::Panel.start
      b.name = @instance
      b.layer = layer
      apply_source_material(b)
      MH::Panel.apply_mh_codes(
        b,
        detail_name: @instance,
        thickness_mm: (@do_day.abs.to_mm rescue nil),
        material_name: (@source_material_name || (@material.respond_to?(:name) ? @material.name : nil)),
        source: @source_entity
      )
      MH::Panel::Group.reset_axes(b)
      MH::Panel::Group.center_origin(b)
      MH::Panel.commit
    end
  end
  def apply_source_material(board)
    apply_material_to_board(board, @source_material)
  end
  def apply_material_to_board(board, material)
    return unless board && board.valid? && material

    board.material = material
    board.entities.grep(Sketchup::Face).each do |face|
      face.material = nil
      face.back_material = nil
    end
  rescue => e
    puts "[MH::Panel::TaoCanh] apply material error: #{e.class}: #{e.message}"
  end
  def draw_grid_preview(view)
    cells = get_grid_cells
    cells = offset_cells(cells) if @canh_cach_mat_goc != 0
    normal = get_normal
    depth = @dao_chieu ? @do_day : -@do_day
    hover_idx = detect_hover_cell(cells, normal) if @noi_bo && @state == 3
    cells.each_with_index do |cell_pts, i|
      faded = @noi_bo && @state == 3 && hover_idx && i != hover_idx
      draw_box(cell_pts, normal, depth, view, faded: faded)
    end
    if @noi_bo && @state == 3 && hover_idx
      vec = make_depth_vec(normal, depth)
      active_pts = cells[hover_idx]
      active_top = active_pts.map { |pt| pt.offset(vec) }
      MH::Panel::View.draw2d_loop(active_pts, guide: false)
      MH::Panel::View.draw2d_loop(active_top, guide: false)
      active_pts.length.times do |i|
        j = (i + 1) % active_pts.length
        MH::Panel::View.draw2d_loop(
          [active_pts[i], active_pts[j], active_top[j], active_top[i]], guide: false
        )
      end
    end
    draw_distances(view)
    draw_division_previews(normal) if @state == 3
  end
  def draw_batch_division_overlay(view)
    normal = get_normal
    return unless normal && @pts[0] && @pts[1] && @pts[3]
    return unless @state == 3 && @batch_stage == :divide
    if @noi_bo
      # Nội bộ: ô đang hover được tô bởi draw_active_batch_item; ở đây chỉ vẽ
      # vạch chia chạy theo chuột trong đúng ô của box đang hover.
      draw_batch_noi_bo_split_preview(view)
    else
      # Tổng thể: vạch chia là toàn cục -> hiện trên TẤT CẢ cánh.
      draw_batch_global_split_preview(view)
    end
  end
  def draw_batch_global_split_preview(view)
    return unless @diem_chia_ht
    khoang = (@che_do_chia == :khoang)
    master_axis = khoang ? (@pts[1] - @pts[0]) : (@pts[3] - @pts[0])
    return if master_axis.length < 0.001
    # Vị trí chia lưu theo tỉ lệ -> mỗi box hiện vạch ở đúng tỉ lệ của nó.
    f = ((@diem_chia_ht - @pts[0]) % master_axis.normalize) / master_axis.length
    return unless f > 0.0001 && f < 0.9999
    Array(@box_batch_preview).each do |item|
      base = item[:cell]
      normal = item[:normal] || get_normal
      next unless base && base.length == 4 && normal
      thickness = item[:thickness] || @do_day
      depth = @dao_chieu ? thickness : -thickness
      axis = khoang ? (base[1] - base[0]) : (base[3] - base[0])
      next if axis.length < 0.001
      u = axis.normalize
      d = f * axis.length
      if khoang
        p1 = base[0].offset(u, d)
        p2 = base[3].offset(u, d)
      else
        p1 = base[0].offset(u, d)
        p2 = base[1].offset(u, d)
      end
      draw_distance_plane(p1, p2, normal, depth)
      draw_gap_preview(p1, p2, axis, normal, depth)
    end
  end
  def draw_batch_noi_bo_split_preview(view)
    info = @o_hover_item
    return unless info && @diem_chia_ht
    item = @box_batch_preview[info[:src_idx]]
    return unless item
    cell = info[:cell]
    normal = item[:normal] || get_normal
    return unless cell && cell.length == 4 && normal
    cells = Array(item[:cells]).empty? ? default_item_cells(item) : item[:cells]
    bounds = cells[info[:cell_idx]]
    return unless bounds
    cx_s, cx_e, cy_s, cy_e = bounds
    thickness = item[:thickness] || @do_day
    depth = @dao_chieu ? thickness : -thickness
    if @che_do_chia == :khoang
      span = cx_e - cx_s
      return if span < 0.001
      f = (info[:dist] - cx_s) / span
      return unless f > 0.0001 && f < 0.9999
      p1 = Geom.linear_combination(1 - f, cell[0], f, cell[1])
      p2 = Geom.linear_combination(1 - f, cell[3], f, cell[2])
      gap_dir = cell[1] - cell[0]
    else
      span = cy_e - cy_s
      return if span < 0.001
      f = (info[:dist] - cy_s) / span
      return unless f > 0.0001 && f < 0.9999
      p1 = Geom.linear_combination(1 - f, cell[0], f, cell[3])
      p2 = Geom.linear_combination(1 - f, cell[1], f, cell[2])
      gap_dir = cell[3] - cell[0]
    end
    draw_distance_plane(p1, p2, normal, depth)
    draw_gap_preview(p1, p2, gap_dir, normal, depth)
  end
  def detect_hover_cell(cells, normal)
    return nil unless @last_ray && normal
    hit = ray_hit_plane(@last_ray, @pts[0], normal)
    return nil unless hit
    cells.each_with_index do |cell_pts, i|
      return i if point_in_cell?(hit, cell_pts, normal)
    end
    nil
  end
  def draw_free_polygon(view)
    return unless @pts_tu_do && @pts_tu_do.length >= 2
    preview_pts = @pts_tu_do.dup
    preview_pts << @pt_tu_do_ht if @pt_tu_do_ht
    if preview_pts.length >= 3
      normal = @normal_tu_do
      unless normal
        v1 = preview_pts[1] - preview_pts[0]
        v2 = preview_pts[2] - preview_pts[0]
        normal = v1.cross(v2)
        normal.normalize! if normal.length > 0
      end
      if normal && normal.length > 0
        depth = @dao_chieu ? @do_day : -@do_day
        draw_box(preview_pts, normal, depth, view)
      else
        preview_pts.each_cons(2) { |a, b| MH::Panel::View.draw_lines([a, b]) }
      end
    else
      MH::Panel::View.draw_lines([preview_pts[0], preview_pts[1]])
    end
  end
  def make_depth_vec(normal, depth)
    vec = normal.clone
    vec.length = depth.abs
    vec.reverse! if depth < 0
    vec
  end
  def draw_box(cell_pts, normal, depth, view, faded: false)
    return unless normal && depth != 0
    vec = make_depth_vec(normal, depth)
    top_pts = cell_pts.map { |pt| pt.offset(vec) }
    face_c = faded ? MH::Panel::View.sub_face_color : nil
    edge_c = faded ? sub_edge_color : nil
    MH::Panel::View.draw_loop(cell_pts, color: edge_c, guide: true)
    MH::Panel::View.draw_loop(top_pts, color: edge_c, guide: true)
    cell_pts.length.times do |i|
      MH::Panel::View.draw_lines([cell_pts[i], top_pts[i]], color: edge_c, guide: true)
    end
    MH::Panel::View.draw_polygon(cell_pts, color: face_c, line: false)
    MH::Panel::View.draw_polygon(top_pts, color: face_c, line: false)
    cell_pts.length.times do |i|
      j = (i + 1) % cell_pts.length
      MH::Panel::View.draw_polygon(
        [cell_pts[i], cell_pts[j], top_pts[j], top_pts[i]], color: face_c, line: false
      )
    end
  end
  def draw_distance_plane(left, right, normal, depth)
    return unless normal && depth != 0
    vec = make_depth_vec(normal, depth)
    MH::Panel::View.draw2d_polygon([left, right, right.offset(vec), left.offset(vec)])
  end
  def draw_gap_preview(p1, p2, gap_dir, normal, depth)
    gap = @ho_giua_cac_canh
    return if gap.abs < 0.001
    return unless normal && depth != 0
    axis = gap_dir.length > 0 ? gap_dir.normalize : return
    depth_vec = make_depth_vec(normal, depth)
    case @chia_canh_le
    when :dau
      ve_gap_box(p1, p2, axis, gap, depth_vec)
    when :cuoi
      ve_gap_box(p1, p2, axis, -gap, depth_vec)
    else
      half = gap / 2.0
      ve_gap_box(p1, p2, axis, half, depth_vec)
      ve_gap_box(p1, p2, axis, -half, depth_vec)
    end
  end
  def ve_gap_box(p1, p2, axis, dist, depth_vec)
    v = Geom::Vector3d.new(axis.x * dist, axis.y * dist, axis.z * dist)
    front = [p1, p1.offset(v), p2.offset(v), p2]
    back = front.map { |pt| pt.offset(depth_vec) }
    MH::Panel::View.draw_loop(front, guide: true)
    MH::Panel::View.draw_loop(back, guide: true)
    front.each_with_index { |fp, i| MH::Panel::View.draw_lines([fp, back[i]], guide: true) }
  end
  def draw_division_previews(normal)
    return unless @pts[0] && @pts[1] && @pts[3]
    depth = @dao_chieu ? @do_day : -@do_day
    vec_x = @pts[1] - @pts[0]
    vec_y = @pts[3] - @pts[0]
    ov = canh_offset_vec
    unless @ds_o
      @diem_chia_tang.each do |dp|
        dp = dp.offset(ov) if ov
        draw_clipped_division(dp, dp.offset(vec_x), normal, depth)
      end
      @diem_chia_khoang.each do |dp|
        dp = dp.offset(ov) if ov
        draw_clipped_division(dp, dp.offset(vec_y), normal, depth)
      end
    end
    draw_current_division(normal, depth, vec_x, vec_y) if @diem_chia_ht
  end
  def draw_clipped_division(p1, p2, normal, depth)
    p1, p2 = clip_division_line(p1, p2, normal)
    draw_distance_plane(p1, p2, normal, depth) if p1 && p2
  end
  def draw_current_division(normal, depth, vec_x, vec_y)
    khoang = @che_do_chia == :khoang
    p1, p2 = division_line_endpoints(khoang ? :khoang : :tang, vec_x, vec_y)
    gap_dir = khoang ? vec_x : vec_y
    p1, p2 = clip_division_line(p1, p2, normal)
    return unless p1 && p2
    ov = canh_offset_vec
    if ov
      p1 = p1.offset(ov)
      p2 = p2.offset(ov)
    end
    draw_distance_plane(p1, p2, normal, depth)
    draw_gap_preview(p1, p2, gap_dir, normal, depth)
  end
  def division_line_endpoints(mode, vec_x, vec_y)
    khoang = mode == :khoang
    span_vec = khoang ? vec_y : vec_x
    if @noi_bo && @o_hover && @ds_o
      vec_n = span_vec.length > 0 ? span_vec.normalize : nil
      return nil unless vec_n
      cell = @ds_o[@o_hover]
      idx_s, idx_e = khoang ? [2, 3] : [0, 1]
      [@diem_chia_ht.offset(vec_n, cell[idx_s]),
       @diem_chia_ht.offset(vec_n, cell[idx_e])]
    else
      [@diem_chia_ht, @diem_chia_ht.offset(span_vec)]
    end
  end
  def draw_distances(view)
    return unless @hien_thi_kich_thuoc
    cells = get_grid_cells
    return if cells.empty?
    precision = MH::Panel::Model.get_unit_precision
    cells.each do |cell_pts|
      next if cell_pts.length < 4
      w = cell_pts[0].distance(cell_pts[1]).to_mm
      h = cell_pts[0].distance(cell_pts[3]).to_mm
      text_w = format("%.#{precision}f", w)
      text_h = format("%.#{precision}f", h)
      text = "#{text_w} x #{text_h}"
      n = cell_pts.length.to_f
      center = Geom::Point3d.new(
        cell_pts.sum(&:x) / n,
        cell_pts.sum(&:y) / n,
        cell_pts.sum(&:z) / n
      )
      MH::Panel::View.draw2d_text(text, center)
    end
  end
  def ve_kich_thuoc_chia(face_pts_list)
    return unless @hien_thi_kich_thuoc && face_pts_list && !face_pts_list.empty?
    precision = MH::Panel::Model.get_unit_precision
    face_pts_list.each do |cell_pts|
      next if cell_pts.length < 4
      w = cell_pts[0].distance(cell_pts[1]).to_mm
      h = cell_pts[0].distance(cell_pts[3]).to_mm
      text = "#{format("%.#{precision}f", w)} x #{format("%.#{precision}f", h)}"
      n = cell_pts.length.to_f
      center = Geom::Point3d.new(
        cell_pts.sum(&:x) / n,
        cell_pts.sum(&:y) / n,
        cell_pts.sum(&:z) / n
      )
      MH::Panel::View.draw2d_text(text, center)
    end
  end
  def tinh_face_chia
    return [] unless @chia_pts && @pts_noi_bat && @pts_noi_bat.length == 4
    sp1, sp2 = @chia_pts
    off_a, off_b = do_lech_khe
    if @chia_truc == :a
      gap_vec = (@pts_noi_bat[1] - @pts_noi_bat[0]).normalize
      sp1a = sp1.offset(gap_vec, -off_a); sp2a = sp2.offset(gap_vec, -off_a)
      sp1b = sp1.offset(gap_vec,  off_b); sp2b = sp2.offset(gap_vec,  off_b)
      [
        [@pts_noi_bat[0], sp1a, sp2a, @pts_noi_bat[3]],
        [sp1b, @pts_noi_bat[1], @pts_noi_bat[2], sp2b]
      ]
    else
      gap_vec = (@pts_noi_bat[3] - @pts_noi_bat[0]).normalize
      sp1a = sp1.offset(gap_vec, -off_a); sp2a = sp2.offset(gap_vec, -off_a)
      sp1b = sp1.offset(gap_vec,  off_b); sp2b = sp2.offset(gap_vec,  off_b)
      [
        [@pts_noi_bat[0], @pts_noi_bat[1], sp2a, sp1a],
        [sp1b, sp2b, @pts_noi_bat[2], @pts_noi_bat[3]]
      ]
    end
  end
  def canh_offset_vec
    return nil if @canh_cach_mat_goc == 0
    normal = get_normal
    return nil unless normal && normal.length > 0
    vec = normal.clone
    vec.length = @canh_cach_mat_goc.abs
    vec.reverse! if @canh_cach_mat_goc > 0
    vec.reverse! if @dao_chieu
    vec
  end
  def offset_cells(cells)
    ov = canh_offset_vec
    return cells unless ov
    cells.map { |cell_pts| cell_pts.map { |pt| pt.offset(ov) } }
  end
  def get_normal
    return @normal_tu_do if free_mode? && @normal_tu_do
    return nil if @pts.length < 3 || !@pts[0] || !@pts[1] || !@pts[3]
    vec1 = @pts[1] - @pts[0]
    vec2 = @pts[3] - @pts[0]
    normal = vec1.cross(vec2)
    normal.normalize! if normal.length > 0
    normal
  end
  def ray_hit_plane(ray, plane_pt, plane_normal)
    denom = ray[1] % plane_normal
    return nil if denom.abs < 1e-10
    w = plane_pt - ray[0]
    t = (w % plane_normal) / denom
    return nil if t < 0
    ray[0].offset(ray[1], t)
  end
  def project_to_free_plane(pt)
    return pt unless @normal_tu_do && @pts_tu_do && @pts_tu_do.length >= 3
    v = pt - @pts_tu_do[0]
    dist = v % @normal_tu_do
    pt.offset(@normal_tu_do, -dist)
  end
  def project_point_to_axis(pt_start, pt_end)
    vec = pt_end - pt_start
    line = [pt_start, vec]
    pt = nil
    if @ip_valid
      projected = @ip.position.project_to_line(line)
      if vec.length > 0
        v = projected - pt_start
        t = (v % vec) / (vec % vec)
        pt = @ip.position if t > 0.01 && t < 0.99
      end
    end
    if pt.nil?
      return :no_ray unless @last_ray
      pt = Geom.closest_points(line, @last_ray)[0]
    end
    project_to_line_clamped(pt, pt_start, pt_end)
  end
  def determine_2point_normal(p1, p2)
    tolerance = 0.001.mm
    if (p1.x - p2.x).abs < tolerance
      return Geom::Vector3d.new(1, 0, 0)
    elsif (p1.y - p2.y).abs < tolerance
      return Geom::Vector3d.new(0, 1, 0)
    elsif (p1.z - p2.z).abs < tolerance
      return Geom::Vector3d.new(0, 0, 1)
    end
    v = p2 - p1
    z_axis = Geom::Vector3d.new(0, 0, 1)
    normal = v.cross(z_axis)
    return normal.normalize if normal.length > 0
    Geom::Vector3d.new(0, 0, 1)
  end
  def compute_plane_directions(normal)
    normal = normal.normalize
    z_axis = Geom::Vector3d.new(0, 0, 1)
    x_axis = Geom::Vector3d.new(1, 0, 0)
    y_axis = Geom::Vector3d.new(0, 1, 0)
    if normal.parallel?(z_axis)
      [x_axis, y_axis]
    elsif normal.parallel?(x_axis)
      [y_axis, z_axis]
    elsif normal.parallel?(y_axis)
      [x_axis, z_axis]
    else
      u_dir = normal.cross(z_axis)
      u_dir.normalize!
      v_dir = u_dir.cross(normal)
      v_dir.normalize!
      [u_dir, v_dir]
    end
  end
  def compute_rectangle_from_2points(p1, p2, normal)
    u_dir, v_dir = compute_plane_directions(normal)
    diag = p2 - p1
    du = diag % u_dir
    dv = diag % v_dir
    u_vec = Geom::Vector3d.new(u_dir.x * du, u_dir.y * du, u_dir.z * du)
    v_vec = Geom::Vector3d.new(v_dir.x * dv, v_dir.y * dv, v_dir.z * dv)
    @pts[1] = p1.offset(u_vec)
    @pts[2] = @pts[1].offset(v_vec)
    @pts[3] = p1.offset(v_vec)
  end
  def compute_state2_rect(pt1, x, y, view)
    vec_12 = @pts[1] - @pts[0]
    z_axis = Geom::Vector3d.new(0, 0, 1)
    is_perpendicular_to_z = vec_12.length > 0.001 && (vec_12.normalize % z_axis).abs < 0.01
    if is_perpendicular_to_z && !@ip.face && @ip.degrees_of_freedom == 3 && !@locked_normal
      pt2 = pt1.project_to_line(@pts)
      z_vec = Geom::Vector3d.new(0, 0, 1)
      distance = (pt1.z - pt2.z).abs
      vec = pt1.z > pt2.z ? z_vec : z_vec.reverse
      vec.length = distance
      height = distance
    else
      pt2 = pt1.project_to_line(@pts)
      vec = pt1 - pt2
      height = vec.length
    end
    if height > 0
      square_point = pt2.offset(vec, @pts[0].distance(@pts[1]))
      if view.pick_helper.test_point(square_point, x, y)
        @pts[2] = @pts[1].offset(vec, @pts[0].distance(@pts[1]))
        @pts[3] = @pts[0].offset(vec, @pts[0].distance(@pts[1]))
        view.tooltip = "Square"
      else
        @pts[2] = @pts[1].offset(vec)
        @pts[3] = @pts[0].offset(vec)
      end
    else
      @pts[2] = @pts[1]
      @pts[3] = @pts[0]
    end
  end
  def compute_free_bounding_rect
    return unless @pts_tu_do && @pts_tu_do.length >= 3 && @normal_tu_do
    normal = @normal_tu_do
    v1 = @pts_tu_do[1] - @pts_tu_do[0]
    v1_proj = v1 - normal.clone.tap { |n| n.length = v1 % normal }
    return if v1_proj.length < 0.001
    x_axis = v1_proj.normalize
    y_axis = normal.cross(x_axis).normalize
    coords = @pts_tu_do.map do |pt|
      v = pt - @pts_tu_do[0]
      [(v % x_axis), (v % y_axis)]
    end
    x_min, x_max = coords.map { |c| c[0] }.minmax
    y_min, y_max = coords.map { |c| c[1] }.minmax
    origin = @pts_tu_do[0].offset(x_axis, x_min).offset(y_axis, y_min)
    @pts[0] = origin
    @pts[1] = origin.offset(x_axis, x_max - x_min)
    @pts[2] = origin.offset(x_axis, x_max - x_min).offset(y_axis, y_max - y_min)
    @pts[3] = origin.offset(y_axis, y_max - y_min)
  end
  def clip_polygon_to_rect(polygon, rect, normal)
    result = polygon.dup
    rect.length.times do |i|
      j = (i + 1) % rect.length
      edge_vec = rect[j] - rect[i]
      inward = normal.cross(edge_vec)
      inward.normalize! if inward.length > 0
      result = clip_polygon_by_plane(result, rect[i], inward)
      return nil if result.nil? || result.length < 3
    end
    result
  end
  def clip_polygon_by_plane(pts, plane_pt, plane_normal)
    return nil if pts.nil? || pts.length < 3
    output = []
    pts.length.times do |i|
      curr = pts[i]
      nxt = pts[(i + 1) % pts.length]
      d_curr = (curr - plane_pt) % plane_normal
      d_nxt = (nxt - plane_pt) % plane_normal
      if d_curr >= -0.001
        output << curr
        if d_nxt < -0.001
          t = d_curr / (d_curr - d_nxt)
          output << Geom.linear_combination(1 - t, curr, t, nxt)
        end
      elsif d_nxt >= -0.001
        t = d_curr / (d_curr - d_nxt)
        output << Geom.linear_combination(1 - t, curr, t, nxt)
      end
    end
    output.length >= 3 ? output : nil
  end
  def clip_division_line(p1, p2, normal)
    return [p1, p2] unless free_mode? && @pts_tu_do && @pts_tu_do.length >= 3
    clipped = clip_segment_to_polygon(p1, p2, @pts_tu_do, normal)
    clipped || [nil, nil]
  end
  def clip_segment_to_polygon(p1, p2, polygon, normal)
    t_enter = 0.0
    t_exit = 1.0
    seg = p2 - p1
    polygon.length.times do |i|
      j = (i + 1) % polygon.length
      edge_vec = polygon[j] - polygon[i]
      inward = normal.cross(edge_vec)
      inward.normalize! if inward.length > 0
      d_start = (p1 - polygon[i]) % inward
      d_seg = seg % inward
      if d_seg.abs < 1e-10
        return nil if d_start < -0.001
      else
        t = -d_start / d_seg
        if d_seg > 0
          t_enter = [t_enter, t].max
        else
          t_exit = [t_exit, t].min
        end
        return nil if t_enter > t_exit + 0.001
      end
    end
    return nil if t_enter > t_exit + 0.001
    [Geom.linear_combination(1 - t_enter, p1, t_enter, p2),
     Geom.linear_combination(1 - t_exit, p1, t_exit, p2)]
  end
  def point_in_cell?(point, cell_pts, normal)
    signs = cell_pts.each_index.map do |i|
      a = cell_pts[i]
      b = cell_pts[(i + 1) % cell_pts.length]
      (b - a).cross(point - a) % normal
    end
    signs.all? { |s| s >= -0.01.mm } || signs.all? { |s| s <= 0.01.mm }
  end
  def free_mode?
    @phuong_phap_ve == "tu_do"
  end
  def tam_mode?
    @che_do_tool != "chia_canh" && @phuong_phap_ve == "tam"
  end
  def edge_pick_mode?
    @che_do_tool != "chia_canh" && @phuong_phap_ve == "chon_theo_canh"
  end
  def face_pick_mode?
    @che_do_tool != "chia_canh" && @phuong_phap_ve == "chon_theo_mat"
  end
  def edge_or_face_pick_mode?
    edge_pick_mode? || face_pick_mode?
  end
  def bounding_box_mode?
    @che_do_tool != "chia_canh" && @phuong_phap_ve == "bounding_box"
  end
  def batch_pair_mode?
    bounding_box_mode? || tam_mode?
  end
  def measurement_pick_mode?
    edge_pick_mode? || face_pick_mode? || bounding_box_mode? || tam_mode?
  end
  def bounding_box_inout_stage?
    bounding_box_mode? && @state == 3 && @batch_stage == :inout
  end
  def tam_inout_stage?
    false
  end
  def pick_pair_inout_stage?
    bounding_box_inout_stage? || tam_inout_stage?
  end
  def entity_visible?(entity)
    return false unless entity && (!entity.respond_to?(:valid?) || entity.valid?)
    return false if entity.respond_to?(:hidden?) && entity.hidden?
    layer = entity.layer if entity.respond_to?(:layer)
    return false if layer && layer.respond_to?(:visible?) && !layer.visible?
    true
  rescue
    false
  end
  def clear_division_preview_state
    @diem_chia_tang.clear
    @diem_chia_khoang.clear
    @tang_ho.clear
    @khoang_ho.clear
    @ds_o = nil
    @o_hover = nil
    @o_hover_item = nil
    @diem_chia_ht = nil
    @lich_su_chia.clear
  end
  def sub_edge_color
    ec = MH::Panel::View.edge_color
    c = Sketchup::Color.new(ec.red, ec.green, ec.blue)
    c.alpha = 0.5
    c
  end
  def find_hover_cell_idx(x, y, view)
    return nil unless @ds_o && @pts[0] && @pts[1] && @pts[3]
    if batch_preview_active?
      return find_hover_batch_cell_idx(view.pickray(x, y))
    end
    normal = get_normal
    return nil unless normal && normal.length > 0
    ray = view.pickray(x, y)
    hit = ray_hit_plane(ray, @pts[0], normal)
    return nil unless hit
    vec_x = @pts[1] - @pts[0]
    vec_y = @pts[3] - @pts[0]
    return nil if vec_x.length < 0.001 || vec_y.length < 0.001
    v = hit - @pts[0]
    x_dist = v % vec_x.normalize
    y_dist = v % vec_y.normalize
    @ds_o.each_with_index do |cell, i|
      cx_s, cx_e, cy_s, cy_e = cell
      return i if x_dist >= cx_s && x_dist <= cx_e && y_dist >= cy_s && y_dist <= cy_e
    end
    nil
  end
  def find_hover_batch_cell_idx(ray)
    return nil unless ray && @ds_o
    Array(@box_batch_preview).each do |item|
      base_cell = item[:cell]
      normal = item[:normal]
      next unless base_cell && normal

      @ds_o.each_with_index do |bounds, index|
        cell = bounding_box_rect_from_bounds(base_cell, *bounds)
        next unless cell

        hit = ray_hit_plane(ray, cell[0], normal)
        return index if hit && point_in_cell?(hit, cell, normal)
      end
    end
    nil
  end
  def update_mode_buttons
    if @state == 0
      init_mode_buttons(
        ["Tạo cánh", "Chia cánh"],
        active_proc: -> { @che_do_tool == "tao_canh" ? 0 : 1 },
        on_click: -> (i) {
          view = Sketchup.active_model.active_view
          if i == 1 && bounding_box_mode? && bounding_box_selection_count(view) > 0
            prepare_bounding_box_batch_preview(view)
            return
          end
          new_mode = i == 0 ? "tao_canh" : "chia_canh"
          return if @che_do_tool == new_mode
          @che_do_tool = new_mode
          write("che_do_tool", @che_do_tool)
          @mat_noi_bat = nil
          @pts_noi_bat = nil
          update_status
          Sketchup.active_model.active_view.invalidate
        }
      )
      clear_mode_buttons2
    elsif pick_pair_inout_stage?
      init_mode_buttons(
        ["Cánh trong", "Cánh ngoài"],
        active_proc: -> { @dao_chieu ? 1 : 0 },
        on_click: -> (i) {
          new_reversed = (i == 1)
          return if @dao_chieu == new_reversed
          view = Sketchup.active_model.active_view
          @dao_chieu = new_reversed
          write("dao_chieu", @dao_chieu)
          update_status
          view.invalidate
        }
      )
      clear_mode_buttons2
    elsif @state == 3
      init_mode_buttons(
        ["Tổng thể", "Nội bộ"],
        active_proc: -> { @noi_bo ? 1 : 0 },
        on_click: -> (i) {
          new_noi_bo = (i == 1)
          return if @noi_bo == new_noi_bo
          view = Sketchup.active_model.active_view
          toggle_noi_bo(view)
        }
      )
      clear_mode_buttons2
    elsif (@state == 1 || @state == 2) && !bounding_box_mode?
      init_mode_buttons(
        ["Cánh trong", "Cánh ngoài"],
        active_proc: -> { @dao_chieu ? 1 : 0 },
        on_click: -> (i) {
          new_reversed = (i == 1)
          return if @dao_chieu == new_reversed
          view = Sketchup.active_model.active_view
          @dao_chieu = new_reversed
          write("dao_chieu", @dao_chieu)
          update_status
          view.invalidate
        }
      )
      clear_mode_buttons2
    else
      @mb_labels = nil
      clear_mode_buttons2
    end
  end
end

