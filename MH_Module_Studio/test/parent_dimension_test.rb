# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioParentDimensionTest < Minitest::Test
  S = MH::ModuleStudio

  def fixture(name)
    JSON.parse(File.read(File.join(__dir__,"fixtures/#{name}.json"),encoding:'UTF-8'))
  end

  def edit(rule,value)
    rows = S::Parametric.variables(rule)
    rows.find { |row| row['symbol']=='T1' }['value'] = value
    S::Parametric.edit_variables(rule,rows)
  end

  def test_parent_length_references_follow_declared_thickness_through_nested_door_groups
    data = fixture('parent-length-door'); original = JSON.generate(data)
    current = S::Core.copy_data(data['snapshot'])
    [20,200,50,18.6,17.6].each do |value|
      rule = edit(data['rule'],value)
      plan = S::Core.plan(rule,current,S::Parametric.targets(rule))
      assert_equal [1],rule.dig('formula_engine','envelope_policy','axes')
      assert_in_delta value,S::Core.dimensions(plan['envelope'])[1],0.000001
      [0,2].each { |axis| assert_in_delta 500,S::Core.dimensions(plan['envelope'])[axis],0.000001 }
      plan['parts'].each { |part| assert_in_delta value,S::Core.dimensions(part['bounds'])[1],0.000001 }
      current.merge!('parts'=>plan['parts'],'envelope'=>plan['envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
      assert_equal 0,S::Core.plan(rule,current,{})['changed_count']
    end
    assert_equal original,JSON.generate(data)
  end

  def test_numeric_symbolic_and_sheet_expressions_share_root_output_semantics
    data = fixture('parent-length-door'); snapshot = data['rule']['formula_engine']['attribute_program']
    program = S::DCFormulas::ParametricProgram.new(snapshot)
    symbolic = program.symbolic_positions
    texts = program.cell_formula_texts('a0van'=>'T1')
    [20,200].each do |value|
      bounds, = program.evaluate(data['values'].merge('a0van'=>value))
      bounds.each do |key,box|
        symbolic[key].each_with_index do |sides,side|
          constant,coefficients = sides[1]
          assert_in_delta box[side][1],constant+coefficients.sum { |input,factor| {'a0van'=>value}.fetch(input)*factor },0.000001
        end
        text = texts[key][1]
        assert text
        ast = S::DCFormulas::Parser.new(text).parse
        actual = S::Parametric.numeric_expression(ast) { |_scope,name| {'t1'=>value}.fetch(name) }
        assert_in_delta value,actual,0.000001
      end
    end
  end

  def test_kitchen_accepts_200_mm_and_repeated_edits_preserve_dimensions
    data = fixture('kitchen-thickness'); before = JSON.generate(data)
    current = S::Core.copy_data(data['snapshot'])
    [200,50,200,17.6].each do |value|
      rule = edit(data['rule'],value)
      plan = S::Core.plan(rule,current,S::Parametric.targets(rule))
      assert S::Core.bounds_close?(current['envelope'],plan['envelope'],0.001)
      %w[part:0001 part:0002 part:0003].each do |key|
        part = plan['parts'].find { |p| p['key']==key }
        assert_in_delta value,S::Core.dimensions(part['bounds'])[part['thickness_axis']],0.000001
      end
      current.merge!('parts'=>plan['parts'],'envelope'=>plan['envelope'],'parameter_values'=>plan['target'],'dc_inputs'=>{})
    end
    assert_equal before,JSON.generate(data)
    error = assert_raises(S::Core::Error) do
      rule = edit(data['rule'],310)
      S::Core.plan(rule,data['snapshot'],S::Parametric.targets(rule))
    end
    refute_match 'ngoài phạm vi',error.message
  end

  def test_measured_root_length_cycles_never_become_outputs
    data = fixture('parent-length-door')
    attrs = data['rule']['formula_engine']['attribute_program']['dc_inputs']
    attrs['_leny_formula'] = 'if(a0Van>1.8,LenY,a0Van)'
    program = S::DCFormulas::Program.new(data['rule']['formula_engine']['attribute_program'])
    assert_empty program.root_outputs
    assert_empty S::EnvelopePolicy.derive(data['rule']['formula_engine']['attribute_program'],program)['axes']
  end

  def test_unexposed_dimension_without_access_metadata_is_an_output_but_textbox_is_not
    data=fixture('parent-length-door')
    source=data['rule']['formula_engine']['attribute_program']
    source['dc_inputs'].delete('_leny_access')
    program=S::DCFormulas::Program.new(source)
    assert_includes program.root_outputs,'leny'
    bounds,=program.evaluate(data['values'].merge('a0van'=>20))
    bounds.each_value { |box| assert_in_delta 20,S::Core.dimensions(box)[1],0.000001 }
    source['dc_inputs']['_leny_access']='TEXTBOX'
    refute_includes S::DCFormulas::Program.new(source).root_outputs,'leny'
  end

  def test_scale_reconstructs_nested_parent_references_at_intrinsic_thickness
    data = fixture('parent-length-door')
    [[1.2,1.4,0.8],[0.8,0.7,1.3]].each do |factors|
      current = S::ScalePlan.scaled_snapshot(data['snapshot'],factors)
      plan = S::ScalePlan.plan(data['rule'],current,data['values'])
      assert_in_delta 17.6,S::Core.dimensions(plan['envelope'])[1],0.000001
      [0,2].each { |axis| assert_in_delta 500*factors[axis],S::Core.dimensions(plan['envelope'])[axis],0.000001 }
      plan['parts'].each { |part| assert_in_delta 17.6,S::Core.dimensions(part['bounds'])[1],0.000001 }
    end
  end
end
