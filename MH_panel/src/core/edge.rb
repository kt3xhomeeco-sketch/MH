module MH::Panel::Edge
  def self.to_vector(edge)
    edge.start.position.vector_to(edge.end.position)
  end
  def self.same?(e1, e2)
    (e1.start.position == e2.start.position && e1.end.position == e2.end.position) ||
      (e1.start.position == e2.end.position && e1.end.position == e2.start.position)
  end
  def self.shares_vertex?(e1, e2)
    (e1.vertices & e2.vertices).any?
  end
  def self.build_chains(edges)
    return [] if edges.empty?
    edge_set = edges.dup
    chains = []
    while edge_set.any?
      chain = [edge_set.shift]
      loop do
        added = false
        edge_set.each do |e|
          if shares_vertex?(chain.last, e)
            chain << e
            edge_set.delete(e)
            added = true
            break
          elsif shares_vertex?(chain.first, e)
            chain.unshift(e)
            edge_set.delete(e)
            added = true
            break
          end
        end
        break unless added
      end
      chains << chain
    end
    chains
  end
  def self.order_chain(edges)
    return edges if edges.length < 2
    edge_list = edges.dup
    start_edge = edge_list.find { |e|
      e.vertices.any? { |v| v.edges.count { |ve| edge_list.include?(ve) } == 1 }
    } || edge_list.first
    ordered = [start_edge]
    edge_list.delete(start_edge)
    while edge_list.any?
      found = false
      edge_list.each do |e|
        if shares_vertex?(ordered.last, e)
          ordered << e
          edge_list.delete(e)
          found = true
          break
        end
      end
      break unless found
    end
    ordered
  end
  def self.smooth(edges)
    return unless edges
    edges.each { |edge|
      if edge.faces.length == 2
        ang = edge.faces[0].normal.angle_between(edge.faces[1].normal)
        if ang < 20.degrees
          edge.soft = true
          edge.smooth = true
        end
      end
    }
  end
  def self.stray?(e)
    return false unless e.valid? && e.is_a?(Sketchup::Edge)
    e.faces.empty? || (e.faces.size > 1 && e.faces.all? { |f| f == e.faces[0] })
  end
  def self.parallel?(e1, e2)
    v1 = e1.start.position.vector_to(e1.end.position)
    v2 = e2.start.position.vector_to(e2.end.position)
    v1.parallel?(v2)
  end
  def self.coplanar?(e)
    return false unless e.faces.size == 2
    f1, f2 = e.faces
    return false unless f1.normal.samedirection?(f2.normal)
    return false if MH::Panel::Face.duplicate?(f1, f2)
    return false unless MH::Panel::Edge.safe_to_merge?(e)
    return false unless MH::Panel::Face.faces_coplanar?(f1, f2)
    true
  end
  def self.safe_to_merge?(e)
    e.faces.all? { |f| MH::Panel::Face.safe_to_merge?(f) }
  end
  def self.convert_to_curve(ents, edges, tag = nil)
    verts = edges.flat_map(&:vertices).uniq
    start_vert = verts.find { |v| v.edges.length == 1 } || verts.first
    new_verts = [start_vert]
    counter = 0
    while new_verts.length < verts.length && counter < verts.length
      edges.each do |edge|
        if edge.end == new_verts.last
          new_verts << edge.start unless new_verts.include?(edge.start)
        elsif edge.start == new_verts.last
          new_verts << edge.end unless new_verts.include?(edge.end)
        end
      end
      counter += 1
    end
    new_verts.collect! { |v| v.position }
    temp_group = ents.add_group
    curve_edges = temp_group.entities.add_curve(new_verts)
    curve_edges.each { |edge| edge.layer = tag } if tag
    edges.each { |edge| edge.erase! if edge.valid? }
    temp_group.explode
  end
  def self.weld(edges)
    return [] if edges.length < 2
    model = Sketchup.active_model
    ents = MH::Panel::Model.active_entities
    MH::Panel.start
    verts = edges.flat_map(&:vertices)
    vert_count = Hash.new(0)
    verts.each { |v| vert_count[v] += 1 }
    end_verts = vert_count.select { |v, c| c == 1 }.keys
    if end_verts.empty?
      start_vert = verts.first
      closed = true
    else
      start_vert = end_verts.first
      closed = false
    end
    sorted_verts = [start_vert]
    edges_set = edges.dup
    while sorted_verts.length < verts.uniq.length
      current = sorted_verts.last
      found = false
      edges_set.each do |edge|
        if edge.start == current && !sorted_verts.include?(edge.end)
          sorted_verts << edge.end
          edges_set.delete(edge)
          found = true
          break
        elsif edge.end == current && !sorted_verts.include?(edge.start)
          sorted_verts << edge.start
          edges_set.delete(edge)
          found = true
          break
        end
      end
      break unless found
    end
    points = sorted_verts.map(&:position)
    points << points.first if closed
    MH::Panel.commit
    MH::Panel.start
    edges.each do |edge|
      edge.explode_curve if edge.curve
    end
    temp_group = ents.add_group
    curve_edges = temp_group.entities.add_curve(points)
    result_entities = temp_group.explode
    result_curves = result_entities.select { |e| e.is_a?(Sketchup::Edge) && e.curve }
                                   .map(&:curve)
                                   .uniq
                                   .map(&:edges)
    MH::Panel.commit
    result_curves
  end
  def self.connect_curves(ents, c1, c2)
    a = c1.first.start.position
    b = c1.last.end.position
    c = c2.first.start.position
    d = c2.last.end.position
    if a.distance(c) <= a.distance(d)
      ents.add_line(a, c)
      line = ents.add_line(b, d)
    else
      ents.add_line(a, d)
      line = ents.add_line(b, c)
    end
    line.find_faces if line && line.valid?
  end
  def self.pts_length(pts)
    total = 0
    (0...pts.length - 1).each do |i|
      total += pts[i].distance(pts[i + 1])
    end
    total
  end
  def self.offset_curve(ents, temp_edges, offset_dist, effective_skip)
    pts_a = MH::Panel::Offset.edges(temp_edges, -offset_dist)
    pts_b = MH::Panel::Offset.edges(temp_edges, offset_dist)
    return unless pts_a && pts_b && pts_a.length > 1 && pts_b.length > 1
    total_len = temp_edges.sum(&:length)
    if pts_length(pts_a) >= total_len
      pts_a, pts_b = pts_b, pts_a
    end
    pts = effective_skip ? pts_b : pts_a
    ents.add_curve(pts)
  end
end
