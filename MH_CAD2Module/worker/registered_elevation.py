"""Strict geometric correspondence when imported CAD lost its cut text.

Each bay needs its own matching wall endpoints/caps and independent front checks;
an unlocated section alone can never assign heights to every bay.
"""
from copy import deepcopy
import json
import time

from geometry import TOL,near,covers,union,overlapping_modules
from materials import BOARD_MM
from parallel_index import ParallelIndex
from oy_sweep import plates


def cap_at(rects,level,x0,x1):
    caps=[r for r in rects if r.w>4*r.h and (near(r.y0,level) or near(r.y1,level))]
    groups={}
    for r in caps:groups.setdefault((round(r.y0,3),round(r.y1,3)),[]).append(r)
    return next((rs for rs in groups.values() if covers([(r.x0,r.x1) for r in rs],x0,x1)),None)


def front_profile(module,view,frame,confirm):
    base=view['box'];left=base[0]+module['source_box'][0]-frame[0];right=base[0]+module['source_box'][2]-frame[0]
    walls=[r for r in view['rects'] if r.h>max(100,4*r.w)]
    ls=[r for r in walls if near(r.x0,left)];rs=[r for r in walls if near(r.x1,right)]
    pairs={}
    for a in ls:
        for b in rs:
            if near(a.y0,b.y0) and near(a.y1,b.y1):pairs[round(a.y0,3),round(a.y1,3)]=(a,b)
    if not pairs:raise ValueError('Mặt đứng chưa có cặp vách đo được trùng hai mép khoang.')
    rows=sorted((a.y0,a.y1,a,b) for a,b in pairs.values())
    for lower,upper in zip(rows,rows[1:]):
        if not near(lower[1],upper[0]):raise ValueError('Cặp vách có khoảng hở/chồng tầng: chưa ghép duy nhất.')
        level=upper[0]-base[1]
        if not any(near(level,v) for v in confirm.get('module_joint_levels_mm',[])):
            raise ValueError(f'Vách gặp tại Z{level:g} nhưng chưa xác nhận đó là ghép thùng; giữ chiều cao tạm.')
    output=[]
    for lo,hi,a,b in rows:
        caps=[cap_at(view['rects'],z,a.x1,b.x0) for z in (lo,hi)]
        if not all(caps):raise ValueError('Đầu vách chưa có tấm ngang khép đủ chiều rộng khoang.')
        output.append(dict(low_mm=round(lo-base[1],6),high_mm=round(hi-base[1],6),front_walls=[a.box(),b.box()],
                           front_caps=[[r.box() for r in group] for group in caps]))
    return output


def section_caps(section,profile,depth):
    base=section['box'][1];rects=section['rects'];result=[]
    for row in profile:
        found=[]
        for value in (row['low_mm'],row['high_mm']):
            candidates=[r for r in rects if r.w>=depth-2*max(BOARD_MM)-TOL and r.h<=max(BOARD_MM)+TOL
                        and (near(r.y0-base,value) or near(r.y1-base,value))]
            if not candidates:raise ValueError('Mặt cắt chưa có cặp biên tấm ngang tại cao độ vách của khoang.')
            found.append(max(candidates,key=lambda r:r.w).box())
        result.append(found)
    return result


def section_orientation(section,child,lo,hi):
    box=section['box']
    rows=[dict(o,points=[[p[1]-box[1],box[0]-p[0]] for p in o['points']]) for o in section['outlines']]
    rects,_=plates(rows)
    front=min(b.get('core_box',b['box'])[1] for b in child['geometry_pipeline']['vertical']['columns'])-child['envelope'][1]
    candidates=[r for r in rects if near(r.h,front) and near(r.x0,lo) and near(r.x1,hi)]
    bands={(round(-r.y1,3),round(-r.y0,3)) for r in candidates}
    if len(bands)!=1:raise ValueError('Chưa đối chiếu duy nhất biên cánh để biết trước/sau của mặt cắt.')
    low,high=next(iter(bands));width=box[2]-box[0]
    if near(high,width):return True
    if near(low,0):return False
    raise ValueError('Cánh đo được không nằm ở biên trước/sau mặt cắt.')


