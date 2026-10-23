# frozen_string_literal: true

# Run outside SketchUp: ruby MH_DWG/tests/placement_test.rb
# These tests validate cancellation and placement ordering, not native stability.
require 'minitest/autorun'
require 'matrix'

$LOADED_FEATURES << 'sketchup.rb'
def file_loaded?(_path) = true

module Geom
  Point3d = Struct.new(:x, :y, :z) do
    def transform(transform)
      values = transform.matrix * Vector[x, y, z, 1]
      self.class.new(*values.to_a.first(3))
    end
  end

  class BoundingBox
    def initialize = @points = []

    def add(point)
      @points << point
      self
    end

    def empty? = @points.empty?

    def min
      Point3d.new(@points.map(&:x).min, @points.map(&:y).min, @points.map(&:z).min)
    end

    def max
      Point3d.new(@points.map(&:x).max, @points.map(&:y).max, @points.map(&:z).max)
    end

    def corner(index)
      low = min
      high = max
      Point3d.new(index.nobits?(1) ? low.x : high.x,
                  index.nobits?(2) ? low.y : high.y,
                  index.nobits?(4) ? low.z : high.z)
    end
  end

  class Transformation
    attr_reader :matrix

    def initialize(matrix = Matrix.identity(4)) = @matrix = matrix
    def *(other) = self.class.new(matrix * other.matrix)
    def inverse = self.class.new(matrix.inverse)
    def to_a = matrix.transpose.to_a.flatten

    def self.translation(point)
      new(Matrix[[1, 0, 0, point.x], [0, 1, 0, point.y], [0, 0, 1, point.z], [0, 0, 0, 1]])
    end

    def self.rotation(_origin, axis, angle)
      c = Math.cos(angle)
      s = Math.sin(angle)
      case axis
      when X_AXIS then new(Matrix[[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]])
      when Y_AXIS then new(Matrix[[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0], [0, 0, 0, 1]])
      else new(Matrix[[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
      end
    end
  end

  def self.intersect_line_plane(ray, _plane) = ray.first
end

ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS = :x
Y_AXIS = :y
Z_AXIS = :z
IDENTITY = Geom::Transformation.new
SB_PROMPT = 0
SB_VCB_VALUE = 1
COPY_MODIFIER_MASK = 4
CONSTRAIN_MODIFIER_MASK = 8
ALT_MODIFIER_MASK = 32
class Numeric
  def degrees = self * Math::PI / 180
end

module UI
  class << self
    attr_accessor :timers, :messages

    def start_timer(_delay, repeat, &block)
      @next_id = @next_id.to_i + 1
      timers[@next_id] = block
      (@repeat_ids ||= {})[@next_id] = repeat
      @next_id
    end

    def stop_timer(id)
      timers.delete(id)
      @repeat_ids&.delete(id)
    end

    def tick
      id = timers.keys.first
      return unless id

      callback = timers.delete(id)
      timers[id] = callback if @repeat_ids[id]
      callback.call
    end

    def messagebox(text) = messages << (text)
  end
end

module Sketchup
  class ToolsObserver; end
  class << self
    attr_accessor :active_model

    def platform = :platform_test
    def set_status_text(*); end
  end
  class InputPoint
    def pick(*); end
    def valid? = false
  end

  class Edge
    Vertex = Struct.new(:position)
    attr_reader :start, :end

    def initialize(first = ORIGIN, last = Geom::Point3d.new(10, 0, 0))
      @start = Vertex.new(first)
      @end = Vertex.new(last)
    end
  end

  class Face; end
  class Group; end

  class ComponentInstance
    attr_accessor :layer, :transformation, :valid, :parent
    attr_reader :definition, :model

    def initialize(definition, model, transformation)
      @definition = definition
      @model = model
      @transformation = transformation
      @valid = true
      @parent = model
      definition.instances << self
    end

    def valid? = @valid
    def visible? = true

    def bounds
      bounds = Geom::BoundingBox.new
      source = definition.bounds
      8.times { |i| bounds.add(source.corner(i).transform(transformation)) } unless source.empty?
      bounds
    end
  end
end

class FakeDefinitionEntities
  include Enumerable

  attr_accessor :transform_failure, :ignore_transform

  def initialize(items, parent = nil, model = nil)
    @items = items
    @parent = parent
    @model = model
  end

  attr_reader :parent

  def add_instance(definition, transform)
    raise 'Wrapper creation while native tool active' unless [0, 21_022].include?(@model.tools.active_tool_id)
    raise 'Wrapper creation without operation' unless @model.operation

    instance = Sketchup::ComponentInstance.new(definition, @model, transform)
    instance.parent = @parent
    @items << instance
    instance
  end

  def each(&) = @items.each(&)
  def length = @items.length

  def transform_entities(transform, entities)
    raise 'Simulated transform failure' if transform_failure
    return true if ignore_transform

    entities.each do |entity|
      if entity.is_a?(Sketchup::Edge)
        entity.start.position = entity.start.position.transform(transform)
        entity.end.position = entity.end.position.transform(transform)
      elsif entity.respond_to?(:transformation)
        entity.transformation = transform * entity.transformation
      end
    end
    true
  end
  # Sketchup::Entities supports length, but is not an Array and has no empty?.
end

class FakeDefinition
  attr_accessor :valid
  attr_reader :entities, :instances, :name

  def initialize(items = [Sketchup::Edge.new], model: nil, name: 'test.dwg')
    @valid = true
    @instances = []
    @name = name
    @entities = FakeDefinitionEntities.new(items, self, model)
  end

  def valid? = @valid

  def invalidate_bounds = true

  def bounds
    bounds = Geom::BoundingBox.new
    entities.each do |entity|
      if entity.is_a?(Sketchup::Edge)
        bounds.add(entity.start.position).add(entity.end.position)
      elsif entity.respond_to?(:bounds)
        source = entity.bounds
        8.times { |i| bounds.add(source.corner(i)) } unless source.empty?
      end
    end
    bounds
  end
end

class FakeDefinitions
  attr_reader :definition, :calls, :last_import_args, :created
  attr_accessor :before_import, :import_definition

  def initialize(model)
    @model = model
    @calls = 0
    @created = []
  end

  def add(name)
    definition = FakeDefinition.new([], model: @model, name: name)
    created << definition
    definition
  end

  def import(*args)
    raise 'Import inside an operation' if @model.operation

    @last_import_args = args
    @calls += 1
    before_import&.call
    @definition = import_definition || FakeDefinition.new
  end
end

class FakeEntities < Array
  def initialize(model)
    @model = model
    super()
  end

  def parent = @model

  def add_instance(definition, transform)
    raise 'Geometry created while custom Tool active' if @model.tool

    instance = Sketchup::ComponentInstance.new(definition, @model, transform)
    self << instance
    instance
  end
end

class FakeLayers < Hash
  def add(name) = self.[]=(name, name)
end

class FakeView
  attr_accessor :point
  attr_reader :invalidations

  def initialize = @point = Geom::Point3d.new(100, 200, 0)

  def invalidate
    @invalidations = @invalidations.to_i + 1
  end

  def pickray(*) = [point, Z_AXIS]
end

class FakeTools
  attr_reader :active_tool_id, :observers
  attr_accessor :observer_failure, :active_tool, :active_tool_name

  def initialize
    @active_tool_id = 0
    @observers = []
  end

  def add_observer(observer)
    return false if observer_failure

    observers << observer
    true
  end

  def remove_observer(observer)
    observers.delete(observer)
    true
  end

  def change(id)
    @active_tool_id = id
    @active_tool_name = { 21_013 => 'ComponentTool', 21_126 => 'ComponentCSTool' }.fetch(id, 'OtherTool')
    observers.dup.each { |observer| observer.onActiveToolChanged(self, '', id) }
  end
end

class FakeModel
  attr_reader :active_entities, :definitions, :layers, :active_view, :commits, :aborts,
              :tool, :operation, :native_placements, :tools
  attr_accessor :active_path, :edit_transform, :valid, :active_layer

  def initialize
    @active_entities = FakeEntities.new(self)
    @definitions = FakeDefinitions.new(self)
    @layers = FakeLayers.new
    @active_view = FakeView.new
    @edit_transform = IDENTITY
    @commits = 0
    @aborts = 0
    @native_placements = []
    @tools = FakeTools.new
    @valid = true
    @active_layer = 'original_tag'
  end

  def valid? = @valid

  def place_component(definition, repeat)
    raise 'Native placement inside an operation' if operation
    raise 'Native placement with custom Tool active' if tool

    native_placements << [definition, repeat]
    tools.change(21_013)
    self
  end

  def select_tool(tool)
    old = @tool
    @tool = tool
    old&.deactivate(active_view)
    tool&.activate
    tools.change(tool ? 1 : 0)
  end

  def start_operation(*)
    raise 'Nested operation' if @operation

    @operation_entities = active_entities.to_a.dup
    @operation = true
  end

  def commit_operation
    @operation = false
    @commits += 1
  end

  def abort_operation
    @operation = false
    @aborts += 1
    active_entities.replace(@operation_entities || [])
  end
end

require_relative '../main'
module MH
  module DWG
    def self.log_event(*); end
    def self.find_clipboard_dwg = 'test.dwg'
  end
end

class PlacementTest < Minitest::Test
  def setup
    MH::DWG.instance_variable_get(:@native_tagger)&.cancel!
    MH::DWG.instance_variable_get(:@native_rotation)&.cancel!
    (MH::DWG.instance_variable_get(:@pending_native_taggers) || []).dup.each(&:cancel!)
    UI.timers = {}
    UI.messages = []
    @model = Sketchup.active_model = FakeModel.new
    MH::DWG.instance_variable_set(:@importing, false)
    MH::DWG.instance_variable_set(:@placement_tool, nil)
    MH::DWG.instance_variable_set(:@native_tagger, nil)
    MH::DWG.instance_variable_set(:@native_rotation, nil)
  end

  def teardown
    MH::DWG.instance_variable_get(:@native_tagger)&.cancel!
    MH::DWG.instance_variable_get(:@native_rotation)&.cancel!
    (MH::DWG.instance_variable_get(:@pending_native_taggers) || []).dup.each(&:cancel!)
  end

  def reload_plugin
    finder = MH::DWG.method(:find_clipboard_dwg)
    logger = MH::DWG.method(:log_event)
    previous_verbose = $VERBOSE
    $VERBOSE = nil
    load File.expand_path('../main.rb', __dir__)
  ensure
    $VERBOSE = previous_verbose
    MH::DWG.define_singleton_method(:find_clipboard_dwg, finder)
    MH::DWG.define_singleton_method(:log_event, logger)
  end

  def paste_and_click
    MH::DWG.paste_from_clipboard(:custom)
    tool = @model.tool
    refute_nil tool
    tool.onMouseMove(0, 0, 0, @model.active_view)
    tool.onLButtonDown(0, 0, 0, @model.active_view)
    tool
  end

  def test_custom_preview_bounds_follow_the_transformed_cad_without_creating_geometry
    MH::DWG.paste_from_clipboard(:custom)
    tool = @model.tool
    assert tool.getExtents.empty?
    tool.onMouseMove(0, 0, 0, @model.active_view)
    bounds = tool.getExtents
    assert_equal Geom::Point3d.new(100, 200, 0), bounds.min
    assert_equal Geom::Point3d.new(110, 200, 0), bounds.max
    assert_empty @model.active_entities
    tool.onCancel(0, @model.active_view)
    assert tool.getExtents.empty?
  end

  def test_custom_suspend_invalidates_preview_without_creating_geometry
    MH::DWG.paste_from_clipboard(:custom)
    before = @model.active_view.invalidations.to_i
    @model.tool.suspend(@model.active_view)
    assert_equal before + 1, @model.active_view.invalidations
    assert_empty @model.active_entities
    assert_empty UI.timers
  end

  def test_axis_anchors_keep_sorted_unique_points_and_nearest_fallback
    edges = [Sketchup::Edge.new(Geom::Point3d.new(5, 0, 0), Geom::Point3d.new(-2, 0, 0)),
             Sketchup::Edge.new(Geom::Point3d.new(5, 0, 0), Geom::Point3d.new(1, 3, 4))]
    assert_equal [-2, 5], MH::DWG.find_all_vertices_on_x_axis(edges).map(&:x)
    assert_equal Geom::Point3d.new(-2, 0, 0), MH::DWG.find_vertex_on_x_axis(edges)
    nearest = Geom::Point3d.new(7, 1, 2)
    off_axis = [Sketchup::Edge.new(Geom::Point3d.new(0, 20, 30), nearest)]
    assert_equal [nearest], MH::DWG.find_all_vertices_on_x_axis(off_axis)
    assert_equal nearest, MH::DWG.find_vertex_on_x_axis(off_axis)
    assert_equal [ORIGIN], MH::DWG.find_all_vertices_on_x_axis([])
  end

  def test_custom_modifiers_preserve_axis_and_ctrl_priority_before_placement
    cases = [
      [COPY_MODIFIER_MASK | CONSTRAIN_MODIFIER_MASK, Geom::Point3d.new(10, 0, 0), [100, 210, 0]],
      [CONSTRAIN_MODIFIER_MASK, Geom::Point3d.new(10, 0, 0), [100, 200, -10]],
      [ALT_MODIFIER_MASK, Geom::Point3d.new(0, 10, 0), [100, 200, 10]]
    ]
    cases.each do |flags, point, expected|
      MH::DWG.paste_from_clipboard(:custom)
      tool = @model.tool
      tool.onMouseMove(0, 0, 0, @model.active_view)
      count = @model.active_entities.length
      tool.onLButtonDown(flags, 0, 0, @model.active_view)
      assert_equal count, @model.active_entities.length
      assert_empty UI.timers
      tool.onLButtonDown(0, 0, 0, @model.active_view)
      UI.tick
      UI.tick
      actual = point.transform(@model.active_entities.last.transformation)
      expected.zip([actual.x, actual.y, actual.z]).each { |value, result| assert_in_delta value, result, 1.0e-6 }
    end
  end

  def test_custom_mouse_snap_preserves_free_plane_and_vertex_fallback
    MH::DWG.paste_from_clipboard(:custom)
    tool = @model.tool
    input = tool.instance_variable_get(:@ip)
    input.define_singleton_method(:valid?) { true }
    input.define_singleton_method(:vertex) { true }
    input.define_singleton_method(:position) { Geom::Point3d.new(105, 205, 0) }
    @model.active_view.define_singleton_method(:screen_coords) { |point| point }
    tool.onMouseMove(0, 105, 205, @model.active_view)
    assert_equal input.position, tool.getExtents.min
    tool.onMouseMove(0, 0, 0, @model.active_view)
    assert_equal @model.active_view.point, tool.getExtents.min
    @model.active_view.point = nil
    tool.onMouseMove(0, 0, 0, @model.active_view)
    assert_equal input.position, tool.getExtents.min
    assert_empty @model.active_entities
  end

  def test_custom_wireframe_keeps_nested_transform_limit_and_cycle_guard
    leaf = FakeDefinition.new([Sketchup::Edge.new, Sketchup::Edge.new(ORIGIN, Geom::Point3d.new(0, 10, 0))])
    translation = Geom::Transformation.translation(Geom::Point3d.new(30, 40, 0))
    nested = Sketchup::ComponentInstance.new(leaf, @model, translation)
    root = FakeDefinition.new([nested])
    tool = MH::DWG::RotatePlaceTool.new(root)
    cycle = Sketchup::ComponentInstance.new(root, @model, IDENTITY)
    leaf.entities.instance_variable_get(:@items) << cycle
    segments = tool.send(:collect_preview_segments, root.entities)
    assert_equal 2, segments.length
    assert_equal Geom::Point3d.new(30, 40, 0), segments.first.first
    assert_equal Geom::Point3d.new(40, 40, 0), segments.first.last
    limited = tool.send(:collect_preview_segments, root.entities, limit: 1)
    assert_equal [segments.first], limited
    assert_empty @model.active_entities
  end

  def test_reload_removes_old_class_methods_that_would_shadow_extracted_helpers
    MH::DWG::RotatePlaceTool.define_method(:onMouseMove) { |*| raise 'Old mouse callback' }
    MH::DWG::WindowsRotationKeys.define_method(:refresh_placement_preview) { raise 'Old preview callback' }
    MH::DWG::NativeRotationSession.define_method(:advanced_turns) { |*| raise 'Old rotation state' }
    reload_plugin
    assert_equal MH::DWG::CustomPlacementInput, MH::DWG::RotatePlaceTool.instance_method(:onMouseMove).owner
    assert_equal MH::DWG::WindowsPreviewRefresh,
                 MH::DWG::WindowsRotationKeys.instance_method(:refresh_placement_preview).owner
    assert_equal MH::DWG::NativeRotationState,
                 MH::DWG::NativeRotationSession.instance_method(:advanced_turns).owner
    MH::DWG.paste_from_clipboard(:custom)
    @model.tool.onMouseMove(0, 0, 0, @model.active_view)
    assert_equal @model.active_view.point, @model.tool.getExtents.min
  ensure
    reload_plugin
  end

  def test_default_uses_one_native_mouse_follow_placement_without_custom_callbacks
    MH::DWG.paste_from_clipboard
    assert_equal [[@model.definitions.definition, false]], @model.native_placements
    assert_nil MH::DWG.instance_variable_get(:@placement_tool)
    assert_nil @model.tool
    assert_empty @model.active_entities
    assert_empty @model.layers
    assert_empty UI.timers
    assert_empty UI.messages
    assert_equal 0, @model.commits
    refute @model.operation
    refute MH::DWG.instance_variable_get(:@importing)
  end

  def native_instance(definition = @model.definitions.definition)
    instance = Sketchup::ComponentInstance.new(definition, @model,
                                               Geom::Transformation.translation(Geom::Point3d.new(100, 200, 0)))
    @model.active_entities << instance
    instance
  end

  def test_native_tag_assignment_is_deferred_and_preserves_geometry_and_active_tag
    MH::DWG.paste_from_clipboard
    instance = native_instance
    transform = instance.transformation
    bounds_before = instance.definition.bounds.max
    @model.tools.change(21_022)
    assert_nil instance.layer
    assert_empty @model.layers
    assert_equal 0, @model.commits
    UI.tick
    assert_equal 'MH_DWG', instance.layer
    assert_same transform, instance.transformation
    assert_equal bounds_before, instance.definition.bounds.max
    assert_equal 'original_tag', @model.active_layer
    assert_equal [instance], @model.active_entities
    assert_equal 1, @model.commits
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_native_tag_reuses_existing_tag_and_does_not_retag_nested_blocks
    existing_tag = @model.layers['MH_DWG'] = Object.new
    child = Sketchup::ComponentInstance.new(FakeDefinition.new, @model, IDENTITY)
    child.layer = 'CAD original tag'
    @model.definitions.import_definition = FakeDefinition.new([child])
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21_022)
    UI.tick
    assert_same existing_tag, instance.layer
    assert_equal 'CAD original tag', child.layer
    assert_equal 1, @model.layers.length
  end

  def test_native_escape_without_placement_does_not_create_tag_and_detaches
    MH::DWG.paste_from_clipboard
    @model.tools.change(21_022)
    UI.tick
    assert_empty @model.layers
    assert_empty @model.active_entities
    assert_equal 0, @model.commits
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_native_tag_waits_while_move_is_active_without_closing_its_operation
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21_022)
    @model.tools.change(21_048)
    @model.start_operation('Native Move', true)
    UI.tick
    assert_nil instance.layer
    assert @model.operation
    assert_equal 0, @model.commits
    @model.commit_operation
    @model.tools.change(21_022)
    UI.tick
    assert_equal 'MH_DWG', instance.layer
    assert_equal 2, @model.commits
    assert_empty @model.tools.observers
  end

  def test_native_tag_does_not_modify_an_undone_or_deleted_instance
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21_022)
    instance.valid = false
    @model.active_entities.delete(instance)
    UI.tick
    assert_nil instance.layer
    assert_empty @model.layers
    assert_equal 0, @model.commits
    assert_empty @model.tools.observers
  end

  def test_native_tag_does_not_touch_unrelated_components_or_existing_instances
    definition = FakeDefinition.new
    old = native_instance(definition)
    old.layer = 'old tag'
    unrelated = native_instance(FakeDefinition.new)
    unrelated.layer = 'unrelated tag'
    tagger = MH::DWG::NativePlacementTagger.new(@model, definition)
    @model.tools.change(21_013)
    tagger.arm!
    recent = native_instance(definition)
    @model.tools.change(21_022)
    UI.tick
    assert_equal 'old tag', old.layer
    assert_equal 'unrelated tag', unrelated.layer
    assert_equal 'MH_DWG', recent.layer
    assert_empty @model.tools.observers
  end

  def test_native_tag_survives_new_paste_before_its_timer_runs
    MH::DWG.paste_from_clipboard
    old = native_instance
    @model.tools.change(21_022)
    MH::DWG.paste_from_clipboard
    UI.tick
    assert_nil old.layer
    assert_empty @model.layers
    recent = native_instance
    @model.tools.change(21_022)
    3.times { UI.tick }
    assert_equal 'MH_DWG', old.layer
    assert_equal 'MH_DWG', recent.layer
    assert_empty @model.tools.observers
    assert_empty UI.timers
    assert_equal 2, @model.native_placements.length
  end

  def test_three_consecutive_pastes_preserve_pending_tags_and_wait_for_move
    instances = 3.times.map do
      MH::DWG.paste_from_clipboard
      instance = native_instance
      @model.tools.change(21_048)
      3.times { UI.tick }
      instance
    end
    @model.start_operation('Native Move', true)
    @model.tools.change(21_048)
    3.times { UI.tick }
    assert @model.operation
    assert_equal 0, @model.commits
    assert(instances.all? { |instance| instance.layer.nil? })
    @model.commit_operation
    @model.tools.change(21_022)
    3.times { UI.tick }
    assert_equal ['MH_DWG'] * 3, instances.map(&:layer)
    assert_equal 4, @model.commits
    assert_empty @model.tools.observers
    assert_empty UI.timers
    assert_empty MH::DWG.instance_variable_get(:@pending_native_taggers)
  end

  def test_pending_tag_uses_frozen_instances_and_skips_later_copies_and_deleted_cad
    MH::DWG.paste_from_clipboard
    old = native_instance
    deleted = native_instance
    MH::DWG.paste_from_clipboard
    later_copy = native_instance(old.definition)
    deleted.valid = false
    @model.active_entities.delete(deleted)
    recent = native_instance
    @model.tools.change(21_022)
    3.times { UI.tick }
    assert_equal 'MH_DWG', old.layer
    assert_equal 'MH_DWG', recent.layer
    assert_nil deleted.layer
    assert_nil later_copy.layer
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_pending_tag_cancels_on_context_change
    MH::DWG.paste_from_clipboard
    old = native_instance
    MH::DWG.paste_from_clipboard
    @model.active_path = [Object.new]
    @model.tools.change(21_022)
    3.times { UI.tick }
    assert_nil old.layer
    assert_empty @model.layers
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_pending_tag_survives_cancellation_of_next_preview
    MH::DWG.paste_from_clipboard
    old = native_instance
    MH::DWG.paste_from_clipboard
    @model.tools.change(21_022) # Esc cancels the new preview without placing.
    3.times { UI.tick }
    assert_equal 'MH_DWG', old.layer
    assert_equal [old], @model.active_entities
    assert_equal 1, @model.commits
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_pending_tag_does_not_interrupt_importers_operation_and_recovers_after_import_failure
    MH::DWG.paste_from_clipboard
    old = native_instance
    @model.tools.change(21_022)
    @model.definitions.before_import = lambda do
      @model.start_operation('DWG importer', true)
      UI.tick # Native import can pump the UI while owning its transaction.
      assert @model.operation
      assert_nil old.layer
      assert_equal 0, @model.commits
      @model.commit_operation
      raise 'Simulated import failure'
    end
    MH::DWG.paste_from_clipboard
    3.times { UI.tick }
    assert_equal 'MH_DWG', old.layer
    assert_equal 2, @model.commits
    assert_empty @model.tools.observers
    assert_empty UI.timers
    assert_match(/Simulated import failure/, UI.messages.last)
    refute MH::DWG.instance_variable_get(:@importing)
  end

  def test_failure_in_one_pending_tag_does_not_drop_other_pending_tags
    MH::DWG.paste_from_clipboard
    failed = native_instance
    def failed.layer=(_)
      raise 'Simulated pending tag failure'
    end
    MH::DWG.paste_from_clipboard
    recent = native_instance
    @model.tools.change(21_022)
    3.times { UI.tick }
    assert_nil failed.layer
    assert_equal 'MH_DWG', recent.layer
    assert_equal [failed, recent], @model.active_entities
    assert_equal 1, @model.aborts
    assert_equal 1, @model.commits
    assert_empty @model.tools.observers
    assert_empty UI.timers
    assert_match(/Simulated pending tag failure/, UI.messages.last)
  end

  def test_reload_cancels_both_current_and_pending_native_taggers
    MH::DWG.paste_from_clipboard
    old = native_instance
    MH::DWG.paste_from_clipboard
    recent = native_instance
    @model.tools.change(21_022)
    reload_plugin
    3.times { UI.tick }
    assert_nil old.layer
    assert_nil recent.layer
    assert_empty @model.tools.observers
    assert_empty UI.timers
    assert_empty MH::DWG.instance_variable_get(:@pending_native_taggers)
  end

  def test_native_tag_cancels_when_model_or_edit_context_changes
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21_022)
    @model.active_path = [Object.new]
    UI.tick
    assert_nil instance.layer
    assert_empty @model.tools.observers
    assert_empty @model.layers
  end

  def test_native_tag_cancels_when_active_model_changes
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21_022)
    Sketchup.active_model = FakeModel.new
    UI.tick
    assert_nil instance.layer
    assert_empty @model.tools.observers
    assert_empty @model.layers
    assert_empty Sketchup.active_model.layers
  end

  def test_native_tag_cancels_when_definition_or_model_becomes_invalid
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21_022)
    instance.definition.valid = false
    UI.tick
    assert_nil instance.layer
    assert_empty @model.tools.observers
    assert_empty @model.layers
  end

  def test_native_tag_rejects_instance_in_another_entities_context
    MH::DWG.paste_from_clipboard
    instance = native_instance
    instance.parent = FakeDefinition.new
    @model.tools.change(21_022)
    UI.tick
    assert_nil instance.layer
    assert_empty @model.layers
    assert_empty @model.tools.observers
  end

  def test_native_tag_observer_registration_failure_is_reported_without_placement
    @model.tools.observer_failure = true
    MH::DWG.paste_from_clipboard
    assert_empty @model.native_placements
    assert_empty @model.tools.observers
    assert_empty UI.timers
    assert_match(/Không theo dõi được công cụ đặt CAD/, UI.messages.last)
    refute MH::DWG.instance_variable_get(:@importing)
  end

  def test_native_tag_failure_aborts_only_tag_operation_without_removing_placed_cad
    MH::DWG.paste_from_clipboard
    instance = native_instance
    def instance.layer=(_)
      raise 'Simulated tag failure'
    end
    @model.tools.change(21_022)
    UI.tick
    assert_equal [instance], @model.active_entities
    assert_equal 1, @model.aborts
    refute @model.operation
    assert_empty @model.tools.observers
    assert_empty UI.timers
    assert_match(/Simulated tag failure/, UI.messages.last)
  end

  def test_native_tag_does_not_mutate_while_ruby_tool_is_active_with_zero_id
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.active_tool = Object.new
    @model.tools.change(0)
    UI.tick
    assert_nil instance.layer
    assert_equal 0, @model.commits
    @model.tools.active_tool = nil
    @model.tools.change(21_022)
    UI.tick
    assert_equal 'MH_DWG', instance.layer
    assert_empty @model.tools.observers
  end

  def test_native_tag_cancels_if_model_is_closed_before_timer
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21_022)
    @model.valid = false
    UI.tick
    assert_nil instance.layer
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_native_mouse_anchor_is_whole_drawing_minimum_even_without_a_vertex_there
    definition = FakeDefinition.new([Sketchup::Edge.new(
      Geom::Point3d.new(21_046, -4743, 8), Geom::Point3d.new(21_176, -4800, 10)
    )])
    @model.definitions.import_definition = definition
    MH::DWG.paste_from_clipboard
    assert_equal ORIGIN, definition.bounds.min
    assert_equal Geom::Point3d.new(130, 57, 2), definition.bounds.max
    assert_equal [[definition, false]], @model.native_placements
    assert_equal 1, @model.commits
    assert_empty UI.timers
    refute @model.operation
  end

  def test_native_paste_cancels_old_custom_pending_creation
    paste_and_click
    UI.tick
    MH::DWG.paste_from_clipboard
    UI.tick
    assert_empty UI.timers
    assert_empty @model.active_entities
    assert_nil MH::DWG.instance_variable_get(:@placement_tool)
    assert_equal [[@model.definitions.definition, false]], @model.native_placements
  end

  def test_reload_cancels_custom_placement_before_handoff
    paste_and_click
    reload_plugin
    3.times { UI.tick }
    assert_empty @model.active_entities
    assert_empty UI.timers
    assert_nil MH::DWG.instance_variable_get(:@placement_tool)
    assert_equal 0, @model.commits
  end

  def test_reload_cancels_custom_placement_after_handoff
    paste_and_click
    UI.tick
    assert_nil @model.tool
    refute_empty UI.timers
    reload_plugin
    3.times { UI.tick }
    assert_empty @model.active_entities
    assert_empty UI.timers
    assert_nil MH::DWG.instance_variable_get(:@placement_tool)
    assert_equal 0, @model.commits
  end

  def test_native_rejects_empty_definition_before_calling_place_component
    @model.definitions.import_definition = FakeDefinition.new([])
    MH::DWG.paste_from_clipboard
    assert_empty @model.native_placements
    assert_equal ['Import DWG lỗi!'], UI.messages
    assert_empty UI.timers
  end

  def test_native_placement_failure_is_reported_without_custom_fallback
    def @model.place_component(*) = nil
    MH::DWG.paste_from_clipboard
    assert_nil MH::DWG.instance_variable_get(:@placement_tool)
    assert_empty @model.active_entities
    assert_empty UI.timers
    assert_match(/Không bật được công cụ đặt CAD native/, UI.messages.last)
    refute MH::DWG.instance_variable_get(:@importing)
  end

  def test_preview_has_no_instance_and_creation_happens_after_tool_exit
    paste_and_click
    refute_respond_to @model.definitions.definition.entities, :empty?
    assert_empty @model.active_entities
    assert_equal 0, @model.commits
    UI.tick
    assert_nil @model.tool
    assert_empty @model.active_entities
    UI.tick
    assert_equal 1, @model.active_entities.length
    assert_equal 'MH_DWG', @model.active_entities.first.layer
    assert_equal 1, @model.commits
    assert_empty UI.timers
    assert_empty UI.messages
  end

  def test_import_explicitly_disables_preserving_the_cad_origin
    MH::DWG.paste_from_clipboard(:custom)
    assert_equal ['test.dwg', { preserve_origin: false }], @model.definitions.last_import_args
    assert_empty @model.active_entities
    refute @model.operation
    assert_empty UI.messages
  end

  def test_every_paste_receives_fresh_origin_options
    MH::DWG.paste_from_clipboard(:custom)
    first_options = @model.definitions.last_import_args.last
    first_options[:preserve_origin] = true
    MH::DWG.paste_from_clipboard(:custom)
    second_options = @model.definitions.last_import_args.last
    refute_same first_options, second_options
    assert_equal({ preserve_origin: false }, second_options)
    assert_equal 2, @model.definitions.calls
  end

  def test_escape_cancels_click_before_handoff
    tool = paste_and_click
    tool.onCancel(0, @model.active_view)
    UI.tick
    assert_empty @model.active_entities
    assert_empty UI.timers
  end

  def test_switch_model_between_handoff_and_creation_does_not_place_anywhere
    paste_and_click
    UI.tick
    other = Sketchup.active_model = FakeModel.new
    UI.tick
    assert_empty @model.active_entities
    assert_empty other.active_entities
    assert_equal 0, @model.commits
  end

  def test_edit_path_change_between_callbacks_cancels_placement
    paste_and_click
    UI.tick
    @model.active_path = [Object.new]
    UI.tick
    assert_empty @model.active_entities
  end

  def test_switch_tool_after_handoff_cancels_pending_creation
    paste_and_click
    UI.tick
    other_tool = Object.new
    def other_tool.activate; end
    @model.select_tool(other_tool)
    UI.tick
    assert_empty @model.active_entities
    assert_same other_tool, @model.tool
  end

  def test_invalidated_definition_does_not_get_recreated
    paste_and_click
    UI.tick
    @model.definitions.definition.valid = false
    UI.tick
    assert_empty @model.active_entities
  end

  def test_another_paste_cancels_old_pending_creation
    paste_and_click
    UI.tick
    MH::DWG.paste_from_clipboard(:custom)
    UI.tick
    assert_empty @model.active_entities
    refute_nil @model.tool
    assert_equal 2, @model.definitions.calls
  end

  def test_nested_context_converts_world_placement_to_local_coordinates
    @model.edit_transform = Geom::Transformation.translation(Geom::Point3d.new(30, 40, 0))
    @model.active_path = [Object.new]
    paste_and_click
    UI.tick
    UI.tick
    actual = ORIGIN.transform(@model.active_entities.first.transformation)
    assert_in_delta 70, actual.x, 0.00001
    assert_in_delta 160, actual.y, 0.00001
  end

  def test_rotation_is_applied_once_without_preview_geometry
    MH::DWG.paste_from_clipboard(:custom)
    tool = @model.tool
    tool.onMouseMove(0, 0, 0, @model.active_view)
    tool.onLButtonDown(COPY_MODIFIER_MASK, 0, 0, @model.active_view)
    assert_empty @model.active_entities
    tool.onLButtonDown(0, 0, 0, @model.active_view)
    UI.tick
    UI.tick
    point = Geom::Point3d.new(10, 0, 0).transform(@model.active_entities.first.transformation)
    assert_in_delta 100, point.x, 0.00001
    assert_in_delta 210, point.y, 0.00001
  end

  def test_reentrant_import_does_not_release_outer_import_lock
    @model.definitions.before_import = lambda do
      MH::DWG.paste_from_clipboard(:custom)
      assert MH::DWG.instance_variable_get(:@importing)
    end
    MH::DWG.paste_from_clipboard(:custom)
    assert_equal 1, @model.definitions.calls
    refute MH::DWG.instance_variable_get(:@importing)
  end

  def test_edit_path_change_during_import_stops_native_placement_before_normalization
    definition = FakeDefinition.new([Sketchup::Edge.new(
      Geom::Point3d.new(100, 100, 0), Geom::Point3d.new(110, 110, 0)
    )])
    @model.definitions.import_definition = definition
    @model.definitions.before_import = -> { @model.active_path = [Object.new] }
    MH::DWG.paste_from_clipboard
    assert_empty @model.native_placements
    assert_equal Geom::Point3d.new(100, 100, 0), definition.bounds.min
    assert_equal 0, @model.commits
    assert_empty @model.tools.observers
    assert_empty UI.timers
    assert_match(/ngữ cảnh|group|component/, UI.messages.last)
    refute MH::DWG.instance_variable_get(:@importing)
  end

  def test_entities_change_during_import_stops_custom_placement
    @model.definitions.before_import = lambda do
      @model.instance_variable_set(:@active_entities, FakeEntities.new(@model))
    end
    MH::DWG.paste_from_clipboard(:custom)
    assert_nil @model.tool
    assert_nil MH::DWG.instance_variable_get(:@placement_tool)
    assert_empty @model.active_entities
    assert_equal 0, @model.commits
    assert_match(/ngữ cảnh|group|component/, UI.messages.last)
  end

  def test_edit_context_change_while_exiting_old_tool_stops_before_import
    tool = Object.new
    def tool.activate; end
    tool.define_singleton_method(:deactivate) { |_| Sketchup.active_model.active_path = [Object.new] }
    @model.select_tool(tool)
    MH::DWG.paste_from_clipboard
    assert_equal 0, @model.definitions.calls
    assert_empty @model.native_placements
    assert_empty UI.timers
    assert_match(/ngữ cảnh|group|component/, UI.messages.last)
  end

  def test_edit_path_snapshot_is_not_changed_by_import_callback_mutating_the_array
    @model.active_path = [Object.new]
    @model.definitions.before_import = -> { @model.active_path << Object.new }
    MH::DWG.paste_from_clipboard
    assert_empty @model.native_placements
    assert_match(/ngữ cảnh|group|component/, UI.messages.last)
  end

  def test_context_change_during_normalization_stops_placement
    definition = FakeDefinition.new([Sketchup::Edge.new(
      Geom::Point3d.new(100, 100, 0), Geom::Point3d.new(110, 110, 0)
    )])
    @model.definitions.import_definition = definition
    original_transform = definition.entities.method(:transform_entities)
    definition.entities.define_singleton_method(:transform_entities) do |*args|
      result = original_transform.call(*args)
      Sketchup.active_model.active_path = [Object.new]
      result
    end
    MH::DWG.paste_from_clipboard
    assert_empty @model.native_placements
    assert_empty @model.tools.observers
    assert_empty UI.timers
    refute @model.operation
    assert_match(/ngữ cảnh|group|component/, UI.messages.last)
  end

  def test_empty_definition_is_rejected_without_creating_geometry
    definitions = @model.definitions
    def definitions.import(*)
      FakeDefinition.new([])
    end
    MH::DWG.paste_from_clipboard(:custom)
    assert_nil @model.tool
    assert_empty @model.active_entities
    assert_equal ['Import DWG lỗi!'], UI.messages
    refute MH::DWG.instance_variable_get(:@importing)
  end

  def test_default_anchor_is_drawing_minimum_not_the_point_nearest_x_axis
    edge = Sketchup::Edge.new(Geom::Point3d.new(-40, -20, -5), ORIGIN)
    @model.definitions.import_definition = FakeDefinition.new([edge])
    paste_and_click
    UI.tick
    UI.tick
    anchor = edge.start.position.transform(@model.active_entities.first.transformation)
    assert_equal @model.active_view.point, anchor
    assert_empty UI.messages
  end

  def test_minimum_corner_can_differ_from_every_actual_vertex
    edge = Sketchup::Edge.new(Geom::Point3d.new(50, 100, 8), Geom::Point3d.new(80, 60, 3))
    definition = FakeDefinition.new([edge])
    anchors = MH::DWG.placement_anchor_points(definition)
    assert_equal Geom::Point3d.new(50, 60, 3), anchors.first
    refute_equal edge.start.position, anchors.first
    refute_equal edge.end.position, anchors.first
  end

  def test_minimum_includes_transformed_nested_cad_blocks
    child = FakeDefinition.new([Sketchup::Edge.new(Geom::Point3d.new(-20, -10, -2), ORIGIN)])
    transform = Geom::Transformation.translation(Geom::Point3d.new(-100, 50, 4))
    block = Sketchup::ComponentInstance.new(child, @model, transform)
    definition = FakeDefinition.new([Sketchup::Edge.new, block])
    assert_equal Geom::Point3d.new(-120, 0, 0), MH::DWG.placement_anchor_points(definition).first
  end

  def test_rotation_keeps_nonzero_minimum_anchor_at_cursor
    minimum = Geom::Point3d.new(50, 60, 3)
    @model.definitions.import_definition = FakeDefinition.new([
                                                                Sketchup::Edge.new(minimum,
                                                                                   Geom::Point3d.new(80, 100, 8))
                                                              ])
    MH::DWG.paste_from_clipboard(:custom)
    tool = @model.tool
    tool.onMouseMove(0, 0, 0, @model.active_view)
    tool.onLButtonDown(COPY_MODIFIER_MASK, 0, 0, @model.active_view)
    tool.onLButtonDown(0, 0, 0, @model.active_view)
    UI.tick
    UI.tick
    anchor = @model.definitions.definition.bounds.min.transform(@model.active_entities.first.transformation)
    assert_in_delta 100, anchor.x, 0.00001
    assert_in_delta 200, anchor.y, 0.00001
    assert_in_delta 0, anchor.z, 0.00001
  end

  def test_nonzero_minimum_anchor_in_nested_edit_context
    minimum = Geom::Point3d.new(-40, -20, -5)
    @model.definitions.import_definition = FakeDefinition.new([Sketchup::Edge.new(minimum, ORIGIN)])
    @model.edit_transform = Geom::Transformation.translation(Geom::Point3d.new(30, 40, 7))
    @model.active_path = [Object.new]
    paste_and_click
    UI.tick
    UI.tick
    world_transform = @model.edit_transform * @model.active_entities.first.transformation
    assert_equal @model.active_view.point, @model.definitions.definition.bounds.min.transform(world_transform)
  end

  def test_tab_cycles_back_to_minimum_without_duplicate_anchor
    MH::DWG.paste_from_clipboard(:custom)
    tool = @model.tool
    tool.onMouseMove(0, 0, 0, @model.active_view)
    assert_equal [ORIGIN, Geom::Point3d.new(10, 0, 0)], tool.instance_variable_get(:@all_axis_vertices)
    tool.onKeyDown(9, 1, 0, @model.active_view)
    assert_equal Geom::Point3d.new(10, 0, 0), tool.instance_variable_get(:@base_offset)
    tool.onKeyDown(9, 1, 0, @model.active_view)
    assert_equal ORIGIN, tool.instance_variable_get(:@base_offset)
  end

  def test_importer_retaining_distant_origin_is_corrected_before_preview
    low = Geom::Point3d.new(21_046, -4743, 8)
    high = Geom::Point3d.new(21_176, -4686, 10)
    definition = FakeDefinition.new([Sketchup::Edge.new(low, high)])
    @model.definitions.import_definition = definition
    MH::DWG.paste_from_clipboard(:custom)
    assert_equal ORIGIN, definition.bounds.min
    assert_equal Geom::Point3d.new(130, 57, 2), definition.bounds.max
    assert_equal ORIGIN, @model.tool.instance_variable_get(:@base_offset)
    assert_empty @model.active_entities
    assert_equal 1, @model.commits
    refute @model.operation
  end

  def test_normalization_moves_nested_instance_not_shared_child_definition
    child = FakeDefinition.new
    shift = Geom::Transformation.translation(Geom::Point3d.new(21_046, -4743, 8))
    block = Sketchup::ComponentInstance.new(child, @model, shift)
    root = FakeDefinition.new([block])
    MH::DWG.normalize_definition_origin(root, @model)
    assert_equal ORIGIN, root.bounds.min
    assert_equal ORIGIN, child.bounds.min
    assert_equal Geom::Point3d.new(10, 0, 0), child.bounds.max
    assert_equal ORIGIN, ORIGIN.transform(block.transformation)
  end

  def test_existing_instances_are_not_changed_by_normalization
    definition = FakeDefinition.new([Sketchup::Edge.new(Geom::Point3d.new(100, 200, 0),
                                                        Geom::Point3d.new(110, 200, 0))])
    Sketchup::ComponentInstance.new(definition, @model, IDENTITY)
    assert_raises(RuntimeError) { MH::DWG.normalize_definition_origin(definition, @model) }
    assert_equal Geom::Point3d.new(100, 200, 0), definition.bounds.min
    assert_equal 0, @model.commits
    assert_equal 0, @model.aborts
  end

  def test_transform_failure_aborts_normalization_and_never_activates_preview
    definition = FakeDefinition.new([Sketchup::Edge.new(Geom::Point3d.new(100, 200, 0),
                                                        Geom::Point3d.new(110, 200, 0))])
    definition.entities.transform_failure = true
    @model.definitions.import_definition = definition
    MH::DWG.paste_from_clipboard(:custom)
    assert_nil @model.tool
    assert_empty @model.active_entities
    assert_equal 0, @model.commits
    assert_equal 1, @model.aborts
    refute @model.operation
    assert_match(/Simulated transform failure/, UI.messages.last)
  end

  def test_failure_to_recenter_is_rejected_instead_of_silently_placing
    definition = FakeDefinition.new([Sketchup::Edge.new(Geom::Point3d.new(100, 200, 0),
                                                        Geom::Point3d.new(110, 200, 0))])
    definition.entities.ignore_transform = true
    @model.definitions.import_definition = definition
    MH::DWG.paste_from_clipboard(:custom)
    assert_nil @model.tool
    assert_equal 0, @model.commits
    assert_equal 1, @model.aborts
    assert_match(/Gốc CAD chưa chuẩn hóa/, UI.messages.last)
  end
end
