module MH::Panel::Material
  def self.create_color(rgb, alpha = 1.0)
    model = Sketchup.active_model
    color_suffix = rgb.gsub(',', '_')
    alpha_suffix = (alpha * 100).to_i
    mat_name = "WPS_#{color_suffix}_#{alpha_suffix}"
    material = model.materials[mat_name]
    unless material
      material = model.materials.add(mat_name)
      rgb_arr = rgb.split(',').map(&:to_i)
      material.color = Sketchup::Color.new(rgb_arr[0], rgb_arr[1], rgb_arr[2])
      material.alpha = alpha
    end
    material
  end

  LED_PNG_BASE64 = "iVBORw0KGgoAAAANSUhEUgAAAAoAAAPoCAYAAADnVm+pAAAACXBIWXMAAC4jAAAuIwF4pT92AAAGvmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNS42LWMxNDggNzkuMTY0MDM2LCAyMDE5LzA4LzEzLTAxOjA2OjU3ICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdEV2dD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlRXZlbnQjIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjEuMCAoV2luZG93cykiIHhtcDpDcmVhdGVEYXRlPSIyMDIyLTExLTAyVDIxOjEyOjAyKzA3OjAwIiB4bXA6TWV0YWRhdGFEYXRlPSIyMDI1LTEyLTMxVDExOjMxOjMxKzA3OjAwIiB4bXA6TW9kaWZ5RGF0ZT0iMjAyNS0xMi0zMVQxMTozMTozMSswNzowMCIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDo2ZDE3ODBkMC05MGMwLTgxNGQtOTAzYS01MzZmYzQ5M2U1MzAiIHhtcE1NOkRvY3VtZW50SUQ9ImFkb2JlOmRvY2lkOnBob3Rvc2hvcDo0Y2IyMGM0Yi00NmE0LTE2NGYtOTBjYi1lYTNmNDNhNTQ0ZjQiIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRpZDo2OTczOGU3OC1kNzU4LWFhNDUtYTYxMy0zZmVhYmFlNDIwNjEiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiBwaG90b3Nob3A6SUNDUHJvZmlsZT0ic1JHQiBJRUM2MTk2Ni0yLjEiPiA8eG1wTU06SGlzdG9yeT4gPHJkZjpTZXE+IDxyZGY6bGkgc3RFdnQ6YWN0aW9uPSJjcmVhdGVkIiBzdEV2dDppbnN0YW5jZUlEPSJ4bXAuaWlkOjY5NzM4ZTc4LWQ3NTgtYWE0NS1hNjEzLTNmZWFiYWU0MjA2MSIgc3RFdnQ6d2hlbj0iMjAyMi0xMS0wMlQyMToxMjowMiswNzowMCIgc3RFdnQ6c29mdHdhcmVBZ2VudD0iQWRvYmUgUGhvdG9zaG9wIDIxLjAgKFdpbmRvd3MpIi8+IDxyZGY6bGkgc3RFdnQ6YWN0aW9uPSJzYXZlZCIgc3RFdnQ6aW5zdGFuY2VJRD0ieG1wLmlpZDoyZWEzM2Q5Yi0xOWYzLWFlNDYtYjVlMS0yYjVlMGVjNmIyNmYiIHN0RXZ0OndoZW49IjIwMjItMTEtMDJUMjE6MTI6MDIrMDc6MDAiIHN0RXZ0OnNvZnR3YXJlQWdlbnQ9IkFkb2JlIFBob3Rvc2hvcCAyMS4wIChXaW5kb3dzKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6NmQxNzgwZDAtOTBjMC04MTRkLTkwM2EtNTM2ZmM0OTNlNTMwIiBzdEV2dDp3aGVuPSIyMDI1LTEyLTMxVDExOjMxOjMxKzA3OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjEuMCAoV2luZG93cykiIHN0RXZ0OmNoYW5nZWQ9Ii8iLz4gPC9yZGY6U2VxPiA8L3htcE1NOkhpc3Rvcnk+IDwvcmRmOkRlc2NyaXB0aW9uPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiA8P3hwYWNrZXQgZW5kPSJyIj8+IXVe+gAABW5JREFUeNrtXc2O4zYM/r6MZ7a7nRY9FX2JPnQfpC/UQw/TYwuzh1ES25FsSktHoi0DgwQbgiIp/ovyDuMf+BPArwBeAfyD+fMTgH8B/DUEoN8C4LcF4M8BEEMAeAufrwvANwAE8DoA+ADwNQB9LAAlYPwYoHyGgP6H8P3L4vcvAF4AvA0A3sPfAGBcAL4D+A/A+xA4/RqI/jHCzCuAb8OEM0SWRvjtbQg0XJ9LgpeXLK5FASdZGCsCykIJljLMZ0aNcaoIS6W47tS4hRFajCjCCAXGm1ZL4DCGUQCMg2QsLQHrSwJwLNoZWVlaPCmuGpATvWPCU/BwXHfADtgMoEgXTwfsgN2uO2AHzFez3RSXBEQ+P4H79+vvN4zXf5hq/PR738IOeHDjknPKUcwBuz52NTt05+NYLqXbtc0WSvs0ihyIme4fO2AH7DnuyfJwF3stBxJ4V1z3LqW7vQ7YATNtRqwBu8A7YAc8darAejTusLSHeTNrGnlODec5Zws9AMri72FXws7Q3FPwlHI0X5oOaDznzqTd3XT52VR8ikZMadRgZATB9WGKGfr2PaQasKL20N6uvQBuydFNOpOd97TscWvRqDbXDDnu4AAOFV2r0XihA6612rNHjnvI3CxV6pXX1+sY9XatBaTW99DXzjzb49a0a71SsJ7vOXGFVIPGjFrhDrg8q5niKMtx16jQezOe065hbtc3QLlf174uynuFPKGRAk5o5CqNTAWurVSBKcD10r5Ejmy5nqnTS9nBpdjLMRujOjc7V+Sy9z3aLGWiPSuBplCOK7qZo4/cMBsul2bOXq/7xxUaWa6Ppj0pD/lj+zSSSozTe5lRbQx3NW9cr3loMhJdeYvoMo+ucxopdxVmafVh32Czj9cn7Zt56ONm9aS2hs543RlKMK8I15xb4dQM4jnFznEmmrFvxRk+oUJqP0s5Vm6WXe5puU5pmcwxSogdj3Uhdzvnon2FdGdmA2Pvm/n3FK5qVysaNWFGNA4g/DYowwwGsKKG73fuKokM4FNuwyJjTmCk7Jb3eO+b3eSYwiiTanhVjozGQtsJDfva9Wmd4dX8ESb547Fys3o117H64dPc8RGjaLsKzK25SmbixgjGsZjrEZ8v9o3RWP422+fXCjX10Uvno8okYMYxoIOK/Zx9ilNG103FFS2NjMlRZFHQaHwPXebhDjIpaqOrvV2b+0fdVkcEnijMc+prF5Gr2mlzVY/rJRZWyUh5pMmrmufXHuJMMY2zQ7zUfM/D2x3FmV1vdQslYLxcNuTIB7vm5+cs0IwJu7Y5L9RzPc5pfMgARgBjzlyzi5OKNjpI7qsP2scZR57CriflYa8vDqa5d4iFJTTSpLe3U62gOmPfu+ZScU2bOFOvj3usc4UDTRactJ7hbsNKVeVodrtALZ6LeUByk/eMkzwnVivUznFHBY3Hq2ccdLlc9cMPE2fUM5qW9Qw95D23xtVavweLfk/socvatfcpnuLDq6Zc/US836n4bjlu9cOh74fb91KyrVAiNKrfEtPKHAAUNO4yrFQQr83kOD2NKtbHu07mDLDk6yOatetMGmWFZdkvzuynj+3P4/a5ve/LpHz1pJ7vKS7ZXLfrzfSxkNb+seY7U9U+nNZ7TXM5FlghzP1jwzRW1J4Wqjg7DbdPPq73Zz5vy8zvaSbuz8S+M3vpJmJh1/DWALO5Vr9DI4URqN0P52YG8JAqqOsZM99DP96s5VhY1kx9cp+CDdi1lVL0ONMsjR52Zt//x8fErqnv7R0qVTjUXpdwrevtdd/zFFMgT2kz2jx8vculXhqThD0P4+ad4CzxcAXjrSbOHvrachXjgF9+//uUPrwDdsAywP8BZ+yDzUbS9/wAAAAASUVORK5CYII="

  def self.led_texture_path
    temp_dir = File.join(ENV['TEMP'] || ENV['TMPDIR'] || '/tmp')
    path = File.join(temp_dir, 'wps_led.png')
    unless File.exist?(path)
      require 'base64'
      File.binwrite(path, Base64.decode64(LED_PNG_BASE64))
    end
    path
  end

  def self.create_led_material(rgb, alpha = 0.5)
    model = Sketchup.active_model
    color_suffix = rgb.gsub(',', '_')
    mat_name = "WPS_LED_#{color_suffix}"
    mat = model.materials[mat_name]
    unless mat
      mat = model.materials.add(mat_name)
      mat.texture = led_texture_path
    end
    rgb_arr = rgb.split(',').map(&:to_i)
    mat.color = Sketchup::Color.new(rgb_arr[0], rgb_arr[1], rgb_arr[2])
    mat.alpha = alpha
    mat
  end

  def self.align_texture(group)
    return unless MH::Panel.is_container?(group) && group.valid?
    mat = group.material
    return unless mat && mat.texture
    entities = group.definition.entities
    faces = entities.grep(Sketchup::Face)
    return if faces.empty?
    faces.each { |f| f.material ||= mat }
    visited = Set.new
    faces.each do |f|
      next if visited.include?(f)
      next unless f.material && f.material.texture
      island = collect_connected_faces(f, visited)
      align_island(island)
    end
  end

  def self.align_island(island)
    return if island.empty?
    edges = island.flat_map(&:edges).uniq
    longest = edges.max_by(&:length)
    anchor = island.find { |f| f.edges.include?(longest) }
    return unless anchor
    align_face_to_longest_edge(anchor)
    mat = anchor.material
    return unless mat && mat.texture
    done = { anchor => true }
    queue = [anchor]
    while queue.any?
      current = queue.shift
      current.edges.each do |edge|
        edge.faces.each do |neighbor|
          next if neighbor == current || done[neighbor]
          next unless island.include?(neighbor)
          spread_front_uv(current, neighbor, mat)
          done[neighbor] = true
          queue << neighbor
        end
      end
    end
  end

  def self.align_face_to_longest_edge(face)
    mat = face.material
    return unless mat && mat.texture
    tex = mat.texture
    origin = find_uv_origin(face)
    long_edge = face.edges.max_by(&:length)
    v = long_edge.line[1].clone
    v.length = tex.width
    if tex.width < tex.height
      v = v.transform(Geom::Transformation.rotation(origin, face.normal, Math::PI / 2))
    end
    face.position_material(mat, [origin, [0, 0, 0], origin + v, [1, 0, 0]], true)
  end

  def self.find_uv_origin(face)
    verts = face.outer_loop.vertices
    long_edge = face.edges.max_by(&:length)
    x_axis = (long_edge.end.position - long_edge.start.position).normalize
    y_axis = x_axis.cross(face.normal).normalize
    origin = long_edge.start.position
    coords = verts.map { |v|
      [(v.position - origin).dot(x_axis), (v.position - origin).dot(y_axis), v]
    }
    xs = coords.map { |c| c[0] }
    ys = coords.map { |c| c[1] }
    corners = [
      [xs.min, ys.min], [xs.max, ys.min],
      [xs.max, ys.max], [xs.min, ys.max]
    ]
    corners.each do |bx, by|
      verts.each do |v|
        next if v.edges.any? { |e| e.soft? || e.hidden? || e.smooth? }
        lx = (v.position - origin).dot(x_axis)
        ly = (v.position - origin).dot(y_axis)
        return v.position if (lx - bx).abs < 1e-4 && (ly - by).abs < 1e-4
      end
    end
    verts.first.position
  end

  def self.spread_front_uv(source, target, material)
    shared = (source.edges & target.edges).first
    return unless shared
    uvh = source.get_UVHelper(true)
    va, vb = shared.vertices
    uvq_a = uvh.get_front_UVQ(va.position)
    uvq_b = uvh.get_front_UVQ(vb.position)
    uv_a = Geom::Point3d.new(uvq_a.x / uvq_a.z, uvq_a.y / uvq_a.z, 0)
    uv_b = Geom::Point3d.new(uvq_b.x / uvq_b.z, uvq_b.y / uvq_b.z, 0)
    target.material = material
    target.position_material(material, [va.position, uv_a, vb.position, uv_b], true)
  end

  def self.collect_connected_faces(face, visited)
    return [] if !face.valid? || visited.include?(face)
    visited.add(face)
    mat = face.material
    result = [face]
    face.edges.each do |e|
      e.faces.each do |adj|
        next if adj == face || !adj.valid? || visited.include?(adj)
        next if adj.material != mat
        if e.soft? || e.smooth? || e.hidden?
          result.concat(collect_connected_faces(adj, visited))
        end
      end
    end
    result
  end

  def self.propagate_uv(faces, material, anchor_point, u_direction, v_direction, tex_size)
    return unless faces.any? && material.texture

    material.texture.size = [tex_size, tex_size]
    first_face = faces.first
    u_dir = u_direction.normalize
    v_dir = v_direction.normalize

    p1 = anchor_point
    p2 = anchor_point.offset(u_dir, tex_size)
    p3 = anchor_point.offset(u_dir, tex_size).offset(v_dir, tex_size)
    p4 = anchor_point.offset(v_dir, tex_size)

    first_face.position_material(material, [
      p1, [0, 1, 0], p2, [1, 1, 0], p3, [1, 0, 0], p4, [0, 0, 0]
    ], true)
    first_face.position_material(material, [
      p1, [1, 1, 0], p2, [0, 1, 0], p3, [0, 0, 0], p4, [1, 0, 0]
    ], false)

    done = { first_face => true }
    queue = [first_face]
    while queue.any?
      current = queue.shift
      current.edges.each do |edge|
        edge.faces.each do |neighbor|
          next if neighbor == current || done[neighbor]
          copy_uv(current, neighbor, material, edge)
          done[neighbor] = true
          queue << neighbor
        end
      end
    end
  end

  def self.copy_uv(source, target, material, shared_edge)
    va, vb = shared_edge.vertices
    uvh_front = source.get_UVHelper(true, false)
    uvq_a = uvh_front.get_front_UVQ(va.position)
    uvq_b = uvh_front.get_front_UVQ(vb.position)
    uv_a = Geom::Point3d.new(uvq_a.x / uvq_a.z, uvq_a.y / uvq_a.z, 0)
    uv_b = Geom::Point3d.new(uvq_b.x / uvq_b.z, uvq_b.y / uvq_b.z, 0)
    mapping_front = [va.position, uv_a, vb.position, uv_b]
    target.position_material(material, mapping_front, true)

    uvh_back = source.get_UVHelper(false, true)
    uvq_a_b = uvh_back.get_back_UVQ(va.position)
    uvq_b_b = uvh_back.get_back_UVQ(vb.position)
    uv_a_b = Geom::Point3d.new(uvq_a_b.x / uvq_a_b.z, uvq_a_b.y / uvq_a_b.z, 0)
    uv_b_b = Geom::Point3d.new(uvq_b_b.x / uvq_b_b.z, uvq_b_b.y / uvq_b_b.z, 0)
    mapping_back = [va.position, uv_a_b, vb.position, uv_b_b]
    target.position_material(material, mapping_back, false)
  end
end
