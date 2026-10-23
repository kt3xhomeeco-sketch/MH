from dataclasses import replace
import json
from pathlib import Path

import ezdxf
import pytest

from geometry import Rect, inside, line_rectangles, overlapping_modules, recognise, rectangle, section_support, validate_joint
from main import analyse_source, declared_scale, find_products, read_geometry
from library import library_root


def cabinet(width=860, thickness=18, height=2110, depth=582, x=1000, y=1000):
    rows = []
    def panel(a, b, w, h):
        rows.append(Rect(a, b, a+w, b+h, str(len(rows)), "panel"))
    for base in (x, x+width):
        panel(base, y, thickness, height)
        panel(base+width-thickness, y, thickness, height)
        panel(base+thickness, y, width-2*thickness, thickness)
        panel(base+thickness, y+height-thickness, width-2*thickness, thickness)
    upper_y = y+height+50
    panel(x, upper_y, thickness, 382)
    panel(x+2*width-thickness, upper_y, thickness, 382)
    panel(x+thickness, upper_y+382-thickness, 2*width-2*thickness, thickness)
    panel(x+width-thickness/2, upper_y, thickness, 382-thickness)
    panel(x, upper_y-50, 2*width, 50)
    panel(x, y-50, 2*width, 50)
    panel(x, upper_y+382, 2*width, 50)
    # Corresponding section with full-height door and top/bottom carcass panels.
    door_x = x+2*width+1500
    panel(door_x, y, thickness, height)
    panel(door_x-depth, y, depth, thickness)
    panel(door_x-depth, y+height-thickness, depth, thickness)
    panel(door_x-depth+18, y+9, 6, height-18)
    return rows


def complete_cabinet():
    """Unlabelled complete views, including plan and the two-leg section support."""
    rows=cabinet()
    for x in (1000,1860):
        rows += [Rect(x,200,x+18,782,'plan-left'),Rect(x+842,200,x+860,782,'plan-right'),
                 Rect(x+18,764,x+842,782,'plan-back'),Rect(x,182,x+860,200,'plan-door')]
    rows += [Rect(4202,3110,4220,3160,'section-front-leg'),
             Rect(3638,3110,3656,3142,'section-back-leg'),
             Rect(3638,3142,4202,3160,'section-deck'),
             Rect(4220,3135,4238,3542,'section-upper-door'),
             Rect(3638,3524,4220,3542,'section-upper-top')]
    return rows


def test_split_double_walls_keep_upper_single_partition():
    result = recognise(cabinet())
    assert [m["size"] for m in result["modules"]] == [[860,582,2110],[860,582,2110],[1720,582,382]]
    assert [m["origin"] for m in result["modules"]] == [[0,18,50],[860,18,50],[0,18,2210]]
    assert result["bounds"] == [1720,600,2642]
    assert result["back_mm"] == 6


def test_changed_dimensions_are_measured_not_hardcoded():
    result = recognise(cabinet(width=930, thickness=20, height=2250, depth=620))
    assert result["panel_mm"] == 20
    assert result["modules"][0]["size"] == [930,620,2250]
    assert result["modules"][2]["size"] == [1860,620,382]


def test_translation_and_handle_changes_keep_signature():
    a = recognise(cabinet())
    b = recognise([replace(r,x0=r.x0+8700,x1=r.x1+8700,y0=r.y0-3520,y1=r.y1-3520,handle="new-"+r.handle) for r in cabinet()])
    assert a["signature"] == b["signature"]
    assert a["modules"][0]["size"] == b["modules"][0]["size"]


def test_no_depth_is_explicit_error():
    rows = [r for r in cabinet() if r.x0 < 4000]
    with pytest.raises(ValueError, match="Thiếu chiều sâu"):
        recognise(rows)


def test_conflicting_depth_is_not_guessed():
    rows = cabinet()
    for row in cabinet(depth=630, x=15000):
        if row.x0 >= 17000:
            rows.append(row)
    with pytest.raises(ValueError, match="Mâu thuẫn chiều sâu"):
        recognise(rows)


