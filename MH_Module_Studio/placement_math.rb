# encoding: UTF-8
require_relative 'frames'

module MH
  module ModuleStudio
    module PlacementMath
      extend self

      def inside?(point, bounds, tolerance = 0.001)
        3.times.all? { |axis| point[axis]>bounds[0][axis]+tolerance && point[axis]<bounds[1][axis]-tolerance }
      end

      def overlap?(a, b)
        3.times.all? { |axis| [a[1][axis],b[1][axis]].min-[a[0][axis],b[0][axis]].max>0.001 }
      end

      # Empty rectangular region containing the cursor seed. Open sides are
      # bounded by the host envelope; real panel faces supply the other limits.
      def cavity(envelope, panels, seed, minimum_hits: 4)
        return unless inside?(seed,envelope) && panels.none? { |box| inside?(seed,box,-0.001) }
        result = Core.copy_data(envelope)
        hits = 0
        3.times do |axis|
          others = [0,1,2]-[axis]
          aligned = panels.select { |box| others.all? { |i| seed[i]>=box[0][i]-0.001 && seed[i]<=box[1][i]+0.001 } }
          low = aligned.filter_map { |box| box[1][axis] if box[1][axis]<seed[axis]-0.001 }.max
          high = aligned.filter_map { |box| box[0][axis] if box[0][axis]>seed[axis]+0.001 }.min
          result[0][axis] = [result[0][axis],low].max if low
          result[1][axis] = [result[1][axis],high].min if high
          hits += [low,high].compact.length
        end
        return if hits<minimum_hits
        # Off-centre braces can miss all six seed rays. Trim the region too, so
        # the preview cannot pass through such a brace or a partial shelf.
        panels.sort_by { |box| 3.times.sum { |axis| [box[0][axis]-seed[axis],seed[axis]-box[1][axis],0].max**2 } }.each do |box|
          next unless overlap?(result,box)
          candidates = 3.times.filter_map do |axis|
            cut = Core.copy_data(result)
            if seed[axis]<box[0][axis]-0.001
              cut[1][axis] = [cut[1][axis],box[0][axis]].min
            elsif seed[axis]>box[1][axis]+0.001
              cut[0][axis] = [cut[0][axis],box[1][axis]].max
            else
              next
            end
            cut if Core.dimensions(cut).all? { |size| size>1 }
          end
          return nil if candidates.empty?
          result = candidates.max_by { |box_bounds| Core.dimensions(box_bounds).reduce(:*) }
        end
        result if Core.dimensions(result).all? { |size| size>1 } && panels.none? { |box| overlap?(result,box) }
      end

      def fit(source, target)
        raise Core::Error,'Kích thước vùng đặt module không hợp lệ.' unless Core.dimensions(source).all? { |v| v>0.01 && v.finite? } && Core.dimensions(target).all? { |v| v>0.1 && v.finite? }
        Frames.bounds_delta(source.map { |point| point.map(&:to_f) },target.map { |point| point.map(&:to_f) })
      end
    end
  end
end
