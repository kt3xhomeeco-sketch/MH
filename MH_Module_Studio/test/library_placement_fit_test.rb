# encoding: UTF-8
# Portable transform regression; the real definition build still requires SketchUp.
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../core'

module Geom
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x, y, z)
      @x = x; @y = y; @z = z
    end
    def to_a
      [x, y, z]
    end
  end

  class Bounds
    attr_reader :min, :max
    def initialize(minimum, maximum)
      @min = Point3d.new(*minimum)
      @max = Point3d.new(*maximum)
    end
  end

  class Transformation
    IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].freeze
    attr_reader :matrix
    def initialize(matrix = IDENTITY)
      @matrix = matrix
    end
    def *(other)
      self.class.new(MH::ModuleStudio::Frames.multiply(matrix, other.matrix))
    end
  end
end

require_relative '../library_placement'

class ModuleStudioLibraryPlacementFitTest < Minitest::Test
  S = MH::ModuleStudio
  Definition = Struct.new(:bounds)
  Root = Struct.new(:definition, :transformation)
  Target = [[18.0, 30.0, 40.0], [918.0, 530.0, 840.0]]

  def test_cavity_fit_uses_native_rule_locks_when_preview_omits_rule_and_host_is_scaled
    source=[[0.0,0.0,0.0],[600.0,17.6,500.0]]
    data={'snapshot'=>{'envelope'=>source,'parts'=>[{'key'=>'panel','thickness_axis'=>1}]}}
    frame=S::Frames::IDENTITY.dup;frame[5]=0.907
    placement={'mode'=>'cavity','bounds'=>[[18.0,0.0,18.0],[582.0,200.0,482.0]],'frame'=>frame}
    before=Marshal.dump(placement)
    root=Root.new(Definition.new(Geom::Bounds.new([-300.0/25.4,-17.6/25.4,0.0],[0.0,0.0,300.0/25.4])),nil)
    S::AssemblyParameters.stub(:data,[locked_rule(1),{}]) do
      fitted=S::LibraryPlacement.fitted_placement(root,data,placement)
      assert_in_delta 17.6/0.907,S::Core.dimensions(fitted['bounds'])[1],0.000001
      transform=S::LibraryPlacement.fit_built(root,fitted)
      measured=S::Frames.box(S::Frames.corners([root.definition.bounds.min.to_a,root.definition.bounds.max.to_a]).map do |point|
        S::Frames.point(transform.matrix,point).map { |value| value*25.4 }
      end)
      assert_in_delta 564.0,S::Core.dimensions(measured)[0],0.000001
      assert_in_delta 17.6,S::Core.dimensions(measured)[1],0.000001
      assert_in_delta 464.0,S::Core.dimensions(measured)[2],0.000001
    end
    assert_equal before,Marshal.dump(placement)
  end

  def test_free_fit_uses_built_definition_bounds_not_snapshot_envelope
    data = { 'snapshot' => { 'envelope' => [[0.0, 0.0, 0.0], [100.0, 100.0, 100.0]] } }
    placement = { 'mode' => 'free_fit', 'bounds' => Target, 'frame' => Geom::Transformation::IDENTITY.to_a }
    root = Root.new(Definition.new(Geom::Bounds.new([-2.0, 3.0, 4.0], [4.0, 6.0, 10.0])), nil)

    corners = S::Frames.corners([[-2.0, 3.0, 4.0], [4.0, 6.0, 10.0]])
    actual_fit = S::LibraryPlacement.fit_built(root, placement)
    measured = S::Frames.box(corners.map do |point|
      S::Frames.point(actual_fit.matrix, point).map { |value| value * 25.4 }
    end)
    Target.each_with_index do |point, bound_index|
      point.each_index { |axis| assert_in_delta point[axis], measured[bound_index][axis], 0.000001 }
    end

    snapshot_fit = S::LibraryPlacement.transform(data, placement)
    snapshot_measure = S::Frames.box(corners.map do |point|
      S::Frames.point(snapshot_fit.matrix, point).map { |value| value * 25.4 }
    end)
    refute S::Core.bounds_close?(snapshot_measure, Target, 0.02)
  end

  def locked_rule(axis)
    { 'constraints' => [{ 'type' => 'thickness', 'source' => 'geometry', 'enabled' => true, 'drive' => true,
                          'face' => { 'part' => 'panel', 'axis' => axis, 'side' => 0 },
                          'other' => { 'part' => 'shelf', 'axis' => axis, 'side' => 1 },
                          'parameter' => 'thickness_1', 'anchor' => 'low' }] }
  end

  def test_locked_non_min_axis_keeps_source_span_while_other_axes_fit_target
    source = [[0.0, 0.0, 0.0], [100.0, 300.0, 200.0]]
    target = [[37.0, 19.0, 53.0], [1060.0, 419.0, 80.0]]
    expected = [[37.0, 19.0, 53.0], [1060.0, 419.0, 253.0]]
    data = { 'snapshot' => { 'envelope' => source, 'parts' => [
      { 'key' => 'panel', 'bounds' => source, 'thickness_axis' => 0 }
    ] }, 'rule' => locked_rule(2) }
    locks = S::LibraryPlacement.locked_axes(data)
    fit_bounds = S::LibraryPlacement.free_fit_bounds(source, target, locked_axes: locks)

    assert_equal [2], locks
    assert_equal expected, fit_bounds
    assert_equal [1023.0, 400.0, 200.0], S::Core.dimensions(fit_bounds)

    root = Root.new(
      Definition.new(Geom::Bounds.new([0.0, 0.0, 0.0], [100.0 / 25.4, 300.0 / 25.4, 200.0 / 25.4])),
      nil
    )
    placement = { 'mode' => 'free_fit', 'bounds' => target, 'frame' => Geom::Transformation::IDENTITY.to_a }
    transform = S::LibraryPlacement.fit_built(root, placement, locked_axes: locks)
    measured = S::Frames.box(S::Frames.corners([[0.0, 0.0, 0.0], [100.0 / 25.4, 300.0 / 25.4, 200.0 / 25.4]]).map do |point|
      S::Frames.point(transform.matrix, point).map { |value| value * 25.4 }
    end)

    expected.each_with_index do |point, bound_index|
      point.each_index { |axis| assert_in_delta point[axis], measured[bound_index][axis], 0.000001 }
    end
  end

  def test_att_thickness_axis_is_used_when_all_visible_parts_agree
    parts = [
      { 'key' => 'panel', 'visible' => true, 'thickness_axis' => 2 },
      { 'key' => 'edge', 'visible' => true, 'thickness_axis' => 2 }
    ]
    data = { 'snapshot' => { 'parts' => parts }, 'rule' => { 'formula_engine' => {}, 'constraints' => [] } }

    assert_equal [2], S::LibraryPlacement.locked_axes(data)
  end

  def test_free_fit_keeps_panel_thickness_when_target_is_thinner
    source = [[0.0, 0.0, 0.0], [500.0, 18.6, 700.0]]
    target = [[37.0, 19.0, 53.0], [1060.0, 31.0, 923.0]]
    expected = [[37.0, 19.0, 53.0], [1060.0, 37.6, 923.0]]
    fit_bounds = S::LibraryPlacement.free_fit_bounds(source, target, locked_axes: [1])

    assert_equal expected, fit_bounds
    assert_equal [1023.0, 18.6, 870.0], S::Core.dimensions(fit_bounds)

    root = Root.new(
      Definition.new(Geom::Bounds.new([0.0, 0.0, 0.0], [500.0 / 25.4, 18.6 / 25.4, 700.0 / 25.4])),
      nil
    )
    placement = { 'mode' => 'free_fit', 'bounds' => target, 'frame' => Geom::Transformation::IDENTITY.to_a }
    transform = S::LibraryPlacement.fit_built(root, placement, locked_axes: [1])
    measured = S::Frames.box(S::Frames.corners([[0.0, 0.0, 0.0], [500.0 / 25.4, 18.6 / 25.4, 700.0 / 25.4]]).map do |point|
      S::Frames.point(transform.matrix, point).map { |value| value * 25.4 }
    end)
    expected.each_with_index do |point, bound_index|
      point.each_index { |axis| assert_in_delta point[axis], measured[bound_index][axis], 0.000001 }
    end
  end

  def test_free_fit_uses_target_thickness_when_it_can_fit
    source = [[0.0, 0.0, 0.0], [500.0, 18.6, 700.0]]
    target = [[0.0, 0.0, 0.0], [600.0, 20.0, 800.0]]

    assert_equal target, S::LibraryPlacement.free_fit_bounds(source, target, locked_axes: [])
  end

  def test_unlocked_or_ordinary_module_fits_every_target_axis
    source = [[0.0, 0.0, 0.0], [500.0, 18.6, 700.0]]
    target = [[37.0, 19.0, 53.0], [1060.0, 31.0, 923.0]]

    assert_equal [], S::LibraryPlacement.locked_axes({ 'snapshot' => { 'parts' => [] } })
    assert_equal target, S::LibraryPlacement.free_fit_bounds(source, target, locked_axes: [])
  end

  def test_mixed_axis_thickness_preserves_each_explicitly_locked_axis
    x = { 'key' => 'x', 'bounds' => [[0.0, 0.0, 0.0], [18.0, 500.0, 700.0]], 'thickness_axis' => 0 }
    y = { 'key' => 'y', 'bounds' => [[0.0, 0.0, 0.0], [500.0, 18.0, 700.0]], 'thickness_axis' => 1 }
    rule = { 'constraints' => [x, y].each_with_index.map do |part, index|
      { 'type' => 'thickness', 'enabled' => true, 'drive' => true,
        'face' => { 'part' => part['key'], 'axis' => part['thickness_axis'], 'side' => 0 },
        'other' => { 'part' => part['key'], 'axis' => part['thickness_axis'], 'side' => 1 },
        'parameter' => "thickness_#{index}" }
    end }

    data = { 'snapshot' => { 'parts' => [x, y] }, 'rule' => rule }
    locks = S::LibraryPlacement.locked_axes(data)

    assert_equal [0, 1], locks
    target = [[0.0, 0.0, 0.0], [10.0, 10.0, 50.0]]
    expected = [[0.0, 0.0, 0.0], [18.0, 18.0, 50.0]]
    assert_equal expected, S::LibraryPlacement.free_fit_bounds([[0.0, 0.0, 0.0], [18.0, 18.0, 60.0]], target, locked_axes: locks)
  end
end
