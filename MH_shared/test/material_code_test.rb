# encoding: UTF-8

require 'minitest/autorun'
require_relative '../material_code'
require_relative '../../MH_Registry/connectors/dc_import/material_code'

class MaterialCodeTest < Minitest::Test
  RULES = {
    'parent_codes' => ['PLY.AC.VER', 'PLY.AC.LK', 'MDFCA.AC.MS'],
    'surface_groups' => {
      'SON' => { 'members' => ['SON'] },
      'LK' => { 'members' => ['LK'] },
      'VER' => { 'members' => ['VER', 'VERKT', 'VERSOI', 'VERKTSOI'] },
      'MS' => { 'members' => ['MS'] }
    }
  }.freeze

  MAPPINGS = [
    { 'min' => 7.5, 'max' => 8.5, 'value' => '8' },
    { 'min' => 16.5, 'max' => 17.9, 'value' => '17' },
    { 'min' => 18.0, 'max' => 18.9, 'value' => '18' }
  ].freeze

  def setup
    MH::MaterialCode.configure(RULES)
  end

  def teardown
    MH::MaterialCode.configure(nil)
  end

  def test_normalizes_and_replaces_thickness
    assert_equal 'MDFCA.AC.MS.333PL', MH::MaterialCode.without_thickness('mdfca.17.ac.ms.333pl')
    assert_equal 'MDFCA.18.AC.MS.333PL', MH::MaterialCode.material_name('mdfca.17.ac.ms.333pl', 18.6, mappings: MAPPINGS)
  end

  def test_handles_multi_material_and_surface_suffixes
    assert_equal ['PLY.AC.LK.4555A', 'HDFCA.AC.VERSOI.2M-BCT'], MH::MaterialCode.split('ply.ac.lk.4555a & hdfca.ac.versoi.2m-bct')
    assert MH::MaterialCode.surface_variant?('PLY.17.AC.LK.4555A.1M-BCT')
    assert_equal 'PLY.AC.LK.4555A', MH::MaterialCode.strip_surface_variant('PLY.AC.LK.4555A.2M')
    assert_equal ['PLY', 'AC', 'LK', '4555A'], MH::MaterialCode.family_parts('PLY.17.AC.LK.4555A.1M')
  end

  def test_veneer_variants_share_the_registry_veneer_group
    assert_equal 'VER', MH::MaterialCode.finish_group('HDFCA.AC.VERSOI')
    assert_equal 'VER', MH::MaterialCode.finish_group('HDFCA.AC.VERKT')
  end

  def test_veneer_parent_candidates_follow_the_registry_group
    candidates = MH::MaterialCode.parent_candidates('PLY.AC.VERSOI.30YY-68/024-30')
    assert_equal 'PLY.AC.VER', candidates.first
    assert_includes candidates, 'PLY.AC.VERSOI'
  end

  def test_handles_mh_tags_and_unmapped_thickness
    assert_equal 'SAT', MH::MaterialCode.material_name('MH_Sat', 17.0, mappings: MAPPINGS)
    assert_nil MH::MaterialCode.material_name('MDFCA.AC.MS', 12.0, mappings: MAPPINGS)
    assert_equal 'MDFCA.12.AC.MS', MH::MaterialCode.material_name('MDFCA.AC.MS', 12.0, mappings: MAPPINGS, fallback_to_actual: true)
  end

  def test_dc_import_uses_the_same_shared_resolution
    pipeline = MH::RegistryApp::Connectors::DCImportPipeline
    pipeline.instance_variable_set(:@thickness_map, MAPPINGS)

    expected = MH::MaterialCode.material_name('PLY.AC.LK.4555A', 17.6, mappings: MAPPINGS, fallback_to_actual: true)
    assert_equal expected, pipeline.material_name_from_code('PLY.AC.LK.4555A', 17.6)
  end
end
