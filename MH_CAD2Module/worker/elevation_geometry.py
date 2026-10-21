"""Measured section construction, independent of the plan partition algorithm."""
from collections import defaultdict
from bisect import bisect_left,bisect_right

from geometry import Rect,TOL,covers,near,rectangle,union,inside
from materials import stock_evidence
from plan_evidence import measure_plan


def panels(rows):
    evidence=measure_plan(rows)
    from parallel_index import ParallelIndex
    index=ParallelIndex([(a,b,o['handle']) for o in rows for a,b in zip(o['points'],o['points'][1:])])
    explicit=[r for o in rows if (r:=rectangle(o['points'],o['handle'],o.get('layer','')))
              and stock_evidence(min(r.w,r.h))['stock_mm'] and max(r.w,r.h)>max(20,2*min(r.w,r.h))]
    found={tuple(round(v,4) for v in r.box()):r for r in explicit}
    for p in evidence['panels']:
        if p['kind']!='straight':continue
        box=union([[*v,*v] for side in p['boundary'] for v in side])
        # A diagonal board remains evidence, but cannot become an axial Z plane.
        if not near(min(box[2]-box[0],box[3]-box[1]),p['measured_mm']):continue
        r=Rect(*box,'|'.join(p['handles']))
        pieces=[e for e in explicit if inside(e.box(),r.box())]
        cuts=sorted({r.x0,r.x1}|{v for e in pieces for v in (e.x0,e.x1)})
        if len(pieces)>1 and all(covers([(e.y0,e.y1) for e in pieces if e.x0<=a+TOL and e.x1>=b-TOL],r.y0,r.y1)
                                for a,b in zip(cuts,cuts[1:]) if b-a>TOL):continue
        candidates=[r]
        if r.h>4*r.w and not any(inside(r.box(),e.box()) for e in explicit):
            offsets=index.groups.get(0,((),{}))[0]
            lo,hi=r.y0-index.origin[1],r.y1-index.origin[1]
            levels=[r.y0]+[v+index.origin[1] for v in offsets[bisect_right(offsets,lo+TOL):bisect_left(offsets,hi-TOL)]
                if index.covers([r.x0,v+index.origin[1]],[r.x1,v+index.origin[1]])]+[r.y1]
            candidates=[Rect(r.x0,a,r.x1,b,r.handle) for a,b in zip(levels,levels[1:]) if b-a>max(20,2*r.w)]
        for candidate in candidates:found.setdefault(tuple(round(v,4) for v in candidate.box()),candidate)
    result=list(found.values())
    # Remove an inferred36 envelope only when narrower closed panels tile it;
    # never split an explicitly drawn unbroken board.
    def tiled(r):
        pieces=[e for e in result if e is not r and inside(e.box(),r.box()) and e.w*e.h<r.w*r.h-TOL]
        cuts=sorted({r.x0,r.x1}|{v for e in pieces for v in (e.x0,e.x1)})
        return len(pieces)>1 and all(covers([(e.y0,e.y1) for e in pieces if e.x0<=a+TOL and e.x1>=b-TOL],r.y0,r.y1)
                                    for a,b in zip(cuts,cuts[1:]) if b-a>TOL)
    return [r for r in result if r in explicit or not tiled(r)],evidence.get('panel_index',{})


def extent(rects):
    return union([r.box() for r in rects]) if rects else None


def tiers(rects,depth):
    """Closed side/cap tiers; a shelf crossing continuous sides is not a tier."""
    sides=[r for r in rects if r.h>max(100,4*r.w)]
    caps=[r for r in rects if r.w>max(100,4*r.h)]
    groups=defaultdict(list)
    for r in sides:groups[(round(r.y0,3),round(r.y1,3))].append(r)
    found={}
    for (lo,hi),walls in groups.items():
        walls.sort(key=lambda r:r.x0)
        for a,b in zip(walls,walls[1:]):
            width=b.x1-a.x0
            if not .65*depth<=width<=depth+72+TOL:continue
            bottom=[r for r in caps if near(r.y0,lo) and r.x0>=a.x0-TOL and r.x1<=b.x1+TOL]
            top=[r for r in caps if near(r.y1,hi) and r.x0>=a.x0-TOL and r.x1<=b.x1+TOL]
            if not all(covers([(r.x0,r.x1) for r in row],a.x1,b.x0) for row in (bottom,top)):continue
            found[(lo,hi)]=dict(low_mm=lo,high_mm=hi,depth_mm=round(width,6),
                section_box=[a.x0,lo,b.x1,hi],handles=sorted({r.handle for r in [a,b]+bottom+top}),
                basis='closed_section_sides_and_caps')
    # Recessed backs may finish inside the cap thickness, while a door is
    # immediately outside it. Both sides must still close the measured span.
    for side in sides:
        bottom=[r for r in caps if r.y0-TOL<=side.y0<=r.y1+TOL]
        top=[r for r in caps if r.y0-TOL<=side.y1<=r.y1+TOL]
        for low in bottom:
            for high in top:
                if high.y1-low.y0<=100:continue
                x0,x1=max(low.x0,high.x0),min(low.x1,high.x1)
                if not .65*depth<=x1-x0<=depth+TOL:continue
                closed=[r for r in sides if r.y0<low.y1-TOL and r.y1>high.y0+TOL]
                left=[r for r in closed if abs(r.x1-x0)<=36+TOL]
                right=[r for r in closed if abs(r.x0-x1)<=36+TOL]
                if not left or not right:continue
                a=min(left,key=lambda r:abs(r.x1-x0));b=min(right,key=lambda r:abs(r.x0-x1))
                if a is b:continue
                box=[min(a.x0,low.x0,high.x0),low.y0,max(b.x1,low.x1,high.x1),high.y1]
                if box[2]-box[0]>depth+72+TOL:continue
                found.setdefault((round(low.y0,3),round(high.y1,3)),dict(low_mm=low.y0,high_mm=high.y1,
                    depth_mm=round(box[2]-box[0],6),section_box=box,handles=sorted({r.handle for r in (a,b,low,high)}),
                    basis='closed_section_caps_with_inset_sides'))
    result=sorted(found.values(),key=lambda r:(r['low_mm'],r['high_mm']))
    if not result:raise ValueError('Mặt cắt đứng chưa khép đủ vách/nóc/đáy để xác định tầng module.')
    for lower,upper in zip(result,result[1:]):
        if upper['low_mm']<lower['high_mm']-TOL:raise ValueError('Mặt cắt đứng có nhiều tầng ứng viên chồng nhau.')
    return result


def seam_check(rects,x0,x1,boundary):
    """An open-front unbroken side vetoes a section seam, never supplies one."""
    crossing=[r.handle for r in rects if r.h>max(100,4*r.w) and
              min(r.x1,x1)-max(r.x0,x0)>TOL and r.y0+TOL<boundary<r.y1-TOL]
    if crossing:raise ValueError('Đường chia mặt cắt cắt xuyên tấm đứng liên tục ở mặt đứng bỏ cánh: '+', '.join(crossing[:4]))


def marker_axis(marker):
    cut=marker.get('cut_line')
    if not cut or len(cut)!=2:return None
    dx,dy=[abs(cut[1][i]-cut[0][i]) for i in (0,1)]
    if max(dx,dy)<=TOL:return None
    return 'vertical' if dx<=TOL else 'horizontal' if dy<=TOL else 'oblique'
