# encoding: UTF-8

module MH::Scale
  module StretchAdapter
    module_function

    def ensure_loaded
      return true if available?

      Sketchup.require File.join(PATH, 'vendor', 'scale_core')
      Sketchup.require File.join(PATH, 'vendor', 'stretch_core')
      available?
    rescue => e
      warn "MHScale StretchAdapter load failed: #{e.class}: #{e.message}"
      false
    end

    def available?
      defined?(SmartScale::StretchCore)
    end

    def prepare_and_redraw_dc(model, axis: nil, origin_states: nil)
      DcLengths.sync_selection(model, axis: axis, origin_states: origin_states)
    rescue => e
      warn "MHScale prepare_and_redraw_dc failed: #{e.class}: #{e.message}"
      nil
    end

    def delta_for_axis(axis, amount)
      ensure_loaded
      SmartScale::StretchCore.delta_for_axis(axis, amount)
    end

    def preview(model, plane, amount, planes = nil, bb = nil)
      return [] unless ensure_loaded

      delta = delta_for_axis(plane[:axis], amount)
      range = moving_range(plane, planes, bb)
      if range
        preview_range_wireframe(model, range, delta)
      else
        SmartScale::StretchCore.preview_wireframe(model, engine_plane(plane), delta)
      end
    rescue => e
      warn "MHScale preview failed: #{e.class}: #{e.message}"
      []
    end

    def commit(model, plane, amount, planes = nil, bb = nil)
      range = moving_range(plane, planes, bb)
      if range
        return { ok: false, message: 'StretchCore chưa load được.' } unless ensure_loaded

        delta = delta_for_axis(plane[:axis], amount)
        stretch_range_selection(model, range, delta)
      else
        StretchOperation.commit(
          model,
          axis: plane[:axis],
          side: plane[:side],
          plane_pos: plane[:pos],
          amount: amount,
          clearance: PlaneVertexSelector::DEFAULT_CLEARANCE
        )
      end
    rescue => e
      { ok: false, message: "#{e.class}: #{e.message}" }
    end

    def engine_plane(plane)
      { axis: plane[:axis], pos: plane[:pos], side: plane[:side] }
    end

    def bbox_handle_cut_planes(axis, side, planes)
      return [] unless planes

      list = planes.select { |item| item[:axis] == axis && item[:usable] }
      list = list.sort_by { |item| item[:pos].to_f }
      side == :plus ? list : list.reverse
    end

    def preview_box_scale(bb, axis, side, amount)
      current = BoxModel.axis_length(bb, axis)
      target = side == :minus ? current - amount.to_f : current + amount.to_f
      target = [target, BoxModel::MIN_LEN].max
      factor = target.to_f / current.to_f
      anchor = side == :minus ? bb.max : bb.min
      transform = Geom::Transformation.scaling(
        anchor,
        axis == :x ? factor : 1.0,
        axis == :y ? factor : 1.0,
        axis == :z ? factor : 1.0
      )
      corners = BoxModel.corners(bb).map { |point| point.transform(transform) }
      [
        [0, 1], [1, 3], [3, 2], [2, 0],
        [4, 5], [5, 7], [7, 6], [6, 4],
        [0, 4], [1, 5], [2, 6], [3, 7]
      ].map { |a, b| [corners[a], corners[b]] }
    end

    def commit_box_scale(model, bb, axis, side, amount)
      return { ok: false, message: 'ScaleCore chưa load được.' } unless ensure_loaded

      current = BoxModel.axis_length(bb, axis)
      target = side == :minus ? current - amount.to_f : current + amount.to_f
      target = [target, BoxModel::MIN_LEN].max
      anchor_mode = side == :minus ? :max : :min
      ok = SmartScale::Core.set_axis_length(
        model,
        axis,
        target,
        anchor_mode: anchor_mode,
        uniform: false
      )
      result(ok, ok ? model.selection.length : 0, ok ? 'Đã scale theo grip box.' : 'Không thể scale selection.')
    rescue => e
      result(false, 0, "#{e.class}: #{e.message}")
    end

    def preview_multi_cut(model, cuts, axis, side, amount)
      return [] unless ensure_loaded
      return [] if cuts.nil? || cuts.empty?

      step = amount.to_f / cuts.length
      delta = delta_for_axis(axis, step)
      targets = SmartScale::StretchCore.targets_for_selection(model, make_unique: false)
      segments = []
      targets.each do |target|
        collect_preview_edges_multi(target.entities, target.transform, cuts, side, delta, segments)
        break if segments.length >= SmartScale::StretchCore::MAX_PREVIEW_EDGES
      end
      segments
    rescue => e
      warn "MHScale preview_multi_cut failed: #{e.class}: #{e.message}"
      []
    end

    def commit_multi_cut(model, cuts, axis, side, amount)
      return { ok: false, message: 'StretchCore chưa load được.' } unless ensure_loaded
      return { ok: false, message: 'Không có plane cùng trục để multi-cut.' } if cuts.nil? || cuts.empty?

      step = amount.to_f / cuts.length
      delta = delta_for_axis(axis, step)
      model.start_operation('MH Scale Multi-Cut Stretch', true)
      targets = SmartScale::StretchCore.targets_for_selection(model, make_unique: true)
      changed = 0
      targets.each { |target| changed += stretch_multi_target(target, cuts, side, delta) }
      model.commit_operation
      result(changed.positive?, changed, changed.positive? ? "Đã stretch multi-cut #{cuts.length} plane." : 'Không có geometry phía động.')
    rescue => e
      model.abort_operation rescue nil
      result(false, 0, "#{e.class}: #{e.message}")
    end

    def stretch_multi_target(target, cuts, side, delta_vec)
      ent = target.entity
      # Instance nam tron mot phia cac cut -> move bang cach doi TRANSFORM theo so cut.
      if ent && SmartScale::StretchCore.group_or_component?(ent)
        state, count = classify_bounds_multi(ent.bounds, Geom::Transformation.new, cuts, side)
        if state == :moving
          ent.transformation = Geom::Transformation.translation(scale_vector(delta_vec, count)) * ent.transformation
          return 1
        end
      end

      local_delta = delta_vec.transform(target.inverse)
      if target.vertices
        return move_vertices_multi(target.entities, target.vertices, target.transform, cuts, side, local_delta)
      end

      stretch_multi_entities(target.entities, target.transform, cuts, side, local_delta)
    end

    def stretch_multi_entities(entities, parent_to_context, cuts, side, local_delta)
      moved = 0
      vertices = []
      nested = []
      entities.each do |ent|
        if ent.is_a?(Sketchup::Edge)
          vertices.concat(ent.vertices)
        elsif SmartScale::StretchCore.group_or_component?(ent)
          nested << ent
        end
      end
      vertices.uniq!
      moved += move_vertices_multi(entities, vertices, parent_to_context, cuts, side, local_delta)
      nested.each do |ent|
        moved += stretch_multi_nested_container(entities, ent, parent_to_context, cuts, side, local_delta)
      end
      moved
    end

    def move_vertices_multi(entities, vertices, parent_to_context, cuts, side, local_delta)
      buckets = Hash.new { |hash, key| hash[key] = [] }
      vertices.each do |vertex|
        world = vertex.position.transform(parent_to_context)
        count = cut_count(world, cuts, side)
        buckets[count] << vertex if count.positive?
      end
      return 0 if buckets.empty?

      moved = 0
      buckets.each do |count, bucket|
        entities.transform_entities(Geom::Transformation.translation(scale_vector(local_delta, count)), bucket)
        moved += bucket.length
      end
      moved
    end

    def stretch_multi_nested_container(parent_entities, ent, parent_to_context, cuts, side, local_delta)
      state, count = classify_bounds_multi(ent.bounds, parent_to_context, cuts, side)
      case state
      when :moving
        SmartScale::StretchCore.move_container_contents_preserve_origin(
          ent,
          scale_vector(local_delta, count)
        )
      when :crossing
        ent.make_unique if ent.respond_to?(:make_unique) && SmartScale::StretchCore.needs_unique?(ent)
        child_tr = parent_to_context * ent.transformation
        child_delta = local_delta.transform(ent.transformation.inverse)
        stretch_multi_entities(SmartScale::StretchCore.child_entities(ent), child_tr, cuts, side, child_delta)
      else
        0
      end
    end

    def classify_bounds_multi(bb, parent_to_context, cuts, side)
      counts = (0..7).map do |i|
        point = bb.corner(i).transform(parent_to_context)
        cut_count(point, cuts, side)
      end
      uniq = counts.uniq
      return [:static, 0] if uniq.length == 1 && uniq.first == 0
      return [:moving, uniq.first] if uniq.length == 1

      [:crossing, nil]
    end

    def moving_range(plane, planes, bb)
      return nil unless planes && bb

      axis = plane[:axis]
      same_axis = planes.select { |item| item[:axis] == axis && item[:usable] }.sort_by { |item| item[:pos].to_f }
      index = same_axis.index { |item| item[:id] == plane[:id] }
      return nil unless index

      if plane[:side] == :plus
        neighbor = same_axis[index + 1]
        return nil unless neighbor

        range(axis, plane[:pos], neighbor[:pos], :min)
      else
        neighbor = same_axis[index - 1]
        return nil unless neighbor

        range(axis, neighbor[:pos], plane[:pos], :max)
      end
    end

    def range(axis, a, b, anchor)
      min, max = [a.to_f, b.to_f].sort
      return nil if (max - min).abs <= BoxModel::MIN_LEN

      { axis: axis, min: min, max: max, anchor: anchor }
    end

    def stretch_range_selection(model, range, delta_vec)
      return result(false, 0, 'Selection rỗng.') if model.selection.empty?
      return result(false, 0, 'Delta quá nhỏ.') if delta_vec.length <= SmartScale::StretchCore::EPS

      model.start_operation('MH Scale Multi-Plane Stretch', true)
      targets = SmartScale::StretchCore.targets_for_selection(model, make_unique: true)
      changed = 0
      targets.each { |target| changed += stretch_range_target(target, range, delta_vec) }
      model.commit_operation
      result(changed.positive?, changed, changed.positive? ? 'Đã stretch vùng giữa 2 plane.' : 'Không có geometry trong vùng giữa 2 plane.')
    rescue => e
      model.abort_operation rescue nil
      result(false, 0, "#{e.class}: #{e.message}")
    end

    def stretch_range_target(target, range, delta_vec)
      ent = target.entity
      if ent && SmartScale::StretchCore.group_or_component?(ent) &&
         classify_bounds_range(ent.bounds, Geom::Transformation.new, range) == :moving
        ent.make_unique if ent.respond_to?(:make_unique) && SmartScale::StretchCore.needs_unique?(ent)
        local_delta = delta_vec.transform(target.inverse)
        return stretch_range_entities(target.entities, target.transform, range, local_delta)
      end

      local_delta = delta_vec.transform(target.inverse)
      if target.vertices
        return move_vertices_range(target.entities, target.vertices, target.transform, range, local_delta)
      end

      stretch_range_entities(target.entities, target.transform, range, local_delta)
    end

    def stretch_range_entities(entities, parent_to_context, range, local_delta)
      moved = 0
      vertices = []
      nested = []
      entities.each do |ent|
        if ent.is_a?(Sketchup::Edge)
          vertices.concat(ent.vertices)
        elsif SmartScale::StretchCore.group_or_component?(ent)
          nested << ent
        end
      end
      vertices.uniq!
      moved += move_vertices_range(entities, vertices, parent_to_context, range, local_delta)
      nested.each do |ent|
        moved += stretch_range_nested_container(entities, ent, parent_to_context, range, local_delta)
      end
      moved
    end

    def move_vertices_range(entities, vertices, parent_to_context, range, local_delta)
      moved = 0
      vertices.each do |vertex|
        world = vertex.position.transform(parent_to_context)
        next unless in_range?(BoxModel.axis_value(world, range[:axis]), range)

        delta = proportional_range_delta(local_delta, world, range)
        next if delta.length <= SmartScale::StretchCore::EPS

        entities.transform_entities(Geom::Transformation.translation(delta), [vertex])
        moved += 1
      end

      moved
    end

    def stretch_range_nested_container(parent_entities, ent, parent_to_context, range, local_delta)
      state = classify_bounds_range(ent.bounds, parent_to_context, range)
      case state
      when :moving, :crossing
        ent.make_unique if ent.respond_to?(:make_unique) && SmartScale::StretchCore.needs_unique?(ent)
        child_tr = parent_to_context * ent.transformation
        child_delta = local_delta.transform(ent.transformation.inverse)
        stretch_range_entities(SmartScale::StretchCore.child_entities(ent), child_tr, range, child_delta)
      else
        0
      end
    end

    def classify_bounds_range(bb, parent_to_context, range)
      vals = (0..7).map { |i| BoxModel.axis_value(bb.corner(i).transform(parent_to_context), range[:axis]) }
      return :moving if vals.all? { |val| in_range?(val, range) }
      return :static if vals.all? { |val| val < range[:min] || val > range[:max] }

      :crossing
    end

    def proportional_range_delta(vector, point, range)
      factor = range_factor(BoxModel.axis_value(point, range[:axis]), range)
      scale_vector(vector, factor)
    end

    def range_factor(value, range)
      span = range[:max].to_f - range[:min].to_f
      return 0.0 if span.abs <= SmartScale::StretchCore::EPS

      raw =
        if range[:anchor] == :max
          (range[:max].to_f - value.to_f) / span
        else
          (value.to_f - range[:min].to_f) / span
        end
      [[raw, 0.0].max, 1.0].min
    end

    def preview_range_wireframe(model, range, delta_vec)
      targets = SmartScale::StretchCore.targets_for_selection(model, make_unique: false)
      segments = []
      targets.each do |target|
        collect_preview_edges_range(target.entities, target.transform, range, delta_vec, segments)
        break if segments.length >= SmartScale::StretchCore::MAX_PREVIEW_EDGES
      end
      segments
    rescue
      []
    end

    def collect_preview_edges_range(entities, parent_to_context, range, delta_vec, segments)
      entities.each do |ent|
        break if segments.length >= SmartScale::StretchCore::MAX_PREVIEW_EDGES
        if ent.is_a?(Sketchup::Edge)
          p1 = ent.start.position.transform(parent_to_context)
          p2 = ent.end.position.transform(parent_to_context)
          segments << [shifted_range_point(p1, range, delta_vec), shifted_range_point(p2, range, delta_vec)]
        elsif SmartScale::StretchCore.group_or_component?(ent)
          state = classify_bounds_range(ent.bounds, parent_to_context, range)
          child_tr = parent_to_context * ent.transformation
          if state == :moving
            collect_preview_edges_range(SmartScale::StretchCore.child_entities(ent), child_tr, range, delta_vec, segments)
          elsif state == :crossing
            collect_preview_edges_range(SmartScale::StretchCore.child_entities(ent), child_tr, range, delta_vec, segments)
          end
        end
      end
    end

    def collect_preview_edges_multi(entities, parent_to_context, cuts, side, delta_vec, segments)
      entities.each do |ent|
        break if segments.length >= SmartScale::StretchCore::MAX_PREVIEW_EDGES
        if ent.is_a?(Sketchup::Edge)
          p1 = ent.start.position.transform(parent_to_context)
          p2 = ent.end.position.transform(parent_to_context)
          segments << [shifted_multi_point(p1, cuts, side, delta_vec), shifted_multi_point(p2, cuts, side, delta_vec)]
        elsif SmartScale::StretchCore.group_or_component?(ent)
          child_tr = parent_to_context * ent.transformation
          collect_preview_edges_multi(SmartScale::StretchCore.child_entities(ent), child_tr, cuts, side, delta_vec, segments)
        end
      end
    end

    def shifted_multi_point(point, cuts, side, delta_vec)
      count = cut_count(point, cuts, side)
      return point if count <= 0

      point.offset(scale_vector(delta_vec, count))
    end

    def cut_count(point, cuts, side)
      cuts.count do |cut|
        value = BoxModel.axis_value(point, cut[:axis])
        side == :plus ? value >= cut[:pos].to_f - SmartScale::StretchCore::EPS : value <= cut[:pos].to_f + SmartScale::StretchCore::EPS
      end
    end

    def scale_vector(vector, factor)
      Geom::Vector3d.new(vector.x * factor, vector.y * factor, vector.z * factor)
    end

    def shifted_range_point(point, range, delta_vec)
      return point unless in_range?(BoxModel.axis_value(point, range[:axis]), range)

      point.offset(proportional_range_delta(delta_vec, point, range))
    end

    def in_range?(value, range)
      value >= range[:min] - SmartScale::StretchCore::EPS && value <= range[:max] + SmartScale::StretchCore::EPS
    end

    def result(ok, changed, message)
      { ok: ok, changed: changed, message: message }
    end
  end
end

