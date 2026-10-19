"""AI retrieves examples; measured CAD anchors and physical checks own geometry."""
from copy import deepcopy
from itertools import product as combinations, islice
import hashlib
import json
import math

from geometry import Rect, TOL, inside, union, overlapping_modules
from learning import valid_state, plan_event_offset
from library import VERSION, atomic_json
from materials import BOARD_MM
from plan_learning import digest, example, fit, infer, KINDS
from stages import plan_runs, recognise_plan
from views import plan_columns
from plan_profiles import stepped_bay, check_stepped_footprints


def frame(product):
    selected=product.get('geometry_pipeline',{}).get('vertical',{}).get('view_id')
    plans=[v for v in product.get('views',[]) if v['role']=='plan' and (not selected or v['id']==selected)]
    if len(plans)!=1:raise ValueError('Cần xác định một mặt bằng trước khi AI tìm mẫu.')
    view=plans[0]
    outlines=[o for o in product.get('outlines',[]) if o.get('points') and all(inside([*p,*p],view['region']) for p in o['points'])]
    if not outlines:raise ValueError('Không có cạnh CAD để kiểm tra phương án AI.')
    envelope=product.get('source_plan_envelope') or union([[*p,*p] for o in outlines for p in o['points']])
    rects=[r for r in product.get('rectangles',[]) if inside(r['box'],view['region'])]
    return dict(view=view,envelope=envelope,size=[envelope[i+2]-envelope[i] for i in (0,1)],rects=rects,outlines=outlines)


def bays(product):
    data=frame(product)
    columns=product.get('geometry_pipeline',{}).get('vertical',{}).get('columns')
    if not columns:
        rects=[Rect(*r['box'],r.get('handle',''),'2 cat nt') for r in data['rects']]
        runs=plan_runs(plan_columns(rects) or stepped_bay(rects,data['outlines']))
        columns=max(runs,key=lambda run:(sum(b['box'][2]-b['box'][0] for b in run),len(run)),default=[])
    return sorted(columns,key=lambda b:b['box'][0])


class Samples:
    """Latest accepted records, soft-ranked for paging, never filtered by family."""
    def __init__(self,root):
        self.root=root
        self.token=None
        self.rows=[]

    def refresh(self):
        files=sorted((self.root/'experiences').glob('*/*.json'))
        exclusions=sorted((self.root/'experience_exclusions').glob('*.json'))
        contents=[(p,p.read_bytes()) for p in files+exclusions]
        self.token=digest([(str(p.relative_to(self.root)),hashlib.sha256(raw).hexdigest()) for p,raw in contents]+[VERSION])
        excluded={p.stem for p in exclusions};latest={}
        for path,raw in contents:
            if path not in files:continue
            try:
                e=json.loads(raw);a=e['analysis']
                if (e.get('status')!='accepted' or e.get('id') in excluded or e.get('parser_version')!=VERSION
                        or e.get('signature')!=path.parent.name or not e.get('input_axes_ignored')
                        or a.get('build_stages',{}).get('elevation') is not False):continue
                if path.name>latest.get(e['signature'],('',None))[0]:latest[e['signature']]=(path.name,e)
            except (ValueError,KeyError,TypeError,AttributeError):continue
        self.rows=[]
        for _,event in sorted(latest.values(),key=lambda pair:pair[0],reverse=True):
            try:
                a=event['analysis'];state=event['after'];data=frame(a);offset=plan_event_offset(event,a)
                if (not valid_state(state) or len(offset)!=2 or any(type(v) not in (float,int) or not math.isfinite(v) or abs(v)>72 for v in offset)
                        or any(abs(p['origin'][2])>.1 for k in KINDS for p in state.get(k,[]))):continue
                partial=bool(event.get('scope',{}).get('partial_sample'))
                if not partial and any(abs(state['bounds'][i]-data['size'][i])>72+TOL for i in (0,1)):continue
                boards=board_rectangles(data['rects'],0)+board_rectangles(data['rects'],1)
                stocks=sorted({s for b in boards for s in BOARD_MM
                               if any(abs(b[i+2]-b[i]-s)<TOL for i in (0,1))})
                card=dict(id=f'S{len(self.rows)+1}',size=data['size'],modules=len(state['modules']),
                          auxiliary=len(state.get('trim_parts',[]))+len(state.get('panel_parts',[])),
                          curved=sum(any(s['type']=='arc' for s in p.get('plan_profile',{}).get('segments',[])) for k in KINDS for p in state.get(k,[])),
                          stocks=stocks,partial=partial,part_count=sum(len(state.get(k,[])) for k in KINDS),
                          parts=[[k,*[round(v,3) for v in p['origin'][:2]],*[round(v,3) for v in p['size'][:2]]]
                                 for k in KINDS for p in state.get(k,[])][:6])
                self.rows.append(dict(card=card,event=event,offset=offset,root=self.root))
            except (ValueError,KeyError,TypeError,IndexError,AttributeError):continue
        return self

    def page(self,target,mode='similar',seen=()):
        def score(row):
            c=row['card'];distance=sum(abs(math.log(max(c['size'][i],1)/max(target['size'][i],1))) for i in (0,1))
            if mode=='parts':distance=c['modules']*.2+distance*.1
            if mode=='curves':distance+=0 if c['curved'] else 10
            return distance
        return [r['card'] for r in sorted(self.rows,key=score) if r['card']['id'] not in seen][:8]


