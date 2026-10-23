# Reference only: previous exhaustive parallel evidence scan, retired in0.15.0.
from collections import defaultdict
import math
from geometry import TOL
from materials import BOARD_MM,stock_evidence
from plan_evidence import edge_key,covers_segment

def _legacy_straight_panels(lines,arc_edges):
    groups=defaultdict(list)
    for a,b,handle in lines:
        if edge_key(a,b) in arc_edges:continue
        length=math.dist(a,b)
        if length<TOL:continue
        u=[(b[i]-a[i])/length for i in (0,1)]
        if u[0]<-1e-8 or abs(u[0])<1e-8 and u[1]<0:u=[-v for v in u]
        n=[-u[1],u[0]];offset=sum(n[i]*a[i] for i in (0,1))
        lo,hi=sorted(sum(u[i]*p[i] for i in (0,1)) for p in (a,b))
        groups[round(math.atan2(u[1],u[0]),6)].append(dict(u=u,n=n,offset=offset,lo=lo,hi=hi,handles=[handle]))
    panels=[]
    for members in groups.values():
        merged=[]
        for edge in sorted(members,key=lambda e:(round(e['offset'],3),e['lo'])):
            if merged and abs(edge['offset']-merged[-1]['offset'])<.002 and edge['lo']<=merged[-1]['hi']+TOL:
                merged[-1]['hi']=max(edge['hi'],merged[-1]['hi']);merged[-1]['handles'].extend(edge['handles'])
            else:merged.append(dict(edge))
        for i,a in enumerate(merged):
            for b in merged[i+1:]:
                thickness=abs(b['offset']-a['offset'])
                if thickness>max(BOARD_MM)+TOL:break
                stock=stock_evidence(thickness)['stock_mm']
                if not stock:continue
                lo=max(a['lo'],b['lo']);hi=min(a['hi'],b['hi'])
                if hi-lo<=max(20,thickness*2):continue
                def point(edge,t):return [edge['u'][j]*t+edge['n'][j]*edge['offset'] for j in (0,1)]
                sides=[[point(edge,t) for t in (lo,hi)] for edge in (a,b)]
                if not all(covers_segment(sides[0][j],sides[1][j],lines) for j in (0,1)):continue
                seams=sorted({round(abs(c['offset']-a['offset']),3) for c in merged
                    if a['offset']+TOL<c['offset']<b['offset']-TOL and c['lo']<=lo+TOL and c['hi']>=hi-TOL})
                panels.append(dict(kind='straight',measured_mm=round(thickness,6),stock_mm=stock,
                    length_mm=round(hi-lo,6),boundary=sides,internal_seams_mm=seams,
                    lamination_candidate=[18,18] if stock==36 else None,
                    handles=sorted(set(a['handles']+b['handles'])),evidence='parallel_faces_and_closed_ends'))
    return panels


