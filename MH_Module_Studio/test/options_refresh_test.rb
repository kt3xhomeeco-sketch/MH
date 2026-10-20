# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../module_options'
require_relative 'formula_fixtures'

class ModuleStudioOptionsRefreshTest < Minitest::Test
  S=MH::ModuleStudio
  Entity=Struct.new(:persistent_id,:name,:attributes) do
    def get_attribute(_dict,key,default=nil);attributes.fetch(key,default);end
  end

  def test_window_reuses_only_identical_rule_and_input_metadata_and_keeps_names_fresh
    snapshot=FormulaFixtures.snapshot
    rule=S::RuleSystem.build(snapshot,S::Core.learn_module([snapshot]));values=S::Parametric.targets(rule)
    root=Entity.new(1,'Original',{'rule_json'=>JSON.generate(rule),'parameter_values_json'=>JSON.generate(values)})
    window=S::ModuleOptions.allocate
    window.instance_variable_set(:@dialog,Object.new)
    window.instance_variable_set(:@model,Struct.new(:active_path).new(nil))
    window.define_singleton_method(:attach) {}
    window.define_singleton_method(:thumbnail) { |_root| nil }
    payloads=[];window.define_singleton_method(:send_state) { |payload| payloads << payload }
    normalized=S::ThicknessSymbols.method(:normalize);calls=0
    S::ModuleOptions.stub(:selected_options_root,root) do
      S::AssemblyContainers.stub(:managed?,false) do
        S::ThicknessSymbols.stub(:normalize,->(data) { calls+=1;normalized.call(data) }) do
          window.refresh;window.refresh
          assert_equal 1,calls
          root.name='Renamed';window.refresh
          assert_equal 'Renamed',payloads.last['name'];assert_equal 1,calls
          root.attributes['parameter_values_json']=JSON.generate(values.merge('t'=>20))
          window.refresh
          assert_equal 2,calls
          rows=window.instance_variable_get(:@display_rows)
          assert_in_delta 20,rows.find { |row| row['id']=='input:t' }['value'],0.001
          root.attributes['rule_json']=JSON.generate(S::Parametric.rename_display(rule,'Changed rule'))
          window.refresh
          assert_equal 3,calls
        end
      end
    end
    assert(payloads.none? { |payload| payload['error'] })
  end
end
