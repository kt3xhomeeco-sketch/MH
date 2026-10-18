"""Reviewable, source-scoped correction from the user's SP04 wall clarification.

This is a development repair recipe, not a product-code rule in the recogniser.
Every position/outline is taken from the archived drawing; reuse requires the
worker's exact geometry signature and parser version.
"""
import copy
import json
from pathlib import Path
import sys
from statistics import median

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'worker'))
from geometry import Rect, near, inside, rectangle, union, overlapping_modules
from library import VERSION


def complete_module_roles(product):
    """User correction: shared bases and the detailed wall each count as modules."""
    p=copy.deepcopy(product);modules=p['modules']
    assert len(modules)==8
    bases=sorted([part for part in p['trim_parts'] if part['role']=='common_base'],key=lambda part:part['origin'][0])
    assert len(bases)==2
    for base in bases:
        supported=[m['id'] for m in modules if near(m['origin'][2],base['origin'][2]+base['size'][2]) and
                   base['origin'][0]-.15<=m['origin'][0] and m['origin'][0]+m['size'][0]<=base['origin'][0]+base['size'][0]+.15]
        assert len(supported)==2
        modules.append({'id':f'M{len(modules)+1:02}','name':f'Module dài dưới {"–".join(supported)}',
                        'origin':base['origin'],'size':base['size'],'source_box':base['source_box'],
                        'handles':base['handles'],'scope':'base_assembly','supports_module_ids':supported,
                        'rule':'user-confirmed-shared-base-module',
                        'explanation':'Người dùng xác nhận khối dài dưới hai module là một module độc lập.'})
    parts=p['panel_parts'];assert len(parts)==23
    low=[min(part['origin'][i] for part in parts) for i in range(3)]
    high=[max(part['origin'][i]+part['size'][i] for part in parts) for i in range(3)]
    for part in parts:
        part['origin']=[round(part['origin'][i]-low[i],4) for i in range(3)]
        part['owner_module_id']='M11'
    modules.append({'id':'M11','name':'Module 11 — Vách giữa, gồm tấm và nẹp','origin':low,
                    'size':[round(high[i]-low[i],4) for i in range(3)],'scope':'wall_assembly',
                    'panel_thickness_mm':18,'panel_parts':parts,
                    'source_box':union([part['source_box'] for part in parts]),
                    'handles':sorted({h for part in parts for h in part['handles']}),
                    'rule':'user-confirmed-detailed-wall-module',
                    'explanation':'Một module vách chứa các tấm và nẹp riêng; 18 mm là độ dày tấm chính, không phải chiều sâu bao cả nẹp.'})
    assert not overlapping_modules(modules)
    p['panel_parts']=[];p['trim_parts']=[part for part in p['trim_parts'] if part['role']!='common_base']
    p['parser_version']=VERSION
    p['geometry_pipeline']['horizontal']['modules']=modules
    p['explanation']=['11 module: 8 module tủ bao gồm cánh, 2 module dài ở dưới và 1 module vách giữa.',
                      'Module vách giữ nguyên 23 tấm/nẹp bên trong; tấm chính dày 18 mm, nẹp sau chạy suốt 2500 mm.',
                      'Phân loại vai trò đã sửa theo xác nhận người dùng; kích thước và vị trí giữ theo hình học CAD.']
    return p


