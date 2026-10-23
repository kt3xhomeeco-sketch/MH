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
    region=S::PlacementMath.cavity(@envelope,@panels,[300,480,400])
    assert_equal [[18,0,18],[582,482,782]],region
    assert S::PlacementMath.open_cavity?(@envelope,region)
    assert_equal frozen_panels,@panels
    assert_equal [[0,0,0],[600,500,800]],@envelope
  end

  def test_ray_region_uses_nearest_axis_hits_and_keeps_open_side_at_envelope
    seed=[300,250,400]
    hits={
      [0,0]=>[18,250,400],[0,1]=>[582,250,400],
      [1,1]=>[300,482,400],
      [2,0]=>[300,250,18],[2,1]=>[300,250,782]
    }
    assert_equal [[18,0,18],[582,482,782]],S::PlacementMath.ray_region(@envelope,seed,hits)
    assert_nil S::PlacementMath.ray_region(@envelope,seed,{[0,0]=>[18,250,400]})
    assert_nil S::PlacementMath.ray_region(@envelope,[300,-2,400],hits)
  end

  def test_closed_box_void_is_not_an_accessible_fit_region
    closed_panels=@panels+[[[18,0,18],[582,18,782]]]
    region=S::PlacementMath.cavity(@envelope,closed_panels,[300,250,400],minimum_hits:1)
    assert_equal [[18,18,18],[582,482,782]],region
    refute S::PlacementMath.open_cavity?(@envelope,region)
    assert S::PlacementMath.open_cavity?(@envelope,[[18,0,18],[582,482,782]])
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

  def test_face_fit_uses_bounded_plane_and_preserves_source_depth
    region=S::PlacementMath.face_fit_region(
      [[10,50,20],[110,50,20],[110,50,220],[10,50,220]],18.6,toward:[0,0,0]
    )
    assert_equal [[0.0,0.0,0.0],[100.0,18.6,200.0]],region['bounds']
    assert_in_delta 50.0,region['origin'][1],0.000001
    x_axis,y_axis,z_axis=region['axes']
    cross=[x_axis[1]*y_axis[2]-x_axis[2]*y_axis[1],x_axis[2]*y_axis[0]-x_axis[0]*y_axis[2],x_axis[0]*y_axis[1]-x_axis[1]*y_axis[0]]
    cross.zip(z_axis).each { |actual,expected| assert_in_delta expected,actual,0.000001 }

    source=[[-20,-9.3,-10],[580,9.3,390]]
    transform=S::PlacementMath.fit(source,region['bounds'])
    assert_in_delta 1.0,transform[5],0.000001
  end

  def test_face_fit_handles_horizontal_plane_and_rejects_degenerate_face
    region=S::PlacementMath.face_fit_region(
      [[0,0,50],[120,0,50],[120,60,50],[0,60,50]],12.0,toward:[0,0,80]
    )
    assert_equal [120.0,12.0,60.0],S::Core.dimensions(region['bounds'])
    assert_raises(S::Core::Error) do
      S::PlacementMath.face_fit_region([[0,0,0],[10,0,0],[20,0,0]],12.0)
    end
    assert_raises(S::Core::Error) do
      S::PlacementMath.face_fit_region([[0,0,0],[10,0,0],[10,10,0]],0)
    end
  end

  def test_exploded_panel_cluster_returns_cabinet_envelope_and_excludes_far_parts
    board=[[0,0,0],[1294.8,400,17.6]]
    side=[[0,0,17.6],[18,400,717.6]]
    back=[[0,0,17.6],[1294.8,18,717.6]]
    top=[[0,382,17.6],[1294.8,400,717.6]]
    far=[[2000,0,0],[2294.8,400,17.6]]
    result=S::PlacementMath.exploded_envelope([board,side,back,top,far],board)
    assert_equal [[0.0,0.0,0.0],[1294.8,400.0,717.6]],result
    assert_equal [1294.8,400.0,717.6],S::Core.dimensions(result)
  end

  def test_exploded_panel_cluster_does_not_aggregate_singletons_or_distant_parts
    board=[[0,0,0],[1294.8,400,17.6]]
    first=[[0,0,17.6],[18,400,717.6]]
    second=[[1276.8,0,17.6],[1294.8,400,717.6]]
    assert_nil S::PlacementMath.exploded_envelope([board],board)
    assert_nil S::PlacementMath.exploded_envelope([board,first],board)
    result=S::PlacementMath.exploded_envelope(
      [board,first,second,[[2000,0,0],[2018,400,700]]],board
    )
    assert_equal [[0.0,0.0,0.0],[1294.8,400.0,717.6]],result
  end
end
