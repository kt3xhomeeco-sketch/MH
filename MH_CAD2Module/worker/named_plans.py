"""Independent measured plans, arranged for inspection without scaling CAD."""
from copy import deepcopy
import time

from plan_reader import analyse_plan, replay_confirmed
from plan_reference import prepare_reference
from stages import envelope_preview


def arrange(product):
    cursor=0
    children=product['plan_results']
    for index,child in enumerate(children):
        frame=child.get('source_plan_envelope',child['envelope'])
        base=child.get('plan_reference',{}).get('source_origin_mm',child['envelope'][:2])
        low=[min(0,frame[i]-base[i]) for i in (0,1)]
        high=[max(child['bounds'][i],frame[i+2]-base[i]) for i in (0,1)]
        span=high[0]-low[0]
        child['display_layout']=dict(index=index+1,count=len(children),offset_mm=[round(cursor-low[0],6),round(-low[1],6)],
                                     reserved_width_mm=round(span,6),gap_mm=1000,placement='inspection_row',height_pending=True)
        cursor+=span+1000
    total=round(cursor-1000,6)
    for child in children:child['display_layout']['total_width_mm']=total
    reserved=total
    for child in children:
        reference=child.get('plan_reference',{})
        if reference.get('scope')!='all_views':continue
        offset=child['display_layout']['offset_mm'][0]-total/2
        reserved=max(reserved,2*max(abs(offset+reference['placed_bounds_mm'][i]) for i in (0,3)))
    if reserved>total:
        for child in children:child['cad_reference_reserved_width_mm']=round(reserved,6)
    combined=any(c.get('build_stages',{}).get('elevation') for c in children)
    product['bounds']=[total,max(c['display_layout']['offset_mm'][1]+c['bounds'][1] for c in children),max(c['bounds'][2] for c in children)]
    product['status']='ready' # Per-plan unresolved partitioning retains its own orange preview/reason.
    product['explanation']=[f'{len(children)} mặt bằng được xếp cạnh nhau, khoảng trống 1000 mm; cao tạm 1600 mm.',
                            'Mặt đứng dùng đối chiếu/cảnh báo; số đo từng mặt bằng được giữ nguyên. Chưa đặt theo cao độ cắt thực.']
    warnings=[message for child in children for message in child.get('warnings',[])]
    product['warnings']=list(dict.fromkeys(warnings))
    product['modules']=[];product['trim_parts']=[];product['panel_parts']=[]
    product['build_stages']=dict(plan=True,elevation=combined)
    product['geometry_pipeline']=dict(mode='plan_and_elevation' if combined else 'plan_only',order=['multiple_named_plans'],default_height_mm=1600)
    if combined:
        for child in children:child['display_layout']['height_pending']=child.get('elevation_pending',True)
        product['elevation_pending']=any(c.get('elevation_pending',True) for c in children)
        product['height_source']='mixed_provisional' if product['elevation_pending'] else 'linked_vertical_section'
        product['height_pending']=any(c.get('height_pending',c.get('elevation_pending',True)) for c in children)
        if all(c.get('height_source')=='product_elevation_bounds' for c in children):product['height_source']='product_elevation_bounds'
        product['geometry_pipeline'].pop('default_height_mm',None)
        product['explanation']=[f'{len(children)} mặt bằng độc lập; chiều cao/chia tầng kiểm tra theo dấu cắt đứng. Khoảng trống 1000 mm giữa các mặt bằng.']
        if len(children)==1 and children[0].get('unified_partial_plan'):
            product['explanation']=list(children[0]['explanation'])
            product['height_source']='mixed_partial'


def analyse_named_plans(product,selected,root):
    view_analysis=deepcopy(product['view_analysis']);check=product['check_outlines']
    children=[]
    for view in selected:
        title=view['title'] or f'Mặt bằng {view["id"]}'
        child={k:deepcopy(product[k]) for k in ('code','name','source_hash','source_path','parser_version','automatic_scan','source_watch','annotation_watch','scan_capture','view_relations') if k in product}
        child['name']=f'{product.get("name",product["code"])} · {title}'
        child['plan_view_id']=view['id'];child['plan_title']=title
        analyse_plan(child,view['outlines'],root,replay=False)
        child['view_analysis']=deepcopy(view_analysis)
        child['view_analysis'].update(selected_view_id=view['id'],selected_view_ids=[view['id']])
        child['check_outlines']=check
        candidate=next(c for c in view_analysis['candidates'] if c['id']==view['id'])
        warnings=[]
        cuts=candidate['section_links']
        for cut in cuts:
            if candidate.get('product_size_check') and cut['front_id']!=candidate['product_size_check']['front_id']:continue
            measured=cut.get('dimension_check')
            if measured and cut['axis']=='horizontal' and not measured['exact_width']:
                warnings.append(f'{title}: mặt bằng rộng {measured["plan_width_mm"]} mm / mặt đứng {measured["front_width_mm"]} mm; giữ số đo CAD để kiểm tra.')
        if not cuts:warnings.append(f'{title}: nhận bằng hình học ván; chưa ghép được ký hiệu cắt. Dựng để kiểm tra.')
        child['warnings']=warnings;child['explanation']+=warnings
        if child['status']=='ready':
            source=child.get('cabinet_plan_envelope',child['source_plan_envelope']);actual=child['bounds']
            if any(abs(actual[i]-(source[i+2]-source[i]))>72.15 for i in (0,1)):
                child.update(status='needs_review',error='Chia khối chưa phủ đủ mặt bằng đo được; dựng khung bao để kiểm tra và sửa.')
        if child['status']!='ready':
            geometry=dict(plane='XY',lines=[dict(a=a,b=b,handle=o['handle'],layer=o.get('layer',''))
                            for o in view['outlines'] for a,b in zip(o['points'],o['points'][1:])])
            if not envelope_preview(child,geometry):continue
            child['placement']=dict(mode='label_plan',plane='XY',origin_mm=child['envelope'][:2],plane_offset_mm=0)
        prepare_reference(child)
        children.append(child)
    if not children:
        product.update(status='needs_review',error='Không có mặt bằng hữu hạn để dựng/kiểm tra.',modules=[])
        return
    # Keep the ordinary single-plan shape compatible with existing readers/history.
    if len(children)==1:
        temporary=dict(plan_results=children)
        arrange(temporary)
        product.update(children[0]);return
    product['plan_results']=children
    arrange(product)


def replay_named(product,root):
    for child in product.get('plan_results',[product]):
        started=time.perf_counter()
        # Combined processing already replayed XY before measuring Z. A final
        # refresh must not overwrite measured heights with the plan-only default.
        if not child.get('build_stages',{}).get('elevation'):replay_confirmed(child,root)
        prepare_reference(child)
        child['current_replay_seconds']=round(time.perf_counter()-started,6)
    if product.get('plan_results'):arrange(product)
    elif product.get('display_layout'):arrange(dict(plan_results=[product]))
