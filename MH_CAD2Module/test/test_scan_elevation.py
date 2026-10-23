from copy import deepcopy

import pytest

from main import run
from scan_views import prepare
from test_elevation_builder import fixture


def geometry(symbols=True):
    product,notes=fixture();lines=[];objects=[]
    for row in product['outlines']:
        for i,(a,b) in enumerate(zip(row['points'],row['points'][1:])):
            lines.append(dict(handle=f'{row["handle"]}:{i}',a=a,b=b,path=[10]))
    for note in notes:
        if note['kind']=='view_title':
            objects.append(dict(handle=note['handle'],text=note['text'],point=note['point'],center_x=note['center_x'],path=[10]))
        else:
            a,b=note['cut_line'];path=[10,note['handle']]
            line=dict(a=a,b=b,handle=note['handle']+'line',path=path if symbols else [10]);lines.append(line)
            if symbols:
                objects.append(dict(handle=note['handle'],symbol=True,path=path,point=note['point'],basis=[[1,0],[0,1]],
                    attributes={k:note['numbers'][0] for k in ('1','2','4','5')},segments=[line]))
            else:
                for i,p in enumerate((a,b)):
                    objects.append(dict(handle=note['handle']+str(i),text=note['numbers'][0],point=p,path=[10]))
    return dict(hash='d'*64,plane='XY',plane_offset_mm=73,model_path='QA.skp',lines=lines,
                scan_annotations=dict(schema=1,objects=objects,issues=[]),
                annotation_watch=[[123,[10],'signature']],source_watch=[['456',[10],[0,0,73],[0,18,73]]])


def build(tmp_path,g=None):
    return run(dict(action='geometry',library=str(tmp_path),build_plan=True,build_elevation=True,
                    geometry=g or geometry()))['analyses'][0]['products'][0]


@pytest.mark.parametrize('symbols',[True,False])
def test_single_scan_reads_titles_and_located_cuts_without_product_code(tmp_path,symbols):
    g=geometry(symbols);p=build(tmp_path,g)
    assert p['geometry_pipeline']['horizontal']['status']=='measured',p['geometry_pipeline']
    assert [m['size'][2] for m in p['modules']]==[1000,1400,1200,1200]
    assert [m['origin'][2] for m in p['modules']]==[0,1000,0,1200]
    assert p['placement']==dict(mode='source_plan',plane='XY',origin_mm=[0,200],plane_offset_mm=73)
    assert not p.get('display_layout') and p['automatic_scan']
    assert p['annotation_watch']==g['annotation_watch'] and p['source_watch']==g['source_watch']
    assert p['scan_capture']['view_titles']==5 and p['scan_capture']['section_markers']==3
    assert p['processing_times']['scan_annotations']>=0
    assert all(not o['handle'].endswith('line') for o in p['outlines'])


def test_rotated_symbol_uses_local_attribute_pair_but_world_cut_direction(tmp_path):
    g=geometry();c=next(o for o in g['scan_annotations']['objects'] if o['handle']=='C1')
    c['basis']=[[0,2],[-3,0]]
    c['attributes']={'1':'wrong','2':'wrong','4':'1','5':'1'}
    assert build(tmp_path,g)['geometry_pipeline']['horizontal']['status']=='measured'


@pytest.mark.parametrize('change',['missing','conflicting','oblique','partial'])
def test_bad_cut_never_invents_or_borrows_other_bay_heights(tmp_path,change):
    g=geometry();objs=g['scan_annotations']['objects'];c=next(o for o in objs if o['handle']=='C2')
    if change=='missing':objs.remove(c)
    if change=='partial':
        objs.remove(c);g['scan_annotations']['issues'].append('Ký hiệu cắt chỉ một phần trong vùng quét.')
    if change=='conflicting':c['attributes']['2']='9'
    if change=='oblique':c['segments'][0]['b'][0]+=300
    p=build(tmp_path,g)
    assert p['elevation_pending'] and [m['size'][2] for m in p['modules']]==[2400,2400]
    assert p['height_source']=='product_elevation_bounds' and not p['height_pending']
    assert p['geometry_pipeline']['horizontal']['issues']
    if change!='missing':assert p['scan_capture']['issues']


