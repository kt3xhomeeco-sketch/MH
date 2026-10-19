"""Measured envelope, bounded stock strips and concentric circular panel evidence."""
from collections import defaultdict
import math

from geometry import TOL, union
from materials import BOARD_MM, stock_evidence
from plan_profiles import arc_runs, arc_bounds


def edge_key(a,b):
    return tuple(sorted(tuple(round(v,3) for v in p) for p in (a,b)))


def covers_segment(a,b,lines):
    length=math.dist(a,b)
    if length<TOL:return False
    u=[(b[i]-a[i])/length for i in (0,1)];spans=[]
    for p,q,_ in lines:
        if any(abs((v[0]-a[0])*u[1]-(v[1]-a[1])*u[0])>TOL for v in (p,q)):continue
        spans.append(sorted(sum((v[i]-a[i])*u[i] for i in (0,1)) for v in (p,q)))
    reach=0
    for lo,hi in sorted(spans):
        if hi<-TOL or lo>length+TOL:continue
        if lo>reach+TOL:return False
        reach=max(reach,hi)
        if reach>=length-TOL:return True
    return False


def straight_panels(lines,arc_edges):
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


def curved_panels(arcs,lines):
    result=[]
    for i,a in enumerate(arcs):
        for b in arcs[i+1:]:
            if math.dist(a['center'],b['center'])>.02:continue
            measured=abs(a['radius']-b['radius']);stock=stock_evidence(measured)['stock_mm']
            if not stock or abs(abs(a['sweep'])-abs(b['sweep']))>.001:continue
            pairs=None
            for order in ((b['start'],b['end']),(b['end'],b['start'])):
                candidate=list(zip((a['start'],a['end']),order))
                if all(abs(math.dist(p,q)-measured)<=TOL and covers_segment(p,q,lines) for p,q in candidate):pairs=candidate;break
            if not pairs:continue
            result.append(dict(kind='arc',measured_mm=round(measured,6),stock_mm=stock,
                center=a['center'],inner_radius=min(a['radius'],b['radius']),outer_radius=max(a['radius'],b['radius']),
                sweep=abs(a['sweep']),caps=pairs,handles=sorted(set(a['handles']+b['handles'])),
                lamination_candidate=[18,18] if stock==36 else None,evidence='concentric_arcs_and_closed_radial_ends'))
    return result


def measure_plan(outlines):
    lines=[(a,b,o['handle']) for o in outlines for a,b in zip(o['points'],o['points'][1:])]
    if not lines:return dict(schema=1,envelope=None,panels=[],arcs=[],stock_counts={})
    arcs=arc_runs(outlines)
    arc_edges={e for arc in arcs for e in arc['source_edges']}
    panels=straight_panels(lines,arc_edges)+curved_panels(arcs,lines)
    counts={str(stock):sum(p['stock_mm']==stock for p in panels) for stock in BOARD_MM}
    envelope=union([[*p,*p] for a,b,_ in lines for p in (a,b)])
    if arcs:envelope=union([envelope]+[arc_bounds(a) for a in arcs])
    return dict(schema=1,envelope=envelope,panels=panels,
        arcs=[{k:v for k,v in arc.items() if k!='source_edges'} for arc in arcs],stock_counts=counts,
        standards_mm=list(BOARD_MM),interpretation='Geometric plate candidates; stock spacing alone is not a module boundary.')
