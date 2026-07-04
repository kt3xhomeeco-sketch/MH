require File.join(Sketchup.find_support_file('Plugins'), 'MH_shared.rb')
raise "[MH_fast_rename/contact_planes_v5] requires MH_shared" unless defined?(MH::Text)

model = Sketchup.active_model

sel = model.selection.select { |e|
  e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
}

if sel.length < 2
  UI.messagebox("Hãy chọn ít nhất 2 component hoặc group!")
  return
end

TOL      = 0.05 / 25.4
PENE_TOL = 0.05 / 25.4
MAX_PASS = 20

EXEMPT_KEYWORDS = ["phào", "nẹp", "viền", "chỉ"]

# ──────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────

def obj_name(obj)
  parts = []
  if obj.respond_to?(:definition)
    parts << obj.name.to_s if obj.respond_to?(:name)
    parts << obj.definition.name.to_s
  else
    parts << (obj.name || "").to_s
  end
  parts.join(" ")
end

def fold_text(str)
  MH::Text.fold(str)
end

def exempt_obj?(obj, keywords)
  name = fold_text(obj_name(obj))
  keywords.any? { |kw| name.include?(fold_text(kw)) }
end

def get_faces_world(entity)
  t    = entity.transformation
  ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
  faces = []
  ents.grep(Sketchup::Face) do |face|
    pts = face.vertices.map { |v| t * v.position }
    next if pts.length < 3
    v1 = Geom::Vector3d.new(pts[1].x-pts[0].x, pts[1].y-pts[0].y, pts[1].z-pts[0].z)
    v2 = Geom::Vector3d.new(pts[2].x-pts[0].x, pts[2].y-pts[0].y, pts[2].z-pts[0].z)
    normal = v1.cross(v2)
    next if normal.length < 1e-10
    normal = normal.normalize
    orig_n     = face.normal
    orig_world = t * Geom::Point3d.new(orig_n.x, orig_n.y, orig_n.z)
    orig_o     = t * Geom::Point3d.new(0, 0, 0)
    orig_dir   = Geom::Vector3d.new(orig_world.x-orig_o.x,
                                    orig_world.y-orig_o.y,
                                    orig_world.z-orig_o.z)
    normal = Geom::Vector3d.new(-normal.x,-normal.y,-normal.z) if normal.dot(orig_dir) < 0
    faces << { pts: pts, normal: normal, owner: entity }
  end
  faces
end

def make_perp(n)
  ref = n.x.abs < 0.9 ? Geom::Vector3d.new(1,0,0) : Geom::Vector3d.new(0,1,0)
  ref.cross(n).normalize
end

def make_axes(normal)
  u = make_perp(normal)
  v = normal.cross(u).normalize
  [u, v]
end

def signed_area_2d(poly)
  n = poly.length; area = 0.0
  n.times { |i| j=(i+1)%n; area += poly[i][0]*poly[j][1]-poly[j][0]*poly[i][1] }
  area / 2.0
end

def ensure_ccw(poly)
  signed_area_2d(poly) >= 0 ? poly : poly.reverse
end

def project_pts_onto_plane(pts, normal, d, u, v)
  pts.map { |p|
    vec   = Geom::Vector3d.new(p.x, p.y, p.z)
    t_val = d - vec.dot(normal)
    p2    = Geom::Point3d.new(p.x+t_val*normal.x,
                               p.y+t_val*normal.y,
                               p.z+t_val*normal.z)
    [Geom::Vector3d.new(p2.x,p2.y,p2.z).dot(u),
     Geom::Vector3d.new(p2.x,p2.y,p2.z).dot(v)]
  }
end

def clip_polygon_by_edge(poly, ex1, ey1, ex2, ey2)
  output = []
  return output if poly.empty?
  inside    = lambda { |x,y| (ex2-ex1)*(y-ey1)-(ey2-ey1)*(x-ex1) >= -1e-10 }
  intersect = lambda { |x1,y1,x2,y2|
    dx1=x2-x1; dy1=y2-y1; dx2=ex2-ex1; dy2=ey2-ey1
    denom=dx1*dy2-dy1*dx2
    return [x1,y1] if denom.abs < 1e-10
    t=((ex1-x1)*dy2-(ey1-y1)*dx2)/denom
    [x1+t*dx1, y1+t*dy1]
  }
  n = poly.length
  n.times do |i|
    cur=poly[i]; prev=poly[(i-1+n)%n]
    ci=inside.call(cur[0],cur[1]); pi=inside.call(prev[0],prev[1])
    if ci
      output << intersect.call(prev[0],prev[1],cur[0],cur[1]) unless pi
      output << cur
    elsif pi
      output << intersect.call(prev[0],prev[1],cur[0],cur[1])
    end
  end
  output
