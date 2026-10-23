"""Section-first Z stage; plan footprints and the plan recognizer stay independent."""
from copy import deepcopy
import math
import re
import time

from geometry import TOL,near,covers,overlapping_modules
from views import normalise,title_role
from elevation_geometry import panels,extent,tiers,seam_check,marker_axis

ENGINE='section-first-v1'


def context(product,annotations):
    summaries={v['id']:v for v in product.get('view_analysis',{}).get('candidates',[])}
    views={}
    for preview in product.get('view_previews',[]):
        summary=summaries[preview['id']]
        if summary['role'] not in ('elevation','section_vertical'):continue
        rects,index=panels(preview['outlines'])
        box=extent(rects)
        if box:
            views[preview['id']]=dict(summary,rects=rects,measured_box=box,panel_index=index,outlines=preview['outlines'],
                declared_role=title_role(summary.get('title','')))
    from plan_reader import raw_signature
    from view_relations import build,source_rows
    relations=build(summaries,source_rows(product))
    product['view_relations']=relations
    for id,proof in relations['poses'].items():
        summaries[id]['width_registration']=proof
        summaries[id]['role_verification']=dict(status='supported' if proof['status']=='proven' else 'pending',
            reason='Tên mặt đề xuất vai trò; vị trí được đối chiếu bằng chuỗi cặp ván, không bằng kích thước bao đơn lẻ.')
    return dict(views=views,markers={a['handle']:a for a in annotations if a['kind']=='section_marker'},source_signature=raw_signature(product['outlines']),relations=relations)


def checks_for(front,views):
    f=front['box'];w,h=f[2]-f[0],f[3]-f[1]
    return [v for v in views.values() if v['role']=='elevation' and
            abs((v['box'][2]-v['box'][0])-w)<=72+TOL and
            abs((v['box'][3]-v['box'][1])-h)<=72+TOL]


def link_sections(child,data):
    views,markers=data['views'],data['markers'];candidate=next(
        (v for v in child.get('view_analysis',{}).get('candidates',[]) if v['id']==child.get('plan_view_id')),None)
    if not candidate:raise ValueError('Chưa có mặt bằng đã định vị để ghép mặt cắt đứng.')
    front_ids={c['front_id'] for c in candidate['section_links'] if c['axis']=='horizontal' and c.get('dimension_check')
               and marker_axis(markers.get(c['marker_handle'],{}))=='horizontal'}
    # Untitled plans may have geometric width checks, but never borrow a cut
    # from an unrelated front merely because its section name matches.
    if not front_ids:front_ids={c['front_id'] for c in candidate['elevation_checks'] if c.get('exact_width')}
    fronts=[views[i] for i in front_ids if i in views and views[i]['role']=='elevation']
    if not fronts:raise ValueError('Chưa liên kết được mặt bằng với đúng mặt đứng/dấu cắt.')
    result=[];stretched=False
    for front in fronts:
        fb=front['measured_box'];frame=child['source_plan_envelope']
        poses=data.get('relations',{}).get('poses',{})
        pp,fp=poses.get(candidate['id'],{}),poses.get(front['id'],{})
        registered=pp.get('status')==fp.get('status')=='proven' and pp['root_id']==fp['root_id']
        if any(e.get('changed_gap') for p in (pp,fp) for e in p.get('path',[])):
            stretched=True;continue # Association is supported; a non-rigid edit is not a measured cut position.
        if data.get('relations') and not registered:continue
        if not registered and abs((fb[2]-fb[0])-(frame[2]-frame[0]))>72+TOL:continue
        for section in views.values():
            if section['role']!='section_vertical':continue
            for cut in section['section_links']:
                if cut['front_id']!=front['id']:continue
                marker=markers.get(cut['marker_handle'])
                if not marker or marker_axis(marker)!='vertical':continue
                numbers=set(re.findall(r'\b([A-Z0-9]+)\s*[-–]\s*\1\b',normalise(section['title'])))
                if not numbers.intersection(marker.get('numbers',[])):continue
                sb=section['box'];datum=front['box']
                if abs((sb[3]-sb[1])-(datum[3]-datum[1]))>TOL:
                    # Different height could be a detail or a missing plinth.
                    # A title is not evidence to silently align its bottom.
                    continue
                x=sum(p[0] for p in marker['cut_line'])/2+(fp['offset_mm']-pp['offset_mm'] if registered else frame[0]-fb[0])
                levels=[]
                for horizontal in candidate['section_links']:
                    mark=markers.get(horizontal['marker_handle'],{})
                    if horizontal['front_id']==front['id'] and marker_axis(mark)=='horizontal':
                        levels.append(sum(p[1] for p in mark['cut_line'])/2-datum[1])
                result.append(dict(section=section,front=front,marker=marker,source_x=x,
                                   position_uncertainty_mm=TOL if registered else abs((fb[2]-fb[0])-(frame[2]-frame[0])),
                                   width_registration=dict(plan=pp,front=fp) if registered else None,
                                   z_base=sb[1],cut_levels=levels,checks=checks_for(front,views)))
    if not result and stretched:raise ValueError('Chuỗi nét xác nhận cùng bộ hình nhưng có một khoảng bị stretch; giữ số đo và khối mặt bằng tạm, chưa lấy vị trí dấu cắt này làm chứng cứ chiều cao.')
    if not result:raise ValueError('Chưa có mặt cắt đứng đúng dấu cắt và cùng cao độ/chiều cao để ghép; giữ khối mặt bằng tạm.')
    return result


