# encoding: UTF-8

module SmartScaleLab
  module DcLengths
    CONTAINERS = [Sketchup::Group, Sketchup::ComponentInstance].freeze
    AXIS_KEY = { x: 'lenx', y: 'leny', z: 'lenz' }.freeze
    FIX_AXES = [:x, :y, :z].freeze
    EPS = 1e-6

    module_function

    def sync_selection(model, axis: nil, origin_states: nil)
      roots = []
      model.selection.each do |entity|
        collect_redraw_roots(entity, roots) if container?(entity)
      end
      sync_roots(roots, axis: axis, origin_states: origin_states)
    rescue => e
      warn "SmartScaleLab DC prepare failed: #{e.class}: #{e.message}"
      empty_result(false)
    end

    def make_selection_unique(model)
      changed = 0
      visited = {}
      model.selection.each do |entity|
        changed += make_container_tree_unique(entity, visited) if container?(entity)
      end
      { ok: true, changed: changed, roots: model.selection.length }
    rescue => e
      warn "SmartScaleLab DC make unique selection failed: #{e.class}: #{e.message}"
      { ok: false, changed: 0, roots: 0 }
    end

    def bake_scaled_selection_for_stretch(model)
      changed = 0
      visited = {}
      model.selection.each do |entity|
        changed += bake_scaled_tree_for_stretch(entity, visited) if valid_instance?(entity)
      end
      { ok: true, changed: changed }
    rescue => e
      warn "SmartScaleLab DC bake scaled selection failed: #{e.class}: #{e.message}"
      { ok: false, changed: changed || 0 }
    end

    def make_roots_unique(roots)
      live = roots.select { |root| valid_instance?(root) }.uniq
      return { ok: true, changed: 0, roots: 0 } if live.empty?

      changed = 0
      live.each do |root|
        next unless shared_definition?(root)

        root.make_unique
        changed += 1
      end
      { ok: true, changed: changed, roots: live.length }
    rescue => e
      warn "SmartScaleLab DC make unique failed: #{e.class}: #{e.message}"
      { ok: false, changed: changed || 0, roots: live&.length.to_i }
    end

    def make_container_tree_unique(instance, visited = {})
      return 0 unless valid_instance?(instance)

      changed = 0
      if shared_definition?(instance)
        instance.make_unique
        changed += 1
      end

      key = instance.definition.object_id
      return changed if visited[key]

      visited[key] = true
      instance.definition.entities.each do |child|
        changed += make_container_tree_unique(child, visited) if container?(child)
      end
      changed
    rescue => e
      warn "SmartScaleLab DC make tree unique failed: #{e.class}: #{e.message}"
      changed || 0
    end

    def schedule_fix_selection(model, axis:, delay: 0.08, stretch_context: nil, redraw: false)
      roots = []
      model.selection.each do |entity|
        collect_redraw_roots(entity, roots) if container?(entity)
      end
      roots = roots.select { |root| valid_instance?(root) }.uniq
      return empty_fix_result(true) if roots.empty? || !axis

      UI.start_timer(delay, false) do
        result = repair_roots(roots, axis, stretch_context)
        schedule_redraw(roots) if redraw && result && result[:ok]
        Sketchup.active_model.active_view.invalidate rescue nil
      end
      {
        ok: true,
        scheduled: true,
        roots: roots.length,
        fixed_children: 0,
        fixed_paths: []
      }
    rescue => e
      warn "SmartScaleLab DC fix schedule failed: #{e.class}: #{e.message}"
      empty_fix_result(false)
    end

    def fix_selection(model, axis:)
      roots = []
      model.selection.each do |entity|
        collect_redraw_roots(entity, roots) if container?(entity)
      end
      repair_roots(roots, axis)
    rescue => e
      warn "SmartScaleLab DC fix selection failed: #{e.class}: #{e.message}"
      empty_fix_result(false)
    end

    def repair_roots(roots, axis, stretch_context = nil)
      live = roots.select { |root| valid_instance?(root) }.uniq
      axes = fix_axes(axis)
      return empty_fix_result(true) if live.empty? || axes.empty?

      model = Sketchup.active_model
      fixed = []
      model.start_operation('SmartScale Lab Fix DC Geometry Origin', true)
      live.each do |root|
        if stretch_context
          repair_child_origins_for_stretch(root, stretch_context, fixed, [])
        else
          axes.each do |current_axis|
            repair_child_geometry_offsets(root, current_axis, fixed, [])
          end
        end
      end
      model.commit_operation
      {
        ok: true,
        scheduled: false,
        roots: live.length,
        fixed_children: fixed.length,
        fixed_paths: fixed
      }
    rescue => e
      model.abort_operation rescue nil
      warn "SmartScaleLab DC fix failed: #{e.class}: #{e.message}"
      empty_fix_result(false)
    end

    def fix_axes(axis)
      return FIX_AXES if axis.nil? || axis == :all

      AXIS_KEY.key?(axis) ? [axis] : []
    end

    def sync_roots(roots, axis: nil, origin_states: nil)
      live = roots.select { |root| valid_instance?(root) }.uniq
      redrawable = []
      locked = []

      model = Sketchup.active_model
      model.start_operation('SmartScale Lab Sync DC', true) if axis
      live.each do |root|
        if axis && formula_locked?(root, axis)
          locked << root
          next
        end

        if axis
          rebase_origin(root, axis, origin_states)
          prepare_actual_length(root, axis)
        end
        redrawable << root
      end
      model.commit_operation if axis

      schedule_redraw(redrawable)
      {
        ok: true,
        changed: false,
        synced_nodes: live.length,
        redraw_nodes: redrawable.length,
        formula_locked_nodes: locked.length,
        formula_locked_pids: locked.map { |root| root.persistent_id rescue nil }.compact
      }
    rescue => e
      model.abort_operation rescue nil
      warn "SmartScaleLab DC prepare failed: #{e.class}: #{e.message}"
      empty_result(false)
    end

    def collect_redraw_roots(instance, roots, visited = {})
      return unless valid_instance?(instance)

      if dynamic?(instance)
        roots << instance
        return
      end

      key = instance.definition.object_id
      return if visited[key]

      visited[key] = true
      instance.definition.entities.each do |child|
        collect_redraw_roots(child, roots, visited) if container?(child)
      end
    end

    def schedule_redraw(roots)
      return if roots.empty?
      return unless defined?($dc_observers) && $dc_observers

      UI.start_timer(0, false) do
        begin
          dc = $dc_observers.get_latest_class rescue nil
          if dc && dc.respond_to?(:redraw_with_undo)
            roots.each do |instance|
              dc.redraw_with_undo(instance) if instance && instance.valid?
            end
          end
        rescue => e
          warn "SmartScaleLab DC redraw failed: #{e.class}: #{e.message}"
        end
      end
    end

    def prepare_actual_length(instance, axis)
      key = AXIS_KEY[axis]
      return unless key

      value = axis_size(instance.bounds, axis).to_f
      dict = instance.attribute_dictionary('dynamic_attributes', true)
      dict[key] = value
      dict["_#{key}_nominal"] = value
    end

    def formula_locked?(instance, axis)
      key = AXIS_KEY[axis]
      return false unless key

      formula_key = "_#{key}_formula"
      formula = attribute_value(instance, formula_key)
      !formula.nil? && !formula.to_s.strip.empty?
    end

    def capture_origin_states(model, axis)
      roots = []
      model.selection.each do |entity|
        collect_redraw_roots(entity, roots) if container?(entity)
      end
      roots.uniq.each_with_object({}) do |root, states|
        pid = root.persistent_id rescue nil
        next unless pid

        origin = axis_value(root.transformation.origin, axis)
        min = axis_min(root.bounds, axis)
        max = axis_max(root.bounds, axis)
        states[pid] = (origin - min).abs <= (origin - max).abs ? :min : :max
      end
    rescue
      {}
    end

    def rebase_origin(instance, axis, origin_states)
      pid = instance.persistent_id rescue nil
      anchor = origin_states && origin_states[pid]
      anchor ||= :min
      target = anchor == :max ? axis_max(instance.bounds, axis) : axis_min(instance.bounds, axis)
      current = axis_value(instance.transformation.origin, axis)
      amount = target - current
      return false if amount.abs <= EPS

      move_origin(instance, axis_vector(axis, amount))
      true
    rescue
      false
    end

    def axis_vector(axis, amount)
      case axis
      when :x then Geom::Vector3d.new(amount, 0, 0)
      when :y then Geom::Vector3d.new(0, amount, 0)
      else Geom::Vector3d.new(0, 0, amount)
      end
    end

    def move_origin(instance, world_move)
      instance.make_unique if shared_definition?(instance)

      tr = instance.transformation
      local_back = Geom::Vector3d.new(
        -world_move.x,
        -world_move.y,
        -world_move.z
      ).transform(tr.inverse)
      entities = instance.definition.entities
      transform_definition_contents(
        entities,
        Geom::Transformation.translation(local_back)
      )
      instance.definition.invalidate_bounds if instance.definition.respond_to?(:invalidate_bounds)
      instance.transformation =
        Geom::Transformation.translation(world_move) * tr
    end

    def transform_definition_contents(entities, transformation)
      vertices = entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
      containers = entities.select { |entity| container?(entity) }
      entities.transform_entities(transformation, vertices) unless vertices.empty?
      containers.each do |container|
        container.transformation = transformation * container.transformation
      end
    end

    def repair_child_geometry_offsets(parent, axis, fixed, path, visited = {})
      return unless valid_instance?(parent)

      parent.definition.entities.each do |child|
        next unless valid_instance?(child)

        label = child_label(child)
        child_path = path + [label]
        definition = child.definition
        offset = axis_value(definition.bounds.min, axis)
        if offset.abs > 1.mm && definition_has_direct_geometry?(definition)
          child.make_unique if shared_definition?(child)
          definition = child.definition
          move_child_axis_to_geometry(child, axis, offset)
          fixed << {
            pid: (child.persistent_id rescue nil),
            path: child_path.join(' > '),
            axis: axis,
            axis_move_mm: offset.to_mm.round(2)
          }
        end

        key = child.definition.object_id
        next if visited[key]

        visited[key] = true
        repair_child_geometry_offsets(child, axis, fixed, child_path, visited)
      end
    end

    def bake_scaled_tree_for_stretch(instance, visited = {})
      return 0 unless valid_instance?(instance)

      key = instance.definition.object_id
      return 0 if visited[key]

      visited[key] = true

      changed = 0
      children = instance.definition.entities.select { |entity| container?(entity) }
      children.each do |child|
        changed += bake_scaled_tree_for_stretch(child, visited)
        changed += 1 if bake_scaled_instance_for_stretch(child)
      end
      changed
    end

    def bake_scaled_instance_for_stretch(instance)
      return false unless valid_instance?(instance)
      return false if hidden_or_tiny_scaled?(instance)

      sx, sy, sz = matrix_scale(instance.transformation)
      return false if [sx, sy, sz].all? { |scale| (scale - 1.0).abs <= 0.001 }
      return false if [sx, sy, sz].any? { |scale| scale.abs <= 0.01 }

      before = bounds_size_mm(instance.bounds)
      instance.make_unique if shared_definition?(instance)
      transformation = instance.transformation
      clean = clean_scaled_transformation(transformation)
      bake = clean.inverse * transformation
      definition = instance.definition
      entities = definition.entities.to_a
      definition.entities.transform_entities(bake, entities) unless entities.empty?
      definition.invalidate_bounds if definition.respond_to?(:invalidate_bounds)
      instance.transformation = clean
      after = bounds_size_mm(instance.bounds)
      dimensions_match?(before, after)
    rescue => e
      warn "SmartScaleLab DC bake scaled child failed: #{e.class}: #{e.message}"
      false
    end

    def clean_scaled_transformation(transformation)
      sx, sy, sz = matrix_scale(transformation)
      array = transformation.to_a
      xaxis = Geom::Vector3d.new(array[0] / sx, array[1] / sx, array[2] / sx)
      yaxis = Geom::Vector3d.new(array[4] / sy, array[5] / sy, array[6] / sy)
      zaxis = Geom::Vector3d.new(array[8] / sz, array[9] / sz, array[10] / sz)
      Geom::Transformation.axes(transformation.origin, xaxis, yaxis, zaxis)
    end

    def matrix_scale(transformation)
      array = transformation.to_a
      [
        Math.sqrt(array[0] * array[0] + array[1] * array[1] + array[2] * array[2]),
        Math.sqrt(array[4] * array[4] + array[5] * array[5] + array[6] * array[6]),
        Math.sqrt(array[8] * array[8] + array[9] * array[9] + array[10] * array[10])
      ]
    end

    def hidden_or_tiny_scaled?(instance)
      dict = instance.attribute_dictionary('dynamic_attributes', false)
      return true if dict && dict['hidden'].to_f != 0.0

      matrix_scale(instance.transformation).any? { |scale| scale.abs <= 0.01 }
    rescue
      false
    end

    def bounds_size_mm(bounds)
      [bounds.width.to_l.to_mm, bounds.depth.to_l.to_mm, bounds.height.to_l.to_mm]
    end

    def dimensions_match?(before, after)
      before.zip(after).all? { |a, b| (a.to_f - b.to_f).abs <= 0.05 }
    end

    def repair_child_origins_for_stretch(parent, context, fixed, path, visited = {}, parent_to_world = nil)
      return unless valid_instance?(parent)

      parent_to_world ||= parent.transformation
      parent.definition.entities.each do |child|
        next unless valid_instance?(child)

        label = child_label(child)
        child_path = path + [label]
        child_to_world = parent_to_world * child.transformation
        if definition_has_direct_geometry?(child.definition) &&
           child_origin_needs_stretch_rebase?(child, parent_to_world, context)
          delta_world = stretch_delta_for_origin(child.transformation.origin.transform(parent_to_world), context)
          if delta_world && delta_world.length > EPS
            child.make_unique if shared_definition?(child)
            move_child_by_world_delta(child, parent_to_world, delta_world)
            child_to_world = parent_to_world * child.transformation
            fixed << {
              pid: (child.persistent_id rescue nil),
              path: child_path.join(' > '),
              axis: context[:axis],
              axis_move_mm: axis_value(delta_world, context[:axis]).to_mm.round(2)
            }
          end
        end

        key = child.object_id
        next if visited[key]

        visited[key] = true
        repair_child_origins_for_stretch(child, context, fixed, child_path, visited, child_to_world)
      end
    end

    def child_origin_needs_stretch_rebase?(child, parent_to_world, context)
      origin_world = child.transformation.origin.transform(parent_to_world)
      delta = stretch_delta_for_origin(origin_world, context)
      return false unless delta && delta.length > EPS

      child_geometry_affected_by_context?(child.bounds, parent_to_world, context)
    rescue
      false
    end

    def child_geometry_affected_by_context?(bounds, bounds_to_world, context)
      samples = (0..7).map { |i| bounds.corner(i).transform(bounds_to_world) }
      case context[:mode]
      when :plane
        affected = samples.map { |point| stretch_delta_for_point(point, context)&.length.to_f > EPS }
        affected.any? && !affected.all?
      when :multi_cut
        counts = samples.map { |point| stretch_cut_count(point, context) }
        return false if counts.all?(&:zero?)
        return false if counts.uniq.length == 1 && counts.first.positive?

        true
      when :range
        values = samples.map { |point| axis_value(point, context[:axis]) }
        values.min <= context[:max].to_f + EPS && values.max >= context[:min].to_f - EPS
      else
        false
      end
    rescue
      false
    end

    def move_child_by_world_delta(child, parent_to_world, delta_world)
      parent_delta = delta_world.transform(parent_to_world.inverse)
      child.transformation =
        Geom::Transformation.translation(parent_delta) *
        child.transformation
    end

    def stretch_delta_for_point(point, context)
      return nil unless point && context

      axis = context[:axis]
      amount =
        case context[:mode]
        when :plane
          point_on_plane_side?(point, context) ? context[:amount].to_f : 0.0
        when :multi_cut
          stretch_cut_count(point, context) * context[:step].to_f
        when :range
          stretch_range_factor(point, context) * context[:amount].to_f
        else
          0.0
        end
      return nil if amount.abs <= EPS

      axis_vector(axis, amount)
    rescue
      nil
    end

    def stretch_delta_for_origin(point, context)
      return nil unless point && context

      axis = context[:axis]
      amount =
        case context[:mode]
        when :plane
          origin_on_plane_side?(point, context) ? context[:amount].to_f : 0.0
        when :multi_cut
          stretch_origin_cut_count(point, context) * context[:step].to_f
        when :range
          stretch_origin_range_factor(point, context) * context[:amount].to_f
        else
          0.0
        end
      return nil if amount.abs <= EPS

      axis_vector(axis, amount)
    rescue
      nil
    end

    def point_on_plane_side?(point, context)
      value = axis_value(point, context[:axis])
      if context[:side] == :minus
        value <= context[:pos].to_f + EPS
      else
        value >= context[:pos].to_f - EPS
      end
    end

    def origin_on_plane_side?(point, context)
      value = axis_value(point, context[:axis])
      if context[:side] == :minus
        value < context[:pos].to_f - EPS
      else
        value > context[:pos].to_f + EPS
      end
    end

    def stretch_cut_count(point, context)
      Array(context[:cuts]).count do |cut|
        value = axis_value(point, cut[:axis])
        if context[:side] == :minus
          value <= cut[:pos].to_f + EPS
        else
          value >= cut[:pos].to_f - EPS
        end
      end
    end

    def stretch_origin_cut_count(point, context)
      Array(context[:cuts]).count do |cut|
        value = axis_value(point, cut[:axis])
        if context[:side] == :minus
          value < cut[:pos].to_f - EPS
        else
          value > cut[:pos].to_f + EPS
        end
      end
    end

    def stretch_range_factor(point, context)
      value = axis_value(point, context[:axis])
      min = context[:min].to_f
      max = context[:max].to_f
      return 0.0 if value < min - EPS || value > max + EPS

      span = max - min
      return 0.0 if span.abs <= EPS

      raw =
        if context[:anchor] == :max
          (max - value.to_f) / span
        else
          (value.to_f - min) / span
      end
      [[raw, 0.0].max, 1.0].min
    end

    def stretch_origin_range_factor(point, context)
      value = axis_value(point, context[:axis])
      min = context[:min].to_f
      max = context[:max].to_f
      return 0.0 if value <= min + EPS || value >= max - EPS

      stretch_range_factor(point, context)
    end

    def definition_has_direct_geometry?(definition)
      definition.entities.grep(Sketchup::Edge).any?
    rescue
      false
    end

    def move_child_axis_to_geometry(child, axis, offset)
      local_axis_move = axis_vector(axis, offset)
      parent_axis_move = local_axis_move.transform(child.transformation)
      child.transformation =
        Geom::Transformation.translation(parent_axis_move) *
        child.transformation
      move_definition_vertices(child.definition, axis_vector(axis, -offset))
    end

    def move_definition_vertices(definition, vector)
      vertices = definition.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
      return if vertices.empty?

      definition.entities.transform_entities(
        Geom::Transformation.translation(vector),
        vertices
      )
      definition.invalidate_bounds if definition.respond_to?(:invalidate_bounds)
    end

    def child_label(child)
      name = child.name.to_s
      name.empty? ? child.definition.name.to_s : name
    rescue
      ''
    end

    def shared_definition?(instance)
      instance.definition.instances.length > 1
    rescue
      false
    end

    def axis_value(point, axis)
      case axis
      when :x then point.x
      when :y then point.y
      else point.z
      end
    end

    def axis_min(bounds, axis)
      axis_value(bounds.min, axis)
    end

    def axis_max(bounds, axis)
      axis_value(bounds.max, axis)
    end

    def attribute_value(instance, key)
      instance_dict = instance.attribute_dictionary('dynamic_attributes', false)
      return instance_dict[key] if instance_dict && !instance_dict[key].nil?

      definition_dict = instance.definition.attribute_dictionary('dynamic_attributes', false)
      definition_dict && definition_dict[key]
    end

    def axis_size(bounds, axis)
      case axis
      when :x then bounds.width
      when :y then bounds.height
      else bounds.depth
      end
    end

    def empty_result(ok)
      {
        ok: ok,
        changed: false,
        synced_nodes: 0,
        redraw_nodes: 0,
        formula_locked_nodes: 0,
        formula_locked_pids: []
      }
    end

    def empty_fix_result(ok)
      {
        ok: ok,
        scheduled: false,
        roots: 0,
        fixed_children: 0,
        fixed_paths: []
      }
    end

    def dynamic?(instance)
      instance.attribute_dictionary('dynamic_attributes', false) ||
        instance.definition.attribute_dictionary('dynamic_attributes', false)
    end

    def valid_instance?(instance)
      container?(instance) && instance.valid? && instance.respond_to?(:definition)
    rescue
      false
    end

    def container?(entity)
      CONTAINERS.any? { |klass| entity.is_a?(klass) }
    end
  end
end
