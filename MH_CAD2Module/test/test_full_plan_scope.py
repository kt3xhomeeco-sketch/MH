import json
from pathlib import Path

import pytest

from drawing_scope import choose_product_plan
from named_plans import analyse_named_plans
from test_drawing_scope import rect


def source(code):
    return json.loads((Path(__file__).parent/'fixtures/named_sp08_sp11.json').read_text(encoding='utf8'))[code]


def test_sp08_keeps_both_measured_plans_and_all_bevelled_end_profiles(tmp_path):
    data=source('SP08');p=data['product']
    selected=choose_product_plan(p,data['annotations'],multiple=True)
    assert [v['id'] for v in selected]==['V01.1','V05.1']
    assert [(v['features']['width_mm'],v['features']['height_mm']) for v in selected]==[(970,336.265),(2400,300)]
    analyse_named_plans(p,selected,tmp_path)
    wide=p['plan_results'][1]
    handles={handle for s in wide['plan_reference']['segments'] for handle in s['handles']}
    assert {'/506B0','/506B1','/506B5','/506B6','/506BB'}<=handles
    assert wide['source_plan_envelope'][2]-wide['source_plan_envelope'][0]==2400
    assert wide['bounds']==[2400,300,1600] and wide['envelope_preview']
    # Repeated 2-2 callouts in two SP08 sheets cannot turn the other body's width into a warning.
    assert all('2400' not in w for w in p['plan_results'][0]['warnings'])


def test_sp11_reads_untitled_L_plans_and_preserves_both_branches(tmp_path):
    data=source('SP11');p=data['product']
    selected=choose_product_plan(p,data['annotations'],multiple=True)
    assert [v['id'] for v in selected]==['V01.1','V04.1','V11.1','V12.1']
    assert [(v['features']['width_mm'],v['features']['height_mm']) for v in selected[-2:]]==[(3920,2420),(3065.003,2420)]
    checks=p['view_analysis']['candidates']
    assert sum(bool(c.get('orthogonal_plan')) for c in checks)==2
    assert all(c['role']=='elevation' for c in checks if c['id'] in ('V07.1','V08.1','V09.1','V10.1'))
    assert all(c['role']!='plan' for c in checks if c['id'].startswith(('V07.','V08.','V09.','V10.')))
    upper=next(c for c in checks if c['id']=='V12.1')
    assert upper['product_size_check']['passed'] and upper['product_size_check']['difference_percent']<15
    assert any(c['kind']=='sheet_border' for c in p['view_analysis']['excluded_context'])
    analyse_named_plans(p,selected,tmp_path)
    assert len(p['plan_results'])==4
    for c in p['plan_results'][-2:]:
        assert c['status']=='ready' and not c.get('envelope_preview') and len(c['modules'])==7
        assert c['bounds'][1]==2420
        assert max(s['start'][1] for s in c['plan_reference']['segments'])==2420
    assert p['plan_results'][1]['bounds']==[3965,720,1600]


def L_plan():
    rows=[]
    # Four compartments on OX, three on OY, each with a measured 598 mm depth.
    for i in range(4):
        x=616+i*800
        rows += [rect(x,1822,18,598,f'X{i}L'),rect(x+782,1822,18,598,f'X{i}R'),
                 rect(x+18,1822,764,18,f'X{i}F'),rect(x+18,2402,764,18,f'X{i}B')]
    for i in range(3):
        y=i*600
        rows += [rect(0,y,598,18,f'Y{i}L'),rect(0,y+582,598,18,f'Y{i}R'),
                 rect(0,y+18,18,564,f'Y{i}F'),rect(580,y+18,18,564,f'Y{i}B')]
    return rows


@pytest.mark.parametrize('turn',('normal','mirror_x','mirror_y','rotate'))
def test_untitled_L_detection_does_not_depend_on_corner_direction(turn):
    rows=L_plan()
    for o in rows:
        o['points']=[[-x,y] if turn=='mirror_x' else [x,-y] if turn=='mirror_y' else [y,-x] if turn=='rotate' else [x,y] for x,y in o['points']]
    p=dict(code='SP99',outlines=rows,regions=[[-10000,-10000,10000,10000]])
    selected=choose_product_plan(p,[],multiple=True)
    assert len(selected)==1
    assert selected[0]['features']['orthogonal_plan']['kind']=='L'


def test_print_frame_alone_cannot_become_a_furniture_plan():
    o=rect(0,0,6300,4455,'PRINT','Defpoints');o['block_names']=['VIEN IN']
    p=dict(code='SP99',outlines=[o],regions=[[0,0,6300,4455]])
    assert not choose_product_plan(p,[],multiple=True)


def test_a_titleless_small_rectangle_does_not_inherit_a_nearby_L_identity():
    p=dict(code='SP99',outlines=L_plan()+[rect(6000,0,600,300,'DETAIL')],regions=[[-100,-100,10000,10000]])
    assert len(choose_product_plan(p,[],multiple=True))==1
