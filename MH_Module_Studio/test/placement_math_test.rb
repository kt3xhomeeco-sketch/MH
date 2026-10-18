# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioPlacementMathTest < Minitest::Test
  S = MH::ModuleStudio

  def setup
    @envelope = [[0,0,0],[600,500,800]]
    @panels = [
      [[0,0,0],[18,500,800]], [[582,0,0],[600,500,800]],
      [[18,0,0],[582,500,18]], [[18,0,782],[582,500,800]],
      [[18,482,18],[582,490,782]]
    ]
  end

  def test_open_front_is_capped_by_current_host_envelope
    frozen_panels = Marshal.load(Marshal.dump(@panels))
    assert_equal [[18,0,18],[582,482,782]], S::PlacementMath.cavity(@envelope,@panels,[300,480,400])
    assert_equal frozen_panels,@panels
    assert_equal [[0,0,0],[600,500,800]],@envelope
  end

  def test_shelf_splits_compartments
    @panels << [[18,0,390],[582,482,408]]
    assert_equal [[18,0,408],[582,482,782]], S::PlacementMath.cavity(@envelope,@panels,[300,480,600])
    assert_equal [[18,0,18],[582,482,390]], S::PlacementMath.cavity(@envelope,@panels,[300,480,200])
    assert_nil S::PlacementMath.cavity(@envelope,@panels,[300,300,400])
  end

  def test_partial_brace_cannot_intersect_import_even_if_seed_rays_miss_it
    @panels << [[18,0,712],[582,70,782]]
    result = S::PlacementMath.cavity(@envelope,@panels,[300,480,400])
    assert_equal [[18,0,18],[582,482,712]], result
    refute(@panels.any? { |panel| S::PlacementMath.overlap?(result,panel) })
  end

  def test_outside_occupied_and_unbounded_areas_are_not_cavities
    [[300,-2,400],[600,300,400],[10,300,400],[300,486,400]].each do |point|
      assert_nil S::PlacementMath.cavity(@envelope,@panels,point)
    end
    assert_nil S::PlacementMath.cavity(@envelope,[@panels.last],[300,480,400])
  end

  def test_fit_accounts_for_nonzero_source_and_target_origins
    source = [[-30,20,10],[570,520,810]]
    target = [[18,0,18],[582,482,782]]
    matrix = S::PlacementMath.fit(source,target)
    transformed = S::Frames.corners(source).map do |point|
      3.times.map { |axis| point[axis]*matrix[axis*5]+matrix[12+axis]*25.4 }
    end
    S::Frames.box(transformed).flatten.zip(target.flatten).each { |a,b| assert_in_delta b,a,0.000001 }
    [[[0,0,0],[0,5,5]],[[0,0,0],[Float::INFINITY,5,5]],[[0,0,0],[-1,5,5]]].each do |bad|
      assert_raises(S::Core::Error) { S::PlacementMath.fit(source,bad) }
    end
    assert_raises(S::Core::Error) { S::PlacementMath.fit([[0,0,0],[0,5,5]],target) }
  end
end
