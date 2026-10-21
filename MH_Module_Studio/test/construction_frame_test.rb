# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioConstructionFrameTest < Minitest::Test
  S=MH::ModuleStudio
  def source(name)
    JSON.parse(File.read(File.join(__dir__,"fixtures/#{name}.json"),encoding:'UTF-8'))
  end

  def current(snapshot,plan)
    snapshot.merge('parts'=>plan['parts'],'envelope'=>plan['envelope'],'parameter_values'=>plan['target'],
      'formula_envelope'=>plan['formula_envelope'],'dc_inputs'=>{})
  end

  def test_cached_construction_dimensions_are_accepted_only_with_complete_geometry_evidence
    data=source('tv-construction-frame');before=JSON.generate(data)
    rule=S::StudioCalculation.build_system([data])
    assert rule['formula_engine']
    assert_equal 350,rule.dig('formula_engine','attribute_program','construction_inputs','envelope',1,1)
    assert_equal 0,S::Core.plan(rule,data,S::Parametric.targets(rule))['changed_count']
    broken=S::Core.copy_data(data);broken['parts'].first['bounds'][0][0]+=1
    refute S::ConstructionFrame.enable(broken)['construction_inputs']
    assert_equal before,JSON.generate(data)
  end

  def test_thickness_edits_and_repeated_scale_preserve_exact_formula_construction_and_requested_union
    %w[tv-construction-frame back-covered-frame].each do |name|
      data=source(name);rule=S::StudioCalculation.build_system([data]);values=S::Parametric.targets(rule)
      key=S::Parametric.variables(rule).find { |row| row['symbol']=='T1' }['binding']
      [20,17.5].each do |thickness|
        plan=S::Core.plan(rule,data,key=>thickness)
        data=current(data,plan);values=plan['target']
        assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
      end
      [[1.03,1.03,1.03],[0.8,1.2,0.9],[1.1,0.8,1.2]].each do |factors|
        scaled=S::ScalePlan.scaled_snapshot(data,factors)
        plan=S::ScalePlan.plan(rule,scaled,values)
        assert S::Core.bounds_close?(scaled['envelope'],plan['envelope'],0.001)
        data=current(data,plan)
        assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
      end
    end
  end

  def test_discrete_selector_with_incorrect_mm_metadata_uses_verified_scalar_values
    data=source('led-scalar-selector');before=JSON.generate(data)
    rule=S::StudioCalculation.build_system([data])
    assert rule['formula_engine']
    input=rule['parameters'].find { |param| param['key']=='qag1xnr2g4' }
    assert_equal '',input['unit']
    assert_equal 2,input['value']
    assert_equal [1.0,2.0],(S::DCOptions.for_parameter(rule,input).map { |row| row['value'] })
    plan=S::Core.plan(rule,data,S::Parametric.targets(rule))
    assert_equal 0,plan['changed_count']
    assert S::Core.plan(rule,data,'qag1xnr2g4'=>1)['changed_count'].positive?
    assert_equal before,JSON.generate(data)
    broken=S::Core.copy_data(data);broken['parts'].first['bounds'][0][0]+=1
    assert_equal 'MILLIMETERS',S::DCOptions.scalar_lists(broken)['dc_inputs']['_qag1xnr2g4_units']
  end

  def test_root_mesh_inherits_exact_root_formulas_without_a_fake_thickness
    data=source('root-dimension-handle');rule=S::StudioCalculation.build_system([data])
    assert rule['formula_engine']
    refute(S::Parametric.variables(rule).any? { |row| %w[T1 T2].include?(row['symbol']) })
    values=S::Parametric.targets(rule)
    assert_in_delta 19.9898,values.fetch('mh_scale'),0.000001
    plan=S::Core.plan(rule,data,values)
    assert plan['changed_count'].positive?
    assert_in_delta 19.9898,S::Core.dimensions(plan['envelope'])[0],0.000001
    data=current(data,plan)
    2.times do
      plan=S::ScalePlan.plan(rule,S::ScalePlan.scaled_snapshot(data,[1.2,1,0.8]),values)
      assert_in_delta 19.9898,S::Core.dimensions(plan['envelope'])[0],0.000001
      assert_in_delta 127.9906,S::Core.dimensions(plan['envelope'])[2],0.000001
      data=current(data,plan)
      assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
    end
  end

  def test_inconsistent_saved_copy_geometry_still_requires_source_repair
    data=source('coincident-copy-source')
    refute S::StudioCalculation.build_system([data])['formula_engine']
  end

  def test_faceted_bevel_and_whole_module_wire_guide_follow_exact_panel_t
    data=source('bevel-linear-mesh');rule=S::StudioCalculation.build_system([data])
    original=JSON.generate(data)
    [20,25,18].each do |value|
      plan=S::Core.plan(rule,data,'dayvan'=>value)
      assert_in_delta value,S::Core.dimensions(plan['envelope'])[1],0.001
      guide=plan['parts'].find { |part| part['key']=='root:mesh' }
      assert_in_delta value,S::Core.dimensions(guide['bounds'])[1],0.001
      data=current(data,plan)
      assert_equal 0,S::Core.plan(rule,data,{})['changed_count']
    end
    values=S::Parametric.targets(rule)
    plan=S::ScalePlan.plan(rule,S::ScalePlan.scaled_snapshot(data,[1.1,1.2,0.9]),values)
    assert_in_delta 18,S::Core.dimensions(plan['envelope'])[1],0.001
    assert_in_delta 330,S::Core.dimensions(plan['envelope'])[0],0.001
    assert_in_delta 270,S::Core.dimensions(plan['envelope'])[2],0.001
    unverified=source('bevel-linear-mesh')
    unverified['parts'].each { |part| part.delete('linear_mesh_verified') }
    assert_raises(S::Core::Error) { S::Core.plan(rule,unverified,'dayvan'=>20) }
    assert_equal original,JSON.generate(source('bevel-linear-mesh'))
  end
end
