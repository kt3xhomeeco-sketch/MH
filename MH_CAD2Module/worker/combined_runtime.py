"""Composition entry only: independent plan XY stage followed by section Z."""
from stages import source_placement,envelope_preview
from named_plans import analyse_named_plans,replay_named,arrange
from elevation_builder import context,apply
from plan_reference import prepare_reference
from cad_levels import measure_levels,stack_offsets,inspection_levels


def analyse(product,selected,annotations,root):
    reference_rows=product['outlines'] if not product.get('scan_capture') else None
    reference_views=product.get('view_previews',[])
    data=context(product,annotations)
    levels=inspection_levels(measure_levels(product,data)) if reference_rows else {}
    analyse_named_plans(product,selected,root)
    if not product.get('modules') and not product.get('plan_results'):return
    replay_named(product,root) # Exact plan feedback supplies XY only, before Z is measured.
    for index,child in enumerate(product.get('plan_results',[product])):
        child['plan_levels_partitioned']=len(selected)>1
        apply(child,data)
        child.setdefault('processing_times',{})['view_registration']=data['relations']['seconds']
        if child.get('elevation_pending') and child.get('scan_capture'):
            from registered_elevation import complete
            try:complete(child,data,root)
            except (ValueError,OSError,KeyError,TypeError) as error:
                child.setdefault('warnings',[]).append('Ghép hình học chưa đủ bằng chứng: '+str(error))
        from product_height import apply as apply_product_height
        apply_product_height(child,data)
        from plan_depth import corroborate
        corroborate(child,data)
        if len(selected)==1:
            from plan_components import complete as complete_components
            complete_components(child,selected[0],data)
        # Preserve the entire SP's source once, regardless of Z recognition.
        # Direct scans already have these drawings at their original location.
        if reference_rows and index==0:
            child['cad_reference_outlines']=reference_rows
            child['cad_reference_views']=reference_views
            child['cad_reference_levels']=levels
            child['cad_reference_markers']=data['markers']
        if reference_rows:child['cad_reference_level']=levels.get(child['plan_view_id'],dict(status='pending',view_id=child['plan_view_id'],issue='Chưa xác định được cao độ.'))
        prepare_reference(child)
    if reference_rows:
        from partial_plan import complete as complete_partial_plan
        unified=complete_partial_plan(product,selected,data)
        children=product.get('plan_results',[product])
        stack_offsets(children)
        for child in children:
            if unified or 'cad_reference_offset_mm' in child:prepare_reference(child)
    if product.get('plan_results'):arrange(product)
    elif product.get('display_layout'):
        temporary=dict(plan_results=[product]);arrange(temporary)


def selected_geometry(request,root,notify):
    from drawing_scope import choose_product_plan
    from library import VERSION
    from scan_views import prepare
    import uuid
    geometry=request['geometry'];automatic=request.get('automatic_scan',not bool(request.get('code')))
    outlines,notes,regions,capture=prepare(geometry)
    product=dict(code=request.get('code') or f'SCAN-{str(uuid.uuid4()).upper()}',
        name=request.get('name','Vùng quét CAD' if automatic else ''),automatic_scan=automatic,
        source_hash=geometry['hash'],parser_version=VERSION,
        source_path=geometry.get('model_path') or 'Nét CAD được chọn trong SketchUp',
        outlines=outlines,regions=regions,scan_capture=capture)
    if geometry.get('source_watch'):product['source_watch']=geometry['source_watch']
    if geometry.get('annotation_watch'):product['annotation_watch']=geometry['annotation_watch']
    notify('views','Đang tách mặt bằng, mặt đứng và liên kết dấu cắt đứng…')
    selected=choose_product_plan(product,notes,multiple=True)
    if selected:
        analyse(product,selected,notes,root)
        for child in product.get('plan_results',[product]):
            source_placement(child,geometry)
            child.pop('display_layout',None) # Direct scans stay at each actual plan, never in a named inspection row.
            child.setdefault('warnings',[]).extend(capture['issues'])
            child.setdefault('processing_times',{})['scan_annotations']=capture['seconds']
    else:
        product.update(status='needs_review',error='Chưa có mặt bằng được xác định để phối hợp mặt đứng; quét riêng mặt bằng hoặc đủ các hình chiếu.',
                       modules=[],trim_parts=[],panel_parts=[],build_stages=dict(plan=True,elevation=False))
        # Keep an explicit correction target, never present an elevation envelope
        # as a recognised plan or infer measured heights from it.
        edges=[dict(a=a,b=b,handle=o['handle']) for o in outlines for a,b in zip(o['points'],o['points'][1:])]
        if envelope_preview(product,dict(geometry,lines=edges)):
            apply(product,dict(views={},markers={}))
            source_placement(product,geometry)
        product['build_stages']=dict(plan=True,elevation=True)
    for child in product.get('plan_results',[product]):
        child.setdefault('warnings',[]).extend(s for s in capture['issues'] if s not in child.get('warnings',[]))
        child.setdefault('processing_times',{})['scan_annotations']=capture['seconds']
    notify('prepare_result','Đã kiểm tra mặt cắt đứng theo vị trí khoang; giữ khối tạm ở nơi thiếu bằng chứng.')
    return dict(analyses=[dict(revision=dict(hash=geometry['hash'],original_path=product['source_path']),products=[product],diagnostics=[])],errors=[])
