"""Local stock bays for a linked horizontal section with perpendicular arms."""
from collections import defaultdict
from copy import deepcopy

from cad_datums import context_hint,panel_boxes
from geometry import TOL,inside,union,overlapping_modules,rectangle
from oy_sweep import bays
from views import title_role


def source_box(box,axis):
    return box[:] if axis==0 else [-box[3],box[0],-box[1],box[2]]


def inventory(front):
    rects=front['rects'];intervals=[(r.x0,r.x1) for r in rects if r.w>100 and r.h<=36+TOL]
    groups=defaultdict(list)
    for r in rects:
        if r.h>100 and r.h>4*r.w:groups[round(r.y0,3),round(r.y1,3)].append(r)
    for group in groups.values():
        for a,b in zip(sorted(group,key=lambda r:r.x0),sorted(group,key=lambda r:r.x0)[1:]):
            if b.x0-a.x1>100:intervals.append((a.x0,b.x1))
    # Inner caps and outside walls describe the same station, not extra modules.
    selected=[]
    for a,b in sorted(set(intervals),key=lambda ab:ab[0]-ab[1]):
        if any(min(b,d)-max(a,c)>min(b-a,d-c)-72-TOL for c,d in selected):continue
        selected.append((a,b))
    return sorted(selected)


def chain_match(widths,intervals):
    states={(0,0):(0,0,[])}
    for i in range(len(widths)+1):
        for j in range(len(intervals)+1):
            score=states.get((i,j))
            if score is None:continue
            candidates=[]
            if i<len(widths):candidates.append(((i+1,j),score))
            if j<len(intervals):candidates.append(((i,j+1),score))
            if i<len(widths) and j<len(intervals):
                w=intervals[j][1]-intervals[j][0];options=widths[i] if isinstance(widths[i],list) else [widths[i]]
                chosen=min(options,key=lambda value:abs(value-w));error=abs(chosen-w)/w
                if error<=.20:candidates.append(((i+1,j+1),(score[0]+1,score[1]-error,score[2]+[dict(module_index=i,chosen_width_mm=chosen,front_interval=list(intervals[j]),difference_mm=round(chosen-w,6))])))
            for key,value in candidates:
                if key not in states or value[:2]>states[key][:2]:states[key]=value
    return states[len(widths),len(intervals)]


