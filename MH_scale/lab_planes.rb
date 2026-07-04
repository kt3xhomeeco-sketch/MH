# encoding: UTF-8

module MH::Scale
  class PlaneStore
    attr_reader :planes

    def initialize
      @planes = []
      @next_id = 1
    end

    def add(axis, pos, side, kind, bb)
      plane = {
        id: @next_id,
        axis: axis,
        pos: BoxModel.clamp_pos(pos, bb, axis),
        side: side || :plus,
        kind: kind || :user,
        usable: BoxModel.usable_axis?(bb, axis)
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
      # KHONG tao them default o giua. Tranh bug: keo default sang cho moi roi scale
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