def target_card(product,cad):
    columns=bays(product)
    rects=frame(product)['rects'];boards=board_rectangles(rects,0)+board_rectangles(rects,1)
    stocks=sorted({s for b in boards for s in BOARD_MM if any(abs(b[i+2]-b[i]-s)<TOL for i in (0,1))})
    return dict(size=cad['size'],stocks=stocks,
                plate_evidence=dict(stock_counts=product.get('plan_evidence',{}).get('stock_counts',{}),
                    curved_plates=sum(p['kind']=='arc' for p in product.get('plan_evidence',{}).get('panels',[]))),
                stepped_footprints=[dict(box=[round(v-cad['base'][i%2],3) for i,v in enumerate(p['box'])],profile=p['profile'])
                    for p in product.get('geometry_pipeline',{}).get('measured_stepped_footprints',[])],
                bays=[[round(b['box'][i]-cad['base'][i%2],3) for i in range(4)] for b in columns],
                measured_auxiliary=[[p['origin'][:2],p['size'][:2]] for p in product.get('trim_parts',[])][:8],
                arcs=[{k:a[k] for k in ('center','radius','sweep')} for a in cad['arcs']])


def board_rectangles(rectangles,axis):
    """A recovered 36mm envelope must not erase two explicit touching 18mm walls."""
    other=1-axis
    boards=[r['box'] for r in rectangles if any(abs(r['box'][axis+2]-r['box'][axis]-s)<=TOL for s in BOARD_MM)
            and r['box'][other+2]-r['box'][other]>max(72,(r['box'][axis+2]-r['box'][axis])*3)]
    result=[]
    for box in boards:
        fragments=[b for b in boards if b is not box and abs(b[other]-box[other])<=TOL
            and abs(b[other+2]-box[other+2])<=TOL and b[axis]>=box[axis]-TOL and b[axis+2]<=box[axis+2]+TOL
            and b[axis+2]-b[axis]<box[axis+2]-box[axis]-TOL]
        reach=box[axis]
        for b in sorted(fragments,key=lambda p:p[axis]):
            if b[axis]>reach+TOL:break
            reach=max(reach,b[axis+2])
        if len(fragments)<2 or reach<box[axis+2]-TOL:result.append(box)
    return result


