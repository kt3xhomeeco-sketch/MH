module MH::Panel::Purge
  def self.fix_all(boards)
    boards = Array(boards)
    return if boards.empty?
    boards.each { |b|
      entities = MH::Panel.get_ents(b)
      process_stray_edge(entities)
      process_coplanar_edge(entities)
      process_hole(entities)
      process_loose_face(entities)
    }
  end
  def self.fix_all_hole(boards)
    boards = Array(boards)
    return if boards.empty?
    boards.each { |b|
      entities = MH::Panel.get_ents(b)
      process_hole(entities)
      process_stray_edge(entities)
      process_coplanar_edge(entities)
      process_loose_face(entities)
    }
  end
  def self.fix_edge(boards)
    boards = Array(boards)
    return if boards.empty?
    boards.each { |b|
      entities = MH::Panel.get_ents(b)
      process_broken_edge(entities)
      process_stray_edge(entities)
      process_coplanar_edge(entities)
      process_hole(entities)
    }
  end
  def self.fix_face(boards)
    boards = Array(boards)
    return if boards.empty?
    boards.each { |b|
      entities = MH::Panel.get_ents(b)
      process_loose_face(entities)
    }
  end
  def self.fix_coplannar(boards)
    boards = Array(boards)
    return if boards.empty?
    boards.each { |b|
      entities = MH::Panel.get_ents(b)
      process_loose_face(entities)
    }
  end
  def self.delete_entities(entities, fix_edge = true)
    model = Sketchup.active_model
    sel = model.selection
    entities.each do |ent|
      next unless ent.valid?
      sel.remove(ent)
      if ent.is_a?(Sketchup::Face)
        edges = ent.edges
        ent.erase!
        if fix_edge
          edges.each { |e|
            e.erase! if e.valid? && e.is_a?(Sketchup::Edge) && coplanar_edge?(e, true) || stray_edge?(e)
          }
        end
      else
        ent.erase!
      end
    end
  end
  def self.edge_protected?(edge)
    if edge.faces.any? { |face_edge| face_edge.visible? || face_edge.layer.visible? }
      return true
    end
    parent = edge.parent
    if parent.is_a?(Sketchup::ComponentDefinition) && parent.behavior.cuts_opening?
      return true if edge.vertices.all? { |v| v.position.on_plane?(GROUND_PLANE) }
    end
    false
  end
  def self.edge_safe_to_merge?(e)
    e.faces.all? { |f| MH::Panel::Face.safe_to_merge?(f) }
  end
  def self.face_safe_to_merge?(f)
    stack = f.outer_loop.edges
    edge = stack.shift
    direction = edge.line[1]
    until stack.empty?
      edge = stack.shift
      return true unless edge.line[1].parallel?(direction)
    end
    false
  end
  def self.faces_coplanar?(f1, f2)
    vertices = f1.vertices + f2.vertices
    plane = Geom.fit_plane_to_points(vertices)
    vertices.all? { |v| v.position.on_plane?(plane) }
  end
  def self.uv_equal?(uvq1, uvq2)
    uv1 = uvq1.to_a.map { |n| n % 1 }
    uv2 = uvq2.to_a.map { |n| n % 1 }
    uv1 == uv2
  end
  def self.continuous_uv?(f1, f2, e)
    if f1.material == f2.material && f1.back_material == f2.back_material
      if f1.material.nil? || f1.material.texture.nil?
        return true
      else
        tw = Sketchup.create_texture_writer
        uvh1 = f1.get_UVHelper(true, true, tw)
        uvh2 = f2.get_UVHelper(true, true, tw)
        p1 = e.start.position
        p2 = e.end.position
        self.uv_equal?(uvh1.get_front_UVQ(p1), uvh2.get_front_UVQ(p1)) &&
          self.uv_equal?(uvh1.get_front_UVQ(p2), uvh2.get_front_UVQ(p2)) &&
          self.uv_equal?(uvh1.get_back_UVQ(p1), uvh2.get_back_UVQ(p1)) &&
          self.uv_equal?(uvh1.get_back_UVQ(p2), uvh2.get_back_UVQ(p2))
      end
    else
      return false
    end
  end
  def self.stray_edge?(e)
    return false unless e.valid? && e.is_a?(Sketchup::Edge)
    parent = e.parent
    cutout = parent.is_a?(Sketchup::ComponentDefinition) && parent.behavior.cuts_opening?
    return false if cutout && e.vertices.all? { |v| v.position.on_plane?(GROUND_PLANE) }
    e.faces.empty? || (e.faces.size > 1 && e.faces.all? { |f| f == e.faces[0] })
  end
  def self.coplanar_edge?(e, check_uv)
    f1, f2 = e.faces
    return false unless e.faces.size == 2
    return false unless f1.normal.samedirection?(f2.normal)
    return false if MH::Panel::Face.duplicate?(f1, f2)
    # A segmented curved side can share the same approximate plane at the
    # tangent junction with a straight side. Removing that boundary edge
    # drops a real profile segment from the board.
    return false if f1.edges.any?(&:curve) || f2.edges.any?(&:curve)
    return false unless edge_safe_to_merge?(e)
    return false unless faces_coplanar?(f1, f2)
    return false if check_uv && !continuous_uv?(f1, f2, e)
    true
  end
  def self.inside_face?(f)
    remove = true
    f.edges.each { |e|
      if e.faces.size <= 2
        remove = false
        break
      end
    }
    return remove
  end
  def self.stray_face?(f)
    f.edges.all? { |e| e.faces.size == 1 }
  end
  def self.process_hole(entities)
    entities.grep(Sketchup::Edge).each { |e|
      next unless e.valid?
      e.find_faces if e.valid? && e.faces.size == 1
    }
  end
  def self.process_stray_edge(entities)
    temp_delete = []
    entities.each do |e|
      temp_delete << e if e.is_a?(Sketchup::Edge) && stray_edge?(e)
    end
    delete_entities(temp_delete)
  end
  def self.process_coplanar_edge(entities)
    temp_delete = []
    entities.each do |e|
      temp_delete << e if e.is_a?(Sketchup::Edge) && coplanar_edge?(e, false)
    end
    delete_entities(temp_delete)
  end
  def self.process_all_edge(entities)
    temp_delete = []
    entities.each do |e|
      temp_delete << e if e.is_a?(Sketchup::Edge)
    end
    delete_entities(temp_delete)
  end
  def self.process_broken_edge(entities)
    temp_edges = []
    entities.each do |e|
      next unless e.valid? && e.is_a?(Sketchup::Edge)
      e.vertices.each do |vertex|
        next unless vertex.edges.length == 2
        v1 = vertex.edges[0].line[1]
        v2 = vertex.edges[1].line[1]
        next unless v1.parallel?(v2)
        pt1 = vertex.position
        pt2 = pt1.clone
        pt2.x += rand(1000) / 100.0
        pt2.y += rand(1000) / 100.0
        pt2.z += rand(1000) / 100.0
        temp_edge = entities.add_line(pt1, pt2)
        temp_edges << temp_edge unless temp_edge.nil?
      end
    end
    entities.erase_entities(temp_edges)
  end
  def self.process_broken_arc(entities)
    return if entities.to_a.empty?
    temp_pt = Geom::Point3d.new(0, 0, 0)
    temp_edges = []
    parent = entities.to_a[0].parent.entities
    entities.each do |e|
      next unless e.valid? && e.is_a?(Sketchup::Edge) && e.curve
      e.vertices.each do |v|
        next unless v.valid?
        found = false
        v.edges.each do |edge|
          next unless edge.valid?
          next unless edge.curve
          next if edge == e || edge.curve.edges.include?(e)
          next if edge.faces.size != e.faces.size
          found = true
          break
        end
        next unless found
        v.edges.each do |edge|
          next unless edge.valid?
          if edge.curve
            next
          end
          edge.soft = true
          edge.smooth = true
        end
        temp_edges << parent.add_line(v.position, temp_pt)
      end
      e.explode_curve if e.curve.count_edges == 1
    end
    parent.erase_entities(temp_edges.compact)
  end
  def self.process_inside_face(entities)
    temp_delete = []
    entities.each do |e|
      temp_delete << e if e.is_a?(Sketchup::Face) && inside_face?(e)
    end
    delete_entities(temp_delete, false)
  end
  def self.process_all_face(entities)
    temp_delete = []
    entities.each do |e|
      temp_delete << e if e.is_a?(Sketchup::Face)
    end
    delete_entities(temp_delete, false)
  end
  def self.process_stray_face(entities)
    temp_delete = []
    entities.each do |e|
      temp_delete << e if e.is_a?(Sketchup::Face) && stray_face?(e)
    end
    delete_entities(temp_delete)
  end
  def self.loose_face?(f)
    f.edges.any? { |e| e.faces.include?(f) && e.faces.size == 1 }
  end
  def self.process_loose_face(entities)
    temp_delete = []
    entities.each do |e|
      temp_delete << e if e.is_a?(Sketchup::Face) && loose_face?(e)
    end
    delete_entities(temp_delete)
  end
end
