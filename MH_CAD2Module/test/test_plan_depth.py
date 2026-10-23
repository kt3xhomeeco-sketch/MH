from copy import deepcopy
import json
from pathlib import Path

import ezdxf
import pytest

from cad_datums import measure
from cad_style import entity_style
from main import read_geometry
from plan_depth import evidence,corroborate
from test_cad_datums import rect
from test_sp25_sections import source
from combined_runtime import analyse
from drawing_scope import choose_product_plan


def test_increasing_y_uses_closed_18_and_6_not_unpaired_or_101_band():
    boards=[rect('front',0,20,1000,18),rect('left',0,38,18,292),rect('right',982,38,18,292),rect('back',18,306,964,6)]
    noise=[rect('wall101',0,330,1000,101,'hach'),dict(handle='oblique',layer='hatch',points=[[0,-90],[1200,500]]),
        dict(handle='first',layer='notes',linetype='DASHED',points=[[0,-50],[1000,-50]])]
    d=evidence(noise+boards)
    assert (d['low_mm'],d['high_mm'])==(20,330)
    assert all('wall101' not in p['handles'] for p in d['panels'])


@pytest.mark.parametrize('change',['layer','linetype','color'])
def test_opposite_faces_of_incompatible_styles_cannot_invent_stock(change):
    rows=[dict(handle='a',layer='wood',points=[[0,0],[1000,0]]),dict(handle='b',layer='wood',points=[[0,18],[1000,18]]),
        dict(handle='c',layer='wood',points=[[0,0],[0,18]]),dict(handle='d',layer='wood',points=[[1000,0],[1000,18]])]
    rows[1][change]='different' if change!='color' else 3
    assert measure(rows,[0,0]) is None


def test_resolved_layer_and_byblock_properties_survive_dxf_read():
    doc=ezdxf.new();doc.linetypes.new('CUSTOM',dxfattribs=dict(pattern=[12,6,-6]))
    doc.layers.new('cabinet',dxfattribs=dict(color=4,linetype='CUSTOM',lineweight=25))
    block=doc.blocks.new('panel')
    block.add_line((0,0),(0,310),dxfattribs=dict(layer='0',color=0,linetype='BYBLOCK',lineweight=-2))
    doc.modelspace().add_blockref('panel',(0,0),dxfattribs=dict(layer='cabinet',color=2,linetype='CONTINUOUS',lineweight=50))
    _,rows,_=read_geometry(doc,1,set(),recover_panels=False)
    assert len(rows)==1
    assert rows[0]['layer']=='cabinet' and rows[0]['color']==2 and rows[0]['linetype']=='CONTINUOUS'
    assert rows[0]['continuous'] and rows[0]['lineweight']==50
    e=doc.modelspace().add_line((0,0),(100,0),dxfattribs=dict(layer='cabinet'))
    assert entity_style(e,'cabinet')['continuous'] is False
    assert entity_style(e,'cabinet')['color']==4


def test_stock_cache_changes_when_style_changes():
    rows=[rect('left',0,0,18,310),rect('right',982,0,18,310),rect('hidden',0,-200,1000,18)]
    assert evidence(rows)['low_mm']==-200
    rows[-1]['continuous']=False
    assert evidence(rows)['low_mm']==0


def test_recognised_bays_are_not_rejected_by_unpaired_raw_context(tmp_path):
    from test_elevation_builder import fixture
    from plan_reader import analyse_plan
    p,_=fixture();rows=[r for r in p['outlines'] if all(y<=800 for x,y in r['points'])]
    rows.append(dict(handle='context',layer='hatch',points=[[0,1000],[1600,1300]]))
    child=dict(code='QA');analyse_plan(child,rows,tmp_path)
    assert child['status']=='ready' and len(child['modules'])==2
    assert all(m['size'][1]==600 for m in child['modules'])
    assert child['source_plan_envelope'][3]==1300 and child['cabinet_plan_envelope'][3]==800


def test_actual_sp25_three_cuts_confirm_310_and_keep_complete_cad(tmp_path,monkeypatch):
    monkeypatch.setattr('partial_plan.complete',lambda *_:False)
    d=source();p=d['product'];selected=choose_product_plan(p,d['annotations'],multiple=True)
    analyse(p,selected,d['annotations'],tmp_path)
    for child in p['plan_results']:
        box=child['modules'][0];proof=child['envelope_preview']['depth_evidence']
        assert box['size'][1:]==[310,2730]
        assert 73<box['origin'][1]<75 and child['elevation_pending']
        assert proof['section_check']['status']=='supported'
        assert [s['view_id'] for s in proof['section_check']['sections']]==['V03.1','V07.1','V08.1']
        assert all(s['depth_mm']==310 for s in proof['section_check']['sections'])
        assert abs(proof['section_check']['plan_depth_mm']-310)<.2
    ref=p['plan_results'][0]['plan_reference']
    assert len(ref['views'])==8 and len(ref['display_copies'])==3
    assert sorted(i for v in ref['views'] for i in v['segment_indices'])==list(range(len(ref['segments'])))


@pytest.mark.parametrize('change',['other_family','conflict','large_gap'])
def test_section_corroboration_is_local_and_cannot_hide_large_errors(tmp_path,change):
    from elevation_builder import context
    from named_plans import analyse_named_plans
    from stages import envelope_preview
    d=source();p=d['product'];selected=choose_product_plan(p,d['annotations'],multiple=True)
    data=context(p,d['annotations']);analyse_named_plans(p,selected,tmp_path);child=p['plan_results'][0]
    before=child['modules'][0]['size'][1]
    if change=='other_family':
        for v in data['views'].values():v['reference_family']='foreign'
    else:
        for v in data['views'].values():
            if v['role']!='section_vertical':continue
            delta=10 if change=='large_gap' else (.7 if v['id']=='V03.1' else 0)
            for row in v['outlines']:
                for point in row['points']:point[0]+=delta*(point[0]-v['box'][0])/310
    corroborate(child,data)
    assert child['modules'][0]['size'][1]==before
    assert child['envelope_preview']['depth_evidence'].get('section_check',{}).get('status')!='supported'
