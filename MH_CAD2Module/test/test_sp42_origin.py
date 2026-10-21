import json
from copy import deepcopy
from pathlib import Path

import pytest
from main import run
from library import atomic_json, VERSION


def packet(tmp_path):
    lines=json.loads((Path(__file__).parent/'fixtures/sp42_plan_edges.json').read_text())
    return dict(action='geometry',library=str(tmp_path),geometry=dict(hash='e'*64,lines=lines,plane='XY',plane_offset_mm=0))


def test_sp42_learned_full_layout_uses_complete_cad_origin_not_last_bay(tmp_path):
    request=packet(tmp_path)
    baseline=run(request)['analyses'][0]['products'][0]
    assert baseline['envelope']==pytest.approx([2178,0,2860,230])
    assert baseline['source_plan_envelope']==pytest.approx([0,0,2860,230])
    state=json.loads((Path(__file__).parent/'fixtures/sp42_accepted_layout.json').read_text())
    event=dict(id='sp42-accepted',status='accepted',signature=baseline['signature'],parser_version=VERSION,
               input_axes_ignored=True,analysis=baseline,after=state,plan_origin_offset_mm=[0,0])
    atomic_json(tmp_path/'experiences'/baseline['signature']/'accepted.json',event)
    rebuilt=run(request)['analyses'][0]['products'][0]
    assert rebuilt['learning']['mode']=='plan_exact'
    assert rebuilt['placement']['origin_mm']==pytest.approx([0,0])
    assert rebuilt['bounds']==[2860,230,1600]
    assert rebuilt['modules'][0]['source_box'][:2]==pytest.approx([2010,0])
    assert rebuilt['trim_parts'][0]['source_box'][:2]==pytest.approx([0,194])
    assert rebuilt['plan_origin_basis']=='source_plan_envelope'
    changed=deepcopy(request)
    changed['geometry'].update(plane='XZ',plane_offset_mm=52)
    for i,l in enumerate(changed['geometry']['lines']):
        l['handle']=str(i+1000)
        for k in ('a','b'):l[k]=[l[k][0]+9000,l[k][1]-1300]
    moved=run(changed)['analyses'][0]['products'][0]
    assert moved['signature']==rebuilt['signature']
    assert moved['placement']['origin_mm']==pytest.approx([9000,-1300])
    assert moved['placement']['plane_offset_mm']==52
    assert moved['modules'][0]['source_box'][:2]==pytest.approx([11010,-1300])
