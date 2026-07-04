module MH::Geo::Face
  def self.rectangle_edges(face)
    edges = face.edges
    return nil unless edges.size == 4
    pairs = []
    edges.combination(2).each do |a, b|
      if a.line[1].parallel?(b.line[1]) && (a.length - b.length).abs < 0.1.mm
        pairs << [a, b]
      end
    end
    return nil unless pairs.size == 2
    pairs
  end
  def self.simplify(face, tol)
    return if tol == 0
    inward = tol < 0
    return unless face && face.valid?
    org_edges = inward ? face.edges : nil
    new_faces = MH::Geo::Offset.faces(face, tol)
    (org_edges || face.edges).each { |e| e.erase! if e.valid? }
    face = new_faces.first
    return unless face && face.valid?
    org_edges = !inward ? face.edges : nil
    new_faces = MH::Geo::Offset.faces(face, -2 * tol)
    (org_edges || face.edges).each { |e| e.erase! if e.valid? }
    face = new_faces.first
    return unless face && face.valid?
    org_edges = inward ? face.edges : nil
    new_faces = MH::Geo::Offset.faces(face, tol)
    (org_edges || face.edges).each { |e| e.erase! if e.valid? }
    new_faces.first
  end
  def self.delete_inside(faces)
    faces.each do |f|
      next unless f.valid?
      f.erase! if inside_face?(f)
    end
    faces.map { |f, t| f.valid? ? [f, t] : nil }.compact
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
  def self.safe_to_merge?(f)
    stack = f.outer_loop.edges
    edge = stack.shift
    direction = edge.line[1]
    until stack.empty?
      edge = stack.shift
      return true unless edge.line[1].parallel?(direction)
    end
    false
  end
  def self.all_coplanar?(faces)
    return true if faces.nil? || faces.length < 2
    faces.all? { |f| f.normal.parallel?(faces.first.normal) }
  end
  def self.inner_loops(face)
    face.loops - [face.outer_loop]
  end
  def self.orient_normal(input, target)
    ref = target.normal
    faces = input.is_a?(Array) ? input : [input]
    faces.each { |f| f.reverse! unless f.normal.samedirection?(ref) }
  end
  def self.faces_coplanar?(f1, f2)
    vertices = f1.vertices + f2.vertices
    plane = Geom.fit_plane_to_points(vertices)
    vertices.all? { |v| v.position.on_plane?(plane) }
  end
  def self.calc_distance(f1, f2)
    pt1 = f1.bounds.center
    pt2 = f2.bounds.center
    pt1.distance(pt2)
  end
  def self.convex?(f1, f2)
    common_edges = f1.edges & f2.edges
    return nil if common_edges.empty?
    e = common_edges[0]
    a = f1.bounds.center
    b = f2.bounds.center
    c = Geom::Point3d.new(
      (e.start.position.x + e.end.position.x) / 2,
      (e.start.position.y + e.end.position.y) / 2,
      (e.start.position.z + e.end.position.z) / 2
    )
    n1 = f1.normal
    n2 = f2.normal
    edge_vec = e.start.position.vector_to(e.end.position)
    cross = n1 * n2
    sign = cross.dot(edge_vec)
    sign < 0
  end
  def self.on_outer?(face, bb, ent)
    pt = face.bounds.center
    pt = pt.transform(ent.transformation)
    [0, 1, 2].each do |i|
      return true if (pt[i] - bb.min[i]).abs < MH::Geo::TOL
      return true if (pt[i] - bb.max[i]).abs < MH::Geo::TOL
    end
    false
  end
  def self.merge_coplanar(faces)
    faces.each do |item|
      f, transform = item
      next unless f.valid?
      f.edges.each do |e|
        e.erase! if e.valid? && e.is_a?(Sketchup::Edge) && MH::Geo::Edge.coplanar?(e)
      end
    end
    faces.map { |item| item[0].valid? ? item : nil }.compact
  end
  def self.duplicate?(f1, f2)
    return false if f1 == f2
    v1 = f1.outer_loop.vertices
    v2 = f2.outer_loop.vertices
    return true if (v1 - v2).empty? && (v2 - v1).empty?
    false
  end
  def self.get_local_bounding(face, transform = IDENTITY)
    edge = face.edges.max_by { |e| e.length }
    p1 = edge.start.position.transform(transform)
    p2 = edge.end.position.transform(transform)
    x_axis = (p2 - p1).normalize
    normal = face.normal.transform(transform)
    y_axis = normal.cross(x_axis).normalize
    vertices = face.outer_loop.vertices.map { |v| v.position.transform(transform) }
    local_coords = vertices.map do |pt|
      vec = p1.vector_to(pt)
      [vec.dot(x_axis), vec.dot(y_axis)]
    end
    xs = local_coords.map { |c| c[0] }
    ys = local_coords.map { |c| c[1] }
    x_min, x_max = xs.min, xs.max
    y_min, y_max = ys.min, ys.max
    [
      p1.offset(x_axis, x_min).offset(y_axis, y_min),
      p1.offset(x_axis, x_max).offset(y_axis, y_min),
      p1.offset(x_axis, x_max).offset(y_axis, y_max),
      p1.offset(x_axis, x_min).offset(y_axis, y_max)
    ]
  end
  def self.orient(faces)
    return [] if faces.length < 2
    adj = {}
    faces.each { |f| adj[f] = [] }
    faces.each do |f|
      f.edges.each do |e|
        e.faces.each do |nf|
          next if nf == f
          adj[f] << nf if faces.include?(nf)
        end
      end
    end
    deg1 = adj.select { |k, v| v.length == 1 }.keys
    is_stripe = deg1.length == 2
    is_loop = deg1.length == 0
    ordered = []
    if is_stripe
      start = deg1.first
      cur = start
      prev = nil
      while cur
        ordered << cur
        nxt = adj[cur].find { |x| x != prev }
        prev = cur
        cur = nxt
      end
      return ordered
    end
    if is_loop
      start = faces.max_by { |f| f.area }
      cur = start
      prev = nil
      begin
        ordered << cur
        nxt = adj[cur].find { |x| x != prev }
        prev = cur
        cur = nxt
      end until cur == start
      return ordered
    end
    faces
  end
  def self.unwrap(faces, trans: IDENTITY, material: nil, flatten: false, entities: Sketchup.active_model.active_entities)
    return nil if faces.length < 2
    return nil if all_coplanar?(faces)
    gx = entities.add_group
    flags = {}
    faces.each do |f|
      f.edges.each do |e|
        flags[e] = { soft: e.soft?, smooth: e.smooth?, hidden: e.hidden? }
      end
    end
    faces.each do |face|
      outer_loop = face.outer_loop
      inner_loops = inner_loops(face)
      new_face = gx.entities.add_face(outer_loop.vertices)
      inner_loops.each do |loop|
        h = gx.entities.add_face(loop.vertices)
        gx.entities.erase_entities(h) if h
      end
      orient_normal(new_face, face)
    end
    gx.entities.grep(Sketchup::Edge).each do |e2|
      flags.each do |e1, data|
        if MH::Geo::Edge.same?(e1, e2)
          e2.soft = data[:soft]
          e2.smooth = data[:smooth]
          e2.hidden = data[:hidden]
        end
      end
    end
    gx.transformation = trans
    exploded_faces = gx.explode.grep(Sketchup::Face)
    if material
      exploded_faces.each { |f| f.material = material }
    end
    faces = orient(exploded_faces)
    faces.reverse!
    start_position = faces[0].edges[0].vertices[0].position
    start_normal = faces[0].normal
    g = entities.add_group
    g.transformation = Geom::Transformation.new(start_position, start_normal)
    (1...faces.length).each { |i|
      cedge = faces[i].edges & faces[i - 1].edges
      tnormal = faces[i].normal
      onormal = faces[i - 1].normal
      rot = tnormal.angle_between(onormal)
      g2 = entities.add_group(faces[i - 1])
      g.entities.add_instance(
        g2.definition, g.transformation.inverse * g2.transformation
      )
      g2.erase!
      if rot != 0.0
        cr = tnormal.cross(onormal)
        t1 = Geom::Transformation.rotation(cedge[0].start, cr, -rot)
        g.transform!(t1)
      end
    }
    g2 = entities.add_group(faces.last)
    g.entities.add_instance(
      g2.definition, g.transformation.inverse * g2.transformation
    )
    g2.erase!
    g.entities.grep(Sketchup::Group).each { |x| x.explode }
    if flatten
      face = g.entities.grep(Sketchup::Face).first
      normal = face.normal
      normal.transform!(g.transformation)
      z = Geom::Vector3d.new(0, 0, 1)
      unless normal.parallel?(z)
        axis = normal.cross(z)
        angle = normal.angle_between(z)
        t = Geom::Transformation.rotation(g.transformation.origin, axis, angle)
        g.transform!(t)
      end
    end
    g
  end
  def self.build(start_face, max_angle_deg = 20)
    return unless start_face.is_a?(Sketchup::Face)
    max_angle = max_angle_deg.degrees
    result, queue, visited = [], [start_face], {}
    while (f = queue.shift)
      next if visited[f]
      visited[f] = true
      result << f
      f.edges.each do |e|
        e.faces.grep(Sketchup::Face).each do |nf|
          next if nf == f || visited[nf]
          queue << nf if f.normal.angle_between(nf.normal) < max_angle
        end
      end
    end
    result
  end
end

