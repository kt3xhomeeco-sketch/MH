# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioAssemblyProbeTest < Minitest::Test
  S = MH::ModuleStudio

  def captured
    JSON.parse(File.read(File.join(__dir__,'fixtures/legacy-assembly-door.json'),encoding:'UTF-8'))
  end

  def test_virtual_scale_probe_keeps_source_data_and_resolves_formula_thickness
    data = captured; before = JSON.generate(data)
    current = data['snapshot']
    [0.8,1.2].each do |factor|
      scaled = S::ScalePlan.scaled_snapshot(current,[factor,factor,factor])
      plan = S::ScalePlan.plan(data['rule'],scaled,data['values'])
      assert_in_delta 17.6,S::Core.dimensions(plan['envelope'])[1],0.000001
      [0,2].each { |axis| assert_in_delta S::Core.dimensions(current['envelope'])[axis]*factor,S::Core.dimensions(plan['envelope'])[axis],0.000001 }
      assert_in_delta current.dig('dc_graph','root_frame',0)*factor,scaled.dig('dc_graph','root_frame',0),0.000001
    end
    assert_equal before,JSON.generate(data)
  end

  def test_invalid_probe_factors_do_not_mutate_source
    data = captured; before = JSON.generate(data)
    [nil,[],[1,2],[1,0,1],[1,-1,1],[1,Float::INFINITY,1],[1,'bad',1]].each do |factors|
      assert_raises(S::Core::Error) { S::ScalePlan.scaled_snapshot(data['snapshot'],factors) }
    end
    assert_equal before,JSON.generate(data)
  end
end
