
import pytest

from combined_runtime import analyse
from drawing_scope import choose_product_plan
from elevation_geometry import panels,tiers
from test_drawing_scope import rect
from test_oy_sweep import cabinet,outlines


def carcass(x,y,w,h,prefix):
    return [rect(x,y,18,h,prefix+'L'),rect(x+w-18,y,18,h,prefix+'R'),
            rect(x+18,y,w-36,18,prefix+'B'),rect(x+18,y+h-18,w-36,18,prefix+'T')]


def fixture():
    plan=outlines(cabinet())
    plan=[dict(o,points=[[x,y+200] for x,y in o['points']]) for o in plan]
    front=carcass(4000,1000,1618,2400,'F')
    opened=[];sections=[]
    for i,(width,cut) in enumerate(((818,1000),(800,1200))):
        x=16000+(818 if i else 0)
        opened+=carcass(x,1000,width,cut,f'O{i}a')+carcass(x,1000+cut,width,2400-cut,f'O{i}b')
        sx=10000+i*2500
        sections+=carcass(sx,1000,600,cut,f'S{i}a')+carcass(sx,1000+cut,600,2400-cut,f'S{i}b')
    notes=[];regions=[]
    for x,y,w,h,title,handle in ((0,200,1618,600,'MẶT CẮT 3-3','P'),(4000,1000,1618,2400,'MẶT ĐỨNG','F'),
          (16000,1000,1618,2400,'MẶT ĐỨNG BỎ CÁNH','O'),(10000,1000,600,2400,'MẶT CẮT 1-1','S1'),
          (12500,1000,600,2400,'MẶT CẮT 2-2','S2')):
        regions.append([x-50,y-150,x+w+50,y+h+50])
        notes.append(dict(kind='view_title',text=title,handle=handle,point=[x,y-100],center_x=x+w/2))
    notes.append(dict(kind='section_marker',handle='H3',point=[4800,1700],axis='horizontal',numbers=['3'],cut_line=[[4000,1700],[5618,1700]]))
    for i,x in enumerate((4400,5200)):
        notes.append(dict(kind='section_marker',handle=f'C{i+1}',point=[x,2200],axis='vertical',numbers=[str(i+1)],cut_line=[[x,1000],[x,3400]]))
    return dict(code='SP99',name='QA',source_hash='a'*64,source_path='QA.dxf',parser_version='0.2.3',
                outlines=plan+front+opened+sections,regions=regions),notes


def build(tmp_path,product=None,notes=None):
    if product is None:product,notes=fixture()
    selected=choose_product_plan(product,notes,multiple=True)
    assert len(selected)==1,product['view_analysis']
    analyse(product,selected,notes,tmp_path)
    return product


def test_section_position_assigns_different_heights_to_two_bays(tmp_path):
    p=build(tmp_path)
    assert p['geometry_pipeline']['horizontal']['status']=='measured',p['geometry_pipeline']['horizontal']
    assert [m['size'] for m in p['modules']]==[[818,600,1000],[818,600,1400],[800,600,1200],[800,600,1200]]
    assert [m['origin'][2] for m in p['modules']]==[0,1000,0,1200]
    assert p['plan_reference']['source_origin_mm']==[0,200]
    assert all(m['height_source']=='linked_vertical_section' for m in p['modules'])
    assert {l['marker_handle'] for m in p['modules'] for l in m['elevation_evidence']['links']}=={'C1','C2'}
    assert p['build_stages']==dict(plan=True,elevation=True) and p['bounds'][2]==2400


def test_single_internal_shelf_cannot_split_continuous_section_sides():
    rows=carcass(0,0,600,2400,'S')+[rect(18,1000,564,18,'shelf')]
    ps,index=panels(rows)
    assert index['method']=='stock_offset_lookup'
    assert [(t['low_mm'],t['high_mm']) for t in tiers(ps,600)]==[(0,2400)]


def test_continuous_open_front_wall_vetoes_a_section_seam(tmp_path):
    p,notes=fixture()
    p['outlines']=[o for o in p['outlines'] if o['handle'] not in ('O0aL','O0bL')]+[rect(16000,1000,18,2400,'uncut')]
    result=build(tmp_path,p,notes)
    assert result['elevation_pending'] and all(m['size'][2]==2400 for m in result['modules'])
    assert result['height_source']=='product_elevation_bounds' and not result['height_pending']
    assert 'xuyên tấm' in result['geometry_pipeline']['horizontal']['issues'][0]


