"""Select a product plan using stock geometry, elevation and local cut callouts.

Titles supply layout/links, never measured sizes. Ambiguous views stay reviewable.
This path deliberately does not invoke the archived rectangle/AI recognisers.
"""
from collections import Counter
import re

from geometry import Rect, TOL, inside, near, rectangle, union, gap_boxes
from plan_profiles import arc_runs, arc_bounds
from oy_sweep import plates, bays
from plan_reader import raw_signature
from views import split_views, title_role, normalise
from plan_scope_geometry import panel_outline, stock_envelope, orthogonal_plan, elevation_band_widths

PLAN_SIZE_TOLERANCE = .15


def close_size(actual,reference):
    return abs(actual-reference)<=reference*PLAN_SIZE_TOLERANCE+TOL


def plan_width_check(view,fronts,cuts):
    """A component must match the whole SP, not borrow its parent's cut title."""
    linked={c['front_id'] for c in cuts if c['axis']=='horizontal'}
    references=[f for f in fronts if f is not view and (not linked or f['id'] in linked)]
    pairs=[(f,box[2]-box[0]) for f in references for box in (f['features']['box'],f['features']['core_box'])]
    if view['features']['orthogonal_plan']:
        pairs += [(f,width) for f in references for width in f['features']['elevation_band_widths_mm']]
    if not pairs:return None
    width=view['features']['width_mm']
    front,reference=min(pairs,key=lambda pair:abs(width-pair[1])/pair[1])
    difference=abs(width-reference)/reference
    from view_signatures import align
    chain=align(front['outlines'],view['outlines'])
    stretched=chain.get('changed_gap') if chain['status']=='proven' else None
    return dict(front_id=front['id'],plan_width_mm=width,front_width_mm=round(reference,3),
                difference_percent=round(difference*100,3),tolerance_percent=20,
                passed=close_size(width,reference) or (difference<=.20 and chain['status']=='proven') or bool(stretched),detail_scale=difference>=.5 and not stretched,
                size_only_tolerance_percent=15,
                changed_gap=stretched)


def check_peer_plans(summaries):
    """Two independent cuts support a size family; fragments cannot outvote it."""
    plans=[s for s in summaries if s['role']=='plan']
    if not any(p.get('product_size_check') for p in plans):
        # Without an elevation, repeated independent plans provide width evidence.
        cohorts=[]
        for seed in plans:
            group=[p for p in plans if close_size(p['width_mm'],seed['width_mm']) and close_size(seed['width_mm'],p['width_mm'])]
            support=len({p['id'].split('.')[0] for p in group})
            if support>=2:cohorts.append((support,seed,group))
        strongest=[c for c in cohorts if c[0]==max((c[0] for c in cohorts),default=0)]
        families={tuple(sorted(p['id'] for p in group)) for _,_,group in strongest}
        if len(families)==1:
            _,reference,group=strongest[0]
            for plan in plans:
                if plan in group:continue
                delta=abs(plan['width_mm']-reference['width_mm'])/reference['width_mm']
                plan['peer_size_check']=dict(reference_view_id=reference['id'],width_mm=plan['width_mm'],
                                             reference_width_mm=reference['width_mm'],difference_percent=round(delta*100,3),
                                             tolerance_percent=20,passed=False)
                plan['role']='detail_section' if delta>=.5 else 'plan_candidate'
                plan['can_confirm']=delta<.5
                plan['reasons'].append(f'Chiều rộng {plan["width_mm"]} mm lệch {delta:.1%} so với nhóm mặt bằng {reference["width_mm"]} mm; không tự dựng như mặt bằng toàn SP.')
        plans=[s for s in plans if s['role']=='plan']
    for plan in plans:
        if any(c['axis']=='horizontal' and c.get('cut_line') and c.get('dimension_check',{}).get('exact_width') for c in plan['section_links']):continue
        if plan.get('orthogonal_plan'):continue # Overall L span is not cabinet depth.
        peers=[p for p in plans if not p.get('orthogonal_plan') and close_size(p['width_mm'],plan['width_mm']) and close_size(plan['width_mm'],p['width_mm'])]
        cohorts=[]
        for seed in peers:
            group=[p for p in peers if close_size(p['height_mm'],seed['height_mm']) and close_size(seed['height_mm'],p['height_mm'])]
            # Separate connected pieces inheriting one title are not independent plans.
            support=len({p['id'].split('.')[0] for p in group})
            if support>=2:cohorts.append((support,seed,group))
        if not cohorts:continue
        best=max(c[0] for c in cohorts)
        strongest=[c for c in cohorts if c[0]==best]
        if any(plan in group for _,_,group in strongest):continue
        families={tuple(sorted(p['id'] for p in group)) for _,_,group in strongest}
        if len(families)!=1:continue # Equal, distinct depth families remain ambiguous.
        reference=strongest[0][1]
        delta=abs(plan['height_mm']-reference['height_mm'])/reference['height_mm']
        plan['peer_size_check']=dict(reference_view_id=reference['id'],depth_mm=plan['height_mm'],
                                     reference_depth_mm=reference['height_mm'],difference_percent=round(delta*100,3),
                                     tolerance_percent=20,passed=False)
        plan['role']='detail_section' if delta>=.5 else 'plan_candidate'
        plan['can_confirm']=delta<.5
        plan['reasons'].append(f'Chiều sâu {plan["height_mm"]} mm lệch {delta:.1%} so với nhóm mặt bằng {reference["height_mm"]} mm; không tự dựng như mặt bằng toàn SP.')


