# encoding: UTF-8
#
# SmartScale::StretchCore -- native one-sided box stretch engine.
#
module SmartScale
  module StretchCore
    AXES = [:x, :y, :z].freeze
    AXIS_INDEX = { x: 0, y: 1, z: 2 }.freeze
    AXIS_VECTOR = {
      x: Geom::Vector3d.new(1, 0, 0),
      y: Geom::Vector3d.new(0, 1, 0),
      z: Geom::Vector3d.new(0, 0, 1)
    }.freeze
    EPS = 1e-6
    MAX_PREVIEW_EDGES = 2000

    Target = Struct.new(:entity, :entities, :transform, :inverse, :vertices)

    module_function

    def stretch_selection(model, plane, delta_vec, min_len: 1.mm)
      return result(false, 0, 'Selection rỗng.') if model.selection.empty?
      return result(false, 0, 'Delta quá nhỏ.') if delta_vec.length <= EPS

      bb = Core.selection_bounds(model)
      return result(false, 0, 'Bounding box không hợp lệ.') if Core.empty_bounds?(bb)
      ok, message = validate_target_length(bb, plane, delta_vec, min_len)
      return result(false, 0, message) unless ok

      model.start_operation('SmartScale Stretch', true)
      targets = targets_for_selection(model, make_unique: true)
      changed = 0
      targets.each { |target| changed += stretch_target(target, plane, delta_vec) }
      model.commit_operation
      result(changed.positive?, changed, changed.positive? ? 'Đã stretch.' : 'Không có geometry phía động.')
    rescue => e
      model.abort_operation rescue nil
      result(false, 0, "#{e.class}: #{e.message}")
    end

    def preview_wireframe(model, plane, delta_vec)
      targets = targets_for_selection(model, make_unique: false)
      segments = []
      targets.each do |target|
        collect_preview_edges(target.entities, target.transform, plane, delta_vec, segments)
        break if segments.length >= MAX_PREVIEW_EDGES
      end
      segments
    rescue
      []
    end

    def targets_for_selection(model, make_unique: false)
      loose_vertices = []
      targets = []
      model.selection.each do |ent|
        if group_or_component?(ent)
          ent.make_unique if make_unique && needs_unique?(ent)
          targets << Target.new(ent, child_entities(ent), ent.transformation,
                                ent.transformation.inverse, nil)
        elsif ent.is_a?(Sketchup::Edge)
          loose_vertices.concat(ent.vertices)
        elsif ent.is_a?(Sketchup::Face)
          loose_vertices.concat(ent.vertices)
        end
      end
      loose_vertices.uniq!
      unless loose_vertices.empty?
        identity = Geom::Transformation.new
        targets << Target.new(nil, model.active_entities, identity, identity, loose_vertices)
      end
      targets
    end

    def stretch_target(target, plane, delta_vec)
      ent = target.entity
      # Instance nam TRON phia dong -> "move" bang cach doi TRANSFORM (giong Fredo),
      # KHONG doi vertex trong def. Neu chi doi vertex, transform giu nguyen ->
      # redraw dung lai theo transform cu -> DC nhay ve cho cu.
      if ent && group_or_component?(ent) &&
         classify_bounds(ent.bounds, Geom::Transformation.new, plane) == :moving
        ent.transformation = Geom::Transformation.translation(delta_vec) * ent.transformation
        return 1
      end

      local_delta = delta_vec.transform(target.inverse)
      if target.vertices
        return move_vertices(target.entities, target.vertices, target.transform, plane, local_delta)
      end
      stretch_entities(target.entities, target.transform, plane, local_delta)
    end

    def axis_value(point, axis)
      case axis
      when :x then point.x
      when :y then point.y
      else point.z
      end
    end

    def side_match?(value, plane)
      if plane[:side] == :minus
        value <= plane[:pos] + EPS
      else
        value >= plane[:pos] - EPS
      end
    end

    def delta_for_axis(axis, amount)
      case axis
      when :x then Geom::Vector3d.new(amount, 0, 0)
      when :y then Geom::Vector3d.new(0, amount, 0)
      else Geom::Vector3d.new(0, 0, amount)
      end
    end

    def shifted_point(point, plane, delta_vec)
      side_match?(axis_value(point, plane[:axis]), plane) ? point.offset(delta_vec) : point
    end

    def validate_target_length(bb, plane, delta_vec, min_len)
      cur = Core.axis_length(bb, plane[:axis])
      amount = axis_value(delta_vec, plane[:axis])
      new_len =
        if plane[:side] == :minus
          cur - amount
        else
          cur + amount
        end
      return [false, 'Kích thước mới quá nhỏ.'] if new_len <= min_len
      [true, nil]
    end

    def result(ok, changed, message)
      { ok: ok, changed: changed, message: message }
    end

    def group_or_component?(ent)
      ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
    end

    def child_entities(ent)
      ent.is_a?(Sketchup::Group) ? ent.entities : ent.definition.entities
    end

    def needs_unique?(ent)
      return false unless ent.respond_to?(:definition)
      # Chi make_unique khi definition DUNG CHUNG that (>1 instance). Khong make_unique
      # DC me 1-ban moi lan stretch -> tranh sinh definition moi (#1, #2...) lam dialog
      # Component Options/Attributes mat lien ket -> hien trong.
      ent.definition.instances.length > 1
    rescue
      false
    end

    def stretch_entities(entities, parent_to_context, plane, local_delta)
      moved = 0
      vertices = []
      nested = []
      entities.each do |ent|
        if ent.is_a?(Sketchup::Edge)
          vertices.concat(ent.vertices)
        elsif group_or_component?(ent)
          nested << ent
        end
      end
      vertices.uniq!
      moved += move_vertices(entities, vertices, parent_to_context, plane, local_delta)
      nested.each do |ent|
        moved += stretch_nested_container(entities, ent, parent_to_context, plane, local_delta)
      end
      moved
    end

    def move_vertices(entities, vertices, parent_to_context, plane, local_delta)
      moving = vertices.select do |vertex|
        world = vertex.position.transform(parent_to_context)
        side_match?(axis_value(world, plane[:axis]), plane)
      end
      return 0 if moving.empty?

      entities.transform_entities(Geom::Transformation.translation(local_delta), moving)
      moving.length
    end

    def stretch_nested_container(parent_entities, ent, parent_to_context, plane, local_delta)
      state = classify_bounds(ent.bounds, parent_to_context, plane)
      case state
      when :moving
        move_container_contents_preserve_origin(ent, local_delta)
      when :crossing
        ent.make_unique if ent.respond_to?(:make_unique) && needs_unique?(ent)
        child_tr = parent_to_context * ent.transformation
        child_delta = delta_context_to_parent(local_delta, ent.transformation.inverse)
        stretch_entities(child_entities(ent), child_tr, plane, child_delta)
      else
        0
      end
    end

    def delta_context_to_parent(delta, inverse)
      delta.transform(inverse)
    end

    def move_container_contents_preserve_origin(ent, delta_in_parent)
      ent.make_unique if ent.respond_to?(:make_unique) && needs_unique?(ent)
      child_delta = delta_context_to_parent(delta_in_parent, ent.transformation.inverse)
      move_entities_preserve_origin(child_entities(ent), child_delta)
    rescue
      0
    end

    def move_entities_preserve_origin(entities, local_delta)
      moved = 0
      vertices = []
      nested = []
      entities.each do |ent|
        if ent.is_a?(Sketchup::Edge)
          vertices.concat(ent.vertices)
        elsif group_or_component?(ent)
          nested << ent
        end
      end
      vertices.uniq!
      unless vertices.empty?
        entities.transform_entities(Geom::Transformation.translation(local_delta), vertices)
        moved += vertices.length
      end
      nested.each do |child|
        moved += move_container_contents_preserve_origin(child, local_delta)
      end
      moved
    end

    def classify_bounds(bb, parent_to_context, plane)
      vals = (0..7).map { |i| axis_value(bb.corner(i).transform(parent_to_context), plane[:axis]) }
      if plane[:side] == :minus
        return :moving if vals.all? { |v| v <= plane[:pos] + EPS }
        return :static if vals.all? { |v| v > plane[:pos] + EPS }
      else
        return :moving if vals.all? { |v| v >= plane[:pos] - EPS }
        return :static if vals.all? { |v| v < plane[:pos] - EPS }
      end
      :crossing
    end

    def collect_preview_edges(entities, parent_to_context, plane, delta_vec, segments)
      entities.each do |ent|
        break if segments.length >= MAX_PREVIEW_EDGES
        if ent.is_a?(Sketchup::Edge)
          p1 = ent.start.position.transform(parent_to_context)
          p2 = ent.end.position.transform(parent_to_context)
          segments << [shifted_point(p1, plane, delta_vec), shifted_point(p2, plane, delta_vec)]
        elsif group_or_component?(ent)
          state = classify_bounds(ent.bounds, parent_to_context, plane)
          child_tr = parent_to_context * ent.transformation
          if state == :moving
            collect_bounds_edges(ent.bounds, parent_to_context, delta_vec, segments)
          elsif state == :crossing
            collect_preview_edges(child_entities(ent), child_tr, plane, delta_vec, segments)
          end
        end
      end
    end

    def collect_bounds_edges(bb, tr, delta_vec, segments)
      c = (0..7).map { |i| bb.corner(i).transform(tr).offset(delta_vec) }
      [[0, 1], [1, 3], [3, 2], [2, 0],
       [4, 5], [5, 7], [7, 6], [6, 4],
       [0, 4], [1, 5], [2, 6], [3, 7]].each do |a, b|
        segments << [c[a], c[b]]
      end
    end
  end
end
