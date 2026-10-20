# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'
require_relative '../options_parameters'

class ModuleStudioListManualInputTest < Minitest::Test
  S=MH::ModuleStudio
  LIST='hghe0m3ihb'.freeze
  INPUT='hsxpei34m2'.freeze

  def setup
    @snapshot=JSON.parse(File.read(File.join(__dir__,'fixtures/drawer-manual-list.json'),encoding:'UTF-8'))
    @rule=S::StudioCalculation.build_system([@snapshot])
    @rows=S::Parametric.variables(@rule)
    @list=@rows.find { |row| row['binding']==LIST }
    @source=@rows.find { |row| row['binding']==INPUT }
    @choice=S::DCOptions.variable_choices(@rule,@rule['parameters'].find { |param| param['key']==LIST },@rows).last
  end

  def edited(value=473.25)
    S::DCOptions.assign!(@rule,@rows,@list['id'],@choice['value'])
    S::DCOptions.assign!(@rule,@rows,@source['id'],value)
    S::Parametric.edit_variables(@rule,@rows)
  end

  def test_actual_drawer_formula_choice_drives_non_list_depth_and_persists_rename
    assert @choice['supported']
    assert_equal INPUT,@choice['input_binding']
    assert_equal INPUT,@choice['formula']
    bundle=edited
    target=S::Parametric.targets(bundle)
    assert_equal 473.25,target[LIST]
    refute target.key?(INPUT),'Manual data must not become a fabricated geometry input'
    plan=S::Core.plan(bundle,@snapshot,target)
    assert_in_delta 473.25,S::Core.dimensions(plan['envelope'])[1],0.001
    assert_equal 18.6,plan['target']['d1'] if plan['target'].key?('d1')
    renamed=S::Parametric.variables(bundle)
    renamed.find { |row| row['binding']==INPUT }['symbol']='MyDepth'
    bundle=S::Parametric.edit_variables(bundle,renamed)
    assert_equal 'MyDepth',S::Parametric.variables(bundle).find { |row| row['binding']==LIST }['formula']
    restored=S::Core.rule!(JSON.parse(JSON.generate(bundle)))
    assert_equal 473.25,S::Parametric.targets(restored)[LIST]
    choice=S::DCOptions.variable_choices(restored,restored['parameters'].find { |param| param['key']==LIST },S::Parametric.variables(restored)).last
    assert_equal 'MyDepth',choice['formula']
    compact=S::OptionsParameters.rows(restored,S::Parametric.targets(restored))
    assert_equal 473.25,compact.find { |row| row['id']==@list['id'] }['value']
  end

  def test_preset_detaches_without_erasing_manual_value_and_reselect_restores_it
    bundle=edited
    rows=S::Parametric.variables(bundle)
    S::DCOptions.assign!(bundle,rows,@list['id'],450)
    bundle=S::Parametric.edit_variables(bundle,rows)
    assert_equal 450,S::Parametric.targets(bundle)[LIST]
    assert_equal 473.25,S::Parametric.variables(bundle).find { |row| row['binding']==INPUT }['value']
    S::DCOptions.assign!(bundle,rows,@list['id'],@choice['value'])
    bundle=S::Parametric.edit_variables(bundle,rows)
    assert_equal 473.25,S::Parametric.targets(bundle)[LIST]
  end

  def test_compact_hidden_input_and_grouped_member_targets_are_scoped
    @rows.each { |row| row['exported']=row['binding']==LIST }
    bundle=edited
    compact=S::OptionsParameters.rows(bundle,S::Parametric.targets(bundle))
    assert_equal 1,compact.length
    assert_equal '=hsxpei34m2',compact.first['selection']
    assert_equal 473.25,compact.first['manual_input']['value']
    grouped=S::OptionsParameters.grouped(%w[A B].map { |pid| {'pid'=>pid,'name'=>pid,'rule'=>bundle,'values'=>S::Parametric.targets(bundle)} })
    assert_equal 1,grouped.length
    assert_match(/common:.*:manual/,grouped.first['manual_input']['id'])
    assert_equal [{'pid'=>'A','variable_id'=>'input:'+INPUT},{'pid'=>'B','variable_id'=>'input:'+INPUT}],grouped.first['manual_input']['targets']
    rows=S::Parametric.variables(bundle)
    rows.find { |row| row['binding']==INPUT }['exported']=true
    bundle=S::Parametric.edit_variables(bundle,rows)
    compact=S::OptionsParameters.rows(bundle,S::Parametric.targets(bundle))
    assert_equal 2,compact.length
    assert(compact.all? { |row| row['manual_input'].nil? })
    assert compact.last['editable']
  end

  def test_unsafe_missing_computed_mismatched_units_and_cycles_stay_rejected
    assert_raises(S::Core::Error) { S::DCOptions.assign!(@rule,@rows,@list['id'],'=system(1)') }
    attrs=@rule['formula_engine']['attribute_program']['dc_inputs']
    attrs["_#{INPUT}_formula"]='d1'
    refute S::DCOptions.for_parameter(@rule,@rule['parameters'].find { |param| param['key']==LIST }).last['supported']
    attrs.delete("_#{INPUT}_formula")
    missing=S::Core.copy_data(@rule)
    missing['parameters'].reject! { |param| param['key']==INPUT }
    refute S::DCOptions.for_parameter(missing,missing['parameters'].find { |param| param['key']==LIST }).last['supported']
    @rule['parameters'].find { |param| param['key']==INPUT }['unit']=''
    refute S::DCOptions.for_parameter(@rule,@rule['parameters'].find { |param| param['key']==LIST }).last['supported']
    @rule['parameters'].find { |param| param['key']==INPUT }['unit']='mm'
    S::DCOptions.assign!(@rule,@rows,@list['id'],@choice['value'])
    @source['formula']=LIST
    assert_raises(S::Core::Error) { S::Parametric.edit_variables(@rule,@rows) }
  end

  def test_new_read_retains_manual_option_selected_in_original_att
    @snapshot['dc_inputs']["_#{LIST}_formula"]=INPUT
    @snapshot['dc_inputs'][INPUT]=@snapshot['dc_inputs'][LIST]
    bundle=S::StudioCalculation.build_system([@snapshot])
    row=S::Parametric.variables(bundle).find { |entry| entry['binding']==LIST }
    assert_equal INPUT,row['formula']
    rows=S::Parametric.variables(bundle)
    S::DCOptions.assign!(bundle,rows,'input:'+INPUT,487.5)
    bundle=S::Parametric.edit_variables(bundle,rows)
    assert_equal 487.5,S::Parametric.targets(bundle)[LIST]
  end
end
