# encoding: UTF-8

module MH::Stretch
  module UiAdapter
    MAX_PREVIEW_SEGMENTS = 1400

    module_function

    def available?
      !!(defined?(StretchOperation) && defined?(PlaneVertexSelector))
    end

    def ensure_loaded
      available?
    end

    def delta_for_axis(axis, amount)
      BoxModel.axis_delta_vector(axis, amount)
    end

    def bbox_handle_cut_planes(axis, side, planes)
      return [] unless planes

      # Hidden default planes only keep legacy UI state; they are not actual
      # cut planes. Including one per selected copy makes a multi-selection
      # divide the requested distance by the number of copies.
      list = planes.select do |item|
        item[:axis] == axis && item[:usable] && !item[:hidden]
      end
      list = list.sort_by { |item| item[:pos].to_f }
      side == :plus ? list : list.reverse
    end

    def moving_range(*)
      nil
    end

    def commit(model, plane, amount, make_unique: true)
      return ui_result(false, 0, 'MH Stretch: engine chưa load.') unless available?
      return ui_result(false, 0, 'MH Stretch: không có plane hợp lệ.') unless plane

      planes = stretch_planes(plane)
      return ui_result(false, 0, 'MH Stretch: không có plane hợp lệ.') if planes.empty?
      if planes.length > 1 && StretchOperation.respond_to?(:commit_many)
        StretchOperation.commit_many(
          model,
          planes: planes,
          amount: amount,
          clearance: PlaneVertexSelector::DEFAULT_CLEARANCE,
          make_unique: make_unique
        )
      else
        active_plane = planes.first || plane
        StretchOperation.commit(
          model,
          axis: active_plane[:axis],
          side: active_plane[:side],
          plane_pos: active_plane[:pos],
          amount: amount,
          clearance: PlaneVertexSelector::DEFAULT_CLEARANCE,
          make_unique: make_unique
        )
      end
    rescue => error
      ui_result(false, 0, "#{error.class}: #{error.message}")
    end

    def make_unique_selection(model)
      return 0 unless available?

      PlaneVertexSelector.make_selection_unique(model.selection.to_a)
    rescue => error
      warn "MH Stretch make unique failed: #{error.class}: #{error.message}"
      0
    end

    def dynamic_components_for_redraw(model)
      ensure_mh_redraw_loaded
      return [] unless defined?(MH::Redraw)
      return [] unless MH::Redraw.respond_to?(:dynamic_component?)

      components = []
      seen = {}
      model.selection.to_a.each do |entity|
        collect_dynamic_components(entity, components, seen)
      end
      components
    rescue => error
      warn "MH Stretch DC collection failed: #{error.class}: #{error.message}"
      []
    end

    # A geometric stretch edits the component definition directly. Before the
    # Dynamic Components redraw rebuilds that definition, synchronize the
    # instance's unconstrained length attributes to the geometry that now
    # exists; otherwise redraw uses stale lenx/leny/lenz values and can resize
    # the stretched component a second time (or restore its old thickness).
    def dynamic_component_anchor_sides(components, axis)
      return {} unless axis

      model = Sketchup.active_model
      components.to_a.each_with_object({}) do |component, anchors|
        next unless component && component.valid? && component.is_a?(Sketchup::ComponentInstance)
        next unless top_level_component?(component, model)

        bounds = component.bounds
        origin_value = BoxModel.axis_value(component.transformation.origin, axis).to_f
        min_value = BoxModel.axis_min(bounds, axis).to_f
        max_value = BoxModel.axis_max(bounds, axis).to_f
        key = component.respond_to?(:persistent_id) ? component.persistent_id : component.entityID
        anchors[[key, axis]] = (origin_value - min_value).abs <= (origin_value - max_value).abs ? :min : :max
      end
    rescue => error
      warn "MH Stretch DC anchor capture failed: #{error.class}: #{error.message}"
      {}
    end

    def sync_dynamic_component_lengths(components, axes:, anchors: {})
      live = components.to_a.select do |component|
        component && component.valid? && component.is_a?(Sketchup::ComponentInstance)
      end
      return 0 if live.empty?

      axis_keys = axes.to_a.map { |axis| { x: 'lenx', y: 'leny', z: 'lenz' }[axis] }.compact.uniq
      return 0 if axis_keys.empty?

      model = Sketchup.active_model
      synced = 0
      model.start_operation('MH Stretch Sync DC Dimensions', true)
      live.each do |component|
        axes.each do |axis|
          key = component.respond_to?(:persistent_id) ? component.persistent_id : component.entityID
          rebase_dynamic_component_origin(component, axis, anchors[[key, axis]])
        end

        bounds = component.bounds
        dictionary = component.attribute_dictionary('dynamic_attributes', true)
        lengths = { 'lenx' => bounds.width, 'leny' => bounds.height, 'lenz' => bounds.depth }
        axis_keys.each do |key|
          formula = dynamic_attribute_value(component, "_#{key}_formula")
          next unless formula.to_s.strip.empty?

          value = lengths.fetch(key).to_f
          dictionary[key] = value
          dictionary["_#{key}_nominal"] = value
          synced += 1
        end
      end
      model.commit_operation
      synced
    rescue => error
      model.abort_operation rescue nil
      warn "MH Stretch DC dimension sync failed: #{error.class}: #{error.message}"
      0
    end

    # Keep the same outer face anchored through DC redraw. Moving the instance
    # origin alone would move the model geometry too, so compensate its
    # definition contents by the inverse local-space displacement.
    def rebase_dynamic_component_origin(component, axis, anchor)
      return false unless anchor
      return false unless top_level_component?(component, Sketchup.active_model)

      bounds = component.bounds
      target = anchor == :max ? BoxModel.axis_max(bounds, axis) : BoxModel.axis_min(bounds, axis)
      origin = component.transformation.origin
      amount = target.to_f - BoxModel.axis_value(origin, axis).to_f
      return false if amount.abs <= 0.001.mm

      world_delta = BoxModel.axis_delta_vector(axis, amount)
      old_transform = component.transformation
      local_back = Geom::Vector3d.new(-world_delta.x, -world_delta.y, -world_delta.z).transform(old_transform.inverse)
      content_transform = Geom::Transformation.translation(local_back)
      entities = component.definition.entities
      vertices = entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
      entities.transform_entities(content_transform, vertices) unless vertices.empty?
      entities.each do |child|
        next unless child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)

        child.transformation = content_transform * child.transformation
      end
      component.transformation = Geom::Transformation.translation(world_delta) * old_transform
      component.definition.invalidate_bounds if component.definition.respond_to?(:invalidate_bounds)
      true
    rescue => error
      warn "MH Stretch DC origin rebase failed: #{error.class}: #{error.message}"
      false
    end

    def top_level_component?(component, model)
      parent = component.parent
      parent == model || parent == model.entities
    rescue
      false
    end

    def dynamic_attribute_value(component, key)
      instance_dictionary = component.attribute_dictionary('dynamic_attributes', false)
      value = instance_dictionary[key] if instance_dictionary
      return value unless value.nil?

      definition_dictionary = component.definition.attribute_dictionary('dynamic_attributes', false)
      definition_dictionary && definition_dictionary[key]
    rescue
      nil
    end

    # Curic Align can create a Dynamic Component instance without its instance
    # dictionary. A later DC redraw then falls back to stale definition values.
    # Recover its full instance metadata from a sibling before make_unique
    # separates the selected copy from that sibling. Normal DC instances are
    # untouched.
    def repair_missing_dynamic_component_attributes(model)
      dynamic_components_for_redraw(model).count do |component|
        repair_missing_instance_attributes(component)
      end
    rescue => error
      warn "MH Stretch DC copy repair failed: #{error.class}: #{error.message}"
      0
    end

    def repair_missing_instance_attributes(component)
      return false unless component && component.valid?
      return false unless component.is_a?(Sketchup::ComponentInstance)

      instance_dictionary = component.attribute_dictionary('dynamic_attributes', false)
      return false if instance_dictionary

      sibling = component.definition.instances.find do |candidate|
        candidate != component && candidate.valid? &&
          candidate.attribute_dictionary('dynamic_attributes', false)
      end
      return false unless sibling

      # A copy made through some third-party tools can lose every instance
      # dictionary, not just dynamic_attributes. DC reads supporting instance
      # state as well, so restore the complete set just like a native
      # add_instance/copy would preserve it.
      sibling.attribute_dictionaries.each do |dictionary|
        dictionary.each_pair do |key, value|
          component.set_attribute(dictionary.name, key, value)
        end
      end
      true
    rescue => error
      warn "MH Stretch DC instance repair #{component.entityID} failed: #{error.class}: #{error.message}"
      false
    end

    # Redrawing a Dynamic Component can be expensive. Process one component per
    # UI turn so SketchUp continues repainting, and only inspect the selected
    # entity tree instead of scanning the whole model.
    def schedule_redraw_dynamic_components(components, delay: 0.05, &after_redraw)
      components = components.to_a.select { |entity| entity && entity.valid? }
      return 0 if components.empty?

      UI.stop_timer(@redraw_timer_id) if @redraw_timer_id
      @redraw_generation = @redraw_generation.to_i + 1
      generation = @redraw_generation
      @redraw_timer_id = UI.start_timer(delay, false) do
        @redraw_timer_id = nil
        redraw_dynamic_components_in_batches(components, generation, &after_redraw)
      end
      components.length
    rescue => error
      @redraw_timer_id = nil
      warn "MH Stretch redraw schedule failed: #{error.class}: #{error.message}"
      0
    end

    def collect_dynamic_components(entity, components, seen)
      return unless entity && entity.valid?

      key = entity.entityID
      return if seen[key]

      seen[key] = true
      if MH::Redraw.dynamic_component?(entity)
        components << entity
        return
      end

      children =
        if entity.is_a?(Sketchup::Group)
          entity.entities
        elsif entity.is_a?(Sketchup::ComponentInstance)
          entity.definition.entities
        end
      children.each { |child| collect_dynamic_components(child, components, seen) } if children
    rescue => error
      warn "MH Stretch DC tree walk failed: #{error.class}: #{error.message}"
    end

    def redraw_dynamic_components_in_batches(components, generation, index = 0, &after_redraw)
      return unless generation == @redraw_generation

      component = components[index]
      unless component && component.valid?
        return finish_batched_redraw(components, generation, index + 1, &after_redraw)
      end

      dc_class = MH::Redraw.dynamic_component_class
      unless dc_class && dc_class.respond_to?(:redraw_with_undo)
        return finish_batched_redraw(components, generation, components.length, &after_redraw)
      end

      Sketchup.status_text = "MH Stretch | Redraw DC #{index + 1}/#{components.length}"
      begin
        dc_class.redraw_with_undo(component)
      rescue => error
        warn "MH Stretch redraw #{component.entityID} failed: #{error.class}: #{error.message}"
      end
      finish_batched_redraw(components, generation, index + 1, &after_redraw)
    end

    def finish_batched_redraw(components, generation, next_index, &after_redraw)
      return unless generation == @redraw_generation

      if next_index < components.length
        @redraw_timer_id = UI.start_timer(0.0, false) do
          @redraw_timer_id = nil
          redraw_dynamic_components_in_batches(components, generation, next_index, &after_redraw)
        end
      else
        @redraw_timer_id = nil
        after_redraw.call if after_redraw
      end
    end

    def redraw_dynamic_components(components)
      ensure_mh_redraw_loaded
      return unless defined?(MH::Redraw)

      dc_class = MH::Redraw.dynamic_component_class
      return unless dc_class && dc_class.respond_to?(:redraw_with_undo)

      if MH::Redraw.respond_to?(:redraw_components)
        MH::Redraw.redraw_components(components, dc_class)
      else
        components.each { |component| dc_class.redraw_with_undo(component) if component && component.valid? }
      end
    rescue => error
      warn "MH Stretch redraw failed: #{error.class}: #{error.message}"
    end

    def ensure_mh_redraw_loaded
      return true if defined?(MH::Redraw)

      plugins_dir = Sketchup.find_support_file('Plugins')
      load File.join(plugins_dir, 'MH_redraw', 'main.rb')
      true
    rescue => error
      warn "MH Stretch cannot load MH_redraw: #{error.class}: #{error.message}"
      false
    end

    def preview(model, plane, amount, max_segments: MAX_PREVIEW_SEGMENTS)
      return [] unless available?
      return [] unless plane
      return [] if amount.to_f.abs <= 0.001.mm

      planes = stretch_planes(plane)
      return [] if planes.empty?

      delta = PlaneVertexSelector.world_delta(planes.first[:axis], amount.to_f / planes.length)
      clearance = PlaneVertexSelector::DEFAULT_CLEARANCE
      segments = []
      seen = {}
      model.selection.each do |entity|
        collect_preview_entity(
          entity,
          Geom::Transformation.new,
          planes,
          delta,
          clearance,
          segments,
          seen,
          max_segments
        )
        break if segments.length >= max_segments
      end
      segments
    rescue => error
      warn "MH Stretch preview failed: #{error.class}: #{error.message}"
      []
    end

    def ui_only_result
      ui_result(true, 0, 'MH Stretch: không có vùng stretch.')
    end

    def ui_result(ok, changed, message)
      {
        ok: ok,
        changed: changed,
        message: message
      }
    end

    def collect_preview_entity(entity, parent_to_world, planes, delta, clearance, segments, seen, max_segments)
      return if segments.length >= max_segments
      return unless entity
      return if entity.respond_to?(:valid?) && !entity.valid?
      return if entity.respond_to?(:hidden?) && entity.hidden?

      if entity.is_a?(Sketchup::Edge)
        add_edge_preview(entity, parent_to_world, planes, delta, clearance, segments, seen)
      elsif entity.is_a?(Sketchup::Face)
        entity.edges.each do |edge|
          add_edge_preview(edge, parent_to_world, planes, delta, clearance, segments, seen)
          break if segments.length >= max_segments
        end
      elsif PlaneVertexSelector.group_or_component?(entity)
        child_to_world = parent_to_world * entity.transformation
        PlaneVertexSelector.child_entities(entity).each do |child|
          collect_preview_entity(child, child_to_world, planes, delta, clearance, segments, seen, max_segments)
          break if segments.length >= max_segments
        end
      end
    rescue => error
      warn "MH Stretch preview collect failed: #{error.class}: #{error.message}"
      nil
    end

    def add_edge_preview(edge, parent_to_world, planes, delta, clearance, segments, seen)
      return unless edge && edge.valid?

      key = edge_key(edge, parent_to_world)
      return if seen[key]

      p1 = edge.start.position.transform(parent_to_world)
      p2 = edge.end.position.transform(parent_to_world)
      s1 = preview_point(p1, planes, delta, clearance)
      s2 = preview_point(p2, planes, delta, clearance)
      return if same_point?(p1, s1) && same_point?(p2, s2)

      seen[key] = true
      segments << [s1, s2]
    rescue
      nil
    end

    def preview_point(point, planes, delta, clearance)
      count = planes.count do |plane|
        PlaneVertexSelector.in_moving_zone?(
          point,
          plane[:axis],
          plane[:side] || :plus,
          plane[:pos],
          clearance
        )
      end
      return point if count.zero?

      point.offset(scale_vector(delta, count))
    end

    def stretch_planes(plane)
      source = plane && plane[:planes]
      planes = source.to_a.select do |item|
        item && item[:axis] && item[:pos] && !item[:hidden]
      end
      planes = [plane] if planes.empty? && plane && !plane[:hidden]
      return [] if planes.empty?
      side = plane[:side] || :plus
      planes.map do |item|
        item.merge(side: side)
      end
    end

    def scale_vector(vector, factor)
      Geom::Vector3d.new(vector.x * factor, vector.y * factor, vector.z * factor)
    end

    def same_point?(a, b)
      a.distance(b) <= 0.0001.mm
    rescue
      false
    end

    def edge_key(edge, parent_to_world)
      base = edge.respond_to?(:persistent_id) ? edge.persistent_id : edge.object_id
      [base, parent_to_world.to_a.map { |value| value.to_f.round(6) }]
    rescue
      [edge.object_id, parent_to_world.object_id]
    end
  end
end


