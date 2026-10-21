# encoding: utf-8
# MH_PK_Addon — pick mat xuyen nested group/component + chu trinh Tab lat mat doi dien.
# HoverCtx (Hash): {kind: :face|:marker, face:, transform:, target:, target_world_tr:, path:, marker:}

module MH_PK_Addon
  module Picker
    PARALLEL_DOT = 0.999
    OVERLAP_MIN = 0.3

    # Pick tai (x, y). Marker trong path thang truoc face.
    def self.pick(view, x, y)
      ph = view.pick_helper(x, y, 6)
      count = ph.do_pick(x, y)
      return nil if count <= 0

      count.times do |i|
        path = ph.path_at(i)
        next unless path && !path.empty?

        marker = path.find { |entity| MH_PK_Addon.pk_marker?(entity) }
        if marker
          return { kind: :marker, marker: marker, path: path, transform: ph.transformation_at(i) }
        end

        leaf = path.last
        next unless leaf.is_a?(Sketchup::Face) && leaf.valid?

        target = owning_target(path)
        next unless target

        return {
          kind: :face,
          face: leaf,
          transform: ph.transformation_at(i),
          target: target,
          target_world_tr: target_world_transform(path, target),
          path: path
        }
      end
      nil
    rescue
      nil
    end

    # Group/Component gan face nhat trong path (khong phai marker).
    def self.owning_target(path)
      path.reverse_each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        next if MH_PK_Addon.pk_marker?(entity)
        return entity if MH_PK_Addon.target_entities(entity)
      end
      nil
    rescue
      nil
    end

    # World transform cua target tinh tu path (nhanh hon walk toan model).
    def self.target_world_transform(path, target)
      tr = Geom::Transformation.new
      path.each do |entity|
        break if entity == target && !(entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
        if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          tr *= entity.transformation
          return tr if entity == target
        end
      end
      MH_PK_Addon.entity_world_transform(target)
    rescue
      Geom::Transformation.new
    end

    # Chu trinh Tab: [mat dang hover] + cac mat doi song (uu tien) + cac mat song song khac.
    def self.face_cycle(ctx)
      face = ctx[:face]
      return [face] unless face && face.valid?

      target = ctx[:target]
      ents = MH_PK_Addon.target_entities(target)
      return [face] unless ents

      world_tr = ctx[:transform]
      n = face.normal.transform(world_tr)
      return [face] if n.length <= 0
      n.normalize!

      anti = []
      para = []
      MH_PK_Addon.faces_for_placement(ents).each do |candidate|
        next if candidate == face
        m = candidate.normal.transform(world_tr)
        next if m.length <= 0
        m.normalize!
        dot = n.dot(m)
        if dot < -PARALLEL_DOT
          anti << candidate
        elsif dot > PARALLEL_DOT
          para << candidate
        end
      end

      anti = anti.select { |candidate| projected_overlap?(face, candidate, world_tr) }
      anti.sort_by! { |candidate| plane_distance(face, candidate, world_tr).abs }
      para.sort_by! { |candidate| plane_distance(face, candidate, world_tr).abs }
      [face] + anti + para
    rescue
      [ctx[:face]].compact
    end

    def self.plane_distance(base_face, other_face, world_tr)
      n = base_face.normal.transform(world_tr)
      return 0.0 if n.length <= 0
      n.normalize!
      base_pt = base_face.bounds.center.transform(world_tr)
      other_pt = other_face.bounds.center.transform(world_tr)
      base_pt.vector_to(other_pt).dot(n)
    rescue
      0.0
    end

    # Bbox cua other chieu len mat base co chong len bbox base >= OVERLAP_MIN?
    def self.projected_overlap?(base_face, other_face, world_tr)
      base_rect = face_screen_rect_on_plane(base_face, base_face, world_tr)
      other_rect = face_screen_rect_on_plane(base_face, other_face, world_tr)
      return false unless base_rect && other_rect

      ix = [base_rect[1], other_rect[1]].min - [base_rect[0], other_rect[0]].max
      iy = [base_rect[3], other_rect[3]].min - [base_rect[2], other_rect[2]].max
      return false if ix <= 0 || iy <= 0

      base_area = (base_rect[1] - base_rect[0]) * (base_rect[3] - base_rect[2])
      return true if base_area <= 0

      (ix * iy) / base_area >= OVERLAP_MIN
    rescue
      true
    end

    # Rect [min_x, max_x, min_y, max_y] cua face trong he truc 2D tren mat base (world).
    def self.face_screen_rect_on_plane(base_face, face, world_tr)
      n = base_face.normal.transform(world_tr)
      return nil if n.length <= 0
      n.normalize!
      x_axis = n.axes[0]
      y_axis = n.axes[1]
      origin = base_face.bounds.center.transform(world_tr)

      xs = []
      ys = []
      face.outer_loop.vertices.each do |v|
        pt = v.position.transform(world_tr)
        vec = origin.vector_to(pt)
        xs << vec.dot(x_axis)
        ys << vec.dot(y_axis)
      end
      return nil if xs.empty?

      [xs.min, xs.max, ys.min, ys.max]
    rescue
      nil
    end

    # Tesselation cache cho highlight — chi tinh lai khi mat doi.
    def self.highlight_mesh(face, world_tr)
      key = [face.entityID, world_tr.to_a]
      return @mesh_cache[1] if @mesh_cache && @mesh_cache[0] == key

      pts = face.outer_loop.vertices.map { |v| v.position.transform(world_tr) }
      mesh =
        begin
          { fill: Geom.tesselate(pts), loop: pts }
        rescue
          { fill: nil, loop: pts }
        end
      @mesh_cache = [key, mesh]
      mesh
    rescue
      nil
    end

    def self.clear_cache
      @mesh_cache = nil
    end

    def self.draw_highlight(view, face, world_tr, color)
      return unless face && face.valid?

      mesh = highlight_mesh(face, world_tr)
      return unless mesh

      view.drawing_color = color
      if mesh[:fill] && !mesh[:fill].empty?
        fill2d = mesh[:fill].map do |pt|
          sp = view.screen_coords(pt)
          Geom::Point3d.new(sp.x, sp.y, 0)
        end
        view.draw2d(GL_TRIANGLES, fill2d)
      end
      view.line_width = 4
      view.drawing_color = Sketchup::Color.new(color.red, color.green, color.blue, 255)
      if mesh[:loop] && mesh[:loop].length >= 2
        loop2d = mesh[:loop].map do |pt|
          sp = view.screen_coords(pt)
          Geom::Point3d.new(sp.x, sp.y, 0)
        end
        view.draw2d(GL_LINE_LOOP, loop2d)
      end
    rescue
      nil
    end
  end
end
