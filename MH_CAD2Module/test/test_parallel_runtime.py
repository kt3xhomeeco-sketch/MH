from copy import deepcopy
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time

import ezdxf
import pytest

from main import run
from parallel_index import ParallelIndex
from test_oy_sweep import cabinet,rectangle
from test_full_plan_scope import L_plan
from directional_layout import polygon
from geometry import overlapping_modules


def source_file(path):
    doc=ezdxf.new('R2018',units=4)
    for index,code in enumerate(('SP01','SP02')):
        shift=index*3000
        block=doc.blocks.new('FRAME'+code)
        block.add_lwpolyline([(-100,-100),(1900,-100),(1900,900),(-100,900)],close=True)
        block.add_attdef('MASP');ref=doc.modelspace().add_blockref(block.name,(shift,0));ref.add_auto_attribs({'MASP':code})
        for line in cabinet():doc.modelspace().add_line([line['a'][0]+shift,line['a'][1]],[line['b'][0]+shift,line['b'][1]])
    doc.saveas(path);return path


def request(path,root,code):return dict(action='analyze',sources=[str(path)],library=str(root),targets=[code],build_elevation=False)


def test_source_is_extracted_once_across_targets_and_algorithm_changes(tmp_path,monkeypatch):
    import main
    path=source_file(tmp_path/'source.dxf');root=tmp_path/'lib';calls=[];original=main.ezdxf.readfile
    def counted(*a,**kw):calls.append(a[0]);return original(*a,**kw)
    monkeypatch.setattr(main.ezdxf,'readfile',counted)
    first=run(request(path,root,'SP01'));second=run(request(path,root,'SP02'))
    assert not first['errors'] and not second['errors']
    assert len(calls)==1
    assert second['analyses'][0]['products'][0]['source_cache']['mode']=='memory'
    monkeypatch.setattr(main,'RECOGNIZER_VERSION',999)
    assert not run(request(path,root,'SP01'))['errors'] and len(calls)==1
    # Same size/mtime edit still changes ctime and the immutable revision hash.
    stat=path.stat();path.write_bytes(path.read_bytes().replace(b'SP02',b'SP03'));os.utime(path,ns=(stat.st_atime_ns,stat.st_mtime_ns))
    changed=run(request(path,root,'SP03'))
    assert not changed['errors'] and len(calls)==2
    assert changed['analyses'][0]['revision']['hash']!=first['analyses'][0]['revision']['hash']
    assert changed['analyses'][0]['products'][0]['code']=='SP03'


def test_disk_source_index_reopens_without_parsing_cad(tmp_path,monkeypatch):
    import main,source_index
    path=source_file(tmp_path/'source.dxf');root=tmp_path/'lib'
    first=run(request(path,root,'SP01'))
    for index in source_index._INDEXES.values():index.db.close()
    source_index._INDEXES.clear()
    def forbidden(*a,**kw):raise AssertionError('CAD parsed again')
    monkeypatch.setattr(main.ezdxf,'readfile',forbidden)
    second=run(request(path,root,'SP02'))
    assert not second['errors']
    assert second['analyses'][0]['products'][0]['source_cache']['mode']=='disk'
    assert first['analyses'][0]['revision']['hash']==second['analyses'][0]['revision']['hash']


def test_corrupt_derived_index_rebuilds_without_losing_archived_source(tmp_path):
    path=source_file(tmp_path/'source.dxf');root=tmp_path/'lib'
    first=run(request(path,root,'SP01'))
    revision=first['analyses'][0]['revision'];stored=Path(revision['stored']);original=stored.read_bytes()
    from source_index import SCHEMA
    database=Path(revision['folder'])/f'geometry-index-v{SCHEMA}.sqlite'
    database.write_bytes(b'corrupt derived cache')
    second=run(request(path,root,'SP02'))
    assert not second['errors']
    assert second['analyses'][0]['products'][0]['source_cache']['mode']=='extracted'
    assert stored.read_bytes()==original and path.read_bytes()==original


def test_resident_exact_feedback_cache_sees_new_samples_and_exclusions(tmp_path):
    from library import atomic_json,VERSION
    packet=dict(action='geometry',library=str(tmp_path),geometry=dict(hash='a'*64,plane='XY',lines=cabinet()))
    baseline=run(packet)['analyses'][0]['products'][0]
    assert len(baseline['modules'])==2
    signature='b'*64
    state=dict(modules=[dict(id='M1',origin=[0,0,0],size=[1618,600,1600])],trim_parts=[],panel_parts=[],bounds=[1618,600,1600])
    event=dict(id='accepted-live',status='accepted',parser_version=VERSION,input_axes_ignored=True,signature=signature,
               analysis=baseline,after=state,plan_origin_offset_mm=[0,0],plan_origin_basis='source_plan_envelope')
    path=tmp_path/'experiences'/signature/'001.json';atomic_json(path,event);before=path.read_bytes()
    accepted=run(packet)['analyses'][0]['products'][0]
    assert len(accepted['modules'])==1 and accepted['learning']['mode']=='plan_exact'
    atomic_json(tmp_path/'experience_exclusions/accepted-live.json',dict(reason='Wrong sample'))
    excluded=run(packet)['analyses'][0]['products'][0]
    assert len(excluded['modules'])==2 and excluded['learning']['mode']=='geometry'
    assert path.read_bytes()==before


