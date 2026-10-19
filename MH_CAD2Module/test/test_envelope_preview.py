from copy import deepcopy
import json
from pathlib import Path

import pytest

from main import run
from test_learning import save_example
from local_ai import inference_packet


def request(root):
    lines=json.loads((Path(__file__).parent/'fixtures/stepped_plan_edges.json').read_text())
    lines=[l for l in lines if l['handle']!='e23']
    for l in lines:
        for key in ('a','b'):l[key]=[l[key][0]+30000,l[key][1]+40000]
    return dict(action='geometry',library=str(root),geometry=dict(hash='a'*64,lines=lines,plane='XY',plane_offset_mm=73))


def product(packet):return run(packet)['analyses'][0]['products'][0]


def test_failed_plan_builds_only_explicit_source_envelope_for_correction(tmp_path):
    p=product(request(tmp_path))
    assert p['status']=='needs_review' and p['error']
    assert p['envelope_preview']['kind']=='selected_cad_envelope'
    assert p['envelope_preview']['reason']==p['error']
    assert len(p['modules'])==1 and not p['trim_parts'] and not p['panel_parts']
    assert p['modules'][0]['size']==[1040,500,1600]
    assert p['modules'][0]['rule']=='source-envelope-preview-v1'
    assert p['placement']==dict(mode='source_plan',plane='XY',origin_mm=[30000,40000],plane_offset_mm=73)
    assert p['envelope']==[30000,40000,31040,40500]
    assert p['views'][0]['unresolved_bays']
    assert not list((tmp_path/'experiences').glob('*/*.json'))


def test_manual_accepted_boxes_replace_preview_and_replay_at_changed_world_position(tmp_path):
    packet=request(tmp_path);p=product(packet)
    correct=dict(modules=[dict(id='M1',origin=[0,0,0],size=[520,500,1600]),dict(id='M2',origin=[520,0,0],size=[520,500,1600])],
                 trim_parts=[],panel_parts=[],bounds=[1040,500,1600])
    save_example(tmp_path,p,correct,eid='accepted-preview',input_axes_ignored=True)
    for line in packet['geometry']['lines']:
        for key in ('a','b'):line[key][0]+=10000
    rebuilt=product(packet)
    assert rebuilt['status']=='ready' and 'envelope_preview' not in rebuilt
    assert rebuilt['learning']['mode']=='plan_exact'
    assert [m['size'] for m in rebuilt['modules']]==[[520,500,1600]]*2
    assert rebuilt['placement']['origin_mm']==[40000,40000]


def test_bad_source_plane_does_not_invent_a_placeable_preview(tmp_path):
    packet=request(tmp_path);packet['geometry']['plane']='invalid'
    p=product(packet)
    assert 'envelope_preview' not in p and p['status']=='needs_review'


def test_preview_requires_two_nonzero_measured_dimensions(tmp_path):
    packet=request(tmp_path);packet['geometry']['lines']=[dict(a=[0,0],b=[500,0],handle='line')]
    p=product(packet)
    assert 'envelope_preview' not in p and not p['modules']


def test_ai_wire_packet_removes_numeric_noise_and_duplicate_geometry_without_mutation():
    part=dict(kind='modules',origin=[0.0000000001,18.000000001],size=[800.00000000003,598.0000000000001])
    packet=dict(target=dict(size=[1985.00000000002,598.000000000003]),candidates=[dict(id='learned',parts=[part]),dict(id='baseline',parts=[deepcopy(part)])])
    original=deepcopy(packet);wire=inference_packet(packet)
    assert packet==original
    assert wire['target']['size']==[1985,598]
    assert wire['candidates'][0]['parts'][0]['size']==[800,598]
    assert wire['candidates'][1]==dict(id='baseline',same_geometry_as='learned')
