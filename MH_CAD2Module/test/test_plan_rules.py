"""Automatic induction must remeasure unseen CAD, never resize accepted boxes."""
from copy import deepcopy
import hashlib
import json
import math

import pytest
from library import VERSION, atomic_json
from plan_learning import PlanRuleLibrary, features, example, fit, infer, matches
from test_learning import sample_product, save_example


def plan(widths=(800, 400), depth=600, stock=18):
    product, _ = sample_product(widths=widths, depth=depth)
    view = next(v for v in product['views'] if v['id']=='sourceP')
    product['views']=[view]
    product['rectangles']=[r for r in product['rectangles'] if '-P-' in r['handle']]
    product['outlines']=[o for o in product['outlines'] if '-P-' in o['handle']]
    # Vary stock independently, retaining the same geometric incidence.
    if stock!=18:
        for r in product['rectangles']:
            for axis in (0,1):
                if abs(r['box'][axis+2]-r['box'][axis]-18)<.01:r['box'][axis+2]+=stock-18
        for o,r in zip(product['outlines'],product['rectangles']):
            b=r['box'];o['points']=[b[:2],[b[2],b[1]],b[2:],[b[0],b[3]],b[:2]]
    product.update(build_stages={'plan':True,'elevation':False}, envelope=[30000,40000,30000+sum(widths),40000+depth],
                   source_plan_envelope=[30000,40000,30000+sum(widths),40000+depth])
    product['signature']=hashlib.sha256(json.dumps(product['outlines']).encode()).hexdigest()
    state=dict(bounds=[sum(widths),depth,1600],modules=[
        dict(id='M1',origin=[0,0,0],size=[widths[0],depth,1600]),
        dict(id='M2',origin=[widths[0],0,0],size=[widths[1],depth,1600])],trim_parts=[],panel_parts=[])
    return product,state


CASES=[((800,400),600),((920,610),650),((740,530),560)]


def train(root):
    events=[]
    for i,(widths,depth) in enumerate(CASES):
        p,s=plan(widths,depth)
        events.append(save_example(root,p,s,eid=f'2026-{i}',input_axes_ignored=True))
    return events


def test_three_different_drawings_activate_and_remeasure_unseen_dimensions(tmp_path):
    train(tmp_path)
    lib=PlanRuleLibrary(tmp_path);summary=lib.refresh()
    assert summary['active']==1,summary
    assert summary['rules'][0]['passed']==summary['rules'][0]['tested']==3
    target,expected=plan((1090,470),710)
    assert lib.apply(target),target
    assert target['learning']['mode']=='plan_rule'
    assert [(p['origin'],p['size']) for p in target['modules']]==[(p['origin'],p['size']) for p in expected['modules']]
    assert all(p['handles'] for p in target['modules'])
    assert target['modules'][1]['source_box']==[31090,40000,31560,40710]


def test_one_two_samples_and_duplicate_signature_do_not_activate(tmp_path):
    p,s=plan();save_example(tmp_path,p,s,eid='001',input_axes_ignored=True)
    save_example(tmp_path,p,s,eid='002',input_axes_ignored=True)
    lib=PlanRuleLibrary(tmp_path)
    assert lib.refresh()['rules'][0]['examples']==['002']
    p,s=plan(*CASES[1]);save_example(tmp_path,p,s,eid='003',input_axes_ignored=True)
    status=lib.refresh()
    assert status['active']==0 and status['waiting']==1
    assert len(status['rules'][0]['examples'])==2


def test_conflict_and_exclusion_deactivate_existing_rule(tmp_path):
    events=train(tmp_path);lib=PlanRuleLibrary(tmp_path)
    assert lib.refresh()['active']==1
    p,s=plan(*CASES[0]);s['modules']=[dict(id='joined',origin=[0,0,0],size=s['bounds'])]
    save_example(tmp_path,p,s,eid='2099-conflict',input_axes_ignored=True)
    status=lib.refresh()
    assert status['active']==0 and status['blocked']==1
    atomic_json(tmp_path/'experience_exclusions'/'2099-conflict.json',{'reason':'test'})
    assert lib.refresh()['active']==1
    atomic_json(tmp_path/'experience_exclusions'/f"{events[0]['id']}.json",{})
    assert lib.refresh()['active']==0


def test_other_stock_topology_and_partial_examples_are_not_reused(tmp_path):
    train(tmp_path);lib=PlanRuleLibrary(tmp_path)
    target,_=plan((1090,470),710,stock=25)
    assert not lib.apply(target)
    target,_=plan((1090,470),710)
    target['outlines'].append(dict(handle='extra',layer='0',points=[[30010,40010],[30100,40100]]))
    assert not lib.apply(target)
    p,s=plan(*CASES[0]);save_example(tmp_path,p,s,eid='2099-partial',input_axes_ignored=True,scope={'partial_sample':True})
    status=lib.refresh()
    assert status['active']==0 and status['issues']


def test_corrupt_cache_is_rebuilt_without_modifying_accepted_history(tmp_path):
    train(tmp_path);original={p:p.read_bytes() for p in (tmp_path/'experiences').glob('*/*.json')}
    lib=PlanRuleLibrary(tmp_path);assert lib.refresh()['active']==1
    path=tmp_path/'rules'/'plan-v1'/'catalog.json'
    catalog=json.loads(path.read_text('utf8'));catalog['candidates'][0]['status']='blocked'
    atomic_json(path,catalog)
    assert lib.refresh()['active']==1
    assert all(p.read_bytes()==b for p,b in original.items())
    assert list((tmp_path/'rules'/'plan-v1'/'revisions').glob('*.json'))


