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
    attr_accessor :timers, :timer_delays
    def start_timer(delay, _repeat, &block)
      (self.timer_delays ||= []) << delay
      (self.timers ||= []) << block
      timers.size
    end
    def stop_timer(_id); end
  end
end
require_relative '../acceptances'
require_relative '../data'
require_relative '../model_index'
require_relative '../product_store'
require_relative '../runtime'
require_relative '../viewport'
require_relative 'product_store_cases'

class ProductPhysicalBoundsTest < Minitest::Test
  def test_flat_annotation_sharing_a_board_x_range_has_no_owner
    board, flat = Sketchup::Group.new, Sketchup::Group.new
    points = [Struct.new(:x).new(0), Struct.new(:x).new(10)]
    context = { entity_ranges: {[board,0.0,10.0]=>'SP06', [flat,0.0,10.0]=>''} }
    MH::ProductContext.stub(:world_x_context, context) do
      assert_equal 'SP06', MH::ProductContext.infer_spatial_product(points, model:Object.new, entity:board)
      assert_equal '', MH::ProductContext.infer_spatial_product(points, model:Object.new, entity:flat)
    end
  end

  def test_flat_and_collapsed_instances_never_supply_product_evidence
    bounds = Struct.new(:width, :height, :depth) { def empty?; false; end }
    transform = Struct.new(:values) { def to_a; values; end }
    identity = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    rotate = [1,0,0,0,0,Math.sqrt(0.5),Math.sqrt(0.5),0,0,-Math.sqrt(0.5),Math.sqrt(0.5),0,0,0,0,1]
    assert MH::ProductContext.physical_product_bounds?(bounds.new(10,20,0.01), transform.new(identity))
    refute MH::ProductContext.physical_product_bounds?(bounds.new(10,20,0), transform.new(rotate))
    collapsed = identity.dup
    collapsed[10] = 0
    refute MH::ProductContext.physical_product_bounds?(bounds.new(10,20,30), transform.new(collapsed))
    sheared_flat = identity.dup
    sheared_flat[8,3] = [1,1,0]
    refute MH::ProductContext.physical_product_bounds?(bounds.new(10,20,30), transform.new(sheared_flat))
  end
end