end

def polygon_intersection_2d(polyA, polyB)
  a = ensure_ccw(polyA); b = ensure_ccw(polyB)
  result = a.dup
  b.length.times do |i|
    break if result.empty?
    ex1,ey1=b[i]; ex2,ey2=b[(i+1)%b.length]
    result = clip_polygon_by_edge(result, ex1, ey1, ex2, ey2)
  end
  result
end

def unproject_from_2d(pts2d, u, v, normal, d)
  pts2d.map { |x, y|
    bx=x*u.x+y*v.x; by=x*u.y+y*v.y; bz=x*u.z+y*v.z
    t_val = d-(bx*normal.x+by*normal.y+bz*normal.z)
    Geom::Point3d.new(bx+t_val*normal.x, by+t_val*normal.y, bz+t_val*normal.z)
  }
end

def faces_contact?(fa, fb, tol, pene_tol)
  return false unless fa[:normal].dot(fb[:normal]) < -0.99
  d_a = Geom::Vector3d.new(fa[:pts][0].x,fa[:pts][0].y,fa[:pts][0].z).dot(fa[:normal])
  d_b = Geom::Vector3d.new(fb[:pts][0].x,fb[:pts][0].y,fb[:pts][0].z).dot(fa[:normal])
  gap = d_b - d_a
  return false if gap < -pene_tol || gap > tol
  u, v   = make_axes(fa[:normal])
  poly_a = project_pts_onto_plane(fa[:pts], fa[:normal], d_a, u, v)
  poly_b = project_pts_onto_plane(fb[:pts], fa[:normal], d_a, u, v)
  inter  = polygon_intersection_2d(poly_a, poly_b)
  return false if inter.length < 3 || signed_area_2d(inter).abs < 1e-6
  inter
end

# ──────────────────────────────────────────────────────────────
# THAY THẾ plane_cuts_obj? – kiểm tra geometry thực (face)
#
# Trả về TRUE chỉ khi plane cắt XUYÊN QUA ít nhất 1 face thực sự:
#   - Face nằm trên plane (tất cả đỉnh |dist| < tol) → BỎ QUA (face tiếp xúc)
#   - Face có đỉnh ở cả 2 phía (+/-) vượt tol         → CẮT XUYÊN → true
#   - Face hoàn toàn 1 phía                            → bình thường → false
# ──────────────────────────────────────────────────────────────
def plane_cuts_obj?(obj, normal, d, tol)
  t    = obj.transformation
  ents = obj.respond_to?(:definition) ? obj.definition.entities : obj.entities

  ents.grep(Sketchup::Face) do |face|
    dists = face.vertices.map { |v|
      p = t * v.position
      normal.x * p.x + normal.y * p.y + normal.z * p.z - d
    }

    # Face nằm trên plane → đây là face tiếp xúc, bỏ qua
    next if dists.all? { |dist| dist.abs <= tol }

    # Face có đỉnh cả 2 phía → plane cắt xuyên qua geometry thực
    has_pos = dists.any? { |dist| dist >  tol }
    has_neg = dists.any? { |dist| dist < -tol }
    return true if has_pos && has_neg
  end

  false
end

def obj_center(obj)
  bb = obj.bounds
  Geom::Point3d.new((bb.min.x+bb.max.x)/2.0,
                    (bb.min.y+bb.max.y)/2.0,
                    (bb.min.z+bb.max.z)/2.0)
end

