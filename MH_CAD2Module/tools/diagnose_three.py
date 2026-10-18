import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'worker'))
from geometry import Rect, inside
from views import recovered_rects, plan_columns, front_tiers, recognise_ordered

ROOT = Path(__file__).resolve().parents[1]
JOBS = {'SP28':'ce57dc67-82b6-7afd-f78b-56004c785b07',
        'SP29':'c56baeaa-c9ea-e847-c20c-9645fe3dbb5c',
        'SP30':'271e7e11-be2d-a7a2-1330-275fbd22b632'}
for code, job in JOBS.items():
    response=json.loads((ROOT/'library/jobs'/job/'response.json').read_text(encoding='utf-8-sig'))
    product=next(p for a in response['analyses'] for p in a['products'] if p['code']==code)
    rects=[Rect(*r['box'],r['handle'],r.get('layer','')) for r in product['rectangles']]
    outlines=product['outlines']+product.get('check_outlines',[])
    views=[]
    for v in product['views']:
        v=dict(v)
        v['rects']=[r for r in rects if inside(r.box(),v['region'])]
        v['outlines']=[o for o in outlines if o['points'] and all(inside([*p,*p],v['region']) for p in o['points'])]
        views.append(v)
    fixture=[{**v,'rects':[{'box':r.box(),'handle':r.handle,'layer':r.layer} for r in v['rects']]} for v in views]
    (ROOT/f'test/fixtures/{code.lower()}_views.json').write_text(json.dumps(fixture,ensure_ascii=False),encoding='utf8')
    print(code,product['error'])
    for v in views:
        print(v['id'],v['role'],len(v['rects']),len(v['outlines']))
        if v['role']=='plan':print('BAYS',[(b['box'],b['handles']) for b in plan_columns(v['rects'])])
    pipeline={}
    try:
        result=recognise_ordered(views,pipeline)
        print('SUCCESS',[(m['origin'],m['size']) for m in result['modules']],result['trim_parts'])
    except ValueError as e:print('ERROR',str(e))
    print('PIPELINE',json.dumps(pipeline,ensure_ascii=False))
    front=next(v for v in views if v['role']=='front_open')
    rs=recovered_rects(front)
