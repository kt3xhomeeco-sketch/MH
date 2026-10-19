"""Real failed scans: trim is aligned to carcass, 18mm behind the closed doors."""
from copy import deepcopy
import json
from pathlib import Path

import pytest

from main import run
from plan_learning import features
from plan_search import physical_check
from test_local_ai import FakeRuntime
from test_plan_search import source


@pytest.mark.parametrize('fixture,depth', [('recessed_trim_plan_edges.json',598),('recessed_trim_shallow_edges.json',370)])
@pytest.mark.parametrize('mirror',[False,True])
def test_real_recessed_trim_covers_front_return_without_blocking_modules(tmp_path,fixture,depth,mirror):
    lines=json.loads((Path(__file__).parent/'fixtures'/fixture).read_text())
    for line in lines:
        for key in ('a','b'):
            x,y=line[key];line[key]=[30000+(1985-x if mirror else x),40000+y]
    p=run(dict(action='geometry',library=str(tmp_path),geometry=dict(hash='a'*64,lines=lines,plane='XY',plane_offset_mm=73)))['analyses'][0]['products'][0]
    assert p['status']=='ready',p.get('error')
    assert [m['size'] for m in p['modules']]==[[w,depth,1600] for w in ([700,385,800] if mirror else [800,385,700])]
    trims=sorted(p['trim_parts'],key=lambda t:t['origin'][0])
    assert [t['size'] for t in trims]==[[50,depth,1600]]*2
    assert [t['origin'] for t in trims]==[[0,0,0],[1935,0,0]]
    assert all(t['original_depth_mm']==50 and t['stock_thickness_mm']==18 and t['solid_proxy'] and t['front_return_box'] for t in trims)
    assert p['bounds']==[1985,depth,1600] and p['placement']['origin_mm']==[30000,40000]
    assert p['placement']['plane_offset_mm']==73
    state={k:deepcopy(p[k]) for k in ('modules','trim_parts','panel_parts','bounds')}
    assert physical_check(p,state,[0,0],features(p))['passed']


def test_ai_search_evaluation_and_final_choice_accept_recessed_trim_source(tmp_path,monkeypatch):
    import local_ai
    source(tmp_path)
    ai=FakeRuntime(dict(decision='choose',candidate_id='baseline',reason='Measured three bays and full-depth returns.'))
    monkeypatch.setattr(local_ai,'Runtime',lambda *_:ai)
    lines=json.loads((Path(__file__).parent/'fixtures/recessed_trim_plan_edges.json').read_text())
    p=run(dict(action='geometry',library=str(tmp_path),ai_enabled=True,geometry=dict(hash='b'*64,lines=lines)))['analyses'][0]['products'][0]
    assert p['status']=='ready',p.get('local_ai')
    assert ai.calls==ai.find_calls==1
    assert p['local_ai']['status']=='choose' and p['local_ai']['final_check']['passed']
    assert len(p['modules'])==3 and len(p['trim_parts'])==2
