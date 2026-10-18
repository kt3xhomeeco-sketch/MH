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
from stages import requested_stages, infer_plan_views, recognise_plan, source_placement
from plan_profiles import expand_plan_outlines

# Invalidate derived geometry without invalidating accepted source measurements.
RECOGNIZER_VERSION = 8


def fold(value):
    text = unicodedata.normalize("NFD", str(value)).replace("đ", "d").replace("Đ", "D")
    return " ".join("".join(c for c in text if not unicodedata.combining(c)).upper().split())


def product_code(value):
    matches = re.findall(r"\bSP\s*[-_]?\s*(\d+)\b", str(value), re.I)
    return ["SP" + m.zfill(2) for m in matches]


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
        code_values = [attrs.get(k, "") for k in ("MASP", "MA_SP", "PRODUCT", "TENBV1", "TENBV2")]
        codes = list(dict.fromkeys(code for value in code_values for code in product_code(value)))
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


def read_geometry(doc, scale, excluded, annotations=None, min_panel_length=100):
    rects, outlines, lines, diagnostics = [], [], [], []

    def walk(entities, parent="", depth=0):
        if depth > 12:
            diagnostics.append("Block lồng quá 12 cấp: đã bỏ qua phần sâu hơn.")
            return
        for entity in entities:
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
                        axis='horizontal' if extent.size.x>extent.size.y else 'vertical'
                        annotations.append({'kind':'section_marker','handle':parent+'/'+handle,
                                            'point':[entity.dxf.insert.x*scale,entity.dxf.insert.y*scale],
                                            'numbers':[attrs['4' if axis=='horizontal' else '1']] if all(k in attrs for k in ('1','4')) else [],
                                            'numbers_all':sorted(set(attrs.values())), 'axis':axis})
                    continue
                try:
                    walk(entity.virtual_entities(), parent + "/" + handle, depth + 1)
                except Exception as error:
                    diagnostics.append(f"Block {handle}: {error}")
                continue
            identity = parent + "/" + handle
            layer = entity.dxf.layer
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
                if len(pts) > 1 and len(outlines) < 25000:
                    outlines.append({"handle": identity, "points": pts[:3000], "layer": layer})
            except (TypeError, ValueError, AttributeError):
                pass

    walk(doc.modelspace())
    if len(lines) <= 15000:
        rects.extend(line_rectangles(lines,min_length=min_panel_length))
    else:
        diagnostics.append("Quá nhiều LINE để ghép vòng trong lượt này; ưu tiên polyline kín.")
    return rects, outlines, diagnostics


def analyse_source(source, root, converter="", targets=None, stages=None):
    stages=stages or {'plan':True,'elevation':True}
    revision = archive_source(source, root)
    target_key='-'+hashlib.sha256(json.dumps(sorted(targets),ensure_ascii=False).encode()).hexdigest()[:12] if targets else ''
    stage_key='full' if stages['elevation'] else 'plan1600'
    cache_path = Path(revision["folder"]) / (f"analysis-{VERSION}-r{RECOGNIZER_VERSION}-{stage_key}" + target_key + ".json")
    if cache_path.is_file():
        result = json.loads(cache_path.read_text(encoding="utf-8"))
        result["revision"] = revision
        return result
    dxf = dxf_for_revision(revision, converter)
    doc = ezdxf.readfile(dxf)
    scale = declared_scale(doc)
    products, frames = find_products(doc, scale)
    if targets:
        codes={c for text in targets for c in product_code(text)}
        names={fold(text) for text in targets}
        products={k:p for k,p in products.items() if k in codes or fold(p['name']) in names}
    annotations=[]
    rects, outlines, diagnostics = read_geometry(doc, scale, frames, annotations,
                                                min_panel_length=100 if stages['elevation'] else 0)
    dependencies = archive_dependencies(doc, revision, root)
    if dependencies:
        diagnostics.append("Nguồn có Xref; bộ nhận dạng hiện chưa ghép hình học từ Xref. Cần bind/Xref vào một bản sao CAD để phân tích đầy đủ.")
    result = {"version": VERSION, "revision": revision, "products": [], "diagnostics": diagnostics,
              "dependencies": dependencies}
    if not products:
        result["diagnostics"].append("Không tìm thấy mã/tên SP yêu cầu trong nguồn." if targets else
                                     "Không thấy block khung có attribute mã SP. Cần nguồn có mã SP để tự định vị sản phẩm.")
    for product in products.values():
        product['parser_version'] = VERSION
        relevant = [r for r in rects if any(inside(r.box(), region) for region in product["regions"])]
        product["rectangles"] = [r.as_dict() for r in relevant]
        product["outlines"] = [p for p in outlines if any(
            all(region[0] <= v[0] <= region[2] and region[1] <= v[1] <= region[3] for v in p["points"])
            for region in product["regions"])]
        views=split_views(product['regions'],annotations,relevant,product['outlines']) or infer_views(relevant,product['outlines'])
        if not stages['elevation'] and not any(v['role']=='plan' for v in views):
            views=infer_plan_views(relevant,product['outlines'])
        prepare_views(product,views,stages)
        try:
            if dependencies:
                raise ValueError("Có Xref chưa ghép hình học; chưa đủ bằng chứng để tự dựng sản phẩm.")
            product.update((recognise_ordered if stages['elevation'] else recognise_plan)(views,product['geometry_pipeline']))
            product["status"] = "ready"
        except ValueError as error:
            product.update(status="needs_review", error=str(error), modules=[])
            product["signature"] = geometry_signature(relevant, outlines=product['outlines'])
        product["source_hash"] = revision["hash"]
        product["source_path"] = revision["original_path"]
        result["products"].append(product)
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
        product['outlines']=[p for view in views if view['role']=='plan' for p in view['outlines']]
        product['check_outlines']=[]
        product['explanation']=['Giai đoạn Mặt bằng: chiều cao tạm 1600 mm; chưa phân tích mặt đứng.']


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


