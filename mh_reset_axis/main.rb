# encoding: UTF-8

require 'sketchup.rb'

module MH
  module ResetAxis
    extend self

    PLUGIN_NAME = 'MH Reset Axis'.freeze
    VERSION = '1.0.9'.freeze
    EPSILON = 1.0e-6
    PARALLEL_COSINE = Math.cos(5.0 * Math::PI / 180.0)
    ORTHOGONAL_COSINE = Math.cos(85.0 * Math::PI / 180.0)

    MODE_SIZE = :size
    MODE_VERTICAL = :vertical

    LABEL_SIZE = 'Dài nhất → Y, ngắn nhất → Z'.freeze
    LABEL_VERTICAL = 'Đứng → Y, ngang → X, ngắn nhất → Z'.freeze

    def container?(entity)
      entity.is_a?(Sketchup::Group) ||
        entity.is_a?(Sketchup::ComponentInstance)
    end

    def selected_containers
      Sketchup.active_model.selection.to_a.select { |entity| container?(entity) }
    end

    def canonical_direction(vector)
      direction = vector.normalize
      components = [direction.x, direction.y, direction.z]
      first = components.find { |value| value.abs > EPSILON }
      first && first < 0.0 ? direction.reverse : direction
    end

    def scaled_vector(vector, scale)
      Geom::Vector3d.new(
        vector.x * scale,
        vector.y * scale,
        vector.z * scale
      )
    end

    def face_normal(face, transformation)
      vertices = face.outer_loop.vertices.map do |vertex|
        vertex.position.transform(transformation)
      end
      return nil if vertices.length < 3

      anchor = vertices.first
      (1...(vertices.length - 1)).each do |index|
        candidate = anchor.vector_to(vertices[index]).cross(
          anchor.vector_to(vertices[index + 1])
        )
        next if candidate.length <= EPSILON

        candidate.normalize!
        return candidate
      end

      nil
    end

    def collect_geometry(entities, transformation, points, edge_vectors, normal_vectors, definition_stack)
      entities.each do |entity|
        if entity.is_a?(Sketchup::Edge)
          point1 = entity.start.position.transform(transformation)
          point2 = entity.end.position.transform(transformation)
          vector = point1.vector_to(point2)
          next if vector.length <= EPSILON

          points << point1
          points << point2
          edge_vectors << vector
        elsif entity.is_a?(Sketchup::Face)
          normal = face_normal(entity, transformation)
          normal_vectors << normal if normal
        elsif container?(entity)
          definition = entity.definition
          key = definition.object_id
          next if definition_stack.include?(key)

          definition_stack << key
          collect_geometry(
            definition.entities,
            transformation * entity.transformation,
            points,
            edge_vectors,
            normal_vectors,
            definition_stack
          )
          definition_stack.pop
        end
      end
    end

    def geometry_data(definition)
      points = []
      edge_vectors = []
      normal_vectors = []
      collect_geometry(
        definition.entities,
        Geom::Transformation.new,
        points,
        edge_vectors,
        normal_vectors,
        [definition.object_id]
      )
      [points, edge_vectors, normal_vectors]
    end

    def polygon_normal(points)
      return nil if points.length < 3

      anchor = points.first
      (1...(points.length - 1)).each do |index|
        candidate = anchor.vector_to(points[index]).cross(
          anchor.vector_to(points[index + 1])
        )
        next if candidate.length <= EPSILON

        candidate.normalize!
        return candidate
      end
      nil
    end

    def polygon_area(points, normal = nil)
      normal ||= polygon_normal(points)
      return 0.0 unless normal

      anchor = points.first
      area = 0.0
      (1...(points.length - 1)).each do |index|
        cross = anchor.vector_to(points[index]).cross(
          anchor.vector_to(points[index + 1])
        )
        area += cross.dot(normal).abs * 0.5
      end
      area
    end

    def collect_parent_geometry(entities, transformation, points, edge_vectors, faces, definition_stack)
      entities.each do |entity|
        if entity.is_a?(Sketchup::Edge)
          point1 = entity.start.position.transform(transformation)
          point2 = entity.end.position.transform(transformation)
          vector = point1.vector_to(point2)
          next if vector.length <= EPSILON

          points << point1
          points << point2
          edge_vectors << vector
        elsif entity.is_a?(Sketchup::Face)
          face_points = entity.outer_loop.vertices.map do |vertex|
            vertex.position.transform(transformation)
          end
          normal = polygon_normal(face_points)
          next unless normal

          edges = entity.outer_loop.edges.filter_map do |edge|
            point1 = edge.start.position.transform(transformation)
            point2 = edge.end.position.transform(transformation)
            vector = point1.vector_to(point2)
            next if vector.length <= EPSILON

            { length: vector.length, direction: vector.normalize }
          end
          faces << {
            area: polygon_area(face_points, normal),
            normal: normal,
            edges: edges
          }
        elsif container?(entity)
          definition = entity.definition
          key = definition.object_id
          next if definition_stack.include?(key)

          definition_stack << key
          collect_parent_geometry(
            definition.entities,
            transformation * entity.transformation,
            points,
            edge_vectors,
            faces,
            definition_stack
          )
          definition_stack.pop
        end
      end
    end

    def parent_geometry_data(instance)
      points = []
      edge_vectors = []
      faces = []
      collect_parent_geometry(
        instance.definition.entities,
        instance.transformation,
        points,
        edge_vectors,
        faces,
        [instance.definition.object_id]
      )
      [points, edge_vectors, faces]
    end

    def direction_clusters(vectors)
      clusters = []

      vectors.each do |vector|
        length = vector.length
        next if length <= EPSILON

        direction = canonical_direction(vector)
        cluster = clusters.find do |candidate|
          candidate[:direction].dot(direction).abs >= PARALLEL_COSINE
        end

        if cluster
          aligned = cluster[:direction].dot(direction) < 0.0 ? direction.reverse : direction
          cluster[:sum] = cluster[:sum] + scaled_vector(aligned, length)
          cluster[:weight] += length
          cluster[:count] += 1
          cluster[:min_length] = length if length < cluster[:min_length]
          cluster[:max_length] = length if length > cluster[:max_length]
          cluster[:direction] = cluster[:sum].normalize
        else
          clusters << {
            direction: direction,
            sum: scaled_vector(direction, length),
            weight: length,
            count: 1,
            min_length: length,
            max_length: length
          }
        end
      end

      clusters
    end

    def perpendicular?(direction1, direction2)
      direction1.dot(direction2).abs <= ORTHOGONAL_COSINE
    end

    def matching_cluster(clusters, direction)
      cluster = clusters.max_by { |candidate| candidate[:direction].dot(direction).abs }
      return nil unless cluster
      return nil if cluster[:direction].dot(direction).abs < PARALLEL_COSINE

      cluster
    end

    def orient_parent_axes(xaxis, yaxis, zaxis, mode)
      target_x = if mode == MODE_VERTICAL
                   dominant_world_axis(xaxis, [X_AXIS, Y_AXIS])
                 else
                   X_AXIS
                 end
      target_z = if mode == MODE_VERTICAL
                   dominant_world_axis(zaxis, [X_AXIS, Y_AXIS, Z_AXIS])
                 else
                   Z_AXIS
                 end

      candidates = []
      [-1.0, 1.0].each do |x_sign|
        [-1.0, 1.0].each do |y_sign|
          x_candidate = scaled_vector(xaxis, x_sign)
          y_candidate = scaled_vector(yaxis, y_sign)
          z_candidate = x_candidate.cross(y_candidate)
          next if z_candidate.length <= EPSILON

          z_candidate.normalize!
          next if z_candidate.dot(zaxis).abs < PARALLEL_COSINE

          score = if mode == MODE_VERTICAL
                    (y_candidate.dot(Z_AXIS) * 6.0) +
                      (x_candidate.dot(target_x) * 2.0) +
                      z_candidate.dot(target_z)
                  else
                    x_candidate.dot(X_AXIS) +
                      y_candidate.dot(Y_AXIS) +
                      (z_candidate.dot(Z_AXIS) * 2.0)
                  end

          candidates << [score, x_candidate, y_candidate, z_candidate]
        end
      end

      best = candidates.max_by(&:first)
      best ? best[1, 3] : [xaxis, yaxis, zaxis]
    end

    def axes_from_largest_face(faces, mode)
      face = faces.select { |candidate| candidate[:area].to_f > EPSILON }
                  .max_by { |candidate| candidate[:area] }
      return nil unless face

      zaxis = face[:normal]
      edges = face[:edges].to_a.select { |edge| edge[:length].to_f > EPSILON }
      return nil if edges.empty?

      y_edge = if mode == MODE_VERTICAL
                 edges.max_by do |edge|
                   [
                     edge[:direction].dot(Z_AXIS).abs.round(4),
                     edge[:length]
                   ]
                 end
               else
                 edges.max_by { |edge| edge[:length] }
               end
      return nil unless y_edge

      yaxis = y_edge[:direction]
      xaxis = yaxis.cross(zaxis)
      return nil if xaxis.length <= EPSILON

      xaxis.normalize!
      yaxis = zaxis.cross(xaxis)
      return nil if yaxis.length <= EPSILON

      yaxis.normalize!
      orient_parent_axes(xaxis, yaxis, zaxis, mode)
    end

    def parent_direction(local_direction, transformation)
      direction = local_direction.transform(transformation)
      direction.length > EPSILON ? direction.normalize : local_direction.normalize
    end

    def parent_axes_fallback(instance, mode)
      points, edge_vectors, normal_vectors = geometry_data(instance.definition)
      axes = axes_for(instance, points, edge_vectors, normal_vectors, mode)
      return nil unless axes

      axes.map { |axis| parent_direction(axis, instance.transformation) }
    end

    def basis_candidates(clusters, points, instance, mode)
      candidates = []

      clusters.each do |z_cluster|
        clusters.each do |y_cluster|
          next if y_cluster.equal?(z_cluster)
          next unless perpendicular?(y_cluster[:direction], z_cluster[:direction])

          zaxis = z_cluster[:direction]
          yaxis = y_cluster[:direction]
          xaxis = yaxis.cross(zaxis)
          next if xaxis.length <= EPSILON

          xaxis.normalize!
          yaxis = zaxis.cross(xaxis)
          next if yaxis.length <= EPSILON

          yaxis.normalize!
          x_cluster = matching_cluster(clusters, xaxis)
          next unless x_cluster

          x_size = displayed_span_along(points, xaxis, instance)
          y_size = displayed_span_along(points, yaxis, instance)
          z_size = displayed_span_along(points, zaxis, instance)
          x_score_size = score_size(x_size)
          y_score_size = score_size(y_size)
          z_score_size = score_size(z_size)

          score = if mode == MODE_SIZE
                    z_verticality = world_direction(zaxis, instance).dot(Z_AXIS).abs
                    [
                      y_score_size,
                      -z_score_size,
                      z_verticality,
                      x_score_size,
                      y_cluster[:weight] + z_cluster[:weight] + x_cluster[:weight]
                    ]
                  else
                    verticality = world_direction(yaxis, instance).dot(Z_AXIS).abs
                    horizontality = 1.0 - world_direction(xaxis, instance).dot(Z_AXIS).abs
                    [
                      verticality,
                      -z_score_size,
                      y_score_size,
                      horizontality,
                      y_cluster[:weight] + z_cluster[:weight] + x_cluster[:weight]
                    ]
                  end

          candidates << [score, xaxis, yaxis, zaxis]
        end
      end

      candidates
    end

    def score_size(value)
      value.round(4)
    end

    def span_along(points, direction)
      values = points.map do |point|
        (point.x * direction.x) + (point.y * direction.y) + (point.z * direction.z)
      end
      values.max - values.min
    end

    def displayed_span_along(points, local_direction, instance)
      model = Sketchup.active_model
      transformation = model.edit_transform * instance.transformation
      world_points = points.map { |point| point.transform(transformation) }
      world_axis = local_direction.transform(transformation)
      return 0.0 if world_axis.length <= EPSILON

      world_axis.normalize!
      span_along(world_points, world_axis)
    end

    def world_direction(local_direction, instance)
      model = Sketchup.active_model
      transformation = model.edit_transform * instance.transformation
      direction = local_direction.transform(transformation)
      direction.length > EPSILON ? direction.normalize : local_direction.normalize
    end

    def dominant_world_axis(direction, candidates)
      candidates.max_by { |axis| direction.dot(axis).abs }
    end

    def orient_axes(instance, xaxis, yaxis, zaxis, mode)
      world_x_unsigned = world_direction(xaxis, instance)
      world_z_unsigned = world_direction(zaxis, instance)

      target_x = if mode == MODE_VERTICAL
                   dominant_world_axis(world_x_unsigned, [X_AXIS, Y_AXIS])
                 else
                   X_AXIS
                 end
      target_z = if mode == MODE_VERTICAL
                   dominant_world_axis(world_z_unsigned, [X_AXIS, Y_AXIS, Z_AXIS])
                 else
                   Z_AXIS
                 end

      candidates = []
      [-1.0, 1.0].each do |x_sign|
        [-1.0, 1.0].each do |y_sign|
          x_candidate = scaled_vector(xaxis, x_sign)
          y_candidate = scaled_vector(yaxis, y_sign)
          z_candidate = x_candidate.cross(y_candidate)
          next if z_candidate.length <= EPSILON

          z_candidate.normalize!
          next if z_candidate.dot(zaxis).abs < PARALLEL_COSINE

          world_x = world_direction(x_candidate, instance)
          world_y = world_direction(y_candidate, instance)
          world_z = world_direction(z_candidate, instance)

          score = if mode == MODE_VERTICAL
                    (world_y.dot(Z_AXIS) * 6.0) +
                      (world_x.dot(target_x) * 2.0) +
                      world_z.dot(target_z)
                  else
                    world_x.dot(X_AXIS) +
                      world_y.dot(Y_AXIS) +
                      (world_z.dot(Z_AXIS) * 2.0)
                  end

          candidates << [score, x_candidate, y_candidate, z_candidate]
        end
      end

      best = candidates.max_by(&:first)
      best ? best[1, 3] : [xaxis, yaxis, xaxis.cross(yaxis).normalize]
    end

    def axes_for(instance, points, edge_vectors, normal_vectors, mode)
      edge_clusters = direction_clusters(edge_vectors)
      vectors = edge_clusters.length >= 3 ? edge_vectors : edge_vectors + normal_vectors
      clusters = direction_clusters(vectors)
      return nil if clusters.length < 3

      best = basis_candidates(clusters, points, instance, mode).max_by(&:first)
      return nil unless best

      xaxis, yaxis, zaxis = best[1, 3]
      yaxis = zaxis.cross(xaxis).normalize
      xaxis, yaxis, zaxis = orient_axes(instance, xaxis, yaxis, zaxis, mode)
      [xaxis.normalize, yaxis.normalize, zaxis.normalize]
    end

    def minimum_corner(points, xaxis, yaxis, zaxis)
      basis = Geom::Transformation.axes(ORIGIN, xaxis, yaxis, zaxis)
      inverse = basis.inverse
      local_points = points.map { |point| point.transform(inverse) }
      minimum = Geom::Point3d.new(
        local_points.map(&:x).min,
        local_points.map(&:y).min,
        local_points.map(&:z).min
      )
      minimum.transform(basis)
    end

    def reset_definition_axes(instance, mode)
      definition = instance.definition
      parent_points, parent_edge_vectors, parent_faces = parent_geometry_data(instance)
      return 'không tìm thấy cạnh hình học' if parent_points.empty? || parent_edge_vectors.empty?

      axes = axes_from_largest_face(parent_faces, mode) ||
             parent_axes_fallback(instance, mode)
      return 'không xác định được ba phương vuông góc' unless axes

      xaxis, yaxis, zaxis = axes
      entities = definition.entities
      content = entities.to_a
      return 'Group/Component đang rỗng' if content.empty?

      origin = minimum_corner(parent_points, xaxis, yaxis, zaxis)
      old_transformation = instance.transformation
      new_transformation = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)

      entities.transform_entities(
        new_transformation.inverse * old_transformation,
        content
      )
      instance.transformation = new_transformation
      definition.invalidate_bounds
      nil
    end

    def run(mode)
      model = Sketchup.active_model
      containers = selected_containers

      if containers.empty?
        UI.messagebox('Hãy chọn ít nhất một Group hoặc Component.')
        return
      end

      model.start_operation(PLUGIN_NAME, true)
      failures = []

      begin
        containers.each do |entity|
          next unless entity.valid?

          entity.make_unique if entity.respond_to?(:make_unique) &&
                                entity.definition.instances.length > 1
        end

        processed_definitions = {}
        containers.each do |entity|
          next unless entity.valid?
          next if processed_definitions[entity.definition.object_id]

          error = reset_definition_axes(entity, mode)
          if error
            name = entity.name.to_s.strip
            name = entity.definition.name.to_s.strip if name.empty?
            name = '(không tên)' if name.empty?
            failures << "#{name}: #{error}"
          else
            processed_definitions[entity.definition.object_id] = true
          end
        end

        model.commit_operation
      rescue StandardError => error
        model.abort_operation
        UI.messagebox("Không thể reset axis:\n#{error.message}")
        puts(error.full_message)
        return
      end

      model.active_view.invalidate
      if failures.empty?
        Sketchup.status_text = "Đã reset axis #{processed_definitions.length} đối tượng."
      else
        UI.messagebox(
          "Đã xử lý #{processed_definitions.length} đối tượng.\n\n" \
          "Không xử lý được:\n#{failures.join("\n")}"
        )
      end
    end

    def command(label, mode, icon_name)
      command = UI::Command.new(label) { run(mode) }
      icon_path = File.join(__dir__, 'icons', icon_name)
      command.small_icon = icon_path
      command.large_icon = icon_path
      command.tooltip = label
      command.status_bar_text = "Reset axis: #{label}"
      command.set_validation_proc do
        selected_containers.empty? ? MF_GRAYED : MF_ENABLED
      end
      command
    end

    unless file_loaded?(__FILE__)
      size_command = command(LABEL_SIZE, MODE_SIZE, 'mode_size.svg')
      vertical_command = command(LABEL_VERTICAL, MODE_VERTICAL, 'mode_vertical.svg')

      menu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
      menu.add_item(size_command)
      menu.add_item(vertical_command)

      toolbar = UI::Toolbar.new(PLUGIN_NAME)
      toolbar.add_item(size_command)
      toolbar.add_item(vertical_command)
      toolbar.restore

      UI.add_context_menu_handler do |context_menu|
        next if selected_containers.empty?

        submenu = context_menu.add_submenu(PLUGIN_NAME)
        submenu.add_item(size_command)
        submenu.add_item(vertical_command)
      end

      file_loaded(__FILE__)
    end
  end
end
