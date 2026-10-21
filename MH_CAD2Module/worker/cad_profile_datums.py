"""Closed thin faces from indexed endpoints, including a board's bevelled ends."""
from bisect import bisect_left,bisect_right
from collections import defaultdict
import math

from geometry import TOL
from materials import BOARD_MM
from parallel_index import ParallelIndex


def stock_profile(points):
    area=abs(sum((a[0]-points[0][0])*(b[1]-points[0][1])-(b[0]-points[0][0])*(a[1]-points[0][1]) for a,b in zip(points,points[1:])))/2
    perimeter=sum(math.dist(a,b) for a,b in zip(points,points[1:]))
    if not perimeter or not area or 2*area/perimeter>max(BOARD_MM)+TOL:return False
    index=ParallelIndex([(a,b,'profile') for a,b in zip(points,points[1:])])
    for _,(offsets,faces) in index.groups.items():
        for left in offsets:
            for stock in BOARD_MM:
                for right in offsets[bisect_left(offsets,left+stock-TOL):bisect_right(offsets,left+stock+TOL)]:
                    for lo,hi,_ in faces[left][0]:
                        spans,ends=faces[right];i=bisect_left(ends,lo)
                        while i<len(spans) and spans[i][0]<hi:
                            if min(hi,spans[i][1])-max(lo,spans[i][0])>max(20,2*stock):return True
                            i+=1
    return False


def closed_faces(rows):
    lines=[(a,b,r['handle']) for r in rows for a,b in zip(r['points'],r['points'][1:]) if math.dist(a,b)>TOL]
    coords={tuple(round(v,3) for v in p):p for a,b,_ in lines for p in (a,b)}
    axes=[defaultdict(list),defaultdict(list)]
    for key in coords:
        for i in (0,1):axes[i][key[i]].append(key[1-i])
    for axis in axes:
        for values in axis.values():values.sort()
    graph=defaultdict(set);handles=defaultdict(set)
    for a,b,handle in lines:
        start,end=[tuple(round(v,3) for v in p) for p in (a,b)];cuts=[start,end]
        for i in (0,1):
            if start[i]!=end[i]:continue
            lo,hi=sorted((start[1-i],end[1-i]));values=axes[i][start[i]]
            cuts=[(start[i],v) if i==0 else (v,start[i]) for v in values[bisect_left(values,lo):bisect_right(values,hi)]]
            break
        cuts.sort()
        for u,v in zip(cuts,cuts[1:]):
            if u==v:continue
            graph[u].add(v);graph[v].add(u);handles[tuple(sorted((u,v)))].add(handle)
    order={p:sorted(ns,key=lambda q:math.atan2(q[1]-p[1],q[0]-p[0])) for p,ns in graph.items()}
    successor={(q,p):ns[(i-1)%len(ns)] for p,ns in order.items() for i,q in enumerate(ns)}
    seen=set();result=[]
    for start,ns in order.items():
        for second in ns:
            if (start,second) in seen:continue
            a,b=start,second;loop=[];used=set()
            while (a,b) not in seen:
                seen.add((a,b));loop.append(a);used.update(handles[tuple(sorted((a,b)))])
                a,b=b,successor[(a,b)]
            if (a,b)!=(start,second) or not 4<=len(loop)<=256 or len(set(loop))!=len(loop):continue
            ps=[coords[p] for p in loop]+[coords[loop[0]]]
            # Only bounded faces; the exterior contour must not fuse all boards.
            area=sum((a[0]-ps[0][0])*(b[1]-ps[0][1])-(b[0]-ps[0][0])*(a[1]-ps[0][1]) for a,b in zip(ps,ps[1:]))
            if area>0 and stock_profile(ps):
                result.append(dict(box_mm=[min(p[0] for p in ps),min(p[1] for p in ps),max(p[0] for p in ps),max(p[1] for p in ps)],handles=sorted(used)))
    return result
