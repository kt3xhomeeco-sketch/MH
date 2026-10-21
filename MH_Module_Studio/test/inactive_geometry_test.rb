# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioInactiveGeometryTest < Minitest::Test
  S=MH::ModuleStudio

  def test_inactive_alternatives_follow_only_the_proved_output_axis
    current={'active'=>{'bounds'=>[[0,-21,0],[600,0,700]]},'hidden'=>{'bounds'=>[[0,-21,0],[600,0,700]]}}
    boxes={'active'=>[[0,-18,0],[600,0,700]],'hidden'=>[[0,-21,0],[600,0,700]]}
    S::InactiveGeometry.align!(boxes,current,{'active'=>true,'hidden'=>false},{'leny'=>18})
    assert_equal [[0,-18,0],[600,0,700]],boxes['hidden']
    S::InactiveGeometry.align!(boxes,boxes.transform_values { |box| {'bounds'=>box} },{'active'=>true,'hidden'=>false},{'leny'=>18})
    assert_equal [[0,-18,0],[600,0,700]],boxes['hidden']
    boxes['hidden']=[[0,-25,0],[650,0,750]]
    before=S::Core.copy_data(boxes)
    S::InactiveGeometry.align!(boxes,current,{'active'=>true,'hidden'=>false},{})
    assert_equal before,boxes
    S::InactiveGeometry.align!(boxes,current,{'active'=>true,'hidden'=>false},{'leny'=>17})
    assert_equal before,boxes
  end

  def test_actual_drawer_can_scale_repeatedly_while_root_length_follows_custom_t
    data=JSON.parse(File.read(File.join(__dir__,'fixtures/drawer-front-custom.json'),encoding:'UTF-8'))
    rule=S::StudioCalculation.build_system([data]);values=S::Parametric.targets(rule)
    current=data
    [[1.03,1.03,1.03],[0.8,1.4,1.2],[1.1,0.6,0.9]].each do |factors|
      scaled=S::ScalePlan.scaled_snapshot(current,factors)
      plan=S::ScalePlan.plan(rule,scaled,values)
      assert_in_delta values.fetch('aaq78h_g67'),S::Core.dimensions(plan['envelope'])[1],0.001
      current=current.merge('parts'=>plan['parts'],'envelope'=>plan['envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
      assert_equal 0,S::Core.plan(rule,current,{})['changed_count']
    end
  end

  def test_mirrored_parent_edge_anchor_follows_repeated_native_scale
    data=JSON.parse(File.read(File.join(__dir__,'fixtures/mirrored-parent-edge.json'),encoding:'UTF-8'))
    rule=S::StudioCalculation.build_system([data]);values=S::Parametric.targets(rule)
    [[1.03,1.03,1.03],[0.8,1.2,0.9]].each do |factors|
      scaled=S::ScalePlan.scaled_snapshot(data,factors)
      plan=S::ScalePlan.plan(rule,scaled,values)
      [0,2].each { |axis| assert_in_delta S::Core.dimensions(scaled['envelope'])[axis],S::Core.dimensions(plan['envelope'])[axis],0.001 }
      assert_in_delta 17.6,S::Core.dimensions(plan['envelope'])[1],0.001
      data=data.merge('parts'=>plan['parts'],'envelope'=>plan['envelope'],'parameter_values'=>plan['target'],'formula_envelope'=>plan['formula_envelope'],'dc_inputs'=>{})
    end
  end

  def test_rebased_layered_door_keeps_hidden_mesh_inside_its_derived_thickness
    data=JSON.parse(File.read(File.join(__dir__,'fixtures/layered-hidden-door.json'),encoding:'UTF-8'))
    rule=S::StudioCalculation.build_system([data])
    plan=S::Core.plan(rule,data,S::Parametric.targets(rule))
    assert_in_delta 18,S::Core.dimensions(plan['envelope'])[1],0.001
    assert(plan['parts'].any? { |part| !part['box_verified'] && part['linear_mesh_verified'] })
  end
end
