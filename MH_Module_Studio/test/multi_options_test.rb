# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../module_options'
require_relative 'formula_fixtures'
class ModuleStudioMultiOptionsTest < Minitest::Test
  S=MH::ModuleStudio
  Entity=Struct.new(:persistent_id,:name,:model,:attributes) do
    def get_attribute(_dict,key,default=nil);attributes.fetch(key,default);end
  end
  def test_multi_selection_merges_T1_without_role_flags_and_applies_all_targets_atomically
    rule=S::RuleSystem.build(FormulaFixtures.snapshot);rule=S::ThicknessSymbols.normalize(rule)
    rule.delete('thickness_symbol_roles')
    model=Struct.new(:active_path).new(nil);values=S::Parametric.targets(rule);key=S::Parametric.variables(rule).find { |r| r['symbol']=='T1' }['binding']
    roots=[18,20].each_with_index.map { |v,i| Entity.new(i+1,"Module #{i}",model,{'rule_json'=>JSON.generate(rule),'parameter_values_json'=>JSON.generate(values.merge(key=>v))}) }
    window=S::ModuleOptions.allocate;window.instance_variable_set(:@model,model);window.instance_variable_set(:@dialog,Object.new)
    window.define_singleton_method(:attach) {};window.define_singleton_method(:thumbnail) { |_root| raise 'Batch must not generate thumbnail' }
    states=[];window.define_singleton_method(:send_state) { |packet| states << packet }
    calls=[]
    selection=roots
    S::ModuleOptions.stub(:selected_options_roots,-> { selection }) do
      S::AssemblyContainers.stub(:managed?,false) do
        window.refresh
        common=window.instance_variable_get(:@display_rows).find { |r| r['id']=='common:T1' }
        assert common;assert common['mixed'];assert_equal 2,common['targets'].length
        assert states.last['batch'];assert_equal 'selection:1,2',states.last['root_pid']
        request={'action'=>'change','root_pid'=>states.last['root_pid'],'token'=>states.last['token'],'variable_id'=>'common:T1','value'=>22}
        S::Assembly.stub(:root,->(_model,anchor) { roots.find { |r| r.persistent_id.to_s==anchor['root'] } }) do
          S::Assembly.stub(:records,[]) do
            S::Assembly.stub(:transact,->(_model,_rows,updates:) { calls << updates }) { window.request(request) }
          end
        end
        assert_equal 1,calls.length;assert_equal 2,calls.first.length
        assert(calls.first.all? { |job| job[2][key]==22 })
        selection=[roots.first];assert_raises(S::Core::Error) { window.request(request) }
      end
    end
  end
  def test_incompatible_units_are_not_silently_merged
    row={'id'=>'v','symbol'=>'size','category'=>'dimension','unit'=>'mm','value'=>1,'options'=>[],'manual_input'=>nil,'editable'=>true}
    S::OptionsParameters.stub(:rows,->(rule,_values) { [row.merge('unit'=>rule['unit'])] }) do
      result=S::OptionsParameters.grouped([{'pid'=>'A','name'=>'A','rule'=>{'unit'=>'mm'},'values'=>{}},{'pid'=>'B','name'=>'B','rule'=>{'unit'=>'cm'},'values'=>{}}])
      assert_equal 2,result.length;refute(result.any? { |r| r['section_id']=='common' })
    end
  end
  def test_copied_wrappers_keep_shared_child_ids_as_two_distinct_targets
    rule=S::ThicknessSymbols.normalize(S::RuleSystem.build(FormulaFixtures.snapshot))
    model=Struct.new(:active_path).new(nil)
    child=Entity.new(7,'Shared child',model,{'trial'=>true,'rule_json'=>JSON.generate(rule),'parameter_values_json'=>JSON.generate(S::Parametric.targets(rule))})
    wrappers=[1,2].map { |id| Entity.new(id,"Wrapper #{id}",model,{}) }
    window=S::ModuleOptions.allocate;window.instance_variable_set(:@model,model);window.instance_variable_set(:@dialog,Object.new)
    window.define_singleton_method(:attach) {};window.define_singleton_method(:send_state) { |_packet| }
    S::ModuleOptions.stub(:selected_options_roots,wrappers) do
      S::AssemblyContainers.stub(:managed?,true) do
        S::AssemblyContainers.stub(:members,[child]) { window.refresh }
      end
    end
    common=window.instance_variable_get(:@display_rows).find { |r| r['id']=='common:T1' }
    assert_equal %w[1/7 2/7],common['targets'].map { |ref| ref['pid'] }.sort
    assert_equal %w[1 2],window.instance_variable_get(:@members).values.map { |member| member['anchor']['scope'] }.sort
  end
end
