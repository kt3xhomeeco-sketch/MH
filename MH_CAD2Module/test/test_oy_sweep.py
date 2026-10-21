from copy import deepcopy
import json
import random
from pathlib import Path

import ezdxf
import pytest

from main import run
from oy_sweep import plates, bays, ENGINE
from plan_reader import raw_signature
from library import atomic_json, VERSION


def rectangle(box,prefix):
    x,y,u,v=box;points=[[x,y],[u,y],[u,v],[x,v],[x,y]]
    return [dict(a=a,b=b,handle=f'{prefix}-{i}',layer='0') for i,(a,b) in enumerate(zip(points,points[1:]))]


def cabinet(double=True,stock=18):
    walls=[[0,0,stock,600],[800,0,800+(2*stock if double else stock),600],
           [1600,0,1600+stock,600]]
    if double:walls[1:2]=[[800,0,800+stock,600],[800+stock,0,800+2*stock,600]]
    boxes=walls+[[stock,600-stock,800,600],[800+(2*stock if double else stock),600-stock,1600,600]]
    return [line for i,box in enumerate(boxes) for line in rectangle(box,str(i))]


def outlines(lines):return [dict(handle=l['handle'],points=[l['a'],l['b']],layer=l.get('layer','0')) for l in lines]


def scan(tmp_path,lines,**values):
    packet=dict(action='geometry',library=str(tmp_path),ai_enabled=True,
                geometry=dict(hash='e'*64,lines=lines,plane='XY',plane_offset_mm=73))
    packet.update(values)
    return run(packet)['analyses'][0]['products'][0]


def test_double_18_shared_face_splits_modules_but_outer_pair_is_auxiliary(tmp_path):
    lines=cabinet()+rectangle([-18,0,0,600],'trim')
    p=scan(tmp_path,lines)
    assert p['status']=='ready',p.get('error')
    assert [m['size'] for m in p['modules']]==[[818,600,1600],[800,600,1600]]
    assert p['trim_parts'][0]['size']==[18,600,1600]
    seams=p['geometry_pipeline']['oy_sweep']['joins']
    assert next(s for s in seams if s['x']==818)['role']=='module_boundary'
    assert next(s for s in seams if s['x']==0)['role']=='outer_plate_or_auxiliary'
    assert p['local_ai']['status']=='not_used'


def test_one_shared_plate_stays_inside_one_module(tmp_path):
    p=scan(tmp_path,cabinet(double=False))
    assert [m['size'] for m in p['modules']]==[[1618,600,1600]]
    assert not p['geometry_pipeline']['oy_sweep']['joins']


def test_unseamed_36_plate_is_not_invented_as_two_18_plates(tmp_path):
    p=scan(tmp_path,cabinet(double=False,stock=36))
    assert [m['size'] for m in p['modules']]==[[1636,600,1600]]
    assert not p['geometry_pipeline']['oy_sweep']['joins']


@pytest.mark.parametrize('stock',[3,6,8,9,12,15,18,25,36,17.94])
def test_all_stock_faces_are_measured_without_forcing_dimensions(tmp_path,stock):
    lines=rectangle([0,0,stock,600],'a')+rectangle([800-stock,0,800,600],'b')+rectangle([stock,600-stock,800-stock,600],'c')
    p=scan(tmp_path,lines)
    assert p['status']=='ready',p.get('error')
    assert p['modules'][0]['size']==[800,600,1600]
    assert p['geometry_pipeline']['oy_sweep']['walls'][0]['stock_mm']==pytest.approx(stock,abs=.001)


def test_different_stock_distance_and_unclosed_gaps_are_not_boards():
    lines=rectangle([0,0,24,600],'bad')
    rects,_=plates(outlines(lines))
    assert not rects
    lines=[dict(a=[0,0],b=[0,600],handle='a'),dict(a=[18,0],b=[18,600],handle='b')]
    assert not plates(outlines(lines))[0]


def test_shallow_36mm_sides_and_measured_double_18_tolerance(tmp_path):
    lines=rectangle([0,0,36,120],'a')+rectangle([764,0,800,120],'b')+rectangle([36,84,764,120],'c')
    assert scan(tmp_path,lines)['modules'][0]['size']==[800,120,1600]
    p=scan(tmp_path,cabinet(stock=17.94))
    assert [m['size'] for m in p['modules']]==[[817.94,600,1600],[800,600,1600]]


def test_anchor_advances_after_large_gap():
    lines=rectangle([0,0,18,600],'a')+rectangle([800,0,818,600],'b')
    rects,_=plates(outlines(lines))
    assert [r.box() for r in rects if r.h>=100]==[[0,0,18,600],[800,0,818,600]]


def test_equal_length_without_equal_y_span_does_not_form_a_module(tmp_path):
    lines=rectangle([0,0,18,600],'a')+rectangle([800,1000,818,1600],'b')
    p=scan(tmp_path,lines)
    assert p['status']=='needs_review' and p['envelope_preview']
    assert not bays(plates(outlines(lines))[0],outlines(lines))[0]


