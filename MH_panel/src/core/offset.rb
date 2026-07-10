if defined?(MH::Geo::Offset) &&
   defined?(MH::Panel::Offset) &&
   MH::Panel::Offset.equal?(MH::Geo::Offset)
  # MH::Panel::Offset is an alias to the shared implementation; do not reopen it
  # with the legacy panel copy or it will overwrite MH::Geo::Offset methods.
else
module MH::Panel::Offset
  def self.offset_face_pts(face, offset)
    verts = face.outer_loop.vertices.map { |v| v.position }
    offset_pts(verts, face.normal, offset)
  end
  def self.moffset_old(face, dist, ent)
    return nil unless dist.is_a?(Numeric) && dist != 0
    pts = []
    verts = face.outer_loop.vertices
    n = verts.length
    plane_normal = face.normal
    n.times do |i|
      a = verts[i].position
      b = verts[(i + 1) % n].position
      c = verts[(i + 2) % n].position
      ab = (b - a).normalize
      bc = (c - b).normalize
      offset_dir1 = ab.cross(plane_normal).normalize
      offset_dir2 = bc.cross(plane_normal).normalize
      line1 = [a.offset(offset_dir1, dist), ab]
      line2 = [b.offset(offset_dir2, dist), bc]
      ip = Geom.intersect_line_line(line1, line2)
      pts << ip if ip
    end
    return nil unless pts.length > 2

    create_face_preserving_curves(ent, pts, face)
  end
  def self.moffset(face, dist, ent)
    return nil unless dist.is_a?(Numeric) && dist != 0
    pts = offset_face_pts(face, -dist)
    return nil unless pts && pts.length > 2
    create_face_preserving_curves(ent, pts, face) || ent.add_face(pts)
  end
  def self.create_face_preserving_curves(entities, points, source_face = nil, source_transform = nil, normal = nil)
    if defined?(MH::Geo::Offset) && MH::Geo::Offset.respond_to?(:create_face_preserving_curves)
      return MH::Geo::Offset.create_face_preserving_curves(entities, points, source_face, source_transform, normal)
    end

    entities.add_face(points)
  rescue
    entities.add_face(points) rescue nil
  end
  def self.preserve_offset_curves(source_face, target_face, offset_points, source_transform = nil)
    return target_face unless source_face && source_face.valid?
    return target_face unless target_face && target_face.valid?
    return target_face unless offset_points && offset_points.length >= 3

    loop_edges = source_face.outer_loop.edges
    return target_face unless loop_edges.any? { |edge| arc_curve?(edge.curve) }

    points = offset_points.dup
    points.pop if points.length > 1 && points.first.distance(points.last) < 0.001.mm
    return target_face unless points.length == loop_edges.length

    transform = source_transform || Geom::Transformation.new
    parent = target_face.parent
    entities = parent.respond_to?(:entities) ? parent.entities : parent
    each_loop_arc_run(loop_edges) do |curve, start_index, edge_count|
      add_matching_arc(entities, curve, transform, points, start_index, edge_count)
    end
    target_face
  rescue => e
    MH::Shared.dbg("MH::Geo::Offset preserve curves error: #{e.class}: #{e.message}") if defined?(MH::Shared)
    target_face
  end
  def self.arc_curve?(curve)
    curve && (curve.is_a?(Sketchup::ArcCurve) rescue false)
  end
  def self.each_loop_arc_run(loop_edges)
    i = 0
    while i < loop_edges.length
      curve = loop_edges[i].curve
      unless arc_curve?(curve)
        i += 1
        next
      end
      count = 1
      count += 1 while (i + count) < loop_edges.length && loop_edges[i + count].curve == curve
      yield curve, i, count
      i += count
    end
  end
  def self.add_matching_arc(entities, curve, transform, points, start_index, edge_count)
    return unless edge_count > 1

    n = points.length
    center = curve.center.transform(transform)
    normal = curve.normal.transform(transform)
    return unless normal.length > 0.001.mm
    normal.normalize!
    xaxis = curve.xaxis.transform(transform)
    return unless xaxis.length > 0.001.mm
    xaxis.normalize!
    yaxis = normal.cross(xaxis)
    return unless yaxis.length > 0.001.mm
    yaxis.normalize!

    run_points = (0..edge_count).map { |offset| points[(start_index + offset) % n] }
    radii = run_points.map { |point| point.distance(center) }.select { |radius| radius > 0.001.mm }
    return if radii.empty?

    radius = radii.sum / radii.length
    start_angle = angle_on_axes(run_points.first, center, xaxis, yaxis)
    end_angle = angle_on_axes(run_points.last, center, xaxis, yaxis)
    end_angle = choose_arc_end_angle(start_angle, end_angle, run_points, center, xaxis, yaxis, curve)
    entities.add_arc(center, xaxis, normal, radius, start_angle, end_angle, edge_count)
  end
  def self.angle_on_axes(point, center, xaxis, yaxis)
    vector = center.vector_to(point)
    Math.atan2(vector.dot(yaxis), vector.dot(xaxis))
  end
  def self.choose_arc_end_angle(start_angle, raw_end_angle, points, center, xaxis, yaxis, curve)
    source_sweep = curve.end_angle.to_f - curve.start_angle.to_f
    source_sweep -= 2 * Math::PI while source_sweep > Math::PI * 2
    source_sweep += 2 * Math::PI while source_sweep < -Math::PI * 2
    source_sweep = Math::PI * 2 if source_sweep.abs < 0.001 && (curve.circular? rescue false)
    source_abs = source_sweep.abs

    positive_end = raw_end_angle
    positive_end += 2 * Math::PI while positive_end <= start_angle
    negative_end = raw_end_angle
    negative_end -= 2 * Math::PI while negative_end >= start_angle

    candidates = [positive_end, negative_end]
    candidates.min_by do |candidate_end|
      sweep = candidate_end - start_angle
      score = source_abs > 0.001 ? (sweep.abs - source_abs).abs : sweep.abs
      points[1...-1].to_a.each do |point|
        angle = angle_on_axes(point, center, xaxis, yaxis)
        if sweep > 0
          angle += 2 * Math::PI while angle < start_angle
          score += 1000 unless angle <= candidate_end + 0.01
        else
          angle -= 2 * Math::PI while angle > start_angle
          score += 1000 unless angle >= candidate_end - 0.01
        end
      end
      score
    end
  end
  def self.faces(face, dist)
    begin
      return nil unless face && face.is_a?(Sketchup::Face) && face.valid?
      return nil unless dist && ((dist.class == Float || dist.class == Length) && dist != 0)
      model = Sketchup.active_model
      norm = face.normal
      mat = face.material
      bat = face.back_material
      lay = face.layer
      ents = face.parent.entities
      selected = false
      ss = Sketchup.active_model.selection
      selected = true if ss.to_a.include?(face)
      loop = face.outer_loop
      edges = []
      curves = []
      lines = []
      loop.edges.each { |e|
        if e.curve
          curves << e.curve
          edges << e
          lines << [e.line, e.start.position, e.end.position]
        else
          edges << e
          lines << [e.line, e.start.position, e.end.position]
        end
      }
      curves.uniq!
      verts = loop.vertices
      pts = []
      verts.each_index { |i|
        pt = verts[i].position
        vec1 = pt.vector_to(verts[i - (verts.length - 1)].position).normalize
        vec2 = pt.vector_to(verts[i - 1].position).normalize
        ang = vec1.angle_between(vec2) / 2.0
        vec3 = (vec1 + vec2).normalize
        if vec1.parallel?(vec2)
          ang = 90.degrees
          tpa = pt.offset(vec1)
          tr = Geom::Transformation.rotation(pt, norm, ang)
          tpa.transform!(tr)
          vec3 = pt.vector_to(tpa)
        end
        if vec3 && vec3.valid? && vec3.length > 0
          vec3.length = 0.5.mm
          tpt = pt.offset(vec3)
          if dist > 0
            if face.classify_point(tpt) == Sketchup::Face::PointInside
              vec3.reverse!
            end
          else
            if face.classify_point(tpt) != Sketchup::Face::PointInside
              vec3.reverse!
            end
          end
          vec3.length = (dist / Math::sin(ang)).abs
          pts << pt.offset(vec3)
        end
      }
      dups = []
      dup = pts.dup
      dup.each_with_index { |p, i|
        dus = []
        pts.each_with_index { |pp, ii|
          next if ii == i
          dus << pp if pp == p
        }
        dups << dus
      }
      puds = []
      dups.each { |dup| puds << dup[0] }
      pts = pts - puds
      unless pts[2]
        return nil
      end
      gp = ents.add_group()
      gents = gp.entities
      pts << pts[0]
      gents.add_edges(pts)
      if curves.length == 1 && curves[0].edges.length == edges.length
        looped = true
      else
        looped = false
      end
      togos = []
      tgps = []
      curves.each { |c|
        cpts = []
        c.vertices.each { |v|
          eds = v.edges
          eds.each { |e| eds.delete(e) unless edges.include?(e) }
          pt = v.position
          vec1 = pt.vector_to(eds[0].other_vertex(v).position).normalize
          vec2 = pt.vector_to(eds[1].other_vertex(v).position).normalize
          ang = vec1.angle_between(vec2) / 2.0
          vec3 = (vec1 + vec2).normalize
          if vec1.parallel?(vec2)
            ang = 90.degrees
            tpa = pt.offset(vec1)
            tr = Geom::Transformation.rotation(pt, norm, ang)
            tpa.transform!(tr)
            vec3 = pt.vector_to(tpa)
          end
          if vec3 && vec3.valid? && vec3.length > 0
            vec3.length = 0.5.mm
            tpt = pt.offset(vec3)
            if dist > 0
              if face.classify_point(tpt) == Sketchup::Face::PointInside
                vec3.reverse!
              end
            else
              if face.classify_point(tpt) != Sketchup::Face::PointInside
                vec3.reverse!
              end
            end
            vec3.length = (dist / Math::sin(ang)).abs
            pt.offset!(vec3)
          end
          if cpts[0]
            dup = false
            cpts.each { |p|
              if p == pt
                dup = true
                break
              end
            }
            cpts << pt unless dup
          else
            cpts << pt
          end
        }
        next unless cpts[1]
        cpts << cpts[0] if looped
        tgp = gents.add_group()
        tgp.entities.add_curve(cpts)
        togos << gents.add_edges(cpts)
        tgps << tgp
        if dist < 0
          p = cpts[0]
          v = cpts[1].vector_to(cpts[0])
          rayt = model.raytest([p, v])
          if rayt && p.distance(rayt[0]) <= dist.abs
            tgp.entities.add_curve(p, rayt[0])
            togos << gents.add_edges(cpts)
          end
          rayt = model.raytest([p, v.reverse])
          if rayt && p.distance(rayt[0]) <= dist.abs
            tgp.entities.add_curve(p, rayt[0])
            togos << gents.add_edges(cpts)
          end
          p = cpts[-1]
          v = cpts[-2].vector_to(cpts[-1])
          rayt = model.raytest([p, v])
          if rayt && p.distance(rayt[0]) <= dist.abs
            tgp.entities.add_curve(p, rayt[0])
            togos << gents.add_edges(cpts)
          end
          rayt = model.raytest([p, v.reverse])
          if rayt && p.distance(rayt[0]) <= dist.abs
            tgp.entities.add_curve(p, rayt[0])
            togos << gents.add_edges(cpts)
          end
        end
      }
      togos.flatten!
      togos.uniq!
      gents.erase_entities(togos) if togos[0]
      gedges = gents.grep(Sketchup::Edge)
      togos = []
      gedges.each { |e|
        p0 = e.start.position
        p1 = e.end.position
        di = e.length
        tgps.each { |tgp|
          eds = tgp.entities.grep(Sketchup::Edge)
          eds.each { |ed|
            edi = ed.length
            next unless edi == di
            ep0 = e.start.position
            ep1 = e.end.position
            next unless (ep0 == p0 && ep1 == p1) || (ep0 == p1 && ep1 == p0)
            togos << e
          }
        }
      }
      togos.uniq!
      gents.erase_entities(togos) if togos[0]
      tr = Geom::Transformation.new()
      gents.intersect_with(true, tr, gents, tr, true, gents.to_a)
      gents.intersect_with(true, tr, gents, tr, true, edges)
      if dist < 0
        gedges = gents.grep(Sketchup::Edge)
        vs = []
        gedges.each { |e| vs << e.vertices }
        vs.flatten!
        vs.uniq!
        tgp = gents.add_group()
        vs.each { |v|
          tgp.entities.add_line(v.position, v.position.offset(norm))
        }
        tgp.explode
        gedges = gents.grep(Sketchup::Edge)
        togos = []
        gedges.each { |e|
          togos << e if e.line[1].parallel?(norm)
        }
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        togos = []
        gedges.each { |e|
          done = []
          e.vertices.each { |v|
            lines.each { |a|
              line = a[0]
              pt1 = a[1]
              pt2 = a[2]
              pv = v.position
              pp = pv.project_to_line(line)
              ppbetween = false
              d1 = pp.distance(pt1) + pp.distance(pt2)
              d2 = pt1.distance(pt2)
              if d1 <= d2 || d1 - d2 < 1e-10
                ppbetween = true
              end
              if pv.distance(pp) < dist.abs && ppbetween
                done << 1
              elsif pv.distance(pp) == dist.abs && ppbetween
                done << 0
              end
            }
            if done.length == 2 && done.include?(1)
              togos << e
            elsif done.length >= 4 && (done - [0]).length == done.length / 2
              togos << e
            end
          }
        }
        togos.uniq!
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        ledges = []
        gedges.each { |e| ledges << e if e.start.edges.length == 1 || e.end.edges.length == 1 }
        nedges = []
        ledges.each { |e|
          vs = e.vertices
          vs.each { |v|
            next if v.edges[1]
            pv = v.position
            ve = pv.vector_to(e.other_vertex(v).position).reverse
            rayt = model.raytest([pv, ve])
            if rayt && rayt[1].include?(gp)
              nedges << gents.add_line(pv, rayt[0])
            end
          }
        }
        gents.intersect_with(true, tr, gents, tr, true, gents.to_a)
        gedges = gents.grep(Sketchup::Edge)
        togos = []
        gedges.each { |e|
          togos << e if e.start.edges.length == 1 || e.end.edges.length == 1
        } unless tgps[0]
        togos.uniq!
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        ps = []
        gedges.each { |e|
          e.vertices.each { |v|
            pv = v.position
            rayt = model.raytest([pv, e.line[1]])
            if rayt && rayt[1].include?(gp) && rayt[1][-1].curve
              ps << [pv, rayt[0]]
            end
            rayt = model.raytest([pv, e.line[1].reverse])
            if rayt && rayt[1].include?(gp) && rayt[1][-1].curve
              ps << [pv, rayt[0]]
            end
          }
        }
        tgps.each { |tgp|
          gedges = tgp.entities.grep(Sketchup::Edge)
          e0 = gedges[0].curve.first_edge
          p = e0.start.position
          v = e0.line[1]
          rayt = model.raytest([p, v])
          if rayt && rayt[1].include?(gp) && !e0.curve.edges.include?(rayt[1][-1])
            gents.add_line(p, rayt[0])
          end
          rayt = model.raytest([p, v.reverse])
          if rayt && rayt[1].include?(gp) && e0.curve.edges.include?(rayt[1][-1])
            gents.add_line(p, rayt[0])
          end
          p = e0.end.position
          v = e0.line[1]
          rayt = model.raytest([p, v])
          if rayt && rayt[1].include?(gp) && !e0.curve.edges.include?(rayt[1][-1])
            gents.add_line(p, rayt[0])
          end
          rayt = model.raytest([p, v.reverse])
          if rayt && rayt[1].include?(gp) && e0.curve.edges.include?(rayt[1][-1])
            gents.add_line(p, rayt[0])
          end
        }
        tgp = gents.add_group()
        ps.each { |a| tgp.entities.add_line(a) }
        tgp.explode
        gents.intersect_with(true, tr, gents, tr, true, gents.to_a)
        gents.intersect_with(true, tr, gents, tr, true, edges)
        tgps.each { |tgp|
          eds = tgp.entities.to_a
          verts = []
          newVerts = []
          startEdge = startVert = nil
          next if eds.length < 2
          ents = eds[0].parent.entities
          eds.each { |e| verts << e.vertices }
          verts.flatten!
          vertsShort = []
          vertsLong = []
          verts.each { |v|
            if vertsLong.include?(v)
              vertsShort << v
            else
              vertsLong << v
            end
          }
          if (startVert = (vertsLong - vertsShort)[0]) == nil
            startVert = vertsLong[0]
            closed = true
            startEdge = startVert.edges[0]
          else
            closed = false
            startEdge = (eds & startVert.edges)[0]
          end
          if startVert == startEdge.start
            newVerts = [startVert]
            counter = 0
            while newVerts.length < verts.length
              eds.each { |edge|
                if edge.end == newVerts[-1]
                  newVerts << edge.start
                elsif edge.start == newVerts[-1]
                  newVerts << edge.end
                end
              }
              counter += 1
              if counter > verts.length
                newVerts.reverse!
                reversed = true
              end
            end
          else
            newVerts = [startVert]
            counter = 0
            while newVerts.length < verts.length
              eds.each { |edge|
                if edge.end == newVerts[-1]
                  newVerts << edge.start
                elsif edge.start == newVerts[-1]
                  newVerts << edge.end
                end
              }
              counter += 1
              if counter > verts.length
                newVerts.reverse!
                reversed = true
              end
            end
          end
          newVerts.uniq!
          newnewVerts = []
          newVerts.each_with_index { |v, i|
            break if i == newVerts.length - 1
            newnewVerts << v
            edged = false
            eds.each { |e|
              if e.start.position == v.position and e.end.position == newVerts[1 + i].position
                newnewVerts << newVerts[1 + i]
                edged = true
                break
              elsif e.end.position == v.position and e.start.position == newVerts[1 + i].position
                newnewVerts << newVerts[1 + i]
                edged = true
                break
              end
            }
            break unless edged
          }
          next unless newnewVerts[1]
          newVerts = newnewVerts
          newVerts.reverse! if reversed
          newVerts << newVerts[0] if closed
          ttgp = tgp.entities.add_group()
          ttgp.entities.add_curve(newVerts)
          tgp.entities.erase_entities(eds)
          ttgp.explode
        }
        tgps.each { |tgp|
          next unless tgp.valid?
          es = tgp.entities.grep(Sketchup::Edge)
          cs = []
          es.each { |e| cs << e.curve if e.curve }
          cs.uniq!
          cs.each { |c|
            vs = c.vertices
            gents.add_curve(vs)
          }
          tgp.erase!
        }
        gents.intersect_with(true, tr, gents, tr, true, gents.to_a)
        gents.intersect_with(true, tr, gents, tr, true, edges)
        gedges = gents.grep(Sketchup::Edge)
        tgp = gents.add_group()
        vs = []
        gedges.each { |e| vs << e.vertices }
        vs.flatten!
        vs.uniq!
        vs.each { |v|
          curved = false
          v.edges.each { |e|
            if e.curve
              curved = true
              break
            end
          }
          next if curved && v.edges[1]
          tgp.entities.add_line(v.position, v.position.offset(norm))
        }
        tgp.explode
        gedges = gents.grep(Sketchup::Edge)
        togos = []
        gedges.each { |e| togos << e if e.line[1].parallel?(norm) }
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        togos = []
        gedges.each { |e|
          e.vertices.each { |v|
            done = false
            lines.each { |a|
              line = a[0]
              pt1 = a[1]
              pt2 = a[2]
              pv = v.position
              pp = pv.project_to_line(line)
              ppbetween = false
              d1 = pp.distance(pt1) + pp.distance(pt2)
              d2 = pt1.distance(pt2)
              if d1 <= d2 || d1 - d2 < 1e-10
                ppbetween = true
              end
              if pv.distance(pp) < dist.abs && ppbetween
                togos << e
                done = true
                break
              end
            }
            break if done
          }
        }
        togos.uniq!
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        togos = []
        gedges.each { |e|
          e.vertices.each { |v|
            cp = face.classify_point(v.position)
            unless cp == Sketchup::Face::PointInside || cp == Sketchup::Face::PointOnVertex || cp == Sketchup::Face::PointOnEdge
              togos << e
              break
            end
          }
        }
        togos.uniq!
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        gedges.each { |e| e.find_faces }
        togos = []
        gedges.each { |e| togos << e unless e.faces.length == 1 }
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        cs = []
        gedges.each { |e| cs << e.curve if e.curve && e.curve.edges.length == 1 }
        cs.uniq!
        cs.each { |c|
          next if c.edges[1]
          ed = c.edges[0]
          vs = ed.vertices
          vx = nil
          vs.each { |v|
            (v.edges - [ed]).each { |ee|
              next unless ee.line[1] && ee.line[1].length != 0
              if ee.line[1].parallel?(ed.line[1])
                vx = v
                break
              end
              ang = ee.line[1].angle_between(ed.line[1])
              if ang < 2.degrees || ang > 178.degrees
                vx = v
                break
              end
            }
            break if vx
          }
          next unless vx
          vxx = (vs - [vx])[0]
          vect = vx.position.vector_to(vxx.position)
          tt = Geom::Transformation.translation(vect)
          gents.transform_entities(tt, vx)
        }
        gfaces = gents.grep(Sketchup::Face)
        gfaces.each { |f|
          f.layer = face.layer
          f.material = face.material
          f.back_material = face.back_material
          f.reverse! unless f.normal == norm
        }
        gfaces = gp.explode.grep(Sketchup::Face)
      else
        gedges = gents.grep(Sketchup::Edge)
        vs = []
        gedges.each { |e| vs << e.vertices }
        ps = []
        gedges.each { |e| break
        e.vertices.each { |v|
          p = v.position
          rayt = model.raytest([p, e.line[1]])
          if rayt && rayt[1].include?(gp) && (e.curve && !e.curve.edges.include?(rayt[1][-1]))
            ps << [p, rayt[0]]
          end
          rayt = model.raytest([p, e.line[1].reverse]) && (e.curve && !e.curve.edges.include?(rayt[1][-1]))
          if rayt && rayt[1].include?(gp)
            ps << [p, rayt[0]]
          end
        }
        }
        tgp = gents.add_group()
        ps.each { |a| tgp.entities.add_line(a) }
        tgp.explode
        tgps.each { |tgp| tgp.explode if tgp.valid? }
        gents.intersect_with(true, tr, gents, tr, true, gents.to_a)
        gents.intersect_with(true, tr, gents, tr, true, edges)
        tr = Geom::Transformation.new()
        gents.intersect_with(true, tr, gents, tr, true, gents.to_a)
        gedges = gents.grep(Sketchup::Edge)
        vs = []
        gedges.each { |e| vs << e.vertices }
        vs.flatten!
        vs.uniq!
        tgp = gents.add_group()
        vs.each { |v|
          curved = false
          v.edges.each { |e|
            if e.curve
              curved = true
              break
            end
          }
          next if curved && v.edges[1]
          tgp.entities.add_line(v.position, v.position.offset(norm))
        }
        tgp.explode
        gedges = gents.grep(Sketchup::Edge)
        gedges.each { |e| e.find_faces }
        togos = []
        gedges.each { |e| togos << e if e.line[1].parallel?(norm) }
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        togos = []
        gedges.each { |e| togos << e if e.faces[1] || e.faces.length == 0 }
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        gedges.each { |e| e.find_faces }
        togos = []
        gedges.each { |e| togos << e unless e.faces[0] }
        gents.erase_entities(togos) if togos[0]
        if MH::Panel::Model.active_entities == ents
          tgp = ents.add_group(edges)
        else
          tgp = ents.add_group()
          tgp.entities.add_edges(verts + [verts[0]])
        end
        tgpp = gents.add_instance(tgp.entities.parent, tgp.transformation)
        tgp.erase!
        tr = Geom::Transformation.new()
        tgpp.entities.intersect_with(true, tr, tgpp.entities, tr, true, gents.to_a)
        tgpp.explode
        gfaces = gents.grep(Sketchup::Face)
        togos = []
        gfaces.each { |f| togos << f if f.loops.length == 1 }
        gents.erase_entities(togos) if togos[0]
        gedges = gents.grep(Sketchup::Edge)
        togos = []
        gedges.each { |e| togos << e unless e.faces[0] }
        gents.erase_entities(togos) if togos[0]
        gfaces = gents.grep(Sketchup::Face)
        gfaces.each { |f|
          f.layer = face.layer
          f.material = face.material
          f.back_material = face.back_material
          f.reverse! unless f.normal == norm
        }
        gfaces = gp.explode.grep(Sketchup::Face)
      end
      ss.add(face) if selected && face.valid?
    rescue => e
      gfaces = []
    end
    return gfaces
  end
  def self.edges(edges, dist)
    return nil if edges.length < 2
    return nil unless dist.is_a?(Numeric) && dist != 0
    sorted_edges = sort_connected_edges(edges)
    return nil unless sorted_edges
    verts = get_ordered_vertices(sorted_edges)
    return nil if verts.length < 2
    normal = get_plane_normal(verts)
    return nil unless normal
    offset_chain_pts(verts, normal, dist)
  end
  def self.sort_connected_edges(edges)
    return edges if edges.length <= 1
    sorted = [edges.first]
    remaining = edges[1..-1]
    while remaining.any?
      last_edge = sorted.last
      first_edge = sorted.first
      found = false
      remaining.each do |edge|
        if edge.vertices.any? { |v| last_edge.vertices.include?(v) }
          sorted << edge
          remaining.delete(edge)
          found = true
          break
        elsif edge.vertices.any? { |v| first_edge.vertices.include?(v) }
          sorted.unshift(edge)
          remaining.delete(edge)
          found = true
          break
        end
      end
      break unless found
    end
    sorted
  end
  def self.get_ordered_vertices(edges)
    return [] if edges.empty?
    if edges.length == 1
      return edges.first.vertices.map(&:position)
    end
    verts = []
    first_edge = edges.first
    second_edge = edges[1]
    shared = first_edge.vertices.find { |v| second_edge.vertices.include?(v) }
    start_vert = first_edge.vertices.find { |v| v != shared }
    verts << start_vert.position
    current_vert = shared
    edges.each_with_index do |edge, i|
      next if i == 0
      verts << current_vert.position
      next_edge = edges[i]
      current_vert = next_edge.vertices.find { |v| v.position != current_vert.position }
    end
    verts << current_vert.position if current_vert
    verts
  end
  def self.get_plane_normal(points)
    return nil if points.length < 3
    (0..points.length - 3).each do |i|
      vec1 = points[i + 1] - points[i]
      vec2 = points[i + 2] - points[i + 1]
      normal = vec1.cross(vec2)
      return normal.normalize if normal.valid?
    end
    nil
  end
  def self.peo_offset(face, dist)
    return [] unless face.is_a?(Sketchup::Face) && face.valid?
    refs = face.outer_loop.vertices.map(&:position)
    return [] if refs.size < 2
    refs = peo_ensure_ccw(refs, face)
    normal = face.normal
    scale_x = 1.0
    if face.parent.respond_to?(:transformation) && face.parent.transformation
      sx = face.parent.transformation.xaxis.length.to_f
      scale_x = sx if sx.abs >= 1e-10
    end
    d = dist.to_f / scale_x
    peo_offset_pts(refs, normal, d)
  end
  def self.peo_offset_pts(refs, normal, d)
    return [] if refs.nil? || refs.size < 3 || normal.nil?
    if defined?(MH::Panel::NativeBridge) && MH::Panel::NativeBridge.loaded?
      begin
        res = MH::Panel::NativeBridge.offset_polygon(refs, normal, d)
        return res if res && res.size >= 3
      rescue => e
        MH::Panel.dbg("MH::Panel Native offset_polygon error: #{e.message}")
      end
    end
    pts = refs.map { |p| Geom::Point3d.new(p.x.to_f, p.y.to_f, p.z.to_f) }
    n = pts.size
    edge_normals = []
    n.times do |i|
      t = pts[(i + 1) % n] - pts[i]
      if t.length < 1e-10
        edge_normals << (edge_normals.empty? ? normal : edge_normals.last)
        next
      end
      t = t.normalize
      ne = normal.cross(t)
      ne = ne.normalize if ne.length > 1e-10
      to_prev = pts[(i - 1) % n] - pts[i]
      ne = ne.reverse if to_prev.length > 1e-10 && ne.dot(to_prev) < 0
      edge_normals << ne
    end
    new_pts = []
    n.times do |i|
      i_prev = (i - 1) % n
      n_prev = edge_normals[i_prev]
      n_curr = edge_normals[i]
      p1 = pts[i_prev].offset(n_prev, d)
      q1 = pts[i].offset(n_prev, d)
      p2 = pts[i].offset(n_curr, d)
      q2 = pts[(i + 1) % n].offset(n_curr, d)
      d1 = q1 - p1
      d2 = q2 - p2
      if d1.cross(d2).length < 1e-10
        new_pts << pts[i].offset(n_curr, d)
        next
      end
      d2_perp = normal.cross(d2)
      denom = d1.dot(d2_perp).to_f
      if denom.abs < 1e-10
        new_pts << pts[i].offset(n_curr, d)
        next
      end
      s = (p2 - p1).dot(d2_perp).to_f / denom
      new_pts << Geom::Point3d.new(p1.x + d1.x * s, p1.y + d1.y * s, p1.z + d1.z * s)
    end
    return new_pts unless new_pts.size >= 3
    peo_inset_rectangle_if_degenerate(pts, new_pts, nil, normal, d)
  end
  def self.peo_ensure_ccw(refs, face)
    return refs if refs.nil? || refs.size < 3 || face.nil?
    normal = face.normal
    edge_vec = refs[1] - refs[0]
    if edge_vec.length > 1e-10
      v_x = edge_vec.normalize
    else
      e = face.outer_loop.edges.first
      v = e.end.position - e.start.position
      v_x = v.length > 1e-10 ? v.normalize : Geom::Vector3d.new(1, 0, 0)
    end
    v_y = normal.cross(v_x)
    v_y = v_y.length > 1e-10 ? v_y.normalize : Geom::Vector3d.new(0, 1, 0)
    o = refs[0]
    coords = refs.map { |p| vec = p - o; [vec.dot(v_x), vec.dot(v_y)] }
    area = 0.0
    n = coords.size
    n.times do |i|
      j = (i + 1) % n
      area += coords[i][0] * coords[j][1] - coords[j][0] * coords[i][1]
    end
    area < 0 ? refs.reverse : refs
  end
  def self.peo_face_2d_basis(refs, normal)
    return nil if refs.nil? || refs.size < 2
    o = refs[0]
    edge = refs[1] - o
    v_x = edge.length > 1e-10 ? edge.normalize : Geom::Vector3d.new(1, 0, 0)
    v_y = normal.cross(v_x)
    v_y = v_y.length > 1e-10 ? v_y.normalize : Geom::Vector3d.new(0, 1, 0)
    [o, v_x, v_y]
  end
  def self.peo_signed_area_2d(pts, o, v_x, v_y)
    return 0.0 if pts.nil? || pts.size < 3
    n = pts.size
    area = 0.0
    n.times do |i|
      vec = pts[i] - o
      vec2 = pts[(i + 1) % n] - o
      area += vec.dot(v_x) * vec2.dot(v_y) - vec2.dot(v_x) * vec.dot(v_y)
    end
    area * 0.5
  end
  def self.peo_segments_intersect_2d?(u1, v1, u2, v2, u3, v3, u4, v4)
    cross = ->(ax, ay, bx, by, cx, cy) { (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) }
    d1 = cross.call(u1, v1, u2, v2, u3, v3)
    d2 = cross.call(u1, v1, u2, v2, u4, v4)
    return false if d1 * d2 > 1e-12
    d3 = cross.call(u3, v3, u4, v4, u1, v1)
    d4 = cross.call(u3, v3, u4, v4, u2, v2)
    return false if d3 * d4 > 1e-12
    return false if d1.abs < 1e-12 && d2.abs < 1e-12 && d3.abs < 1e-12 && d4.abs < 1e-12
    true
  end
  def self.peo_polygon_self_intersects_2d?(pts, o, v_x, v_y)
    return false if pts.nil? || pts.size < 4
    uv = pts.map { |p| vec = p - o; [vec.dot(v_x), vec.dot(v_y)] }
    n = uv.size
    n.times do |i|
      i1 = (i + 1) % n
      n.times do |j|
        next if i >= j
        next if (i - j).abs <= 1 || (i == 0 && j == n - 1)
        j1 = (j + 1) % n
        return true if peo_segments_intersect_2d?(uv[i][0], uv[i][1], uv[i1][0], uv[i1][1],
                                                   uv[j][0], uv[j][1], uv[j1][0], uv[j1][1])
      end
    end
    false
  end
  def self.peo_inset_rectangle_if_degenerate(pts, new_pts, face, normal, dist)
    basis = peo_face_2d_basis(pts, normal)
    return new_pts if basis.nil?
    o, v_x, v_y = basis
    area_old = peo_signed_area_2d(pts, o, v_x, v_y).abs
    area_new = peo_signed_area_2d(new_pts, o, v_x, v_y)
    return new_pts if area_old < 1e-10
    use_rect = area_new <= 0 || area_new < area_old * 0.01 ||
               peo_polygon_self_intersects_2d?(new_pts, o, v_x, v_y)
    return new_pts unless use_rect
    ux = pts.map { |p| (p - o).dot(v_x) }
    uy = pts.map { |p| (p - o).dot(v_y) }
    d = dist.to_f.abs
    x1 = ux.min.to_f + d
    x2 = ux.max.to_f - d
    y1 = uy.min.to_f + d
    y2 = uy.max.to_f - d
    return new_pts if x1 >= x2 - 1e-6 || y1 >= y2 - 1e-6
    [[x1, y1], [x2, y1], [x2, y2], [x1, y2]].map do |x, y|
      Geom::Point3d.new(o.x + v_x.x * x + v_y.x * y,
                        o.y + v_x.y * x + v_y.y * y,
                        o.z + v_x.z * x + v_y.z * y)
    end
  end
end
end
