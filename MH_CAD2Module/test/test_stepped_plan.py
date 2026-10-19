"""Regression for the 35-edge unequal-depth scan that produced no modules."""
from copy import deepcopy
import json
from pathlib import Path

import pytest

from main import run
from plan_learning import features
from plan_search import physical_check, proposals
from test_plan_search import source
from test_local_ai import FakeRuntime


def packet(root):
    lines=json.loads((Path(__file__).parent/'fixtures/stepped_plan_edges.json').read_text())
    return dict(action='geometry',library=str(root),geometry=dict(hash='a'*64,lines=lines,plane='XY',plane_offset_mm=73))


def product(request):
    return run(request)['analyses'][0]['products'][0]


def state(p):
    return {k:deepcopy(p[k]) for k in ('modules','trim_parts','panel_parts','bounds')}


def test_35_edge_scan_keeps_stepped_rear_and_two_solid_trims(tmp_path):
    p=product(packet(tmp_path))
    assert p['status']=='ready',p.get('error')
    assert [m['size'] for m in p['modules']]==[[1004,500,1600]]
    m=p['modules'][0]
    assert m['origin']==[18,0,0] and m['rule']=='plan-stepped-rear-v1'
    assert len(m['plan_profile']['segments'])==8
    assert [215,367] in [s['start'] for s in m['plan_profile']['segments']]
    assert [p['size'] for p in p['trim_parts']]==[[18,500,1600]]*2
    assert all(t['solid_proxy'] for t in p['trim_parts'])
    assert len(p['outlines'])==35 and p['bounds']==[1040,500,1600]
    assert p['placement']['origin_mm']==[0,0] and p['placement']['plane_offset_mm']==73
    assert physical_check(p,state(p),[0,0],features(p))['passed']


@pytest.mark.parametrize('mirror',[False,True])
def test_stepped_rear_is_measured_after_translation_and_mirror(tmp_path,mirror):
    request=packet(tmp_path)
    for line in request['geometry']['lines']:
        for k in ('a','b'):
            x,y=line[k];line[k]=[100000+(1040-x if mirror else x),-5000+y]
    p=product(request)
    assert p['status']=='ready',p.get('error')
    assert p['placement']['origin_mm']==[100000,-5000]
    assert p['modules'][0]['size']==[1004,500,1600]
    assert physical_check(p,state(p),[0,0],features(p))['passed']


def test_rectangle_cannot_replace_measured_recess_even_with_matching_size(tmp_path):
    p=product(packet(tmp_path));bad=state(p)
    bad['modules'][0].pop('plan_profile')
    with pytest.raises(ValueError,match='giật cấp'):physical_check(p,bad,[0,0],features(p))
    choices,_=proposals(p,features(p),[])
    assert [c['id'] for c in choices]==['baseline']


def test_incomplete_rear_preserves_source_and_does_not_invent_ready_module(tmp_path):
    request=packet(tmp_path)
    request['geometry']['lines']=[l for l in request['geometry']['lines'] if l['handle']!='e23']
    p=product(request)
    assert p['status']=='needs_review'
    assert p['outlines'] and p['envelope_preview'] and len(p['modules'])==1
    assert p['views'][0]['unresolved_bays']
    assert features(p)['refs']


def test_unidentified_scan_retains_edges_for_diagnostics(tmp_path):
    request=packet(tmp_path)
    request['geometry']['lines']=request['geometry']['lines'][:4]
    p=product(request)
    assert p['status']=='needs_review' and len(p['outlines'])==4


def test_ai_can_search_and_decide_on_original_failed_shape(tmp_path,monkeypatch):
    import local_ai
    source(tmp_path)
    runtime=FakeRuntime(dict(decision='choose',candidate_id='baseline',reason='Keep measured stepped rear.'))
    monkeypatch.setattr(local_ai,'Runtime',lambda *_:runtime)
    request=packet(tmp_path);request['ai_enabled']=True
    p=product(request)
    assert p['status']=='ready',p.get('local_ai')
    assert runtime.find_calls==runtime.calls==1
    assert p['local_ai']['status']=='choose' and p['local_ai']['final_check']['passed']
    assert p['modules'][0]['plan_profile']


def test_unresolved_direct_plan_reaches_ai_search_instead_of_precondition_failure(tmp_path,monkeypatch):
    import local_ai
    source(tmp_path)
    runtime=FakeRuntime(error=ValueError('Search reached'))
    monkeypatch.setattr(local_ai,'Runtime',lambda *_:runtime)
    request=packet(tmp_path);request['ai_enabled']=True
    request['geometry']['lines']=[l for l in request['geometry']['lines'] if l['handle']!='e23']
    p=product(request)
    assert runtime.find_calls==1 and 'Search reached' in p['local_ai']['message']
    assert p['status']=='needs_review' and p['envelope_preview']
