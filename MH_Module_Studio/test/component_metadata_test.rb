# encoding: UTF-8
require 'minitest/autorun'
require_relative '../library'
require_relative '../update_work'
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
  def test_store_reuses_prepared_seed_and_pid_only_when_values_change
    definition=Struct.new(:persistent_id,:attributes,:writes) do
      def get_attribute(_dict,key,default=nil);attributes.fetch(key,default);end
      def set_attribute(_dict,key,value);self.writes+=1;attributes[key]=value;end
    end.new(10,{},0)
    attributes={'trial'=>true,'rule_json'=>JSON.generate({'id'=>'rule'}),'parameter_values_json'=>'{}'}
    root=Entity.new(1,definition,attributes)
    root.define_singleton_method(:set_attribute) { |_dict,key,value| attributes[key]=value }
    Thread.current[:mh_module_update]={seeds:{}}
    begin
      S::ComponentMetadata.store(root,seed_json:'prepared')
      writes=root.attributes.dup
      assert_equal 1,definition.writes
      definition.attributes.delete(S::ComponentMetadata::KEY)
      S::ComponentMetadata.store(root)
      assert_equal 'prepared',definition.attributes.fetch(S::ComponentMetadata::KEY)
      assert_equal writes,root.attributes
      definition.attributes[S::ComponentMetadata::KEY]='old'
      S::ComponentMetadata.store(root,seed_json:'changed')
      assert_equal 'changed',definition.attributes.fetch(S::ComponentMetadata::KEY)
    ensure
      Thread.current[:mh_module_update]=nil
    end
  end
end
