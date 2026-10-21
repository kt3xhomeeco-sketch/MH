import json
from pathlib import Path

from combined_runtime import analyse
from drawing_scope import choose_product_plan


def source():
    return json.loads((Path(__file__).parent/'fixtures/named_sp35_sections.json').read_text('utf8'))


def build(tmp_path):
    d=source();p=d['product'];s=choose_product_plan(p,d['annotations'],multiple=True)
    analyse(p,s,d['annotations'],tmp_path)
    return p


def test_horizontal_5_5_marker_can_confirm_large_l_section():
    d=source();p=d['product'];s=choose_product_plan(p,d['annotations'],multiple=True)
    assert [v['id'] for v in s]==['V01.1']
    plan=p['view_analysis']['candidates'][0]
    assert plan['role']=='plan' and plan['height_mm']==1830
    assert len(plan['section_links'])==2 and all(c['axis']=='horizontal' for c in plan['section_links'])


def test_name_alone_or_vertical_marker_does_not_confirm_5_5():
    for mode in ['remove','vertical']:
        d=source()
        if mode=='remove':d['annotations']=[a for a in d['annotations'] if a.get('numbers')!=['5']]
        else:
            for a in d['annotations']:
                if a.get('numbers')==['5']:a['axis']='vertical'
        assert not choose_product_plan(d['product'],d['annotations'],multiple=True)


def test_plan_bays_cross_projection_and_auxiliary_sums_match_distinct_fronts(tmp_path):
    p=build(tmp_path);proof=p['plan_components'];parts=p['modules']
    assert p['status']=='ready' and 'error' not in p and 'envelope_preview' not in p
    assert [(round(m['size'][0],3),round(m['size'][1],3)) for m in parts]==[(512.001,325),(968.037,580),(666,680),(500,1102)]
    assert proof['closed_bays']==3 and proof['pending_bays']==1
    a,b=proof['front_matches']
    assert (a['axis'],a['front_id'],a['matched_modules'])==('X','V04.1',3)
    assert (b['axis'],b['front_id'],b['matched_modules'])==('Y','V08.1',2)
    assert abs(a['sum_with_auxiliary_mm']-2170.038)<.001 and b['sum_with_auxiliary_mm']==1730
    assert abs(a['unexplained_front_mm'])<.001 and abs(b['unexplained_front_mm'])<.001
    assert b['projected_widths_used_mm']==[580] # Same corner seen from the other face; not a duplicate module.
    assert len(p['trim_parts'])==8
    assert all(m['height_source']=='product_elevation_bounds' and m['elevation_pending'] for m in parts)
    open_box=next(m for m in parts if m.get('unresolved'))
    assert open_box['size'][1]==680 and abs(open_box['plan_component_evidence']['sections'][0]['depth_mm']-690)<.01
    assert abs(open_box['plan_component_evidence']['sections'][0]['difference_mm']+10)<.01
    assert p['plan_reference']['views'][0]['plane']=='XY'
    assert p['cad_reference_levels']['V01.1']['placement_z_mm']==0
    ref=p['plan_reference']
    assert len(ref['display_copies'])==4
    assert sorted(i for v in ref['views'] for i in v['segment_indices'])==list(range(len(ref['segments'])))


def test_missing_all_front_profiles_keeps_explicit_preview_instead_of_inventing_modules(tmp_path,monkeypatch):
    import plan_components
    original=plan_components.complete
    def no_front(child,view,data):
        data['views']={k:v for k,v in data['views'].items() if v['role']!='elevation'}
        return original(child,view,data)
    monkeypatch.setattr(plan_components,'complete',no_front)
    p=build(tmp_path)
    assert p['envelope_preview'] and 'plan_components' not in p
