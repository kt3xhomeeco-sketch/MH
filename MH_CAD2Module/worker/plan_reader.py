"""Plan-only entry: measured OY sweep and explicitly accepted exact feedback."""
from copy import deepcopy
import hashlib
import json
import math
import time

from geometry import union, TOL
from library import VERSION
from learning import valid_state, plan_event_offset
from materials import BOARD_MM
from oy_sweep import ENGINE, plates, bays
from plan_evidence import measure_plan
from stages import finish_plan
from cad_style import structural_rows

KINDS=('modules','trim_parts','panel_parts')


def raw_signature(outlines):
    points=[p for o in outlines for p in o.get('points',[])]
    if not points:return None
    base=[min(p[i] for p in points) for i in (0,1)]
    edges=sorted({tuple(sorted(tuple(round(p[i]-base[i],3) for i in (0,1)) for p in (a,b)))
                  for o in outlines for a,b in zip(o['points'],o['points'][1:])})
    return hashlib.sha256(json.dumps(['raw-plan-v1',edges],separators=(',',':')).encode()).hexdigest()


def replay_confirmed(product,root):
    """Only identical source edges; archived rule transfer/AI is never called."""
    source_signature=raw_signature(product.get('outlines',[]))
    if not source_signature:return False
    from exact_feedback_index import events_for
    for path,event in events_for(root,source_signature,raw_signature):
        try:
            if event.get('structural_signature')!=raw_signature(structural_rows(product.get('outlines',[]))):
                product['learning']=dict(mode='review',event=event['id'],
                    message='Kiểu nét kết cấu đã thay đổi; giữ kết quả hình học và yêu cầu xác nhận lại mẫu cũ.',
                    issues=[dict(code='structural_style_changed')])
                continue
            old=event['analysis']
            state=deepcopy(event['after'])
            if not valid_state(state):continue
            offset=plan_event_offset(event,product)
            if not isinstance(offset,list) or len(offset)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>2*max(BOARD_MM) for v in offset):continue
            old_frame=old.get('source_plan_envelope',old.get('envelope'))
            frame=product['source_plan_envelope']
            if old_frame and any(abs(state['bounds'][i]-(old_frame[i+2]-old_frame[i]))>2*max(BOARD_MM)+TOL for i in (0,1)):
                product.update(status='needs_review',error='Mẫu đúng cũ không khớp kích thước nguồn CAD; cần xác nhận lại box cho nguồn này.')
                product['learning']=dict(mode='review',event=event['id'],message=product['error'],
                    issues=[dict(code='source_binding_mismatch',message=product['error'])])
                return False
            if any(abs(p['origin'][2])>.1 for k in KINDS for p in state.get(k,[])):continue
            for kind in KINDS:
                for part in state.get(kind,[]):
                    part['origin'][2]=0;part['size'][2]=1600
                    part.pop('entity_id',None);part.pop('transform',None)
                    part['height_source']='provisional_default'
                    part['source_box']=[frame[i]+offset[i]+part['origin'][i] for i in (0,1)]+[
                        frame[i]+offset[i]+part['origin'][i]+part['size'][i] for i in (0,1)]
                    part['plan_box']=list(part['source_box'])
            state['bounds'][2]=1600
            product.update({k:state.get(k,[]) for k in (*KINDS,'bounds')},status='ready',manual_boxes=True,
                           height_source='provisional_default',default_height_mm=1600,
                           plan_origin_offset_mm=offset,plan_origin_basis='source_plan_envelope')
            product.pop('error',None);product.pop('envelope_preview',None)
            product['learning']=dict(mode='plan_exact',event=event['id'],message='Dùng box đã xác nhận cho đúng cùng các cạnh CAD; không gọi AI hoặc suy rộng mẫu.')
            product['experience']=dict(event=event['id'],file=str(path),stage='plan_only')
            return True
        except (OSError,ValueError,KeyError,TypeError,AttributeError):continue
    return False


