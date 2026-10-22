# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'

class ModuleStudioCustomAttributesTest < Minitest::Test
  S=MH::ModuleStudio

  def source
    data=FormulaFixtures.snapshot
    data['dc_inputs'].merge!('caption'=>'Cánh | Drawer','_caption_access'=>'NONE','_caption_units'=>'STRING',
      'derived'=>36.0/25.4,'_derived_units'=>'MILLIMETERS','_derived_formulaunits'=>'CENTIMETERS','_derived_formula'=>'2*t',
      'custom_count'=>7,'_custom_count_label'=>'Số riêng', 'dialogheight'=>850,'_dialogheight_formula'=>'850')
    data
  end

  def test_hidden_text_computed_and_unused_custom_data_are_retained_without_overriding_geometry
    data=source;before=JSON.generate(data)
    rule=S::StudioCalculation.build_system([data])
    %w[caption derived custom_count].each do |key|
      param=rule['parameters'].find { |item| item['dc_key']==key }
      assert param,key
      assert_equal key,param['key']
      refute param['editable']
    end
    refute(rule['parameters'].any? { |item| item['key']=='dialogheight' })
    assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
    rows=S::Parametric.variables(rule)
    rows.find { |row| row['binding']=='t' }['value']=20
    rule=S::Parametric.edit_variables(rule,rows)
    values=S::Parametric.evaluate_variables(rule)
    assert_in_delta 40,values['input:derived'],0.000001
    sheet=S::Parametric.sheet(rule,data)
    derived=sheet['variables'].find { |row| row['binding']=='derived' }
    assert_equal '2*t',derived['source_formula']
    refute derived['editable']
    assert_equal 'Cánh | Drawer',values['input:caption']
    assert_equal before,JSON.generate(data)
    restored=S::Core.rule!(JSON.parse(JSON.generate(rule)))
    assert_equal values,S::Parametric.evaluate_variables(restored)
  end

  def test_custom_values_share_one_compiled_program_per_evaluation_and_keep_new_inputs
    data=source
    data['dc_inputs'].merge!('derived_two'=>54.0/25.4,'_derived_two_units'=>'MILLIMETERS',
      '_derived_two_formulaunits'=>'CENTIMETERS','_derived_two_formula'=>'3*t')
    rule=S::StudioCalculation.build_system([data])
    original=S::DCFormulas::Program.method(:new);compiled=0
    factory=lambda { |*args| compiled+=1;original.call(*args) }
    S::DCFormulas::Program.stub(:new,factory) do
      first=S::Parametric.evaluate_variables(rule)
      assert_in_delta 36,first['input:derived'],0.000001
      assert_in_delta 54,first['input:derived_two'],0.000001
      assert_equal 1,compiled
      changed=S::Core.copy_data(rule)
      changed['parametric_variables']=S::Parametric.variables(changed)
      changed['parametric_variables'].find { |row| row['binding']=='t' }['value']=20
      second=S::Parametric.evaluate_variables(changed)
      assert_in_delta 40,second['input:derived'],0.000001
      assert_in_delta 60,second['input:derived_two'],0.000001
      assert_equal 2,compiled
    end
  end

  def test_old_payload_upgrades_without_changing_its_existing_symbols_or_original_source
    data=source
    old=S::RuleSystem.build(data,S::Core.learn_module([data]))
    rows=S::Parametric.variables(old);rows.find { |row| row['binding']=='t' }['symbol']='DAY_VAN'
    old=S::Parametric.edit_variables(old,rows)
    before=JSON.generate(old)
    upgraded=S::DCCustomAttributes.upgrade(old)
    assert_equal 'DAY_VAN',S::Parametric.variables(upgraded).find { |row| row['binding']=='t' }['symbol']
    assert(S::Parametric.variables(upgraded).any? { |row| row['binding']=='derived' })
    assert_equal upgraded,S::DCCustomAttributes.upgrade(upgraded)
    assert_equal before,JSON.generate(old)
  end

  def test_fallback_keeps_original_keys_and_disambiguates_own_geometry_parameters
    data=FormulaFixtures.snapshot
    data['dc_inputs'].merge!('thickness_1'=>1,'_thickness_1_access'=>'TEXTBOX','_thickness_1_units'=>'FLOAT')
    rule=S::RuleSystem.build(data)
    setback=rule['parameters'].find { |param| param['dc_key']=='s' }
    assert_equal 's',setback['key']
    collision=rule['parameters'].find { |param| param['dc_key']=='thickness_1' }
    assert_equal 'thickness_1_1',collision['key']
    assert_equal rule['parameters'].length,rule['parameters'].map { |param| param['key'] }.uniq.length
  end

  def test_equal_att_symbols_remain_separate_between_modules
    rule=S::StudioCalculation.build_system([FormulaFixtures.snapshot])
    rows=S::Parametric.variables(rule)
    rows.each { |row| row['exported']=false }
    rows << {'id'=>'custom:same','name'=>'Riêng','symbol'=>'att_1','category'=>'number','unit'=>'','value'=>1,'formula'=>'','exported'=>true}
    a=S::Parametric.edit_variables(rule,rows)
    rows.last['value']=2
    b=S::Parametric.edit_variables(rule,rows)
    grouped=S::OptionsParameters.grouped([{'pid'=>'11','name'=>'A','rule'=>a,'values'=>{}},{'pid'=>'22','name'=>'B','rule'=>b,'values'=>{}}])
    assert_equal [1,2],(grouped.map { |row| row['value'] })
    assert_equal ['11','22'],(grouped.map { |row| row['targets'].first['pid'] })
    assert_equal 2,grouped.map { |row| row['id'] }.uniq.length
  end

  def test_actual_drawer_front_keeps_every_custom_attribute_and_unexposed_parent_thickness_formula
    data=JSON.parse(File.read(File.join(__dir__,'fixtures/drawer-front-custom.json'),encoding:'UTF-8'))
    rule=S::StudioCalculation.build_system([data])
    keys=data['dc_inputs'].keys.reject { |key| key.start_with?('_') || S::DCCustomAttributes::STANDARD.include?(key) }
    present=rule['parameters'].flat_map { |param| [param['key'],param['dc_key']] }
    assert_equal 22,keys.length
    assert_empty keys-present
    assert(rule['parameters'].none? { |param| param['key'].match?(/\Aatt_\d+\z/) })
    key=S::Parametric.variables(rule).find { |row| row['symbol']=='T1' }['binding']
    refute(rule['parameters'].any? { |param| param['dc_key']=='leny' || param['key']=='leny' })
    assert_equal 'aaq78h_g67',data['dc_inputs']['_leny_formula']
    plan=S::Core.plan(rule,data,key=>20)
    assert_in_delta 20,S::Core.dimensions(plan['envelope'])[1],0.001
  end
end
