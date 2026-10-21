# encoding: UTF-8
require 'minitest/autorun'
require_relative 'fixtures'
require_relative '../parametric'

class ModuleStudioPartFormulaTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  System = MH::ModuleStudio::RuleSystem
  Parametric = MH::ModuleStudio::Parametric

  def setup
    @snapshot = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'readable_nested_dc.json'), encoding: 'UTF-8'))
    @rule = System.build(@snapshot, Core.learn_module([@snapshot]))
    @key = @snapshot['parts'].find { |part| part['name'] == 'Giằng Trước' }['key']
  end

  def edit(text, field = 'lenz', rule = @rule)
    Parametric.edit_part_formula(rule, @key, field, text)
  end

  def plan(rule, snapshot = @snapshot, targets = Parametric.targets(rule))
    Core.plan(rule, snapshot, targets)
  end

  def part(result)
    result['parts'].find { |item| item['key'] == @key }
  end

  def test_formula_changes_part_and_recalculates_with_inputs_and_envelope
    before = JSON.generate(@rule)
    edited = edit('IF(Parent!giang > 50, giang + 10, 60)')
    result = plan(edited)
    assert_in_delta 80, Core.dimensions(part(result)['bounds'])[2], 0.001
    assert_in_delta 770, part(result)['bounds'][0][2], 0.001
    assert_equal @snapshot['envelope'], result['envelope']
    result = plan(edited, @snapshot, Parametric.targets(edited).merge('giang' => 90))
    assert_in_delta 100, Core.dimensions(part(result)['bounds'])[2], 0.001
    assert_equal before, JSON.generate(@rule)
    sheet = Parametric.sheet(edited, @snapshot, result)['parts'].find { |row| row['key'] == @key }
    assert_equal 'manual', sheet['expressions'][2]['kind']
    assert_equal 'IF(Parent!giang > 50, giang + 10, 60)', sheet['expressions'][2]['text']
  end

  def test_module_dimensions_local_references_and_custom_variables
    rows = Parametric.variables(@rule)
    rows << { 'id' => 'custom:gap', 'binding' => nil, 'name' => 'Khe', 'symbol' => 'khe', 'category' => 'dimension', 'unit' => 'mm', 'value' => 2, 'formula' => '', 'exported' => true }
    edited = Parametric.edit_variables(@rule, rows)
    edited = edit('Module.LenX - 2 * dayvan - khe', 'lenx', edited)
    edited = edit('Module!LenZ - LenZ', 'z', edited)
    result = plan(edited)
    assert_in_delta 560.8, Core.dimensions(part(result)['bounds'])[0], 0.001
    assert_in_delta 780, part(result)['bounds'][0][2], 0.001
    rows.pop
    assert_raises(Core::Error) { Parametric.edit_variables(edited, rows) }
    assert_equal 'Module!LenZ - LenZ', Core.rule!(JSON.parse(JSON.generate(edited))).dig('part_formulas', @key, 'z')
  end

  def test_invalid_references_cycles_code_and_nonfinite_results_are_rejected
    %w[missing LenZ].each { |text| assert_raises(Core::Error) { edit(text) } }
    assert_raises(Core::Error) { edit('Kernel.system(1)') }
    assert_raises(Core::Error) { edit('1 / 0') }
    first = edit('LenX', 'lenz')
    assert_raises(Core::Error) { edit('LenZ', 'lenx', first) }
    assert_raises(Core::Error) { Parametric.edit_part_formula(@rule, 'missing', 'x', '1') }
    assert_raises(Core::Error) { Parametric.edit_part_formula(@rule, @key, 'copies', '2') }
  end

  def test_unsafe_size_and_envelope_conflict_do_not_change_source
    before = JSON.generate(@snapshot)
    assert_raises(Core::Error) { plan(edit('-1')) }
    assert_raises(Core::Error) { plan(edit('Module.LenZ + 1')) }
    bottom = @snapshot['parts'].find { |item| item['name'] == 'Đáy' }
    edited = Parametric.edit_part_formula(@rule, bottom['key'], 'lenx', 'Module.LenX - 1')
    assert_match(/xung đột/, assert_raises(Core::Error) { plan(edited) }.message)
    assert_equal before, JSON.generate(@snapshot)
  end

  def test_repeated_trial_update_and_restoring_imported_formula_are_idempotent
    edited = edit('giang + 10')
    result = plan(edited)
    trial = Marshal.load(Marshal.dump(@snapshot))
    trial['parts'] = result['parts']
    trial['parameter_values'] = result['target']
    again = plan(edited, trial)
    assert_equal 0, again['changed_count']
    restored = edit('', 'lenz', edited)
    result = plan(restored, trial)
    assert_in_delta 70, Core.dimensions(part(result)['bounds'])[2], 0.001
    assert_in_delta 780, part(result)['bounds'][0][2], 0.001
    assert_equal [], restored['part_formulas'].keys
    assert_includes restored['part_formula_parts'], @key
  end

  def test_ordinary_group_formula_replaces_its_thickness_and_keeps_contacts
    snapshot = StudioFixtures.cabinet(18)
    rule = System.build(snapshot)
    edited = Parametric.edit_part_formula(rule, 'left', 'lenx', '20')
    result = Core.plan(edited, snapshot, Parametric.targets(edited))
    left = result['parts'].find { |item| item['key'] == 'left' }
    bottom = result['parts'].find { |item| item['key'] == 'bottom' }
    assert_in_delta 20, Core.dimensions(left['bounds'])[0], 0.001
    assert_in_delta 20, bottom['bounds'][0][0], 0.001
    assert_equal snapshot['envelope'], result['envelope']
  end
end
