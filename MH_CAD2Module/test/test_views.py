import json
from pathlib import Path

import ezdxf
import pytest

from geometry import Rect
from main import analyse_source, read_geometry, title_center
from library import library_root
from test_geometry import complete_cabinet
from materials import stock_evidence
from views import recognise_ordered, split_views, geometry_roles


def outlined(rects):
    return [{'handle':r.handle,'points':[[r.x0,r.y0],[r.x1,r.y0],[r.x1,r.y1],[r.x0,r.y1],[r.x0,r.y0]]} for r in rects]


def simple_views():
    plan=[Rect(0,0,18,600,'pl'),Rect(782,0,800,600,'pr'),Rect(18,582,782,600,'pb')]
    front=[]
    for y,h in ((2000,1000),(3000,400)):
        front += [Rect(2000,y,2018,y+h,f'fl{y}'),Rect(2782,y,2800,y+h,f'fr{y}'),
                  Rect(2018,y,2782,y+18,f'fb{y}'),Rect(2018,y+h-18,2782,y+h,f'ft{y}')]
    section=[Rect(4000,2982,4600,3000,'st'),Rect(4000,3000,4600,3018,'sb')]
    return [{'id':key,'role':role,'title':role,'rects':rs,'outlines':outlined(rs),'region':[0,0,10000,10000]}
            for key,role,rs in [('P','plan',plan),('F','front_open',front),('S','section_vertical',section)]]


def test_leaders_and_anonymous_callouts_removed_but_actual_sections_and_furniture_remain():
    doc=ezdxf.new()
    block=doc.blocks.new('*U9990')
    block.add_circle((0,0),20)
    block.add_line((-1000,0),(1000,0))
    for tag in ('1','2','4','5'):block.add_attdef(tag)
    marker=doc.modelspace().add_blockref(block.name,(0,0))
    marker.add_auto_attribs({'1':'1','2':'1','4':'3','5':'3'})
    furniture=doc.blocks.new('*U9991')
    furniture.add_lwpolyline([(0,0),(18,0),(18,2200),(0,2200)],close=True)
    doc.modelspace().add_blockref(furniture.name,(4000,0))
    real_section=doc.blocks.new('MAT CAT ACTUAL GEOMETRY')
    real_section.add_lwpolyline([(0,0),(600,0),(600,18),(0,18)],close=True)
    doc.modelspace().add_blockref(real_section.name,(6000,0))
    leader=doc.modelspace().add_leader([(0,0),(50000,50000)])
    annotations=[]
    rects,outlines,_=read_geometry(doc,1,set(),annotations)
    assert len(rects)==2 and len(outlines)==2
    assert not any(marker.dxf.handle in o['handle'] or leader.dxf.handle in o['handle'] for o in outlines)
    assert annotations[0]['numbers']==['3'] and annotations[0]['axis']=='horizontal'


def test_horizontal_section_symbol_can_be_on_previous_sheet():
    annotations=[{'kind':'view_title','text':'MẶT ĐỨNG','point':[1000,1000],'center_x':1500,'handle':'T1'},
                 {'kind':'view_title','text':'MẶT CẮT 3-3','point':[12000,1000],'center_x':12500,'handle':'T2'},
                 {'kind':'section_marker','point':[1500,4000],'axis':'horizontal','numbers':['3'],'handle':'M'}]
    views=split_views([[0,0,10000,8000],[10000,0,20000,8000]],annotations,[],[])
    assert [v['role'] for v in views]==['front_check','plan']


def test_plan_precedes_tiers_and_closed_front_cannot_add_drawer_modules():
    views=simple_views()
    # A drawer in the front cannot create a vertical bay missing from the plan.
    drawer=[Rect(2100,2100,2118,2400,'dl'),Rect(2382,2100,2400,2400,'dr'),Rect(2118,2100,2382,2118,'db')]
    views[1]['rects']+=drawer;views[1]['outlines']+=outlined(drawer)
    pipeline={};result=recognise_ordered(views,pipeline)
    assert [m['size'] for m in result['modules']]==[[800,600,1000],[800,600,400]]
    assert len(pipeline['vertical']['columns'])==1
    check={'id':'C','role':'front_check','rects':drawer,'outlines':outlined(drawer)}
    changed=recognise_ordered(views+[check],{})
    assert changed['modules']==result['modules']
    views[0]['rects'][1]=Rect(882,0,900,600,'changed-plan-wall')
    views[0]['rects'][2]=Rect(18,582,882,600,'changed-plan-back')
    with pytest.raises(ValueError,match='mặt bằng'):
        recognise_ordered(views,{})


def real_sp01_views():
    views=json.loads((Path(__file__).parent/'fixtures/sp01_views.json').read_text(encoding='utf8'))
    for v in views:v['rects']=[Rect(*r['box'],r['handle'],r['layer']) for r in v.pop('rectangles')]
    return views


