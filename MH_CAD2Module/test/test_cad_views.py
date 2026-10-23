import json
from copy import deepcopy
from pathlib import Path

import ezdxf
import pytest

from cad_views import project
from combined_runtime import analyse
from drawing_scope import choose_product_plan
from main import run
from named_plans import replay_named
from scan_views import prepare
from test_elevation_builder import fixture


def low_source():
    return json.loads((Path(__file__).parent/'fixtures/low_cabinet_scan_edges.json').read_text('utf8'))


def low_product(tmp_path):
    rows,notes,regions,_=prepare(dict(hash='c'*64,lines=low_source()))
    product=dict(code='SP99',name='QA',source_hash='c'*64,source_path='QA.dxf',outlines=rows,regions=regions)
    selected=choose_product_plan(product,notes,multiple=True)
    analyse(product,selected,notes,tmp_path)
    return product


def test_actual_low_cabinet_copies_uncropped_views_even_with_provisional_height(tmp_path):
    p=low_product(tmp_path);ref=p['plan_reference'];views=ref['views']
    assert p['elevation_pending'] and p['modules'][0]['size'][2]==1600
    assert ref['scope']=='all_views' and len(ref['segments'])==169
    assert [v['plane'] for v in views]==['XY','XZ','XZ','YZ']
    assert [v.get('role') for v in views]==['plan','front_check','front_open','section_vertical']
    assert sorted(i for v in views for i in v['segment_indices'])==list(range(169))
    assert views[1]['box_mm'][3]-views[1]['box_mm'][1]==pytest.approx(870)
    assert views[-1]['direction_basis']=='unresolved' # Symmetric stock pairs cannot prove the viewing direction.
    assert 'hướng nhìn' in views[-1]['registration_issue']
    assert ref['placed_bounds_mm'][5]==pytest.approx(870)


def test_actual_projection_aligns_front_width_floor_and_side_depth_without_scaling(tmp_path):
    p=low_product(tmp_path);ref=p['plan_reference'];plan=ref['plan_bounds_mm']
    for view in ref['views'][1:]:
        b=view['box_mm'];lo=project(b[:2],view,plan);hi=project(b[2:],view,plan)
        assert lo[2]==0 and hi[2]==pytest.approx(870)
        if view['role']!='section_vertical':
            if view['role']=='front_check':
                assert lo[:2]==pytest.approx([plan[0],0]) and hi[:2]==pytest.approx([plan[2],0])
            else:
                front=ref['views'][1];left=project(front['box_mm'][:2],front,plan)[0]
                assert lo[0]==pytest.approx(left) and lo[1]==hi[1]==0
                assert 'drawing_x_offset_mm' not in view and ref['display_mode']=='front_overlay'
        else:
            assert view['plane']=='YZ' and lo[0]==hi[0]==pytest.approx(view['display_x_mm'])
            # Complete context stays visible, but does not define the wood datum.
            cabinet=view['cabinet_datum']['box_mm']
            front=project([cabinet[2],cabinet[1]],view,plan)
            back=project([cabinet[0],cabinet[1]],view,plan)
            assert sorted([front[1],back[1]])==pytest.approx([0,600],abs=.001)
            assert view['display_x_mm']==pytest.approx(1300,abs=.001)
            assert view['section_position']['basis']=='box_edge'
    # The carcass/label placement must not be changed to fit a reference drawing.
    assert p['display_layout']['total_width_mm']==1340
    assert p['bounds']==[1300,582,1600]


def test_replay_retains_full_reference_and_no_plan_height_learning_is_granted(tmp_path):
    p=low_product(tmp_path);before=deepcopy(p['plan_reference'])
    replay_named(p,tmp_path)
    assert p['plan_reference']==before and p['elevation_pending']
    assert p['geometry_pipeline']['horizontal']['status']=='provisional'


def test_direct_scan_keeps_original_cad_without_full_reference_copy(tmp_path):
    p=run(dict(action='geometry',library=str(tmp_path),build_elevation=True,
               geometry=dict(hash='b'*64,lines=low_source())))['analyses'][0]['products'][0]
    assert p['placement']['mode']=='source_plan'
    assert 'cad_reference_outlines' not in p and p['plan_reference'].get('scope') is None


def test_multi_plan_source_context_is_attached_once_and_spacing_is_unchanged(tmp_path):
    p,notes=fixture()
    # Copy the measured first plan into a separate region and give it a distinct title.
    original=[o for o in p['outlines'] if all(y<900 for _,y in o['points'])]
    p['outlines'] += [dict(o,handle=o['handle']+'copy',points=[[x,y+5000] for x,y in o['points']]) for o in original]
    b=p['regions'][0];p['regions'].append([b[0],b[1]+5000,b[2],b[3]+5000])
    notes.append(dict(kind='view_title',text='MẶT CẮT 4-4',handle='P4',point=[0,5100],center_x=809))
    selected=choose_product_plan(p,notes,multiple=True);assert len(selected)==2
    analyse(p,selected,notes,tmp_path)
    children=p['plan_results']
    assert sum(c['plan_reference'].get('scope')=='all_views' for c in children)==1
    assert all(c['display_layout']['gap_mm']==1000 for c in children)
    assert children[0]['display_layout']['total_width_mm']==4236


def test_unidentified_context_is_preserved_and_not_rotated(tmp_path):
    p,notes=fixture();p['outlines'].append(dict(handle='UNKNOWN',points=[[17000,800],[17010,850]]))
    selected=choose_product_plan(p,notes,multiple=True);analyse(p,selected,notes,tmp_path)
    ref=p['plan_reference'];idx=next(i for i,s in enumerate(ref['segments']) if 'UNKNOWN' in s['handles'])
    view=next(v for v in ref['views'] if idx in v['segment_indices'])
    assert view['plane']=='XY' and view['alignment']=='unresolved'


def test_dxf_entry_resident_source_cache_and_plan_only_import_are_independent(tmp_path,monkeypatch):
    import main
    doc=ezdxf.new('R2018',units=4);space=doc.modelspace();lines=low_source()
    xs=[r[k][0] for r in lines for k in ('a','b')];ys=[r[k][1] for r in lines for k in ('a','b')]
    x0,y0=min(xs)-100,min(ys)-100;w,h=max(xs)-x0+100,max(ys)-y0+100
    frame=doc.blocks.new('FRAME');frame.add_lwpolyline([(0,0),(w,0),(w,h),(0,h)],close=True);frame.add_attdef('MASP')
    space.add_blockref(frame.name,[x0,y0]).add_auto_attribs({'MASP':'SP99'})
    for row in lines:space.add_line(row['a'],row['b'])
    path=tmp_path/'low.dxf';doc.saveas(path);calls=[];read=main.ezdxf.readfile
    def counted(*a,**kw):calls.append(a[0]);return read(*a,**kw)
    monkeypatch.setattr(main.ezdxf,'readfile',counted)
    request=dict(sources=[str(path)],library=str(tmp_path/'library'),targets=['SP99'])
    plan=run(request)['analyses'][0]['products'][0]
    full=run(dict(request,build_elevation=True))['analyses'][0]['products'][0]
    again=run(dict(request,build_elevation=True))['analyses'][0]['products'][0]
    assert len(calls)==1 and full['source_cache']['mode']=='memory'
    assert plan['plan_reference'].get('scope') is None and full['plan_reference']['scope']=='all_views'
    assert len(full['plan_reference']['segments'])==169
    assert again['plan_reference']==full['plan_reference']
