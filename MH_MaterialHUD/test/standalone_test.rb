# encoding: UTF-8
require 'minitest/autorun'
require_relative '../../MH_shared/material_code'
require_relative '../../MH_shared/text'
require_relative '../../MH_shared/name_grammar'
require_relative '../../MH_shared/product_context'
require_relative '../../MH_shared/project_data'

# Pure Ruby test harness: deliberately no MH_Thongke and no Registry app.
module Sketchup
  class Overlay; end
  class Group; end
  class ComponentInstance; end
  class Face; end
  class << self
    attr_accessor :active_model, :status_text
  end
end
module Geom
  class Transformation; end
end
module UI
  class << self
    attr_accessor :timers
    def start_timer(_delay, _repeat, &block)
      (self.timers ||= []) << block
      timers.size
    end
    def stop_timer(_id); end
  end
end
require_relative '../acceptances'
require_relative '../data'
require_relative '../model_index'
require_relative '../runtime'
require_relative '../viewport'

class MaterialHudStandaloneTest < Minitest::Test
  HUD = MH::MaterialHUD
  Catalog = HUD::Catalog

  def setup
    MH::MaterialCode.configure({})
    HUD.instance_variable_set(:@mode, 'view')
    HUD.instance_variable_set(:@overlay, nil)
    HUD.instance_variable_set(:@index, nil)
    HUD.instance_variable_set(:@catalog, nil)
    Sketchup.active_model = nil
    UI.timers = []
  end

  def teardown
    MH::MaterialCode.configure(nil)
  end

  def snapshot(rows, version = 1, model_key = MH::ProjectData.current_model_key)
    { ok: true, model_key: model_key, version: version, json_path: 'shared.json', rows_count: rows.size, rows: rows }
  end

  def row(code, product = 'SP03')
    { 'Ma_SP' => product, 'Ma_vat_lieu' => code }
  end

  def test_standalone_has_no_thongke_dependency
    refute defined?(MH_Thongke)
    refute defined?(MH::RegistryApp)
    catalog = Catalog.new(snapshot([row('ASH')]))
    assert_equal 'ASH', catalog.section('SP03', {}, 0).first[:name]
  end

  def test_split_deduplicate_group_modules_and_preserve_notes
    rows = [row('ASH & MDFCA.AC.LAM.L8304', 'SP03.01').merge('ghi_chu' => 'test'), row('ASH & MDFCA.AC.LAM.L8304', 'SP03.02').merge('ghi_chu' => 'test')]
    result = Catalog.new(snapshot(rows)).section('SP03', {}, 0)
    assert_equal ['ASH', 'MDFCA.AC.LAM.L8304'], result.map { |r| r[:name] }
    assert result.all? { |r| r[:note] == 'test' && r[:status] == 'SPEC' }
  end

  def test_catalog_uses_shared_material_specification_for_the_second_column
    rows = [row('MDFCA.AC.LAM.L8304').merge(
      'Excel_E' => 'MẶT VÁCH',
      'Excel_F' => 'GỖ MDFCA AC E1 PHỦ LAMINATE',
      'Excel_G' => 'L8304 KEding'
    )]
    result = Catalog.new(snapshot(rows)).section('SP03', {}, 0).first
    assert_equal 'MẶT VÁCH GỖ MDFCA AC E1 PHỦ LAMINATE L8304 KEding', result[:note]
  end

  def test_same_count_reload_does_not_keep_old_codes
    assert HUD.accept_snapshot(snapshot([row('OLD')]))
    old = HUD.instance_variable_get(:@catalog)
    assert HUD.accept_snapshot(snapshot([row('NEW')], 2))
    fresh = HUD.instance_variable_get(:@catalog)
    refute_same old, fresh
    assert_equal ['NEW'], fresh.section('SP03', {}, 1).map { |r| r[:name] }
  end

  def test_wrong_model_and_failed_reload_clear_previous_data
    HUD.accept_snapshot(snapshot([row('OLD')]))
    refute HUD.accept_snapshot(snapshot([row('OTHER')], 2, 'another_model'))
    assert_nil HUD.instance_variable_get(:@catalog)
    HUD.accept_snapshot(snapshot([row('OLD')]))
    refute HUD.accept_snapshot({ ok: false, error: 'bad json' })
    assert_nil HUD.instance_variable_get(:@catalog)
    assert_equal [], HUD.data[:rows]
  end

  def test_material_matching_ignores_thickness_and_face_variant_not_family
    logical = Catalog.material_key('PLY.AC.LK.4555A')
    actual = Catalog.material_key('PLY.17.AC.LK.4555A.2M')
    assert Catalog.matches?(logical, actual)
    refute Catalog.matches?(Catalog.material_key('PLY.AC'), Catalog.material_key('PLY.AC.VERKT.30YY-68'))
    assert Catalog.matches?('PLY.AC.30YY-68', 'PLY.AC.30YY-68/024-30')
  end

  def test_model_change_invalidates_matched_status
    catalog = Catalog.new(snapshot([row('ASH')]))
    assert_equal 'OK', catalog.section('SP03', { 'ASH' => 'ASH' }, 1).first[:status]
    rows = catalog.section('SP03', { 'PLY' => 'PLY' }, 2)
    assert_equal ['SPEC', 'NO SPEC'], rows.map { |r| r[:status] }
  end

  def test_incomplete_index_never_claims_missing_or_matching
    catalog = Catalog.new(snapshot([row('ASH')]))
    assert_equal '…', catalog.section('SP03', {}, 1, complete: false).first[:status]
    assert_equal 'OK', catalog.section('SP03', { 'ASH' => 'ASH' }, 1, complete: true).first[:status]
  end

  def test_tab_toggles_once_per_press_and_does_not_claim_other_keys
    tool = HUD::InteractionTool.new
    assert tool.onKeyDown(9, 1, 0, nil)
    assert_equal 'select', HUD.mode
    tool.onKeyDown(9, 2, 0, nil)
    assert_equal 'select', HUD.mode
    assert tool.onKeyUp(9, 1, 0, nil)
    tool.onKeyDown(9, 1, 0, nil)
    assert_equal 'view', HUD.mode
    refute tool.onKeyDown(65, 1, 0, nil)
  end

  def test_rules_snapshot_restores_after_nested_exception
    assert_raises(RuntimeError) do
      MH::MaterialCode.with_rules_snapshot do
        first = MH::MaterialCode.rules
        MH::MaterialCode.with_rules_snapshot { assert_same first, MH::MaterialCode.rules }
        raise 'test'
      end
    end
    assert_nil MH::MaterialCode.instance_variable_get(:@rules_snapshot)
  end

  def test_empty_model_index_finishes_without_timer_loop
    index = HUD::ModelIndex.new(Struct.new(:entities).new([]))
    assert index.step
    assert index.complete
  end

  def test_color_values_are_not_material_codes
    refute HUD::ModelIndex.displayable_material_name?('#FFFFFF')
    refute HUD::ModelIndex.displayable_material_name?('#FFFFF')
    refute HUD::ModelIndex.displayable_material_name?('rgb(255, 255, 255)')
    refute HUD::ModelIndex.displayable_material_name?('Color_FFFFFF')
    assert HUD::ModelIndex.displayable_material_name?('MDFCA.AC.LAM.L8304')
  end

  def test_saved_approval_does_not_match_other_product_or_any_target
    approvals = HUD::Acceptances.new({ 'SP05|VL|MDFCA.PANEL||' => { 'action' => 'accept' } })
    assert approvals.accepted?('SP05', 'MDFCA.PANEL', '')
    refute approvals.accepted?('SP04', 'MDFCA.PANEL', '')
    refute approvals.accepted?('SP05', 'MDFCA.PANEL', 'ASH')
  end

  def test_index_yields_work_and_finishes
    entity = Object.new
    def entity.valid?; true; end
    index = HUD::ModelIndex.new(Struct.new(:entities).new(Array.new(20, entity)))
    refute index.step(0)
    refute index.complete
    25.times { break if index.step(0) }
    assert index.complete
    assert_equal 20, index.visited
  end

  def test_stopping_incomplete_index_allows_restart
    HUD.instance_variable_set(:@index, HUD::ModelIndex.new(Struct.new(:entities).new([])))
    HUD.stop_timers
    assert_nil HUD.index
  end

  def test_view_select_switch_reuses_index_and_unchanged_refresh_does_not_redraw
    view = Object.new
    view.instance_variable_set(:@invalidations, 0)
    def view.invalidate; @invalidations += 1; end
    def view.invalidations; @invalidations; end
    model = Struct.new(:path, :guid, :selection, :active_path, :active_view).new('test.skp', 'test', [], [], view)
    Sketchup.active_model = model
    HUD.instance_variable_set(:@overlay_model, model)
    overlay = Object.new
    def overlay.enabled?; true; end
    HUD.instance_variable_set(:@overlay, overlay)
    index = Object.new
    def index.complete; true; end
    def index.visible_products(_view); ['SP03']; end
    def index.materials; { 'SP03' => { 'ASH' => 'ASH' } }; end
    HUD.instance_variable_set(:@index, index)
    HUD.instance_variable_set(:@index_revision, 1)
    MH::ProjectData.stub(:snapshot, snapshot([row('ASH')])) do
      HUD.refresh
      assert_equal ['SP03'], HUD.data[:products]
      first = view.invalidations
      HUD.refresh
      assert_equal first, view.invalidations
      HUD.toggle_mode
      assert_equal [], HUD.data[:products]
      HUD.toggle_mode
      assert_equal ['SP03'], HUD.data[:products]
      assert_same index, HUD.index
    end
  end
end
