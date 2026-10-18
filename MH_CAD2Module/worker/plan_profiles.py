"""Measured closed side profiles; circular runs remain analytic arcs."""
import math
from collections import defaultdict
from geometry import TOL, union, gap_boxes


def axis_edge(a,b):
    return abs(a[0]-b[0])<.001 or abs(a[1]-b[1])<.001


def fit_arc(points):
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


def profile_from_points(points):
    index=next((i for i,p in enumerate(points) if axis_edge(p,points[(i+1)%len(points)])),None)
    if index is None:raise ValueError('Chưa hỗ trợ spline hoặc vòng tròn kín làm khối mặt bằng.')
    points=points[index:]+points[:index]
    closed=points+[points[0]];segments=[];i=0
    while i<len(points):
        finish=i+1
        if axis_edge(closed[i],closed[finish]):
            while (finish<len(points) and axis_edge(closed[finish],closed[finish+1]) and
                   (abs(closed[i][0]-closed[finish+1][0])<.001 or abs(closed[i][1]-closed[finish+1][1])<.001)):
                finish+=1
            segments.append(dict(type='line',start=closed[i],end=closed[finish]))
        else:
            while finish<len(points) and not axis_edge(closed[finish],closed[finish+1]):finish+=1
            arc=fit_arc(closed[i:finish+1]) if finish-i>=3 else None
            if not arc:raise ValueError('Biên cong chưa khớp cung tròn đo từ CAD; cần kiểm tra spline/cạnh xiên.')
            segments.append(arc)
        i=finish
    return dict(schema=1,segments=segments)


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
        box=union([[*p,*p] for p in points]);width=box[2]-box[0]
        if abs(box[2 if side=='left' else 0]-boundary)>TOL:continue
        if width>TOL and width<=base[3]-base[1]+60:
            relative=[[p[i]-box[i] for i in (0,1)] for p in points]
            profile=profile_from_points(relative)
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
    return True
