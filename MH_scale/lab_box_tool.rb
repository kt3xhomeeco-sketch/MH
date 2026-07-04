# encoding: UTF-8

module MH::Scale
  class BoxTool
    DRAG_THRESHOLD_PX = 3
    AXIS_KEYS = { 39 => :x, 37 => :y, 38 => :z }.freeze
    PREF_SECTION = 'MHScale'.freeze
    PREF_PLANE_STRETCH_GRIPS = 'show_plane_stretch_grips'.freeze
    PREF_DEFAULT_PLANE = 'show_default_plane'.freeze
    PREF_ALLOW_EXTRA_PLANES = 'allow_extra_planes'.freeze
    PREF_DC_REDRAW = 'dc_redraw_enabled'.freeze
    PREF_DC_FIX = 'dc_fix_enabled'.freeze
    PREF_STRETCH_PRO = 'stretch_pro'.freeze

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
      @dimension_hits = {}
      @hover_dimension_axis = nil
      @target_mode = false
      @target_source_point = nil
      @target_point = nil
      @target_operation = nil
      @show_plane_stretch_grips =
        Sketchup.read_default(PREF_SECTION, PREF_PLANE_STRETCH_GRIPS, true) != false
      @show_default_plane =
        Sketchup.read_default(PREF_SECTION, PREF_DEFAULT_PLANE, true) != false
      @allow_extra_planes =
        Sketchup.read_default(PREF_SECTION, PREF_ALLOW_EXTRA_PLANES, true) != false
      @dc_redraw_enabled =
        Sketchup.read_default(PREF_SECTION, PREF_DC_REDRAW, true) != false
      @dc_fix_enabled =
        Sketchup.read_default(PREF_SECTION, PREF_DC_FIX, false) == true
      @stretch_pro =
        Sketchup.read_default(PREF_SECTION, PREF_STRETCH_PRO, false) == true
      @pro_context = nil
      @dc_axis = nil
      @dc_origin_states = nil
      @dc_stretch_context = nil
      @dc_fix_after_stretch = true
      @dc_redraw_after_stretch = true
    end

    def activate
      refresh_bounds
      if BoxModel.empty_bounds?(@bb)
        Sketchup.status_text = 'MH Scale | Hover object để xem dim | Click object để chọn scale.'
      else
        Sketchup.status_text = 'MH Scale | Chọn grip trục để tạo mặt cắt.'
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

    def onMouseMove(_flags, x, y, view)
      update_hover_target(x, y, view) if selection_empty? && !@drag && !@target_mode
      refresh_bounds
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
              @show_plane_stretch_grips
            ).hit(x, y)
          end
        activate_hovered_axis(hit) if hit && hit[:kind] == :handle
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

      if @drag && @drag[:type] == :stretch && @drag[:click_scale]
        update_drag_stretch(x, y, view, force: true)
        commit_stretch(view)
        update_status
        view.invalidate
        return
      end

      if (axis = dimension_axis_at(x, y))
        input_dimension(axis, view)
        return
      end

      case @state.hover[:kind]
      when :plane_stretch
        start_plane_stretch_drag(@state.hover[:id], @state.hover[:side], x, y, view)
      when :plane
        start_plane_drag(@state.hover[:id], x, y)
      when :handle
        start_stretch_drag(@state.hover[:axis], @state.hover[:side], x, y, view)
      else
        add_creation_preview
      end

      update_status
      view.invalidate
    end

    def onLButtonUp(_flags, _x, _y, view)
      if @drag
        return if @drag[:click_scale]

        commit_or_finish_drag(view)
        update_status
        view.invalidate
      end
    end

    def onKeyDown(key, _repeat, _flags, view)
      case key
      when 9
        cycle_axis
      when 27
        cancel_or_exit(view)
        return
      when 46
        delete_active_plane
      else
        set_axis_from_key(key)
      end
      refresh_creation_preview(view)
      update_status
      view.invalidate
    end

    def getMenu(menu)
      settings = menu.add_submenu('Cài đặt')
      grip_item = settings.add_item('Hiện grip +/- của plane') do
        toggle_plane_stretch_grips
      end
      settings.set_validation_proc(grip_item) do
        @show_plane_stretch_grips ? MF_CHECKED : MF_UNCHECKED
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
      redraw_item = settings.add_item('Tự redraw DC sau scale') do
        toggle_dc_redraw
      end
      settings.set_validation_proc(redraw_item) do
        @dc_redraw_enabled ? MF_CHECKED : MF_UNCHECKED
      end
      fix_item = settings.add_item('Fix') do
        toggle_dc_fix
      end
      settings.set_validation_proc(fix_item) do
        @dc_fix_enabled ? MF_CHECKED : MF_UNCHECKED
      end
      pro_item = settings.add_item('Stretch Pro') do
        toggle_stretch_pro
      end
      settings.set_validation_proc(pro_item) do
        @stretch_pro ? MF_CHECKED : MF_UNCHECKED
      end
      menu.add_separator
      menu.add_item('Xóa active plane') { delete_active_plane; Sketchup.active_model.active_view.invalidate }
      menu.add_item('Clear user planes') { @planes.clear_user!; Sketchup.active_model.active_view.invalidate }
      menu.add_separator
      menu.add_item('Thoát MH Scale') { Sketchup.active_model.select_tool(nil) }
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
        @show_plane_stretch_grips,
        @dimension_hits,
        @hover_dimension_axis
      ).draw
      @ip.draw(view) if @ip.valid?
      @drag_ip.draw(view) if stretch_dragging? && @drag_ip.valid?
      draw_target(view)
      @target_ip.draw(view) if @target_mode && @target_ip.valid?
    end

    def getExtents
      refresh_bounds
      bb = Geom::BoundingBox.new
      return bb if BoxModel.empty_bounds?(@bb)

      bb.add(@bb.min, @bb.max)
      @planes.planes.each do |plane|
        next unless plane[:usable]

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
        @bb = hover_target_bounds
      else
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
      @hover_target = nil
      @active_axis = nil
      @active_side = :plus
      @planes.planes.clear
      @state.set_active(nil)
      @state.set_hover(nil)
      @creation_preview = nil
      @dimension_hits.clear
      @hover_dimension_axis = nil
      refresh_actual_bounds
      view.tooltip = nil
      Sketchup.status_text = 'MH Scale | Đã chọn object. Hover grip để chọn trục.'
    rescue => e
      warn "MHScale select hover target failed: #{e.class}: #{e.message}"
    end

    def toggle_plane_stretch_grips
      @show_plane_stretch_grips = !@show_plane_stretch_grips
      Sketchup.write_default(
        PREF_SECTION,
        PREF_PLANE_STRETCH_GRIPS,
        @show_plane_stretch_grips
      )
      if !@show_plane_stretch_grips && @state.hover[:kind] == :plane_stretch
        @state.set_hover(nil)
      end
      Sketchup.active_model.active_view.invalidate
    end

    def toggle_default_plane
      @show_default_plane = !@show_default_plane
      Sketchup.write_default(
        PREF_SECTION,
        PREF_DEFAULT_PLANE,
        @show_default_plane
      )

      if @show_default_plane
        ensure_active_axis_plane if @active_axis
      else
        @planes.planes.clear
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
        @dc_redraw_enabled ? 'MH Scale | Redraw DC: bật' : 'MH Scale | Redraw DC: tắt'
    end

    def toggle_dc_fix
      @dc_fix_enabled = !@dc_fix_enabled
      Sketchup.write_default(
        PREF_SECTION,
        PREF_DC_FIX,
        @dc_fix_enabled
      )
      Sketchup.status_text =
        @dc_fix_enabled ? 'MH Scale | Fix: bật' : 'MH Scale | Fix: tắt'
    end

    def toggle_stretch_pro
      @stretch_pro = !@stretch_pro
      Sketchup.write_default(PREF_SECTION, PREF_STRETCH_PRO, @stretch_pro)
      Sketchup.status_text =
        @stretch_pro ? 'MH Scale | Stretch Pro: bật' : 'MH Scale | Stretch Pro: tắt'
    end

    def dimension_preview
      return nil unless @drag && @drag[:type] == :stretch && @drag[:started]

      {
        axis: @drag[:axis],
        side: @drag[:side],
        amount: @drag[:amount]
      }
    end

    def stretch_dragging?
      @drag && @drag[:type] == :stretch
    end

    def arm_target_mode(x, y, view)
      handle_hit = HitTest.new(
        view,
        @bb,
        @planes.planes,
        @show_plane_stretch_grips
      ).hit_handle(x, y)

      axis = handle_hit ? handle_hit[:axis] : @active_axis
      unless axis
        Sketchup.status_text = 'MH Scale | Chọn grip trục trước khi dùng target.'
        return
      end

      @target_ip.pick(view, x, y)
      picked = @target_ip.valid? ? @target_ip.position : nil
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
        Sketchup.status_text = 'MH Scale | Ctrl+click một điểm hợp lệ để chọn điểm kéo.'
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
      plane = stretch_plane_for(axis)
      cuts = StretchAdapter.bbox_handle_cut_planes(axis, side, @planes.planes)
      @target_operation = {
        axis: axis,
        side: side,
        plane_id: plane && plane[:id],
        cuts: cuts,
        box_scale: plane.nil? && cuts.empty?
      }
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
          "MH Scale | Target vuông góc #{axis.to_s.upcase}#{side == :minus ? '-' : '+'}. Click để hoàn thành."
        else
          "MH Scale | Đã chọn điểm kéo #{axis.to_s.upcase}#{side == :minus ? '-' : '+'}. Click điểm target."
        end
    end

    def update_target_preview(x, y, view)
      return unless @target_operation && @target_source_point

      @target_ip.pick(view, x, y)
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
        "MH Scale | Target Δ #{Sketchup.format_length(amount)} | Click để hoàn thành."
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
      @target_ip.clear
      @preview_segments = []
    end

    def target_point_from_mouse(x, y, view, source, axis)
      if @target_ip.valid?
        return target_point_from_world_point(@target_ip.position, source, axis)
      end

      ray = view.pickray(x, y)
      return nil unless ray

      closest = Geom.closest_points(ray, [source, axis_vector(axis)])
      closest && closest[1]
    rescue
      nil
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
        length = SmartScale::Core.parse_length(match[2])
        return nil unless length

        return match[1] == '-' ? current - length : current + length
      end

      if (match = input.match(%r{\A([*/])\s*([0-9]+(?:[.,][0-9]+)?)\z}))
        factor = match[2].tr(',', '.').to_f
        return nil if factor <= 0

        return match[1] == '*' ? current * factor : current / factor
      end

      SmartScale::Core.parse_length(input)
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
      length = SmartScale::Core.parse_length(length_text)
      return nil unless length && length > 0

      negative ? -length.to_f : length.to_f
    end

    def apply_dimension_view_offset(view, offset)
      return unless offset

      model = Sketchup.active_model
      targets = model.selection.to_a
      return if targets.empty?

      vector = dominant_view_offset_vector(view, offset)
      return if vector.length <= 1e-6

      model.start_operation('MH Scale Dimension View Offset', true)
      model.active_entities.transform_entities(Geom::Transformation.translation(vector), targets)
      model.commit_operation
    rescue => e
      model.abort_operation rescue nil
      warn "MHScale dimension view offset failed: #{e.class}: #{e.message}"
    end

    def dominant_view_offset_vector(_view, offset)
      Geom::Vector3d.new(0, offset.to_f, 0)
    rescue
      Geom::Vector3d.new(0, 0, 0)
    end

    def input_dimension(axis, view)
      switch_axis(axis, @active_side)
      plane = stretch_plane_for(axis)
      if plane
        @state.set_active(kind: :plane, id: plane[:id])
      else
        @state.set_active(kind: :handle, axis: axis, side: @active_side)
      end
      view.invalidate
      view.refresh
      current = BoxModel.axis_length(@bb, axis)
      default = ''
      result = UI.inputbox(
        ["Kích thước #{axis.to_s.upcase} (hiện tại #{Sketchup.format_length(current)}):"],
        [default],
        'MH Scale - Nhập kích thước'
      )
      return unless result

      parsed_input = parse_dimension_input(result[0], current)
      target = parsed_input[:target]
      unless target && target > BoxModel::MIN_LEN
        UI.messagebox('Giá trị kích thước không hợp lệ.')
        return
      end

      view_offset = parsed_input[:view_offset]
      amount = @active_side == :minus ? current - target : target - current
      cuts = plane ? StretchAdapter.bbox_handle_cut_planes(axis, @active_side, @planes.planes) : []
      operation = {
        axis: axis,
        side: @active_side,
        plane_id: plane && plane[:id],
        cuts: cuts,
        box_scale: plane.nil?
      }
      result = commit_operation(operation, amount)
      apply_dimension_view_offset(view, view_offset) if result[:ok]
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

    def start_stretch_drag(axis, side, x, y, view)
      switch_axis(axis, side)
      plane = stretch_plane_for(axis)
      cuts = StretchAdapter.bbox_handle_cut_planes(axis, side, @planes.planes)
      box_scale = plane.nil? && cuts.empty?

      @state.set_active(plane ? { kind: :plane, id: plane[:id] } : { kind: :handle, axis: axis, side: side })
      origin = BoxModel.face_handles(@bb).find { |key, _| key[:axis] == axis && key[:side] == side }&.last
      origin ||= plane ? BoxModel.plane_center(@bb, plane) : @bb.center
      @drag = {
        type: :stretch,
        click_scale: true,
        id: plane && plane[:id],
        axis: axis,
        side: side,
        cuts: cuts,
        box_scale: box_scale,
        start: [x, y],
        origin: origin,
        source_ip: Sketchup::InputPoint.new(origin),
        amount: 0.0,
        last_valid_amount: 0.0,
        started: false
      }
      update_drag_stretch(x, y, view)
    end

    def start_plane_stretch_drag(id, side, x, y, view)
      plane = @planes.by_id(id)
      return unless plane

      switch_axis(plane[:axis], side || :plus)
      @state.set_active(kind: :plane_stretch, id: plane[:id], side: @active_side)
      origin = BoxModel.plane_center(@bb, plane)
      @drag = {
        type: :stretch,
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
      update_drag_stretch(x, y, view)
    end

    def update_drag(x, y, view)
      case @drag[:type]
      when :stretch
        update_drag_stretch(x, y, view)
      else
        update_drag_plane(x, y, view)
      end
    end

    def update_drag_plane(x, y, view)
      plane = @planes.by_id(@drag[:id])
      return unless plane

      unless @drag[:started]
        dx = x - @drag[:start][0]
        dy = y - @drag[:start][1]
        return if Math.hypot(dx, dy) < DRAG_THRESHOLD_PX * ui_scale
        @drag[:started] = true
      end

      @ip.pick(view, x, y)
      return unless @ip.valid?

      plane[:kind] = :user
      plane[:pos] = BoxModel.clamp_pos(BoxModel.axis_value(@ip.position, plane[:axis]), @bb, plane[:axis])
      @state.set_active(kind: :plane, id: plane[:id])
    end

    def update_drag_stretch(x, y, view, force: false)
      plane = @planes.by_id(@drag[:id])
      return unless plane || @drag[:cuts] || @drag[:box_scale]

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
      if @drag[:type] == :stretch
        commit_stretch(view)
      else
        @drag = nil
        @drag_ip.clear
      end
    end

    def commit_stretch(view)
      plane = @planes.by_id(@drag[:id])
      amount = @drag[:amount].to_f
      started = @drag[:started]
      side = @drag[:side]
      cuts = @drag[:cuts]
      box_scale = @drag[:box_scale]
      axis = @drag[:axis]
      @drag = nil
      @drag_ip.clear
      @preview_segments = []
      return unless started && (box_scale || plane || (cuts && !cuts.empty?))

      operation = {
        axis: axis,
        side: side,
        plane_id: plane && plane[:id],
        cuts: cuts,
        box_scale: box_scale
      }
      finish_model_change(commit_operation(operation, amount), view)
    end

    def preview_operation(operation, amount)
      if operation[:box_scale]
        return StretchAdapter.preview_box_scale(
          @bb,
          operation[:axis],
          operation[:side],
          amount
        )
      end
      if operation[:cuts] && !operation[:cuts].empty?
        return StretchAdapter.preview_multi_cut(
          Sketchup.active_model,
          operation[:cuts],
          operation[:axis],
          operation[:side],
          amount
        )
      end
      range_plane = range_stretch_plane(operation)
      if range_plane
        return StretchAdapter.preview(
          Sketchup.active_model,
          range_plane.merge(side: operation[:side]),
          amount,
          @planes.planes,
          @bb
        )
      end

      plane = @planes.by_id(operation[:plane_id])
      return [] unless plane

      StretchAdapter.preview(
        Sketchup.active_model,
        plane.merge(side: operation[:side]),
        amount,
        @planes.planes,
        @bb
      )
    end

    def commit_operation(operation, amount)
      @pro_context = nil
      @dc_axis = operation[:axis]
      if operation[:box_scale]
        @dc_stretch_context = nil
        @dc_fix_after_stretch = false
        @dc_redraw_after_stretch = false
        @dc_origin_states = nil
        return StretchAdapter.commit_box_scale(
          Sketchup.active_model,
          @bb,
          operation[:axis],
          operation[:side],
          amount
        )
      end

      range_stretch = range_stretch_operation?(operation)
      manual_geometry = range_stretch || multi_cut_operation?(operation)
      @dc_stretch_context = build_dc_stretch_context(operation, amount)
      @dc_fix_after_stretch = !@dc_stretch_context.nil?
      @dc_redraw_after_stretch = !manual_geometry && @dc_stretch_context.nil?
      DcLengths.make_selection_unique(Sketchup.active_model)
      DcLengths.bake_scaled_selection_for_stretch(Sketchup.active_model)
      @dc_origin_states = DcLengths.capture_origin_states(
        Sketchup.active_model,
        @dc_axis
      )
      if @stretch_pro && stretch_pro_eligible?(operation)
        plane = @planes.by_id(operation[:plane_id])
        if plane
          @pro_context = {
            axis: operation[:axis] || plane[:axis],
            side: operation[:side] || plane[:side] || :plus,
            amount: amount.to_f,
            boundary: plane[:pos].to_f
          }
        end
      end
      if operation[:cuts] && !operation[:cuts].empty?
        return StretchAdapter.commit_multi_cut(
          Sketchup.active_model,
          operation[:cuts],
          operation[:axis],
          operation[:side],
          amount
        )
      end
      range_plane = range_stretch_plane(operation)
      if range_plane
        return StretchAdapter.commit(
          Sketchup.active_model,
          range_plane.merge(side: operation[:side]),
          amount,
          @planes.planes,
          @bb
        )
      end

      plane = @planes.by_id(operation[:plane_id])
      return { ok: false, message: 'Không có plane hợp lệ.' } unless plane

      StretchAdapter.commit(
        Sketchup.active_model,
        plane.merge(side: operation[:side]),
        amount,
        @planes.planes,
        @bb
      )
    end

    def finish_model_change(result, view)
      Sketchup.status_text = result[:message].to_s
      dc_result = nil
      if result[:ok] && @pro_context
        ctx = @pro_context
        pro_result = StretchPro.finalize(
          Sketchup.active_model,
          ctx[:axis],
          ctx[:side],
          ctx[:amount],
          ctx[:boundary],
          @dc_redraw_enabled,
          @dc_origin_states
        )
        dc_result = pro_result && pro_result[:dc]
      elsif result[:ok] && @dc_redraw_enabled && @dc_redraw_after_stretch
        dc_result = StretchAdapter.prepare_and_redraw_dc(
          Sketchup.active_model,
          axis: @dc_axis,
          origin_states: @dc_origin_states
        )
      end
      schedule_dc_fix_after_stretch if result[:ok] && @dc_fix_after_stretch
      show_dc_warning(dc_result)
      @pro_context = nil
      @dc_axis = nil
      @dc_origin_states = nil
      @dc_stretch_context = nil
      @dc_fix_after_stretch = true
      @dc_redraw_after_stretch = true
      redraw_actual_box(view)
    end

    def schedule_dc_fix_after_stretch
      return unless @dc_axis
      return unless @dc_fix_enabled

      DcLengths.schedule_fix_selection(
        Sketchup.active_model,
        axis: @dc_axis,
        delay: @dc_redraw_enabled ? 0.22 : 0.05,
        stretch_context: @dc_stretch_context,
        redraw: @dc_redraw_enabled
      )
    rescue => e
      warn "MHScale schedule_dc_fix_after_stretch failed: #{e.class}: #{e.message}"
    end

    def build_dc_stretch_context(operation, amount)
      return nil unless operation
      return nil if operation[:box_scale]

      axis = operation[:axis]
      side = operation[:side] || :plus
      return nil unless axis

      cuts = Array(operation[:cuts])
      unless cuts.empty?
        return {
          mode: :multi_cut,
          axis: axis,
          side: side,
          cuts: cuts.map { |cut| { axis: cut[:axis], pos: cut[:pos].to_f } },
          step: amount.to_f / cuts.length
        }
      end

      range_plane = range_stretch_plane(operation)
      if range_plane
        range = StretchAdapter.moving_range(
          range_plane.merge(side: side),
          @planes.planes,
          @bb
        )
        return nil unless range

        return range.merge(mode: :range, amount: amount.to_f)
      end

      plane = @planes.by_id(operation[:plane_id])
      return nil unless plane

      {
        mode: :plane,
        axis: axis,
        side: side,
        pos: plane[:pos].to_f,
        amount: amount.to_f
      }
    rescue
      nil
    end

    def stretch_pro_eligible?(operation)
      return false
      return false if operation[:box_scale]

      plane = @planes.by_id(operation[:plane_id])
      return false unless plane

      cuts = Array(operation[:cuts])
      return false if cuts.length > 1

      range = StretchAdapter.moving_range(
        plane.merge(side: operation[:side] || plane[:side]),
        @planes.planes,
        @bb
      )
      range.nil?
    end

    def range_stretch_operation?(operation)
      return false if operation[:box_scale]
      return false if operation[:cuts] && !operation[:cuts].empty?

      !!range_stretch_plane(operation)
    rescue
      false
    end

    def range_stretch_plane(operation)
      return nil if operation[:cuts] && !operation[:cuts].empty?

      plane = @planes.by_id(operation[:plane_id])
      return nil unless plane

      side = operation[:side] || plane[:side]
      !!StretchAdapter.moving_range(
        plane.merge(side: side),
        @planes.planes,
        @bb
      ) ? plane : nil
    rescue
      nil
    end

    def multi_cut_operation?(operation)
      Array(operation[:cuts]).length > 1
    end

    def show_dc_warning(dc_result)
      return unless dc_result

      formula_count = dc_result[:formula_locked_nodes].to_i
      return if formula_count <= 0

      Sketchup.status_text =
        "MH Scale | Giữ geometry, bỏ redraw #{formula_count} DC có công thức."
    end

    def redraw_actual_box(view)
      @preview_segments = []
      @creation_preview = nil
      @dimension_hits.clear
      @hover_dimension_axis = nil
      refresh_actual_bounds
      view.invalidate
      view.refresh

      UI.start_timer(0.12, false) do
        refresh_actual_bounds
        active_view = Sketchup.active_model.active_view
        active_view.invalidate
        active_view.refresh
      end
    rescue => e
      warn "MHScale redraw_actual_box failed: #{e.class}: #{e.message}"
      view.invalidate
    end

    def refresh_actual_bounds
      refresh_bounds
      return if BoxModel.empty_bounds?(@bb)

      @planes.reclamp!(@bb)
      @planes.recenter_defaults!(@bb) if @show_default_plane
      if @show_default_plane && @active_axis && @planes.first_for_axis(@active_axis).nil?
        ensure_active_axis_plane
      end
    end

    def add_creation_preview
      return unless @allow_extra_planes && @creation_preview

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

      fallback = @planes.planes.last
      fallback ||= @planes.ensure_axis_default(@bb, @active_axis, @active_side) if @show_default_plane && @active_axis
      @state.set_active(fallback ? { kind: :plane, id: fallback[:id] } : nil)
    end

    def stretch_plane_for(axis)
      active = @planes.by_id(@state.active_plane_id)
      return active if active && active[:axis] == axis

      existing = @planes.first_for_axis(axis)
      return existing if existing
      return nil unless @show_default_plane

      @planes.ensure_axis_default(@bb, axis, @active_side)
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

    def set_axis_from_key(key)
      axis = AXIS_KEYS[key]
      return unless axis

      switch_axis(axis, :plus)
      @state.set_active(kind: :handle, axis: @active_axis, side: @active_side)
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

      unless @show_default_plane
        @state.set_active(nil) if @planes.planes.empty?
        return nil
      end

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
          'MH Scale | Rê tới target | Click để hoàn thành | Ctrl+click để chọn lại điểm kéo.'
        elsif @drag && @drag[:click_scale]
          'MH Scale | Di chuột để scale | Click lần hai để hoàn thành | Esc để hủy.'
        elsif hover_preview?
          'MH Scale | Đang preview dim object | Click object để chọn scale.'
        elsif selection_empty?
          'MH Scale | Hover object để xem dim | Click object để chọn scale.'
        else
          plane_mode = @allow_extra_planes ? 'Thêm plane: bật' : 'Thêm plane: tắt'
          "MH Scale | Hover grip: chọn trục | Click grip: bắt đầu scale | #{plane_mode}."
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

