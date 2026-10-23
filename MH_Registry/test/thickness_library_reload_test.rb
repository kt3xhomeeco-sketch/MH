# encoding: UTF-8
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
$LOAD_PATH.unshift(File.expand_path('../../MH_shared/vendor/rubyzip/lib', __dir__))
require 'zip'
require_relative '../../MH_shared/excel_bridge'
require_relative '../../MH_shared/material_code'
require_relative '../config_manager'
require_relative '../connectors/dc_import_pipeline'

class ThicknessLibraryReloadTest < Minitest::Test
  Pipeline = MH::RegistryApp::Connectors::DCImportPipeline

  def setup
    @previous_directory = ENV['MH_NHAP_XUATVAN_LIBRARY']
    @directory = Dir.mktmpdir('mh_thickness_reload_')
    ENV['MH_NHAP_XUATVAN_LIBRARY'] = @directory
    MH::MaterialCode.configure('mappings' => [
      { 'nhom' => 'chat_lieu', 'gia_tri_map' => 'PLY' },
      { 'nhom' => 'chat_lieu', 'gia_tri_map' => 'MDFCA' },
      { 'nhom' => 'tieu_chuan', 'gia_tri_map' => 'E0' },
      { 'nhom' => 'tieu_chuan', 'gia_tri_map' => 'E1' },
      { 'nhom' => 'nha_cung_cap', 'gia_tri_map' => 'AC' },
      { 'nhom' => 'nha_cung_cap', 'gia_tri_map' => 'TL' },
      { 'nhom' => 'be_mat', 'gia_tri_map' => 'VERSOI' },
      { 'nhom' => 'finish_code', 'gia_tri_map' => 'SON' }
    ])
    @rows = [['material_type', 'opt1_panel', 'opt1_back', 'opt2_panel', 'opt2_back'],
             ['PLY', '17.6', '11', '17.6', '8'],
             ['MDFCA.TL', '17.6', '11', '17.6', '8'],
             ['MDFCA.SON', '17.6', '11', '17.6', '8'],
             ['MDFCA.VERSOI.SON', '18.6', '11', '18.6', '8'],
             ['GGT', '18', '', '25', '']]
    save_library
    # Reproduce the open session: config was loaded while the old path was missing.
    Pipeline.on_config_changed({})
  end

  def teardown
    ENV['MH_NHAP_XUATVAN_LIBRARY'] = @previous_directory
    MH::MaterialCode.configure(nil)
    FileUtils.remove_entry(@directory)
  end

  def save_library
    MH::RegistryApp.safe_write_xlsx(MH::MaterialLibrary.path, {
      'dc_thickness_options' => @rows,
      'dc_thickness_group_layers' => [
        ['layer_key', 'include_in_thickness_parent', 'parent_order'],
        ['chat_lieu', '1', '1'], ['do_day', '0', '2'],
        ['tieu_chuan', '0', '3'], ['nha_cung_cap', '0', '4'], ['be_mat', '1', '5'],
        ['finish_code', '1', '6']
      ],
      'ma_thickness' => [['min', 'max', 'value'], ['17.5', '17.7', '17']]
    })
  end

  def test_empty_open_session_recovers_options_for_the_screenshot_materials
    before = File.binread(MH::MaterialLibrary.path)
    %w[PLY.17.E0.AC MDFCA.17.E1.TL MDFCA.AC.SON].each do |code|
      assert_equal [17.6, 17.6], Pipeline.thickness_options_for_material_code(code).map { |o| o['panel_mm'] }
    end
    assert_equal [18.0, 25.0], Pipeline.thickness_options_for_material_code('GGT').map { |o| o['panel_mm'] }
    assert_equal before, File.binread(MH::MaterialLibrary.path)
  end

  def test_surface_and_finish_code_select_their_specific_thickness_group
    assert_equal [17.6, 17.6], Pipeline.thickness_options_for_material_code('MDFCA.E1.AC.SON').map { |o| o['panel_mm'] }
    assert_equal [18.6, 18.6], Pipeline.thickness_options_for_material_code('MDFCA.E1.AC.VERSOI.SON').map { |o| o['panel_mm'] }
  end

  def test_repeated_hud_reads_do_not_reopen_excel
    original = MH::ExcelBridge.method(:read_all)
    calls = 0
    counted = lambda { |path| calls += 1; original.call(path) }
    MH::ExcelBridge.stub(:read_all, counted) do
      5.times { Pipeline.thickness_options_for_material_code('GGT') }
    end
    assert_equal 1, calls
  end

  def test_changed_workbook_invalidates_cached_options
    Pipeline.thickness_options_for_material_code('GGT')
    @rows[-1][1] = '20'
    save_library
    # Advance the periodic check without a wall-clock sleep.
    Pipeline.instance_variable_set(:@thickness_library_checked_at, nil)
    assert_equal [20.0, 25.0], Pipeline.thickness_options_for_material_code('GGT').map { |o| o['panel_mm'] }
  end

  def test_stale_json_snapshot_cannot_keep_the_library_cache_empty
    Pipeline.thickness_options_for_material_code('GGT')
    Pipeline.on_config_changed({})
    assert_equal [18.0, 25.0], Pipeline.thickness_options_for_material_code('GGT').map { |o| o['panel_mm'] }
  end
end
