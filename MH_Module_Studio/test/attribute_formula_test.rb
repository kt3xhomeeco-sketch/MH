# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'

class ModuleStudioAttributeFormulaTest < Minitest::Test
  Core = MH::ModuleStudio::Core

  def test_one_dc_is_enough_and_formulas_have_priority_over_comparison
    data = FormulaFixtures.snapshot
    before = JSON.generate(data)
    rule = Core.learn_module([data])
    assert_equal %w[b s t], rule['rules'].keys.sort
    assert(rule['rules'].values.all? { |entry| entry['rule_source'] == 'dc_attributes' })
    assert(rule['attribute_formulas'].any? { |entry| entry['path'] == 'carrier' && entry['attribute'] == 'y' })
    assert_equal JSON.parse(before), data, 'Reading and compiling must not alter the captured values.'
    plan = Core.plan(rule, data, 's' => 20)
    parts = plan['parts'].to_h { |part| [part['key'], part] }
    assert_in_delta 172, Core.dimensions(parts['top']['bounds'])[1], 0.001
    assert_in_delta 172, parts['back']['bounds'][0][1], 0.001
    assert_in_delta 180, parts['back']['bounds'][1][1], 0.001
    assert_equal data['envelope'], plan['envelope']
  end

  def test_combined_thickness_and_setback_follow_att_and_preserve_envelope
    data = FormulaFixtures.snapshot
    rule = Core.learn_module([data])
    plan = Core.plan(rule, data, 't' => 20, 'b' => 10, 's' => 20)
    top = plan['parts'].find { |part| part['key'] == 'top' }
    assert_equal [560.0, 170.0, 20.0], (Core.dimensions(top['bounds']).map { |value| value.round(6) })
    assert_equal 0, Core.plan(rule, data, {})['changed_count']
  end

  def test_round_trip_and_repeated_trial_edit_without_dc
    data = FormulaFixtures.snapshot
    rule = Core.rule!(JSON.parse(JSON.generate(Core.learn_module([data]))))
    plan = Core.plan(rule, data, 's' => 0)
    trial = data.merge('parts' => plan['parts'], 'dc_inputs' => {}, 'parameter_values' => plan['target'])
    restored = Core.plan(rule, trial, 's' => 18)
    data['parts'].zip(restored['parts']).each do |a, b|
      assert Core.bounds_close?(a['bounds'], b['bounds'], 0.00001)
    end
    assert_raises(Core::Error) { Core.plan(rule, trial.reject { |key, _| key == 'parameter_values' }, 's' => 20) }
  end

  def test_interpreter_recalculates_conditional_and_nonlinear_formulas
    data = FormulaFixtures.snapshot
    data['dc_inputs']['_cut_formula'] = 'if(b>0,b+s*s/1.8,0)'
    rule = Core.learn_module([data])
    plan = Core.plan(rule, data, 's' => 20)
    top = plan['parts'].find { |part| part['key'] == 'top' }
    assert_in_delta 200 - 8 - 20.0 * 20 / 18, Core.dimensions(top['bounds'])[1], 0.001
  end

  def test_opaque_functions_are_reported_and_comparison_is_only_fallback
    data = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'dc_mixed_thickness.json'), encoding: 'UTF-8'))
    graph = FormulaFixtures.snapshot['dc_graph']
    graph['nodes'].first['attributes']['_lenx_formula'] = 'secret_abf()'
    # Use the valid graph/geometry with an opaque function to test rejection.
    opaque = FormulaFixtures.snapshot
    opaque['dc_graph'] = graph
    error = assert_raises(Core::Error) { Core.learn_module([opaque]) }
    assert_match 'secret_abf', error.message
    rule = Core.learn_module(data)
    assert(rule['rules'].values.all? { |entry| entry['rule_source'] == 'observations' })
    assert_match 'Đọc lại module', rule['attribute_diagnostic']
  end

  def test_cycle_missing_reference_code_and_excessive_depth_are_rejected
    %w[parent!missing Kernel.system(1) __send__(1)].each do |formula|
      data = FormulaFixtures.snapshot
      data['dc_graph']['nodes'].first['attributes']['_lenx_formula'] = formula
      assert_raises(Core::Error) { Core.learn_module([data]) }
    end
    data = FormulaFixtures.snapshot
    data['dc_inputs']['_cut_formula'] = 'cut'
    error = assert_raises(Core::Error) { Core.learn_module([data]) }
    assert_match 'tham chiếu vòng', error.message
    parser = MH::ModuleStudio::DCFormulas::Parser
    assert_raises(Core::Error) { parser.new('(' * 50 + '1' + ')' * 50).parse }
  end

  def test_geometry_cache_mismatch_and_visibility_changes_are_not_guessed
    data = FormulaFixtures.snapshot
    data['parts'].find { |part| part['key'] == 'top' }['bounds'][1][1] -= 2
    error = assert_raises(Core::Error) { Core.learn_module([data]) }
    assert_match 'chưa khớp hình học', error.message
    data = FormulaFixtures.snapshot
    data['dc_graph']['nodes'].first['attributes']['_hidden_formula'] = 'if(parent!s>1.9,1,0)'
    data['dc_graph']['nodes'].first['attributes']['_hidden_formulaunits'] = 'CENTIMETERS'
    rule = Core.learn_module([data])
    assert_raises(Core::Error) { Core.plan(rule, data, 's' => 20) }
  end

  def test_scaled_wrappers_and_duplicate_names_use_distinct_parent_ids
    data = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'readable_nested_dc.json'), encoding: 'UTF-8'))
    rule = Core.learn_module([data])
    assert_equal %w[dayvan giang hauday luihau sauranh], rule['rules'].keys.sort
    assert_equal 29, rule['attribute_formulas'].length
    before = data['parts'].find { |part| part['name'] == 'Hậu' }['bounds']
    plan = Core.plan(rule, data, 'luihau' => 20)
    back = plan['parts'].find { |part| part['name'] == 'Hậu' }
    assert_in_delta before[0][1] - 2, back['bounds'][0][1], 0.001
    assert_in_delta before[1][1] - 2, back['bounds'][1][1], 0.001
    assert_equal 2, plan['changed_count'], 'Only the back and rear brace depend on setback in this DC.'
    plan = Core.plan(rule, data, 'dayvan' => 20, 'hauday' => 9, 'luihau' => 20)
    assert_equal 6, plan['changed_count']
    assert Core.bounds_close?(plan['envelope'], data['envelope'])
  end

  def test_rotation_mirror_invalid_parent_and_program_tampering_are_rejected
    data = FormulaFixtures.snapshot
    data['dc_graph']['nodes'].first['transform'][0] = -1
    assert_raises(Core::Error) { Core.learn_module([data]) }
    data = FormulaFixtures.snapshot
    data['dc_graph']['nodes'].first.merge!('id' => 'left', 'parent_id' => 'missing')
    assert_raises(Core::Error) { Core.learn_module([data]) }
    rule = Core.learn_module([FormulaFixtures.snapshot])
    rule['attribute_program']['dc_graph']['nodes'].first['part_key'] = 'foreign'
    assert_raises(Core::Error) { Core.rule!(rule) }
  end

  def test_dc_inputs_can_be_captured_without_choosing_one_geometric_thickness_group
    data = FormulaFixtures.snapshot
    # Two different groups each contain two panels: no geometric majority.
    data['parts'].reject! { |part| part['key'] == 'top' }
    data['parts'].find { |part| part['key'] == 'bottom' }['bounds'][1][2] = 8
    assert_raises(Core::Error) { Core.use_measured_parameter!(data) }
    Core.capture_parameter!(data)
    assert_equal 'dc_parameter_set', data['parameter_source']['kind']
    assert_equal %w[b t], data['parameter_source']['dc_keys'].sort
  end

  def test_formula_rules_cannot_be_loaded_without_the_module_program
    rule = Core.learn_module([FormulaFixtures.snapshot])
    assert_raises(Core::Error) { Core.rule!(rule['rules']['s']) }
  end

  def test_bridge_retains_intermediate_attributes_and_instance_override
    original = FormulaFixtures.snapshot
    definitions = {}
    nodes = original['dc_graph']['nodes']
    nodes.each do |node|
      children = nodes.select { |entry| entry['path'][0...-1] == node['path'] }.map do |child|
        { 'definition' => child['id'], 'name' => child['name'], 'transform' => child['transform'] }
      end
      definitions[node['id']] = { 'name' => node['name'], 'hasGeometry' => !!node['part_key'], 'bounds' => node['local_bounds'],
                                 'nodes' => children, 'faceCount' => node['part_key'] ? 6 : 0, 'edgeCount' => node['part_key'] ? 12 : 0,
                                 'attributes' => node['attributes'].to_h { |key, value| ["dynamic_attributes/#{key}", value] } }
    end
    top_level = nodes.select { |node| node['path'].length == 1 }.map do |node|
      { 'definition' => node['id'], 'name' => node['name'], 'transform' => node['transform'] }
    end
    carrier = top_level.find { |node| node['definition'] == 'carrier' }
    carrier['attributes'] = { 'dynamic_attributes/_y_formula' => 'parent!leny-parent!s-parent!b' }
    definitions['carrier']['attributes']['dynamic_attributes/_y_formula'] = 'bad_definition_formula()'
    definitions['module'] = { 'hasGeometry' => false, 'nodes' => top_level,
                              'attributes' => original['dc_inputs'].to_h { |key, value| ["dynamic_attributes/#{key}", value] } }
    definitions['root'] = { 'hasGeometry' => false, 'nodes' => [{ 'definition' => 'module', 'name' => 'Tủ' }] }
    read = MH::ModuleStudio::Reader.from_bridge({ 'root' => 'root', 'definitions' => definitions }, label: 'Bridge test', parameter: nil)
    group = read['dc_graph']['nodes'].find { |node| node['name'] == 'Group hậu' }
    leaf = read['dc_graph']['nodes'].find { |node| node['path'][0...-1] == group['path'] }
    assert_equal group['id'], leaf['parent_id']
    assert_equal 'parent!leny-parent!s-parent!b', group['attributes']['_y_formula']
    assert_equal %w[b s t], Core.learn_module([read])['rules'].keys.sort
    refute(read['parts'].any? { |part| part['box_verified'] })
  end
end
