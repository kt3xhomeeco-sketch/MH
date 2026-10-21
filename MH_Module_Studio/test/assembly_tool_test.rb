# encoding: UTF-8
require 'minitest/autorun'
require_relative '../assembly_tool'

class ModuleStudioAssemblyToolTest < Minitest::Test
  def setup
    @tool = MH::ModuleStudio::AssemblyTool.allocate
    @tool.define_singleton_method(:refresh) { nil }
    @tool.define_singleton_method(:changed) { @changed = true }
    @tool.fresh
  end

  def test_loading_minimal_saved_link_supplies_hud_defaults_without_mutating_source
    source = {'id'=>'saved','mode'=>'fit','gap'=>3,'b'=>{'root'=>'42'}}
    original = JSON.generate(source)
    @tool.load_record(source)
    @tool.validate_input
    assert_equal 2,@tool.record['count']
    assert_equal 90,@tool.record['angle']
    @tool.action(:step,['gap',1])
    assert_equal 4,@tool.record['gap']
    assert_equal original,JSON.generate(source)
  end

  def test_invalid_hud_edits_restore_previous_values_and_explain_the_problem
    @tool.action(:step,['count',-2])
    assert_equal 2,@tool.record['count']
    assert_includes @tool.error,'Số lượng'
    @tool.fresh('fit')
    @tool.action(:step,['gap',-1])
    assert_equal 0,@tool.record['gap']
    assert_includes @tool.error,'Khoảng hở'
  end

  def test_drag_escape_restores_whole_draft_and_clears_only_the_gesture
    @tool.load_record('id'=>'saved','mode'=>'contact','gap'=>3)
    prior = MH::ModuleStudio::Core.copy_data(@tool.record)
    @tool.instance_variable_set(:@drag,{'before'=>prior})
    @tool.record['gap'] = 90
    @tool.cancel_gesture
    assert_equal prior,@tool.record
    assert_nil @tool.instance_variable_get(:@drag)
  end

  def test_direction_and_count_controls_are_direct_and_reference_gap_cannot_be_overwritten
    @tool.fresh('repeat')
    %w[left right up down].each do |direction|
      @tool.action(:direction,direction)
      assert_equal direction,@tool.record['direction']
    end
    @tool.action(:step,['count',1])
    assert_equal 3,@tool.record['count']
    @tool.record['r1'] = {'root'=>'A'}
    @tool.action(:step,['gap',1])
    assert_equal 0,@tool.record['gap']
    assert_includes @tool.error,'tham chiếu'
    @tool.action(:manual)
    assert_nil @tool.record['r1']
    @tool.action(:step,['gap',1])
    assert_equal 1,@tool.record['gap']
  end

  def test_inspector_values_and_opposing_boundary_keep_existing_face_selection
    @tool.load_record('id'=>'saved','mode'=>'contact','gap'=>3,'a'=>{'root'=>'A'},'b'=>{'root'=>'B'})
    @tool.action(:bound)
    assert_equal 'fit',@tool.record['mode']
    assert_equal 'A',@tool.record.dig('a','root')
    assert_equal 'B',@tool.record.dig('b','root')
    assert_equal 'c',@tool.instance_variable_get(:@picking)
    @tool.action(:fit_size,false)
    assert_equal 'center',@tool.record['mode']
    @tool.action(:fit_size,true)
    assert_equal 'fit',@tool.record['mode']
    @tool.action(:value,['gap',5])
    assert_equal 5,@tool.record['gap']
    @tool.action(:value,['gap',-1])
    assert_equal 5,@tool.record['gap']
    assert_includes @tool.error,'Khoảng hở'
  end

  def test_open_boundary_uses_positive_ui_input_for_inward_signed_contacts
    @tool.load_record('mode'=>'contact','gap'=>-80,'import_link'=>{'boundary'=>'envelope'})
    @tool.action(:value,['gap',90]);assert_equal(-90,@tool.record['gap'])
    @tool.action(:step,['gap',1]);assert_equal(-91,@tool.record['gap'])
    @tool.onUserText('82',nil);assert_equal(-82,@tool.record['gap'])
    assert_equal 82,MH::ModuleStudio::AssemblyPresentation.gap(@tool.record,@tool.record['gap'])
    @tool.action(:flip);assert_equal 82,@tool.record['gap']
    assert_equal(-82,MH::ModuleStudio::AssemblyPresentation.gap(@tool.record,@tool.record['gap']))
    @tool.action(:flip);@tool.action(:bound)
    assert_equal 'fit',@tool.record['mode'];assert_equal 82,@tool.record['gap'];refute @tool.record['import_link']
  end

  def test_flip_side_preserves_faces_and_cannot_override_a_measured_gap
    @tool.load_record('mode'=>'contact','gap'=>3,'a'=>{'root'=>'A'},'b'=>{'root'=>'B'})
    @tool.action(:flip)
    assert_equal(-3,@tool.record['gap'])
    assert_equal 'A',@tool.record['a']['root']
    assert_equal 'B',@tool.record['b']['root']
    @tool.record['r1'] = {'root'=>'R'}
    @tool.action(:flip)
    assert_equal(-3,@tool.record['gap'])
    assert_includes @tool.error,'tham chiếu'
  end
end