def test_two_exploded_strokes_with_same_endpoint_ids_are_ambiguous(tmp_path):
    g=geometry(False)
    line=next(r for r in g['lines'] if r['handle']=='C2line')
    duplicate=dict(line,handle='duplicate',a=[line['a'][0]+50,line['a'][1]],b=[line['b'][0]+50,line['b'][1]])
    g['lines'].append(duplicate)
    p=build(tmp_path,g)
    assert p['elevation_pending']
    assert any('nhiều đường' in s for s in p['scan_capture']['issues'])


def test_repeated_text_cannot_override_conflicting_symbol_attributes(tmp_path):
    g=geometry();c=next(o for o in g['scan_annotations']['objects'] if o['handle']=='C2')
    c['attributes']['2']='9'
    for i,point in enumerate((c['segments'][0]['a'],c['segments'][0]['b'])):
        g['scan_annotations']['objects'].append(dict(handle='inside'+str(i),text='2',point=point,path=c['path']))
    assert build(tmp_path,g)['elevation_pending']


def test_text_graphics_and_same_definition_edge_ids_do_not_become_stock():
    g=geometry();g['lines'] += [dict(handle='same',path=[20],a=[0,-100],b=[100,-100]),
                                 dict(handle='same',path=[21],a=[30000,0],b=[30000,18])]
    g['scan_annotations']['objects'].append(dict(handle='title',texts=['MẶT BẰNG'],point=[0,-100],center_x=809,path=[20],text_graphics=True))
    rows,notes,regions,capture=prepare(g)
    assert not any(r['handle']=='20/same' for r in rows)
    assert any(r['handle']=='21/same' for r in rows)
    assert regions[0][1]<-100 # Include the title baseline, not only the CAD edge envelope.


def test_plan_only_scan_never_calls_annotation_or_elevation_processing(tmp_path,monkeypatch):
    import scan_views
    from test_scanned_l_partition import source
    def forbidden(*args,**kwargs):raise AssertionError('Combined scanner used in plan-only stage')
    monkeypatch.setattr(scan_views,'prepare',forbidden)
    p=run(dict(action='geometry',library=str(tmp_path),geometry=dict(lines=source(),hash='e'*64)))['analyses'][0]['products'][0]
    assert len(p['modules'])==7 and len(p['trim_parts'])==4


def test_multiple_scanned_plans_keep_individual_world_origins_and_cut_levels(tmp_path):
    g=geometry();rows=[r for r in g['lines'] if max(r['a'][1],r['b'][1])<=800]
    g['lines'] += [dict(r,handle='extra'+r['handle'],a=[r['a'][0],r['a'][1]+5000],b=[r['b'][0],r['b'][1]+5000]) for r in rows]
    g['scan_annotations']['objects'].append(dict(handle='TP4',text='MẶT CẮT 4-4',point=[0,5100],center_x=809,path=[10]))
    line=dict(handle='H4line',path=[10,'H4'],a=[4000,2700],b=[5618,2700]);g['lines'].append(line)
    g['scan_annotations']['objects'].append(dict(handle='H4',symbol=True,path=line['path'],point=[4809,2700],basis=[[1,0],[0,1]],
        attributes={k:'4' for k in ('1','2','4','5')},segments=[line]))
    p=build(tmp_path,g);children=p['plan_results']
    assert len(children)==2
    assert [c['placement']['origin_mm'] for c in children]==[[0,200],[0,5200]]
    assert all(not c.get('display_layout') for c in children)
    assert [[m['origin'][2] for m in c['modules']] for c in children]==[[0,0],[1000,1200]]
    assert all(c['annotation_watch']==g['annotation_watch'] for c in children)
