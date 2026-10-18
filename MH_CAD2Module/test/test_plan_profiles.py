import json
import math
from copy import deepcopy
from pathlib import Path

import pytest
from main import run
from library import atomic_json, VERSION
from learning import valid_state
from plan_profiles import profile_from_points, valid_profile


def request(tmp_path):
    lines=json.loads((Path(__file__).parent/'fixtures/sp41_plan_edges.json').read_text())
    return dict(action='geometry',library=str(tmp_path),geometry=dict(hash='d'*64,lines=lines,plane='XY'))


def test_sp41_full_curved_end_uses_arc_and_complete_measured_bounds(tmp_path):
    packet=request(tmp_path)
    p=run(packet)['analyses'][0]['products'][0]
    assert p['status']=='ready',p.get('error')
    assert p['bounds']==[2860,350,1600]
    assert [m['size'] for m in p['modules']]==[[1362,350,1600],[1360,350,1600],[120,350,1600]]
    assert len(p['trim_parts'])==1
    end=p['modules'][-1]
    assert end['origin']==[2740,0,0]
    assert valid_profile(end['plan_profile'],end['size'])
    arc=next(s for s in end['plan_profile']['segments'] if s['type']=='arc')
    assert arc['radius']==pytest.approx(100,abs=.001)
    assert abs(arc['sweep'])==pytest.approx(math.pi/2,abs=.001)
    assert p['source_plan_envelope']==[0,0,2860,350]
    translated=deepcopy(packet)
    for l in translated['geometry']['lines']:
        for k in ('a','b'):l[k]=[l[k][0]+10000,l[k][1]-5000]
    q=run(translated)['analyses'][0]['products'][0]
    assert q['signature']==p['signature']
    other=next(s for s in q['modules'][-1]['plan_profile']['segments'] if s['type']=='arc')
    assert other['radius']==pytest.approx(arc['radius'],abs=.001)
    assert other['center']==pytest.approx(arc['center'],abs=.001)
    assert q['modules'][-1]['origin']==end['origin']


def test_exact_plan_experience_replays_curves_instead_of_boxes(tmp_path):
    packet=request(tmp_path)
    p=run(packet)['analyses'][0]['products'][0]
    state={k:deepcopy(p[k]) for k in ('modules','trim_parts','panel_parts','bounds')}
    state['modules'][1]['size'][0]=1362
    end=state['modules'][-1]
    end['origin'][0]+=2;end['size'][0]-=2
    for s in end['plan_profile']['segments']:
        for k in ('start','end','center'):
            if k in s:s[k]=[max(0,s[k][0]-2),s[k][1]]
    event=dict(id='arc-example',status='accepted',signature=p['signature'],parser_version=VERSION,
               input_axes_ignored=True,analysis=deepcopy(p),after=state)
    assert valid_state(state)
    atomic_json(tmp_path/'experiences'/p['signature']/'arc.json',event)
    rebuilt=run(packet)['analyses'][0]['products'][0]
    assert rebuilt['learning']['mode']=='plan_exact'
    assert rebuilt['modules'][-1]['plan_profile']==end['plan_profile']
    assert rebuilt['modules'][-1]['size']==[118,350,1600]
    bad=deepcopy(state);bad['modules'][-1]['plan_profile']['segments'][3]['radius']=10
    assert not valid_state(bad)


def test_noncircular_and_incomplete_curved_end_are_not_fabricated(tmp_path):
    with pytest.raises(ValueError):profile_from_points([[0,0],[100,0],[101,20],[106,40],[125,50],[125,100],[0,100]])
    packet=request(tmp_path)
    # Remove one edge in the outer arc, leaving an incomplete end outline.
    packet['geometry']['lines'].pop(90)
    p=run(packet)['analyses'][0]['products'][0]
    assert p['status']=='needs_review'
    assert 'bo' in p['error'] or 'cong' in p['error']


def test_dxf_arc_and_bulge_outlines_keep_exact_circle_coordinates():
    import ezdxf
    from main import outline_points
    doc=ezdxf.new()
    arc=doc.modelspace().add_arc((2000,3000),1000,270,360)
    points=outline_points(arc,1)
    fitted=__import__('plan_profiles').fit_arc(points)
    assert fitted['radius']==pytest.approx(1000,abs=.01)
    assert fitted['center']==pytest.approx([2000,3000],abs=.01)
    poly=doc.modelspace().add_lwpolyline([(0,100,math.tan(math.pi/8)),(100,0,0),(100,200,0),(0,200,0)],format='xyb',close=True)
    pts=outline_points(poly,1)
    if pts[0]==pts[-1]:pts.pop()
    profile=profile_from_points(pts)
    assert next(s for s in profile['segments'] if s['type']=='arc')['radius']==pytest.approx(100,abs=.01)


def test_corrupt_profile_metadata_is_rejected_without_exception():
    assert not valid_profile({'schema':1,'segments':[3,4,5]},[100,100,1600])
    assert not valid_profile({'schema':1,'segments':[{'type':'line','start':[0,0],'end':[1,1]}]*3},[100,100,1600])
