import copy
import json
from pathlib import Path

from learning import ExperienceLibrary, compile_sample, EvidenceError, RULE_SCHEMA
from library import VERSION, atomic_json
import pytest


def sample_product(widths=(800, 400), depth=600, upper_depth=350, lower_height=700,
                   upper_height=400, upper_z=1300, plinth=50, prefix='source'):
    """Separate CAD views, fixed 18mm stock, independently variable spans."""
    w = sum(widths)
    modules = [dict(id='M01', name='Left', origin=[0, 0, plinth], size=[widths[0], depth, lower_height]),
               dict(id='M02', name='Right', origin=[widths[0], 0, plinth], size=[widths[1], depth, lower_height]),
               dict(id='M03', name='Upper', origin=[0, depth-upper_depth, upper_z], size=[w, upper_depth, upper_height])]
    auxiliary = [dict(id='A01', name='Base', role='auxiliary', origin=[0, 0, 0], size=[w, depth, plinth])]
    views, rectangles, outlines = [], [], []
    def add_view(key, role, boxes, dx, dy):
        rs = []
        for i, box in enumerate(boxes):
            b = [box[0]+dx, box[1]+dy, box[2]+dx, box[3]+dy]
            handle = f'{prefix}-{key}-{i}'
            rs.append(dict(box=b, handle=handle, layer='2 cat nt'))
            outlines.append(dict(handle=handle, layer='2 cat nt', points=[b[:2], [b[2],b[1]], b[2:], [b[0],b[3]], b[:2]]))
        rectangles.extend(rs)
        views.append(dict(id=prefix+key, role=role, title='ignored',
                          region=[min(r['box'][0] for r in rs)-1, min(r['box'][1] for r in rs)-1,
                                  max(r['box'][2] for r in rs)+1, max(r['box'][3] for r in rs)+1]))
    def frame(x, y, width, height):
        return [[x,y,x+18,y+height], [x+width-18,y,x+width,y+height],
                [x+18,y,x+width-18,y+18], [x+18,y+height-18,x+width-18,y+height]]
    front = []
    for m in modules:
        front += frame(m['origin'][0], m['origin'][2], m['size'][0], m['size'][2])
    front += [[widths[0]-9, upper_z+18, widths[0]+9, upper_z+upper_height-18], [0,0,w,plinth]]
    add_view('F', 'front_open', front, 10000, 20000)
    add_view('P', 'plan', frame(0,0,widths[0],depth)+frame(widths[0],0,widths[1],depth), 30000, 40000)
    add_view('Q', 'plan', frame(0,depth-upper_depth,w,upper_depth), 50000, 60000)
    add_view('S', 'section_vertical', frame(0,plinth,depth,lower_height)+
             frame(depth-upper_depth,upper_z,upper_depth,upper_height)+[[0,0,depth,plinth]], 70000,80000)
    state = dict(modules=modules, panel_parts=auxiliary, trim_parts=[], bounds=[w, depth, upper_z+upper_height])
    product = dict(code='SP99', name='unrelated name', parser_version=VERSION,
                   signature=('a' if prefix=='source' else 'b')*64, rectangles=rectangles,
                   outlines=outlines, views=views, status='needs_review', error='original recognizer failed', modules=[])
    return product, state


def save_example(root, product, state, eid='sample', **extra):
    event = dict(id=eid, signature=product['signature'], parser_version=VERSION, status='accepted',
                 analysis=product, after=state, **extra)
    atomic_json(root/'experiences'/product['signature']/f'{eid}.json', event)
    return event


def changed_product(**extra):
    return sample_product(widths=(920,610), depth=650, upper_depth=400, lower_height=830,
                          upper_height=500, upper_z=1400, plinth=60, prefix='target', **extra)


