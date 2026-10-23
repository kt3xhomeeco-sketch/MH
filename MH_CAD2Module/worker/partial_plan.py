"""Keep independently closed bays; reconcile repeated plans before drawing boxes."""
from copy import deepcopy
from collections import defaultdict

from geometry import TOL,near,covers,overlapping_modules
from oy_sweep import plates,bays
from cad_datums import context_hint
from views import title_role


def caps(rects,level,left,right,bottom):
    groups=defaultdict(list)
    for r in rects:
        if r.w>100 and any(near(r.h,t) for t in (3,6,8,9,12,15,18,25,36)) and (near(r.y0,level) or near(r.y1,level)):
            groups[round(r.y0,3),round(r.y1,3)].append(r)
    valid=[rs for rs in groups.values() if covers([(r.x0,r.x1) for r in rs],left,right)]
    return min(valid,key=lambda rs:(not near(rs[0].y0 if bottom else rs[0].y1,level),rs[0].h)) if valid else None


def profiles(front,left,right):
    rects=front['rects'];result=[]
    ls=[r for r in rects if near(r.x0,left) and r.h>100 and r.h>4*r.w]
    rs=[r for r in rects if near(r.x1,right) and r.h>100 and r.h>4*r.w]
    for a in ls:
        for b in rs:
            if not near(a.y0,b.y0) or not near(a.y1,b.y1):continue
            low=caps(rects,a.y0,a.x1,b.x0,True);high=caps(rects,a.y1,a.x1,b.x0,False)
            if low and high:
                result.append(dict(low_mm=min(a.y0,min(r.y0 for r in low))-front['box'][1],
                    high_mm=max(a.y1,max(r.y1 for r in high))-front['box'][1],walls=[a.box(),b.box()],
                    caps=[[r.box() for r in low],[r.box() for r in high]]))
    unique={(round(r['low_mm'],3),round(r['high_mm'],3)):r for r in result}
    return [unique[k] for k in sorted(unique)]


