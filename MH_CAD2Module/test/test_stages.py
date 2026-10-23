import json
from pathlib import Path
import pytest

from main import run, replay_experience, analyse_source
from stages import recognise_plan
from test_three_wardrobes import source_views
from test_views import simple_views


@pytest.mark.parametrize('code,widths', [('SP28',[860,1422]),('SP29',[1100,1300,1134]),('SP30',[1044.5,1044.5])])
def test_plan_stage_ignores_all_front_and_section_geometry(code,widths):
    views=[v for v in source_views(code) if v['role']=='plan']
    pipeline={};result=recognise_plan(views,pipeline)
    assert [m['size'][0] for m in result['modules']]==widths
    assert all(m['size'][1:]==[550,1600] and m['origin'][2]==0 for m in result['modules'])
    assert result['height_source']=='provisional_default'
    assert pipeline['mode']=='plan_only' and 'horizontal' not in pipeline
    assert all(p['size'][2]==1600 for p in result['trim_parts'])


def test_standalone_selected_plan_needs_no_front_or_section(tmp_path):
    plan=simple_views()[0];lines=[]
    for r in plan['rects']:
        pts=[[r.x0,r.y0],[r.x1,r.y0],[r.x1,r.y1],[r.x0,r.y1]]
        lines.extend(dict(a=a,b=b,handle=f'{r.handle}:{i}') for i,(a,b) in enumerate(zip(pts,pts[1:]+pts[:1])))
    product=run(dict(action='geometry',code='SP99',library=str(tmp_path),geometry=dict(hash='a'*64,lines=lines)))['analyses'][0]['products'][0]
    assert product['status']=='ready',product.get('error')
    assert [m['size'] for m in product['modules']]==[[800,600,1600]]
    assert product['build_stages']=={'plan':True,'elevation':False}
    assert product['learning']['mode']=='geometry'


def test_plan_stage_cannot_replay_full_height_example(tmp_path):
    class ForbiddenMemory:
        def apply(self,product):
            raise AssertionError('A full-layout example must not override plan preview')
    product=dict(build_stages={'plan':True,'elevation':False},modules=[dict(size=[800,600,1600])])
    assert replay_experience(product,tmp_path,ForbiddenMemory()) is False
    assert product['modules'][0]['size'][2]==1600


def test_no_selected_stage_returns_explicit_error(tmp_path):
    with pytest.raises(ValueError,match='Chọn giai đoạn'):
        run(dict(library=str(tmp_path),build_plan=False,build_elevation=False))


def test_plan_correction_is_not_treated_as_a_full_height_training_sample(tmp_path):
    from test_learning import sample_product,save_example
    from learning import ExperienceLibrary
    source,state=sample_product()
    source['build_stages']={'plan':True,'elevation':False}
    save_example(tmp_path,source,state)
    assert ExperienceLibrary(tmp_path).events()==[]


def test_cache_separates_plan_preview_and_full_construction(tmp_path,monkeypatch):
    import main
    monkeypatch.setattr(main,'archive_source',lambda *_:{'folder':str(tmp_path),'hash':'a'*64})
    for stage in ('full','plan1600'):
        path=tmp_path/f'analysis-{main.VERSION}-r{main.RECOGNIZER_VERSION}-{stage}.json'
        path.write_text(json.dumps({'revision':{'hash':'a'*64},'products':[{'mode':stage}]}),encoding='utf8')
    assert analyse_source('a',tmp_path,stages={'plan':True,'elevation':False})['products'][0]['mode']=='plan1600'
    def reparse(*_):raise RuntimeError('Full stage must refresh current plan feedback and section evidence')
    monkeypatch.setattr(main,'dxf_for_revision',reparse)
    with pytest.raises(RuntimeError,match='refresh current'):
        analyse_source('a',tmp_path,stages={'plan':True,'elevation':True})


