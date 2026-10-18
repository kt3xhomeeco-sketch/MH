# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'

class ModuleStudioDCFunctionCoverageTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  Functions = MH::ModuleStudio::DCFormulas
  Parametric = MH::ModuleStudio::Parametric

  def numeric(text)
    Parametric.numeric_expression(Functions::Parser.new(text).parse) { raise 'Unexpected reference' }
  end

  def test_additional_math_functions_have_dc_units_and_domain_checks
    { 'degrees(pi())' => 180, 'radians(180)' => Math::PI, 'exp(1)' => Math::E,
      'ln(exp(2))' => 2, 'log10(100)' => 2, 'int(-1.1)' => -2,
      'isodd(-3.9)' => 1, 'isodd(4.9)' => 0, 'sign(-2)' => -1, 'sign(0)' => 0, 'sign(2)' => 1,
      'even(3.1)' => 4, 'even(-3.1)' => -4, 'even(0)' => 0,
      'odd(4.1)' => 5, 'odd(-4.1)' => -5, 'odd(0)' => 1, 'odd(3)' => 3,
      'asin(.5)' => 30, 'acos(.5)' => 60, 'atan(1)' => 45,
      'acosh(cosh(30))' => 30, 'asinh(sinh(30))' => 30, 'atanh(tanh(-30))' => -30,
      'nearest(25,10,24,36)' => 24, 'nearest(30,24,36)' => 24,
      'if(0,exp(1000),18)' => 18 }.each do |text, expected|
      assert_in_delta expected, numeric(text), 1.0e-8, text
    end
    %w[ln(0) ln(-1) log10(-1) exp(1000) acos(2) asin(-2) acosh(.5) atanh(1)
       sinh(100000) nearest(2) sign() int(1,2)].each do |text|
      assert_raises(Core::Error, text) { numeric(text) }
    end
  end

  def test_source_reader_accepts_only_the_complete_verified_template
    source = Functions::NOMINAL_SOURCE.sub('__FUNCTION__', 'fresh_width').sub('__PRODUCT__', 'test_product').sub('__LENGTH__', 'lenx')
    aliases = Functions.source_nominal_aliases(source)
    assert_equal({ 'fresh_width' => { 'kind' => 'parent_nominal', 'attribute' => 'lenx', 'signature' => Functions::NOMINAL_SIGNATURE } }, aliases)
    changed = source.sub('fresh_width', 'fresh_depth').sub('_lenx_nominal', '_leny_nominal')
    assert_equal 2, Functions.source_nominal_aliases(source + "\n" + changed).length
    unbound = Functions::UNBOUND_SOURCE.sub('__FUNCTION__', 'unused_helper').sub('__PRODUCT__', 'fixture')
    assert_equal aliases, Functions.source_nominal_aliases(source + unbound)
    assert_raises(Core::Error) { Functions.source_nominal_aliases(unbound) }
    [source + '; Kernel.system("bad")', source.sub('2.54', '25.4'), source.sub("ret = dict", "Kernel.system('bad'); ret = dict"),
     source.sub('_lengthunits', '_unverified_units'), source + source.sub('_lenx_nominal', '_lenz_nominal'), '', ' '].each do |text|
      assert_raises(Core::Error) { Functions.source_nominal_aliases(text) }
    end
    sample = FormulaFixtures.snapshot
    node = sample['dc_graph']['nodes'].find { |entry| entry['id'] == 'top' }
    # Formula coordinates are cm: subtract t expressed in cm from parent nominal.
    node['attributes']['_lenx_formula'] = 'fresh_width()-2*parent!t'
    sample['function_aliases'] = JSON.parse(JSON.generate(aliases))
    plan = Core.plan(Core.learn_module([sample]), sample, 't' => 20)
    top = plan['parts'].find { |part| part['key'] == 'top' }
    assert_in_delta 560, Core.dimensions(top['bounds'])[0], 0.001
  end

  def test_implicit_original_and_explicit_copy_indices_control_positions
    sample = FormulaFixtures.snapshot
    node = sample['dc_graph']['nodes'].find { |entry| entry['id'] == 'bottom' }
    node['attributes']['_z_formula'] = 'COPY * (parent!t + parent!b)'
    original = Core.learn_module([sample])
    assert_equal 0, Core.plan(original, sample, {})['changed_count']
    assert_in_delta 0, Functions::SymbolicProgram.new(sample).symbolic_positions['bottom'][0][2][0], 0.001
    node['attributes']['copy'] = 2
    sample['parts'].find { |part| part['key'] == 'bottom' }['bounds'].each { |point| point[2] += 52 }
    engine = Core.learn_module([sample])
    saved = JSON.parse(JSON.generate(engine))
    plan = Core.plan(saved, sample, 't' => 20)
    bottom = plan['parts'].find { |part| part['key'] == 'bottom' }
    assert_in_delta 56, bottom['bounds'][0][2], 0.001
    expressions = Functions::SymbolicProgram.new(sample).symbolic_positions['bottom'][0][2]
    assert_in_delta 2, expressions[1]['t'], 0.001
    node['attributes']['_copies_formula'] = 'parent!t'
    changed = Core.learn_module([sample])
    refute changed['parameters'].find { |param| param['key'] == 't' }['editable']
  end

  def test_named_container_wins_over_a_same_named_descendant_but_unrelated_duplicates_remain_ambiguous
    sample = FormulaFixtures.snapshot
    sample['dc_inputs']['_name'] = 'Cabinet'
    top = sample['dc_graph']['nodes'].find { |node| node['id'] == 'top' }
    bottom = sample['dc_graph']['nodes'].find { |node| node['id'] == 'bottom' }
    bottom['attributes']['_name'] = 'Cabinet'
    top['attributes']['_lenx_formula'] = 'Cabinet!LenX-2*Cabinet!t'
    plan = Core.plan(Core.learn_module([sample]), sample, 't' => 20)
    assert_in_delta 560, Core.dimensions(plan['parts'].find { |part| part['key'] == 'top' }['bounds'])[0], 0.001
    sample['dc_inputs']['_name'] = 'Root'
    sample['dc_graph']['nodes'].find { |node| node['id'] == 'right' }['attributes']['_name'] = 'Cabinet'
    program = Functions::Program.new(sample)
    assert_match 'không rõ group', assert_raises(Core::Error) { program.reference_path('top', 'cabinet') }.message
  end

  def test_numeric_string_formula_metadata_keeps_guards_and_rejects_text_lengths
    sample = FormulaFixtures.snapshot
    top = sample['dc_graph']['nodes'].find { |node| node['id'] == 'top' }
    top['attributes'].merge!('_hidden_formula' => 'if(parent!t>0,0,1)', '_hidden_formulaunits' => 'STRING')
    rule = Core.learn_module([sample])
    assert Core.plan(rule, sample, 't' => 20)['changed_count'].positive?
    top['attributes']['_lenx_formulaunits'] = 'STRING'
    assert_match 'STRING', assert_raises(Core::Error) { Core.learn_module([sample]) }.message
  end
end