def test_four_lines_reconstruct_panel_and_gap_rejected():
    pts = [(0,0),(18,0),(18,2110),(0,2110)]
    lines = [(pts[i],pts[(i+1)%4],str(i),"panel") for i in range(4)]
    rects = line_rectangles(lines)
    assert len(rects)==1 and rects[0].w==18 and rects[0].h==2110
    lines[1] = ((18,10),(18,2110),"1","panel")
    assert not line_rectangles(lines)


def test_l_shape_not_bbox_rectangle():
    assert rectangle([(0,0),(100,0),(100,18),(18,18),(18,100),(0,100)],"L") is None


def test_source_dxf_dim_deleted_still_builds(tmp_path):
    doc = ezdxf.new("R2018", units=4)
    block = doc.blocks.new("FRAME")
    block.add_lwpolyline([(0,0),(10000,0),(10000,8000),(0,8000)],close=True)
    block.add_attdef("MASP", insert=(9000,100),text="SP01")
    block.add_attdef("TENSP",insert=(9000,200),text="TỦ ÁO")
    insert=doc.modelspace().add_blockref("FRAME",(0,0))
    insert.add_auto_attribs({"MASP":"SP01","TENSP":"TỦ ÁO"})
    for rect in complete_cabinet():
        doc.modelspace().add_lwpolyline([(rect.x0,rect.y0),(rect.x1,rect.y0),(rect.x1,rect.y1),(rect.x0,rect.y1)],close=True)
    source=tmp_path/"input.dxf";doc.saveas(source)
    result=analyse_source(str(source),library_root(str(tmp_path/"library")))
    assert result["products"][0]["status"]=="ready"
    assert result['products'][0]['geometry_pipeline']['mode']=='plan_and_elevation'
    assert len(result["products"][0]["modules"])==2
    assert result['products'][0]['elevation_pending'] # No section markers were supplied.
    assert result["products"][0]["code"]=="SP01"


def test_unit_scale_and_unknown_units():
    doc=ezdxf.new(units=1)
    assert declared_scale(doc)==25.4
    doc.header["$INSUNITS"]=0
    with pytest.raises(ValueError,match="Đơn vị"):
        declared_scale(doc)


@pytest.mark.skipif(not Path(r"E:\MAC\OneDrive\Desktop\Drawing1.dwg").exists(),reason="Local user drawing not supplied")
def test_actual_drawing1_geometry_only(tmp_path):
    result=analyse_source(r"E:\MAC\OneDrive\Desktop\Drawing1.dwg",library_root(str(tmp_path/"actual")))
    product=next(p for p in result["products"] if p["code"]=="SP60")
    assert product['status']=='ready' and len(product['plan_results'])==2
    upper=next(c for c in product['plan_results'] if c['plan_title']=='MẶT CẮT 3-3')
    lower=next(c for c in product['plan_results'] if c['plan_title']=='MẶT CẮT 4-4')
    assert upper['elevation_pending']
    assert [m['size'] for m in lower['modules']]==[[860,600,2110],[860,600,2110]]
    assert [m['origin'][2] for m in lower['modules']]==[50,50]
    assert lower['geometry_pipeline']['horizontal']['status']=='measured'
    candidate=next(c for c in product['view_analysis']['candidates'] if c['title']=='MẶT CẮT 4-4')
    result=analyse_source(r"E:\MAC\OneDrive\Desktop\Drawing1.dwg",library_root(str(tmp_path/"actual")),
                          plan_choices={'SP60':dict(source_hash=product['source_hash'],view_id=candidate['id'],signature=candidate['signature'])})
    product=result['products'][0]
    assert product["status"]=="ready",product.get("error")
    # Tier association is pending, but the linked front still measures the
    # whole SP stock envelope from Z50 to Z2592; do not revert it to1600.
    assert [m["size"] for m in product["modules"]]==[[860,600,2542],[860,600,2542]]
    assert [m['origin'][2] for m in product['modules']]==[50,50]
    assert product['elevation_pending'] and product['geometry_pipeline']['horizontal']['issues']


