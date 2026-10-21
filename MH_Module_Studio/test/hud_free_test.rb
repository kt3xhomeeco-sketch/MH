# encoding: UTF-8
require 'minitest/autorun'
require_relative '../hud_config'

class ModuleStudioHUDFreeTest < Minitest::Test
  S=MH::ModuleStudio
  def config
    S::LibraryCatalog.settings('hud_board_version'=>2,'hud_boards'=>[{'id'=>'one','name'=>'Bảng','key'=>'B','slots'=>['A','B']+Array.new(6)}])
  end
  def position(x=0.8,y=0.3)
    {'x'=>x,'y'=>y}
  end
  def layout(board=S::HUDBoards.current(config),spacing=100)
    S::HUDLayout.compose(1000,800,S::LibraryCatalog.layout(1000,800,60,spacing:spacing),board)
  end
  def test_migration_keeps_slots_docks_and_digits_without_inventing_free_icons
    state=config;board=S::HUDBoards.current(state)
    assert_equal 3,state['hud_board_version'];assert_empty board['free']
    assert_equal ['A','B']+Array.new(6),board['slots']
    assert_empty board['shortcuts']
  end
  def test_ring_free_and_dock_moves_swap_and_keep_digit_identity
    state=S::HUDBoards.edit(config,'shortcut',{'id'=>'one','entry'=>'A','digit'=>'9'})
    state=S::HUDBoards.put_free(state,'A',position,'one')
    board=S::HUDBoards.current(state);assert_nil board['slots'][0]
    assert_equal position,board['free']['A'];assert_equal '9',board['shortcuts']['A']
    state=S::HUDBoards.put_free(state,'B',position,'one',replace:'A')
    board=S::HUDBoards.current(state);assert_equal 'A',board['slots'][1];assert_equal position,board['free']['B']
    state=S::HUDBoards.put(state,'A',3,'one',zone:'left')
    state=S::HUDBoards.put(state,'B',3,'one',zone:'left')
    board=S::HUDBoards.current(state);assert_equal 'B',board['docks']['left'][3];assert_equal position,board['free']['A']
    state=S::HUDBoards.put_free(state,'B',position(0.2,0.4),'one')
    state=S::HUDBoards.put_free(state,'A',position(0.2,0.4),'one',replace:'B')
    board=S::HUDBoards.current(state);assert_equal position,board['free']['B'];assert_equal position(0.2,0.4),board['free']['A']
    assert_equal '9',board['shortcuts']['A']
  end
  def test_free_position_validation_clipping_and_clear
    bad=[position(Float::NAN),position(-0.1),position(1.1),position.merge('snap_x'=>8),position.merge('snap_y'=>'1')]
    bad.each { |value| assert_raises(S::Core::Error) { S::HUDBoards.put_free(config,'A',value,'one') } }
    state=S::HUDBoards.put_free(config,'A',position(0,1),'one')
    board=S::HUDBoards.current(state);point=layout(board)['free']['A']
    assert_equal [34,766],point
    state=S::HUDBoards.edit(state,'shortcut',{'id'=>'one','entry'=>'A','digit'=>'0'})
    state=S::HUDBoards.edit(state,'clear',{'id'=>'one','zone'=>'free','slot'=>'A'})
    assert_empty S::HUDBoards.current(state)['free'];assert_empty S::HUDBoards.current(state)['shortcuts']
  end
  def test_snap_horizontal_and_vertical_to_ring_and_follow_changed_radius
    board=S::HUDBoards.current(config);ring=layout(board)
    x=800;y=ring['items'][0][1]+7
    preview=S::HUDLayout.free_drop(ring,board,x,y,1000,800,moving:'A')
    assert_equal 0,preview['position']['snap_y'];assert_equal [['y',ring['items'][0][1]]],preview['guides']
    state=S::HUDBoards.put_free(config,'A',preview['position'],'one')
    changed=layout(S::HUDBoards.current(state),160)
    assert_equal changed['items'][0][1],changed['free']['A'][1]
    assert_in_delta 800,changed['free']['A'][0],0.0001
    vertical=S::HUDLayout.free_drop(ring,board,ring['items'][2][0]+6,700,1000,800)
    assert_equal 2,vertical['position']['snap_x']
    missed=S::HUDLayout.free_drop(ring,board,ring['center'][0]+20,ring['items'][0][1]-20,1000,800)
    assert_empty missed['guides']
  end
  def test_other_free_icon_alignment_resize_and_exact_hit
    state=S::HUDBoards.put_free(config,'A',position(0.8,0.2),'one');board=S::HUDBoards.current(state);ring=layout(board)
    preview=S::HUDLayout.free_drop(ring,board,700,166,1000,800,moving:'B')
    assert_includes preview['guides'],['y',160.0]
    assert_equal [:free,'A'],S::HUDLayout.free_hit(ring,800,160)
    assert_nil S::HUDLayout.free_hit(ring,840,160)
    resized=S::HUDLayout.compose(1400,1000,S::LibraryCatalog.layout(1400,1000,60),board)
    assert_equal [1120.0,200.0],resized['free']['A']
  end
  def test_new_free_icons_keep_their_offset_from_the_hud_board_when_the_board_moves
    board=S::HUDBoards.current(config);ring=layout(board)
    preview=S::HUDLayout.free_drop(ring,board,ring['center'][0]+180,ring['center'][1]-90,1000,800,moving:'A')
    assert_equal true,preview['position']['relative']
    state=S::HUDBoards.put_free(config,'A',preview['position'],'one')
    original=S::HUDLayout.compose(1000,800,S::LibraryCatalog.layout(1000,800,60,center:[ring['center'][0],ring['center'][1]],spacing:100),S::HUDBoards.current(state))
    moved=S::HUDLayout.compose(1000,800,S::LibraryCatalog.layout(1000,800,60,center:[ring['center'][0]-120,ring['center'][1]+70],spacing:100),S::HUDBoards.current(state))
    assert_equal preview['point'],original['free']['A']
    assert_equal [original['free']['A'][0]-120,original['free']['A'][1]+70],moved['free']['A']
  end
  def test_free_icons_follow_the_hud_up_down_left_and_right
    board=S::HUDBoards.current(config);ring=layout(board)
    preview=S::HUDLayout.free_drop(ring,board,ring['center'][0]+330,ring['center'][1]+120,1000,800,moving:'A')
    state=S::HUDBoards.put_free(config,'A',preview['position'],'one');board=S::HUDBoards.current(state)
    origin=layout(board)['free']['A']
    {'up'=>[0,-80],'down'=>[0,80],'left'=>[-80,0],'right'=>[80,0]}.each_value do |dx,dy|
      center=[ring['center'][0]+dx,ring['center'][1]+dy]
      moved=S::HUDLayout.compose(1000,800,S::LibraryCatalog.layout(1000,800,60,center:center,spacing:100),board)
      assert_equal [origin[0]+dx,origin[1]+dy],moved['free']['A']
    end
  end
  def test_free_icon_cluster_translates_with_the_ring_at_all_viewport_edges
    base=S::HUDBoards.current(config);ring=S::HUDLayout.compose(1000,800,S::LibraryCatalog.layout(1000,800,60),base)
    preview=S::HUDLayout.free_drop(ring,base,ring['center'][0]+280,ring['center'][1]-110,1000,800,moving:'A')
    state=S::HUDBoards.put_free(config,'A',preview['position'],'one');board=S::HUDBoards.current(state)
    extent=ring['radius']+ring['size']/2.0+8
    [[15,400],[985,400],[500,15],[500,785]].each do |requested_x,requested_y|
      requested=S::LibraryCatalog.layout(1000,800,60,center:[requested_x,requested_y])
      moved=S::HUDLayout.compose(1000,800,requested,board)
      cx,cy=moved['center'];x,y=moved['free']['A']
      assert_in_delta 280,x-cx,0.001
      assert_in_delta(-110,y-cy,0.001)
      assert_operator cx,:>=,extent
      assert_operator cx,:<=,1000-extent
      assert_operator cy,:>=,extent
      assert_operator cy,:<=,800-extent
    end
  end
  def test_snapped_free_icon_cluster_keeps_both_snap_axes_after_edge_clamp
    board=S::HUDBoards.put_free(config,'A',{'x'=>500,'y'=>-500,'relative'=>true,'snap_x'=>2,'snap_y'=>0},'one')
    moved=S::HUDLayout.compose(1000,800,S::LibraryCatalog.layout(1000,800,60,center:[10,10]),S::HUDBoards.current(board))
    assert_equal moved['items'][2][0],moved['free']['A'][0]
    assert_equal moved['items'][0][1],moved['free']['A'][1]
  end
  def test_oversized_free_cluster_uses_deterministic_common_translation
    board=S::HUDBoards.current(config);board['free']['A']={'x'=>900.0,'y'=>0.0,'relative'=>true}
    ring=S::LibraryCatalog.layout(700,500,60,center:[50,250])
    first=S::HUDLayout.compose(700,500,ring,board);second=S::HUDLayout.compose(700,500,ring,board)
    assert_equal first['center'],second['center']
    assert_equal first['free']['A'][0]-first['center'][0],900.0
    assert_equal second['free']['A'],first['free']['A']
  end
  def test_existing_viewport_positions_migrate_to_their_current_offset_from_the_board
    board=S::HUDBoards.put_free(config,'A',position(0.8,0.3),'one')
    original=layout(S::HUDBoards.current(board));anchored=S::HUDLayout.anchor_legacy_free(S::HUDBoards.current(board),original)
    assert_equal [800.0,240.0],original['free']['A']
    assert_equal({'x'=>300.0,'y'=>-160.0,'relative'=>true},anchored['A'])
    migrated=S::HUDBoards.put_free(board,'A',anchored['A'],'one')
    result=layout(S::HUDBoards.current(migrated))
    assert_equal original['free']['A'],result['free']['A']
  end
  def test_remap_and_roundtrip_preserve_free_coordinates_and_assigned_digit
    state=S::HUDBoards.put_free(config,'A',position.merge('snap_y'=>0),'one')
    state=S::HUDBoards.edit(state,'shortcut',{'id'=>'one','entry'=>'A','digit'=>'7'})
    prior={'folders'=>[{'id'=>''}],'entries'=>[{'id'=>'A','folder'=>'','sha256'=>'a'*64}]}
    catalog={'folders'=>[{'id'=>''}],'entries'=>[{'id'=>'renamed','folder'=>'','sha256'=>'a'*64}]}
    mapped,=S::HUDConfig.remap(state,prior,catalog);board=S::HUDBoards.current(mapped)
    assert_equal position.merge('snap_y'=>0),board['free']['renamed'];assert_equal({'renamed'=>'7'},board['shortcuts'])
    assert_equal mapped.slice(*S::HUDConfig::KEYS),S::HUDConfig.parse(JSON.generate(S::HUDConfig.document(mapped,catalog)))['settings']
  end
end