def test_parser_update_and_missing_status_invalidate_or_restore_cache(tmp_path,monkeypatch):
    import plan_learning
    train(tmp_path);lib=PlanRuleLibrary(tmp_path)
    assert lib.refresh()['active']==1
    status=tmp_path/'rules'/'plan-v1'/'status.json'
    status.unlink()
    assert lib.refresh()['active']==1 and status.exists()
    monkeypatch.setattr(plan_learning,'VERSION','new-parser')
    changed=lib.refresh()
    assert changed['active']==0 and len(changed['issues'])==3


def test_exact_feedback_has_priority_over_automatic_rule(tmp_path):
    from main import replay_experience
    train(tmp_path)
    p,s=plan(*CASES[0]);assert replay_experience(p,tmp_path)
    assert p['learning']['mode']=='plan_exact'
    p,s=plan((1090,470),710);assert replay_experience(p,tmp_path)
    assert p['learning']['mode']=='plan_rule'


def test_worker_background_refresh_and_malformed_event(tmp_path):
    from main import run
    train(tmp_path)
    atomic_json(tmp_path/'experiences'/'broken'/'bad.json',{'status':'accepted','signature':'broken','analysis':None})
    result=run({'action':'learn_plan','library':str(tmp_path)})
    assert result['plan_rules']['active']==1
    assert result['plan_rules']['issues']


def curved_plan(widths=(800,400),depth=600,radius=100):
    from plan_profiles import profile_from_points
    p,s=plan(widths,depth)
    # A rounded left bay and a rectangular right frame; the arc is real source evidence.
    p['rectangles']=p['rectangles'][4:];p['outlines']=p['outlines'][4:]
    points=[[radius+radius*math.cos(math.pi+i*math.pi/48),radius+radius*math.sin(math.pi+i*math.pi/48)] for i in range(25)]
    points += [[widths[0],0],[widths[0],depth],[0,depth]]
    s['modules'][0]['plan_profile']=profile_from_points(points)
    world=[[x+30000,y+40000] for x,y in points]
    p['outlines'].append(dict(handle='rounded-left',layer='0',points=world+[world[0]]))
    p['signature']=hashlib.sha256(json.dumps(p['outlines']).encode()).hexdigest()
    return p,s


def test_arcs_remeasure_target_radius_and_require_cad_confirmation(tmp_path):
    for i,((widths,depth),radius) in enumerate(zip(CASES,(100,120,90))):
        p,s=curved_plan(widths,depth,radius)
        save_example(tmp_path,p,s,eid=f'2026-{i}',input_axes_ignored=True)
    lib=PlanRuleLibrary(tmp_path)
    status=lib.refresh();assert status['active']==1,status
    target,expected=curved_plan((1090,470),710,140)
    assert lib.apply(target),target.get('learning')
    arcs=[a for a in target['modules'][0]['plan_profile']['segments'] if a['type']=='arc']
    assert len(arcs)==1 and arcs[0]['radius']==pytest.approx(140,abs=.01)
    from plan_learning import RuleError
    cad=features(target);cad['arcs']=[]
    with pytest.raises(RuleError,match='cung tròn'):
        infer(lib.catalog['candidates'][0]['program'],cad)


def test_ambiguous_correlated_training_rejects_different_new_relation(tmp_path):
    # Training cannot tell whether an offset belongs to board edge or centre.
    train(tmp_path);lib=PlanRuleLibrary(tmp_path);assert lib.refresh()['active']==1
    target,_=plan((1090,470),710)
    cad=features(target);program=deepcopy(lib.catalog['candidates'][0]['program'])
    choices=next(c for axis in program['bindings'] for c in axis if len(c)>1)
    choices[-1]['delta']+=1
    from plan_learning import RuleError
    with pytest.raises(RuleError,match='nhiều vị trí'):
        infer(program,cad)


def test_normal_source_scan_uses_rule_and_keeps_world_origin(tmp_path):
    from main import run
    train(tmp_path);p,_=plan((1090,470),710)
    lines=[dict(a=a,b=b,handle=o['handle'],layer='0') for o in p['outlines'] for a,b in zip(o['points'],o['points'][1:])]
    result=run(dict(action='geometry',library=str(tmp_path),build_plan=True,build_elevation=False,
                    geometry=dict(hash='c'*64,lines=lines,plane='XY',plane_offset_mm=73)))
    target=result['analyses'][0]['products'][0]
    assert target['learning']['mode']=='plan_rule',target
    assert target['placement']['origin_mm']==[30000,40000]
    assert target['placement']['plane_offset_mm']==73


def test_measurement_reuse_does_not_trust_signature_after_cad_changes(tmp_path):
    lib=PlanRuleLibrary(tmp_path)
    p,_=plan()
    initial=lib.measured_features(p)
    assert lib.measured_features(deepcopy(p)) is initial
    stock,_=plan(stock=25);stock['signature']=p['signature']
    assert lib.measured_features(stock)['family']!=initial['family']
    moved=deepcopy(p)
    moved['source_plan_envelope'][0]-=18
    assert lib.measured_features(moved)['base'][0]==initial['base'][0]-18
    renamed=deepcopy(p)
    for o in renamed['outlines']:o['handle']='new-'+o['handle']
    proof=lib.measured_features(renamed)['proof']
    assert any('new-' in h for axis in proof for handles in axis.values() for h in handles)
    assert all('new-' not in h for axis in initial['proof'] for handles in axis.values() for h in handles)
    assert p['signature']==stock['signature']==moved['signature']==renamed['signature']
