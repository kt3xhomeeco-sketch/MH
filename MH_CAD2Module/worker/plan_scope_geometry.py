"""Scope stock profiles and two perpendicular plan arms without an OY-only crop."""
import math

from geometry import TOL, Rect, near, union, rectangle, gap_boxes
from materials import BOARD_MM
from oy_sweep import bays


def panel_outline(row):
    points=row['points']
    if len(points)<4 or math.dist(points[0],points[-1])>TOL:return False
    box=[min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)]
    w,h=box[2]-box[0],box[3]-box[1]
    if rectangle(points,row['handle'],row.get('layer','')):
        return any(near(min(w,h),stock) for stock in BOARD_MM) and max(w,h)>2*min(w,h)
    perimeter=sum(math.dist(a,b) for a,b in zip(points,points[1:]))
    area=abs(sum(a[0]*(b[1]-points[0][1])-b[0]*(a[1]-points[0][1]) for a,b in zip(points,points[1:])))/2
    if not perimeter or not area or 2*area/perimeter>max(BOARD_MM)+TOL:return False
    edges=[(a,b,math.dist(a,b)) for a,b in zip(points,points[1:]) if math.dist(a,b)>20]
    # Curved profiles are handled by the existing analytic arc witness path.
    if len(edges)>128:return False
    for index,(a,b,length) in enumerate(edges):
        ux,uy=(b[0]-a[0])/length,(b[1]-a[1])/length
        for c,d,other in edges[index+1:]:
            if abs(ux*(d[1]-c[1])-uy*(d[0]-c[0]))>other*.00001:continue
            spacing=abs(ux*(c[1]-a[1])-uy*(c[0]-a[0]))
            if not any(near(spacing,stock) for stock in BOARD_MM):continue
            projections=sorted((ux*(p[0]-a[0])+uy*(p[1]-a[1]) for p in (c,d)))
            if min(length,projections[1])-max(0,projections[0])>20:return True
    return False


def outline_box(row):
    points=row['points']
    return [min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)]


def stock_envelope(rows,rects):
    boxes=[r.box() for r in rects]+[outline_box(o) for o in rows if panel_outline(o)]
    return union(boxes) if boxes else None


def elevation_band_widths(rects,width):
    """Measured upper/lower cabinet rows may have different widths on one front."""
    horizontal=[r for r in rects if r.h<=max(BOARD_MM)+TOL and r.w>100]
    result=set()
    for seed in horizontal:
        group=[r for r in horizontal if abs(r.y0-seed.y0)<=36 and abs(r.y1-seed.y1)<=36]
        box=union([r.box() for r in group])
        span=box[2]-box[0]
        if len(group)>=2 and span>width*.5:result.add(round(span,3))
    return sorted(result)


def band(columns,span):
    boxes=[c['box'] for c in columns if 100<=c['box'][3]-c['box'][1]<=800]
    candidates=[]
    for seed in boxes:
        group=[b for b in boxes if abs(b[1]-seed[1])<=72 and abs(b[3]-seed[3])<=72]
        extent=union(group)
        if len(group)>=2 and extent[2]-extent[0]>span*.5:candidates.append(extent)
    return max(candidates,key=lambda b:b[2]-b[0],default=None)


def orthogonal_plan(rows,rects,columns,box):
    """Two long, shallow, joined bay bands distinguish an L plan from an elevation."""
    w,h=box[2]-box[0],box[3]-box[1]
    if min(w,h)<=1200:return None
    along_x=band(columns,w)
    if not along_x:return None
    turned=[dict(o,points=[[y,-x] for x,y in o['points']]) for o in rows]
    turned_rects=[Rect(r.y0,-r.x1,r.y1,-r.x0,r.handle,r.layer) for r in rects]
    try:turned_columns,_=bays(turned_rects,turned)
    except ValueError:return None
    along_y=band(turned_columns,h)
    if not along_y:return None
    world_y=[-along_y[3],along_y[0],-along_y[1],along_y[2]]
    if max(gap_boxes(along_x,world_y))>max(along_x[3]-along_x[1],world_y[2]-world_y[0])+72:return None
    return dict(kind='L',basis='perpendicular_stock_bay_bands',x_band_mm=along_x,y_band_mm=world_y,
                branch_depths_mm=[round(along_x[3]-along_x[1],3),round(world_y[2]-world_y[0],3)])
