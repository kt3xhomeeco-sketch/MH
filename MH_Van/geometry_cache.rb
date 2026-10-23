# encoding: UTF-8

module MH
  module Van
    # Store local geometry once per definition. Rotation and translation do not
    # change thickness; scale/shear are applied using transformed plane normals.
    module GeometryCache
      EPSILON = 1.0e-9
      class << self
        def clear
          @profiles = {}
        end

        def invalidate(definition)
          (@profiles ||= {}).delete(definition)
        end

        def transform_axes(transform)
          # SketchUp's xaxis/yaxis/zaxis accessors normalize the vectors and
          # discard scale. Read the affine columns, including homogeneous w.
          matrix = transform.to_a
          weight = matrix[15].to_f
          return nil if weight.abs <= EPSILON

          [0, 4, 8].map { |offset| matrix[offset, 3].map { |value| value.to_f / weight } }
        end

        def thickness(entity, transform = nil)
          definition = entity.respond_to?(:definition) ? entity.definition : nil
          return nil unless definition

          profile = (@profiles ||= {})[definition] ||= build_profile(definition)
          transform ||= entity.transformation
          axes = transform_axes(transform)
          return nil unless axes
          cofactors = [cross(axes[1], axes[2]), cross(axes[2], axes[0]), cross(axes[0], axes[1])]
          determinant = dot(axes[0], cofactors[0]).abs
          return nil if determinant <= EPSILON

          candidates = profile[:planes].filter_map do |plane|
            normal = plane[:normal]
            transformed = (0..2).map { |i| (0..2).sum { |j| cofactors[j][i] * normal[j] } }
            normal_length = length(transformed)
            next if normal_length <= EPSILON

            # |det(A)| / |cofactor(A) n| is the distance scale between
            # parallel planes, including nonuniform scale and mirrored axes.
            { thickness: plane[:span] * determinant / normal_length,
              area: plane[:area] * normal_length, paired: plane[:paired] }
          end
          if candidates.any?
            paired = candidates.select { |candidate| candidate[:paired] }
            best = (paired.empty? ? candidates : paired).max_by { |candidate| candidate[:area] }
            mm = best[:thickness] * 25.4
            return mm if mm > 0.1
            return nil unless profile[:has_children]
          end

          # Assemblies without direct faces have no unique board normal. Use
          # local bounds, keeping flat objects excluded even when rotated.
          dimensions = profile[:dimensions]
          return nil unless dimensions.all? { |value| value > EPSILON }

          mm = dimensions.each_with_index.map { |value, index| value * length(axes[index]) * 25.4 }.min
          mm > 0.1 ? mm : nil
        end

        private

        def build_profile(definition)
          faces = definition.entities.grep(Sketchup::Face)
          vertices = faces.flat_map(&:vertices).uniq
          points = vertices.map { |vertex| p = vertex.position; [p.x.to_f, p.y.to_f, p.z.to_f] }
          directions = {}
          faces.each do |face|
            vector = face.normal
            normal = [vector.x.to_f, vector.y.to_f, vector.z.to_f]
            size = length(normal)
            next if size <= EPSILON || face.area.to_f <= EPSILON

            normal = normal.map { |value| value / size }
            sign = normal.find { |value| value.abs > 1.0e-6 }.to_f < 0 ? -1 : 1
            normal = normal.map { |value| value * sign }
            key = normal.map { |value| value.round(6) }
            direction = directions[key] ||= { normal: normal, offsets: {} }
            point = face.vertices.first.position
            offset = dot(normal, [point.x.to_f, point.y.to_f, point.z.to_f]).round(6)
            direction[:offsets][offset] = direction[:offsets].fetch(offset, 0.0) + face.area.to_f
          end
          planes = directions.values.map do |direction|
            projections = points.map { |point| dot(point, direction[:normal]) }
            { normal: direction[:normal], span: projections.max - projections.min,
              area: direction[:offsets].values.max, paired: direction[:offsets].length > 1 }
          end
          bounds = definition.bounds
          { planes: planes, dimensions: [bounds.width.to_f, bounds.height.to_f, bounds.depth.to_f],
            has_children: definition.entities.any? { |child| child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance) } }
        end

        def dot(a, b)
          a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        end

        def cross(a, b)
          [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        end

        def length(vector)
          Math.sqrt(dot(vector, vector))
        end
      end
    end
  end
end
