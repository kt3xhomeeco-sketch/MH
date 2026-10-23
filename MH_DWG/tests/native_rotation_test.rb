# frozen_string_literal: true

# Run outside SketchUp: ruby MH_DWG/tests/native_rotation_test.rb
# Includes the stable placement/tag regressions. Native crash stability needs SU.
require_relative 'placement_test'

class FakeRotationKeys
  attr_accessor :focused, :failure, :refresh_failure, :cursor
  attr_reader :states, :preview_refreshes

  def initialize
    @focused = true
    @states = { x: false, y: false, z: false, mouse: false }
    @cursor = [400, 300]
    @preview_refreshes = []
  end

  def focused? = focused

  def snapshot
    raise 'Simulated keyboard failure' if failure

    states.dup
  end

  def refresh_placement_preview
    raise 'Simulated preview refresh failure' if refresh_failure

    preview_refreshes << cursor.dup
    true
  end
end

# Validate Win32 coordinate/message handling without sending live window input.
class WindowsPreviewRefreshTest < Minitest::Test
  def setup
    require 'fiddle'
    @keys = MH::DWG::WindowsRotationKeys.allocate
    @posted = []
    @capture = 0
    @root = 100
    @owner = 0
    @pressed = false
    @client = [160, 210]
    @post_result = 1
    functions = {
      foreground: -> { 100 },
      window_owner: ->(*) { @owner },
      key_state: ->(*) { @pressed ? 0x8000 : 0 },
      window_pid: lambda { |_, pointer|
        pointer[0, 4] = [Process.pid].pack('L<')
        1
      },
      cursor_pos: lambda { |pointer|
        pointer[0, 8] = [-1700, 450].pack('l<l<')
        1
      },
      mouse_capture: -> { @capture },
      window_at_point: lambda { |point|
        @sampled_screen = [point].pack('q<').unpack('l<l<')
        200
      },
      window_root: ->(*) { @root },
      screen_to_client: lambda { |_, pointer|
        pointer[0, 8] = @client.pack('l<l<')
        1
      },
      client_rect: lambda { |_, pointer|
        pointer[0, 16] = [0, 0, 800, 600].pack('l<l<l<l<')
        1
      },
      post_message: lambda { |*args|
        @posted << args
        @post_result
      }
    }
    functions.each { |name, function| @keys.instance_variable_set("@#{name}", function) }
    { pid_buffer: 4, point_buffer: 8, rect_buffer: 16 }.each do |name, size|
      @keys.instance_variable_set("@#{name}", Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE))
    end
  end

  def test_posts_one_move_in_client_coordinates_without_click_or_cursor_warp
    assert @keys.refresh_placement_preview
    assert_equal [-1700, 450], @sampled_screen
    assert_equal [[200, 0x0200, 0, 160 | (210 << 16)]], @posted
  end

  def test_uses_native_mouse_capture_window_when_present
    @capture = 300
    assert @keys.refresh_placement_preview
    assert_equal 300, @posted.first.first
    assert_nil @sampled_screen
  end

  def test_does_not_post_to_another_application_window
    @root = 999
    refute @keys.refresh_placement_preview
    assert_empty @posted
  end

  def test_does_not_post_while_an_owned_dialog_is_in_foreground
    @owner = 123
    refute @keys.refresh_placement_preview
    assert_empty @posted
  end

  def test_does_not_post_while_a_modifier_or_mouse_button_is_down
    @pressed = true
    refute @keys.refresh_placement_preview
    assert_empty @posted
  end

  def test_does_not_post_when_cursor_is_outside_client_area
    @client = [-1, 210]
    refute @keys.refresh_placement_preview
    assert_empty @posted
  end

  def test_failed_post_returns_false_without_raising
    @post_result = 0
    refute @keys.refresh_placement_preview
  end
end

