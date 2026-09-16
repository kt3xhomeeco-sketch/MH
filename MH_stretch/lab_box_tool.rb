# encoding: UTF-8

module MH::Stretch
  class BoxTool
    DRAG_THRESHOLD_PX = 3
    DIMENSION_AXIS_KEYS = { 39 => :x, 40 => :y, 38 => :z }.freeze
    PREF_SECTION = 'MH::Stretch'.freeze
    PREF_PLANE_GRIPS = 'show_plane_grips'.freeze
    PREF_DEFAULT_PLANE = 'show_default_plane'.freeze
    PREF_ALLOW_EXTRA_PLANES = 'allow_extra_planes'.freeze
    PREF_DC_REDRAW = 'dc_redraw_enabled'.freeze
    PREF_OFFSET_PLANES = 'offset_planes_enabled'.freeze
    PREF_OFFSET_DISTANCE = 'offset_plane_distance'.freeze
    PREF_OFFSET_COUNT = 'offset_plane_count'.freeze
    PREF_OFFSET_MODE = 'offset_plane_mode'.freeze
    PREF_OFFSET_DIVISIONS = 'offset_plane_divisions'.freeze
    PREF_NO_PLANE_MODE = 'no_plane_mode'.freeze
    PREF_DIM_OFFSET_AXIS = 'dimension_offset_axis'.freeze
    PREF_DIM_OFFSET_AXES = 'dimension_offset_axes'.freeze
    DEFAULT_OFFSET_DISTANCE = 20.mm

    def initialize
      @state = State.new
      @planes = PlaneStore.new
      @ip = Sketchup::InputPoint.new
      @target_ip = Sketchup::InputPoint.new
      @drag_ip = Sketchup::InputPoint.new
      @bb = nil
      @drag = nil
      @preview_segments = []
      @creation_preview = nil
      @cursor_xy = nil
      @hover_target = nil
      @active_axis = nil
      @active_side = :plus
      @pinned_plane_id = nil
      @dimension_hits = {}
      @hover_dimension_axis = nil
      @target_mode = false
      @target_source_point = nil
      @target_point = nil
      @target_operation = nil
      @ctrl_snap_active = false
      @target_reference_ip = nil
      @last_unique_selection_key = nil
      @show_plane_grips =
        Sketchup.read_default(PREF_SECTION, PREF_PLANE_GRIPS, true) != false
      @show_default_plane =
        Sketchup.read_default(PREF_SECTION, PREF_DEFAULT_PLANE, true) != false
      @allow_extra_planes =
        Sketchup.read_default(PREF_SECTION, PREF_ALLOW_EXTRA_PLANES, true) != false
      @dc_redraw_enabled =
        Sketchup.read_default(PREF_SECTION, PREF_DC_REDRAW, true) != false
      @offset_planes_enabled =
        truthy_pref?(Sketchup.read_default(PREF_SECTION, PREF_OFFSET_PLANES, false))
      @offset_plane_distance = read_offset_plane_distance
      @offset_plane_count =
        Sketchup.read_default(PREF_SECTION, PREF_OFFSET_COUNT, 1).to_i == 2 ? 2 : 1
      @offset_plane_mode = read_offset_plane_mode
      @offset_plane_divisions = read_offset_plane_divisions
      @no_plane_mode = read_no_plane_mode
      @dimension_offset_axes = read_dimension_offset_axes
      @pending_redraw_components = []
    end

    def activate
      auto_make_unique_current_selection
      refresh_bounds
      if BoxModel.empty_bounds?(@bb)
        Sketchup.status_text = 'MH Stretch | Hover object để xem dim | Click object để chọn UI box.'
      else
        Sketchup.status_text = 'MH Stretch | Chọn grip/plane rồi kéo để stretch.'
      end
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def onCancel(_reason, view)
      cancel_or_exit(view)
    end

    def onMouseMove(flags, x, y, view)
      update_hover_target(x, y, view) if selection_empty? && !@drag && !@target_mode
      refresh_bounds
      update_ctrl_snap_preview(flags, x, y, view)
      if BoxModel.empty_bounds?(@bb)
        @state.set_hover(nil)
        @creation_preview = nil
        @dimension_hits.clear
        @hover_dimension_axis = nil
        @ip.clear
        update_status
        return view.invalidate
      end

      if @drag
        @creation_preview = nil
        update_drag(x, y, view)
      elsif @target_mode
        update_target_preview(x, y, view)
      elsif hover_preview?
        @state.set_hover(nil)
        @creation_preview = nil
        @dimension_hits.clear
        @hover_dimension_axis = nil
        @ip.clear
        @cursor_xy = [x, y]
        view.tooltip = 'Click để chọn object'
        update_status
      else
        @hover_dimension_axis = dimension_axis_at(x, y)
        hit =
          unless @hover_dimension_axis
            HitTest.new(
              view,
              @bb,
              @planes.planes,
              @show_plane_grips
            ).hit(x, y)
          end
        activate_hovered_axis(hit) if hit && hit[:kind] == :handle && !pinned_plane?
        @state.set_hover(hit)
        @cursor_xy = [x, y]
        if hit || @hover_dimension_axis
          @creation_preview = nil
          @ip.clear
          view.tooltip = @hover_dimension_axis ? 'Click để nhập kích thước' : nil
        else
          @creation_preview = @allow_extra_planes ? build_creation_preview(x, y, view) : nil
          @ip.clear unless @allow_extra_planes
          view.tooltip = @ip.valid? ? @ip.tooltip : nil
        end
        update_status
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      update_hover_target(x, y, view) if selection_empty? && !@drag && !@target_mode
      refresh_bounds
      return if BoxModel.empty_bounds?(@bb)

      if hover_preview?
        select_hover_target(view)
        update_status
        view.invalidate
        return
      end

      if ctrl_down?(flags) && !@drag
        arm_target_mode(x, y, view)
        view.invalidate
        return
      end

      if @target_mode
        commit_target(view)
        return
      end

      if @drag && @drag[:type] == :grip && @drag[:click_grip]
        update_grip_drag(x, y, view, force: true)
        finish_grip_drag(view)
        update_status
        view.invalidate
        return
      end

      if (axis = dimension_axis_at(x, y))
        input_dimension(axis, view)
        return
      end

      case @state.hover[:kind]
      when :plane_grip
        start_plane_side_drag(@state.hover[:id], @state.hover[:side], x, y, view)
      when :plane
        start_plane_drag(@state.hover[:id], x, y)
      when :handle
        clear_pinned_plane
        start_grip_drag(@state.hover[:axis], @state.hover[:side], x, y, view)
      else
        add_creation_preview
      end

      update_status
      view.invalidate
    end

    def onLButtonUp(_flags, _x, _y, view)
      if @drag
        return if @drag[:click_grip]

        commit_or_finish_drag(view)
        update_status
        view.invalidate
      end
    end

    def onKeyDown(key, _repeat, _flags, view)
      case key
      when 9
        toggle_plane_mode
      when 27
        cancel_or_exit(view)
        return
      when 46
        delete_active_plane
      else
        return input_dimension_from_key(key, view)
      end
      refresh_creation_preview(view)
      update_status
      view.invalidate
    end

    # Text entered into SketchUp's Measurements box while MH Stretch is active
    # configures the automatic offset planes.  During a drag, the box retains
    # SketchUp's normal distance-entry behavior instead.
    def onUserText(text, view)
      return if @drag || @target_mode

      if (divisions = parse_offset_divisions(text))
        return configure_offset_divisions(divisions, view)
      end

      distance = parse_offset_distance(text)
      unless distance
        Sketchup.status_text = 'MH Stretch | Offset plane không hợp lệ.'
        return
      end

      @offset_plane_distance = distance
      @offset_plane_divisions = nil
      @no_plane_mode = false
      if !@offset_planes_enabled
        @offset_planes_enabled = true
        @offset_plane_count = 1
        @offset_plane_mode = :near
        @show_default_plane = false
      end
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_PLANES, @offset_planes_enabled)
      Sketchup.write_default(PREF_SECTION, PREF_DEFAULT_PLANE, @show_default_plane)
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_COUNT, @offset_plane_count)
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_DISTANCE, Sketchup.format_length(@offset_plane_distance))
      write_offset_plane_mode
      write_offset_plane_divisions
      write_no_plane_mode

      @planes.clear_defaults!
      @planes.clear_hidden_defaults!
      sync_offset_planes if @active_axis
      Sketchup.status_text = "MH Stretch | Offset plane: #{offset_plane_label}."
      refresh_creation_preview(view)
      view.invalidate
    rescue => error
      warn "MH::Stretch offset input failed: #{error.class}: #{error.message}"
    end

    def getMenu(menu)
      settings = menu.add_submenu('Cài đặt')
      grip_item = settings.add_item('Hiện grip +/- của plane') do
        toggle_plane_grip_grips
      end
      settings.set_validation_proc(grip_item) do
        @show_plane_grips ? MF_CHECKED : MF_UNCHECKED
      end
      plane_item = settings.add_item('Hiện plane mặc định ở giữa') do
        toggle_default_plane
      end
      settings.set_validation_proc(plane_item) do
        @show_default_plane ? MF_CHECKED : MF_UNCHECKED
      end
      extra_item = settings.add_item('Cho phép tạo thêm plane') do
        toggle_extra_planes
      end
      settings.set_validation_proc(extra_item) do
        @allow_extra_planes ? MF_CHECKED : MF_UNCHECKED
      end
      redraw_item = settings.add_item('Tự redraw DC sau stretch') do
        toggle_dc_redraw
      end
      settings.set_validation_proc(redraw_item) do
        @dc_redraw_enabled ? MF_CHECKED : MF_UNCHECKED
      end
      settings.add_separator
      offset_item = settings.add_item('Tự đặt plane theo offset') do
        toggle_offset_planes
      end
      settings.set_validation_proc(offset_item) do
        @offset_planes_enabled ? MF_CHECKED : MF_UNCHECKED
      end
      settings.add_item("Cài offset plane (#{offset_plane_label})") do
        configure_offset_planes
      end
      move_axis_menu = settings.add_submenu("Trục move sau space: #{dimension_offset_axes_label}")
      BoxModel::AXES.each do |axis|
        item = move_axis_menu.add_item(axis.to_s.upcase) do
          toggle_dimension_offset_axis(axis)
        end
        move_axis_menu.set_validation_proc(item) do
          @dimension_offset_axes.include?(axis) ? MF_CHECKED : MF_UNCHECKED
        end
      end
      menu.add_separator
      menu.add_item('Make unique selection ngay') { make_unique_selection_now; Sketchup.active_model.active_view.invalidate }
      menu.add_item('Xóa active plane') { delete_active_plane; Sketchup.active_model.active_view.invalidate }
      menu.add_item('Clear user planes') { @planes.clear_user!; Sketchup.active_model.active_view.invalidate }
      menu.add_separator
      menu.add_item('Thoát MH Stretch') { Sketchup.active_model.select_tool(nil) }
    end

    def draw(view)
      refresh_bounds
      return if BoxModel.empty_bounds?(@bb)

      if hover_preview?
        DimensionRenderer.new(view, @bb).draw
        return
      end

      Overlay.new(
        view,
        @bb,
        @state,
        @planes.planes,
        @preview_segments,
        @creation_preview,
        dimension_preview,
        @show_plane_grips,
        @dimension_hits,
        @hover_dimension_axis
      ).draw
      @ip.draw(view) if @ip.valid?
      @drag_ip.draw(view) if grip_dragging? && @drag_ip.valid?
      draw_target(view)
      @target_ip.draw(view) if (@target_mode || @ctrl_snap_active) && @target_ip.valid?
    end

    def getExtents
      refresh_bounds
      bb = Geom::BoundingBox.new
      return bb if BoxModel.empty_bounds?(@bb)

      bb.add(@bb.min, @bb.max)
      @planes.planes.each do |plane|
        next unless plane[:usable]
        next if plane[:hidden]

        bb.add(BoxModel.display_plane_points(@bb, plane))
        bb.add(BoxModel.plane_center(@bb, plane))
      end
      @preview_segments.each { |a, b| bb.add(a, b) }
      bb.add(BoxModel.display_plane_points(@bb, @creation_preview)) if @creation_preview
      bb.add(@target_source_point) if @target_source_point
      bb.add(@target_point) if @target_point
      bb
    end

    private

    def refresh_bounds
      model = Sketchup.active_model
      if model.selection.empty?
        @last_unique_selection_key = nil
        @bb = hover_target_bounds
      else
        auto_make_unique_current_selection(model)
        @hover_target = nil
        @bb = BoxModel.selection_bounds(model)
        @planes.reclamp!(@bb) unless BoxModel.empty_bounds?(@bb)
      end
    end

    def selection_empty?
      Sketchup.active_model.selection.empty?
    rescue
      true
    end

    def hover_preview?
      selection_empty? && valid_hover_target? && !BoxModel.empty_bounds?(@bb)
    end

    def valid_hover_target?
      @hover_target && (!@hover_target.respond_to?(:valid?) || @hover_target.valid?)
    rescue
      false
    end

    def hover_target_bounds
      bb = Geom::BoundingBox.new
      bb.add(@hover_target.bounds) if valid_hover_target? && @hover_target.respond_to?(:bounds)
      bb
    rescue
      Geom::BoundingBox.new
    end

    def update_hover_target(x, y, view)
      picked = pick_hover_target(x, y, view)
      return if picked == @hover_target

      @hover_target = picked
      @dimension_hits.clear
      @hover_dimension_axis = nil
    end

    def pick_hover_target(x, y, view)
      helper = view.pick_helper
      helper.do_pick(x, y)

      target = selectable_from_pick_path(helper)
      target ||= selectable_entity(helper.best_picked) if helper.respond_to?(:best_picked)
      target
    rescue
      nil
    end

    def selectable_from_pick_path(helper)
      return nil unless helper.respond_to?(:count) && helper.respond_to?(:path_at)

      0.upto(helper.count - 1) do |index|
        path = helper.path_at(index) rescue nil
        entities = pick_path_entities(path)
        target = entities.find { |entity| selectable_entity(entity, containers_only: true) }
        target ||= entities.find { |entity| selectable_entity(entity) }
        return target if target
      end
      nil
    end

    def pick_path_entities(path)
      return [] unless path
      return path.to_a if path.respond_to?(:to_a)
      return path if path.is_a?(Array)

      []
    rescue
      []
    end

    def selectable_entity(entity, containers_only: false)
      return nil unless entity
      return nil if entity.respond_to?(:valid?) && !entity.valid?
      return nil if entity.respond_to?(:hidden?) && entity.hidden?
      return nil if entity.respond_to?(:locked?) && entity.locked?

      container =
        entity.is_a?(Sketchup::Group) ||
        entity.is_a?(Sketchup::ComponentInstance)
      return entity if container
      return nil if containers_only

      entity.respond_to?(:bounds) ? entity : nil
    rescue
      nil
    end

    def select_hover_target(view)
      return unless valid_hover_target?

      model = Sketchup.active_model
      model.selection.clear
      model.selection.add(@hover_target)
      auto_make_unique_current_selection(model)
      @hover_target = nil
      @active_axis = nil
      @active_side = :plus
      clear_pinned_plane
      @planes.planes.clear
      @state.set_active(nil)
      @state.set_hover(nil)
      @creation_preview = nil
      @dimension_hits.clear
      @hover_dimension_axis = nil
      refresh_actual_bounds
      view.tooltip = nil
      Sketchup.status_text = 'MH Stretch | Đã chọn object. Hover grip để chọn trục.'
    rescue => e
      warn "MH::Stretch select hover target failed: #{e.class}: #{e.message}"
    end

    def toggle_plane_grip_grips
      @show_plane_grips = !@show_plane_grips
      Sketchup.write_default(
        PREF_SECTION,
        PREF_PLANE_GRIPS,
        @show_plane_grips
      )
      if !@show_plane_grips && @state.hover[:kind] == :plane_grip
        @state.set_hover(nil)
      end
      Sketchup.active_model.active_view.invalidate
    end

    def toggle_default_plane
      @show_default_plane = !@show_default_plane
      @no_plane_mode = !@show_default_plane && !@offset_planes_enabled
      Sketchup.write_default(
        PREF_SECTION,
        PREF_DEFAULT_PLANE,
        @show_default_plane
      )
      write_no_plane_mode

      if @offset_planes_enabled
        @planes.clear_defaults!
        @planes.clear_hidden_defaults!
        ensure_active_axis_plane if @active_axis
      elsif @show_default_plane
        @planes.clear_hidden_defaults!
        ensure_active_axis_plane if @active_axis
      else
        @planes.clear_defaults!
        sync_hidden_default_planes if @active_axis && !@no_plane_mode
        @planes.clear_hidden_defaults! if @no_plane_mode
        @state.set_active(nil)
        @state.set_hover(nil)
      end
      @creation_preview = nil
      Sketchup.active_model.active_view.invalidate
    end

    def toggle_extra_planes
      @allow_extra_planes = !@allow_extra_planes
      Sketchup.write_default(
        PREF_SECTION,
        PREF_ALLOW_EXTRA_PLANES,
        @allow_extra_planes
      )
      @creation_preview = nil
      @ip.clear unless @allow_extra_planes
      Sketchup.active_model.active_view.invalidate
    end

    def toggle_dc_redraw
      @dc_redraw_enabled = !@dc_redraw_enabled
      Sketchup.write_default(
        PREF_SECTION,
        PREF_DC_REDRAW,
        @dc_redraw_enabled
      )
      Sketchup.status_text =
        @dc_redraw_enabled ? 'MH Stretch | Redraw DC: bật' : 'MH Stretch | Redraw DC: tắt'
    end

    def toggle_offset_planes
      @offset_planes_enabled = !@offset_planes_enabled
      @offset_plane_mode = :near if @offset_planes_enabled
      @offset_plane_divisions = nil
      @no_plane_mode = !@offset_planes_enabled && !@show_default_plane
      Sketchup.write_default(
        PREF_SECTION,
        PREF_OFFSET_PLANES,
        @offset_planes_enabled
      )
      write_offset_plane_mode if @offset_planes_enabled
      write_offset_plane_divisions
      write_no_plane_mode
      if @offset_planes_enabled
        @planes.clear_defaults!
        @planes.clear_hidden_defaults!
        ensure_active_axis_plane if @active_axis
      else
        @planes.clear_offset_planes!
        ensure_active_axis_plane if @active_axis
      end
      @creation_preview = nil
      Sketchup.status_text =
        @offset_planes_enabled ? 'MH Stretch | Offset plane: bật' : 'MH Stretch | Offset plane: tắt'
      Sketchup.active_model.active_view.invalidate
    end

    def toggle_plane_mode
      if @offset_plane_divisions
        @offset_planes_enabled = true
        @offset_plane_divisions = nil
        @offset_plane_count = 1
        @offset_plane_mode = :near
        @no_plane_mode = false
        status = "MH Stretch | 1 mặt gần đầu mút: #{Sketchup.format_length(@offset_plane_distance)}"
      elsif !@offset_planes_enabled
        @offset_planes_enabled = true
        @show_default_plane = false
        @offset_plane_count = 1
        @offset_plane_mode = :near
        @no_plane_mode = false
        status = "MH Stretch | 1 mặt gần đầu mút: #{Sketchup.format_length(@offset_plane_distance)}"
      elsif @offset_plane_count == 1
        @no_plane_mode = false
        if @offset_plane_mode == :near
          @offset_plane_mode = :opposite
          status = "MH Stretch | 1 mặt đối diện đầu mút: #{Sketchup.format_length(@offset_plane_distance)}"
        else
          @offset_plane_count = 2
          status = "MH Stretch | 2 mặt theo offset: #{Sketchup.format_length(@offset_plane_distance)}"
        end
      else
        @offset_planes_enabled = false
        @show_default_plane = false
        @no_plane_mode = true
        status = 'MH Stretch | Không có mặt stretch'
      end

      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_PLANES, @offset_planes_enabled)
      Sketchup.write_default(PREF_SECTION, PREF_DEFAULT_PLANE, @show_default_plane)
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_COUNT, @offset_plane_count)
      write_offset_plane_mode
      write_offset_plane_divisions
      write_no_plane_mode

      if @offset_planes_enabled
        @planes.clear_defaults!
        @planes.clear_hidden_defaults!
        sync_offset_planes if @active_axis
      else
        @planes.clear_offset_planes!
        @planes.clear_hidden_defaults!
        ensure_active_axis_plane if @active_axis
      end

      @creation_preview = nil
      Sketchup.status_text = status
      Sketchup.active_model.active_view.invalidate
    end

    def configure_offset_planes
      result = UI.inputbox(
        ['Offset cách mép:', 'Số mặt offset (1 hoặc 2):'],
        [Sketchup.format_length(@offset_plane_distance), @offset_plane_count.to_s],
        'MH Stretch - Offset Plane'
      )
      return unless result

      distance = parse_length(result[0])
      count = result[1].to_i
      unless distance && distance >= 0 && [1, 2].include?(count)
        UI.messagebox('Offset không hợp lệ. Nhập khoảng cách >= 0 và số mặt là 1 hoặc 2.')
        return
      end

      @offset_plane_distance = distance.to_f
      @offset_plane_count = count
      @offset_plane_mode = :near if count == 1
      @offset_plane_divisions = nil
      @no_plane_mode = false
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_DISTANCE, Sketchup.format_length(@offset_plane_distance))
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_COUNT, @offset_plane_count)
      write_offset_plane_mode
      write_offset_plane_divisions
      write_no_plane_mode
      sync_offset_planes if @offset_planes_enabled
      Sketchup.status_text = "MH Stretch | Offset plane #{offset_plane_label}."
      Sketchup.active_model.active_view.invalidate
    end

    def toggle_dimension_offset_axis(axis)
      axis = normalize_axis_pref(axis)
      if @dimension_offset_axes.include?(axis)
        if @dimension_offset_axes.length <= 1
          Sketchup.status_text = 'MH Stretch | Phải giữ ít nhất 1 trục move sau space.'
          return
        end
        @dimension_offset_axes = @dimension_offset_axes - [axis]
      else
        @dimension_offset_axes = (@dimension_offset_axes + [axis]).uniq
      end
      write_dimension_offset_axes
      Sketchup.status_text = "MH Stretch | Move sau space chọn trục #{dimension_offset_axes_label}."
      Sketchup.active_model.active_view.invalidate
    end

    def make_unique_selection_now
      model = Sketchup.active_model
      return if model.selection.empty?

      model.start_operation('MH Stretch Make Unique', true)
      changed = UiAdapter.make_unique_selection(model)
      model.commit_operation
      Sketchup.status_text = "MH Stretch | Make unique #{changed} object."
      @last_unique_selection_key = selection_key(model.selection.to_a)
      refresh_actual_bounds
    rescue => error
      model.abort_operation rescue nil
      Sketchup.status_text = "MH Stretch | Make unique lỗi: #{error.message}"
      warn "MH::Stretch make unique selection failed: #{error.class}: #{error.message}"
    end

    def auto_make_unique_current_selection(model = Sketchup.active_model)
      selection = model.selection.to_a
      if selection.empty?
        @last_unique_selection_key = nil
        return 0
      end

      key = selection_key(selection)
      return 0 if key == @last_unique_selection_key

      @last_unique_selection_key = key
      return 0 unless selection.any? { |entity| PlaneVertexSelector.group_or_component?(entity) }

      model.start_operation('MH Stretch Auto Make Unique', true)
      changed = UiAdapter.make_unique_selection(model)
      model.commit_operation
      @last_unique_selection_key = selection_key(model.selection.to_a)
      Sketchup.status_text = "MH Stretch | Auto make unique #{changed} object." if changed.positive?
      changed
    rescue => error
      model.abort_operation rescue nil
      warn "MH::Stretch auto make unique failed: #{error.class}: #{error.message}"
      0
    end

    def selection_key(selection)
      selection.map do |entity|
        if entity.respond_to?(:persistent_id)
          entity.persistent_id
        else
          entity.object_id
        end
      end.sort
    rescue
      []
    end

    def dimension_preview
      return nil unless @drag && @drag[:type] == :grip && @drag[:started]

      {
        axis: @drag[:axis],
        side: @drag[:side],
        amount: @drag[:amount]
      }
    end

    def grip_dragging?
      @drag && @drag[:type] == :grip
    end

    def arm_target_mode(x, y, view)
      handle_hit = HitTest.new(
        view,
        @bb,
        @planes.planes,
        @show_plane_grips
      ).hit_handle(x, y)

      axis = handle_hit ? handle_hit[:axis] : @active_axis
      unless axis
        Sketchup.status_text = 'MH Stretch | Chọn grip trục trước khi dùng target.'
        return
      end

      @target_ip.clear
      reference_point =
        if handle_hit
          grip_reference_point(handle_hit[:axis], handle_hit[:side])
        else
          grip_reference_point
        end
      pick_target_input_point(view, x, y, reference_point)
      picked =
        if @target_ip.valid? && strong_input_point?(@target_ip)
          @target_ip.position
        end
      source =
        if handle_hit
          match = BoxModel.face_handles(@bb).find do |key, _point|
            key[:axis] == handle_hit[:axis] && key[:side] == handle_hit[:side]
          end
          match && match.last
        elsif picked
          outside_face_source(picked, axis) || picked
        end

      unless source
        Sketchup.status_text = 'MH Stretch | Ctrl+click vertex/edge để bắt điểm kéo.'
        return
      end

      side =
        if handle_hit
          handle_hit[:side] || :plus
        elsif picked && outside_axis_side(picked, axis)
          outside_axis_side(picked, axis)
        else
          value = BoxModel.axis_value(source, axis)
          if (value - BoxModel.axis_min(@bb, axis)).abs <=
             (value - BoxModel.axis_max(@bb, axis)).abs
            :minus
          else
            :plus
          end
      end
      switch_axis(axis, side)
      between_region = BetweenPlanesAdapter.region_for_grip(
        axis: axis,
        grip_point: source,
        planes: @planes.planes
      )
      @target_operation =
        if between_region
          {
            mode: :between_planes,
            axis: axis,
            side: side,
            between_region: between_region
          }
        else
          plane = active_plane_for(axis)
          cuts = UiAdapter.bbox_handle_cut_planes(axis, side, @planes.planes)
          {
            axis: axis,
            side: side,
            plane_id: plane && plane[:id],
            cuts: cuts,
            box_grip: plane.nil? && cuts.empty?
          }
        end
      @target_source_point = source.clone
      @target_point = picked && outside_axis_side(picked, axis) ? target_point_from_world_point(picked, source, axis) : nil
      @target_mode = true
      @preview_segments = []
      @creation_preview = nil
      if @target_point
        amount =
          BoxModel.axis_value(@target_point, axis) -
          BoxModel.axis_value(@target_source_point, axis)
        @target_operation[:amount] = amount
        @preview_segments = preview_operation(@target_operation, amount)
      end
      Sketchup.status_text =
        if @target_point
          "MH Stretch | Target vuông góc #{axis.to_s.upcase}#{side == :minus ? '-' : '+'}. Click để hoàn thành."
        else
          "MH Stretch | Đã chọn điểm kéo #{axis.to_s.upcase}#{side == :minus ? '-' : '+'}. Click điểm target."
        end
    end

    def update_target_preview(x, y, view)
      return unless @target_operation && @target_source_point

      pick_target_input_point(view, x, y, @target_source_point)
      @target_point = target_point_from_mouse(
        x,
        y,
        view,
        @target_source_point,
        @target_operation[:axis]
      )
      return unless @target_point
      amount =
        BoxModel.axis_value(@target_point, @target_operation[:axis]) -
        BoxModel.axis_value(@target_source_point, @target_operation[:axis])
      @target_operation[:amount] = amount
      @preview_segments = preview_operation(@target_operation, amount)
      view.tooltip = @target_ip.valid? ? @target_ip.tooltip : ''
      Sketchup.status_text =
        "MH Stretch | Target Δ #{Sketchup.format_length(amount)} | Click để hoàn thành."
    end

    def commit_target(view)
      return unless @target_operation && @target_point

      result = commit_operation(@target_operation, @target_operation[:amount].to_f)
      clear_target
      finish_model_change(result, view)
    end

    def draw_target(view)
      return unless @target_source_point

      color = BoxModel.color(@target_operation ? @target_operation[:axis] : @active_axis)
      view.draw_points([@target_source_point], (7 * ui_scale).to_i, 7, color)
      return unless @target_point

      view.line_stipple = '-'
      view.line_width = 2 * ui_scale
      view.drawing_color = color
      view.draw(GL_LINES, [@target_source_point, @target_point])
      view.line_stipple = ''
    end

    def clear_target
      @target_mode = false
      @target_source_point = nil
      @target_point = nil
      @target_operation = nil
      @ctrl_snap_active = false
      @target_reference_ip = nil
      @target_ip.clear
      @preview_segments = []
    end

    def update_ctrl_snap_preview(flags, x, y, view)
      active = ctrl_down?(flags) && !@drag && !@target_mode && !BoxModel.empty_bounds?(@bb)
      unless active
        if @ctrl_snap_active
          @ctrl_snap_active = false
          @target_ip.clear unless @target_mode
          view.tooltip = nil unless @target_mode
        end
        return
      end

      @ctrl_snap_active = true
      @target_ip.clear
      pick_target_input_point(view, x, y, snap_reference_point(view, x, y))
      if @target_ip.valid? && strong_input_point?(@target_ip)
        view.tooltip = @target_ip.tooltip
        Sketchup.status_text = 'MH Stretch | Ctrl snap: đã bắt điểm, click để chọn điểm kéo.'
      else
        view.tooltip = 'Giữ Ctrl và đưa chuột vào vertex/edge để bắt điểm.'
        Sketchup.status_text = 'MH Stretch | Ctrl snap: tìm vertex/edge.'
      end
    rescue
      @target_ip.clear
    end

    def pick_target_input_point(view, x, y, reference_point = nil)
      if reference_point
        @target_reference_ip = Sketchup::InputPoint.new(reference_point)
        @target_ip.pick(view, x, y, @target_reference_ip)
      else
        @target_reference_ip = nil
        @target_ip.pick(view, x, y)
      end
    rescue ArgumentError
      @target_reference_ip = nil
      @target_ip.pick(view, x, y)
    rescue
      @target_ip.clear
    end

    def snap_reference_point(view, x, y)
      handle = HitTest.new(
        view,
        @bb,
        @planes.planes,
        @show_plane_grips
      ).hit_handle(x, y)
      return grip_reference_point(handle[:axis], handle[:side]) if handle

      grip_reference_point
    rescue
      grip_reference_point
    end

    def grip_reference_point(axis = @active_axis, side = @active_side)
      return nil unless axis && @bb && !BoxModel.empty_bounds?(@bb)

      handle = BoxModel.face_handles(@bb).find do |key, _point|
        key[:axis] == axis && key[:side] == (side || :plus)
      end
      handle && handle.last
    rescue
      nil
    end

    def target_point_from_mouse(x, y, view, source, axis)
      if usable_target_input_point?(view, x, y)
        return target_point_from_world_point(@target_ip.position, source, axis)
      end

      ray = view.pickray(x, y)
      return nil unless ray

      closest = Geom.closest_points(ray, [source, axis_vector(axis)])
      closest && closest[1]
    rescue
      nil
    end

    def usable_target_input_point?(view, x, y)
      return false unless @target_ip && @target_ip.valid?
      return false unless strong_input_point?(@target_ip)

      input_point_screen_close?(@target_ip, view, x, y)
    rescue
      false
    end

    def target_point_from_world_point(point, source, axis)
      amount = BoxModel.axis_value(point, axis) - BoxModel.axis_value(source, axis)
      source.offset(axis_vector(axis), amount)
    end

    def outside_face_source(point, axis)
      side = outside_axis_side(point, axis)
      return nil unless side

      face_value = side == :minus ? BoxModel.axis_min(@bb, axis) : BoxModel.axis_max(@bb, axis)
      axis_point(point, axis, face_value)
    end

    def outside_axis_side(point, axis)
      value = BoxModel.axis_value(point, axis)
      return :minus if value < BoxModel.axis_min(@bb, axis) - BoxModel::MIN_LEN
      return :plus if value > BoxModel.axis_max(@bb, axis) + BoxModel::MIN_LEN

      nil
    end

    def dimension_axis_at(x, y)
      @dimension_hits.each do |axis, rect|
        rx, ry, width, height = rect
        return axis if x >= rx && x <= rx + width && y >= ry && y <= ry + height
      end
      nil
    end

    def parse_dimension_input(text, current)
      raw = text.to_s
      input = raw.strip
      return { target: nil, view_offset: nil } if input.empty?

      parts = input.split(/\s+/)
      offset = nil
      dimension_text = input
      if raw =~ /\s/ && !parts.empty?
        token = parts.last
        offset = parse_view_offset_token(token)
        if offset
          dimension_text = parts[0...-1].join(' ')
          dimension_text = current_dimension_text(current) if dimension_text.empty?
        end
      end

      {
        target: parse_dimension_target(dimension_text, current),
        view_offset: offset
      }
    end

    def parse_dimension_target(text, current)
      input = text.to_s.strip
      return nil if input.empty?

      if (match = input.match(/\A([+\-])\s*(.+)\z/))
        length = parse_length(match[2])
        return nil unless length

        return match[1] == '-' ? current - length : current + length
      end

      if (match = input.match(%r{\A([*/])\s*([0-9]+(?:[.,][0-9]+)?)\z}))
        factor = match[2].tr(',', '.').to_f
        return nil if factor <= 0

        return match[1] == '*' ? current * factor : current / factor
      end

      parse_length(input)
    end

    def parse_length(text)
      input = text.to_s.strip
      return nil if input.empty?
      return input.tr(',', '.').to_f.mm if input.match?(/\A\d+(?:[,.]\d+)?\z/)

      Sketchup.parse_length(input)
    rescue
      nil
    end

    def parse_offset_distance(text)
      input = text.to_s.strip
      return nil if input.empty? || input.start_with?('-')

      length = parse_length(input.sub(/\A\+/, ''))
      return nil unless length && length >= 0

      length.to_f
    rescue
      nil
    end

    def parse_offset_divisions(text)
      match = text.to_s.strip.match(%r{\A/\s*(\d+)\z})
      return nil unless match

      divisions = match[1].to_i
      divisions >= 2 ? divisions : nil
    end

    def configure_offset_divisions(divisions, view)
      refresh_bounds
      unless @active_axis && @bb && BoxModel.usable_axis?(@bb, @active_axis)
        Sketchup.status_text = 'MH Stretch | Hover hoặc chọn trục trước khi nhập /x.'
        return
      end

      @offset_plane_divisions = divisions
      @offset_plane_distance = BoxModel.axis_length(@bb, @active_axis).to_f / divisions
      @offset_planes_enabled = true
      @show_default_plane = false
      @offset_plane_count = 1
      @offset_plane_mode = :near
      @no_plane_mode = false
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_PLANES, true)
      Sketchup.write_default(PREF_SECTION, PREF_DEFAULT_PLANE, false)
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_COUNT, @offset_plane_count)
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_DISTANCE, Sketchup.format_length(@offset_plane_distance))
      write_offset_plane_mode
      write_offset_plane_divisions
      write_no_plane_mode

      @planes.clear_defaults!
      @planes.clear_hidden_defaults!
      sync_offset_planes
      Sketchup.status_text = "MH Stretch | Chia trục #{@active_axis.to_s.upcase} thành #{divisions} phần; offset #{Sketchup.format_length(@offset_plane_distance)}."
      refresh_creation_preview(view)
      view.invalidate
    end

    def read_offset_plane_distance
      stored = Sketchup.read_default(PREF_SECTION, PREF_OFFSET_DISTANCE, Sketchup.format_length(DEFAULT_OFFSET_DISTANCE))
      value = stored.is_a?(Numeric) ? stored.to_f : parse_length(stored)
      value && value >= 0 ? value.to_f : DEFAULT_OFFSET_DISTANCE
    rescue
      DEFAULT_OFFSET_DISTANCE
    end

    def read_offset_plane_mode
      Sketchup.read_default(PREF_SECTION, PREF_OFFSET_MODE, 'near').to_s == 'opposite' ? :opposite : :near
    rescue
      :near
    end

    def read_offset_plane_divisions
      value = Sketchup.read_default(PREF_SECTION, PREF_OFFSET_DIVISIONS, 0).to_i
      value >= 2 ? value : nil
    rescue
      nil
    end

    def read_no_plane_mode
      stored = Sketchup.read_default(PREF_SECTION, PREF_NO_PLANE_MODE, nil)
      return truthy_pref?(stored) unless stored.nil?

      !@offset_planes_enabled && !@show_default_plane
    rescue
      false
    end

    def write_offset_plane_mode
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_MODE, (@offset_plane_mode || :near).to_s)
    end

    def write_offset_plane_divisions
      Sketchup.write_default(PREF_SECTION, PREF_OFFSET_DIVISIONS, @offset_plane_divisions || 0)
    end

    def write_no_plane_mode
      Sketchup.write_default(PREF_SECTION, PREF_NO_PLANE_MODE, !!@no_plane_mode)
    end

    def opposite_side(side)
      side == :minus ? :plus : :minus
    end

    def truthy_pref?(value)
      value == true || value.to_s.downcase == 'true'
    end

    def normalize_axis_pref(value)
      axis = value.to_s.downcase.to_sym
      BoxModel::AXES.include?(axis) ? axis : :x
    end

    def read_dimension_offset_axes
      stored = Sketchup.read_default(PREF_SECTION, PREF_DIM_OFFSET_AXES, nil)
      axes = parse_axes_pref(stored)
      if axes.empty?
        axes = [normalize_axis_pref(Sketchup.read_default(PREF_SECTION, PREF_DIM_OFFSET_AXIS, :x))]
      end
      axes.empty? ? [:x] : axes
    rescue
      [:x]
    end

    def parse_axes_pref(value)
      value.to_s.split(/[,\s]+/).each_with_object([]) do |item, axes|
        axis = normalize_axis_pref(item)
        axes << axis if BoxModel::AXES.include?(axis) && !axes.include?(axis)
      end
    end

    def write_dimension_offset_axes
      @dimension_offset_axes = [:x] if @dimension_offset_axes.to_a.empty?
      Sketchup.write_default(PREF_SECTION, PREF_DIM_OFFSET_AXES, @dimension_offset_axes.map(&:to_s).join(','))
    end

    def offset_plane_label
      return "chia #{@offset_plane_divisions} phần" if @offset_plane_divisions

      side_label =
        if @offset_plane_count == 2
          '2 mặt'
        elsif @offset_plane_mode == :opposite
          '1 mặt đối diện'
        else
          '1 mặt gần đầu mút'
        end
      "#{Sketchup.format_length(@offset_plane_distance)}, #{side_label}"
    rescue
      "#{@offset_plane_distance.to_f.to_mm.round(2)}mm, #{@offset_plane_count} mặt"
    end

    def dimension_offset_axes_label
      @dimension_offset_axes.to_a.map { |axis| axis.to_s.upcase }.join('+')
    end

    def current_dimension_text(current)
      Sketchup.format_length(current)
    rescue
      current.to_f.to_s
    end

    def parse_view_offset_token(token)
      text = token.to_s.strip
      return nil unless text =~ /\A[+-]?\s*\d/

      negative = text.start_with?('-')
      length_text = text.sub(/\A[+-]/, '').strip
      length = parse_length(length_text)
      return nil unless length && length > 0

      negative ? -length.to_f : length.to_f
    end

    def apply_dimension_view_offset(view, offset)
      return 0 unless offset

      model = Sketchup.active_model
      targets = model.selection.to_a
      return 0 if targets.empty?

      vector = dimension_offset_vector(view, offset)
      return 0 if vector.length <= 1e-6

      model.start_operation('MH Stretch Dimension Axis Offset', true)
      model.active_entities.transform_entities(Geom::Transformation.translation(vector), targets)
      model.commit_operation
      targets.length
    rescue => error
      model.abort_operation rescue nil
      warn "MH::Stretch dimension axis offset failed: #{error.class}: #{error.message}"
      0
    end

    # A leading-space value (for example ` 100`) is an offset rather than a
    # requested final size.  Its direction now follows the same cut-plane
    # rules as numeric stretch, instead of using the camera-facing axis.
    def apply_dimension_space_offset(axis, cuts, offset)
      return 0 unless offset && offset.to_f.abs > StretchOperation::MIN_AMOUNT

      # With two or more cuts there is no single object translation direction:
      # move the two ends equally instead.
      if cuts.length >= 2
        result = commit_dimension_delta(axis, cuts, offset)
        return result[:changed].to_i
      end

      side = cuts.length == 1 ? (cuts.first[:side] || :plus) : :plus
      vector = BoxModel.axis_delta_vector(axis, stretch_amount_for_side(side, offset))
      model = Sketchup.active_model
      targets = model.selection.to_a
      return 0 if targets.empty? || vector.length <= 1e-6

      model.start_operation('MH Stretch Dimension Cut Offset', true)
      model.active_entities.transform_entities(Geom::Transformation.translation(vector), targets)
      model.commit_operation
      targets.length
    rescue => error
      model.abort_operation rescue nil
      warn "MH::Stretch dimension cut offset failed: #{error.class}: #{error.message}"
      0
    end

    def dimension_offset_vector(view, offset)
      axis, sign = dimension_offset_axis_from_view(view)
      BoxModel.axis_delta_vector(axis, offset.to_f * sign)
    rescue
      Geom::Vector3d.new(0, 0, 0)
    end

    def dimension_offset_axis_from_view(view)
      direction = view.camera.direction.clone
      direction.normalize!
      axes = @dimension_offset_axes.to_a.empty? ? [:x] : @dimension_offset_axes
      best =
        axes.map do |axis|
          vector = axis_vector(axis)
          dot = direction.dot(vector)
          [axis, dot, dot.abs]
        end.max_by { |item| item[2] }
      axis = best ? best[0] : :x
      dot = best ? best[1] : 1.0
      [axis, dot.negative? ? -1.0 : 1.0]
    rescue
      [:x, 1.0]
    end

    def input_dimension(axis, view)
      dimension_side = dimension_input_side(axis)
      switch_axis(axis, dimension_side)
      dimension_planes = dimension_cut_planes(axis)
      plane = dimension_planes.first || dimension_stretch_plane(axis, dimension_side)
      if plane && plane[:id]
        @state.set_active(kind: :plane, id: plane[:id])
      else
        @state.set_active(kind: :handle, axis: axis, side: dimension_side)
      end
      view.invalidate
      view.refresh
      current = BoxModel.axis_length(@bb, axis)
      default = ''
      result = UI.inputbox(
        ["Kích thước #{axis.to_s.upcase} (hiện tại #{Sketchup.format_length(current)}):"],
        [default],
        'MH Stretch - Nhập kích thước'
      )
      return unless result

      parsed_input = parse_dimension_input(result[0], current)
      target = parsed_input[:target]
      unless target && target > BoxModel::MIN_LEN
        UI.messagebox('Giá trị kích thước không hợp lệ.')
        return
      end

      delta = target.to_f - current.to_f
      result = commit_dimension_delta(axis, dimension_planes, delta)
      result = correct_dimension_result(result, axis, dimension_planes, target)
      moved_by_view_offset = apply_dimension_space_offset(axis, dimension_planes, parsed_input[:view_offset])
      if moved_by_view_offset.positive?
        result[:ok] = true
        result[:changed] = result[:changed].to_i + moved_by_view_offset
        result[:message] = [
          result[:message].to_s,
          "Move/stretch #{moved_by_view_offset} đối tượng theo mặt cắt trục #{axis.to_s.upcase}."
        ].reject(&:empty?).join(' | ')
      end
      @hover_dimension_axis = nil
      finish_model_change(result, view)
    end

    def start_plane_drag(id, x, y)
      plane = @planes.by_id(id)
      return unless plane

      switch_axis(plane[:axis], plane[:side])
      @state.set_active(kind: :plane, id: id)
      @drag = {
        type: :plane,
        id: id,
        start: [x, y],
        started: false
      }
    end

    def start_grip_drag(axis, side, x, y, view)
      switch_axis(axis, side)
      plane = active_plane_for(axis)
      cuts = @no_plane_mode ? [] : UiAdapter.bbox_handle_cut_planes(axis, side, @planes.planes)
      box_grip = plane.nil? && cuts.empty?

      @state.set_active(plane ? { kind: :plane, id: plane[:id] } : { kind: :handle, axis: axis, side: side })
      origin = BoxModel.face_handles(@bb).find { |key, _| key[:axis] == axis && key[:side] == side }&.last
      origin ||= plane ? BoxModel.plane_center(@bb, plane) : @bb.center
      @drag = {
        type: :grip,
        click_grip: true,
        id: plane && plane[:id],
        axis: axis,
        side: side,
        cuts: cuts,
        box_grip: box_grip,
        start: [x, y],
        origin: origin,
        source_ip: Sketchup::InputPoint.new(origin),
        amount: 0.0,
        last_valid_amount: 0.0,
        started: false
      }
      update_grip_drag(x, y, view)
    end

    def start_plane_side_drag(id, side, x, y, view)
      plane = @planes.by_id(id)
      return unless plane

      switch_axis(plane[:axis], side || :plus)
      @state.set_active(kind: :plane_grip, id: plane[:id], side: @active_side)
      origin = BoxModel.plane_center(@bb, plane)
      @drag = {
        type: :grip,
        id: plane[:id],
        axis: plane[:axis],
        side: @active_side,
        start: [x, y],
        origin: origin,
        source_ip: Sketchup::InputPoint.new(origin),
        amount: 0.0,
        last_valid_amount: 0.0,
        started: false
      }
      update_grip_drag(x, y, view)
    end

    def update_drag(x, y, view)
      case @drag[:type]
      when :grip
        update_grip_drag(x, y, view)
      else
        update_drag_plane(x, y, view)
      end
    end

    def update_drag_plane(x, y, view)
      plane = @planes.by_id(@drag[:id])
      return unless plane

      @no_plane_mode = false
      write_no_plane_mode

      unless @drag[:started]
        dx = x - @drag[:start][0]
        dy = y - @drag[:start][1]
        return if Math.hypot(dx, dy) < DRAG_THRESHOLD_PX * ui_scale
        @drag[:started] = true
        @pinned_plane_id = plane[:id]
      end

      @ip.pick(view, x, y)
      return unless @ip.valid?

      if plane[:kind] == :offset_auto
        @offset_planes_enabled = false
        Sketchup.write_default(PREF_SECTION, PREF_OFFSET_PLANES, false)
        plane[:kind] = :user
        @planes.clear_offset_planes!
        Sketchup.status_text = 'MH Stretch | Đã chuyển offset plane thành plane user.'
      end
      plane[:kind] = :user
      plane[:pos] = BoxModel.clamp_pos(BoxModel.axis_value(@ip.position, plane[:axis]), @bb, plane[:axis])
      @state.set_active(kind: :plane, id: plane[:id])
    end

    def update_grip_drag(x, y, view, force: false)
      plane = @planes.by_id(@drag[:id])
      return unless plane || @drag[:cuts] || @drag[:box_grip]

      unless @drag[:started]
        dx = x - @drag[:start][0]
        dy = y - @drag[:start][1]
        return if !force && Math.hypot(dx, dy) < DRAG_THRESHOLD_PX * ui_scale
        @drag[:started] = true
      end

      amount = axis_drag_amount(
        x,
        y,
        view,
        @drag[:origin],
        @drag[:axis],
        @drag[:side],
        @drag[:start],
        @drag[:last_valid_amount],
        @drag[:source_ip]
      )
      @drag[:amount] = amount
      @drag[:last_valid_amount] = amount
      operation = @drag.merge(plane_id: @drag[:id])
      @preview_segments = preview_operation(operation, amount)
    end

    def commit_or_finish_drag(view)
      if @drag[:type] == :grip
        finish_grip_drag(view)
      else
        @drag = nil
        @drag_ip.clear
      end
    end

    def finish_grip_drag(view)
      started = @drag[:started]
      operation = @drag && @drag.dup
      amount = @drag ? @drag[:amount].to_f : 0.0
      @drag = nil
      @drag_ip.clear
      @preview_segments = []
      return unless started

      finish_model_change(commit_operation(operation, amount), view)
    end

    def preview_operation(operation, amount)
      if operation && operation[:mode] == :between_planes
        return BetweenPlanesAdapter.preview(
          Sketchup.active_model,
          operation[:between_region],
          amount
        )
      end

      return [] if @no_plane_mode && operation && operation[:box_grip]

      plane = operation && @planes.by_id(operation[:id] || operation[:plane_id])
      planes = operation_stretch_planes(operation, plane)
      return [] if planes.empty?

      UiAdapter.preview(
        Sketchup.active_model,
        stretch_bundle(operation, plane, planes),
        amount
      )
    end

    def build_grip_operation(axis, side, plane, cuts: nil)
      {
        axis: axis,
        side: side,
        id: plane && plane[:id],
        plane_id: plane && plane[:id],
        plane: plane,
        cuts: cuts
      }
    end

    def commit_operation(operation, amount)
      if operation && operation[:mode] == :between_planes
        @pending_redraw_components =
          @dc_redraw_enabled ? UiAdapter.dynamic_components_for_redraw(Sketchup.active_model) : []
        return BetweenPlanesAdapter.commit(
          Sketchup.active_model,
          operation[:between_region],
          amount,
          make_unique: false
        )
      end

      if @no_plane_mode && operation && operation[:box_grip]
        return scale_selection_without_cut(operation[:axis], amount, operation[:side])
      end

      plane =
        if operation
          @planes.by_id(operation[:id] || operation[:plane_id]) || operation[:plane]
        end
      planes = operation_stretch_planes(operation, plane)
      return ui_only_result if planes.empty?

      @pending_redraw_components =
        @dc_redraw_enabled ? UiAdapter.dynamic_components_for_redraw(Sketchup.active_model) : []
      UiAdapter.commit(
        Sketchup.active_model,
        stretch_bundle(operation, plane, planes),
        amount,
        make_unique: false
      )
    end

    def ui_only_result
      UiAdapter.ui_only_result
    end

    def dimension_stretch_plane(axis, side)
      return nil unless axis

      pos =
        if side == :minus
          BoxModel.axis_max(@bb, axis)
        else
          BoxModel.axis_min(@bb, axis)
        end
      {
        id: nil,
        axis: axis,
        side: side || :plus,
        pos: pos,
        kind: :dimension,
        usable: true
      }
    end

    def dimension_stretch_planes(axis, side)
      stretch_planes_for(axis, side, dimension_stretch_plane(axis, side))
    end

    # Numeric dimension input is deliberately independent of the active grip.
    # It follows the cut planes currently present on that axis:
    # - no cut: retain the legacy positive-axis behavior;
    # - one cut: use the moving side encoded by that cut;
    # - 2+ cuts: stretch equally from both ends.
    def dimension_cut_planes(axis)
      return [] if @no_plane_mode

      @planes.planes.select do |plane|
        plane && plane[:axis] == axis && plane[:usable] && !plane[:hidden]
      end
    end

    # Keep the side chosen by the user before opening the dimension box.  This
    # is important for a single offset plane: resetting to + here would move a
    # "near the - endpoint" cut to the other end before the value is applied.
    def dimension_input_side(axis)
      return @active_side || :plus if @active_axis == axis

      plane = @planes.first_for_axis(axis)
      return :plus unless plane

      if @offset_planes_enabled && @offset_plane_count == 1 && @offset_plane_mode == :opposite
        opposite_side(plane[:side])
      else
        plane[:side] || :plus
      end
    end

    def commit_dimension_delta(axis, cuts, delta)
      return ui_only_result if delta.to_f.abs <= StretchOperation::MIN_AMOUNT

      if cuts.empty?
        return scale_selection_without_cut(axis, delta)
      end

      if cuts.length == 1
        plane = cuts.first
        side = plane[:side] || :plus
        amount = stretch_amount_for_side(side, delta)
        return commit_operation(build_grip_operation(axis, side, plane, cuts: [plane]), amount)
      end

      minus_plane = cuts.min_by { |plane| plane[:pos].to_f }.merge(side: :minus)
      plus_plane = cuts.max_by { |plane| plane[:pos].to_f }.merge(side: :plus)
      half = delta.to_f / 2.0
      merge_dimension_results(
        commit_operation(build_grip_operation(axis, :minus, minus_plane, cuts: [minus_plane]), -half),
        commit_operation(build_grip_operation(axis, :plus, plus_plane, cuts: [plus_plane]), half)
      )
    end

    # No cut plane means this is a true Scale operation, rather than a vertex
    # stretch. It matches SketchUp's one-axis scale handle: the negative end
    # is the fixed pivot and the positive end receives the requested length.
    def scale_selection_without_cut(axis, delta, side = :plus)
      current = BoxModel.axis_length(@bb, axis).to_f
      signed_delta = side == :minus ? -delta.to_f : delta.to_f
      target = current + signed_delta
      return UiAdapter.ui_result(false, 0, 'Kích thước sau scale không hợp lệ.') if target <= BoxModel::MIN_LEN
      return UiAdapter.ui_result(false, 0, 'Không có chiều dài để scale.') if current <= BoxModel::MIN_LEN

      factor = target / current
      pivot = side == :minus ? BoxModel.axis_max(@bb, axis) : BoxModel.axis_min(@bb, axis)
      origin = axis_point(@bb.center, axis, pivot)
      scales =
        case axis
        when :x then [factor, 1.0, 1.0]
        when :y then [1.0, factor, 1.0]
        else [1.0, 1.0, factor]
        end
      model = Sketchup.active_model
      targets = model.selection.to_a
      return UiAdapter.ui_result(false, 0, 'Selection rỗng.') if targets.empty?

      # Native Scale bypasses commit_operation's normal StretchAdapter path,
      # so capture Dynamic Components here before their transformations change.
      @pending_redraw_components =
        @dc_redraw_enabled ? UiAdapter.dynamic_components_for_redraw(model) : []

      model.start_operation('MH Stretch Native Axis Scale', true)
      transform = Geom::Transformation.scaling(origin, *scales)
      model.active_entities.transform_entities(transform, targets)
      model.commit_operation
      UiAdapter.ui_result(true, targets.length, "Đã scale trục #{axis.to_s.upcase} theo Scale SketchUp.")
    rescue => error
      model.abort_operation rescue nil
      UiAdapter.ui_result(false, 0, "#{error.class}: #{error.message}")
    end

    def stretch_amount_for_side(side, delta)
      side == :minus ? -delta.to_f : delta.to_f
    end

    def merge_dimension_results(*results)
      usable = results.compact
      changed = usable.sum { |item| item[:changed].to_i }
      ok = usable.any? { |item| item[:ok] }
      messages = usable.map { |item| item[:message].to_s }.reject(&:empty?).uniq
      {
        ok: ok,
        changed: changed,
        unique_count: usable.sum { |item| item[:unique_count].to_i },
        message: messages.join(' | ')
      }
    end

    def stretch_planes_for(axis, side, fallback_plane = nil)
      planes = UiAdapter.bbox_handle_cut_planes(axis, side, @planes.planes)
      planes = [fallback_plane].compact if planes.empty?
      planes
    end

    def operation_stretch_planes(operation, fallback_plane)
      return [] unless operation

      side = operation[:side] || fallback_plane && fallback_plane[:side] || :plus
      planes = operation[:cuts].to_a.select { |item| item && item[:axis] == operation[:axis] && item[:usable] }
      planes = [fallback_plane].compact if planes.empty?
      planes.map { |item| item.merge(side: side) }
    end

    def stretch_bundle(operation, fallback_plane, planes)
      side = operation[:side] || fallback_plane && fallback_plane[:side] || :plus
      base = (fallback_plane || planes.first).dup
      base[:axis] = operation[:axis] || base[:axis]
      base[:side] = side
      base[:planes] = planes.map { |plane| plane.merge(side: side) }
      base
    end

    def correct_dimension_result(result, axis, cuts, target)
      return result unless result[:ok]

      refresh_bounds
      actual = BoxModel.axis_length(@bb, axis)
      delta = target.to_f - actual.to_f
      return result if delta.abs <= 0.05.mm

      correction_result = commit_dimension_delta(axis, cuts, delta)
      return result unless correction_result[:ok]

      correction_result[:changed] = result[:changed].to_i + correction_result[:changed].to_i
      correction_result[:unique_count] = result[:unique_count].to_i + correction_result[:unique_count].to_i
      correction_result[:message] =
        "#{correction_result[:message]} Dim corrected #{actual.to_mm.round(2)}mm -> #{target.to_mm.round(2)}mm."
      correction_result
    rescue => error
      warn "MH::Stretch dimension correction failed: #{error.class}: #{error.message}"
      result
    end

    def finish_model_change(result, view)
      redraw_count =
        if result[:ok] && @dc_redraw_enabled
          UiAdapter.schedule_redraw_dynamic_components(@pending_redraw_components) do
            refresh_after_dc_redraw
          end
        else
          0
        end
      unique_count = result[:unique_count].to_i
      suffix = []
      suffix << "unique #{unique_count}" if unique_count.positive?
      suffix << "redraw #{redraw_count} DC" if redraw_count.positive?
      Sketchup.status_text = [result[:message].to_s, suffix.join(', ')].reject(&:empty?).join(' | ')
      @pending_redraw_components = []
      refresh_ui_box(view)
    end

    def refresh_ui_box(view)
      @preview_segments = []
      @creation_preview = nil
      @dimension_hits.clear
      @hover_dimension_axis = nil
      refresh_actual_bounds
      view.invalidate
    rescue => e
      warn "MH::Stretch refresh_ui_box failed: #{e.class}: #{e.message}"
      view.invalidate
    end

    def refresh_after_dc_redraw
      refresh_actual_bounds
      Sketchup.active_model.active_view.invalidate
    rescue => e
      warn "MH::Stretch post-redraw refresh failed: #{e.class}: #{e.message}"
    end

    def refresh_actual_bounds
      refresh_bounds
      return if BoxModel.empty_bounds?(@bb)

      @planes.reclamp!(@bb)
      if @no_plane_mode
        @planes.clear_hidden_defaults!
      elsif @offset_planes_enabled
        @planes.clear_defaults!
        @planes.clear_hidden_defaults!
        sync_offset_planes
      elsif @show_default_plane
        @planes.clear_hidden_defaults!
        @planes.recenter_defaults!(@bb)
        if @active_axis && @planes.first_for_axis(@active_axis).nil?
          ensure_active_axis_plane
        end
      else
        sync_hidden_default_planes
      end
    end

    def sync_hidden_default_planes(axis = @active_axis)
      return [] if BoxModel.empty_bounds?(@bb)
      return [] if @no_plane_mode
      return [] if @show_default_plane
      return [] unless axis

      source_bounds = outer_selection_bounds
      source_bounds = [@bb] if source_bounds.empty?
      @planes.sync_hidden_defaults!(@bb, axis, @active_side, source_bounds)
    end

    def sync_offset_planes(axis = @active_axis, motion_side = @active_side)
      return [] if BoxModel.empty_bounds?(@bb)
      return [] unless @offset_planes_enabled
      return [] unless axis

      if @offset_plane_divisions
        return @planes.sync_division_planes!(
          @bb,
          axis,
          motion_side || :plus,
          @offset_plane_divisions
        )
      end

      @planes.sync_offset_planes!(
        @bb,
        axis,
        offset_plane_side_for(motion_side),
        @offset_plane_distance,
        @offset_plane_count
      )
    end

    def active_offset_plane(axis = @active_axis, side = @active_side)
      planes = sync_offset_planes(axis, side)
      if @offset_plane_divisions
        return side == :minus ? planes.min_by { |plane| plane[:pos].to_f } : planes.max_by { |plane| plane[:pos].to_f }
      end

      planes.find { |plane| plane[:side] == offset_plane_side_for(side) } || planes.first
    end

    def offset_plane_side_for(motion_side)
      side = motion_side || :plus
      @offset_plane_mode == :opposite ? opposite_side(side) : side
    end

    def outer_selection_bounds
      Sketchup.active_model.selection.to_a.each_with_object([]) do |entity, bounds|
        next unless entity
        next if entity.respond_to?(:valid?) && !entity.valid?
        next if entity.respond_to?(:hidden?) && entity.hidden?
        next unless entity.respond_to?(:bounds)

        bb = entity.bounds
        bounds << bb if bb && bb.valid?
      end
    rescue
      []
    end

    def add_creation_preview
      return unless @allow_extra_planes && @creation_preview

      @no_plane_mode = false
      write_no_plane_mode
      plane = @planes.add(
        @creation_preview[:axis],
        @creation_preview[:pos],
        @active_side,
        :user,
        @bb
      )
      @state.set_active(kind: :plane, id: plane[:id])
      @creation_preview = nil
    end

    def refresh_creation_preview(view)
      return @creation_preview = nil unless @allow_extra_planes
      return unless @cursor_xy
      return @creation_preview = nil if @drag || @state.hover[:kind]

      @creation_preview = build_creation_preview(@cursor_xy[0], @cursor_xy[1], view)
    end

    def build_creation_preview(x, y, view)
      axis = @active_axis
      return nil unless axis

      return nil unless BoxModel.usable_axis?(@bb, axis)
      unless point_inside_projected_box?(x, y, view)
        @ip.clear
        return nil
      end

      @ip.pick(view, x, y)
      if @ip.valid?
        pos = BoxModel.clamp_pos(BoxModel.axis_value(@ip.position, axis), @bb, axis)
        return { axis: axis, pos: pos, side: @active_side, kind: :preview, usable: true }
      end

      center = @bb.center
      p_min = axis_point(center, axis, BoxModel.axis_min(@bb, axis))
      p_max = axis_point(center, axis, BoxModel.axis_max(@bb, axis))
      s_min = view.screen_coords(p_min)
      s_max = view.screen_coords(p_max)
      dx = s_max.x - s_min.x
      dy = s_max.y - s_min.y
      len2 = dx * dx + dy * dy
      return nil if len2 <= 1.0

      t = ((x - s_min.x) * dx + (y - s_min.y) * dy).to_f / len2
      t = [[t, 0.0].max, 1.0].min
      min = BoxModel.axis_min(@bb, axis)
      pos = BoxModel.clamp_pos(min + BoxModel.axis_length(@bb, axis) * t, @bb, axis)
      { axis: axis, pos: pos, side: @active_side, kind: :preview, usable: true }
    end

    def point_inside_projected_box?(x, y, view)
      points = BoxModel.corners(@bb).map do |point|
        screen = view.screen_coords(point)
        [screen.x.to_f, screen.y.to_f]
      end
      polygon = convex_hull(points)
      return false if polygon.length < 3

      inside = false
      previous = polygon[-1]
      polygon.each do |current|
        ax, ay = previous
        bx, by = current
        crosses = (by > y) != (ay > y)
        if crosses
          edge_x = (ax - bx) * (y - by).to_f / (ay - by) + bx
          inside = !inside if x < edge_x
        end
        previous = current
      end
      inside
    end

    def convex_hull(points)
      sorted = points.uniq.sort
      return sorted if sorted.length <= 2

      lower = []
      sorted.each do |point|
        lower.pop while lower.length >= 2 && cross_2d(lower[-2], lower[-1], point) <= 0
        lower << point
      end
      upper = []
      sorted.reverse_each do |point|
        upper.pop while upper.length >= 2 && cross_2d(upper[-2], upper[-1], point) <= 0
        upper << point
      end
      lower[0...-1] + upper[0...-1]
    end

    def cross_2d(origin, a, b)
      (a[0] - origin[0]) * (b[1] - origin[1]) -
        (a[1] - origin[1]) * (b[0] - origin[0])
    end

    def axis_point(point, axis, value)
      case axis
      when :x then Geom::Point3d.new(value, point.y, point.z)
      when :y then Geom::Point3d.new(point.x, value, point.z)
      else Geom::Point3d.new(point.x, point.y, value)
      end
    end

    def delete_active_plane
      deleted = @planes.delete(@state.active_plane_id)
      return unless deleted

      clear_pinned_plane if deleted[:id] == @pinned_plane_id

      fallback = @planes.planes.last
      fallback ||= @planes.ensure_axis_default(@bb, @active_axis, @active_side) if @show_default_plane && @active_axis
      @state.set_active(fallback ? { kind: :plane, id: fallback[:id] } : nil)
    end

    def active_plane_for(axis)
      return nil if @no_plane_mode

      active = @planes.by_id(@state.active_plane_id)
      return active if active && active[:axis] == axis
      return active_offset_plane(axis, @active_side) if @offset_planes_enabled

      existing = @planes.first_for_axis(axis)
      return existing if existing

      if @show_default_plane
        @planes.ensure_axis_default(@bb, axis, @active_side)
      else
        sync_hidden_default_planes(axis)
        @planes.first_for_axis(axis)
      end
    end

    def axis_drag_amount(x, y, view, origin, axis, side = nil, start_xy = nil, fallback_amount = nil, source_ip = nil)
      vector = axis_vector(axis)
      drag_ip = pick_drag_input_point(view, x, y, source_ip)
      snap_amount = drag_snap_amount(drag_ip, view, x, y, origin, vector)
      return snap_amount if snap_amount

      screen_amount = screen_axis_drag_amount(x, y, view, origin, vector, side, start_xy)
      plane_amount = view_plane_axis_drag_amount(x, y, view, origin, vector, start_xy)
      base_amount = balanced_axis_drag_amount(view, screen_amount, plane_amount)
      return base_amount if base_amount

      visual_amount = visual_grip_drag_amount(x, y, view, origin, axis, side, start_xy)
      return visual_amount if visual_amount

      ray = view.pickray(x, y)
      fallback_available = fallback_amount && !fallback_amount.to_f.nan?
      return fallback_amount.to_f if fallback_available && !ray
      return 0.0 unless ray

      closest = Geom.closest_points(ray, [origin, vector])
      point = closest && closest[1]
      unless point
        return fallback_amount.to_f if fallback_available
        return 0.0
      end

      (point - origin).dot(vector)
    rescue
      fallback_amount.to_f
    end

    def visual_grip_drag_amount(x, y, view, origin, axis, side, start_xy)
      return nil unless start_xy && origin && @bb && !BoxModel.empty_bounds?(@bb)

      center = @bb.center
      center_screen = view.screen_coords(center)
      origin_screen = view.screen_coords(origin)
      vx = origin_screen.x - center_screen.x
      vy = origin_screen.y - center_screen.y
      len = Math.hypot(vx, vy)
      return nil if len < 8 * ui_scale

      dx = x - start_xy[0]
      dy = y - start_xy[1]
      outward_pixels = (dx * vx + dy * vy).to_f / len
      amount = view.pixels_to_model(outward_pixels.abs, origin).to_f
      amount = -amount if outward_pixels.negative?
      side == :minus ? -amount : amount
    rescue
      nil
    end

    def pick_drag_input_point(view, x, y, source_ip)
      @drag_ip.clear
      if source_ip && source_ip.valid?
        @drag_ip.pick(view, x, y, source_ip)
      else
        @drag_ip.pick(view, x, y)
      end
      @drag_ip
    rescue ArgumentError
      @drag_ip.pick(view, x, y)
      @drag_ip
    rescue
      @drag_ip.clear
      @drag_ip
    end

    def balanced_axis_drag_amount(view, screen_amount, plane_amount)
      if parallel_projection?(view)
        return screen_amount if screen_amount
        return plane_amount
      end

      plane_amount || screen_amount
    rescue
      plane_amount || screen_amount
    end

    def parallel_projection?(view)
      camera = view.camera
      camera.respond_to?(:perspective?) && !camera.perspective?
    rescue
      false
    end

    def view_plane_axis_drag_amount(x, y, view, origin, vector, start_xy)
      return nil unless start_xy

      camera_dir = view.camera.direction
      normal = vector.cross(camera_dir)
      return nil if normal.length <= 1e-6

      ray = view.pickray(x, y)
      point = Geom.intersect_line_plane(ray, [origin, normal])
      return nil unless point

      (point - origin).dot(vector)
    rescue
      nil
    end

    def screen_axis_drag_amount(x, y, view, origin, vector, side, start_xy)
      return nil unless start_xy

      model_len = view.pixels_to_model(100, origin)
      return nil unless model_len && model_len > 0

      p0 = view.screen_coords(origin)
      p1 = view.screen_coords(origin.offset(vector, model_len))
      sx = p1.x - p0.x
      sy = p1.y - p0.y
      len2 = sx * sx + sy * sy
      return depth_axis_drag_amount(y, model_len, side, start_xy) if len2 < (6 * ui_scale) ** 2

      dx = x - start_xy[0]
      dy = y - start_xy[1]
      ((dx * sx + dy * sy).to_f / len2) * model_len
    rescue
      nil
    end

    def depth_axis_drag_amount(y, model_len, side, start_xy)
      sign = side == :minus ? -1.0 : 1.0
      dy = y - start_xy[1]
      (-dy.to_f / 100.0) * model_len * sign
    rescue
      nil
    end

    def strong_input_point?(ip)
      return false unless ip && ip.valid?

      dof = ip.degrees_of_freedom rescue nil
      return true if dof && dof <= 2
      return true if (ip.vertex rescue nil)
      return true if (ip.edge rescue nil)

      false
    end

    def drag_snap_amount(ip, view, x, y, origin, vector)
      return nil unless usable_drag_input_point?(ip, view, x, y)

      amount = (ip.position - origin).dot(vector).to_f
      return nil if amount.nan?

      amount
    rescue
      nil
    end

    def usable_drag_input_point?(ip, view, x, y)
      return false unless ip && ip.valid?
      return false unless input_point_screen_close?(ip, view, x, y)

      strong_input_point?(ip)
    rescue
      false
    end

    def input_point_screen_close?(ip, view, x, y)
      point = ip.position
      return false unless point

      screen = view.screen_coords(point)
      tolerance = input_point_screen_tolerance(ip)
      Math.hypot(x - screen.x, y - screen.y) <= tolerance * ui_scale
    rescue
      false
    end

    def input_point_screen_tolerance(ip)
      return 18 if (ip.vertex rescue nil)
      return 15 if (ip.edge rescue nil)

      10
    end

    def axis_vector(axis)
      case axis
      when :x then Geom::Vector3d.new(1, 0, 0)
      when :y then Geom::Vector3d.new(0, 1, 0)
      else Geom::Vector3d.new(0, 0, 1)
      end
    end

    def cycle_axis
      axes = BoxModel::AXES
      current_index = axes.index(@active_axis)
      idx = current_index ? current_index : -1
      switch_axis(axes[(idx + 1) % axes.length], :plus)
      @state.set_active(kind: :handle, axis: @active_axis, side: @active_side)
    end

    def input_dimension_from_key(key, view)
      axis = DIMENSION_AXIS_KEYS[key]
      return unless axis

      refresh_bounds
      return if BoxModel.empty_bounds?(@bb)

      input_dimension(axis, view)
    end

    def switch_axis(axis, side = :plus)
      @planes.retain_axis!(axis) if axis != @active_axis
      @active_axis = axis
      @active_side = side || :plus
      @creation_preview = nil
      ensure_active_axis_plane
    end

    def ensure_active_axis_plane
      return nil unless @active_axis

      if @no_plane_mode
        @planes.clear_hidden_defaults!
        @state.set_active(nil)
        return nil
      end

      if @offset_planes_enabled
        @planes.clear_defaults!
        @planes.clear_hidden_defaults!
        plane = active_offset_plane(@active_axis, @active_side)
        @state.set_active(plane ? { kind: :plane, id: plane[:id] } : nil)
        return plane
      end

      unless @show_default_plane
        sync_hidden_default_planes
        @state.set_active(nil) if @planes.planes.empty?
        return nil
      end

      @planes.clear_hidden_defaults!
      plane = @planes.ensure_axis_default(@bb, @active_axis, @active_side)
      @state.set_active(kind: :plane, id: plane[:id])
      plane
    end

    def activate_hovered_axis(hit)
      axis = hit[:axis]
      side = hit[:side] || :plus
      switch_axis(axis, side)
      @state.set_active(kind: :handle, axis: axis, side: side)
    end

    def pinned_plane?
      @pinned_plane_id && @planes.by_id(@pinned_plane_id)
    end

    def clear_pinned_plane
      @pinned_plane_id = nil
    end

    def cancel_or_exit(view)
      if @target_mode
        clear_target
      elsif @drag
        @drag = nil
        @drag_ip.clear
        @preview_segments = []
      else
        Sketchup.active_model.select_tool(nil)
      end
      update_status
      view.invalidate
    end

    def update_status
      message =
        if @target_mode
          'MH Stretch | Rê tới target | Click để stretch.'
        elsif @drag && @drag[:click_grip]
          'MH Stretch | Di chuột kéo grip | Click kết thúc.'
        elsif hover_preview?
          'MH Stretch | Đang preview dim object | Click object để chọn UI box.'
        elsif selection_empty?
          'MH Stretch | Hover object để xem dim | Click object để chọn UI box.'
        else
          plane_mode =
            if @offset_planes_enabled
              "Offset plane: #{offset_plane_label}"
            else
              @allow_extra_planes ? 'Thêm plane: bật' : 'Thêm plane: tắt'
            end
          "MH Stretch | Hover grip/plane để stretch | #{plane_mode}."
        end
      Sketchup.status_text = message
    rescue
      nil
    end

    def ui_scale
      UI.scale_factor
    rescue
      1.0
    end

    def ctrl_down?(flags)
      mask = defined?(MK_CONTROL) ? MK_CONTROL : 8
      (flags.to_i & mask.to_i) != 0
    rescue
      false
    end
  end
end




