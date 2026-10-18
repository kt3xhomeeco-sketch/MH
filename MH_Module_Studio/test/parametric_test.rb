# encoding: UTF-8
require 'minitest/autorun'
require_relative '../parametric'
require_relative 'fixtures'

class ModuleStudioParametricTest < Minitest::Test
  Core = MH::ModuleStudio::Core
  System = MH::ModuleStudio::RuleSystem
  Parametric = MH::ModuleStudio::Parametric

  def source
    JSON.parse(File.read(File.join(__dir__, 'fixtures', 'readable_nested_dc.json'), encoding: 'UTF-8'))
  end

  def test_all_scopes_and_dynamic_root_and_brace_values_are_converted
    snapshot = source
    leaf = snapshot['dc_graph']['nodes'].find { |node| node['part_key'] }
    leaf['attributes'].merge!('material' => 'MDF.18', '_material_formula' => '"MDF.18"')
    rule = System.build(snapshot, Core.learn_module([snapshot]))
    before = JSON.generate(snapshot)
    rows = Parametric.describe(rule, snapshot)
    assert_operator rows.length, :>, 30
    assert(rows.any? { |r| !r['node_id'].empty? && r['part_key'] })
    assert(rows.any? { |r| r['path'] == 'khung_hau' && r['key'] == 'x' })
    assert_in_delta 10.6, rows.find { |r| r['path'] == 'khung_hau' && r['key'] == 'x' }['value'], 0.001
    assert_in_delta 600, rows.find { |r| r['node_id'].empty? && r['key'] == 'lenx' }['value'], 0.001
    changed = Parametric.describe(rule, snapshot, { 'dayvan' => 20, 'giang' => 100 })
    assert_in_delta 12, changed.find { |r| r['path'] == 'khung_hau' && r['key'] == 'x' }['value'], 0.001
    brace = changed.select { |r| r['path'] == 'noc1' && r['key'] == 'lenz' }
    assert_equal 2, brace.length
    assert_equal 2, brace.map { |r| r['node_id'] }.uniq.length
    assert(brace.all? { |r| (r['value'] - 100).abs < 0.001 && r['formula'].downcase.include?('giang') })
    assert_equal before, JSON.generate(snapshot)
    assert(rows.all? { |r| r['editable'] == false && !r['key'].start_with?('_') })
  end

  def bundle
    snapshot = source
    System.build(snapshot, Core.learn_module([snapshot]))
  end

  def custom(symbol = 'co_so', value = 19.4)
    { 'id' => 'custom:base', 'binding' => nil, 'name' => 'Ván cơ sở', 'symbol' => symbol,
      'category' => 'dimension', 'unit' => 'mm', 'value' => value, 'formula' => '', 'exported' => true }
  end

  def test_custom_variable_drives_bound_att_input_and_preserves_envelope
    snapshot = source
    rule = bundle
    before = JSON.generate(rule)
    rows = Parametric.variables(rule)
    rows << custom
    board = rows.find { |r| r['binding'] == 'dayvan' }
    board.merge!('name' => 'Ván thùng', 'symbol' => 'T', 'formula' => 'co_so + 0.6')
    edited = Parametric.edit_variables(rule, rows)
    assert_equal before, JSON.generate(rule)
    assert_in_delta 20, Parametric.targets(edited)['dayvan'], 0.001
    plan = Core.plan(edited, snapshot, Parametric.targets(edited))
    assert_equal snapshot['envelope'], plan['envelope']
    assert_operator plan['changed_count'], :>, 0
    restored = Core.rule!(JSON.parse(JSON.generate(edited)))
    assert_equal 'T', Parametric.variables(restored).find { |r| r['binding'] == 'dayvan' }['symbol']
    assert_in_delta 20, Parametric.targets(restored)['dayvan'], 0.001
    exposed = Core.exposed_parameters(restored, 'dayvan' => 20)
    assert_equal 'Ván thùng', exposed.find { |r| r['key'] == 'dayvan' }['label']
    assert_equal 'T', exposed.find { |r| r['key'] == 'dayvan' }['symbol']
    assert_equal false, exposed.find { |r| r['key'] == 'dayvan' }['can_edit']
    assert_in_delta 19.4, exposed.find { |r| r['key'] == 'co_so' }['value'], 0.001
    Core.set_exposed_parameters!(restored, ['hauday'])
    assert_equal restored['parameters'].select { |p| p['editable'] }.map { |p| p['key'] }.sort, Parametric.targets(restored).keys.sort
    assert_in_delta 20, Parametric.targets(restored)['dayvan'], 0.001
    assert_equal false, Parametric.variables(restored).find { |r| r['binding'] == 'dayvan' }['exported']
  end

  def test_rejects_duplicate_symbols_cycles_missing_references_and_deleting_att
    rule = bundle
    rows = Parametric.variables(rule)
    rows << custom('DAYVAN')
    assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
    rows = Parametric.variables(rule) + [custom]
    rows.last['formula'] = 'co_so + 1'
    assert_match(/vòng lặp/, assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }.message)
    rows.last['formula'] = 'da_xoa + 1'
    assert_match(/không tồn tại/, assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }.message)
    rows = Parametric.variables(rule)
    rows.shift
    assert_match(/Không thể bỏ/, assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }.message)
  end

  def test_referenced_custom_cannot_be_deleted_and_alias_does_not_replace_binding
    rule = bundle
    rows = Parametric.variables(rule) + [custom]
    rows.find { |r| r['binding'] == 'dayvan' }['formula'] = 'co_so + 0.6'
    edited = Parametric.edit_variables(rule, rows)
    assert_raises(Core::Error) { Parametric.edit_variables(edited, rows[0...-1]) }
    rows.last['symbol'] = 'if'
    assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
    rows = Parametric.variables(rule) + [custom('lenx')]
    assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
    rows.last['symbol'] = 'co_so'
    rows.last['unit'] = 'cm'
    assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
  end

  def test_text_categories_are_data_and_copy_count_boolean_and_injection_are_checked
    rule = bundle
    rows = Parametric.variables(rule) + [custom]
    rows.last.merge!('category' => 'information', 'value' => '<img src=x onerror=alert(1)>', 'unit' => '')
    edited = Parametric.edit_variables(rule, rows)
    assert_equal rows.last['value'], Parametric.variables(edited).last['value']
    rows.last.merge!('category' => 'copies', 'value' => 2.5)
    assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
    rows.last.merge!('category' => 'boolean', 'value' => 2)
    assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
    rows.last.merge!('category' => 'number', 'value' => 1, 'formula' => 'Kernel.system(1)')
    assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
    rows.last['formula'] = '1 / 0'
    assert_raises(Core::Error) { Parametric.edit_variables(rule, rows) }
  end

  def test_safe_conditional_formula_and_six_part_columns_follow_preview
    snapshot = source
    rule = bundle
    rows = Parametric.variables(rule) + [custom]
    rows.find { |r| r['binding'] == 'dayvan' }['formula'] = 'IF(co_so > 18, MAX(co_so, 20), 18)'
    edited = Parametric.edit_variables(rule, rows)
    plan = Core.plan(edited, snapshot, Parametric.targets(edited))
    sheet = Parametric.sheet(edited, snapshot, plan)
    assert_equal snapshot['parts'].length, sheet['parts'].length
    assert(sheet['parts'].all? { |p| p['values'].length == 6 && p['formulas'].length == 6 })
    sheet['parts'].each do |part|
      expected = plan['parts'].find { |p| p['key'] == part['key'] }
      assert_equal Core.dimensions(expected['bounds']) + expected['bounds'][0], part['values']
    end
    assert_includes sheet['categories'].keys, 'copies'
    assert_includes sheet['categories'].keys, 'behavior'
  end

  def test_ordinary_group_uses_same_variable_table_and_geometry_solver
    snapshot = StudioFixtures.cabinet(18)
    rule = System.build(snapshot)
    rows = Parametric.variables(rule) + [custom('co_so', 20)]
    board = rows.find { |r| (r['value'] - 18).abs < 0.01 }
    board['formula'] = 'co_so'
    edited = Parametric.edit_variables(rule, rows)
    plan = Core.plan(edited, snapshot, Parametric.targets(edited))
    assert_equal snapshot['envelope'], plan['envelope']
    assert_operator plan['changed_count'], :>, 0
    assert_nil edited['formula_engine']
    assert_equal [], Parametric.sheet(edited, snapshot, plan)['attributes']
  end

  def test_part_cells_show_exact_scoped_variables_and_world_coordinates
    snapshot = source
    rule = bundle
    before = JSON.generate(rule)
    parts = Parametric.sheet(rule, snapshot)['parts'].to_h { |part| [part['name'], part] }
    assert_equal 'dayvan', parts['Hông Trái']['expressions'][0]['text']
    assert_equal 'Module.LenX - 2 * dayvan', parts['Giằng Trước']['expressions'][0]['text']
    assert_equal 'giang', parts['Giằng Trước']['expressions'][2]['text']
    assert_equal 'giang', parts['Giằng Sau']['expressions'][2]['text']
    assert_equal 'Module.LenY - dayvan - hauday - luihau', parts['Giằng Sau']['expressions'][4]['text']
    assert_equal 'dayvan - sauranh', parts['Hậu']['expressions'][3]['text']
    assert_equal 'Module.LenY - hauday - luihau', parts['Hậu']['expressions'][4]['text']
    assert_in_delta 10.6, parts['Hậu']['values'][3], 0.001
    assert_equal '', parts['Đáy']['expressions'][3]['text']
    assert_equal before, JSON.generate(rule)
  end

  def test_part_cells_follow_renamed_symbols_and_preview_values
    snapshot = source
    rule = bundle
    rows = Parametric.variables(rule)
    rows.find { |row| row['binding'] == 'dayvan' }.merge!('symbol' => 'T', 'value' => 20)
    edited = Parametric.edit_variables(rule, rows)
    plan = Core.plan(edited, snapshot, Parametric.targets(edited))
    parts = Parametric.sheet(edited, snapshot, plan)['parts'].to_h { |part| [part['name'], part] }
    assert_equal 'T', parts['Hông Trái']['expressions'][0]['text']
    assert_in_delta 20, parts['Hông Trái']['values'][0], 0.001
    assert_equal 'Module.LenX - 2 * T', parts['Giằng Trước']['expressions'][0]['text']
    assert_in_delta 560, parts['Giằng Trước']['values'][0], 0.001
    assert_equal 'T - sauranh', parts['Hậu']['expressions'][3]['text']
    assert_in_delta 12, parts['Hậu']['values'][3], 0.001
  end

  def test_conditional_att_retains_original_evidence_and_translates_the_condition
    snapshot = source
    rule = bundle
    nodes = rule.dig('formula_engine', 'attribute_program', 'dc_graph', 'nodes')
    node = nodes.find { |entry| !entry['part_key'] && entry['attributes']['_lenx_formula'] }
    child = nodes.find { |entry| entry['parent_id'] == node['id'] && entry['part_key'] }
    node['attributes']['_lenx_formula'] = 'IF(parent!dayvan > 1, parent!dayvan, 1)'
    part = Parametric.sheet(rule, snapshot)['parts'].find { |entry| entry['key'] == child['part_key'] }
    assert_equal 'att', part['expressions'][0]['kind']
    assert_match(/if\(/i, part['expressions'][0]['text'])
    assert_includes part['expressions'][0]['text'], 'dayvan'
    assert_includes part['formulas'][0], 'IF(parent!dayvan > 1, parent!dayvan, 1)'
  end

  def test_own_thickness_rule_names_variable_without_inventing_other_dependencies
    snapshot = StudioFixtures.cabinet(18)
    rule = System.build(snapshot)
    parts = Parametric.sheet(rule, snapshot)['parts']
    entry = rule['constraints'].find { |constraint| constraint['type'] == 'thickness' }
    part = parts.find { |item| item['key'] == entry['face']['part'] }
    row = Parametric.variables(rule).find { |variable| variable['binding'] == entry['parameter'] }
    assert_equal row['symbol'], part['expressions'][entry['face']['axis']]['text']
    assert_equal 'rule', part['expressions'][entry['face']['axis']]['kind']
    assert(parts.flat_map { |item| item['expressions'] }.none? { |cell| cell['kind'] == 'att' })
    assert(parts.flat_map { |item| item['expressions'] }.any? { |cell| cell['kind'] == 'measured' && cell['text'].empty? })
  end
end
