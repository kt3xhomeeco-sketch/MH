"""Measured plan plates: parallel OY faces, stock spacing and aligned depth runs."""
from collections import defaultdict
from bisect import bisect_left, bisect_right
from geometry import Rect, TOL, near, covers
from materials import BOARD_MM
from plan_profiles import arc_runs, stepped_regions
from plan_evidence import edge_key
from cad_style import structural_rows, interrupted

ENGINE = 'oy-stock-sweep-v1'


def axes(outlines):
    outlines=structural_rows(outlines)
    arcs=arc_runs(outlines)
    curved={e for arc in arcs for e in arc['source_edges']}
    groups=[defaultdict(list),defaultdict(list)]
    for row in outlines:
        for a,b in zip(row['points'],row['points'][1:]):
            if edge_key(a,b) in curved:continue
            for axis in (0,1):
                other=1-axis
                if abs(a[axis]-b[axis])>.001 or abs(a[other]-b[other])<=TOL:continue
                key=round((a[axis]+b[axis])/2,3)
                lo,hi=sorted((a[other],b[other]))
                groups[axis][key].append((lo,hi,str(row['handle'])))
    for group in groups:
        for key,intervals in group.items():
            merged=[]
            for lo,hi,handle in sorted(intervals):
                if not merged or lo>merged[-1][1]+TOL:merged.append([lo,hi,{handle}])
                else:merged[-1][1]=max(hi,merged[-1][1]);merged[-1][2].add(handle)
            group[key]=merged
    return groups,arcs


def proof(intervals,lo,hi):
    for a,b,handles in intervals:
        if a-TOL<=lo and hi<=b+TOL:return handles
    return None


def framed_front(r,groups,xs,ys):
    """A stock infill can sit inside two closed, protruding door end profiles.

    Probe caps only within36 mm of each infill end. A long inset front stroke,
    full rear stroke and matching cap starts prove the measured assembly band.
    """
    if not any(near(r.h,s) for s in BOARD_MM) or r.w<=100:return None
    candidates=[]
    caps=[]
    for low,high in ((r.x0-max(BOARD_MM)-TOL,r.x0+TOL),(r.x1-TOL,r.x1+max(BOARD_MM)+TOL)):
        ends=[]
        for x in xs[bisect_left(xs,low):bisect_right(xs,high)]:
            for a,b,handles in groups[0][x]:
                if r.y0-max(BOARD_MM)-TOL<=a<r.y0-TOL and b>=r.y1-TOL:ends.append((x,a,handles))
        caps.append(ends)
    for left,low,lh in caps[0]:
        for right,other,rh in caps[1]:
            if not near(low,other):continue
            back=proof(groups[1].get(round(r.y1,3),[]),left,right)
            if not back:continue
            for y in ys[bisect_left(ys,low-TOL):bisect_left(ys,r.y0-TOL)]:
                front=proof(groups[1][y],left+max(BOARD_MM),right-max(BOARD_MM))
                if front:
                    candidates.append(Rect(left,low,right,r.y1,'+'.join(sorted(lh|rh|back|front|{r.handle})),'front_envelope'))
                    break
    return min(candidates,key=lambda p:(p.y0,-p.w)) if candidates else None