def confirmed_trim_box(parts,confirm):
    """A source-scoped user representation, not a measured solid envelope."""
    size=confirm.get('top_trim_box_mm')
    if size is None:return parts
    if len(parts)!=2 or not isinstance(size,list) or len(size)!=2 or not confirm.get('event_id'):
        raise ValueError('Nẹp một khối cần hai tấm chữ L và xác nhận kích thước theo nguồn.')
    a,b=sorted(parts,key=lambda p:p['origin'][1])
    depth,height=size
    if not all(isinstance(v,(int,float)) and v>0 for v in size) or not (
        near(a['origin'][1]+a['size'][1],b['origin'][1]) and near(a['origin'][2],b['origin'][2]) and
        a['size'][1]<b['size'][1] and a['size'][2]>b['size'][2] and
        near(depth,max(p['size'][1] for p in parts)) and near(height,max(p['size'][2] for p in parts))):
        raise ValueError('Khối nẹp xác nhận không khớp hai nhánh chữ L đo trên mặt cắt.')
    part=deepcopy(a);evidence=part['elevation_evidence']
    evidence.update(kind='top_trim_proxy',confirmed_box_mm=size,confirmation_event=confirm['event_id'],
                    section_parts=[dict(box=p['elevation_evidence']['section_panel'],
                        stock_mm=p['elevation_evidence']['stock_mm'],
                        parallel_proof=p['elevation_evidence']['parallel_proof']) for p in (a,b)],
                    high_mm=a['origin'][2]+height)
    part.update(name='Nẹp nóc chữ L · khối theo xác nhận',rule='confirmed-section-top-trim-box-v1',
        explanation='Một khối nẹp theo kích thước người dùng xác nhận; hai tấm chữ L đo từ mặt cắt được giữ làm bằng chứng, không báo đây là khung bao đo được.')
    part['size'][1:]=size;part['source_box'][3]=part['source_box'][1]+depth
    part['handles']=sorted(set(h for p in parts for h in p['handles']))
    part.pop('stock_thickness_mm',None)
    return [part]


