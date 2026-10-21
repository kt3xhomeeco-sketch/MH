# encoding: UTF-8
require 'minitest/autorun'
require 'json'
require_relative 'sketchup_stub'
$LOADED_FEATURES << 'sketchup.rb'
$LOADED_FEATURES << File.expand_path('../../MH_shared.rb', __dir__)
require_relative '../main'

class VanRegressionTest < Minitest::Test
  VAN = MH::Van
  def setup
    VAN.instance_variables.each { |key| VAN.remove_instance_variable(key) unless key == :@menu_loaded }
    MH::Van::GeometryCache.clear
    Sketchup.reset_defaults
    Sketchup.active_model = @model = Sketchup::Model.new
    UI.timers, UI.errors = {},[]
    $measurements = Hash.new(0)
  end

  def definition(thickness=18, baked=Geom::Transformation.new)
    points = [[0,0,0],[600,0,0],[600,200,0],[0,200,0],[0,0,thickness],[600,0,thickness],[600,200,thickness],[0,200,thickness]]
    vertices = points.map { |point| Sketchup::Vertex.new(Geom::Point3d.new(*point.map { |v| v / 25.4 }).transform(baked)) }
    entities = Sketchup::Entities.new
    [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]].each { |indices| entities << Sketchup::Face.new(indices.map { |i| vertices[i] }) }
    Sketchup::Definition.new(entities, rand(1_000_000))
  end

  def board(id=1, definition: self.definition, transform: Geom::Transformation.new)
    entity = Sketchup::Group.new(id, definition, @model.layers[0], transform)
    entity.parent = @model
    @model.entities << entity
    entity
  end

  def inventory(count=100, row_count=10)
    shared = definition
    count.times { |i| board(i+1, definition: shared) }
    records = @model.entities.to_h { |entity| [entity.persistent_id,{entity: entity, ancestors: [],ancestor_ids: [],transform: entity.transformation}] }
    rows = @model.entities.each_slice(count / row_count).with_index.map do |entities,index|
      { 'key'=>"18|MDF_#{index}", 'ids'=>entities.map(&:persistent_id), 'ancestor_ids'=>[],
        'paths'=>entities.map { |entity| {'id'=>entity.persistent_id,'ancestor_ids'=>[]} }, 'visible'=>true, 'all_hidden'=>false }
    end
    VAN.instance_variable_set(:@last_records_by_id,records)
    VAN.instance_variable_set(:@last_rows,rows)
    VAN.send(:rebuild_row_indexes,rows)
    rows
  end

  def set_rows(rows,visible)
    VAN.set_visible_rows(JSON.generate('rows'=>rows,'visible'=>visible))
    assert_empty UI.errors
  end

  def test_rotated_instances_and_baked_geometry_keep_18_mm_in_both_scopes
    [0,15,30,45,77,90,135].each do |angle|
      transform = Geom::Transformation.rotation_x(angle)
      [board(definition: definition,transform: transform),board(definition: definition(18,transform))].each do |entity|
        [:nesting,:no_nesting].each do |scope|
          VAN.instance_variable_set(:@active_scan_scope,scope)
          assert_in_delta 18,VAN.send(:record_thickness_mm,entity),1.0e-6
        end
      end
    end
  end

  def test_scale_mirror_parent_transform_and_shear_match_plane_measurement
    entity = board
    transforms = [Geom::Transformation.rotation_x(45) * Geom::Transformation.scaling(2,3,4),
                  Geom::Transformation.scaling(-2,3,-4),
                  Geom::Transformation.new([[1,0,0],[0,1,0],[0.6,0.3,2]])]
    transforms.each do |transform|
      expected = VAN.send(:largest_face_thickness_mm,entity,transform)
      assert_in_delta expected,VAN.send(:thickness_mm,entity,transform),1.0e-6
    end
    assert_in_delta 72,VAN.send(:thickness_mm,entity,transforms[0]),1.0e-6
    assert_equal 0,VAN.send(:thickness_mm,entity,Geom::Transformation.scaling(1,1,0))
  end

  def test_normalized_axis_accessors_do_not_lose_real_instance_scale
    # Actual __1205. Hậu: the definition is 14.142857 mm thick and its
    # instance reduces that axis by 0.7777777778, producing an 11 mm board.
    entity = board(definition: definition(14.142857142859473),
                   transform: Geom::Transformation.scaling(2.470476954117617,0.8577194752774973,0.7777777777776506))
    assert_in_delta 1,entity.transformation.zaxis.length,1.0e-12
    [0,27,67,90].each do |angle|
      transform = Geom::Transformation.rotation_x(angle) * entity.transformation
      [:nesting,:no_nesting].each do |scope|
        VAN.instance_variable_set(:@active_scan_scope,scope)
        assert_in_delta 11,VAN.send(:record_thickness_mm,entity,transform),1.0e-6
      end
    end
    assert_in_delta 11,VAN.send(:bounds_thickness_mm,entity),1.0e-6
  end

  def test_homogeneous_matrix_scale_is_applied_to_plane_distances
    entity = board
    # Geom::Transformation may store uniform scale in element 15, rather
    # than in its three axis columns (legacy single-argument scaling).
    transform = Geom::Transformation.new([[1,0,0],[0,1,0],[0,0,1]],[12,20,30],0.5)
    assert_in_delta 1,transform.zaxis.length,1.0e-12
    assert_in_delta 36,VAN.send(:thickness_mm,entity,transform),1.0e-6
    assert_in_delta 36,VAN.send(:largest_face_thickness_mm,entity,transform),1.0e-6
    assert_equal [2,2,2],VAN.send(:transformation_scales,transform)
    assert_nil MH::Van::GeometryCache.thickness(entity,Geom::Transformation.new([[1,0,0],[0,1,0],[0,0,1]],[0,0,0],0))
  end

  def test_flat_face_rotated_out_of_xy_is_excluded
    entities = Sketchup::Entities.new
    entities << Sketchup::Face.new([[0,0,0],[600,0,0],[600,200,0],[0,200,0]].map { |p| Sketchup::Vertex.new(Geom::Point3d.new(*p.map { |v| v/25.4 })) })
    entity = board(definition: Sketchup::Definition.new(entities,123), transform: Geom::Transformation.rotation_x(45))
    assert_nil VAN.send(:all_group_component_thickness_mm,entity)
    assert_empty VAN.send(:no_nesting_records)
  end

  def test_thickness_format_preserves_hundredths_and_ignores_float_noise
    assert_equal '17.6',VAN.send(:format_thickness,17.60000000001)
    assert_equal '17.64',VAN.send(:format_thickness,17.63999999999)
    assert_equal '17.641',VAN.send(:format_thickness,17.641)
    assert_equal '18',VAN.send(:format_thickness,18.00000000001)
    assert_equal '18',VAN.send(:format_thickness,17.99999999999)
  end

  def test_close_thicknesses_stay_in_separate_rows_on_scan_and_regroup
    board(1,definition: definition(17.6))
    board(2,definition: definition(17.64))
    board(3,definition: definition(17.6),transform: Geom::Transformation.rotation_x(27) * Geom::Transformation.scaling(1,1,1.000000000001))
    [:nesting,:no_nesting].each do |scope|
      VAN.instance_variable_set(:@active_scan_scope,scope)
      records = @model.entities.map { |entity| {entity: entity,ancestors: [],ancestor_ids: [],transform: entity.transformation} }
      rows = VAN.send(:scan_rows,records,include_abf_counts: false)
      assert_equal ['17.6|Default','17.64|Default'],rows.map { |row| row['key'] }
      assert_equal ['17.6','17.64'],rows.map { |row| row['thickness'] }
      assert_equal [[1,3],[2]],rows.map { |row| row['ids'] }
      items = VAN.instance_variable_get(:@last_group_scan_items)
      ruby_rows = VAN.send(:ruby_group_scan_items,items)
      native_rows = VAN.send(:native_group_scan_items,items)
      assert_equal ruby_rows,native_rows if native_rows
      VAN.send(:refresh_group_code_display)
      assert_equal ['17.6|Default','17.64|Default'],VAN.instance_variable_get(:@last_rows).map { |row| row['key'] }
    end
  end

  def test_hundredth_mm_edit_moves_only_the_edited_board_to_a_new_row
    board(1,definition: definition(17.6))
    edited = board(2,definition: definition(17.6))
    VAN.refresh_nesting
    before = VAN.send(:watched_thickness_signature,edited)
    edited.definition.entities.flat_map(&:vertices).uniq.each { |vertex| vertex.position.z = 17.64/25.4 if vertex.position.z > 0 }
    VAN.mark_dirty_definition_entities(edited.definition.entities)
    refute_equal before,VAN.send(:watched_thickness_signature,edited)
    VAN.refresh_dirty_rows
    rows = VAN.instance_variable_get(:@last_rows)
    assert_equal ['17.6|Default','17.64|Default'],rows.map { |row| row['key'] }
    assert_equal [[1],[2]],rows.map { |row| row['ids'] }
  end

  def test_geometry_is_cached_once_and_invalidated_after_edit
    shared = definition
    entity = board(definition: shared)
    assert_in_delta 18,VAN.send(:thickness_mm,entity),1.0e-6
    reads = $measurements[:face_area]
    20.times { |i| assert_in_delta 36,VAN.send(:thickness_mm,board(i+2,definition: shared,transform: Geom::Transformation.scaling(1,1,2))),1.0e-6 }
    assert_equal reads,$measurements[:face_area]
    shared.entities.flat_map(&:vertices).uniq.each { |v| v.position.z = 25.0/25.4 if v.position.z > 0 }
    VAN.instance_variable_set(:@last_records_by_id,{1=>{entity: entity}})
    VAN.instance_variable_set(:@definition_record_ids,{shared.entityID=>[1]})
    VAN.mark_dirty_definition_entities(shared.entities)
    assert_in_delta 25,VAN.send(:thickness_mm,entity),1.0e-6
    assert_operator $measurements[:face_area],:>,reads
  end

  def test_bulk_fast_hide_persists_once_inside_operation_and_repeated_toggle_only_changes_tags
    Sketchup.write_default(VAN::DICT,VAN::FAST_VISIBILITY_KEY,true)
    rows = inventory(10_000,100)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    set_rows(rows,false)
    assert_equal 1,$measurements[:state_reads]
    assert_equal 1,$measurements[:state_writes]
    assert_equal :write,@model.log[-2]
    assert_equal :commit,@model.log[-1]
    assert_equal [:start,true],@model.log.first
    assert @model.entities.all? { |entity| !entity.layer.visible? }
    $measurements = Hash.new(0)
    set_rows(rows,true)
    set_rows(rows,false)
    assert_equal 0,$measurements[:layer_writes]
    assert_equal 0,$measurements[:hidden_writes]
    assert_equal 0,$measurements[:state_reads]
    assert_equal 0,$measurements[:state_writes]
    assert_equal 200,$measurements[:tag_writes]
    assert rows.all? { |row| !row['visible'] && row['all_hidden'] }
    puts "10k boards / 100 rows: initial hide + two toggles #{((Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000).round(1)} ms (standalone doubles)"
  end

  def test_write_failure_aborts_and_discards_runtime_mapping
    Sketchup.write_default(VAN::DICT,VAN::FAST_VISIBILITY_KEY,true)
    rows = inventory
    @model.fail_write = true
    VAN.set_visible_rows(JSON.generate('rows'=>rows,'visible'=>false))
    assert_equal :abort,@model.log.last
    assert @model.entities.all? { |entity| entity.layer == @model.layers[0] }
    assert_nil VAN.instance_variable_get(:@fast_visibility_runtime)
    assert_equal false,!!VAN.instance_variable_get(:@suspend_dirty_tracking)
    @model.fail_write = false; UI.errors = []
    set_rows(rows,false)
    assert @model.entities.all? { |entity| !entity.layer.visible? }
  end

  def test_undo_reload_and_model_switch_do_not_reuse_previous_cache
    Sketchup.write_default(VAN::DICT,VAN::FAST_VISIBILITY_KEY,true)
    rows = inventory
    set_rows(rows,false)
    @model.restore_snapshot
    VAN::ModelChangeObserver.new.onTransactionUndo(@model)
    assert_empty VAN.fast_visibility_state(@model)
    assert VAN.instance_variable_get(:@full_refresh_requested)
    model2 = Sketchup::Model.new
    VAN.send(:prepare_model_runtime,@model)
    VAN.send(:prepare_model_runtime,model2)
    assert_empty VAN.fast_visibility_state(model2)
    assert_empty VAN.instance_variable_get(:@fast_row_bindings)
  end

  def test_no_idle_geometry_scan_and_refresh_events_are_coalesced
    inventory(200,10)
    @model.selection.concat(@model.entities)
    dialog = Object.new
    dialog.define_singleton_method(:visible?) { true }
    VAN.instance_variable_set(:@dialog,dialog)
    $measurements = Hash.new(0)
    10.times { VAN.refresh_dirty_rows; VAN.send(:start_auto_refresh) }
    assert_empty UI.timers
    assert_equal 0,$measurements[:definition_bounds] + $measurements[:entity_bounds] + $measurements[:face_area]
    20.times { VAN.mark_dirty_entity(@model.entities.first) }
    assert_equal 1,UI.timers.size
    assert_equal false,UI.timers.values.first[1]
  end

  def test_native_and_ruby_grouping_agree_for_mixed_rows
    items = [18,27].each_with_index.map { |thickness,i| {'key'=>'*|MDF','code'=>'MDF','raw_code'=>"#{thickness}_MDF",'default_code'=>'MDF','thickness'=>thickness.to_s,'thickness_value'=>thickness,'color'=>i.zero? ? '#ff0000' : '#0000ff','id'=>i+1,'ancestor_ids'=>[],'path'=>{'id'=>i+1,'ancestor_ids'=>[]},'visible'=>true} }
    ruby_rows = VAN.ruby_group_scan_items(items)
    native_rows = VAN.native_group_scan_items(items)
    skip 'optional native binary is unavailable' unless native_rows
    assert_equal ruby_rows,native_rows
  end

  def test_nesting_callback_resets_scan_scope
    scopes = []
    original = VAN.method(:refresh_records)
    VAN.define_singleton_method(:refresh_records) { |scope| scopes << scope }
    VAN.refresh_no_nesting; VAN.refresh_nesting
    assert_equal [:no_nesting,:nesting],scopes
  ensure
    VAN.define_singleton_method(:refresh_records,original)
  end

  def test_original_tags_and_legacy_keys_are_preserved
    Sketchup.write_default(VAN::DICT,VAN::FAST_VISIBILITY_KEY,true)
    rows = inventory(10,2)
    original = @model.layers.add('Original_Tag')
    @model.entities.each { |entity| entity.layer=original }
    set_rows(rows,false)
    assert VAN.restore_all_fast_hidden_entities(@model)
    assert @model.entities.all? { |entity| entity.layer == original }
    assert_empty VAN.fast_visibility_state(@model)
    legacy = @model.layers.add('__MH_Van_Hidden__legacy')
    legacy.set_attribute(VAN::DICT,'fast_visibility_key','18_MDF_WHITE')
    state = {'tags'=>{'18_MDF_WHITE'=>{'temp_tag_pid'=>legacy.persistent_id,'temp_tag_name'=>legacy.name}}}
    assert_same legacy,VAN.fast_visibility_temp_layer(@model,state,'18_MDF_WHITE',create: false)
    refute_equal VAN.fast_visibility_safe_key('18|OAK/WHITE'),VAN.fast_visibility_safe_key('18|OAK WHITE')
  end

  def test_manual_tag_reassignment_becomes_the_restore_destination
    Sketchup.write_default(VAN::DICT,VAN::FAST_VISIBILITY_KEY,true)
    rows = inventory(10,2)
    set_rows(rows,false)
    replacement = @model.layers.add('Manually_Reassigned')
    entity = @model.entities.first
    entity.layer = replacement
    VAN.mark_dirty_entity(entity)
    set_rows([rows.first],false)
    assert VAN.restore_all_fast_hidden_entities(@model)
    assert_same replacement,entity.layer
  end

  def test_normal_visibility_and_partial_protected_row_match_actual_model
    rows = inventory(10,2)
    set_rows(rows,false)
    assert @model.entities.all?(&:hidden?)
    set_rows(rows,true)
    assert @model.entities.none?(&:hidden?)
    Sketchup.write_default(VAN::DICT,VAN::FAST_VISIBILITY_KEY,true)
    protected = @model.layers.add('MH_DWG')
    @model.entities.first.layer=protected
    set_rows([rows.first],false)
    assert_same protected,@model.entities.first.layer
    assert rows.first['visible']
    refute rows.first['all_hidden']
  end

  def test_fallback_isolation_reuses_tags_and_has_undoable_toggle
    rows = inventory(100,10)
    VAN.isolate_row(JSON.generate('key'=>rows.first['key'],'ids'=>rows.first['ids']))
    assert_empty UI.errors
    assert rows.first['visible']
    assert rows.drop(1).none? { |row| row['visible'] }
    $measurements = Hash.new(0)
    VAN.isolate_row(JSON.generate('key'=>rows.first['key'],'ids'=>rows.first['ids']))
    assert rows.all? { |row| row['visible'] }
    assert_equal :commit,@model.log.last
    VAN.isolate_row(JSON.generate('key'=>rows.first['key'],'ids'=>rows.first['ids']))
    assert_equal 0,$measurements[:layer_writes]
    assert_equal 0,$measurements[:face_area]
    assert_equal false,!!VAN.instance_variable_get(:@suspend_dirty_tracking)
  end

  def test_geometry_patch_removes_old_row_and_does_not_resurrect_deleted_items
    entity = board
    VAN.refresh_nesting
    definition = entity.definition
    definition.entities.flat_map(&:vertices).uniq.each { |v| v.position.z = 27.0/25.4 if v.position.z > 0 }
    VAN.mark_dirty_definition_entities(definition.entities)
    VAN.refresh_dirty_rows
    rows = VAN.instance_variable_get(:@last_rows)
    assert_equal ['27|Default'],rows.map { |row| row['key'] }
    assert_in_delta 27,rows.first['thickness_value'],1.0e-6
    entity.valid = false
    assert VAN.send(:patch_cached_rows_for_ids,[entity.persistent_id])
    VAN.send(:refresh_group_code_display)
    assert_empty VAN.instance_variable_get(:@last_rows)
    assert_empty VAN.instance_variable_get(:@last_group_scan_items)
  end

  def test_layer_events_refresh_visibility_without_measuring_geometry
    rows = inventory(10,2)
    layer = @model.layers[0]
    layer.visible = false
    $measurements = Hash.new(0)
    VAN::VisibilityLayersObserver.new.onLayerChanged(@model.layers,layer)
    VAN.refresh_dirty_rows
    assert rows.none? { |row| row['visible'] }
    assert_equal 0,$measurements[:face_area] + $measurements[:definition_bounds] + $measurements[:entity_bounds]
  end

  def test_closing_dialog_detaches_only_van_observers_and_reopening_scans_current_geometry
    entity = board
    foreign = Object.new
    targets = [@model,@model.entities,@model.materials,@model.layers,entity,entity.definition.entities,Sketchup]
    targets.each { |target| target.add_observer(foreign) }
    3.times do |index|
      VAN.show
      assert_equal 1,VAN.instance_variable_get(:@observed_entities).length
      assert_equal 2,VAN.instance_variable_get(:@observed_containers).length
      VAN.mark_dirty_entity(entity)
      refute_empty UI.timers
      VAN.instance_variable_get(:@dialog).close
      targets.each { |target| assert_equal [foreign],target.observers }
      assert_empty UI.timers
      assert_empty VAN.instance_variable_get(:@last_records_by_id)
      assert_empty MH::Van::GeometryCache.instance_variable_get(:@profiles)
      $measurements = Hash.new(0)
      VAN.mark_dirty_entity(entity)
      VAN.mark_dirty_definition_entities(entity.definition.entities)
      VAN.mark_dirty_material(foreign)
      VAN.mark_visibility_dirty
      VAN.mark_selected_records_dirty(@model)
      VAN.request_full_refresh
      VAN.refresh_dirty_rows
      assert_empty UI.timers
      refute VAN.instance_variable_get(:@full_refresh_requested)
      assert_equal 0,$measurements.values.sum
      entity.definition.entities.flat_map(&:vertices).uniq.each do |vertex|
        vertex.position.z = (19+index)/25.4 if vertex.position.z > 0
      end
    end
    VAN.show
    assert_equal '21',VAN.instance_variable_get(:@last_rows).first['thickness']
    assert_empty UI.errors
  end

  def test_closing_dialog_preserves_fast_hidden_tags_and_model_state
    Sketchup.write_default(VAN::DICT,VAN::FAST_VISIBILITY_KEY,true)
    entity = board
    VAN.show
    rows = VAN.instance_variable_get(:@last_rows)
    set_rows(rows,false)
    layer, attributes, operation_log = entity.layer,@model.attributes.dup,@model.log.dup
    VAN.instance_variable_get(:@dialog).close
    assert_same layer,entity.layer
    refute layer.visible?
    assert_equal attributes,@model.attributes
    assert_equal operation_log,@model.log
    assert_empty VAN.instance_variable_get(:@fast_row_bindings)
    assert_nil VAN.instance_variable_get(:@fast_isolate_layout)
    assert_nil VAN.instance_variable_get(:@fast_visibility_runtime)
    VAN.show
    refute VAN.instance_variable_get(:@last_rows).first['visible']
  end

  def test_structural_event_bursts_skip_redundant_work_and_prune_old_observers
    removed = board(1)
    edited = board(2)
    VAN.show
    VAN.request_full_refresh
    @model.entities.delete(removed)
    removed.valid = false
    added = board(3)
    edited.definition.entities.flat_map(&:vertices).uniq.each { |vertex| vertex.position.z = 17.64/25.4 if vertex.position.z > 0 }
    $measurements = Hash.new(0)
    1000.times do
      VAN.mark_dirty_definition_entities(edited.definition.entities)
      VAN.mark_dirty_entity(added)
      VAN.mark_visibility_dirty
      VAN.request_full_refresh
    end
    assert_equal 1,UI.timers.length
    assert_equal 0,$measurements.values.sum
    assert_empty VAN.instance_variable_get(:@dirty_entity_ids)
    timer = UI.timers.delete(VAN.instance_variable_get(:@refresh_timer_id))
    timer.last.call
    assert_empty UI.timers
    assert_equal ['17.64','18'],VAN.instance_variable_get(:@last_rows).map { |row| row['thickness'] }
    assert_empty removed.observers
    assert_empty removed.definition.entities.observers
    assert_equal [edited,added],VAN.instance_variable_get(:@observed_entities)
    assert_equal 3,VAN.instance_variable_get(:@observed_containers).length
  end

  def test_repeated_structural_refresh_keeps_only_current_nesting_objects
    current = board(1)
    VAN.show
    20.times do |index|
      previous = current
      @model.entities.delete(previous)
      previous.valid = false
      current = board(index+2)
      VAN.request_full_refresh
      timer = UI.timers.delete(VAN.instance_variable_get(:@refresh_timer_id))
      timer.last.call
      assert_empty previous.observers
      assert_empty previous.definition.entities.observers
      assert_equal [current],VAN.instance_variable_get(:@observed_entities)
      assert_equal 2,VAN.instance_variable_get(:@observed_containers).length
      assert_equal 1,MH::Van::GeometryCache.instance_variable_get(:@profiles).length
    end
  end

  def test_inventory_does_not_construct_or_scan_abf_private_tools
    previous_abf = Object.const_get(:ABF) if Object.const_defined?(:ABF)
    Object.send(:remove_const,:ABF) if previous_abf
    calls = 0
    tool = Class.new
    tool.define_singleton_method(:new) { calls += 1; raise 'Private ABF tool must not be constructed' }
    abf = Module.new
    abf.const_set(:SheetTypesTool,tool)
    Object.const_set(:ABF,abf)
    board(1,definition: definition(17.6))
    board(2,definition: definition(17.64))
    board(3,definition: definition(17.6))
    3.times { VAN.refresh_nesting }
    assert_equal 0,calls
    assert_equal [2,1],VAN.instance_variable_get(:@last_rows).map { |row| row['count'] }
    assert_equal [2,1],VAN.send(:abf_sheet_type_rows).map { |row| row[:quantity] }
    item = VAN.instance_variable_get(:@last_group_scan_items).find { |entry| entry['id'] == 3 }
    item['raw_code'] = 'Other'
    VAN.send(:refresh_group_code_display)
    assert_equal 3,VAN.instance_variable_get(:@last_rows).length
    assert_equal [1,1,1],VAN.send(:abf_sheet_type_rows).map { |row| row[:quantity] }
    assert_equal 0,calls
  ensure
    Object.send(:remove_const,:ABF) if Object.const_defined?(:ABF)
    Object.const_set(:ABF,previous_abf) if previous_abf
  end

  def test_material_notification_skips_duplicate_hub_invalidation_but_retains_fallback
    previous_hub = MH.const_get(:ModelHub) if MH.const_defined?(:ModelHub,false)
    previous_hud = MH.const_get(:MaterialHUD) if MH.const_defined?(:MaterialHUD,false)
    MH.send(:remove_const,:ModelHub) if previous_hub
    MH.send(:remove_const,:MaterialHUD) if previous_hud
    revision, notifications, finishes = 0,0,[]
    hub = Module.new
    hub.define_singleton_method(:model_signature) { revision }
    hub.define_singleton_method(:invalidate!) { |_kind| revision += 1; notifications += 1 }
    hud = Module.new
    hud.define_singleton_method(:begin_material_change) { |entities| entities }
    hud.define_singleton_method(:finish_material_change) { |token| finishes << token }
    hud.define_singleton_method(:model_materials_changed) { finishes << :fallback }
    MH.const_set(:ModelHub,hub)
    MH.const_set(:MaterialHUD,hud)
    entity = board
    token = VAN.send(:begin_hud_material_change,[entity])
    hub.invalidate!(:model) # The actual ModelObserver already saw the commit.
    VAN.send(:notify_material_code_change,token)
    assert_equal 1,notifications
    assert_equal [[entity]],finishes
    token = VAN.send(:begin_hud_material_change,[entity])
    VAN.send(:notify_material_code_change,token) # A missed material-only event.
    assert_equal 2,notifications
    assert_equal 2,finishes.length
    VAN.send(:notify_material_code_change) # Unpaired notifications still work.
    assert_equal 3,notifications
    assert_equal :fallback,finishes.last
  ensure
    MH.send(:remove_const,:ModelHub) if MH.const_defined?(:ModelHub,false)
    MH.send(:remove_const,:MaterialHUD) if MH.const_defined?(:MaterialHUD,false)
    MH.const_set(:ModelHub,previous_hub) if previous_hub
    MH.const_set(:MaterialHUD,previous_hud) if previous_hud
  end

  def test_nested_board_uses_the_whole_parent_transform
    child = board(1,transform: Geom::Transformation.rotation_x(30) * Geom::Transformation.scaling(1,1,2))
    children = Sketchup::Entities.new
    children << child
    parent_definition = Sketchup::Definition.new(children,789)
    parent = board(2,definition: parent_definition,transform: Geom::Transformation.rotation_x(45) * Geom::Transformation.scaling(2,2,2))
    @model.entities.delete(child)
    child.parent = parent_definition
    records = VAN.send(:part_records)
    assert_equal 1,records.size
    assert_equal [parent.persistent_id],records.first[:ancestor_ids]
    assert_in_delta 72,VAN.send(:record_thickness_mm,child,records.first[:transform]),1.0e-6
  end

  def test_shared_isolate_owns_selection_and_zoom
    rows = inventory(100,10)
    isolate = Module.new
    engine = Module.new
    state = Module.new
    state.define_singleton_method(:fetch) { |_model| {'soft_unisolated'=>false} }
    engine.define_singleton_method(:isolate_entities) do |model,entities,preserve_selection:|
      model.selection.clear
      model.selection.add(entities)
      model.active_view.zoom(entities)
      true
    end
    isolate.const_set(:Engine,engine)
    isolate.const_set(:State,state)
    MH.const_set(:Isolate,isolate)
    VAN.isolate_row(JSON.generate('key'=>rows.first['key'],'ids'=>rows.first['ids']))
    assert_empty UI.errors
    assert_equal 1,$measurements[:zooms]
    assert_equal 1,$measurements[:selection_adds]
    assert_equal false,!!VAN.instance_variable_get(:@suspend_dirty_tracking)
  ensure
    MH.send(:remove_const,:Isolate) if MH.const_defined?(:Isolate,false)
  end
end
