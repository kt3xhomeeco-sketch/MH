# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioDrawerVariantsTest < Minitest::Test
  S=MH::ModuleStudio
  def item(name,folder='Ngăn kéo')
    {'id'=>folder+'/'+name,'folder'=>folder,'name'=>name}
  end
  def entries(kind='âm')
    [250,300,350,400,450,500,550].map { |size| item("Ngăn kéo #{kind} 1 tầng #{size}") }
  end
  def test_standard_depth_uses_clearance_and_never_crosses_families
    rows=entries
    rows+=[item('Ngăn kéo âm 1 tầng 540','Khác'),item('Ngăn kéo âm 2 tầng 540'),item('Ngăn kéo bi 1 tầng 540'),item('Ngăn kéo âm 1 tầng 18 540')]
    assert_equal 500,S::DrawerVariants.choose(rows,rows.first['id'],550)['size']
    assert_equal 550,S::DrawerVariants.choose(rows,rows.first['id'],565)['size']
    assert_equal 550,S::DrawerVariants.choose(rows,rows.first['id'],564.5)['size']
    assert_equal 500,S::DrawerVariants.choose(rows,rows.first['id'],564.49)['size']
    ball=entries('bi')
    assert_equal 550,S::DrawerVariants.choose(ball,ball.first['id'],555)['size']
    assert_equal 500,S::DrawerVariants.choose(ball,ball.first['id'],550)['size']
    assert_raises(S::Core::Error) { S::DrawerVariants.choose(rows,rows.first['id'],250) }
  end
  def test_unsized_seed_can_select_sibling_without_guessing_frames_or_fronts
    seed=item('Ngăn kéo âm 1 tầng');rows=entries+[seed]
    assert_equal 500,S::DrawerVariants.choose(rows,seed['id'],560)['size']
    %w[Khung Mặt].each { |prefix| assert_nil S::DrawerVariants.info(item(prefix+' ngăn kéo 500')) }
    single=item('Ngăn kéo 3 tầng');assert_nil S::DrawerVariants.choose([single],single['id'],600)
    assert_nil S::DrawerVariants.choose(rows,'missing',600)
    assert_equal rows.first['id'],S::DrawerVariants.choose(rows,rows.first['id'],265)['id']
  end
  def test_drawer_depth_stays_nominal_in_scaled_host_and_input_is_unchanged
    placement={'mode'=>'cavity','frame'=>[1,0,0,0,0,2,0,0,0,0,1,0,0,0,0,1],'bounds'=>[[10,20,30],[610,320,430]]}
    data={'snapshot'=>{'envelope'=>[[5,7,9],[505,557,209]]},'drawer_fit'=>{'available_depth'=>600}}
    original=S::Core.copy_data(placement)
    fitted=S::DrawerVariants.fit_bounds(data,placement)
    assert_equal [[10,20,30],[610,295,430]],fitted['bounds']
    assert_equal 600,fitted['fit_depth_mm']
    assert_equal original,placement
    linked=placement.merge('mode'=>'template');assert_same linked,S::DrawerVariants.fit_bounds(data,linked)
    assert_raises(S::Core::Error) { S::DrawerVariants.fit_bounds(data,placement.merge('bounds'=>[[0,0,0],[600,100,400]])) }
  end
end