def plates(outlines):
    groups,arcs=axes(outlines);found={};checks=0
    for axis in (0,1):
        other=1-axis;primary=groups[axis];secondary=groups[other];positions=sorted(primary);cap_positions=sorted(secondary)
        for left in positions:
            neighbours={right for stock in BOARD_MM for right in positions[
                bisect_left(positions,left+stock-TOL):bisect_right(positions,left+stock+TOL)]}
            for right in sorted(neighbours):
                distance=right-left
                if distance>max(BOARD_MM)+TOL:break
                stock=next((s for s in BOARD_MM if near(distance,s)),None)
                if not stock:continue
                for lo,hi,left_handles in sorted(primary[left],key=lambda r:r[0]-r[1]):
                    for a,b,right_handles in primary[right]:
                        low,high=max(lo,a),min(hi,b)
                        if high-low<=max(20,2*stock):continue
                        caps={y:handles for y in cap_positions[bisect_left(cap_positions,low-TOL):bisect_right(cap_positions,high+TOL)]
                              if (handles:=proof(secondary[y],left,right))}
                        if len(caps)<2:continue
                        bottom,top=min(caps),max(caps)
                        # Keep near-end alternatives: a tiny hinge/overlay line
                        # must not erase the depth shared by the other walls.
                        starts=[y for y in caps if y<=bottom+max(BOARD_MM)+TOL]
                        ends=[y for y in caps if y>=top-max(BOARD_MM)-TOL]
                        spans={(start,end) for start in starts for end in ends}
                        if axis==1:
                            # Short horizontal returns are auxiliary evidence;
                            # recover them after the long depth-side pass.
                            keys=sorted(caps)
                            for i,start in enumerate(keys):
                                for end in keys[i+1:]:
                                    if end-start>2*max(BOARD_MM)+TOL:break
                                    spans.add((start,end))
                        for start,end in sorted(spans):
                            checks+=1
                            if end-start<=max(20,2*stock):continue
                            box=[left,start,right,end] if axis==0 else [start,left,end,right]
                            handles=left_handles|right_handles|caps[start]|caps[end]
                            key=tuple(round(v,3) for v in box)
                            found[key]=Rect(*box,'+'.join(sorted(handles)),'2 cat nt')
                            if len(found)>20000:raise ValueError('Quá nhiều tấm ứng viên; quét gọn một mặt bằng.')
    frontage=[]
    vertical_positions=sorted(groups[0])
    horizontal_positions=sorted(groups[1])
    for r in list(found.values()):
        framed=framed_front(r,groups,vertical_positions,horizontal_positions)
        if framed:frontage.append(framed)
        if not any(near(r.h,s) for s in BOARD_MM) or r.w<=100:continue
        for y in horizontal_positions[bisect_left(horizontal_positions,r.y0-max(BOARD_MM)-TOL):bisect_left(horizontal_positions,r.y0-TOL)]:
            if not TOL<r.y0-y<=max(BOARD_MM)+TOL:continue
            bottom=proof(groups[1][y],r.x0,r.x1)
            left=proof(groups[0].get(round(r.x0,3),[]),y,r.y0)
            right=proof(groups[0].get(round(r.x1,3),[]),y,r.y0)
            if bottom and left and right:
                # A closed door/front assembly can include a non-stock lip or
                # gap. It extends the footprint, never counts as another board.
                frontage.append(Rect(r.x0,y,r.x1,r.y1,'+'.join(sorted(bottom|left|right|{r.handle})),'front_envelope'))
    for r in frontage:found.setdefault(tuple(round(v,3) for v in r.box()),r)
    return sorted(found.values(),key=lambda r:(r.x0,r.y0,r.x1,r.y1)),dict(
        engine=ENGINE,vertical_lines=len(groups[0]),horizontal_lines=len(groups[1]),
        stock_pairs_checked=checks,recovered_arcs=len(arcs),direction='X ascending; faces parallel OY',
        standards_mm=list(BOARD_MM),front_assemblies=len(frontage),
        excluded_interrupted=sum(interrupted(o) for o in outlines),
        excluded_handles=[str(o['handle']) for o in outlines if interrupted(o)][:16])


def walls(rects):
    vertical=[r for r in rects if any(near(r.w,s) for s in BOARD_MM) and 100<=r.h<=1200 and r.h>2*r.w]
    horizontal=[r for r in rects if (any(near(r.h,s) for s in BOARD_MM) or r.layer=='front_envelope') and r.w>r.h*2]
    rows=[]
    for r in vertical:
        fronts=[p for p in horizontal if near(p.y1,r.y0) and p.x0-TOL<=r.x0 and r.x1<=p.x1+TOL]
        front=min([r.y0]+[p.y0 for p in fronts])
        rows.append(dict(box=[r.x0,front,r.x1,r.y1],core=r.box(),stock=r.w,
                         handles=[r.handle]+[p.handle for p in fronts]))
    # A 36 mm outer envelope with an explicit 18+18 seam is two atomic plates.
    eighteen=defaultdict(list)
    for r in rows:
        if near(r['stock'],18):eighteen[round(r['box'][0],3)].append(r)
    def compound(r):
        return near(r['stock'],36) and any(a is not b and near(b['box'][2],r['box'][2]) and
            all(near(a['box'][i],r['box'][i]) and near(b['box'][i],r['box'][i]) for i in (1,3))
            for a in eighteen[round(r['box'][0],3)] for b in eighteen[round(a['box'][2],3)])
    rows=[r for r in rows if not compound(r)]
    def support(row):
        return len({(round(r['box'][0],3),round(r['box'][2],3)) for r in rows
                    if near(r['box'][1],row['box'][1]) and near(r['box'][3],row['box'][3])})
    chosen=defaultdict(list)
    def variant(a,b):
        x,y=a['core'],b['core']
        if min(x[3],y[3])-max(x[1],y[1])<=TOL:return False
        if any(abs(x[i]-y[i])>max(BOARD_MM)+TOL for i in (1,3)):return False
        same=all(near(x[i],y[i]) for i in (1,3))
        shared=set(a['handles'][0].split('+')) & set(b['handles'][0].split('+'))
        return same or bool(shared)
    for row in sorted(rows,key=lambda r:(support(r),r['box'][3]-r['box'][1]),reverse=True):
        key=tuple(round(row['box'][i],3) for i in (0,2))
        # Compare only retained representatives; discarded variants cannot bridge
        # two independent ranges through a transitive overlap chain.
        if not any(variant(row,other) for other in chosen[key]):chosen[key].append(row)
    return sorted((r for group in chosen.values() for r in group),key=lambda r:(r['box'][0],r['box'][1]))


