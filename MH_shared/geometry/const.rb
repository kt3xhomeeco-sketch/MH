# encoding: UTF-8

require 'sketchup'

module MH
  module Geo
    TOL = 0.001 unless const_defined?(:TOL)
    AREA_TOL = 0.01 unless const_defined?(:AREA_TOL)
    EPS = 1e-10 unless const_defined?(:EPS)
  end
end