def assign(child,links):
    assigned={m['id']:[] for m in child['modules']}
    for link in links:
        margin=link['position_uncertainty_mm']
        matches=[m for m in child['modules'] if m['source_box'][0]+margin-TOL<=link['source_x']<=m['source_box'][2]-margin+TOL]
        if len(matches)!=1:continue # The cut lies on a seam or two L branches: ambiguous.
        assigned[matches[0]['id']].append(link)
    return assigned


def module_tiers(module,links,child):
    candidates=[];records=[]
    if not links:raise ValueError(f'{module["id"]}: chưa có dấu cắt đứng nằm đúng trong khoang này.')
    for link in links:
        sec,front=link['section'],link['front'];fb=front['box']
        rows=tiers(sec['rects'],module['size'][1]);base=link['z_base']
        profile=[(round(r['low_mm']-base,6),round(r['high_mm']-base,6)) for r in rows]
        if any(not math.isfinite(lo+hi) or lo<-TOL or not .1<hi-lo<100000 for lo,hi in profile):
            raise ValueError('Cao độ/kích thước mặt cắt đứng vượt phạm vi dựng hợp lệ.')
        if child.get('plan_levels_partitioned'):
            levels=link['cut_levels']
            selected=[(lo,hi) for lo,hi in profile if any(lo+TOL<z<hi-TOL for z in levels)]
            if not levels or len(selected)!=1:
                raise ValueError('Nhiều mặt bằng: chưa xác định được cao độ dấu cắt ngang thuộc duy nhất tầng module nào.')
            profile=selected
        frame=child['source_plan_envelope'];x0=module['source_box'][0]-frame[0];x1=module['source_box'][2]-frame[0]
        check_rows=[]
        for view in link['checks']:
            box=view['box'];vx0,vx1=box[0]+x0,box[0]+x1
            heights=[r for r in view['rects'] if r.h>max(100,4*r.w) and min(r.x1,vx1)-max(r.x0,vx0)>TOL]
            floor=view['box'][1]
            if profile[0][0]<-TOL or profile[-1][1]>box[3]-floor+TOL:
                raise ValueError(f'{module["id"]}: chiều cao mặt cắt và mặt đứng không khớp tại khoang.')
            if view['declared_role']=='front_open':
                if not heights:raise ValueError('Mặt đứng bỏ cánh chưa có vách đo được tại khoang để kiểm tra.')
                if not child.get('plan_levels_partitioned') and any(not covers(profile,r.y0-floor,r.y1-floor) for r in heights):
                    raise ValueError('Mặt cắt chưa phủ đủ các tầng vách ở mặt đứng bỏ cánh.')
                for lo,hi in profile:
                    matching=[r for r in heights if near(r.y0-floor,lo) and near(r.y1-floor,hi)]
                    if not matching:raise ValueError('Đáy/nóc tầng mặt cắt chưa khớp đầu vách ở mặt đứng bỏ cánh.')
                boundaries={z for pair in profile for z in pair if TOL<z<box[3]-floor-TOL}
                for z in boundaries:seam_check(view['rects'],vx0,vx1,floor+z)
            check_rows.append(dict(view_id=view['id'],role=view['declared_role'] or 'elevation',passed=True))
        records.append(dict(section_id=sec['id'],front_id=front['id'],marker_handle=link['marker']['handle'],
            marker_point=link['marker']['point'],cut_line=link['marker']['cut_line'],source_x_mm=round(link['source_x'],6),
            position_uncertainty_mm=round(link['position_uncertainty_mm'],6),
            section_base_mm=base,front_base_mm=fb[1],plan_cut_levels_mm=link['cut_levels'],
            tiers=rows,checks=check_rows,panel_index=sec['panel_index']))
        candidates.append(profile)
    if any(len(p)!=len(candidates[0]) or any(abs(a-b)>TOL for pair,other in zip(p,candidates[0]) for a,b in zip(pair,other)) for p in candidates[1:]):
        raise ValueError(f'{module["id"]}: các mặt cắt đứng tại cùng khoang cho vị trí chia khác nhau.')
    return candidates[0],records


