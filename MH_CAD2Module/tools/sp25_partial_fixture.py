"""Check the actual indexed DWG without changing any SketchUp model."""
import json
import sys
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'worker'))
from main import analyse_source

if __name__=='__main__':
    prior=json.loads((ROOT/'outputs/sp25-pre-partition-product.json').read_text('utf8'))
    timings=[]
    for _ in range(2):
        started=time.perf_counter()
        result=analyse_source(prior['source_path'],ROOT/'library',targets=['SP25'])
        p=result['products'][0];timings.append(dict(seconds=time.perf_counter()-started,cache=p['source_cache']))
        c=p['plan_results'][0]
        assert len(p['plan_results'])==1 and c['partial_plan']['span_mm']==[0,2610]
        assert c['partial_plan']['confirmed_modules']==7 and c['partial_plan']['unresolved_modules']==1
    (ROOT/'outputs/sp25-partial-product.json').write_text(json.dumps(p,ensure_ascii=False),'utf8')
    (ROOT/'outputs/sp25-partial-timings.json').write_text(json.dumps(timings,indent=2),'utf8')
    print(json.dumps(dict(timings=timings,parts=[dict(name=m['name'],origin=m['origin'],size=m['size'],pending=m.get('unresolved',False)) for m in c['modules']]),ensure_ascii=False))