@pytest.mark.parametrize('change',['missing','outside','axis','on_seam','different_height'])
def test_uncertain_cut_never_borrows_another_bay_section(tmp_path,change):
    p,notes=fixture()
    c=next(n for n in notes if n['handle']=='C2')
    if change=='missing':notes.remove(c)
    if change=='outside':c['point'][0]=30000;c['cut_line']=[[30000,1000],[30000,3400]]
    if change=='axis':c['cut_line']=[[5100,2000],[5500,2000]] # Stale axis field cannot authorise a vertical cut.
    if change=='on_seam':c['point'][0]=4818;c['cut_line']=[[4818,1000],[4818,3400]]
    if change=='different_height':
        for row in p['outlines']:
            if row['handle'].startswith('S1'):
                row['points']=[[x,1000+(y-1000)*.8] for x,y in row['points']]
    result=build(tmp_path,p,notes)
    assert result['elevation_pending'] and all(m['size'][2]==2400 for m in result['modules'])
    assert result['product_height']['scope']=='product_envelope_only'
    assert result['geometry_pipeline']['horizontal']['issues']


def test_translation_keeps_size_and_cut_registration(tmp_path):
    p,notes=fixture();dx,dy=11000,-17000
    for o in p['outlines']:o['points']=[[x+dx,y+dy] for x,y in o['points']]
    p['regions']=[[b[0]+dx,b[1]+dy,b[2]+dx,b[3]+dy] for b in p['regions']]
    for n in notes:
        n['point']=[n['point'][0]+dx,n['point'][1]+dy]
        if 'center_x' in n:n['center_x']+=dx
        if 'cut_line' in n:n['cut_line']=[[x+dx,y+dy] for x,y in n['cut_line']]
    result=build(tmp_path,p,notes)
    assert result['geometry_pipeline']['horizontal']['status']=='measured'
    assert [m['origin'][2] for m in result['modules']]==[0,1000,0,1200]
    assert result['plan_reference']['source_origin_mm']==[dx,200+dy]


def test_stage_cannot_call_old_partitioner_or_ai(tmp_path,monkeypatch):
    import views,local_ai
    import main
    def forbidden(*a,**k):raise AssertionError('Old partitioner or AI was called')
    monkeypatch.setattr(views,'recognise_ordered',forbidden);monkeypatch.setattr(local_ai.Assistant,'apply',forbidden)
    monkeypatch.setattr(main,'recognise_ordered',forbidden)
    assert build(tmp_path)['height_source']=='linked_vertical_section'


def test_exploded_lines_recover_side_seams_only_at_full_width_caps(tmp_path):
    p,notes=fixture()
    p['outlines']=[dict(o,handle=f'{o["handle"]}:{i}',points=[a,b]) for o in p['outlines']
                   for i,(a,b) in enumerate(zip(o['points'],o['points'][1:]))]
    assert build(tmp_path,p,notes)['geometry_pipeline']['horizontal']['status']=='measured'
    rows=carcass(0,0,600,2400,'S')+[rect(18,1000,564,18,'shelf')]
    rows=[dict(o,points=[a,b]) for o in rows for a,b in zip(o['points'],o['points'][1:])]
    assert [(t['low_mm'],t['high_mm']) for t in tiers(panels(rows)[0],600)]==[(0,2400)]


