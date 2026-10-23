class MH::Panel::CatVan
  VK_TAB = 9
  VK_SHIFT = 16
  AXES = [
    [:x, 'YOZ', Geom::Vector3d.new(1, 0, 0)],
    [:z, 'XOY', Geom::Vector3d.new(0, 0, 1)],
    [:y, 'XOZ', Geom::Vector3d.new(0, 1, 0)]
  ].freeze

  def initialize
    @input = Sketchup::InputPoint.new
    @axis_index = 0
    @targets = []
    @hover_target = nil
    @cut_scope = :all_selected
    @drag_start = nil
    @drag_end = nil
    @cut_mode = :axis
    @point_one = nil
    @plane_point = nil
    @plane_normal = nil
    @cut_coordinate = nil
  end

  def activate
    @targets = Sketchup.active_model.selection.grep(Sketchup::Group) +
               Sketchup.active_model.selection.grep(Sketchup::ComponentInstance)
    @targets.select! { |entity| MH::Geo::Solid.solid?(entity) }
    update_status
  end

  def resume(view)
    update_status
    view.invalidate
  end

  def onMouseMove(_flags, x, y, view)
    if @drag_start
      @drag_end = [x, y]
      view.invalidate
      return
    end

    @input.pick(view, x, y)
    @hover_target = pick_solid(view, x, y)
    sync_cut_scope_selection if @cut_scope == :hovered_only && @hover_target
    return unless @input.valid? && active_targets.any?

    if @cut_mode == :axis
      @cut_coordinate = axis_value(@input.position)
      @plane_point = point_on_axis_plane(@input.position)
      @plane_normal = axis[2]
    elsif @point_one
      @preview_normal = point_cut_normal(@point_one, @input.position)
    end
    view.invalidate
  end

  def onLButtonDown(flags, x, y, view)
    @input.pick(view, x, y)
    @hover_target = pick_solid(view, x, y)
    if ctrl_down?(flags)
      @drag_start = [x, y]
      @drag_end = [x, y]
      return
    end

    if @cut_mode == :points
      handle_point_cut_click(view)
      return
    end

    onMouseMove(nil, x, y, view)
    return unless valid_cut?

    cut_targets
    @cut_coordinate = nil
    update_status
    view.invalidate
  end

  def onLButtonUp(flags, x, y, view)
    return unless @drag_start

    start = @drag_start
    finish = @drag_end || [x, y]
    @drag_start = @drag_end = nil
    moved = (start[0] - finish[0]).abs + (start[1] - finish[1]).abs
    if ctrl_down?(flags) && moved > 4
      add_dragged_targets(view, start, finish)
    else
      toggle_target(@hover_target)
    end
    update_status
    view.invalidate
  end

  def onKeyDown(key, repeat, _flags, view)
    if key == VK_SHIFT
      return if repeat.to_i > 1

      @cut_scope = @cut_scope == :all_selected ? :hovered_only : :all_selected
      sync_cut_scope_selection
      update_status
      view.invalidate
      return
    end
    return unless key == VK_TAB
    return if @cut_mode == :points

    @axis_index = (@axis_index + 1) % AXES.length
    update_status
    view.invalidate
  end

  def getMenu(menu)
    menu.add_item('Cắt ván theo trục') { set_cut_mode(:axis) }
    menu.add_item('Cắt ván theo 2 điểm') { set_cut_mode(:points) }
  end

  def draw(view)
    @input.draw(view) if @input.valid?
    draw_point_cut_preview(view) if @cut_mode == :points && @point_one && @input.valid?
    if valid_cut?
      corners = preview_corners
      if corners
        view.drawing_color = Sketchup::Color.new(44, 161, 214, 70)
        view.draw(GL_QUADS, corners)
        view.drawing_color = Sketchup::Color.new(24, 112, 160)
        view.line_width = 2
        view.draw(GL_LINE_LOOP, corners)
      end
    end
    draw_selection_rect(view) if @drag_start && @drag_end
  end

  def getExtents
    bounds = target_bounds
    return unless bounds

    bounds
  end

  private

  def axis
    AXES[@axis_index]
  end

  def axis_value(point, direction = axis[2])
    point.x * direction.x + point.y * direction.y + point.z * direction.z
  end

  def target_bounds
    targets = active_targets
    return nil if targets.empty?

    bounds = Geom::BoundingBox.new
    targets.each { |target| bounds.add(target.bounds) if target.valid? }
    bounds.empty? ? nil : bounds
  end

  def valid_cut?
    bounds = target_bounds
    return false unless bounds && @cut_coordinate
    return target_crosses_plane?(bounds) if @cut_mode == :points

    min, max = axis_bounds(bounds)
    @cut_coordinate > min + 0.1.mm && @cut_coordinate < max - 0.1.mm
  end

  def axis_bounds(bounds)
    axis_bounds_for(bounds, axis[2])
  end

  def axis_bounds_for(bounds, direction)
    case axis_index_for(direction)
    when :x then [bounds.min.x, bounds.max.x]
    when :y then [bounds.min.y, bounds.max.y]
    else [bounds.min.z, bounds.max.z]
    end
  end

  def axis_index_for(direction)
    AXES.max_by { |_, _, candidate| direction.dot(candidate).abs }[0]
  end

  def preview_corners
    return oriented_preview_corners if @cut_mode == :points

    axis_preview_corners(axis[2], @cut_coordinate)
  end

  def axis_preview_corners(direction, value)
    bounds = target_bounds
    return nil unless bounds && direction && value

    min = bounds.min
    max = bounds.max
    case axis_index_for(direction)
    when :x
      [Geom::Point3d.new(value, min.y, min.z), Geom::Point3d.new(value, max.y, min.z),
       Geom::Point3d.new(value, max.y, max.z), Geom::Point3d.new(value, min.y, max.z)]
    when :y
      [Geom::Point3d.new(min.x, value, min.z), Geom::Point3d.new(max.x, value, min.z),
       Geom::Point3d.new(max.x, value, max.z), Geom::Point3d.new(min.x, value, max.z)]
    else
      [Geom::Point3d.new(min.x, min.y, value), Geom::Point3d.new(max.x, min.y, value),
       Geom::Point3d.new(max.x, max.y, value), Geom::Point3d.new(min.x, max.y, value)]
    end
  end

  def cut_targets
    model = Sketchup.active_model
    original_targets = active_targets.select(&:valid?)
    preserved = @targets.select { |target| target && target.valid? && !original_targets.include?(target) }
    created = []
    unchanged = []
    model.start_operation('Cat van', true)
    begin
      original_targets.each do |target|
        unless target_crosses_cut?(target)
          unchanged << target
          next
        end
        pieces = cut_target(target)
        raise 'Khong the cat tam da chon' unless pieces && pieces.length == 2

        target.erase!
        created.concat(pieces)
      end
      result_targets = (preserved + unchanged + created).uniq
      model.selection.clear
      model.selection.add(result_targets)
      model.commit_operation
      @targets = result_targets
    rescue => e
      model.abort_operation
      UI.beep
      MH::Panel.dbg("[MH::Panel::CatVan] cut error: #{e.class}: #{e.message}")
    end
  end

  def cut_target(target)
    bounds = target.bounds
    return nil unless target_crosses_cut?(target)

    first = duplicate_target(target)
    second = duplicate_target(target)
    return nil unless first && second

    cutter_a = add_half_space(parent_entities(target), bounds, true)
    cutter_b = add_half_space(parent_entities(target), bounds, false)
    ok_a = MH::Geo::Solid.intersect(first, cutter_a)
    ok_b = MH::Geo::Solid.intersect(second, cutter_b)
    [cutter_a, cutter_b].each { |cutter| cutter.erase! if cutter && cutter.valid? }
    return nil unless ok_a && ok_b && MH::Geo::Solid.solid?(first) && MH::Geo::Solid.solid?(second)

    base_name = target.name.to_s
    first.name = base_name
    second.name = base_name
    first.material = target.material if first.respond_to?(:material=)
    second.material = target.material if second.respond_to?(:material=)
    [first, second]
  rescue
    [first, second].compact.each { |piece| piece.erase! if piece.valid? }
    nil
  end

  def duplicate_target(target)
    copy = target.copy rescue nil
    return copy if copy

    copy = parent_entities(target).add_instance(target.definition, target.transformation)
    copy.name = target.name if copy.respond_to?(:name=)
    copy.material = target.material if copy.respond_to?(:material=)
    copy
  end

  def add_half_space(entities, bounds, first_half)
    return add_oriented_half_space(entities, bounds, first_half) if @cut_mode == :points

    add_axis_half_space(entities, bounds, first_half, axis[2], @cut_coordinate)
  end

  def add_axis_half_space(entities, bounds, first_half, direction, coordinate)
    return nil unless direction && coordinate

    margin = [bounds.width, bounds.height, bounds.depth].max + 100.mm
    min = bounds.min
    max = bounds.max
    low, high = axis_bounds_for(bounds, direction)
    if first_half
      high = coordinate
    else
      low = coordinate
    end
    case axis_index_for(direction)
    when :x then min = Geom::Point3d.new(low, min.y - margin, min.z - margin); max = Geom::Point3d.new(high, max.y + margin, max.z + margin)
    when :y then min = Geom::Point3d.new(min.x - margin, low, min.z - margin); max = Geom::Point3d.new(max.x + margin, high, max.z + margin)
    else min = Geom::Point3d.new(min.x - margin, min.y - margin, low); max = Geom::Point3d.new(max.x + margin, max.y + margin, high)
    end
    add_box(entities, min, max)
  end

  def parent_entities(target)
    parent = target.parent
    parent.respond_to?(:entities) ? parent.entities : parent
  end

  def active_targets
    if @cut_scope == :hovered_only
      return [@hover_target] if @hover_target && @hover_target.valid? && MH::Geo::Solid.solid?(@hover_target)

      return []
    end

    selected = @targets.select { |target| target && target.valid? }
    selected.empty? && @hover_target && @hover_target.valid? ? [@hover_target] : selected
  end

  def target_crosses_cut?(target)
    return target_crosses_plane?(target.bounds) if @cut_mode == :points

    minimum, maximum = axis_bounds(target.bounds)
    @cut_coordinate > minimum + 0.1.mm && @cut_coordinate < maximum - 0.1.mm
  end

  def handle_point_cut_click(view)
    return unless @input.valid? && active_targets.any?

    if @point_one.nil?
      @point_one = @input.position.clone
      Sketchup.set_status_text('Chọn điểm thứ hai để xác định mặt cắt.', SB_PROMPT)
      view.invalidate
      return
    end
    # Use the active X/Y/Z reference at the moment of the second click.
    # A cached preview normal may belong to the axis selected before Tab.
    normal = point_cut_normal(@point_one, @input.position)
    return unless normal
    @plane_point = @point_one
    @plane_normal = normal
    @cut_coordinate = 0
    UI.start_timer(0.01, false) do
      cut_targets if valid_cut?
      @point_one = nil
      @point_thickness = nil
      @preview_normal = nil
      @plane_point = @plane_normal = nil
      Sketchup.active_model.active_view.invalidate
    end
    view.invalidate
  end

  def set_cut_mode(mode)
    @cut_mode = mode
    @point_one = nil
    @point_thickness = nil
    @preview_normal = nil
    @plane_point = @plane_normal = nil
    @cut_coordinate = nil
    update_status
    Sketchup.active_model.active_view.invalidate
  end

  def point_on_axis_plane(point, direction = axis[2])
    bounds = target_bounds
    center = bounds.center
    center.offset(direction, axis_value(point, direction) - axis_value(center, direction))
  end

  def thickness_axis(bounds)
    dimensions = [[bounds.width, Geom::Vector3d.new(1, 0, 0)], [bounds.height, Geom::Vector3d.new(0, 1, 0)], [bounds.depth, Geom::Vector3d.new(0, 0, 1)]]
    dimensions.min_by(&:first)[1]
  end

  def point_cut_normal(start_point, end_point)
    direction = start_point.vector_to(end_point)
    return nil if direction.length <= 0.1.mm

    # Point mode rotates a vertical cutting plane around the first point.
    # The line to the cursor stays on the plane while the plane remains
    # parallel to the global Z axis, regardless of the panel shape.
    normal = direction.cross(Geom::Vector3d.new(0, 0, 1))
    return nil if normal.length <= 0.001.mm

    normal.normalize!
    normal
  end

  def thickness_direction_for(target)
    return thickness_axis(target_bounds) unless target && target.respond_to?(:definition)

    bounds = target.definition.bounds
    choices = [
      [bounds.width, target.transformation.xaxis],
      [bounds.height, target.transformation.yaxis],
      [bounds.depth, target.transformation.zaxis]
    ]
    direction = choices.min_by(&:first)[1].clone
    direction.normalize!
    direction
  rescue
    thickness_axis(target_bounds)
  end

  def draw_point_cut_preview(view)
    view.drawing_color = Sketchup::Color.new(24, 112, 160)
    view.line_width = 2
    view.draw(GL_LINES, [@point_one, @input.position])
    return unless @preview_normal

    corners = oriented_preview_corners(@point_one, @preview_normal)
    return unless corners
    view.drawing_color = Sketchup::Color.new(44, 161, 214, 70)
    view.draw(GL_QUADS, corners)
    view.drawing_color = Sketchup::Color.new(24, 112, 160)
    view.draw(GL_LINE_LOOP, corners)
  end

  def target_crosses_plane?(bounds)
    return false unless @plane_point && @plane_normal
    distances = (0..7).map { |index| @plane_point.vector_to(bounds.corner(index)).dot(@plane_normal) }
    distances.min < -0.1.mm && distances.max > 0.1.mm
  end

  def oriented_preview_corners(point = @plane_point, normal = @plane_normal)
    return nil unless point && normal
    bounds = target_bounds
    return nil unless bounds
    u = normal.cross(Geom::Vector3d.new(0, 0, 1))
    u = normal.cross(Geom::Vector3d.new(0, 1, 0)) if u.length <= 0.001.mm
    u.normalize!
    v = normal.cross(u)
    v.normalize!
    projected = (0..7).map do |index|
      vector = point.vector_to(bounds.corner(index))
      [vector.dot(u), vector.dot(v)]
    end
    padding = 2.mm
    u_min, u_max = projected.map(&:first).minmax
    v_min, v_max = projected.map(&:last).minmax
    [
      point.offset(u, u_min - padding).offset(v, v_min - padding),
      point.offset(u, u_max + padding).offset(v, v_min - padding),
      point.offset(u, u_max + padding).offset(v, v_max + padding),
      point.offset(u, u_min - padding).offset(v, v_max + padding)
    ]
  end

  def add_oriented_half_space(entities, bounds, first_half)
    span = bounds.diagonal + 200.mm
    center = @plane_point.offset(@plane_normal, first_half ? -span / 2.0 : span / 2.0)
    u = @plane_normal.cross(Geom::Vector3d.new(0, 0, 1))
    u = @plane_normal.cross(Geom::Vector3d.new(0, 1, 0)) if u.length <= 0.001.mm
    u.normalize!
    v = @plane_normal.cross(u)
    v.normalize!
    add_oriented_box(entities, center, u, v, @plane_normal, span, span, span / 2.0)
  end

  def add_oriented_box(entities, center, u, v, normal, half_u, half_v, half_normal)
    group = entities.add_group
    points = [-1, 1].product([-1, 1], [-1, 1]).map { |a, b, c| center.offset(u, a * half_u).offset(v, b * half_v).offset(normal, c * half_normal) }
    [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [1, 5, 7, 3], [3, 7, 6, 2], [2, 6, 4, 0]].each { |indices| group.entities.add_face(indices.map { |index| points[index] }) }
    group
  end

  def pick_solid(view, x, y)
    helper = view.pick_helper
    helper.do_pick(x, y)
    hits = helper.count.times.filter_map do |index|
      path = helper.path_at(index)
      Array(path).reverse.select { |entity| MH::Geo::Solid.solid?(entity) }
    end.flatten.uniq
    hits.find { |entity| @targets.include?(entity) } || hits.first
  rescue
    nil
  end

  def sync_cut_scope_selection
    targets = if @cut_scope == :hovered_only
                [@hover_target].compact.select { |target| target.valid? && MH::Geo::Solid.solid?(target) }
              else
                @targets.select { |target| target && target.valid? }
              end
    return if targets.empty? && @cut_scope == :hovered_only

    selection = Sketchup.active_model.selection
    return if selection.to_a == targets

    selection.clear
    selection.add(targets)
  rescue => e
    MH::Panel.dbg("[MH::Panel::CatVan] sync selection error: #{e.class}: #{e.message}")
  end

  def ctrl_down?(flags)
    (flags & COPY_MODIFIER_MASK) != 0
  rescue
    false
  end

  def toggle_target(target)
    return unless target && target.valid?

    if @targets.include?(target)
      @targets.delete(target)
    else
      @targets << target
    end
    Sketchup.active_model.selection.clear
    Sketchup.active_model.selection.add(@targets)
  end

  def add_dragged_targets(view, start, finish)
    left, right = [start[0], finish[0]].minmax
    top, bottom = [start[1], finish[1]].minmax
    candidates = Sketchup.active_model.active_entities.grep(Sketchup::Group) +
                 Sketchup.active_model.active_entities.grep(Sketchup::ComponentInstance)
    candidates.each do |target|
      next unless MH::Geo::Solid.solid?(target)
      next unless screen_bounds_overlap?(view, target.bounds, left, top, right, bottom)
      @targets << target unless @targets.include?(target)
    end
    Sketchup.active_model.selection.clear
    Sketchup.active_model.selection.add(@targets)
  end

  def screen_bounds_overlap?(view, bounds, left, top, right, bottom)
    points = (0..7).map { |index| view.screen_coords(bounds.corner(index)) }
    xs = points.map(&:x)
    ys = points.map(&:y)
    xs.max >= left && xs.min <= right && ys.max >= top && ys.min <= bottom
  rescue
    false
  end

  def draw_selection_rect(view)
    x1, y1 = @drag_start
    x2, y2 = @drag_end
    view.drawing_color = Sketchup::Color.new(24, 112, 160)
    view.draw2d(GL_LINE_LOOP, [Geom::Point3d.new(x1, y1, 0), Geom::Point3d.new(x2, y1, 0),
                               Geom::Point3d.new(x2, y2, 0), Geom::Point3d.new(x1, y2, 0)])
  end

  def add_box(entities, min, max)
    group = entities.add_group
    points = [
      Geom::Point3d.new(min.x, min.y, min.z), Geom::Point3d.new(max.x, min.y, min.z),
      Geom::Point3d.new(max.x, max.y, min.z), Geom::Point3d.new(min.x, max.y, min.z),
      Geom::Point3d.new(min.x, min.y, max.z), Geom::Point3d.new(max.x, min.y, max.z),
      Geom::Point3d.new(max.x, max.y, max.z), Geom::Point3d.new(min.x, max.y, max.z)
    ]
    faces = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    faces.each { |indices| group.entities.add_face(indices.map { |index| points[index] }) }
    group
  end

  def update_status
    if active_targets.empty?
      Sketchup.set_status_text('Di chuột lên tấm để cắt. Ctrl+click hoặc Ctrl+quét để chọn nhiều tấm. Shift đổi phạm vi cắt.', SB_PROMPT)
    else
      scope = @cut_scope == :hovered_only ? 'chỉ khối dưới chuột' : 'tất cả khối đang chọn'
      prompt = if @cut_mode == :axis
                 "Cắt mặt #{axis[1]}. Tab: YOZ / XOY / XOZ."
               else
                 'Cắt theo 2 điểm. Mặt cắt xoay qua điểm 1 và luôn song song trục Z.'
               end
      Sketchup.set_status_text("#{prompt} Shift: đổi phạm vi (#{scope}). Ctrl: chọn thêm hoặc quét chọn.", SB_PROMPT)
    end
  end
end
