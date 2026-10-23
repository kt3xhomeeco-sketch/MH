"""Separate measured construction views from annotation and check-only views."""
from __future__ import annotations

import re
import unicodedata
from collections import Counter

from geometry import (Rect, TOL, near, union, inside, gap_boxes, line_rectangles,
                      covers, overlapping_modules, geometry_signature, section_support, validate_joint)
from geometry import enclosures
from materials import BOARD_MM, TURNED_TRIM, perimeter_trims


def normalise(text):
    text = unicodedata.normalize('NFD',str(text)).replace('đ','d').replace('Đ','D')
    return ' '.join(''.join(c for c in text if not unicodedata.combining(c)).upper().split())


def section_symbol(entity):
    """Match callout attributes/names, never anonymous furniture blocks in general."""
    attrs = {a.dxf.tag: a.dxf.text.strip() for a in entity.attribs}
    paired = (all(k in attrs and re.fullmatch(r'[A-Z0-9]+',attrs[k],re.I) for k in ('1','2','4','5'))
              and attrs['1']==attrs['2'] and attrs['4']==attrs['5'])
    name = normalise(entity.dxf.name)
    named = any(s in name for s in ('SECTION MARK','SECTION SYMBOL','KY HIEU MAT CAT','KY HIEU MC'))
    return paired or named


def title_role(text):
    text = normalise(text)
    if 'MAT DUNG' in text:
        return 'front_open' if any(s in text for s in ('BO CANH','KHONG CANH','CAU TAO')) else 'front_check'
    if 'MAT BANG' in text or 'CAT BANG' in text:
        return 'plan'
    if 'MAT CAT' in text:
        return 'section'
    if 'MAT BEN' in text:
        return 'section_vertical'
    return None


def split_views(regions, annotations, rects, outlines, classify_geometry=True):
    """Use title centres for columns and title baselines for drawing rows."""
    views=[]
    for region in regions:
        notes=[a for a in annotations if region[0]<=a['point'][0]<region[2] and region[1]<=a['point'][1]<region[3]]
        titles=[a for a in notes if a['kind']=='view_title']
        markers=[a for a in annotations if a['kind']=='section_marker' and
                 any(r[0]<=a['point'][0]<r[2] and r[1]<=a['point'][1]<r[3] for r in regions)]
        levels=[]
        for a in sorted(titles,key=lambda v:v['point'][1]):
            if not levels or abs(a['point'][1]-levels[-1][0]['point'][1])>150:
                levels.append([])
            levels[-1].append(a)
        for row_index,row in enumerate(levels):
            row.sort(key=lambda a:a['center_x'])
            top=levels[row_index+1][0]['point'][1] if row_index+1<len(levels) else region[3]
            occupied=[]
            for r in sorted((r for r in rects if inside(r.box(),[region[0],row[0]['point'][1],region[2],top])),key=lambda r:r.x0):
                if occupied and r.x0<=occupied[-1][1]+60:occupied[-1][1]=max(occupied[-1][1],r.x1)
                else:occupied.append([r.x0,r.x1])
            clusters=[min(occupied,key=lambda b:max(b[0]-t['center_x'],t['center_x']-b[1],0)) if occupied else None for t in row]
            borders=[]
            for i in range(len(row)-1):
                a,b=clusters[i:i+2]
                borders.append((a[1]+b[0])/2 if a and b and a[1]<b[0] else (row[i]['center_x']+row[i+1]['center_x'])/2)
            for i,title in enumerate(row):
                box=[region[0] if i==0 else borders[i-1],
                     title['point'][1],
                     region[2] if i==len(row)-1 else borders[i],top]
                role=title_role(title['text'])
                if role=='section':
                    ids=re.findall(r'(\d+)\s*[-–]\s*\1',title['text'])
                    axes={m['axis'] for m in markers if set(ids).intersection(m['numbers'])}
                    role='plan' if axes=={'horizontal'} else 'section_vertical' if axes=={'vertical'} else 'section_unknown'
                r=[p for p in rects if inside(p.box(),box)]
                o=[p for p in outlines if p['points'] and all(inside([*v,*v],box) for v in p['points'])]
                views.append({'id':f'V{len(views)+1:02}','role':role,'title':title['text'],
                              'region':box,'title_handle':title['handle'],'rects':r,'outlines':o,
                              'section_markers':[m for m in markers if m['axis']=='vertical' and
                              set(re.findall(r'(\d+)\s*[-–]\s*\1',title['text'])).intersection(m['numbers'])] if role=='section_vertical' else []})
    return geometry_roles(views) if classify_geometry else views


def construction_extent(rects):
    remaining=set(range(len(rects)));boxes=[]
    while remaining:
        stack=[remaining.pop()];group=[]
        while stack:
            i=stack.pop();group.append(rects[i].box())
            for j in list(remaining):
                if max(gap_boxes(rects[i].box(),rects[j].box()))<=60:
                    remaining.remove(j);stack.append(j)
        boxes.append(union(group))
    return max(boxes,key=lambda b:(b[2]-b[0])*(b[3]-b[1]))


