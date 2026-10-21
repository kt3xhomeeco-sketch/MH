import json
from pathlib import Path

import pytest

from cad_views import project
from combined_runtime import analyse
from drawing_scope import choose_product_plan


def source():
    return json.loads((Path(__file__).parent/'fixtures/named_sp24_registration.json').read_text('utf8'))


def test_actual_repeated_section_codes_link_to_their_own_front_family():
    d=source();p=d['product'];selected=choose_product_plan(p,d['annotations'],multiple=True)
    assert len(selected)==6
    summaries={v['id']:v for v in p['view_analysis']['candidates']}
    assert summaries['V03.1']['role']=='elevation' and summaries['V03.1']['title']=='MẶT ĐỨNG'
    assert summaries['V03.2']['section_links'][0]['marker_handle']=='/2838F'
    assert summaries['V11.1']['section_links'][0]['marker_handle']=='/2841B'
    assert {c['front_id'] for c in summaries['V05.1']['section_links']}=={'V03.1'}
    assert {c['front_id'] for c in summaries['V14.1']['section_links']}=={'V10.1'}
    assert [v['features']['box'][0] for v in selected]==sorted(v['features']['box'][0] for v in selected)


def test_actual_sp24_full_references_have_measured_heights_cut_positions_and_directions(tmp_path):
    d=source();p=d['product'];selected=choose_product_plan(p,d['annotations'],multiple=True)
    analyse(p,selected,d['annotations'],tmp_path);children=p['plan_results'];ref=children[0]['plan_reference']
    v={v['id']:v for v in ref['views']}
    assert len(children)==6 and all(c['plan_reference'].get('shared') for c in children[1:])
    assert v['V03.1']['plane']=='XZ' and v['V07.1']['role']=='front_open' and v['V15.1']['role']=='front_open'
    assert v['V10.2']['plane']=='XZ' and v['V10.2']['parent_view_id']=='V10.1'
    returned={i for i in v['V05.1']['segment_indices'] if any(h in ('/28FB0','/28FB1') for h in ref['segments'][i]['handles'])}
    assert returned # Full polylines crossing the caption-row border stay with C-C.
    assert v['V01.1']['z_mm']==pytest.approx(2354.626664)
    assert v['V06.1']['z_mm']==pytest.approx(1892.537381)
    assert v['V09.1']['z_mm']==pytest.approx(2484.626664)
    assert v['V13.1']['z_mm']==pytest.approx(1198.56627)
    sides=[v[i] for i in ['V03.2','V04.1','V08.1','V11.1','V12.1','V16.1']]
    assert v['V16.1']['depth_alignment']['basis']=='cabinet_min_y' and 'tạm căn' in v['V16.1']['registration_issue']
    assert [s['display_x_mm'] for s in sides]==sorted(s['display_x_mm'] for s in sides)
    for side in sides:
        proof=side['section_position'];front=v[proof['front_id']]
        assert side['plane']=='YZ' and side['reversed_depth'] and side['direction_basis']=='symbol_arrows'
        assert len(side['arrow_heads'])==2 and side['view_direction']==[1,0]
        measured=proof['cut_line'][0][0]-proof['source_origin_mm'][0]+front['x_offset_mm']
        assert side['display_x_mm']==pytest.approx(measured,abs=.01)
    a,b,c=[v[i] for i in ('V09.1','V13.1','V14.1')]
    pa,pb,pc=[project(x['box_mm'][:2],x,ref['plan_bounds_mm']) for x in (a,b,c)]
    assert pb[0]-pa[0]==pytest.approx(25,abs=.01)
    assert pc[0]==pytest.approx(pb[0],abs=.01)
    back=[project(x['box_mm'][2:],x,ref['plan_bounds_mm'])[1] for x in (a,b,c)]
    assert back==pytest.approx([back[0]]*3)
    # The two source cabinet families remain separate instead of stacking their repeated codes.
    assert pa[0]>v['V01.1']['box_mm'][2]+999
    assert sorted(i for e in ref['views'] for i in e['segment_indices'])==list(range(len(ref['segments'])))
