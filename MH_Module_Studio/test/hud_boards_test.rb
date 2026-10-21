# encoding: UTF-8
require 'minitest/autorun'
require_relative '../hud_config'
require_relative '../library_hud'

class ModuleStudioHUDBoardsTest < Minitest::Test
  S=MH::ModuleStudio
  def config
    S::LibraryCatalog.settings('hud_board_version'=>1,'hud_boards'=>[{'id'=>'one','name'=>'Tấm đứng','key'=>'D','slots'=>Array.new(8)}])
  end
  def test_sparse_drop_replaces_exact_slot_and_internal_move_swaps_without_filling
    original=config
    first=S::HUDBoards.put(original,'A.skp',5,'one')
    assert_equal [nil,nil,nil,nil,nil,'A.skp',nil,nil],S::HUDBoards.current(first)['slots']
    assert S::HUDBoards.current(original)['slots'].all?(&:nil?)
    second=S::HUDBoards.put(first,'B.skp',1,'one')
    swapped=S::HUDBoards.put(second,'A.skp',1,'one')
    assert_equal [nil,'A.skp',nil,nil,nil,'B.skp',nil,nil],S::HUDBoards.current(swapped)['slots']
    replaced=S::HUDBoards.put(swapped,'C.skp',5,'one')
    assert_equal [nil,'A.skp',nil,nil,nil,'C.skp',nil,nil],S::HUDBoards.current(replaced)['slots']
    assert_raises(S::Core::Error) { S::HUDBoards.put(config,'A',8,'one') }
    assert_raises(S::Core::Error) { S::HUDBoards.put(config,'A',0,'missing') }
  end
  def test_board_edit_requires_name_unique_letter_and_pages_are_explicit
    state=S::HUDBoards.edit(config,'create',{'id'=>'two','name'=>'Tủ dưới','key'=>'T'})
    assert_equal 'two',state['hud_board']
    assert_equal 8,S::HUDBoards.current(state)['slots'].length
    state=S::HUDBoards.edit(state,'page',{'id'=>'two'})
    assert_equal 16,S::HUDBoards.current(state)['slots'].length
    assert_raises(S::Core::Error) { S::HUDBoards.edit(state,'update',{'id'=>'two','name'=>'Tủ','key'=>'D'}) }
    assert_raises(S::Core::Error) { S::HUDBoards.edit(state,'create',{'id'=>'three','name'=>'Tủ','key'=>''}) }
    assert_raises(S::Core::Error) { S::HUDBoards.edit(state,'create',{'id'=>'three','name'=>' ','key'=>'R'}) }
    state=S::HUDBoards.edit(state,'delete',{'id'=>'two'})
    assert_equal 'one',state['hud_board']
  end
  def test_new_folders_never_create_boards_or_icons_and_search_keeps_positions
    empty=S::LibraryCatalog.settings('folder'=>'folder','folder_keys'=>{'folder'=>'F'})
    assert_empty empty['hud_boards']
    entries=[{'id'=>'A','folder'=>'folder','name'=>'Tấm đứng'},{'id'=>'B','folder'=>'folder','name'=>'Tấm ngang'}]
    state=S::HUDBoards.put(config,'A',6,'one')
    assert_nil S::HUDBoards.entries(entries,state,'ngang')[6]
    assert_equal entries.first,S::HUDBoards.entries(entries,state,'đứng')[6]
    assert_equal 1,S::HUDBoards.entries(entries,state).compact.length
  end
  def test_legacy_explicit_order_migrates_once_and_remap_keeps_holes_name_and_key
    old=S::LibraryCatalog.settings('hud_orders'=>{'Old'=>['A','B']},'folder_keys'=>{'Old'=>'O'})
    assert_equal ['A','B',nil,nil,nil,nil,nil,nil],S::HUDBoards.current(old)['slots']
    old=S::HUDBoards.put(old,'A',5,old['hud_board'])
    previous={'folders'=>[{'id'=>''}],'entries'=>[{'id'=>'A','folder'=>'Old','sha256'=>'a'*64},{'id'=>'B','folder'=>'Old'}]}
    catalog={'folders'=>[{'id'=>''},{'id'=>'Renamed'}],'entries'=>[{'id'=>'New','folder'=>'Renamed','sha256'=>'a'*64}]}
    mapped,missing=S::HUDConfig.remap(old,previous,catalog)
    assert_equal [nil,nil,nil,nil,nil,'New',nil,nil],S::HUDBoards.current(mapped)['slots']
    assert_equal 'Old',S::HUDBoards.current(mapped)['name']
    assert_equal 'O',S::HUDBoards.current(mapped)['key']
    assert_includes missing,'B'
    roundtrip=S::HUDConfig.parse(JSON.generate(S::HUDConfig.document(mapped,catalog)))['settings']
    assert_equal mapped.slice(*S::HUDConfig::KEYS),roundtrip
    cleared=S::HUDBoards.edit(mapped,'delete',{'id'=>mapped['hud_board']})
    assert_empty S::LibraryCatalog.settings(cleared)['hud_boards'],'Legacy orders must not resurrect deleted boards'
  end
  def test_sector_selection_matches_hover_and_click_beyond_icon_and_leaves_edit_exact
    layout=S::LibraryCatalog.layout(1200,800,60)
    hud=S::LibraryHUD.allocate;hud.define_singleton_method(:geometry) { |_view| layout }
    hud.instance_variable_set(:@library,Struct.new(:config).new(config))
    hud.instance_variable_set(:@items,Array.new(8) { |i| {'id'=>i.to_s} });hud.instance_variable_set(:@page,0)
    cx,cy=layout['center']
    8.times do |i|
      angle=-Math::PI/2+i*Math::PI/4+0.15
      x,y=cx+Math.cos(angle)*300,cy+Math.sin(angle)*300
      assert_equal [:item,i],hud.hit(x,y,nil)
      hud.instance_variable_set(:@editing,true)
      assert_nil hud.hit(x,y,nil)
      hud.instance_variable_set(:@editing,false)
    end
    hud.instance_variable_get(:@items)[2]=nil
    assert_nil hud.hit(cx+300,cy,nil)
    assert_equal [:center,nil],hud.hit(cx,cy,nil)
    assert_nil S::HUDBoards.direction(layout,cx+34,cy)
    extent=layout['radius']+layout['size']*0.5
    refute_equal :close,hud.hit(cx+extent-8,cy-extent-24,nil)&.first
  end
end