def draw_contact_plane(model, extent_objs, normal, d_val, u, v, mat, layer)
  all_u = []; all_v = []
  extent_objs.each do |obj|
    bb = obj.bounds
    8.times do |k|
      x = (k&1)==0 ? bb.min.x : bb.max.x
      y = (k&2)==0 ? bb.min.y : bb.max.y
      z = (k&4)==0 ? bb.min.z : bb.max.z
      vec   = Geom::Vector3d.new(x, y, z)
      t_val = d_val - vec.dot(normal)
      p2    = Geom::Vector3d.new(x+t_val*normal.x,
                                  y+t_val*normal.y,
                                  z+t_val*normal.z)
      all_u << p2.dot(u)
      all_v << p2.dot(v)
    end
  end
  return nil if all_u.empty? || all_v.empty?
  margin   = 2.0 / 25.4
  big_poly = [
    [all_u.min-margin, all_v.min-margin],
    [all_u.max+margin, all_v.min-margin],
    [all_u.max+margin, all_v.max+margin],
    [all_u.min-margin, all_v.max+margin]
  ]
  pts3d = unproject_from_2d(big_poly, u, v, normal, d_val)
  begin
    face = model.active_entities.add_face(pts3d)
    if face.is_a?(Sketchup::Face)
      face.material = mat; face.back_material = mat; face.layer = layer
      return face
    end
  rescue; end
  nil
end

def split_by_plane(grp, normal, d)
  g_pos = grp.select { |obj|
    c = obj_center(obj)
    normal.x*c.x + normal.y*c.y + normal.z*c.z >= d
  }
  g_neg = grp.select { |obj|
    c = obj_center(obj)
    normal.x*c.x + normal.y*c.y + normal.z*c.z < d
  }
  [g_pos, g_neg].reject(&:empty?)
end

def separator_score(grp, normal, d_val, tol, keywords)
  dots = []
  grp.each do |obj|
    next if exempt_obj?(obj, keywords)
    return -1 if plane_cuts_obj?(obj, normal, d_val, tol)
    c = obj_center(obj)
    dots << (normal.x*c.x + normal.y*c.y + normal.z*c.z - d_val)
  end
  n_pos = dots.count { |s| s >= 0 }
  n_neg = dots.count { |s| s <  0 }
  return -1 if n_pos == 0 || n_neg == 0
  [n_pos, n_neg].min.to_f
end

def find_all_separators(grp, tol, pene_tol, keywords)
  return [] if grp.length < 2

  all_faces   = grp.map { |obj| get_faces_world(obj) }
  seen_planes = []
  candidates  = []

  try_add = lambda { |normal, d_val|
    if normal.z < -1e-6 ||
       (normal.z.abs < 1e-6 && normal.y < -1e-6) ||
       (normal.z.abs < 1e-6 && normal.y.abs < 1e-6 && normal.x < -1e-6)
      normal = Geom::Vector3d.new(-normal.x, -normal.y, -normal.z)
      d_val  = -d_val
    end

    dup = seen_planes.any? { |sp|
      sp[:normal].dot(normal) > 0.9999 && (sp[:d] - d_val).abs < tol
    }
    return if dup
    seen_planes << { normal: normal, d: d_val }

    score = separator_score(grp, normal, d_val, tol, keywords)
    return if score < 0

    u, v = make_axes(normal)
    candidates << { normal: normal, d: d_val, u: u, v: v, score: score }
  }

  (0...grp.length).each do |i|
    (i+1...grp.length).each do |j|
      bb_a = grp[i].bounds; bb_b = grp[j].bounds
      next unless (0..2).all? { |ax|
        bb_a.min.to_a[ax] <= bb_b.max.to_a[ax] + tol &&
        bb_b.min.to_a[ax] <= bb_a.max.to_a[ax] + tol
      }

      all_faces[i].each do |fa|
        all_faces[j].each do |fb|
          next unless faces_contact?(fa, fb, tol, pene_tol)

          contact_pt = fa[:pts][0]
          cp_vec     = Geom::Vector3d.new(contact_pt.x,
                                          contact_pt.y,
                                          contact_pt.z)
          # Chỉ giữ lại mặt cắt dọc và ngang (X, Y, Z), bỏ mặt cắt vuông góc (u1, u2)
          [[1,0,0],[0,0,1]].each do |nx,ny,nz|
            n_ax = Geom::Vector3d.new(nx, ny, nz)
            try_add.call(n_ax, cp_vec.dot(n_ax))
          end
        end
      end
    end
  end

  candidates.sort_by { |c| -c[:score] }
end