def test_actual_sp01_plan_bays_then_tiers_and_confirmed_exterior_trim():
    pipeline={};result=recognise_ordered(real_sp01_views(),pipeline)
    assert len(pipeline['vertical']['columns'])==2
    assert [m['size'] for m in result['modules']]==[[729,600,2200],[1502,600,2150],[681,600,443],[1502,600,443]]
    assert result['modules'][2]['origin']==[24,0,2200]
    assert all(m['scope']=='carcass_and_doors' for m in result['modules'])
    assert result['modules'][2]['carcass_size']==[681,582,443]
    assert result['modules'][1]['carcass_size']==[1502,582,2150]
    assert result['bounds']==[2255,600,2643]
    assert len(result['trim_parts'])==3
    assert result['trim_parts'][0]['face_width_mm']==24
    assert result['trim_parts'][0]['stock_thickness_mm']==18
    assert result['modules'][2]['joint_evidence']['section_handles']==['/DF628','/DF5E0']
    assert result['modules'][3]['joint_evidence']['section_handles']==['/DF60F','/DF5FD']
    auxiliary=result['trim_parts'][1:]
    assert [p['owner_module_id'] for p in auxiliary]==['M03','M03']
    assert [p['origin'] for p in auxiliary]==[[0,0,2200],[705,0,2200]]
    assert [p['size'] for p in auxiliary]==[[24,18,443],[24,18,443]]
    assert result['modules'][2]['auxiliary_part_ids']==[p['id'] for p in auxiliary]
    assert set(result['modules'][2]['depth_evidence']['handles'])=={'/DF5D6','/DF5E0','/DF5E1','/DF5DE'}


@pytest.mark.parametrize('handles', [('/DF65A',),('/DF65B',),('/DF5E1',)])
def test_two_side_trims_require_closed_inner_carcass_and_section_depth(handles):
    views=real_sp01_views()
    for view in views:
        view['rects']=[r for r in view['rects'] if r.handle not in handles]
        view['outlines']=[o for o in view['outlines'] if o['handle'] not in handles]
    with pytest.raises(ValueError,match='nẹp|Nẹp'):
        recognise_ordered(views,{})


def test_24_face_width_without_plan_stock_witness_is_not_silently_deleted():
    views=real_sp01_views()
    views[0]['rects']=[r for r in views[0]['rects'] if r.handle!='/DF5BD']
    with pytest.raises(ValueError,match='24 mm'):
        recognise_ordered(views,{})


def test_stock_prior_preserves_measurement_and_does_not_make_36_a_division():
    assert stock_evidence(24)['stock_mm'] is None
    assert stock_evidence(18.02)['measured_mm']==18.02
    assert stock_evidence(36)['lamination_candidate']==[18,18]


def test_mtext_wrapping_box_does_not_move_title_to_another_view():
    doc=ezdxf.new();a=doc.modelspace().add_mtext('MẶT CẮT 1-1',dxfattribs={'insert':(180000,73000),'char_height':90,'width':13778})
    centre=title_center(a);a.dxf.width=500
    assert title_center(a)==centre and 180000<centre<181000


def test_geometry_corrects_mislabelled_front_and_retains_actual_sections():
    for name in ('sp01','sp04'):
        views=json.loads((Path(__file__).parent/f'fixtures/{name}_views.json').read_text(encoding='utf8'))
        for v in views:
            v['rects']=[Rect(*r['box'],r['handle'],r['layer']) for r in v.pop('rectangles')]
            v['expected_role']=v['role']
            if v['role']=='front_open':v['role']='front_check'
            elif v['role']=='front_check':v['role']='front_open'
        result=geometry_roles(views)
        assert [v['role'] for v in result]==[v['expected_role'] for v in views]


def test_target_cache_cannot_hide_other_products_from_full_scan(tmp_path):
    doc=ezdxf.new(units=4)
    frame=doc.blocks.new('FRAME')
    frame.add_lwpolyline([(0,0),(10000,0),(10000,8000),(0,8000)],close=True)
    frame.add_attdef('MASP',insert=(9000,100))
    for i,code in enumerate(('SP01','SP02')):
        x=i*12000
        block=doc.modelspace().add_blockref('FRAME',(x,0))
        block.add_auto_attribs({'MASP':code})
        for r in complete_cabinet():
            doc.modelspace().add_lwpolyline([(r.x0+x,r.y0),(r.x1+x,r.y0),(r.x1+x,r.y1),(r.x0+x,r.y1)],close=True)
    source=tmp_path/'two.dxf';doc.saveas(source);root=library_root(str(tmp_path/'lib'))
    one=analyse_source(str(source),root,targets=['SP1'])
    two=analyse_source(str(source),root,targets=['SP02'])
    full=analyse_source(str(source),root)
    assert [p['code'] for p in one['products']]==['SP01']
    assert [p['code'] for p in two['products']]==['SP02']
    assert {p['code'] for p in full['products']}=={'SP01','SP02'}
    assert all(p['status']=='ready' for p in full['products'])