def test_independent_bay_height_depth_remeasurement_and_auxiliary_roles(tmp_path):
    source, source_state = sample_product()
    save_example(tmp_path, source, source_state)
    target, expected = changed_product()
    assert ExperienceLibrary(tmp_path).apply(target), target.get('learning')
    assert target['learning']['mode']=='similar'
    assert target['status']=='ready' and 'error' not in target
    for kind in ('modules','panel_parts'):
        assert [(p['origin'],p['size']) for p in target[kind]] == [(p['origin'],p['size']) for p in expected[kind]]
    assert target['bounds']==expected['bounds']
    for part in target['modules']+target['panel_parts']:
        assert len(part['anchor_evidence'])==6
        assert part['handles'] and all(h.startswith('target-') for h in part['handles'])
    assert list((tmp_path/'rules'/f'v{RULE_SCHEMA}').glob('*.json'))
    # A second process reads compiled rules without losing float-plane bindings.
    again, _ = changed_product()
    assert ExperienceLibrary(tmp_path).apply(again)
    assert again['modules']==target['modules']


def test_missing_plan_different_topology_and_stock_do_not_transfer(tmp_path):
    source, state = sample_product(); save_example(tmp_path,source,state)
    missing, _ = changed_product(); missing['views']=[v for v in missing['views'] if v['role']!='plan']
    assert not ExperienceLibrary(tmp_path).apply(missing)
    assert missing['status']=='needs_review'
    changed, _ = changed_product(); changed['rectangles'].pop()
    changed['outlines'].pop()
    assert not ExperienceLibrary(tmp_path).apply(changed)


def test_conflicting_depth_is_a_review_with_geometry_reason(tmp_path):
    source, state = sample_product(); save_example(tmp_path,source,state)
    target, _ = changed_product()
    section = next(v for v in target['views'] if v['role']=='section_vertical')
    for r in target['rectangles']:
        if r['handle'].startswith('target-S-'):
            r['box'][0] += 10 if r['box'][0]>70100 else 0
            r['box'][2] += 10 if r['box'][2]>70100 else 0
    target['outlines']=[o for o in target['outlines'] if not o['handle'].startswith('target-S-')]
    section['region'][2]+=20
    target['status']='ready'; target.pop('error')
    assert not ExperienceLibrary(tmp_path).apply(target)
    assert target['status']=='needs_review'
    assert target['learning']['issues']


def test_two_accepted_groupings_require_confirmation(tmp_path):
    source, state = sample_product(); save_example(tmp_path,source,state,'first')
    other=copy.deepcopy(state)
    upper=other['modules'].pop()
    a,b=copy.deepcopy(upper),copy.deepcopy(upper)
    a['size'][0]=800; b['origin'][0]=800;b['size'][0]=400;b['id']='M04'
    other['modules'] += [a,b]
    separate=copy.deepcopy(source);separate['signature']='c'*64
    save_example(tmp_path,separate,other,'second')
    target,_=changed_product()
    assert not ExperienceLibrary(tmp_path).apply(target)
    assert target['learning']['issues'][0]['code']=='conflicting_examples'


def test_partial_exact_example_is_never_automatic_complete_product(tmp_path):
    source,state=sample_product()
    save_example(tmp_path,source,state,scope={'partial_sample':True,'excluded':['crown']})
    assert ExperienceLibrary(tmp_path).apply(source)
    assert source['status']=='needs_review'
    assert source['learning']['issues'][0]['excluded']==['crown']
    target,_=changed_product()
    assert not ExperienceLibrary(tmp_path).apply(target)
    assert any('thiếu' in i['message'] for i in target['learning']['issues'])


def test_bad_files_unaccepted_samples_and_new_feedback(tmp_path):
    source,state=sample_product()
    event=save_example(tmp_path,source,state)
    folder=tmp_path/'experiences'/source['signature']
    (folder/'broken.json').write_text('{bad')
    event['status']='pending';atomic_json(folder/'sample.json',event)
    target,_=changed_product()
    assert not ExperienceLibrary(tmp_path).apply(target)
    event['status']='accepted';atomic_json(folder/'sample.json',event)
    target,_=changed_product()
    assert ExperienceLibrary(tmp_path).apply(target)


