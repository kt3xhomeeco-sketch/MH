# encoding: UTF-8
require 'minitest/autorun'
require_relative '../assembly_tool'

class ModuleStudioAssemblyFacePickerTest < Minitest::Test
  S = MH::ModuleStudio

  def test_modifiers_are_explicit_and_control_wins
    {0=>'part',1=>'part',4=>'module',5=>'module',8=>'assembly',12=>'assembly',13=>'assembly'}.each do |flags,level|
      assert_equal level,S::AssemblyFacePicker.level(flags,shift_mask:4,ctrl_mask:8)
    end
  end

  def test_labels_distinguish_envelope_levels_and_all_six_local_faces
    %w[module assembly].each do |level|
      3.times do |axis|
        2.times do |side|
          label = S::AssemblyFacePicker.label('level'=>level,'axis'=>axis,'side'=>side)
          assert_includes label,S::AssemblyFacePicker::LABELS.fetch(level)
          assert_includes label,S::AssemblyFacePicker::SIDES[axis][side]
        end
      end
    end
    assert_includes S::AssemblyFacePicker.label('part'=>'panel','axis'=>0,'side'=>0),'Mặt tấm'
    assert_includes S::AssemblyFacePicker.label('path'=>[],'axis'=>0,'side'=>1),'Phủ bì module'
  end

  def test_draft_accepts_virtual_anchor_without_changing_the_source_or_autosaving
    tool = S::AssemblyTool.allocate
    tool.define_singleton_method(:refresh) { nil }
    tool.fresh
    anchor = {'root'=>'42','axis'=>0,'side'=>1,'level'=>'assembly','path'=>[]}
    tool.pick(anchor)
    assert_equal anchor,tool.record['a']
    refute_same anchor,tool.record['a']
    assert_equal 'b',tool.instance_variable_get(:@picking)
    anchor['side'] = 0
    assert_equal 1,tool.record['a']['side']
    assert_nil tool.record['id']
  end

  def test_external_dependency_checks_include_parent_child_containment_and_cycles
    row = {'id'=>'link','external'=>true,'mode'=>'contact',
      'a'=>{'root'=>'parent','level'=>'assembly'},'b'=>{'root'=>'child','scope'=>'parent'}}
    assert_raises(S::Core::Error) { S::AssemblyExternal.validate!([row]) }
    row['b'] = {'root'=>'other','level'=>'assembly'}
    assert_equal ['link'],S::AssemblyExternal.validate!([row])
    reverse = S::Core.copy_data(row).merge('id'=>'reverse','a'=>row['b'],'b'=>row['a'])
    assert_raises(S::Core::Error) { S::AssemblyExternal.validate!([row,reverse]) }
    row['mode'] = 'repeat'
    assert_raises(S::Core::Error) { S::AssemblyExternal.validate!([row]) }
  end

  def test_pick_policy_excludes_the_other_module_but_keeps_opposing_and_measurement_boundaries
    tool = S::AssemblyTool.allocate
    tool.define_singleton_method(:refresh) { nil }
    tool.fresh
    a = {'root'=>'outer','axis'=>0,'side'=>0}
    b = {'root'=>'inner','axis'=>0,'side'=>1}
    tool.pick(a)
    refute tool.pick_allowed?(a.merge('axis'=>1))
    assert tool.pick_allowed?(b)
    assert_raises(S::Core::Error) { tool.pick(a) }
    tool.pick(b)
    assert tool.pick_allowed?(a) # no picking: native body dragging stays available
    tool.action(:pick,'a')
    refute tool.pick_allowed?(b)
    assert tool.pick_allowed?(a)
    tool.action(:bound)
    assert tool.pick_allowed?(a.merge('side'=>1))
    refute tool.pick_allowed?(b)
    tool.action(:measure)
    tool.pick(a)
    assert tool.pick_allowed?(a.merge('side'=>1))
    refute tool.pick_allowed?(b)
  end

  def test_pick_policy_accounts_for_assembly_containment_without_excluding_siblings
    tool = S::AssemblyTool.allocate
    tool.define_singleton_method(:refresh) { nil }
    tool.fresh
    tool.pick('root'=>'wrapper','scope'=>nil,'level'=>'assembly','axis'=>0,'side'=>0)
    refute tool.pick_allowed?('root'=>'child','scope'=>'wrapper')
    assert tool.pick_allowed?('root'=>'child','scope'=>'another')
    tool.fresh
    tool.pick('root'=>'child','scope'=>'wrapper','axis'=>0,'side'=>0)
    refute tool.pick_allowed?('root'=>'wrapper','level'=>'assembly')
    assert tool.pick_allowed?('root'=>'sibling','scope'=>'wrapper')
  end
end
