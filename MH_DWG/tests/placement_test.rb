# Run outside SketchUp: ruby MH_DWG/tests/placement_test.rb
# These tests validate cancellation and placement ordering, not native stability.
require 'minitest/autorun'
require 'matrix'

$LOADED_FEATURES << 'sketchup.rb'
def file_loaded?(_path); true; end

module Geom
  class Point3d < Struct.new(:x, :y, :z)
    def transform(tr)
      values = tr.matrix * Vector[x, y, z, 1]
      self.class.new(*values.to_a.first(3))
    end
  end

  class BoundingBox
    def initialize; @points = []; end
    def add(point); @points << point; self; end
    def empty?; @points.empty?; end
    def min
      Point3d.new(@points.map(&:x).min, @points.map(&:y).min, @points.map(&:z).min)
    end
    def max
      Point3d.new(@points.map(&:x).max, @points.map(&:y).max, @points.map(&:z).max)
    end
    def corner(index)
      low, high = min, max
      Point3d.new((index & 1).zero? ? low.x : high.x,
                  (index & 2).zero? ? low.y : high.y,
                  (index & 4).zero? ? low.z : high.z)
    end
  end

  class Transformation
    attr_reader :matrix
    def initialize(matrix = Matrix.identity(4)); @matrix = matrix; end
    def *(other); self.class.new(matrix * other.matrix); end
    def inverse; self.class.new(matrix.inverse); end
    def to_a; matrix.transpose.to_a.flatten; end
    def self.translation(p)
      new(Matrix[[1, 0, 0, p.x], [0, 1, 0, p.y], [0, 0, 1, p.z], [0, 0, 0, 1]])
    end
    def self.rotation(_origin, axis, angle)
      c, s = Math.cos(angle), Math.sin(angle)
      case axis
      when X_AXIS then new(Matrix[[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]])
      when Y_AXIS then new(Matrix[[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0], [0, 0, 0, 1]])
      else new(Matrix[[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
      end
    end
  end

  def self.intersect_line_plane(ray, _plane); ray.first; end
end

ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS, Y_AXIS, Z_AXIS = :x, :y, :z
IDENTITY = Geom::Transformation.new
SB_PROMPT, SB_VCB_VALUE = 0, 1
COPY_MODIFIER_MASK, CONSTRAIN_MODIFIER_MASK, ALT_MODIFIER_MASK = 4, 8, 32
class Numeric
  def degrees; self * Math::PI / 180; end
end

module UI
  class << self
    attr_accessor :timers, :messages
    def start_timer(_delay, _repeat, &block)
      @next_id = @next_id.to_i + 1
      timers[@next_id] = block
      @next_id
    end
    def stop_timer(id); timers.delete(id); end
    def tick
      id = timers.keys.first
      timers.delete(id).call if id
    end
    def messagebox(text); messages << text; end
  end
end

module Sketchup
  class ToolsObserver; end
  class << self
    attr_accessor :active_model
    def set_status_text(*); end
  end
  class InputPoint
    def pick(*); end
    def valid?; false; end
  end
  class Edge
    Vertex = Struct.new(:position)
    attr_reader :start, :end
    def initialize(a = ORIGIN, b = Geom::Point3d.new(10, 0, 0))
      @start, @end = Vertex.new(a), Vertex.new(b)
    end
  end
  class Face; end
  class Group; end
  class ComponentInstance
    attr_accessor :layer, :transformation, :valid, :parent
    attr_reader :definition, :model
    def initialize(definition, model, transformation)
      @definition, @model, @transformation = definition, model, transformation
      @valid = true
      @parent = model
      definition.instances << self
    end
    def valid?; @valid; end
    def visible?; true; end
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
  def initialize(items); @items = items; end
  def each(&block); @items.each(&block); end
  def length; @items.length; end
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
  attr_reader :entities, :instances
  def initialize(items = [Sketchup::Edge.new])
    @valid = true
    @instances = []
    @entities = FakeDefinitionEntities.new(items)
  end
  def valid?; @valid; end
  def name; 'test.dwg'; end
  def invalidate_bounds; true; end
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
  attr_reader :definition, :calls, :last_import_args
  attr_accessor :before_import, :import_definition
  def initialize(model); @model = model; @calls = 0; end
  def import(*args)
    raise 'Import inside an operation' if @model.operation
    @last_import_args = args
    @calls += 1
    before_import.call if before_import
    @definition = import_definition || FakeDefinition.new
  end
end

class FakeEntities < Array
  def initialize(model); @model = model; super(); end
  def parent; @model; end
  def add_instance(definition, transform)
    raise 'Geometry created while custom Tool active' if @model.tool
    instance = Sketchup::ComponentInstance.new(definition, @model, transform)
    self << instance
    instance
  end
end

class FakeLayers < Hash
  def add(name); self[name] = name; end
end

class FakeView
  attr_accessor :point
  def initialize; @point = Geom::Point3d.new(100, 200, 0); end
  def invalidate; end
  def pickray(*); [point, Z_AXIS]; end
end

class FakeTools
  attr_reader :active_tool_id, :observers
  attr_accessor :observer_failure, :active_tool
  def initialize
    @active_tool_id = 0
    @observers = []
  end
  def add_observer(observer)
    return false if observer_failure
    observers << observer
    true
  end
  def remove_observer(observer); observers.delete(observer); true; end
  def change(id)
    @active_tool_id = id
    observers.dup.each { |observer| observer.onActiveToolChanged(self, '', id) }
  end
end

class FakeModel
  attr_reader :active_entities, :definitions, :layers, :active_view, :commits, :aborts, :tool, :operation, :native_placements
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
  def valid?; @valid; end
  def tools; @tools; end
  def place_component(definition, repeat)
    raise 'Native placement inside an operation' if operation
    raise 'Native placement with custom Tool active' if tool
    native_placements << [definition, repeat]
    tools.change(21013)
    self
  end
  def select_tool(tool)
    old = @tool
    @tool = tool
    old.deactivate(active_view) if old
    tool.activate if tool
    tools.change(tool ? 1 : 0)
  end
  def start_operation(*)
    raise 'Nested operation' if @operation
    @operation_entities = active_entities.to_a.dup
    @operation = true
  end
  def commit_operation; @operation = false; @commits += 1; end
  def abort_operation
    @operation = false
    @aborts += 1
    active_entities.replace(@operation_entities || [])
  end
end

require_relative '../main'
module MH::DWG
  def self.log_event(*); end
  def self.find_clipboard_dwg; 'test.dwg'; end
end

class PlacementTest < Minitest::Test
  def setup
    MH::DWG.instance_variable_get(:@native_tagger)&.cancel!
    UI.timers, UI.messages = {}, []
    @model = Sketchup.active_model = FakeModel.new
    MH::DWG.instance_variable_set(:@importing, false)
    MH::DWG.instance_variable_set(:@placement_tool, nil)
    MH::DWG.instance_variable_set(:@native_tagger, nil)
  end

  def teardown
    MH::DWG.instance_variable_get(:@native_tagger)&.cancel!
  end

  def paste_and_click
    MH::DWG.paste_from_clipboard(:custom)
    tool = @model.tool
    refute_nil tool
    tool.onMouseMove(0, 0, 0, @model.active_view)
    tool.onLButtonDown(0, 0, 0, @model.active_view)
    tool
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
    @model.tools.change(21022)
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
    @model.tools.change(21022)
    UI.tick
    assert_same existing_tag, instance.layer
    assert_equal 'CAD original tag', child.layer
    assert_equal 1, @model.layers.length
  end

  def test_native_escape_without_placement_does_not_create_tag_and_detaches
    MH::DWG.paste_from_clipboard
    @model.tools.change(21022)
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
    @model.tools.change(21022)
    @model.tools.change(21048)
    @model.start_operation('Native Move', true)
    UI.tick
    assert_nil instance.layer
    assert @model.operation
    assert_equal 0, @model.commits
    @model.commit_operation
    @model.tools.change(21022)
    UI.tick
    assert_equal 'MH_DWG', instance.layer
    assert_equal 2, @model.commits
    assert_empty @model.tools.observers
  end

  def test_native_tag_does_not_modify_an_undone_or_deleted_instance
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21022)
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
    @model.tools.change(21013)
    tagger.arm!
    recent = native_instance(definition)
    @model.tools.change(21022)
    UI.tick
    assert_equal 'old tag', old.layer
    assert_equal 'unrelated tag', unrelated.layer
    assert_equal 'MH_DWG', recent.layer
    assert_empty @model.tools.observers
  end

  def test_native_tag_cancelled_on_new_paste_does_not_retag_previous_import
    MH::DWG.paste_from_clipboard
    old = native_instance
    @model.tools.change(21022)
    MH::DWG.paste_from_clipboard
    UI.tick
    assert_nil old.layer
    assert_empty @model.layers
    assert_equal 1, @model.tools.observers.length
    assert_equal 2, @model.native_placements.length
  end

  def test_native_tag_cancels_when_model_or_edit_context_changes
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21022)
    @model.active_path = [Object.new]
    UI.tick
    assert_nil instance.layer
    assert_empty @model.tools.observers
    assert_empty @model.layers
  end

  def test_native_tag_cancels_when_active_model_changes
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21022)
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
    @model.tools.change(21022)
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
    @model.tools.change(21022)
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
    def instance.layer=(_); raise 'Simulated tag failure'; end
    @model.tools.change(21022)
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
    @model.tools.change(21022)
    UI.tick
    assert_equal 'MH_DWG', instance.layer
    assert_empty @model.tools.observers
  end

  def test_native_tag_cancels_if_model_is_closed_before_timer
    MH::DWG.paste_from_clipboard
    instance = native_instance
    @model.tools.change(21022)
    @model.valid = false
    UI.tick
    assert_nil instance.layer
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_native_mouse_anchor_is_whole_drawing_minimum_even_without_a_vertex_there
    definition = FakeDefinition.new([Sketchup::Edge.new(
      Geom::Point3d.new(21046, -4743, 8), Geom::Point3d.new(21176, -4800, 10)
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

  def test_native_rejects_empty_definition_before_calling_place_component
    @model.definitions.import_definition = FakeDefinition.new([])
    MH::DWG.paste_from_clipboard
    assert_empty @model.native_placements
    assert_equal ['Import DWG lỗi!'], UI.messages
    assert_empty UI.timers
  end

  def test_native_placement_failure_is_reported_without_custom_fallback
    def @model.place_component(*); nil; end
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
      Sketchup::Edge.new(minimum, Geom::Point3d.new(80, 100, 8))
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
    low = Geom::Point3d.new(21046, -4743, 8)
    high = Geom::Point3d.new(21176, -4686, 10)
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
    shift = Geom::Transformation.translation(Geom::Point3d.new(21046, -4743, 8))
    block = Sketchup::ComponentInstance.new(child, @model, shift)
    root = FakeDefinition.new([block])
    MH::DWG.normalize_definition_origin(root, @model)
    assert_equal ORIGIN, root.bounds.min
    assert_equal ORIGIN, child.bounds.min
    assert_equal Geom::Point3d.new(10, 0, 0), child.bounds.max
    assert_equal ORIGIN, ORIGIN.transform(block.transformation)
  end

  def test_existing_instances_are_not_changed_by_normalization
    definition = FakeDefinition.new([Sketchup::Edge.new(Geom::Point3d.new(100, 200, 0), Geom::Point3d.new(110, 200, 0))])
    Sketchup::ComponentInstance.new(definition, @model, IDENTITY)
    assert_raises(RuntimeError) { MH::DWG.normalize_definition_origin(definition, @model) }
    assert_equal Geom::Point3d.new(100, 200, 0), definition.bounds.min
    assert_equal 0, @model.commits
    assert_equal 0, @model.aborts
  end

  def test_transform_failure_aborts_normalization_and_never_activates_preview
    definition = FakeDefinition.new([Sketchup::Edge.new(Geom::Point3d.new(100, 200, 0), Geom::Point3d.new(110, 200, 0))])
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
    definition = FakeDefinition.new([Sketchup::Edge.new(Geom::Point3d.new(100, 200, 0), Geom::Point3d.new(110, 200, 0))])
    definition.entities.ignore_transform = true
    @model.definitions.import_definition = definition
    MH::DWG.paste_from_clipboard(:custom)
    assert_nil @model.tool
    assert_equal 0, @model.commits
    assert_equal 1, @model.aborts
    assert_match(/Gốc CAD chưa chuẩn hóa/, UI.messages.last)
  end
end