def test_dxf_entry_and_revision_index_keep_stages_separate(tmp_path,monkeypatch):
    import ezdxf,main
    from library import library_root
    product,notes=fixture();doc=ezdxf.new('R2018',units=4);space=doc.modelspace()
    for i,b in enumerate(product['regions']):
        w,h=b[2]-b[0],b[3]-b[1]
        block=doc.blocks.new('FRAME'+str(i));block.add_lwpolyline([(0,0),(w,0),(w,h),(0,h)],close=True)
        block.add_attdef('MASP');space.add_blockref(block.name,b[:2]).add_auto_attribs({'MASP':'SP99'})
    for o in product['outlines']:
        if len(o['points'])==2:space.add_line(*o['points'])
        else:space.add_lwpolyline(o['points'],close=True)
    for i,n in enumerate(notes):
        if n['kind']=='view_title':space.add_text(n['text'],dxfattribs=dict(insert=n['point'],height=30))
        else:
            block=doc.blocks.new('SECTION MARK '+str(i));origin=n['point']
            block.add_line([n['cut_line'][0][j]-origin[j] for j in (0,1)],[n['cut_line'][1][j]-origin[j] for j in (0,1)])
            for tag in ('1','2','4','5'):block.add_attdef(tag)
            space.add_blockref(block.name,origin).add_auto_attribs({tag:n['numbers'][0] for tag in ('1','2','4','5')})
    source=tmp_path/'combined.dxf';doc.saveas(source);root=library_root(str(tmp_path/'library'))
    calls=[];read=main.ezdxf.readfile
    def counted(*a,**kw):calls.append(a[0]);return read(*a,**kw)
    monkeypatch.setattr(main.ezdxf,'readfile',counted)
    plan=main.run(dict(sources=[str(source)],library=str(root)))['analyses'][0]['products'][0]
    full=main.run(dict(sources=[str(source)],library=str(root),build_elevation=True))['analyses'][0]['products'][0]
    assert len(calls)==1 and full['source_cache']['mode']=='memory'
    assert full['geometry_pipeline']['horizontal']['status']=='measured',full.get('geometry_pipeline')
    assert [m['size'][2] for m in plan['modules']]==[1600,1600]
    assert [m['size'][2] for m in full['modules']]==[1000,1400,1200,1200]


def test_multiple_plans_use_horizontal_cut_height_to_avoid_repeating_all_tiers(tmp_path):
    p,notes=fixture();plan=[o for o in p['outlines'] if max(q[1] for q in o['points'])<=800]
    p['outlines'] += [dict(o,handle='extra-'+o['handle'],points=[[x,y+5000] for x,y in o['points']]) for o in plan]
    b=p['regions'][0];p['regions'].append([b[0],b[1]+5000,b[2],b[3]+5000])
    notes.append(dict(kind='view_title',text='MẶT CẮT 4-4',handle='P4',point=[0,5100],center_x=809))
    notes.append(dict(kind='section_marker',handle='H4',axis='horizontal',numbers=['4'],point=[4800,2700],cut_line=[[4000,2700],[5618,2700]]))
    selected=choose_product_plan(p,notes,multiple=True);assert len(selected)==2
    analyse(p,selected,notes,tmp_path)
    children=p['plan_results']
    assert [m['size'][2] for m in children[0]['modules']]==[1000,1200]
    assert [m['origin'][2] for m in children[1]['modules']]==[1000,1200]
    assert all(c['geometry_pipeline']['horizontal']['status']=='measured' for c in children)
    assert children[0]['display_layout']['gap_mm']==1000


def test_two_sections_at_same_bay_cannot_supply_different_splits(tmp_path):
    p,notes=fixture();c=next(n for n in notes if n['handle']=='C2')
    p['outlines']=[o for o in p['outlines'] if not o['handle'].startswith('O')]
    c['point'][0]=4400;c['cut_line']=[[4400,1000],[4400,3400]]
    result=build(tmp_path,p,notes)
    assert result['elevation_pending']
    assert 'khác nhau' in result['geometry_pipeline']['horizontal']['issues'][0]


def test_pending_heights_do_not_enter_full_height_experience_library(tmp_path):
    from test_learning import sample_product,save_example
    from learning import ExperienceLibrary
    source,state=sample_product();source['elevation_pending']=True
    save_example(tmp_path,source,state)
    assert ExperienceLibrary(tmp_path).events()==[]


def test_source_floor_datum_preserves_50mm_plinth_below_carcass(tmp_path):
    p,notes=fixture()
    for x,w,name in ((4000,1618,'Fbase'),(16000,1618,'Obase'),(10000,600,'Sbase1'),(12500,600,'Sbase2')):
        p['outlines'].append(rect(x,950,w,50,name))
    result=build(tmp_path,p,notes)
    assert result['geometry_pipeline']['horizontal']['status']=='measured'
    assert [m['origin'][2] for m in result['modules']]==[50,1050,50,1250]
    assert result['bounds'][2]==2450
