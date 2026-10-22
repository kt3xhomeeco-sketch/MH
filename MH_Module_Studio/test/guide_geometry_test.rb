# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'
class ModuleStudioGuideGeometryTest < Minitest::Test
  S=MH::ModuleStudio
  def source
    translate=S::Frames::IDENTITY.dup;translate[12]=2
    {'parts'=>[{'key'=>'panel','bounds'=>[[0,0,0],[300,18,500]]}],
     'dc_graph'=>{'root_frame'=>S::Frames::IDENTITY,'nodes'=>[
      {'id'=>'carrier','parent_id'=>'','transform'=>translate,'part_key'=>nil},
      {'id'=>'child','parent_id'=>'carrier','transform'=>S::Frames::IDENTITY,'part_key'=>'panel','local_bounds'=>[[0,0,0],[10,1,20]]}]}}
  end
  def test_captured_guide_frame_resolves_nested_ancestry_without_mutating_the_program
    data=source;before=Marshal.dump(data)
    reference=S::GeometryMotion.guide_reference(data,'panel')
    assert_equal [2.0,0.0,0.0],S::Frames.point(reference['frame'],[0,0,0])
    assert_equal [[0,0,0],[300,18,500]],reference['bounds']
    assert_equal before,Marshal.dump(data)
    assert_nil S::GeometryMotion.guide_reference(data,'missing')
    assert_nil S::GeometryMotion.guide_reference(nil,'panel')
  end
  def test_missing_or_cyclic_ancestry_cannot_authorize_legacy_repair
    data=source;data['dc_graph']['nodes'][0]['parent_id']='child'
    assert_nil S::GeometryMotion.guide_reference(data,'panel')
    data=source;data['dc_graph']['nodes'][1]['parent_id']='missing'
    assert_nil S::GeometryMotion.guide_reference(data,'panel')
    data=source;data['dc_graph']['nodes'][1].delete('local_bounds')
    assert_nil S::GeometryMotion.guide_reference(data,'panel')
  end
  def test_legacy_edge_point_follows_original_mesh_to_new_bounds_without_clamping_offsets
    old=[[-298.5,-17.6,1],[-1.5,0,299]];current=[[-300,-17.6,0],[0,0,300]]
    matrix=S::GeometryMotion.matrix(old,current)
    point=S::Frames.point(matrix,[-1.5,-17.6,150].map { |v| v/25.4 }).map { |v| v*25.4 }
    assert_in_delta 0,point[0],0.000001;assert_in_delta(-17.6,point[1],0.000001);assert_in_delta 150,point[2],0.000001
    offset=S::Frames.point(matrix,[-1.5,-20,150].map { |v| v/25.4 }).map { |v| v*25.4 }
    assert_in_delta(-20,offset[1],0.000001,'Intentional offsets are not clamped to a board edge')
  end
end
