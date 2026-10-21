# encoding: UTF-8
require_relative 'domain'

module MH
  module ModuleStudio
    module Frames
      extend self
      IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].freeze
      def multiply(a, b)
        16.times.map { |index| row = index % 4; column = index / 4; 4.times.sum { |k| a[k * 4 + row] * b[column * 4 + k] } }
      end
      def point(matrix, point)
        homogeneous = matrix[3] * point[0] + matrix[7] * point[1] + matrix[11] * point[2] + matrix[15]
        raise Core::Error, 'Phép biến đổi suy biến.' if homogeneous.abs < 1.0e-10
        3.times.map { |axis| (matrix[axis] * point[0] + matrix[4 + axis] * point[1] + matrix[8 + axis] * point[2] + matrix[12 + axis]) / homogeneous }
      end
      def corners(bounds)
        [0, 1].repeated_permutation(3).map { |sides| 3.times.map { |axis| bounds[sides[axis]][axis] } }
      end
      def box(points)
        [3.times.map { |axis| points.map { |point| point[axis] }.min },
         3.times.map { |axis| points.map { |point| point[axis] }.max }]
      end

      # Millimetre bounds -> affine matrix operating on SketchUp inch vertices.
      # The adapter only constructs Geom::Transformation and applies this plan.
      def bounds_delta(old_bounds, new_bounds)
        old_size = Core.dimensions(old_bounds)
        new_size = Core.dimensions(new_bounds)
        scale = 3.times.map { |axis| new_size[axis] / old_size[axis] }
        matrix = IDENTITY.dup
        [0, 5, 10].each_with_index { |index, axis| matrix[index] = scale[axis] }
        3.times { |axis| matrix[12 + axis] = (new_bounds[0][axis] - old_bounds[0][axis] * scale[axis]) / 25.4 }
        matrix
      end
      def scale_frame(matrix)
        axes = [0, 4, 8].map { |offset| matrix[offset, 3].map { |v| v / matrix[15] } }
        lengths = axes.map { |axis| Math.sqrt(axis.sum { |v| v * v }) }
        raise Core::Error, 'Module có scale bằng 0.' if lengths.any? { |value| value < 1.0e-8 }
        3.times do |a|
          ((a + 1)...3).each do |b|
            dot = 3.times.sum { |i| axes[a][i] * axes[b][i] } / (lengths[a] * lengths[b])
            raise Core::Error, 'Module bị shear; bản đầu cần các trục vuông góc.' if dot.abs > 1.0e-6
          end
        end
        result = IDENTITY.dup
        [0, 5, 10].each_with_index { |index, axis| result[index] = lengths[axis] }
        result
      end
    end

  end
end
