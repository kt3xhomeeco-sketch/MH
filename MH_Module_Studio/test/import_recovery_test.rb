# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioImportRecoveryTest < Minitest::Test
  S=MH::ModuleStudio

  def data
    snapshot=JSON.parse(File.read(File.join(__dir__,'fixtures/readable_nested_dc.json'),encoding:'UTF-8'))
    rule=S::StudioCalculation.build_system([snapshot])
    {'rule'=>rule,'snapshot'=>snapshot,'values'=>S::Parametric.targets(rule)}
  end

  def test_restores_saved_formula_geometry_without_mutating_source_data_or_current
    payload=data;current=S::Core.copy_data(payload['snapshot'])
    current['parts'].first['bounds'][1][0]+=8
    before=Marshal.dump([payload,current])
    result=S::ImportRecovery.plan(payload,current)
    assert_equal 1,result['changed_count']
    assert_equal payload['snapshot']['parts'].first['bounds'],result['parts'].first['bounds']
    assert_equal current['parts'].first['bounds'],result['parts'].first['old_bounds']
    assert_equal before,Marshal.dump([payload,current])
    assert_raises(S::Core::Error) { S::Core.plan(payload['rule'],current,payload['values']) }
  end

  def test_rejects_changed_topology_visibility_ids_and_inconsistent_saved_formulas
    payload=data
    %w[key face_count edge_count visible].each do |field|
      current=S::Core.copy_data(payload['snapshot'])
      current['parts'].first[field]=field=='key' ? 'unknown-part' : field=='visible' ? false : 999
      assert_raises(S::Core::Error,field) { S::ImportRecovery.plan(payload,current) }
    end
    payload['snapshot']['parts'].first['bounds'][1][0]+=8
    assert_raises(S::Core::Error) { S::ImportRecovery.plan(payload,payload['snapshot']) }
  end
end