def find_contacts_in_group(model, grp, mat, layer, tol, pene_tol, keywords)
  return 0 if grp.length < 2
  all_faces   = grp.map { |obj| get_faces_world(obj) }
  seen_planes = []
  drawn       = 0

  # Chỉ trục X (dọc) và Z (ngang), bỏ Y (vuông góc)
  world_axes = [
    Geom::Vector3d.new(1, 0, 0),
    Geom::Vector3d.new(0, 0, 1)
  ]

  (0...grp.length).each do |i|
    (i+1...grp.length).each do |j|
      bb_a = grp[i].bounds; bb_b = grp[j].bounds
      next unless (0..2).all? { |ax|
        bb_a.min.to_a[ax] <= bb_b.max.to_a[ax]+tol &&
        bb_b.min.to_a[ax] <= bb_a.max.to_a[ax]+tol
      }
      all_faces[i].each do |fa|
        all_faces[j].each do |fb|
          next unless faces_contact?(fa, fb, tol, pene_tol)

          contact_pt = fa[:pts][0]
          cp_vec = Geom::Vector3d.new(contact_pt.x, contact_pt.y, contact_pt.z)

          # Chỉ thử 3 trục thế giới X, Y, Z — bỏ mặt cắt vuông góc
          world_axes.each do |normal|
            d_val = cp_vec.dot(normal)

            blocked = grp.any? { |obj|
              !exempt_obj?(obj, keywords) && plane_cuts_obj?(obj, normal, d_val, tol)
            }
            next if blocked

            dup = seen_planes.any? { |sp|
              sp[:normal].dot(normal) > 0.9999 && (sp[:d]-d_val).abs < tol
            }
            next if dup
            seen_planes << { normal: normal, d: d_val }

            u, v = make_axes(normal)
            face = draw_contact_plane(model, grp, normal, d_val, u, v, mat, layer)
            drawn += 1 if face
          end
        end
      end
    end
  end
  drawn
end

# ──────────────────────────────────────────────────────────────
# SETUP
# ──────────────────────────────────────────────────────────────
mat_name = "ContactPlane"
mat      = model.materials[mat_name] || model.materials.add(mat_name)
mat.color = Sketchup::Color.new(0, 180, 255)
mat.alpha  = 0.5

layer_name = "Contact_Planes"
layer = model.layers[layer_name] || model.layers.add(layer_name)

to_erase = model.active_entities.select { |e|
  e.is_a?(Sketchup::Face) && e.layer.name == layer_name
}
model.active_entities.erase_entities(to_erase) unless to_erase.empty?

model.start_operation("Contact planes", true)

total_drawn = 0
pass_num    = 0

groups = [sel.dup]

MAX_PASS.times do |pass_idx|
  pass_num  = pass_idx + 1
  any_split = false
  new_groups = []

  groups.each do |grp|
    if grp.length < 2
      new_groups << grp
      next
    end

    separators = find_all_separators(grp, TOL, PENE_TOL, EXEMPT_KEYWORDS)

    if separators.empty?
      new_groups << grp
      next
    end

    any_split  = true
    sub_groups = [grp]

    separators.each do |sep|
      next_subs = []
      sub_groups.each do |sg|
        score = separator_score(sg, sep[:normal], sep[:d], TOL, EXEMPT_KEYWORDS)
        if score > 0
          draw_contact_plane(model, sg, sep[:normal], sep[:d],
                             sep[:u], sep[:v], mat, layer)
          total_drawn += 1
          next_subs.concat(split_by_plane(sg, sep[:normal], sep[:d]))
        else
          next_subs << sg
        end
      end
      sub_groups = next_subs
    end

    new_groups.concat(sub_groups)
  end

  groups = new_groups
  break unless any_split
end

groups.each do |grp|
  drawn = find_contacts_in_group(model, grp, mat, layer, TOL, PENE_TOL, EXEMPT_KEYWORDS)
  total_drawn += drawn
end

model.commit_operation

exempt_objs  = sel.select { |obj| exempt_obj?(obj, EXEMPT_KEYWORDS) }
exempt_count = exempt_objs.length
all_names    = sel.map { |obj| obj_name(obj) }.first(10).join("\n  ")
exempt_names = exempt_objs.map { |obj| obj_name(obj) }.join("\n  ")

UI.messagebox(
  "✅ Hoàn tất!\n" \
  "Phase 1: #{pass_num} vòng lặp → #{groups.length} nhóm độc lập\n" \
  "Tổng contact plane: #{total_drawn}\n" \
  "Layer: '#{layer_name}'\n" \
  "Chi tiết miễn trừ: #{exempt_count} obj\n" \
  "Tên miễn trừ:\n  #{exempt_names.empty? ? '(không có)' : exempt_names}\n" \
  "--- 10 tên đầu ---\n  #{all_names}"
)
