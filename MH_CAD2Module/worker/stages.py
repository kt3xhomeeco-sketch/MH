"""User-selected construction stages. Plan preview height is explicitly provisional."""
from geometry import Rect, TOL, near, union, inside, gap_boxes, geometry_signature, overlapping_modules
from materials import BOARD_MM
from views import plan_columns
from plan_profiles import curved_ends, stepped_bay
import math

PLAN_HEIGHT_MM = 1600


def source_placement(product,geometry):
    if product.get('status')!='ready' and not product.get('envelope_preview'):return
    plane=geometry.get('plane','XY')
    offset=geometry.get('plane_offset_mm',0)
    if plane not in ('XY','XZ','YZ') or not isinstance(offset,(float,int)) or not math.isfinite(offset):
        raise ValueError('Mặt phẳng/vị trí nguồn quét không hợp lệ.')
    if product['geometry_pipeline']['mode']=='plan_only':
        offset_xy=product.get('plan_origin_offset_mm',[0,0])
        anchor=product.get('source_plan_envelope',product['envelope']) if product.get('plan_origin_basis')=='source_plan_envelope' else product['envelope']
        origin=[anchor[i]+offset_xy[i] for i in (0,1)]
    else:
        # Full mode registers the elevation's X back to its measured plan.
        horizontal=product['geometry_pipeline'].get('horizontal',{})
        first=product['modules'][0]
        if 'x_offset' not in horizontal or 'plan_box' not in first:
            raise ValueError('Chưa ghép được gốc mặt bằng để dựng ngay trên CAD nguồn.')
        origin=[product['envelope'][0]-horizontal['x_offset'],
                first['plan_box'][1]-first.get('carcass_origin',first['origin'])[1]]
    product['placement']={'mode':'source_plan','plane':plane,'origin_mm':[round(v,6) for v in origin],
                          'plane_offset_mm':offset}
    product['explanation'].append('Quét trực tiếp: dựng tại mặt bằng CAD đã quét, không đặt theo nhãn SP.')


def selected_envelope(geometry):
    points=[row[k] for row in geometry.get('lines',[]) for k in ('a','b')]
    if not points or any(len(p)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) for v in p) for p in points):
        raise ValueError('Vùng quét không có tọa độ CAD hữu hạn để dựng khung bao.')
    return union([[*p,*p] for p in points])


def envelope_preview(product,geometry):
    """A selectable correction target, explicitly not a recognised module layout."""
    if product.get('status')=='ready' or product.get('build_stages',{}).get('elevation') is not False:return False
    box=selected_envelope(geometry)
    size=[round(box[2]-box[0],6),round(box[3]-box[1],6),PLAN_HEIGHT_MM]
    offset=geometry.get('plane_offset_mm',0)
    if (any(not .1<v<100000 for v in size[:2]) or geometry.get('plane','XY') not in ('XY','XZ','YZ')
            or type(offset) not in (float,int) or not math.isfinite(offset)):return False
    reason=product.get('error') or product.get('local_ai',{}).get('message') or 'Chưa xác định được cách chia module.'
    product.update(envelope=box,source_plan_envelope=box,bounds=size,plan_origin_offset_mm=[0,0],
        plan_origin_basis='source_plan_envelope',height_source='provisional_default',default_height_mm=PLAN_HEIGHT_MM,
        envelope_preview=dict(kind='selected_cad_envelope',reason=reason,dimensions_from='selected_source_edges',height_provisional=True),
        modules=[dict(id='M01',name='Khối tạm CAD — chưa chia module',origin=[0,0,0],size=size,
            source_box=box,plan_box=box,handles=sorted({str(l['handle']) for l in geometry['lines']}),
            rule='source-envelope-preview-v1',height_source='provisional_default',envelope_preview=True,
            explanation='Chỉ là khung bao vùng CAD đã quét để chọn và sửa; chưa xác nhận module đúng.')],
        trim_parts=[],panel_parts=[])
    product['outlines']=[dict(handle=l['handle'],layer=l.get('layer',''),points=[l['a'],l['b']]) for l in geometry['lines']]
    product['views']=[dict(id='PREVIEW',role='plan',title='Khung bao vùng quét — chưa phân tích',region=box,unresolved_bays=True)]
    product['geometry_pipeline']=dict(mode='plan_only',order=['source_envelope_preview'],default_height_mm=PLAN_HEIGHT_MM,
        vertical=dict(view_id='PREVIEW',columns=[]))
    product.setdefault('explanation',[]).append('Chưa chia được module: dựng khối tạm theo khung bao CAD, cao tạm 1600 mm. Bấm Sai, chọn các box đã vẽ đúng rồi bấm Kết quả đúng.')
    return True


