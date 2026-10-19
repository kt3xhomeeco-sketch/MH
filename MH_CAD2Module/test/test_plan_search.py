"""Near examples and reusable parts are proposals, not measured dimensions."""
from copy import deepcopy
import hashlib
import json

import pytest

from learning import ExperienceLibrary
from library import atomic_json
from local_ai import Assistant, validate_search
from plan_learning import features
from plan_search import Samples, proposals, physical_check, compiled_sample, board_rectangles
from stages import recognise_plan, source_placement
from geometry import Rect
from test_local_ai import FakeRuntime, fixture
from test_plan_rules import plan, curved_plan
from test_learning import save_example


def drawing(widths=(1090,470,650),depth=710,stock=18,trim=False):
    p,_=plan();p['rectangles']=[];p['outlines']=[];left=30000
    for width in widths:
        boxes=[[left,40000,left+stock,40000+depth],[left+width-stock,40000,left+width,40000+depth],
               [left+stock,40000,left+width-stock,40000+stock],
               [left+stock,40000+depth-stock,left+width-stock,40000+depth]]
        for b in boxes:
            h=str(len(p['rectangles']));p['rectangles'].append(dict(box=b,handle=h,layer='2 cat nt'))
            p['outlines'].append(dict(handle=h,layer='2 cat nt',points=[b[:2],[b[2],b[1]],b[2:],[b[0],b[3]],b[:2]]))
        left+=width
    if trim:
        b=[30000-stock,40000,30000,40050];h='extra-trim'
        p['rectangles'].append(dict(box=b,handle=h,layer='2 cat nt'))
        p['outlines'].append(dict(handle=h,layer='2 cat nt',points=[b[:2],[b[2],b[1]],b[2:],[b[0],b[3]],b[:2]]))
    p['views'][0]['region']=[29900,39999,left+1,40000+depth+1]
    p['geometry_pipeline']=dict(mode='plan_only')
    result=recognise_plan([dict(p['views'][0],rects=[Rect(*r['box'],r['handle'],r['layer']) for r in p['rectangles']],outlines=p['outlines'])],p['geometry_pipeline'])
    p.update(result,status='ready');p.pop('error',None)
    return p


def source(root,merged=False,partial=False):
    p,state=plan()
    if merged:state['modules']=[dict(id='whole',origin=[0,0,0],size=state['bounds'])]
    if partial:state['modules']=state['modules'][:1]
    return save_example(root,p,state,eid='001',input_axes_ignored=True,scope=dict(partial_sample=partial))


class ComposeRuntime(FakeRuntime):
    def choose(self,packet):
        self.calls+=1
        c=next(c for c in packet['candidates'] if c['method']=='composed_measured_bays')
        return dict(decision='choose',candidate_id=c['id'],reason='Repeat measured bays and retain auxiliary parts.'),dict(model='test',seconds=.1,cached=False)


def test_different_family_noise_is_offered_to_ai_and_remeasured(tmp_path):
    p,expected=fixture(tmp_path)
    p['outlines'].append(dict(handle='noise',layer='0',points=[[30100,40100],[30210,40130]]))
    lib=Samples(tmp_path).refresh();cad=features(p)
    assert features(lib.rows[0]['event']['analysis'])['family']!=cad['family']
    ai=FakeRuntime();assert Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),ai).apply(p),p.get('local_ai')
    assert p['learning']['method']=='adapted_cad_anchors'
    assert [m['size'] for m in p['modules']]==[m['size'] for m in expected['modules']]
    assert ai.find_calls==ai.calls==1
    assert p['local_ai']['final_check']['passed']


def test_two_bay_example_can_repeat_into_three_current_cad_bays(tmp_path):
    source(tmp_path);p=drawing();ai=ComposeRuntime()
    assert Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),ai).apply(p),p.get('local_ai')
    assert [m['size'][:2] for m in p['modules']]==[[1090,710],[470,710],[650,710]]
    assert p['learning']['method']=='composed_measured_bays'
    source_placement(p,dict(plane='XZ',plane_offset_mm=73))
    assert p['placement']==dict(mode='source_plan',plane='XZ',origin_mm=[30000,40000],plane_offset_mm=73)


def test_app_scores_grouping_but_does_not_reject_near_variants(tmp_path):
    source(tmp_path);p=drawing();lib=Samples(tmp_path).refresh()
    options,_=proposals(p,features(p),lib.rows)
    repeated=next(c for c in options if c['method']=='composed_measured_bays')
    assert repeated['evaluation']['module_bay_spans']==[1,1,1]
    assert repeated['evaluation']['structure_score']==100
    assert any(len(c['state']['modules'])==2 for c in options)


