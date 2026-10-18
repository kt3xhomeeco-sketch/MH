# frozen_string_literal: true
require 'json'
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioParametersTest < Minitest::Test
  Core = MH::ModuleStudio::Core

  def samples
    JSON.parse(File.read(File.join(__dir__, 'fixtures', 'dc_mixed_thickness.json'), encoding: 'UTF-8'))
  end

  def test_parent_module_owns_all_rules_and_captured_settings
    rule = Core.learn_module(samples)

    assert_equal 'module_parameter_set', rule['kind']
    assert_equal %w[ba4ulq2qnw ikqikbwfw7], rule['rules'].keys.sort
    assert_equal 6, rule['parameters'].length
    assert_equal 2, (rule['parameters'].count { |parameter| parameter['editable'] })
    setback = rule['parameters'].find { |parameter| parameter['key'] == 'iwc3l3ib0g' }
    assert_equal 18, setback['value']
    assert_equal false, setback['editable']
    refute rule['control_context'].key?('ba4ulq2qnw')
    refute rule['control_context'].key?('ikqikbwfw7')
  end

  def test_combined_plan_updates_shared_boards_once_with_both_effects
    data = samples
    rule = Core.learn_module(data)
    plan = Core.plan(rule, data.last, 'ba4ulq2qnw' => 18, 'ikqikbwfw7' => 9)
    parts = plan['parts'].to_h { |part| [part['name'], part] }

    assert_in_delta 564, Core.dimensions(parts['Nóc']['bounds'])[0], 0.001
    assert_in_delta 173, Core.dimensions(parts['Nóc']['bounds'])[1], 0.001
    assert_in_delta 18, Core.dimensions(parts['Nóc']['bounds'])[2], 0.001
    assert_in_delta 9, Core.dimensions(parts['Hậu']['bounds'])[1], 0.001
    assert_equal data.last['envelope'], plan['envelope']
    assert_equal plan['parts'].length, plan['parts'].map { |part| part['key'] }.uniq.length
    assert_equal true, plan['combination_unverified']
  end

  def test_partial_targets_preserve_other_parameter_current_value
    data = samples
    plan = Core.plan(Core.learn_module(data), data.last, 'ikqikbwfw7' => 9)

    assert_in_delta 17.6, plan['target']['ba4ulq2qnw'], 0.001
    assert_equal 9, plan['target']['ikqikbwfw7']
    assert_equal false, plan['combination_unverified']
  end

  def test_round_trip_retains_the_entire_parameter_set
    rule = JSON.parse(JSON.generate(Core.learn_module(samples)))
    Core.rule!(rule)

    assert_equal 2, rule['rules'].length
    assert_equal 6, rule['parameters'].length
    assert_equal 18, rule['control_context']['iwc3l3ib0g']['display_value']
  end

  def test_repeat_edits_use_current_geometry_without_dc_metadata
    data = samples
    rule = Core.learn_module(data)
    forward = Core.plan(rule, data.last, 'ba4ulq2qnw' => 18, 'ikqikbwfw7' => 9)
    trial = data.last.merge('parts' => forward['parts'], 'dc_inputs' => {})
    backward = Core.plan(rule, trial, 'ba4ulq2qnw' => 17.6, 'ikqikbwfw7' => 11)

    data.last['parts'].zip(backward['parts']).each do |before, after|
      2.times { |side| 3.times { |axis| assert_in_delta before['bounds'][side][axis], after['bounds'][side][axis], 0.001 } }
    end
  end

  def test_unlearned_and_unknown_targets_are_rejected
    data = samples
    rule = Core.learn_module(data)

    assert_raises(Core::Error) { Core.plan(rule, data.last, 'iwc3l3ib0g' => 20) }
    assert_raises(Core::Error) { Core.plan(rule, data.last, 'foreign' => 20) }
    assert_raises(Core::Error) { Core.plan(rule, data.last, 'ikqikbwfw7' => 0) }
  end

  def test_fixed_context_is_enforced_but_learned_parameters_can_change
    data = samples
    rule = Core.learn_module(data)
    data.last['dc_inputs']['iwc3l3ib0g'] = 20 / 25.4

    error = assert_raises(Core::Error) { Core.plan(rule, data.last, 'ikqikbwfw7' => 9) }
    assert_match 'Hậu Lùi', error.message
  end

  def fourth_state(data, rule)
    plan = Core.plan(rule, data.last, 'ba4ulq2qnw' => 18.6, 'ikqikbwfw7' => 11)
    result = Marshal.load(Marshal.dump(data.last))
    result['id'] = 'fourth-combination'
    result['parts'] = plan['parts']
    result['dc_inputs']['ba4ulq2qnw'] = 18.6 / 25.4
    result['parameter'] = 18.6
    result
  end

  def test_independent_fourth_combination_verifies_joint_targets
    data = samples
    data << fourth_state(data, Core.learn_module(data))
    rule = Core.learn_module(data)
    plan = Core.plan(rule, data[1], 'ba4ulq2qnw' => 18.6, 'ikqikbwfw7' => 11)

    assert_equal false, plan['combination_unverified']
  end

  def test_non_additive_interaction_is_not_silently_bundled
    data = samples
    extra = fourth_state(data, Core.learn_module(data))
    extra['parts'].find { |part| part['name'] == 'Nóc' }['bounds'][1][1] -= 1
    data << extra

    error = assert_raises(Core::Error) { Core.learn_module(data) }
    assert_match 'tổ hợp tham số chưa khớp', error.message
  end

  def test_no_op_does_not_move_any_geometry
    data = samples
    plan = Core.plan(Core.learn_module(data), data.last, {})

    assert_equal 0, plan['changed_count']
  end

  def test_import_rejects_missing_rule_and_nested_bundle
    rule = Core.learn_module(samples)
    missing = Marshal.load(Marshal.dump(rule))
    missing['rules'].delete('ikqikbwfw7')
    assert_raises(Core::Error) { Core.rule!(missing) }
    rule['rules']['ikqikbwfw7'] = rule
    assert_raises(Core::Error) { Core.rule!(rule) }
  end

  def test_exposed_selection_survives_round_trip_without_dropping_internal_rules
    rule = Core.learn_module(samples)
    Core.set_exposed_parameters!(rule, %w[ikqikbwfw7 iwc3l3ib0g])
    copy = Core.rule!(JSON.parse(JSON.generate(rule)))

    assert_equal %w[ikqikbwfw7 iwc3l3ib0g].sort, copy['exposed_parameter_keys'].sort
    assert_equal 2, copy['rules'].length
    exported = Core.exposed_parameters(copy, 'ikqikbwfw7' => 9)
    assert_equal 2, exported.length
    back = exported.find { |parameter| parameter['key'] == 'ikqikbwfw7' }
    assert_equal 9, back['value']
    assert_equal true, back['can_edit']
    setback = exported.find { |parameter| parameter['key'] == 'iwc3l3ib0g' }
    assert_equal false, setback['can_edit']
    assert_equal 'needs_rule', setback['status']
  end

  def test_unchecked_parameter_is_hidden_but_can_still_be_calculated
    data = samples
    rule = Core.learn_module(data)
    Core.set_exposed_parameters!(rule, ['ikqikbwfw7'])

    assert_equal 18, Core.plan(rule, data.last, 'ba4ulq2qnw' => 18)['target']['ba4ulq2qnw']
    plan = Core.plan(rule, data.last, 'ikqikbwfw7' => 9)
    assert_in_delta 17.6, plan['target']['ba4ulq2qnw'], 0.001
    assert_equal 9, plan['target']['ikqikbwfw7']
  end

  def test_empty_selection_is_preserved_and_legacy_defaults_remain_compatible
    rule = Core.learn_module(samples)
    Core.set_exposed_parameters!(rule, [])
    copy = Core.rule!(JSON.parse(JSON.generate(rule)))
    assert_empty copy['exposed_parameter_keys']
    assert_empty Core.exposed_parameters(copy)
    copy.delete('exposed_parameter_keys')
    Core.rule!(copy)
    assert_equal copy['rules'].keys.sort, copy['exposed_parameter_keys'].sort
  end

  def test_unknown_or_duplicate_exposed_keys_are_rejected
    rule = Core.learn_module(samples)

    assert_raises(Core::Error) { Core.set_exposed_parameters!(rule, ['foreign']) }
    assert_raises(Core::Error) { Core.set_exposed_parameters!(rule, %w[ikqikbwfw7 ikqikbwfw7]) }
    rule['exposed_parameter_keys'] = ['foreign']
    assert_raises(Core::Error) { Core.rule!(rule) }
  end
end
