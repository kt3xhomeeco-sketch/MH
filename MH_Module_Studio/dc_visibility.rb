# encoding: UTF-8
module MH
  module ModuleStudio
    module DCVisibility
      extend self

      def enabled?(snapshot)
        snapshot['visibility_version']==1
      end

      def compatible_guards!(before, after, enabled)
        left = before.reject { |key,_value| enabled && key.end_with?('!hidden') }
        right = after.reject { |key,_value| enabled && key.end_with?('!hidden') }
        unless left==right
          message = enabled ? 'Tham số làm đổi số lượng hoặc góc xoay; chưa hỗ trợ.' : 'Tham số làm đổi số lượng, ẩn/hiện hoặc góc xoay; đọc lại DC để cập nhật quy tắc.'
          raise Core::Error,message
        end
      end

      def states(snapshot, &attribute)
        nodes = snapshot['dc_graph']['nodes']
        by_id = nodes.to_h { |node| [id(node),node] }
        cache = {}; stack = []; resolve = nil
        resolve = lambda do |key|
          next true if key.empty?
          next cache[key] if cache.key?(key)
          raise Core::Error,'Cây ẩn/hiện vòng hoặc quá sâu.' if stack.include?(key) || stack.length>=30
          node = by_id.fetch(key)
          unless [true,false].include?(node['hidden']) && [true,false].include?(node['tag_visible'])
            raise Core::Error,'Thiếu trạng thái ẩn/hiện riêng của group; đọc lại từ SketchUp.'
          end
          stack << key
          hidden = hidden_formula?(node) ? !attribute.call(key,'hidden').zero? : node['hidden']
          visible = resolve.call(parent(node)) && !hidden && node['tag_visible']
          stack.pop
          cache[key] = visible
        end
        visible = nodes.select { |node| node['part_key'] }.to_h { |node| [node['part_key'],resolve.call(id(node))] }
        updates = nodes.select { |node| hidden_formula?(node) }.filter_map do |node|
          anchor = nodes.find do |leaf|
            next false unless leaf['part_key']
            path = id(leaf); seen = []
            until path.empty? || seen.include?(path)
              break if path==id(node)
              seen << path; path = parent(by_id.fetch(path))
            end
            path==id(node)
          end
          next unless anchor
          depth = 0; path = id(anchor)
          until path==id(node)
            depth += 1; path = parent(by_id.fetch(path))
          end
          {'part'=>anchor['part_key'],'depth'=>depth,'hidden'=>!attribute.call(id(node),'hidden').zero?}
        end
        [visible,updates]
      rescue KeyError
        raise Core::Error,'Cây ẩn/hiện thiếu group cha.'
      end

      def id(node)
        node.key?('parent_id') ? node['id'] : node['path'].join(' / ')
      end

      def parent(node)
        node.key?('parent_id') ? node['parent_id'] : node['path'][0...-1].join(' / ')
      end

      def hidden_formula?(node)
        !node['attributes']['_hidden_formula'].to_s.strip.empty?
      end

      def updates(before, after)
        old = before.to_h { |entry| [[entry['part'],entry['depth']],entry['hidden']] }
        after.reject { |entry| old[[entry['part'],entry['depth']]]==entry['hidden'] }
      end

      def pending(snapshot, desired)
        nodes = snapshot.dig('dc_graph','nodes') || []
        by_id = nodes.to_h { |node| [id(node),node] }
        parts = nodes.select { |node| node['part_key'] }.to_h { |node| [node['part_key'],node] }
        desired.reject do |entry|
          node = parts.fetch(entry['part'])
          if node['visibility_flattened']
            true
          else
            entry['depth'].times { node = by_id.fetch(parent(node)) }
            node['hidden']==entry['hidden']
          end
        end
      rescue KeyError
        raise Core::Error,'Thiếu cây ẩn/hiện hiện tại; đọc lại module.'
      end

      def apply_metadata!(snapshot, desired)
        nodes = snapshot.dig('dc_graph','nodes') || []
        by_id = nodes.to_h { |node| [id(node),node] }
        parts = nodes.select { |node| node['part_key'] }.to_h { |node| [node['part_key'],node] }
        desired.each do |entry|
          node = parts.fetch(entry['part'])
          next if node['visibility_flattened']
          entry['depth'].times { node = by_id.fetch(parent(node)) }
          node['hidden'] = entry['hidden']
        end
      end

      def part_change(part,bounds,visible,_updates)
        moving = !Core.bounds_close?(part['bounds'],bounds,0.001)
        old_visible = part['visible']!=false
        GeometryMotion.validate!(part.merge('visible'=>visible),bounds,moving)
        part.merge('bounds'=>bounds,'old_bounds'=>part['bounds'],'visible'=>visible,'old_visible'=>old_visible,
                   'changed'=>moving || old_visible!=visible)
      end
    end
  end
end
