# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'

class ModuleStudioRuleSystemTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  System = MH::ModuleStudio::RuleSystem

  def test_ordinary_cabinet_thickness_contact_and_current_envelope
    source = StudioFixtures.cabinet(18)
    before = JSON.generate(source)
    rule = System.build(source)
    assert_equal 2, rule['parameters'].length
    assert(rule['constraints'].any? { |c| c['type'] == 'contact' && c['face']['part'] == 'left' && c['other']['part'] == 'bottom' })
    plan = Core.plan(rule, source, 'thickness_1' => 20)
    parts = plan['parts'].to_h { |p| [p['key'], p] }
    assert_in_delta 20, parts['bottom']['bounds'][0][0], 0.001
    assert_in_delta 780, parts['bottom']['bounds'][1][0], 0.001
    assert_in_delta 20, Core.dimensions(parts['bottom']['bounds'])[2], 0.001
    assert_equal source['envelope'], Core.union(plan['parts'])
    assert_equal before, JSON.generate(source)
    stretched = StudioFixtures.cabinet(18, width: 1100)
    plan = Core.plan(rule, stretched, 'thickness_1' => 20)
    assert_in_delta 1080, plan['parts'].find { |p| p['key'] == 'bottom' }['bounds'][1][0], 0.001
    next_state = source.merge('parts' => plan['parts'], 'envelope' => plan['envelope'])
    assert_in_delta 22, Core.plan(rule, next_state, 'thickness_1' => 22)['target']['thickness_1'], 0.001
  end

  def test_separated_and_edge_only_faces_are_not_contacts
    source = StudioFixtures.cabinet(18)
    source['parts'] = source['parts'].select { |p| %w[left bottom].include?(p['key']) }
    source['parts'].last['bounds'][0][0] += 1
    source['envelope'] = Core.union(source['parts'])
    assert_empty(System.build(source)['constraints'].select { |c| c['type'] == 'contact' })
  end

  def test_standalone_panel_thickness_is_an_output_with_explicit_anchor
    source = StudioFixtures.cabinet(18)
    source['parts'] = [source['parts'].find { |part| part['key'] == 'left' }]
    source['envelope'] = Core.union(source['parts'])
    %w[low high center].each do |anchor|
      rule = System.build(source)
      driver = rule['constraints'].find { |entry| entry['type'] == 'thickness' }
      rule = System.edit(rule, driver.merge('anchor' => anchor))
      current = Core.copy_data(source)
      [20, 17.6, 22, 18].each do |value|
        plan = Core.plan(rule, current, driver['parameter'] => value)
        bounds = plan['parts'].first['bounds']
        assert_in_delta value, Core.dimensions(bounds)[0], 0.001
        assert_equal Core.dimensions(source['envelope'])[1..2], Core.dimensions(bounds)[1..2]
        expected = anchor == 'low' ? bounds[0][0] : anchor == 'high' ? bounds[1][0] : bounds.sum { |p| p[0] } / 2.0
        original = anchor == 'low' ? 0 : anchor == 'high' ? 18 : 9
        assert_in_delta original, expected, 0.001
        current = current.merge('parts' => plan['parts'], 'envelope' => plan['envelope'])
      end
      fixed = System.edit(rule, System.constraint('fix', 'manual', face: System.face('left', 0, anchor == 'low' ? 1 : 0), gap: 0))
      assert_raises(Core::Error) { Core.plan(fixed, source, driver['parameter'] => 20) }
    end
  end

  def test_conflict_and_unverified_panel_rejected
    source = StudioFixtures.cabinet(18)
    rule = System.build(source)
    fix = System.constraint('fix', 'manual', face: System.face('left', 0, 1), gap: 0)
    edited = System.edit(rule, fix)
    assert_match(/xung đột/, assert_raises(Core::Error) { Core.plan(edited, source, 'thickness_1' => 20) }.message)
    source['parts'].first['box_verified'] = false
    assert_match(/xác minh/, assert_raises(Core::Error) { Core.plan(rule, source, 'thickness_1' => 20) }.message)
  end

  def test_att_uses_same_system_and_formula_priority_after_roundtrip
    source = FormulaFixtures.snapshot
    engine = Core.learn_module([source])
    rule = Core.rule!(JSON.parse(JSON.generate(System.build(source, engine))))
    assert(rule['constraints'].any? { |c| c['type'] == 'formula' && c['translated'] })
    assert(rule['constraints'].select { |c| c['type'] == 'contact' }.none? { |c| c['drive'] })
    plan = Core.plan(rule, source, 's' => 20, 'b' => 10)
    top = plan['parts'].find { |p| p['key'] == 'top' }
    assert_in_delta 170, Core.dimensions(top['bounds'])[1], 0.001
    current = source.merge('parts' => plan['parts'], 'dc_inputs' => {}, 'parameter_values' => plan['target'])
    second = Core.plan(rule, current, 's' => 21)
    assert_in_delta 169, Core.dimensions(second['parts'].find { |p| p['key'] == 'top' }['bounds'])[1], 0.001
    Core.set_exposed_parameters!(rule, ['t'])
    assert_equal 22, Core.plan(rule, current, 's' => 22)['target']['s']
    assert_equal ['t'], (Core.exposed_parameters(rule).map { |p| p['key'] })
  end

  def test_manual_between_and_center_and_invalid_references
    source = StudioFixtures.cabinet(18)
    rule = System.build(source)
    between = System.constraint('between', 'manual', face: System.face('shelf', 0, 0),
                                other: System.face('left', 0, 1), third: System.face('right', 0, 0), gap: 0, gap2: 0)
    rule = System.edit(rule, between)
    assert_equal Core::FORMAT, System.edit(rule, nil, remove: between['id'])['format']
    assert_in_delta 760, Core.dimensions(Core.plan(rule, source, 'thickness_1' => 20)['parts'].find { |p| p['key'] == 'shelf' }['bounds'])[0], 0.001
    center = System.constraint('center', 'manual', face: System.face('shelf', 2, 0),
                               other: System.face('bottom', 2, 1), third: System.face('top', 2, 0), gap: 0)
    rule = System.edit(rule, center)
    assert_in_delta 360, Core.plan(rule, source, 'thickness_1' => 20)['parts'].find { |p| p['key'] == 'shelf' }['bounds'].sum { |p| p[2] } / 2, 0.001
    between['other']['part'] = 'missing'
    assert_raises(Core::Error) { System.edit(rule, between) }
  end

  def test_sparse_solver_conflicting_cycle
    solver = MH::ModuleStudio::PlaneSolver
    rows = [[{ 0 => 1.0, 1 => -1.0 }, 2.0, 'A'], [{ 1 => 1.0, 2 => -1.0 }, 3.0, 'B'], [{ 0 => 1.0, 2 => -1.0 }, 7.0, 'Cycle']]
    assert_raises(Core::Error) { solver.solve(rows, [0.0, 0.0, 0.0]) }
    assert_raises(Core::Error) { solver.solve([[{ 0 => 1.0 }, 0.0, 'Fixed'], [{ 0 => 1.0 }, 0.1, 'Small conflict']], [0.0]) }
  end

  def test_manual_att_gap_override_remains_stable_across_repeated_updates
    source = FormulaFixtures.snapshot
    rule = System.build(source, Core.learn_module([source]))
    contact = System.constraint('offset', 'manual', face: System.face('back', 1, 0), other: System.face('top', 1, 1), gap: 0, drive: false)
    manual = contact.merge('gap' => 2.0, 'drive' => true)
    rule = System.edit(rule, manual)
    plan = Core.plan(rule, source, 's' => 20)
    top = plan['parts'].find { |p| p['key'] == 'top' }
    assert_in_delta 170, Core.dimensions(top['bounds'])[1], 0.001
    current = source.merge('parts' => plan['parts'], 'dc_inputs' => {}, 'parameter_values' => plan['target'])
    second = Core.plan(rule, current, 's' => 21)
    assert_in_delta 169, Core.dimensions(second['parts'].find { |p| p['key'] == 'top' }['bounds'])[1], 0.001
  end

  def test_inactive_thickness_does_not_poison_later_parameter_measurement
    source = StudioFixtures.cabinet(18)
    rule = System.build(source)
    shelf_rule = rule['constraints'].find { |c| c['type'] == 'thickness' && c['face']['part'] == 'shelf' }
    rule = System.edit(rule, shelf_rule.merge('enabled' => false))
    plan = Core.plan(rule, source, 'thickness_1' => 20)
    assert_in_delta 18, Core.dimensions(plan['parts'].find { |p| p['key'] == 'shelf' }['bounds'])[2], 0.001
    current = source.merge('parts' => plan['parts'])
    assert_equal 22, Core.plan(rule, current, 'thickness_1' => 22)['target']['thickness_1']
  end
end
