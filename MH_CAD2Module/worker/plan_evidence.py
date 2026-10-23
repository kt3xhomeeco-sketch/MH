"""Measured envelope, bounded stock strips and concentric circular panel evidence."""
from collections import OrderedDict
from copy import deepcopy
import hashlib
import json
import math

from geometry import TOL, union
from materials import BOARD_MM, stock_evidence
from plan_profiles import arc_runs, arc_bounds
from cad_style import structural_rows, interrupted

_MEASURES=OrderedDict()


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
    from parallel_index import ParallelIndex
    return ParallelIndex(lines,arc_edges).panels()


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
    source=[(a,b,o['handle']) for o in outlines for a,b in zip(o['points'],o['points'][1:])]
    if not source:return dict(schema=1,envelope=None,panels=[],arcs=[],stock_counts={})
    # Only fields that change structural eligibility affect this evidence cache.
    key=hashlib.sha256(json.dumps([source,[interrupted(o) for o in outlines]],separators=(',',':')).encode()).hexdigest()
    if key in _MEASURES:
        _MEASURES.move_to_end(key)
        return deepcopy(_MEASURES[key])
    rows=structural_rows(outlines)
    lines=[(a,b,o['handle']) for o in rows for a,b in zip(o['points'],o['points'][1:])]
    arcs=arc_runs(rows)
    arc_edges={e for arc in arcs for e in arc['source_edges']}
    from parallel_index import ParallelIndex
    index=ParallelIndex(lines,arc_edges)
    panels=index.panels()+curved_panels(arcs,lines)
    counts={str(stock):sum(p['stock_mm']==stock for p in panels) for stock in BOARD_MM}
    envelope=union([[*p,*p] for a,b,_ in source for p in (a,b)])
    if arcs:envelope=union([envelope]+[arc_bounds(a) for a in arcs])
    result=dict(schema=1,envelope=envelope,panels=panels,
        arcs=[{k:v for k,v in arc.items() if k!='source_edges'} for arc in arcs],stock_counts=counts,
        panel_index=dict(method='stock_offset_lookup',directions=len(index.groups),faces=sum(len(g[0]) for g in index.groups.values()),offset_probes=index.probes,candidate_pairs=index.pair_checks),
        standards_mm=list(BOARD_MM),interpretation='Geometric plate candidates; stock spacing alone is not a module boundary.')
    _MEASURES[key]=deepcopy(result)
    if len(_MEASURES)>16:_MEASURES.popitem(last=False)
    return result
