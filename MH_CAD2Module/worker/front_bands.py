"""Cross-check cropped fronts at three data-derived horizontal heights."""
from collections import defaultdict,Counter
from copy import deepcopy

from cad_datums import measure
from geometry import TOL,near
from materials import BOARD_MM
from view_signatures import align,signature,match


def sample_heights(rows,floors):
    events=defaultdict(list)
    for side,body in enumerate(rows):
        datum=measure(body,[0,0])
        if not datum:return []
        for p in datum['panels']:
            x,y,r,t=p['box_mm'];width=r-x
            if t-y<=max(40,3*width) or not any(near(width,s) for s in BOARD_MM):continue
            key=(round(x/TOL),round(r/TOL))
            events[round(y-floors[side],6)].append((side,key,1))
            events[round(t-floors[side],6)].append((side,key,-1))
    active=[Counter(),Counter()];bands=[];levels=sorted(events)
    for i,z in enumerate(levels[:-1]):
        for side,key,delta in events[z]:
            active[side][key]+=delta
            if active[side][key]<=0:del active[side][key]
        end=levels[i+1];rank=min(len(v) for v in active)
        if rank>=2 and end-z>4*TOL:bands.append((max(0,z),end,rank))
    bands=[b for b in bands if b[1]>b[0]+4*TOL]
    if not bands:return []
    best=max(b[2] for b in bands);bands=[b for b in bands if b[2]==best]
    total=sum(b-a for a,b,_ in bands);heights=[]
    for fraction in (.2,.5,.8):
        distance=total*fraction
        for a,b,_ in bands:
            if distance<=b-a:
                z=round(a+distance,6)
                if not any(near(z,old) for old in heights):heights.append(z)
                break
            distance-=b-a
    return heights


def verify(target,source,target_floor,source_floor):
    levels=sample_heights((target,source),(target_floor,source_floor));checks=[]
    for z in levels:
        at,other=target_floor+z,source_floor+z
        result=match(signature(target,0,at),signature(source,0,other))
        checks.append(dict(height_mm=z,target_slice=round(at,6),source_slice=round(other,6),**result))
    poses=[]
    for check in checks:
        for c in check['candidates']:
            old=next((p for p in poses if near(p['offset_mm'],c['offset_mm'])),None)
            if old is None:poses.append(dict(offset_mm=c['offset_mm']))
    for p in poses:
        votes=[(i,c) for i,check in enumerate(checks) for c in check['candidates'] if near(c['offset_mm'],p['offset_mm'])]
        p['support']=len({i for i,_ in votes});p['ratio']=sum(c['coverage'] for _,c in votes)/len(checks)
        p['pairs']=sum(c['matched_pairs'] for _,c in votes)
    poses.sort(key=lambda p:(p['ratio'],p['support'],p['pairs']),reverse=True)
    if not poses or poses[0]['support']<2:return dict(status='insufficient',height_checks=checks)
    best=poses[0]
    tied=[p for p in poses if abs(p['ratio']-best['ratio'])<.000001 and p['support']==best['support']]
    if len(tied)!=1:return dict(status='ambiguous',height_checks=checks)
    matching=[dict(check,candidates=[c],status='proven',**{k:v for k,v in c.items() if k not in ('matches','candidates','status')})
              for check in checks for c in check['candidates'] if near(c['offset_mm'],best['offset_mm'])]
    primary=max(matching,key=lambda c:(c['coverage'],c['matched_pairs']))
    result={k:deepcopy(v) for k,v in primary.items() if k!='height_mm'}
    result.update(status='proven',height_checks=checks,height_support=best['support'],band_ratio=round(best['ratio'],6),
        reason='Hai mặt khớp qua chuỗi ván tại nhiều cao độ; phần bị lược bỏ không kéo lệch mốc ghép.')
    return result


def align_fronts(target,source,target_floor=None,source_floor=None):
    result=align(target,source)
    # Complete, fully agreeing views need no extra sweep. Partial/failed matches
    # are checked at no more than three levels selected from actual board spans.
    partial=min(result.get('target_coverage',0),result.get('source_coverage',0))<.8
    if result['status']=='proven' and not partial:return result
    if target_floor is None:target_floor=min(p[1] for r in target for p in r['points'])
    if source_floor is None:source_floor=min(p[1] for r in source for p in r['points'])
    bands=verify(target,source,target_floor,source_floor)
    if bands['status']=='proven':return bands
    if bands.get('height_checks'):result['height_checks']=bands['height_checks']
    return result