def complete(child,data,root):
    if not child.get('scan_capture') or data['markers'] or child.get('envelope_preview') or child.get('plan_levels_partitioned'):return False
    if any(m.get('plan_profile') for m in child['modules']):return False
    if child['scan_capture'].get('excluded_symbol_groups'):return False
    signature=data['source_signature'];confirm={}
    path=root/'source_context'/f'{signature}.json'
    if path.is_file():
        value=json.loads(path.read_text(encoding='utf8'))
        if value.get('source_signature')==signature:confirm=value
    started=time.perf_counter();frame=child['source_plan_envelope'];width=frame[2]-frame[0]
    fronts=[v for v in data['views'].values() if near(v['box'][2]-v['box'][0],width)]
    if len(fronts)<2:return False
    matches=[];reasons=[]
    for front in fronts:
        peers=[v for v in fronts if near(v['height_mm'],front['height_mm'])]
        if len(peers)<2:continue
        try:
            profiles=[front_profile(m,front,frame,confirm) for m in child['modules']]
            depth={round(m['size'][1],3) for m in child['modules']}
            if len(depth)!=1:raise ValueError('Các khoang sâu khác nhau chưa có mặt cắt định vị riêng.')
            depth=next(iter(depth))
            sections=[s for s in data['views'].values() if s not in fronts and near(s['width_mm'],depth) and near(s['height_mm'],front['height_mm'])]
            for section in sections:
                try:
                    caps=[section_caps(section,profile,depth) for profile in profiles]
                    low=min(r['low_mm'] for p in profiles for r in p);high=max(r['high_mm'] for p in profiles for r in p)
                    reverse=section_orientation(section,child,low,high)
                    matches.append((front,peers,section,profiles,caps,reverse))
                except ValueError as error:reasons.append(str(error))
        except ValueError as error:reasons.append(str(error))
    if len(matches)!=1:
        child['geometry_pipeline']['horizontal']['issues'].append('Ghép hình học: '+('nhiều phương án cùng hợp lệ.' if len(matches)>1 else '; '.join(dict.fromkeys(reasons)) or 'thiếu mặt cắt khớp chiều sâu/chiều cao.'))
        return False
    front,peers,section,profiles,caps,reverse=matches[0]
    common=dict(basis='registered_parallel_panels',source_signature=signature,front_id=front['id'],front_box=front['box'],
                section_id=section['id'],section_box=section['box'],front_checks=[dict(id=v['id'],box=v['box']) for v in peers],
                reversed_depth=reverse)
    output=[];records=[]
    for module,profile,proofs in zip(child['modules'],profiles,caps):
        for index,(row,cap) in enumerate(zip(profile,proofs)):
            part=deepcopy(module);lo,hi=row['low_mm'],row['high_mm']
            evidence=dict(common,**row,kind='module',section_caps=cap,plan_frame=frame)
            part.update(id=f'{module["id"]}-Z{index+1:02}',name=f'{module.get("name",module["id"])} · Tầng {index+1}',
                height_source='registered_view_geometry',elevation_pending=False,rule='registered-section-panels-v1',elevation_evidence=evidence,
                explanation=f'Z{lo:g}..{hi:g} mm: cặp vách tại đúng khoang, kiểm tra tấm song song trên mặt cắt và hai mặt đứng; không đọc DIM.')
            part['origin'][2]=round(lo,6);part['size'][2]=round(hi-lo,6)
            output.append(part)
        records.append(dict(plan_module_id=module['id'],intervals_mm=[[r['low_mm'],r['high_mm']] for r in profile],links=[],registration=common))
    trims=deepcopy(child.get('trim_parts',[]))
    for trim in trims:
        boxes=[]
        for view in peers:
            vb=view['box'];x0=vb[0]+trim['source_box'][0]-frame[0];x1=x0+trim['size'][0]
            options=[r for r in view['rects'] if near(r.x0,x0) and near(r.x1,x1) and r.h>100]
            if not options:break
            panel=max(options,key=lambda r:r.h);boxes.append(dict(box=panel.box(),view_box=vb,view_id=view['id']))
        spans={(round(v['box'][1]-v['view_box'][1],3),round(v['box'][3]-v['view_box'][1],3)) for v in boxes}
        if len(boxes)==len(peers) and len(spans)==1:
            lo,hi=next(iter(spans));trim['origin'][2]=lo;trim['size'][2]=hi-lo
            trim.update(height_source='registered_view_geometry',elevation_pending=False,
                elevation_evidence=dict(common,kind='end_panel',low_mm=lo,high_mm=hi,front_panels=boxes,plan_frame=frame))
    top=[];top_boxes=[];top_pending=False
    if confirm.get('top_trim') is True:
        low=max(r['high_mm'] for p in profiles for r in p);sb=section['box'];depth=sb[2]-sb[0]
        index=ParallelIndex([(a,b,o['handle']) for o in section['outlines'] for a,b in zip(o['points'],o['points'][1:])])
        peer_indices={v['id']:ParallelIndex([(a,z,o['handle']) for o in v['outlines'] for a,z in zip(o['points'],o['points'][1:])]) for v in peers}
        for panel in index.panels(allow_short=True):
            b=union([[*p,*p] for side in panel['boundary'] for p in side])
            if b[1]<sb[1]+low-TOL or not near(min(b[2]-b[0],b[3]-b[1]),panel['measured_mm']):continue
            lo,hi=b[1]-sb[1],b[3]-sb[1]
            # Both fronts must contain the exact fascia band, never a DIM label.
            if not all(all(peer_indices[v['id']].covers(
                    [v['box'][0],v['box'][1]+h],[v['box'][2],v['box'][1]+h]) for h in (low,hi)) for v in peers):
                # A horizontal return shares the bottom of the fascia; its own
                # height is measured in section and need not cross the front.
                if not near(hi-lo,panel['stock_mm']):continue
            y=depth-(b[2]-sb[0]) if reverse else b[0]-sb[0]
            part=dict(id=f'TOP{len(top)+1:02}',name='Nẹp nóc · tấm đo từ mặt cắt',origin=[0,round(y,6),round(lo,6)],
                size=[width,round(b[2]-b[0],6),round(hi-lo,6)],source_box=[frame[0],frame[1]+y,frame[2],frame[1]+y+b[2]-b[0]],
                handles=panel['handles'],role='plan_auxiliary',solid_proxy=True,stock_thickness_mm=panel['stock_mm'],
                height_source='registered_view_geometry',elevation_pending=False,rule='measured-section-top-trim-v1',
                elevation_evidence=dict(common,kind='top_trim',low_mm=lo,high_mm=hi,section_panel=b,stock_mm=panel['stock_mm'],
                                        parallel_proof=panel['evidence'],plan_frame=frame),
                explanation='Nẹp nóc: độ dày từ cặp song song khép hai đầu trên mặt cắt; chiều dài đối chiếu hai mặt đứng, phân loại nẹp do người dùng xác nhận.')
            if not any(overlapping_modules([part,q]) for q in top):top.append(part);top_boxes.append(b)
        for o in section['outlines']:
            for a,b in zip(o['points'],o['points'][1:]):
                if max(a[1],b[1])<=sb[1]+low+TOL:continue
                dim=0 if near(a[1],b[1]) else 1 if near(a[0],b[0]) else None
                if dim is None:top_pending=True;continue
                other=1-dim;lo,hi=sorted((a[dim],b[dim]))
                if dim==1:lo=max(lo,sb[1]+low)
                spans=[(q[dim],q[dim+2]) for q in top_boxes if q[other]-TOL<=a[other]<=q[other+2]+TOL]
                if not covers(spans,lo,hi):top_pending=True
    elif not isinstance(confirm.get('top_trim'),bool):
        top_pending=any(v['box'][3]-v['box'][1]>max(r['high_mm'] for p in profiles for r in p)+TOL for v in peers)
    # Apply only after the measured L has passed complete section coverage.
    if top and not top_pending:top=confirmed_trim_box(top,confirm)
    parts=output+trims+top
    if overlapping_modules(parts):raise ValueError('Ghép hình học tạo khối chồng nhau; giữ khối tạm.')
    pending=top_pending or any(p.get('elevation_pending') for p in parts)
    child.update(modules=output,trim_parts=trims+top,elevation_pending=pending,
        height_source='mixed_provisional' if pending else 'registered_view_geometry',bounds=child['bounds'][:2]+[max(p['origin'][2]+p['size'][2] for p in parts)])
    child.pop('default_height_mm',None)
    child['warnings']=[v for v in child.get('warnings',[]) if 'mặt cắt đứng đúng dấu cắt' not in v]
    child['geometry_pipeline']['horizontal']=dict(engine='registered-section-panels-v1',status='partial' if pending else 'measured',
        modules=records,issues=['Nẹp/vùng trên nóc chưa được xác nhận hoặc chưa khép đủ cặp tấm; không tự lấp khối.'] if top_pending else ['Phần phụ còn thiếu chiều cao đo được.'] if pending else [],seconds=round(time.perf_counter()-started,6),
        source_confirmation=confirm.get('event_id'),registration=common)
    child['explanation']=['Ghép hình học khi mã cắt bị mất: từng khoang có cặp vách khép, đối chiếu tấm song song trên mặt cắt và hai mặt đứng.',
        'Chiều cao/cao độ lấy từ nét thật; các xác nhận về ghép thùng/nẹp chỉ dùng cho đúng hình học nguồn này.']
    child['scan_capture']['registration']='registered_parallel_panels'
    child['scan_capture']['issues']=['Không đọc được mã cắt; đã ghép duy nhất bằng hình học và xác nhận nguồn.']
    return True
