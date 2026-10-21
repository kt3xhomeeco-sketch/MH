# encoding: UTF-8
# Hợp đồng số học dùng chung với Desktop product_x_cluster.js. Đơn vị inch.
module MH
  module ProductXCluster
    remove_const(:VERSION) if const_defined?(:VERSION, false)
    VERSION = 'name-first-world-x-v3'.freeze
    EPS = 1e-7 unless const_defined?(:EPS, false)
    module_function

    def group_markers(markers, gap_mm = 10)
      groups = []
      limit = [gap_mm.to_f, 0].max / 25.4
      markers.sort_by { |m| m[:lo] }.each do |marker|
        group = groups.last
        if !group || marker[:lo] - group[:hi] > limit + EPS
          group = { hi: marker[:hi], markers: [] }
          groups << group
        end
        group[:hi] = [group[:hi], marker[:hi]].max
        group[:markers] << marker
      end
      groups.flat_map do |group|
        codes = group[:markers].map { |m| m[:code] }.uniq.sort
        group[:markers].map { |marker| marker.merge(code: codes.join('|'), codes: codes) }
      end
    end

    def close(a, b)
      (a - b).abs <= EPS
    end

    def compare(a, b)
      return a[0] < b[0] ? -1 : 1 unless close(a[0], b[0])
      close(a[1], b[1]) ? 0 : a[1] < b[1] ? -1 : 1
    end

    def resolve(items, markers)
      groups = []
      items.select { |i| i[:lo].is_a?(Numeric) && i[:hi].is_a?(Numeric) && i[:lo].finite? && i[:hi].finite? && i[:lo] <= i[:hi] }
           .sort_by { |i| [i[:lo], i[:hi], i[:id].to_s] }.each do |item|
        group = groups.last
        if !group || item[:lo] > group[:hi] + EPS
          group = { lo: item[:lo], hi: item[:hi], ids: [], seeds: {}, owners: [], cost: nil }
          groups << group
        end
        group[:hi] = [group[:hi], item[:hi]].max
        group[:ids] << item[:id]
      end
      labels = markers.select { |m| m[:x].is_a?(Numeric) && m[:x].finite? && !m[:code].to_s.empty? }.sort_by { |m| m[:x] }
      labels.each do |marker|
        best = Float::INFINITY
        candidates = []
        groups.each_with_index do |group, index|
          next if (marker[:x] < group[:lo] - EPS || marker[:x] > group[:hi] + EPS) && labels.any? { |other|
            other[:code] != marker[:code] && other[:x] >= group[:lo] - EPS && other[:x] <= group[:hi] + EPS
          }
          hit = [[marker[:x], group[:hi]].min, group[:lo]].max
          low, high = [marker[:x], hit].minmax
          next if labels.any? { |other| other[:code] != marker[:code] && other[:x] > low + EPS && other[:x] < high - EPS }
          distance = [group[:lo] - marker[:x], marker[:x] - group[:hi], 0].max
          if distance < best - EPS
            best = distance
            candidates = [index]
          elsif close(distance, best)
            candidates << index
          end
        end
        candidates.each do |i|
          groups[i][:seeds][marker[:code]] = [best, groups[i][:seeds].fetch(marker[:code], Float::INFINITY)].min
        end
      end
      offer = lambda do |group, code, cost|
        result = group[:cost] ? compare(cost, group[:cost]) : -1
        if result < 0
          group[:cost] = cost
          group[:owners] = [code]
        elsif result == 0
          group[:owners] |= [code]
        end
      end
      groups.each_with_index do |seed_group, seed|
        seed_group[:seeds].each do |code, initial|
          offer.call(seed_group, code, [initial, initial])
          [-1, 1].each do |direction|
            cost = [initial, initial]
            i = seed + direction
            while i >= 0 && i < groups.length
              break if groups[i][:seeds].any? { |other, distance| other != code && distance <= EPS }
              left, right = [i, i - direction].minmax.map { |j| groups[j] }
              distance = [0, right[:lo] - left[:hi]].max
              cost = [[cost[0], distance].max, cost[1] + distance]
              offer.call(groups[i], code, cost)
              i += direction
            end
          end
        end
      end
      owners, ambiguous = {}, []
      groups.each do |group|
        group[:ids].each do |id|
          owners[id] = group[:owners].first if group[:owners].length == 1
          ambiguous << id if group[:owners].length > 1
        end
      end
      present_codes = owners.values.uniq
      empty = labels.reject { |marker| present_codes.include?(marker[:code]) }.map { |marker| marker[:code] }
      { owners: owners, ambiguous: ambiguous, empty_markers: empty.uniq, groups: groups.length }
    end
  end
end
