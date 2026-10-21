import pytest

from view_signatures import align,match,signature


def pairs(xs,span=600):return [[x,x+18,span] for x in xs]


def rect(x,y,w,h,name):
    return dict(handle=name,points=[[x,y],[x+w,y],[x+w,y+h],[x,y+h],[x,y]])


def test_unique_gap_chain_finds_large_translation_and_ignores_line_lengths():
    r=match(pairs([0,782,1182,1982],600),pairs([10000,10782,11182,11982],2400))
    assert r['status']=='proven' and r['offset_mm']==-10000 and r['matched_pairs']==4
    assert r['candidates'][0]['matches'][0]['residual_mm']==0


def test_periodic_partial_chain_does_not_choose_left_or_nearest_envelope():
    r=match(pairs([0,500,1000,1500,2000]),pairs([10000,10500]))
    assert r['status']=='ambiguous' and len(r['candidates'])==4


def test_asymmetric_partial_chain_and_reflection_have_a_unique_pose():
    r=match(pairs([0,400,1000,1700]),pairs([11000,11700]))
    assert r['status']=='proven' and r['offset_mm']==-10000
    r=match([[0,18,900],[594,600,900]],[[9000,9006,2400],[9582,9600,2400]],True)
    assert r['status']=='proven' and r['offset_mm']==9600 and r['scale']==-1


def test_source_scaling_is_not_allowed():
    assert match(pairs([0,400,1100]),pairs([0,440,1210]))['status']=='insufficient'


def test_only_standard_closed_stations_vote_and_duplicates_do_not_add_votes():
    rows=[rect(x,0,18,600,str(i)) for i,x in enumerate([0,400,1100])]
    noise=[rect(-200,0,24,700,'notstock'),dict(handle='open',points=[[-500,0],[-500,600],[-482,600],[-482,0]])]
    assert len(signature(rows+rows+noise,0))==3
    r=align(rows+noise,[rect(x+5000,2000,18,2400,'f'+str(i)) for i,x in enumerate([0,400,1100])])
    assert r['status']=='proven' and r['offset_mm']==-5000


def test_different_cad_axes_are_compared_as_the_same_physical_depth():
    plan=[rect(0,y,1500,t,str(i)) for i,(y,t) in enumerate([(0,18),(300,12),(594,6)])]
    side=[rect(5000+y,2000,t,2400,'s'+str(i)) for i,(y,t) in enumerate([(0,18),(300,12),(594,6)])]
    r=align(plan,side,1,0)
    assert r['status']=='proven' and r['offset_mm']==-5000


def test_l_arm_slice_does_not_use_the_other_branch():
    rows=[rect(0,-1200,600,18,'return'),rect(0,-1200,18,1800,'left'),rect(582,-1200,18,1200,'inner'),
          rect(0,0,2000,18,'front'),rect(0,582,2000,18,'back'),rect(1982,0,18,600,'right')]
    assert min(p[0] for p in signature(rows,1,1000))==0
    assert min(p[0] for p in signature(rows,1,300))==-1200


def test_repeated_patterns_are_bounded_and_remain_unresolved():
    r=match(pairs(range(0,150000,100)),pairs(range(300000,330000,100)))
    assert r['status'] in ('ambiguous','insufficient')
    assert r.get('probes',0)<150000


def test_middle_stretch_keeps_both_chains_even_when_exact_pose_matches_only_half():
    r=match(pairs([0,400,1000,1700]),pairs([10000,10400,12600,13300]))
    assert r['status']=='proven' and r['coverage']==.5
    assert r['changed_gap']['sequence_coverage']==1 and r['changed_gap']['gap_difference_mm']==-1600
    assert r['offset_mm']==-10000 and r['changed_gap']['right_offset_mm']==-11600
    assert r['changed_gap']['anchor_side']=='left' and 'stretch' in r['reason']


def test_missing_station_and_twenty_percent_total_difference_do_not_block_best_ratio():
    r=match(pairs([0,400,1000,1700,2400]),pairs([10000,10400,11700,12880]))
    assert r['status']=='proven' and r['coverage']==.75 and r['offset_mm']==-10000


def test_uniform_scaling_is_never_mistaken_for_one_changed_middle_gap():
    r=match(pairs([0,400,1000,1700]),pairs([10000,10440,11100,11870]))
    assert r['status']=='insufficient' and not r.get('changed_gap')
