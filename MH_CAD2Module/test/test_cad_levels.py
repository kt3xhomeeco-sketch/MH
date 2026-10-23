from copy import deepcopy
import json
from pathlib import Path

import pytest

from cad_views import project
from combined_runtime import analyse
from drawing_scope import choose_product_plan
from named_plans import replay_named
from test_elevation_builder import fixture


def level_source():
    p,notes=fixture();plan=[o for o in p['outlines'] if max(q[1] for q in o['points'])<=800]
    p['outlines'] += [dict(o,handle='extra-'+o['handle'],points=[[x,y+5000] for x,y in o['points']]) for o in plan]
    b=p['regions'][0];p['regions'].append([b[0],b[1]+5000,b[2],b[3]+5000])
    notes.append(dict(kind='view_title',text='MẶT CẮT 4-4',handle='P4',point=[0,5100],center_x=809))
    notes.append(dict(kind='section_marker',handle='H4',axis='horizontal',numbers=['4'],point=[4800,2700],cut_line=[[4000,2700],[5618,2700]]))
    return p,notes


def build(tmp_path,p=None,notes=None):
    if p is None:p,notes=level_source()
    selected=choose_product_plan(p,notes,multiple=True);assert len(selected)==2
    analyse(p,selected,notes,tmp_path)
    return p


def test_two_horizontal_sections_stack_same_xy_at_actual_cut_heights(tmp_path):
    p=build(tmp_path);children=p['plan_results'];ref=children[0]['plan_reference']
    plans=[v for v in ref['views'] if v.get('role')=='plan' and v.get('level',{}).get('status')=='measured']
    assert len(plans)==2 and sorted(v['z_mm'] for v in plans)==[700,1700]
    boxes=[]
    for view in plans:
        boxes.append([project(view['box_mm'][:2],view,ref['plan_bounds_mm']),project(view['box_mm'][2:],view,ref['plan_bounds_mm'])])
    assert boxes[0][0][:2]==pytest.approx(boxes[1][0][:2]) and boxes[0][1][:2]==pytest.approx(boxes[1][1][:2])
    assert children[1]['plan_reference']['shared'] and children[1]['plan_reference']['z_mm']==1700
    assert children[1]['plan_reference']['xy_offset_mm']==[-2618,0]
    # Only the CAD references stack; existing module row transforms are preserved.
    assert children[1]['display_layout']['offset_mm']==[2618,0]
    before=deepcopy(children[1]['plan_reference']);replay_named(p,tmp_path)
    assert p['plan_results'][1]['plan_reference']==before


def test_reference_heights_work_when_vertical_module_inference_fails(tmp_path):
    p,notes=level_source();notes=[n for n in notes if n['handle'] not in ('C1','C2')]
    p=build(tmp_path,p,notes)
    assert all(c['elevation_pending'] for c in p['plan_results'])
    assert [c['plan_reference']['z_mm'] for c in p['plan_results']]==[700,1700]


@pytest.mark.parametrize('bad',['missing','oblique','outside','conflicting'])
def test_bad_horizontal_cut_uses_explicit_inspection_spacing_without_inventing_measurement(tmp_path,bad):
    p,notes=level_source();cut=next(n for n in notes if n['handle']=='H3')
    if bad=='missing':notes.remove(cut)
    if bad=='oblique':cut['cut_line'][1][1]+=10
    if bad=='outside':cut['cut_line']=[[4000,5000],[5618,5000]]
    if bad=='conflicting':notes.append(dict(kind='section_marker',handle='H3b',axis='horizontal',numbers=['3'],point=[16500,1900],cut_line=[[16000,1900],[17618,1900]]))
    p=build(tmp_path,p,notes);level=p['plan_results'][0]['plan_reference']['level']
    assert level['status']=='provisional' and p['plan_results'][0]['plan_reference']['z_mm']==2700
    assert level['issue'] and level['basis']=='inspection_spacing'
    assert p['plan_results'][1]['plan_reference']['z_mm']==1700


