"""Uncropped CAD inspection planes, independent of module-height recognition."""
from collections import defaultdict

from geometry import near,union
from oy_sweep import plates
from plan_profiles import arc_bounds
from views import title_role
from materials import BOARD_MM


def segment_box(segment):
    if segment['type']=='arc':return arc_bounds(segment)
    return union([[*p,*p] for p in (segment['start'],segment['end'])])


def project(point,view,plan):
    x,y=point;box=view.get('anchor_box_mm',view['box_mm'])
    if view['plane']=='YZ':
        depth=box[2]-x if view.get('reversed_depth') else x-box[0]
        return [view['display_x_mm'],view.get('display_y_mm',plan[1])+depth,y-box[1]]
    if view['plane']=='XZ':
        if view['role']=='section_vertical' and view.get('alignment')!='section_display_copy':
            x=view['display_x_mm']+(box[2]-x if view.get('reversed_depth') else x-box[0])
        else:x+=view.get('drawing_x_offset_mm',view['x_offset_mm'])
        return [x,0,y-box[1]]
    offset=view.get('xy_offset_mm',[0,0])
    return [x+offset[0],y+offset[1],view.get('z_mm',0)]


def depth_direction(plan,side):
    """Compare indexed stock-pair offsets; never scan all parallel line pairs."""
    if not plan or not side:return None
    pb,sb=plan['box_mm'],side['box_mm']
    pairs={(b[1]-pb[1],b[3]-pb[1]) for p in plan['panels'] for b in [p['box_mm']]
           if b[2]-b[0]>max(100,4*(b[3]-b[1])) and any(near(b[3]-b[1],s) for s in BOARD_MM)}
    spans={(b[0]-sb[0],b[2]-sb[0]) for p in side['panels'] for b in [p['box_mm']]
           if b[3]-b[1]>max(100,4*(b[2]-b[0])) and any(near(b[2]-b[0],s) for s in BOARD_MM)}
    bins=defaultdict(list)
    for a,b in pairs:bins[round(a/.15)].append((a,b))
    def matches(spans):
        return sum(any(near(a,x) and near(b,y) for k in (round(a/.15)-1,round(a/.15),round(a/.15)+1) for x,y in bins[k]) for a,b in spans)
    depth=sb[2]-sb[0]
    direct=matches(spans)
    reverse=matches({(depth-b,depth-a) for a,b in spans})
    if direct==reverse or max(direct,reverse)==0:return None
    return reverse>direct


def front_offset(plan_rows,front_rows,plan,front,base):
    from view_signatures import align
    result=align(plan_rows,front_rows)
    return result['offset_mm'] if result['status']=='proven' else None


def front_kind(summary,body,box):
    kind=title_role(summary.get('title',''))
    if kind in ('front_open','front_check'):return kind
    slopes=set()
    for row in body:
        for a,b in zip(row['points'],row['points'][1:]):
            dx,dy=b[0]-a[0],b[1]-a[1]
            if abs(dx)>.1*(box[2]-box[0]) and abs(dy)>.1*(box[3]-box[1]):slopes.add(dx*dy>0)
    if len(slopes)==2:return 'front_check'
    boards,_=plates(body)
    if sum(r.h>max(100,4*r.w) for r in boards)>=3 and sum(r.w>max(100,4*r.h) for r in boards)>=3:return 'front_open'
    return 'front_unspecified'


def prepare_views(product,rows,base,segments):
    summaries={v['id']:v for v in product['view_analysis']['candidates']}
    indexed=defaultdict(list)
    for row in rows:indexed[row['handle']].append(row)
    entries=[];owners=defaultdict(set)
    for preview in product.get('cad_reference_views',[]):
        handles=set(preview.get('source_handles',[o['handle'] for o in preview['outlines']]))
        row_ids=preview.get('source_row_indices')
        body=[rows[i] for i in row_ids] if row_ids is not None else [r for h in handles for r in indexed[h]]
        own=set(row_ids or [])
        indices=[i for i,s in enumerate(segments) if set(s.get('source_rows',[])) & own] if row_ids is not None else [i for i,s in enumerate(segments) if set(s['handles']) & handles]
        if not indices:continue
        box=union([segment_box(segments[i]) for i in indices])
        entry=dict(id=preview['id'],plane='XY',box_mm=box,segment_indices=indices,alignment='unresolved',
                   title=summaries[preview['id']].get('title',''))
        entries.append((entry,body))
        for i in indices:owners[i].add(entry['id'])
    # Keep every source segment exactly once, including unclassified symbols and
    # context that the recognizer deliberately removed from its working geometry.
    for entry,_ in entries:entry['segment_indices']=[i for i in entry['segment_indices'] if len(owners[i])==1]
    entries=[(e,r) for e,r in entries if e['segment_indices']]
    missing=[i for i in range(len(segments)) if len(owners[i])!=1]
    if missing:
        entries.append((dict(id='SOURCE-CONTEXT',plane='XY',alignment='unresolved',title='Nét nguồn chưa phân loại',
                             box_mm=union([segment_box(segments[i]) for i in missing]),segment_indices=missing),[]))
    selected=next((pair for pair in entries if pair[0]['id']==product['plan_view_id']),None)
    if selected is None:raise ValueError('Thiếu mặt bằng gốc để căn bộ hình chiếu CAD.')
    plan,plan_rows=selected;pb=plan['box_mm'];plan['alignment']='source_plan';plan['role']='plan'
    plan['anchor_box_mm']=pb
    from cad_registration import register
    register(entries,product,base,plan)
    values=[v for v,_ in entries]
    for view in values:
        level=product.get('cad_reference_levels',{}).get(view['id'])
        if not level:continue
        view['level']=level;view['z_mm']=level.get('placement_z_mm',level.get('level_mm',0))
        if level['status'] in ('measured','provisional'):
            view.update(plane='XY',role='plan')
            if view is not plan:view['alignment']='registered_plan_level' if level['status']=='measured' else 'provisional_plan_level'
    from cad_display import arrange
    copies=arrange(values)
    points=[project([b[i],b[j]],v,pb) for v in values+copies for b in [v['box_mm']] for i in (0,2) for j in (1,3)]
    bounds=[min(p[i] for p in points) for i in range(3)]+[max(p[i] for p in points) for i in range(3)]
    return dict(views=values,display_copies=copies,display_mode='front_overlay',plan_bounds_mm=pb,placed_bounds_mm=bounds)