def geometry_roles(views):
    """Rank construction geometry first; headings only supply spatial hints."""
    boxes={v['id']:construction_extent(v['rects']) for v in views if v['rects']}
    for v in views:
        walls=[r.box() for r in v['rects'] if 3<=r.w<=60 and r.h>800]
        if walls:boxes[v['id']]=union(walls)
    fronts=[]
    for v in views:
        if v['id'] not in boxes:continue
        b=boxes[v['id']];w,h=b[2]-b[0],b[3]-b[1]
        if h>800 and w>h*.35:
            walls=[r for r in v['rects'] if 12<=r.w<=40 and r.h>800]
            doubles=sum(a.h for a in walls for b in walls if a is not b and near(a.x1,b.x0)
                        and near(a.y0,b.y0) and near(a.y1,b.y1))
            tall=[e for e in enclosures(v['rects']) if e['box'][3]-e['box'][1]>800]
            if tall:fronts.append(((round(doubles,2),len(tall)),v))
    fronts.sort(key=lambda item:item[0],reverse=True)
    if not fronts or fronts[0][0]==(0,0) or (len(fronts)>1 and fronts[0][0]==fronts[1][0]):return views
    primary=fronts[0][1];box=boxes[primary['id']];fw,fh=box[2]-box[0],box[3]-box[1]
    for v in views:
        if v['id'] not in boxes:continue
        b=boxes[v['id']];w,h=b[2]-b[0],b[3]-b[1]
        role=None
        if v is primary:role='front_open'
        elif near(w,fw,120) and near(h,fh,120):role='front_check'
        elif 100<=h<=1200 and w>h*1.2 and plan_columns(v['rects']):role='plan'
        elif 100<=w<=1200 and h>fh*.6 and w<fw*.8:role='section_vertical'
        if role:
            v['title_role']=v.get('role');v['role']=role
            v['role_evidence']={'basis':'construction_geometry','width_mm':round(w,3),'height_mm':round(h,3),
                                'closed_carcasses':len(enclosures(v['rects']))}
    return views


def infer_views(rects, outlines):
    """Infer separated orthogonal views only when construction evidence is present."""
    groups=[];remaining=set(range(len(rects)))
    while remaining:
        stack=[remaining.pop()];group=[]
        while stack:
            i=stack.pop();group.append(rects[i])
            for j in list(remaining):
                if max(gap_boxes(rects[i].box(),rects[j].box()))<=60:
                    remaining.remove(j);stack.append(j)
        groups.append(group)
    front_groups=[g for g in groups if (lambda b:b[3]-b[1]>800 and b[2]-b[0]>(b[3]-b[1])*.35)(union([r.box() for r in g])) and enclosures(g)]
    if not front_groups:return []
    front_groups.sort(key=lambda g:len(enclosures(g)),reverse=True)
    if len(front_groups)>1 and len(enclosures(front_groups[0]))==len(enclosures(front_groups[1])):return []
    front=front_groups[0];fb=union([r.box() for r in front]);width=fb[2]-fb[0];height=fb[3]-fb[1]
    views=[]
    for g in groups:
        box=union([r.box() for r in g]);w,h=box[2]-box[0],box[3]-box[1]
        if g is front:role='front_open'
        elif 150<=h<=1200 and w>h*1.2 and plan_columns(g):role='plan'
        elif near(w,width) and abs(h-height)<=120:role='front_check'
        elif 100<=w<=1200 and h>height*.6 and w<width*.8:role='section_vertical'
        else:continue
        views.append({'id':f'I{len(views)+1:02}','role':role,'title':'Suy ra từ cụm hình học tách rời',
                      'region':box,'rects':g,'outlines':[p for p in outlines if p['points'] and
                      all(inside([*v,*v],box) for v in p['points'])],'section_markers':[]})
    return geometry_roles(views)


