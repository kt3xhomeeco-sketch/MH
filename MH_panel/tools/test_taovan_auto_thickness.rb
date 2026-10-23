# encoding: UTF-8
# Portable host-geometry tests for TaoVan auto-thickness. Run: ruby tools/test_taovan_auto_thickness.rb
require 'minitest/autorun'

class Numeric
  def mm
    to_f
  end
end

module Sketchup
  class Face; end
end

module Geom
  class Vector3d
    attr_reader :x, :y, :z

    def initialize(x, y, z)
      @x, @y, @z = x.to_f, y.to_f, z.to_f
    end

    def normalize!
      length = Math.sqrt((@x * @x) + (@y * @y) + (@z * @z))
      raise 'zero vector' if length <= 0
      @x /= length; @y /= length; @z /= length
      self
    end

    def dot(other)
      (@x * other.x) + (@y * other.y) + (@z * other.z)
    end
  end

  def self.fit_plane_to_points(points)
    p0, p1, p2 = points
    u = [p1.x - p0.x, p1.y - p0.y, p1.z - p0.z]
    v = [p2.x - p0.x, p2.y - p0.y, p2.z - p0.z]
    n = [(u[1] * v[2]) - (u[2] * v[1]),
         (u[2] * v[0]) - (u[0] * v[2]),
         (u[0] * v[1]) - (u[1] * v[0])]
    length = Math.sqrt(n.sum { |value| value * value })
    return nil if length <= 0
    n.map! { |value| value / length }
    [n[0], n[1], n[2], -((n[0] * p0.x) + (n[1] * p0.y) + (n[2] * p0.z))]
  end
end

module MH
  module Panel
    module Preset
      def self.included(base); base.extend(ClassMethods); end
      module ClassMethods
        def settings_section(*); end
      end
    end

    module Board
      class << self
        attr_accessor :thickness, :calls
      end
      self.calls = 0
      def self.calc_thickness(_container)
        self.calls += 1
        thickness
      end
    end
  end
end

require_relative '../src/tools/taovan'

class FakePoint
  attr_reader :x, :y, :z
  def initialize(x, y, z); @x, @y, @z = x.to_f, y.to_f, z.to_f; end
  def transform(transform); transform.apply(self); end
  def -(other); FakeVector.new(@x - other.x, @y - other.y, @z - other.z); end
end

class FakeVector
  attr_reader :x, :y, :z
  def initialize(x, y, z); @x, @y, @z = x, y, z; end
  def dot(other); (@x * other.x) + (@y * other.y) + (@z * other.z); end
end

class FakeTransform
  attr_reader :m, :t
  def initialize(m, t = [0.0, 0.0, 0.0])
    @m, @t = m, t
  end

  def self.identity
    new([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])
  end

  def self.diagonal(x, y, z)
    new([[x.to_f, 0.0, 0.0], [0.0, y.to_f, 0.0], [0.0, 0.0, z.to_f]])
  end

  def self.rotation_x(degrees)
    angle = degrees * Math::PI / 180.0
    c, s = Math.cos(angle), Math.sin(angle)
    new([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]])
  end

  def *(other)
    matrix = Array.new(3) do |i|
      Array.new(3) { |j| (0..2).sum { |k| @m[i][k] * other.m[k][j] } }
    end
    translation = Array.new(3) do |i|
      @t[i] + (0..2).sum { |k| @m[i][k] * other.t[k] }
    end
    self.class.new(matrix, translation)
  end

  def apply(point)
    FakePoint.new(
      (@m[0][0] * point.x) + (@m[0][1] * point.y) + (@m[0][2] * point.z) + @t[0],
      (@m[1][0] * point.x) + (@m[1][1] * point.y) + (@m[1][2] * point.z) + @t[1],
      (@m[2][0] * point.x) + (@m[2][1] * point.y) + (@m[2][2] * point.z) + @t[2]
    )
  end
end

FakeVertex = Struct.new(:position)
FakeLoop = Struct.new(:vertices)
FakeBounds = Struct.new(:center)
FakeDefinition = Struct.new(:entities)
FakeEntities = Struct.new(:items) do
  def grep(klass); items.grep(klass); end
end
FakeContainer = Struct.new(:definition, :transformation)

