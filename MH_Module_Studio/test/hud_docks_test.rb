# encoding: UTF-8
require 'minitest/autorun'
require_relative '../hud_config'

class ModuleStudioHUDDocksTest < Minitest::Test
  S=MH::ModuleStudio
  def config
    S::LibraryCatalog.settings('hud_board_version'=>1,'hud_boards'=>[{'id'=>'one','name'=>'Bảng','key'=>'B','slots'=>['A','B']+Array.new(6)}])
  end
  def test_old_board_migrates_without_implicit_digits_and_moves_swap_across_zones
    state=config;board=S::HUDBoards.current(state)
    assert_equal 3,state['hud_board_version'];assert_empty board['shortcuts']
    assert_equal ['A','B']+Array.new(6),board['slots']
    state=S::HUDBoards.put(state,'A',5,'one',zone:'left')
    assert_nil S::HUDBoards.current(state)['slots'][0]
    assert_equal [nil,nil,nil,nil,nil,'A'],S::HUDBoards.current(state)['docks']['left']
    state=S::HUDBoards.put(state,'B',5,'one',zone:'left')
    assert_equal 'A',S::HUDBoards.current(state)['slots'][1]
    assert_equal 'B',S::HUDBoards.current(state)['docks']['left'][5]
    assert_raises(S::Core::Error) { S::HUDBoards.put(state,'C',64,'one',zone:'left') }
    assert_raises(S::Core::Error) { S::HUDBoards.put(state,'C',1,'one',zone:'unknown') }
  end
  def test_explicit_numeric_shortcuts_move_with_identity_and_reject_duplicates
    state=S::HUDBoards.edit(config,'shortcut',{'id'=>'one','entry'=>'A','digit'=>'9'})
    state=S::HUDBoards.put(state,'A',2,'one',zone:'bottom')
    assert_equal 'A',S::HUDBoards.current(state)['shortcuts'].key('9')
    assert_raises(S::Core::Error) { S::HUDBoards.edit(state,'shortcut',{'id'=>'one','entry'=>'B','digit'=>'9'}) }
    assert_raises(S::Core::Error) { S::HUDBoards.edit(state,'shortcut',{'id'=>'one','entry'=>'B','digit'=>'12'}) }
    state=S::HUDBoards.edit(state,'shortcut',{'id'=>'one','entry'=>'A','digit'=>''})
    assert_empty S::HUDBoards.current(state)['shortcuts']
    state=S::HUDBoards.edit(state,'shortcut',{'id'=>'one','entry'=>'A','digit'=>'0'})
    state=S::HUDBoards.edit(state,'clear',{'id'=>'one','zone'=>'bottom','slot'=>2})
    assert_empty S::HUDBoards.current(state)['shortcuts']
  end
  def test_spacing_changes_radius_without_changing_icon_size
    close=S::LibraryCatalog.layout(1400,1000,86,spacing:80)
    far=S::LibraryCatalog.layout(1400,1000,86,spacing:200)
    assert_equal close['size'],far['size'];assert_operator far['radius'],:>,close['radius']
    assert_equal 200,S::LibraryCatalog.settings('hud_spacing'=>999)['hud_spacing']
  end
  def test_docks_anchor_on_resize_wrap_inside_viewport_and_do_not_share_corners
    state=config
    %w[top bottom left right].each { |zone| state=S::HUDBoards.put(state,zone,5,'one',zone:zone) }
    board=S::HUDBoards.current(state)
    before=S::HUDLayout.compose(1400,1000,S::LibraryCatalog.layout(1400,1000,60),board,editing:true)
    after=S::HUDLayout.compose(1600,1200,S::LibraryCatalog.layout(1600,1200,60),board,editing:true)
    assert_equal before['docks']['left'][5][0],after['docks']['left'][5][0]
    assert_in_delta 200,after['docks']['right'][5][0]-before['docks']['right'][5][0],0.001
    assert_in_delta 200,after['docks']['bottom'][5][1]-before['docks']['bottom'][5][1],0.001
    points=before['docks'].values.flatten(1)
    assert_equal points.uniq.length,points.length
    assert(points.all? { |x,y| x>=30 && y>=30 && x<=1370 && y<=970 })
    normal=S::HUDLayout.compose(1400,1000,S::LibraryCatalog.layout(1400,1000,60),board)
    assert_equal before['docks']['left'][5],normal['docks']['left'][5]
    hit=S::HUDLayout.dock_hit(before,board,*before['docks']['left'][5])
    assert_equal [:dock,['left',5]],hit
    assert_nil S::HUDLayout.dock_hit(before,board,*before['docks']['left'][0])
  end
  def test_config_remaps_docked_icon_and_digit_without_moving_its_slot
    state=S::HUDBoards.put(config,'A',7,'one',zone:'right')
    state=S::HUDBoards.edit(state,'shortcut',{'id'=>'one','entry'=>'A','digit'=>'4'})
    previous={'folders'=>[{'id'=>''}],'entries'=>[{'id'=>'A','folder'=>'','sha256'=>'a'*64},{'id'=>'B','folder'=>''}]}
    current={'folders'=>[{'id'=>''}],'entries'=>[{'id'=>'new-A','folder'=>'','sha256'=>'a'*64}]}
    mapped,=S::HUDConfig.remap(state,previous,current);board=S::HUDBoards.current(mapped)
    assert_equal [nil]*7+['new-A'],board['docks']['right']
    assert_equal({'new-A'=>'4'},board['shortcuts'])
    assert_nil board['slots'][1]
    parsed=S::HUDConfig.parse(JSON.generate(S::HUDConfig.document(mapped,current)))
    assert_equal mapped.slice(*S::HUDConfig::KEYS),parsed['settings']
  end
end