def plan_columns(rects):
    """Find matching depth-side chains before considering any elevation shelves."""
    vertical=[r for r in rects if 12<=r.w<=40 and r.h>=100 and r.h>r.w*5]
    links=[r for r in rects if 12<=r.h<=40 and r.w>r.h]
    remaining=set(range(len(vertical)))
    chains=[]
    while remaining:
        stack=[remaining.pop()]; group=[]
        while stack:
            i=stack.pop();a=vertical[i];group.append(a)
            for j in list(remaining):
                b=vertical[j]
                if min(a.y1,b.y1)-max(a.y0,b.y0)<=max(a.w,b.w)+TOL and any(near(p.h,a.w) and near(p.h,b.w) and
                       max(gap_boxes(a.box(),p.box()))<=TOL and max(gap_boxes(b.box(),p.box()))<=TOL for p in links):
                    remaining.remove(j);stack.append(j)
        core=union([r.box() for r in group])
        chains.append({'box':core,'core':core,'handles':[r.handle for r in group],
                       'thickness':min(p.w for p in group)})
    chains=[c for c in chains if not covers([(s['core'][0],s['core'][2]) for s in chains if s is not c
            and near(s['core'][1],c['core'][1]) and near(s['core'][3],c['core'][3])
            and c['core'][0]-TOL<=s['core'][0] and s['core'][2]<=c['core'][2]+TOL
            and s['core'][2]-s['core'][0]<c['core'][2]-c['core'][0]-TOL],c['core'][0],c['core'][2])]
    for r in rects:
        owners=[c for c in chains if 2<=r.w<c['thickness']*.7 and r.h<=120
                and c['core'][1]-TOL<=r.y0 and r.y1<=c['core'][3]+TOL
                and max(gap_boxes(r.box(),c['core']))<=TOL]
        if owners:
            owner=max(owners,key=lambda c:c['core'][3]-c['core'][1])
            owner['box']=union([owner['box'],r.box()]);owner['handles'].append(r.handle)
    candidates=[]
    for i,left in enumerate(chains):
        for right in chains[i+1:]:
            a,b=sorted((left,right),key=lambda c:c['box'][0])
            x0,y0,_,y1=a['box'];rx0,ry0,x1,ry1=b['box']
            if not (near(y0,ry0) and near(y1,ry1) and rx0-a['box'][2]>=100):continue
            # A middle side with the same depth is a real intervening boundary.
            if any(c is not a and c is not b and a['box'][2]-TOL<=c['box'][0] and c['box'][2]<=rx0+TOL
                   and near(c['box'][1],y0) and near(c['box'][3],y1) for c in chains):continue
            caps={}
            for p in rects:
                if 2<=p.h<=60 and p.w>100 and y0-TOL<=p.y0 and p.y1<=y1+TOL:
                    caps.setdefault((round(p.y0,1),round(p.h,1)),[]).append((p.x0,p.x1))
            if not any(covers(spans,a['core'][2],b['core'][0]) for spans in caps.values()):continue
            candidates.append({'box':[x0,y0,x1,y1],'core_box':[a['core'][0],y0,b['core'][2],y1],
                               'handles':a['handles']+b['handles']})
    unique={tuple(round(v,2) for v in c['box']):c for c in candidates}
    return sorted(unique.values(),key=lambda c:(c['box'][1],c['box'][0]))


def recovered_rects(view):
    lines=[(a,b,p['handle'],p.get('layer','')) for p in view['outlines']
           if all(near(a[0],b[0]) or near(a[1],b[1]) for a,b in zip(p['points'],p['points'][1:]))
           for a,b in zip(p['points'],p['points'][1:])]
    measured=view['rects']
    recovered=line_rectangles(lines)
    # A shelf/drawer line crossing an explicitly closed panel does not split
    # that panel into hundreds of alternative walls.
    def measured_seams(r):
        vertical=r.h>r.w
        peers=[p for p in measured if p.w<=60 and near(r.x0,p.x0) and near(r.x1,p.x1)] if vertical else [
            p for p in measured if p.h<=60 and near(r.y0,p.y0) and near(r.y1,p.y1)]
        if not any(inside(r.box(),p.box()) for p in peers):return True
        ends=[y for p in peers for y in ((p.y0,p.y1) if vertical else (p.x0,p.x1))]
        return all(any(near(edge,end) for end in ends) for edge in ((r.y0,r.y1) if vertical else (r.x0,r.x1)))
    recovered=[r for r in recovered if measured_seams(r)]
    panels=measured+recovered
    unique={}
    for r in panels:unique.setdefault(tuple(round(v,2) for v in r.box()),r)
    return list(unique.values())


