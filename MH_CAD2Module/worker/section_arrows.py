"""Read visible arrow chevrons inside a section symbol, including nested blocks."""
from collections import defaultdict
from itertools import combinations
import math


def visible_lines(entities,scale,depth=0):
    if depth>12:return []
    result=[]
    for entity in entities:
        if entity.dxf.get('invisible',0):continue
        if entity.dxftype()=='INSERT':result.extend(visible_lines(entity.virtual_entities(),scale,depth+1))
        elif entity.dxftype()=='LINE':
            result.append([[p.x*scale,p.y*scale] for p in (entity.dxf.start,entity.dxf.end)])
    return result


def arrow_evidence(lines,cut):
    if not cut:return {}
    axis=0 if abs(cut[1][0]-cut[0][0])<.15 else 1
    tangent=1-axis;nodes=defaultdict(list);length=math.dist(*cut)
    for a,b in lines:
        if not .15<math.dist(a,b)<length*.25:continue
        nodes[tuple(round(v,3) for v in a)].append(b)
        nodes[tuple(round(v,3) for v in b)].append(a)
    heads=[]
    for tip,tails in nodes.items():
        if len(tails)>8:continue
        for a,b in combinations(tails,2):
            middle=[(a[i]+b[i])/2 for i in (0,1)];normal=tip[axis]-middle[axis];span=abs(a[tangent]-b[tangent])/2
            if abs(a[axis]-b[axis])>.15 or abs(tip[tangent]-middle[tangent])>.15 or not .25*span<abs(normal)<4*span:continue
            if (a[tangent]-tip[tangent])*(b[tangent]-tip[tangent])>=0:continue
            if min(abs(tip[tangent]-p[tangent]) for p in cut)>4*max(span,abs(normal)):continue
            heads.append(dict(tip=list(tip),tail_a=a,tail_b=b))
    signs={1 if h['tip'][axis]>(h['tail_a'][axis]+h['tail_b'][axis])/2 else -1 for h in heads}
    if len(signs)!=1:return {}
    direction=[0,0];direction[axis]=signs.pop()
    return dict(view_direction=direction,arrow_heads=heads)