def physical_check(product,state,offset,cad):
    if not valid_state(state):raise ValueError('Kích thước, gốc hoặc biên cong của phương án không hợp lệ.')
    parts=[p for k in KINDS for p in state.get(k,[])]
    if len(parts)>64:raise ValueError('Phương án vượt 64 khối trong lượt AI ngắn; quét gọn từng phần.')
    if overlapping_modules(parts):raise ValueError('Phương án có khối đặc chồng nhau.')
    if any(abs(p['origin'][2])>.05 or abs(p['size'][2]-1600)>.05 for p in parts):
        raise ValueError('Phương án mặt bằng phải giữ cao tạm 1600 mm và Z=0.')
    if any(not math.isfinite(v) or abs(v)>72 for v in offset):raise ValueError('Gốc phương án vượt vùng CAD.')
    if any(abs(state['bounds'][i]+offset[i]-cad['size'][i])>72+TOL for i in (0,1)):
        raise ValueError('Phương án chưa bao phủ toàn bộ sản phẩm CAD.')
    check_stepped_footprints(product,parts,[cad['base'][i]+offset[i] for i in (0,1)])
    source=frame(product)
    walls=[board_rectangles(source['rects'],axis) for axis in (0,1)]
    for p in parts:
        if not p.get('handles'):raise ValueError('Mặt khối chưa có cạnh CAD đối chiếu.')
        for axis in (0,1):
            lo=p['origin'][axis]+offset[axis];hi=lo+p['size'][axis]
            other=1-axis;start=p['origin'][other]+offset[other];end=start+p['size'][other]
            for raw in walls[axis]:
                b=[raw[i]-cad['base'][i%2] for i in range(4)]
                if min(end,b[other+2])-max(start,b[other])<=TOL:continue
                if any(b[axis]+TOL<v<b[axis+2]-TOL for v in (lo,hi)):
                    raise ValueError('Đường chia xuyên qua một vách/tấm liền trên CAD.')
        for segment in p.get('plan_profile',{}).get('segments',[]):
            if segment['type']!='arc':continue
            center=[segment['center'][i]+p['origin'][i]+offset[i] for i in (0,1)]
            ends=[[segment[key][i]+p['origin'][i]+offset[i] for i in (0,1)] for key in ('start','end')]
            if not any(math.dist(a['center'],center)<.05 and abs(a['radius']-segment['radius'])<.05
                       and abs(abs(a['sweep'])-abs(segment['sweep']))<.001
                       and any(all(math.dist(x,y)<.05 for x,y in zip(ends,order)) for order in
                               ([a['start'],a['end']],[a['end'],a['start']])) for a in cad['arcs']):
                raise ValueError('Tâm/bán kính/góc quét không khớp cung CAD mới.')
    return dict(passed=True,checks=['finite_dimensions','no_solid_overlap','cad_walls','cad_arcs','source_frame','plan_height_1600'])


def bindings(sample,product,cad):
    """Map semantic seams/outer edges/arc centres, then nearby measured alternatives."""
    source=sample['cad'];src_bays=bays(sample['_analysis']);dst_bays=bays(product)
    seams=[]
    for axis in (0,1):
        left=sorted({round(b['box'][axis+j]-source['base'][axis],4) for b in src_bays for j in (0,2)})
        right=sorted({round(b['box'][axis+j]-cad['base'][axis],4) for b in dst_bays for j in (0,2)})
        seams.append((left,right))
    options=[]
    for axis in (0,1):
        values=[]
        for value in sample['planes'][axis]:
            refs=cad['refs'][axis]
            if abs(value)<=.05:desired=[0]
            elif abs(value-source['size'][axis])<=.05:desired=[cad['size'][axis]]
            else:
                arcs=[i for i,a in enumerate(source['arcs']) if abs(a['center'][axis]-value)<=.05]
                if arcs:
                    desired=[a['center'][axis] for i,a in enumerate(cad['arcs']) if i in arcs]
                else:
                    old,new=seams[axis]
                    matching=next((i for i,v in enumerate(old) if abs(v-value)<=.05),None)
                    desired=[new[matching]] if matching is not None and len(old)==len(new) else []
            if not desired:
                ratio=value/max(source['size'][axis],1)
                # Ratios only rank measured references; they never become coordinates.
                desired=sorted(set(refs.values()),key=lambda v:abs(v/max(cad['size'][axis],1)-ratio))[:3]
            choices=[]
            for wanted in desired:
                keys=[k for k,v in refs.items() if abs(v-wanted)<=.05]
                if keys:
                    key=min(keys,key=lambda k:0 if k.startswith('arc:') else 1 if k.startswith('edge:') else 2)
                    choices.append(dict(ref=key,delta=0))
            if not choices:raise ValueError('Chưa tìm được cạnh đo tương ứng trên CAD mới.')
            values.append(choices)
        options.append(values)
    return options