def test_two_bay_and_one_bay_templates_can_be_combined(tmp_path):
    source(tmp_path,merged=True)
    one=drawing(widths=(600,),depth=600)
    state={k:deepcopy(one.get(k,[])) for k in ('modules','trim_parts','panel_parts','bounds')}
    save_example(tmp_path,one,state,eid='002',input_axes_ignored=True)
    p=drawing();lib=Samples(tmp_path).refresh();options,_=proposals(p,features(p),lib.rows)
    composed=[c for c in options if c['method']=='composed_measured_bays']
    assert any(c['evaluation']['module_bay_spans']==[1,2] for c in composed)
    assert any(c['evaluation']['module_bay_spans']==[2,1] for c in composed)


def test_ai_can_request_a_second_search_page(tmp_path):
    for i in range(10):
        p,s=plan((800+i*20,400),600)
        save_example(tmp_path,p,s,eid=f'{i:03}',input_axes_ignored=True)
    target=drawing(widths=(1090,470))
    class Paged(FakeRuntime):
        def find(self,packet):
            self.find_calls+=1
            if self.find_calls==1:
                assert len(packet['samples'])==8
                return dict(sample_ids=[],search='parts',reason='Search reusable parts.'),dict(cached=False)
            assert len(packet['samples'])==2 and packet['seen']==8
            return dict(sample_ids=[packet['samples'][0]['id']],search='done',reason='Use this sample.'),dict(cached=False)
        def choose(self,packet):
            self.calls+=1
            return dict(decision='choose',candidate_id=packet['candidates'][0]['id'],reason='Measured.'),dict(cached=False,model='test')
    runtime=Paged();Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),runtime).apply(target)
    assert runtime.find_calls==2 and runtime.calls==1
    assert target['local_ai']['rounds']==3 and len(target['local_ai']['searches'])==2


def test_changed_board_stock_and_extra_short_trim_use_current_cad(tmp_path):
    source(tmp_path);p=drawing(widths=(1090,470),stock=25,trim=True)
    assert Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),ComposeRuntime()).apply(p),p.get('local_ai')
    assert [m['size'][:2] for m in p['modules']]==[[1090,710],[470,710]]
    assert len(p['trim_parts'])==1
    assert p['trim_parts'][0]['size']==[25,710,1600]
    assert p['trim_parts'][0]['original_depth_mm']==50
    source_placement(p,dict(plane='XY'))
    assert p['placement']['origin_mm']==[29975,40000]


def test_partial_example_supplies_parts_without_whole_layout_transfer(tmp_path):
    source(tmp_path,partial=True);p=drawing();lib=Samples(tmp_path).refresh()
    options,_=proposals(p,features(p),lib.rows)
    assert lib.rows[0]['card']['partial']
    assert any(c['method']=='composed_measured_bays' for c in options)
    assert not any(c['method'] in ('measured_anchors','adapted_cad_anchors') for c in options)


def test_individually_accepted_variants_remain_available_to_ai(tmp_path):
    source(tmp_path)
    p,s=plan((920,610),650);s['modules']=[dict(id='whole',origin=[0,0,0],size=s['bounds'])]
    save_example(tmp_path,p,s,eid='002',input_axes_ignored=True)
    target=drawing(widths=(1090,470))
    lib=Samples(tmp_path).refresh();assert len(lib.rows)==2
    options,_=proposals(target,features(target),lib.rows)
    assert {len(c['state']['modules']) for c in options}>={1,2}
    atomic_json(tmp_path/'experience_exclusions'/'002.json',{})
    assert len(lib.refresh().rows)==1


def test_native_measured_plan_rejects_cut_inside_board_overlap_and_unproven_arc(tmp_path):
    p=drawing(widths=(1090,470));cad=features(p)
    state={k:deepcopy(p.get(k,[])) for k in ('modules','trim_parts','panel_parts','bounds')}
    state['modules'][0]['size'][0]-=9
    state['modules'][1]['origin'][0]-=9;state['modules'][1]['size'][0]+=9
    with pytest.raises(ValueError,match='xuyên'):physical_check(p,state,[0,0],cad)
    state['modules'][0]['size'][0]+=20
    with pytest.raises(ValueError,match='chồng|hợp lệ'):physical_check(p,state,[0,0],cad)
    p,s=curved_plan((1090,470),710,140)
    for part in s['modules']:part['handles']=['cad-edge']
    cad=features(p);cad['arcs']=[]
    with pytest.raises(ValueError,match='cung CAD'):physical_check(p,s,[0,0],cad)


def test_source_binding_mismatch_blocks_ai_but_soft_review_can_be_resolved(tmp_path):
    p,_=fixture(tmp_path);p['learning']=dict(mode='review',issues=[dict(code='source_binding_mismatch')])
    runtime=FakeRuntime();assert not Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),runtime).apply(p)
    assert runtime.find_calls==0
    p['learning']=dict(mode='review',rule='ambiguous-anchors')
    assert Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),runtime).apply(p)


