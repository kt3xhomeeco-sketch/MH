# encoding: UTF-8
require 'minitest/autorun'
require_relative 'formula_fixtures'

class ModuleStudioConditionalVisibilityTest < Minitest::Test
  S = MH::ModuleStudio

  def source
    data = FormulaFixtures.snapshot
    data['visibility_version'] = 1
    data['dc_graph']['nodes'].each { |node| node.merge!('hidden'=>false,'tag_visible'=>true) }
    data
  end

  def hidden_back
    data = source
    back = data['dc_graph']['nodes'].find { |node| node['part_key']=='back' }
    back.merge!('hidden'=>true)
    back['attributes'].merge!('_hidden_formula'=>'parent!t<2','_hidden_formulaunits'=>'FLOAT')
    # Back's parent is the carrier; explicitly reference the root by its name.
    data['dc_inputs']['_name'] = 'cabinet'
    back['attributes']['_hidden_formula'] = 'cabinet!t<2'
    data['parts'].find { |part| part['key']=='back' }['visible'] = false
    data
  end

  def current(data,plan)
    result = S::Core.copy_data(data).merge('parts'=>plan['parts'],'dc_inputs'=>{},'parameter_values'=>plan['target'])
    nodes = result['dc_graph']['nodes']
    by_id = nodes.to_h { |node| [S::DCVisibility.id(node),node] }
    plan['visibility_updates'].each do |entry|
      node = nodes.find { |item| item['part_key']==entry['part'] }
      entry['depth'].times { node = by_id.fetch(S::DCVisibility.parent(node)) }
      node['hidden'] = entry['hidden']
    end
    result
  end

  def test_hidden_panel_is_recomputed_before_reappearing_and_survives_repeated_edits
    data = hidden_back
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    inactive = S::Core.plan(rule,data,'t'=>19)
    back = inactive['parts'].find { |part| part['key']=='back' }
    refute back['visible']
    assert_equal data['parts'].find { |part| part['key']=='back' }['bounds'],back['bounds']
    shown = S::Core.plan(rule,current(data,inactive),'t'=>22)
    back = shown['parts'].find { |part| part['key']=='back' }
    assert back['visible']
    assert_in_delta 22,back['bounds'][0][0],0.000001
    assert_in_delta 556,S::Core.dimensions(back['bounds'])[0],0.000001
    assert_equal [{'part'=>'back','depth'=>0,'hidden'=>false}],shown['visibility_updates']
    assert_equal 0,S::Core.plan(rule,current(data,shown),{})['changed_count']
    hidden = S::Core.plan(rule,current(data,shown),'t'=>17)
    refute hidden['parts'].find { |part| part['key']=='back' }['visible']
    assert S::Core.bounds_close?(S::Core.union(hidden['parts']),data['envelope'],0.001)
  end

  def test_scalar_visibility_input_and_ancestor_hidden_are_preserved_without_topology_changes
    data = source
    data['dc_inputs'].merge!('toggle'=>0,'_toggle_access'=>'TEXTBOX','_toggle_units'=>'FLOAT')
    carrier = data['dc_graph']['nodes'].find { |node| node['id']=='carrier' }
    carrier['attributes'].merge!('_hidden_formula'=>'parent!toggle','_hidden_formulaunits'=>'FLOAT')
    engine = S::Core.learn_module([data])
    assert engine['parameters'].find { |p| p['key']=='toggle' }['editable']
    rule = S::RuleSystem.build(data,engine)
    plan = S::Core.plan(rule,data,'toggle'=>1)
    refute plan['parts'].find { |p| p['key']=='back' }['visible']
    assert_equal [{'part'=>'back','depth'=>1,'hidden'=>true}],plan['visibility_updates']
    restored = S::Core.plan(rule,current(data,plan),'toggle'=>0)
    assert restored['parts'].find { |p| p['key']=='back' }['visible']
    assert_equal(data['parts'].map { |p| p['key'] },restored['parts'].map { |p| p['key'] })
  end

  def test_tag_mask_is_not_overridden_by_hidden_formulas
    data = hidden_back
    back = data['dc_graph']['nodes'].find { |n| n['part_key']=='back' }
    back['tag_visible'] = false
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    plan = S::Core.plan(rule,data,'t'=>22)
    refute plan['parts'].find { |p| p['key']=='back' }['visible']
    assert_equal false,plan['visibility_updates'].first['hidden']
  end

  def test_dormant_conditional_dependency_is_found_beyond_local_probe
    data = source
    data['dc_inputs'].merge!('offset'=>0,'_offset_access'=>'TEXTBOX','_offset_units'=>'MILLIMETERS')
    top = data['dc_graph']['nodes'].find { |node| node['part_key']=='top' }
    top['attributes']['_leny_formula'] = 'parent!leny-parent!cut-if(parent!offset>2,0.5,0)'
    engine = S::Core.learn_module([data])
    assert engine['rules'].key?('offset')
    plan = S::Core.plan(engine,data,'offset'=>21)
    assert_in_delta 169,S::Core.dimensions(plan['parts'].find { |p| p['key']=='top' }['bounds'])[1],0.000001
  end

  def test_unactivated_dependency_is_disclosed_instead_of_claiming_verified_motion
    data = source
    data['dc_inputs'].merge!('offset'=>0,'_offset_access'=>'TEXTBOX','_offset_units'=>'MILLIMETERS')
    top = data['dc_graph']['nodes'].find { |node| node['part_key']=='top' }
    top['attributes']['_leny_formula'] = 'parent!leny-parent!cut-if(parent!offset>20000,0.5,0)'
    engine = S::Core.learn_module([data])
    assert_equal 'conditional_dependency',engine['rules']['offset']['recognition']
    assert_match 'điều kiện',engine['parameters'].find { |p| p['key']=='offset' }['reason']
    assert_equal 0,S::Core.plan(engine,data,'offset'=>10)['changed_count']
  end

  def test_copies_and_rotation_changes_remain_guarded
    %w[copies rotx].each do |key|
      data = source
      data['dc_graph']['nodes'].first['attributes']["_#{key}_formula"] = 'if(parent!t>2,1,0)'
      data['dc_graph']['nodes'].first['attributes']["_#{key}_formulaunits"] = 'FLOAT'
      rule = S::Core.learn_module([data])
      assert_raises(S::Core::Error) { S::Core.plan(rule,data,'t'=>22) }
    end
  end

  def test_activation_cannot_introduce_an_overlap_that_was_previously_hidden
    data = source
    spare = S::Core.copy_data(data['parts'].find { |part| part['key']=='top' })
    spare.merge!('key'=>'spare','name'=>'Spare','visible'=>false)
    node = S::Core.copy_data(data['dc_graph']['nodes'].find { |entry| entry['part_key']=='top' })
    node.merge!('id'=>'spare','path'=>['spare'],'part_key'=>'spare','hidden'=>true)
    node['attributes'].merge!('_hidden_formula'=>'parent!t<2','_hidden_formulaunits'=>'FLOAT')
    data['parts'] << spare; data['dc_graph']['nodes'] << node
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    assert_match 'giao vào',assert_raises(S::Core::Error) { S::Core.plan(rule,data,'t'=>22) }.message
  end

  def test_min_and_round_inputs_are_found_without_local_motion
    ['min(parent!offset,2)','round(parent!offset,0)'].each do |formula|
      data = source
      data['dc_inputs'].merge!('offset'=>30.0/25.4,'_offset_access'=>'TEXTBOX','_offset_units'=>'MILLIMETERS')
      top = data['dc_graph']['nodes'].find { |node| node['part_key']=='top' }
      top['attributes']['_leny_formula'] = "parent!leny-parent!cut-(#{formula}-#{formula.start_with?('min') ? 2 : 3})"
      engine = S::Core.learn_module([data])
      assert engine['rules'].key?('offset')
      assert S::Core.plan(engine,data,'offset'=>formula.start_with?('min') ? 0 : 20)['changed_count'].positive?
    end
  end

  def test_unsupported_inactive_mesh_formulas_do_not_disable_other_inputs
    data = hidden_back
    back = data['dc_graph']['nodes'].find { |n| n['part_key']=='back' }
    back['attributes']['_lenx_formula'] = 'opaque_function()'
    rule = S::Core.learn_module([data])
    assert S::Core.plan(rule,data,'t'=>19)['changed_count'].positive?
    assert_raises(S::Core::Error) { S::Core.plan(rule,data,'t'=>22) }
  end

  def test_stale_own_hidden_flag_under_a_mask_is_normalized_only_on_the_owned_copy
    data = hidden_back
    back = data['dc_graph']['nodes'].find { |node| node['part_key']=='back' }
    back.merge!('hidden'=>false,'tag_visible'=>false)
    before = JSON.generate(data)
    rule = S::Core.learn_module([data])
    plan = S::Core.plan(rule,data,{})
    assert_equal 0,plan['changed_count']
    assert_equal true,plan['visibility_updates'].first['hidden']
    assert_equal before,JSON.generate(data)
  end

  def test_repeated_scale_reads_actual_previous_hidden_state_instead_of_template_state
    data = source
    carrier = data['dc_graph']['nodes'].find { |node| node['id']=='carrier' }
    carrier['attributes'].merge!('_hidden_formula'=>'parent!lenx>65','_hidden_formulaunits'=>'FLOAT')
    rule = S::RuleSystem.build(data,S::Core.learn_module([data]))
    saved = rule['parameters'].select { |p| p['editable'] }.to_h { |p| [p['key'],p['value']] }
    [1.2,0.8].each_with_index do |factor,index|
      stretched = S::Core.copy_data(data)
      stretched['parts'].each { |p| p['bounds'].each { |point| point[0] *= factor } }
      stretched['envelope'] = S::Core.union(stretched['parts'])
      stretched['dc_inputs'] = {}; stretched['parameter_values'] = saved
      plan = S::ScalePlan.plan(rule,stretched,saved)
      data = current(stretched,plan)
      assert_equal index==1,data['parts'].find { |p| p['key']=='back' }['visible']
      assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
    end
    assert_in_delta 576,S::Core.dimensions(data['envelope'])[0],0.001
  end

  def test_visibility_selector_can_be_recognized_when_another_input_must_be_changed_first
    data = hidden_back
    data['dc_inputs'].merge!('toggle'=>0,'_toggle_access'=>'TEXTBOX','_toggle_units'=>'FLOAT',
                             'support'=>0,'_support_access'=>'TEXTBOX','_support_units'=>'FLOAT')
    back = data['dc_graph']['nodes'].find { |node| node['part_key']=='back' }
    back['attributes'].merge!('_hidden_formula'=>'cabinet!toggle=0','_lenx_formula'=>'parent!w*cabinet!support')
    engine = S::Core.learn_module([data])
    assert_equal 'conditional_dependency',engine['rules']['toggle']['recognition']
    assert_nil engine['rules']['toggle']['probe_value']
    assert_raises(S::Core::Error) { S::Core.plan(engine,data,'toggle'=>1) }
    plan = S::Core.plan(engine,data,'toggle'=>1,'support'=>1)
    assert plan['parts'].find { |p| p['key']=='back' }['visible']
    assert_equal 0,S::Core.plan(engine,current(data,plan),{})['changed_count']
  end
end
