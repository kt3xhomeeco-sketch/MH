"""Continuous front bands corroborated by the two stock faces in side sections."""
from geometry import TOL,near,rectangle,covers
from cad_datums import context_hint
from materials import BOARD_MM


def measure(front,offset,ordered,data,reference):
    poses=data['relations']['poses'];root=poses[front['id']]['root_id'];result=[]
    views={v['id']:v for v in reference.get('views',[])}
    for row in front['outlines']:
        r=rectangle(row['points'],row['handle'],row.get('layer',''))
        if not r or context_hint(row) or r.w<=100 or not TOL<r.h<=100:continue
        x0,x1=r.x0+offset,r.x1+offset
        if not covers(ordered,x0,x1) or not any(near(x0,a) for a,b in ordered) or not any(near(x1,b) for a,b in ordered):continue
        low,high=r.y0-front['box'][1],r.y1-front['box'][1];sections=[]
        for v in data['views'].values():
            ref=views.get(v['id'],{})
            if v['role']!='section_vertical' or 'reversed_depth' not in ref:continue
            cuts=[]
            for link in v.get('section_links',[]):
                mark=data['markers'].get(link['marker_handle']);pose=poses.get(link['front_id'],{})
                if not mark or mark['axis']!='vertical' or pose.get('status')!='proven' or pose['root_id']!=root:continue
                x=sum(p[0] for p in mark['cut_line'])/2+pose['offset_mm']
                if x0-TOL<=x<=x1+TOL:cuts.append(dict(marker_handle=link['marker_handle'],source_x_mm=x,front_id=link['front_id']))
            if not cuts:continue
            stock=[q for q in v['rects'] if any(near(q.w,s) for s in BOARD_MM) and q.h>=r.h-TOL and
                q.y0-v['box'][1]<=low+TOL and q.y1-v['box'][1]>=high-TOL]
            if len(stock)<2:continue
            a=min(stock,key=lambda q:q.x0);b=max(stock,key=lambda q:q.x1)
            if b.x0-a.x1<100:continue
            sb=v['box'];rev=ref['reversed_depth']
            y0,y1=(sb[2]-b.x1,sb[2]-a.x0) if rev else (a.x0-sb[0],b.x1-sb[0])
            sections.append(dict(view_id=v['id'],section_box=sb,panels=[a.box(),b.box()],reversed_depth=rev,
                depth_low_mm=round(y0,6),depth_high_mm=round(y1,6),cuts=cuts))
        if len(sections)<2 or any(not near(s[k],sections[0][k]) for s in sections for k in ('depth_low_mm','depth_high_mm')):continue
        result.append(dict(x0=x0,x1=x1,low_mm=low,high_mm=high,front_band=r.box(),front_handle=r.handle,
            sections=sections,depth_low_mm=sections[0]['depth_low_mm'],depth_high_mm=sections[0]['depth_high_mm']))
    return result
