# encoding: UTF-8

module MH::Stretch
  class PlaneStore
    attr_reader :planes

    def initialize
      @planes = []
      @next_id = 1
    end

    def add(axis, pos, side, kind, bb, hidden: false)
      plane = {
        id: @next_id,
        axis: axis,
        pos: BoxModel.clamp_pos(pos, bb, axis),
        side: side || :plus,
        kind: kind || :user,
        usable: BoxModel.usable_axis?(bb, axis),
        hidden: hidden
      }
      @next_id += 1
      @planes << plane
      plane
    end

    def delete(id)
      return nil unless id

      idx = @planes.index { |plane| plane[:id] == id }
      return nil unless idx

      @planes.delete_at(idx)
    end

    def by_id(id)
      @planes.find { |plane| plane[:id] == id }
    end

    def first_for_axis(axis)
      @planes.find { |plane| plane[:axis] == axis }
    end

    def ensure_axis_default(bb, axis, side = :plus)
      # Da co plane tren truc nay (ke ca default da bi keo thanh :user) -> dung lai,
      # KHONG tao them default o giua. Tranh bug: keo default sang cho moi roi edit
      # lai sinh ra mot mat cat chinh giua.
      existing = @planes.find { |plane| plane[:axis] == axis && plane[:kind] == :default } ||
                 @planes.find { |plane| plane[:axis] == axis }
      existing || add(axis, midpoint(bb, axis), side, :default, bb)
    end

    def reclamp!(bb)
      @planes.each do |plane|
        plane[:usable] = BoxModel.usable_axis?(bb, plane[:axis])
        plane[:pos] = BoxModel.clamp_pos(plane[:pos], bb, plane[:axis]) if plane[:usable]
      end
    end

    def recenter_defaults!(bb)
      @planes.each do |plane|
        next unless plane[:kind] == :default

        plane[:pos] = midpoint(bb, plane[:axis])
      end
    end

    def sync_hidden_defaults!(bb, axis, side, source_bounds)
      return [] unless axis

      @planes.delete_if { |plane| plane[:kind] == :hidden_default && plane[:axis] != axis }
      positions = source_bounds.to_a.map { |bounds| midpoint(bounds, axis) }
      hidden = @planes.select { |plane| plane[:kind] == :hidden_default && plane[:axis] == axis }

      positions.each_with_index do |pos, index|
        plane = hidden[index]
        if plane
          plane[:pos] = BoxModel.clamp_pos(pos, bb, axis)
          plane[:side] = side || :plus
          plane[:usable] = BoxModel.usable_axis?(bb, axis)
          plane[:hidden] = true
        else
          hidden[index] = add(axis, pos, side, :hidden_default, bb, hidden: true)
        end
      end

      extra = hidden.drop(positions.length)
      @planes.delete_if { |plane| extra.include?(plane) } if extra && !extra.empty?
      hidden.first(positions.length)
    end

    def clear_hidden_defaults!
      @planes.delete_if { |plane| plane[:kind] == :hidden_default }
    end

    def clear_defaults!
      @planes.delete_if { |plane| plane[:kind] == :default }
    end

    def clear_user!
      @planes.delete_if { |plane| plane[:kind] == :user }
    end

    def retain_axis!(axis)
      @planes.delete_if { |plane| plane[:axis] != axis }
    end

    private

    def midpoint(bb, axis)
      (BoxModel.axis_min(bb, axis) + BoxModel.axis_max(bb, axis)) / 2.0
    end
  end
end



