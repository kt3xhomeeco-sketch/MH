# encoding: UTF-8

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
$LOAD_PATH.unshift(File.expand_path('../../MH_shared/vendor/rubyzip/lib', __dir__))
require 'zip'
require_relative '../../MH_shared/xlsx_io'

# Load the real export module without SketchUp or its extension menus.
$LOADED_FEATURES << 'sketchup.rb'
$LOADED_FEATURES << 'MH_shared.rb'
def file_loaded?(_path)
  true
end
require_relative '../main'

class ExportItemNameTest < Minitest::Test
  BASE_CODE = 'MDFCA.17.AC.LK.P7013(KEDING)'.freeze
  BASE_NAME = 'MDF CHỐNG ẨM AN CƯỜNG PHỦ LAMINATE'.freeze

  def setup
    @previous_directory = ENV['MH_NHAP_XUATVAN_LIBRARY']
    @directory = Dir.mktmpdir('mh_material_names_')
    ENV['MH_NHAP_XUATVAN_LIBRARY'] = @directory
    FileUtils.cp(File.expand_path('../../MH_shared/material_item_names.py', __dir__), @directory)
    @rows = [
      ['Từ khóa trong Excel', 'Mã tạo ra', 'Nhóm', 'Đang dùng', 'Thứ tự'],
      ['#', nil, nil, nil, nil],
      ['MDF chống ẩm', 'MDFCA', 'chat_lieu', 'Có', 1],
      ['Ván nhựa An Cường', 'WPB', 'chat_lieu', 'Có', 1],
      ['An Cường', 'AC', 'nha_cung_cap', 'Có', 4],
      ['Laminate', 'LAM', 'be_mat', 'Có', 5],
      ['Veneer', 'VER', 'be_mat', 'Có', 5],
      ['Veneer kỹ thuật', 'VERKT', 'be_mat', 'Có', 5],
      ['Tên tắt không được dùng', 'MDFCA', 'chat_lieu', 'Không', 0],
      ['Màu hoàn thiện', 'L8304', 'finish_code', 'Có', 6]
    ]
    save_config
  end

  def teardown
    ENV['MH_NHAP_XUATVAN_LIBRARY'] = @previous_directory
    FileUtils.remove_entry(@directory)
  end

  def save_config
    MH::XlsxIO.write(File.join(@directory, 'material_code_library.xlsx'),
                      'Huong_dan' => [['Giữ nguyên sheet hướng dẫn']], 'mapping' => @rows,
                      'ma_thickness' => [['min', 'max', 'value'], [17.5, 17.7, 17]])
  end

  def item_name(code)
    MH::Export.export_item_name(MH::Export.board_row_name(code))
  end

  def test_each_face_count
    assert_equal "#{BASE_NAME} 1 MẶT", item_name("#{BASE_CODE}.1M")
    assert_equal "#{BASE_NAME} 2 MẶT", item_name("#{BASE_CODE}.2M")
  end

  def test_standalone_backer_suffixes
    assert_equal "#{BASE_NAME} BACKER TRẮNG", item_name("#{BASE_CODE}-BCT")
    assert_equal "#{BASE_NAME} BACKER ĐEN", item_name("#{BASE_CODE}-BCĐ")
  end

  def test_all_combined_face_and_backer_suffixes
    { 'BCT' => 'TRẮNG', 'BCĐ' => 'ĐEN' }.each do |backer, color|
      [1, 2].each do |count|
        assert_equal "#{BASE_NAME} #{count} MẶT BACKER #{color}",
                     item_name("#{BASE_CODE}.#{count}M-#{backer}")
      end
    end
  end

  def test_lowercase_and_whitespace
    assert_equal "#{BASE_NAME} 2 MẶT BACKER ĐEN",
                 item_name("  #{BASE_CODE.downcase}.2m-bcđ  ")
  end

  def test_qualifiers_before_paint_code
    base, labels = MH::Export.material_item_name_qualifiers("#{BASE_CODE}.1M-BCĐ.BQ123-30")
    assert_equal "#{BASE_CODE}.BQ123-30", base
    assert_equal ['1 mặt', 'backer đen'], labels
    assert_equal "#{BASE_NAME} 1 MẶT BACKER ĐEN",
                 item_name("#{BASE_CODE}.1M-BCĐ.BQ123-30")
  end

  def test_does_not_translate_embedded_identifiers
    %w[X1M 2M123 BCT123 BCĐ123 1M-OTHER OTHER-BCT123].each do |finish|
      code = "MDFCA.17.AC.LK.#{finish}"
      assert_equal [code, []], MH::Export.material_item_name_qualifiers(code)
    end
  end

  def test_no_qualifiers_preserves_existing_name_and_supplier_deduplication
    assert_equal BASE_NAME, item_name(BASE_CODE)
    assert_equal 'VÁN NHỰA AN CƯỜNG', item_name('WPB.17.AC')
    assert_equal 'VÁN NHỰA AN CƯỜNG 2 MẶT BACKER TRẮNG', item_name('WPB.17.AC.2M-BCT')
  end

  def test_unmapped_base_is_not_lost
    assert_equal 'VÁN UNKNOWN.17 1 MẶT BACKER ĐEN', item_name('UNKNOWN.17.1M-BCĐ')
    assert_equal 'VÁN UNKNOWN.17', item_name('UNKNOWN.17')
    assert_equal 'VÁN', item_name('')
  end

  def test_duplicate_qualifiers_are_not_repeated
    assert_equal "#{BASE_NAME} 1 MẶT BACKER TRẮNG",
                 item_name("#{BASE_CODE}-BCT.1M-BCT")
  end

  def test_preview_translates_names_without_changing_codes_or_quantities
    codes = %w[1M-BCT 2M-BCĐ].map { |suffix| "#{BASE_CODE}.#{suffix}" }
    input = codes.map do |code|
      { name: 'Ván', size: '1220x2440', material_code: code, unit: 'tấm', quantity: 3, note: '' }
    end
    [true, false].each do |show_paint|
      rows = MH::Export.regroup_preview_rows(input, show_paint)
      assert_equal codes, rows.map { |row| row[:material_code] }
      assert_equal [3, 3], rows.map { |row| row[:quantity] }
      assert_equal ["#{BASE_NAME} 1 MẶT BACKER TRẮNG", "#{BASE_NAME} 2 MẶT BACKER ĐEN"],
                   rows.map { |row| row[:name] }
    end
  end
  def test_exact_tokens_longest_codes_and_registry_aliases
    assert_equal 'MDF CHỐNG ẨM AN CƯỜNG PHỦ VENEER KỸ THUẬT', item_name('MDFCA.17.AC.VERKT')
    assert_equal BASE_NAME, item_name('MDFCA.17.AC.LAM')
    assert_equal 'VÁN XMDFCA.17.AC123.LK123', item_name('XMDFCA.17.AC123.LK123')
  end

  def test_shared_workbook_changes_are_visible_without_restart
    assert_equal BASE_NAME, item_name(BASE_CODE)
    @rows[2][0] = 'MDF chống ẩm mới'
    save_config
    assert_equal 'MDF CHỐNG ẨM MỚI AN CƯỜNG PHỦ LAMINATE', item_name(BASE_CODE)
  end

  def test_preview_uses_one_python_call_then_reuses_cache
    calls = 0
    original = MH::MaterialItemNames.method(:request)
    counted = lambda do |payload, python|
      calls += 1
      original.call(payload, python)
    end
    rows = ['MDFCA.17.AC.LK', 'WPB.17.AC', 'MDFCA.17.AC.VERKT'].map do |code|
      { name: 'Ván', size: '1220x2440', material_code: code, unit: 'tấm', quantity: 3, note: '' }
    end
    MH::MaterialItemNames.stub(:request, counted) do
      2.times { MH::Export.regroup_preview_rows(rows, true) }
    end
    assert_equal 1, calls
  end

  def test_missing_library_fails_instead_of_using_a_private_dictionary
    File.delete(File.join(@directory, 'material_code_library.xlsx'))
    error = assert_raises(RuntimeError) { item_name(BASE_CODE) }
    assert_includes error.message, 'Không tìm thấy thư viện'
  end

  def test_disabled_rows_and_finish_mapping_are_not_purchase_names
    @rows.insert(2, ['Sai tên', 'MDFCA', 'chat_lieu', 'Không', 0])
    @rows << ['E1', 'E1', 'tieu_chuan', 'Có', 3]
    save_config
    assert_equal BASE_NAME, item_name('MDFCA.17.AC.LAM.L8304')
    assert_equal 'MDF CHỐNG ẨM E1 AN CƯỜNG PHỦ LAMINATE', item_name('MDFCA.17.E1.AC.LAM')
  end

  def test_preview_groups_by_nominal_code_size_and_keeps_edge_thickness
    rows = ['17.6mm', '17.8mm'].map do |size|
      { name: 'Ván', size: size, material_code: 'MDFCA.17.AC.LAM', unit: 'tấm', quantity: 2 }
    end
    rows << { name: 'Nẹp 22', size: '1mm', material_code: 'MDFCA.17.AC.LAM', unit: 'md', quantity: 5 }
    preview = MH::Export.regroup_preview_rows(rows, true)
    board = preview.find { |row| row[:unit] == 'tấm' }
    assert_equal '17', board[:size]
    assert_equal 4, board[:quantity]
    assert_equal '1mm', preview.find { |row| row[:unit] == 'md' }[:size]
  end

end
