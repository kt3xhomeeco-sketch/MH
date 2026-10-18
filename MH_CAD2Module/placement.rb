# frozen_string_literal: true

module MH
  module CAD2Module
    # Portable checks shared by host construction and unit tests.
    module Placement
      module_function

      def base_x(label_center_x, width)
        Float(label_center_x) - Float(width) / 2.0
      end

      def source_matrix(placement)
        u, v = placement.fetch('origin_mm')
        offset = placement.fetch('plane_offset_mm', 0)
        raise ArgumentError, 'Gốc nguồn quét không hợp lệ.' unless [u, v, offset].all? { |n| n.is_a?(Numeric) && n.finite? }
        axes, origin = case placement.fetch('plane')
                       when 'XY' then [[[1, 0, 0], [0, 1, 0], [0, 0, 1]], [u, v, offset]]
                       when 'XZ' then [[[1, 0, 0], [0, 0, 1], [0, -1, 0]], [u, offset, v]]
                       when 'YZ' then [[[0, 1, 0], [0, 0, 1], [1, 0, 0]], [offset, u, v]]
                       else raise ArgumentError, 'Mặt phẳng nguồn quét không hợp lệ.'
                       end
        axes.flat_map { |axis| axis + [0] } + origin.map { |n| n / 25.4 } + [1]
      end

      def validate_module(mod)
        size = mod.fetch('size')
        origin = mod.fetch('origin')
        valid = size.length == 3 && origin.length == 3 &&
                size.all? { |value| value.is_a?(Numeric) && value.finite? && value.positive? && value < 100_000 } &&
                origin.all? { |value| value.is_a?(Numeric) && value.finite? && value.abs < 100_000 }
        raise ArgumentError, 'Kích thước hoặc vị trí module không hợp lệ.' unless valid
        true
      end

      def overlap?(a, b)
        3.times.all? do |axis|
          left = [a['origin'][axis], b['origin'][axis]].max
          right = [a['origin'][axis] + a['size'][axis], b['origin'][axis] + b['size'][axis]].min
          right - left > 0.1
        end
      end
    end
  end
end