def complete(child,view,data):
    if not child.get('envelope_preview') or child.get('manual_boxes') or child.get('scan_capture'):return False
    summary=next(c for c in child['view_analysis']['candidates'] if c['id']==view['id'])
    links=[c for c in summary['section_links'] if c['axis']=='horizontal' and c.get('cut_line')]
    if not links or min(view['features']['width_mm'],view['features']['height_mm'])<=1200:return False
    fronts=[v for v in data['views'].values() if v['role']=='elevation' and title_role(v.get('title',''))=='front_open']
    if len(fronts)<2 or child.get('height_source')!='product_elevation_bounds':return False
    rows=[r for r in view['outlines'] if not context_hint(r)];candidates=[]
    for axis in (0,1):
        local=[dict(r,points=r['points'] if axis==0 else [[p[1],-p[0]] for p in r['points']]) for r in rows]
        _,rects=panel_boxes(local);cells,details=bays(rects,local)
        for cell in cells:
            b=cell['box'];side=[w['source_box'] for w in details['walls'] if inside(w['box'],b)]
            caps=[r.box() for r in rects if r.w>100 and r.h<=36+TOL and inside(r.box(),b)]
            candidates.append(dict(axis=axis,source_box=source_box(b,axis),local_box=b,closed=True,handles=cell['handles'],walls=side,caps=caps))
        groups=defaultdict(list)
        for r in rects:
            if r.h>100 and r.h>4*r.w:groups[round(r.y0,3),round(r.y1,3)].append(r)
        for group in groups.values():
            ordered=sorted(group,key=lambda r:r.x0)
            for a,b in zip(ordered,ordered[1:]):
                if b.x0-a.x1<=100:continue
                box=[a.x0,a.y0,b.x1,a.y1];depth=box[3]-box[1]
                sections=[v for v in data['views'].values() if v['role']=='section_vertical' and abs(v['box'][2]-v['box'][0]-depth)<=36+TOL]
                if not sections:continue
                candidates.append(dict(axis=axis,source_box=source_box(box,axis),local_box=box,closed=False,
                    walls=[a.box(),b.box()],handles=[a.handle,b.handle]))
    selected=[]
    for c in sorted(candidates,key=lambda c:(not c['closed'],-(c['source_box'][2]-c['source_box'][0])*(c['source_box'][3]-c['source_box'][1]))):
        b=c['source_box']
        if any(min(b[2],q['source_box'][2])-max(b[0],q['source_box'][0])>TOL and min(b[3],q['source_box'][3])-max(b[1],q['source_box'][1])>TOL for q in selected):continue
        selected.append(c)
    if {c['axis'] for c in selected}!={0,1}:return False
    frame=child['source_plan_envelope'];before=child['modules'][0];modules=[];trims=[];matches=[]
    for axis in (0,1):
        arm=sorted([c for c in selected if c['axis']==axis],key=lambda c:c['local_box'][0]);widths=[c['local_box'][2]-c['local_box'][0] for c in arm]
        # A perpendicular arm is also visible in this elevation. Overlapping
        # projections are alternatives, never extra cabinet widths to add twice.
        projected={}
        end=max(c['source_box'][axis+2] for c in arm)
        for c in selected:
            b=c['source_box']
            if c['axis']!=axis and 0<=b[axis]-end<=72+TOL:
                projected.setdefault(round(b[axis],3),[]).append(b[axis+2]-b[axis])
        options=widths+[sorted(set(values)) for key,values in sorted(projected.items())]
        ranked=[]
        for f in fronts:
            spans=inventory(f);score=chain_match(options,spans)
            ranked.append((score[0],score[1],f,spans,score[2]))
        ranked.sort(key=lambda r:r[:2],reverse=True);best=ranked[0]
        ambiguous=len(ranked)>1 and best[:2]==ranked[1][:2]
        group=dict(axis='X' if axis==0 else 'Y',front_id=None if ambiguous else best[2]['id'],status='ambiguous' if ambiguous or not best[0] else 'supported',
            front_title=best[2].get('title',''),
            matched_modules=best[0],module_widths_mm=widths,front_intervals=best[3],matches=best[4],
            module_span_mm=max(c['local_box'][2] for c in arm)-min(c['local_box'][0] for c in arm),
            front_width_mm=best[2]['box'][2]-best[2]['box'][0])
        body=list(best[2]['rects'])
        for row in best[2]['outlines']:
            r=rectangle(row['points'],row['handle'],row.get('layer',''))
            # A24mm frontal turned trim is18mm stock plus the adjoining6mm
            # seam in this plan; it is not a new standard board thickness.
            if r and abs(r.w-24)<=TOL and r.h>100 and not context_hint(row):body.append(r)
        body_box=union([r.box() for r in body])
        group['front_furniture_width_mm']=body_box[2]-body_box[0]
        group['projected_width_options_mm']=options
        group['projected_widths_used_mm']=[m['chosen_width_mm'] for m in best[4] if m['module_index']>=len(arm)]
        matches.append(group)
        for c in arm:
            b=c['source_box'];w=c['local_box'][2]-c['local_box'][0];depth=c['local_box'][3]-c['local_box'][1]
            sections=[dict(view_id=v['id'],depth_mm=v['box'][2]-v['box'][0],difference_mm=round(depth-v['box'][2]+v['box'][0],6)) for v in data['views'].values()
                if v['role']=='section_vertical' and abs(depth-v['box'][2]+v['box'][0])<=36+TOL]
            part=dict(id=f'M{len(modules)+1:02}',name=f'Khoang {group["axis"]} · {w:g} × {depth:g}',origin=[b[0]-frame[0],b[1]-frame[1],before['origin'][2]],
                size=[b[2]-b[0],b[3]-b[1],before['size'][2]],source_box=b,plan_box=b[:],height_source=before['height_source'],elevation_pending=True,
                elevation_evidence=deepcopy(before['elevation_evidence']),plan_component_evidence=dict(c,sections=sections),handles=c['handles'],
                rule='horizontal-cut-component-v1',explanation='Khoang từ cặp ván theo hướng nhánh; chiều cao đang là khung SP, chưa xác nhận tầng. '+('Thiếu biên hậu: giữ box tạm riêng.' if not c['closed'] else ''))
            if not c['closed']:part.update(unresolved=True,envelope_preview=True)
            modules.append(part)
    # Retain closed narrow connector strips rather than letting their overall
    # width determine which front family owns each perpendicular module chain.
    _,boards=panel_boxes(rows)
    for r in boards:
        if min(r.w,r.h)>36+TOL or max(r.w,r.h)>100:continue
        b=r.box()
        if any(inside(b,p['source_box']) for p in modules+trims):continue
        part=dict(id=f'T{len(trims)+1:02}',name='Nẹp nối · theo CAD',origin=[b[0]-frame[0],b[1]-frame[1],before['origin'][2]],
            size=[r.w,r.h,before['size'][2]],source_box=b,plan_box=b[:],height_source=before['height_source'],elevation_pending=True,
            elevation_evidence=deepcopy(before['elevation_evidence']),solid_proxy=True,role='plan_auxiliary',handles=r.handle.split('+'))
        if not overlapping_modules(modules+trims+[part]):trims.append(part)
    if overlapping_modules(modules+trims):return False
    for g in matches:
        parts=[p for p in modules if p['plan_component_evidence']['axis']==(0 if g['axis']=='X' else 1)]
        axis=0 if g['axis']=='X' else 1
        g['module_width_sum_mm']=sum(p['size'][axis] for p in parts)+sum(g['projected_widths_used_mm'])
        g['auxiliary_width_sum_mm']=sum(p['size'][axis] for p in trims if p['size'][axis]<=36+TOL and p['size'][1-axis]>36)
        g['sum_with_auxiliary_mm']=g['module_width_sum_mm']+g['auxiliary_width_sum_mm']
        g['unexplained_front_mm']=g['front_furniture_width_mm']-g['sum_with_auxiliary_mm']
    child.update(status='ready',modules=modules,trim_parts=trims,panel_parts=[],plan_components=dict(engine='linked-horizontal-arms-v1',source_signature=data['source_signature'],
        front_matches=matches,cut_links=links,closed_bays=sum(c['closed'] for c in selected),pending_bays=sum(not c['closed'] for c in selected)),
        plan_partition_pending=True,elevation_pending=True,bounds=[frame[2]-frame[0],frame[3]-frame[1],child['bounds'][2]])
    child.pop('envelope_preview',None);child.pop('error',None)
    child['geometry_pipeline']['horizontal'].update(status='partial',issues=['Chia khoang theo nhánh mặt bằng; chiều cao từng khoang và phần chênh mặt đứng còn cần kiểm tra.'])
    child['explanation']=['Dấu cắt ngang xác nhận mặt cắt bằng lớn/chữ L; chia từng nhánh từ cặp ván. Không yêu cầu một chiều rộng tổng khớp mọi mặt đứng.',
        'Giữ số đo thực; tổng module và nẹp được so với từng mặt đứng. Phần chênh chưa được tự coi là nẹp hay tự co giãn.']
    child['warnings']=list(child['geometry_pipeline']['horizontal']['issues'])
    for g in matches:
        child['explanation'].append(f'Nhánh {g["axis"]} → {g["front_title"]} ({g["front_id"] or "còn phân vân"}): module/phần chiếu {g["module_width_sum_mm"]:.3f} + phụ {g["auxiliary_width_sum_mm"]:.3f} = {g["sum_with_auxiliary_mm"]:.3f} mm; phần tủ mặt đứng {g["front_furniture_width_mm"]:.3f} mm, lệch {g["unexplained_front_mm"]:.3f} mm. Khung nguồn {g["front_width_mm"]:.3f} mm giữ riêng.')
    for p in modules:
        ev=p['plan_component_evidence'];sections=ev['sections']
        if sections:
            nearest=min(sections,key=lambda s:abs(s['difference_mm']))
            if abs(nearest['difference_mm'])>TOL:
                child['warnings'].append(f'{p["name"]}: mặt cắt {nearest["view_id"]} sâu {nearest["depth_mm"]:.3f} mm, chênh {nearest["difference_mm"]:.3f} mm; giữ số đo mặt bằng và box tạm để kiểm tra.')
        else:child['warnings'].append(f'{p["name"]}: chưa có mặt cắt xác nhận chiều sâu này.')
    child['explanation'].extend(child['warnings'])
    return True
