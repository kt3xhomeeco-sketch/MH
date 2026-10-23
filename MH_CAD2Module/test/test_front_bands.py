import json
from pathlib import Path

import pytest

from front_bands import align_fronts,verify
from drawing_scope import choose_product_plan
from view_signatures import align
from test_view_signatures import rect


def test_actual_sp25_cropped_right_side_is_verified_at_three_heights_in_shared_band():
    d=json.loads((Path(__file__).parent/'fixtures/named_sp25_sections.json').read_text('utf8'));p=d['product']
    choose_product_plan(p,d['annotations'],multiple=True)
    bodies={v['id']:[p['outlines'][i] for i in v['source_row_indices']] for v in p['view_previews']}
    r=align_fronts(bodies['V06.1'],bodies['V02.1'])
    assert r['status']=='proven' and r['offset_mm']==pytest.approx(8103.634)
    assert r['height_support']==3 and all(860<c['height_mm']<1460 for c in r['height_checks'])
    assert all(c['coverage']==1 for c in r['height_checks'])


def test_global_alias_at_different_height_is_resolved_by_same_height_slices():
    target=[rect(x,860,18,600,'t'+str(i)) for i,x in enumerate([0,400,1000])]
    target += [rect(x+2000,1800,18,600,'fake'+str(i)) for i,x in enumerate([0,400,1000])]
    source=[rect(x+5000,860,18,600,'s'+str(i)) for i,x in enumerate([0,400,1000])]
    assert align(target,source)['status']=='ambiguous'
    r=align_fronts(target,source,0,0)
    assert r['status']=='proven' and r['offset_mm']==-5000 and r['height_support']==3
    assert all(860<c['height_mm']<1460 for c in r['height_checks'])


def test_repetition_at_the_same_height_stays_ambiguous_across_all_three_slices():
    target=[rect(x,860,18,600,'t'+str(i)) for i,x in enumerate([0,400,1000,2000,2400,3000])]
    source=[rect(x+5000,860,18,600,'s'+str(i)) for i,x in enumerate([0,400,1000])]
    r=verify(target,source,0,0)
    assert r['status']=='ambiguous' and len(r['height_checks'])==3


def test_three_slices_do_not_turn_unrelated_spacing_into_a_match():
    a=[rect(x,0,18,2400,'t'+str(i)) for i,x in enumerate([0,400,1000])]
    b=[rect(x+5000,0,18,2400,'s'+str(i)) for i,x in enumerate([0,550,1300])]
    assert align_fronts(a,b)['status']=='insufficient'
