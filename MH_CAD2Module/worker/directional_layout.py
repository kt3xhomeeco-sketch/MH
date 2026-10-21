"""Measured bay layouts in panel-local directions; preserve world CAD placement."""
import math

from geometry import union, TOL
from oy_sweep import plates,bays
from stages import finish_plan


def polygon(part):
    profile=part.get('plan_profile')
    if profile and all(s['type']=='line' for s in profile['segments']):
        return [[s['start'][i]+part['origin'][i] for i in (0,1)] for s in profile['segments']]
    x,y=part['origin'][:2];w,h=part['size'][:2]
    return [[x,y],[x+w,y],[x+w,y+h],[x,y+h]]


def contains(point,points):
    signs=[]
    for a,b in zip(points,points[1:]+points[:1]):
        length=math.dist(a,b)
        cross=(b[0]-a[0])*(point[1]-a[1])-(b[1]-a[1])*(point[0]-a[0])
        if abs(cross)>TOL*length:signs.append(cross>0)
    return not signs or all(s==signs[0] for s in signs)


def overlap(a,b):
    """Separating axes for convex measured footprints, not their bounding boxes."""
    pa,pb=polygon(a),polygon(b)
    for points in (pa,pb):
        for start,end in zip(points,points[1:]+points[:1]):
            dx,dy=end[0]-start[0],end[1]-start[1];length=math.hypot(dx,dy)
            if length<=TOL:continue
            axis=(-dy/length,dx/length)
            projected=[[sum(p[i]*axis[i] for i in (0,1)) for p in poly] for poly in (pa,pb)]
            if min(max(projected[0]),max(projected[1]))-max(min(projected[0]),min(projected[1]))<=.1:return False
    return True


def convex(points):
    signs=[]
    for index,a in enumerate(points):
        b,c=points[(index+1)%len(points)],points[(index+2)%len(points)]
        cross=(b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0])
        if abs(cross)>.0001:signs.append(cross>0)
    return bool(signs) and all(s==signs[0] for s in signs)


def on_boundary(point,points):
    for a,b in zip(points,points[1:]+points[:1]):
        length=math.dist(a,b)
        if length and abs((b[0]-a[0])*(point[1]-a[1])-(b[1]-a[1])*(point[0]-a[0]))<=TOL*length:
            if min(a[0],b[0])-TOL<=point[0]<=max(a[0],b[0])+TOL and min(a[1],b[1])-TOL<=point[1]<=max(a[1],b[1])+TOL:return True
    return False


def footprint(part,points,base):
    bounds=union([[*p,*p] for p in points]);relative=[[round(p[i]-bounds[i],6) for i in (0,1)] for p in points]
    return dict(part,origin=[round(bounds[i]-base[i],6) for i in (0,1)]+[0],
        size=[round(bounds[2]-bounds[0],6),round(bounds[3]-bounds[1],6),1600],source_box=bounds,plan_box=bounds,
        plan_profile=dict(schema=1,segments=[dict(type='line',start=a,end=b) for a,b in zip(relative,relative[1:]+relative[:1])]),
        height_source='provisional_default')


def line_coverage(a,b,parts):
    """Clip to convex footprints; endpoint/midpoint sampling misses long gaps."""
    runs=[]
    for part in parts:
        points=polygon(part)
        sign=1 if sum(p[0]*q[1]-q[0]*p[1] for p,q in zip(points,points[1:]+points[:1]))>0 else -1
        low,high=0.,1.
        for p,q in zip(points,points[1:]+points[:1]):
            dx,dy=q[0]-p[0],q[1]-p[1]
            start=sign*(dx*(a[1]-p[1])-dy*(a[0]-p[0]))
            step=sign*(dx*(b[1]-a[1])-dy*(b[0]-a[0]))
            tolerance=TOL*math.hypot(dx,dy)
            if abs(step)<=tolerance:
                if min(start,start+step)<-tolerance:low,high=1,0;break
            elif step>0:low=max(low,-start/step)
            else:high=min(high,-start/step)
        if high>=low:runs.append((max(0,low),min(1,high)))
    return runs


def bridge_gaps(panel,parts,base):
    sides=[[[p[i]-base[i] for i in (0,1)] for p in side] for side in panel['boundary']]
    covered=[line_coverage(*side,parts) for side in sides]
    stops=sorted({0.,1.}|{v for rows in covered for run in rows for v in run})
    gaps=[];length=panel['length_mm']
    for lo,hi in zip(stops,stops[1:]):
        mid=(lo+hi)/2
        if (hi-lo)*length<=TOL or all(any(a-1e-8<=mid<=b+1e-8 for a,b in runs) for runs in covered):continue
        if lo*length<TOL or (1-hi)*length<TOL:return None
        points=[]
        for side,ts in ((sides[0],(lo,hi)),(sides[1],(hi,lo))):
            points.extend([[base[i]+side[0][i]+(side[1][i]-side[0][i])*t for i in (0,1)] for t in ts])
        gaps.append(footprint(dict(handles=panel['handles'],role='plan_auxiliary',solid_proxy=True,
            stock_thickness_mm=panel['stock_mm'],face_width_mm=panel['measured_mm'],rule='measured-shared-rail-v1',
            explanation='Đoạn thanh liên tục đi qua khoảng hở giữa các thùng; giữ riêng, không tạo module lấp khoảng hở.'),points,base))
    return gaps


