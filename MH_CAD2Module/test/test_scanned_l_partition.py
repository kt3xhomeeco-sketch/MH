import json
import math
from pathlib import Path

import pytest

from main import run
from geometry import overlapping_modules
from directional_layout import contains,polygon
from test_oy_sweep import rectangle,outlines
from oy_sweep import plates,bays


def source():
    return json.loads((Path(__file__).parent/'fixtures/scanned_l_plan_edges.json').read_text(encoding='utf8'))


@pytest.mark.parametrize('angle',[0,31,90,121])
def test_actual_direct_L_scan_recovers_both_arms_and_preserves_empty_gaps(tmp_path,angle):
    lines=source();base=[min(row[k][i] for row in lines for k in ('a','b')) for i in (0,1)]
    c,s=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    for row in lines:
        for k in ('a','b'):
            x,y=[row[k][i]-base[i] for i in (0,1)]
            row[k]=[10000+c*x-s*y,20000+s*x+c*y]
    p=run(dict(action='geometry',library=str(tmp_path),geometry=dict(hash='e'*64,lines=lines,plane='XY',plane_offset_mm=73)))['analyses'][0]['products'][0]
    assert p['status']=='ready' and not p.get('envelope_preview'),p.get('error')
    assert len(p['modules'])==7 and len(p['trim_parts'])==4
    assert not overlapping_modules(p['modules']+p['trim_parts'])
    def world_inside(x,y,parts):
        point=[10000+c*x-s*y,20000+s*x+c*y]
        point=[point[i]-p['source_plan_envelope'][i] for i in (0,1)]
        return any(contains(point,polygon(part)) for part in parts)
    for x,y in ((300,250),(300,900),(300,1600),(800,2200),(2000,2200),(2750,2200),(3500,2200)):
        assert world_inside(x,y,p['modules'])
    assert not world_inside(1500,1000,p['modules']+p['trim_parts'])
    assert not world_inside(1200,2200,p['modules']+p['trim_parts'])
    assert world_inside(1200,1830,p['trim_parts']) # Only the actual18 mm rail crosses this opening.
    assert p['placement']['plane_offset_mm']==73
    if angle==0:
        assert [m['size'][:2] for m in p['modules']]==[[598,490],[598,800],[598,1050],[350,598],[900,598],[600,598],[836,598]]
        assert len([t for t in p['trim_parts'] if t.get('original_depth_mm')==50])==2
        assert sum(t['size'][0]*t['size'][1] for t in p['trim_parts'])==43092


def test_shared_front_rail_cannot_close_an_empty_gap_between_cabinets():
    boxes=[[0,0,18,600],[800,0,818,600],[1118,0,1136,600],[1918,0,1936,600],
           [0,0,1936,18],[18,576,800,582],[1136,576,1918,582]]
    rows=outlines([l for i,b in enumerate(boxes) for l in rectangle(b,str(i))])
    candidates,_=bays(plates(rows)[0],rows)
    assert [b['box'] for b in candidates]==[[0,0,818,600],[1118,0,1936,600]]
