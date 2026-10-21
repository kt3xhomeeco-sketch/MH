module MH::Panel::Solid
  def self.bulk_solid?(containers)
    containers.all? { |c| solid?(c) }
  end
  def self.within?(point, containers, on_boundary = true, verify_solid = true, odd_even = false)
    return if verify_solid && !solid?(containers)
    if odd_even
      containers.count { |c| within?(point, c, on_boundary) }.odd?
    else
      containers.any? { |c| within?(point, c, on_boundary) }
    end
  end
  def self.bulk_union(target, modifiers)
    modifiers = modifiers.dup
    until modifiers.empty?
      return nil unless union(target, modifiers.shift)
    end
    true
  end
  def self.subtract(targets, modifiers)
    status = trim(targets, modifiers)
    return status unless status
    modifiers.first.parent.entities.erase_entities(modifiers)
    true
  end
  def self.bulk_trim(targets, modifiers)
    targets = [targets] unless targets.is_a?(Array)
    targets.each do |target|
      modifiers_dup = modifiers.dup
      until modifiers_dup.empty?
        return nil unless trim(target, modifiers_dup.shift)
      end
    end
  end
  def self.bulk_intersect(target, modifiers)
    modifiers = modifiers.dup
    until modifiers.empty?
      return nil unless intersect(target, modifiers.shift)
    end
    true
  end
  def self.solid?(container)
    return false unless instance?(container)
    definition(container).entities.grep(Sketchup::Edge).all? { |e| e.faces.size.even? }
  end
  def self.within?(point, container, on_boundary = true, verify_solid = true)
    return false if verify_solid && !solid?(container)
    point = point.transform(container.transformation.inverse)
    vector = Geom::Vector3d.new(234, 1343, 345)
    ray = [point, vector]
    intersections = []
    definition(container).entities.grep(Sketchup::Face) do |face|
      return on_boundary if within_face?(point, face)
      intersection = Geom.intersect_line_plane(ray, face.plane)
      next unless intersection
      next if intersection == point
      next unless (intersection - point).samedirection?(vector)
      next unless within_face?(intersection, face)
      intersections << intersection
    end
    intersections = uniq_points(intersections)
    intersections.size.odd?
  end
  def self.union(target, modifier)
    target = target.make_unique if target.is_a?(Sketchup::Group)
    temp_group = target.parent.entities.add_group
    merge_into(temp_group, modifier)
    modifier = temp_group
    target_ents = definition(target).entities
    modifier_ents = definition(modifier).entities
    add_intersection_edges(target, modifier)
    overlapping_edges = find_corresponding_faces(target, modifier, nil)[0].flat_map(&:edges).map(&:vertices)
    erase1 = find_faces(target, modifier, true, false)
    erase2 = find_faces(modifier, target, true, false)
    c_faces1, c_faces2 = find_corresponding_faces(target, modifier, false)
    erase1.concat(c_faces1)
    erase2.concat(c_faces2)
    erase_faces_with_edges(erase1)
    erase_faces_with_edges(erase2)
    merge_into(target, modifier)
    overlapping_edges.select! { |vs| vs.all?(&:valid?) }
    overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
    target_ents.erase_entities(find_coplanar_edges(overlapping_edges))
    weld_hack(target_ents)
    solid?(target) ? true : nil
  end
  def self.subtract(target, modifier)
    status = trim(target, modifier)
    return status unless status
    modifier.erase!
    true
  end
  def self.trim(target, modifier)
    return false unless solid?(target) && solid?(modifier)
    target = target.make_unique
    temp_group = target.parent.entities.add_group
    merge_into(temp_group, modifier, true)
    modifier = temp_group
    target_ents = definition(target).entities
    modifier_ents = definition(modifier).entities
    add_intersection_edges(target, modifier)
    overlapping_edges = find_corresponding_faces(target, modifier, nil)[0].flat_map(&:edges).map(&:vertices)
    erase1 = find_faces(target, modifier, true, false)
    erase2 = find_faces(modifier, target, false, false)
    c_faces1, c_faces2 = find_corresponding_faces(target, modifier, true)
    erase1.concat(c_faces1)
    erase2.concat(c_faces2)
    erase_faces_with_edges(erase1)
    erase_faces_with_edges(erase2)
    modifier_ents.each { |f| f.reverse! if f.is_a? Sketchup::Face }
    merge_into(target, modifier)
    overlapping_edges.select! { |vs| vs.all?(&:valid?) }
    overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
    target_ents.erase_entities(find_coplanar_edges(overlapping_edges))
    weld_hack(target_ents)
    solid?(target) ? true : nil
  end
  def self.intersect(target, modifier)
    return false unless solid?(target) && solid?(modifier)
    target = target.make_unique if target.is_a?(Sketchup::Group)
    temp_group = target.parent.entities.add_group
    merge_into(temp_group, modifier)
    modifier = temp_group
    target_ents = definition(target).entities
    modifier_ents = definition(modifier).entities
    add_intersection_edges(target, modifier)
    overlapping_edges = find_corresponding_faces(target, modifier, nil)[0].flat_map(&:edges).map(&:vertices)
    erase1 = find_faces(target, modifier, false, false)
    erase2 = find_faces(modifier, target, false, false)
    c_faces1, c_faces2 = find_corresponding_faces(target, modifier, false)
    erase1.concat(c_faces1)
    erase2.concat(c_faces2)
    erase_faces_with_edges(erase1)
    erase_faces_with_edges(erase2)
    merge_into(target, modifier)
    overlapping_edges.select! { |vs| vs.all?(&:valid?) }
    overlapping_edges.map! { |vs| vs[0].common_edge(vs[1]) }.compact!
    target_ents.erase_entities(find_coplanar_edges(overlapping_edges))
    weld_hack(target_ents)
    target
  end
  def self.definition(instance)
    if instance.is_a?(Sketchup::ComponentInstance) ||
       (Sketchup.version.to_i >= 15 && instance.is_a?(Sketchup::Group))
      instance.definition
    else
      instance.model.definitions.find { |d| d.instances.include?(instance) }
    end
  end
  def self.instance?(entity)
    entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
  end
  def self.uniq_points(points)
    points.reduce([]) { |a, p| a.any? { |p1| p1 == p } ? a : a << p }
  end
  def self.within_face?(point, face, on_boundary = true)
    pc = face.classify_point(point)
    return on_boundary if [Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(pc)
    pc == Sketchup::Face::PointInside
  end
  def self.add_intersection_edges(container1, container2)
    entities1 = definition(container1).entities
    entities2 = definition(container2).entities
    temp_group = container1.parent.entities.add_group
    entities1.intersect_with(
      false,
      container1.transformation,
      temp_group.entities,
      IDENTITY,
      true,
      find_mesh_geometry(entities2)
    )
    entities2.intersect_with(
      false,
      container1.transformation.inverse,
      temp_group.entities,
      container1.transformation.inverse,
      true,
      find_mesh_geometry(entities1)
    )
    interior_hole_hack(merge_into(container1, temp_group, true).grep(Sketchup::Edge))
    interior_hole_hack(merge_into(container2, temp_group).grep(Sketchup::Edge))
    nil
  end
  def self.point_at_face(face)
    return if face.area.zero?
    index = 1
    begin
      points = face.mesh.polygon_points_at(index)
      index += 1
    end while points[0].on_line?(points[1], points[2])
    Geom.linear_combination(0.5, Geom.linear_combination(0.5, points[0], 0.5, points[1]), 0.5, points[2])
  end
  def self.find_faces(scope, reference, interior, on_surface)
    definition(scope).entities.select do |f|
      next unless f.is_a?(Sketchup::Face)
      point = point_at_face(f)
      next unless point
      point.transform!(scope.transformation)
      next if interior != within?(point, reference, interior == on_surface, false)
      true
    end
  end
  def self.find_corresponding_faces(container1, container2, orientation)
    faces = [[], []]
    definition(container1).entities.grep(Sketchup::Face) do |face1|
      normal1 = transform_as_normal(face1.normal, container1.transformation)
      points1 = face1.vertices.map { |v| v.position.transform(container1.transformation) }
      definition(container2).entities.grep(Sketchup::Face) do |face2|
        next unless face2.is_a?(Sketchup::Face)
        normal2 = transform_as_normal(face2.normal, container2.transformation)
        next unless normal1.parallel?(normal2)
        points2 = face2.vertices.map { |v| v.position.transform(container2.transformation) }
        next unless points1.all? { |v| points2.include?(v) }
        unless orientation.nil?
          next if normal1.samedirection?(normal2) != orientation
        end
        faces[0] << face1
        faces[1] << face2
      end
    end
    faces
  end
  def self.purge_edges(entities)
    to_purge = entities.grep(Sketchup::Edge).select { |e| e.faces.size < 2 }
    entities.erase_entities(to_purge)
    nil
  end
  def self.merge_into(destination, to_move, keep_original = false)
    tr = destination.transformation.inverse * to_move.transformation
    entities = definition(destination).entities
    temp = entities.add_instance(definition(to_move), tr)
    to_move.erase! unless keep_original
    temp.explode
  end
  def self.find_coplanar_edges(entities)
    entities.grep(Sketchup::Edge).select do |e|
      next unless e.faces.size == 2
      next unless e.faces[0].material == e.faces[1].material
      next unless e.faces[0].layer == e.faces[1].layer
      next unless e.faces[0].normal.parallel?(e.faces[1].normal)
      e.faces[0].vertices.all? do |v|
        e.faces[1].classify_point(v.position) != Sketchup::Face::PointNotOnPlane
      end
      e.faces[1].vertices.all? do |v|
        e.faces[0].classify_point(v.position) != Sketchup::Face::PointNotOnPlane
      end
    end
  end
  def self.weld_hack(entities)
    return if solid?(entities.parent)
    temp_group = entities.add_group
    naked_edges(entities).each do |e|
      temp_group.entities.add_line(e.start, e.end)
    end
    temp_group.explode
    nil
  end
  def self.naked_edges(entities)
    entities.grep(Sketchup::Edge).select { |e| e.faces.size == 1 }
  end
  def self.erase_faces_with_edges(faces)
    return if faces.empty?
    erase = faces + (faces.flat_map(&:edges).select { |e| (e.faces - faces).empty? })
    erase.first.parent.entities.erase_entities(erase)
    nil
  end
  def self.find_mesh_geometry(entities)
    entities.select { |e| [Sketchup::Face, Sketchup::Edge].include?(e.class) }
  end
  def self.transform_as_normal(normal, transformation)
    tr = transpose(transformation).inverse
    normal.transform(tr).normalize
  end
  def self.transpose(transformation)
    a = transformation.to_a
    Geom::Transformation.new([a[0], a[4], a[8], 0, a[1], a[5], a[9], 0, a[2], a[6], a[10], 0, 0, 0, 0, a[15]])
  end
  def self.interior_hole_hack(edges)
    return if edges.empty?
    entities = edges.first.parent.entities
    old_entities = entities.to_a
    edges.each(&:find_faces)
    new_faces = entities.to_a - old_entities
    entities.erase_entities(new_faces.select { |f| !wrapping_face(f) || f.edges.any? { |e| e.faces.size != 2 } })
    nil
  end
  def self.wrapping_face(face)
    (face.edges.map(&:faces).inject(:&) - [face]).first
  end
end
