# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'
require_relative 'formula_fixtures'

class ModuleStudioImportTemplateTest < Minitest::Test
  S=MH::ModuleStudio
  def template
    S::ImportTemplate.defaults.merge('enabled'=>true)
  end
  def face(axis,side,coordinate)
    bounds=[[18,0,18],[582,580,782]]
    bounds.each { |point| point[axis]=coordinate }
    {'axis'=>axis,'side'=>side,'coordinate'=>coordinate,'bounds'=>bounds,'anchor'=>{'root'=>'host','axis'=>axis,'side'=>side}}
  end
  def inside_faces
    [face(0,1,18),face(0,0,582),face(1,0,580),face(2,1,18),face(2,0,782)]
  end
  def test_five_inside_faces_fit_paired_axes_and_keep_free_depth
    data=template;data['faces'].each { |slot| slot['gap']=2 }
    result=S::ImportTemplate.match(data,[[0,0,0],[500,300,700]],[[18,0,18],[582,580,782]],inside_faces,mode:'inside')
    assert_equal 5,result['matches'].length
    assert_equal [[20,278,20],[580,578,780]],result['bounds']
    assert(result['matches'].all? { |match| match['gap']==2 })
  end
  def test_one_or_two_contacts_do_not_require_the_other_slots_or_resize_unpaired_axis
    candidates=inside_faces.values_at(0,4)
    source=[[0,0,0],[400,300,600]]
    result=S::ImportTemplate.match(template,source,[[18,0,18],[582,580,782]],candidates,mode:'inside',origin:[30,50,40])
    assert_equal [[18,50,182],[418,350,782]],result['bounds']
    assert_equal 2,result['matches'].length
    result=S::ImportTemplate.match(template,source,[[18,0,18],[582,580,782]],candidates.first(1),mode:'inside')
    assert_equal 1,result['matches'].length
    assert_equal [400,300,600],S::Core.dimensions(result['bounds'])
    assert_nil S::ImportTemplate.match(template,source,[[18,0,18],[582,580,782]],[],mode:'inside')
  end
  def test_opposed_door_uses_outside_faces_and_inset_door_leaves_depth_free
    data=template.merge('role'=>'door')
    region=[[0,19.6,0],[600,600,800]]
    outside=[face(0,0,0),face(0,1,600),face(1,0,19.6),face(2,0,0),face(2,1,800)]
    result=S::ImportTemplate.match(data,[[0,0,0],[400,18.6,700]],region,outside,mode:'outside',mount:[1,0])
    assert_equal 5,result['matches'].length
    assert S::Core.bounds_close?([[0,0,0],[600,18.6,800]],result['bounds'],0.00001)
    assert_equal 1,result['matches'].find { |row| row['mount'] }['gap']
    inside=S::ImportTemplate.match(data,[[0,0,0],[400,18.6,700]],[[18,0,18],[582,580,782]],inside_faces,mode:'inside',origin:[0,0,0])
    assert_equal 4,inside['matches'].length
    assert_equal 0,inside['bounds'][0][1]
    assert_in_delta 18.6,S::Core.dimensions(inside['bounds'])[1],0.00001
  end
  def test_mm_gaps_in_scaled_host_frame_and_bad_templates
    data=template;data['faces'].first['gap']=4
    result=S::ImportTemplate.match(data,[[0,0,0],[100,100,100]],[[18,0,18],[582,580,782]],inside_faces.first(1),mode:'inside',scales:[2,1,1])
    assert_equal 20,result['bounds'][0][0]
    data['faces'].last['axis']=0
    assert_raises(S::Core::Error) { S::ImportTemplate.validate(data) }
  end
  def test_same_symbol_physical_thickness_sync_is_private_and_serializes_with_template
    snapshot=FormulaFixtures.snapshot
    engine=S::Core.learn_module([snapshot]);master=S::ThicknessSymbols.normalize(S::RuleSystem.build(snapshot,engine))
    values=S::Parametric.targets(master)
    common=S::ImportTemplate.thickness_values(master,values)
    assert_equal 18,common['t1']
    rows=S::Parametric.variables(master)
    rows.find { |row| row['symbol']=='T1' }['value']=17.6
    member=S::Parametric.edit_variables(master,rows)
    before=Marshal.dump([master,member])
    edited=S::ImportTemplate.synchronize(member,S::Parametric.targets(member),common)
    assert_equal 18,S::ImportTemplate.thickness_values(edited,S::Parametric.targets(edited))['t1']
    assert_equal before,Marshal.dump([master,member])
    renamed=S::Parametric.variables(member);renamed.find { |row| row['symbol']=='T1' }['symbol']='DoorT'
    own=S::Parametric.edit_variables(member,renamed)
    assert_nil S::ImportTemplate.synchronize(own,S::Parametric.targets(own),common)
    saved=S::ImportTemplate.edit(member,template.merge('role'=>'door'))
    restored=S::Core.rule!(JSON.parse(JSON.generate(saved)))
    assert S::ImportTemplate.enabled?(restored)
    assert_equal 'door',restored['import_template']['role']
    refute master.key?('import_template')
  end
end
