# encoding: UTF-8
require 'minitest/autorun'
require_relative 'fixtures'

class ModuleStudioRuleMigrationTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  System = MH::ModuleStudio::RuleSystem

  def test_scalar_project_keeps_observed_effects_in_common_system
    source = StudioFixtures.samples.last
    legacy = StudioFixtures.rule
    migrated = System.migrate(source, JSON.parse(JSON.generate(legacy)))
    direct = Core.plan(legacy, source, 23)
    unified = Core.plan(migrated, source, 'thickness' => 23)
    assert_equal 'module_rule_system', migrated['kind']
    assert(migrated['constraints'].any? { |c| c['source'] == 'observations' })
    direct['parts'].zip(unified['parts']).each { |a, b| assert Core.bounds_close?(a['bounds'], b['bounds'], 0.001) }
    assert_equal legacy['id'], migrated['id']
  end

  def test_unknown_att_input_remains_visible_read_only
    source = StudioFixtures.cabinet(18)
    source['dc_inputs'] = { 'setback' => 18.0 / 25.4, '_setback_access' => 'TEXTBOX', '_setback_units' => 'MILLIMETERS', '_setback_formlabel' => 'Hậu lùi' }
    rule = System.build(source)
    input = rule['parameters'].find { |p| p['dc_key'] == 'setback' }
    assert_equal 'Hậu lùi', input['label']
    assert_in_delta 18, input['value'], 0.001
    refute input['editable']
    refute_includes rule['exposed_parameter_keys'], input['key']
    assert_raises(Core::Error) { Core.plan(rule, source, input['key'] => 20) }
  end
end
