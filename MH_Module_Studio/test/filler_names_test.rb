# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioFillerNamesTest < Minitest::Test
  S = MH::ModuleStudio

  def data
    JSON.parse(File.read(File.join(__dir__,'fixtures/filler-left-owned.json'),encoding:'UTF-8'))
  end

  def test_reported_right_dc_keeps_custom_five_cm_backing_during_scale_and_thickness_edits
    snapshot=JSON.parse(File.read(File.join(__dir__,'fixtures/filler-right-dc.json'),encoding:'UTF-8'))
    assert_equal '5',snapshot['dc_inputs']['xuong']
    rule=S::StudioCalculation.build_system([snapshot])
    [[2,1,1],[1,2,1]].each do |factors|
      current=S::ScalePlan.scaled_snapshot(snapshot,factors)
      plan=S::ScalePlan.plan(rule,current,S::Parametric.targets(rule))
      [18.6,200,20,18.6].each do |t|
        current=current.merge('parts'=>plan['parts'],'envelope'=>plan['envelope'],'formula_envelope'=>plan['formula_envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
        plan=S::Core.plan(rule,current,{'dodaytam'=>t})
        parts=plan['parts'].to_h { |p| [p['name'],p] }
        assert_in_delta 50,S::Core.dimensions(parts['SP14_Xương Nẹp']['bounds'])[1],0.000001
        assert_in_delta t,S::Core.dimensions(parts['SP14_Xương Nẹp']['bounds'])[0],0.000001
        assert_in_delta 50*factors[0],S::Core.dimensions(parts['SP14_Nẹp Bù']['bounds'])[0],0.000001
      end
      loaded=S::Core.rule!(JSON.parse(JSON.generate(rule)))
      assert_equal rule.dig('formula_engine','attribute_program','dc_inputs','xuong'),loaded.dig('formula_engine','attribute_program','dc_inputs','xuong')
    end
  end

  def test_fixed_fifty_mm_span_remains_fixed_while_true_thickness_changes_the_envelope
    d=data; rule=d['rule']; current=d['snapshot']; before=JSON.generate(d)
    [18.6,20,30,80,200,18.6,80,17.6].each do |thickness|
      plan=S::Core.plan(rule,current,'dodaytam'=>thickness)
      parts=plan['parts'].to_h { |part| [part['name'],part] }
      assert_in_delta thickness,S::Core.dimensions(parts['SP14_Nẹp Bù']['bounds'])[1],0.000001
      assert_in_delta thickness,S::Core.dimensions(parts['SP14_Xương Nẹp']['bounds'])[0],0.000001
      assert_in_delta 50,S::Core.dimensions(parts['SP14_Xương Nẹp']['bounds'])[1],0.000001
      assert_in_delta thickness+50,S::Core.dimensions(plan['envelope'])[1],0.000001
      assert_in_delta [50,thickness].max,S::Core.dimensions(plan['envelope'])[0],0.000001
      assert_in_delta 50,S::Core.dimensions(parts['SP14_Nẹp Bù']['bounds'])[0],0.000001
      current=current.merge('parts'=>plan['parts'],'envelope'=>plan['envelope'],'formula_envelope'=>plan['formula_envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
      assert_equal 0,S::Core.plan(rule,current,{})['changed_count']
    end
    assert_equal before,JSON.generate(d)
    assert_nil rule['part_formulas']
  end

  def test_names_preserve_canonical_att_and_saved_current_values
    d=data; original=JSON.generate(d['rule']); key=d['snapshot']['parts'].last['key']
    rule=S::Parametric.rename_display(d['rule'],'Nẹp tủ A')
    rule=S::Parametric.rename_display(rule,'Xương trái',part_key:key)
    assert_equal d['rule']['formula_engine'],rule['formula_engine']
    assert_equal 'Nẹp tủ A',rule['module_name']
    assert_equal 'Xương trái',S::Parametric.sheet(rule,d['snapshot'])['parts'].find { |part| part['key']==key }['name']
    exported=S::Parametric.with_values(rule,'dodaytam'=>30)
    assert_equal 30,S::Parametric.targets(exported)['dodaytam']
    assert_equal original,JSON.generate(d['rule'])
    assert_equal 'Nẹp_tủ A.skp',S::Parametric.filename('Nẹp:tủ A')
    ['',"A\nB",'x'*121].each { |name| assert_raises(S::Core::Error) { S::Parametric.rename_display(rule,name) } }
    %w[CON NUL.skp COM1].each { |name| assert_raises(S::Core::Error) { S::Parametric.filename(name) } }
  end

  def test_exposed_root_width_is_not_silently_replaced_and_scale_uses_explicit_target
    d=data; rule=d['rule']; source=d['snapshot']
    plan=S::Core.plan(rule,source,'dodaytam'=>80)
    current=source.merge('parts'=>plan['parts'],'envelope'=>plan['envelope'],'formula_envelope'=>plan['formula_envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
    scaled=S::ScalePlan.scaled_snapshot(current,[2,1,1])
    resized=S::ScalePlan.plan(rule,scaled,plan['target'])
    assert_in_delta 160,S::Core.dimensions(resized['envelope'])[0],0.000001
    assert_in_delta 160,S::Core.dimensions(resized['formula_envelope'])[0],0.000001
    too_small=S::ScalePlan.scaled_snapshot(current,[0.5,1,1])
    assert_match 'Scale',assert_raises(S::Core::Error) { S::ScalePlan.plan(rule,too_small,plan['target']) }.message
    blocked=S::Core.copy_data(rule)
    blocked['formula_engine']['attribute_program']['dc_inputs']['_lenx_access']='TEXTBOX'
    assert_raises(S::Core::Error) { S::Core.plan(blocked,source,'dodaytam'=>80) }
    damaged=S::Core.copy_data(current);damaged['parts'].first['bounds'][1][0]=51
    assert_match 'hình học hiện tại',assert_raises(S::Core::Error) { S::Core.plan(rule,damaged,'dodaytam'=>20) }.message
  end
end
