"""Place full source views in their own front family, retaining cut evidence."""
from geometry import near
from views import title_role
from cad_datums import measure,front_at


def register(entries,product,base,selected):
    from cad_views import front_kind,depth_direction
    summaries={v['id']:v for v in product['view_analysis']['candidates']}
    markers=product.get('cad_reference_markers',{})
    from view_relations import build,depth_link,edge
    rows_by_id={v['id']:r for v,r in entries}
    relations=product.get('view_relations') or build(summaries,rows_by_id)
    poses=relations['poses']
    datums={}
    def datum(view,rows):
        if view['id'] not in datums:
            datums[view['id']]=measure(rows,base)
            if datums[view['id']]:view['cabinet_datum']=datums[view['id']]
        return datums[view['id']]
    plans=[(e,r) for e,r in entries if summaries.get(e['id'],{}).get('role')=='plan' or e is selected]
    families={}
    for e,rows in sorted(plans,key=lambda p:p[0]['box_mm'][0]):
        key=summaries[e['id']].get('reference_family')
        families.setdefault(key,(e,rows))
    if not families:return
    root=selected['box_mm'];first_seed=next(iter(families.values()))[0]
    first_datum=datum(*next(iter(families.values())))
    first_y=first_datum['box_mm'][1] if first_datum else first_seed['box_mm'][1]
    cursor=first_seed['box_mm'][0];shifts={}
    for key,(seed,seed_rows) in families.items():
        measured=datum(seed,seed_rows);b=seed['box_mm']
        shifts[key]=[cursor-b[0],first_y-(measured['box_mm'][1] if measured else b[1])]
        cursor+=b[2]-b[0]+1000
    selected_key=summaries[selected['id']].get('reference_family');anchor_shift=shifts[selected_key][:]
    for shift in shifts.values():
        shift[0]-=anchor_shift[0];shift[1]-=anchor_shift[1]
    fronts=[]
    for view,body in entries:
        s=summaries.get(view['id'],{});key=s.get('reference_family')
        if key not in families:continue
        seed,plan_rows=families[key];pb=seed['box_mm'];b=view['box_mm'];shift=shifts[key]
        view['reference_family']=key
        datum(view,body)
        proof=poses.get(view['id'],{})
        view['axis_registration']={'W':proof} if proof else {}
        dx=proof['offset_mm'] if proof.get('status')=='proven' and proof['root_id']==seed['id'] else None
        if view in [p[0] for p in plans]:
            source=datum(seed,plan_rows);target=datum(view,body)
            dy=(source['box_mm'][1]-target['box_mm'][1]) if source and target else pb[1]-b[1]
            view.update(plane='XY',role='plan',xy_offset_mm=[round(shift[0]+(dx if dx is not None else pb[0]-b[0]),6),round(shift[1]+dy,6)],
                        alignment='source_plan' if view is selected else 'registered_plan_level',anchor_box_mm=b)
            view['y_alignment_basis']='cabinet_min_y' if source and target else 'provisional_source_min_y'
            if not source or not target:view['registration_issue']='Chưa đủ cặp ván kín để căn Y; tạm dùng Y thấp nhất của nguồn.'
            if view is not seed and dx is None:view['registration_issue']='Chưa khớp cặp ván theo X; tạm căn mép bản CAD đầy đủ.'
            continue
        caption=title_role(s.get('title',''))
        named=s.get('role')=='elevation' or (caption in ('front_check','front_open') and b[3]-b[1]>250)
        peers=[e for e,_ in entries if e is not view and e is not seed and near(e['box_mm'][2]-e['box_mm'][0],pb[2]-pb[0]) and near(e['box_mm'][3]-e['box_mm'][1],b[3]-b[1])]
        sides=[e for e,_ in entries if e is not view and near(e['box_mm'][2]-e['box_mm'][0],pb[3]-pb[1]) and near(e['box_mm'][3]-e['box_mm'][1],b[3]-b[1])]
        if not named and not (caption not in ('section','section_vertical') and peers and sides and near(b[2]-b[0],pb[2]-pb[0])):continue
        view.update(plane='XZ',role=front_kind(s,body,b),anchor_box_mm=b,
                    x_offset_mm=round(shift[0]+(dx if dx is not None else pb[0]-b[0]),6),
                    alignment='matched_front' if dx is not None else 'front_pending_alignment')
        fronts.append(view)
    for view,_ in entries:
        if view.get('role'):continue
        b=view['box_mm'];s=summaries.get(view['id'],{})
        parents=[f for f in fronts if f.get('reference_family')==s.get('reference_family') and
                 s.get('title')==summaries.get(f['id'],{}).get('title') and
                 all(b[i]>=f['box_mm'][i]-.15 and b[i+2]<=f['box_mm'][i+2]+.15 for i in (0,1))]
        if len(parents)==1:
            parent=parents[0]
            view.update({k:parent[k] for k in ('plane','role','anchor_box_mm','x_offset_mm','alignment','reference_family')})
            view['parent_view_id']=parent['id']
    # Captions are local to complete drawing components; source order determines
    # family/order, while cut strokes determine section position inside the box.
    for view,body in sorted(entries,key=lambda p:p[0]['box_mm'][0]):
        if view.get('role') in ('plan','front_open','front_check','front_unspecified'):continue
        s=summaries.get(view['id'],{});key=s.get('reference_family')
        if key not in families:continue
        seed,plan_rows=families[key];pb=seed['box_mm'];b=view['box_mm'];shift=shifts[key]
        local_fronts=[f for f in fronts if f.get('reference_family')==key]
        named=s.get('role')=='section_vertical'
        matched=near(b[2]-b[0],pb[3]-pb[1]) and any(near(b[3]-b[1],f['box_mm'][3]-f['box_mm'][1]) for f in local_fronts)
        if not named and not matched:continue
        cuts=[]
        for cut in s.get('section_links',[]):
            front=next((f for f in local_fronts if f['id']==cut['front_id']),None)
            marker=markers.get(cut['marker_handle'],{});line=marker.get('cut_line')
            if front is not None and cut['axis']=='vertical' and line and abs(line[0][0]-line[1][0])<.15:
                cuts.append((front,marker,cut))
        anchor=list(b);reverse=None;direction={}
        if cuts:
            front,marker,cut=min(cuts,key=lambda p:abs(s['box'][0]-summaries[p[0]['id']]['box'][0]))
            line=marker['cut_line'];x=sum(p[0] for p in line)/2-base[0]+front['x_offset_mm']
            anchor[1]=front['anchor_box_mm'][1]
            position=dict(basis='cut_marker',front_id=front['id'],marker_handle=cut['marker_handle'],cut_line=line,
                          source_origin_mm=base,front_x_offset_mm=front['x_offset_mm'])
            if marker.get('view_direction') in ([1,0],[-1,0]) and marker.get('arrow_heads'):
                reverse=marker['view_direction'][0]>0
                direction=dict(direction_basis='symbol_arrows',view_direction=marker['view_direction'],arrow_heads=marker['arrow_heads'])
        else:
            edge='left' if b[0]<seed['box_mm'][0] else 'right'
            measured=datum(seed,plan_rows);edge_box=measured['box_mm'] if measured else pb
            placed=[edge_box[i]+shift[i%2] for i in range(4)]
            x=placed[0 if edge=='left' else 2];position=dict(basis='box_edge',box_mm=placed,edge=edge)
        plan_datum=datum(seed,plan_rows);side_datum=datum(view,body)
        if reverse is None:
            reverse=depth_direction(plan_datum,side_datum)
            direction['direction_basis']='panel_geometry' if reverse is not None else 'unresolved'
        if plan_datum and side_datum:
            anchor[0],anchor[2]=side_datum['box_mm'][0],side_datum['box_mm'][2]
            y,basis=front_at(plan_datum,x-shift[0]);y+=shift[1]
            view['depth_alignment']=dict(basis=basis,plan_id=seed['id'],plan_y_mm=round(y,6),
                                         plan_x_mm=round(x-shift[0],6),plan_shift_mm=[round(v,6) for v in shift],side_box_mm=side_datum['box_mm'])
            if basis=='cabinet_min_y':view['registration_issue']='Chưa có cặp ván bao qua vị trí cắt X này; tạm căn theo Y thấp nhất của tủ, cần kiểm tra độ lùi.'
        else:
            y=pb[1]+shift[1]
            view['depth_alignment']=dict(basis='provisional_source_min_y',plan_id=seed['id'],plan_y_mm=round(y,6))
            view['registration_issue']='Chưa đủ cặp ván kín để loại nét bối cảnh khỏi mốc Y; tạm căn Y thấp nhất của nguồn.'
        view.update(plane='YZ',role='section_vertical',alignment='section_inspection',anchor_box_mm=anchor,
                    reversed_depth=reverse is True,display_x_mm=round(x,6),display_y_mm=round(y,6),datum_proven=bool(cuts) or matched,
                    section_position=position,**direction)
        if cuts:
            front,_,_=cuts[0]
            if front.get('axis_registration',{}).get('W',{}).get('status')!='proven':
                view['registration_issue']=(view.get('registration_issue','')+' X dấu cắt còn tạm vì mặt đứng chưa khớp chuỗi ngang với mặt bằng.').strip()
            height=edge(front['id'],view['id'],rows_by_id,'H',1,1,target_slice=sum(p[0] for p in position['cut_line'])/2)
            view.setdefault('axis_registration',{})['H']=height
            # Keep partial-height source frames provisional unless their measured
            # H chain confirms the floor; a title is never a floor measurement.
            if height['status']=='proven':
                anchor[1]=front['anchor_box_mm'][1]-height['offset_mm']
            else:view['registration_issue']=(view.get('registration_issue','')+' Chuỗi cao độ H chưa xác nhận mốc sàn; giữ mốc khung nguồn tạm.').strip()
            view['datum_proven']=height['status']=='proven'
            candidates=[]
            for plan,plan_body in plans:
                if plan.get('reference_family')!=key:continue
                plan_x=x-plan['xy_offset_mm'][0]+base[0]
                level=product.get('cad_reference_levels',{}).get(plan['id'],{})
                side_z=anchor[1]+base[1]+level['level_mm'] if level.get('status')=='measured' else None
                link=depth_link(plan['id'],view['id'],rows_by_id,plan_x,side_z,reverse)
                if link['status']=='proven':candidates.append((plan,link))
            view.setdefault('axis_registration',{})['D']=dict(status='provisional',reason='Chưa có chuỗi chiều sâu duy nhất tại vị trí/cao độ cắt.')
            if candidates:
                placed=[c['offset_mm']+p['xy_offset_mm'][1]+(-anchor[2] if reverse else anchor[0])-base[1]+(-base[0] if reverse else base[0]) for p,c in candidates]
                if all(near(v,placed[0]) for v in placed):
                    plan,link=candidates[0]
                    view['axis_registration']['D']=dict(link,plan_id=plan['id'],placement_y_mm=round(placed[0],6))
                    # Existing local datum placement remains visible when D chains
                    # disagree; only a unique cross-view result may replace it.
                    view['display_y_mm']=round(placed[0],6)
                    view['depth_alignment'].update(basis='stock_axis_chain',plan_id=plan['id'],plan_y_mm=view['display_y_mm'],
                        plan_shift_mm=plan['xy_offset_mm'],plan_x_mm=round(x-plan['xy_offset_mm'][0],6))
                else:view['axis_registration']['D']=dict(status='conflict',reason='Các cao độ/mặt bằng cho vị trí chiều sâu khác nhau; giữ mốc tạm để kiểm tra.')
        if reverse is None:view['registration_issue']=(view.get('registration_issue','')+' Chưa xác định được hướng nhìn; giữ hướng tạm để kiểm tra.').strip()
