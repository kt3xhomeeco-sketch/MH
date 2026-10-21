# encoding: UTF-8

require 'minitest/autorun'
require_relative '../material_code'
require_relative '../../MH_Registry/connectors/dc_import/material_code'
require_relative '../../MH_Registry/connectors/dc_import/thickness_selection'

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

  def test_brand_finish_face_suffix_does_not_insert_an_implicit_paint_layer
    %w[1M 2M 1M-BCT 2M-BCT].each do |suffix|
      code = "MDFCA.18.AC.LK.P7013(KEDING).#{suffix}"
      parsed = MH::MaterialCode.parse(code)
      assert_equal "P7013(KEDING).#{suffix}", parsed[:finish_code]
      assert_equal 'MDFCA.AC.LK.P7013(KEDING)',
                   MH::MaterialCode.strip_surface_variant(MH::MaterialCode.without_thickness(code))
      refute_includes parsed[:segments], 'SON'
    end
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

  def test_dc_thickness_uses_the_configured_parent_layer_structure
    # Không có quy tắc E1/AC/TL nào trong pipeline. Sheet cấu trúc lớp quyết
    # định chỉ chat_lieu + be_mat được dùng để ghép nhóm cha độ dày.
    MH::MaterialCode.configure(RULES.merge(
      'layers' => [
        { 'key' => 'chat_lieu', 'required' => true },
        { 'key' => 'do_day', 'role' => 'thickness', 'optional' => true, 'pattern' => '\\A\\d+(?:[,.]\\d+)?\\z' },
        { 'key' => 'tieu_chuan', 'optional' => true },
        { 'key' => 'nha_cung_cap', 'optional' => true },
        { 'key' => 'be_mat', 'optional' => true },
        { 'key' => 'finish_code', 'role' => 'finish', 'optional' => true, 'capture_rest' => true }
      ],
      'mappings' => [
        { 'gia_tri' => 'E0', 'gia_tri_map' => 'E0', 'nhom' => '2_tieu_chuan' },
        { 'gia_tri' => 'E1', 'gia_tri_map' => 'E1', 'nhom' => '2_tieu_chuan' },
        { 'gia_tri' => 'FSC', 'gia_tri_map' => 'FSC', 'nhom' => '2_tieu_chuan' },
        { 'gia_tri' => 'AC', 'gia_tri_map' => 'AC', 'nhom' => '3_nha_cung_cap' },
        { 'gia_tri' => 'TL', 'gia_tri_map' => 'TL', 'nhom' => '3_nha_cung_cap' }
      ]
    ))
    pipeline = MH::RegistryApp::Connectors::DCImportPipeline
    expected = [{ 'panel_mm' => 17.6, 'back_mm' => 11 }]
    pipeline.instance_variable_set(:@thickness_group_layers, [
      { 'layer_key' => 'chat_lieu', 'include_in_thickness_parent' => true, 'parent_order' => 1 },
      { 'layer_key' => 'tieu_chuan', 'include_in_thickness_parent' => false, 'parent_order' => 2 },
      { 'layer_key' => 'nha_cung_cap', 'include_in_thickness_parent' => false, 'parent_order' => 3 },
      { 'layer_key' => 'be_mat', 'include_in_thickness_parent' => true, 'parent_order' => 4 }
    ])
    # Khóa thư viện là kết quả của chính cấu trúc lớp trên: MDFCA + MEL.
    pipeline.instance_variable_set(:@thickness_options_by_type, { 'MDFCA.MEL' => expected })

    %w[E0 E1 FSC].each do |standard|
      code = "MDFCA.#{standard}.TL.MEL.MS446FR"
      assert_equal 'MDFCA.MEL', pipeline.thickness_material_code_key(code)
      assert_equal expected, pipeline.thickness_options_for_material_code(code)
    end
  end
end