def test_parallel_lookup_probes_only_standard_offsets_for_sparse_faces():
    lines=[([i*200,0],[i*200,600],str(i)) for i in range(10000)]
    index=ParallelIndex(lines)
    assert index.panels()==[]
    assert index.probes<=10000*9 and index.pair_checks==0


def test_collinear_fragments_use_interval_lookup_instead_of_cross_product():
    lines=[]
    for i in range(500):
        for row in rectangle([0,i*300,18,i*300+100],str(i)):lines.append((row['a'],row['b'],row['handle']))
    index=ParallelIndex(lines);panels=index.panels()
    assert len(panels)==500 and index.pair_checks<2000


@pytest.mark.parametrize('angle',[0,31,90,121])
def test_L_layout_uses_both_directions_and_keeps_the_empty_corner(tmp_path,angle):
    c,s=math.cos(math.radians(angle)),math.sin(math.radians(angle));lines=[]
    for o in L_plan():
        points=[[30000+c*x-s*y,40000+s*x+c*y] for x,y in o['points']]
        lines += [dict(a=a,b=b,handle=o['handle']) for a,b in zip(points,points[1:])]
    p=run(dict(action='geometry',library=str(tmp_path),geometry=dict(hash='f'*64,lines=lines,plane='XY')))['analyses'][0]['products'][0]
    assert p['status']=='ready' and len(p['modules'])==7,p.get('error')
    assert p['geometry_pipeline']['directional_layout']['all_straight_panels_covered']
    assert not overlapping_modules(p['modules'])
    area=0
    for part in p['modules']:
        points=polygon(part)
        area+=abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(points,points[1:]+points[:1])))/2
    assert area==pytest.approx(2990000,abs=2)


def test_oblique_cabinet_profiles_preserve_real_18_spacing_without_false_aabb_overlap(tmp_path):
    c,s=math.cos(.54),math.sin(.54);lines=deepcopy(cabinet())
    for line in lines:
        for key in ('a','b'):
            x,y=line[key];line[key]=[10000+c*x-s*y,20000+s*x+c*y]
    p=run(dict(action='geometry',library=str(tmp_path),geometry=dict(hash='e'*64,lines=lines,plane='XY')))['analyses'][0]['products'][0]
    assert p['status']=='ready' and len(p['modules'])==2
    assert all(m['plan_profile'] for m in p['modules'])
    assert not overlapping_modules(p['modules'])
    bad=deepcopy(p['modules']);bad[1]=deepcopy(bad[0]);bad[1]['id']='overlap'
    assert overlapping_modules(bad)


def test_resident_reuses_pid_and_raw_source_and_recovers_after_bad_job(tmp_path):
    path=source_file(tmp_path/'source.dxf');queue=tmp_path/'jobs/.resident-test/queue';queue.mkdir(parents=True)
    worker=Path(__file__).resolve().parents[1]/'worker/resident.py'
    options={'creationflags':getattr(subprocess,'CREATE_NO_WINDOW',0)}
    process=subprocess.Popen([sys.executable,str(worker),'--queue',str(queue),'--parent',str(os.getpid())],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,**options)
    def submit(number,values):
        folder=tmp_path/'jobs'/str(number);folder.mkdir();req=folder/'request.json';response=folder/'response.json'
        req.write_text(json.dumps(values),encoding='utf8')
        (queue/f'{number}.json').write_text(json.dumps(dict(request=str(req),response=str(response))),encoding='utf8')
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            assert process.poll() is None,'Resident stopped'
            if response.exists():return json.loads(response.read_text(encoding='utf8'))
            time.sleep(.02)
        raise AssertionError('Resident did not respond')
    try:
        first=submit(1,request(path,tmp_path,'SP01'));second=submit(2,request(path,tmp_path,'SP02'))
        assert first['ok'] and second['ok']
        assert first['worker']['pid']==second['worker']['pid']==process.pid
        assert second['worker']['job_number']==2
        assert second['analyses'][0]['products'][0]['source_cache']['mode']=='memory'
        failed=submit(3,dict(action='geometry',library=str(tmp_path),geometry={}))
        assert not failed['ok']
        fourth=submit(4,request(path,tmp_path,'SP01'))
        assert fourth['ok'] and fourth['worker']['pid']==process.pid
    finally:
        process.terminate();process.wait(timeout=10)
