# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'
class ModuleStudioDoorReplaceTest < Minitest::Test
  S=MH::ModuleStudio
  def data(axis=1,side=1)
    bounds=[[5,7,9],[405,25.6,709]]
    {'snapshot'=>{'envelope'=>bounds},'import_template'=>S::ImportTemplate.defaults.merge('role'=>'door','door_face'=>"#{axis}:#{side}")}
  end
  def placement
    {'mode'=>'replace','frame'=>[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],'bounds'=>[[10,20,30],[610,520,830]]}
  end
  def test_door_keeps_actual_source_thickness_and_target_front_plane_without_mutating_inputs
    source=data;target=placement;before=Marshal.dump([source,target])
    result=S::ImportTemplate.replace_bounds(source,target)
    assert S::Core.bounds_close?([[10,20,30],[610,38.6,830]],result['bounds'],0.00001)
    assert_equal before,Marshal.dump([source,target])
    refute source['import_template']['enabled'],'Door role survives disabled contact templates'
  end
  def test_scaled_mirrored_target_and_reverse_mount_keep_the_correct_front_datum
    target=placement.merge('frame'=>[-1.3,0,0,0,0,2,0,0,0,0,0.8,0,10,20,30,1])
    result=S::ImportTemplate.replace_bounds(data,target)
    assert_in_delta 9.3,S::Core.dimensions(result['bounds'])[1],0.000001
    assert_equal [10,20,30],result['bounds'][0]
    result=S::ImportTemplate.replace_bounds(data(1,0),target)
    assert_equal target['bounds'][1],result['bounds'][1]
    assert_in_delta 510.7,result['bounds'][0][1],0.000001
  end
  def test_thickness_axis_is_explicit_and_preserves_molded_source_span_instead_of_only_T1
    source=data(2,1);source['snapshot']['envelope']=[[0,0,0],[400,700,42]];source['door_thickness']=18.6
    result=S::ImportTemplate.replace_bounds(source,placement)
    assert_equal [[10,20,30],[610,520,72]],result['bounds']
    source=data(0,0);source['snapshot']['envelope']=[[0,0,0],[20,400,700]]
    assert_equal [[590,20,30],[610,520,830]],S::ImportTemplate.replace_bounds(source,placement)['bounds']
  end
  def test_ordinary_samples_and_nonreplace_fit_retain_existing_bounds
    target=placement
    assert_same target,S::ImportTemplate.replace_bounds({'snapshot'=>data['snapshot']},target)
    source=data;source['import_template']['role']='module'
    assert_same target,S::ImportTemplate.replace_bounds(source,target)
    %w[cavity template].each do |mode|
      current=target.merge('mode'=>mode)
      assert_same current,S::ImportTemplate.replace_bounds(data,current)
    end
  end
end
