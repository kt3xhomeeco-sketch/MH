from copy import deepcopy
import json
from pathlib import Path

import pytest

from elevation_builder import context
from product_height import apply,measure
from test_elevation_builder import fixture,build
from drawing_scope import choose_product_plan
from combined_runtime import analyse


def pending():
    product,notes=fixture()
    selected=choose_product_plan(product,notes,multiple=True)
    data=context(product,notes)
    from named_plans import analyse_named_plans
    from elevation_builder import apply as tiers
    analyse_named_plans(product,selected,Path('unused'))
    data['markers']={}
    tiers(product,data)
    return product,data


def test_measured_product_height_does_not_grant_module_tiers():
    p,d=pending();before=[(m['origin'][:2],m['size'][:2]) for m in p['modules']]
    apply(p,d)
    assert [(m['origin'][:2],m['size'][:2]) for m in p['modules']]==before
    assert all(m['origin'][2]==0 and m['size'][2]==2400 for m in p['modules'])
    assert p['elevation_pending'] and not p['height_pending']
    assert p['geometry_pipeline']['horizontal']['status']=='provisional'
    assert p['product_height']['module_tiers_measured'] is False
    assert 'default_height_mm' not in p and 'default_height_mm' not in p['geometry_pipeline']
    assert not any('1600' in s for s in p['explanation'])


@pytest.mark.parametrize('change',['missing','foreign','conflict','cap_only'])
def test_unknown_or_conflicting_height_keeps_1600(change):
    p,d=pending()
    if change=='missing':d['views']={}
    if change=='foreign':
        for pose in d['relations']['poses'].values():
            if pose['view_id']!=p['plan_view_id']:pose['root_id']='different-sp'
        for v in p['view_analysis']['candidates']:v['elevation_checks']=[]
    if change=='conflict':
        v=next(v for v in d['views'].values() if v['role']=='elevation')
        v['box']=list(v['box']);v['box'][3]+=200
    if change=='cap_only':
        for v in d['views'].values():v['rects']=[r for r in v['rects'] if r.w>r.h]
    apply(p,d)
    assert p['product_height']['status']=='pending' and p['height_pending']
    assert all(m['size'][2]==1600 for m in p['modules'])


def test_raised_stock_bottom_and_top_ignore_outer_wall_envelope():
    p,d=pending()
    for v in d['views'].values():
        if v['role']!='elevation':continue
        # Drawing contains context below/above the furniture; source geometry
        # proof covers only the actual boards, not an architectural envelope.
        v['box']=list(v['box']);v['box'][1]-=50;v['box'][3]+=600
    apply(p,d)
    assert p['product_height']['low_mm']==50 and p['product_height']['high_mm']==2450
    assert all(m['origin'][2]==50 and m['size'][2]==2400 for m in p['modules'])


def test_real_sp25_envelope_boxes_follow_measured_2730(tmp_path,monkeypatch):
    # Isolate the original envelope-height path from later partial partitioning.
    monkeypatch.setattr('partial_plan.complete',lambda *_:False)
    d=json.loads((Path(__file__).parent/'fixtures/named_sp25_sections.json').read_text('utf8'))
    p=d['product'];selected=choose_product_plan(p,d['annotations'],multiple=True)
    analyse(p,selected,d['annotations'],tmp_path)
    for child in p['plan_results']:
        assert child['envelope_preview']['height_provisional'] is False
        assert child['modules'][0]['size'][2]==2730
        assert child['modules'][0]['origin'][2]==0
        assert child['height_source']=='product_elevation_bounds' and child['elevation_pending']
    assert p['bounds'][2]==2730 and not p['height_pending']


def test_strict_tier_measurements_still_win(tmp_path):
    p=build(tmp_path)
    assert 'product_height' not in p
    assert p['height_source']=='linked_vertical_section'
    assert [m['size'][2] for m in p['modules']]==[1000,1400,1200,1200]


@pytest.mark.parametrize('strict',[True,False])
def test_final_replay_cannot_reset_combined_heights(tmp_path,monkeypatch,strict):
    from named_plans import replay_named
    import named_plans
    p=build(tmp_path) if strict else pending()[0]
    if not strict:
        _,data=pending();apply(p,data)
    before=deepcopy(p['modules'])
    def forbidden(*_args):raise AssertionError('Plan-only replay after Z measurement')
    monkeypatch.setattr(named_plans,'replay_confirmed',forbidden)
    replay_named(p,tmp_path)
    assert p['modules']==before
