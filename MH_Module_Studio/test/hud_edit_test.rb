# encoding: UTF-8
require 'minitest/autorun'
require_relative '../library_hud'
require_relative '../module_options'

class ModuleStudioHUDEditTest < Minitest::Test
  class LibraryStub
    attr_reader :config, :catalog

    def initialize
      @config = { 'folder' => 'target' }
      @catalog = { 'root' => 'D:/Library' }
    end

    def save_settings(values)
      @config.merge!(values)
    end

    def publish; end

    def entry(id)
      raise MH::ModuleStudio::Core::Error, 'Missing item' unless id == 'source/module.skp'
      { 'id' => id }
    end
  end

  def setup
    @library = LibraryStub.new
    @hud = MH::ModuleStudio::LibraryHUD.allocate
    @hud.instance_variable_set(:@library, @library)
  end

  def test_library_browsing_during_edit_does_not_change_destination_folder
    @hud.set_editing(true)
    @library.save_settings('folder' => 'source')
    assert_equal 'source', @library.config['folder']
    assert_equal 'target', @hud.hud_folder
    assert_equal 'target', @hud.hud_settings['folder']
    @hud.set_editing(true)
    assert_equal 'target', @hud.hud_folder
    @hud.set_editing(false)
    assert_equal 'target', @library.config['folder']
    refute @hud.editing
  end

  def test_drag_cancellation_and_stale_events_do_not_end_another_drag
    @hud.set_editing(true)
    assert_raises(MH::ModuleStudio::Core::Error) { @hud.begin_external_drag('source/module.skp', 'wrong root', 'token') }
    @hud.begin_external_drag('source/module.skp', 'D:/Library', 'first')
    @hud.cancel_external_drag('stale')
    assert @hud.drag_active?
    @hud.end_external_drag('stale')
    assert @hud.drag_active?
    @hud.cancel_external_drag('first')
    refute @hud.drag_active?
    @hud.begin_external_drag('source/module.skp', 'D:/Library', 'second')
    @hud.set_editing(false)
    refute @hud.drag_active?
  end

  def test_pending_placement_hides_hud_and_its_click_targets_before_input_is_valid
    @hud.instance_variable_set(:@pending, { 'name' => 'Cabinet' })
    @hud.instance_variable_set(:@input, Struct.new(:valid?).new(false))
    view = Object.new
    assert_nil @hud.hit(100, 100, view)
    @hud.draw(view)
    assert_nil @hud.instance_variable_get(:@draw_error)
  end

  def test_pending_placement_ignores_invisible_browse_controls
    pending = { 'name' => 'Cabinet' }
    @hud.instance_variable_set(:@pending, pending)
    @hud.instance_variable_set(:@active, true)
    @hud.instance_variable_set(:@query, 'cabinet')
    [65, 49, 9, 13, 8, 39].each do |key|
      assert @hud.onKeyDown(key, 1, 0, Object.new)
      assert_same pending, @hud.pending
      assert_equal 'cabinet', @hud.query
    end
  end

  def test_escape_cancels_preview_and_keeps_current_library_context
    view = Struct.new(:tooltip).new('Preview')
    input = Object.new
    input.define_singleton_method(:clear) { @cleared = true }
    @hud.instance_variable_set(:@input,input)
    @hud.instance_variable_set(:@active,true)
    @hud.instance_variable_set(:@pending,{'name'=>'Cabinet'})
    @hud.instance_variable_set(:@placement,{'mode'=>'replace'})
    @hud.instance_variable_set(:@placement_mouse,[10,20,true])
    @hud.instance_variable_set(:@placement_error,'Stale error')
    @hud.instance_variable_set(:@query,'cabinet')
    @hud.instance_variable_set(:@page,2)
    @hud.define_singleton_method(:refresh) { @refreshed = true }
    @hud.define_singleton_method(:finish) { @finished = true }
    assert @hud.onKeyDown(27,1,0,view)
    assert_nil @hud.pending
    assert_nil @hud.instance_variable_get(:@placement)
    assert_nil @hud.instance_variable_get(:@placement_mouse)
    assert_nil @hud.instance_variable_get(:@placement_error)
    assert_equal '',view.tooltip
    assert_equal 'cabinet',@hud.query
    assert_equal 2,@hud.instance_variable_get(:@page)
    assert_equal 'target',@library.config['folder']
    assert input.instance_variable_get(:@cleared)
    assert @hud.active
    assert @hud.instance_variable_get(:@refreshed)
    refute @hud.instance_variable_get(:@finished)
    @hud.onKeyDown(27,2,0,view)
    refute @hud.instance_variable_get(:@finished),'Holding Esc must not immediately close the returned Library'
    @hud.onKeyDown(27,1,0,view)
    assert @hud.instance_variable_get(:@finished)
  end

  def test_space_still_exits_during_placement
    @hud.instance_variable_set(:@active,true)
    @hud.instance_variable_set(:@pending,{'name'=>'Cabinet'})
    @hud.define_singleton_method(:finish) { @finished = true }
    assert @hud.onKeyDown(32,1,0,Object.new)
    assert @hud.instance_variable_get(:@finished)
  end

  def test_icon_click_uses_fast_preview_without_running_full_preflight
    @library.define_singleton_method(:preview) { |id| {'entry_id'=>id,'name'=>'Cabinet'} }
    @library.define_singleton_method(:prepare) { |_id| raise 'Full preflight must wait for placement' }
    input=Object.new;input.define_singleton_method(:clear) {}
    @hud.instance_variable_set(:@input,input)
    @hud.define_singleton_method(:refresh) {}
    @hud.choose('id'=>'cabinet.skp')
    assert_equal 'cabinet.skp',@hud.pending['entry_id']
    assert_nil @hud.error
  end

  def test_successful_import_and_replacement_exit_without_opening_options
    point = Object.new
    input = Object.new
    input.define_singleton_method(:pick) { |_view,_x,_y| }
    input.define_singleton_method(:valid?) { true }
    input.define_singleton_method(:position) { point }
    calls = []
    @library.define_singleton_method(:place) { |data,position,placement:| calls << [data,position,placement] }
    @hud.instance_variable_set(:@input,input)
    @hud.define_singleton_method(:update_placement) { |_view,_x,_y,_flags| }
    @hud.define_singleton_method(:replacement?) { |flags| flags!=0 }
    @hud.define_singleton_method(:refresh) { @unexpected_refresh = true }
    @hud.define_singleton_method(:finish) { @finished = true; @active = false; @pending = nil }
    [nil,{'mode'=>'replace'}].each do |placement|
      data = {'name'=>'Cabinet'}
      @hud.instance_variable_set(:@active,true)
      @hud.instance_variable_set(:@pending,data)
      @hud.instance_variable_set(:@placement,placement)
      MH::ModuleStudio.stub(:show_options,-> { flunk 'Import must not open Module Options' }) do
        @hud.onLButtonDown(placement ? 1 : 0,10,20,Object.new)
      end
      assert_equal [data,point,placement],calls.last
      assert_nil @hud.error
      assert @hud.instance_variable_get(:@finished)
      refute @hud.active
      assert_nil @hud.pending
      refute @hud.instance_variable_get(:@unexpected_refresh)
    end
  end
end