def bounds(outlines):
    return union([[*p,*p] for row in outlines for p in row['points']]) if outlines else None


def context_word(row):
    text=normalise(' '.join([row.get('layer',''),*row.get('block_names',[])]))
    text=re.sub(r'[_\-]+',' ',text)
    if re.search(r'\b(TUONG|WALL|MASONRY|CONCRETE)\b',text):return 'wall'
    if re.search(r'\b(CAU THANG|STAIR\w*)\b',text):return 'stairs'
    return None


def components(outlines):
    """Spatial sweep over outline bounds; distant drawings cannot become one SP."""
    boxes=[bounds([o]) for o in outlines];parents=list(range(len(outlines)))
    def root(i):
        while parents[i]!=i:
            parents[i]=parents[parents[i]];i=parents[i]
        return i
    active=[]
    for i in sorted(range(len(boxes)),key=lambda i:boxes[i][0]):
        a=boxes[i];active=[j for j in active if boxes[j][2]+60>=a[0]]
        for j in active:
            if max(gap_boxes(a,boxes[j]))<=60:parents[root(i)]=root(j)
        active.append(i)
    groups={}
    for i,o in enumerate(outlines):groups.setdefault(root(i),[]).append(o)
    return sorted(groups.values(),key=lambda rows:(bounds(rows)[0],bounds(rows)[1]))


def stair_evidence(outlines,stock):
    if len(stock)>=2:return False
    lines=[];diagonal=False
    for row in outlines:
        for a,b in zip(row['points'],row['points'][1:]):
            dx,dy=abs(b[0]-a[0]),abs(b[1]-a[1])
            if dx>300 and dy<TOL:lines.append((round(min(a[0],b[0]),1),round(max(a[0],b[0]),1),round(a[1],1)))
            if dx>100 and dy>100:diagonal=True
    spans={}
    for x0,x1,y in lines:spans.setdefault((x0,x1),set()).add(y)
    repeated=any(sum(100<=b-a<=400 for a,b in zip(sorted(ys),sorted(ys)[1:]))>=4 for ys in spans.values())
    return repeated and (diagonal or any(context_word(o)=='stairs' for o in outlines))