def run(request):
    root = library_root(request.get("library", ""))
    if request.get("action") == "products":
        return {"products": read_product_list(request["path"])}
    if request.get('action') == 'learn_plan':
        return {'plan_rules': ExperienceLibrary(library_root(request.get('learning_library') or str(root))).refresh_plan_rules()}
    stages=requested_stages(request)
    memory = ExperienceLibrary(root)
    if request.get("action") == "geometry":
        geometry = request["geometry"]
        automatic=request.get('automatic_scan',not bool(request.get('code')))
        code=request.get('code') or f'SCAN-{str(uuid.uuid4()).upper()}'
        rows = [(tuple(row["a"]), tuple(row["b"]), row["handle"], row.get("layer", "")) for row in geometry["lines"]]
        rects = line_rectangles(rows,min_length=100 if stages['elevation'] else 0)
        product = {"code": code, "name": request.get("name", "Vùng quét CAD" if automatic else ""),
                   'automatic_scan':automatic,"source_hash": geometry["hash"], "parser_version": VERSION,
                   "source_path": geometry.get("model_path") or "Nét CAD được chọn trong SketchUp",
                   "outlines": [{"handle": h, "layer": layer, "points": [a,b]} for a,b,h,layer in rows],
                   "rectangles": [r.as_dict() for r in rects], "regions": [union([r.box() for r in rects])] if rects else []}
        views=infer_views(rects,product['outlines'])
        if not stages['elevation'] and not any(v['role']=='plan' for v in views):
            views=infer_plan_views(rects,product['outlines'])
        prepare_views(product,views,stages)
        try:
            product.update((recognise_ordered if stages['elevation'] else recognise_plan)(views,product['geometry_pipeline']))
            product["status"] = "ready"
            replay_experience(product, root, memory)
        except ValueError as error:
            product.update(status="needs_review", error=str(error), modules=[])
            product["signature"] = geometry_signature(rects, outlines=product['outlines'])
            replay_experience(product, root, memory)
        try:
            source_placement(product,geometry)
        except ValueError as error:
            product.update(status='needs_review',error=str(error),modules=[])
        return {"analyses": [{"revision": {"hash": geometry["hash"], "original_path": product["source_path"]},
                              "products": [product], "diagnostics": []}], "errors": []}
    analyses, errors = [], []
    for source in request.get("sources", []):
        try:
            analysis = analyse_source(source, root, request.get("converter", ""),request.get('targets'),stages)
            for product in analysis["products"]:
                replay_experience(product, root, memory)
            analyses.append(analysis)
        except Exception as error:
            errors.append({"source": source, "error": str(error)})
    if not request.get("sources"):
        raise ValueError("Chưa cấu hình nguồn DWG/DXF trong bảng Quản lý.")
    return {"analyses": analyses, "errors": errors}


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
