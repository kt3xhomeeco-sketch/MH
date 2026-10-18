"""User-selected construction stages. Plan preview height is explicitly provisional."""
from geometry import Rect, TOL, near, union, inside, gap_boxes, geometry_signature, overlapping_modules
from materials import BOARD_MM
from views import plan_columns
from plan_profiles import curved_ends
import math

PLAN_HEIGHT_MM = 1600


def source_placement(product,geometry):
    if product.get('status')!='ready':return
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


def requested_stages(request):
    if request.get('build_plan',True) is not True:
        raise ValueError('Chọn giai đoạn Mặt bằng trước khi dựng; Mặt đứng dùng kèm Mặt bằng.')
    return {'plan':True,'elevation':request.get('build_elevation',False) is True}


def infer_plan_views(rects,outlines):
    """A selected standalone plan needs no elevation to establish its role."""
    remaining=set(range(len(rects)));views=[]
    while remaining:
        stack=[remaining.pop()];group=[]
        while stack:
            i=stack.pop();group.append(rects[i])
            for j in list(remaining):
                if max(gap_boxes(rects[i].box(),rects[j].box()))<=60:
                    remaining.remove(j);stack.append(j)
        bays=plan_columns(group)
        if not bays or any(not 100<=b['box'][3]-b['box'][1]<=1200 for b in bays):continue
        box=union([r.box() for r in group])
        if box[3]-box[1]>1200:continue
        views.append({'id':f'P{len(views)+1:02}','role':'plan','title':'Mặt bằng từ vùng quét',
                      'region':box,'rects':group,'outlines':[o for o in outlines if o['points'] and
                      all(inside([*p,*p],box) for p in o['points'])]})
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
        runs=plan_runs(plan_columns(view['rects']))
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
        footprints.append({'box':[x0,front,x1,y1],'handles':bay['handles']+[r.handle for r in doors]})
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
    envelope=union([envelope]+[r.box() for r in extras])
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
            mod['explanation']='Khối cuối bo theo biên ngoài mặt bằng; cung tròn đo từ CAD, cao tạm 1600 mm.'
    if overlapping_modules(modules):
        raise ValueError('Các khoang mặt bằng chồng lấn; cần kiểm tra đường chia trước khi dựng.')
    trims=[]
    for i,r in enumerate(extras):
        trim=dict(part(r.box(),f'T{i+1:02}',[r.handle]),role='plan_auxiliary',solid_proxy=True,face_width_mm=round(r.w,3),
                  stock_thickness_mm=round(r.w,3),explanation='Phần phụ đo từ mặt bằng; cao tạm 1600 mm.')
        if near(r.h,50):
            adjacent=[(j,p) for j,p in enumerate(footprints) if
                      (near(r.x1,p['box'][0]) or near(r.x0,p['box'][2])) and
                      (near(r.y0,p['box'][1]) or near(r.y1,p['box'][3]))]
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
        trims.append(trim)
    pipeline.update(mode='plan_only',order=['vertical_from_plan'],vertical={'view_id':plan['id'],'columns':bays},
                    default_height_mm=PLAN_HEIGHT_MM)
    return {'modules':modules,'trim_parts':trims,'panel_parts':[],
            'bounds':[round(envelope[2]-envelope[0],3),round(envelope[3]-envelope[1],3),PLAN_HEIGHT_MM],
            'envelope':envelope,'source_plan_envelope':union([[*p,*p] for o in plan['outlines'] for p in o['points']]) if plan['outlines'] else envelope,
            'default_height_mm':PLAN_HEIGHT_MM,'height_source':'provisional_default',
            'signature':geometry_signature(plan['rects'],envelope,plan['outlines']),
            'explanation':['Giai đoạn Mặt bằng: chỉ đo rộng, sâu và vị trí từ hình học mặt bằng.',
                           'Tất cả khối cao tạm 1600 mm, đặt Z=0; chưa đọc chiều cao hoặc chia tầng theo mặt đứng.']}
