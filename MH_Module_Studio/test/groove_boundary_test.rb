# encoding: UTF-8
require 'minitest/autorun'
require_relative 'fixtures'

class ModuleStudioGrooveBoundaryTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  System = MH::ModuleStudio::RuleSystem

  def setup
    @source = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'readable_nested_dc.json'), encoding: 'UTF-8'))
    @rule = System.build(@source, Core.learn_module([@source]))
  end

  def advance(current, requested)
    plan = Core.plan(@rule, current, requested)
    state = current.merge('parts' => plan['parts'], 'parameter_values' => plan['target'], 'dc_inputs' => {})
    assert_equal 0, Core.plan(@rule, state, {})['changed_count'], 'Saved values must still describe the resulting geometry.'
    assert Core.bounds_close?(Core.union(state['parts']), @source['envelope'])
    state
  end

  def test_groove_can_leave_outer_boundary_then_other_parameters_remain_editable
    current = advance(@source, 'dayvan' => 20)
    [20, 0, 8, 20, 0].each do |groove|
      current = advance(current, 'sauranh' => groove)
      back = current['parts'].find { |part| part['name'] == 'Hậu' }
      assert_in_delta 20 - groove, back['bounds'][0][0], 0.001
      assert_in_delta 20 - groove, back['bounds'][0][2], 0.001
      assert_in_delta 580 + groove, back['bounds'][1][0], 0.001
    end
    current = advance(current, 'giang' => 200, 'hauday' => 10, 'luihau' => 20)
    assert_in_delta 470, current['parts'].find { |part| part['name'] == 'Hậu' }['bounds'][0][1], 0.001
  end

  def test_rejected_groove_does_not_poison_next_edit
    current = advance(@source, 'dayvan' => 20, 'sauranh' => 20)
    before = JSON.generate(current)
    assert_match 'phủ bì', assert_raises(Core::Error) { Core.plan(@rule, current, 'sauranh' => 21) }.message
    assert_equal before, JSON.generate(current)
    advance(current, 'sauranh' => 8, 'dayvan' => 22)
  end

  def test_submillimeter_groove_cannot_expand_the_envelope_and_poison_next_edit
    current = advance(@source, 'dayvan' => 20, 'sauranh' => 20)
    before = JSON.generate(current)
    assert_match 'phủ bì', assert_raises(Core::Error) { Core.plan(@rule, current, 'sauranh' => 20.1) }.message
    assert_equal before, JSON.generate(current)
    advance(current, 'sauranh' => 8, 'dayvan' => 20.1)
  end

  def test_manual_exterior_fix_is_still_enforced
    current = advance(@source, 'dayvan' => 20, 'sauranh' => 20)
    back = current['parts'].find { |part| part['name'] == 'Hậu' }
    fix = System.constraint('fix', 'manual', face: System.face(back['key'], 0, 0), gap: 0)
    @rule = System.edit(@rule, fix)
    plan = Core.plan(@rule, current, 'sauranh' => 8)
    assert_in_delta 0, plan['parts'].find { |part| part['key'] == back['key'] }['bounds'][0][0], 0.001
  end

  def test_new_att_collision_is_still_rejected
    current = advance(@source, 'sauranh' => 0)
    before = JSON.generate(current)
    assert_match 'giao vào', assert_raises(Core::Error) { Core.plan(@rule, current, 'giang' => 850) }.message
    assert_equal before, JSON.generate(current)
    advance(current, 'luihau' => 20)
  end

  def test_own_formula_cannot_reuse_imported_overlap_permission
    current = advance(@source, 'sauranh' => 0)
    back = current['parts'].find { |part| part['name'] == 'Hậu' }
    @rule = MH::ModuleStudio::Parametric.edit_part_formula(@rule, back['key'], 'x', '0')
    assert_match 'giao vào', assert_raises(Core::Error) { Core.plan(@rule, current, {}) }.message
  end

  def test_imported_parameter_engine_handles_groove_joint_return_without_rule_wrapper
    engine = Core.learn_module([@source])
    current = @source
    [0, 8, 0, 18.6, 8].each do |groove|
      plan = Core.plan(engine, current, 'sauranh' => groove)
      current = current.merge('parts' => plan['parts'], 'parameter_values' => plan['target'], 'dc_inputs' => {})
      assert_equal 0, Core.plan(engine, current, {})['changed_count']
    end
  end
end
