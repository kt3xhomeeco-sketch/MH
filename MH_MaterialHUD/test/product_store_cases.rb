# encoding: UTF-8
class MaterialHudProductStoreTest < Minitest::Test
  HUD = MH::MaterialHUD
  Definition = Struct.new(:entities, :instances, :name) do
    def hash; object_id.hash; end
    def eql?(other); equal?(other); end
  end
  Point = Struct.new(:x, :y, :z)
  Material = Struct.new(:name, :display_name) do
    def hash; object_id.hash; end
    def eql?(other); equal?(other); end
  end

  def setup
    MH::MaterialCode.configure({})
    @transform = Object.new
    def @transform.*(other); other; end
    @view = Object.new
    camera = Object.new
    def camera.perspective?; false; end
    @view.define_singleton_method(:camera) { camera }
    def @view.screen_coords(point); point; end
    @markers = [{ code: 'SP01', x: 0.0, y: 100.0 }, { code: 'SP02', x: 200.0, y: 100.0 }]
    @model = Struct.new(:entities, :active_view, :definitions).new([], @view, [])
    @next_id = 0
  end

  def teardown
    MH::MaterialCode.configure(nil)
  end

  def face(material, back = nil)
    item = Sketchup::Face.new
    id = (@next_id += 1)
    item.define_singleton_method(:valid?) { true }
    item.define_singleton_method(:entityID) { id }
    item.define_singleton_method(:material) { material }
    item.define_singleton_method(:back_material) { back }
    item
  end

  def instance(owner, definition, x, right = x + 20)
    item = Sketchup::Group.new
    id = (@next_id += 1)
    transform = @transform
    item.instance_variable_set(:@valid, true)
    item.instance_variable_set(:@owner, owner)
    item.instance_variable_set(:@points, [Point.new(x, 10, 0), Point.new(right, 30, 0)])
    item.instance_variable_set(:@parent, @model)
    item.define_singleton_method(:valid?) { @valid }
    item.define_singleton_method(:entityID) { id }
    item.define_singleton_method(:owner) { @owner }
    item.define_singleton_method(:points) { @points }
    item.define_singleton_method(:bounds) { Struct.new(:center).new(@points.first) }
    item.define_singleton_method(:parent) { @parent }
    item.define_singleton_method(:name) { @owner }
    item.define_singleton_method(:definition) { definition }
    item.define_singleton_method(:transformation) { transform }
    item.define_singleton_method(:material) { nil }
    definition.instances << item
    @model.definitions << definition unless @model.definitions.include?(definition)
    item
  end

  def environment(resolver: nil, &block)
    resolver ||= lambda { |entity, **options|
      owner = options[:spatial_product].to_s
      [owner, options[:world_transform], owner]
    }
    Geom::Transformation.stub(:new, @transform) do
      MH::ProductContext.stub(:spatial_markers, @markers) do
        MH::ProductContext.stub(:world_points_for_entity, ->(entity, _world) { entity.points }) do
          MH::ProductContext.stub(:average_point, ->(points) { points.first }) do
            MH::ProductContext.stub(:infer_spatial_product, lambda { |points, **_options|
              lo, hi = points.map(&:x).minmax
              choices = @markers.map { |m| [[lo - m[:x], m[:x] - hi, 0].max, m[:code]] }.sort
              choices[0][0] == choices[1][0] ? '' : choices[0][1]
            }) { MH::ProductContext.stub(:resolve_instance_product, resolver, &block) }
          end
        end
      end
    end
  end

  def finish(scan)
    100.times { return scan if scan.step(0.1) }
    flunk 'scan did not complete'
  end

  def test_sp_scan_reads_only_matching_roots_and_reuses_definition_materials
    shared = Definition.new([face(Material.new('ASH', 'ASH'), Material.new('PLY', 'PLY'))], [], 'Shared')
    root1 = instance('SP01', shared, 10)
    root2 = instance('SP02', shared, 160)
    @model.entities = [root1, root2]
    environment do
      store = HUD::ProductStore.new(@model)
      first = finish(store.scan(['SP01']))
      assert_equal %w[ASH PLY], first.materials['SP01'].keys.sort
      assert_equal [root1], store.roots_for(['SP01']).map { |record| record[:entity] }
      assert_nil store.roots_for(['SP02']).first[:index]
      second = finish(store.scan(['SP02']))
      assert_equal %w[ASH PLY], second.materials['SP02'].keys.sort
      assert_equal 1, store.definitions.reads
      visited = store.roots_for(['SP01']).first[:index].visited
      finish(store.scan(['SP01']))
      assert_equal visited, store.roots_for(['SP01']).first[:index].visited
      assert_equal 1, store.definitions.reads
    end
  end

  def test_observed_matches_show_before_the_directory_finishes
    first_definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    second_definition = Definition.new([face(Material.new('PLY', 'PLY'))], [], 'Second')
    @model.entities = [instance('SP01', first_definition, 10), instance('SP02', second_definition, 160)]
    environment do
      store = HUD::ProductStore.new(@model)
      2.times { store.step(0) }
      scan = store.scan(['SP01'])
      store.stub(:step, false) do
        refute scan.step(0.1)
        assert_equal ['ASH'], scan.materials['SP01'].keys
        refute scan.complete
      end
      finish(scan)
      assert scan.complete
    end
  end

  def test_new_selection_reorders_unfinished_directory_without_losing_records
    first_definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    second_definition = Definition.new([face(Material.new('PLY', 'PLY'))], [], 'Second')
    first = instance('SP01', first_definition, 10)
    second = instance('SP02', second_definition, 160)
    @model.entities = [first, second]
    environment do
      store = HUD::ProductStore.new(@model)
      2.times { store.step(0) }
      original = store.roots_for(['SP01']).first
      scan = store.scan(['SP02'])
      assert_equal ['SP02'], store.instance_variable_get(:@priority_products)
      assert_same original, store.roots_for(['SP01']).first
      assert_equal ['PLY'], finish(scan).materials['SP02'].keys
      assert_same original, store.roots_for(['SP01']).first
      assert_equal 2, store.roots_count
    end
  end

  def test_matching_roots_are_read_before_unrelated_wildcard_roots
    definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    matching = instance('SP01', definition, 10)
    boundary = instance('SP09', definition, 80, 140)
    @model.entities = [boundary, matching]
    environment do
      store = HUD::ProductStore.new(@model)
      100.times { break if store.step(0.1) }
      assert_equal [matching], store.roots_for(['SP01']).map { |r| r[:entity] }
      assert_equal ['ASH'], finish(store.scan(['SP01'])).materials['SP01'].keys
    end
  end

  def test_copied_panel_is_read_in_destination_product_before_global_rebuild_finishes
    first_definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    source_definition = Definition.new([face(Material.new('PLY', 'PLY'))], [], 'Source')
    first = instance('SP01', first_definition, 10)
    source = instance('SP02', source_definition, 160)
    @model.entities = [first, source]
    resolver = lambda do |entity, **options|
      spatial = options[:spatial_product].to_s
      owner = spatial.empty? ? entity.owner : spatial
      [owner, options[:world_transform], spatial]
    end
    environment(resolver: resolver) do
      store = HUD::ProductStore.new(@model)
      assert_equal ['ASH'], finish(store.scan(['SP01'])).materials['SP01'].keys
      # Preserve source metadata, but physically place the copied panel in SP01.
      copied = instance('SP02', source_definition, 10)
      @model.entities << copied
      store.changed_entity(copied)
      store.prioritize_changes(['SP01'], [copied])
      store.stub(:revision, :new_revision) do
        assert_equal :all, store.synchronize(unknown_if_untracked: true)
      end
      2.times { store.step(0) }
      assert_equal [copied], store.roots_for(['SP01']).map { |record| record[:entity] }
      scan = store.scan(['SP01'])
      store.stub(:step, false) do
        refute scan.step(0.1)
        assert_equal ['PLY'], scan.materials['SP01'].keys
        assert_empty scan.materials.fetch('SP02', {})
        refute store.complete
      end
      assert_equal %w[ASH PLY], finish(scan).materials['SP01'].keys.sort
    end
  end

  def test_world_x_owns_nesting_above_or_below_labels_and_ignores_copied_metadata
    child_definition = Definition.new([face(Material.new('PLY', 'PLY'))], [], 'Panel')
    child = instance('', child_definition, 10)
    definition = Definition.new([child], [], 'Nesting')
    root = instance('', definition, 10)
    child.instance_variable_set(:@parent, definition)
    root.instance_variable_set(:@points, [Point.new(10, 120, 0), Point.new(30, 140, 0)])
    child.instance_variable_set(:@points, [Point.new(10, 120, 0), Point.new(30, 140, 0)])
    @model.entities = [root]
    environment do
      store = HUD::ProductStore.new(@model)
      assert_equal ['PLY'], finish(store.scan(['SP01'])).materials['SP01'].keys
      child.instance_variable_set(:@owner, 'SP02')
      store.changed_entity(child, definition)
      assert_equal ['SP01'], store.synchronize
      assert_empty finish(store.scan(['SP02'])).materials['SP02']
      assert_equal ['SP01'], store.products_for_entities([root])
    end
  end

  def test_non_creating_dictionary_lookup_preserves_product_fields
    entity = Object.new
    calls = []
    entity.define_singleton_method(:get_attribute) { |*args| raise 'slow fallback should not run' }
    entity.define_singleton_method(:attribute_dictionary) do |name, create|
      calls << [name, create]
      name == 'dynamic_attributes' ? { 'product_code' => 'SP02', 'actual_product' => 'SP01' } : nil
    end
    assert_equal %w[SP02 SP01], MH::ProductContext.attribute_product_values(entity)
    assert_equal [['MH_Registry', false], ['MH_ProductContext', false], ['dynamic_attributes', false]], calls
  end

  def test_boundary_root_uses_world_x_and_ignores_nested_copied_product_name
    child_definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'Child')
    child = instance('SP09', child_definition, 110)
    definition = Definition.new([child], [], 'Boundary')
    root = instance('SP01', definition, 80, 140)
    child.instance_variable_set(:@parent, definition)
    @model.entities = [root]
    environment do
      store = HUD::ProductStore.new(@model)
      scan = finish(store.scan(['SP02']))
      assert_equal ['ASH'], scan.materials['SP02'].keys
      assert_equal [root], store.roots_for(['SP02']).map { |record| record[:entity] }
      assert_equal ['SP02'], store.products_for_entities([root])
    end
  end

  def test_definition_edit_invalidates_only_its_product_and_changes_the_result
    first_definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    second_definition = Definition.new([face(Material.new('PLY', 'PLY'))], [], 'Second')
    first = instance('SP01', first_definition, 10)
    second = instance('SP02', second_definition, 160)
    @model.entities = [first, second]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(%w[SP01 SP02]))
      preserved = store.roots_for(['SP02']).first[:index]
      first_definition.entities.replace([face(Material.new('GGT', 'GGT'))])
      store.changed_entity(nil, first_definition)
      assert_equal ['SP01'], store.synchronize
      assert_same preserved, store.roots_for(['SP02']).first[:index]
      updated = finish(store.scan(['SP01']))
      assert_equal ['GGT'], updated.materials['SP01'].keys
      assert_equal 3, store.definitions.reads
    end
  end

  def test_definition_callbacks_only_queue_work_until_synchronization
    definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    @model.entities = [instance('SP01', definition, 10)]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(['SP01']))
      store.stub(:root_ids_for_definition, ->(*) { raise 'observer must not walk the instance graph' }) do
        100.times { store.changed_entity(nil, definition) }
      end
      assert_equal 1, store.instance_variable_get(:@dirty_definitions).size
      assert_equal ['SP01'], store.synchronize
    end
  end

  def test_explicit_recursive_material_edit_keeps_unaffected_product_cache
    first_definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    second_definition = Definition.new([face(Material.new('PLY', 'PLY'))], [], 'Second')
    first = instance('SP01', first_definition, 10)
    @model.entities = [first, instance('SP02', second_definition, 160)]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(%w[SP01 SP02]))
      preserved = store.roots_for(['SP02']).first[:index]
      token = store.begin_material_change([first], recursive: true)
      first_definition.entities.replace([face(Material.new('GGT', 'GGT'))])
      store.unknown_change! # definition collection events during make_unique
      store.stub(:revision, :material_revision) do
        assert store.finish_material_change(token)
        assert_equal ['SP01'], store.synchronize(unknown_if_untracked: true)
      end
      assert store.complete
      assert_same preserved, store.roots_for(['SP02']).first[:index]
      assert_equal ['GGT'], finish(store.scan(['SP01'])).materials['SP01'].keys
      assert_equal ['PLY'], finish(store.scan(['SP02'])).materials['SP02'].keys
    end
  end

  def test_explicit_face_edit_updates_every_shared_occurrence
    material_face = face(Material.new('ASH', 'ASH'))
    definition = Definition.new([material_face], [], 'Shared')
    material_face.define_singleton_method(:parent) { definition }
    @model.entities = [instance('SP01', definition, 10), instance('SP02', definition, 160)]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(%w[SP01 SP02]))
      token = store.begin_material_change([material_face])
      definition.entities.replace([face(Material.new('GGT', 'GGT'))])
      store.stub(:revision, :material_revision) do
        assert store.finish_material_change(token)
        assert_equal %w[SP01 SP02], store.synchronize(unknown_if_untracked: true).sort
      end
      scan = finish(store.scan(%w[SP01 SP02]))
      assert_equal ['GGT'], scan.materials['SP01'].keys
      assert_equal ['GGT'], scan.materials['SP02'].keys
    end
  end

  def test_recursive_scope_with_both_parent_and_child_includes_siblings
    child_definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'Child')
    sibling_definition = Definition.new([face(Material.new('PLY', 'PLY'))], [], 'Sibling')
    child = instance('SP01', child_definition, 10)
    sibling = instance('SP01', sibling_definition, 20)
    parent_definition = Definition.new([child, sibling], [], 'Parent')
    parent = instance('SP01', parent_definition, 10)
    child.instance_variable_set(:@parent, parent_definition)
    sibling.instance_variable_set(:@parent, parent_definition)
    @model.entities = [parent]
    environment do
      store = HUD::ProductStore.new(@model)
      token = store.begin_material_change([parent, child], recursive: true)
      assert_equal [parent_definition, child_definition, sibling_definition].sort_by(&:object_id),
        token[:scope][:definitions].sort_by(&:object_id)
      refute token[:scope][:unknown]
    end
  end

  def test_scoped_edit_does_not_cover_a_later_untracked_transaction
    definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    root = instance('SP01', definition, 10)
    @model.entities = [root]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(['SP01']))
      token = store.begin_material_change([root], recursive: true)
      store.stub(:revision, :material_revision) { assert store.finish_material_change(token) }
      store.stub(:revision, :later_revision) do
        assert_equal :all, store.synchronize(unknown_if_untracked: true)
      end
      refute store.complete
    end
  end

  def test_make_unique_invalidates_old_and_new_definitions_not_the_source_result
    shared = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'Shared')
    first = instance('SP01', shared, 10)
    second = instance('SP02', shared, 160)
    @model.entities = [first, second]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(%w[SP01 SP02]))
      token = store.begin_material_change([first], recursive: true)
      unique = Definition.new([face(Material.new('GGT', 'GGT'))], [first], 'Unique')
      first.define_singleton_method(:definition) { unique }
      shared.instances.delete(first)
      store.unknown_change!
      store.stub(:revision, :material_revision) do
        assert store.finish_material_change(token)
        assert_equal %w[SP01 SP02], store.synchronize(unknown_if_untracked: true).sort
      end
      scan = finish(store.scan(%w[SP01 SP02]))
      assert_equal ['GGT'], scan.materials['SP01'].keys
      assert_equal ['ASH'], scan.materials['SP02'].keys
    end
  end

  def test_scoped_edit_during_directory_build_removes_old_materials
    first_definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    second_definition = Definition.new([face(Material.new('PLY', 'PLY'))], [], 'Second')
    first = instance('SP01', first_definition, 10)
    @model.entities = [first, instance('SP02', second_definition, 160)]
    environment do
      store = HUD::ProductStore.new(@model)
      2.times { store.step(0) }
      scan = store.scan(['SP01'])
      store.stub(:step, false) { scan.step(0.1) }
      assert_equal ['ASH'], scan.materials['SP01'].keys
      token = store.begin_material_change([first], recursive: true)
      first_definition.entities.replace([face(Material.new('GGT', 'GGT'))])
      store.stub(:revision, :material_revision) do
        assert store.finish_material_change(token)
        assert_equal ['SP01'], store.synchronize(unknown_if_untracked: true)
      end
      assert_equal ['GGT'], finish(scan).materials['SP01'].keys
    end
  end

  def test_undo_redo_and_completed_scan_references_never_keep_old_materials
    definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    @model.entities = [instance('SP01', definition, 10)]
    environment do
      store = HUD::ProductStore.new(@model)
      scan = finish(store.scan(['SP01']))
      history = HUD::HistoryObserver.new(store)
      definition.entities.replace([face(Material.new('PLY', 'PLY'))])
      history.onTransactionUndo(@model)
      assert_equal :all, store.synchronize
      assert_equal ['PLY'], finish(scan).materials['SP01'].keys
      definition.entities.replace([face(Material.new('ASH', 'ASH'))])
      history.onTransactionRedo(@model)
      assert_equal :all, store.synchronize
      assert_equal ['ASH'], finish(scan).materials['SP01'].keys
    end
  end

  def test_camera_reset_retains_definition_contents
    definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    @model.entities = [instance('SP01', definition, 10)]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(['SP01']))
      contents = store.definitions
      store.reset_ownership
      refute store.complete
      assert_same contents, store.definitions
      assert_equal ['ASH'], finish(store.scan(['SP01'])).materials['SP01'].keys
      assert_equal 1, store.definitions.reads
    end
  end

  def test_collection_observers_do_not_enumerate_or_watch_every_definition
    targets = [@model.entities, @model.definitions, [], @model]
    targets.each do |target|
      target.define_singleton_method(:add_observer) { |observer| (@attached ||= []) << observer }
      target.define_singleton_method(:remove_observer) { |observer| @attached.delete(observer) }
    end
    materials = targets[2]
    @model.define_singleton_method(:materials) { materials }
    @model.definitions.define_singleton_method(:each) { |*| raise 'do not enumerate all definitions to attach observers' }
    environment do
      store = HUD::ProductStore.new(@model)
      assert_equal 4, store.instance_variable_get(:@observers).length
      store.dispose
      assert targets.all? { |target| target.instance_variable_get(:@attached).empty? }
    end
  end

  def test_untracked_nested_edit_invalidates_even_when_root_observer_fired
    definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'First')
    root = instance('SP01', definition, 10)
    @model.entities = [root]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(['SP01']))
      definition.entities.replace([face(Material.new('GGT', 'GGT'))])
      store.changed_entity(root)
      store.stub(:revision, :new_revision) do
        assert_equal :all, store.synchronize(unknown_if_untracked: true)
      end
      assert_equal ['GGT'], finish(store.scan(['SP01'])).materials['SP01'].keys
    end
  end

  def test_move_and_delete_invalidate_previous_and_new_product_ownership
    definition = Definition.new([face(Material.new('ASH', 'ASH'))], [], 'Moved')
    root = instance('SP01', definition, 10)
    @model.entities = [root]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(['SP01']))
      root.instance_variable_set(:@owner, 'SP02')
      root.instance_variable_set(:@points, [Point.new(160, 10, 0), Point.new(180, 30, 0)])
      store.changed_entity(root)
      assert_equal %w[SP01 SP02], store.synchronize.sort
      assert_empty finish(store.scan(['SP01'])).materials['SP01']
      assert_equal ['ASH'], finish(store.scan(['SP02'])).materials['SP02'].keys
      root.instance_variable_set(:@valid, false)
      store.changed_entity(root.entityID)
      assert_equal ['SP02'], store.synchronize
      assert_empty finish(store.scan(['SP02'])).materials['SP02']
    end
  end

  def test_material_rename_invalidates_all_occurrences_without_rereading_faces
    material = Material.new('ASH', 'ASH')
    definition = Definition.new([face(material)], [], 'Shared')
    @model.entities = [instance('SP01', definition, 10), instance('SP02', definition, 160)]
    environment do
      store = HUD::ProductStore.new(@model)
      finish(store.scan(%w[SP01 SP02]))
      material.display_name = 'GGT'
      store.changed_material(material)
      assert_equal %w[SP01 SP02], store.synchronize.sort
      scan = finish(store.scan(%w[SP01 SP02]))
      assert_equal ['GGT'], scan.materials['SP01'].keys
      assert_equal ['GGT'], scan.materials['SP02'].keys
      assert_equal 1, store.definitions.reads
      store.unknown_change!
      assert_equal :all, store.synchronize
      refute store.complete
    end
  end
end
