# encoding: UTF-8
require_relative 'frames'

module MH
  module ModuleStudio
    module GeometryMotion
      extend self

      def wire?(part)
        part['face_count']==0 && part['edge_count'].is_a?(Numeric) && part['edge_count']>0
      end

      def validate!(part, bounds, moving)
        sizes = Core.dimensions(Core.bounds!(bounds))
        return if part['visible']==false && !moving
        if wire?(part) || part['affine_verified']==true || part['linear_mesh_verified']==true
          old = Core.dimensions(part['bounds'])
          raise Core::Error,"#{part['name']}: không dựng thêm chiều dày cho nét 2D." if 3.times.any? { |axis| old[axis]<=0.001 && sizes[axis]>0.001 }
          raise Core::Error,"#{part['name']}: không làm suy biến mặt hình học." if 3.times.any? { |axis| old[axis]>0.001 && sizes[axis]<=0.001 }
        elsif !part['box_verified'] && moving
          unless sizes.zip(Core.dimensions(part['bounds'])).all? { |a,b| (a-b).abs<=0.000001 }
            raise Core::Error,"#{part['name']}: chỉ thay kích thước tấm hộp đã xác minh; chi tiết khác chỉ được di chuyển nguyên hình."
          end
        else
          raise Core::Error,"#{part['name']}: kích thước mới không hợp lệ." unless sizes.all? { |size| size>0.1 }
        end
      end

      # Captured ATT frames retain the untouched local coordinates of legacy
      # guide points; resolving their ancestry never reads native model objects.
      def guide_reference(snapshot,key)
        return unless snapshot && snapshot.dig('dc_graph','nodes').is_a?(Array)
        nodes=snapshot['dc_graph']['nodes'];node=nodes.find { |item| item['part_key']==key }
        part=snapshot['parts'].find { |item| item['key']==key }
        return unless node && part && node['local_bounds'].is_a?(Array)
        lookup=nodes.to_h { |item| [item['id'],item] };chain=[];seen=[];current=node
        while current
          return if seen.include?(current['id']) || chain.length>=40
          seen << current['id'];chain.unshift(current)
          break if current['parent_id'].to_s.empty?
          current=lookup[current['parent_id']]
          return unless current
        end
        frame=snapshot['dc_graph']['root_frame'] || Frames::IDENTITY
        chain.each { |item| frame=Frames.multiply(frame,item['transform']) }
        {'frame'=>frame,'bounds'=>part['bounds'],'local_bounds'=>node['local_bounds']}
      end

      def matrix(old_bounds, target)
        old = Core.dimensions(old_bounds); sizes = Core.dimensions(target)
        matrix = Frames::IDENTITY.dup
        3.times do |axis|
          if old[axis]<=0.001
            raise Core::Error,'Không kéo dày hình học suy biến.' if sizes[axis]>0.001
            scale = 1.0
          else
            scale = sizes[axis].to_f/old[axis]
          end
          matrix[axis*5] = scale
          matrix[12+axis] = (target[0][axis]-old_bounds[0][axis]*scale)/25.4
        end
        matrix
      end
    end
  end
end
