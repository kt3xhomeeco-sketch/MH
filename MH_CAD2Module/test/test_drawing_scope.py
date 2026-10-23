from copy import deepcopy
import json
import math
from pathlib import Path

import ezdxf
import pytest

from drawing_scope import choose_product_plan, features
from main import read_geometry, run
from plan_reference import prepare_reference
from test_oy_sweep import cabinet


def rect(x,y,w,h,handle,layer='panel'):
    return dict(handle=handle,layer=layer,points=[[x,y],[x+w,y],[x+w,y+h],[x,y+h],[x,y]])


def drawing(axis='horizontal',plan_width=1618):
    plan=[dict(handle=l['handle'],points=[[p[0],p[1]+200] for p in (l['a'],l['b'])]) for l in cabinet()]
    if plan_width!=1618:
        for row in plan:
            for p in row['points']:p[0]*=plan_width/1618
    front=[rect(4000,200,18,2400,'FL'),rect(5600,200,18,2400,'FR'),
           rect(4018,200,1582,18,'FB'),rect(4018,2582,1582,18,'FT')]
    notes=[dict(kind='view_title',text='MẶT CẮT 2-2',point=[700,0],center_x=809,handle='TP'),
           dict(kind='view_title',text='MẶT ĐỨNG',point=[4700,0],center_x=4809,handle='TF'),
           dict(kind='section_marker',point=[4800,1200],axis=axis,numbers=['2'],handle='CUT')]
    return dict(code='SP01',outlines=plan+front,regions=[[-100,-100,10000,5000]]),notes


def test_same_section_title_never_determines_cut_orientation():
    p,notes=drawing();selected=choose_product_plan(p,notes)
    assert selected and p['view_analysis']['status']=='selected'
    cut=p['view_analysis']['candidates'][0]['section_links'][0]
    assert cut['axis']=='horizontal' and cut['dimension_check']['exact_width']
    p,notes=drawing('vertical');assert choose_product_plan(p,notes) is None
    candidate=p['view_analysis']['candidates'][0]
    assert candidate['role']=='section_vertical' and not candidate['can_confirm']
    assert candidate['section_links'][0]['dimension_check']['passed'] is False


def test_wrong_width_cannot_borrow_a_cut_from_an_unrelated_elevation():
    p,notes=drawing()
    for row in p['outlines']:
        if row['handle']=='FR':
            row['points']=[[x+200,y] for x,y in row['points']]
    assert choose_product_plan(p,notes) is None
    assert p['view_analysis']['candidates'][0]['role']=='plan_candidate'


def test_marker_outside_this_product_cannot_link_a_section():
    p,notes=drawing();notes[-1]['point']=[4800,12000]
    assert choose_product_plan(p,notes) is None
    assert p['view_analysis']['candidates'][0]['section_links']==[]


def test_geometry_and_context_separate_wall_and_staircase_from_product():
    p,notes=drawing()
    p['outlines'].append(rect(-20,1000,200,2400,'wall','A_WALL'))
    stairs=[dict(handle=f'S{i}',layer='STAIR',points=[[7000,200+i*200],[8000,200+i*200]]) for i in range(7)]
    stairs.append(dict(handle='diagonal',layer='STAIR',points=[[7000,200],[8000,1400]]))
    p['outlines']+=stairs
    notes.append(dict(kind='view_title',text='MẶT CẮT 5-5',point=[7400,0],center_x=7500,handle='TS'))
    selected=choose_product_plan(p,notes)
    assert selected and all(o['handle']!='wall' and not o['handle'].startswith('S') for o in selected['outlines'])
    assert any(o['kind']=='wall' for o in p['view_analysis']['excluded_context'])
    stair=next(c for c in p['view_analysis']['candidates'] if c['kind']=='stairs')
    assert not stair['can_confirm']
    with pytest.raises(ValueError,match='hợp lệ'):
        choose_product_plan(p,notes,dict(view_id=stair['id'],signature=stair['signature']))


def test_wall_layer_alone_does_not_delete_a_real_18mm_panel():
    p,notes=drawing()
    for row in p['outlines']:row['layer']='TUONG'
    selected=choose_product_plan(p,notes)
    assert selected and selected['features']['kind']=='furniture'


