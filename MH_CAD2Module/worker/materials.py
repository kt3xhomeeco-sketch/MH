"""User-supplied material priors. Dimensions themselves are never rounded to stock."""
from geometry import TOL, near, inside

BOARD_MM=(3,6,8,9,12,15,18,25,36)
# Confirmed by the user: an exterior 24 mm frontal strip can be 18 mm stock turned out.
TURNED_TRIM=({'face_mm':24,'stock_mm':18},)


def stock_evidence(measured):
    matched=next((v for v in BOARD_MM if near(measured,v)),None)
    return {'measured_mm':measured,'stock_mm':matched,
            'lamination_candidate':[18,18] if matched==36 else None}


def perimeter_trims(unassigned, plan_rects, shift, envelope, gaps=()):
    """Classify an adjacent exterior strip only with a matching plan stock witness."""
    parts=[];unresolved=[]
    for r in sorted(unassigned,key=lambda r:r.h,reverse=True):
        if any(inside(r.box(),p['source_box']) for p in parts):continue
        rule=next((p for p in TURNED_TRIM if near(r.w,p['face_mm'])),None)
        adjacent=near(r.x0,envelope[2]) or near(r.x1,envelope[0]) or any(
            near(r.x0,a) and near(r.x1,b) for a,b in gaps)
        witnesses=[p for p in plan_rects if rule and near(min(p.w,p.h),rule['stock_mm']) and
                   max(p.w,p.h)<=120 and r.x0-shift-TOL<=p.x0 and p.x1<=r.x1-shift+TOL]
        if rule and adjacent and witnesses:
            parts.append({'role':'edge_trim','face_width_mm':r.w,'stock_thickness_mm':rule['stock_mm'],
                          'source_box':r.box(),'plan_boxes':[p.box() for p in witnesses],
                          'handles':[r.handle]+[p.handle for p in witnesses],
                          'evidence':'User-confirmed turned trim rule plus matching plan section of 18 mm stock.'})
        else:
            # A straight stock-width strip needs its own exact plan footprint;
            # do not infer its depth from the neighbouring cabinet.
            stock=next((s for s in BOARD_MM if near(r.w,s)),None)
            measured=[p for p in plan_rects if stock and near(p.w,stock) and p.h>=stock and
                      near(p.x0,r.x0-shift) and near(p.x1,r.x1-shift)]
            footprints={tuple(round(v,2) for v in p.box()):p for p in measured}
            if adjacent and len(footprints)==1:
                p=next(iter(footprints.values()))
                parts.append({'role':'edge_trim' if p.h<=120 else 'end_panel','face_width_mm':r.w,'stock_thickness_mm':stock,
                              'source_box':r.box(),'plan_boxes':[p.box()],
                              'handles':[r.handle,p.handle],
                              'evidence':'Stock-width frontal strip with an exactly aligned measured plan footprint.'})
            else:unresolved.append(r)
    return parts,unresolved
