module MH::Panel::Board
  def self.calc_thickness(group)
    MH::Geo::BoardAnalyzer.calc_thickness(group)
  end
  def self.reset_axes(group)
    MH::Panel.start
    return nil unless group && group.respond_to?(:definition)
    definition = group.definition
    entities = definition.entities
    edges = entities.grep(Sketchup::Edge)
    faces = entities.grep(Sketchup::Face)
    return nil if edges.empty? || faces.empty?
    longest_edge = edges.max_by { |e| e.length }
    edge_vec = longest_edge.start.position.vector_to(longest_edge.end.position)
    largest_face = faces.max_by { |f| f.area }
    zaxis = largest_face.normal
    dot = edge_vec.dot(zaxis)
    xaxis = Geom::Vector3d.new(
      edge_vec.x - dot * zaxis.x,
      edge_vec.y - dot * zaxis.y,
      edge_vec.z - dot * zaxis.z
    )
    xaxis = edge_vec if xaxis.length < 0.001
    xaxis.normalize!
    yaxis = zaxis.cross(xaxis)
    yaxis.normalize!
    p1 = longest_edge.start.position
    p2 = longest_edge.end.position
    origin = [p1, p2].min_by { |p| [p.z, p.y, -p.x] }
    new_axes = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
    definition.entities.transform_entities(new_axes.inverse, entities.to_a)
    definition.instances.each { |i| i.transformation *= new_axes }
    MH::Panel.commit
  end
  def self.add_thickness(group, d)
    MH::Geo::BoardAnalyzer.add_thickness(group, d)
  end
  def self.change_thickness(group, target, bb)
    MH::Geo::BoardAnalyzer.change_thickness(group, target, bb)
  end
  def self.clone_and_clean(b)
    ents = b.parent.entities
    dup = ents.add_instance(b.definition, b.transformation)
    dup = dup.make_unique
    MH::Panel::ABF.clean_tag(dup)
    faces = MH::Panel.grep_ents(dup, :face)
    faces.each { |f| MH::Panel::ABF.remove_band(f) if f.valid? }
    dup
  end
  def self.filter_and_fix
    model = Sketchup.active_model
    selection = model.selection
    boards = selection.to_a.select { |e| MH::Panel.is_container?(e) && MH::Panel::Board.calc_thickness(e) }
    MH::Panel.start
    boards.map! { |board|
      b = MH::Panel::Group.component_to_group(board)
      board = b if b
      board = board.make_unique
      MH::Panel::Group.fix_scale(board)
      board
    }
    MH::Panel.commit
    MH::Panel.select(boards)
    boards
  end
  def self.calc_local_size(board)
    MH::Geo::BoardAnalyzer.calc_local_size(board)
  end
  def self.vparallel?(a, b)
    MH::Geo::BoardAnalyzer.vparallel?(a, b)
  end
  def self.is_container?(ent)
    MH::Geo::Util.is_container?(ent)
  end
  def self.is_panel?(ent)
    MH::Geo::BoardAnalyzer.panel?(ent)
  end
  def self.make(face, ents, offset, push)
    group = MH::Geo::BoardBuilder.from_face(face, ents, offset: offset, thickness: push)
    group.material = face.material if group && face && face.respond_to?(:material) && face.material
    group
  end
  def self.make_box(ents, transform, width_mm, depth_mm, thickness_mm, offset: 0)
    MH::Geo::BoardBuilder.from_box(
      ents,
      transform: transform,
      width_mm: width_mm,
      depth_mm: depth_mm,
      thickness_mm: thickness_mm,
      offset: offset
    )
  end
  def self.calc_normal(board)
    MH::Geo::BoardAnalyzer.calc_normal(board)
  end
  def self.group_by_normal(boards)
    MH::Geo::BoardAnalyzer.group_by_normal(boards)
  end
  def self.rebuild(board)
    ents = MH::Panel.get_ents(board)
    local_bb = Geom::BoundingBox.new
    ents.each { |e| local_bb.add(e.bounds) if e.respond_to?(:bounds) }
    return false if local_bb.empty?
    x0, y0, z0 = local_bb.min.x, local_bb.min.y, local_bb.min.z
    x1, y1, z1 = local_bb.max.x, local_bb.max.y, local_bb.max.z
    return false if [x1 - x0, y1 - y0, z1 - z0].any? { |d| d < 1e-6 }
    if board.material.nil? && ents.grep(Sketchup::Face).any?
      materials = ents.grep(Sketchup::Face).map(&:material).compact.uniq
      board.material = materials.first if materials.size == 1
    end
    ents.clear!
    pts = [
      Geom::Point3d.new(x0, y0, z0), Geom::Point3d.new(x1, y0, z0),
      Geom::Point3d.new(x1, y1, z0), Geom::Point3d.new(x0, y1, z0),
      Geom::Point3d.new(x0, y0, z1), Geom::Point3d.new(x1, y0, z1),
      Geom::Point3d.new(x1, y1, z1), Geom::Point3d.new(x0, y1, z1),
    ]
    faces = []
    faces << ents.add_face(pts[0], pts[1], pts[2], pts[3])
    faces << ents.add_face(pts[4], pts[5], pts[6], pts[7])
    faces << ents.add_face(pts[0], pts[1], pts[5], pts[4])
    faces << ents.add_face(pts[1], pts[2], pts[6], pts[5])
    faces << ents.add_face(pts[2], pts[3], pts[7], pts[6])
    faces << ents.add_face(pts[3], pts[0], pts[4], pts[7])
    faces.compact!
    box_center = Geom::Point3d.new((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
    faces.each do |face|
      next unless face && face.valid?
      fc = face.bounds.center
      face.reverse! if face.normal.dot(fc - box_center) < 0
    end
    true
  end
  def self.get_band_faces(ents, min_edge_length = 0)
    target_faces = []
    ents.each do |entity|
      exd = get_cnc_faces(entity)
      MH::Panel.grep_ents(entity, :face).each do |face|
        next if exd.include?(face)
        next unless MH::Panel::Face.rectangle_edges(face)
        next unless face.edges.map { |e| e.length }.max > min_edge_length
        target_faces << { face: face, parent: entity }
      end
    end
    target_faces
  end
  def self.tim_van_gan_nhat(refs, d:, hidden: false)
    refs = [refs] unless refs.is_a?(Array)
    min_x = Float::INFINITY;  min_y = Float::INFINITY;  min_z = Float::INFINITY
    max_x = -Float::INFINITY; max_y = -Float::INFINITY; max_z = -Float::INFINITY
    refs.each do |b|
      bb = b.bounds
      x0 = bb.min.x - d; y0 = bb.min.y - d; z0 = bb.min.z - d
      x1 = bb.max.x + d; y1 = bb.max.y + d; z1 = bb.max.z + d
      min_x = x0 if x0 < min_x; min_y = y0 if y0 < min_y; min_z = z0 if z0 < min_z
      max_x = x1 if x1 > max_x; max_y = y1 if y1 > max_y; max_z = z1 if z1 > max_z
    end
    result = []
    MH::Panel::Model.active_entities.each do |g|
      next unless MH::Panel.is_container?(g)
      next if refs.include?(g)
      unless hidden
        next if g.hidden?
        next if g.layer && !g.layer.visible?
      end
      next unless calc_thickness(g)
      gb = g.bounds
      next if gb.min.x > max_x || gb.max.x < min_x ||
              gb.min.y > max_y || gb.max.y < min_y ||
              gb.min.z > max_z || gb.max.z < min_z
      result << g
    end
    result
  end
  def self.get_cnc_faces(input)
    MH::Geo::BoardAnalyzer.get_cnc_faces(input)
  end
end
