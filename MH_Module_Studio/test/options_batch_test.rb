# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../module_options'

class ModuleStudioOptionsBatchTest < Minitest::Test
  S=MH::ModuleStudio

  def test_two_rows_on_one_module_generate_one_atomic_update_and_keep_original_draft
    snapshot=JSON.parse(File.read(File.join(__dir__,'fixtures/readable_nested_dc.json'),encoding:'UTF-8'))
    rule=S::RuleSystem.build(snapshot,S::Core.learn_module([snapshot]))
    values=S::Parametric.targets(rule); raw=JSON.generate(rule); saved=JSON.generate(values)
    entity=Object.new
    entity.define_singleton_method(:get_attribute) { |_dict,key| key=='rule_json' ? raw : saved }
    window=S::ModuleOptions.allocate
    window.instance_variable_set(:@model,:model)
    window.instance_variable_set(:@root,Struct.new(:persistent_id).new(1))
    window.instance_variable_set(:@display_rows,[{'id'=>'T','editable'=>true,'targets'=>[{'pid'=>'1','variable_id'=>'input:dayvan'}]},
      {'id'=>'back','editable'=>true,'targets'=>[{'pid'=>'1','variable_id'=>'input:luihau'}]}])
    window.instance_variable_set(:@members,{'1'=>{'anchor'=>{'root'=>'1','scope'=>'scope'},'rule'=>rule,'raw'=>raw,'values_raw'=>saved}})
    calls=[]
    S::Assembly.stub(:root,entity) do
      S::Assembly.stub(:records,[]) do
        S::Assembly.stub(:transact,->(_model,_links,updates:) { calls << updates }) do
          window.apply_changes([{'variable_id'=>'T','value'=>20},{'variable_id'=>'back','value'=>22}])
        end
      end
    end
    assert_equal 1,calls.length
    assert_equal 1,calls.first.length
    assert_equal 20,calls.first.first[2]['dayvan']
    assert_equal 22,calls.first.first[2]['luihau']
    assert_equal raw,JSON.generate(rule)
    assert_raises(S::Core::Error) { window.apply_changes([]) }
    assert_raises(S::Core::Error) { window.apply_changes([{'variable_id'=>'hidden','value'=>20}]) }
  end
end
