# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioAssemblyThicknessTest < Minitest::Test
  S = MH::ModuleStudio

  def captured
    JSON.parse(File.read(File.join(__dir__,'fixtures/legacy-assembly-door.json'),encoding:'UTF-8'))
  end

  def edit(rule,value)
    rows = S::Parametric.variables(rule)
    rows.find { |row| row['symbol']=='T1' }['value'] = value
    S::Parametric.edit_variables(rule,rows)
  end

  def test_legacy_none_formula_dimension_migrates_and_repeated_thickness_edits_keep_other_axes
    data = captured; original = JSON.generate(data)
    current = S::Core.copy_data(data['snapshot']); rule = data['rule']
    [20,18.6,17.6].each do |value|
      edited = edit(rule,value)
      assert_equal [1],edited.dig('formula_engine','envelope_policy','axes')
      plan = S::Core.plan(edited,current,S::Parametric.targets(edited))
      assert_in_delta value,S::Core.dimensions(plan['envelope'])[1],0.000001
      [0,2].each { |axis| assert_in_delta S::Core.dimensions(current['envelope'])[axis],S::Core.dimensions(plan['envelope'])[axis],0.000001 }
      current.merge!('parts'=>plan['parts'],'envelope'=>plan['envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
      assert_equal 0,S::Core.plan(edited,current,{})['changed_count']
    end
    assert_equal original,JSON.generate(data)
  end

  def test_older_empty_policy_is_upgraded_but_forged_extra_axes_are_rejected
    data = captured; engine = data['rule']['formula_engine']
    engine['envelope_policy'] = {'version'=>1,'axes'=>[],'source'=>'readonly_att_independent_geometry'}
    assert_equal [1],S::Core.rule!(data['rule']).dig('formula_engine','envelope_policy','axes')
    engine['envelope_policy']['axes'] = [0,1]
    assert_raises(S::Core::Error) { S::Core.rule!(data['rule']) }
  end

  def test_editable_dimensions_remain_fixed_and_unexposed_independent_outputs_can_change
    %w[TEXTBOX LIST].each do |access|
      data = captured; attrs = data['rule'].dig('formula_engine','attribute_program','dc_inputs')
      attrs['_leny_access'] = access
      error = assert_raises(S::Core::Error) { edited = edit(data['rule'],20); S::Core.plan(edited,data['snapshot'],S::Parametric.targets(edited)) }
      assert_match 'phủ bì',error.message
    end
    ['NONE',''].each do |access|
      data = captured; attrs = data['rule'].dig('formula_engine','attribute_program','dc_inputs')
      attrs['_leny_access'] = access; attrs.delete('_leny_formula')
      edited = edit(data['rule'],20)
      assert_in_delta 20,S::Core.dimensions(S::Core.plan(edited,data['snapshot'],S::Parametric.targets(edited))['envelope'])[1],0.000001
    end
  end

  def test_self_reference_in_an_inactive_declared_branch_does_not_free_the_axis
    data = captured
    data['rule'].dig('formula_engine','attribute_program','dc_inputs')['_leny_formula'] = 'if(a0Van>1.8,LenY,a0Van)'
    rule = S::Core.rule!(data['rule'])
    assert_empty rule.dig('formula_engine','envelope_policy','axes')
    assert_raises(S::Core::Error) { S::Core.plan(edit(rule,20),data['snapshot'],'a0van'=>20) }
  end

  def test_declared_span_is_rechecked_for_the_actual_target_not_only_the_baseline
    data = captured
    data['rule'].dig('formula_engine','attribute_program','dc_inputs')['_leny_formula'] = 'if(a0Van>1.8,a0Van+0.1,a0Van)'
    assert_equal 0,S::Core.plan(data['rule'],data['snapshot'],{})['changed_count']
    error = assert_raises(S::Core::Error) { S::Core.plan(edit(data['rule'],20),data['snapshot'],'a0van'=>20) }
    assert_match 'không khớp công thức kích thước cha',error.message
  end

  def test_scale_up_and_down_restore_intrinsic_thickness_without_changing_x_z_targets
    data = captured
    [[1.2,1.2,1.2],[0.8,0.8,0.8],[1,1.3,1]].each do |factors|
      current = S::Core.copy_data(data['snapshot'])
      current['parts'].each { |part| part['bounds'].each { |point| 3.times { |axis| point[axis]*=factors[axis] } } }
      current['envelope'] = S::Core.union(current['parts'])
      plan = S::ScalePlan.plan(data['rule'],current,data['values'])
      assert_in_delta 17.6,S::Core.dimensions(plan['envelope'])[1],0.000001
      [0,2].each { |axis| assert_in_delta S::Core.dimensions(current['envelope'])[axis],S::Core.dimensions(plan['envelope'])[axis],0.000001 }
    end
  end

  def test_aggregate_correction_distributes_by_size_and_rejects_fixed_or_impossible_spans
    assert_equal [1.0,1.0],S::AssemblyMath.envelope_correction(2,[1,1],[600,600])
    assert_equal [0.5,1.5],S::AssemblyMath.envelope_correction(2,[1,1],[200,600])
    assert_equal [2.0,0.0],S::AssemblyMath.envelope_correction(2,[1,0],[600,18.6])
    assert_raises(S::Core::Error) { S::AssemblyMath.envelope_correction(5,[0,0],[18.6,18.6]) }
    assert_raises(S::Core::Error) { S::AssemblyMath.envelope_correction(-1300,[1,1],[600,600]) }
  end
end