class MaterialHudStandaloneTest < Minitest::Test
  HUD = MH::MaterialHUD
  Catalog = HUD::Catalog

  def setup
    MH::MaterialCode.configure({})
    HUD.instance_variable_get(:@product_store)&.dispose
    HUD.instance_variable_set(:@product_store, nil)
    HUD.instance_variable_set(:@pending_model_change, false)
    HUD.stop_timers
    HUD.instance_variable_set(:@pending_view_change, false)
    HUD.instance_variable_set(:@camera_event_signature, nil)
    HUD.instance_variable_set(:@mode, 'view')
    HUD.instance_variable_set(:@overlay, nil)
    HUD.instance_variable_set(:@index, nil)
    HUD.reset_selection_material_indexes
    HUD.instance_variable_set(:@selection_resolver, nil)
    HUD.instance_variable_set(:@selection_resolver_model, nil)
    HUD.instance_variable_set(:@picked_path, nil)
    HUD.instance_variable_set(:@picked_selection_ids, nil)
    HUD.instance_variable_set(:@picked_paths_by_entity, {})
    HUD.instance_variable_set(:@catalog, nil)
    Sketchup.active_model = nil
    UI.timers = []
    UI.timer_delays = []
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

  def test_catalog_keeps_product_name_from_shared_json
    catalog = Catalog.new(snapshot([row('ASH', 'SP03').merge('Ten_SP' => 'VÁCH ỐP HÀNH LANG')]))
    assert_equal 'VÁCH ỐP HÀNH LANG', catalog.product_name('SP03')
    assert_equal 'VÁCH ỐP HÀNH LANG', catalog.section('SP03', {}, 0).first[:product_name]
  end

  def test_material_options_include_product_name_description_and_code
    source_row = row('MDFCA.AC.LAM.L8304', 'SP03').merge(
      'Ten_SP' => 'VÁCH ỐP HÀNH LANG',
      'Quy_cach_vat_lieu' => 'MẶT VÁCH MDF PHỦ LAMINATE'
    )
    option = Catalog.new(snapshot([source_row])).material_options_for_product('SP03').first

    assert_equal 'VÁCH ỐP HÀNH LANG', option[:product_name]
    assert_equal '', option[:detail]
    assert_equal 'MẶT VÁCH MDF PHỦ LAMINATE', option[:description]
    assert_equal 'MDFCA.AC.LAM.L8304', option[:code]
  end

  def test_material_options_split_excel_e_detail_from_material_description
    source_row = row('MDFCA.AC.LAM.L8304', 'SP03').merge(
      'Ten_SP' => 'HỆ TỦ KHU PANTRY',
      'Excel_E' => 'THÙNG, HẬU TỦ',
      'Excel_F' => 'GỖ MDF CHỐNG ẨM CƯỜNG E1 PHỦ MELAMINE',
      'Excel_G' => 'MS 025 SMM'
    )
    option = Catalog.new(snapshot([source_row])).material_options_for_product('SP03').first

    assert_equal "THÙNG\nHẬU TỦ", option[:detail]
    assert_equal 'GỖ MDF CHỐNG ẨM CƯỜNG E1 PHỦ MELAMINE MS 025 SMM', option[:description]
  end

  def test_material_options_keep_two_product_names_under_the_same_sp
    shared_code = 'PLY.E0.AC.MEL.MS991FR'
    rows = [
      row(shared_code, 'SP50').merge(
        'Ten_SP' => 'TỦ PHỤ KIỆN', 'Excel_E' => 'THÙNG, HẬU',
        'Excel_F' => 'GỖ PLYWOOD CHỐNG ẨM', 'Excel_G' => 'MS 991FR'
      ),
      row(shared_code, 'SP50').merge(
        'Ten_SP' => 'HỆ THÙNG ĐỢT ĐỂ ĐỒ', 'Excel_E' => 'HẬU',
        'Excel_F' => 'GỖ PLYWOOD CHỐNG ẨM', 'Excel_G' => 'MS 991FR'
      )
    ]
    options = Catalog.new(snapshot(rows)).material_options_for_product('SP50')

    assert_equal ['TỦ PHỤ KIỆN', 'HỆ THÙNG ĐỢT ĐỂ ĐỒ'], options.map { |option| option[:product_name] }
    assert_equal ["THÙNG\nHẬU", 'HẬU'], options.map { |option| option[:detail] }
    assert_equal [true, true], options.map { |option| option[:product_group_start] }
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

  def test_keding_face_variant_matches_one_catalog_row_without_no_spec
    logical = 'MDFCA.AC.LK.P7013(KEDING)'
    actual = 'MDFCA.18.AC.LK.P7013(KEDING).1M-BCT'
    materials = { Catalog.material_key(actual) => actual }
    rows = Catalog.new(snapshot([row(logical)])).section('SP03', materials, 1)
    assert_equal [[logical, 'OK']], rows.map { |item| [item[:name], item[:status]] }
  end

  def test_world_x_never_prunes_a_wrapper_using_camera_rectangles
    index = HUD::ModelIndex.allocate
    refute index.unrequested_spatial_subtree?(nil, nil, 'SP02')
  end

  def test_spatial_index_uses_world_points_without_screen_projection
    index = HUD::ModelIndex.allocate
    model = Object.new
    index.instance_variable_set(:@model, model)
    points = [Struct.new(:x, :y, :z).new(20, -1000, 900)]
    index.stub(:world_points, points) do
      MH::ProductContext.stub(:spatial_marker_entity?, false) do
        MH::ProductContext.stub(:infer_spatial_product, lambda { |actual, **options|
          assert_same points, actual
          assert_same model, options[:model]
          refute options.key?(:view)
          'SP02'
        }) { assert_equal 'SP02', index.spatial_product_for_instance(nil, nil) }
      end
    end
  end

  def test_marker_change_discards_spatial_cell_cache
    model = Struct.new(:entities).new([])
    markers = [{ code: 'SP01', x: 0.0, y: 100.0 }]
    index = nil
    MH::ProductContext.stub(:spatial_markers, markers) { index = HUD::ModelIndex.new(model) }
    index.instance_variable_set(:@spatial_product_cache, { [0, 0] => markers })
    MH::ProductContext.stub(:spatial_markers, [{ code: 'SP01', x: 200.0, y: 100.0 }]) { index.step }
    assert_empty index.instance_variable_get(:@spatial_product_cache)
  end

  def test_grouped_thicknesses_display_logical_code_in_either_read_order
    [['GGT.18', 'GGT.25'], ['GGT.25', 'GGT.18']].each do |names|
      index = HUD::ModelIndex.allocate
      index.instance_variable_set(:@materials, Hash.new { |hash, key| hash[key] = {} })
      index.instance_variable_set(:@material_cache, {})
      names.each { |name| index.collect_material(Struct.new(:name, :display_name).new(name, name), 'SP03') }

      assert_equal ['GGT'], index.materials['SP03'].keys
      unmatched = Catalog.new(snapshot([])).section('SP03', index.materials['SP03'], 1)
      assert_equal ['GGT'], unmatched.map { |item| item[:name] }
      assert_equal ['NO SPEC'], unmatched.map { |item| item[:status] }

      matched = Catalog.new(snapshot([row('GGT')])).section('SP03', index.materials['SP03'], 1)
      assert_equal ['GGT'], matched.map { |item| item[:name] }
      assert_equal ['OK'], matched.map { |item| item[:status] }
    end
  end

  def test_direct_material_change_rebuilds_the_live_index
    view = Object.new
    def view.invalidate; end
    model = Struct.new(:active_view).new(view)
    Sketchup.active_model = model
    HUD.instance_variable_set(:@overlay_model, model)
    overlay = Object.new
    def overlay.enabled?; true; end
    HUD.instance_variable_set(:@overlay, overlay)
    HUD.instance_variable_set(:@index, Object.new)
    HUD.instance_variable_set(:@index_revision, 3)

    assert HUD.model_materials_changed
    assert_nil HUD.index
    assert_equal 4, HUD.instance_variable_get(:@index_revision)
    assert_equal 1, UI.timers.size
  end

  def test_incomplete_index_waits_for_missing_but_confirms_observed_matches
    catalog = Catalog.new(snapshot([row('ASH')]))
    assert_equal '…', catalog.section('SP03', {}, 1, complete: false).first[:status]
    assert_equal 'OK', catalog.section('SP03', { 'ASH' => 'ASH' }, 1, complete: false).first[:status]
    assert_equal 'OK', catalog.section('SP03', { 'ASH' => 'ASH' }, 1, complete: true).first[:status]
  end

  def test_new_observed_material_is_no_spec_without_waiting_for_full_scan
    catalog = Catalog.new(snapshot([row('ASH')]))
    rows = catalog.section('SP03', { 'PLY' => 'PLY.17' }, 1, complete: false)
    assert_equal ['ASH', 'PLY'], rows.map { |item| item[:name] }
    assert_equal ['…', 'NO SPEC'], rows.map { |item| item[:status] }
    completed = catalog.section('SP03', { 'PLY' => 'PLY.17' }, 1, complete: true)
    assert_equal ['SPEC', 'NO SPEC'], completed.map { |item| item[:status] }
  end

  def test_select_startup_waits_for_model_materials_then_replaces_pending_statuses
    view = Object.new
    def view.invalidate; end
    model = Struct.new(:path, :active_view).new('sp10.skp', view)
    Sketchup.active_model = model
    overlay = Object.new
    def overlay.enabled?; true; end
    HUD.instance_variable_set(:@overlay, overlay)
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@mode, 'select')
    HUD.instance_variable_set(:@index_revision, 0)
    index = Struct.new(:complete, :materials, :steps).new(false, {}, 0)
    def index.step(_budget = nil)
      self.steps += 1
      if steps == 2
        self.materials = { 'SP10' => {
          'MDFCA.E1.TL.SON' => 'MDFCA.17.E1.TL.SON',
          'PLY.E0.AC' => 'PLY.17.E0.AC'
        } }
        self.complete = true
      end
      complete
    end
    rows = [row('MDFCA.E1.TL.SON', 'SP10'), row('PLY.E0.AC', 'SP10')]
    MH::ProjectData.stub(:snapshot, snapshot(rows)) do
      HUD.stub(:products_for_selection, ['SP10']) do
        HUD::ModelIndex.stub(:new, index) do
          HUD.refresh
          assert_nil HUD.index
          assert_same index, HUD.instance_variable_get(:@selection_material_index)
          assert_equal ['…', '…'], HUD.data[:rows].select { |r| r[:type] == :item }.map { |r| r[:status] }
          assert HUD.data[:indexing]
          HUD.set_mode('select')
          assert_same index, HUD.instance_variable_get(:@selection_material_index)
          UI.timers.last.call
          assert_equal ['OK', 'OK'], HUD.data[:rows].select { |r| r[:type] == :item }.map { |r| r[:status] }
          refute HUD.data[:indexing]
          HUD.refresh
          assert_equal 2, index.steps
        end
      end
    end
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

  def test_camera_events_defer_work_and_keep_pan_zoom_cache
    camera = Struct.new(:direction, :up, :height).new([0.0, 0.0, -1.0], [0.0, 1.0, 0.0], 100)
    def camera.perspective?; false; end
    model = Struct.new(:active_view).new(Struct.new(:camera).new(camera))
    Sketchup.active_model = model
    cached = Object.new
    HUD.instance_variable_set(:@selection_material_indexes, { ['SP10'] => cached })
    HUD.instance_variable_set(:@selection_material_view_signature, HUD.selection_material_view_signature)
    camera.height = 500
    HUD.view_changed
    assert_same cached, HUD.instance_variable_get(:@selection_material_indexes)[['SP10']]
    camera.direction = [0.0, 0.6, -0.8]
    HUD.view_changed
    assert_same cached, HUD.instance_variable_get(:@selection_material_indexes)[['SP10']]
    HUD.apply_pending_view_change
    assert_empty HUD.instance_variable_get(:@selection_material_indexes)
  end

  def test_camera_motion_coalesces_one_timer_and_does_not_dispose_store
    camera = Struct.new(:direction, :up, :height).new([0.0, 0.0, -1.0], [0.0, 1.0, 0.0], 100)
    def camera.perspective?; false; end
    view = Struct.new(:camera).new(camera)
    model = Struct.new(:active_view).new(view)
    Sketchup.active_model = model
    HUD.instance_variable_set(:@overlay_model, model)
    overlay = Object.new
    def overlay.enabled?; true; end
    HUD.instance_variable_set(:@overlay, overlay)
    store = Object.new
    def store.dispose; raise 'must not dispose from camera callback'; end
    HUD.instance_variable_set(:@product_store, store)
    HUD.instance_variable_set(:@selection_material_view_signature, HUD.selection_material_view_signature)
    100.times do |i|
      camera.height = 100 + i
      HUD.view_changed
    end
    assert_same store, HUD.instance_variable_get(:@product_store)
    assert_equal 1, UI.timers.size
    HUD.refresh
    assert_equal 1, UI.timers.size
  ensure
    HUD.instance_variable_set(:@product_store, nil)
  end

  def test_material_scan_yields_between_small_slices_and_refreshes_view_completion
    scan = Struct.new(:complete, :materials, :budgets).new(false, {}, [])
    def scan.step(budget)
      budgets << budget
      self.complete = budgets.length == 2
    end
    HUD.instance_variable_set(:@selection_material_index, scan)
    HUD.instance_variable_set(:@selection_material_started_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))
    refreshes = 0
    HUD.stub(:visible?, true) do
      HUD.stub(:refresh, -> { refreshes += 1 }) do
        HUD.run_selection_material_slice
        assert_equal [0.004], scan.budgets
        assert_equal [0.01], UI.timer_delays
        UI.timers.last.call
      end
    end
    assert_equal 1, refreshes
    assert_equal [0.004, 0.004], scan.budgets
  end

  def test_world_x_query_preserves_ambiguous_ranges_and_ignores_y_z
    point = Struct.new(:x, :y, :z)
    context = { ranges: {[20.0,20.0]=>'SP09', [100.0,100.0]=>''}, units:[], result:{owners:{}} }
    MH::ProductContext.stub(:world_x_context, context) do
      assert_equal 'SP09', MH::ProductContext.infer_spatial_product([point.new(20, -10000, 9000)], model:Object.new)
      assert_equal '', MH::ProductContext.infer_spatial_product([point.new(100, 20, 0)], model:Object.new)
    end
  end

  def test_mode_is_saved_and_restored_from_the_model
    model = Object.new
    values = {}
    model.define_singleton_method(:set_attribute) { |_dict, key, value| values[key] = value }
    model.define_singleton_method(:get_attribute) { |_dict, key, fallback| values.fetch(key, fallback) }
    Sketchup.active_model = model

    HUD.set_mode('select')
    HUD.instance_variable_set(:@mode, nil)
    assert_equal 'select', HUD.mode
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

  def test_pick_path_uses_mapped_parent_before_shared_child
    index = HUD::ModelIndex.allocate
    index.instance_variable_set(:@entity_products, { 10 => 'SP09', 20 => 'SP03' })
    parent = Struct.new(:entityID).new(10)
    child = Struct.new(:entityID).new(20)

    assert_equal ['SP09'], index.products_for_entity_path([parent, child])
  end

  def test_selected_explicit_product_code_gets_only_its_json_materials
    entity = Struct.new(:entityID, :name, :definition).new(101, 'SP03', nil)
    model = Struct.new(:selection, :active_path, :entities, :active_view).new([entity], [], [], nil)
    Sketchup.active_model = model
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@catalog, Catalog.new(snapshot([
      row('ASH', 'SP03'), row('PLY.AC', 'SP04')
    ])))

    result = HUD.material_choices_for_selection(model)

    assert result[:ok], result[:error]
    assert_equal 'SP03', result[:product]
    assert_equal ['ASH'], result[:materials]
  end

  def test_selected_detail_reads_product_code_from_registry_attributes
    entity = Object.new
    entity.define_singleton_method(:entityID) { 102 }
    entity.define_singleton_method(:name) { '' }
    entity.define_singleton_method(:definition) { Struct.new(:name).new('Tấm Đứng Trước#155') }
    entity.define_singleton_method(:get_attribute) do |dictionary, key, _fallback|
      dictionary == 'MH_Registry' && key == 'dc_product_code' ? 'SP04' : nil
    end
    model = Struct.new(:selection, :active_path, :entities, :active_view).new([entity], [], [], nil)
    Sketchup.active_model = model
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@catalog, Catalog.new(snapshot([
      row('MDFCA.E1.AC.MEL.MS640WN', 'SP04'), row('PLY.AC', 'SP05')
    ])))

    result = HUD.material_choices_for_selection(model)

    assert result[:ok], result[:error]
    assert_equal 'SP04', result[:product]
    assert_equal ['MDFCA.E1.AC.MEL.MS640WN'], result[:materials]
  end

  def test_index_code_cache_distinguishes_same_name_groups_by_product_attribute
    index = HUD::ModelIndex.allocate
    index.instance_variable_set(:@code_cache, {})
    first = Object.new
    second = Object.new
    [first, second].each do |entity|
      entity.define_singleton_method(:name) { '' }
      entity.define_singleton_method(:definition) { Struct.new(:name).new('Tấm Đứng Trước') }
    end
    first.define_singleton_method(:get_attribute) do |dictionary, key, _fallback|
      dictionary == 'MH_Registry' && key == 'dc_product_code' ? 'SP04' : nil
    end
    second.define_singleton_method(:get_attribute) do |dictionary, key, _fallback|
      dictionary == 'MH_Registry' && key == 'dc_product_code' ? 'SP05' : nil
    end

    assert_equal 'SP04', index.product_code_for_entity(first)
    assert_equal 'SP05', index.product_code_for_entity(second)
  end

  def test_selected_spatial_owner_overrides_stale_product_attribute
    entity = Object.new
    entity.define_singleton_method(:entityID) { 103 }
    entity.define_singleton_method(:name) { '' }
    entity.define_singleton_method(:definition) { Struct.new(:name).new('Tấm Đứng Trước#155') }
    entity.define_singleton_method(:get_attribute) do |dictionary, key, _fallback|
      dictionary == 'MH_Registry' && key == 'dc_product_code' ? 'SP06' : nil
    end
    model = Struct.new(:selection, :active_path, :entities, :active_view).new([entity], [], [], nil)
    Sketchup.active_model = model
    index = Object.new
    def index.complete; true; end
    def index.products_for_selected_entities(_entities, parent_transform: nil); ['SP07']; end
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@index, index)

    assert_equal ['SP07'], HUD.products_for_selection(model)
  end

  def test_index_rechecks_spatial_owner_instead_of_old_cached_owner
    index = HUD::ModelIndex.allocate
    index.instance_variable_set(:@entity_products, { 104 => 'SP06' })
    index.instance_variable_set(:@descendant_products, {})
    transform = Object.new
    transform.define_singleton_method(:*) { |_other| self }
    index.define_singleton_method(:world_points) { |_entity, _transform| [] }
    entity = Object.new
    entity.define_singleton_method(:entityID) { 104 }
    entity.define_singleton_method(:transformation) { transform }

    MH::ProductContext.stub(:infer_spatial_product, lambda { |_points, **options|
      assert_same entity, options[:entity]
      'SP07'
    }) do
      assert_equal ['SP07'], index.products_for_selected_entities([entity], parent_transform: transform)
    end
  end

  def test_nested_copy_inherits_new_spatial_owner_over_stale_child_metadata
    transformation_class = Class.new do
      def *(other); self; end
    end
    Geom::Transformation.define_singleton_method(:new) { transformation_class.new }
    outer = Sketchup::Group.new
    detail = Sketchup::Group.new
    [outer, detail].each do |entity|
      entity.define_singleton_method(:transformation) { transformation_class.new }
      entity.define_singleton_method(:name) { '' }
    end
    context = MH::ProductContext
    originals = %i[world_points_for_entity infer_spatial_product code_from_entity_sources instance_name_product_code]
      .to_h { |name| [name, context.method(name)] }
    context.define_singleton_method(:world_points_for_entity) { |entity, _transform| [entity] }
    context.define_singleton_method(:infer_spatial_product) { |_points, **_opts| 'SP07' }
    context.define_singleton_method(:code_from_entity_sources) { |_entity| 'SP06' }
    context.define_singleton_method(:instance_name_product_code) { |_entity| '' }

    assert_equal ['SP07'], context.codes_for_instance_path([outer, detail])
  ensure
    originals&.each { |name, method| context.define_singleton_method(name, method) }
    Geom::Transformation.singleton_class.send(:remove_method, :new)
  end

  def test_explicit_new_instance_name_overrides_copied_old_metadata_when_no_marker_matches
    transformation_class = Class.new do
      def *(other); self; end
    end
    Geom::Transformation.define_singleton_method(:new) { transformation_class.new }
    parent = Sketchup::Group.new
    detail = Sketchup::Group.new
    parent.define_singleton_method(:transformation) { transformation_class.new }
    parent.define_singleton_method(:name) { '' }
    detail.define_singleton_method(:transformation) { transformation_class.new }
    detail.define_singleton_method(:name) { 'SP07 - Hông Phải' }
    context = MH::ProductContext
    originals = %i[world_points_for_entity infer_spatial_product code_from_entity_sources]
      .to_h { |name| [name, context.method(name)] }
    context.define_singleton_method(:world_points_for_entity) { |entity, _transform| [entity] }
    context.define_singleton_method(:infer_spatial_product) { |points, **_opts| instance_name_product_codes(points.first).first.to_s }
    context.define_singleton_method(:code_from_entity_sources) { |_entity| 'SP06' }

    assert_equal ['SP07'], context.codes_for_instance_path([parent, detail])
  ensure
    originals&.each { |name, method| context.define_singleton_method(name, method) }
    Geom::Transformation.singleton_class.send(:remove_method, :new)
  end

  def test_shared_product_context_returns_spatial_owner_to_other_apps
    transformation_class = Class.new do
      def *(other); self; end
    end
    Geom::Transformation.define_singleton_method(:new) { transformation_class.new }
    entity = Sketchup::Group.new
    entity.define_singleton_method(:entityID) { 901 }
    entity.define_singleton_method(:name) { '' }
    entity.define_singleton_method(:transformation) { transformation_class.new }
    model = Struct.new(:selection, :active_path, :entities, :guid, :active_view).new([entity], [], [entity], 'shared-test', nil)
    Sketchup.active_model = model
    context = MH::ProductContext
    originals = %i[world_points_for_entity infer_spatial_product code_from_entity_sources instance_name_product_code]
      .to_h { |name| [name, context.method(name)] }
    context.define_singleton_method(:world_points_for_entity) { |instance, _transform| [instance] }
    context.define_singleton_method(:infer_spatial_product) { |_points, **_opts| 'SP07' }
    context.define_singleton_method(:code_from_entity_sources) { |_instance| 'SP06' }
    context.define_singleton_method(:instance_name_product_code) { |_instance| '' }
    context.instance_variable_set(:@codes_cache_key, nil)

    assert_equal ['SP07'], context.codes_from_selection(model, allow_slow_scan: false)
    assert_equal 'SP07', context.code_from_entity(entity)
  ensure
    originals&.each { |name, method| context.define_singleton_method(name, method) }
    context.instance_variable_set(:@codes_cache_key, nil) if context
    Geom::Transformation.singleton_class.send(:remove_method, :new)
  end

  def test_active_path_transform_composes_nested_edit_context
    parent_transform = Object.new
    child_transform = Object.new
    parent = Struct.new(:transformation).new(parent_transform)
    child = Struct.new(:transformation).new(child_transform)
    model = Struct.new(:active_path).new([parent, child])
    identity = Geom::Transformation.new
    composed = []
    identity.define_singleton_method(:*) do |transform|
      composed << transform
      self
    end

    Geom::Transformation.define_singleton_method(:new) { identity }
    assert_same identity, HUD.active_path_transform(model)
    assert_equal [parent_transform, child_transform], composed
  ensure
    Geom::Transformation.singleton_class.send(:remove_method, :new) if Geom::Transformation.singleton_class.method_defined?(:new)
  end

  def test_hud_face_pick_targets_deepest_nested_instance_and_its_parent_transform
    transformation_class = Class.new do
      attr_reader :parts
      def initialize(parts = []); @parts = parts; end
      def *(other); self.class.new(parts + [other]); end
    end
    outer_transform = Object.new
    inner_transform = Object.new
    outer = Sketchup::ComponentInstance.new
    inner = Sketchup::Group.new
    face = Sketchup::Face.new
    [[outer, 201, outer_transform], [inner, 202, inner_transform], [face, 203, nil]].each do |entity, id, transform|
      entity.define_singleton_method(:entityID) { id }
      entity.define_singleton_method(:valid?) { true }
      entity.define_singleton_method(:transformation) { transform } if transform
    end
    model = Struct.new(:selection, :active_path).new([face], [])
    Sketchup.active_model = model
    Geom::Transformation.define_singleton_method(:new) { transformation_class.new }
    HUD.instance_variable_set(:@picked_path, [outer, inner, face])
    HUD.instance_variable_set(:@picked_selection_ids, [203])
    HUD.instance_variable_set(:@picked_paths_by_entity, { 203 => [outer, inner, face] })

    context = HUD.selection_target_contexts(model).first

    assert_same inner, context[:entity]
    assert_equal [outer_transform], context[:parent_transform].parts
  ensure
    Geom::Transformation.singleton_class.send(:remove_method, :new)
  end

  def test_hud_pick_keeps_selected_parent_group_as_assignment_root
    transformation_class = Class.new do
      attr_reader :parts
      def initialize(parts = []); @parts = parts; end
      def *(other); self.class.new(parts + [other]); end
    end
    outer = Sketchup::Group.new
    detail = Sketchup::Group.new
    face = Sketchup::Face.new
    outer_transform = Object.new
    detail_transform = Object.new
    outer.define_singleton_method(:entityID) { 211 }
    outer.define_singleton_method(:valid?) { true }
    outer.define_singleton_method(:transformation) { outer_transform }
    outer.define_singleton_method(:entities) { [detail] }
    detail.define_singleton_method(:entityID) { 212 }
    detail.define_singleton_method(:valid?) { true }
    detail.define_singleton_method(:transformation) { detail_transform }
    face.define_singleton_method(:entityID) { 213 }
    face.define_singleton_method(:valid?) { true }
    model = Struct.new(:selection, :active_path, :entities).new([outer], [], [outer])
    Sketchup.active_model = model
    Geom::Transformation.define_singleton_method(:new) { transformation_class.new }
    HUD.instance_variable_set(:@picked_selection_ids, [211])
    HUD.instance_variable_set(:@picked_paths_by_entity, { 211 => [outer, detail, face] })

    context = HUD.selection_target_contexts(model).first

    assert_same outer, context[:entity]
    assert_empty context[:child_slots]
  ensure
    Geom::Transformation.singleton_class.send(:remove_method, :new)
  end

  def test_ctrl_pick_target_is_deepest_instance_not_hit_face
    outer = Sketchup::Group.new
    detail = Sketchup::ComponentInstance.new
    face = Sketchup::Face.new

    assert_same detail, HUD.deepest_material_instance_from_path([outer, detail, face], outer)
    assert_same outer, HUD.deepest_material_instance_from_path([outer, face], outer)
  end

  def test_select_mode_resolves_owner_without_building_full_model_index
    entity = Sketchup::Group.new
    entity.define_singleton_method(:entityID) { 204 }
    entity.define_singleton_method(:get_attribute) do |dictionary, key, _fallback|
      dictionary == 'MH_Registry' && key == 'dc_product_code' ? 'SP07' : nil
    end
    model = Struct.new(:selection, :active_path, :entities, :active_view).new([entity], [], [], nil)
    Sketchup.active_model = model

    assert_equal ['SP07'], HUD.products_for_selection(model)
    assert_nil HUD.index
    refute HUD.instance_variable_get(:@selection_resolver).complete
  end

  def test_shift_pick_keeps_each_nested_detail_and_removes_deselected_path
    transformation_class = Class.new do
      attr_reader :parts
      def initialize(parts = []); @parts = parts; end
      def *(other); self.class.new(parts + [other]); end
    end
    Geom::Transformation.define_singleton_method(:new) { transformation_class.new }
    make_path = lambda do |start_id|
      outer = Sketchup::ComponentInstance.new
      detail = Sketchup::Group.new
      face = Sketchup::Face.new
      [[outer, start_id], [detail, start_id + 1], [face, start_id + 2]].each do |entity, id|
        entity.define_singleton_method(:entityID) { id }
        entity.define_singleton_method(:valid?) { true }
        entity.define_singleton_method(:transformation) { id }
      end
      [outer, detail, face]
    end
    outer_a, detail_a, face_a = make_path.call(310)
    outer_b, detail_b, face_b = make_path.call(320)
    model = Struct.new(:selection, :active_path).new([face_a], [])
    Sketchup.active_model = model

    HUD.remember_pick_path([outer_a, detail_a, face_a], face_a, selected_entities: [face_a])
    model.selection = [face_a, face_b]
    HUD.remember_pick_path([outer_b, detail_b, face_b], face_b, selected_entities: model.selection, additive: true)
    targets = HUD.selection_target_contexts(model).map { |entry| entry[:entity] }
    assert_equal [detail_a, detail_b], targets

    model.selection = [face_a]
    HUD.remember_pick_path([outer_b, detail_b, face_b], face_b, selected_entities: model.selection, additive: true)
    assert_equal [detail_a], HUD.selection_target_contexts(model).map { |entry| entry[:entity] }
  ensure
    Geom::Transformation.singleton_class.send(:remove_method, :new)
  end

  def test_model_change_invalidates_index_while_hud_is_hidden
    model = Struct.new(:entities, :active_view, :selection, :path).new([], nil, [], 'test.skp')
    Sketchup.active_model = model
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@overlay, nil)
    HUD.instance_variable_set(:@index, Object.new)
    HUD.instance_variable_set(:@index_revision, 3)
    HUD.instance_variable_set(:@catalog, Object.new)

    HUD.model_changed

    assert_nil HUD.index
    assert_equal 4, HUD.instance_variable_get(:@index_revision)
  end

  def test_selected_parent_group_inherits_one_product_from_its_details
    parent = Struct.new(:entityID, :name, :definition).new(110, 'Group', nil)
    model = Struct.new(:selection, :active_path, :entities, :active_view).new([parent], [], [], nil)
    Sketchup.active_model = model
    index = HUD::ModelIndex.allocate
    index.instance_variable_set(:@entity_products, {})
    index.instance_variable_set(:@descendant_products, Hash.new { |hash, key| hash[key] = {} }.merge(110 => { 'SP07' => true }))
    index.instance_variable_set(:@complete, true)
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@index, index)
    HUD.instance_variable_set(:@catalog, Catalog.new(snapshot([
      row('MDFCA.PANEL', 'SP07'), row('PLY.AC', 'SP08')
    ])))

    result = HUD.material_choices_for_selection(model)

    assert result[:ok], result[:error]
    assert_equal 'SP07', result[:product]
    assert_equal ['MDFCA.PANEL'], result[:materials]
  end

  def test_selection_resolver_builds_index_while_overlay_is_hidden
    model = Struct.new(:entities, :active_view).new([], nil)
    Sketchup.active_model = model
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@overlay, nil)

    HUD.ensure_index

    assert HUD.index
    assert HUD.index.complete
  end

  def test_selected_parent_group_reports_multiple_descendant_products_as_ambiguous
    parent = Struct.new(:entityID, :name, :definition).new(120, 'Assembly', nil)
    model = Struct.new(:selection, :active_path, :entities, :active_view).new([parent], [], [], nil)
    Sketchup.active_model = model
    index = HUD::ModelIndex.allocate
    index.instance_variable_set(:@entity_products, {})
    index.instance_variable_set(:@descendant_products, Hash.new { |hash, key| hash[key] = {} }.merge(120 => { 'SP01' => true, 'SP02' => true }))
    index.instance_variable_set(:@complete, true)
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@index, index)
    HUD.instance_variable_set(:@catalog, Catalog.new(snapshot([row('ASH', 'SP01'), row('PLY', 'SP02')])))

    result = HUD.material_choices_for_selection(model)

    refute result[:ok]
    assert_equal ['SP01', 'SP02'], result[:products]
    assert_match(/cùng một mã SP/, result[:error])
  end

  def test_color_values_are_not_material_codes
    refute HUD::ModelIndex.displayable_material_name?('#FFFFFF')
    refute HUD::ModelIndex.displayable_material_name?('#FFFFF')
    refute HUD::ModelIndex.displayable_material_name?('rgb(255, 255, 255)')
    refute HUD::ModelIndex.displayable_material_name?('Color_FFFFFF')
    assert HUD::ModelIndex.displayable_material_name?('MDFCA.AC.LAM.L8304')
  end

  def test_index_uses_the_material_display_name
    index = HUD::ModelIndex.allocate
    index.instance_variable_set(:@materials, Hash.new { |hash, key| hash[key] = {} })
    index.instance_variable_set(:@material_cache, {})
    material = Struct.new(:name, :display_name).new('MDFCA.17.AC.MEL.MS446FR1', 'MDFCA.17.AC.MEL.MS446FR')

    index.collect_material(material, 'SP03')

    assert_equal({ 'MDFCA.AC.MEL.SON.MS446FR' => 'MDFCA.17.AC.MEL.MS446FR' }, index.materials['SP03'])
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

  def test_stale_overlay_does_not_raise_during_json_reload_checks
    model = Struct.new(:selection).new([])
    Sketchup.active_model = model
    stale_overlay = Object.new
    def stale_overlay.enabled?; raise RuntimeError, 'invalid overlay'; end
    HUD.instance_variable_set(:@overlay_model, model)
    HUD.instance_variable_set(:@overlay, stale_overlay)

    refute HUD.visible?
    assert_nil HUD.instance_variable_get(:@overlay)
    assert_nil HUD.instance_variable_get(:@overlay_model)
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
