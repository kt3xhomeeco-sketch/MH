"""AI must choose an ID; native CAD measurement remains authoritative."""
from copy import deepcopy
import json
import time
from pathlib import Path

import pytest

from library import atomic_json
from learning import ExperienceLibrary
from local_ai import Assistant, Runtime, compact, status
from test_plan_rules import plan
from test_learning import save_example


class FakeRuntime:
    def __init__(self, answer=None, error=None):
        self.answer = dict(decision='choose', candidate_id='learned', reason='Two measured bays.') if answer is None else answer
        self.error = error
        self.calls = 0
        self.find_calls = 0

    def find(self, packet):
        self.find_calls += 1
        if self.error:
            raise self.error
        return dict(sample_ids=[packet['samples'][0]['id']],search='done',reason='Use the measured construction.'),dict(seconds=.2,model='test',cached=False)

    def choose(self, packet):
        self.calls += 1
        assert packet['measured_axes'] and 'source_path' not in packet
        if self.error:
            raise self.error
        return self.answer, dict(seconds=1.5, model='test', cached=False)


def fixture(root):
    p, s = plan()
    save_example(root, p, s, eid='001', input_axes_ignored=True)
    target, expected = plan((1090,470),710)
    target.update(status='ready', modules=[dict(id='M1', origin=[0,0,0], size=expected['bounds'])],
                  bounds=expected['bounds'], learning=dict(mode='staged'), geometry_pipeline=dict(mode='plan_only'))
    target.pop('error', None)
    target['modules'][0]['handles']=[o['handle'] for o in target['outlines']]
    return target, expected


def test_ai_selects_measured_unseen_planes_and_full_source_origin(tmp_path):
    p, expected = fixture(tmp_path)
    runtime = FakeRuntime()
    assistant = Assistant(dict(ai_enabled=True), ExperienceLibrary(tmp_path), runtime)
    assert assistant.apply(p)
    assert [m['size'] for m in p['modules']] == [m['size'] for m in expected['modules']]
    assert p['learning']['mode'] == 'local_ai'
    assert p['plan_origin_offset_mm'] == [0,0]
    assert p['plan_origin_basis'] == 'source_plan_envelope'
    assert all(m['handles'] and m['anchor_evidence'] for m in p['modules'])
    assert runtime.calls == 1


def test_candidate_coordinates_include_source_offset_and_curved_profile():
    candidate = dict(id='learned', offset=[18,-9], state=dict(modules=[
        dict(origin=[0,50,0],size=[800,600,1600],plan_profile=dict(schema=1,segments=[dict(type='arc',radius=140)]))]))
    before = deepcopy(candidate)
    part = compact(candidate)['parts'][0]
    assert part['origin']==[18,41] and part['profile']['segments'][0]['radius']==140
    assert candidate==before


def test_rule_and_ai_eligibility_share_one_measurement_when_ai_is_skipped(tmp_path, monkeypatch):
    import plan_learning
    from main import replay_experience
    original = plan_learning.features
    calls = []
    def counted(product):
        calls.append(product['signature'])
        return original(product)
    monkeypatch.setattr(plan_learning, 'features', counted)
    target, _ = plan((1090,470),710)
    before = deepcopy(target)
    memory = ExperienceLibrary(tmp_path)
    assert not replay_experience(target, tmp_path, memory)
    runtime = FakeRuntime()
    assert not Assistant(dict(ai_enabled=True), memory, runtime).apply(target)
    assert len(calls)==1 and runtime.calls==0
    assert target['modules']==before['modules']
    assert target['local_ai']['status']=='skipped'


@pytest.mark.parametrize('answer', [
    dict(decision='choose', candidate_id='invented', reason='bad'),
    dict(decision='choose', candidate_id='none', reason='bad'),
    dict(decision='choose', candidate_id='learned', reason='bad', size=[999,999]),
    dict(decision='choose', candidate_id='learned', reason='x'*181),
    [],
])
def test_invalid_ai_cannot_change_geometry(tmp_path, answer):
    p, _ = fixture(tmp_path)
    before = deepcopy(p)
    assert not Assistant(dict(ai_enabled=True), ExperienceLibrary(tmp_path), FakeRuntime(answer)).apply(p)
    assert {k:v for k,v in p.items() if k!='local_ai'} == before
    assert p['local_ai']['status'] == 'fallback'


def test_timeout_reject_and_baseline_leave_recognizer_intact(tmp_path):
    p, _ = fixture(tmp_path)
    for runtime in [FakeRuntime(error=TimeoutError('test timeout')),
                    FakeRuntime(dict(decision='reject', candidate_id='none', reason='uncertain')),
                    FakeRuntime(dict(decision='choose', candidate_id='baseline', reason='baseline'))]:
        target = deepcopy(p)
        assert not Assistant(dict(ai_enabled=True), ExperienceLibrary(tmp_path), runtime).apply(target)
        assert target['modules'] == p['modules']
        assert target['local_ai']['status'] in ('fallback','reject','choose')


