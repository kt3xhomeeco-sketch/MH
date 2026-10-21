# encoding: UTF-8
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../library_hud'
COPY_MODIFIER_MASK=8 unless defined?(COPY_MODIFIER_MASK)
CONSTRAIN_MODIFIER_MASK=4 unless defined?(CONSTRAIN_MODIFIER_MASK)
class ModuleStudioPlacementModifiersTest < Minitest::Test
  S=MH::ModuleStudio
  def setup
    @hud=S::LibraryHUD.allocate;@hud.instance_variable_set(:@pending,{'import_template'=>{'enabled'=>true}})
  end
  def test_click_flags_select_links_unlinked_fit_or_replace
    calls=[];linked={'mode'=>'template'};replacement={'mode'=>'replace'};cavity={'mode'=>'cavity'}
    S::ImportLinks.stub(:detect,->(*_args,**_kw) { calls << :links;linked }) do
      S::LibraryPlacement.stub(:detect,->(*_args,**kw) { calls << (kw[:replace] ? :replace : :fit);kw[:replace] ? replacement : cavity }) do
        [[0,linked],[4,cavity],[8,replacement],[12,replacement]].each do |flags,expected|
          @hud.update_placement(nil,1,2,flags)
          expected ? assert_equal(expected,@hud.instance_variable_get(:@placement)) : assert_nil(@hud.instance_variable_get(:@placement))
        end
        @hud.instance_variable_set(:@pending,{});@hud.update_placement(nil,1,2,0)
        assert_nil @hud.instance_variable_get(:@placement)
      end
    end
    assert_equal %i[links fit replace replace],calls
    S::ImportLinks.stub(:detect,nil) { @hud.instance_variable_set(:@pending,{'import_template'=>{'enabled'=>true}});@hud.update_placement(nil,1,2,0) }
    assert_nil @hud.instance_variable_get(:@placement)
    S::LibraryPlacement.stub(:detect,nil) { @hud.update_placement(nil,1,2,4) }
    assert_nil @hud.instance_variable_get(:@placement)
  end
  def test_press_and_release_modifiers_update_without_moving_the_mouse
    @hud.instance_variable_set(:@active,true);@hud.instance_variable_set(:@last_mouse,[10,20])
    values=[];@hud.define_singleton_method(:update_placement) { |_view,_x,_y,flags| values << flags }
    view=Object.new;view.define_singleton_method(:invalidate) {}
    @hud.onKeyDown(16,1,0,view);@hud.onKeyDown(17,1,4,view);@hud.onKeyUp(17,1,4,view);@hud.onKeyUp(16,1,0,view)
    assert_equal [4,12,4,0],values
  end
  def test_placement_click_uses_current_modifiers_instead_of_the_preview
    view=Object.new;placements=[];finished=[]
    input=Object.new;input.define_singleton_method(:pick) { |*_args| };input.define_singleton_method(:valid?) { true };input.define_singleton_method(:position) { :point };input.define_singleton_method(:clear) {}
    library=Object.new;library.define_singleton_method(:place) { |_data,_point,placement:| placements << placement }
    library.define_singleton_method(:resolve_fit) { |data,placement| [data,placement] }
    @hud.instance_variable_set(:@input,input);@hud.instance_variable_set(:@library,library)
    @hud.define_singleton_method(:hit) { |*_args| nil };@hud.define_singleton_method(:finish) { finished << true };@hud.define_singleton_method(:refresh) {}
    S::ImportLinks.stub(:detect,{'mode'=>'template'}) do
      S::LibraryPlacement.stub(:detect,->(*_args,**kw) { {'mode'=>kw[:replace] ? 'replace' : 'cavity'} }) do
        @hud.update_placement(view,1,2,0)
        @hud.onLButtonDown(4,1,2,view)
        @hud.onLButtonDown(8,1,2,view)
        @hud.onLButtonDown(0,1,2,view)
        assert @hud.pending
        @hud.onLButtonDown(4,1,2,view)
      end
    end
    assert_equal [{'mode'=>'cavity'},{'mode'=>'replace'},{'mode'=>'replace'},{'mode'=>'cavity'}],placements
    assert_equal 2,finished.length
    @hud.cancel_placement(view.tap { |v| v.define_singleton_method(:tooltip=) { |_value| } })
    assert_nil @hud.pending
    refute @hud.replacement?(0)
  end
end