def front_tiers(rects, widths):
    walls=[r for r in rects if 12<=r.w<=60 and r.h>100 and r.h>r.w*5]
    caps=[r for r in rects if 3<=r.h<=60 and r.w>100]
    found={}
    for i,left in enumerate(walls):
        for right in walls[i+1:]:
            a,b=sorted((left,right),key=lambda r:r.x0)
            if not (near(a.y0,b.y0) and near(a.y1,b.y1)):continue
            if not any(near(b.x1-a.x0,w) for w in widths):continue
            middle=[w for w in walls if a.x1-TOL<=w.x0 and w.x1<=b.x0+TOL and
                    near(w.y0,a.y0) and near(w.y1,a.y1)]
            if any(u is not v and near(u.x1,v.x0) and near(u.y0,a.y0) and near(u.y1,a.y1)
                   and near(v.y0,a.y0) and near(v.y1,a.y1) for u in middle for v in middle):continue
            spanning=[p for p in caps if ((near(p.x0,a.x1) and near(p.x1,b.x0)) or
                      (near(p.x0,a.x0) and near(p.x1,b.x1))) and
                      any(near(v,y) for v in (p.y0,p.y1) for y in (a.y0,a.y1))]
            if not spanning:continue
            box=[a.x0,a.y0,b.x1,a.y1]
            key=tuple(round(v,2) for v in box)
            if key in found and found[key]['left_mm']+found[key]['right_mm']<=a.w+b.w:continue
            found[key]={'box':box,'left_mm':a.w,'right_mm':b.w,
                                                'handles':[a.handle,b.handle]+[p.handle for p in spanning]}
    # Hidden end panels can continue into a plinth/cornice, while a cap is drawn
    # as adjacent visible/hidden pieces. Require both complete cap rows and an
    # actual side endpoint at each end; an internal shelf cannot end a module.
    for i,left in enumerate(walls):
        for right in walls[i+1:]:
            a,b=sorted((left,right),key=lambda r:r.x0)
            if near(a.y0,b.y0) and near(a.y1,b.y1):continue
            if not any(near(b.x1-a.x0,w) for w in widths):continue
            y0,y1=max(a.y0,b.y0),min(a.y1,b.y1)
            if y1-y0<=100 or max(abs(a.y0-b.y0),abs(a.y1-b.y1))>120+TOL:continue
            middle=[w for w in walls if a.x1-TOL<=w.x0 and w.x1<=b.x0+TOL and
                    near(w.y0,y0) and near(w.y1,y1)]
            if any(u is not v and near(u.x1,v.x0) and near(u.y0,y0) and near(u.y1,y1)
                   and near(v.y0,y0) and near(v.y1,y1) for u in middle for v in middle):continue
            ends=[]
            for edge,is_bottom in ((y0,True),(y1,False)):
                groups={}
                for p in caps:
                    if not near(p.y0 if is_bottom else p.y1,edge):continue
                    if not any(near(p.h,s) for s in BOARD_MM):continue
                    if p.x0<a.x1-TOL or p.x1>b.x0+TOL:continue
                    groups.setdefault(round(p.h,2),[]).append(p)
                proofs=[ps for ps in groups.values() if covers([(p.x0,p.x1) for p in ps],a.x1,b.x0)]
                if not proofs:break
                ends+=min(proofs,key=len)
            else:
                key=tuple(round(v,2) for v in (a.x0,y0,b.x1,y1))
                found.setdefault(key,{'box':[a.x0,y0,b.x1,y1],'left_mm':a.w,'right_mm':b.w,
                                     'handles':[a.handle,b.handle]+[p.handle for p in ends],
                                     'cap_evidence':'continuous_visible_and_hidden_cap_rows'})
    rows=list(found.values())
    for row in rows:
        x0,y0,x1,y1=row['box']
        lids=[p for p in caps if near(p.x0,x0) and near(p.x1,x1) and near(p.y0,y1) and
              near(p.h,row['left_mm']) and near(p.h,row['right_mm'])]
        if lids:
            row['box'][3]=max(p.y1 for p in lids)
            row['handles'] += [p.handle for p in lids]
    # A larger recovered loop can contain two actual panels joined at a seam.
    return [r for r in rows if not covers([(s['box'][1],s['box'][3]) for s in rows
            if s is not r and near(s['box'][0],r['box'][0]) and near(s['box'][2],r['box'][2])
            and inside(s['box'],r['box']) and s['box'][3]-s['box'][1]<r['box'][3]-r['box'][1]-TOL],
            r['box'][1],r['box'][3])]


def section_joint(sections, boundary, depth):
    for view in sections:
        caps=[r for r in view['rects'] if 3<=r.h<=60 and depth-60-TOL<=r.w<=depth+TOL]
        for below in caps:
            if not near(below.y1,boundary):continue
            for above in caps:
                if near(above.y0,boundary) and min(above.x1,below.x1)-max(above.x0,below.x0)>=depth-120-TOL:
                    return {'bottom':boundary,'section_x':[min(below.x0,above.x0),max(below.x1,above.x1)],
                            'handles':[below.handle,above.handle],'view_id':view['id']}
    return None


