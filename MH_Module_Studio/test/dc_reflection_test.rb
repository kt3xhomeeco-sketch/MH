# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'
require_relative '../parametric'

class ModuleStudioDCReflectionTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  Program = MH::ModuleStudio::DCFormulas::ParametricProgram
  Parametric = MH::ModuleStudio::Parametric

  def reflected
    sample = FormulaFixtures.snapshot
    top = sample['dc_graph']['nodes'].find { |node| node['id'] == 'top' }
    top['transform'][0] = -1
    top['transform'][12] = 575 / 25.4
    top['local_bounds'].each { |point| point[0] -= 7 / 25.4 }
    top['attributes']['_x_formula'] = 'parent!lenx-parent!t-0.7*(parent!lenx-2*parent!t)/56.4'
    sample
  end

  def test_mirrored_offset_panel_retains_ordered_bounds_and_repeated_edits
    sample = reflected
    rule = JSON.parse(JSON.generate(Core.learn_module([sample])))
    assert_equal 0, Core.plan(rule, sample, {})['changed_count']
    [20, 16, 22, 18].each do |thickness|
      plan = Core.plan(rule, sample, 't' => thickness)
      top = plan['parts'].find { |part| part['key'] == 'top' }
      assert_in_delta thickness, top['bounds'][0][0], 0.001
      assert_in_delta 600 - thickness, top['bounds'][1][0], 0.001
      assert_equal sample['envelope'], plan['envelope']
      sample['parts'] = plan['parts']
      sample['parameter_values'] = plan['target']
      sample['dc_inputs'].delete_if { |key, _value| rule['rules'].key?(key) }
      assert_equal 0, Core.plan(rule, sample, plan['target'])['changed_count']
    end
  end

  def test_nested_reflection_and_nominal_resize_keep_symbolic_and_cell_formulas
    sample = FormulaFixtures.snapshot
    carrier = sample['dc_graph']['nodes'].find { |node| node['id'] == 'carrier' }
    carrier['transform'][0] = -1
    carrier['transform'][12] = 582 / 25.4
    carrier['attributes'].merge!('_x_formula' => 'parent!lenx-parent!t', '_lenx_formula' => 'parent!lenx-2*parent!t')
    back = sample['dc_graph']['nodes'].find { |node| node['id'] == 'back' }
    back['attributes']['_lenx_formula'] = 'aane20kv9i5qc67a()-parent!b+parent!b'
    rule = MH::ModuleStudio::RuleSystem.build(sample, Core.learn_module([sample]))
    plan = Core.plan(rule, sample, 't' => 20)
    actual = plan['parts'].find { |part| part['key'] == 'back' }
    assert_in_delta 20, actual['bounds'][0][0], 0.001
    assert_in_delta 580, actual['bounds'][1][0], 0.001
    symbolic = Program.new(sample).symbolic_positions.fetch('back')
    assert_in_delta 1, symbolic[0][0][1].fetch('t'), 0.001
    assert_in_delta(-1, symbolic[1][0][1].fetch('t'), 0.001)
    program = Program.new(sample)
    program.evaluate(Core.formula_values(sample, program.controls))
    cells = program.cell_formula_texts('t' => 'T', 'b' => 'B', 's' => 'S').fetch('back')
    assert cells[0], 'Reflected size must retain an editable cell formula'
    assert cells[3], 'Reflected position must retain an editable cell formula'
    evaluate_cell = lambda do |text|
      expanded = text.gsub('Module.LenX', '600').gsub(/\bT\b/, '20').gsub(/\bB\b/, '8')
      ast = MH::ModuleStudio::DCFormulas::Parser.new(expanded).parse
      Parametric.numeric_expression(ast) { raise 'Unexpected reference' }
    end
    assert_in_delta 560, evaluate_cell.call(cells[0]), 0.001
    assert_in_delta 20, evaluate_cell.call(cells[3]), 0.001
    sheet = Parametric.sheet(rule, sample, plan)['parts'].find { |part| part['key'] == 'back' }
    assert_in_delta 560, sheet['values'][0], 0.001
    assert_in_delta 20, sheet['values'][3], 0.001
  end

  def test_fixed_reflection_does_not_allow_negative_lengths_shear_or_new_rotations
    sample = reflected
    top = sample['dc_graph']['nodes'].find { |node| node['id'] == 'top' }
    top['attributes']['_lenx_formula'] = '-1'
    assert_match 'phải dương', assert_raises(Core::Error) { Core.learn_module([sample]) }.message
    sample = reflected
    top = sample['dc_graph']['nodes'].find { |node| node['id'] == 'top' }
    top['transform'][1] = 0.2
    assert_raises(Core::Error) { Program.new(sample) }
    sample = reflected
    top = sample['dc_graph']['nodes'].find { |node| node['id'] == 'top' }
    top['attributes']['_rotz_formula'] = 'parent!t'
    rule = Core.learn_module([sample])
    refute rule['parameters'].find { |param| param['key'] == 't' }['editable']
  end

  def test_reflected_default_dimensions_are_positive_and_position_gets_formula_marker
    sample = FormulaFixtures.snapshot
    left = sample['dc_graph']['nodes'].find { |node| node['id'] == 'left' }
    left['transform'][0] = -1
    left['transform'][12] = 18 / 25.4
    left['transform'][10] = -1
    left['transform'][14] = 500 / 25.4
    program = Program.new(sample)
    values = Core.formula_values(sample, program.controls)
    bounds, = program.evaluate(values)
    assert_in_delta 500, program.attribute('left', 'lenz'), 0.001
    assert Core.bounds_close?(sample['parts'].find { |part| part['key'] == 'left' }['bounds'], bounds['left'], 0.001)
    assert program.has_cell_formula?('left', 3), 'Mirrored X depends on LenX even when the local minimum is zero'
    changed, = program.evaluate(values.merge('t' => 16))
    assert_in_delta 2, changed['left'][0][0], 0.001
    assert_in_delta 18, changed['left'][1][0], 0.001
  end
end
