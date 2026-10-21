# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'
require_relative '../parametric'

class ModuleStudioCoordinateATTTest < Minitest::Test
  Studio = MH::ModuleStudio

  def setup
    @snapshot = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'offset_origin_cabinet.json'), encoding: 'UTF-8'))
    @rule = Studio::RuleSystem.build(@snapshot, Studio::Core.learn_module([@snapshot]))
  end

  def expression_value(text, rule, envelope)
    values = Studio::Parametric.variables(rule).to_h { |row| [row['symbol'].downcase, row['value']] }
    parsed = Studio::DCFormulas::Parser.new(text.gsub(/\bModule\.(lenx|leny|lenz)\b/i, 'Module!\1')).parse
    Studio::Parametric.numeric_expression(parsed) do |scope, key|
      scope == 'module' ? Studio::Core.dimensions(envelope)[%w[lenx leny lenz].index(key)] : values.fetch(key)
    end
  end

  def test_displaced_origin_preserves_att_instead_of_disabling_all_formulas
    top = @snapshot['dc_graph']['nodes'].find { |node| node['name'] == 'Len Nóc Trước' }
    assert_operator top['local_bounds'][0].map(&:abs).max * 25.4, :>, 0.02
    assert_operator @rule['parameters'].count { |param| param['editable'] }, :>=, 12
    assert @rule['formula_engine']
    sheet = Studio::Parametric.sheet(@rule, @snapshot)
    sheet['parts'].reject { |part| @snapshot['parts'].find { |p| p['key'] == part['key'] }['visible'] == false }.each do |part|
      6.times do |index|
        cell = part['expressions'][index]
        refute_empty cell['text'], "#{part['name']}: #{Studio::Parametric::PART_FIELDS[index]}"
        assert_equal 'att', cell['kind']
        assert_in_delta part['values'][index], expression_value(cell['text'], @rule, @snapshot['envelope']), 0.001
      end
    end
    right = sheet['parts'].find { |part| part['name'] == 'Hông Phải' }
    assert_includes right['expressions'][3]['text'], 'Module.LenX'
    assert_equal '0', right['expressions'][5]['text']
    assert_includes right['formulas'][3], 'parent!abh13iq2kv'
  end

  def test_positions_and_translated_cells_recalculate_after_combined_parameter_changes
    rule = @rule
    rows = Studio::Parametric.variables(rule)
    changes = { 'abh13iq2kv' => 20, 'g3dnsrlh5l' => 10, 'h0z7qfyu_8' => 20, 'we8ogzgj1d' => 90 }
    rows.each { |row| row['value'] = changes[row['binding']] if changes.key?(row['binding']) }
    rule = Studio::Parametric.edit_variables(rule, rows)
    plan = Studio::Core.plan(rule, @snapshot, Studio::Parametric.targets(rule))
    sheet = Studio::Parametric.sheet(rule, @snapshot, plan)
    back = plan['parts'].find { |part| part['name'] == 'Hậu' }
    assert_in_delta 12, back['bounds'][0][0], 0.001
    assert_in_delta 532, back['bounds'][0][1], 0.001
    right = plan['parts'].find { |part| part['name'] == 'Hông Phải' }
    assert_in_delta 580, right['bounds'][0][0], 0.001
    sheet['parts'].each do |part|
      next if @snapshot['parts'].find { |p| p['key'] == part['key'] }['visible'] == false
      6.times do |index|
        text = part['expressions'][index]['text']
        refute_empty text
        assert_in_delta part['values'][index], expression_value(text, rule, plan['envelope']), 0.001
      end
    end
    current = @snapshot.merge('parts' => plan['parts'], 'parameter_values' => plan['target'], 'dc_inputs' => {})
    assert_equal 0, Studio::Core.plan(rule, current, {})['changed_count']
    assert Studio::Core.bounds_close?(@snapshot['envelope'], plan['envelope'])
  end

  def test_formula_only_coordinates_are_in_the_attribute_inventory_and_edit_round_trip
    sheet = Studio::Parametric.sheet(@rule, @snapshot)
    row = sheet['parts'].find { |part| part['name'] == 'Hậu' }
    text = row['expressions'][4]['text']
    edited = Studio::Parametric.edit_part_formula(@rule, row['key'], 'y', text)
    plan = Studio::Core.plan(edited, @snapshot, 'g3dnsrlh5l' => 10, 'h0z7qfyu_8' => 20)
    assert_in_delta 532, plan['parts'].find { |part| part['key'] == row['key'] }['bounds'][0][1], 0.001
    assert_equal text, Studio::Core.rule!(JSON.parse(JSON.generate(edited))).dig('part_formulas', row['key'], 'y')
    sample = FormulaFixtures.snapshot
    bundle = Studio::RuleSystem.build(sample, Studio::Core.learn_module([sample]))
    attrs = Studio::Parametric.sheet(bundle, sample)['attributes']
    assert(attrs.any? { |attr| attr['key'] == 'x' && attr['formula'] == 'parent!t' })
  end
end
