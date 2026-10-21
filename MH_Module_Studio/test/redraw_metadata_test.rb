# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../runtime'
require_relative 'formula_fixtures'

class ModuleStudioRedrawMetadataTest < Minitest::Test
  S=MH::ModuleStudio
  class Entity
    attr_accessor :name
    attr_reader :persistent_id
    def initialize(pid);@persistent_id=pid;@name='';@attributes={};end
    def get_attribute(dict,key,default=nil);@attributes.fetch([dict,key],default);end
    def set_attribute(dict,key,value);@attributes[[dict,key]]=value;end
    def delete_attribute(dict,key);@attributes.delete([dict,key]);end
  end

  def setup
    snapshot=FormulaFixtures.snapshot
    @rule=S::RuleSystem.build(snapshot,S::Core.learn_module([snapshot]))
    @values=S::Parametric.targets(@rule)
    @root=Entity.new(1)
    @bindings=snapshot['parts'].to_h { |part| [part['key'],{entity:Entity.new(part['key'])}] }
    S::Runtime.stamp(@root,@rule,@bindings,@values)
  end

  def full_stamps(rule=@rule,values=@values)
    calls=[]
    S::Runtime.stub(:stamp,->(*args) { calls << args }) { S::Runtime.stamp_redraw(@root,rule,@bindings,values) }
    calls
  end

  def test_geometry_only_redraw_retains_identical_validated_metadata
    before=Marshal.dump([@root,@bindings])
    assert_empty full_stamps
    assert_equal before,Marshal.dump([@root,@bindings])
  end

  def test_new_instance_and_changed_values_or_rule_require_full_stamp
    @root.set_attribute(S::Reader::DICT,'root_pid','old-copy')
    assert_equal 1,full_stamps.length
    @root.set_attribute(S::Reader::DICT,'root_pid','1')
    key=@values.keys.first
    assert_equal 1,full_stamps(@rule,@values.merge(key=>20)).length
    renamed=S::Parametric.rename_display(@rule,'Renamed module')
    assert_equal 1,full_stamps(renamed).length
  end

  def test_new_or_mismatched_parts_and_missing_exposure_metadata_require_full_stamp
    entity=@bindings.values.first[:entity]
    entity.set_attribute(S::Reader::DICT,'instance_id','another-instance')
    assert_equal 1,full_stamps.length
    S::Runtime.stamp(@root,@rule,@bindings,@values)
    entity.delete_attribute(S::Reader::DICT,'part_key')
    assert_equal 1,full_stamps.length
    S::Runtime.stamp(@root,@rule,@bindings,@values)
    @root.delete_attribute(S::Reader::DICT,'exposed_parameters_json')
    assert_equal 1,full_stamps.length
  end

  def test_changed_rule_takes_full_redraw_stamp_path
    changed=S::Parametric.rename_display(@rule,'Different')
    assert_equal 1,full_stamps(changed).length
  end
end