def compiled_sample(row):
    key=digest([2,VERSION,row['event']])
    path=row['root']/'rules'/'ai-plan-v2'/'samples'/f'{key}.json'
    try:
        saved=json.loads(path.read_text(encoding='utf8'))
        if saved.get('checksum')==digest(saved['sample']):return saved['sample']
    except (OSError,ValueError,TypeError,KeyError):pass
    sample=example(row['event'])
    atomic_json(path,dict(sample=sample,checksum=digest(sample)))
    return sample


def transferred(row,product,cad):
    event=row['event']
    if row['card']['partial']:return []
    sample=compiled_sample(row);sample['_analysis']=event['analysis']
    result=[]
    # Preserve already proven constant offsets when the exact construction fits.
    if sample['cad']['family']==cad['family']:
        try:
            state,offset=infer(fit([sample]),cad)
            result.append((state,offset,'measured_anchors'))
        except (ValueError,KeyError,TypeError,IndexError):pass
    choices=bindings(sample,product,cad)
    axes=[list(islice(combinations(*values),16)) for values in choices]
    for x,y in islice(combinations(*axes),24):
        try:
            program=dict(shape=deepcopy(sample['shape']),bindings=[[[c] for c in x],[[c] for c in y]])
            # Trim material is remeasured from target references, never scaled.
            for shape in program['shape']:
                if shape.get('stock'):
                    widths=[cad['refs'][i][program['bindings'][i][shape['hi'][i]][0]['ref']]-
                            cad['refs'][i][program['bindings'][i][shape['lo'][i]][0]['ref']] for i in (0,1)]
                    stock=next((s for _,_,s in cad['stocks'] if any(abs(w-s)<=TOL for w in widths)),None)
                    if stock:shape['stock']=stock
            state,offset=infer(program,cad)
            result.append((state,offset,'adapted_cad_anchors'))
        except (ValueError,KeyError,TypeError,IndexError):continue
    return result


def module_units(rows):
    units={}
    for row in rows:
        event=row['event'];columns=bays(event['analysis']);base=frame(event['analysis'])['envelope'][:2]
        for part in event['after']['modules']:
            lo=part['origin'][0]+row['offset'][0];hi=lo+part['size'][0]
            covered=[b for b in columns if lo-.05<=b['box'][0]-base[0] and b['box'][2]-base[0]<=hi+.05]
            if covered and abs(covered[0]['box'][0]-base[0]-lo)<.05 and abs(covered[-1]['box'][2]-base[0]-hi)<.05:
                units.setdefault(len(covered),[]).append(row['card']['id'])
    return units


def compositions(rows,product,cad,units=None):
    data=frame(product)
    try:
        measured=recognise_plan([dict(data['view'],rects=[Rect(*r['box'],r.get('handle',''),'2 cat nt') for r in data['rects']],
                                     outlines=data['outlines'])],{})
    except ValueError:return []
    modules=sorted(measured['modules'],key=lambda p:p['origin'][0])
    if not 1<=len(modules)<=12:return []
    units=module_units(rows) if units is None else units
    paths=[[]]
    for _ in modules:
        done=[p for p in paths if sum(p)==len(modules)]
        paths=done+[p+[n] for p in paths if sum(p)<len(modules) for n in sorted(units) if sum(p)+n<=len(modules)]
        paths=paths[:12]
    result=[]
    envelope=measured['envelope'];offset=[envelope[i]-cad['base'][i] for i in (0,1)]
    for path in paths:
        if sum(path)!=len(modules):continue
        state={k:deepcopy(measured.get(k,[])) for k in KINDS};state['bounds']=deepcopy(measured['bounds']);state['modules']=[]
        index=0;used=[]
        for count in path:
            group=modules[index:index+count];index+=count;used.extend(units[count])
            if len(group)==1:part=deepcopy(group[0])
            else:
                if any(p.get('plan_profile') for p in group):break
                if any(abs(p['origin'][1]-group[0]['origin'][1])>.05 or abs(p['size'][1]-group[0]['size'][1])>.05 for p in group):break
                if any(abs(a['origin'][0]+a['size'][0]-b['origin'][0])>.05 for a,b in zip(group,group[1:])):break
                part=deepcopy(group[0]);part['size'][0]=group[-1]['origin'][0]+group[-1]['size'][0]-part['origin'][0]
                part['handles']=sorted({h for p in group for h in p.get('handles',[])})
            part['id']=f'M{len(state["modules"])+1}'
            part['source_box']=[cad['base'][i]+offset[i]+part['origin'][i] for i in (0,1)]+[
                cad['base'][i]+offset[i]+part['origin'][i]+part['size'][i] for i in (0,1)]
            part['plan_box']=list(part['source_box']);state['modules'].append(part)
        else:
            result.append((state,offset,'composed_measured_bays',sorted(set(used))))
    return result