def apply(child,data):
    started=time.perf_counter();proof=dict(engine=ENGINE,status='provisional',modules=[],issues=[])
    child['build_stages']=dict(plan=True,elevation=True)
    child['plan_engine']=ENGINE
    child['geometry_pipeline'].update(mode='plan_and_elevation',order=['independent_plan_partition','linked_vertical_sections','elevation_checks'])
    child['geometry_pipeline']['horizontal']=proof
    original=deepcopy(child['modules'])
    try:
        if child.get('envelope_preview') or child.get('status')!='ready':raise ValueError('Mặt bằng chưa chia đủ khoang; chưa gán chiều cao cho khối bao.')
        links=link_sections(child,data);assigned=assign(child,links);output=[]
        for module in original:
            profile,records=module_tiers(module,assigned[module['id']],child)
            for level,(lo,hi) in enumerate(profile):
                part=deepcopy(module);part['id']=f'{module["id"]}-Z{level+1:02}'
                part.update(name=f'{module.get("name",module["id"])} · Tầng {level+1}',height_source='linked_vertical_section',rule=ENGINE,
                            elevation_evidence=dict(plan_module_id=module['id'],low_mm=lo,high_mm=hi,links=records),
                            explanation=f'Chiều cao {hi-lo:g} mm, Z={lo:g} mm từ mặt cắt đứng đúng vị trí; giữ biên mặt bằng và cánh trong module.')
                part['origin'][2]=lo;part['size'][2]=round(hi-lo,6)
                for key in ('carcass_origin','carcass_size'):part.pop(key,None)
                output.append(part)
            proof['modules'].append(dict(plan_module_id=module['id'],intervals_mm=profile,links=records))
        if overlapping_modules(output):raise ValueError('Các tầng module sau ghép mặt cắt đứng chồng nhau.')
        child['modules']=output
        # Trims have their own vertical evidence. Do not invent a full-height trim.
        for kind in ('trim_parts','panel_parts'):
            for part in child.get(kind,[]):
                part['height_source']='provisional_default';part['elevation_pending']=True
        pending=any(child.get(k) for k in ('trim_parts','panel_parts'))
        child['height_source']='mixed_provisional' if pending else 'linked_vertical_section'
        child['elevation_pending']=bool(pending)
        proof['status']='partial' if pending else 'measured'
        if pending:proof['issues'].append('Phần phụ chưa có mặt cắt riêng: vẫn cao tạm 1600 mm, chưa dùng học chiều cao.')
        child.pop('default_height_mm',None);child.pop('manual_boxes',None)
        child['learning']=dict(mode='geometry',message='Giữ cách chia mặt bằng; chiều cao/chia tầng lấy từ mặt cắt đứng liên kết, chưa suy rộng mẫu chiều cao.')
        child['explanation']=['Kết hợp Mặt bằng + Mặt đứng: biên XY giữ từ mặt bằng; vị trí chia Z ưu tiên mặt cắt đứng.',
                              'Dấu cắt xác định đúng khoang; mặt đứng bỏ cánh/có cánh dùng kiểm tra, cánh không tự tạo đường chia.']
    except ValueError as error:
        child['modules']=original;proof['modules']=[];proof['issues']=[str(error)]
        child['height_source']='provisional_default';child['elevation_pending']=True
        for key in ('modules','trim_parts','panel_parts'):
            for part in child.get(key,[]):part['elevation_pending']=True
        child.setdefault('warnings',[]).append(str(error))
        child.setdefault('explanation',[]).append('Mặt đứng chưa đủ bằng chứng: giữ khối mặt bằng cao tạm 1600 mm. '+str(error))
    child['bounds'][2]=max((p['origin'][2]+p['size'][2] for k in ('modules','trim_parts','panel_parts') for p in child.get(k,[])),default=1600)
    proof['seconds']=round(time.perf_counter()-started,6)
    child.setdefault('processing_times',{})['elevation']=proof['seconds']
    return child