def test_profiles_and_unbound_planes_require_more_evidence():
    source,state=sample_product()
    event=dict(analysis=source,after=state)
    state['modules'][0]['origin'][0]=1.234
    state['modules'][0]['size'][0]-=1.234
    with pytest.raises(EvidenceError):compile_sample(event)
    state['modules'][0]['profile']=[[0,0],[1,0],[1,1]]
    with pytest.raises(EvidenceError,match='biên dạng'):compile_sample(event)


def wardrobe_variant():
    """Resize real manually accepted SP21 evidence, without resizing its stock."""
    event=json.loads((Path(__file__).parent/'fixtures'/'learning_wardrobe.json').read_text(encoding='utf-8'))
    prototype=compile_sample(event)
    source=event['analysis']
    def warp(value, axis):
        if axis==0:return value+(85 if value>600 else 0)-(130 if value>1600 else 0)
        if axis==1:return value+(50 if value>300 else 0)
        return value+(100 if value>1000 else 0)+(58 if value>2240 else 0)
    target=copy.deepcopy(source)
    target.update(code='SP_DIFFERENT',signature='f'*64,rectangles=[],outlines=[],views=[],status='needs_review')
    for i,view in enumerate(prototype['views']):
        original=next(v for v in source['views'] if v['id']==view['id'])
        transforms=[]
        for cad_axis in (0,1):
            physical=(1 if view['role']=='section_vertical' else 0) if cad_axis==0 else (1 if view['role']=='plan' else 2)
            fit=next(f for f in prototype['fits'][physical] if f['view']==view['id'] and f['axis']==cad_axis)
            plane,anchor=fit['bindings'][0]
            offset=anchor['value']-fit['sign']*plane
            transforms.append((physical,fit['sign'],offset))
        def point(p):
            q=[]
            for a in (0,1):
                physical,sign,offset=transforms[a]
                q.append(round(offset+sign*warp(sign*(p[a]-offset),physical)+(i*10000 if a==0 else 0)-original['region'][a],6))
            return q
        rs=[];os=[]
        for row in source['rectangles']:
            b=row['box'];r=original['region']
            if r[0]<=b[0]<=b[2]<=r[2] and r[1]<=b[1]<=b[3]<=r[3]:
                m=copy.deepcopy(row);m['box']=point(b[:2])+point(b[2:]);m['handle']='new'+row['handle'];rs.append(m)
        for row in source['outlines']:
            r=original['region']
            if all(r[0]<=p[0]<=r[2] and r[1]<=p[1]<=r[3] for p in row['points']):
                m=copy.deepcopy(row);m['points']=[point(p) for p in row['points']];m['handle']='new'+row['handle'];os.append(m)
        coords=[p for o in os for p in o['points']]+[r['box'][:2] for r in rs]+[r['box'][2:] for r in rs]
        v=copy.deepcopy(original);v['id']='new'+view['id'];v['region']=[min(p[0] for p in coords)-1,min(p[1] for p in coords)-1,max(p[0] for p in coords)+1,max(p[1] for p in coords)+1]
        target['views'].append(v);target['rectangles']+=rs;target['outlines']+=os
    expected=copy.deepcopy(event['after'])
    for kind in ('modules','panel_parts','trim_parts'):
        for part in expected[kind]:
            end=[part['origin'][a]+part['size'][a] for a in range(3)]
            part['origin']=[warp(v,a) for a,v in enumerate(part['origin'])]
            part['size']=[warp(end[a],a)-part['origin'][a] for a in range(3)]
    expected['bounds']=[warp(v,a) for a,v in enumerate(expected['bounds'])]
    return event,target,expected