class FakeFace < Sketchup::Face
  attr_reader :area, :outer_loop, :bounds
  def initialize(width, depth, z, bounds_center: nil)
    points = [
      FakePoint.new(0, 0, z), FakePoint.new(width, 0, z),
      FakePoint.new(width, depth, z), FakePoint.new(0, depth, z)
    ]
    @area = width * depth
    @outer_loop = FakeLoop.new(points.map { |point| FakeVertex.new(point) })
    @bounds = FakeBounds.new(bounds_center || FakePoint.new(width / 2.0, depth / 2.0, z))
  end
end

class TaoVanAutoThicknessTest < Minitest::Test
  def setup
    MH::Panel::Board.calls = 0
    MH::Panel::Board.thickness = nil
  end

  def container(local_thickness, transform = FakeTransform.identity)
    first = FakeFace.new(600.0, 400.0, 0.0)
    second = FakeFace.new(600.0, 400.0, local_thickness)
    FakeContainer.new(FakeDefinition.new(FakeEntities.new([first, second])), transform)
  end

  def tool(auto: true, manual: 17.6, tr: nil)
    instance = MH::Panel::TaoVan.allocate
    instance.instance_variable_set(:@do_day_tu_dong, auto)
    instance.instance_variable_set(:@do_day, manual)
    instance.instance_variable_set(:@do_day_khong_gian, manual)
    instance.instance_variable_set(:@tr, tr)
    instance
  end

  def sampled(local_thickness, transform)
    MH::Panel::Board.thickness = local_thickness
    parent = container(local_thickness, transform)
    tool(tr: transform).send(:auto_thickness_from_source, parent, transform)
  end

  def test_full_ancestor_transform_uses_local_definition_length_in_world_frame
    actual = sampled(17.6 / 1.8, FakeTransform.diagonal(1.0, 1.0, 1.8))
    assert_in_delta 17.6, actual, 0.0001
  end

  def test_own_scale_uses_full_picked_transform
    actual = sampled(17.6 / 1.8, FakeTransform.diagonal(1.8, 1.8, 1.8))
    assert_in_delta 17.6, actual, 0.0001
  end

  def test_rotated_mirrored_nonuniform_ancestor
    transform = FakeTransform.rotation_x(25.0) * FakeTransform.diagonal(-0.7, 1.0, 1.8)
    actual = sampled(17.6 / 1.8, transform)
    assert_in_delta 17.6, actual, 0.0001
  end

  def test_off_plane_bbox_center_does_not_affect_thickness
    local_thickness = 17.6 / 1.8
    transform = FakeTransform.diagonal(1.0, 1.0, 1.8)
    first = FakeFace.new(600.0, 400.0, 0.0,
                        bounds_center: FakePoint.new(300.0, 200.0, 500.0))
    second = FakeFace.new(600.0, 400.0, local_thickness,
                         bounds_center: FakePoint.new(300.0, 200.0, -500.0 + local_thickness))
    parent = FakeContainer.new(FakeDefinition.new(FakeEntities.new([first, second])), transform)
    MH::Panel::Board.thickness = local_thickness
    actual = tool(tr: transform).send(:auto_thickness_from_source, parent, transform)
    assert_in_delta 17.6, actual, 0.0001
  end

  def test_manual_mode_does_not_sample
    MH::Panel::Board.thickness = 99.0
    instance = tool(auto: false, manual: 9.0, tr: FakeTransform.identity)
    instance.send(:cap_nhat_do_day, container(17.6))
    assert_in_delta 9.0, instance.instance_variable_get(:@do_day_khong_gian), 1e-9
    assert_equal 0, MH::Panel::Board.calls
  end

  def test_invalid_thickness_falls_back_to_manual
    MH::Panel::Board.thickness = nil
    instance = tool(auto: true, manual: 12.0, tr: FakeTransform.identity)
    instance.send(:cap_nhat_do_day, container(17.6))
    assert_in_delta 12.0, instance.instance_variable_get(:@do_day_khong_gian), 1e-9
  end

  def test_missing_picked_transform_falls_back_to_parent_transformation
    MH::Panel::Board.thickness = 17.6 / 1.8
    parent = container(17.6 / 1.8, FakeTransform.diagonal(1.8, 1.8, 1.8))
    instance = tool(auto: true, manual: 5.0, tr: nil)
    instance.send(:cap_nhat_do_day, parent)
    assert_in_delta 17.6, instance.instance_variable_get(:@do_day_khong_gian), 0.0001
  end
end
