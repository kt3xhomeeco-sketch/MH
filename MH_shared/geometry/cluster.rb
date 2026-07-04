# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    module Cluster
      module_function

      class UnionFind
        def initialize(count)
          @parent = (0...count).to_a
          @rank = Array.new(count, 0)
        end

        def find(index)
          root = index
          root = @parent[root] while @parent[root] != root
          while @parent[index] != root
            next_index = @parent[index]
            @parent[index] = root
            index = next_index
          end
          root
        end

        def union(left, right)
          root_left = find(left)
          root_right = find(right)
          return if root_left == root_right

          root_left, root_right = root_right, root_left if @rank[root_left] < @rank[root_right]
          @parent[root_right] = root_left
          @rank[root_left] += 1 if @rank[root_left] == @rank[root_right]
        end

        def groups
          result = {}
          @parent.length.times { |index| (result[find(index)] ||= []) << index }
          result.values
        end
      end

      # Khoảng cách bình phương giữa 2 AABB.
      # Thứ tự tham số giữ tương thích với MH_fast_rename.bb_distance_raw.
      def bb_distance_raw(min1x, max1x, min1y, max1y, min1z, max1z,
                          min2x, max2x, min2y, max2y, min2z, max2z)
        dx = min2x > max1x ? min2x - max1x : (min1x > max2x ? min1x - max2x : 0.0)
        dy = min2y > max1y ? min2y - max1y : (min1y > max2y ? min1y - max2y : 0.0)
        dz = min2z > max1z ? min2z - max1z : (min1z > max2z ? min1z - max2z : 0.0)
        dx * dx + dy * dy + dz * dz
      end

      def bb_distance_tuple(left, right)
        return Float::INFINITY unless left && right && left.length >= 6 && right.length >= 6

        bb_distance_raw(
          left[0], left[1], left[2], left[3], left[4], left[5],
          right[0], right[1], right[2], right[3], right[4], right[5]
        )
      end

      def bounds_tuple(bounds)
        return nil unless bounds && bounds.valid?

        [
          bounds.min.x, bounds.max.x,
          bounds.min.y, bounds.max.y,
          bounds.min.z, bounds.max.z
        ]
      rescue
        nil
      end

      def boxes_flat_from_bounds(bounds_list)
        boxes = Array(bounds_list).filter_map { |bounds| bounds_tuple(bounds) }
        boxes.flatten
      end

      # Tự suy gap threshold từ nearest-neighbor jump.
      # boxes_flat: [minx,maxx,miny,maxy,minz,maxz, ...]
      def auto_gap_threshold(boxes_flat, count = nil, sample_limit: 80, fallback: 100.0)
        count ||= Array(boxes_flat).length / 6
        return fallback if count < 2

        max_sample = [count, sample_limit].min
        indices = count <= sample_limit ? (0...count).to_a : (0...count).to_a.sample(max_sample)
        nn_dists = []

        indices.each do |index|
          offset = index * 6
          ax0 = boxes_flat[offset]
          ax1 = boxes_flat[offset + 1]
          ay0 = boxes_flat[offset + 2]
          ay1 = boxes_flat[offset + 3]
          az0 = boxes_flat[offset + 4]
          az1 = boxes_flat[offset + 5]
          min_d2 = Float::INFINITY

          indices.each do |other|
            next if index == other

            other_offset = other * 6
            distance = bb_distance_raw(
              ax0, ax1, ay0, ay1, az0, az1,
              boxes_flat[other_offset], boxes_flat[other_offset + 1],
              boxes_flat[other_offset + 2], boxes_flat[other_offset + 3],
              boxes_flat[other_offset + 4], boxes_flat[other_offset + 5]
            )
            min_d2 = distance if distance < min_d2
          end

          nn_dists << min_d2 if min_d2 < Float::INFINITY
        end

        return fallback if nn_dists.empty?

        sorted = nn_dists.sort
        best_jump = 0.0
        best_split = nil
        sorted.each_cons(2) do |left, right|
          jump = right - left
          next unless jump > best_jump

          best_jump = jump
          best_split = (left + right) / 2.0
        end

        range = sorted.last - sorted.first
        threshold_sq = if best_split && best_jump > range * 0.2
                         best_split
                       else
                         sorted[sorted.length / 2] * 2.0
                       end
        Math.sqrt(threshold_sq)
      rescue
        fallback
      end

      def distance_cluster_indices(boxes_flat, gap_threshold = nil, count: nil, grid: true)
        count ||= Array(boxes_flat).length / 6
        return [] if count <= 0
        return [[0]] if count == 1

        threshold = gap_threshold || auto_gap_threshold(boxes_flat, count)
        gap_sq = threshold * threshold
        union_find = UnionFind.new(count)

        if grid
          union_by_grid(boxes_flat, count, threshold, gap_sq, union_find)
        else
          union_all_pairs(boxes_flat, count, gap_sq, union_find)
        end

        union_find.groups
      end

      def distance_clusters(items, gap_threshold = nil, bounds: nil, grid: true)
        list = Array(items)
        return [] if list.empty?
        return [list] if list.length == 1

        bounds_list = bounds || list.map { |item| item.respond_to?(:bounds) ? item.bounds : nil }
        tuples = bounds_list.map { |bound| bounds_tuple(bound) }
        valid_pairs = []
        tuples.each_with_index do |tuple, index|
          valid_pairs << [index, tuple] if tuple
        end
        return [] if valid_pairs.empty?

        boxes_flat = valid_pairs.flat_map { |(_index, tuple)| tuple }
        groups = distance_cluster_indices(boxes_flat, gap_threshold, count: valid_pairs.length, grid: grid)
        groups.map do |indices|
          indices.map { |local_index| list[valid_pairs[local_index][0]] }
        end
      end

      def union_all_pairs(boxes_flat, count, gap_sq, union_find)
        (0...count).each do |index|
          offset = index * 6
          ax0 = boxes_flat[offset]
          ax1 = boxes_flat[offset + 1]
          ay0 = boxes_flat[offset + 2]
          ay1 = boxes_flat[offset + 3]
          az0 = boxes_flat[offset + 4]
          az1 = boxes_flat[offset + 5]

          ((index + 1)...count).each do |other|
            other_offset = other * 6
            distance = bb_distance_raw(
              ax0, ax1, ay0, ay1, az0, az1,
              boxes_flat[other_offset], boxes_flat[other_offset + 1],
              boxes_flat[other_offset + 2], boxes_flat[other_offset + 3],
              boxes_flat[other_offset + 4], boxes_flat[other_offset + 5]
            )
            union_find.union(index, other) if distance < gap_sq
          end
        end
      end

      def union_by_grid(boxes_flat, count, gap_threshold, gap_sq, union_find)
        cell_size = gap_threshold > 0.01 ? gap_threshold : 100.0
        inv_cell = 1.0 / cell_size
        grid = {}

        count.times do |index|
          offset = index * 6
          cx = ((boxes_flat[offset] + boxes_flat[offset + 1]) * 0.5 * inv_cell).floor
          cy = ((boxes_flat[offset + 2] + boxes_flat[offset + 3]) * 0.5 * inv_cell).floor
          cz = ((boxes_flat[offset + 4] + boxes_flat[offset + 5]) * 0.5 * inv_cell).floor
          (grid[[cx, cy, cz]] ||= []) << index
        end

        grid.each do |cell_key, cell_indices|
          cx, cy, cz = cell_key
          (-1..1).each do |dx|
            (-1..1).each do |dy|
              (-1..1).each do |dz|
                neighbor = grid[[cx + dx, cy + dy, cz + dz]]
                next unless neighbor

                cell_indices.each do |index|
                  offset = index * 6
                  ax0 = boxes_flat[offset]
                  ax1 = boxes_flat[offset + 1]
                  ay0 = boxes_flat[offset + 2]
                  ay1 = boxes_flat[offset + 3]
                  az0 = boxes_flat[offset + 4]
                  az1 = boxes_flat[offset + 5]

                  neighbor.each do |other|
                    next if other <= index

                    other_offset = other * 6
                    distance = bb_distance_raw(
                      ax0, ax1, ay0, ay1, az0, az1,
                      boxes_flat[other_offset], boxes_flat[other_offset + 1],
                      boxes_flat[other_offset + 2], boxes_flat[other_offset + 3],
                      boxes_flat[other_offset + 4], boxes_flat[other_offset + 5]
                    )
                    union_find.union(index, other) if distance < gap_sq
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