def test_zero_level_is_measured_and_source_translation_does_not_change_heights(tmp_path):
    p,notes=level_source();cut=next(n for n in notes if n['handle']=='H3')
    cut['cut_line']=[[4000,1000],[5618,1000]];cut['point']=[4800,1000]
    for o in p['outlines']:o['points']=[[x+10000,y-50000] for x,y in o['points']]
    p['regions']=[[b[0]+10000,b[1]-50000,b[2]+10000,b[3]-50000] for b in p['regions']]
    for n in notes:
        n['point']=[n['point'][0]+10000,n['point'][1]-50000]
        if 'center_x' in n:n['center_x']+=10000
        if 'cut_line' in n:n['cut_line']=[[x+10000,y-50000] for x,y in n['cut_line']]
    p=build(tmp_path,p,notes)
    assert [c['plan_reference']['z_mm'] for c in p['plan_results']]==[0,1700]
    assert all(c['plan_reference']['level']['status']=='measured' for c in p['plan_results'])


def test_actual_sp20_missing_cut_markers_stacks_once_at_provisional_zero_and_1000(tmp_path):
    data=json.loads((Path(__file__).parent/'fixtures/named_sp20_levels.json').read_text('utf8'))
    p=build(tmp_path,data['product'],data['annotations']);children=p['plan_results'];ref=children[0]['plan_reference']
    assert [c['plan_title'] for c in children]==['MẶT CẮT A-A','MẶT CẮT B-B']
    assert [c['plan_reference']['z_mm'] for c in children]==[0,1000]
    assert all(c['elevation_pending'] for c in children)
    assert all(c['plan_reference']['level']['status']=='provisional' for c in children)
    assert all(c['plan_reference']['level']['issue'] for c in children)
    assert children[1]['plan_reference']['shared']
    plans=[v for v in ref['views'] if v.get('role')=='plan']
    assert len(plans)==2 and len(ref['views'])==7
    assert sorted(i for v in ref['views'] for i in v['segment_indices'])==list(range(len(ref['segments'])))
    for corner in (slice(0,2),slice(2,4)):
        points=[project(v['box_mm'][corner],v,ref['plan_bounds_mm']) for v in plans]
        assert points[0][:2]==pytest.approx(points[1][:2])
        assert points[1][2]-points[0][2]==1000
    # Module solids still have provisional heights and retain their inspection row.
    assert children[0]['envelope_preview'] and children[1]['display_layout']['offset_mm'][0]>0


def test_missing_all_levels_stays_deterministic_and_keeps_direct_source_untouched(tmp_path):
    p,notes=level_source();notes=[n for n in notes if n['kind']!='section_marker']
    p=build(tmp_path,p,notes)
    assert [c['plan_reference']['z_mm'] for c in p['plan_results']]==[0,1000]
    before=deepcopy(p['plan_results'][1]['plan_reference']);replay_named(p,tmp_path)
    assert p['plan_results'][1]['plan_reference']==before
    direct,notes=level_source();direct['scan_capture']={'issues':[]}
    direct=build(tmp_path,direct,notes)
    assert all('cad_reference_level' not in c for c in direct['plan_results'])


@pytest.mark.parametrize('measured',[True,False])
def test_only_one_plan_is_placed_at_zero_even_for_a_measured_horizontal_section(tmp_path,measured):
    p,notes=fixture()
    if not measured:notes=[n for n in notes if n['handle']!='H3']
    selected=choose_product_plan(p,notes,multiple=True);assert len(selected)==1
    analyse(p,selected,notes,tmp_path)
    ref=p['plan_reference'];level=ref['level']
    assert ref['z_mm']==0 and level['placement_basis']=='single_plan_zero'
    assert level['plan_count']==1
    if measured:
        assert level['status']=='measured' and level['level_mm']==700 and level['links']
    else:assert level['status']=='provisional' and level['issue']
    view=next(v for v in ref['views'] if v['id']==ref['view_id'])
    assert view['z_mm']==0 and project(view['box_mm'][:2],view,ref['plan_bounds_mm'])[2]==0
