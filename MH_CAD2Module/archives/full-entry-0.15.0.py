    memory = ExperienceLibrary(root)
    from local_ai import Assistant
    assistant = Assistant(request, memory)
    if request.get("action") == "geometry":
        geometry = request["geometry"]
        report_progress(request,root,'read_edges',f"Đang ghép biên tấm từ {len(geometry['lines'])} cạnh CAD…")
        automatic=request.get('automatic_scan',not bool(request.get('code')))
        code=request.get('code') or f'SCAN-{str(uuid.uuid4()).upper()}'
        rows = [(tuple(row["a"]), tuple(row["b"]), row["handle"], row.get("layer", "")) for row in geometry["lines"]]
        rects = line_rectangles(rows,min_length=100 if stages['elevation'] else 0)
        product = {"code": code, "name": request.get("name", "Vùng quét CAD" if automatic else ""),
                   'automatic_scan':automatic,"source_hash": geometry["hash"], "parser_version": VERSION,
                   "source_path": geometry.get("model_path") or "Nét CAD được chọn trong SketchUp",
                   "outlines": [{"handle": h, "layer": layer, "points": [a,b]} for a,b,h,layer in rows],
                   "rectangles": [r.as_dict() for r in rects], "regions": [union([r.box() for r in rects])] if rects else []}
        if geometry.get('source_watch'):product['source_watch']=geometry['source_watch']
        report_progress(request,root,'views','Đang xác định mặt bằng và đo các tấm/cung…')
        views=infer_views(rects,product['outlines'])
        if not stages['elevation'] and not any(v['role']=='plan' for v in views):
            views=infer_plan_views(rects,product['outlines'],allow_unresolved=True)
        prepare_views(product,views,stages)
        report_progress(request,root,'partition','Đang chia module từ hình học CAD…')
        try:
            product.update((recognise_ordered if stages['elevation'] else recognise_plan)(views,product['geometry_pipeline']))
            product["status"] = "ready"
            report_progress(request,root,'experience','Đang đối chiếu kinh nghiệm đã xác nhận…')
            replay_experience(product, root, memory)
        except ValueError as error:
            product.update(status="needs_review", error=str(error), modules=[])
            if not stages['elevation']:
                product['envelope']=selected_envelope(geometry)
                product['source_plan_envelope']=list(product['envelope'])
            product["signature"] = geometry_signature(rects, outlines=product['outlines'])
            replay_experience(product, root, memory)
        assistant.apply(product)
        report_progress(request,root,'prepare_result','Đã phân tích xong; đang chuyển kết quả về SketchUp để kiểm tra và dựng…')
        envelope_preview(product,geometry)
        try:
            source_placement(product,geometry)
        except ValueError as error:
            product.update(status='needs_review',error=str(error),modules=[])
        return {"analyses": [{"revision": {"hash": geometry["hash"], "original_path": product["source_path"]},
                              "products": [product], "diagnostics": []}], "errors": []}
    analyses, errors = [], []
    for source in request.get("sources", []):
        try:
            analysis = analyse_source(source, root, request.get("converter", ""),request.get('targets'),stages,request.get('plan_choices'))
            for product in analysis["products"]:
                if product.get('view_analysis',{}).get('selected_view_id'):
                    replay_experience(product, root, memory)
                    assistant.apply(product)
                    from plan_reference import prepare_reference
                    prepare_reference(product)
            analyses.append(analysis)
        except Exception as error:
            errors.append({"source": source, "error": str(error)})
    if not request.get("sources"):
        raise ValueError("Chưa cấu hình nguồn DWG/DXF trong bảng Quản lý.")
    return {"analyses": analyses, "errors": errors}
