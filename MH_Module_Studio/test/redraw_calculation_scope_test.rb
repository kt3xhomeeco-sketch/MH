# encoding: UTF-8
require 'minitest/autorun'
require_relative '../scale_redraw'
require_relative 'formula_fixtures'

class ModuleStudioRedrawCalculationScopeTest < Minitest::Test
  S=MH::ModuleStudio
  def test_exact_plan_reuse_is_local_and_changed_geometry_rule_or_values_miss
    rule={'name'=>'A'};current={'id'=>'one','envelope'=>[[0,0,0],[100,18,500]]};values={'T'=>18}
    calls=0
    calculate=lambda do |*_args|
      calls+=1
      {'envelope'=>[[0,0,0],[100,18,500]]}
    end
    S::ScalePlan.stub(:plan,calculate) do
      S::ScaleRedraw.with_calculations do
        first=S::ScaleRedraw.plan(rule,current,values)
        first['envelope'][1][0]=-100
        fresh=current.merge('id'=>'two','label'=>'new read','captured_at'=>'later')
        S::ScaleRedraw.with_calculations do
          assert_equal 100,S::ScaleRedraw.plan(rule,fresh,values)['envelope'][1][0]
        end
        assert_equal 1,calls
        S::ScaleRedraw.plan(rule,current.merge('envelope'=>[[0,0,0],[200,18,500]]),values)
        S::ScaleRedraw.plan(rule.merge('name'=>'B'),current,values)
        S::ScaleRedraw.plan(rule,current,{'T'=>20})
        assert_equal 4,calls
      end
      S::ScaleRedraw.plan(rule,current,values)
      assert_equal 5,calls,'A later repair must not retain the previous calculation scope.'
    end
  end

  def test_failure_discards_the_repair_scope
    calculate=lambda { |*_args| {'ok'=>true} }
    S::ScalePlan.stub(:plan,calculate) do
      assert_raises(RuntimeError) do
        S::ScaleRedraw.with_calculations { S::ScaleRedraw.plan({}, {}, {});raise 'Failed verification' }
      end
      assert_nil S::ScaleRedraw.instance_variable_get(:@calculations)
    end
  end

  def test_public_scale_validates_once_and_a_serialized_flag_cannot_bypass_it
    data=FormulaFixtures.snapshot
    rule=S::StudioCalculation.build_system([data]);values=S::Parametric.targets(rule)
    original=S::RuleSystem.method(:validate!);checks=0
    validate=lambda { |bundle| checks+=1;original.call(bundle) }
    S::RuleSystem.stub(:validate!,validate) do
      plan=S::ScalePlan.plan(rule,data,values)
      assert_equal 1,checks
      assert_equal 0,plan['changed_count']
      invalid=S::Core.copy_data(rule)
      invalid['validated']=true
      invalid['parts'].first['base_bounds'][1][0]='damaged'
      assert_raises(S::Core::Error) { S::ScalePlan.plan(invalid,data,values) }
      assert_equal 2,checks
    end
  end
end