def strip_context(outlines):
    kept=[];removed=[]
    for row in outlines:
        r=rectangle(row['points'],row['handle'],row.get('layer',''))
        kind=context_word(row)
        thick=r and 72<min(r.w,r.h)<=600 and max(r.w,r.h)>1200
        # A layer/name alone must not erase an actual 18 mm cabinet panel.
        if kind=='wall' and thick:removed.append(dict(handle=row['handle'],kind='wall',reason='Closed thick strip and wall layer/block'))
        else:kept.append(row)
    return kept,removed


def features(view):
    rows=view['outlines'];box=bounds(rows);rects,scan=plates(rows)
    w,h=box[2]-box[0],box[3]-box[1]
    words=Counter(context_word(o) for o in rows)
    thick=[r for o in rows if (r:=rectangle(o['points'],o['handle'],o.get('layer','')))
           and 72<min(r.w,r.h)<=600 and max(r.w,r.h)>1200]
    stairs=stair_evidence(rows,rects)
    wall=thick and not rects and (words['wall'] or any((a.w>a.h)!=(b.w>b.h) for a in thick for b in thick))
    kind='stairs' if stairs else 'wall' if wall else 'furniture' if len(rects)>=2 else 'unknown'
    columns=[]
    if kind=='furniture':
        try:columns,_=bays(rects,rows)
        except ValueError:pass
    supports=[r for r in rects if r.h>max(100,3*r.w)]
    profiles=[bounds([o]) for o in rows if panel_outline(o) and (lambda b:b[3]-b[1]>max(100,3*(b[2]-b[0])))(bounds([o]))]
    core=union([r.box() for r in supports]+profiles) if len(supports)+len(profiles)>=2 else box
    turned=orthogonal_plan(rows,rects,columns,box) if view.get('declared_role') not in ('front_open','front_check') else None
    return dict(box=box,width_mm=round(w,3),height_mm=round(h,3),kind=kind,
                stock_count=len(rects),columns=columns,rects=rects,
                core_box=core,orthogonal_plan=turned,elevation_band_widths_mm=elevation_band_widths(rects,w),layer_hints={k:v for k,v in words.items() if k},
                stock_checks=scan['spacing_checks'] if 'spacing_checks' in scan else None)