def requested_stages(request):
    if request.get('build_plan',True) is not True:
        raise ValueError('Chọn giai đoạn Mặt bằng trước khi dựng; Mặt đứng dùng kèm Mặt bằng.')
    return {'plan':True,'elevation':request.get('build_elevation',False) is True}


def infer_plan_views(rects,outlines,allow_unresolved=False):
    """A selected standalone plan needs no elevation to establish its role."""
    remaining=set(range(len(rects)));views=[]
    while remaining:
        stack=[remaining.pop()];group=[]
        while stack:
            i=stack.pop();group.append(rects[i])
            for j in list(remaining):
                if max(gap_boxes(rects[i].box(),rects[j].box()))<=60:
                    remaining.remove(j);stack.append(j)
        box=union([r.box() for r in group])
        selected=[o for o in outlines if o['points'] and all(inside([*p,*p],box) for p in o['points'])]
        bays=plan_columns(group) or stepped_bay(group,selected)
        unresolved=allow_unresolved and sum(12<=r.w<=40 and r.h>=100 for r in group)>=2
        if not bays and not unresolved:continue
        if not 100<=box[3]-box[1]<=1200 or any(not 100<=b['box'][3]-b['box'][1]<=1200 for b in bays):continue
        views.append({'id':f'P{len(views)+1:02}','role':'plan','title':'Mặt bằng từ vùng quét',
                      'region':box,'rects':group,'outlines':selected,'unresolved_bays':not bool(bays)})
    return views


def plan_frontage(view,bays):
    profiles=list(view['rects'])
    for outline in view['outlines']:
        pts=outline['points']
        if len(pts)<4 or not all(near(a,b) for a,b in zip(pts[0],pts[-1])):continue
        profiles.append(Rect(*union([[*p,*p] for p in pts]),outline['handle'],outline.get('layer','')))
    return [r for r in profiles if 3<=r.h<=60 and r.w>r.h and
            any(near(r.y1,b['box'][1]) for b in bays)]


def plan_runs(bays):
    """Keep best non-overlapping chains; an invalid candidate cannot break a valid run."""
    spans={}
    for bay in bays:
        key=tuple(round(bay['box'][i],2) for i in (0,2,3))
        if key not in spans or bay['box'][1]>spans[key]['box'][1]:spans[key]=bay
    # Coincident side pairs use the innermost construction front; frontage supplies door extent later.
    paths=[]
    for bay in sorted(spans.values(),key=lambda b:(b['box'][0],b['box'][1],b['box'][2])):
        choices=[[bay]]
        for run in paths:
            previous=run[-1]
            gap=bay['box'][0]-previous['box'][2]
            if -.1<=gap<=60 and near(bay['box'][3],previous['box'][3],60):
                choices.append(run+[bay])
        score=max(sum(b['box'][2]-b['box'][0] for b in run) for run in choices)
        best={tuple(tuple(round(v,2) for v in b['box']) for b in run):run for run in choices
              if near(sum(b['box'][2]-b['box'][0] for b in run),score,.01)}
        paths.extend(list(best.values())[:2])
    return paths