def test_sp32_selected_lines_keep_short_trims_and_extend_solid_proxies_to_cabinet_depth(tmp_path):
    lines=json.loads((Path(__file__).parent/'fixtures/sp32_plan_edges.json').read_text())
    result=run(dict(action='geometry',code='SP32',library=str(tmp_path),
                    geometry=dict(hash='b'*64,lines=lines)))
    product=result['analyses'][0]['products'][0]
    assert product['status']=='ready',product.get('error')
    assert [m['size'] for m in product['modules']]==[[1164,250,1600],[432,250,1600],[1321,250,1600],[432,250,1600]]
    short=[p for p in product['trim_parts'] if p.get('original_depth_mm')==50]
    assert len(short)==2 and len(product['trim_parts'])==3
    assert sorted(p['origin'] for p in short)==[[1182,0,0],[3385,0,0]]
    assert all(p['size']==[18,250,1600] and p['solid_proxy'] for p in short)
    assert all(p['plan_box'][3]-p['plan_box'][1]==pytest.approx(50) for p in short)
    assert all(p['depth_evidence']['module_ids'] for p in short)
    assert product['bounds']==[3403,250,1600]
    assert product['placement']['mode']=='source_plan'
    assert product['placement']['origin_mm']==pytest.approx([247430.649053,652.442276])


def test_short_trim_does_not_choose_between_conflicting_adjacent_depths():
    from geometry import Rect
    from test_views import outlined
    # One short strip touches two carcasses with a shared front and different backs.
    rects=[Rect(0,0,18,500,'a'),Rect(782,0,800,500,'b'),Rect(18,482,782,500,'c'),
           Rect(818,0,836,550,'d'),Rect(1600,0,1618,550,'e'),Rect(836,532,1600,550,'f'),
           Rect(800,0,818,50,'trim')]
    view=dict(id='P',role='plan',rects=rects,outlines=outlined(rects))
    with pytest.raises(ValueError,match='Nẹp sâu 50'):
        recognise_plan([view],{})


def test_direct_scan_placement_preserves_plane_and_height_without_label(tmp_path):
    lines=json.loads((Path(__file__).parent/'fixtures/sp32_plan_edges.json').read_text())
    product=run(dict(action='geometry',code='SP97',library=str(tmp_path),
                    geometry=dict(hash='c'*64,lines=lines,plane='XY',plane_offset_mm=73)))['analyses'][0]['products'][0]
    assert product['status']=='ready'
    assert product['placement']['plane_offset_mm']==73
    assert product['placement']['plane']=='XY'
    assert 'label_id' not in product
    product=run(dict(action='geometry',code='SP97',library=str(tmp_path),
                    geometry=dict(hash='c'*64,lines=lines,plane='wrong')))['analyses'][0]['products'][0]
    assert product['status']=='needs_review' and not product['modules']


def test_scan_without_code_keeps_same_geometry_signature_for_learning(tmp_path):
    lines=json.loads((Path(__file__).parent/'fixtures/sp32_plan_edges.json').read_text())
    request=dict(action='geometry',library=str(tmp_path),geometry=dict(hash='f'*64,lines=lines,plane='XY'))
    first=run(request)['analyses'][0]['products'][0]
    second=run(request)['analyses'][0]['products'][0]
    named=run(dict(request,code='SP32'))['analyses'][0]['products'][0]
    assert first['status']=='ready' and first['automatic_scan']
    assert first['code'].startswith('SCAN-') and first['code']!=second['code']
    assert first['name']=='Vùng quét CAD'
    assert first['signature']==second['signature']==named['signature']
    assert first['modules']==second['modules']==named['modules']
    assert first['placement']==named['placement']


def test_accepted_manual_plan_boxes_replay_only_same_geometry_and_keep_height_provisional(tmp_path):
    from library import VERSION,atomic_json
    from learning import ExperienceLibrary
    signature='a'*64
    state=dict(modules=[dict(id='M1',origin=[0,0,0],size=[500,600,900]),dict(id='M2',origin=[500,0,0],size=[300,600,900])],
               trim_parts=[],panel_parts=[],bounds=[800,600,900])
    event=dict(id='accepted-boxes',signature=signature,parser_version=VERSION,status='accepted',input_axes_ignored=True,
               analysis=dict(build_stages=dict(plan=True,elevation=False)),after=state)
    atomic_json(tmp_path/'experiences'/signature/'example.json',event)
    product=dict(signature=signature,build_stages=dict(plan=True,elevation=False),envelope=[1000,2000,1800,2600],explanation=[])
    assert replay_experience(product,tmp_path)
    assert product['learning']['mode']=='plan_exact'
    assert product['manual_boxes']
    assert len(product['modules'])==2
    assert all(p['size'][2]==1600 for p in product['modules'])
    assert product['modules'][1]['source_box']==[1500,2000,1800,2600]
    assert ExperienceLibrary(tmp_path).events()==[]
    different=dict(product,signature='b'*64)
    assert not replay_experience(different,tmp_path)