def separate_side_trims(tier, rects, sections, depth):
    """Refine a bay envelope only around a separately closed, full-height carcass."""
    rule=next((p for p in TURNED_TRIM if near(tier['left_mm'],p['face_mm']) and
               near(tier['right_mm'],p['face_mm'])),None)
    if not rule:return None
    x0,y0,x1,y1=tier['box'];face=rule['face_mm'];stock=rule['stock_mm']
    walls=[r for r in rects if near(r.w,stock) and near(r.y0,y0) and near(r.y1,y1)]
    left=[r for r in walls if near(r.x0,x0+face)]
    right=[r for r in walls if near(r.x1,x1-face)]
    if not left and not right:return None
    if len(left)!=1 or len(right)!=1:
        raise ValueError('Nẹp hai bên chưa có đủ hai vách thùng bên trong cùng chiều cao; cần kiểm tra trước khi tách.')
    a,b=left[0],right[0]
    caps=[r for r in rects if near(r.x0,a.x1) and near(r.x1,b.x0) and
          any(near(r.h,s) for s in BOARD_MM)]
    bottom=[r for r in caps if near(r.y0,y0)]
    top=[r for r in caps if near(r.y1,y1)]
    if not bottom or not top:
        raise ValueError('Thùng bên trong nẹp chưa khép đủ nóc/đáy; không tự trừ 24 mm từ kích thước khoang.')
    # The section must establish both the carcass depth and which end faces forward.
    proofs=[]
    for view in sections:
        rs=view['rects']
        outer=[r for r in rs if near(r.w,depth) and near(r.y0,y0) and r.y1>=y1-TOL]
        bases=[r for r in rs if near(r.y0,y0) and near(r.h,bottom[0].h) and depth-60<=r.w<depth-TOL]
        backs=[r for r in rs if 3<=r.w<=12 and near(r.y1,y1) and r.y0<y0+60]
        roofs=[r for r in rs if near(r.y1,y1) and near(r.h,top[0].h) and r.w>100]
        for shell in outer:
            for base in bases:
                front_right=near(base.x0,shell.x0) and near(shell.x1-base.x1,stock)
                front_left=near(base.x1,shell.x1) and near(base.x0-shell.x0,stock)
                for back in backs:
                    for roof in roofs:
                        rear_left=(front_right and 0<=back.x0-shell.x0<=60 and
                                   near(roof.x0,back.x1) and near(roof.x1,base.x1))
                        rear_right=(front_left and 0<=shell.x1-back.x1<=60 and
                                    near(roof.x1,back.x0) and near(roof.x0,base.x0))
                        if rear_left or rear_right:
                            proofs.append({'depth_mm':base.w,'front_offset_mm':depth-base.w,
                                           'view_id':view['id'],'handles':[shell.handle,base.handle,back.handle,roof.handle]})
    unique={(round(p['depth_mm'],3),round(p['front_offset_mm'],3)):p for p in proofs}
    if len(unique)!=1:
        raise ValueError('Đã thấy hai nẹp và thùng bên trong nhưng mặt cắt chưa xác nhận duy nhất chiều sâu/vị trí mặt trước.')
    proof=next(iter(unique.values()))
    handles=[a.handle,b.handle]+[r.handle for r in bottom+top]
    parts=[{'role':'module_side_trim','side':side,'face_width_mm':face,'stock_thickness_mm':stock,
            'source_box':box,'handles':tier['handles'],'depth_evidence':proof,
            'evidence':'User-confirmed auxiliary side trims; full-height inner side panels and both caps; front band measured in the matching section.'}
           for side,box in [('left',[x0,y0,a.x0,y1]),('right',[b.x1,y0,x1,y1])]]
    return {'box':[a.x0,y0,b.x1,y1],'handles':handles,'depth_evidence':proof,'parts':parts}


