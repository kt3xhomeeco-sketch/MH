# encoding: UTF-8

module MH
  module Panel
    TOL = MH::Geo::TOL unless const_defined?(:TOL)
    AREA_TOL = MH::Geo::AREA_TOL unless const_defined?(:AREA_TOL)

    if defined?(MH::Panel::NativeBridge) && !defined?(MH::Geo::NativeBridge)
      MH::Geo.const_set(:NativeBridge, MH::Panel::NativeBridge)
    end

    Offset = MH::Geo::Offset unless const_defined?(:Offset)
    Face = MH::Geo::Face unless const_defined?(:Face)
    Edge = MH::Geo::Edge unless const_defined?(:Edge)
    Solid = MH::Geo::Solid unless const_defined?(:Solid)
  end
end
