import json
from pathlib import Path

from geometry import overlapping_modules
from stages import plan_runs
from test_plan_feedback import product, request as previous_request, save_feedback


def packet(tmp_path):
    lines=json.loads((Path(__file__).parent/'fixtures/sp40_plan_edges.json').read_text())
    return dict(action='geometry',library=str(tmp_path),geometry=dict(hash='c'*64,lines=lines))


def test_sp40_scan_needs_no_code_and_retains_three_nonoverlapping_bays(tmp_path):
    first=product(packet(tmp_path))
    second=product(packet(tmp_path))
    named=product(dict(packet(tmp_path),code='SP40'))
    assert first['status']=='ready',first.get('error')
    assert [m['size'] for m in first['modules']]==[[1072,170,1600],[300,170,1600],[982,170,1600]]
    assert [m['origin'] for m in first['modules']]==[[18,0,0],[1090,0,0],[1390,0,0]]
    assert len(first['trim_parts'])==2
    assert sorted(t['origin'] for t in first['trim_parts'])==[[0,0,0],[2372,0,0]]
    assert all(t['size']==[18,170,1600] for t in first['trim_parts'])
    assert all(t['solid_proxy'] is True for t in first['trim_parts'])
    assert not overlapping_modules(first['modules']+first['trim_parts'])
    assert first['bounds']==[2390,170,1600]
    assert first['code']!=second['code']
    assert first['signature']==second['signature']==named['signature']
    assert first['modules']==named['modules']


def test_sp40_does_not_reuse_a_previous_scan_feedback_by_name(tmp_path):
    previous=product(previous_request(tmp_path,'single'))
    save_feedback(tmp_path,previous,'previous-scan')
    current=product(packet(tmp_path))
    assert current['signature']!=previous['signature']
    assert current['learning']['mode']=='geometry'
    assert len(current['modules'])==3
    assert 'experience' not in current


def test_overlapping_candidate_cannot_interrupt_a_valid_plan_run():
    def bay(x0,x1):return dict(box=[x0,0,x1,170])
    bays=[bay(18,1090),bay(1090,1390),bay(1372,2390),bay(1390,2372)]
    best=max(plan_runs(bays),key=lambda run:sum(b['box'][2]-b['box'][0] for b in run))
    assert [b['box'][0:3:2] for b in best]==[[18,1090],[1090,1390],[1390,2372]]
