# encoding: utf-8

require 'json'
require 'time'

module MH_PK_Addon
  DEFAULT_SIZE_MM = 4.0
  MIN_SIZE_MM = 0.5
  DEFAULT_SHAPE = 'square'.freeze
  DEFAULT_FACE_MODE = 'largest'.freeze
  ACCESSORY_DICT = 'MH_PK_Addon_Accessory'.freeze
  SHAPES = %w[square circle triangle].freeze
  FACE_MODES = %w[largest smallest].freeze
  FACE_MODE_LABELS = {
    'largest' => 'largest - mat lon nhat',
    'smallest' => 'smallest - mat nho nhat'
  }.freeze

  def self.model
    Sketchup.active_model
  end

  def self.live_selection(mdl = model)
    mdl.selection.to_a.select { |entity| live_entity?(entity) }
  rescue
    []
  end

  def self.restore_selection(mdl, entities)
    mdl.selection.clear
    valid = Array(entities).select { |entity| live_entity?(entity) }
    mdl.selection.add(valid) unless valid.empty?
  rescue
    nil
  end

  def self.thongke_api_call(method_name, *args)
    if defined?(MH::RegistryApp::Connector)
      result = MH::RegistryApp::Connector.call('thongke', method_name, *args)
      return result[:value] if result.is_a?(Hash) && result[:ok]
      return result['value'] if result.is_a?(Hash) && result['ok']
    end
    return MH_Thongke.send(method_name, *args) if defined?(MH_Thongke) && MH_Thongke.respond_to?(method_name)

    nil
  rescue => e
    puts "MH_PK_Addon Thongke API #{method_name} error: #{e.class}: #{e.message}" rescue nil
    nil
  end

  def self.mh_thongke_mini_visible?
    value = thongke_api_call(:mini_import_visible?)
    return !!value unless value.nil?

    false
  rescue
    false
  end

  def self.suspend_mh_thongke_mini_import
    return false unless defined?(MH_Thongke)

    api_result = thongke_api_call(:begin_external_mutation, 'MH_PK_Addon')
    return !!api_result unless api_result.nil?
    return MH_Thongke.pause_mini_import_refresh('MH_PK_Addon') if MH_Thongke.respond_to?(:pause_mini_import_refresh)

    false
  rescue => e
    puts "MH_PK_Addon pause Mini Import error: #{e.class}: #{e.message}" rescue nil
    false
  end

  def self.resume_mh_thongke_mini_import(was_visible)
    return unless defined?(MH_Thongke)

    api_result = thongke_api_call(:end_external_mutation, 'MH_PK_Addon', was_visible)
    return unless api_result.nil?
    MH_Thongke.resume_mini_import_refresh('MH_PK_Addon', was_visible) if MH_Thongke.respond_to?(:resume_mini_import_refresh)
  rescue => e
    puts "MH_PK_Addon resume Mini Import setup error: #{e.class}: #{e.message}" rescue nil
  end

  def self.with_mh_thongke_mini_suspended
    was_visible = suspend_mh_thongke_mini_import
    yield
  ensure
    resume_mh_thongke_mini_import(was_visible)
  end

  def self.html_escape(value)
    value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;').gsub("'", '&#39;')
  end

  def self.live_entity?(entity)
    entity && !(entity.respond_to?(:deleted?) && entity.deleted?)
  rescue
    false
  end

  def self.target_entities(entity)
    return nil unless live_entity?(entity)
    return entity.entities if entity.is_a?(Sketchup::Group)
    return entity.definition.entities if entity.is_a?(Sketchup::ComponentInstance) && entity.definition
    nil
  rescue
    nil
  end

  def self.pk_marker?(entity)
    return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

    entity.get_attribute('MH_PK_Addon', 'generated_pk').to_s == 'true' ||
      entity.get_attribute('MH_Thongke', 'generated_pk').to_s == 'true'
  rescue
    false
  end

  def self.find_parent_entity(target)
    return nil unless live_entity?(target)

    found = nil
    visited = {}
    walk = lambda do |ents, parent|
      return if found || !ents || visited[ents.object_id]
      visited[ents.object_id] = true

      ents.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        if entity.entityID == target.entityID
          found = parent
          return
        end

        child = target_entities(entity)
        walk.call(child, entity) if child
      end
    end
    walk.call(model.entities, nil)
    found
  rescue
    nil
  end

  def self.unique_id(entity = nil)
    entity_id = entity.respond_to?(:entityID) ? entity.entityID.to_i : 0
    "mh_pk_#{Time.now.to_f.to_s.gsub('.', '_')}_#{entity_id}_#{rand(1_000_000)}"
  rescue
    "mh_pk_#{Time.now.to_i}_#{rand(1_000_000)}"
  end

  def self.numeric_id
    rand(1_000_000..9_999_999)
  rescue
    Time.now.to_i
  end

  def self.selected_target
    mdl = model
    selected = mdl.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
    selected.each do |entity|
      next if pk_marker?(entity)
      return entity if target_entities(entity)
    end

    Array(mdl.active_path).reverse_each do |entity|
      next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      next if pk_marker?(entity)
      return entity if target_entities(entity)
    end
    nil
  rescue
    nil
  end

  def self.selected_targets
    mdl = model
    selected = mdl.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
    selected = selected.reject { |e| pk_marker?(e) }
    selected = selected.select { |e| !!target_entities(e) }
    return selected unless selected.empty?

    fallback = selected_target
    fallback ? [fallback] : []
  rescue
    []
  end

  def self.entity_world_transform(target)
    return Geom::Transformation.new unless target

    found = nil
    visited = {}
    finder = lambda do |ents, parent_tr|
      return if found || !ents
      ents.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        tr = parent_tr * entity.transformation
        if entity == target
          found = tr
          return
        end

        child = target_entities(entity)
        next unless child

        key = child.object_id
        next if visited[key]

        visited[key] = true
        finder.call(child, tr)
        return if found
      end
    end
    finder.call(model.entities, Geom::Transformation.new)
    found || (target.respond_to?(:transformation) ? target.transformation : Geom::Transformation.new)
  rescue
    Geom::Transformation.new
  end

  def self.normalize_transform_axes(tr)
    x_axis = tr.xaxis
    y_axis = tr.yaxis
    return tr if x_axis.length <= 0 || y_axis.length <= 0

    x_axis.length = 1.0
    y_axis.length = 1.0
    z_axis = x_axis.cross(y_axis)
    return tr if z_axis.length <= 0

    z_axis.length = 1.0
    y_axis = z_axis.cross(x_axis)
    y_axis.length = 1.0 if y_axis.length > 0
    Geom::Transformation.axes(tr.origin, x_axis, y_axis, z_axis)
  rescue
    tr
  end

  def self.unscaled_local_transform(local_tr, container_tr)
    world_tr = container_tr * local_tr
    world_unscaled = normalize_transform_axes(world_tr)
    container_tr.inverse * world_unscaled
  rescue
    local_tr
  end

  def self.next_abf_board_index(mdl = nil)
    mdl ||= model
    used = {}
    scan = lambda do |ents|
      ents.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        idx = entity.get_attribute('ABF', 'board-index').to_i
        used[idx] = true if idx > 0
        child = target_entities(entity)
        scan.call(child) if child
      end
    end
    scan.call(mdl.entities)
    idx = 1
    idx += 1 while used[idx]
    idx
  rescue
    1
  end

  def self.ensure_abf_board_attributes(entity)
    return nil unless entity && (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))

    idx = entity.get_attribute('ABF', 'board-index')
    idx = next_abf_board_index if idx.to_s.strip.empty? || idx.to_i <= 0
    entity.set_attribute('ABF', 'board-index', idx.to_i)
    entity.set_attribute('ABF', 'is-board', true)
    entity.set_attribute('ABF', 'label-rotation', entity.get_attribute('ABF', 'label-rotation') || 0)
    idx.to_i
  rescue
    nil
  end

  def self.target_status
    target = selected_target
    return { ok: false, text: 'Chua chon Group/Component dich.' } unless target

    ents = target_entities(target)
    world_tr = entity_world_transform(target)
    face = placement_face(ents, world_tr)
    name = target.name.to_s.strip
    name = target.definition.name.to_s.strip if name.empty? && target.respond_to?(:definition) && target.definition
    name = "Entity #{target.entityID}" if name.empty?
    mode_text = default_face_mode == 'largest' ? 'mat lon nhat' : 'mat nho nhat'
    {
      ok: !!face,
      text: face ? "Target: #{name} | #{mode_text}: #{face_area_for_placement(face, world_tr).round(4)} in2" : "Target: #{name} | khong co face truc tiep"
    }
  rescue => e
    { ok: false, text: "Loi target: #{e.message}" }
  end

  def self.faces_for_placement(entities)
    return [] unless entities

    entities.grep(Sketchup::Face).select { |face| face.valid? && (face.area rescue 0).to_f > 0.0 }
  rescue
    []
  end

  def self.face_area_for_placement(face, transform = nil)
    return 0.0 unless face && face.valid?

    area = transform ? (face.area(transform) rescue nil) : nil
    area = face.area rescue 0.0 if area.nil?
    area.to_f
  rescue
    0.0
  end

  def self.smallest_face(entities, transform = nil)
    faces_for_placement(entities).min_by { |face| face_area_for_placement(face, transform) }
  rescue
    nil
  end

  def self.largest_face(entities, transform = nil)
    faces_for_placement(entities).max_by { |face| face_area_for_placement(face, transform) }
  rescue
    nil
  end

  def self.placement_face(entities, transform = nil)
    default_face_mode == 'smallest' ? smallest_face(entities, transform) : largest_face(entities, transform)
  rescue
    largest_face(entities, transform) || smallest_face(entities, transform)
  end

  def self.face_transform(face)
    return nil unless face

    origin = face.bounds.center
    normal = face.normal
    edge = face.edges.max_by { |e| e.length rescue 0.0 }
    x_axis = edge ? edge.start.position.vector_to(edge.end.position) : normal.axes[0]
    x_axis = normal.axes[0] unless x_axis && x_axis.valid? && x_axis.length > 0
    x_axis.normalize!
    x_axis.reverse! if x_axis.x < 0 || (x_axis.x == 0 && x_axis.y < 0)
    y_axis = normal.cross(x_axis)
    y_axis = normal.axes[1] unless y_axis && y_axis.valid? && y_axis.length > 0
    y_axis.normalize!
    x_axis = y_axis.cross(normal)
    x_axis.normalize!
    Geom::Transformation.axes(origin, x_axis, y_axis, normal)
  rescue
    nil
  end

  def self.marker_size_inches(size_mm)
    mm = size_mm.to_f
    mm = DEFAULT_SIZE_MM if mm <= 0
    mm = [[mm, MIN_SIZE_MM].max, 50.0].min
    mm / 25.4
  end

  def self.face_local_bounds(face, face_tr)
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
    return nil unless entity.respond_to?(:bounds)

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

  def self.occupied_rects(entities, face_tr)
    entities.to_a.map do |entity|
      next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      next if entity.respond_to?(:deleted?) && entity.deleted?

      entity_face_rect(entity, face_tr)
    end.compact
  rescue
    []
  end

  def self.point_in_rect?(x, y, rect, pad)
    x >= rect[0] - pad && x <= rect[1] + pad &&
      y >= rect[2] - pad && y <= rect[3] + pad
  rescue
    false
  end

  def self.free_marker_transform(entities, face, face_tr, size_inch)
    bounds = face_local_bounds(face, face_tr)
    return face_tr unless bounds

    min_x, max_x, min_y, max_y = bounds
    width = max_x - min_x
    height = max_y - min_y
    return face_tr if width <= 0 || height <= 0

    pad = [size_inch * 0.75, 1.0 / 25.4].max
    usable_w = width - pad * 2.0
    usable_h = height - pad * 2.0
    usable_w = width if usable_w <= 0
    usable_h = height if usable_h <= 0

    occupied = occupied_rects(entities, face_tr)
    start = occupied.length
    start.upto([start + occupied.length + 120, 400].max) do |slot|
      total = [slot + 1, 1].max
      cols = Math.sqrt(total).ceil
      rows = (total.to_f / cols).ceil
      cell_w = usable_w / cols
      cell_h = usable_h / rows
      col = slot % cols
      row = slot / cols
      x = min_x + (width - usable_w) / 2.0 + cell_w * (col + 0.5)
      y = min_y + (height - usable_h) / 2.0 + cell_h * (row + 0.5)
      next if occupied.any? { |rect| point_in_rect?(x, y, rect, pad) }

      x_offset = face_tr.xaxis.clone
      x_offset.length = x.abs
      x_offset.reverse! if x < 0
      y_offset = face_tr.yaxis.clone
      y_offset.length = y.abs
      y_offset.reverse! if y < 0
      return Geom::Transformation.translation(x_offset + y_offset) * face_tr
    end

    face_tr
  rescue
    face_tr
  end

  def self.marker_points(shape, size)
    half = size.to_f / 2.0
    case shape.to_s
    when 'circle'
      segments = 24
      (0...segments).map do |i|
        angle = Math::PI * 2.0 * i / segments
        Geom::Point3d.new(Math.cos(angle) * half, Math.sin(angle) * half, 0)
      end
    when 'triangle'
      (0...3).map do |i|
        angle = Math::PI / 2.0 + Math::PI * 2.0 * i / 3.0
        Geom::Point3d.new(Math.cos(angle) * half, Math.sin(angle) * half, 0)
      end
    else
      [
        Geom::Point3d.new(-half, -half, 0),
        Geom::Point3d.new(half, -half, 0),
        Geom::Point3d.new(half, half, 0),
        Geom::Point3d.new(-half, half, 0)
      ]
    end
  end

  def self.marker_material
    mat = model.materials['MH_PK_Addon'] || model.materials.add('MH_PK_Addon')
    mat.color = Sketchup::Color.new(0, 0, 0)
    mat
  rescue
    nil
  end

  # Noi ten + spec thanh 1 doan (khong dau '-'); tranh lap spec khi ten da chua spec
  # (vd ten tu excel "den led - anh sang vang" + spec "anh sang vang").
  def self.display_name(name, spec)
    name_text = name.to_s.strip
    spec_text = spec.to_s.strip
    return 'Phu kien' if name_text.empty? && spec_text.empty?
    return name_text if spec_text.empty?
    return spec_text if name_text.empty?
    return name_text if search_text(name_text).include?(search_text(spec_text))

    "#{name_text} #{spec_text}"
  end

  def self.default_xlsx_path
    saved = settings_value('library_path', model.get_attribute(ACCESSORY_DICT, 'xlsx_path', '')).to_s
    return saved unless saved.strip.empty?

    bundled = File.join(ROOT_DIR, 'thu_vien_phu_kien.xlsx')
    File.file?(bundled) ? bundled : ''
  rescue
    ''
  end

  def self.save_xlsx_path(path)
    model.set_attribute(ACCESSORY_DICT, 'xlsx_path', path.to_s)
  rescue
    nil
  end

  def self.default_shape
    shape = settings_value('shape', model.get_attribute(ACCESSORY_DICT, 'shape', DEFAULT_SHAPE)).to_s
    SHAPES.include?(shape) ? shape : DEFAULT_SHAPE
  rescue
    DEFAULT_SHAPE
  end

  def self.default_size_mm
    size = settings_value('size_mm', model.get_attribute(ACCESSORY_DICT, 'size_mm', DEFAULT_SIZE_MM)).to_f
    size = DEFAULT_SIZE_MM if size <= 0
    [[size, MIN_SIZE_MM].max, 50.0].min
  rescue
    DEFAULT_SIZE_MM
  end

  def self.normalize_face_mode(value, fallback = DEFAULT_FACE_MODE)
    str = value.to_s.strip.downcase
    return 'largest' if str == 'largest' || str.include?('large') || str.include?('lon')
    return 'smallest' if str == 'smallest' || str.include?('small') || str.include?('nho')

    FACE_MODES.include?(fallback.to_s) ? fallback.to_s : DEFAULT_FACE_MODE
  rescue
    DEFAULT_FACE_MODE
  end

  def self.default_face_mode
    normalize_face_mode(settings_value('face_mode', model.get_attribute(ACCESSORY_DICT, 'face_mode', DEFAULT_FACE_MODE)))
  rescue
    DEFAULT_FACE_MODE
  end

  def self.face_mode_label(mode = default_face_mode)
    FACE_MODE_LABELS[normalize_face_mode(mode)] || FACE_MODE_LABELS[DEFAULT_FACE_MODE]
  rescue
    FACE_MODE_LABELS[DEFAULT_FACE_MODE]
  end

  def self.save_settings(path:, shape:, size_mm:, face_mode: nil)
    save_xlsx_path(path)
    model.set_attribute(ACCESSORY_DICT, 'shape', SHAPES.include?(shape.to_s) ? shape.to_s : DEFAULT_SHAPE)
    model.set_attribute(ACCESSORY_DICT, 'size_mm', size_mm.to_f)
    model.set_attribute(ACCESSORY_DICT, 'face_mode', normalize_face_mode(face_mode, default_face_mode))
  rescue
    nil
  end

  def self.ensure_settings_facade
    return true if defined?(MH::Settings)
    path = File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
    load path if File.exist?(path)
    defined?(MH::Settings)
  rescue
    false
  end

  def self.settings_value(key, fallback)
    return fallback unless ensure_settings_facade
    MH::Settings.read('pk_addon', key.to_s, fallback, scope: :global)
  rescue
    fallback
  end

  def self.refresh_abf_statistics
    return unless defined?(ABF)

    %i[process_selection refresh_statistics update_statistics update_html].each do |method_name|
      ABF.send(method_name) if ABF.respond_to?(method_name)
    end
  rescue
    nil
  end

  def self.read_accessories_from_csv(path)
    require 'csv'
    names = []
    CSV.foreach(path.to_s, headers: false) do |row|
      next unless row
      name = row[0].to_s.strip
      next if name.empty?
      names << name
    end
    names
  rescue
    []
  end

  def self.read_accessories_from_xlsx(path)
    return [] unless defined?(MH::ExcelBridge)

    rows = MH::ExcelBridge.read_sheet(path.to_s)
    Array(rows).filter_map do |row|
      name = Array(row)[0].to_s.strip
      name.empty? ? nil : name
    end
  rescue => e
    puts "MH_PK_Addon read xlsx error: #{e.class}: #{e.message}" rescue nil
    []
  end

  def self.accessory_names_from_file(path)
    return [] if path.to_s.strip.empty?
    return [] unless File.file?(path.to_s)

    ext = File.extname(path.to_s).downcase
    names =
      case ext
      when '.csv'
        read_accessories_from_csv(path)
      when '.xlsx'
        read_accessories_from_xlsx(path)
      when '.xls'
        puts "MH_PK_Addon: .xls is not supported. Please convert to .xlsx." rescue nil
        []
      else
        []
      end

    names.map { |n| n.to_s.strip }.reject(&:empty?).uniq
  rescue
    []
  end

  def self.create_marker_group(entities, transform, data)
    name = data[:name].to_s.strip
    spec = data[:spec].to_s.strip
    label = display_name(name, spec)
    shape = data[:shape].to_s.empty? ? 'square' : data[:shape].to_s
    size = marker_size_inches(data[:size_mm])

    group = entities.add_group
    group.name = label
    points = marker_points(shape, size)
    face = group.entities.add_face(points) rescue nil
    edges = face ? face.edges : points.each_with_index.map { |pt, idx| group.entities.add_line(pt, points[(idx + 1) % points.length]) }
    mat = marker_material
    if mat
      face.material = mat if face
      face.back_material = mat if face
      edges.each { |edge| edge.material = mat if edge.respond_to?(:material=) }
    end
    group.transformation = transform
    set_marker_attributes(group, data.merge(label: label, shape: shape))
    group
  end

  def self.convert_marker_faces_to_edges(entity)
    ents = target_entities(entity)
    return unless ents

    ents.grep(Sketchup::Face).each { |face| face.erase! if face.valid? }
  rescue
    nil
  end

  def self.ensure_marker_face(entity)
    ents = target_entities(entity)
    return unless ents
    return unless ents.grep(Sketchup::Face).empty?

    edges = ents.grep(Sketchup::Edge)
    points = edges.flat_map { |edge| [edge.start.position, edge.end.position] }
    unique = []
    points.each do |pt|
      unique << pt unless unique.any? { |old| old.distance(pt) < 0.0001 }
    end
    return if unique.length < 3

    center = Geom::Point3d.new(
      unique.map(&:x).sum / unique.length,
      unique.map(&:y).sum / unique.length,
      unique.map(&:z).sum / unique.length
    )
    xs = unique.map(&:x)
    ys = unique.map(&:y)
    zs = unique.map(&:z)
    spreads = [xs.max - xs.min, ys.max - ys.min, zs.max - zs.min]
    drop_axis = spreads.each_with_index.min[1]
    sorted = unique.sort_by do |pt|
      case drop_axis
      when 0 then Math.atan2(pt.z - center.z, pt.y - center.y)
      when 1 then Math.atan2(pt.z - center.z, pt.x - center.x)
      else Math.atan2(pt.y - center.y, pt.x - center.x)
      end
    end
    face = ents.add_face(sorted) rescue nil
    if face.nil?
      edges.each { |edge| edge.erase! if edge.valid? }
      xs = unique.map(&:x)
      ys = unique.map(&:y)
      zs = unique.map(&:z)
      case drop_axis
      when 0
        x = xs.sum / xs.length
        sorted = [
          Geom::Point3d.new(x, ys.min, zs.min),
          Geom::Point3d.new(x, ys.max, zs.min),
          Geom::Point3d.new(x, ys.max, zs.max),
          Geom::Point3d.new(x, ys.min, zs.max)
        ]
      when 1
        y = ys.sum / ys.length
        sorted = [
          Geom::Point3d.new(xs.min, y, zs.min),
          Geom::Point3d.new(xs.max, y, zs.min),
          Geom::Point3d.new(xs.max, y, zs.max),
          Geom::Point3d.new(xs.min, y, zs.max)
        ]
      else
        z = zs.sum / zs.length
        sorted = [
          Geom::Point3d.new(xs.min, ys.min, z),
          Geom::Point3d.new(xs.max, ys.min, z),
          Geom::Point3d.new(xs.max, ys.max, z),
          Geom::Point3d.new(xs.min, ys.max, z)
        ]
      end
      face = ents.add_face(sorted) rescue nil
    end
    mat = marker_material
    if face && mat
      face.material = mat
      face.back_material = mat
    end
  rescue
    nil
  end

  def self.delete_attr_if_present(entity, dict, key)
    return unless entity && entity.respond_to?(:delete_attribute)

    entity.delete_attribute(dict, key) if entity.get_attribute(dict, key)
  rescue
    nil
  end

  def self.remove_nesting_attrs(entity)
    # Chi xoa cac thuoc tinh lien quan den tam van (nesting) de tranh xep van nham
    # Khong xoa thuoc tinh thong ke phu kien va khong xoa thuoc tinh tren definition de bao ve thu vien ABF
    delete_attr_if_present(entity, 'ABF', 'is-board')
    delete_attr_if_present(entity, 'ABF', 'board-index')
    delete_attr_if_present(entity, 'ABF', 'is-user-nesting-obj')
    
    # Xoa cac thuoc tinh lien ket ZSU
    delete_attr_if_present(entity, 'ZSU', 'lien_ket')
    delete_attr_if_present(entity, 'ZSU', 'lien_ket_id')
  rescue
    nil
  end

  def self.set_marker_attributes(group, data)
    uid = unique_id(group)
    now = Time.now.strftime('%d/%m/%y %H:%M')
    label = data[:label].to_s.strip
    label = display_name(data[:name], data[:spec]) if label.empty?

    group.set_attribute('MH_PK_Addon', 'generated_pk', 'true')
    group.set_attribute('MH_PK_Addon', 'version', VERSION)
    group.set_attribute('MH_PK_Addon', 'pk_uid', uid)

    # Keep MH_Thongke nesting exclusion, but still write the ABF statistic attrs
    # required by the ABF statistics dialog.
    group.set_attribute('MH_Thongke', 'generated_pk', 'true')
    group.set_attribute('MH_Thongke', 'exclude_from_nesting', 'true')
    group.set_attribute('MH_Thongke', 'pk_uid', uid)
    group.set_attribute('MH_Thongke', 'pk_name', label)
    group.set_attribute('MH_Thongke', 'pk_base_name', data[:name].to_s.strip)
    group.set_attribute('MH_Thongke', 'pk_spec', data[:spec].to_s.strip)
    group.set_attribute('MH_Thongke', 'pk_shape', data[:shape].to_s)
    product_code = product_code_base(data[:product_code])
    group.set_attribute('MH_Thongke', 'product_code', product_code)
    group.set_attribute('MH_Thongke', 'actual_product', product_code)
    group.set_attribute('MH_Thongke', 'product', product_code)
    group.set_attribute('MH_Thongke', 'ma_sp', product_code)
    group.set_attribute('MH_Thongke', 'ten_sp', data[:ten_sp].to_s.strip)
    group.set_attribute('MH_Thongke', 'ghi_chu', data[:note].to_s.strip)
    group.set_attribute('MH_Thongke', 'ngay_dat', data[:order_date].to_s.strip)
    group.set_attribute('MH_Thongke', 'last_modified', now)
    group.set_attribute('uni_tools', 'temp_id', uid)

    remove_nesting_attrs(group)

    # Gan cac thuoc tinh thong ke ABF de ABF Solutions nhan dien thong ke phu kien
    group.set_attribute('ABF', 'is-statistical-object', true)
    group.set_attribute('ABF', 'statistical-name', label)
    group.set_attribute('ABF', 'statistical-type', 'hardware')
    group.set_attribute('ABF', 'setting-name', label)
    group.set_attribute('ABF', 'unit', 'cai')

    target_pid = data[:target_persistent_id].to_i
    if target_pid > 0
      group.set_attribute('ABF', 'face-drill-group-id', target_pid)
      group.set_attribute('ABF', 'is-side-drill', true)
    end

    ensure_marker_face(group)
  end

  def self.apply_abf_stat_attrs(entity, label, target = nil)
    return unless entity
    existing_target_pid = entity.get_attribute('ABF', 'face-drill-group-id').to_i rescue 0
    remove_nesting_attrs(entity)
    target_pid = existing_target_pid
    target_pid = target.persistent_id if target && target.respond_to?(:persistent_id)
    name = label.to_s.strip.empty? ? 'Phu kien' : label.to_s.strip
    entity.set_attribute('MH_Thongke', 'generated_pk', 'true') rescue nil
    entity.set_attribute('MH_Thongke', 'exclude_from_nesting', 'true') rescue nil
    entity.set_attribute('MH_Thongke', 'pk_name', name) rescue nil

    # Gan cac thuoc tinh thong ke ABF
    entity.set_attribute('ABF', 'is-statistical-object', true) rescue nil
    entity.set_attribute('ABF', 'statistical-name', name) rescue nil
    entity.set_attribute('ABF', 'statistical-type', 'hardware') rescue nil
    entity.set_attribute('ABF', 'setting-name', name) rescue nil
    entity.set_attribute('ABF', 'unit', 'cai') rescue nil

    if target_pid.to_i > 0
      entity.set_attribute('ABF', 'face-drill-group-id', target_pid.to_i) rescue nil
      entity.set_attribute('ABF', 'is-side-drill', true) rescue nil
    end
    ensure_marker_face(entity)
  rescue
    nil
  end

  def self.refresh_pk_product_attrs(entity, target = nil)
    return false unless entity

    read_attr = lambda do |obj, dict, key|
      obj ? obj.get_attribute(dict, key).to_s.strip : ''
    rescue
      ''
    end

    code = product_code_base(detect_product_code(target)) if target
    code = product_code_base(read_attr.call(entity, 'MH_Thongke', 'product_code')) if code.to_s.empty?
    code = product_code_base(read_attr.call(entity, 'MH_Thongke', 'actual_product')) if code.empty?
    code = product_code_base(read_attr.call(entity, 'MH_Thongke', 'product')) if code.empty?
    code = product_code_base(read_attr.call(entity, 'MH_Thongke', 'ma_sp')) if code.empty?

    ten_sp = ''
    ten_sp = product_name_from_excel(code) unless code.empty?
    ten_sp = read_attr.call(target, 'MH_Thongke', 'ten_sp') if ten_sp.empty? && target
    ten_sp = read_attr.call(entity, 'MH_Thongke', 'ten_sp') if ten_sp.empty?

    changed = false
    unless code.empty?
      %w[product_code actual_product product ma_sp].each do |key|
        if entity.get_attribute('MH_Thongke', key).to_s.strip != code
          entity.set_attribute('MH_Thongke', key, code)
          changed = true
        end
      end
    end

    unless ten_sp.empty?
      if entity.get_attribute('MH_Thongke', 'ten_sp').to_s.strip != ten_sp
        entity.set_attribute('MH_Thongke', 'ten_sp', ten_sp)
        changed = true
      end
    end

    entity.set_attribute('MH_Thongke', 'last_modified', Time.now.strftime('%d/%m/%y %H:%M')) if changed
    changed
  rescue
    false
  end

  def self.migrate_existing_pk_for_abf
    mdl = nil
    original_selection = []
    with_mh_thongke_mini_suspended do
      mdl = model
      original_selection = live_selection(mdl)
      all = []
      pk_parents = []
      pk_parent_by_entity_id = {}
      walk = lambda do |ents, parent|
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          all << e
          child = e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities
          walk.call(child, e) if child
          if parent && pk_marker?(e)
            pk_parents << parent
            pk_parent_by_entity_id[e.entityID] = parent
          end
        end
      end
      walk.call(mdl.entities, nil)

      migrated = 0
      mdl.start_operation('MH PK Exclude Nesting', true)
      all.each do |e|
        next unless pk_marker?(e)
        label = e.get_attribute('MH_Thongke', 'pk_name').to_s.strip
        label = e.name.to_s.strip if label.empty?
        label = 'Phu kien' if label.empty?
        apply_abf_stat_attrs(e, label, pk_parent_by_entity_id[e.entityID])
        refresh_pk_product_attrs(e, pk_parent_by_entity_id[e.entityID])
        migrated += 1
      end
      pk_parents.compact.uniq.each { |parent| ensure_abf_board_attributes(parent) }
      mdl.commit_operation
      restore_selection(mdl, original_selection)
      refresh_abf_statistics
      migrated
    end
  rescue => e
    mdl.abort_operation rescue nil
    restore_selection(mdl, original_selection) rescue nil
    raise e
  end

  def self.fix_lost_abf_statistics
    migrate_existing_pk_for_abf
  end

  def self.register_selected_as_pk_statistics
    mdl = nil
    selected = []
    with_mh_thongke_mini_suspended do
      mdl = model
      selected = live_selection(mdl).select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      return 0 if selected.empty?

      count = 0
      mdl.start_operation('MH PK Register Selected', true)
      selected.each do |entity|
        next unless live_entity?(entity)

        parent = find_parent_entity(entity)
        label = accessory_label(entity)
        label = entity.name.to_s.strip if label.empty?
        label = entity.definition.name.to_s.strip if label.empty? && entity.respond_to?(:definition) && entity.definition
        label = 'Phu kien' if label.empty?

        entity.set_attribute('MH_PK_Addon', 'generated_pk', 'true')
        entity.set_attribute('MH_PK_Addon', 'version', VERSION)
        entity.set_attribute('MH_PK_Addon', 'pk_uid', unique_id(entity)) if entity.get_attribute('MH_PK_Addon', 'pk_uid').to_s.strip.empty?

        apply_abf_stat_attrs(entity, label, parent)
        refresh_pk_product_attrs(entity, parent)
        ensure_abf_board_attributes(parent) if parent
        count += 1
      end
      mdl.commit_operation
      refresh_abf_statistics
      count
    end
  rescue => e
    mdl.abort_operation rescue nil
    raise e
  end

  ZSU_NAME_KEYS = %w[name ten ten_pk setting-name].freeze

  def self.zsu_name(entity)
    ZSU_NAME_KEYS.each do |key|
      value = entity.get_attribute('ZSU', key).to_s.strip rescue ''
      return value unless value.empty?
    end
    ''
  rescue
    ''
  end

  def self.accessory_label(entity)
    manual = manual_label_override(entity)
    return manual unless manual.empty?

    value = entity.get_attribute('ABF', 'setting-name').to_s.strip rescue ''
    value = entity.get_attribute('ABF', 'statistical-name').to_s.strip if value.empty?
    value = zsu_name(entity) if value.empty?
    value = entity.get_attribute('MH_Thongke', 'pk_name').to_s.strip if value.empty?
    value = entity.get_attribute('MH_PK_Addon', 'pk_name').to_s.strip if value.empty?
    value = entity.name.to_s.strip if value.empty?
    if value.empty? && entity.respond_to?(:definition) && entity.definition
      value = entity.definition.name.to_s.strip
    end
    value.empty? ? 'Phu kien' : value
  rescue
    'Phu kien'
  end

  def self.manual_label_override(entity)
    return '' unless entity

    value = entity.get_attribute('MH_PK_Addon', 'manual_label_name').to_s.strip rescue ''
    value = entity.get_attribute('MH_Thongke', 'manual_label_name').to_s.strip if value.empty?
    value
  rescue
    ''
  end

  def self.set_manual_label_override(entity, label)
    name = label.to_s.strip
    return if name.empty? || !entity

    entity.set_attribute('MH_PK_Addon', 'manual_label', 'true') rescue nil
    entity.set_attribute('MH_PK_Addon', 'manual_label_name', name) rescue nil
    entity.set_attribute('MH_Thongke', 'manual_label', 'true') rescue nil
    entity.set_attribute('MH_Thongke', 'manual_label_name', name) rescue nil
    entity.set_attribute('MH_Thongke', 'current-name', name) rescue nil
  rescue
    nil
  end

  def self.restore_manual_label_attrs(entity)
    name = manual_label_override(entity)
    return false if name.empty?

    entity.name = name if pk_marker?(entity) rescue nil
    entity.set_attribute('MH_Thongke', 'pk_name', name) rescue nil
    entity.set_attribute('MH_Thongke', 'current-name', name) rescue nil
    entity.set_attribute('ABF', 'setting-name', name) rescue nil
    entity.set_attribute('ABF', 'statistical-name', name) rescue nil
    entity.set_attribute('ZSU', 'name', name) rescue nil
    unless entity.get_attribute('ZSU_LED', 'ten_hien_thi').to_s.strip.empty?
      entity.set_attribute('ZSU_LED', 'ten_hien_thi', name) rescue nil
    end
    true
  rescue
    false
  end

  def self.restore_manual_label_overrides
    changed = 0
    visited = {}
    walk = lambda do |ents|
      key = ents.object_id
      return if visited[key]

      visited[key] = true
      ents.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        changed += 1 if restore_manual_label_attrs(entity)
        child = target_entities(entity)
        walk.call(child) if child
      end
    end
    walk.call(model.entities)
    changed
  rescue
    0
  end

  def self.exclude_selected_accessories_from_nesting
    mdl = nil
    selected = []
    with_mh_thongke_mini_suspended do
      mdl = model
      selected = live_selection(mdl).select do |entity|
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end
      raise 'Chon phu kien can bo nesting truoc.' if selected.empty?

      changed = 0
      mdl.start_operation('MH PK Exclude Selected Nesting', true)
      selected.each do |entity|
        label = accessory_label(entity)
        parent = find_parent_entity(entity)
        ensure_abf_board_attributes(parent) if parent
        apply_abf_stat_attrs(entity, label, parent)
        changed += 1
      end
      mdl.commit_operation
      restore_selection(mdl, selected)
      refresh_abf_statistics
      changed
    end
  rescue => e
    mdl.abort_operation rescue nil
    restore_selection(mdl, selected) rescue nil
    raise e
  end

  def self.detect_product_code(entity)
    candidates = []
    product_keys = %w[actual_product product product_code ma_sp productCode product-code sp maSP ma_sp_code]
    %w[MH_Thongke MH_PK_Addon ABF ZSU DynamicAttributes dynamic_attributes].each do |dict|
      product_keys.each { |key| candidates << entity.get_attribute(dict, key) rescue nil }
    end
    candidates.concat(attribute_values_with_product_code(entity))
    candidates << entity.name.to_s
    if entity.respond_to?(:definition) && entity.definition
      %w[MH_Thongke MH_PK_Addon ABF ZSU DynamicAttributes dynamic_attributes].each do |dict|
        product_keys.each { |key| candidates << entity.definition.get_attribute(dict, key) rescue nil }
      end
      candidates.concat(attribute_values_with_product_code(entity.definition))
      candidates << entity.definition.name.to_s
    end
    candidates.each do |value|
      str = value.to_s.strip.upcase
      next if str.empty?
      code = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
        MH::NameGrammar.first_product(str)
      else
        str[/([A-Z]+\d+[A-Z]?(?:\.\d+)?)/i, 1]
      end
      return normalize_product_code(code) unless code.to_s.empty?
    end
    ''
  rescue
    ''
  end

  def self.attribute_values_with_product_code(entity)
    values = []
    dictionaries = entity.respond_to?(:attribute_dictionaries) ? entity.attribute_dictionaries : nil
    return values unless dictionaries

    dictionaries.each do |dict|
      next unless dict
      dict.each_pair do |_key, value|
        text = value.to_s
        has_code = if defined?(MH::NameGrammar) && MH::NameGrammar.respond_to?(:first_product)
          !MH::NameGrammar.first_product(text).to_s.empty?
        else
          !!(text =~ /[A-Z]+\d+[A-Z]?(?:\.\d+)?/i)
        end
        values << text if has_code
      end
    end
    values
  rescue
    []
  end

  def self.normalize_product_code(value)
    if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:exact)
      MH::ProductContext.exact(value)
    else
      value.to_s.strip.upcase
    end
  end

  def self.product_code_base(value)
    if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:base)
      MH::ProductContext.base(value)
    else
      normalize_product_code(value).split('.').first.to_s
    end
  end

  def self.product_code_match?(value, target)
    value_exact = normalize_product_code(value)
    target_exact = normalize_product_code(target)
    return false if value_exact.empty? || target_exact.empty?

    value_exact == target_exact || product_code_base(value_exact) == product_code_base(target_exact)
  end

  def self.detect_ten_sp(entity)
    code = detect_product_code(entity)
    unless code.to_s.strip.empty?
      resolved = product_name_from_excel(code)
      return resolved unless resolved.to_s.strip.empty?
    end

    entity.get_attribute('MH_Thongke', 'ten_sp').to_s.strip
  rescue
    ''
  end

  def self.product_name_from_excel(product_code)
    code = product_code_base(product_code)
    return '' if code.empty?

    if defined?(MH_Thongke) && MH_Thongke.respond_to?(:import_excel_product_name_for)
      name = MH_Thongke.import_excel_product_name_for(code, true).to_s.strip
      return name unless name.empty?
    end

    rows = []
    rows.concat(thongke_excel_rows_from_loaded_module(code)) rescue nil
    thongke_excel_cache_sources.each { |source_rows| rows.concat(Array(source_rows)) } rescue nil
    rows.each do |row|
      next unless row.is_a?(Hash)
      row_code = row_value(row, :ma_sp, 'ma_sp', :actual_product, 'actual_product', :product, 'product')
      next unless product_code_match?(row_code, code)

      name = row_value(row, :ten_sp, 'ten_sp').to_s.strip
      return name unless name.empty?
    end
    ''
  rescue
    ''
  end

  def self.normalized_data(hash)
    data = {}
    (hash || {}).each { |k, v| data[k.to_s.to_sym] = v }
    data[:qty] = data[:qty].to_i
    data[:qty] = 1 if data[:qty] <= 0
    data[:size_mm] = data[:size_mm].to_f
    data[:size_mm] = default_size_mm if data[:size_mm] <= 0
    data[:name] = data[:name].to_s.strip
    data[:name] = 'Phu kien' if data[:name].empty?
    data[:shape] = data[:shape].to_s
    data[:shape] = default_shape unless SHAPES.include?(data[:shape])
    data[:spec] = data[:spec].to_s.strip
    data[:product_code] = product_code_base(data[:product_code])
    data[:ten_sp] = data[:ten_sp].to_s.strip
    data[:ten_sp] = product_name_from_excel(data[:product_code]) if data[:ten_sp].empty? && !data[:product_code].empty?
    data[:note] = data[:note].to_s.strip
    data[:order_date] = data[:order_date].to_s.strip
    data
  end

  def self.qty_for_suggestion(row)
    type = (row['type'] || row[:type]).to_s
    count = (row['count'] || row[:count]).to_f
    return count.round if count > 0

    qty = (row['qty'] || row[:qty]).to_f
    return qty.round if qty > 0 && type != 'length'

    length_items = row['length_items'] || row[:length_items]
    length_count = Array(length_items).length
    return length_count if length_count > 0

    1
  rescue
    1
  end

  def self.suggestion_name(row)
    name = (row['name'] || row[:name] || row['hw_name'] || row[:hw_name]).to_s.strip
    spec = (row['spec'] || row[:spec]).to_s.strip
    if (row['hw_name'] || row[:hw_name]) && !spec.empty? && !name.downcase.include?(spec.downcase)
      name = [name, spec].reject(&:empty?).join(' ')
    end
    name.empty? ? 'Phu kien' : name
  end

  def self.suggestion_note(row)
    (row['ghi_chu'] || row[:ghi_chu] || row['note'] || row[:note]).to_s.strip
  rescue
    ''
  end

  def self.row_value(row, *keys)
    return nil unless row.is_a?(Hash)

    keys.each do |key|
      return row[key] if row.key?(key)
      sym = key.to_s.to_sym
      return row[sym] if row.key?(sym)
      str = key.to_s
      return row[str] if row.key?(str)
    end
    nil
  rescue
    nil
  end

  def self.thongke_status_key(value)
    if defined?(MH_Thongke) && MH_Thongke.respond_to?(:status_key)
      return MH_Thongke.status_key(value).to_s
    end

    value.to_s.strip.upcase.gsub(/\s+/, '_')
  rescue
    value.to_s.strip.upcase
  end

  def self.thongke_visible_spec_status?(value)
    key = thongke_status_key(value)
    key == 'SPEC' || key == 'THIEU'
  rescue
    false
  end

  def self.row_explicit_status(row)
    row_value(row, :trang_thai, 'trang_thai', :trangthai, 'trangthai', :status, 'status',
              :state, 'state', :tinh_trang, 'tinh_trang', :spec_status, 'spec_status',
              :spec_state, 'spec_state')
  rescue
    nil
  end

  def self.pk_excel_row?(row)
    kind = row_value(row, :kind, 'kind').to_s.strip.upcase
    return false if kind == 'VL'
    return true if kind == 'PK'

    !suggestion_name(row).to_s.strip.empty?
  rescue
    false
  end

  def self.thongke_model_item_key(item)
    if defined?(MH_Thongke) && MH_Thongke.respond_to?(:mini_model_item_key)
      return MH_Thongke.mini_model_item_key(item)
    end

    kind = (item[:kind] || item['kind']).to_s
    name = (item[:name] || item['name']).to_s.downcase
    "#{kind}:#{name}"
  rescue
    item.object_id.to_s
  end

  def self.thongke_excel_item_target_name(row)
    return '' unless row.is_a?(Hash)

    if defined?(MH_Thongke) && MH_Thongke.respond_to?(:pk_update_target_name)
      return MH_Thongke.pk_update_target_name(row, nil).to_s
    end

    suggestion_name(row)
  rescue
    suggestion_name(row)
  end

  def self.thongke_spec_pk_rows_from_excel_rows(product_code, excel_rows)
    return [] unless defined?(MH_Thongke)

    code = normalize_product_code(product_code)
    return [] if code.empty?

    excel_rows = Array(excel_rows).select do |row|
      row.is_a?(Hash) &&
        pk_excel_row?(row) &&
        product_code_match?(row_value(row, :ma_sp, 'ma_sp', :actual_product, 'actual_product', :product, 'product'), code)
    end
    excel_rows = excel_rows.select { |row| row.is_a?(Hash) && pk_excel_row?(row) }
    excel_rows = Array(MH_Thongke.mini_group_excel_items(excel_rows, true)) if MH_Thongke.respond_to?(:mini_group_excel_items)

    model_items =
      if MH_Thongke.respond_to?(:mini_pk_grouped_model_items)
        Array(MH_Thongke.mini_pk_grouped_model_items(code))
      else
        []
      end

    matched_model_keys = []
    rows = []
    excel_rows.each do |row|
      model = nil
      duplicate_used = false
      target_name = thongke_excel_item_target_name(row)

      if MH_Thongke.respond_to?(:mini_pk_prepare_excel_item) && MH_Thongke.respond_to?(:mini_pk_match_model_item)
        item = MH_Thongke.mini_pk_prepare_excel_item(row)
        model, target_name, duplicate_used = MH_Thongke.mini_pk_match_model_item(code, model_items, item, matched_model_keys)
        has_qty = model && ((model[:qty] || model['qty']).to_f > 0 || (model[:count] || model['count']).to_f > 0)
        ids = model ? Array(model[:ids] || model['ids']) : []
        model = nil if model && ids.empty? && !model[:virtual] && !model['virtual'] && !has_qty
        next if duplicate_used && !model
      end

      if model
        key = thongke_model_item_key(model)
        matched_model_keys << key unless matched_model_keys.include?(key)
        next
      end

      status =
        if MH_Thongke.respond_to?(:resolve_mini_excel_only_status_key)
          MH_Thongke.resolve_mini_excel_only_status_key(code, 'PK', false, row_value(row, :hw_name, 'hw_name').to_s, row_value(row, :spec, 'spec').to_s)
        else
          'SPEC'
        end
      next unless thongke_visible_spec_status?(status)

      name = suggestion_name(row)
      rows << {
        name: name,
        suggestion_name: name,
        qty: qty_for_suggestion(row),
        note: suggestion_note(row),
        ten_sp: row_value(row, :ten_sp, 'ten_sp').to_s.strip,
        product_code: normalize_product_code(row_value(row, :ma_sp, 'ma_sp', :actual_product, 'actual_product', :product, 'product') || code),
        status: thongke_status_key(status),
        target_name: target_name.to_s,
        raw: row
      }
    end
    rows.sort_by { |row| row[:name].to_s.downcase }
  rescue => e
    puts "MH_PK_Addon SPEC PK source error: #{e.message}" rescue nil
    []
  end

  def self.thongke_live_spec_pk_rows(product_code)
    return [] unless defined?(MH_Thongke)

    code = normalize_product_code(product_code)
    return [] if code.empty?

    sources = []
    if MH_Thongke.respond_to?(:mini_excel_items)
      sources << Array(MH_Thongke.mini_excel_items(code, false))
      sources << Array(MH_Thongke.mini_excel_items(code, true))
    else
      sources << thongke_excel_rows_from_loaded_module(code)
    end
    sources << thongke_excel_rows_from_loaded_module(code)
    thongke_excel_cache_sources.each { |rows| sources << rows }

    sources.each do |source_rows|
      rows = thongke_spec_pk_rows_from_excel_rows(code, source_rows)
      return rows unless rows.empty?
    end
    []
  rescue => e
    puts "MH_PK_Addon SPEC PK rows error: #{e.message}" rescue nil
    []
  end

  def self.thongke_explicit_status_spec_pk_rows(product_code)
    sources = []
    loaded_excel_rows = thongke_excel_rows_from_loaded_module(product_code)
    sources << loaded_excel_rows unless loaded_excel_rows.empty?
    thongke_excel_cache_sources.each { |rows| sources << rows unless rows.empty? }
    loaded_rows = thongke_rows_from_loaded_module
    sources << loaded_rows unless loaded_rows.empty?

    sources.each do |rows|
      filtered = Array(rows).select do |row|
        next false unless row.is_a?(Hash)
        row_product = row_value(row, :actual_product, 'actual_product', :product, 'product', :ma_sp, 'ma_sp')
        product_code_match?(row_product, product_code) && pk_excel_row?(row) && thongke_visible_spec_status?(row_explicit_status(row))
      end
      suggestions = build_suggestions_from_rows(product_code, filtered)
      return suggestions unless suggestions.empty?
    end
    []
  rescue
    []
  end

  def self.thongke_spec_suggestion_rows(product_code)
    rows = thongke_live_spec_pk_rows(product_code)
    rows = thongke_live_spec_pk_rows(product_code) if rows.empty?
    return rows unless rows.empty?

    rows = thongke_explicit_status_spec_pk_rows(product_code)
    return rows unless rows.empty?

    project_data_pk_suggestion_rows(product_code)
  rescue
    []
  end

  def self.project_data_pk_suggestion_rows(product_code)
    return [] unless defined?(MH::ProjectData) && MH::ProjectData.respond_to?(:rows_for_product)

    MH::ProjectData.ensure_loaded if MH::ProjectData.respond_to?(:ensure_loaded)
    source_rows = Array(MH::ProjectData.rows_for_product(product_code))
    filtered = source_rows.select { |row| row.is_a?(Hash) && pk_excel_row?(row) }
    build_suggestions_from_rows(product_code, filtered)
  rescue => e
    puts "MH_PK_Addon ProjectData PK rows error: #{e.message}" rescue nil
    []
  end

  def self.search_text(value)
    text = value.to_s.downcase
    map = {
      'à' => 'a', 'á' => 'a', 'ạ' => 'a', 'ả' => 'a', 'ã' => 'a',
      'â' => 'a', 'ầ' => 'a', 'ấ' => 'a', 'ậ' => 'a', 'ẩ' => 'a', 'ẫ' => 'a',
      'ă' => 'a', 'ằ' => 'a', 'ắ' => 'a', 'ặ' => 'a', 'ẳ' => 'a', 'ẵ' => 'a',
      'è' => 'e', 'é' => 'e', 'ẹ' => 'e', 'ẻ' => 'e', 'ẽ' => 'e',
      'ê' => 'e', 'ề' => 'e', 'ế' => 'e', 'ệ' => 'e', 'ể' => 'e', 'ễ' => 'e',
      'ì' => 'i', 'í' => 'i', 'ị' => 'i', 'ỉ' => 'i', 'ĩ' => 'i',
      'ò' => 'o', 'ó' => 'o', 'ọ' => 'o', 'ỏ' => 'o', 'õ' => 'o',
      'ô' => 'o', 'ồ' => 'o', 'ố' => 'o', 'ộ' => 'o', 'ổ' => 'o', 'ỗ' => 'o',
      'ơ' => 'o', 'ờ' => 'o', 'ớ' => 'o', 'ợ' => 'o', 'ở' => 'o', 'ỡ' => 'o',
      'ù' => 'u', 'ú' => 'u', 'ụ' => 'u', 'ủ' => 'u', 'ũ' => 'u',
      'ư' => 'u', 'ừ' => 'u', 'ứ' => 'u', 'ự' => 'u', 'ử' => 'u', 'ữ' => 'u',
      'ỳ' => 'y', 'ý' => 'y', 'ỵ' => 'y', 'ỷ' => 'y', 'ỹ' => 'y',
      'đ' => 'd'
    }
    text.each_char.map { |char| map[char] || char }.join
  rescue
    value.to_s.downcase
  end

  def self.accessory_target_keywords(name)
    text = search_text(name)
    return ['canh'] if text.include?('tay nam')
    return ['hong'] if text.include?('cam bien')
    return %w[mat noc] if %w[dem vai ni da].any? { |word| text.include?(word) }

    ['day']
  rescue
    ['day']
  end

  def self.entity_search_name(entity)
    parts = []
    parts << entity.name.to_s if entity.respond_to?(:name)
    parts << entity.definition.name.to_s if entity.respond_to?(:definition) && entity.definition
    search_text(parts.join(' '))
  rescue
    ''
  end

  def self.child_targets_for_routing(roots)
    found = []
    visited = {}
    walk = lambda do |entity|
      ents = target_entities(entity)
      return unless ents

      ents.each do |child|
        next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
        next if pk_marker?(child)
        next unless target_entities(child)
        next if visited[child.object_id]

        visited[child.object_id] = true
        found << child
        walk.call(child)
      end
    end
    Array(roots).each { |root| walk.call(root) }
    found
  rescue
    []
  end

  def self.routed_targets_for_accessory(data)
    roots = selected_targets
    return [] if roots.empty?

    keywords = accessory_target_keywords(data[:name])
    candidates = child_targets_for_routing(roots)
    candidates = roots if candidates.empty?
    matched = candidates.select do |entity|
      name = entity_search_name(entity)
      keywords.any? { |keyword| name.include?(keyword) }
    end
    matched.empty? ? roots : matched
  rescue
    selected_targets
  end

  def self.distribute_qty(total_qty, targets)
    qty = total_qty.to_i
    qty = 1 if qty <= 0
    list = Array(targets).select { |target| live_entity?(target) }
    return [] if list.empty?

    base = qty / list.length
    remain = qty % list.length
    list.each_with_index.map do |target, index|
      target_qty = base + (index < remain ? 1 : 0)
      next if target_qty <= 0

      [target, target_qty]
    end.compact
  rescue
    []
  end

  def self.thongke_rows_from_loaded_module
    return [] unless defined?(MH_Thongke)

    snapshot = thongke_api_call(:report_snapshot, false)
    rows = []
    if snapshot.is_a?(Hash)
      rows.concat(Array(snapshot['accessories']))
      rows.concat(Array(snapshot[:accessories]))
    end
    rows.select { |row| row.is_a?(Hash) }
  rescue
    []
  end

  def self.thongke_excel_rows_from_loaded_module(product_code = nil)
    return [] unless defined?(MH_Thongke)

    rows = thongke_api_call(:import_excel_data, product_code)
    rows = thongke_api_call(:import_excel_data_snapshot, product_code) if rows.nil?
    Array(rows).select { |row| row.is_a?(Hash) }
  rescue
    []
  end

  def self.thongke_rows_from_excel_cache(_path = nil)
    thongke_excel_cache_sources.flatten
  rescue
    []
  end

  def self.thongke_excel_cache_sources(_path = nil)
    sources = thongke_api_call(:import_excel_cache_sources)
    Array(sources).map { |rows| Array(rows).select { |row| row.is_a?(Hash) } }.reject(&:empty?)
  rescue => e
    puts "MH_PK_Addon Thongke Excel cache API error: #{e.message}" rescue nil
    []
  end

  def self.build_suggestions_from_rows(product_code, rows)
    code = normalize_product_code(product_code)
    return [] if code.empty?

    grouped = {}
    Array(rows).each do |row|
      row_product = row['actual_product'] || row[:actual_product] || row['product'] || row[:product] || row['ma_sp'] || row[:ma_sp]
      next unless product_code_match?(row_product, code)
      next if row['is_missing'] == true || row[:is_missing] == true
      kind = (row['kind'] || row[:kind]).to_s.strip.upcase
      next if kind == 'VL'

      name = suggestion_name(row)
      qty = qty_for_suggestion(row).to_i
      qty = 1 if qty <= 0
      ten_sp = (row['ten_sp'] || row[:ten_sp]).to_s.strip
      note = suggestion_note(row)
      key = [name.downcase, note.downcase].join('|')
      item = grouped[key] ||= {
        name: name,
        suggestion_name: name,
        qty: 0,
        note: note,
        ten_sp: ten_sp,
        product_code: normalize_product_code(row_product)
      }
      item[:qty] += qty
      item[:ten_sp] = ten_sp if item[:ten_sp].to_s.empty? && !ten_sp.empty?
      item[:product_code] = normalize_product_code(row_product) if item[:product_code].to_s.empty?
    end
    grouped.values.sort_by { |item| [item[:name].to_s.downcase, item[:note].to_s.downcase] }
  rescue
    []
  end

  def self.build_excel_pk_rows_for_dropdown(product_code, rows)
    code = normalize_product_code(product_code)
    return [] if code.empty?

    Array(rows).each_with_index.filter_map do |row, index|
      next unless row.is_a?(Hash)
      row_product = row_value(row, :actual_product, 'actual_product', :product, 'product', :ma_sp, 'ma_sp')
      next unless product_code_match?(row_product, code)
      next unless pk_excel_row?(row)

      name = suggestion_name(row)
      next if name.to_s.strip.empty?

      {
        name: name,
        suggestion_name: name,
        qty: qty_for_suggestion(row),
        note: suggestion_note(row),
        ten_sp: row_value(row, :ten_sp, 'ten_sp').to_s.strip,
        product_code: normalize_product_code(row_product),
        spec: row_value(row, :spec, 'spec').to_s.strip,
        status: row_explicit_status(row),
        source_index: index,
        raw: row
      }
    end
  rescue
    []
  end

  def self.thongke_all_excel_pk_rows(product_code)
    code = normalize_product_code(product_code)
    return [] if code.empty?

    loaded = build_excel_pk_rows_for_dropdown(code, thongke_excel_rows_from_loaded_module(code))
    return loaded unless loaded.empty?

    thongke_excel_cache_sources.each do |rows|
      built = build_excel_pk_rows_for_dropdown(code, rows)
      return built unless built.empty?
    end

    thongke_suggestion_rows(code)
  rescue
    []
  end

  def self.thongke_suggestion_rows(product_code)
    sources = []
    loaded_excel_rows = thongke_excel_rows_from_loaded_module(product_code)
    sources << loaded_excel_rows unless loaded_excel_rows.empty?

    thongke_excel_cache_sources.each { |rows| sources << rows unless rows.empty? }

    loaded_rows = thongke_rows_from_loaded_module
    sources << loaded_rows unless loaded_rows.empty?

    sources.each do |rows|
      suggestions = build_suggestions_from_rows(product_code, rows)
      return suggestions unless suggestions.empty?
    end
    []
  rescue
    []
  end

  def self.pk_suggestion_context
    target = selected_target
    return { ok: false, text: 'Chua chon Group/Component dich.', product_code: '', ten_sp: '', rows: [] } unless target

    status = target_status
    return status.merge(product_code: '', ten_sp: '', rows: []) unless status[:ok]

    product_code = detect_product_code(target)
    ten_sp = detect_ten_sp(target)
    rows = thongke_spec_suggestion_rows(product_code)
    {
      ok: true,
      text: status[:text],
      product_code: product_code,
      ten_sp: ten_sp,
      rows: rows
    }
  rescue => e
    { ok: false, text: "Loi goi y PK: #{e.message}", product_code: '', ten_sp: '', rows: [] }
  end

  def self.add_accessory(raw_data)
    mdl = nil
    original_selection = []
    with_mh_thongke_mini_suspended do
      data = normalized_data(raw_data)
      mdl = model
      original_selection = live_selection(mdl)
      target = selected_target
      raise 'Chon Group/Component dich truoc khi add PK.' unless target

      target.make_unique if target.is_a?(Sketchup::ComponentInstance) && target.respond_to?(:make_unique)
      ensure_abf_board_attributes(target)
      ents = target_entities(target)
      raise 'Object dich khong co entities hop le.' unless ents

      world_tr = entity_world_transform(target)
      face = placement_face(ents, world_tr)
      raise 'Object dich khong co face truc tiep de gan PK.' unless face

      face_tr = face_transform(face)
      raise 'Khong tinh duoc mat gan PK.' unless face_tr

      added = []
      data[:face_normal] = face.normal.to_s
      data[:target_persistent_id] = target.persistent_id rescue nil
      mdl.start_operation('MH PK Add', true)
      data[:qty].times do
        size = marker_size_inches(data[:size_mm])
        transform = free_marker_transform(ents, face, face_tr, size)
        transform = unscaled_local_transform(transform, world_tr)
        added << create_marker_group(ents, transform, data)
      end
      mdl.commit_operation
      restore_selection(mdl, original_selection)
      refresh_abf_statistics
      { count: added.length, target: target.name.to_s.empty? ? "Entity #{target.entityID}" : target.name.to_s }
    end
  rescue => e
    model.abort_operation rescue nil
    restore_selection(mdl, original_selection) rescue nil
    raise e
  end

  def self.add_accessory_to_selection(raw_data)
    mdl = nil
    original_selection = []
    with_mh_thongke_mini_suspended do
      data = normalized_data(raw_data)
      mdl = model
      original_selection = live_selection(mdl)
      targets = selected_targets
      raise 'Chon Group/Component dich truoc khi add PK.' if targets.empty?

      added = []
      affected = []

      mdl.start_operation('MH PK Add Multi', true)
      targets.each do |target|
        world_tr = entity_world_transform(target)
        target.make_unique if target.is_a?(Sketchup::ComponentInstance) && target.respond_to?(:make_unique)
        ensure_abf_board_attributes(target)
        ents = target_entities(target)
        next unless ents

        face = placement_face(ents, world_tr)
        next unless face

        face_tr = face_transform(face)
        next unless face_tr

        target_data = data.dup
        detected_product = detect_product_code(target)
        target_data[:product_code] = product_code_base(detected_product) unless detected_product.to_s.empty?
        target_data[:ten_sp] = detect_ten_sp(target) if target_data[:ten_sp].to_s.strip.empty?
        target_data[:face_normal] = face.normal.to_s
        target_data[:target_persistent_id] = target.persistent_id rescue nil

        target_data[:qty].times do
          size = marker_size_inches(target_data[:size_mm])
          transform = free_marker_transform(ents, face, face_tr, size)
          transform = unscaled_local_transform(transform, world_tr)
          marker = create_marker_group(ents, transform, target_data)
          added << marker if marker
        end
        affected << target
      end

      raise 'Khong co object hop le de gan PK.' if added.empty?

      mdl.commit_operation
      restore_selection(mdl, original_selection)
      refresh_abf_statistics
      { count: added.length, targets: affected.length }
    end
  rescue => e
    model.abort_operation rescue nil
    restore_selection(mdl, original_selection) rescue nil
    raise e
  end

  def self.add_accessory_routed_to_selection(raw_data)
    mdl = nil
    original_selection = []
    with_mh_thongke_mini_suspended do
      data = normalized_data(raw_data)
      mdl = model
      original_selection = live_selection(mdl)
      targets = routed_targets_for_accessory(data).select { |target| live_entity?(target) }
      raise 'Chon Group/Component dich truoc khi add PK.' if targets.empty?
      target_qty_pairs = distribute_qty(data[:qty], targets)
      raise 'Khong co object hop le de chia so luong PK.' if target_qty_pairs.empty?

      added = []
      affected = []

      mdl.start_operation('MH PK Add Routed', true)
      target_qty_pairs.each do |target, routed_qty|
        world_tr = entity_world_transform(target)
        target.make_unique if target.is_a?(Sketchup::ComponentInstance) && target.respond_to?(:make_unique)
        ensure_abf_board_attributes(target)
        ents = target_entities(target)
        next unless ents

        face = placement_face(ents, world_tr)
        next unless face

        face_tr = face_transform(face)
        next unless face_tr

        target_data = data.dup
        target_data[:qty] = routed_qty
        detected_product = detect_product_code(target)
        target_data[:product_code] = product_code_base(detected_product) unless detected_product.to_s.empty?
        target_data[:ten_sp] = detect_ten_sp(target) if target_data[:ten_sp].to_s.strip.empty?
        target_data[:face_normal] = face.normal.to_s
        target_data[:target_persistent_id] = target.persistent_id rescue nil

        target_data[:qty].times do
          size = marker_size_inches(target_data[:size_mm])
          transform = free_marker_transform(ents, face, face_tr, size)
          transform = unscaled_local_transform(transform, world_tr)
          marker = create_marker_group(ents, transform, target_data)
          added << marker if marker
        end
        affected << target
      end

      raise 'Khong co object hop le de gan PK.' if added.empty?

      mdl.commit_operation
      restore_selection(mdl, original_selection)
      refresh_abf_statistics
      { count: added.length, targets: affected.length }
    end
  rescue => e
    model.abort_operation rescue nil
    restore_selection(mdl, original_selection) rescue nil
    raise e
  end

  def self.quick_add
    data = {
      name: 'Phu kien',
      spec: '',
      qty: 1,
      shape: 'square',
      size_mm: DEFAULT_SIZE_MM,
      product_code: '',
      ten_sp: '',
      note: '',
      order_date: ''
    }
    result = add_accessory(data)
    UI.messagebox("Da them #{result[:count]} PK vao #{result[:target]}.")
  rescue => e
    UI.messagebox(e.message)
  end

  # Tim lai face trong ents sau make_unique (face cu thuoc definition cu).
  def self.refind_face(ents, center_local, normal_local)
    candidates = faces_for_placement(ents)
    return nil if candidates.empty?

    same_normal = candidates.select do |face|
      n = face.normal
      n.valid? && normal_local.valid? && n.dot(normal_local).abs > 0.999
    end
    pool = same_normal.empty? ? candidates : same_normal
    pool.min_by { |face| face.bounds.center.distance(center_local) }
  rescue
    nil
  end

  # Add 1 PK len dung mat da pick tu HUD tool (hover_ctx tu Picker.pick).
  # data nhan them: :excel_key, :section, :length_mode, :length_mm, :length_source.
  def self.add_armed_pk_to_face(hover_ctx, raw_data)
    mdl = nil
    original_selection = []
    with_mh_thongke_mini_suspended do
      data = normalized_data(raw_data)
      mdl = model
      original_selection = live_selection(mdl)
      target = hover_ctx[:target]
      face = hover_ctx[:face]
      raise 'Chua co mat hop le de gan PK.' unless live_entity?(target) && face && face.valid?

      face_center_local = face.bounds.center
      face_normal_local = face.normal

      mdl.start_operation('MH PK Add', true)
      target.make_unique if target.is_a?(Sketchup::ComponentInstance) && target.respond_to?(:make_unique)
      ensure_abf_board_attributes(target)
      ents = target_entities(target)
      raise 'Object dich khong co entities hop le.' unless ents

      defn = target.respond_to?(:definition) ? target.definition : nil
      if !face.valid? || (defn && face.parent != defn)
        face = refind_face(ents, face_center_local, face_normal_local)
      end
      raise 'Mat gan PK khong con hop le.' unless face && face.valid?

      face_tr = face_transform(face)
      raise 'Khong tinh duoc mat gan PK.' unless face_tr

      world_tr = hover_ctx[:target_world_tr] || entity_world_transform(target)
      detected_product = detect_product_code(target)
      data[:product_code] = product_code_base(detected_product) unless detected_product.to_s.empty?
      data[:ten_sp] = product_name_from_excel(data[:product_code]) if data[:ten_sp].to_s.strip.empty? && !data[:product_code].to_s.empty?
      data[:ten_sp] = detect_ten_sp(target) if data[:ten_sp].to_s.strip.empty?
      data[:face_normal] = face.normal.to_s
      data[:target_persistent_id] = target.persistent_id rescue nil

      size = marker_size_inches(data[:size_mm])
      transform = free_marker_transform(ents, face, face_tr, size)
      transform = unscaled_local_transform(transform, world_tr)
      marker = create_marker_group(ents, transform, data)
      raise 'Khong tao duoc PK.' unless marker

      if data[:length_mode]
        length_mm = data[:length_mm].to_f
        length_mm = target_longest_dimension_mm(target, world_tr) if length_mm <= 0
        if length_mm > 0
          source = data[:length_mm].to_f > 0 ? 'manual' : LENGTH_SOURCE_LONGEST_EDGE
          apply_length_attrs(marker, length_mm, source)
        end
      end
      trace_record_add(marker, data)
      restore_manual_label_overrides

      mdl.commit_operation
      restore_selection(mdl, original_selection)
      refresh_abf_statistics
      marker
    end
  rescue => e
    model.abort_operation rescue nil
    restore_selection(mdl, original_selection) rescue nil
    raise e
  end

  # Doi ten PK marker sang PK khac (click vao marker khi dang arm PK moi).
  # Giu nguyen pk_uid + geometry; ghi rename-history + excel-match qua traceability.
  def self.rename_marker(marker, raw_data)
    mdl = nil
    with_mh_thongke_mini_suspended do
      data = normalized_data(raw_data)
      mdl = model
      raise 'PK khong hop le.' unless live_entity?(marker) && pk_marker?(marker)

      from_label = accessory_label(marker)
      label = display_name(data[:name], data[:spec])
      raise 'Ten PK moi trung ten cu.' if label == from_label

      mdl.start_operation('MH PK Rename', true)
      marker.name = label
      marker.set_attribute('MH_Thongke', 'pk_name', label)
      marker.set_attribute('MH_Thongke', 'pk_base_name', data[:name].to_s.strip)
      marker.set_attribute('MH_Thongke', 'pk_spec', data[:spec].to_s.strip)
      marker.set_attribute('MH_Thongke', 'ghi_chu', data[:note].to_s.strip) unless data[:note].to_s.strip.empty?
      marker.set_attribute('MH_Thongke', 'last_modified', Time.now.strftime('%d/%m/%y %H:%M'))
      marker.set_attribute('ABF', 'setting-name', label)
      marker.set_attribute('ABF', 'statistical-name', label)
      trace_record_rename(marker, from_label, data)
      set_manual_label_override(marker, label)
      restore_manual_label_attrs(marker)
      mdl.commit_operation
      refresh_abf_statistics
      label
    end
  rescue => e
    model.abort_operation rescue nil
    raise e
  end

  # Doi ten object phu kien ABF (ban le, ray... cua ABF, khong phai PK marker cua minh):
  # chi cap nhat ten thong ke ABF (setting-name/statistical-name) + truy vet MH_Thongke.
  # KHONG dong vao entity.name va cac attr ky thuat (is-minifix, is-intersect...) cua ABF.
  def self.rename_abf_object(entity, raw_data)
    mdl = nil
    with_mh_thongke_mini_suspended do
      data = normalized_data(raw_data)
      mdl = model
      raise 'Object khong hop le.' unless live_entity?(entity)

      from_label = accessory_label(entity)
      label = display_name(data[:name], data[:spec])
      raise 'Ten moi trung ten cu.' if label == from_label

      mdl.start_operation('MH PK Rename ABF', true)
      entity.set_attribute('ABF', 'setting-name', label)
      entity.set_attribute('ABF', 'statistical-name', label)
      # dong bo ten sang thu vien ZSU (giu cac key ZSU khac nguyen ven)
      entity.set_attribute('ZSU', 'name', label)
      # obj LED (is-intersect length_measuring) → MH_Thongke uu tien doc ZSU_LED/ten_hien_thi,
      # phai ghi de o day thi ten moi moi "dinh" o ca bang thong ke.
      unless entity.get_attribute('ZSU_LED', 'ten_hien_thi').to_s.strip.empty?
        entity.set_attribute('ZSU_LED', 'ten_hien_thi', label)
      end
      entity.set_attribute('MH_Thongke', 'last_modified', Time.now.strftime('%d/%m/%y %H:%M'))
      trace_record_rename(entity, from_label, data)
      set_manual_label_override(entity, label)
      restore_manual_label_attrs(entity)
      mdl.commit_operation
      refresh_abf_statistics
      label
    end
  rescue => e
    model.abort_operation rescue nil
    raise e
  end

  # Doi ten thong nhat: PK marker cua minh hoac object ABF co ten thong ke.
  def self.rename_accessory(entity, raw_data)
    pk_marker?(entity) ? rename_marker(entity, raw_data) : rename_abf_object(entity, raw_data)
  end

  # Gom moi PK marker trong model: [{marker:, parent:, world_center:}].
  # product_code: chi loc marker co product khac (marker khong product van giu).
  def self.pk_markers_in_model(product_code = nil)
    code = product_code_base(product_code)
    found = []
    visited = {}
    walk = lambda do |ents, parent_tr, parent|
      ents.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        next unless live_entity?(entity)

        if pk_marker?(entity)
          marker_code = product_code_base(entity.get_attribute('MH_Thongke', 'product_code'))
          next if !code.empty? && !marker_code.empty? && marker_code != code

          found << {
            marker: entity,
            parent: parent,
            world_center: entity.bounds.center.transform(parent_tr)
          }
          next
        end

        child = target_entities(entity)
        next unless child

        key = child.object_id
        next if visited[key]

        visited[key] = true
        walk.call(child, parent_tr * entity.transformation, entity)
      end
    end
    walk.call(model.entities, Geom::Transformation.new, nil)
    found
  rescue
    []
  end

  # Gom moi "danh tinh" cua marker: ten hien tai + ten goc + toan bo lich su doi ten
  # + excel-match keys. De bang excel van tick dung du phu kien da doi ten nhieu lan.
  def self.tick_identity_sets(markers)
    keys = {}
    names = {}
    add_name = lambda do |value|
      normalized = search_text(value).strip
      names[normalized] = true unless normalized.empty?
    end

    Array(markers).each do |item|
      marker = item.is_a?(Hash) ? item[:marker] : item
      next unless live_entity?(marker)

      key = marker.get_attribute('MH_Thongke', 'excel-match-key').to_s.strip
      keys[key] = true unless key.empty?
      add_name.call(accessory_label(marker))
      [marker.get_attribute('MH_Thongke', 'pk_name'),
       marker.get_attribute('MH_Thongke', 'pk_base_name'),
       marker.get_attribute('MH_Thongke', 'current-name'),
       marker.get_attribute('MH_Thongke', 'original-name'),
       marker.get_attribute('MH_Thongke', 'excel-match-name')].each { |value| add_name.call(value) }

      hist = marker.get_attribute('MH_Thongke', 'rename-history').to_s
      unless hist.empty?
        (JSON.parse(hist) rescue []).each do |record|
          next unless record.is_a?(Hash)
          add_name.call(record['from'])
          add_name.call(record['to'])
          keys[record['excel_key'].to_s] = true unless record['excel_key'].to_s.empty?
        end
      end
      mhist = marker.get_attribute('MH_Thongke', 'excel-match-history').to_s
      unless mhist.empty?
        (JSON.parse(mhist) rescue []).each do |record|
          next unless record.is_a?(Hash)
          keys[record['key'].to_s] = true unless record['key'].to_s.empty?
          add_name.call(record['name'])
        end
      end
    end
    [keys, names]
  end

  # Cac dong VIRTUAL trong bao cao MH_Thongke (Nguon LED, Thanh nhom LED, Bas treo...)
  # — khong co object rieng nhung bam theo model that. Cache 10s de khong lag.
  def self.thongke_virtual_rows_cached(product_code = nil)
    unless @virtual_rows_cache && (Time.now.to_f - @virtual_rows_cache[0]) < 30
      rows = []
      snapshot = thongke_api_call(:report_snapshot, false)
      # cache cua MH_Thongke chua build → ep build 1 lan (TTL 30s nen khong lag lien tuc)
      if !snapshot.is_a?(Hash) || Array(snapshot[:accessories] || snapshot['accessories']).empty?
        snapshot = thongke_api_call(:report_snapshot, true)
      end
      if snapshot.is_a?(Hash)
        Array(snapshot[:accessories] || snapshot['accessories']).each do |row|
          next unless row.is_a?(Hash)
          virtual = (row[:virtual_source] || row['virtual_source']).to_s
          next if virtual.empty?

          name = (row[:name] || row['name']).to_s.strip
          next if name.empty?

          rows << {
            name: name,
            product: product_code_base(row[:actual_product] || row['actual_product'] || row[:product] || row['product'])
          }
        end
      end
      @virtual_rows_cache = [Time.now.to_f, rows]
    end

    code = product_code_base(product_code)
    all = @virtual_rows_cache[1]
    code.empty? ? all : all.select { |r| r[:product].empty? || r[:product] == code }
  rescue
    []
  end

  def self.thongke_virtual_names_cached(product_code)
    thongke_virtual_rows_cached(product_code).map { |r| r[:name] }.uniq
  rescue
    []
  end

  # Danh dau row[:ticked] cho cac dong excel da co phu kien trong model.
  # Khop theo: excel-match-key → ten chinh xac (moi danh tinh lich su) → ten chua ten dong excel.
  # extra_markers: cac phu kien ABF (khong phai pk marker) tu Leaders de tick ca khi doi ten ABF.
  def self.apply_tick_state(rows, product_code, extra_markers = [])
    markers = pk_markers_in_model(product_code) + Array(extra_markers)
    keys, names = tick_identity_sets(markers)
    thongke_virtual_names_cached(product_code).each do |virtual_name|
      normalized = search_text(virtual_name).strip
      names[normalized] = true unless normalized.empty?
    end
    name_list = names.keys

    Array(rows).each do |row|
      key = row[:excel_key].to_s.strip
      row_norm = search_text(row[:name]).strip
      display_norm = search_text(display_name(row[:name], row[:spec])).strip
      row[:ticked] = (!key.empty? && keys[key]) ||
                     names[row_norm] ||
                     names[display_norm] ||
                     (row_norm.length >= 6 && name_list.any? { |n| n.include?(row_norm) }) ||
                     false
    end
    rows
  rescue
    rows
  end
end