def test_disabled_confirmed_rules_review_full_height_do_not_call_ai(tmp_path):
    p, _ = fixture(tmp_path)
    cases = [(False,'staged',False),(True,'plan_exact',False),(True,'plan_rule',False),
             (True,'user_confirmed',False),(True,'staged',True)]
    for enabled, mode, elevation in cases:
        target=deepcopy(p); target['learning']['mode']=mode;target['build_stages']['elevation']=elevation
        runtime=FakeRuntime()
        assert not Assistant(dict(ai_enabled=enabled), ExperienceLibrary(tmp_path), runtime).apply(target)
        assert runtime.calls == 0 and 'local_ai' not in target


def test_partial_and_conflicting_examples_are_individual_candidates_but_exclusions_apply(tmp_path):
    from plan_search import Samples
    p, s = plan()
    save_example(tmp_path,p,s,eid='001',input_axes_ignored=True,scope=dict(partial_sample=True))
    target,_=plan((1090,470),710)
    runtime=FakeRuntime();memory=ExperienceLibrary(tmp_path)
    Assistant(dict(ai_enabled=True),memory,runtime).apply(target)
    assert runtime.calls==1 and target['local_ai']['selected_samples'][0]['partial']
    save_example(tmp_path,p,s,eid='002',input_axes_ignored=True)
    atomic_json(tmp_path/'experience_exclusions'/'002.json',{})
    assert Samples(tmp_path).refresh().rows[0]['event']['id']=='001'
    p,s=plan((920,610),650);s['modules']=[dict(id='joined',origin=[0,0,0],size=s['bounds'])]
    save_example(tmp_path,p,s,eid='003',input_axes_ignored=True)
    p,s=plan((740,530),560);save_example(tmp_path,p,s,eid='004',input_axes_ignored=True)
    assert len(Samples(tmp_path).refresh().rows)==3
    assert memory.refresh_plan_rules()['active']==0


def test_one_call_budget_per_job_and_acceptance_files_immutable(tmp_path):
    p,_=fixture(tmp_path);runtime=FakeRuntime();assistant=Assistant(dict(ai_enabled=True),ExperienceLibrary(tmp_path),runtime)
    files={f:f.read_bytes() for f in (tmp_path/'experiences').glob('*/*.json')}
    assert assistant.apply(p)
    target,_=fixture(tmp_path)
    assert not assistant.apply(target)
    assert runtime.calls==1 and target['local_ai']['status']=='skipped'
    assert all(f.read_bytes()==data for f,data in files.items())


def test_remote_endpoint_and_missing_config_are_rejected(tmp_path):
    path=tmp_path/'config.json'
    for endpoint in ['http://example.com:11435','https://127.0.0.1:11435','http://u@127.0.0.1:11435',
                     'http://127.0.0.1:11435/path','http://127.0.0.1:11435?x=1']:
        atomic_json(path,dict(endpoint=endpoint))
        with pytest.raises(ValueError):Runtime(path)
    assert status(tmp_path/'missing.json')['ready'] is False


def test_runtime_schema_pin_cache_and_no_model_pull(tmp_path):
    path=tmp_path/'config.json'
    atomic_json(path,dict(endpoint='http://127.0.0.1:11435',qa_root=str(tmp_path),model='test',model_digest='sha'))
    runtime=Runtime(path);calls=[]
    def api(route,payload=None,timeout=3):
        calls.append(route)
        if route=='/api/version':return dict(version='test')
        if route=='/api/tags':return dict(models=[dict(name='test',digest='sha')])
        assert route=='/api/chat' and payload['format']['properties']['candidate_id']['enum']==['learned','none']
        return dict(done=True,done_reason='stop',message=dict(content=json.dumps(FakeRuntime().answer)))
    runtime.api=api
    packet=dict(candidates=[dict(id='learned')])
    first,metrics=runtime.choose(packet);assert not metrics['cached']
    again,metrics=runtime.choose(packet);assert metrics['cached'] and first==again
    assert calls.count('/api/chat')==1 and '/api/pull' not in calls
    runtime.config['model_digest']='changed'
    with pytest.raises(ValueError):runtime.choose(packet)


def test_shared_ai_deadline_and_context_guard_do_not_publish_incomplete_answers(tmp_path):
    config=tmp_path/'config.json'
    atomic_json(config,dict(endpoint='http://127.0.0.1:11435',qa_root=str(tmp_path),model='test',model_digest='sha'))
    runtime=Runtime(config);calls=[]
    def api(route,payload=None,timeout=3):
        calls.append(route)
        if route=='/api/version':return dict(version='test')
        if route=='/api/tags':return dict(models=[dict(name='test',digest='sha')])
        return dict(done=True,done_reason='stop',prompt_eval_count=4000,message=dict(content=json.dumps(FakeRuntime().answer)))
    runtime.api=api;runtime.deadline=time.monotonic()-1
    with pytest.raises(TimeoutError):runtime.choose(dict(candidates=[dict(id='learned')]))
    assert '/api/chat' not in calls
    runtime.deadline=time.monotonic()+60
    with pytest.raises(ValueError,match='Ngữ cảnh'):runtime.choose(dict(candidates=[dict(id='learned')]))
    assert not list((tmp_path/'tests'/'cache').glob('*.json'))