def bays(rects,outlines):
    sides=walls(rects);groups=[]
    for wall in sides:
        group=next((g for g in groups if near(g[0]['core'][1],wall['core'][1]) and near(g[0]['core'][3],wall['core'][3])),None)
        if group is None:groups.append([wall])
        else:group.append(wall)
    horizontal=[r for r in rects if any(near(r.h,s) for s in BOARD_MM) and r.w>r.h*2]
    candidates=[];joins=[]
    for group in sorted(groups,key=lambda g:g[0]['box'][1]-g[0]['box'][3]):
        ordered=sorted(group,key=lambda w:w['box'][0])
        cells=[]
        for left,right in zip(ordered,ordered[1:]):
            a,b=left['box'],right['box']
            if near(a[2],b[0]) and near(left['stock'],18) and near(right['stock'],18):
                joins.append(dict(x=a[2],y=[a[1],a[3]],pattern=[18,18],priority='shared_face'))
            if b[0]-a[2]<100:continue
            caps={}
            for p in horizontal:
                if a[1]-TOL<=p.y0 and p.y1<=a[3]+TOL:
                    caps.setdefault((round(p.y0,3),round(p.y1,3)),[]).append(p)
            closing=next((rs for rs in caps.values() if covers([(r.x0,r.x1) for r in rs],a[2],b[0])),None)
            if not closing:continue
            # A shared front rail alone cannot close a gap between cabinets.
            # Inset6 mm backs are valid closure near the rear ends of the sides.
            rear=[p for p in horizontal if p.y1>=a[3]-2*max(BOARD_MM)-TOL and p.y0<=a[3]+TOL]
            rear_rows={}
            for p in rear:rear_rows.setdefault((round(p.y0,3),round(p.y1,3)),[]).append((p.x0,p.x1))
            if not any(covers(spans,a[2],b[0]) for spans in rear_rows.values()):continue
            box=[a[0],min(a[1],b[1]),b[2],a[3]]
            cells.append(dict(box=box,core_box=[left['core'][0],min(left['core'][1],right['core'][1]),right['core'][2],a[3]],
                handles=left['handles']+right['handles']+[r.handle for r in closing],rule=ENGINE))
        merged=[]
        for cell in cells:
            if merged and cell['box'][0]<merged[-1]['box'][2]-TOL:
                # One shared plate is internal structure. Two touching plates
                # create adjacent, non-overlapping cells at their shared face.
                merged[-1]['box'][2]=cell['box'][2]
                merged[-1]['core_box'][2]=cell['core_box'][2]
                merged[-1]['handles']+=cell['handles']
            else:merged.append(cell)
        for cell in merged:
            box=cell['box']
            if any(all(min(box[i+2],c['box'][i+2])-max(box[i],c['box'][i])>TOL for i in (0,1)) for c in candidates):continue
            candidates.append(cell)
    candidates.extend(stepped_regions(rects,outlines,candidates))
    for seam in joins:
        left=any(near(b['box'][2],seam['x']) and near(b['box'][1],seam['y'][0]) and near(b['box'][3],seam['y'][1]) for b in candidates)
        right=any(near(b['box'][0],seam['x']) and near(b['box'][1],seam['y'][0]) and near(b['box'][3],seam['y'][1]) for b in candidates)
        seam['role']='module_boundary' if left and right else 'outer_plate_or_auxiliary' if left or right else 'unassigned'
    return sorted(candidates,key=lambda b:b['box'][0]),dict(
        walls=[dict(box=r['box'],source_box=r['core'],stock_mm=r['stock']) for r in sides],
        joins=joins,depth_groups=[dict(y=[g[0]['box'][1],g[0]['box'][3]],walls=len(g)) for g in groups])
