import json
import math
from pathlib import Path

import pytest

from main import run
from geometry import overlapping_modules


def source():
    return json.loads((Path(__file__).parent/'fixtures/deep_end_scan_edges.json').read_text(encoding='utf8'))


def check(p):
    assert p['status']=='ready' and not p.get('envelope_preview'),p.get('error')
    assert len(p['modules'])==2 and len(p['trim_parts'])==2
    assert not overlapping_modules(p['modules']+p['trim_parts'])
    assert sum(m['size'][0]*m['size'][1] for m in p['modules'])==pytest.approx(1455*520,abs=.01)
    assert sum(m['size'][0]*m['size'][1] for m in p['trim_parts'])==pytest.approx(2*18*600,abs=.01)


def test_actual_multiview_scan_retains_deeper_outer_panels_instead_of_whole_envelope(tmp_path):
    p=run(dict(action='geometry',library=str(tmp_path),build_elevation=True,
        geometry=dict(hash='b'*64,plane='XY',lines=source())))['analyses'][0]['products'][0]
    check(p)
    assert [m['size'] for m in p['modules']]==[[970,520,2700],[485,520,2700]]
    assert [m['origin'] for m in p['modules']]==[[18,0,0],[988,0,0]]
    assert [m['origin'] for m in p['trim_parts']]==[[0,0,0],[1473,0,0]]
    assert all(m['size']==[18,600,2700] and m['solid_proxy'] for m in p['trim_parts'])
    assert p['elevation_pending'] and p['scan_capture']['section_markers']==0
    assert p['bounds']==[1491,600,2700] and p['height_source']=='product_elevation_bounds'


@pytest.mark.parametrize('angle',[0,31,90,121])
def test_actual_plan_only_recovers_measured_end_panels_in_each_direction(tmp_path,angle):
    x0,y0=7021.559670061398,249.05575225210592
    rows=[r for r in source() if all(x0-.1<=r[k][0]<=x0+1491.1 and y0-.1<=r[k][1]<=y0+600.1 for k in ('a','b'))]
    c,s=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    for row in rows:
        for k in ('a','b'):
            x,y=row[k][0]-x0,row[k][1]-y0
            row[k]=[10000+c*x-s*y,-2000+s*x+c*y]
    p=run(dict(action='geometry',library=str(tmp_path),geometry=dict(hash='c'*64,plane='XY',plane_offset_mm=73,lines=rows)))['analyses'][0]['products'][0]
    if angle==0:check(p)
    else:
        assert p['status']=='ready' and not p.get('envelope_preview'),p.get('error')
        assert len(p['modules'])==2 and len(p['trim_parts'])==2
        # Rotated AABBs are larger; actual convex footprint area stays measured.
        def area(part):
            pts=[s['start'] for s in part['plan_profile']['segments']]
            return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(pts,pts[1:]+pts[:1]))/2)
        # Panel-local coordinates are rounded to0.001 mm before transformation.
        assert sum(area(m) for m in p['modules'])==pytest.approx(1455*520,abs=2)
        assert sum(area(m) for m in p['trim_parts'])==pytest.approx(2*18*600,abs=2)
    assert p['placement']['plane_offset_mm']==73