def test_multiple_horizontal_cuts_require_explicit_geometry_bound_choice():
    p,notes=drawing()
    extra=[dict(o,handle='X'+o['handle'],points=[[x,y+4000] for x,y in o['points']]) for o in p['outlines'] if o['handle'] not in ('FL','FR','FB','FT')]
    extra.append(rect(18,4582,1582,18,'new_shelf'))
    p['outlines']+=extra;p['regions'][0][3]=8000
    notes.append(dict(kind='view_title',text='MẶT CẮT 3-3',point=[700,3900],center_x=809,handle='TX'))
    notes.append(dict(notes[-2],kind='section_marker',point=[4800,1400],axis='horizontal',numbers=['3'],handle='CUT3'))
    assert choose_product_plan(p,notes) is None
    candidates=[c for c in p['view_analysis']['candidates'] if c['role']=='plan']
    assert len(candidates)==2
    c=candidates[0];choice=dict(view_id=c['id'],signature=c['signature'])
    assert choose_product_plan(p,notes,choice)['id']==c['id']
    with pytest.raises(ValueError,match='đã đổi'):
        choose_product_plan(p,notes,dict(choice,signature='stale'))


def test_untitled_product_views_can_be_cross_checked_from_stock_geometry():
    p,_=drawing();selected=choose_product_plan(p,[])
    assert selected and selected['features']['height_mm']==600
    assert p['view_analysis']['candidates'][0]['elevation_checks']


def test_exploded_axis_marker_uses_cut_line_not_text_bbox():
    doc=ezdxf.new();b=doc.blocks.new('SECTION MARK')
    b.add_line((-500,0),(500,0));b.add_circle((0,0),5000)
    for tag in ('1','2','4','5'):b.add_attdef(tag)
    ref=doc.modelspace().add_blockref(b.name,(4800,1200))
    ref.add_auto_attribs({'1':'1','2':'1','4':'2','5':'2'})
    notes=[];_,rows,_=read_geometry(doc,1,set(),notes,recover_panels=False)
    assert rows==[] and notes[0]['axis']=='horizontal'
    assert list(notes[0]['cut_line'])==[[4300,1200],[5300,1200]]


@pytest.mark.parametrize('rotation,expected',[(90,'vertical'),(45,'oblique')])
def test_rotated_cut_retains_its_identifier_but_uses_world_direction(rotation,expected):
    doc=ezdxf.new();b=doc.blocks.new('SECTION MARK');b.add_line((-500,0),(500,0))
    for tag in ('1','2','4','5'):b.add_attdef(tag)
    ref=doc.modelspace().add_blockref(b.name,(0,0),dxfattribs={'rotation':rotation})
    ref.add_auto_attribs({'1':'9','2':'9','4':'2','5':'2'})
    notes=[];read_geometry(doc,1,set(),notes,recover_panels=False)
    assert notes[0]['numbers']==['2'] and notes[0]['axis']==expected


def test_shared_title_block_requires_product_specific_confirmation():
    p,notes=drawing();p['shared_frame_codes']=['SP01','SP02']
    assert choose_product_plan(p,notes) is None
    candidate=next(c for c in p['view_analysis']['candidates'] if c['can_confirm'])
    assert choose_product_plan(p,notes,dict(view_id=candidate['id'],signature=candidate['signature']))


def test_one_valid_plan_must_not_silently_drop_another_elevation_family():
    p,notes=drawing()
    p['outlines'] += [rect(7000,200,18,600,'L2'),rect(8982,200,18,600,'R2'),rect(7018,200,1964,18,'B2')]
    notes.append(dict(kind='view_title',text='MẶT ĐỨNG',point=[7800,0],center_x=8000,handle='TF2'))
    assert choose_product_plan(p,notes) is None
    assert p['view_analysis']['multiple_elevation_sizes']


def test_nested_block_context_and_layer_inheritance_are_preserved():
    doc=ezdxf.new();block=doc.blocks.new('TUONG_BAO')
    block.add_lwpolyline([(0,0),(200,0),(200,2400),(0,2400)],close=True)
    doc.modelspace().add_blockref(block.name,(0,0),dxfattribs={'layer':'A_WALL'})
    _,rows,_=read_geometry(doc,1,set(),recover_panels=False)
    assert rows[0]['block_names']==['TUONG_BAO'] and rows[0]['layer']=='A_WALL'


