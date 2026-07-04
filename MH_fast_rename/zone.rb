# encoding: UTF-8
# Zone data structure for MH_fast_rename

module MH
  module FastRename

    # Represents a rectangular zone (block) containing objects
    class Zone
      attr_accessor :id, :label, :bounds, :entities, :zone_type, :parent_id, :label_offset

      def initialize(id, bounds, entities = [])
        @id = id
        @bounds = bounds # [min_pt, max_pt] as Geom::Point3d
        @entities = entities
        @label = ""
        @zone_type = :sp
        @parent_id = nil
        @label_offset = 0
      end

      def contains?(entity)
        bb = entity.bounds
        center = bb.center
        mn, mx = @bounds
        center.x >= mn.x && center.x <= mx.x &&
          center.y >= mn.y && center.y <= mx.y &&
          center.z >= mn.z && center.z <= mx.z
      end

      def center
        mn, mx = @bounds
        Geom::Point3d.new(
          (mn.x + mx.x) / 2.0,
          (mn.y + mx.y) / 2.0,
          (mn.z + mx.z) / 2.0
        )
      end

      def width;  mx = @bounds[1]; mn = @bounds[0]; mx.x - mn.x; end
      def depth;  mx = @bounds[1]; mn = @bounds[0]; mx.y - mn.y; end
      def height; mx = @bounds[1]; mn = @bounds[0]; mx.z - mn.z; end

      # Split this zone along a plane. axis: :x, :y, :z. pos: coordinate value
      def split(axis, pos)
        ents1 = []
        ents2 = []
        @entities.each do |e|
          if e.bounds.center.send(axis) < pos
            ents1 << e
          else
            ents2 << e
          end
        end

        zones = []
        zones << MH::FastRename.create_zone(0, ents1) if ents1.any?
        zones << MH::FastRename.create_zone(0, ents2) if ents2.any?
        zones
      end

      # 8 corners of the bounding box
      def corners
        mn, mx = @bounds
        [
          Geom::Point3d.new(mn.x, mn.y, mn.z), Geom::Point3d.new(mx.x, mn.y, mn.z),
          Geom::Point3d.new(mx.x, mx.y, mn.z), Geom::Point3d.new(mn.x, mx.y, mn.z),
          Geom::Point3d.new(mn.x, mn.y, mx.z), Geom::Point3d.new(mx.x, mn.y, mx.z),
          Geom::Point3d.new(mx.x, mx.y, mx.z), Geom::Point3d.new(mn.x, mx.y, mx.z)
        ]
      end
    end

    # Edge-to-edge bounding box distance between two entities
    def self.bb_distance(e1, e2)
      b1 = e1.bounds; b2 = e2.bounds
      # For each axis, compute the gap (0 if overlapping)
      dx = [b2.min.x - b1.max.x, b1.min.x - b2.max.x, 0].max
      dy = [b2.min.y - b1.max.y, b1.min.y - b2.max.y, 0].max
      dz = [b2.min.z - b1.max.z, b1.min.z - b2.max.z, 0].max
      Math.sqrt(dx**2 + dy**2 + dz**2)
    end

    # Auto-detect gap threshold using nearest-neighbor distance analysis
    def self.auto_gap_threshold(entities)
      return 100.0 if entities.length < 2

      # For each entity, find its nearest neighbor (edge-to-edge)
      nn_dists = []
      entities.each_with_index do |a, i|
        min_d = Float::INFINITY
        entities.each_with_index do |b, j|
          next if i == j
          d = bb_distance(a, b)
          min_d = d if d < min_d
        end
        nn_dists << min_d if min_d < Float::INFINITY
      end

      return 100.0 if nn_dists.empty?

      # Sort nearest-neighbor distances
      sorted = nn_dists.sort

      # Find the largest absolute gap in the NN distances
      # This separates "within-cluster" from "between-cluster" distances
      best_split = nil
      best_jump = 0
      sorted.each_cons(2) do |a, b|
        jump = b - a
        if jump > best_jump
          best_jump = jump
          best_split = (a + b) / 2.0
        end
      end

      # Only use the split if the jump is significant (> 30% of range)
      range = sorted.last - sorted.first
      if best_split && best_jump > range * 0.2
        puts "FastRename: NN distances range=#{sorted.first.round(2)}..#{sorted.last.round(2)}, best_jump=#{best_jump.round(2)}"
        best_split
      else
        # Fallback: use median * 2
        sorted[sorted.length / 2] * 2.0
      end
    end

    # Group selected entities into zones based on spatial proximity
    # Uses auto-detected gap threshold based on edge-to-edge BB distances
    def self.cluster_entities(entities, gap_threshold = nil)
      return [] if entities.empty?
      return [create_zone(0, entities)] if entities.length == 1

      gap_threshold ||= auto_gap_threshold(entities)
      puts "FastRename: auto gap_threshold = #{gap_threshold.round(2)}"

      # Single-linkage clustering using edge-to-edge distance
      clusters = entities.map { |e| [e] }

      changed = true
      while changed
        changed = false
        i = 0
        while i < clusters.length
          j = i + 1
          while j < clusters.length
            should_merge = false
            clusters[i].each do |a|
              clusters[j].each do |b|
                if bb_distance(a, b) < gap_threshold
                  should_merge = true
                  break
                end
              end
              break if should_merge
            end
            if should_merge
              clusters[i].concat(clusters[j])
              clusters.delete_at(j)
              changed = true
            else
              j += 1
            end
          end
          i += 1
        end
      end

      # Create zones from clusters
      clusters.each_with_index.map { |cl, idx| create_zone(idx, cl) }
    end

    def self.create_zone(idx, ents)
      bb = Geom::BoundingBox.new
      ents.each { |e| bb.add(e.bounds) }
      pad = 0.0  # padding = 0mm
      mn = Geom::Point3d.new(bb.min.x - pad, bb.min.y - pad, bb.min.z - pad)
      mx = Geom::Point3d.new(bb.max.x + pad, bb.max.y + pad, bb.max.z + pad)
      Zone.new(idx, [mn, mx], ents)
    end

    # Sort zones left-to-right, bottom-to-top and assign labels
    def self.sort_and_label_zones(zones, prefix = nil, start_num = 1)
      prefix = MH::FastRename.product_family if prefix.to_s.strip.empty? && MH::FastRename.respond_to?(:product_family)
      prefix = 'SP' if prefix.to_s.strip.empty?
      # Sort: primary by X (left to right), secondary by Y (bottom to top)
      sorted = zones.sort_by { |z| [z.center.x.round(0), z.center.y.round(0)] }
      sp_count = 0
      sorted.each_with_index do |z, i|
        z.id = i
        if z.zone_type == :sp
          sp_count += z.label_offset if z.label_offset
          z.label = if MH::FastRename.respond_to?(:format_product_code)
            MH::FastRename.format_product_code(start_num + sp_count, prefix)
          else
            "#{prefix}%02d" % (start_num + sp_count)
          end
          sp_count += 1
        end
      end
      
      moduls = sorted.select { |z| z.zone_type == :modul }
      moduls.group_by(&:parent_id).each do |pid, mods|
        parent = sorted.find { |z| z.id == pid }
        next unless parent
        mod_count = 1
        mods.each do |mz|
          mod_count += mz.label_offset if mz.label_offset
          mz.label = "#{parent.label}.#{mod_count}"
          mod_count += 1
        end
      end
      
      sorted
    end

  end
end