def view_slots(product,annotations):
    rows=product['outlines'];row_ids={id(row):i for i,row in enumerate(rows)}
    proxies=[Rect(*bounds([o]),o['handle'],o.get('layer','')) for o in rows]
    slots=split_views(product['regions'],annotations,proxies,rows,classify_geometry=False)
    for region_index,region in enumerate(product['regions']):
        titled=any(a['kind']=='view_title' and inside([*a['point'],*a['point']],region) for a in annotations)
        if titled:continue
        body=[o for o in rows if inside(bounds([o]),region)]
        if body:slots.append(dict(id=f'V{len(slots)+1:02}',title='',role='unknown',region=region,outlines=body,untitled_sheet=True,sheet_index=region_index+1))
    result=[];removed=[]
    for slot in slots:
        borders=[o for o in slot['outlines'] if any(all(abs(a-b)<=TOL for a,b in zip(bounds([o]),region)) for region in product['regions'])
                 and ('VIEN IN' in [normalise(n) for n in o.get('block_names',[])] or normalise(o.get('layer',''))=='DEFPOINTS')]
        removed.extend(dict(handle=o['handle'],kind='sheet_border',reason='Printing frame matching the product sheet') for o in borders)
        clean,rejected=strip_context([o for o in slot['outlines'] if o not in borders]);removed.extend(rejected)
        for index,group in enumerate(components(clean)):
            v={k:value for k,value in slot.items() if k not in ('rects','outlines','section_markers')}
            v.update(id=f"{slot['id']}.{index+1}",outlines=group,declared_role=title_role(slot['title']))
            box=bounds(group)
            sheet=next((r for r in product['regions'] if inside(box,r)),None)
            if sheet:
                v['sheet_box']=sheet
                captions=[a for a in annotations if a['kind']=='view_title' and inside([*a['point'],*a['point']],sheet)
                          and a['point'][1]<=box[1]+TOL and box[0]<=a['center_x']<=box[2]]
                if captions:
                    caption=min(captions,key=lambda a:box[1]-a['point'][1])
                    v.update(title=caption['text'],title_handle=caption['handle'],declared_role=title_role(caption['text']))
            v['source_handles']=[o['handle'] for o in group]
            v['source_row_indices']=[row_ids[id(o)] for o in group]
            v['features']=features(v)
            f=v['features']
            # Architectural outlines may touch a cabinet. Anchor a prospective
            # plan on closed stock sides, then retain nearby doors/trims/curves.
            core=stock_envelope(group,f['rects'])
            if v['declared_role'] not in ('front_open','front_check') and core:
                for arc in arc_runs(group):
                    if any(inside([*arc[end],*arc[end]],[core[0]-72,core[1]-72,core[2]+72,core[3]+72]) for end in ('start','end')):
                        core=union([core,arc_bounds(arc)])
                crop=[core[0]-72,core[1]-72,core[2]+72,core[3]+72]
                body=[o for o in group if inside(bounds([o]),crop)]
                if body and len(body)<len(group):
                    removed.extend(dict(handle=o['handle'],kind='outside_product',reason='Outside measured stock/curve envelope') for o in group if o not in body)
                    v['outlines']=body;v['features']=features(v)
            v['signature']=raw_signature(v['outlines'])
            if v.get('untitled_sheet') and v['features']['orthogonal_plan']:
                v['title']=f'Mặt bằng chữ L · Tờ {v["sheet_index"]}'
            result.append(v)
    # A complete polyline can cross the caption-row border while still touching
    # exactly one drawing (SP24's two L returns). Keep it with that full reference.
    owned={i for v in result for i in v['source_row_indices']}
    rejected={r['handle'] for r in removed if r['kind'] in ('wall','sheet_border')}
    for i,row in enumerate(rows):
        if i in owned or row['handle'] in rejected:continue
        box=bounds([row]);matches=[v for v in result if v.get('sheet_box') and inside(box,v['sheet_box']) and max(gap_boxes(box,v['features']['box']))<=TOL]
        if len(matches)!=1:continue
        matches[0]['source_row_indices'].append(i);matches[0]['source_handles'].append(row['handle'])
    return result,removed


def markers_for(front,annotations,regions):
    box=front['features']['box'];margin=72
    expanded=[box[0]-margin,box[1]-margin,box[2]+margin,box[3]+margin]
    return [a for a in annotations if a['kind']=='section_marker'
            and any(inside([*a['point'],*a['point']],region) for region in regions)
            and inside([*a['point'],*a['point']],expanded)]


def align_width(plan,front,relaxed=False):
    from view_signatures import align
    p,f=plan['features'],front['features']
    proof=align(front['outlines'],plan['outlines'])
    # Both exterior and measured long-panel envelopes are retained (plinth/trim).
    pairs=[(pb,fb) for pb in (p['box'],p['core_box']) for fb in (f['box'],f['core_box'])]
    if relaxed:pairs.sort(key=lambda pair:abs((pair[0][2]-pair[0][0])-(pair[1][2]-pair[1][0])))
    for pb,fb in pairs:
            pw,fw=pb[2]-pb[0],fb[2]-fb[0]
            if not relaxed and abs(pw-fw)>72+TOL:continue
            proven=proof['status']=='proven'
            matches=proof.get('matched_pairs',0)*2 if proven else 0
            shift=proof['offset_mm']+pb[0]-fb[0] if proven else None
            if not relaxed and not near(pw,fw) and not proven:continue
            return dict(front_id=front['id'],plan_width_mm=round(pw,3),front_width_mm=round(fw,3),
                        width_difference_mm=round(pw-fw,3),aligned_panel_faces=matches,
                        exact_width=near(pw,fw),passed=near(pw,fw),panel_offset_mm=shift,basis='measured_geometry',axis_check=proof)
    return None


