import json
from pathlib import Path

import pytest

from drawing_scope import choose_product_plan
from elevation_builder import context
from view_relations import build,depth_link,inverse,source_rows
from view_signatures import align
from test_view_signatures import rect


def actual(name):
    d=json.loads((Path(__file__).parent/f'fixtures/named_{name}.json').read_text('utf8'))
    p=d['product'];choose_product_plan(p,d['annotations'],multiple=True)
    return p,d['annotations']


def test_sp24_cut_level_resolves_18mm_phase_and_registers_partial_plans():
    p,notes=actual('sp24_registration');data=context(p,notes);g=data['relations'];q=g['poses']
    assert next(f for f in g['families'] if f['root_id']=='V09.1')['anchor_id']=='V15.1'
    assert align(source_rows(p)['V09.1'],source_rows(p)['V13.1'])['status']!='proven'
    assert q['V13.1']['status']==q['V14.1']['status']=='proven'
    assert q['V13.1']['offset_mm']==pytest.approx(-8863.536333,abs=.001)
    assert q['V14.1']['offset_mm']==pytest.approx(-11853.020833,abs=.001)
    assert q['V14.1']['path'][-1]['target_slice']==pytest.approx(-184964.38+644.911386)
    assert q['V13.1']['path'][0]['source_id']=='V15.1'


def test_sp25_complete_front_rejects_weaker_repeated_pair_match():
    p,notes=actual('sp25_sections');q=context(p,notes)['relations']['poses']
    assert q['V02.1']['status']=='proven' and q['V02.1']['offset_mm']==pytest.approx(0,abs=.001)
    assert align(source_rows(p)['V01.1'],source_rows(p)['V02.1'])['status']!='proven'
    assert q['V02.1']['path'][0]['source_id']=='V06.1'


def test_missing_or_wrong_middle_station_uses_highest_ratio_without_scaling():
    a=[rect(x,0,18,600,str(i)) for i,x in enumerate([0,400,1000])]
    b=[rect(x+5000,2000,18,2400,'b'+str(i)) for i,x in enumerate([0,500,1000])]
    views=dict(P=dict(id='P',role='plan',box=[0,0,1018,600],reference_family='F'),
               F=dict(id='F',role='elevation',title='MẶT ĐỨNG BỎ CÁNH',stock_count=3,box=[5000,2000,6018,4400],reference_family='F'))
    q=build(views,dict(P=a,F=b))['poses']['F']
    assert q['status']=='proven' and q['offset_mm']==-5000
    assert q['path'][0]['coverage']==pytest.approx(2/3,abs=.000001)
    assert q['path'][0]['matched_pairs']==2


def test_depth_chain_compares_y_to_x_at_the_actual_l_arm_and_cut_height():
    plan=[rect(0,-1200,600,18,'return'),rect(0,-1200,18,1800,'left'),
          rect(0,0,2000,18,'front'),rect(0,582,2000,18,'back'),rect(1982,0,18,600,'right')]
    side=[rect(5000,2000,18,2400,'sf'),rect(5582,2000,18,2400,'sb')]
    rows=dict(P=plan,S=side)
    q=depth_link('P','S',rows,1000,3200,False)
    assert q['status']=='proven' and q['offset_mm']==-5000 and q['axis']=='D'
    assert q['target_axis']==1 and q['source_axis']==0
    assert depth_link('P','S',rows,1000,3200,None)['status']=='ambiguous'


def test_inverse_preserves_evidence_and_swaps_slice_axis():
    p,notes=actual('sp24_registration');q=context(p,notes)['relations']['poses']['V14.1']['path'][-1]
    r=inverse(q)
    assert r['offset_mm']==-q['offset_mm'] and r['source_slice']==q['target_slice']
    for c in r['candidates']:
        for m in c['matches']:
            assert m['target'][0]-m['source'][0]==pytest.approx(c['offset_mm'],abs=.15)


def stretch_source():
    plan=[rect(x,200,18,600,'p'+str(i)) for i,x in enumerate([0,400,1000,1700])]
    plan += [rect(0,y,1718,18,'rail'+str(y)) for y in (200,782)]
    front=[rect(x,2000,18,2400,'f'+str(i)) for i,x in enumerate([10000,10400,13800,14500])]
    front += [rect(10000,y,4518,18,'fr'+str(y)) for y in (2000,4382)]
    p=dict(code='QA',outlines=plan+front,regions=[[-100,-100,20000,5000]])
    notes=[dict(kind='view_title',text='MẶT BẰNG',point=[0,0],center_x=859,handle='P'),
           dict(kind='view_title',text='MẶT ĐỨNG BỎ CÁNH',point=[10000,1800],center_x=12259,handle='F')]
    p.update(name='QA stretch',source_hash='e'*64,source_path='QA-stretch.dxf',parser_version='0.2.3')
    return p,notes


def test_one_stretched_middle_gap_overrides_total_size_filter_above_fifty_percent():
    p,notes=stretch_source()
    selected=choose_product_plan(p,notes,multiple=True)
    assert selected
    check=next(v for v in p['view_analysis']['candidates'] if v['role']=='plan')['product_size_check']
    assert check['difference_percent']>50 and check['passed'] and not check['detail_scale']
    assert check['changed_gap']['sequence_coverage']==1