def recognise_ordered(views, pipeline):
    """Plan bays first; only then assign front-open tier heights within those bays."""
    plans=[v for v in views if v['role']=='plan']
    fronts=[v for v in views if v['role']=='front_open']
    sections=[v for v in views if v['role']=='section_vertical']
    if not plans or len(fronts)!=1 or not sections:
        raise ValueError('Luồng chia dọc trước cần mặt bằng/mặt cắt bằng, một mặt đứng bỏ cánh và mặt cắt đứng tương ứng.')
    layouts=[]
    for view in plans:
        bays=plan_columns(view['rects'])
        # Keep connected bay runs; isolated detail drawings do not add score to a cabinet.
        runs=[]
        for bay in sorted(bays,key=lambda b:b['box'][0]):
            if runs and abs(bay['box'][0]-runs[-1][-1]['box'][2])<=60 and abs(bay['box'][3]-runs[-1][-1]['box'][3])<=60:
                runs[-1].append(bay)
            else:runs.append([bay])
        layouts += [(sum(b['box'][2]-b['box'][0] for b in run),view,run) for run in runs]
    if not layouts:raise ValueError('Chưa ghép được các vách sâu tương ứng ở mặt bằng; chưa bắt đầu chia tầng ngang.')
    layouts.sort(key=lambda v:(round(v[0],2),len(v[2])),reverse=True)
    _,plan,bays=layouts[0]
    for i,b in enumerate(bays):b['id']=f'C{i+1:02}'
    pipeline['vertical']={'view_id':plan['id'],'columns':bays}
    front=fronts[0];rects=recovered_rects(front)
    ranges=[(i,j,bays[j]['box'][2]-bays[i]['box'][0]) for i in range(len(bays)) for j in range(i,len(bays))]
    candidates=front_tiers(rects,[w for _,_,w in ranges])
    shifts={round(c['box'][0]-bays[i]['box'][0],2) for c in candidates for i,j,w in ranges if near(c['box'][2]-c['box'][0],w)}
    matches=[]
    for shift in shifts:
        mapped=[]
        for c in candidates:
            ids=[(i,j) for i,j,w in ranges if near(c['box'][0],bays[i]['box'][0]+shift) and near(c['box'][2],bays[j]['box'][2]+shift)]
            if ids:mapped.append({**c,'columns':list(range(ids[0][0],ids[0][1]+1))})
        covered={i for c in mapped for i in c['columns']}
        matches.append((len(covered),sum((c['box'][2]-c['box'][0])*(c['box'][3]-c['box'][1]) for c in mapped),shift,mapped))
    if not matches:raise ValueError('Các khoang đo từ mặt bằng không ghép được với bề rộng thùng ở mặt đứng bỏ cánh.')
    matches.sort(key=lambda m:(m[0],m[1]),reverse=True)
    count,_,shift,tiers=matches[0]
    pipeline['horizontal']={'view_id':front['id'],'x_offset':shift,'candidates':tiers}
    if count!=len(bays):raise ValueError('Có khoang mặt bằng chưa ghép được tầng ngang ở mặt đứng bỏ cánh; không dùng chi tiết ngăn kéo thay thế.')
    for i,bay in enumerate(bays):
        intervals=sorted((t['box'][1],t['box'][3]) for t in tiers if i in t['columns'])
        sides=[r for r in front['rects'] if 12<=r.w<=60 and r.h>100 and
               (near(r.x0,bay['box'][0]+shift) or near(r.x1,bay['box'][2]+shift))]
        for side in sides:
            reach=side.y0;covered=0
            for lo,hi in intervals:
                lo=max(lo,reach,side.y0);hi=min(hi,side.y1)
                if hi>lo:covered+=hi-lo;reach=hi
            if side.h-covered>120+TOL:
                raise ValueError('Có tầng thùng trong khoang mặt bằng chưa khép đủ nóc/đáy; không bỏ tầng còn thiếu để dựng phần trên.')
    if len(matches)>1 and matches[1][:2]==matches[0][:2] and abs(matches[1][2]-shift)>TOL:
        raise ValueError('Có nhiều cách ghép mặt bằng với mặt đứng bỏ cánh; cần kiểm tra vị trí hình chiếu.')
    all_rects=rects+[r for v in sections for r in v['rects']]
    all_outlines=front['outlines']+[o for v in sections for o in v['outlines']]
    checks=[v for v in views if v['role']=='front_check']
    front_left=min((r.x0 for r in rects if 12<=r.w<=60 and r.h>500),default=min(c['box'][0] for c in tiers))
    def matching_sections(tier):
        selected=[]
        connected=set(tier['columns'])
        while True:
            neighbours={j for i in connected for j in range(len(bays)) if
                        (near(bays[i]['box'][0],bays[j]['box'][2]) or near(bays[i]['box'][2],bays[j]['box'][0])) and
                        near(bays[i]['box'][1],bays[j]['box'][1]) and near(bays[i]['box'][3],bays[j]['box'][3])}
            if neighbours.issubset(connected):break
            connected|=neighbours
        shared_box=union([bays[i]['box'] for i in connected])
        for section in sections:
            located=[]
            for marker in section.get('section_markers',[]):
                for check in checks:
                    if not inside([*marker['point'],*marker['point']],check['region']):continue
                    walls=[r for r in check['rects'] if r.w>=3 and r.h>500 and
                           'HATCH' not in normalise(r.layer)]
                    if not walls:continue
                    left=min(r.x0 for r in walls)
                    located.append(marker['point'][0]-left+front_left)
            if not located or any(shared_box[0]+shift-TOL<=x<=shared_box[2]+shift+TOL for x in located):selected.append(section)
        if not selected:
            depth=max(bays[i]['box'][3]-bays[i]['box'][1] for i in tier['columns'])
            # Repeated cabinets may have only one cut. Share it only when both
            # measured tier planes and depth agree; validate_joint still checks
            # this bay's front seam and rejects an uncut section panel.
            selected=[s for s in sections if section_joint([s],tier['box'][1],depth) and
                      any(near(r.y1,tier['box'][3]) and 3<=r.h<=60 and
                          depth-60-TOL<=r.w<=depth+TOL for r in s['rects'])]
        return selected
    # Assign the gap between tiers from a construction joint, not a door edge.
    for lower in tiers:
        for upper in tiers:
            if lower is upper or not set(lower['columns']).issubset(upper['columns']):continue
            gap=upper['box'][1]-lower['box'][3]
            if not (-TOL<=gap<=120):continue
            depth=max(bays[i]['box'][3]-bays[i]['box'][1] for i in upper['columns'])
            local_sections=matching_sections(upper)
            local_rects=rects+[r for v in local_sections for r in v['rects']]
            local_outlines=front['outlines']+[o for v in local_sections for o in v['outlines']]
            if abs(gap)<=TOL:
                if 'joint_evidence' not in upper:
                    joint=section_joint(local_sections,upper['box'][1],depth)
                    if not joint:raise ValueError('Đường chia ngang chưa có hai panel tiếp giáp ở mặt cắt đứng.')
                    upper['joint_evidence']=validate_joint(upper,local_rects,local_outlines,joint)
                continue
            own_bottom=any(near(r.y0,upper['box'][1]) and near(r.x0,upper['box'][0]+upper['left_mm']) and
                           near(r.x1,upper['box'][2]-upper['right_mm']) and 3<=r.h<=60 for r in rects)
            joint=section_joint(local_sections,upper['box'][1],depth)
            if own_bottom and joint:
                upper['joint_evidence']=validate_joint(upper,local_rects,local_outlines,joint)
                lower['carcass_box']=list(lower['box']);lower['box'][3]=upper['box'][1]
                lower['handles']+=joint['handles']
            else:
                support=section_support(upper,local_rects,local_outlines,depth,upper['left_mm'],require_profile=False)
                if not support or not near(support['bottom'],lower['box'][3]):
                    raise ValueError('Khoảng giữa hai tầng chưa có mối ghép mặt cắt xác nhận; không chia theo đáy cánh.')
                upper['joint_evidence']=validate_joint(upper,local_rects,local_outlines,support)
                upper['carcass_box']=list(upper['box']);upper['box'][1]=support['bottom']
                upper['handles']+=support['handles']
    envelope=union([t['box'] for t in tiers]);plan_box=union([b['box'] for b in bays])
    front_profiles=[]
    for outline in plan['outlines']:
        pts=outline['points']
        if len(pts)<4 or not all(near(a,b) for a,b in zip(pts[0],pts[-1])):continue
        box=union([[*p,*p] for p in pts])
        front_profiles.append(Rect(*box,outline['handle'],outline.get('layer','')))
    # A framed door's closed stepped contour has a measurable footprint even
    # when its section is not a rectangle. Use its band only for door depth.
    door_rows=[r for r in plan['rects']+front_profiles if 3<=r.h<=60 and r.w>r.h and any(near(r.y1,b['box'][1]) for b in bays)]
    if any(covers([(r.x0,r.x1) for r in door_rows if near(r.y1,b['box'][1])],b['box'][0],b['box'][2]) for b in bays):
        plan_box[1]=min(r.y0 for r in door_rows)
    trims=[r.box() for r in rects if near(r.x0,envelope[0]) and near(r.x1,envelope[2]) and
           0<r.h<=120 and (near(r.y1,envelope[1]) or near(r.y0,envelope[3]))]
    envelope=union([envelope]+trims)
    output=[];auxiliary=[]
    for t in sorted(tiers,key=lambda c:(round(c['box'][1],2),c['box'][0])):
        selected=[bays[i] for i in t['columns']]
        footprint=union([b['box'] for b in selected])
        if any(not near(b['box'][1],footprint[1]) or not near(b['box'][3],footprint[3]) for b in selected):
            raise ValueError('Một tầng ngang đang gộp các khoang có chiều sâu khác nhau; cần kiểm tra cấu tạo.')
        refined=separate_side_trims(t,rects,matching_sections(t),footprint[3]-footprint[1])
        x0,y0,x1,y1=refined['box'] if refined else t['box']
        front_offset=refined['depth_evidence']['front_offset_mm'] if refined else 0
        m={'id':f'M{len(output)+1:02}','name':f'Module {len(output)+1:02}',
           'origin':[round(x0-envelope[0],3),round(footprint[1]-plan_box[1]+front_offset,3),round(y0-envelope[1],3)],
           'size':[round(x1-x0,3),round(footprint[3]-footprint[1]-front_offset,3),round(y1-y0,3)],
           'source_box':[x0,y0,x1,y1],'plan_box':footprint,'column_ids':[b['id'] for b in selected],
           'handles':sorted(set(t['handles']+[h for b in selected for h in b['handles']])),
           'rule':'plan-first-front-tiers-v1',
           'explanation':'Chia khoang dọc từ mặt bằng trước; cao độ tầng lấy từ mặt đứng bỏ cánh và kiểm tra mối ghép mặt cắt.'}
        if 'joint_evidence' in t:m['joint_evidence']=t['joint_evidence']
        if 'carcass_box' in t:m['carcass_box']=t['carcass_box']
        if refined:
            m.update(enclosure_box=t['box'],depth_evidence=refined['depth_evidence'],
                     rule='plan-first-inner-carcass-with-side-trims-v1',
                     explanation='Thùng kín nằm giữa hai nẹp phụ 24 mm; vách/nóc/đáy lấy từ mặt đứng bỏ cánh, chiều sâu và mặt trước xác nhận bằng mặt cắt.')
            m['handles']=sorted(set(m['handles']+refined['handles']+refined['depth_evidence']['handles']))
            for part in refined['parts']:
                part['owner_module_id']=m['id']
                part['plan_origin_y']=footprint[1]-plan_box[1]
                auxiliary.append(part)
        # One replacement module is the complete assembly, including its doors.
        body_origin=list(m['origin']);body_size=list(m['size'])
        projected=[x0-shift,x1-shift]
        frontage=[r for r in door_rows if near(r.y1,footprint[1]) and max(r.x0,projected[0])<min(r.x1,projected[1])-TOL]
        door_depth=0;door_handles=[]
        if covers([(r.x0,r.x1) for r in frontage],*projected):
            door_depth=max(0,footprint[1]-min(r.y0 for r in frontage))
            door_handles=[r.handle for r in frontage]
        if refined:
            door_depth=refined['depth_evidence']['front_offset_mm']
            door_handles=refined['depth_evidence']['handles']
        m['scope']='carcass_and_doors'
        if door_depth>TOL:
            m['carcass_origin']=body_origin;m['carcass_size']=body_size
            m['origin'][1]=round(m['origin'][1]-door_depth,3)
            m['size'][1]=round(m['size'][1]+door_depth,3)
            m['door_evidence']={'depth_mm':door_depth,'handles':door_handles,'basis':'measured_plan_or_matching_section'}
            m['explanation']+=' Khối module bao gồm cả thùng và cánh; phần phụ không gộp vào thùng.'
        output.append(m)
    if overlapping_modules(output):raise ValueError('Các tầng sau khi ghép hình chiếu chồng nhau; cần kiểm tra đường chia.')
    pipeline['horizontal']['modules']=output
    # Record uncovered structural frontage instead of silently guessing it is trim.
    trims=[]
    walls=[r for r in rects if 12<=r.w<=40 and r.h>500 and
           envelope[0]-60-TOL<=r.x0 and r.x1<=envelope[2]+60+TOL and
           min(r.y1,envelope[3])-max(r.y0,envelope[1])>r.h*.5]
    if walls:
        outer=union([r.box() for r in walls]);extra=(outer[2]-outer[0])-(envelope[2]-envelope[0])
        gaps=[(a['box'][2]+shift,b['box'][0]+shift) for a,b in zip(bays,bays[1:]) if b['box'][0]-a['box'][2]>TOL]
        unassigned=[r for r in walls if r.x0<envelope[0]-TOL or r.x1>envelope[2]+TOL or
                    any(near(r.x0,a) and near(r.x1,b) for a,b in gaps)]
        if unassigned:
            trims,unresolved=perimeter_trims(unassigned,plan['rects'],shift,envelope,gaps)
            pipeline['trim_parts']=trims
            if unresolved:
                extra=sum(b-a for a,b in {(round(r.x0,2),round(r.x1,2)) for r in unresolved})
                pipeline['unassigned_front']={'width_mm':round(extra,3),'handles':[r.handle for r in unresolved],
                                              'boxes':[r.box() for r in unresolved]}
                raise ValueError(f'Còn {round(extra,3):g} mm bề rộng mặt đứng ngoài các khoang mặt bằng đã ghép; cần xác định phần vách/ốp trước khi dựng.')
    trims+=auxiliary
    pipeline['trim_parts']=trims
    pipeline['checks']=[{'view_id':v['id'],'role':'check_only'} for v in views if v['role']=='front_check']
    cut_stock=Counter(round(r.w,2) for r in plan['rects'] if r.h>100 and any(near(r.w,s) for s in BOARD_MM if s>=12))
    panel=cut_stock.most_common(1)[0][0] if cut_stock else min(t['left_mm'] for t in tiers)
    backs=Counter(round(min(r.w,r.h),2) for r in all_rects if 2<=min(r.w,r.h)<panel*.7 and max(r.w,r.h)>200)
    product_envelope=union([envelope]+[t['source_box'] for t in trims])
    old_front=plan_box[1]
    plan_box[1]=min([old_front]+[b[1] for t in trims for b in t.get('plan_boxes',[])])
    for m in output:
        for key in ('origin','carcass_origin'):
            if key not in m:continue
            m[key]=[round(m[key][0]+envelope[0]-product_envelope[0],3),
                    round(m[key][1]+old_front-plan_box[1],3),
                    round(m[key][2]+envelope[1]-product_envelope[1],3)]
    for i,t in enumerate(trims):
        t['id']=f'T{i+1:02}'
        if t.get('owner_module_id'):
            origin_y=t.pop('plan_origin_y');part_depth=t['depth_evidence']['front_offset_mm']
        else:
            plan_part=union(t['plan_boxes']);origin_y=plan_part[1]-plan_box[1];part_depth=plan_part[3]-plan_part[1]
        t['origin']=[round(t['source_box'][0]-product_envelope[0],3),round(origin_y,3),round(t['source_box'][1]-product_envelope[1],3)]
        t['size']=[round(t['source_box'][2]-t['source_box'][0],3),round(part_depth,3),round(t['source_box'][3]-t['source_box'][1],3)]
    for m in output:
        owned=[p['id'] for p in trims if p.get('owner_module_id')==m['id']]
        if owned:m['auxiliary_part_ids']=owned
    return {'modules':output,'bounds':[round(product_envelope[2]-product_envelope[0],3),round(plan_box[3]-plan_box[1],3),round(product_envelope[3]-product_envelope[1],3)],
            'envelope':product_envelope,'front_box':envelope,'panel_mm':panel,'back_mm':backs.most_common(1)[0][0] if backs else None,
            'trim_parts':trims,'material_standards_mm':list(BOARD_MM),
            'depth_evidence':[{'depth':b['box'][3]-b['box'][1],'handles':b['handles'],'view_id':plan['id']} for b in bays],
            'signature':geometry_signature(all_rects,envelope,all_outlines),
            'explanation':['Mặt bằng/mặt cắt bằng chia khoang dọc trước; mặt đứng bỏ cánh và mặt cắt đứng chia tầng ngang sau.',
                           'Mặt đứng có cánh chỉ đối chiếu; leader và ký hiệu mặt cắt đã loại khỏi dữ liệu hình học.',
                           'Kích thước đo từ LINE/POLYLINE; không sử dụng DIM.']}