def choose_product_plan(product,annotations,choice=None,multiple=False):
    views,removed=view_slots(product,annotations)
    fronts=[v for v in views if v['features']['kind'] not in ('wall','stairs')
            and v['features']['height_mm']>250 and v['features']['width_mm']>200
            and v['declared_role'] in ('front_open','front_check')]
    if not fronts:
        fronts=[v for v in views if v['features']['kind']=='furniture' and not v['features']['orthogonal_plan'] and v['features']['height_mm']>1200
                and v['features']['width_mm']>v['features']['height_mm']*.35]
    fronts += [v for v in views if v not in fronts and v.get('untitled_sheet') and v['features']['kind']=='furniture'
               and not v['features']['orthogonal_plan'] and v['features']['height_mm']>1200 and v['features']['width_mm']>200]
    from view_families import assign,link_unique_vertical
    assign(views,fronts)
    front_markers={f['id']:markers_for(f,annotations,product['regions']) for f in fronts}
    link_unique_vertical(views,fronts,front_markers)
    summaries=[];eligible=[];by_id={v['id']:v for v in views}
    for view in views:
        f=view['features'];role='unknown';reason=[];links=[];cut_links=[]
        numbers=set(re.findall(r'\b([A-Z0-9]+)\s*[-–]\s*\1\b',normalise(view['title'])))
        for front in fronts:
            if front is view:continue
            if front.get('reference_family')!=view.get('reference_family'):continue
            for marker in front_markers[front['id']]:
                if numbers.intersection(marker.get('numbers',[])):
                    cut_links.append(dict(front_id=front['id'],marker_handle=marker['handle'],axis=marker['axis'],
                                          point=marker['point'],cut_line=marker.get('cut_line')))
            link=align_width(view,front,relaxed=multiple)
            if link:links.append(link)
        axes={m['axis'] for m in cut_links}
        for cut in cut_links:
            front=by_id[cut['front_id']]['features']
            if cut['axis']=='horizontal':
                cut['dimension_check']=next((link for link in links if link['front_id']==cut['front_id']),None)
            elif cut['axis']=='vertical':
                full=union([[*p,*p] for i in view['source_row_indices'] for p in product['outlines'][i]['points']])
                delta=abs((full[3]-full[1])-front['height_mm'])
                cut['dimension_check']=dict(section_height_mm=f['height_mm'],front_height_mm=front['height_mm'],
                                            difference_mm=round(delta,3),passed=delta<=max(72,front['height_mm']*.20)+TOL)
        if multiple and axes=={'vertical'}:
            # A local name match is still only a proposal: duplicated markers
            # or incompatible height must not force a section classification.
            valid=[c for c in cut_links if c.get('dimension_check',{}).get('passed')]
            if len(valid)!=1:
                reason.append('Dấu cắt đứng trùng/mâu thuẫn chiều cao; chưa xác nhận loại mặt từ tên.')
                cut_links=[];axes=set()
            else:cut_links=valid
        has_bays=bool(f['columns']);blocked=False
        plausible_plan=has_bays and 100<=f['height_mm']<=1200
        if f['orthogonal_plan']:plausible_plan=True
        if multiple and axes=={'horizontal'}:
            # A horizontal cut can expose a large L plan. The direction comes
            # from the actual marker, and closed stock validates the drawing.
            plausible_plan=f['width_mm']>.1 and .1<f['height_mm'] and (f['height_mm']<=1200 or bool(f['orthogonal_plan']) or f['stock_count']>=2)
        if f['kind'] in ('wall','stairs'):
            role=f['kind'];blocked=True;reason.append('Hình học bối cảnh kiến trúc, không có bằng chứng khoang ván.')
        elif view in fronts:
            role='elevation';blocked=True;reason.append('Mặt đứng: hình học ván và bố trí/caption mặt đứng.')
        elif axes=={'vertical'}:
            role='section_vertical';blocked=True
            heights=[front['features']['height_mm'] for front in fronts if any(c['front_id']==front['id'] for c in cut_links)]
            reason.append('Mã cắt liên kết với đường cắt dọc trên mặt đứng.')
            reason.append('Chiều cao đối chiếu: '+', '.join(str(round(h,3))+' mm' for h in heights)+'.')
        elif view['declared_role']=='section_vertical':
            role='section_vertical';blocked=True;reason.append('Mặt bên; chưa phải mặt bằng.')
        elif plausible_plan:
            if multiple and axes=={'horizontal'}:
                role='plan';reason.append('Đường cắt ngang trên mặt đứng; giữ kích thước CAD dù chiều rộng đối chiếu có thể lệch.')
            elif multiple and not axes and (view['declared_role']=='plan' or has_bays or f['orthogonal_plan']):
                role='plan';reason.append('Có hình học mặt bằng ván; dựng để kiểm tra, đối chiếu mặt đứng không chặn kích thước lệch.')
            elif axes=={'horizontal'} and any(c.get('dimension_check') for c in cut_links):
                role='plan';reason.append('Đường cắt ngang trên mặt đứng và chiều rộng hình học khớp.')
            elif not axes and view['declared_role'] in ('plan',None) and links:
                role='plan';reason.append('Mặt bằng có khoang ván và chiều rộng đối chiếu mặt đứng.')
            elif not fronts and not view['title'] and len(views)==1:
                role='plan';reason.append('Nguồn chỉ có một cụm mặt bằng ván; chưa có mặt đứng để đối chiếu.')
            else:
                role='plan_candidate';reason.append('Có khoang ván nhưng thiếu hoặc mâu thuẫn liên kết đường cắt/kích thước; cần xác nhận.')
        else:reason.append('Chưa đủ bằng chứng đây là mặt bằng sản phẩm.')
        size_check=plan_width_check(view,fronts,cut_links) if multiple and role=='plan' else None
        if multiple and role=='plan' and re.search(r'\b(MAT CAT TRICH|CAT CHI TIET|PHONG TO|DETAIL SECTION|ENLARGED)\b',normalise(view['title'])):
            role='detail_section';blocked=True
            reason.append('Caption chỉ mặt cắt trích/phóng to chi tiết; không phải mặt bằng toàn SP.')
        elif size_check and not size_check['passed']:
            role='detail_section' if size_check['detail_scale'] else 'plan_candidate'
            blocked=size_check['detail_scale']
            reason.append(f'Rộng {size_check["plan_width_mm"]} mm / mặt đứng {size_check["front_width_mm"]} mm, lệch {size_check["difference_percent"]}%; chưa có chuỗi nét khớp để xác nhận chênh lệch này là cùng bộ hình.')
        confirmed=False
        if choice and choice.get('view_id')==view['id']:
            if choice.get('signature')!=view['signature']:raise ValueError('Hình học vùng xác nhận đã đổi; đọc lại nguồn.')
            if blocked or not plausible_plan:raise ValueError('Vùng này không có mặt bằng khoang ván hợp lệ để dựng.')
            role='plan';confirmed=True;reason.append('Người dùng xác nhận vùng mặt bằng này sau khi xem đối chiếu.')
        summary=dict(id=view['id'],title=view['title'],role=role,kind=f['kind'],box=f['box'],
                     width_mm=f['width_mm'],height_mm=f['height_mm'],stock_count=f['stock_count'],
                     signature=view['signature'],reasons=reason,elevation_checks=links,section_links=cut_links,
                     can_confirm=plausible_plan and not blocked,confirmed=confirmed)
        summary.update({k:view[k] for k in ('reference_front_id','reference_family','sheet_box','reference_link_basis','local_reference_front_id','family_geometry_link') if k in view})
        if view.get('reference_link_basis'):reason.append('Bộ mặt đứng gần hình không có dấu cắt; ghép dấu cắt đứng duy nhất trên mặt đứng khác sau khi đối chiếu chiều cao và cặp ván.')
        if size_check:summary['product_size_check']=size_check
        if f['orthogonal_plan']:
            summary['orthogonal_plan']=f['orthogonal_plan']
            reason.append('Mặt bằng chữ L: hai nhánh khoang ván vuông góc, giữ toàn bộ nhánh OX/OY.')
        summaries.append(summary)
        if role=='plan':eligible.append(view)
    if multiple:
        check_peer_plans(summaries)
        eligible=[by_id[s['id']] for s in summaries if s['role']=='plan']
        # An explicit choice may override a modest mismatch, never a detail-scale one.
        if any(s['confirmed'] and not s['can_confirm'] for s in summaries):
            raise ValueError('Vùng xác nhận là mặt cắt trích khác kích thước quá lớn so với mặt bằng toàn SP.')
    if choice and not any(v['confirmed'] for v in summaries):raise ValueError('Không tìm thấy vùng đã xác nhận; đọc lại nguồn.')
    confirmed=[v for v in summaries if v['confirmed']]
    if confirmed:eligible=[by_id[confirmed[0]['id']]]
    # Multiple cuts at different heights may have the same edges/grouping. Keep
    # one only if their translated geometry is identical; otherwise ask explicitly.
    signatures={v['signature'] for v in eligible}
    selected=eligible[0] if eligible and len(signatures)==1 else None
    if product.get('shared_frame_codes') and not confirmed:selected=None
    distinct_fronts=any(abs(a['features']['width_mm']-b['features']['width_mm'])>72+TOL and
                        abs(a['features']['height_mm']-b['features']['height_mm'])>120
                        for a in fronts for b in fronts)
    if distinct_fronts and not confirmed:selected=None
    if multiple:
        selected=sorted(eligible,key=lambda v:v['features']['box'][0])
        if product.get('shared_frame_codes') and not confirmed:selected=[]
    analysis=dict(schema=1,candidates=summaries,excluded_context=removed,
                  selected_view_id=(selected[0]['id'] if multiple else selected['id']) if selected else None,
                  status='selected' if selected else 'needs_confirmation',
                  message='Đã chọn mặt bằng theo hình học và đối chiếu mặt đứng.' if selected else
                          'Chưa có một mặt bằng duy nhất: xem các vùng hình chiếu và xác nhận mặt bằng cần dựng.')
    if product.get('shared_frame_codes'):
        analysis['shared_frame_codes']=product['shared_frame_codes']
        if not selected:analysis['message']='Khung chứa nhiều mã SP ('+', '.join(product['shared_frame_codes'])+'); xác nhận đúng vùng của '+product['code']+'.'
    if distinct_fronts:
        analysis['multiple_elevation_sizes']=True
        analysis['scope_warning']='Có các mặt đứng khác kích thước; chọn một vùng không có nghĩa đã dựng đủ mọi cụm SP trong khung.'
        if not selected:analysis['message']=analysis['scope_warning']+' Xem vùng và xác nhận phần cần dựng.'
    if multiple:
        analysis['selected_view_ids']=[v['id'] for v in selected]
        if selected:analysis['message']=f'Đã tìm {len(selected)} mặt bằng theo tên, kích thước và chuỗi nét khớp; giữ số đo CAD, loại mặt cắt trích và ghi cảnh báo sai lệch.'
    if selected:
        first=selected[0] if multiple else selected
        chosen=next(s for s in summaries if s['id']==first['id'])
        analysis['basis']=chosen['reasons']
        analysis['selected_signature']=first['signature']
    product['view_analysis']=analysis
    product['view_previews']=[dict(id=v['id'],outlines=v['outlines'],source_handles=v['source_handles'],source_row_indices=v['source_row_indices']) for v in views]
    product['check_outlines']=[o for v in fronts for o in v['outlines']]
    return selected
