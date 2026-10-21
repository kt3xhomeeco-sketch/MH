# encoding: UTF-8
require 'minitest/autorun'
require_relative '../core'

class ModuleStudioAssemblyInferenceTest < Minitest::Test
  S = MH::ModuleStudio

  def plane(x,normal: [1,0,0],y: 0,z: 0,width: 100,height: 100)
    {'point'=>[x,y+width/2.0,z+height/2.0],'normal'=>normal,
     'points'=>[[x,y,z],[x,y+width,z],[x,y+width,z+height],[x,y,z+height]]}
  end

  def anchor(id,side=0)
    {'root'=>id,'path'=>[],'axis'=>0,'side'=>side}
  end

  def test_contact_requires_opposed_overlapping_nonpenetrating_faces_within_search_distance
    a = plane(10)
    b = plane(13,normal:[-1,0,0],y:50)
    contact = S::AssemblyInference.contact(a,b,max_gap:20)
    assert_in_delta 3,contact['gap']
    assert_in_delta 5000,contact['area']
    assert_in_delta 75,contact['point'][1]
    assert_nil S::AssemblyInference.contact(a,plane(13),max_gap:20)
    assert_nil S::AssemblyInference.contact(a,plane(13,normal:[-1,0,0],y:100),max_gap:20)
    assert_nil S::AssemblyInference.contact(a,plane(13,normal:[-1,0,0],y:200),max_gap:20)
    assert_nil S::AssemblyInference.contact(a,plane(9,normal:[-1,0,0]),max_gap:20)
    assert_nil S::AssemblyInference.contact(a,b,max_gap:2)
    assert_in_delta 0,S::AssemblyInference.contact(a,plane(10,normal:[-1,0,0]),max_gap:0)['gap']
  end

  def test_rotated_coplanar_rectangles_use_polygon_overlap_not_projected_bounding_boxes
    a = plane(0)
    b = plane(3,normal:[-1,0,0])
    b['points'] = [[3,80,140],[3,140,80],[3,200,140],[3,140,200]]
    assert_nil S::AssemblyInference.contact(a,b,max_gap:20)
    b['points'] = [[3,50,-20],[3,120,50],[3,50,120],[3,-20,50]]
    result = S::AssemblyInference.contact(a,b,max_gap:20)
    assert result['area']>8000 && result['area']<10000
    reversed = S::Core.copy_data(a); reversed['points'].reverse!
    assert_in_delta result['area'],S::AssemblyInference.contact(reversed,b,max_gap:20)['area']
  end

  def test_existing_dependencies_choose_direction_duplicates_copies_and_cycles_are_skipped
    a = anchor('A'); b = anchor('B',1); c = anchor('C')
    prior = {'id'=>'old','mode'=>'contact','a'=>b,'b'=>a,'gap'=>3}
    candidate = {'a'=>a.merge('axis'=>1),'b'=>b.merge('axis'=>1),'gap'=>4}
    chosen = S::AssemblyInference.choose([candidate],[prior])
    assert_equal 'B',chosen.first.dig('a','root')
    assert_equal 'A',chosen.first.dig('b','root')
    assert_equal 4,chosen.first['gap']
    assert_empty S::AssemblyInference.choose([candidate],[prior]+chosen)
    assert_empty S::AssemblyInference.choose([{'a'=>a,'b'=>b,'gap'=>3}],[prior])
    repeat = {'id'=>'copy','mode'=>'repeat','b'=>c,'copies'=>['A']}
    assert_empty S::AssemblyInference.choose([candidate],[repeat])
    assert_empty S::AssemblyInference.choose([candidate.merge('visible'=>false)],[])
    untouched = JSON.generate(prior)
    chosen.first['a']['name']='local'
    assert_equal untouched,JSON.generate(prior)
  end

  def test_scope_and_gap_are_retained_without_rounding_and_external_validation_can_reverse
    a = anchor('A').merge('scope'=>'S'); b = anchor('B').merge('scope'=>'S')
    row = S::AssemblyInference.record(a,b,2.123456789)
    assert_equal 'S',row['scope']; assert row['id'].start_with?('S:')
    assert_equal 2.123456789,row['gap']; refute row['external']
    b.delete('scope')
    result = S::AssemblyInference.choose([{'a'=>a,'b'=>b,'gap'=>3}],[]) do |rows|
      raise S::Core::Error,'external cycle' if rows.last.dig('b','root')=='B'
    end
    assert result.first['external']
    assert_equal 'A',result.first.dig('b','root')
  end

  def test_candidates_validate_range_and_keep_source_immutable
    modules = [{'faces'=>[{'anchor'=>anchor('A'),'plane'=>plane(0)}]},
               {'faces'=>[{'anchor'=>anchor('B'),'plane'=>plane(3,normal:[-1,0,0])}]}]
    before = JSON.generate(modules)
    assert_equal 1,S::AssemblyInference.candidates(modules,max_gap:3).length
    assert_equal before,JSON.generate(modules)
    [-1,1001,'bad'].each { |gap| assert_raises(S::Core::Error) { S::AssemblyInference.candidates(modules,max_gap:gap) } }
  end

  def test_coplanar_adjacent_and_separated_faces_keep_plane_offset_without_remote_matches
    a=plane(0)
    adjacent=S::AssemblyInference.coplanar(a,plane(0,y:100),max_gap:0)
    assert_equal 'coplanar',adjacent['relation']
    assert_in_delta 0,adjacent['gap']
    assert_in_delta 0,adjacent['separation']
    assert_in_delta 20,S::AssemblyInference.coplanar(a,plane(0,y:120),max_gap:20)['separation']
    assert_nil S::AssemblyInference.coplanar(a,plane(0,y:120.1),max_gap:20)
    assert_nil S::AssemblyInference.coplanar(a,plane(0.03,y:100),max_gap:20)
    assert_nil S::AssemblyInference.coplanar(a,plane(0,normal:[0,1,0],y:100),max_gap:20)
    diagonal=plane(0,y:110,z:110)
    assert_nil S::AssemblyInference.coplanar(a,diagonal,max_gap:10)
    assert_in_delta Math.sqrt(200),S::AssemblyInference.coplanar(a,diagonal,max_gap:15)['separation']
    b=plane(0);b['points']=[[0,80,140],[0,140,80],[0,200,140],[0,140,200]]
    assert_nil S::AssemblyInference.coplanar(a,b,max_gap:10),'Projected bounding-box overlap is not enough'
    assert_in_delta 0.5,S::AssemblyInference.segment_distance2([1,0],[0,0],[2,2])
  end

  def test_coplanar_candidates_are_explicit_and_reverse_signed_offsets_consistently
    a=anchor('A');b=anchor('B')
    modules=[{'faces'=>[{'anchor'=>a,'plane'=>plane(0)}]}, {'faces'=>[{'anchor'=>b,'plane'=>plane(0.01,y:100)}]}]
    candidates=S::AssemblyInference.candidates(modules,max_gap:0)
    assert_equal 1,candidates.length
    assert_equal 'coplanar',candidates.first['relation']
    prior={'id'=>'old','mode'=>'contact','a'=>b.merge('axis'=>1),'b'=>a.merge('axis'=>1),'gap'=>0}
    row=S::AssemblyInference.choose(candidates,[prior]).first
    assert_equal 'B',row.dig('a','root')
    assert_equal 'coplanar',row['relation']
    assert_in_delta(-0.01,row['gap'])
    assert_empty S::AssemblyInference.choose(candidates,[prior,row])
  end

  def envelope(id,low,high)
    faces=3.times.flat_map do |axis|
      2.times.map do |side|
        normal=[0,0,0];normal[axis]=side.zero? ? -1 : 1
        others=[0,1,2]-[axis]
        points=[[0,0],[1,0],[1,1],[0,1]].map do |pair|
          point=low.dup;point[axis]=[low,high][side][axis]
          others.each_with_index { |other,i| point[other]=[low,high][pair[i]][other] }
          point
        end
        {'anchor'=>anchor(id,side).merge('axis'=>axis,'level'=>'module'),
         'plane'=>{'normal'=>normal,'point'=>3.times.map { |i| points.sum { |p| p[i] }/4.0 },'points'=>points}}
      end
    end
    {'faces'=>faces}
  end

  def test_only_selected_envelopes_block_a_gap_not_mesh_on_virtual_faces
    a=envelope('A',[0,0,0],[10,100,100]);b=envelope('B',[20,0,0],[30,100,100])
    row=S::AssemblyInference.candidates([a,b],max_gap:10).find { |entry| entry['relation']=='contact' }
    assert row
    assert S::AssemblyInference.unobstructed?(row,[a,b])
    blocker=envelope('C',[14,20,20],[16,80,80])
    refute S::AssemblyInference.unobstructed?(row,[a,b,blocker])
    outside=envelope('C',[14,150,150],[16,180,180])
    assert S::AssemblyInference.unobstructed?(row,[a,b,outside])
    behind=envelope('C',[40,0,0],[50,100,100])
    assert S::AssemblyInference.unobstructed?(row,[a,b,behind])
    touching=row.merge('gap'=>0)
    assert S::AssemblyInference.unobstructed?(touching,[a,b,blocker])
  end

  def test_legacy_migration_only_removes_inferred_panel_links_wholly_in_the_selection
    a=anchor('A').merge('path'=>['panelA']);b=anchor('B').merge('part'=>'panelB')
    legacy={'id'=>'legacy','mode'=>'contact','inferred'=>true,'a'=>a,'b'=>b,'gap'=>3}
    manual=legacy.merge('id'=>'manual','inferred'=>false)
    elsewhere=legacy.merge('id'=>'elsewhere','b'=>anchor('C'))
    envelope=legacy.merge('id'=>'envelope','a'=>anchor('A').merge('level'=>'module'),'b'=>anchor('B').merge('level'=>'module'))
    other_scope=S::Core.copy_data(legacy).merge('id'=>'other_scope')
    %w[a b].each { |key| other_scope[key]['scope']='other' }
    rows=[legacy,manual,elsewhere,envelope,other_scope];before=JSON.generate(rows)
    assert_equal [legacy],S::AssemblyInference.legacy_panel_links(rows,[[nil,'A'],[nil,'B']])
    assert_equal before,JSON.generate(rows)
    assert_empty S::AssemblyInference.legacy_panel_links(rows,[[nil,'A']])
  end

  def test_parallel_offset_planes_keep_signed_distances_and_range_without_moving_faces
    a=plane(0);b=plane(7,y:100)
    result=S::AssemblyInference.parallel(a,b,max_gap:20)
    assert_equal 'parallel',result['relation']
    assert_in_delta 7,result['gap']
    assert_in_delta(-7,S::AssemblyInference.parallel(a,plane(-7,y:100),max_gap:20)['gap'])
    assert_nil S::AssemblyInference.parallel(a,b,max_gap:6)
    assert_nil S::AssemblyInference.parallel(a,plane(7,normal:[0,1,0]),max_gap:20)
    assert_nil S::AssemblyInference.parallel(a,plane(-7,normal:[-1,0,0]),max_gap:20)
    assert S::AssemblyInference.parallel(a,plane(7,normal:[-1,0,0],y:100),max_gap:20)
    modules=[{'faces'=>[{'anchor'=>anchor('A'),'plane'=>a}]},{'faces'=>[{'anchor'=>anchor('B'),'plane'=>b}]}]
    rows=S::AssemblyInference.candidates(modules,max_gap:20)
    assert_equal 1,rows.length
    assert_equal 'parallel',rows.first['relation']
    prior={'id'=>'old','mode'=>'contact','a'=>anchor('B').merge('axis'=>1),'b'=>anchor('A').merge('axis'=>1),'gap'=>0}
    chosen=S::AssemblyInference.choose(rows,[prior]).first
    assert_equal 'B',chosen.dig('a','root')
    assert_in_delta(-7,chosen['gap'])
    assert_match(/Song song/,S::AssemblyPresentation.label(chosen))
  end
end