def test_ai_rejection_prevents_automatic_build(tmp_path):
    p,_=fixture(tmp_path)
    runtime=FakeRuntime(dict(decision='reject',candidate_id='none',reason='Ambiguous grouping.'))
    assert not Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),runtime).apply(p)
    assert p['status']=='needs_review' and p['local_ai']['status']=='reject'


def test_feedback_changed_during_ai_does_not_apply_stale_choice(tmp_path):
    p,_=fixture(tmp_path);before=deepcopy(p)
    class Changed(FakeRuntime):
        def choose(self,packet):
            atomic_json(tmp_path/'experience_exclusions'/'001.json',{})
            return super().choose(packet)
    assert not Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),Changed()).apply(p)
    assert p['modules']==before['modules'] and p['local_ai']['status']=='fallback'
    assert 'thay đổi' in p['local_ai']['message']


def test_compiled_example_cache_recovers_and_new_feedback_has_own_revision(tmp_path):
    source(tmp_path);row=Samples(tmp_path).refresh().rows[0]
    original=compiled_sample(row)
    path=next((tmp_path/'rules'/'ai-plan-v2'/'samples').glob('*.json'))
    saved=json.loads(path.read_text('utf8'));saved['sample']['shape']=[];atomic_json(path,saved)
    assert compiled_sample(row)['shape']==original['shape']
    p,s=plan();s['modules']=[dict(id='whole',origin=[0,0,0],size=s['bounds'])]
    save_example(tmp_path,p,s,eid='999',input_axes_ignored=True)
    newer=Samples(tmp_path).refresh().rows[0]
    assert len(compiled_sample(newer)['shape'])==1
    assert len(list((tmp_path/'rules'/'ai-plan-v2'/'samples').glob('*.json')))==2


def test_baseline_choice_keeps_correct_full_source_registration_with_trim(tmp_path):
    source(tmp_path);p=drawing(widths=(1090,470),trim=True)
    runtime=FakeRuntime(dict(decision='choose',candidate_id='baseline',reason='Keep measured CAD.'))
    before=deepcopy(p['modules'])
    assert not Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),runtime).apply(p)
    source_placement(p,dict(plane='YZ',plane_offset_mm=73))
    assert p['modules']==before and p['local_ai']['final_check']['passed']
    assert p['placement']['origin_mm']==[29982,40000]


def test_recovered_double_wall_envelope_preserves_real_cabinet_seam():
    left=[1092,0,1110,705];right=[1110,0,1128,705];envelope=[1092,0,1128,705]
    assert board_rectangles([dict(box=b) for b in (left,right,envelope)],0)==[left,right]
    assert board_rectangles([dict(box=envelope)],0)==[envelope]


def test_full_line_scan_keeps_two_bays_with_recovered_36mm_envelope(tmp_path,monkeypatch):
    import local_ai
    from main import run
    source(tmp_path);p=drawing(widths=(1110,450),depth=705)
    lines=[dict(a=a,b=b,handle=o['handle'],layer='0') for o in p['outlines'] for a,b in zip(o['points'],o['points'][1:])]
    monkeypatch.setattr(local_ai,'Runtime',lambda *_:FakeRuntime())
    r=run(dict(action='geometry',library=str(tmp_path),build_plan=True,build_elevation=False,ai_enabled=True,
               geometry=dict(hash='e'*64,lines=lines,plane='XY',plane_offset_mm=73)))
    product=r['analyses'][0]['products'][0]
    assert product['status']=='ready',product.get('local_ai')
    assert product['local_ai']['status']=='choose',product.get('local_ai')
    assert product['local_ai']['final_check']['passed']
    assert [m['size'] for m in product['modules']]==[[1110,705,1600],[450,705,1600]]
    assert product['placement']['origin_mm']==[30000,40000]
    from plan_search import target_card
    assert target_card(product,features(product))['stocks']==[18]


def test_ai_failure_cannot_fall_back_to_a_plan_cutting_through_wall(tmp_path):
    p,_=fixture(tmp_path)
    p['modules'][0]['size']=list(p['bounds'])
    p['modules'][0]['origin'][0]=9;p['modules'][0]['size'][0]-=9
    runtime=FakeRuntime(error=TimeoutError('offline'))
    assert not Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),runtime).apply(p)
    assert p['status']=='needs_review'
    assert not p['local_ai'].get('fallback_to_cad')
    assert 'xuyên' in p['error']


@pytest.mark.parametrize('answer',[
    dict(sample_ids=['invented'],search='done',reason='bad'),
    dict(sample_ids=['S1','S1'],search='done',reason='bad'),
    dict(sample_ids=['S1'],search='execute_code',reason='bad'),
    dict(sample_ids=['S1'],search='done',reason='bad',dimensions=[999]),
    None,
])
def test_search_reply_is_bounded_and_cannot_invent_ids(answer):
    with pytest.raises(ValueError):validate_search(answer,['S1'])