def test_reference_keeps_analytic_arcs_and_corrected_source_origin():
    points=[[100+50*math.cos(t),200+50*math.sin(t)] for t in [i*math.pi/24 for i in range(13)]]
    p=dict(status='ready',envelope=[100,200,150,250],source_plan_envelope=[100,200,150,250],plan_origin_offset_mm=[3,6],
           outlines=[dict(handle='arc',points=points)],view_analysis=dict(selected_view_id='V1'))
    prepare_reference(p)
    data=p['plan_reference'];assert data['source_origin_mm']==[103,206]
    assert len(data['segments'])==1 and data['segments'][0]['type']=='arc'
    assert data['segments'][0]['center']==[-3,-6]
    assert data['segments'][0]['radius']==pytest.approx(50)


def source_file(tmp_path,ambiguous=False):
    p,notes=drawing();doc=ezdxf.new('R2018',units=4)
    frame=doc.blocks.new('FRAME');frame.add_lwpolyline([(-100,-100),(10000,-100),(10000,8000),(-100,8000)],close=True)
    frame.add_attdef('MASP');ref=doc.modelspace().add_blockref(frame.name,(0,0));ref.add_auto_attribs({'MASP':'SP01'})
    rows=p['outlines']+[rect(1800,1000,200,2400,'wall','WALL')]
    if ambiguous:
        rows += [dict(row,points=[[x,y+4000] for x,y in row['points']]) for row in p['outlines'] if row['handle'] not in ('FL','FR','FB','FT')]
        rows.append(rect(18,4582,1582,18,'extra'))
        notes.append(dict(kind='view_title',text='MẶT CẮT 3-3',point=[700,3900],center_x=809,handle='TX'))
        notes.append(dict(kind='section_marker',point=[4800,1500],axis='horizontal',numbers=['3'],handle='CX'))
    for row in rows:doc.modelspace().add_lwpolyline(row['points'],dxfattribs={'layer':row.get('layer','0')})
    marker=doc.blocks.new('SECTION MARK');marker.add_line((-500,0),(500,0))
    for tag in ('1','2','4','5'):marker.add_attdef(tag)
    for note in notes:
        if note['kind']=='view_title':doc.modelspace().add_text(note['text'],dxfattribs={'insert':note['point'],'height':40})
        else:
            ref=doc.modelspace().add_blockref(marker.name,note['point']);n=note['numbers'][0]
            ref.add_auto_attribs({'1':'9','2':'9','4':n,'5':n})
    path=tmp_path/'mixed.dxf';doc.saveas(path);return path


def test_worker_isolates_and_transports_named_product_plan(tmp_path,monkeypatch):
    import main,local_ai
    def forbidden(*_args,**_kwargs):raise AssertionError('Old/AI pipeline invoked')
    monkeypatch.setattr(main,'line_rectangles',forbidden);monkeypatch.setattr(local_ai,'Runtime',forbidden)
    path=source_file(tmp_path)
    request=dict(action='analyze',sources=[str(path)],targets=['SP01'],library=str(tmp_path/'lib'))
    result=run(request);assert not result['errors']
    product=result['analyses'][0]['products'][0]
    assert product['status']=='ready',product.get('error')
    assert product['bounds']==[1618,600,1600]
    assert all(0<=point[0]<=1618 and 200<=point[1]<=800 for row in product['outlines'] for point in row['points'])
    assert product['check_outlines'] and product['plan_reference']['segments']
    assert product['plan_reference']['source_origin_mm']==[0,200]
    assert any(row['kind']=='wall' for row in product['view_analysis']['excluded_context'])


def test_worker_confirmation_is_saved_for_one_source_revision_only(tmp_path):
    path=source_file(tmp_path,ambiguous=True)
    request=dict(action='analyze',sources=[str(path)],targets=['SP01'],library=str(tmp_path/'lib'))
    first=run(request)['analyses'][0]['products'][0]
    assert first['status']=='ready' and len(first['plan_results'])==2
    c=next(c for c in first['view_analysis']['candidates'] if c['role']=='plan')
    choice=dict(source_hash=first['source_hash'],view_id=c['id'],signature=c['signature'])
    chosen=run(dict(request,plan_choices={'SP01':choice}))['analyses'][0]['products'][0]
    assert chosen['status']=='ready' and chosen['view_analysis']['selected_view_id']==c['id']
    repeated=run(request)['analyses'][0]['products'][0]
    assert repeated['view_analysis']['selected_view_id']==c['id']
    doc=ezdxf.readfile(path);doc.modelspace().add_line((9000,7000),(9010,7000));doc.saveas(path)
    changed=run(dict(request,plan_choices={'SP01':choice}))
    assert changed['errors'] and 'đã đổi' in changed['errors'][0]['error']
    assert len(run(request)['analyses'][0]['products'][0]['plan_results'])==2