def resolve(product):
    p=copy.deepcopy(product)
    rs=[Rect(*r['box'],r['handle'],r['layer']) for r in p['rectangles']]
    views=[]
    for v in p['views']:
        views.append({**v,'rects':[r for r in rs if inside(r.box(),v['region'])],
                      'outlines':[o for o in p['outlines']+p['check_outlines'] if all(inside([*q,*q],v['region']) for q in o['points'])]})
    front=next(v for v in views if v['role']=='front_open')
    plan=next(v for v in views if v['id']==p['geometry_pipeline']['vertical']['view_id'])
    sections=[v for v in views if v['role']=='section_vertical']
    outer=max(front['rects'],key=lambda r:r.w*r.h)
    bays=p['geometry_pipeline']['vertical']['columns']
    shift=median(t['box'][0]-bays[t['columns'][0]]['box'][0] for t in p['geometry_pipeline']['horizontal']['candidates'] if len(t['columns'])==1)
    # The human identified the 1600 × 18 plan rectangle as the wall, not a cabinet.
    slab=next(r for r in plan['rects'] if near(r.w,1600) and near(r.h,18))
    wall_col=next(i for i,b in enumerate(bays) if inside(slab.box(),b['box']))
    slab_section=next(v for v in sections if any(near(r.w,18) and near(r.h,2400) and near(r.y0,outer.y0) for r in v['rects']))
    tall=next(r for r in slab_section['rects'] if near(r.w,slab.h) and near(r.h,2400) and near(r.y0,outer.y0))
    strips=sorted([r for r in slab_section['rects'] if near(r.x0,tall.x0) and near(r.x1,tall.x1) and r.y0>=tall.y0-.15],key=lambda r:r.y0)
    assert len(strips)==2 and near(strips[0].y1,strips[1].y0)
    wall_height=strips[-1].y1-tall.y0
    assert near(wall_height,2500)
    front_y=min(r.y0 for r in plan['rects'] if near(r.h,18) and any(near(r.y1,b['box'][1]) for b in bays))
    def origin(box,y):return [round(box[0]-outer.x0,3),round(y-front_y,3),round(box[1]-outer.y0,3)]
    modules=[]
    tiers=p['geometry_pipeline']['horizontal']['candidates']
    for t in sorted((t for t in tiers if len(t['columns'])==1 and wall_col not in t['columns']),key=lambda t:(round(t['box'][1],2),t['box'][0])):
        x0,y0,x1,y1=t['box'];bay=bays[t['columns'][0]];depth=bay['box'][3]-bay['box'][1]
        caps=[r for v in sections for r in v['rects'] if near(r.w,depth) and near(r.y1,y0) and near(r.h,18)]
        # Upper caps end at the upper top instead of its bottom.
        if not caps:caps=[r for v in sections for r in v['rects'] if near(r.w,depth) and near(r.y1,y1) and near(r.h,18)]
        assert caps
        profiles=[]
        for v in sections:
            for cap in caps:
                for o in v['outlines']:
                    q=o['points'];box=[min(a[0] for a in q),min(a[1] for a in q),max(a[0] for a in q),max(a[1] for a in q)]
                    if len(q)>3 and q[0]==q[-1] and cap.x1-.15<=box[0] and .15<box[2]-cap.x1<=18.15 and y0-60<=box[1] and box[3]<=y1+.15 and box[3]-box[1]>(y1-y0)*.4:
                        profiles.append((box,o['handle']))
        assert profiles,t['box']
        z0=min(y0,min(q[0][1] for q in profiles));door_depth=bay['box'][1]-front_y
        assert near(door_depth,18)
        mod={'id':f'M{len(modules)+1:02}','name':f'Module tủ {len(modules)+1:02}',
             'origin':origin([x0,z0,x1,y1],bay['box'][1]-door_depth),
             'size':[round(x1-x0,3),round(depth+door_depth,3),round(y1-z0,3)],
             'carcass_size':[round(x1-x0,3),round(depth,3),round(y1-y0,3)],
             'scope':'carcass_and_doors','source_box':[x0,z0,x1,y1],'carcass_box':t['box'],
             'column_ids':[bay['id']],'plan_box':bay['box'],
             'handles':sorted(set(t['handles']+bay['handles']+[r.handle for r in caps]+[q[1] for q in profiles])),
             'rule':'verified-plan-front-section-assembly',
             'explanation':'Vách đôi chia khoang từ mặt bằng; thùng và cánh đo từ mặt đứng/mặt cắt. Vách 18 ở giữa và chân đế chung tách khỏi module.'}
        modules.append(mod)
    assert len(modules)==8 and not overlapping_modules(modules)
    panels=[]
    wall_x=slab.x0+shift
    def add_panel(name,box,y,depth,handles,role,profile=None):
        part={'id':f'P{len(panels)+1:02}','name':name,'role':role,'owner_part_id':'W01',
              'origin':origin(box,y),'size':[round(box[2]-box[0],3),round(depth,3),round(box[3]-box[1],3)],
              'source_box':box,'handles':handles,'explanation':'Tấm/nẹp riêng của vách W01; kích thước theo hình học CAD và xác nhận của người dùng.'}
        if profile:part['profile']=profile
        panels.append(part)
    for r in strips:
        add_panel('Vách giữa 18 mm',[wall_x,r.y0,wall_x+slab.w,r.y1],slab.y0,slab.h,[slab.handle,r.handle],'wall_panel')
    # Back strips: the user explicitly confirmed their full 2500 mm vertical extent.
    back=[r for r in plan['rects'] if near(r.h,18) and near(r.w,50) and near(r.y0,slab.y1) and slab.x0-.15<=r.x0 and r.x1<=slab.x1+.15]
    assert len(back)==2
    for r in back:
        add_panel('Nẹp sau 50 × 18 — chạy suốt 2500',[r.x0+shift,outer.y0,r.x1+shift,outer.y0+wall_height],r.y0,r.h,[r.handle],'back_trim')
        panels[-1]['height_evidence']='User confirmed full-height 2500 mm, 2026-10-18'
    wall_box=[wall_x,outer.y0,wall_x+slab.w,outer.y0+wall_height]
    seen=set()
    for o in front['outlines']:
        points=o['points'];box=[min(a[0] for a in points),min(a[1] for a in points),max(a[0] for a in points),max(a[1] for a in points)]
        if len(points)<4 or points[0]!=points[-1] or not inside(box,wall_box):continue
        key=tuple(round(v,2) for v in box)
        if key in seen:continue
        rec=rectangle(points,o['handle'])
        if near(min(box[2]-box[0],box[3]-box[1]),80):depth=12;role='front_trim'
        elif (not rec and len(points)==8) or (rec and near(rec.w,980) and near(rec.h,1880)):depth=5;role='decorative_infill'
        else:continue
        witnesses=[r for v in views if v['role']=='plan' for r in v['rects'] if near(r.h,depth)]
        assert witnesses
        seen.add(key)
        profile=[[round(x-box[0],3),round(z-box[1],3)] for x,z in points[:-1]]
        add_panel(f'Nẹp mặt {depth} mm' if role=='front_trim' else 'Tấm trang trí 5 mm',box,slab.y0-depth,depth,[o['handle']]+[r.handle for r in witnesses],role,profile)
    support=[]
    for t in tiers:
        if len(t['columns'])!=2:continue
        if t['box'][3]>min(m['source_box'][1] for m in modules)+60:continue
        b=t['box'];box=[b[0],b[1],b[2],min(m['source_box'][1] for m in modules)]
        support.append({'id':f'A{len(support)+1:02}','role':'common_base','name':'Chân đế chung — đối chiếu',
                        'origin':origin(box,front_y),'size':[round(box[2]-box[0],3),360,round(box[3]-box[1],3)],
                        'source_box':box,'handles':t['handles'],'face_width_mm':round(box[2]-box[0],3),'stock_thickness_mm':None})
    assert len(support)==2
    support.append({'id':'A03','role':'cad_envelope_reference','name':'Đường bao nguồn CAD — tham chiếu',
                    'origin':[0,0,0],'size':[round(outer.w,3),round(max(b['box'][3] for b in bays)-front_y,3),round(outer.h,3)],
                    'source_box':outer.box(),'handles':[outer.handle],
                    'explanation':'Khung đường bao CAD, không phải khối vật liệu hay module; giữ vị trí toàn sản phẩm và phần ốp chưa thay mẫu.'})
    p.update(status='ready',modules=modules,panel_parts=panels,trim_parts=support,
             bounds=support[-1]['size'],manual_recovery=True)
    p['recognition_error']=p.pop('error',None)
    p['geometry_pipeline']['horizontal']['modules']=modules
    p['geometry_pipeline']['vertical']['columns'][wall_col]['role']='wall_assembly'
    p['explanation']=['Hình học chia 4 khoang tủ ở hai bên, mỗi khoang 2 tầng; module bao gồm thùng và cánh.',
                      'Người dùng xác nhận giữa là vách 18 × 1600, nẹp sau 50 × 18 chạy suốt 2500; dựng riêng theo tấm, không coi là module tủ.',
                      'Hai chân đế chung giữ dạng khung đối chiếu; các tấm/nẹp vách là khối đặc theo đường bao CAD.']
    return complete_module_roles(p)


if __name__=='__main__':
    response=json.loads((ROOT/'outputs/assembly-response.json').read_text(encoding='utf8'))
    assert response['ok'] and not response['errors']
    source=next(p for a in response['analyses'] for p in a['products'] if p['code']=='SP04')
    result=resolve(source)
    (ROOT/'outputs/sp04-geometry-recipe.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({'modules':[(m['size'],m['origin']) for m in result['modules']],
                      'panel_parts':len(result['panel_parts']),'bounds':result['bounds']},ensure_ascii=False))
