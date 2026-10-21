"""Measured SP envelope height, independent of proving module tier boundaries."""
from copy import deepcopy
import time

from geometry import TOL


def measure(child,data):
    poses=data.get('relations',{}).get('poses',{})
    plan=poses.get(child.get('plan_view_id'),{})
    candidate=next((v for v in child.get('view_analysis',{}).get('candidates',[])
                    if v['id']==child.get('plan_view_id')), {})
    exact={v['front_id'] for v in candidate.get('elevation_checks',[]) if v.get('exact_width')}
    supports=[]
    for view in data.get('views',{}).values():
        if view['role']!='elevation':continue
        pose=poses.get(view['id'],{})
        registered=plan.get('status')==pose.get('status')=='proven' and plan.get('root_id')==pose.get('root_id')
        if plan.get('status')==pose.get('status')=='proven' and not registered:continue
        if not registered and view['id'] not in exact:continue
        box=view['box'];rects=view['rects']
        # A cap alone is not a whole-height front. Walls/context outside stock
        # are never included merely because they enlarge the transported CAD.
        if not any(r.h>max(100,4*r.w) for r in rects):continue
        low=min(r.y0 for r in rects)-box[1];high=max(r.y1 for r in rects)-box[1]
        if high-low<100 or high-low<.5*(box[3]-box[1]):continue
        supports.append(dict(view_id=view['id'],view_box=box,
            registration=deepcopy(pose) if registered else dict(status='exact_plan_width'),
            panels=[dict(box=r.box(),handle=r.handle) for r in rects],
            low_mm=round(low,6),high_mm=round(high,6)))
    if not supports:return dict(status='pending',issue='Chưa có mặt đứng cùng SP với cặp tấm ván đo được đủ chiều cao.')
    heights=[s['view_box'][3]-s['view_box'][1] for s in supports]
    if max(heights)-min(heights)>TOL:
        return dict(status='pending',issue='Các mặt đứng liên kết chưa thống nhất mốc đáy/chiều cao; giữ 1600 mm để kiểm tra.')
    low=min(s['low_mm'] for s in supports);high=max(s['high_mm'] for s in supports)
    if low<-TOL or not 100<high-low<100000:
        return dict(status='pending',issue='Cao độ tấm ván của SP vượt phạm vi dựng hợp lệ.')
    return dict(status='measured',basis='linked_front_stock_envelope',source_signature=data.get('source_signature'),
        plan_view_id=child.get('plan_view_id'),low_mm=low,high_mm=high,supports=supports,
        scope='product_envelope_only',module_tiers_measured=False)


def apply(child,data):
    started=time.perf_counter()
    parts=[p for k in ('modules','trim_parts','panel_parts') for p in child.get(k,[])]
    pending=[p for p in parts if p.get('height_source','provisional_default')=='provisional_default']
    if not pending:return
    proof=measure(child,data);child['product_height']=proof
    if proof['status']!='measured':
        child['height_pending']=True
        return
    low,high=proof['low_mm'],proof['high_mm']
    # Do not stretch unresolved extras through tiers whose Z is already known.
    # A whole-SP fallback is only suitable when all parts are still plan boxes.
    if len(pending)!=len(parts):
        proof.update(status='pending',issue='Đã có tầng module đo riêng; phần phụ còn cần cao độ riêng để tránh chồng khối.')
        child['height_pending']=True
        return
    for part in pending:
        part['origin'][2]=low;part['size'][2]=round(high-low,6)
        part.update(height_source='product_elevation_bounds',elevation_pending=True,
            elevation_evidence=dict(basis=proof['basis'],source_signature=proof['source_signature'],low_mm=low,high_mm=high))
        for key in ('carcass_origin','carcass_size'):part.pop(key,None)
    child.update(height_source='product_elevation_bounds',height_pending=False)
    child['bounds'][2]=high
    child.pop('default_height_mm',None)
    child['geometry_pipeline'].pop('default_height_mm',None)
    if child.get('envelope_preview'):child['envelope_preview']['height_provisional']=False
    message=f'Cao độ SP đo từ cặp tấm ván trên mặt đứng: Z{low:g}..{high:g} mm, cao {high-low:g} mm; chưa xác nhận cách chia tầng module.'
    for key in ('explanation','warnings'):
        child[key]=[s for s in child.get(key,[]) if '1600' not in s]
    child.setdefault('explanation',[]).append(message)
    child.setdefault('processing_times',{})['product_height']=round(time.perf_counter()-started,6)
