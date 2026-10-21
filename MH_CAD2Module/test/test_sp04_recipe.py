import json
from pathlib import Path
import sys

from geometry import Rect, overlapping_modules
from views import recognise_ordered
from main import replay_experience
from library import VERSION

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from resolve_sp04_geometry import resolve


def test_user_confirmed_wall_stays_thin_and_cabinet_modules_include_doors():
    rows=json.loads((Path(__file__).parent/'fixtures/sp04_views.json').read_text(encoding='utf8'))
    views=[];rects=[];outlines=[];check=[]
    for row in rows:
        view=dict(row);view['rects']=[Rect(*r['box'],r['handle'],r['layer']) for r in view.pop('rectangles')]
        views.append(view);rects.extend(r.as_dict() for r in view['rects'])
        (check if view['role']=='front_check' else outlines).extend(view['outlines'])
    pipe={}
    try:recognise_ordered(views,pipe)
    except ValueError:pass
    result=resolve({'rectangles':rects,'views':[{k:v for k,v in row.items() if k not in ('rects','outlines')} for row in views],
                    'outlines':outlines,'check_outlines':check,'geometry_pipeline':pipe,'error':'geometry ambiguity'})
    assert len(result['modules'])==11 and not overlapping_modules(result['modules'])
    assert [m['size'][2] for m in result['modules'][:8]]==[860]*4+[1390]*4
    assert all(m['size'][1]==360 and m['origin'][1]==0 and m['scope']=='carcass_and_doors' for m in result['modules'][:8])
    bases=result['modules'][8:10]
    assert [m['size'] for m in bases]==[[1698,360,250]]*2
    assert [m['supports_module_ids'] for m in bases]==[['M01','M02'],['M03','M04']]
    assembly=result['modules'][10]
    assert assembly['size']==[1600,48,2500] and assembly['origin']==[1782,312,0]
    wall=[p for p in assembly['panel_parts'] if p['role']=='wall_panel']
    assert [p['size'] for p in wall]==[[1600,18,2400],[1600,18,100]]
    assert wall[0]['origin'][1:]==[12,0] and wall[1]['origin'][1:]==[12,2400]
    back=[p for p in assembly['panel_parts'] if p['role']=='back_trim']
    assert len(back)==2 and all(p['size']==[50,18,2500] and p['origin'][1]==30 for p in back)
    assert len(assembly['panel_parts'])==23 and result['panel_parts']==[]
    assert result['bounds']==[5200,360,2680]


def test_accepted_geometry_role_correction_recovers_missing_bounds_and_panels(tmp_path):
    signature='a'*64
    folder=tmp_path/'experiences'/signature;folder.mkdir(parents=True)
    after={'modules':[{'id':'M01','size':[1126,360,860],'origin':[42,0,250]}],
           'panel_parts':[{'id':'P01','role':'wall_panel','size':[1600,18,2400],'origin':[1782,324,0]}],
           'trim_parts':[],'bounds':[5200,360,2680]}
    (folder/'accepted.json').write_text(json.dumps({'id':'confirmed-wall','status':'accepted','parser_version':VERSION,
                                                   'signature':signature,'after':after}),encoding='utf8')
    product={'signature':signature,'status':'needs_review','modules':[],'error':'wall mistaken for cabinet'}
    replay_experience(product,tmp_path)
    assert product['status']=='ready' and 'error' not in product
    assert product['bounds']==after['bounds'] and product['panel_parts']==after['panel_parts']


def test_experience_preserves_nested_wall_parts_and_rejects_invalid_child(tmp_path):
    signature='b'*64;folder=tmp_path/'experiences'/signature;folder.mkdir(parents=True)
    wall={'id':'M11','size':[1600,48,2500],'origin':[1782,312,0],
          'panel_parts':[{'id':'P01','size':[1600,18,2400],'origin':[0,12,0]}]}
    event={'id':'eleven-modules','status':'accepted','signature':signature,'parser_version':VERSION,
           'after':{'modules':[wall],'bounds':[5200,360,2680]}}
    path=folder/'accepted.json';path.write_text(json.dumps(event),encoding='utf8')
    product={'signature':signature,'status':'needs_review','modules':[]}
    replay_experience(product,tmp_path)
    assert product['modules'][0]['panel_parts']==wall['panel_parts']
    wall['panel_parts'][0]['size'][1]=0
    path.write_text(json.dumps(event),encoding='utf8')
    rejected={'signature':signature,'status':'needs_review','modules':[]}
    replay_experience(rejected,tmp_path)
    assert rejected['status']=='needs_review' and rejected['modules']==[]
