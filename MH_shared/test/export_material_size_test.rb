# encoding: UTF-8
require 'minitest/autorun'
require 'tmpdir'
$LOAD_PATH.unshift(File.expand_path('../vendor/rubyzip/lib', __dir__))
require 'zip'
require_relative '../excel_bridge'

class ExportMaterialSizeTest < Minitest::Test
  def test_nominal_size_comes_only_from_the_thickness_position
    {
      'GGT.18' => '18', 'MDFCA.17.AC.LAM.2M-BCT' => '17',
      'PLY.17.E0.AC' => '17', 'MDFCA.17,6.AC' => '17.6',
      'GGT.18.6' => '18.6', ' GGT.018.00 ' => '18',
      'MDFCA.E1.AC.LAM.P7013' => 'original', 'MDFCA.AC.SON.BQ123-30' => 'original',
      'GGT.1M' => 'original', 'GGT.0' => 'original',
      'GGT.18 & PLY.8' => 'original'
    }.each do |code, expected|
      assert_equal expected, MH::MaterialCode.export_size(code, fallback: 'original'), code
    end
  end

  def test_all_shared_report_writes_use_the_code_and_preserve_edge_sizes
    rows = [
      ['STT', 'Tên hàng', 'Kích thước', 'Mã hiệu', 'Đơn vị'],
      [1, 'Gỗ ghép thanh', '18.6mm', 'GGT.18', 'tấm'],
      [2, 'Nẹp 22', '1mm', 'GGT.18', 'md'],
      [3, 'Ván', '8mm', 'MDFCA.AC.MEL.MS123', 'tấm']
    ]
    Dir.mktmpdir('mh_export_sizes_') do |directory|
      path = File.join(directory, 'report.xlsx')
      MH::ExcelBridge.write(path, sheets: { 'DMVT' => rows })
      exported = MH::ExcelBridge.read_all(path)['DMVT']
      assert_equal ['18', '1mm', '8mm'], exported.drop(1).map { |r| r[2] }
      assert_equal '18.6mm', rows[1][2]
    end
  end

  def test_material_report_with_metadata_and_code_in_name
    rows = [
      ['Ngày nesting', '13/10/2026'], [],
      ['STT', 'Tên hàng', 'Dày', '', 'ĐVT'],
      [1, 'GGT.18', '18.6', '', 'm2'],
      [2, 'Tay nắm', '128x20', '', 'cái']
    ]
    prepared = MH::ExcelBridge.material_export_sizes(rows)
    assert_equal '18', prepared[3][2]
    assert_equal '128x20', prepared[4][2]
    assert_equal rows.first, prepared.first
  end

  def test_hash_exports_use_the_same_rule
    Dir.mktmpdir('mh_export_sizes_') do |directory|
      path = File.join(directory, 'hash_report.xlsx')
      MH::ExcelBridge.write_hashes(path, sheet_name: 'Report', rows: [
        { 'size' => '18.6mm', 'material_code' => 'GGT.18', 'unit' => 'tấm' }
      ])
      assert_equal '18', MH::ExcelBridge.read_all(path)['Report'][1][0]
    end
  end
end
