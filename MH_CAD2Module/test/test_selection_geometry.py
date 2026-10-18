from library import library_root
from main import run
from test_geometry import cabinet, complete_cabinet


def test_selected_lines_need_no_dwg_or_product_frame(tmp_path):
    lines=[]
    for rect in complete_cabinet():
        pts=[(rect.x0,rect.y0),(rect.x1,rect.y0),(rect.x1,rect.y1),(rect.x0,rect.y1)]
        for i in range(4):
            lines.append({"a":pts[i],"b":pts[(i+1)%4],"handle":f"{rect.handle}:{i}"})
    result=run({"action":"geometry","library":str(tmp_path/"lib"),"code":"SP02","build_elevation":True,
                "geometry":{"hash":"f"*64,"lines":lines,"model_path":""}})
    product=result["analyses"][0]["products"][0]
    assert product["status"]=="ready",product.get("error")
    assert product["code"]=="SP02"
    assert [m["size"] for m in product["modules"]]==[[860,600,2110],[860,600,2110],[1720,600,432]]
    assert product['geometry_pipeline']['mode']=='plan_first'


def test_missing_plan_cannot_fall_back_to_front_first(tmp_path):
    lines=[]
    for rect in cabinet():
        points=[(rect.x0,rect.y0),(rect.x1,rect.y0),(rect.x1,rect.y1),(rect.x0,rect.y1)]
        lines += [{'a':a,'b':b,'handle':str(i)} for i,(a,b) in enumerate(zip(points,points[1:]+points[:1]))]
    product=run({'action':'geometry','code':'SP02','library':str(tmp_path/'lib'),'build_elevation':True,
                 'geometry':{'hash':'d'*64,'lines':lines}})['analyses'][0]['products'][0]
    assert product['status']=='needs_review'
    assert not product['modules']
    assert 'mặt bằng' in product['error']