def test_multiple_mode_keeps_all_cuts_and_size_disagreement_as_warning(tmp_path):
    p,notes=drawing()
    for row in p['outlines']:
        if row['handle']=='FR':row['points']=[[x+200,y] for x,y in row['points']]
    selected=choose_product_plan(p,notes,multiple=True)
    assert len(selected)==1
    from named_plans import analyse_named_plans
    analyse_named_plans(p,selected,tmp_path)
    assert p['status']=='ready' and p['bounds']==[1618,600,1600]
    assert p['warnings'] and 'mặt đứng' in p['warnings'][0]


def test_distinct_and_identical_cuts_are_both_arranged_with_a_clear_1000mm_gap(tmp_path):
    path=source_file(tmp_path,ambiguous=True)
    p=run(dict(sources=[str(path)],library=str(tmp_path/'lib')))['analyses'][0]['products'][0]
    children=p['plan_results'];assert len(children)==2
    assert children[0]['display_layout']['offset_mm']==[0,0]
    assert children[1]['display_layout']['offset_mm']==[2618,0]
    assert children[0]['display_layout']['total_width_mm']==4236
    assert children[0]['plan_view_id']!=children[1]['plan_view_id']
    assert all(c['plan_reference']['segments'] and c['source_hash']==p['source_hash'] for c in children)
    from named_plans import arrange
    children[1]=deepcopy(children[0]);arrange(p)
    assert children[1]['display_layout']['offset_mm'][0]==2618


def test_found_horizontal_plan_with_missing_partition_gets_an_envelope(tmp_path):
    p,notes=drawing()
    p['outlines']=[o for o in p['outlines'] if o['handle'] in ('FL','FR','FB','FT')]+[rect(0,200,1618,600,'unclosed-body')]
    selected=choose_product_plan(p,notes,multiple=True)
    assert len(selected)==1
    from named_plans import analyse_named_plans
    analyse_named_plans(p,selected,tmp_path)
    assert p['status']=='needs_review' and p['envelope_preview']
    assert p['modules'][0]['size']==[1618,600,1600]
    assert p['plan_reference'] and p['placement']['mode']=='label_plan'


def test_partial_bays_do_not_hide_the_rest_of_a_found_plan(tmp_path,monkeypatch):
    import named_plans
    p,notes=drawing();selected=choose_product_plan(p,notes,multiple=True)
    original=named_plans.analyse_plan
    def partial(child,*args,**kwargs):
        original(child,*args,**kwargs)
        child['bounds'][0]=800
        child['modules']=child['modules'][:1]
    monkeypatch.setattr(named_plans,'analyse_plan',partial)
    named_plans.analyse_named_plans(p,selected,tmp_path)
    assert p['envelope_preview'] and p['bounds']==[1618,600,1600]


def test_identical_source_at_a_new_path_does_not_reuse_the_old_path(tmp_path):
    path=source_file(tmp_path);request=dict(sources=[str(path)],library=str(tmp_path/'lib'))
    first=run(request)['analyses'][0]['products'][0]
    other=tmp_path/'moved.dxf';other.write_bytes(path.read_bytes())
    moved=run(dict(request,sources=[str(other)]))['analyses'][0]['products'][0]
    assert moved['source_hash']==first['source_hash']
    assert moved['source_path']==str(other.resolve())


@pytest.mark.parametrize('ratio,role',[(.86,'plan'),(1.14,'plan'),(.84,'plan_candidate'),(1.16,'plan_candidate'),(.79,'plan_candidate'),(1.21,'plan_candidate'),
                                        (.5,'detail_section'),(.25,'detail_section'),(2,'detail_section')])
def test_plan_width_tolerance_never_accepts_detail_scale_as_whole_product(ratio,role):
    p,notes=drawing(plan_width=1618*ratio)
    selected=choose_product_plan(p,notes,multiple=True)
    candidate=p['view_analysis']['candidates'][0]
    assert candidate['role']==role
    assert bool(selected)==(role=='plan')
    assert candidate['can_confirm']==(role!='detail_section')
    assert candidate['product_size_check']['tolerance_percent']==20
    if role=='detail_section':
        with pytest.raises(ValueError,match='không có mặt bằng'):
            choose_product_plan(p,notes,dict(view_id=candidate['id'],signature=candidate['signature']),multiple=True)