def support_outlines():
    rows = json.loads((Path(__file__).parent/'fixtures/top_support_section.json').read_text())
    # Align actual section with the synthetic cabinet's upper bottom at 3160.
    for row in rows:
        row['points'] = [[x, y-5113.04+3160] for x,y in row['points']]
    return rows


def test_top_module_includes_full_two_legs_below_door():
    result = recognise(cabinet(), support_outlines())
    assert result['modules'][2]['size'] == [1720,582,432]
    assert result['modules'][2]['origin'] == [0,18,2160]
    assert result['modules'][2]['section_support']['extension_mm'] == 50
    assert result['modules'][2]['section_support']['below_door_mm'] == 25
    assert result['modules'][2]['joint_evidence']['front_handles']
    assert result['modules'][2]['joint_evidence']['section_no_cut'] is True
    assert result['bounds'] == [1720,600,2642]


def test_support_offset_is_measured_and_requires_both_legs():
    outlines = support_outlines()
    for point in outlines[-1]['points']:
        if abs(point[1]-3135) < .01:
            point[1] -= 5
    # Changing the door does not move the module's support plane.
    assert recognise(cabinet(), outlines)['modules'][2]['size'][2] == 432
    for row in outlines[:3]:
        for point in row['points']:
            if abs(point[1]-3110) < .01:
                point[1] -= 10
    # A changed section cannot silently disagree with the front seam.
    with pytest.raises(ValueError, match='mặt đứng'):
        recognise(cabinet(), outlines)
    assert recognise(cabinet(), [r for r in outlines if r['handle']!='/C09'])['modules'][2]['size'][2] == 382


def test_support_from_individual_edges_and_signature_includes_profile():
    outlines = support_outlines()
    edges = [{'handle':f'{row["handle"]}-{i}','points':[a,b]} for row in outlines
             for i,(a,b) in enumerate(zip(row['points'],row['points'][1:]))]
    assert recognise(cabinet(), edges)['modules'][2]['size'] == [1720,582,432]
    assert recognise(cabinet(), outlines)['signature'] != recognise(cabinet())['signature']


def test_door_bottom_cuts_unbroken_section_leg_and_carcass_bottom_has_no_front_seam():
    rows, outlines = cabinet(), support_outlines()
    module = {'box': [1000,3160,2720,3542]}
    support = section_support(module, rows, outlines, 582, 18)
    # Door edge at 3135 passes through the 3110..3160 front leg.
    with pytest.raises(ValueError, match='cắt xuyên'):
        validate_joint(module, rows, outlines, {**support, 'bottom':3135})
    # Top of the foot band is not a continuous front joint on both sides.
    with pytest.raises(ValueError, match='mặt đứng'):
        validate_joint(module, rows, outlines, {**support, 'bottom':3160})


def test_sp01_drawers_inside_enclosure_are_not_ready_modules():
    data=json.loads((Path(__file__).parent/'fixtures/sp01_nested_drawers.json').read_text())
    rows=[Rect(*r['box'],r['handle'],r['layer']) for r in data]
    outer=next(r for r in rows if r.handle=='/DF6AB')
    y0,y1=outer.y0,outer.y1
    rows += [Rect(190000,y0,190018,y1,'door'),
             Rect(189759,y0,190000,y0+18,'bottom'),
             Rect(189759,y1-18,190000,y1,'top')]
    with pytest.raises(ValueError,match='chồng nhau'):
        recognise(rows)


def test_touching_modules_are_allowed_but_contained_module_is_rejected():
    a={'id':'outer','origin':[0,0,0],'size':[800,600,2000]}
    b={'id':'next','origin':[800,0,0],'size':[800,600,2000]}
    c={'id':'drawer','origin':[20,20,100],'size':[300,500,400]}
    assert overlapping_modules([a,b])==[]
    assert overlapping_modules([a,c])==['outer/drawer']
