# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative 'formula_fixtures'

class ModuleStudioLibraryFunctionsTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  Functions = MH::ModuleStudio::DCFormulas
  Parametric = MH::ModuleStudio::Parametric

  def fixture
    sample = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'library_nominal_cabinet.json'), encoding: 'UTF-8'))
    # Portable geometry tests model these captured bounds as synthetic boxes.
    # SDK-only reading in production must never certify those boxes itself.
    sample['parts'].each { |part| part['box_verified'] = true }
    sample
  end

  def numeric(text)
    Parametric.numeric_expression(Functions::Parser.new(text).parse) { |_scope, _key| raise 'Unexpected reference' }
  end

  def test_standard_numeric_functions_and_lazy_choose
    { 'SMALLEST(3,1,2)' => 1, 'largest(-2,4,3)' => 4, 'ROUND(1.12789,2)' => 1.13,
      'round(125,-1)' => 130, 'ceiling(1.23,.1)' => 1.3, 'ceiling(2.1)' => 3,
      'floor(1.29,.1)' => 1.2, 'sqrt(9)' => 3, 'iseven(4.9)' => 1, 'iseven(3.9)' => 0,
      'choose(2,1/0,17)' => 17, 'sin(30)' => 0.5, 'cos(60)' => 0.5, 'tan(45)' => 1,
      'pi()' => Math::PI, 'true()' => 1, 'false()' => 0 }.each do |text, expected|
      assert_in_delta expected, numeric(text), 1.0e-9, text
    end
    %w[sqrt(-1) round(1,999) ceiling(2,0) floor(2,-1) choose(0,1,2) pi(1) smallest()].each do |text|
      assert_raises(Core::Error, text) { numeric(text) }
    end
  end

  def test_verified_nominal_function_body_is_recognized_without_executing_it
    bodies = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'nominal_function_sequences.json'), encoding: 'UTF-8'))
    bodies.each do |name, body|
      entry = Functions.verified_nominal_reference(body)
      assert_equal Functions::NOMINAL_FUNCTIONS.fetch(name), entry['attribute']
      modified = Marshal.load(Marshal.dump(body))
      modified[13] << ['putself']
      assert_nil Functions.verified_nominal_reference(modified), 'Extra executable instructions must reject the entire implementation.'
    end
    assert_nil Functions.verified_nominal_reference([])
    assert_raises(Core::Error) { Functions::Parser.new('unverified_random_name()').parse }
    assert_raises(Core::Error) { Functions::Parser.new('f_pkd9225hweeqn4(1)').parse }
  end

  def test_alias_schema_and_units_are_not_guessed
    source = fixture
    source['function_aliases']['new_alias'] = { 'kind' => 'parent_nominal', 'attribute' => 'leny', 'signature' => Functions::NOMINAL_SIGNATURE }
    top = source['dc_graph']['nodes'].find { |node| node['name'] == 'Nóc' }
    top['attributes']['_leny_formula'] = 'new_alias()-parent!t1_ylmsdir'
    rule = Core.learn_module([source])
    assert_includes rule['rules'].keys, 'iwc3l3ib0g'
    source['function_aliases']['new_alias']['attribute'] = 'Kernel.system'
    assert_raises(Core::Error) { Functions::Program.new(source) }
    source = fixture
    source['dc_inputs']['_lengthunits'] = 'MILLIMETERS'
    assert_match 'danh nghĩa', assert_raises(Core::Error) { Functions::Program.new(source).evaluate(Functions::Program.new(source).controls.transform_values { |control| control['display_value'] }) }.message
  end

  def test_library_att_becomes_editable_and_nested_back_resizes_once
    source = fixture
    before = JSON.generate(source)
    rule = MH::ModuleStudio::RuleSystem.build(source, Core.learn_module([source]))
    %w[ba4ulq2qnw ikqikbwfw7 iwc3l3ib0g iwz_2qxr5k gapw12nc10].each do |key|
      assert rule['parameters'].find { |parameter| parameter['key'] == key }['editable'], key
    end
    plan = Core.plan(rule, source, 'ba4ulq2qnw' => 20, 'ikqikbwfw7' => 10, 'iwc3l3ib0g' => 20, 'iwz_2qxr5k' => 8)
    back = plan['parts'].find { |part| part['name'] == 'Hậu' }
    width = Core.dimensions(source['envelope'])[0]
    depth = Core.dimensions(source['envelope'])[1]
    assert_in_delta width - 40 + 16, Core.dimensions(back['bounds'])[0], 0.001
    assert_in_delta 10, Core.dimensions(back['bounds'])[1], 0.001
    assert_in_delta 12, back['bounds'][0][0], 0.001
    assert_in_delta depth - 20 - 10, back['bounds'][0][1], 0.001
    assert Core.bounds_close?(Core.union(plan['parts']), source['envelope'])
    current = source.merge('parts' => plan['parts'], 'parameter_values' => plan['target'], 'dc_inputs' => {})
    assert_equal 0, Core.plan(rule, current, {})['changed_count']
    restored = Core.plan(Core.rule!(JSON.parse(JSON.generate(rule))), current, 'ba4ulq2qnw' => 17.6, 'ikqikbwfw7' => 8, 'iwc3l3ib0g' => 18)
    source['parts'].zip(restored['parts']).each { |a, b| assert Core.bounds_close?(a['bounds'], b['bounds'], 0.001), a['name'] }
    assert_equal before, JSON.generate(source)
  end

  def test_hidden_parts_do_not_block_active_att_but_activation_is_not_guessed
    source = fixture
    engine = Core.learn_module([source])
    hidden = source['parts'].select { |part| part['visible'] == false }
    refute_empty hidden
    plan = Core.plan(engine, source, 'gapw12nc10' => 50)
    hidden.each do |part|
      assert_equal part['bounds'], plan['parts'].find { |entry| entry['key'] == part['key'] }['bounds']
    end
    parameter = engine['parameters'].find { |entry| entry['key'] == 'we15u_bhc0' }
    refute parameter['editable']
    assert_match 'ẩn/hiện', parameter['reason']
  end

  def test_imported_conditional_groove_branch_cannot_shrink_the_envelope
    source = fixture
    rule = MH::ModuleStudio::RuleSystem.build(source, Core.learn_module([source]))
    first = Core.plan(rule, source, 'ba4ulq2qnw' => 20)
    current = source.merge('parts' => first['parts'], 'parameter_values' => first['target'], 'dc_inputs' => {})
    assert_match 'phủ bì', assert_raises(Core::Error) { Core.plan(rule, current, 'iwz_2qxr5k' => 20) }.message
    second = Core.plan(rule, current, 'iwz_2qxr5k' => 19)
    current = current.merge('parts' => second['parts'], 'parameter_values' => second['target'])
    assert_equal 0, Core.plan(rule, current, {})['changed_count']
    assert_equal 0, Core.plan(rule, current, 'iwz_2qxr5k' => 8)['target']['gapw12nc10']
  end

  def test_new_loaded_alias_is_captured_as_portable_data_without_calling_the_function
    skip 'Portable adapter test only' if Object.const_defined?(:DCFunctionsV1)
    source = fixture
    top = source['dc_graph']['nodes'].find { |node| node['name'] == 'Nóc' }
    top['attributes']['_leny_formula'] = 'new_verified_alias()-parent!t1_ylmsdir'
    klass = Class.new do
      define_method(:new_verified_alias) { raise 'Imported function must never be called' }
    end
    Object.const_set(:DCFunctionsV1, klass)
    body = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'nominal_function_sequences.json'), encoding: 'UTF-8'))['yo3oe7ej_1zgk34f']
    sequence = Object.new
    sequence.define_singleton_method(:to_a) { body }
    RubyVM::InstructionSequence.stub(:of, sequence) { MH::ModuleStudio::DCFunctionCapture.capture_function_aliases!(source) }
    assert_equal 'leny', source.dig('function_aliases', 'new_verified_alias', 'attribute')
    Object.send(:remove_const, :DCFunctionsV1)
    serialized = JSON.parse(JSON.generate(source))
    engine = Core.learn_module([serialized])
    assert_includes engine['rules'].keys, 'iwc3l3ib0g'
    assert_equal 0, Core.plan(engine, serialized, {})['changed_count']
  ensure
    Object.send(:remove_const, :DCFunctionsV1) if defined?(klass) && Object.const_defined?(:DCFunctionsV1) && Object.const_get(:DCFunctionsV1).equal?(klass)
  end

  def test_new_math_functions_work_in_the_editable_variable_table
    sample = FormulaFixtures.snapshot
    rule = MH::ModuleStudio::RuleSystem.build(sample, Core.learn_module([sample]))
    rows = Parametric.variables(rule)
    rows.find { |row| row['binding'] == 't' }['formula'] = 'round(17.65,1) + smallest(1,2)'
    edited = Parametric.edit_variables(rule, rows)
    assert_in_delta 18.7, Parametric.targets(edited)['t'], 0.001
    assert Core.bounds_close?(Core.plan(edited, sample, Parametric.targets(edited))['envelope'], sample['envelope'])
  end

  def test_library_dependencies_are_visible_as_own_parametric_formulas
    sample = fixture
    rule = MH::ModuleStudio::RuleSystem.build(sample, Core.learn_module([sample]))
    back = sample['parts'].find { |part| part['name'] == 'Hậu' }
    positions = Functions::SymbolicProgram.new(sample).symbolic_positions
    low, high = positions.fetch(back['key'])
    width = MH::ModuleStudio::AffinePosition.add(high[0], low[0], -1)
    assert_in_delta 1, width[1]['@lenx'], 0.001
    assert_in_delta(-2, width[1]['ba4ulq2qnw'], 0.001)
    assert_in_delta 2, width[1]['iwz_2qxr5k'], 0.001
    sheet = Parametric.sheet(rule, sample)
    row = sheet['parts'].find { |part| part['key'] == back['key'] }
    assert_equal 'att', row['expressions'][0]['kind']
    assert_match 'Module.LenX', row['expressions'][0]['text']
    assert_match 'ba4ulq2qnw', row['expressions'][0]['text']
    saved = JSON.parse(JSON.generate(rule))
    saved['position_rules_version'] = 1
    saved['constraints'].select { |entry| entry['type'] == 'position' }.each { |entry| entry['expression'] = nil }
    Core.rule!(saved)
    assert_equal 2, saved['position_rules_version']
    width_rule = saved['constraints'].find { |entry| entry['type'] == 'position' && entry['face']['part'] == back['key'] && entry['measure'] == 'dimension' && entry['face']['axis'] == 0 }
    assert_in_delta(-2, width_rule['expression']['coefficients']['ba4ulq2qnw'], 0.001)
  end
end
