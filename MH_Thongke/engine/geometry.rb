# encoding: utf-8
# MH_Thongke — Geometry Helpers
# Bounds, dimensions, placement transforms, face alignment
# Tách từ main.rb: dòng 425–511, 3540–3654

module MH_Thongke

  # -------------------------------------------------------
  # PHÀO CHỈ: Lấy 3 chiều bounding box → sort → cạnh dài nhất là chiều dài,
  # 2 cạnh còn lại là kích thước mặt cắt hiển thị trong tên
  # -------------------------------------------------------
  def self.entity_local_bounds(entity)
    if entity.is_a?(Sketchup::ComponentInstance)
      entity.definition.bounds
    elsif entity.is_a?(Sketchup::Group)
      entity.definition.bounds
    else
      entity.bounds
    end
  end

  def self.entity_world_corners(entity, parent_wt)
    full_wt = parent_wt * entity.transformation
    bb = entity_local_bounds(entity)
    (0..7).map { |i| bb.corner(i).transform(full_wt) }
  end

  def self.get_phaochi_info(entity, parent_wt)
    corners = entity_world_corners(entity, parent_wt)
    xs = corners.map(&:x); ys = corners.map(&:y); zs = corners.map(&:z)
    dims_inch = [xs.max - xs.min, ys.max - ys.min, zs.max - zs.min].sort  # [min, mid, max]
    len_mm   = (dims_inch[2] * 25.4).round(1)   # cạnh dài nhất
    w_mm     = (dims_inch[0] * 25.4).round(1)   # cạnh ngắn nhất
    h_mm     = (dims_inch[1] * 25.4).round(1)   # cạnh ngắn thứ 2
    { len_mm: len_mm, w_mm: w_mm, h_mm: h_mm }
  end

  def self.get_world_dimensions_mm(entity, parent_wt)
    corners = entity_world_corners(entity, parent_wt)
    xs = corners.map(&:x); ys = corners.map(&:y); zs = corners.map(&:z)
    [xs.max - xs.min, ys.max - ys.min, zs.max - zs.min].map { |dim| (dim * 25.4).round(0).to_i }.sort.reverse
  end

  def self.clean_dimension_name(value)
    value.to_s.strip.gsub(/\s+/, " ")
  end

  def self.special_hardware_kind(name)
    normalized = name.to_s.downcase
    return :con_tien if normalized.include?("con tiện") || normalized.include?("con tien")
    return :canh_nhom_kinh if normalized.include?("cánh nhôm kính") || normalized.include?("canh nhom kinh")
    return :guong if normalized.include?("gương") || normalized.include?("guong")
    return :la_inox if normalized.include?("la inox")
    return :kinh if normalized.include?("kính") || normalized.include?("kinh")
    nil
  end

  def self.mh_name_norm(value)

    cached_norm(value)

  end

  def self.accessory_unit_for_name(name)
    return "md" if phaochi_name?(name)
    norm = mh_name_norm(name)
    return "Cái" if norm =~ /(nguon led|bo nguon|driver led|adapter)/
    return "md" if norm =~ /(led|suot ao|thanh nhom|gioang cua|doang cua)/
    return "Thanh" if norm.include?("la inox")
    return "Bộ" if norm.include?("khung sat")
    nil
  end

  # Nhận diện "phào chỉ" robust:
  # - có/không dấu
  # - có/không khoảng trắng, gạch nối, dấu chấm, gạch dưới
  # - có thêm hậu tố số/ký tự phía sau
  def self.phaochi_name?(name)
    text = fix_vietnamese_mojibake(name).to_s
    norm = mh_name_norm(text).gsub(/[^a-z0-9]+/, " ").strip
    return false if norm.empty?
    !!(norm =~ /\bphao\s*chi\b/)
  rescue
    false
  end

  def self.accessory_display_name_for_rules(name)
    text = name.to_s.strip
    return text if text.empty?
    norm = mh_name_norm(text)
    return text if norm.include?(" md")
    return "#{text} md" if norm.include?("la inox")
    text
  end

  def self.add_special_hardware_row(kind, entity, parent_wt, prod_code, current_top, is_selected, base_name_override = nil)
    base_name = base_name_override.to_s.strip
    base_name = entity.name.to_s.strip if base_name.empty?
    base_name = entity.definition.name.to_s.strip if base_name.empty? && entity.respond_to?(:definition)
    base_name = "Đối tượng" if base_name.empty?

    dims = get_world_dimensions_mm(entity, parent_wt)
    a, b, c = dims
    flat_name = base_name.gsub(/(?:dày|day)\s*\d+/i, "").gsub(/\s+/, " ").strip
    flat_name = base_name if flat_name.empty?
    display_name = case kind
                   when :con_tien then "#{base_name} #{a}x#{b}x#{c}"
                   when :canh_nhom_kinh then "#{base_name} bản #{c}"
                   when :guong, :kinh, :la_inox then "#{flat_name} dày #{c}"
                   else base_name
                   end
    display_name = accessory_display_name_for_rules(display_name)
    kich_thuoc = [:canh_nhom_kinh, :guong, :kinh, :la_inox].include?(kind) ? "#{a}x#{b}" : "#{a}x#{b}x#{c}"
    display_prod = @group_by == "NAME" ? "--" : prod_code
    data_key = @group_by == "NAME" ? display_name : "#{display_name}_#{prod_code}_#{kich_thuoc}"
    unit = accessory_unit_for_name(display_name) || "Cái"

    @data_map[data_key] ||= {
      name: display_name, product: display_prod, actual_product: prod_code,
      ten_sp: entity.get_attribute("MH_Thongke","ten_sp") || "",
      ghi_chu: entity.get_attribute("MH_Thongke","ghi_chu") || "",
      ngay_dat: normalize_order_date(entity.get_attribute("MH_Thongke","ngay_dat")),
      last_modified: entity.get_attribute("MH_Thongke","last_modified") || "",
      trang_thai: "", new_name: "", kich_thuoc: kich_thuoc,
      layer: entity.layer.name, count: 0, length: 0.0, sel_count: 0, sel_length: 0.0, unit: unit,
      dict: "MH_Thongke", key: "special_hardware", type: :count,
      entities: [], stat_entities: [], length_items: [], is_missing: false
    }
    @data_map[data_key][:count] += 1
    @data_map[data_key][:sel_count] += 1 if is_selected
    top_id = current_top.entityID rescue nil
    unless top_id && @entity_ids_in_data[data_key].include?(top_id)
      @data_map[data_key][:entities] << current_top
      @entity_ids_in_data[data_key] << top_id if top_id
    end
    e_id = entity.entityID rescue nil
    unless e_id && @stat_entity_ids[data_key].include?(e_id)
      @data_map[data_key][:stat_entities] << [entity, current_top, parent_wt]
      @stat_entity_ids[data_key] << e_id if e_id
    end
    unless @all_item_names_set.include?(display_name)
      @all_item_names << display_name
      @all_item_names_set << display_name
    end
  end

  def self.get_world_length(entity, parent_wt)
    corners = entity_world_corners(entity, parent_wt)
    xs = corners.map(&:x); ys = corners.map(&:y); zs = corners.map(&:z)
    dx = xs.max - xs.min; dy = ys.max - ys.min; dz = zs.max - zs.min
    [dx, dy, dz].max
  end

  # -------------------------------------------------------
  # PLACEMENT GEOMETRY — Transform PK lên mặt phẳng
  # -------------------------------------------------------

  def self.smallest_face(entities)
    return nil unless entities
    entities.grep(Sketchup::Face).select { |f| (f.area rescue 0) > 0 }.min_by { |f| f.area rescue Float::INFINITY }
  end

  def self.largest_face(entities)
    smallest_face(entities)
  end

  def self.largest_face_transform(entities)
    face = smallest_face(entities)
    return nil unless face
    pt = face.bounds.center
    normal = face.normal
    
    # Tìm cạnh dài nhất để làm trục X (đảm bảo tính nhất quán)
    longest_edge = face.edges.max_by { |e| e.length }
    if longest_edge
      x_axis = longest_edge.start.position.vector_to(longest_edge.end.position).normalize
      if x_axis.x < 0 || (x_axis.x == 0 && x_axis.y < 0) || (x_axis.x == 0 && x_axis.y == 0 && x_axis.z < 0)
        x_axis.reverse!
      end
    else
      x_axis = normal.axes[0]
    end
    
    y_axis = normal.cross(x_axis).normalize
    x_axis = y_axis.cross(normal).normalize
    
    Geom::Transformation.axes(pt, x_axis, y_axis, normal)
  end

  def self.definition_plane_transform(defn, face_tr)
    bb = defn.bounds
    face_origin = face_tr.origin
    face_x = face_tr.xaxis
    face_y = face_tr.yaxis
    face_normal = face_tr.zaxis

    dims = [bb.width.to_f, bb.depth.to_f, bb.height.to_f]
    def_axes = [X_AXIS, Y_AXIS, Z_AXIS]

    sorted = dims.each_with_index.sort_by { |d, _| d }
    thin_idx = sorted[0][1]
    long_idx = sorted[2][1]
    mid_idx  = sorted[1][1]

    src_normal = def_axes[thin_idx]
    src_x = def_axes[long_idx]
    src_y = src_normal.cross(src_x)
    src_y = def_axes[mid_idx] unless src_y.valid?

    src_tr = Geom::Transformation.axes(bb.center, src_x, src_y, src_normal)
    dst_tr = Geom::Transformation.axes(face_origin, face_x, face_y, face_normal)

    dst_tr * src_tr.inverse
  rescue => e
    puts "definition_plane_transform error: #{e.message}"
    Geom::Transformation.new
  end

  def self.face_grid_offset(ents, face_tr, lib_defn, index, total)
    return Geom::Transformation.new unless ents && face_tr
    index = [index.to_i, 0].max
    total = [total.to_i, 1].max
    face = largest_face(ents)
    unless face
      offset_x = (index % 10) * 4.0
      offset_y = (index / 10).to_i * 4.0
      return Geom::Transformation.translation(Geom::Vector3d.new(offset_x, offset_y, 0))
    end

    origin = face_tr.origin
    x_axis = face_tr.xaxis
    y_axis = face_tr.yaxis
    vertices = face.vertices.map(&:position)
    xs = vertices.map { |pt| origin.vector_to(pt).dot(x_axis) }
    ys = vertices.map { |pt| origin.vector_to(pt).dot(y_axis) }
    min_x, max_x = xs.minmax
    min_y, max_y = ys.minmax
    width = max_x.to_f - min_x.to_f
    height = max_y.to_f - min_y.to_f
    return Geom::Transformation.new if width <= 0 || height <= 0

    margin = 1.0 / 25.4
    if lib_defn && lib_defn.respond_to?(:bounds)
      dims = [lib_defn.bounds.width.to_f, lib_defn.bounds.depth.to_f, lib_defn.bounds.height.to_f].sort
      margin = [margin, dims[1].to_f * 0.5 + 1.0 / 25.4].max
    elsif lib_defn.to_f > 0
      margin = [margin, lib_defn.to_f * 0.5 + 1.0 / 25.4].max
    end
    usable_w = width - margin * 2.0
    usable_h = height - margin * 2.0
    usable_w = width if usable_w <= 0
    usable_h = height if usable_h <= 0
    cols = Math.sqrt(total).ceil
    rows = (total.to_f / cols).ceil
    col = index % cols
    row = index / cols
    cell_w = usable_w / cols
    cell_h = usable_h / rows
    x = min_x + (width - usable_w) / 2.0 + cell_w * (col + 0.5)
    y = min_y + (height - usable_h) / 2.0 + cell_h * (row + 0.5)

    offset = x_axis.clone
    offset.length = x.abs
    offset.reverse! if x < 0
    y_offset = y_axis.clone
    y_offset.length = y.abs
    y_offset.reverse! if y < 0
    Geom::Transformation.translation(offset + y_offset)
  rescue => e
    puts "face_grid_offset error: #{e.message}"
    Geom::Transformation.new
  end

  def self.calculate_placement_transform(ents, lib_defn, face_tr, index = nil, total = nil)
    return Geom::Transformation.new unless face_tr && lib_defn && lib_defn.respond_to?(:bounds)
    base_tr = definition_plane_transform(lib_defn, face_tr)
    
    existing_pks = ents.select { |e| pk_marker_entity?(e) }
    start_index = existing_pks.size
    idx = index.nil? ? start_index : start_index + index.to_i
    ttl = total.nil? ? idx + 1 : start_index + total.to_i
    base_tr = face_grid_offset(ents, face_tr, lib_defn, idx, ttl) * base_tr
    base_tr
  end

  def self.pk_marker_size_for_face(ents, face_tr, total = 1)
    default_size = pk_marker_max_size
    face = smallest_face(ents)
    return default_size unless face && face_tr

    total = [total.to_i, 1].max
    origin = face_tr.origin
    x_axis = face_tr.xaxis
    y_axis = face_tr.yaxis
    xs = face.vertices.map { |v| origin.vector_to(v.position).dot(x_axis) }
    ys = face.vertices.map { |v| origin.vector_to(v.position).dot(y_axis) }
    width = xs.max.to_f - xs.min.to_f
    height = ys.max.to_f - ys.min.to_f
    cols = Math.sqrt(total).ceil
    rows = (total.to_f / cols).ceil
    cell_w = width.abs / cols
    cell_h = height.abs / rows
    limit = [cell_w, cell_h].min * 0.7
    min_size = 0.5 / 25.4
    [[default_size, limit].min, min_size].max
  rescue
    default_size
  end

  def self.face_local_bounds(ents, face_tr)
    face = largest_face(ents)
    return nil unless face && face_tr

    origin = face_tr.origin
    x_axis = face_tr.xaxis
    y_axis = face_tr.yaxis
    xs = face.vertices.map { |v| origin.vector_to(v.position).dot(x_axis) }
    ys = face.vertices.map { |v| origin.vector_to(v.position).dot(y_axis) }
    [xs.min.to_f, xs.max.to_f, ys.min.to_f, ys.max.to_f]
  rescue
    nil
  end

  def self.entity_face_rect(entity, face_tr)
    return nil unless entity && face_tr && entity.respond_to?(:bounds)

    bb = entity.bounds
    return nil unless bb && bb.valid?

    origin = face_tr.origin
    x_axis = face_tr.xaxis
    y_axis = face_tr.yaxis
    xs = []
    ys = []
    8.times do |i|
      pt = bb.corner(i)
      xs << origin.vector_to(pt).dot(x_axis)
      ys << origin.vector_to(pt).dot(y_axis)
    end
    [xs.min.to_f, xs.max.to_f, ys.min.to_f, ys.max.to_f]
  rescue
    nil
  end

  def self.occupied_face_rects(ents, face_tr)
    return [] unless ents && face_tr

    ents.map do |e|
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next if e.respond_to?(:deleted?) && e.deleted?

      entity_face_rect(e, face_tr)
    end.compact
  rescue
    []
  end

  def self.point_in_expanded_rect?(x, y, rect, pad)
    x >= rect[0] - pad && x <= rect[1] + pad &&
      y >= rect[2] - pad && y <= rect[3] + pad
  rescue
    false
  end

  def self.free_face_grid_transform(ents, face_tr, marker_size, index = nil, total = nil)
    bounds = face_local_bounds(ents, face_tr)
    return nil unless bounds && face_tr

    min_x, max_x, min_y, max_y = bounds
    width = max_x - min_x
    height = max_y - min_y
    return nil if width <= 0 || height <= 0

    size = marker_size.to_f
    size = pk_marker_max_size if size <= 0
    pad = [size * 0.75, 1.0 / 25.4].max
    usable_w = width - pad * 2.0
    usable_h = height - pad * 2.0
    usable_w = width if usable_w <= 0
    usable_h = height if usable_h <= 0

    occupied = occupied_face_rects(ents, face_tr)
    start = index.nil? ? occupied.length : [index.to_i, 0].max
    total_hint = total.nil? ? 0 : total.to_i
    hint_total = [total_hint, start + 1, 1].max
    max_slots = [hint_total + occupied.length + 80, 400].max

    start.upto(max_slots) do |slot|
      grid_total = [hint_total, slot + 1].max
      cols = Math.sqrt(grid_total).ceil
      rows = (grid_total.to_f / cols).ceil
      next if cols <= 0 || rows <= 0

      cell_w = usable_w / cols
      cell_h = usable_h / rows
      col = slot % cols
      row = slot / cols
      x = min_x + (width - usable_w) / 2.0 + cell_w * (col + 0.5)
      y = min_y + (height - usable_h) / 2.0 + cell_h * (row + 0.5)
      next if occupied.any? { |rect| point_in_expanded_rect?(x, y, rect, pad) }

      x_offset = face_tr.xaxis.clone
      x_offset.length = x.abs
      x_offset.reverse! if x < 0
      y_offset = face_tr.yaxis.clone
      y_offset.length = y.abs
      y_offset.reverse! if y < 0
      return Geom::Transformation.translation(x_offset + y_offset) * face_tr
    end

    nil
  rescue
    nil
  end

  def self.pk_marker_placement_transform(ents, face_tr, marker_size, index = nil, total = nil)
    return Geom::Transformation.new unless face_tr
    free_tr = free_face_grid_transform(ents, face_tr, marker_size.to_f, index, total)
    return free_tr if free_tr

    existing_pks = ents.select { |e| pk_marker_entity?(e) }
    start_index = existing_pks.size
    idx = index.nil? ? start_index : index.to_i
    ttl = total.nil? ? idx + 1 : total.to_i
    face_grid_offset(ents, face_tr, marker_size.to_f, idx, ttl) * face_tr
  end

  def self.pk_marker_entity?(entity)
    (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
      (entity.get_attribute("ABF", "is-statistical-object").to_s == "true" ||
       entity.get_attribute("MH_Thongke", "generated_pk").to_s == "true")
  rescue
    false
  end

  def self.pk_marker_points(shape, size)
    half = size.to_f / 2.0
    case shape.to_s
    when "circle"
      segments = 24
      (0...segments).map do |i|
        a = (Math::PI * 2.0 * i) / segments
        Geom::Point3d.new(Math.cos(a) * half, Math.sin(a) * half, 0)
      end
    when "triangle"
      r = half
      (0...3).map do |i|
        a = Math::PI / 2.0 + (Math::PI * 2.0 * i) / 3.0
        Geom::Point3d.new(Math.cos(a) * r, Math.sin(a) * r, 0)
      end
    else
      [
        Geom::Point3d.new(-half, -half, 0),
        Geom::Point3d.new( half, -half, 0),
        Geom::Point3d.new( half,  half, 0),
        Geom::Point3d.new(-half,  half, 0)
      ]
    end
  end

  def self.pk_link_id
    chars = ("a".."z").to_a + ("0".."9").to_a
    Array.new(9) { chars[rand(chars.length)] }.join
  end

  def self.pk_numeric_id
    rand(100000..999999)
  end

  def self.next_abf_board_index(model = nil)
    model ||= Sketchup.active_model
    used_indexes = {}
    scan = lambda do |entities|
      entities.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        idx = entity.get_attribute("ABF", "board-index").to_i
        used_indexes[idx] = true if idx > 0
        child_entities = (entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.entities : entity.entities) rescue nil
        scan.call(child_entities) if child_entities
      end
    end
    scan.call(model.entities) if model
    idx = 1
    idx += 1 while used_indexes[idx]
    idx
  rescue
    1
  end

  def self.allocate_abf_board_index(model = nil)
    next_abf_board_index(model)
  end

  def self.ensure_abf_board_attributes(entity, model = nil)
    return nil unless entity && (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))

    model ||= Sketchup.active_model
    board_index = entity.get_attribute("ABF", "board-index")
    board_index = allocate_abf_board_index(model) if board_index.to_s.strip.empty? || board_index.to_i <= 0
    entity.set_attribute("ABF", "board-index", board_index.to_i)
    entity.set_attribute("ABF", "is-board", true)
    entity.set_attribute("ABF", "label-rotation", entity.get_attribute("ABF", "label-rotation") || 0)
    board_index.to_i
  rescue => e
    puts "ensure_abf_board_attributes error: #{e.message}"
    nil
  end

  def self.set_attr_if_needed(entity, dict, key, value)
    entity.set_attribute(dict, key, value) unless entity.get_attribute(dict, key) == value
  end

  def self.delete_attr_if_present(entity, dict, key)
    entity.delete_attribute(dict, key) unless entity.get_attribute(dict, key).nil?
  rescue
  end

  def self.pk_unique_id(entity = nil)
    entity_id = entity.respond_to?(:entityID) ? entity.entityID.to_i : 0
    "mh_pk_#{Time.now.to_f.to_s.gsub('.', '_')}_#{entity_id}_#{rand(1_000_000)}"
  rescue
    "mh_pk_#{Time.now.to_i}_#{rand(1_000_000)}"
  end

  def self.pk_side_drill_normal(entity)
    normal = entity.respond_to?(:transformation) ? entity.transformation.zaxis : Z_AXIS.clone
    normal = Z_AXIS.clone unless normal && normal.valid?
    normal.reverse!
    normal.length = 0.0586667
    normal
  rescue
    Geom::Vector3d.new(0, 0, -0.0586667)
  end

  def self.pk_marker_max_size
    4.0 / 25.4
  end

  class << self
    remove_method(:pk_marker_layer) if method_defined?(:pk_marker_layer)
  end

  def self.clamp_pk_marker_geometry(entity, max_size = pk_marker_max_size)
    return unless entity && max_size.to_f > 0

    defn = entity.respond_to?(:definition) ? entity.definition : nil
    ents = if entity.is_a?(Sketchup::Group)
             entity.entities
           elsif defn
             defn.entities
           end
    return unless ents

    bb = defn ? defn.bounds : entity.bounds
    dims = [bb.width.to_f, bb.depth.to_f, bb.height.to_f]
    current = dims.max
    return if current <= 0 || current <= max_size.to_f

    scale = max_size.to_f / current
    ents.transform_entities(Geom::Transformation.scaling(bb.center, scale), ents.to_a)
  rescue => e
    puts "clamp_pk_marker_geometry error: #{e.message}"
  end

  def self.wire_pk_marker_geometry(entity)
    defn = entity.respond_to?(:definition) ? entity.definition : nil
    ents = if entity.is_a?(Sketchup::Group)
             entity.entities
           elsif defn
             defn.entities
           end
    return unless ents

    ents.grep(Sketchup::Face).each { |face| face.erase! if face.valid? }
  rescue => e
    puts "wire_pk_marker_geometry error: #{e.message}"
  end

  def self.pk_marker_material(model = nil)
    model ||= Sketchup.active_model
    mat = model.materials["MH_PK"] || model.materials.add("MH_PK")
    mat.color = Sketchup::Color.new(0, 0, 0)
    mat
  rescue
    nil
  end

  def self.ensure_pk_marker_face_material(entity)
    defn = entity.respond_to?(:definition) ? entity.definition : nil
    ents = if entity.is_a?(Sketchup::Group)
             entity.entities
           elsif defn
             defn.entities
           end
    return unless ents

    edges = ents.grep(Sketchup::Edge)
    edges.each { |edge| edge.find_faces rescue nil } if ents.grep(Sketchup::Face).empty?
    mat = pk_marker_material
    ents.grep(Sketchup::Face).each do |face|
      face.material = mat if mat
      face.back_material = mat if mat
    end
    edges.each { |edge| edge.material = mat if mat && edge.respond_to?(:material=) }
  rescue => e
    puts "ensure_pk_marker_face_material error: #{e.message}"
  end

  def self.ensure_pk_marker_attributes(entity, display_name = nil, shape = nil)
    return nil unless entity

    name = display_name.to_s.strip
    name = entity.get_attribute("ABF", "statistical-name").to_s.strip if name.empty?
    name = entity.get_attribute("ABF", "setting-name").to_s.strip if name.empty?
    name = entity.get_attribute("MH_Thongke", "pk_name").to_s.strip if name.empty?
    name = entity.name.to_s.sub(/\APK\s+\w+\s*-\s*/i, "").strip if name.empty?
    name = "Phu kien" if name.empty?
    entity.name = name if entity.respond_to?(:name=)

    marker_shape = shape.to_s.strip
    marker_shape = entity.get_attribute("MH_Thongke", "pk_shape").to_s.strip if marker_shape.empty?
    
    # Khong xoa thuoc tinh lien ket khoan lo cua ABF va thuoc tinh thong ke ABF
    delete_attr_if_present(entity, "ZSU", "lien_ket")
    delete_attr_if_present(entity, "ZSU", "lien_ket_id")
    
    # Chi xoa cac thuoc tinh lien quan den tam van (nesting) de tranh xep van nham
    delete_attr_if_present(entity, "ABF", "is-board")
    delete_attr_if_present(entity, "ABF", "board-index")
    delete_attr_if_present(entity, "ABF", "is-user-nesting-obj")

    uid = entity.get_attribute("MH_Thongke", "pk_uid").to_s.strip
    uid = pk_unique_id(entity) if uid.empty?
    set_attr_if_needed(entity, "MH_Thongke", "generated_pk", "true")
    set_attr_if_needed(entity, "MH_Thongke", "exclude_from_nesting", "true")
    set_attr_if_needed(entity, "MH_Thongke", "pk_uid", uid)
    set_attr_if_needed(entity, "MH_Thongke", "pk_name", name)
    set_attr_if_needed(entity, "MH_Thongke", "pk_shape", marker_shape) unless marker_shape.empty?
    set_attr_if_needed(entity, "uni_tools", "temp_id", uid) if entity.get_attribute("uni_tools", "temp_id").to_s.empty?

    # Dam bao thuoc tinh thong ke ABF duoc thiet lap chinh xac tren instance de ABF Solutions nhan dien
    set_attr_if_needed(entity, "ABF", "is-statistical-object", "true")
    set_attr_if_needed(entity, "ABF", "statistical-name", name)
    set_attr_if_needed(entity, "ABF", "statistical-type", "hardware")
    set_attr_if_needed(entity, "ABF", "setting-name", name)
    set_attr_if_needed(entity, "ABF", "unit", "cai")

    # TUYET DOI KHONG xoa thuoc tinh ABF tren definition cua component de tranh pha huy thu vien ABF
    if entity.respond_to?(:definition) && entity.definition
      defn = entity.definition
      # Chi xoa ZSU lien_ket va MH_Thongke tren definition, khong dong vao ABF dictionary tren definition
      {
        "ZSU" => ["lien_ket", "lien_ket_id"],
        "MH_Thongke" => ["generated_pk", "exclude_from_nesting", "pk_uid", "pk_name", "pk_shape"]
      }.each do |dict, keys|
        keys.each { |key| delete_attr_if_present(defn, dict, key) }
      end
    end

    ensure_pk_marker_face_material(entity)
    clamp_pk_marker_geometry(entity)
    name
  rescue => e
    puts "ensure_pk_marker_attributes error: #{e.message}"
    display_name
  end

  def self.entity_bounds_thickness(entity, normal)
    bb = entity.respond_to?(:definition) ? entity.definition.bounds : entity.bounds
    tr = entity.respond_to?(:transformation) ? entity.transformation : Geom::Transformation.new
    vals = (0..7).map do |i|
      pt = bb.corner(i).transform(tr)
      pt.x * normal.x + pt.y * normal.y + pt.z * normal.z
    end
    vals.max - vals.min
  end

  def self.force_instance_flat_on_face(inst, face_tr)
    normal = face_tr.zaxis
    face_x = face_tr.xaxis
    face_y = face_tr.yaxis
    base_tr = inst.transformation
    center = inst.bounds.center
    step = Math::PI / 2

    rotations = [Geom::Transformation.new]
    [face_x, face_y, normal].each do |axis|
      [step, -step, Math::PI].each do |angle|
        rotations << Geom::Transformation.rotation(center, axis, angle)
      end
    end

    best = nil
    rotations.each do |rot|
      inst.transformation = rot * base_tr
      thick = entity_bounds_thickness(inst, normal)
      best = [thick, inst.transformation] if best.nil? || thick < best[0]
    end
    inst.transformation = best[1] if best
  rescue
  end

end
