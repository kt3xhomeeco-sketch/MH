# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'

class ModuleStudioPositionRulesTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  System = MH::ModuleStudio::RuleSystem

  def sample
    JSON.parse(File.read(File.join(__dir__, 'fixtures', 'readable_nested_dc.json'), encoding: 'UTF-8'))
  end

  def rear(rule)
    rule['constraints'].find { |c| c['type'] == 'position' && c['measure'] == 'distance' && c['face']['part'].include?('giằng sau') && c['face']['axis'] == 1 && c['face']['side'] == 1 }
  end

  def test_rear_brace_offset_uses_exact_att_sum_and_side_edge
    source = sample
    rule = System.build(source, Core.learn_module([source]))
    entry = rear(rule)
    refute_nil entry
    assert entry['other']['part'].include?('hông trái')
    assert_equal 1, entry['other']['side']
    assert_equal({ 'constant' => 0.0, 'coefficients' => { 'hauday' => 1.0, 'luihau' => 1.0 } }, entry['expression'])
    refute entry['drive']
    assert_equal 'dc_attributes', entry['source']
    data = source['parts'].to_h { |p| [p['key'], p['bounds']] }
    gap = data[entry['other']['part']][1][1] - data[entry['face']['part']][1][1]
    assert_in_delta 26, gap, 0.001
    planned = Core.plan(rule, source, 'hauday' => 10)
    data = planned['parts'].to_h { |p| [p['key'], p['bounds']] }
    assert_in_delta 28, data[entry['other']['part']][1][1] - data[entry['face']['part']][1][1], 0.001
    assert_equal source['envelope'], planned['envelope']
  end

  def test_dimensions_and_top_alignment_are_exact_not_perturbation_fit
    source = sample
    rule = System.build(source, Core.learn_module([source]))
    rows = rule['constraints'].select { |c| c['type'] == 'position' && c['face']['part'].include?('giằng sau') }
    assert_equal 9, rows.length
    height = rows.find { |c| c['measure'] == 'dimension' && c['face']['axis'] == 2 }
    assert_equal({ 'giang' => 1.0 }, height['expression']['coefficients'])
    top = rows.find { |c| c['measure'] == 'distance' && c['face']['axis'] == 2 && c['face']['side'] == 1 }
    assert_equal({ 'constant' => 0.0, 'coefficients' => {} }, top['expression'])
  end

  def test_conditional_expression_stays_unsimplified_but_other_axes_work
    source = FormulaFixtures.snapshot
    rule = System.build(source, Core.learn_module([source]))
    rows = rule['constraints'].select { |c| c['type'] == 'position' && c['face']['part'] == 'top' && c['measure'] == 'dimension' }
    assert_nil rows.find { |c| c['face']['axis'] == 1 }['expression']
    assert_equal({ '@lenx' => 1.0, 't' => -2.0 }, rows.find { |c| c['face']['axis'] == 0 }['expression']['coefficients'])
  end

  def test_ordinary_geometry_remains_measured_and_old_rules_gain_descriptions
    source = StudioFixtures.cabinet(18)
    rule = System.build(source)
    entries = rule['constraints'].select { |c| c['type'] == 'position' }
    assert_equal 54, entries.length
    assert(entries.all? { |c| !c['drive'] && c['source'] == 'geometry' && c['expression'].nil? })
    old = JSON.parse(JSON.generate(rule))
    old.delete('position_rules_version')
    old['constraints'].reject! { |c| c['type'] == 'position' }
    Core.rule!(old)
    assert_equal 54, (old['constraints'].count { |c| c['type'] == 'position' })
    assert_raises(Core::Error) { System.edit(rule, entries.first) }
    assert_raises(Core::Error) { System.edit(rule, nil, remove: entries.first['id']) }
  end
end
