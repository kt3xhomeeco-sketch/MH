# encoding: UTF-8
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
$LOAD_PATH.unshift(File.expand_path('../vendor/rubyzip/lib', __dir__))
require 'zip'
require_relative '../excel_bridge'
require_relative '../registry_api'
require_relative '../material_item_names'
require_relative '../../MH_Registry/config_manager'

class MaterialLibraryTest < Minitest::Test
  def setup
    @previous_directory = ENV['MH_NHAP_XUATVAN_LIBRARY']
    @directory = Dir.mktmpdir('mh_shared_workbook_')
    ENV['MH_NHAP_XUATVAN_LIBRARY'] = @directory
    @sheets = {
      'Huong_dan' => [['Hướng dẫn phải được giữ']],
      'mapping' => [['Từ khóa trong Excel', 'Mã tạo ra', 'Nhóm', 'Đang dùng', 'Thứ tự'],
                    ['MDF chống ẩm', 'MDFCA', 'chat_lieu', 'Có', '1']],
      'dc_thickness_options' => [['material_type', 'opt1_panel', 'opt1_back'], ['MDFCA', '17.6', '8']],
      'material_code_exclusions' => [['Từ khóa'], ['Sơn tĩnh điện']],
      'material_code_rules' => [['Quy tắc', 'Giá trị'], ['Dấu ghép các phần', '.']],
      'dc_thickness_group_layers' => [['layer_key'], ['chat_lieu']],
      'ma_thickness' => [['min', 'max', 'value'], ['17.5', '17.7', '17']],
      'ma_detail_aliases' => [['pattern', 'target'], ['VÁCH', 'VACH']],
      'ma_tag_materials' => [['tag_name', 'material_name']],
      'ma_surface_face_rules' => [['material_pattern', 'face_count']],
      'ma_column_aliases' => [['internal_name', 'alias']]
    }
    MH::ExcelBridge.write(MH::MaterialLibrary.path, sheets: @sheets)
  end

  def teardown
    ENV['MH_NHAP_XUATVAN_LIBRARY'] = @previous_directory
    FileUtils.remove_entry(@directory)
  end

  def test_all_public_readers_and_writers_resolve_the_same_workbook
    expected = File.join(@directory, 'material_code_library.xlsx')
    assert_equal expected, MH::Registry.material_code_library_path
    assert_equal expected, MH::RegistryApp.material_code_library_path
    assert_equal expected, MH::MaterialItemNames.config_path
  end

  def test_material_assign_and_superimp_load_from_the_shared_path
    data = {}
    MH::RegistryApp.merge_material_assign_config_from_material_code_library!(data)
    assert_equal '17', data.fetch('ma_thickness').first.fetch('value')
    assert_equal 'MDFCA', data.fetch('dc_thickness_options_library').first.fetch('material_type')
    assert_equal '17.6', data.fetch('dc_thickness_options_library').first.fetch('options').first.fetch('panel')
  end

  def test_hot_reload_removes_old_accessors_and_frozen_paths
    [MH::Registry, MH::RegistryApp].each do |target|
      target.define_singleton_method(:material_code_library_path) { 'old/missing/library.xlsx' }
      target.const_set(:MATERIAL_CODE_LIBRARY_PATH, 'old/missing/library.xlsx'.freeze)
      MH::MaterialLibrary.attach(target)
      assert_equal MH::MaterialLibrary.path, target.material_code_library_path
      assert_equal MH::MaterialLibrary::Accessors, target.method(:material_code_library_path).owner
      refute target.const_defined?(:MATERIAL_CODE_LIBRARY_PATH, false)
    end
  end

  def test_repeated_binding_and_directory_changes_do_not_capture_a_path
    2.times { MH::MaterialLibrary.attach(MH::RegistryApp) }
    ENV['MH_NHAP_XUATVAN_LIBRARY'] = File.join(@directory, 'new_location')
    expected = File.join(@directory, 'new_location', 'material_code_library.xlsx')
    assert_equal expected, MH::Registry.material_code_library_path
    assert_equal expected, MH::RegistryApp.material_code_library_path
  end

end