def analyse_plan(product,outlines,root,notify=None,replay=True):
    notify=notify or (lambda *_:None)
    started=time.perf_counter();times={}
    product.update(plan_engine=ENGINE,parser_version=VERSION,outlines=outlines,check_outlines=[],
                   build_stages=dict(plan=True,elevation=False),
                   geometry_pipeline=dict(mode='plan_only',order=['parallel_stock_index','aligned_depth_groups','double_wall_seams'],default_height_mm=1600),
                   local_ai=dict(status='not_used',message='Nhận tấm từ cặp biên song song theo hướng ván; không gọi AI.'))
    product['signature']=raw_signature(outlines)
    product['learning']=dict(mode='geometry',message='Chia khoang từ cặp tấm khép kín theo hướng ván và đường tiếp giáp hai tấm 18 mm.')
    notify('read_edges',f"Đang quét {sum(len(o['points'])-1 for o in outlines)} cạnh: tra khoảng độ dày trong từng nhóm hướng…")
    t=time.perf_counter();rects,scan=plates(outlines);times['stock_scan']=time.perf_counter()-t
    product['rectangles']=[r.as_dict() for r in rects]
    frame=union([[*p,*p] for o in outlines for p in o['points']]) if outlines else None
    product['envelope']=frame;product['source_plan_envelope']=frame
    product['views']=[dict(id='P01',role='plan',title='Mặt bằng · quét OY theo độ dày ván',region=frame)] if frame else []
    try:
        notify('partition','Đang ghép đường cùng khoảng Y và xét đường giữa hai tấm 18 mm…')
        t=time.perf_counter();columns,details=bays(rects,outlines);times['depth_and_seams']=time.perf_counter()-t
        scan.update(details)
        if not columns:raise ValueError('Chưa có khoang khép bằng các tấm đúng độ dày và cùng khoảng Y; quét đủ biên tấm/mặt bằng.')
        # Disconnected plans are not silently combined into a single product.
        if any(b['box'][0]-a['box'][2]>2*max(BOARD_MM)+TOL or
               min(a['box'][3],b['box'][3])-max(a['box'][1],b['box'][1])<100 or
               min(abs(a['box'][1]-b['box'][1]),abs(a['box'][3]-b['box'][3]))>max(BOARD_MM)+TOL
               for a,b in zip(columns,columns[1:])):
            raise ValueError('Vùng quét có các cụm khoang rời nhau; quét riêng mặt bằng một sản phẩm.')
        t=time.perf_counter()
        product.update(finish_plan(dict(id='P01',rects=rects,outlines=outlines),columns,product['geometry_pipeline']))
        times['footprints_arcs_trims']=time.perf_counter()-t
        product['status']='ready'
        product['signature']=raw_signature(outlines)
        product['plan_origin_basis']='source_plan_envelope'
        product['plan_origin_offset_mm']=[round(product['envelope'][i]-product['source_plan_envelope'][i],6) for i in (0,1)]
    except ValueError as error:
        product.update(status='needs_review',error=str(error),modules=[])
    notify('measure_evidence','Đang ghi bằng chứng tấm, cung và các đường chia…')
    t=time.perf_counter();product['plan_evidence']=measure_plan(outlines);times['evidence']=time.perf_counter()-t
    from plan_depth import evidence as depth_evidence
    stock_depth=depth_evidence(outlines)
    if stock_depth:
        ps=stock_depth['panels']
        product['cabinet_plan_envelope']=[min(p['box_mm'][0] for p in ps),stock_depth['low_mm'],max(p['box_mm'][2] for p in ps),stock_depth['high_mm']]
    if product['plan_evidence'].get('envelope'):product['source_plan_envelope']=product['plan_evidence']['envelope']
    if product['status']=='ready':
        product['plan_origin_offset_mm']=[round(product['envelope'][i]-product['source_plan_envelope'][i],6) for i in (0,1)]
    t=time.perf_counter()
    source=product.get('cabinet_plan_envelope',product['source_plan_envelope'])
    partial=product['status']=='ready' and source and any(abs(product['bounds'][i]-(source[i+2]-source[i]))>72.15 for i in (0,1))
    if product['status']!='ready' or partial:
        from directional_layout import recover
        recover(product,outlines,product['plan_evidence'])
    times['directional_layout']=time.perf_counter()-t
    product['material_standards_mm']=list(BOARD_MM)
    product['geometry_pipeline']['oy_sweep']=scan
    product['explanation']=[
        'Truy tìm cặp biên theo khoảng độ dày chuẩn trong từng nhóm hướng OX/OY/xiên; kiểm tra khép hai đầu và chiều dài chung.',
        'Ưu tiên cạnh dài/cùng khoảng Y. Chuỗi 18–18 giữ hai tấm, xét mặt tiếp giáp ở giữa; tấm/nẹp đầu ngoài giữ riêng.',
        'Chiều cao tạm 1600 mm; chưa đọc mặt đứng. Bộ đọc này không gọi AI hoặc bộ chia cũ.']
    recovered=product['geometry_pipeline'].get('directional_layout')
    if recovered:
        product['views'][0]['title']='Mặt bằng · chia khoang theo hướng tấm'
        product['explanation'].append(f'Đã ghép {recovered["modules"]} module theo các hướng của tấm; giữ nẹp/thanh chung riêng và không lấp khoảng hở giữa các thùng.')
    if replay:
        notify('experience','Đang đối chiếu box đã xác nhận trên đúng cùng hình học CAD…')
        t=time.perf_counter();replay_confirmed(product,root);times['exact_feedback']=time.perf_counter()-t
    times['total_plan']=time.perf_counter()-started
    product['processing_times']={k:round(v,6) for k,v in times.items()}
    return product
