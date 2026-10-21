# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'
class ModuleStudioContactDisplayTest < Minitest::Test
  S=MH::ModuleStudio
  def plane(x,width,height,side=1)
    {'normal'=>[side,0,0],'point'=>[x,width/2.0,height/2.0],'points'=>[[x,0,0],[x,width,0],[x,width,height],[x,0,height]]}
  end
  def test_volume_projects_the_smaller_face_without_enlarging_it_to_the_other_module
    shape=S::ContactDisplay.prism(plane(0,100,200),plane(80,20,30,-1))
    assert shape['volume'];assert_equal 600,shape['area']
    assert_equal [[0.0,0,0],[80,20,30]],S::Frames.box(shape['points'])
    assert_in_delta 80,Math.sqrt(S::AssemblyMath.dot(S::AssemblyMath.sub(*shape['ends']),S::AssemblyMath.sub(*shape['ends']))),0.00001
    zero=S::ContactDisplay.prism(plane(0,100,100),plane(0,20,30,-1));refute zero['volume']
  end
  def test_oblique_parallel_faces_keep_the_small_face_area_and_gap
    c=Math.cos(0.7);s=Math.sin(0.7);matrix=[c,s,0,0,-s,c,0,0,0,0,1,0,0,0,0,1]
    planes=[plane(0,100,200),plane(80,20,30,-1)].map do |p|
      p.merge('normal'=>S::Frames.point(matrix,p['normal']),'point'=>S::Frames.point(matrix,p['point']),'points'=>p['points'].map { |v| S::Frames.point(matrix,v) })
    end
    shape=S::ContactDisplay.prism(*planes);assert_in_delta 600,shape['area'],0.00001
    delta=S::AssemblyMath.sub(*shape['ends']);assert_in_delta 80,Math.sqrt(S::AssemblyMath.dot(delta,delta)),0.00001
  end
  def test_dimension_hit_wins_over_volume_and_zero_gap_has_no_box_hit
    item={'id'=>'one','rect'=>[40,40,60,60],'volume'=>true,'polygons'=>[[[0,0],[100,0],[100,100],[0,100]]]}
    assert_equal ['dimension','one'],S::ContactDisplay.hit([item],50,50)
    assert_equal ['settings','one'],S::ContactDisplay.hit([item],10,10)
    assert_nil S::ContactDisplay.hit([item],110,10)
    item['volume']=false;assert_nil S::ContactDisplay.hit([item],10,10)
    assert_equal ['dimension','one'],S::ContactDisplay.hit([item],50,50)
  end
end
