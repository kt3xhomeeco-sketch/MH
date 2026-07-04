# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    module Fit
      module_function

      def scale_to_box(source_bounds, target_min, target_size, eps: 0.001.mm)
        dmin = source_bounds.min
        dmax = source_bounds.max
        dx = (dmax.x - dmin.x).abs
        dy = (dmax.y - dmin.y).abs
        dz = (dmax.z - dmin.z).abs
        target_x, target_y, target_z = target_size

        sx = dx > eps ? target_x / dx : 1.0
        sy = dy > eps ? target_y / dy : 1.0
        sz = dz > eps ? target_z / dz : 1.0

        scale_from_min(source_bounds, target_min, sx, sy, sz)
      end

      def scale_from_min(source_bounds, target_min, sx, sy, sz)
        t1 = Geom::Transformation.translation(ORIGIN - source_bounds.min)
        t2 = Geom::Transformation.scaling(ORIGIN, sx, sy, sz)
        t3 = Geom::Transformation.translation(target_min - ORIGIN)
        t3 * t2 * t1
      end
    end
  end
end
