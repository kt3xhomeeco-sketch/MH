# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'
require_relative '../library_catalog'

class ModuleStudioDCCopiesTest < Minitest::Test
  S = MH::ModuleStudio

  def captured
    JSON.parse(File.read(File.join(__dir__,'fixtures/owned-plinth-copies.json'),encoding:'UTF-8'))
  end

  def current(data,plan)
    data = S::Core.copy_data(data)
    data.merge!('parts'=>plan['parts'],'envelope'=>plan['envelope'],'dc_inputs'=>{},'parameter_values'=>plan['target'])
    data['dc_graph'] = plan['copy_graph'] if plan['copy_graph']
    S::DCVisibility.apply_metadata!(data,plan['visibility_updates'])
    data
  end

  def test_existing_owned_rule_unlocks_count_without_changing_symbol_visibility_or_source
    data = captured; original = JSON.generate(data)
    rule = S::Core.rule!(S::Core.copy_data(data['rule']))
    row = S::Parametric.variables(rule).find { |v| v['binding']=='b6sochanphu' }
    assert S::DCCopies.enabled?(rule)
    assert_equal 'copies',row['category']
    assert_equal 'b6sochanphu',row['symbol']
    refute row['exported']
    assert rule['parameters'].find { |p| p['key']=='b6sochanphu' }['editable']
    assert_equal original,JSON.generate(data)
  end

  def test_repeated_increase_decrease_reuses_keys_and_evaluates_exact_copy_spacing
    data = captured; rule = S::Core.rule!(data['rule']); snapshot = data['snapshot']
    original_bounds = snapshot['envelope']
    [7,3,8,5,2,7].each do |count|
      plan = S::Core.plan(rule,snapshot,'b6sochanphu'=>count)
      assert_equal count+5,plan['parts'].length
      assert S::Core.bounds_close?(original_bounds,plan['envelope'],0.001)
      parts = plan['parts'].reject { |p| %w[part:0001 part:0002 part:0004 part:0005 part:0006].include?(p['key']) }.sort_by { |p| p['bounds'][0][0] }
      assert_equal count,parts.length
      parts.each_with_index do |part,index|
        assert_in_delta((700-17.6)/(count-1)*index,part['bounds'][0][0],0.000001)
        assert_in_delta 17.6,S::Core.dimensions(part['bounds'])[0],0.000001
      end
      snapshot = current(snapshot,plan)
      assert_equal 0,S::Core.plan(rule,snapshot,{})['changed_count']
      sheet = S::Parametric.sheet(rule,snapshot)
      assert_equal plan['parts'].length,sheet['parts'].length
    end
  end

  def test_parametric_count_edit_visibility_and_symbol_rename_feed_real_geometry
    data = captured; rule = S::Core.rule!(data['rule'])
    rows = S::Parametric.variables(rule)
    count = rows.find { |row| row['binding']=='b6sochanphu' }
    count.merge!('symbol'=>'N','value'=>7,'exported'=>true)
    edited = S::Parametric.edit_variables(rule,rows)
    plan = S::Core.plan(edited,data['snapshot'],S::Parametric.targets(edited))
    assert_equal 2,plan['copy_add'].length
    assert_equal 7,S::OptionsParameters.rows(edited,plan['target']).find { |row| row['symbol']=='N' }['value']
    count['exported'] = false
    hidden = S::Parametric.edit_variables(rule,rows)
    assert_equal plan['parts'],S::Core.plan(hidden,data['snapshot'],S::Parametric.targets(hidden))['parts']
    rows.find { |row| row['binding']=='b6sochanphu' }['value'] = 3.5
    assert_raises(S::Core::Error) { S::Parametric.edit_variables(rule,rows) }
  end

  def test_bad_counts_damaged_geometry_and_new_collisions_are_rejected_without_mutation
    data = captured; original = JSON.generate(data)
    rule = S::Core.rule!(S::Core.copy_data(data['rule']))
    [1,0,-1,3.5,102].each do |count|
      assert_raises(S::Core::Error) { S::Core.plan(rule,data['snapshot'],'b6sochanphu'=>count) }
    end
    broken = S::Core.copy_data(data['snapshot']); broken['parts'].last['bounds'][0][0] += 5
    assert_raises(S::Core::Error) { S::Core.plan(rule,broken,'b6sochanphu'=>7) }
    assert_raises(S::Core::Error) { S::Core.plan(rule,data['snapshot'],'b6sochanphu'=>100) }
    assert_equal original,JSON.generate(data)
  end

  def test_scaled_dynamic_count_keeps_thickness_and_roundtrips_library_payload
    data = captured; rule = S::Core.rule!(data['rule'])
    plan = S::Core.plan(rule,data['snapshot'],'b6sochanphu'=>7,'a5dodayvan'=>20)
    snapshot = current(data['snapshot'],plan)
    scaled = S::ScalePlan.scaled_snapshot(snapshot,[1.2,1.1,1])
    result = S::ScalePlan.plan(rule,scaled,plan['target'])
    assert_in_delta 840,S::Core.dimensions(result['envelope'])[0],0.000001
    assert_equal 12,result['parts'].length
    revised = current(scaled,result)
    assert_equal 0,S::Core.plan(rule,revised,{})['changed_count']
    payload = {'format'=>'mh_module_library','version'=>1,'name'=>'Chân bệ','rule'=>rule,'values'=>result['target'],'snapshot'=>revised}
    restored = S::LibraryCatalog.payload(JSON.generate(payload))
    assert_equal 12,restored['snapshot']['parts'].length
    assert_equal 0,S::Core.plan(restored['rule'],restored['snapshot'],{})['changed_count']
  end

  def test_new_copy_cannot_bypass_rotation_guards_with_copy_index_formula
    data = captured
    program = data['rule']['formula_engine']['attribute_program']
    program['dc_graph']['nodes'].each do |node|
      node['attributes']['_rotx_formula'] = 'if(copy>4,90,0)' if node['attributes']['_copies_formula']
    end
    rule = S::Core.rule!(data['rule'])
    error = assert_raises(S::Core::Error) { S::Core.plan(rule,data['snapshot'],'b6sochanphu'=>7) }
    assert_match 'xoay',error.message
  end

  def test_legacy_program_can_upgrade_scalar_count_without_relaxing_hidden_guards
    data = captured
    source = data['rule']['formula_engine']['attribute_program']
    source.delete('visibility_version')
    rule = S::Core.rule!(data['rule'])
    assert rule['parameters'].find { |row| row['key']=='b6sochanphu' }['editable']
    refute rule['formula_engine']['attribute_program']['visibility_version']
    plan = S::Core.plan(rule,data['snapshot'],'b6sochanphu'=>7)
    assert_equal 2,plan['copy_add'].length
    assert_raises(S::Core::Error) { S::Core.plan(rule,data['snapshot'],'c5_an_vien_nhua'=>1) }
  end
end
