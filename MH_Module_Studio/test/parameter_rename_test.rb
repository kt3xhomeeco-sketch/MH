# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioParameterRenameTest < Minitest::Test
  Studio = MH::ModuleStudio
  Core = Studio::Core
  Parametric = Studio::Parametric

  def setup
    @snapshot = JSON.parse(File.read(File.join(__dir__, 'fixtures/readable_nested_dc.json'), encoding: 'UTF-8'))
    @rule = Studio::StudioCalculation.build_system([@snapshot])
    @brace = @snapshot['parts'].find { |part| part['name'] == 'Giằng Trước' }['key']
  end

  def custom(id, symbol, value, formula = '')
    { 'id' => "custom:#{id}", 'binding' => nil, 'name' => symbol, 'symbol' => symbol,
      'category' => 'dimension', 'unit' => 'mm', 'value' => value, 'formula' => formula, 'exported' => true }
  end

  def test_renaming_updates_generated_and_manual_detail_cells_and_preserves_geometry
    rule = Parametric.edit_part_formula(@rule, @brace, 'lenz', 'giang + 10')
    before_rule = JSON.generate(rule)
    before_snapshot = JSON.generate(@snapshot)
    expected = Core.plan(rule, @snapshot, Parametric.targets(rule))
    rows = Parametric.variables(rule)
    rows.find { |row| row['binding'] == 'giang' }['symbol'] = 'CaoGiang'
    rows.find { |row| row['binding'] == 'dayvan' }['symbol'] = 'T'
    renamed = Parametric.edit_variables(rule, rows)
    assert_equal 'CaoGiang + 10', renamed.dig('part_formulas', @brace, 'lenz')
    sheet = Parametric.sheet(renamed, @snapshot)
    assert_equal 'CaoGiang + 10', sheet['parts'].find { |part| part['key'] == @brace }['expressions'][2]['text']
    assert_equal 'T', sheet['parts'].find { |part| part['name'] == 'Hông Trái' }['expressions'][0]['text']
    saved = Core.rule!(JSON.parse(JSON.generate(renamed)))
    actual = Core.plan(saved, @snapshot, Parametric.targets(saved))
    assert_equal expected['parts'], actual['parts']
    assert_equal before_rule, JSON.generate(rule)
    assert_equal before_snapshot, JSON.generate(@snapshot)
    assert_equal rule.dig('formula_engine', 'attribute_program'), renamed.dig('formula_engine', 'attribute_program')
  end

  def test_custom_variable_and_bound_input_dependencies_follow_renamed_identity
    rows = Parametric.variables(@rule) + [custom('base', 'co_so', 60), custom('offset', 'bu_them', 10)]
    rows.find { |row| row['binding'] == 'giang' }['formula'] = 'co_so + bu_them'
    rule = Parametric.edit_variables(@rule, rows)
    rule = Parametric.edit_part_formula(rule, @brace, 'lenz', 'co_so + bu_them')
    rows = Parametric.variables(rule).reverse
    rows.find { |row| row['id'] == 'custom:base' }['symbol'] = 'nen'
    rows.find { |row| row['id'] == 'custom:offset' }['symbol'] = 'them'
    renamed = Parametric.edit_variables(rule, rows)
    assert_equal 'nen + them', Parametric.variables(renamed).find { |row| row['binding'] == 'giang' }['formula']
    assert_equal 'nen + them', renamed.dig('part_formulas', @brace, 'lenz')
    assert_in_delta 70, Parametric.targets(renamed)['giang'], 0.001
    assert_equal Core.plan(rule, @snapshot, Parametric.targets(rule))['parts'], Core.plan(renamed, @snapshot, Parametric.targets(renamed))['parts']
  end

  def test_simultaneous_custom_symbol_swap_is_single_pass_and_case_insensitive
    rows = Parametric.variables(@rule) + [custom('a', 'a', 60), custom('b', 'b', 10)]
    rows.find { |row| row['binding'] == 'giang' }['formula'] = 'A + b'
    rule = Parametric.edit_variables(@rule, rows)
    rule = Parametric.edit_part_formula(rule, @brace, 'lenz', 'a + B')
    rows = Parametric.variables(rule)
    rows.find { |row| row['id'] == 'custom:a' }['symbol'] = 'b'
    rows.find { |row| row['id'] == 'custom:b' }['symbol'] = 'a'
    renamed = Parametric.edit_variables(rule, rows)
    assert_equal 'b + a', Parametric.variables(renamed).find { |row| row['binding'] == 'giang' }['formula']
    assert_equal 'b + a', renamed.dig('part_formulas', @brace, 'lenz')
    assert_in_delta 70, Parametric.targets(renamed)['giang'], 0.001
  end

  def test_reference_rewriter_preserves_functions_numbers_similar_names_and_local_fields
    expression = 'IF(t>0, t + thickness + parent!T + Module!t, 1e3 + Self!t + Module.LenX + Module!LenX)'
    actual = Studio::ParameterRename.expression(expression, { 't' => 'Van', 'lenx' => 'W', 'e3' => 'bad', 'if' => 'bad' }, detail: true)
    assert_equal 'IF(Van>0, Van + thickness + parent!Van + Module!Van, 1e3 + Self!t + Module.LenX + Module!LenX)', actual
    assert_equal '"t" + \'t\' + Van', Studio::ParameterRename.expression('"t" + \'t\' + t', { 't' => 'Van' })
    rule = Parametric.edit_part_formula(@rule, @brace, 'lenz', 'Parent!giang + 10')
    rows = Parametric.variables(rule)
    rows.find { |row| row['binding'] == 'giang' }['symbol'] = 'Cao'
    renamed = Parametric.edit_variables(rule, rows)
    assert_equal 'Parent!Cao + 10', renamed.dig('part_formulas', @brace, 'lenz')
    assert_equal Core.plan(rule, @snapshot, {})['parts'], Core.plan(renamed, @snapshot, {})['parts']
  end

  def test_invalid_or_duplicate_symbols_leave_rule_and_draft_unchanged
    rule = Parametric.edit_part_formula(@rule, @brace, 'lenz', 'giang + 10')
    %w[dayvan bad-name IF].each do |symbol|
      rows = Parametric.variables(rule)
      rows.find { |row| row['binding'] == 'giang' }['symbol'] = symbol
      before = [JSON.generate(rule), JSON.generate(rows)]
      assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
      assert_equal before, [JSON.generate(rule), JSON.generate(rows)]
    end
  end

  def test_display_name_change_does_not_rename_formula_symbol
    rule = Parametric.edit_part_formula(@rule, @brace, 'lenz', 'giang + 10')
    rows = Parametric.variables(rule)
    rows.find { |row| row['binding'] == 'giang' }['name'] = 'Giằng mới'
    renamed = Parametric.edit_variables(rule, rows)
    assert_equal 'giang + 10', renamed.dig('part_formulas', @brace, 'lenz')
    assert_equal 'Giằng mới', Parametric.variables(renamed).find { |row| row['binding'] == 'giang' }['name']
  end

  def test_conditional_generated_detail_formula_keeps_a_mixed_case_new_symbol
    node = @snapshot['dc_graph']['nodes'].find { |entry| entry['part_key'] == @brace }
    node = @snapshot['dc_graph']['nodes'].find { |entry| entry['id'] == node['parent_id'] }
    node['attributes']['_lenz_formula'] = 'IF(parent!giang > 0, parent!giang, 1)'
    rule = Studio::StudioCalculation.build_system([@snapshot])
    rows = Parametric.variables(rule)
    rows.find { |row| row['binding'] == 'giang' }['symbol'] = 'CaoGiang'
    renamed = Parametric.edit_variables(rule, rows)
    sheet = Parametric.sheet(renamed, @snapshot)
    cell = sheet['parts'].find { |part| part['key'] == @brace }['expressions'][2]
    assert_equal 'att', cell['kind']
    assert_includes cell['text'], 'CaoGiang'
    assert_match(/if\(/i, cell['text'])
    assert_equal rule.dig('formula_engine', 'attribute_program'), renamed.dig('formula_engine', 'attribute_program')
  end
end
