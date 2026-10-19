from copy import deepcopy
import math
import random

import pytest

from materials import BOARD_MM
from plan_evidence import measure_plan
from plan_profiles import arc_runs, profile_from_points, valid_profile, arc_bounds
from test_plan_profiles import request
from main import run


def outlines(points):
    return [dict(handle=f'e{i}',points=[a,b],layer='0') for i,(a,b) in enumerate(zip(points,points[1:]))]


def plate(stock,angle=0):
    points=[[0,0],[500,0],[500,stock],[0,stock],[0,0]]
    radians=math.radians(angle)
    return outlines([[p[0]*math.cos(radians)-p[1]*math.sin(radians)+30000,
                      p[0]*math.sin(radians)+p[1]*math.cos(radians)+40000] for p in points])


def curved_plate(stock):
    # No vertex at angle zero: its two neighbouring chords form an axial segment.
    angles=[math.radians(-90+i*20) for i in range(10)]
    outer=[[math.cos(t)*(100+stock),math.sin(t)*(100+stock)] for t in angles]
    inner=[[math.cos(t)*100,math.sin(t)*100] for t in reversed(angles)]
    points=outer+inner+[outer[0]]
    return outlines(points),points[:-1]


@pytest.mark.parametrize('stock',[3,6,9,12,15,18,25,36])
@pytest.mark.parametrize('angle',[0,31])
def test_stock_is_perpendicular_distance_with_closed_ends(stock,angle):
    data=measure_plan(plate(stock,angle))
    assert len(data['panels'])==1
    p=data['panels'][0]
    assert p['kind']=='straight' and p['stock_mm']==stock
    assert p['measured_mm']==pytest.approx(stock,abs=.001)
    assert p['length_mm']==pytest.approx(500,abs=.001)
    assert p['lamination_candidate']==([18,18] if stock==36 else None)


def test_distance_is_not_forced_to_stock_and_unclosed_gaps_are_not_panels():
    assert measure_plan(plate(17.94))['panels'][0]['measured_mm']==17.94
    assert measure_plan(plate(17.94))['panels'][0]['stock_mm']==18
    assert not measure_plan(plate(24))['panels']
    p=plate(18)
    assert not measure_plan([p[0],p[2]])['panels']
    assert 8 in BOARD_MM  # Preserve previously supported material.


def test_36_envelope_preserves_explicit_18_joint():
    p=outlines([[0,0],[500,0],[500,36],[0,36],[0,0]])
    p.append(dict(handle='joint',points=[[0,18],[500,18]]))
    panels=measure_plan(p)['panels']
    assert len([a for a in panels if a['stock_mm']==18])==2
    assert next(a for a in panels if a['stock_mm']==36)['internal_seams_mm']==[18]
    single=measure_plan(p[:-1])['panels']
    assert len(single)==1 and single[0]['stock_mm']==36 and single[0]['internal_seams_mm']==[]


@pytest.mark.parametrize('stock',[3,6,9,12,15,18,25,36])
def test_unwelded_concentric_arc_boards_include_axial_chord_and_true_extremum(stock):
    edges,points=curved_plate(stock)
    random.Random(9).shuffle(edges)
    for edge in edges[::2]:edge['points'].reverse()
    data=measure_plan(edges)
    assert len(data['arcs'])==2
    assert len(data['panels'])==1
    p=data['panels'][0]
    assert p['kind']=='arc' and p['stock_mm']==stock
    assert p['measured_mm']==pytest.approx(stock,abs=.001)
    assert data['envelope'][2]==pytest.approx(100+stock,abs=.001)
    assert max(p[0] for p in points)<data['envelope'][2]-.5
    origin=[0,-100-stock]
    profile=profile_from_points([[p[i]-origin[i] for i in (0,1)] for p in points])
    assert sum(s['type']=='arc' for s in profile['segments'])==2
    assert valid_profile(profile,[100+stock,2*(100+stock),1600])
    translated=deepcopy(edges)
    for edge in translated:edge['points']=[[p[0]+100000,p[1]-3000] for p in edge['points']]
    assert measure_plan(translated)['panels'][0]['measured_mm']==pytest.approx(stock,abs=.001)


def test_missing_arc_panel_end_or_ellipse_does_not_invent_wood_or_circle():
    edges,_=curved_plate(18)
    assert not measure_plan(edges[:-1])['panels']
    ellipse=deepcopy(edges)
    for edge in ellipse:edge['points']=[[p[0]*2,p[1]] for p in edge['points']]
    assert not arc_runs(ellipse)


def test_evidence_is_attached_to_plan_without_changing_known_module_layout(tmp_path):
    p=run(request(tmp_path))['analyses'][0]['products'][0]
    assert p['status']=='ready'
    assert p['plan_evidence']['arcs']
    assert p['plan_evidence']['stock_counts']['18']>0
    assert 3 in p['material_standards_mm'] and 9 in p['material_standards_mm']
    assert [m['size'][:2] for m in p['modules']]==[[1362,350],[1360,350],[120,350]]
