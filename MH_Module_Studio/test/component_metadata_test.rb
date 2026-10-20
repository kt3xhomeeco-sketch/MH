# encoding: UTF-8
require 'minitest/autorun'
require_relative '../library'
class ModuleStudioComponentMetadataTest < Minitest::Test
  S=MH::ModuleStudio
  Entity=Struct.new(:persistent_id,:definition,:attributes) do
    def get_attribute(_dict,key,default=nil);attributes.fetch(key,default);end
    def set_attribute(_dict,key,value);attributes[key]=value;end
  end
  def test_definition_carries_rules_and_values_without_copying_live_instance_identity
    definition=Entity.new(10,nil,{})
    root=Entity.new(1,definition,{'trial'=>true,'instance_id'=>'live-A','root_pid'=>'1','rule_id'=>'rule','rule_json'=>JSON.generate({'id'=>'rule'}),'parameter_values_json'=>JSON.generate({'T1'=>18}),'formula_envelope_json'=>'[[0,0,0],[1,2,3]]'})
    S::ComponentMetadata.store(root)
    seed=JSON.parse(definition.attributes.fetch(S::ComponentMetadata::KEY))
    refute seed.key?('instance_id');refute seed.key?('root_pid')
    assert_equal '10',root.attributes['definition_pid']
    refute S::ComponentMetadata.pending?(root)
    imported=Entity.new(2,definition,{})
    assert S::ComponentMetadata.pending?(imported)
    rule,values,envelope=S::ComponentMetadata.source(imported)
    assert_equal 'rule',rule['id'];assert_equal 18,values['T1'];assert_equal '[[0,0,0],[1,2,3]]',envelope
    changed=Entity.new(11,nil,definition.attributes.dup);root.definition=changed
    assert S::ComponentMetadata.pending?(root),'Definition replacement invalidates old instance metadata even with the same rule ID'
    root.attributes.delete('definition_pid');refute S::ComponentMetadata.pending?(root),'Legacy owned modules are not reset merely because the marker is new'
    root.attributes['rule_id']='different'
    assert S::ComponentMetadata.pending?(root),'Legacy replacement by a different rule still receives source properties'
    root.definition=Entity.new(12,nil,{})
    refute S::ComponentMetadata.pending?(root),'Ordinary geometry is not assigned unrelated module rules'
  end
end
