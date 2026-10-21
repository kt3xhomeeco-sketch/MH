# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioAssemblyMathTest < Minitest::Test
  MathCore = MH::ModuleStudio::AssemblyMath
  Error = MH::ModuleStudio::Core::Error

  def face(point, normal = [1,0,0])
    { 'point' => point, 'normal' => normal }
  end

  def test_offsets_keep_tangential_position_and_work_with_rotated_planes
    assert_equal [3.0,0.0,0.0], MathCore.offset(face([18,0,0]),face([18,70,80]),3)
    assert_equal [-5.0,0.0,0.0], MathCore.offset(face([18,0,0]),face([20,70,80]),-3)
    n = MathCore.unit([1,1,0])
    vector = MathCore.offset(face([0,0,0],n),face([5,5,100],n),0)
    assert_in_delta(-5,vector[0],1.0e-8)
    assert_in_delta(-5,vector[1],1.0e-8)
    assert_in_delta 0,vector[2],1.0e-8
    assert_raises(Error) { MathCore.offset(face([0,0,0]),face([0,0,0],[0,0,1]),0) }
  end

  def test_fit_tracks_actual_inner_faces_after_thickness_changes
    a = face([18.6,0,0]); c = face([581.4,0,0],[-1,0,0])
    result = MathCore.centered(a,c,[100,300],clearance:3)
    assert_in_delta 556.8,result['size'],1.0e-8
    assert_in_delta 100,result['delta'],1.0e-8
    result = MathCore.centered(face([25,0,0]),face([575,0,0]),[21.6,578.4],clearance:3)
    assert_in_delta 544,result['size'],1.0e-8
    assert_in_delta 0,result['delta'],1.0e-8
    assert_raises(Error) { MathCore.centered(a,c,[0,600]) }
    assert_raises(Error) { MathCore.centered(a,c,[100,300],clearance:300) }
  end

  def test_repeat_has_clear_gaps_instead_of_center_pitch_and_includes_source
    result = MathCore.repeat_layout(count:3,size:18,start:0,gap:100)
    assert_equal [0,118,236],result['positions']
    result = MathCore.repeat_layout(count:3,size:18,start:0,gap:0,interval:[0,800],ends:true)
    assert_in_delta 186.5,result['gap'],1.0e-8
    assert_equal [186.5,391.0,595.5],result['positions']
    result = MathCore.repeat_layout(count:3,size:18,start:0,gap:0,interval:[800,0],ends:false)
    assert_equal [0,391.0,782.0],result['positions']
    assert_equal [391.0],MathCore.repeat_layout(count:1,size:18,start:0,gap:0,interval:[0,800],ends:false)['positions']
    [0,1.5,101].each { |count| assert_raises(Error) { MathCore.repeat_layout(count:count,size:18,start:0,gap:0) } }
    assert_raises(Error) { MathCore.repeat_layout(count:3,size:300,start:0,gap:0,interval:[0,800]) }
    assert_raises(Error) { MathCore.repeat_layout(count:2,size:18,start:0,gap:-1) }
    assert_equal [0,0,-1],MathCore::DIRECTIONS['down']
    assert_equal [-1,0,0],MathCore::DIRECTIONS['left']
  end

  def test_motion_obeys_all_constraints_and_keeps_remaining_degrees_of_freedom
    assert_equal [10,20,30],MathCore.allowed_motion([10,20,30],[])
    assert_equal [10.0,20.0,0.0],MathCore.allowed_motion([10,20,30],[[0,0,1]])
    assert_equal [0.0,20.0,0.0],MathCore.allowed_motion([10,20,30],[[0,0,1],[1,0,0]])
    assert_equal [0.0,0.0,0.0],MathCore.allowed_motion([10,20,30],[[0,0,1],[1,0,0],[0,1,0]])
    result = MathCore.allowed_motion([10,0,20],[[1,1,0],[2,2,0]])
    assert_in_delta 5,result[0],1.0e-8
    assert_in_delta(-5,result[1],1.0e-8)
    assert_in_delta 20,result[2],1.0e-8
  end

  def test_surfaces_and_dependencies_distinguish_copied_assembly_scopes
    anchor = {'scope'=>'one','root'=>'42','part'=>'left','axis'=>0,'side'=>1,'path'=>['old']}
    assert MathCore.same_surface?(anchor,anchor.merge('path'=>['new']))
    refute MathCore.same_surface?(anchor,anchor.merge('scope'=>'two'))
    refute MathCore.same_surface?(anchor,anchor.merge('side'=>0))
    refute MathCore.same_surface?(nil,anchor)
    raw = anchor.reject { |key,_value| key=='part' }
    refute MathCore.same_surface?(raw,raw.merge('path'=>['other']))
    assert MathCore.same_surface?(raw.merge('panel'=>'stable'),raw.merge('panel'=>'stable','path'=>['new']))
    first = {'id'=>'one','a'=>{'scope'=>'one','root'=>'A'},'b'=>{'scope'=>'one','root'=>'B'}}
    second = {'id'=>'two','a'=>{'scope'=>'two','root'=>'B'},'b'=>{'scope'=>'two','root'=>'A'}}
    assert_equal %w[one two],(MathCore.ordered([first,second]).map { |row| row['id'] })
  end

  def test_contact_solution_changes_size_only_when_translation_is_insufficient
    rows = [{'normal'=>[1,0,0],'delta'=>20},{'normal'=>[-1,0,0],'delta'=>-20}]
    assert_equal({'move'=>[20.0,0.0,0.0],'sizes'=>[]},MathCore.contact_solution(rows))
    rows.last['delta'] = -120
    assert_raises(Error) { MathCore.contact_solution(rows) }
    result = MathCore.contact_solution(rows,[[0,-1]])
    assert_equal [20.0,0.0,0.0],result['move']
    assert_in_delta 100,result['sizes'].first,1.0e-9
    # Inset planes of a raw scaled group move by fractions of outer size.
    result = MathCore.contact_solution(rows,[[0.1,-0.9]])
    assert_in_delta 7.5,result['move'][0],1.0e-9
    assert_in_delta 125,result['sizes'].first,1.0e-9
    rows += [{'normal'=>[0,1,0],'delta'=>5},{'normal'=>[0,-1,0],'delta'=>45}]
    result = MathCore.contact_solution(rows,[[0,-1,0,0],[0,0,0,-1]])
    assert_equal [20.0,5.0,0.0],result['move']
    assert_equal [100.0,-50.0],result['sizes']
    assert_raises(Error) { MathCore.contact_solution([rows.first,rows.first.merge('delta'=>70)],[[0,0]]) }
  end

  def test_order_and_cycle_rejection_do_not_mutate_records
    records = [{ 'id'=>'second', 'a'=>{'root'=>'B'}, 'b'=>{'root'=>'C'} },
               { 'id'=>'first', 'a'=>{'root'=>'A'}, 'b'=>{'root'=>'B'} }]
    original = JSON.generate(records)
    assert_equal %w[first second],(MathCore.ordered(records).map { |row| row['id'] })
    assert_equal original,JSON.generate(records)
    assert_raises(Error) { MathCore.ordered(records + [{'a'=>{'root'=>'C'},'b'=>{'root'=>'A'}}]) }
    assert_raises(Error) { MathCore.ordered([{'a'=>{'root'=>'A'},'b'=>{'root'=>'A'}}]) }
  end

  def test_angle_alignment_uses_minimum_rotation_and_rejects_bad_angles
    assert_in_delta 0,MathCore.rotation([1,0,0],[0,1,0],90)['radians'],1.0e-8
    turn = MathCore.rotation([1,0,0],[0,1,0],0)
    assert_in_delta Math::PI/2,turn['radians'],1.0e-8
    assert_equal [0.0,0.0,-1.0],turn['axis']
    assert_in_delta Math::PI,MathCore.rotation([1,0,0],[-1,0,0],0)['radians'],1.0e-8
    assert_raises(Error) { MathCore.rotation([1,0,0],[1,0,0],181) }
  end
end