def complete(product,selected,data):
    children=product.get('plan_results',[])
    # This path repairs failed repeated views, leaving established layouts and
    # direct-scan coordinates independent. Never replay/overwrite manual boxes.
    if len(children)<2 or product.get('scan_capture') or not all(c.get('envelope_preview') and not c.get('manual_boxes') for c in children):return False
    poses=data.get('relations',{}).get('poses',{});root=poses.get(children[0]['plan_view_id'],{}).get('root_id')
    if not root or any(poses.get(c['plan_view_id'],{}).get('status')!='proven' or poses[c['plan_view_id']]['root_id']!=root for c in children):return False
    if any(e.get('changed_gap') for c in children for e in poses[c['plan_view_id']].get('path',[])):return False
    fronts=[v for v in data['views'].values() if v['role']=='elevation' and title_role(v.get('title',''))=='front_open'
            and poses.get(v['id'],{}).get('status')=='proven' and poses[v['id']]['root_id']==root]
    if len(fronts)!=1:return False
    front=fronts[0];fp=poses[front['id']]['offset_mm'];master=deepcopy(children[0])
    depth=master.get('envelope_preview',{}).get('depth_evidence',{})
    check=depth.get('section_check',{})
    if check.get('status')!='supported' or master.get('height_source')!='product_elevation_bounds':return False
    d=check['chosen_depth_mm'];frame=master['source_plan_envelope'];y=depth['low_mm'];fb=front['measured_box']
    span=[fb[0]+fp,fb[2]+fp];groups=defaultdict(list)
    for view in selected:
        rows=[r for r in view['outlines'] if not context_hint(r)];rects,_=plates(rows)
        cells,_=bays(rects,rows);offset=poses[view['id']]['offset_mm']
        for cell in cells:
            b=cell['box'];x0,x1=b[0]+offset,b[2]+offset
            if abs(b[3]-b[1]-d)>1 or x0<span[0]-TOL or x1>span[1]+TOL:continue
            profile=profiles(front,x0-fp,x1-fp)
            if not profile:continue
            key=(round(x0,3),round(x1,3))
            groups[key].append(dict(view_id=view['id'],source_box=b,offset_mm=offset,handles=cell['handles'],profile=profile))
    ordered=sorted(groups)
    # Conflicting overlapping candidates make only their own interval pending.
    # One independently closed bay is still worth keeping.
    conflicting={k for a,b in zip(ordered,ordered[1:]) if b[0]<a[1]-TOL for k in (a,b)}
    ordered=[k for k in ordered if k not in conflicting]
    if not ordered:return False
    modules=[];trims=[];issues=[]
    floor,ceiling=master['product_height']['low_mm'],master['product_height']['high_mm']
    lo,hi=floor,ceiling
    common=dict(front_id=front['id'],front_box=front['box'],front_offset_mm=fp,source_signature=data['source_signature'])
    def part(x0,x1,lo,hi,identity):
        return dict(id=identity,name=identity,origin=[round(x0-frame[0],6),round(y-frame[1],6),round(lo,6)],
            size=[round(x1-x0,6),d,round(hi-lo,6)],source_box=[x0,y,x1,y+d],plan_box=[x0,y,x1,y+d],
            height_source='front_stock_bounds',elevation_pending=False,rule='partial-registered-plan-v1')
    def unresolved(x0,x1,low,high,reason):
        p=part(x0,x1,low,high,f'U{1+sum(bool(m.get("unresolved")) for m in modules):02}')
        p.update(name='Chưa xác định · box tạm',height_source='product_elevation_bounds',elevation_pending=True,
            envelope_preview=True,unresolved=True,rule='partial-source-envelope-v1',handles=[],
            elevation_evidence=dict(basis=master['product_height']['basis'],source_signature=data['source_signature'],low_mm=low,high_mm=high),
            explanation=reason)
        modules.append(p);issues.append(reason)
    for index,(x0,x1) in enumerate(ordered):
        votes=groups[x0,x1];profile=votes[0]['profile']
        for level,row in enumerate(profile):
            lo,hi=row['low_mm'],row['high_mm'];p=part(x0,x1,lo,hi,f'M{index+1:02}-Z{level+1:02}')
            p.update(name=f'Khoang {index+1:02} · Tầng {level+1:02}',handles=sorted({h for v in votes for h in v['handles']}),
                elevation_evidence=dict(common,kind='bay',**row,plan_witnesses=[{k:v for k,v in r.items() if k!='profile'} for r in votes]),
                explanation=f'Khoang từ cặp ván mặt bằng và cặp vách/nóc/đáy mặt đứng bỏ cánh; Z{lo:g}..{hi:g} mm. Giữ kết quả dù vùng khác còn lỗi.')
            modules.append(p)
    # Independent closed front panels in the narrow gaps are auxiliaries, not
    # a reason to discard adjacent bays with slightly different source depths.
    gaps=[(span[0],ordered[0][0])]+[(a[1],b[0]) for a,b in zip(ordered,ordered[1:])]+[(ordered[-1][1],span[1])]
    for x0,x1 in gaps:
        if x1-x0<=TOL:continue
        panels=[r for r in front['rects'] if near(r.x0,x0-fp) and near(r.x1,x1-fp) and r.h>100]
        if panels and covers([(r.y0,r.y1) for r in panels],min(r.y0 for r in panels),max(r.y1 for r in panels)):
            lo=min(r.y0 for r in panels)-front['box'][1];hi=max(r.y1 for r in panels)-front['box'][1]
            p=part(x0,x1,lo,hi,f'T{len(trims)+1:02}')
            p.update(name='Nẹp phụ · biên ván đo được',role='plan_auxiliary',solid_proxy=True,handles=[r.handle for r in panels],
                elevation_evidence=dict(common,kind='trim',low_mm=lo,high_mm=hi,panels=[r.box() for r in panels]))
            trims.append(p)
        else:
            unresolved(x0,x1,lo,hi,'Khoảng giữa các khoang chưa có ván khép kín: giữ box tạm riêng, không bỏ khoang đã chia.')
    # Keep the unmatched source tail as an independent correction target.
    lo,hi=floor,ceiling
    if frame[2]>span[1]+TOL:
        unresolved(span[1],frame[2],lo,hi,'Phần cuối ngoài chuỗi mặt đứng bỏ cánh còn là box tạm để sửa.')
    # A continuous front band owns its boundaries; seams in the bodies below
    # do not split it. A short plinth still has two standard-stock side faces.
    from continuous_bands import measure as measure_bands
    bands=measure_bands(front,fp,ordered,data,master['plan_reference'])
    for row in bands:
        p=part(row['x0'],row['x1'],row['low_mm'],row['high_mm'],f'B{len([m for m in modules if m.get("height_source")=="front_section_band"])+1:02}')
        p['origin'][1]+=row['depth_low_mm'];p['size'][1]=row['depth_high_mm']-row['depth_low_mm']
        p['source_box'][1]+=row['depth_low_mm'];p['source_box'][3]=p['source_box'][1]+p['size'][1];p['plan_box']=p['source_box'][:]
        p.update(name='Module chân' if near(row['low_mm'],floor) else 'Module nóc liên tục',height_source='front_section_band',
            elevation_evidence=dict(common,kind='band',**row),handles=[row['front_handle']],
            explanation='Một biên kín liên tục trên mặt đứng và hai cặp ván mặt cắt cùng cao độ; không chia theo thùng bên dưới.')
        if not overlapping_modules(modules+trims+[p]):modules.append(p)
    # A band above measured bay sides is not silently attached to every module.
    for x0,x1 in ordered:
        top=max(r['high_mm'] for r in groups[x0,x1][0]['profile'])
        # Only a small conflicting roof band is a residual, never fill the
        # intentionally empty space over a shorter, independently closed bay.
        if TOL<hi-top<=36+TOL and not any(b['x0']<=x0+TOL and b['x1']>=x1-TOL and near(b['low_mm'],top) and near(b['high_mm'],hi) for b in bands):
            unresolved(x0,x1,top,hi,f'Vùng X{x0-frame[0]:g}..{x1-frame[0]:g}, Z{top:g}..{hi:g}: nóc/nẹp chưa cùng biên trên mặt đứng và mặt cắt; giữ box tạm riêng.')
    if overlapping_modules(modules+trims):return False
    master.update(status='ready',modules=modules,trim_parts=trims,panel_parts=[],unified_partial_plan=True,
        source_plan_variants=[dict(view_id=c['plan_view_id'],title=c['plan_title']) for c in children],
        height_source='mixed_partial',elevation_pending=True,plan_partition_pending=bool(issues),
        partial_plan=dict(engine='registered-partial-bays-v1',span_mm=[span[0]-frame[0],span[1]-frame[0]],
            depth_evidence=depth,confirmed_modules=sum(not p.get('unresolved') for p in modules),unresolved_modules=sum(bool(p.get('unresolved')) for p in modules),issues=issues),
        explanation=['Đối chiếu các mặt bằng cùng bộ hình: chỉ dựng một bộ module tại vị trí chung, không tạo một box đầy SP cho mỗi mặt bằng.',
            f'Đã chia {sum(not p.get("unresolved") for p in modules)} phần có cặp ván/vách khép kín; phần chưa rõ giữ riêng.']+issues,
        warnings=issues,bounds=[frame[2]-frame[0],y-frame[1]+d,hi])
    master.pop('envelope_preview',None);master.pop('error',None)
    master['geometry_pipeline']['horizontal'].update(status='partial',issues=issues)
    master['geometry_pipeline']['partial_plan']=master['partial_plan']
    product['plan_results']=[master]
    return True
