import json
from copy import deepcopy
from pathlib import Path

from library import VERSION, atomic_json
from main import run


def request(tmp_path, kind):
    lines = json.loads((Path(__file__).parent / 'fixtures' / f'plan_feedback_{kind}.json').read_text())
    return dict(action='geometry', library=str(tmp_path), geometry=dict(hash='a' * 64, lines=lines))


def product(packet):
    return run(packet)['analyses'][0]['products'][0]


def save_feedback(tmp_path, source, identity):
    state = dict(modules=[dict(id='M1', origin=[36, 0, 0], size=[1238, 600, 1600])],
                 trim_parts=[dict(id='T1', origin=[0, 0, 0], size=[36, 600, 1600], solid_proxy=True),
                             dict(id='T2', origin=[1274, 0, 0], size=[36, 600, 1600], solid_proxy=True)],
                 panel_parts=[], bounds=[1310, 600, 1600])
    event = dict(id=identity, status='accepted', parser_version=VERSION, signature=source['signature'],
                 input_axes_ignored=True, analysis=deepcopy(source), after=state, plan_origin_offset_mm=[-18, -9])
    atomic_json(tmp_path / 'experiences' / source['signature'] / f'{identity}.json', event)


def test_real_single_bay_rebuild_uses_accepted_boxes_after_geometry_recognition(tmp_path):
    packet = request(tmp_path, 'single')
    original = product(packet)
    assert original['modules'][0]['size'] == [1238, 600, 1600]
    save_feedback(tmp_path, original, 'correct-source')
    # A fresh scan has a different code/hash/handle set and translated coordinates.
    changed = deepcopy(packet)
    changed['geometry']['hash'] = 'b' * 64
    for i, line in enumerate(changed['geometry']['lines']):
        line['handle'] = f'new-{i}'
        for key in ('a', 'b'):
            line[key] = [line[key][0] + 5000, line[key][1] - 3000]
    rebuilt = product(changed)
    assert rebuilt['signature'] == original['signature']
    assert rebuilt['learning']['mode'] == 'plan_exact'
    assert rebuilt['modules'][0]['origin'] == [36, 0, 0]
    assert rebuilt['modules'][0]['size'] == [1238, 600, 1600]
    assert len(rebuilt['trim_parts']) == 2
    assert rebuilt['bounds'] == [1310, 600, 1600]
    assert rebuilt['plan_origin_offset_mm'] == [-18, -9]  # Explicit accepted offset is already source-based.
    assert rebuilt['placement']['origin_mm'] == [original['source_plan_envelope'][0]+5000-18, original['source_plan_envelope'][1]-3000-9]


def test_misbound_two_bay_sample_does_not_train_single_bay_or_silently_override_source(tmp_path):
    source = product(request(tmp_path, 'two_bays'))
    # Circular ends (100 mm left / 500 mm right) are now included from CAD.
    assert source['bounds'][0] == 2800
    assert sum('plan_profile' in m for m in source['modules']) == 2
    save_feedback(tmp_path, source, 'wrong-source')
    target = product(request(tmp_path, 'single'))
    assert source['signature'] != target['signature']
    assert target['learning']['mode'] == 'geometry'
    same_source = product(request(tmp_path, 'two_bays'))
    assert same_source['status'] == 'needs_review'
    assert same_source['learning']['issues'][0]['code'] == 'source_binding_mismatch'
    atomic_json(tmp_path/'experience_exclusions'/'wrong-source.json',dict(reason='relinked_to_correct_source'))
    assert product(request(tmp_path, 'two_bays'))['learning']['mode']=='geometry'