def test_moderate_width_mismatch_remains_explicitly_reviewable():
    p,notes=drawing(plan_width=1618*.75)
    assert not choose_product_plan(p,notes,multiple=True)
    c=p['view_analysis']['candidates'][0]
    selected=choose_product_plan(p,notes,dict(view_id=c['id'],signature=c['signature']),multiple=True)
    assert len(selected)==1


@pytest.mark.parametrize('depth,role',[(550,'plan'),(500,'plan_candidate'),(450,'plan_candidate'),(180,'detail_section')])
def test_two_full_plans_cross_check_a_same_width_detail_depth(depth,role):
    p,notes=drawing();p['regions'][0][3]=8000
    for number,y,h in [('3',4200,600),('4',6200,depth)]:
        p['outlines'].append(rect(0,y,1618,h,'BODY'+number))
        notes.append(dict(kind='view_title',text=f'MẶT CẮT {number}-{number}',point=[700,y-200],center_x=809,handle='T'+number))
        notes.append(dict(kind='section_marker',point=[4800,1400],axis='horizontal',numbers=[number],handle='C'+number))
    selected=choose_product_plan(p,notes,multiple=True)
    c=next(c for c in p['view_analysis']['candidates'] if c['title']=='MẶT CẮT 4-4')
    assert c['role']==role
    assert len(selected)==(3 if role=='plan' else 2)
    if role!='plan':assert not c['peer_size_check']['passed']


def test_explicit_enlarged_detail_caption_is_not_a_whole_plan_even_at_matching_width():
    p,notes=drawing();notes[0]['text']='MẶT CẮT 2-2 PHÓNG TO CHI TIẾT'
    assert not choose_product_plan(p,notes,multiple=True)
    c=p['view_analysis']['candidates'][0]
    assert c['role']=='detail_section' and not c['can_confirm']


def test_sp04_real_geometry_excludes_four_details_borrowing_a_horizontal_cut_title():
    views=json.loads((Path(__file__).parent/'fixtures/sp04_views.json').read_text(encoding='utf8'))
    p=dict(code='SP04',outlines=[o for v in views for o in v['outlines']],
           regions=[[174812,70200,185312.75,77076],[185312.75,70200,195813,77076]])
    notes=[dict(kind='view_title',text=v['title'],point=[(v['region'][0]+v['region'][2])/2,v['region'][1]],
                center_x=(v['region'][0]+v['region'][2])/2,handle=v['title_handle']) for v in views]
    notes += [dict(kind='section_marker',handle='cut'+n,point=[178209,74000],axis='horizontal',numbers=[n]) for n in ('4','5','6')]
    selected=choose_product_plan(p,notes,multiple=True)
    assert [v['id'] for v in selected]==['V01.1','V02.1','V06.1']
    assert all(v['features']['width_mm']==5200 for v in selected)
    details=[s for s in p['view_analysis']['candidates'] if s['role']=='detail_section']
    assert sorted(s['width_mm'] for s in details)==[100,600,800,1551.524]
    assert all(not s['can_confirm'] and s['product_size_check']['difference_percent']>=50 for s in details)


def test_peer_widths_can_exclude_an_enlarged_view_without_an_elevation():
    p,notes=drawing();p['outlines']=[o for o in p['outlines'] if o['handle'] not in ('FL','FR','FB','FT')]
    notes=[notes[0]];notes[0]['text']='MẶT BẰNG';p['regions'][0][3]=8000
    original=deepcopy(p['outlines'])
    for number,y,scale in [('2',4000,1),('3',6000,2)]:
        p['outlines'] += [dict(o,handle=number+o['handle'],points=[[x*scale,yy+y] for x,yy in o['points']]) for o in original]
        notes.append(dict(kind='view_title',text='MẶT BẰNG '+number,point=[700,y],center_x=809*scale,handle='T'+number))
    selected=choose_product_plan(p,notes,multiple=True)
    assert len(selected)==2
    enlarged=next(c for c in p['view_analysis']['candidates'] if c['width_mm']==3236)
    assert enlarged['role']=='detail_section' and not enlarged['can_confirm']
    assert enlarged['peer_size_check']['reference_width_mm']==1618
