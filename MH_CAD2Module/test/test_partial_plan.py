from copy import deepcopy

from combined_runtime import analyse
from drawing_scope import choose_product_plan
from test_sp25_sections import source


def build(tmp_path):
    d=source();p=d['product'];p['code']='QA-PARTIAL'
    analyse(p,choose_product_plan(p,d['annotations'],multiple=True),d['annotations'],tmp_path)
    return p


def test_common_bays_survive_unclosed_tail_and_trim_depth_noise(tmp_path):
    p=build(tmp_path)
    assert len(p['plan_results'])==1
    c=p['plan_results'][0];parts=c['modules'];known=[m for m in parts if m.get('height_source')=='front_stock_bounds']
    assert [(m['origin'][0],m['size'][0],m['origin'][2],m['size'][2]) for m in known]==[
        (25,575,860,600),(618,996,50,2110),(618,996,2160,540),
        (1614,996,50,2110),(1614,996,2160,540)]
    assert c['partial_plan']['span_mm']==[0,2610]
    assert all(m['size'][1]==310 for m in parts+c['trim_parts'] if m['name']!='Module chân')
    tail=next(m for m in parts if m['origin'][0]==2610)
    assert tail['size']==[1084.829,310,2730] and tail['envelope_preview'] and tail['unresolved']
    assert [(m['origin'][0],m['size'][0]) for m in c['trim_parts']]==[(0,25),(600,18)]
    assert len(c['source_plan_variants'])==3
    assert c['partial_plan']['confirmed_modules']==7 and c['partial_plan']['unresolved_modules']==1
    bands=[m for m in parts if m['height_source']=='front_section_band']
    assert [(m['origin'][0],m['origin'][2],m['size']) for m in bands]==[(618,2700,[1992,310,30]),(618,0,[1992,292,50])]
    foot=bands[-1]
    assert foot['origin'][1]-known[0]['origin'][1]==18
    assert all(len(m['elevation_evidence']['sections'])==2 for m in bands)
    ref=c['plan_reference']
    assert len(ref['views'])==8 and len(ref['display_copies'])==3
    assert sorted(i for v in ref['views'] for i in v['segment_indices'])==list(range(len(ref['segments'])))
    assert sorted(v['z_mm'] for v in ref['views'] if v['role']=='plan')==[0,1000,2000]


def test_one_bad_bay_does_not_discard_other_registered_bays(tmp_path,monkeypatch):
    import partial_plan
    original=partial_plan.complete
    def damaged(p,selected,data):
        front=next(v for v in data['views'].values() if 'BỎ CÁNH' in v.get('title','').upper())
        offset=data['relations']['poses'][front['id']]['offset_mm']
        base=p['plan_results'][0]['source_plan_envelope'][0]
        front['rects']=[r for r in front['rects'] if abs(r.x0+offset-base-618)>.15]
        return original(p,selected,data)
    monkeypatch.setattr(partial_plan,'complete',damaged)
    p=build(tmp_path);c=p['plan_results'][0]
    assert c['unified_partial_plan']
    assert c['partial_plan']['confirmed_modules']==3
    assert any(m.get('unresolved') and m['origin'][0]==600 for m in c['modules'])
    assert any(not m.get('unresolved') and m['origin'][0]==1614 for m in c['modules'])


def test_no_unification_for_manual_or_scan_sources(tmp_path,monkeypatch):
    import partial_plan
    original=partial_plan.complete
    blocked=[]
    def check(p,selected,data):
        for mode in ['manual','scan']:
            other=deepcopy(p)
            if mode=='manual':other['plan_results'][0]['manual_boxes']=True
            else:other['scan_capture']={'source':'native'}
            before=deepcopy(other)
            assert original(other,selected,data) is False and other==before
            blocked.append(mode)
        return original(p,selected,data)
    monkeypatch.setattr(partial_plan,'complete',check)
    build(tmp_path)
    assert blocked==['manual','scan']


def test_even_one_closed_bay_survives_other_missing_walls(tmp_path,monkeypatch):
    import partial_plan
    original=partial_plan.complete
    def damaged(p,selected,data):
        front=next(v for v in data['views'].values() if 'BỎ CÁNH' in v.get('title','').upper())
        offset=data['relations']['poses'][front['id']]['offset_mm'];base=p['plan_results'][0]['source_plan_envelope'][0]
        front['rects']=[r for r in front['rects'] if all(abs(r.x0+offset-base-x)>.15 for x in (618,1614))]
        return original(p,selected,data)
    monkeypatch.setattr(partial_plan,'complete',damaged)
    c=build(tmp_path)['plan_results'][0]
    assert c['partial_plan']['confirmed_modules']==1
    known=[m for m in c['modules'] if not m.get('unresolved')]
    assert len(known)==1 and known[0]['origin'][0]==25
    assert any(m.get('unresolved') and m['origin'][0]==600 for m in c['modules'])