def recover(product,outlines,evidence):
    panels=[p for p in evidence.get('panels',[]) if p['kind']=='straight']
    if not panels or evidence.get('arcs'):return False
    angles={0.0}
    for panel in panels:angles.add(round(panel['direction_rad']%(math.pi/2),6))
    if len(angles)>12:return False
    base=product['source_plan_envelope'][:2]
    candidates=[];auxiliary=[];seams=[]
    for canonical in sorted(angles):
        for angle in (canonical+i*math.pi/2 for i in range(4)):
            c,s=math.cos(angle),math.sin(angle)
            def local(p):
                x,y=p[0]-base[0],p[1]-base[1]
                return [round(c*x+s*y,6),round(-s*x+c*y,6)]
            def world(p):return [round(base[0]+c*p[0]-s*p[1],6),round(base[1]+s*p[0]+c*p[1],6)]
            rows=[dict(o,points=[local(p) for p in o['points']]) for o in outlines]
            rects,_=plates(rows)
            try:
                columns,details=bays(rects,rows)
                if not columns:continue
                for seam in details['joins']:
                    if seam['role']=='module_boundary':seams.append([world([seam['x'],y]) for y in seam['y']])
                result=finish_plan(dict(id='P01',rects=rects,outlines=rows),columns,{})
            except ValueError:continue
            for kind in ('modules','trim_parts'):
                for part in result[kind]:
                    if part.get('plan_profile'):continue
                    box=[part['origin'][i]+result['envelope'][i] for i in (0,1)]
                    box += [box[i]+part['size'][i] for i in (0,1)]
                    points=[world(p) for p in ([box[0],box[1]],[box[2],box[1]],[box[2],box[3]],[box[0],box[3]])]
                    target=auxiliary if kind=='trim_parts' else candidates
                    target.append(footprint(dict(part,direction_rad=angle,
                        rule=part['rule'] if kind=='trim_parts' else 'parallel-stock-bays-v2'),points,base))
    candidates.sort(key=lambda p:p['size'][0]*p['size'][1],reverse=True)
    selected=[]
    for part in candidates:
        points=polygon(part)
        crossing=False
        for a,b in seams:
            ends=[[p[i]-base[i] for i in (0,1)] for p in (a,b)]
            middle=[(ends[0][i]+ends[1][i])/2 for i in (0,1)]
            if all(on_boundary(p,points) for p in ends) and contains(middle,points) and not on_boundary(middle,points):crossing=True;break
        if crossing:continue
        if any(all(contains(point,polygon(other)) for point in polygon(part)) for other in selected):continue
        if any(overlap(part,other) for other in selected):return False
        selected.append(part)
    if not selected:return False
    trims=[]
    for part in sorted(auxiliary,key=lambda p:p['size'][0]*p['size'][1],reverse=True):
        points=polygon(part)
        if any(all(contains(p,polygon(other)) for p in points) for other in selected+trims):continue
        if any(overlap(part,other) for other in selected+trims):continue
        trims.append(part)
    # Every closed straight stock witness must be covered, including both L arms.
    for panel in panels:
        bridges=bridge_gaps(panel,selected+trims,base)
        if bridges is None:return False
        for part in bridges:
            if any(overlap(part,other) for other in selected+trims):return False
            trims.append(part)
    frame=product['source_plan_envelope']
    selected.sort(key=lambda p:tuple(round(v,3) for v in p['origin'][:2]))
    for index,part in enumerate(selected):
        part.update(id=f'M{index+1:02}',name=f'Khoang theo hướng tấm {index+1:02}',scope='carcass_and_doors',
                    explanation='Khoang từ các tấm khép kín trong hệ trục theo hướng ván; giữ tọa độ CAD, cao tạm1600 mm.')
    for index,part in enumerate(trims):
        part.update(id=f'T{index+1:02}',height_source='provisional_default')
        if part.get('depth_evidence'):
            part['depth_evidence']=dict(part['depth_evidence'],frame_angle_rad=part['direction_rad'],
                module_ids=[m['id'] for m in selected if any(on_boundary(p,polygon(m)) for p in polygon(part))])
    product.update(status='ready',modules=selected,trim_parts=trims,panel_parts=[],envelope=list(frame),
                   bounds=[frame[2]-frame[0],frame[3]-frame[1],1600],plan_origin_offset_mm=[0,0],plan_origin_basis='source_plan_envelope')
    product.pop('error',None);product.pop('envelope_preview',None)
    product['geometry_pipeline']['directional_layout']=dict(frames_tested=4*len(angles),modules=len(selected),auxiliary=len(trims),all_straight_panels_covered=True)
    return True
