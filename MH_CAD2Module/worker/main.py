"""MH CAD2Module worker: run with --request <json> --response <json>."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import time
import unicodedata
import uuid

import ezdxf
from ezdxf import bbox
from ezdxf.path import make_path
from ezdxf.entities import Text
from ezdxf.tools.text_size import text_size

from geometry import Rect, geometry_signature, inside, line_rectangles, overlapping_modules, rectangle, union
from learning import ExperienceLibrary
from library import VERSION, archive_dependencies, archive_source, atomic_json, dxf_for_revision, library_root
from views import section_symbol, title_role, split_views, infer_views, recognise_ordered
from stages import requested_stages, infer_plan_views, recognise_plan, source_placement, selected_envelope, envelope_preview
from plan_profiles import expand_plan_outlines
from plan_evidence import measure_plan

# Invalidate derived geometry without invalidating accepted source measurements.
RECOGNIZER_VERSION = 38


def fold(value):
    text = unicodedata.normalize("NFD", str(value)).replace("đ", "d").replace("Đ", "D")
    return " ".join("".join(c for c in text if not unicodedata.combining(c)).upper().split())


def product_code(value):
    matches = re.findall(r"\bSP\s*[-_]?\s*(\d+)\b", str(value), re.I)
    if matches:return ["SP" + m.zfill(2) for m in matches]
    text=str(value).strip()
    return [text.upper()] if re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*\d[A-Za-z0-9_-]*',text) else []


def declared_scale(doc):
    unit = doc.header.get("$INSUNITS", 0)
    factors = {1: 25.4, 2: 304.8, 4: 1.0, 5: 10.0, 6: 1000.0, 13: 0.001}
    if unit not in factors:
        raise ValueError(f"Đơn vị CAD chưa được hỗ trợ/khai báo (INSUNITS={unit}). Đặt đơn vị chính xác trước khi dựng.")
    return factors[unit]


def find_products(doc, scale):
    found = {}
    frames = set()
    for entity in doc.modelspace().query("INSERT"):
        attrs = {fold(a.dxf.tag): a.dxf.text for a in entity.attribs}
        explicit = [code for key in ('MASP','MA_SP','PRODUCT') for code in product_code(attrs.get(key,''))]
        fallback = [code for key in ('TENBV1','TENBV2') for code in product_code(attrs.get(key,''))]
        codes = list(dict.fromkeys(explicit or [c for c in fallback if c.startswith('SP')] or fallback))
        if not codes:
            continue
        name = next((attrs[k] for k in ("TENSP", "TEN_SP", "PRODUCT_NAME") if attrs.get(k)), "")
        if not name:
            name = next((attrs[k] for k in ("TENBV2", "TENBV1") if attrs.get(k) and not product_code(attrs[k])), "")
        try:
            extent = bbox.extents([entity])
            if not extent.has_data:
                continue
            limits = [extent.extmin.x * scale, extent.extmin.y * scale,
                      extent.extmax.x * scale, extent.extmax.y * scale]
        except Exception:
            continue
        frames.add(entity.dxf.handle)
        for code in codes:
            product = found.setdefault(code, {"code": code, "name": name, "regions": []})
            product["regions"].append(limits)
            if len(codes)>1:product['shared_frame_codes']=sorted(set(product.get('shared_frame_codes',[])+codes))
    return found, frames


def title_center(entity):
    # MTEXT width is a wrapping box, often spanning well beyond the visible title.
    if entity.dxftype()=='MTEXT':
        widths=[text_size(Text.new(dxfattribs={'text':line,'height':entity.dxf.char_height,
                 'style':entity.dxf.style},doc=entity.doc)).width for line in entity.plain_text().splitlines()]
        alignment=(entity.dxf.attachment_point-1)%3
        return entity.dxf.insert.x+max(widths,default=0)*(0.5,0,-0.5)[alignment]
    extent=bbox.extents([entity])
    return (extent.extmin.x+extent.extmax.x)/2


def outline_points(entity,scale):
    kind=entity.dxftype()
    if kind=='ARC':
        sweep=(entity.dxf.end_angle-entity.dxf.start_angle)%360
        count=max(4,math.ceil(sweep/5))+1
        # Sample exact circular coordinates, rather than a cubic-Bezier surrogate.
        return [[round(p.x*scale,3),round(p.y*scale,3)] for p in entity.vertices(entity.angles(count))]
    if kind in ('LWPOLYLINE','POLYLINE') and entity.has_arc:
        result=[]
        for segment in entity.virtual_entities():
            points=outline_points(segment,scale)
            result.extend(points[1:] if result and points and result[-1]==points[0] else points)
        return result
    path=make_path(entity)
    return [[round(p.x*scale,3),round(p.y*scale,3)] for p in path.flattening(max(0.1/scale,0.001))]


def read_geometry(doc, scale, excluded, annotations=None, min_panel_length=100, recover_panels=True):
    rects, outlines, lines, diagnostics = [], [], [], []

    def walk(entities, parent="", depth=0, block_names=(), inherited_layer='0', inherited_style=None):
        if depth > 12:
            diagnostics.append("Block lồng quá 12 cấp: đã bỏ qua phần sâu hơn.")
            return
        for entity in entities:
            if entity.dxf.get('invisible', 0):
                continue
            kind = entity.dxftype()
            handle = str(entity.dxf.get("handle", "") or parent)
            if kind in ('TEXT','MTEXT') and annotations is not None:
                text=entity.plain_text() if kind=='MTEXT' else entity.dxf.text
                if title_role(text):
                    annotations.append({'kind':'view_title','text':text,'handle':parent+'/'+handle,
                                        'point':[entity.dxf.insert.x*scale,entity.dxf.insert.y*scale],
                                        'center_x':title_center(entity)*scale})
            if kind in ("DIMENSION", "TEXT", "MTEXT", "ATTRIB", "ATTDEF", "HATCH", 'LEADER','MLEADER','MULTILEADER'):
                continue
            if kind == "INSERT":
                if handle in excluded:
                    continue
                if section_symbol(entity):
                    if annotations is not None:
                        extent=bbox.extents([entity])
                        attrs={a.dxf.tag:a.dxf.text.strip() for a in entity.attribs}
                        segments=[]
                        for line in entity.virtual_entities():
                            if line.dxftype()=='LINE' and not line.dxf.get('invisible',0):
                                p,q=line.dxf.start,line.dxf.end
                                segments.append(([p.x*scale,p.y*scale],[q.x*scale,q.y*scale]))
                        cut=max(segments,key=lambda pair:math.dist(*pair),default=None)
                        delta=[abs(cut[1][i]-cut[0][i]) for i in (0,1)] if cut else [extent.size.x,extent.size.y]
                        axis='horizontal' if delta[1]<max(.15,delta[0]*.001) else 'vertical' if delta[0]<max(.15,delta[1]*.001) else 'oblique'
                        local_axis=axis
                        if cut:
                            dx,dy=[cut[1][i]-cut[0][i] for i in (0,1)];angle=math.radians(entity.dxf.rotation)
                            ux=(dx*math.cos(angle)+dy*math.sin(angle))/entity.dxf.xscale
                            uy=(-dx*math.sin(angle)+dy*math.cos(angle))/entity.dxf.yscale
                            local_axis='horizontal' if abs(ux)>=abs(uy) else 'vertical'
                        annotations.append({'kind':'section_marker','handle':parent+'/'+handle,
                                            'point':[entity.dxf.insert.x*scale,entity.dxf.insert.y*scale],
                                            'numbers':[fold(attrs['4' if local_axis=='horizontal' else '1'])] if all(k in attrs for k in ('1','4')) else [],
                                            'numbers_all':sorted(set(attrs.values())), 'axis':axis,'cut_line':cut})
                        from section_arrows import visible_lines,arrow_evidence
                        annotations[-1].update(arrow_evidence(visible_lines(entity.virtual_entities(),scale),cut))
                    continue
                try:
                    layer=entity.dxf.layer if entity.dxf.layer!='0' else inherited_layer
                    from cad_style import entity_style
                    walk(entity.virtual_entities(), parent + "/" + handle, depth + 1,
                         block_names+(entity.dxf.name,),layer,entity_style(entity,layer,inherited_style))
                except Exception as error:
                    diagnostics.append(f"Block {handle}: {error}")
                continue
            identity = parent + "/" + handle
            layer = entity.dxf.layer if entity.dxf.layer!='0' else inherited_layer
            points = None
            if kind == "LWPOLYLINE" and entity.closed:
                if all(abs(p[4]) < 1e-8 for p in entity.get_points("xyseb")):
                    points = [(p.x * scale, p.y * scale) for p in entity.vertices_in_wcs()]
            elif kind == "POLYLINE" and entity.is_closed:
                if not any(abs(v.dxf.get("bulge", 0)) > 1e-8 for v in entity.vertices):
                    points = [(p.x * scale, p.y * scale) for p in entity.points_in_wcs()]
            elif kind == "LINE":
                a, b = entity.dxf.start, entity.dxf.end
                lines.append(((a.x * scale, a.y * scale), (b.x * scale, b.y * scale), identity, layer))
            if points:
                candidate = rectangle(points, identity, layer)
                if candidate:
                    rects.append(candidate)
            try:
                pts = outline_points(entity,scale)
                if len(pts) > 1:
                    from cad_style import entity_style
                    outlines.append({"handle": identity, "points": pts, "layer": layer,
                                     'block_names':list(block_names),'entity_type':kind,**entity_style(entity,layer,inherited_style)})
            except (TypeError, ValueError, AttributeError):
                pass

    walk(doc.modelspace())
    if not recover_panels:
        return rects, outlines, diagnostics
    if len(lines) <= 15000:
        rects.extend(line_rectangles(lines,min_length=min_panel_length))
    else:
        diagnostics.append("Quá nhiều LINE để ghép vòng trong lượt này; ưu tiên polyline kín.")
    return rects, outlines, diagnostics


def analyse_source(source, root, converter="", targets=None, stages=None, plan_choices=None):
    source_started=time.perf_counter()
    stages=stages or {'plan':True,'elevation':True}
    revision = archive_source(source, root)
    revision_seconds=time.perf_counter()-source_started
    saved_choices={}
    for path in (root/'view_choices'/revision['hash']).glob('SP*.json'):
        try:saved_choices[path.stem]=json.loads(path.read_text(encoding='utf8'))
        except (OSError,ValueError):continue
    explicit_choices=plan_choices or {}
    plan_choices={**saved_choices,**explicit_choices}
    target_key='-'+hashlib.sha256(json.dumps(sorted(targets),ensure_ascii=False).encode()).hexdigest()[:12] if targets else ''
    if plan_choices:
        target_key+='-'+hashlib.sha256(json.dumps(plan_choices,sort_keys=True).encode()).hexdigest()[:12]
    stage_key='full' if stages['elevation'] else 'plan1600'
    cache_path = Path(revision["folder"]) / (f"analysis-{VERSION}-r{RECOGNIZER_VERSION}-{stage_key}" + target_key + ".json")
    result=None
    if cache_path.is_file() and not stages['elevation']:
        try:
            result=json.loads(cache_path.read_text(encoding='utf8'))
            if not isinstance(result.get('products'),list) or result['revision']['hash']!=revision['hash']:result=None
        except (OSError,ValueError,TypeError,KeyError,AttributeError):result=None
    if result is not None:
        result["revision"] = revision
        result['source_cache']=dict(mode='analysis',revision_check=round(revision_seconds,6),total_source=round(time.perf_counter()-source_started,6))
        for product in result.get('products',[]):
            product.update(source_path=revision.get('original_path',product.get('source_path')),source_hash=revision['hash'])
            product['source_cache']=result['source_cache']
            product['processing_from_cache']=True
            for child in product.get('plan_results',[]):child.update(source_path=product['source_path'],source_hash=revision['hash'])
            for child in product.get('plan_results',[]):child.update(source_cache=result['source_cache'],processing_from_cache=True)
        return result
    from source_index import load_index
    def extract():
        doc=ezdxf.readfile(dxf_for_revision(revision,converter))
        scale=declared_scale(doc);products,frames=find_products(doc,scale);annotations=[]
        rects,outlines,diagnostics=read_geometry(doc,scale,frames,annotations,recover_panels=False)
        dependencies=archive_dependencies(doc,revision,root)
        if dependencies:diagnostics.append('Nguồn có Xref chưa ghép; cần bind vào bản sao CAD trước khi phân tích đầy đủ.')
        return dict(source_hash=revision['hash'],products=products,annotations=annotations,
                    rectangles=[r.as_dict() for r in rects],outlines=outlines,diagnostics=diagnostics,dependencies=dependencies)
    index_started=time.perf_counter();index,cache_mode=load_index(revision,extract)
    index_seconds=time.perf_counter()-index_started
    from copy import deepcopy
    products=deepcopy(index.meta['products']);annotations=index.meta['annotations']
    if targets:
        codes={c for text in targets for c in product_code(text)}
        names={fold(text) for text in targets}
        products={k:p for k,p in products.items() if k in codes or fold(p['name']) in names}
    diagnostics=list(index.meta['diagnostics']);dependencies=index.meta['dependencies']
    result = {"version": VERSION, "revision": revision, "products": [], "diagnostics": diagnostics,
              "dependencies": dependencies}
    if not products:
        result["diagnostics"].append("Không tìm thấy mã/tên SP yêu cầu trong nguồn." if targets else
                                     "Không thấy block khung có attribute mã SP. Cần nguồn có mã SP để tự định vị sản phẩm.")
    for product in products.values():
        product['parser_version'] = VERSION
        selection_started=time.perf_counter()
        relevant=index.rectangles(product['regions'],full=False)
        product["rectangles"] = [r.as_dict() for r in relevant]
        product['outlines']=index.select(product['regions'])
        product['source_cache']=dict(mode=cache_mode,revision_check=round(revision_seconds,6),index_load=round(index_seconds,6),
                                    spatial_selection=round(time.perf_counter()-selection_started,6),indexed_outlines=index.db.execute('SELECT count(*) FROM outlines').fetchone()[0])
        from drawing_scope import choose_product_plan
        from plan_reference import prepare_reference
        choice=(plan_choices or {}).get(product['code'])
        if choice and choice.get('source_hash')!=revision['hash']:
            raise ValueError('Nguồn CAD đã đổi sau khi xem trước; đọc lại và xác nhận vùng mới.')
        selected=choose_product_plan(product,annotations,choice,multiple=True)
        if selected and product['code'] in explicit_choices:
            atomic_json(root/'view_choices'/revision['hash']/(product['code']+'.json'),choice)
        check=product['check_outlines']
        if not selected:
            product.update(status='needs_review',error=product['view_analysis']['message'],modules=[],
                           build_stages=dict(stages),signature=None,explanation=[product['view_analysis']['message']],
                           source_hash=revision['hash'],source_path=revision['original_path'])
            result['products'].append(product)
            continue
        if not stages['elevation']:
            product.update(source_hash=revision['hash'],source_path=revision['original_path'])
            from named_plans import analyse_named_plans
            analyse_named_plans(product,selected,root)
            if dependencies:
                product.pop('plan_results',None)
                product.update(status='needs_review',error='Có Xref chưa ghép hình học; chưa đủ bằng chứng dựng.',modules=[])
            result['products'].append(product)
            continue
        product.update(source_hash=revision['hash'],source_path=revision['original_path'])
        if dependencies:
            product.update(status='needs_review',error='Có Xref chưa ghép hình học; chưa đủ bằng chứng dựng.',modules=[])
        else:
            from combined_runtime import analyse
            analyse(product,selected,annotations,root)
        result['products'].append(product)
    result['source_cache']=dict(mode=cache_mode,revision_check=round(revision_seconds,6),index_load=round(index_seconds,6),total_source=round(time.perf_counter()-source_started,6))
    for product in result['products']:
        product['source_cache']['total_source']=result['source_cache']['total_source']
        for child in product.get('plan_results',[]):child['source_cache']=product['source_cache']
    atomic_json(cache_path, result)
    return result


def read_product_list(path):
    path = Path(path)
    if path.suffix.lower() in (".xlsx", ".xlsm"):
        import openpyxl
        workbook = openpyxl.load_workbook(path, read_only=True, data_only=True)
        try:
            rows = [tuple(row) for sheet in workbook for row in sheet.iter_rows(values_only=True)]
        finally:
            workbook.close()
    elif path.suffix.lower() in (".csv", ".tsv", ".txt"):
        text = path.read_text(encoding="utf-8-sig")
        try:
            dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t")
        except csv.Error:
            dialect = csv.excel
        rows = list(csv.reader(text.splitlines(), dialect))
    else:
        raise ValueError("Chọn XLSX/XLSM hoặc CSV/TSV. File XLS cũ cần lưu lại thành XLSX.")
    codes = list(dict.fromkeys(code for row in rows for value in row if value is not None for code in product_code(value)))
    if not codes:
        # Named product list: use a recognised name column, never quantities/dates.
        for i, row in enumerate(rows):
            columns = [n for n, value in enumerate(row) if fold(value or "") in ("TEN SP", "TENSP", "TEN SAN PHAM")]
            if columns:
                return list(dict.fromkeys(str(r[columns[0]]).strip() for r in rows[i+1:]
                                          if len(r) > columns[0] and r[columns[0]]))
        raise ValueError("Không thấy mã SP hoặc cột Tên SP trong file danh sách.")
    return codes


def prepare_views(product, views, stages=None):
    stages=stages or {'plan':True,'elevation':True}
    if not stages['elevation']:expand_plan_outlines(views,product['outlines'])
    product['build_stages']=dict(stages)
    product['geometry_pipeline']={'mode':'plan_first','order':['vertical_from_plan','horizontal_from_open_front_and_sections','closed_front_check']}
    product['views']=[{k:v for k,v in view.items() if k not in ('rects','outlines')} for view in views]
    product['check_outlines']=[p for view in views if view['role']=='front_check' for p in view['outlines']]
    if views:product['outlines']=[p for view in views if view['role']!='front_check' for p in view['outlines']]
    product['explanation']=['Chia khoang dọc bằng mặt bằng trước, sau đó chia tầng ngang từ mặt đứng bỏ cánh và mặt cắt.',
                            'Mặt đứng có cánh chỉ dùng đối chiếu. Nét đã explode cần đủ cụm hình học để phân loại hình chiếu.']
    if not stages['elevation']:
        product['geometry_pipeline']={'mode':'plan_only','order':['vertical_from_plan'],'default_height_mm':1600}
        plans=[view for view in views if view['role']=='plan']
        if plans:product['outlines']=[p for view in plans for p in view['outlines']]
        product['check_outlines']=[]
        product['explanation']=['Giai đoạn Mặt bằng: chiều cao tạm 1600 mm; chưa phân tích mặt đứng.']
        product['plan_evidence']=measure_plan(product['outlines'])
        product['material_standards_mm']=list(product['plan_evidence']['standards_mm'])


def replay_experience(product, root, memory=None):
    memory=memory or ExperienceLibrary(root)
    if product.get('build_stages',{}).get('elevation') is False:
        if hasattr(memory,'refresh_plan_rules'):memory.refresh_plan_rules()
        if hasattr(memory,'apply_plan') and memory.apply_plan(product):return True
        if product.get('learning',{}).get('mode')=='review':return False
        if hasattr(memory,'apply_plan_rules') and memory.apply_plan_rules(product):return True
        if product.get('learning',{}).get('mode')=='review':return False
        product['learning']={'mode':'staged','message':'Chưa có mẫu đúng khớp hình học hoặc quy tắc đủ điều kiện cho mặt bằng đang quét; đang dùng thuật toán đo gốc, cao tạm 1600 mm. '+product.get('plan_rule_note','')}
        return False
    return memory.apply(product)


def report_progress(request, root, stage, message):
    path=request.get('progress_file')
    if path and Path(path).resolve().is_relative_to((root/'jobs').resolve()):
        atomic_json(Path(path),dict(stage=stage,message=message))


def run_plan(request,root,stages):
    from plan_reader import analyse_plan, replay_confirmed
    notify=lambda stage,message:report_progress(request,root,stage,message)
    if request.get('action')=='geometry':
        geometry=request['geometry']
        automatic=request.get('automatic_scan',not bool(request.get('code')))
        product=dict(code=request.get('code') or f'SCAN-{str(uuid.uuid4()).upper()}',
            name=request.get('name','Vùng quét CAD' if automatic else ''),automatic_scan=automatic,
            source_hash=geometry['hash'],source_path=geometry.get('model_path') or 'Nét CAD được chọn trong SketchUp')
        if geometry.get('source_watch'):product['source_watch']=geometry['source_watch']
        from cad_style import metadata
        outlines=[dict(handle=str(row['handle']),layer=row.get('layer',''),points=[row['a'],row['b']],**metadata(row)) for row in geometry['lines']]
        analyse_plan(product,outlines,root,notify)
        envelope_preview(product,geometry)
        try:source_placement(product,geometry)
        except ValueError as error:product.update(status='needs_review',error=str(error),modules=[])
        notify('prepare_result','Đã đọc cặp biên theo hướng tấm; đang chuyển về SketchUp để kiểm tra nguồn và dựng…')
        return dict(analyses=[dict(revision=dict(hash=geometry['hash'],original_path=product['source_path']),products=[product],diagnostics=[])],errors=[])
    if not request.get('sources'):raise ValueError('Chưa cấu hình nguồn DWG/DXF trong bảng Quản lý.')
    analyses=[];errors=[]
    for source in request['sources']:
        try:
            notify('read_source','Đang đọc nguồn CAD và quét các tấm theo OY…')
            analysis=analyse_source(source,root,request.get('converter',''),request.get('targets'),stages,request.get('plan_choices'))
            for product in analysis['products']:
                if not analysis.get('dependencies') and product.get('view_analysis',{}).get('selected_view_id'):
                    from named_plans import replay_named
                    replay_named(product,root)
            analyses.append(analysis)
        except Exception as error:errors.append(dict(source=source,error=str(error)))
    notify('prepare_result','Đã đọc nguồn bằng cặp biên song song; không gọi AI.')
    return dict(analyses=analyses,errors=errors)


def run(request):
    root = library_root(request.get("library", ""))
    if request.get('action') == 'ai_status':
        from local_ai import status, CONFIG
        return {'local_ai': status(request.get('ai_config') or CONFIG)}
    if request.get("action") == "products":
        return {"products": read_product_list(request["path"])}
    if request.get('action') == 'learn_plan':
        return {'plan_rules': ExperienceLibrary(library_root(request.get('learning_library') or str(root))).refresh_plan_rules()}
    stages=requested_stages(request)
    if not stages['elevation']:
        return run_plan(request,root,stages)
    if request.get('action')=='geometry':
        from combined_runtime import selected_geometry
        return selected_geometry(request,root,lambda stage,message:report_progress(request,root,stage,message))
    if not request.get('sources'):raise ValueError('Chưa cấu hình nguồn DWG/DXF trong bảng Quản lý.')
    analyses=[];errors=[]
    for source in request['sources']:
        try:
            report_progress(request,root,'sections','Đang đọc mặt bằng và liên kết mặt cắt đứng theo vị trí…')
            analyses.append(analyse_source(source,root,request.get('converter',''),request.get('targets'),stages,request.get('plan_choices')))
        except Exception as error:errors.append(dict(source=source,error=str(error)))
    return dict(analyses=analyses,errors=errors)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--response", required=True)
    args = parser.parse_args()
    try:
        request = json.loads(Path(args.request).read_text(encoding="utf-8-sig"))
        response = {"ok": True, **run(request), "completed_at": time.time()}
    except Exception as error:
        response = {"ok": False, "error": f"{type(error).__name__}: {error}"}
    atomic_json(Path(args.response), response)
    return 0 if response["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