def recognise_plan(views,pipeline):
    layouts=[]
    for view in views:
        if view['role']!='plan':continue
        runs=plan_runs(plan_columns(view['rects']) or stepped_bay(view['rects'],view['outlines']))
        layouts.extend((sum(b['box'][2]-b['box'][0] for b in run),view,run) for run in runs)
    if not layouts:raise ValueError('Chưa ghép được khoang từ mặt bằng. Quét đủ vách và đường khép khoang; chưa cần mặt đứng.')
    layouts.sort(key=lambda row:(round(row[0],2),len(row[2])),reverse=True)
    score,plan,bays=layouts[0]
    def shape(run):
        left=min(b['box'][0] for b in run);front=min(b['box'][1] for b in run)
        return [[round(v,1) for v in (b['box'][0]-left,b['box'][1]-front,b['box'][2]-left,b['box'][3]-front)] for b in run]
    if any(near(other[0],score) and len(other[2])==len(bays) and shape(other[2])!=shape(bays) for other in layouts[1:]):
        raise ValueError('Các mặt bằng cùng mức bằng chứng có khoang khác nhau; quét riêng mặt bằng cần dựng.')
    frontage=plan_frontage(plan,bays)
    footprints=[]
    for i,bay in enumerate(bays):
        bay['id']=f'C{i+1:02}'
        x0,y0,x1,y1=bay['box']
        doors=[r for r in frontage if max(r.x0,x0)<min(r.x1,x1)-TOL and x0-TOL<=r.x0 and r.x1<=x1+TOL and near(r.y1,y0)]
        # The closed door contour gives the forward extent, including framed doors.
        front=min([y0]+[r.y0 for r in doors])
        footprint={'box':[x0,front,x1,y1],'carcass_box':bay['box'],'handles':bay['handles']+[r.handle for r in doors]}
        if bay.get('stepped_rear'):
            footprint.update(plan_profile=bay['plan_profile'],stepped_rear=True)
        footprints.append(footprint)
    footprints.extend(curved_ends(plan,footprints))
    footprints.sort(key=lambda p:p['box'][0])
    envelope=union([p['box'] for p in footprints])
    extras=[]
    for r in plan['rects']:
        stock=next((s for s in BOARD_MM if s>=12 and near(r.w,s)),None)
        if not stock or not stock<=r.h<=envelope[3]-envelope[1]+60:continue
        if any(min(r.x1,p['box'][2])-max(r.x0,p['box'][0])>TOL and
               min(r.y1,p['box'][3])-max(r.y0,p['box'][1])>TOL for p in footprints):continue
        if not any(near(r.x1,p['box'][0]) or near(r.x0,p['box'][2]) for p in footprints):continue
        if r.y1<envelope[1]-TOL or r.y0>envelope[3]+TOL:continue
        extras.append(r)
    extras=list({tuple(round(v,2) for v in r.box()):r for r in extras}.values())
    # LINE recovery may emit a full strip and its split subloops. Keep its measured union once.
    extras=[r for r in extras if not any(p is not r and near(p.x0,r.x0) and near(p.x1,r.x1)
            and inside(r.box(),p.box()) and p.h>r.h+TOL for p in extras)]
    returns={}
    for r in extras:
        if not near(r.h,50):continue
        caps=[p for p in frontage if p.w<=72 and near(p.h,r.w) and near(p.y1,r.y0)
              and p.x0-TOL<=r.x0 and r.x1<=p.x1+TOL and any(
                  near(p.x1,f['box'][0]) or near(p.x0,f['box'][2]) for f in footprints)]
        if caps:returns[id(r)]=max(caps,key=lambda p:p.w)
    envelope=union([envelope]+[r.box() for r in extras]+[p.box() for p in returns.values()])
    def part(box,identity,handles):
        x0,y0,x1,y1=box
        return {'id':identity,'origin':[round(x0-envelope[0],3),round(y0-envelope[1],3),0],
                'size':[round(x1-x0,3),round(y1-y0,3),PLAN_HEIGHT_MM],
                'source_box':box,'plan_box':box,'handles':sorted(set(handles)),
                'height_source':'provisional_default','rule':'plan-only-1600-v1'}
    modules=[dict(part(p['box'],f'M{i+1:02}',p['handles']),name=f'Khoang mặt bằng {i+1:02}',scope='carcass_and_doors',
                  explanation='Rộng, sâu và vị trí từ mặt bằng; cao tạm 1600 mm, chưa chia tầng ngang.') for i,p in enumerate(footprints)]
    for mod,footprint in zip(modules,footprints):
        if 'plan_profile' in footprint:
            mod['plan_profile']=footprint['plan_profile']
            mod['explanation']=('Khối có hậu giật cấp theo biên kín CAD; không lấp phần lõm, cao tạm 1600 mm.' if footprint.get('stepped_rear') else
                                'Khối cuối bo theo biên ngoài mặt bằng; cung tròn đo từ CAD, cao tạm 1600 mm.')
            if footprint.get('stepped_rear'):mod['rule']='plan-stepped-rear-v1'
    if overlapping_modules(modules):
        raise ValueError('Các khoang mặt bằng chồng lấn; cần kiểm tra đường chia trước khi dựng.')
    trims=[]
    for i,r in enumerate(extras):
        trim=dict(part(r.box(),f'T{i+1:02}',[r.handle]),role='plan_auxiliary',solid_proxy=True,face_width_mm=round(r.w,3),
                  stock_thickness_mm=round(r.w,3),explanation='Phần phụ đo từ mặt bằng; cao tạm 1600 mm.')
        if near(r.h,50):
            adjacent=[(j,p) for j,p in enumerate(footprints) if
                      (near(r.x1,p['box'][0]) or near(r.x0,p['box'][2])) and
                      (near(r.y0,p['box'][1]) or near(r.y1,p['box'][3]) or
                       near(r.y0,p.get('carcass_box',p['box'])[1]) or near(r.y1,p.get('carcass_box',p['box'])[3]))]
            planes={(round(p['box'][1],3),round(p['box'][3],3)) for _,p in adjacent}
            if len(planes)!=1:
                raise ValueError('Nẹp sâu 50 mm chưa ghép được duy nhất mặt trước/sau của tủ bên cạnh.')
            front,back=next(iter(planes))
            trim['origin'][1]=round(front-envelope[1],3)
            trim['size'][1]=round(back-front,3)
            trim.update(name=f'Nẹp bù sâu {i+1:02}',solid_proxy=True,original_depth_mm=round(r.h,3),
                        rule='plan-short-trim-full-depth-v1',
                        depth_evidence={'basis':'user_confirmed_50mm_trim_to_cabinet_depth',
                                        'module_ids':[f'M{j+1:02}' for j,_ in adjacent],
                                        'cabinet_front':front,'cabinet_back':back},
                        explanation=f'Nẹp CAD sâu 50 mm; theo yêu cầu người dùng, khối phụ dựng sâu {trim["size"][1]:g} mm bằng tủ; cao tạm 1600 mm.')
            if id(r) in returns:
                cap=returns[id(r)]
                trim['origin'][0]=round(cap.x0-envelope[0],3)
                trim['size'][0]=round(cap.w,3)
                trim['face_width_mm']=round(cap.w,3)
                trim['front_return_box']=cap.box()
                trim['handles']=sorted(set(trim['handles']+[cap.handle]))
                trim['explanation']+=' Rộng khối phụ lấy cả bản nẹp ngang phía trước đo được trên CAD.'
        trims.append(trim)
    pipeline.update(mode='plan_only',order=['vertical_from_plan'],vertical={'view_id':plan['id'],'columns':bays},
                    default_height_mm=PLAN_HEIGHT_MM)
    if any(p.get('stepped_rear') for p in footprints):
        pipeline['measured_stepped_footprints']=[dict(box=p['box'],profile=p['plan_profile']) for p in footprints if p.get('stepped_rear')]
    return {'modules':modules,'trim_parts':trims,'panel_parts':[],
            'bounds':[round(envelope[2]-envelope[0],3),round(envelope[3]-envelope[1],3),PLAN_HEIGHT_MM],
            'envelope':envelope,'source_plan_envelope':union([envelope]+[[*p,*p] for o in plan['outlines'] for p in o['points']]),
            'default_height_mm':PLAN_HEIGHT_MM,'height_source':'provisional_default',
            'signature':geometry_signature(plan['rects'],envelope,plan['outlines']),
            'explanation':['Giai đoạn Mặt bằng: chỉ đo rộng, sâu và vị trí từ hình học mặt bằng.',
                           'Tất cả khối cao tạm 1600 mm, đặt Z=0; chưa đọc chiều cao hoặc chia tầng theo mặt đứng.']}
