import json
from pathlib import Path

import pytest

from combined_runtime import analyse
from drawing_scope import choose_product_plan
from cad_views import project


def source():
    return json.loads((Path(__file__).parent/'fixtures/named_sp25_sections.json').read_text('utf8'))


def test_actual_sp25_second_and_third_cuts_find_markers_on_complete_front(tmp_path):
    d=source();p=d['product'];selected=choose_product_plan(p,d['annotations'],multiple=True)
    assert [v['id'] for v in selected]==['V01.1','V04.1','V05.1']
    summaries={v['id']:v for v in p['view_analysis']['candidates']}
    for id,marker in [('V07.1','/288FA'),('V08.1','/288C2')]:
        s=summaries[id]
        assert s['role']=='section_vertical' and s['reference_front_id']=='V06.1'
        assert s['reference_family']==summaries['V02.1']['reference_family']
        assert summaries['V06.1']['family_geometry_link']['status']=='proven'
        assert s['section_links'][0]['front_id']=='V02.1'
        assert s['section_links'][0]['marker_handle']==marker
        assert s['section_links'][0]['dimension_check']['passed']
    analyse(p,selected,d['annotations'],tmp_path)
    ref=p['plan_results'][0]['plan_reference'];views={v['id']:v for v in ref['views']}
    for id in ('V03.1','V07.1','V08.1'):
        v=views[id]
        assert v['plane']=='YZ' and v['direction_basis']=='symbol_arrows'
        proof=v['section_position'];front=views[proof['front_id']]
        assert proof['front_id']=='V02.1'
        assert v['display_x_mm']==pytest.approx(proof['cut_line'][0][0]-ref['source_origin_mm'][0]+front['x_offset_mm'],abs=.001)
    assert views['V06.1']['plane']=='XZ' and views['V06.1']['role']=='front_open'
    copies=ref['display_copies']
    assert [v['source_view_id'] for v in copies]==['V03.1','V07.1','V08.1']
    assert ref['display_mode']=='front_overlay'
    assert project(views['V06.1']['box_mm'][:2],views['V06.1'],ref['plan_bounds_mm'])==pytest.approx(project(views['V02.1']['box_mm'][:2],views['V02.1'],ref['plan_bounds_mm']),abs=.001)
    link=views['V02.1']['axis_registration']['W']['path'][-1]
    assert link['height_support']==3
    assert all(860<c['height_mm']<1460 for c in link['height_checks'])
    previous=max((views[i] for i in ('V02.1','V06.1')),key=lambda v:project(v['box_mm'][2:],v,ref['plan_bounds_mm'])[0])
    for v in copies:
        left=project(v['box_mm'][:2],v,ref['plan_bounds_mm'])
        right=project(previous['box_mm'][2:],previous,ref['plan_bounds_mm'])
        assert left[0]-right[0]==pytest.approx(500) and left[1]==right[1]==0
        previous=v
    assert sorted(i for v in ref['views'] for i in v['segment_indices'])==list(range(len(ref['segments'])))


def test_duplicate_external_marker_cannot_force_a_flat_view_to_stand():
    d=source();marker=next(m for m in d['annotations'] if m['handle']=='/288FA')
    d['annotations'].append(dict(marker,handle='ambiguous2'))
    choose_product_plan(d['product'],d['annotations'],multiple=True)
    s=next(v for v in d['product']['view_analysis']['candidates'] if v['id']=='V07.1')
    assert s['role']=='unknown' and not s['section_links'] and s['reference_family']=='V02.1'


def test_same_cut_name_with_wrong_geometry_cannot_borrow_a_marker():
    d=source();p=d['product']
    # Actual2-2 lies entirely in this source range. Change its geometric height.
    for row in p['outlines']:
        if all(414600<x<415200 for x,y in row['points']):
            row['points']=[[x,-184964.38+(y+184964.38)*1.30] for x,y in row['points']]
    for region in p['regions']:
        if region[0]<414900<region[2]:region[3]+=1200 # Keep the changed top inside the source sheet.
    choose_product_plan(p,d['annotations'],multiple=True)
    s=next(v for v in p['view_analysis']['candidates'] if v['id']=='V07.1')
    assert s['role']!='section_vertical' and not s['section_links']
