# encoding: UTF-8

module SmartScaleLab
  class State
    attr_accessor :active, :hover

    def initialize
      @active = empty_ref
      @hover = empty_ref
    end

    def set_hover(hit)
      @hover = normalize_ref(hit)
    end

    def set_active(ref)
      @active = normalize_ref(ref)
    end

    def active_plane_id
      [:plane, :plane_stretch].include?(@active[:kind]) ? @active[:id] : nil
    end

    private

    def empty_ref
      { kind: nil, id: nil, axis: nil, side: nil }
    end

    def normalize_ref(ref)
      return empty_ref unless ref

      empty_ref.merge(ref)
    end

  end
end