def test_real_manual_sample_changed_bays_height_depth_and_cad_placement(tmp_path):
    event,target,expected=wardrobe_variant()
    atomic_json(tmp_path/'experiences'/event['signature']/'sample.json',event)
    assert ExperienceLibrary(tmp_path).apply(target),target.get('learning')
    for kind in ('modules','panel_parts'):
        for actual,wanted in zip(target[kind],expected[kind]):
            assert actual['origin']==pytest.approx(wanted['origin'],abs=0.01)
            assert actual['size']==pytest.approx(wanted['size'],abs=0.01)
    assert target['bounds']==pytest.approx([2205,650,2650],abs=0.01)
    assert [m['size'][0] for m in target['modules']]==pytest.approx([1160,945,1160,945],abs=0.01)


def test_corrupted_derived_cache_rebuilds_from_immutable_example(tmp_path):
    source,state=sample_product();event=save_example(tmp_path,source,state)
    memory=ExperienceLibrary(tmp_path);memory.compiled(event)
    path=next((tmp_path/'rules'/f'v{RULE_SCHEMA}').glob('*.json'))
    cached=json.loads(path.read_text());cached['prototype']['after']['modules'][0]['size'][0]=9999
    atomic_json(path,cached)
    target,_=changed_product()
    assert ExperienceLibrary(tmp_path).apply(target)
    assert target['modules'][0]['size'][0]==920


def test_legacy_full_learning_remains_available_without_entering_new_section_stage(tmp_path):
    import main
    source,state=sample_product();save_example(tmp_path,source,state)
    target,expected=changed_product()
    main.replay_experience(target,tmp_path)
    actual=target
    assert actual['learning']['mode']=='similar' and actual['bounds']==expected['bounds']


def test_changed_stock_is_not_scaled_into_a_template(tmp_path):
    source,state=sample_product();save_example(tmp_path,source,state)
    target,_=changed_product()
    # Change a complete thin-panel edge throughout its matching view.
    for row in target['rectangles']:
        if row['handle']=='target-P-0':row['box'][2]+=7
    target['outlines']=[o for o in target['outlines'] if o['handle']!='target-P-0']
    assert not ExperienceLibrary(tmp_path).apply(target)
    assert target['status']=='needs_review'


def test_new_unbroken_section_panel_cannot_reuse_old_joint(tmp_path):
    source,state=sample_product();save_example(tmp_path,source,state)
    target,_=changed_product()
    target['rectangles'].append(dict(handle='continuous',layer='2 cat nt',box=[70000,80000,70018,81900]))
    assert not ExperienceLibrary(tmp_path).apply(target)
    assert target['status']=='needs_review'


def test_extra_profile_or_extra_construction_view_is_not_silently_ignored(tmp_path):
    source,state=sample_product();save_example(tmp_path,source,state)
    profile,_=changed_product()
    profile['outlines'].append(dict(handle='new-L-support',layer='2 cat nt',
                                    points=[[10060,21400],[10100,21400],[10100,21500]]))
    assert not ExperienceLibrary(tmp_path).apply(profile)
    extra,_=changed_product()
    extra['views'].append(dict(extra['views'][0],id='another-product'))
    assert not ExperienceLibrary(tmp_path).apply(extra)


def test_latest_accepted_feedback_supersedes_older_layout_without_erasing_history(tmp_path):
    source,state=sample_product();save_example(tmp_path,source,state,'first')
    newer=copy.deepcopy(state);upper=newer['modules'].pop()
    left,right=copy.deepcopy(upper),copy.deepcopy(upper)
    left['size'][0]=800;right['origin'][0]=800;right['size'][0]=400;right['id']='M04'
    newer['modules'] += [left,right]
    save_example(tmp_path,source,newer,'z-latest')
    target,_=changed_product()
    assert ExperienceLibrary(tmp_path).apply(target)
    assert target['learning']['event']=='z-latest' and len(target['modules'])==4
    assert len(list((tmp_path/'experiences'/source['signature']).glob('*.json')))==2
