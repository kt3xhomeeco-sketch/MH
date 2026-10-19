"""Measured closed side profiles; circular runs remain analytic arcs."""
import math
from collections import defaultdict
from geometry import TOL, union, gap_boxes, near, inside, covers
from materials import BOARD_MM


def axis_edge(a,b):
    return abs(a[0]-b[0])<.001 or abs(a[1]-b[1])<.001


def fit_arc(points):
    if len(points)<4:return None
    a=points[0];b=[v-o for v,o in zip(points[len(points)//2],a)];c=[v-o for v,o in zip(points[-1],a)]
    det=2*(b[0]*c[1]-b[1]*c[0])
    if abs(det)<1e-9:return None
    bb=sum(v*v for v in b);cc=sum(v*v for v in c)
    center=[a[0]+(bb*c[1]-cc*b[1])/det,a[1]+(b[0]*cc-c[0]*bb)/det]
    radius=math.dist(a,center)
    if radius<.02 or any(abs(math.dist(p,center)-radius)>.02 for p in points):return None
    turns=[]
    for p,q in zip(points,points[1:]):
        u=[p[i]-center[i] for i in (0,1)];v=[q[i]-center[i] for i in (0,1)]
        turns.append(math.atan2(u[0]*v[1]-u[1]*v[0],sum(x*y for x,y in zip(u,v))))
    if any(abs(t)>math.pi/3 or t*turns[0]<=0 for t in turns):return None
    sweep=sum(turns)
    if not .001<abs(sweep)<=2*math.pi:return None
    return dict(type='arc',start=a,end=points[-1],center=center,radius=radius,sweep=sweep,segments=len(points)-1)


def longest_arc(points,start):
    finish=start+3
    if finish>=len(points):return None
    arc=fit_arc(points[start:finish+1])
    if not arc:return None
    while finish+1<len(points):
        extended=fit_arc(points[start:finish+2])
        if not extended:break
        finish+=1;arc=extended
    return finish,arc


def profile_from_points(points):
    # An axial chord at an arc extremum is still curved, not a straight seam.
    count=len(points)
    index=next((i for i,p in enumerate(points) if axis_edge(p,points[(i+1)%count]) and not any(
        fit_arc([points[(j+k)%count] for k in range(4)]) for j in (i-2,i-1,i))),None)
    if index is None:raise ValueError('Chưa hỗ trợ spline hoặc vòng tròn kín làm khối mặt bằng.')
    points=points[index:]+points[:index]
    closed=points+[points[0]];segments=[];i=0
    while i<len(points):
        finish=i+1
        fitted=longest_arc(closed,i)
        if fitted:
            finish,arc=fitted
            if segments and segments[-1]['type']=='arc' and (math.dist(segments[-1]['center'],arc['center'])>.02 or abs(segments[-1]['radius']-arc['radius'])>.02):
                raise ValueError('Biên cong đổi tâm/bán kính liên tục; chưa xác nhận được cung tròn CAD.')
            segments.append(arc)
        elif axis_edge(closed[i],closed[finish]):
            while (finish<len(points) and axis_edge(closed[finish],closed[finish+1]) and
                   (abs(closed[i][0]-closed[finish+1][0])<.001 or abs(closed[i][1]-closed[finish+1][1])<.001)):
                finish+=1
            segments.append(dict(type='line',start=closed[i],end=closed[finish]))
        else:raise ValueError('Biên cong chưa khớp cung tròn đo từ CAD; cần kiểm tra spline/cạnh xiên.')
        i=finish
    return dict(schema=1,segments=segments)


def arc_runs(outlines):
    """Recover circular runs from un-welded LINEs, including axial chords."""
    graph=defaultdict(set);coords={};handles=defaultdict(set)
    for outline in outlines:
        for a,b in zip(outline['points'],outline['points'][1:]):
            ka,kb=(tuple(round(v,3) for v in p) for p in (a,b))
            if ka==kb:continue
            coords[ka]=a;coords[kb]=b;graph[ka].add(kb);graph[kb].add(ka)
            handles[tuple(sorted((ka,kb)))].add(outline['handle'])
    seen=set();runs=[]
    starts=sorted(graph,key=lambda p:(len(graph[p])==2,p))
    for start in starts:
        for second in sorted(graph[start]):
            edge=tuple(sorted((start,second)))
            if edge in seen:continue
            order=[start,second];seen.add(edge);previous,current=start,second
            while len(graph[current])==2 and current!=start:
                following=next(p for p in graph[current] if p!=previous)
                edge=tuple(sorted((current,following)))
                if edge in seen:break
                seen.add(edge);order.append(following);previous,current=current,following
            points=[coords[p] for p in order];closed=order[0]==order[-1];n=len(points)-1
            def straight(k):
                a,b=points[k:k+2]
                local=[j for j in (k-2,k-1,k) if closed or 0<=j and j+3<len(points)]
                if any(fit_arc([points[(j+t)%n] if closed else points[j+t] for t in range(4)]) for j in local):return False
                if axis_edge(a,b):return True
                neighbours=[]
                if closed or k>0:neighbours.append((points[(k-1)%n],a,b))
                if closed or k+2<len(points):neighbours.append((a,b,points[(k+2)%n] if closed else points[k+2]))
                turns=[];lengths=[]
                for x,y,z in neighbours:
                    u=[y[i]-x[i] for i in (0,1)];v=[z[i]-y[i] for i in (0,1)]
                    turns.append(abs(math.atan2(u[0]*v[1]-u[1]*v[0],sum(u[i]*v[i] for i in (0,1)))))
                    lengths.append(min(math.dist(x,y),math.dist(y,z)))
                return any(t<1e-7 for t in turns) or (len(turns)==2 and min(turns)>math.pi/3) or (lengths and math.dist(a,b)>3*max(lengths))
            flags=[straight(i) for i in range(n)]
            if closed:
                if not any(flags):continue
                seam=flags.index(True);unique=order[:-1];order=unique[seam:]+unique[:seam];order.append(order[0])
                points=[coords[p] for p in order];flags=flags[seam:]+flags[:seam]
            i=0
            while i<n:
                if flags[i]:i+=1;continue
                finish=i+1
                while finish<n and not flags[finish]:finish+=1
                arc=fit_arc(points[i:finish+1])
                if arc:
                    keys=order[i:finish+1]
                    if keys[0]>keys[-1]:keys=list(reversed(keys));arc=fit_arc([coords[p] for p in keys])
                    edges=[tuple(sorted((a,b))) for a,b in zip(keys,keys[1:])]
                    arc.update(source_edges=edges,handles=sorted({h for e in edges for h in handles[e]}))
                    runs.append(arc)
                i=finish
    # Never turn a smooth non-circular run into a succession of fitted circles.
    runs=[a for a in runs if not any(a is not b and any(math.dist(a[p],b[q])<.002 for p in ('start','end') for q in ('start','end'))
        and (math.dist(a['center'],b['center'])>.02 or abs(a['radius']-b['radius'])>.02) for b in runs)]
    return sorted(runs,key=lambda a:(a['center'],a['radius'],a['start']))


def arc_bounds(arc):
    points=[arc['start'],arc['end']]
    start=math.atan2(arc['start'][1]-arc['center'][1],arc['start'][0]-arc['center'][0])
    for angle in (0,math.pi/2,math.pi,3*math.pi/2):
        delta=((angle-start) if arc['sweep']>0 else (start-angle))%(2*math.pi)
        if delta<=abs(arc['sweep'])+1e-8:
            points.append([arc['center'][0]+arc['radius']*math.cos(angle),arc['center'][1]+arc['radius']*math.sin(angle)])
    return [round(v,9) for v in union([[*p,*p] for p in points])]


def expand_plan_outlines(views,outlines):
    """Keep connected end arcs extending beyond the rectangle-only view bounds."""
    for view in views:
        if view['role']!='plan':continue
        box=list(view['region']);selected=[];remaining=list(outlines)
        while remaining:
            add=[o for o in remaining if o['points'] and max(gap_boxes(union([[*p,*p] for p in o['points']]),box))<=TOL]
            if not add:break
            selected.extend(add)
            used={id(o) for o in add};remaining=[o for o in remaining if id(o) not in used]
            box=union([box]+[[*p,*p] for o in add for p in o['points']])
        view['outlines']=selected;view['region']=box


def exterior_loop(lines):
    """Walk the unbounded face of a measured planar graph, including panel seams."""
    coords={tuple(round(v,3) for v in p):p for edge in lines for p in edge}
    if len(coords)>2000:raise ValueError('Biên cong quá nhiều điểm; quét gọn một sản phẩm.')
    graph=defaultdict(set)
    for a,b in lines:
        dx=b[0]-a[0];dy=b[1]-a[1];length=math.hypot(dx,dy)
        if length<.001:continue
        cuts=[]
        for key,p in coords.items():
            along=((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(length*length)
            distance=abs((p[0]-a[0])*dy-(p[1]-a[1])*dx)/length
            if -.00001<=along<=1.00001 and distance<.002:cuts.append((along,key))
        cuts.sort()
        for (_,u),(_,v) in zip(cuts,cuts[1:]):
            if u!=v:graph[u].add(v);graph[v].add(u)
    ordered={p:sorted(neighbours,key=lambda q:math.atan2(q[1]-p[1],q[0]-p[0])) for p,neighbours in graph.items()}
    if any(len(neighbours)<2 for neighbours in graph.values()):return None
    seen=set();loops=[]
    for start in graph:
        for second in graph[start]:
            if (start,second) in seen:continue
            loop=[];a,b=start,second
            while (a,b) not in seen:
                seen.add((a,b));loop.append(a)
                neighbours=ordered[b];following=neighbours[(neighbours.index(a)-1)%len(neighbours)]
                a,b=b,following
            if (a,b)!=(start,second) or len(loop)<4 or len(set(loop))!=len(loop):continue
            pts=[coords[k] for k in loop]
            area=sum(p[0]*q[1]-q[0]*p[1] for p,q in zip(pts,pts[1:]+pts[:1]))/2
            loops.append((abs(area),pts))
    return max(loops,key=lambda row:row[0])[1] if loops else None


def stepped_bay(rects,outlines):
    """Unequal-depth sides need a connected stepped rear, not an invented rectangle."""
    sides=[r for r in rects if 12<=r.w<=40 and r.h>=100 and r.h>5*r.w]
    if len(sides)<3:return []
    left=min(sides,key=lambda r:(r.x0,-r.h));right=max(sides,key=lambda r:(r.x1,r.h))
    if (not near(left.y0,right.y0) or near(left.y1,right.y1) or right.x0-left.x1<100
            or max(left.h,right.h)>1200):return []
    if any(r is not left and r is not right and left.x1+TOL<r.x0<right.x0-TOL
           and near(r.y0,left.y0) for r in sides):return []
    rear=[left,right]+[r for r in rects if r not in (left,right) and r.y0>left.y0+60
        and inside(r.box(),[left.x0,left.y0,right.x1,max(left.y1,right.y1)])
        and any(near(min(r.w,r.h),s) for s in BOARD_MM) and max(r.w,r.h)>72]
    paths=[[left]];path=None
    while paths:
        run=paths.pop(0)
        if run[-1] is right:path=run;break
        for r in rear:
            if r not in run and max(gap_boxes(run[-1].box(),r.box()))<=TOL:paths.append(run+[r])
        if len(paths)>128:return []
    if not path or sum(r.w>r.h for r in path)<2 or not any(r in sides for r in path[1:-1]):return []
    fronts=[r for r in rects if 2<=r.h<=60 and r.w>100 and near(r.y1,left.y0)]
    if not covers([(r.x0,r.x1) for r in fronts],left.x0,right.x1):return []
    box=[left.x0,min(r.y0 for r in fronts),right.x1,max(left.y1,right.y1)]
    selected=[o for o in outlines if o['points'] and all(inside([*p,*p],box) for p in o['points'])]
    lines=[(a,b) for o in selected for a,b in zip(o['points'],o['points'][1:])]
    if not lines or any(not axis_edge(a,b) for a,b in lines):return []
    points=exterior_loop(lines)
    if not points or any(not near(a,b) for a,b in zip(union([[*p,*p] for p in points]),box)):return []
    profile=profile_from_points([[p[i]-box[i] for i in (0,1)] for p in points])
    if len(profile['segments'])<=4:return []
    return [dict(box=box,core_box=box,handles=sorted({o['handle'] for o in selected}),
                 plan_profile=profile,stepped_rear=True)]


def point_in_polygon(point,polygon):
    x,y=point;result=False
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:result=not result
    return result


def check_stepped_footprints(product,parts,base):
    """Grouping may change; filling the measured rear recess may not."""
    for measured in product.get('geometry_pipeline',{}).get('measured_stepped_footprints',[]):
        box=measured['box']
        expected=[[s['start'][i]+box[i] for i in (0,1)] for s in measured['profile']['segments']]
        polygons=[]
        for part in parts:
            origin=[base[i]+part['origin'][i] for i in (0,1)]
            if any(min(origin[i]+part['size'][i],box[i+2])-max(origin[i],box[i])<=TOL for i in (0,1)):continue
            profile=part.get('plan_profile')
            if profile and any(s['type']!='line' for s in profile['segments']):
                raise ValueError('Phương án đổi biên hậu giật cấp thành cung không có trên CAD.')
            points=[s['start'] for s in profile['segments']] if profile else [[0,0],[part['size'][0],0],part['size'][:2],[0,part['size'][1]]]
            polygons.append([[p[i]+origin[i] for i in (0,1)] for p in points])
        axes=[sorted({box[i],box[i+2]}|{p[i] for poly in [expected]+polygons for p in poly if box[i]<p[i]<box[i+2]}) for i in (0,1)]
        if len(axes[0])*len(axes[1])>20000:raise ValueError('Biên hậu giật cấp quá phức tạp để đối chiếu.')
        for x0,x1 in zip(axes[0],axes[0][1:]):
            for y0,y1 in zip(axes[1],axes[1][1:]):
                if min(x1-x0,y1-y0)<=TOL:continue
                point=[(x0+x1)/2,(y0+y1)/2]
                if point_in_polygon(point,expected)!=any(point_in_polygon(point,p) for p in polygons):
                    raise ValueError('Phương án lấp phần lõm hoặc làm mất biên hậu giật cấp đã đo trên CAD.')


def curved_ends(plan,footprints):
    """Filled outer end proxies, separate from the measured rectangular bays."""
    base=union([p['box'] for p in footprints]);found=[]
    for side,boundary in (('left',base[0]),('right',base[2])):
        sign=-1 if side=='left' else 1
        lines=[];handles=[]
        for outline in plan['outlines']:
            for a,b in zip(outline['points'],outline['points'][1:]):
                if min(sign*(a[0]-boundary),sign*(b[0]-boundary)) < -TOL:continue
                if min(a[1],b[1])<base[1]-60 or max(a[1],b[1])>base[3]+60:continue
                lines.append((a,b));handles.append(outline['handle'])
        if not any(not axis_edge(a,b) for a,b in lines):continue
        points=exterior_loop(lines)
        if not points:raise ValueError('Phần bo cuối tủ chưa có biên kín; cần quét đủ đường arc và cạnh nối.')
        profile=profile_from_points(points)
        box=union([arc_bounds(s) if s['type']=='arc' else union([[*s[p],*s[p]] for p in ('start','end')]) for s in profile['segments']]);width=box[2]-box[0]
        if abs(box[2 if side=='left' else 0]-boundary)>TOL:continue
        if width>TOL and width<=base[3]-base[1]+60:
            for segment in profile['segments']:
                for field in ('start','end','center'):
                    if field in segment:segment[field]=[segment[field][i]-box[i] for i in (0,1)]
            if any(s['type']=='arc' for s in profile['segments']):
                found.append(dict(box=box,handles=sorted(set(handles)),plan_profile=profile,curved_end=True))
            else:raise ValueError('Phần bo cuối tủ thiếu biên arc kín; chưa dựng phần cong.')
    return found


def valid_profile(profile,size):
    try:return _valid_profile(profile,size)
    except (TypeError,ValueError,KeyError,AttributeError,OverflowError):return False


def _valid_profile(profile,size):
    if not isinstance(profile,dict) or profile.get('schema')!=1:return False
    segments=profile.get('segments')
    if not isinstance(segments,list) or not 3<=len(segments)<=500:return False
    for i,s in enumerate(segments):
        if s.get('type') not in ('line','arc'):return False
        for field in ('start','end'):
            p=s.get(field)
            if not isinstance(p,list) or len(p)!=2 or any(type(v) not in (float,int) or not math.isfinite(v) or v<-.1 or v>size[j]+.1 for j,v in enumerate(p)):return False
        if math.dist(s['end'],segments[(i+1)%len(segments)].get('start',[]))>.02:return False
        if s['type']=='arc':
            c=s.get('center');r=s.get('radius');sweep=s.get('sweep');count=s.get('segments')
            if (not isinstance(c,list) or len(c)!=2 or any(type(v) not in (float,int) or not math.isfinite(v) for v in c) or
                type(r) not in (float,int) or not math.isfinite(r) or not 0<r<100000 or
                type(sweep) not in (float,int) or not math.isfinite(sweep) or not .001<abs(sweep)<=2*math.pi or
                type(count) is not int or not 3<=count<=2000):return False
            if any(abs(math.dist(s[p],c)-r)>.02 for p in ('start','end')):return False
            a=math.atan2(s['start'][1]-c[1],s['start'][0]-c[0])+sweep
            if math.dist([c[0]+r*math.cos(a),c[1]+r*math.sin(a)],s['end'])>.02:return False
            limits=arc_bounds(s)
            if any(limits[i]<-.1 or limits[i+2]>size[i]+.1 for i in (0,1)):return False
    return True