def proposals(product,cad,rows):
    options=[];rejected=[];seen={};units=module_units(rows);columns=bays(product)
    def evaluate(state,offset):
        spans=[];partial=0
        for part in state['modules']:
            lo=cad['base'][0]+offset[0]+part['origin'][0];hi=lo+part['size'][0]
            covered=[b for b in columns if lo-.05<=b['box'][0] and b['box'][2]<=hi+.05]
            spans.append(len(covered))
            partial+=sum(b['box'][0]+.15<v<b['box'][2]-.15 for b in columns for v in (lo,hi))
        mismatch=sum(n not in units for n in spans) if units else 0
        measured=[]
        for p in product.get('trim_parts',[]):
            measured.append([product['envelope'][i]+p['origin'][i] for i in (0,1)]+p['size'][:2])
        actual=[[cad['base'][i]+offset[i]+p['origin'][i] for i in (0,1)]+p['size'][:2]
                for kind in ('trim_parts','panel_parts') for p in state.get(kind,[])]
        missing=sum(not any(all(abs(a-b)<.05 for a,b in zip(m,part)) for part in actual) for m in measured)
        return dict(module_bay_spans=spans,partial_bay_cuts=partial,example_module_spans=sorted(units),
                    missing_measured_auxiliary=missing,structure_score=max(0,100-30*partial-20*mismatch-20*missing),
                    note='Soft grouping evidence only; different examples may be adapted.')
    def add(state,offset,method,ids):
        try:
            checks=physical_check(product,state,offset,cad)
            key=digest([[round(float(v),4) for v in offset],[[k,[round(float(v),4) for v in p['origin']],
                [round(float(v),4) for v in p['size']],p.get('plan_profile')] for k in KINDS for p in state.get(k,[])]])
            if key in seen:return
            candidate=dict(id='learned' if not options else f'P{len(options)+1}',state=state,offset=offset,
                           method=method,samples=ids,checks=checks,evaluation=evaluate(state,offset))
            options.append(candidate);seen[key]=candidate
        except (ValueError,KeyError,TypeError,IndexError) as error:
            rejected.append(dict(samples=ids,method=method,reason=str(error)))
    for row in rows:
        try:
            for state,offset,method in transferred(row,product,cad):add(state,offset,method,[row['card']['id']])
        except (ValueError,KeyError,TypeError,IndexError) as error:
            rejected.append(dict(samples=[row['card']['id']],reason=str(error)))
    for state,offset,method,ids in compositions(rows,product,cad,units):add(state,offset,method,ids)
    if product.get('status')=='ready':
        state={k:deepcopy(product.get(k,[])) for k in KINDS};state['bounds']=deepcopy(product['bounds'])
        offset=[product['envelope'][i]-cad['base'][i] for i in (0,1)]
        try:
            checks=physical_check(product,state,offset,cad)
            options.append(dict(id='baseline',state=state,offset=offset,method='cad_recognizer',samples=[],checks=checks,
                                evaluation=evaluate(state,offset)))
        except (ValueError,KeyError,TypeError,IndexError) as error:rejected.append(dict(method='cad_recognizer',reason=str(error)))
    baseline=[c for c in options if c['id']=='baseline']
    return [c for c in options if c['id']!='baseline'][:7]+baseline,rejected[:12]
