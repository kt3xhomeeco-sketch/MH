# encoding: UTF-8
require 'minitest/autorun'
require_relative '../library_placement'

class ModuleStudioReplaceTargetPolicyTest < Minitest::Test
  S=MH::ModuleStudio
  Model=Struct.new(:raw) do
    def get_attribute(*)
      raw
    end
  end

  def test_detached_policy_reads_only_global_reference_identity_not_target_rules
    target={'root'=>'target'}
    rows=[{'mode'=>'contact','a'=>{'root'=>'other-a'},'b'=>{'root'=>'other-b'}}]
    model=Model.new(JSON.generate(rows))
    assert S::LibraryPlacement.detached_target?(model,target)
    rows.first['b']['root']='target';model.raw=JSON.generate(rows)
    refute S::LibraryPlacement.detached_target?(model,target)
    rows.first['b']={'root'=>'child','scope'=>'target'};model.raw=JSON.generate(rows)
    refute S::LibraryPlacement.detached_target?(model,target)
    refute S::LibraryPlacement.detached_target?(model,{'root'=>'child','scope'=>'parent'})
  end

  def test_malformed_old_link_metadata_cannot_block_geometry_replacement_or_be_rewritten
    ['{broken','null','[null]','[]'].each do |raw|
      model=Model.new(raw)
      assert S::LibraryPlacement.detached_target?(model,{'root'=>'target'})
      assert_equal raw,model.raw
    end
  end
end