def test_short_internal_panel_does_not_split_a_deeper_module(tmp_path):
    lines=rectangle([0,0,18,600],'a')+rectangle([782,0,800,600],'b')+rectangle([18,582,782,600],'back')+rectangle([400,0,418,550],'inside')
    p=scan(tmp_path,lines)
    assert [m['size'] for m in p['modules']]==[[800,600,1600]]


def test_reversed_segmented_translated_lines_keep_the_same_split(tmp_path):
    source=cabinet();parts=[]
    for line in source:
        a,b=line['a'],line['b'];mid=[(a[i]+b[i])/2 for i in (0,1)]
        for j,(x,y) in enumerate(((a,mid),(mid,b))):
            parts.append(dict(a=[y[0]+100000,y[1]-3000],b=[x[0]+100000,x[1]-3000],handle=f"{line['handle']}-{j}"))
    random.Random(7).shuffle(parts)
    p=scan(tmp_path,parts)
    assert [m['size'] for m in p['modules']]==[[818,600,1600],[800,600,1600]]
    assert p['placement']['origin_mm']==[100000,-3000]


def test_normal_plan_cannot_call_archived_matcher_rules_or_ai(tmp_path,monkeypatch):
    import main, views, local_ai, plan_learning
    def forbidden(*_args,**_kwargs):raise AssertionError('Archived path was invoked')
    for target,name in [(main,'line_rectangles'),(main,'infer_views'),(main,'replay_experience'),
                        (views,'plan_columns'),(local_ai,'Runtime'),(plan_learning.PlanRuleLibrary,'refresh')]:
        monkeypatch.setattr(target,name,forbidden)
    assert scan(tmp_path,cabinet())['status']=='ready'


def test_dxf_path_uses_the_same_sweep_without_old_rectangle_recovery(tmp_path,monkeypatch):
    import main, local_ai
    def forbidden(*_args,**_kwargs):raise AssertionError('Archived path was invoked')
    monkeypatch.setattr(main,'line_rectangles',forbidden);monkeypatch.setattr(local_ai,'Runtime',forbidden)
    doc=ezdxf.new('R2018',units=4);frame=doc.blocks.new('FRAME')
    frame.add_lwpolyline([[-100,-100],[2000,-100],[2000,900],[-100,900]],close=True)
    frame.add_attdef('MASP',insert=(0,-80),text='SP01');ref=doc.modelspace().add_blockref('FRAME',(0,0));ref.add_auto_attribs({'MASP':'SP01'})
    for l in cabinet():doc.modelspace().add_line(l['a'],l['b'])
    source=tmp_path/'source.dxf';doc.saveas(source)
    p=run(dict(action='analyze',sources=[str(source)],library=str(tmp_path/'lib'),ai_enabled=True))['analyses'][0]['products'][0]
    assert p['status']=='ready' and p['plan_engine']==ENGINE
    assert [m['size'] for m in p['modules']]==[[818,600,1600],[800,600,1600]]


def test_legacy_accepted_edges_replay_exactly_but_nearby_geometry_does_not(tmp_path):
    lines=cabinet();p=scan(tmp_path,lines);legacy=deepcopy(p);legacy.pop('plan_engine');legacy.pop('plan_origin_basis')
    signature='a'*64
    state=dict(modules=[dict(id='M1',origin=[0,0,0],size=[1618,600,1600])],trim_parts=[],panel_parts=[],bounds=[1618,600,1600])
    e=dict(id='old-accepted',status='accepted',parser_version=VERSION,signature=signature,input_axes_ignored=True,
           analysis=legacy,after=state,plan_origin_offset_mm=[0,0],plan_origin_basis='source_plan_envelope')
    atomic_json(tmp_path/'experiences'/signature/'0001.json',e)
    original=(tmp_path/'experiences'/signature/'0001.json').read_bytes()
    replay=scan(tmp_path,lines)
    assert len(replay['modules'])==1 and replay['learning']['mode']=='plan_exact'
    moved=deepcopy(lines)
    for l in moved:
        for k in ('a','b'):l[k]=[l[k][0]+30000,l[k][1]+40000]
    translated=scan(tmp_path,moved)
    assert translated['learning']['mode']=='plan_exact' and translated['placement']['origin_mm']==[30000,40000]
    changed=deepcopy(lines)
    for l in changed:
        for k in ('a','b'):
            if l[k][0]>=1600:l[k][0]+=10
    assert raw_signature(outlines(changed))!=raw_signature(outlines(lines))
    assert scan(tmp_path,changed)['learning']['mode']=='geometry'
    assert (tmp_path/'experiences'/signature/'0001.json').read_bytes()==original


def test_phase_times_are_recorded_without_being_added_together_twice(tmp_path):
    p=scan(tmp_path,cabinet());times=p['processing_times']
    assert {'stock_scan','depth_and_seams','footprints_arcs_trims','evidence','exact_feedback','total_plan'}<=times.keys()
    assert all(v>=0 for v in times.values())
    assert times['total_plan']>=max(v for k,v in times.items() if k!='total_plan')
