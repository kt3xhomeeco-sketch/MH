# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioCustomInputsTest < Minitest::Test
  S=MH::ModuleStudio

  def snapshot
    JSON.parse(File.read(File.join(__dir__,'fixtures/filler-right-dc.json'),encoding:'UTF-8'))
  end

  def test_hidden_five_cm_custom_att_becomes_fifty_mm_variable_and_named_part_formula
    data=snapshot;before=JSON.generate(data)
    rule=S::StudioCalculation.build_system([data])
    sheet=S::Parametric.sheet(rule,data)
    row=sheet['variables'].find { |r| r['binding']=='xuong' }
    assert row
    assert_equal 'Xuong',row['name']
    assert_equal 'mm',row['unit']
    assert_in_delta 50,row['value'],0.000001
    assert row['can_edit'] || rule['parameters'].find { |p| p['key']=='xuong' }['editable']
    part=sheet['parts'].find { |p| p['key']=='sp14_xương nẹp' }
    assert_match(/xuong/i,part['expressions'][1]['text'])
    assert_equal ['xuong'],part['expressions'][1]['variables']
    assert_equal before,JSON.generate(data)
    assert_equal '5',rule.dig('formula_engine','attribute_program','dc_inputs','xuong')
  end

  def test_renamed_custom_symbol_edits_geometry_saves_and_remains_fixed_after_scale
    data=snapshot;rule=S::StudioCalculation.build_system([data])
    rows=S::Parametric.variables(rule)
    x=rows.find { |r| r['binding']=='xuong' };x['symbol']='XUONG';x['value']=70;x['exported']=true
    rule=S::Parametric.edit_variables(rule,rows)
    values=S::Parametric.targets(rule)
    plan=S::Core.plan(rule,data,values)
    actual=plan['parts'].find { |p| p['key']=='sp14_xương nẹp' }
    assert_in_delta 70,S::Core.dimensions(actual['bounds'])[1],0.000001
    assert_in_delta 88.6,S::Core.dimensions(plan['envelope'])[1],0.000001
    current=data.merge('parts'=>plan['parts'],'envelope'=>plan['envelope'],'formula_envelope'=>plan['formula_envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
    saved=S::Core.rule!(JSON.parse(JSON.generate(S::Parametric.with_values(rule,values))))
    assert_equal 0,S::Core.plan(saved,current,{})['changed_count']
    result=S::ScalePlan.plan(saved,S::ScalePlan.scaled_snapshot(current,[1,2,1]),values)
    assert_in_delta 70,S::Core.dimensions(result['parts'].find { |p| p['key']=='sp14_xương nẹp' }['bounds'])[1],0.000001
    option=S::OptionsParameters.rows(saved,values).find { |r| r['symbol']=='XUONG' }
    assert_in_delta 70,option['value'],0.000001
    assert option['editable']
  end

  def test_mixed_scalar_use_is_not_guessed_to_be_mm_and_unused_or_formula_constants_are_not_promoted
    data=snapshot
    data['dc_inputs'].merge!('unused'=>'123','_unused_label'=>'Unused','derived'=>'5','_derived_formula'=>'5')
    node=data['dc_graph']['nodes'].last
    node['attributes']['_hidden_formula']='if(parent!xuong<0,1,0)'
    enabled=S::DCCustomInputs.enable(data)
    controls=S::Core.dc_controls(enabled)
    assert_equal '',controls['xuong']['unit']
    assert_equal 5,controls['xuong']['display_value']
    refute controls.key?('unused')
    refute controls.key?('derived')
    refute controls.key?('scaletool')
    program=S::DCFormulas::Program.new(enabled)
    bounds,=program.evaluate(S::Core.formula_values(enabled,controls).merge('xuong'=>7))
    assert_in_delta 70,S::Core.dimensions(bounds['sp14_xương nẹp'])[1],0.000001
  end

  def test_old_programs_keep_legacy_meaning_and_failed_discovery_keeps_geometry_fallback
    data=snapshot
    refute S::Core.dc_controls(data).key?('xuong')
    old=S::Core.learn_module([data])
    refute(old['parameters'].any? { |p| p['key']=='xuong' })
    assert_equal 0,S::Core.plan(old,data,{'dodaytam'=>18.6})['changed_count']
    broken=S::Core.copy_data(data);broken['dc_graph']['root_frame'][1]=0.5
    rule=S::StudioCalculation.build_system([broken])
    assert_nil rule['formula_engine']
    assert(rule['warnings'].any? { |text| text.include?('ATT chưa dịch được') })
  end
end