class NativeRotationTest < Minitest::Test
  def setup
    @fixture = PlacementTest.new('fixture')
    @fixture.setup
    @model = Sketchup.active_model
    @keys = FakeRotationKeys.new
    @model.definitions.import_definition = FakeDefinition.new([
                                                                Sketchup::Edge.new(ORIGIN,
                                                                                   Geom::Point3d.new(10, 20, 30))
                                                              ])
  end

  def teardown = @fixture.teardown

  def start_session
    MH::DWG.stub(:rotation_key_source, @keys) { MH::DWG.paste_from_clipboard }
    @session = MH::DWG.instance_variable_get(:@native_rotation)
    @source = @model.definitions.definition
    refute_nil @session
    @session.tick
  end

  def tap(axis)
    @keys.states[axis] = true
    @session.tick
    @keys.states[axis] = false
    @session.tick
    @session.tick # Allow the restarted native tool to activate.
  end

  def current_definition = @model.native_placements.last.first

  def assert_point(expected, actual)
    %i[x y z].each { |axis| assert_in_delta expected.public_send(axis), actual.public_send(axis), 0.00001 }
  end

  def test_no_rotation_keeps_the_stable_pipeline_without_wrapper_definitions
    start_session
    4.times { @session.tick }
    assert_empty @model.definitions.created
    assert_equal [[@source, false]], @model.native_placements
    assert_equal 0, @model.commits
    assert_empty @model.active_entities
  end

  { z: Geom::Point3d.new(-20, 10, 30), y: Geom::Point3d.new(30, 20, -10),
    x: Geom::Point3d.new(10, -30, 20) }.each do |axis, expected|
    define_method("test_#{axis}_key_rotates_90_degrees_and_keeps_native_placement") do
      start_session
      tap(axis)
      child = current_definition.entities.to_a.first
      assert_point expected, Geom::Point3d.new(10, 20, 30).transform(child.transformation)
      assert_point ORIGIN, ORIGIN.transform(child.transformation)
      assert_equal @source, child.definition
      assert_equal Geom::Point3d.new(10, 20, 30), @source.bounds.max
      assert_empty @model.active_entities
      assert_equal 21_013, @model.tools.active_tool_id
      assert_equal false, @model.native_placements.last.last
      assert_empty UI.messages
    end
  end

  def test_held_modifier_does_not_auto_repeat_and_rotates_only_on_release
    start_session
    @keys.states[:x] = true
    10.times { @session.tick }
    assert_equal 1, @model.native_placements.length
    @keys.states[:x] = false
    @session.tick
    10.times { @session.tick }
    assert_equal 2, @model.native_placements.length
    assert_equal [1, 0, 0], @session.instance_variable_get(:@turns)
  end

  def test_paste_shortcut_modifier_already_held_is_not_treated_as_rotation
    @keys.states[:z] = true
    start_session
    @keys.states[:z] = false
    @session.tick
    assert_equal 1, @model.native_placements.length
    tap(:z)
    assert_equal 2, @model.native_placements.length
  end

  def test_four_taps_return_to_original_definition_and_reuse_24_directions
    start_session
    4.times { tap(:z) }
    assert current_definition.equal?(@source), 'Four turns must return to the source definition'
    assert_equal 23, @model.definitions.created.length
    assert_equal 1, @model.commits
    assert_equal 24, @session.instance_variable_get(:@orientations).values.uniq.length
    assert_equal 5, @model.native_placements.length
  end

  def test_rotation_refreshes_preview_at_stationary_cursor_after_native_activation
    start_session
    assert_empty @keys.preview_refreshes
    @keys.cursor = [617, 241]
    tap(:z)
    assert_equal [[617, 241]], @keys.preview_refreshes
    assert_empty @model.active_entities
    5.times { @session.tick }
    assert_equal 1, @keys.preview_refreshes.length
  end

  def test_preview_refresh_waits_for_restarted_native_tool_and_uses_latest_cursor
    start_session
    restart_before_native_activation(:x)
    @session.tick
    assert_empty @keys.preview_refreshes
    @keys.cursor = [810, 340]
    @model.tools.change(21_013)
    @session.tick
    assert_equal [[810, 340]], @keys.preview_refreshes
  end

  def test_pending_preview_refresh_never_runs_during_mouse_click_or_after_cancel
    start_session
    restart_before_native_activation(:y)
    @model.tools.change(21_013)
    @keys.states[:mouse] = true
    @session.tick
    assert_empty @keys.preview_refreshes
    @keys.states[:mouse] = false
    @session.cancel!
    @session.tick
    assert_empty @keys.preview_refreshes
  end

  def test_pending_preview_refresh_waits_until_sketchup_has_focus_again
    start_session
    @keys.focused = false
    @session.rotate!(:z)
    @session.tick
    assert_empty @keys.preview_refreshes
    @keys.focused = true
    2.times { @session.tick }
    assert_equal [@keys.cursor], @keys.preview_refreshes
  end

  def restart_before_native_activation(axis)
    delayed_placement = lambda do |definition, repeat|
      @model.native_placements << [definition, repeat]
      @model.tools.change(0)
      @model
    end
    @model.stub(:place_component, delayed_placement) { @session.rotate!(axis) }
  end

  def test_immediate_native_activation_queues_refresh_without_waiting_for_next_tick
    start_session
    @session.rotate!(:z)
    assert_equal [@keys.cursor], @keys.preview_refreshes
  end

  def test_preview_refresh_failure_keeps_native_placement_and_tag_observer
    start_session
    @keys.refresh_failure = true
    tap(:z)
    assert_equal 1, @model.tools.observers.length
    assert_equal 21_013, @model.tools.active_tool_id
    assert_empty UI.messages
    instance = @fixture.native_instance(current_definition)
    @model.tools.change(21_022)
    3.times { UI.tick }
    assert_equal 'MH_DWG', instance.layer
    assert_empty UI.timers
  end

  def test_mixed_axes_use_the_old_z_y_x_euler_order_without_changing_source
    start_session
    tap(:z)
    tap(:x)
    tap(:y)
    rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees) *
               Geom::Transformation.rotation(ORIGIN, Y_AXIS, 90.degrees) *
               Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees)
    child = current_definition.entities.to_a.first
    assert_point Geom::Point3d.new(10, 20, 30).transform(rotation),
                 Geom::Point3d.new(10, 20, 30).transform(child.transformation)
    assert_equal 1, @model.commits
    assert_equal Geom::Point3d.new(10, 20, 30), @source.bounds.max
    assert_equal 1, @source.entities.length
  end

  def test_rotated_component_is_tagged_without_retagging_nested_cad
    start_session
    tap(:x)
    instance = @fixture.native_instance(current_definition)
    @model.tools.change(21_022)
    3.times { UI.tick }
    assert_equal 'MH_DWG', instance.layer
    assert_nil current_definition.entities.to_a.first.layer
    assert_equal [instance], @model.active_entities
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_click_winning_the_rotation_race_never_rotates_placed_geometry
    start_session
    instance = @fixture.native_instance(@source)
    transform = instance.transformation
    tap(:y)
    assert_equal 1, @model.native_placements.length
    assert_empty @model.definitions.created
    UI.tick
    assert_same transform, instance.transformation
    assert_equal 'MH_DWG', instance.layer
    assert_empty UI.timers
  end

  def test_mouse_gesture_suppresses_rotation
    start_session
    @keys.states[:y] = true
    @session.tick
    @keys.states[:y] = false
    @keys.states[:mouse] = true
    @session.tick
    @keys.states[:mouse] = false
    @session.tick
    assert_equal 1, @model.native_placements.length
    assert_empty @model.definitions.created
  end

  def test_background_app_cannot_rotate_and_focus_resume_ignores_held_modifier
    start_session
    @keys.focused = false
    @keys.states[:z] = true
    @session.tick
    @keys.focused = true
    @session.tick
    @keys.states[:z] = false
    @session.tick
    assert_equal 1, @model.native_placements.length
    tap(:z)
    assert_equal 2, @model.native_placements.length
  end

  def test_orbit_pauses_keys_and_escape_detaches_without_creating_geometry
    start_session
    @model.tools.change(10_508)
    tap(:x)
    assert_equal 1, @model.native_placements.length
    @model.tools.change(21_013)
    @session.tick
    @model.tools.change(21_022)
    3.times { UI.tick }
    assert_empty @model.active_entities
    assert_empty @model.layers
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_move_cancels_rotation_but_keeps_deferred_tag_assignment
    start_session
    instance = @fixture.native_instance(@source)
    @model.tools.change(21_048)
    3.times { UI.tick }
    assert_nil instance.layer
    assert_empty UI.timers
    @model.tools.change(21_022)
    UI.tick
    assert_equal 'MH_DWG', instance.layer
  end

  def test_context_or_model_change_cancels_the_keyboard_timer
    start_session
    @model.active_path = [Object.new]
    @session.tick
    assert_empty UI.timers
    assert_empty @model.definitions.created
  end

  def test_new_paste_stops_the_old_rotation_timer
    start_session
    old = @session
    MH::DWG.stub(:rotation_key_source, @keys) { MH::DWG.paste_from_clipboard }
    @keys.states[:y] = true
    old.tick
    @keys.states[:y] = false
    old.tick
    assert_equal 2, @model.native_placements.length
    assert_equal 1, UI.timers.length
  end

  def test_keyboard_failure_stops_once_without_recreating_geometry
    start_session
    @keys.failure = true
    @session.tick
    assert_empty UI.timers
    assert_match(/Simulated keyboard failure/, UI.messages.last)
    assert_empty @model.definitions.created
  end

  def assert_rotation_start_failure_keeps_placement_and_tag
    assert_equal [[@model.definitions.definition, false]], @model.native_placements
    assert_nil MH::DWG.instance_variable_get(:@native_rotation)
    assert_equal 1, @model.tools.observers.length
    assert_empty UI.timers
    assert_match(/phím xoay/, UI.messages.last)
    refute_match(/Lỗi import CAD/, UI.messages.last)
    refute MH::DWG.instance_variable_get(:@importing)
    assert_empty @model.definitions.created

    instance = @fixture.native_instance
    @model.tools.change(21_022)
    UI.tick
    assert_equal 'MH_DWG', instance.layer
    assert_empty @model.tools.observers
    assert_empty UI.timers
  end

  def test_initial_keyboard_snapshot_failure_keeps_native_placement_and_tag
    @keys.failure = true
    MH::DWG.stub(:rotation_key_source, @keys) { MH::DWG.paste_from_clipboard }
    assert_rotation_start_failure_keeps_placement_and_tag
  end

  def test_initial_focus_check_failure_keeps_native_placement_and_tag
    def @keys.focused? = raise('Simulated focus failure')
    MH::DWG.stub(:rotation_key_source, @keys) { MH::DWG.paste_from_clipboard }
    assert_rotation_start_failure_keeps_placement_and_tag
  end

  def test_rotation_timer_start_failure_keeps_native_placement_and_tag
    UI.stub(:start_timer, ->(*) { raise 'Simulated timer failure' }) do
      MH::DWG.stub(:rotation_key_source, @keys) { MH::DWG.paste_from_clipboard }
    end
    assert_rotation_start_failure_keeps_placement_and_tag
  end

  def test_prompt_failure_cleans_up_rotation_timer_and_keeps_tag
    Sketchup.stub(:set_status_text, ->(*) { raise 'Simulated prompt failure' }) do
      MH::DWG.stub(:rotation_key_source, @keys) { MH::DWG.paste_from_clipboard }
    end
    assert_rotation_start_failure_keeps_placement_and_tag
  end

  def test_3d_text_sharing_the_native_tool_id_cannot_rotate_cad
    start_session
    @model.tools.active_tool_name = '3DTextTool'
    tap(:x)
    assert_equal 1, @model.native_placements.length
    assert_empty UI.timers
    assert_empty @model.definitions.created
  end

  def test_wrapper_failure_aborts_and_does_not_start_another_native_placement
    start_session
    definitions = @model.definitions
    def definitions.add(_) = raise('Simulated wrapper failure')
    tap(:x)
    assert_equal 1, @model.aborts
    refute @model.operation
    assert_equal 1, @model.native_placements.length
    assert_empty @model.active_entities
    assert_empty UI.timers
    assert_match(/Simulated wrapper failure/, UI.messages.last)
  end
end
