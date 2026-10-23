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

      # A placeable cavity must reach at least one side of the host envelope.
      # A fully enclosed void is not an accessible fit target; use the host's
      # outside bounds instead (for example, a closed box with six panels).
      def open_cavity?(envelope, region, tolerance: 0.02)
        return false unless envelope && region
        3.times.any? do |axis|
          (region[0][axis]-envelope[0][axis]).abs<=tolerance ||
            (region[1][axis]-envelope[1][axis]).abs<=tolerance
        end
      end

      # Build the empty region around a picked point from six nearest ray hits.
      # Missing hits stay clipped to the host envelope, which supports an open
      # face while keeping the other five measured limits exact.
      def ray_region(envelope, seed, hits, minimum_hits: 4)
        Core.bounds!(envelope)
        return unless inside?(seed,envelope)
        region=Core.copy_data(envelope);count=0
        3.times do |axis|
          2.times do |side|
            point=hits[[axis,side]]
            next unless point && point.length==3 && point.all? { |value| value.is_a?(Numeric) && value.finite? }
            coordinate=[[point[axis],envelope[0][axis]].max,envelope[1][axis]].min
            if side.zero?
              next unless coordinate<seed[axis]-0.001
              region[0][axis]=[region[0][axis],coordinate].max
            else
              next unless coordinate>seed[axis]+0.001
              region[1][axis]=[region[1][axis],coordinate].min
            end
            count+=1
          end
        end
        return if count<minimum_hits || !inside?(seed,region)
        region if Core.dimensions(region).all? { |size| size>1.0 }
      end

      # Top-level panels of one exploded cabinet may be separate components.
      # Starting from the picked panel, accept only same-layer containers whose
      # bodies meet on a substantial face area. A spatial limit stops a chain
      # from collecting a distant second cabinet; a separate touching candidate
      # is ambiguous. The returned box is the world-space cabinet envelope.
      def exploded_envelope(boxes, picked, minimum_contact_area: 500.0)
        bounds=Array(boxes).map { |box| Core.bounds!(box) }
        picked=Core.bounds!(picked)
        index=bounds.index { |box| Core.bounds_close?(box,picked,0.02) }
        return unless index && bounds.length>1
        neighbors=bounds.each_index.filter_map do |other|
          next if other==index
          axis=contact_axis(picked,bounds[other])
          next unless axis
          next unless contact_area(picked,bounds[other],axis)>=minimum_contact_area
          other
        end
        # One touching part does not prove a surrounding module. Require two
        # independent siblings, then use only their direct contacts with the
        # picked panel; this avoids growing through an entire connected cabinet
        # bank by transitive adjacency.
        return if neighbors.length<2
        members=[index,*neighbors].map { |item| bounds[item] }
        host=Frames.box(members.flat_map { |box| Frames.corners(box) })
        return if Core.bounds_close?(host,picked,0.02)
        host
      end

      def contact_axis(a, b)
        bounds=[Core.bounds!(a),Core.bounds!(b)]
        gap=3.times.select { |axis| (bounds[0][1][axis]-bounds[1][0][axis]).abs<=0.02 || (bounds[1][1][axis]-bounds[0][0][axis]).abs<=0.02 }
        gap.length==1 ? gap.first : nil
      end

      def contact_area(a, b, axis)
        other_axes=(0..2).to_a-[axis]
        spans=other_axes.map do |other|
          [a[1][other],b[1][other]].min-[a[0][other],b[0][other]].max
        end
        return 0.0 unless spans.all?(&:positive?)
        spans.reduce(:*)
      end

      def fit(source, target)
        raise Core::Error,'Kích thước vùng đặt module không hợp lệ.' unless Core.dimensions(source).all? { |v| v>0.01 && v.finite? } && Core.dimensions(target).all? { |v| v>0.1 && v.finite? }
        Frames.bounds_delta(source.map { |point| point.map(&:to_f) },target.map { |point| point.map(&:to_f) })
      end

      # A loose SketchUp face is a two-dimensional target. Fit the module's X/Z
      # footprint to the face bounds, keep its Y depth (including physical T),
      # and return a right-handed world frame for the native placement adapter.
      def face_fit_region(points, depth, toward: nil)
        points=Array(points).map { |point| Array(point).map(&:to_f) }
        unless points.length>=3 && points.all? { |point| point.length==3 && point.all?(&:finite?) }
          raise Core::Error,'Mặt chọn không tạo được vùng đặt hữu hạn.'
        end
        depth=Float(depth)
        raise Core::Error,'Chiều sâu mẫu không hợp lệ để Fit mặt.' unless depth.finite? && depth>0.01

        base=points.first
        normal=nil
        (1...(points.length-1)).each do |index|
          candidate=vector_cross(vector_sub(points[index],base),vector_sub(points[index+1],base))
          if vector_length(candidate)>0.000001
            normal=vector_unit(candidate)
            break
          end
        end
        raise Core::Error,'Mặt chọn bị suy biến, không thể Fit.' unless normal
        normal=normal.map { |value| -value } if toward && vector_dot(normal,vector_sub(toward.map(&:to_f),base))<0

        world_up=[0.0,0.0,1.0]
        projected_up=vector_sub(world_up,normal.map { |value| value*vector_dot(world_up,normal) })
        if vector_length(projected_up)>0.000001
          z_axis=vector_unit(projected_up)
          x_axis=vector_unit(vector_cross(normal,z_axis))
        else
          edges=points.each_index.map { |index| vector_sub(points[(index+1)%points.length],points[index]) }
          edge=edges.max_by { |vector| vector_length(vector_sub(vector,normal.map { |value| value*vector_dot(vector,normal) })) }
          x_axis=vector_unit(vector_sub(edge,normal.map { |value| value*vector_dot(edge,normal) }))
          z_axis=vector_unit(vector_cross(x_axis,normal))
        end

        x_values=points.map { |point| vector_dot(vector_sub(point,base),x_axis) }
        z_values=points.map { |point| vector_dot(vector_sub(point,base),z_axis) }
        min_x,max_x=x_values.minmax
        min_z,max_z=z_values.minmax
        width=max_x-min_x;height=max_z-min_z
        unless width.finite? && height.finite? && width>0.1 && height>0.1
          raise Core::Error,'Mặt chọn không có diện tích Fit hợp lệ.'
        end
        origin=3.times.map { |axis| base[axis]+x_axis[axis]*min_x+z_axis[axis]*min_z }
        {'origin'=>origin,'axes'=>[x_axis,normal,z_axis],
         'bounds'=>[[0.0,0.0,0.0],[width,depth,height]]}
      rescue ArgumentError,TypeError
        raise Core::Error,'Kích thước vùng mặt không hợp lệ.'
      end

      def vector_sub(a,b)
        3.times.map { |axis| a[axis]-b[axis] }
      end

      def vector_dot(a,b)
        3.times.sum { |axis| a[axis]*b[axis] }
      end

      def vector_cross(a,b)
        [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
      end

      def vector_length(vector)
        Math.sqrt(vector_dot(vector,vector))
      end

      def vector_unit(vector)
        length=vector_length(vector)
        raise Core::Error,'Trục mặt chọn không hợp lệ.' unless length.finite? && length>0.000001
        vector.map { |value| value/length }
      end
    end
  end
end
