"""Automatically induce bounded, measured plan-anchor rules from accepted examples."""
from copy import deepcopy
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math

from geometry import TOL, Rect, inside, union, overlapping_modules
from library import VERSION, atomic_json
from materials import BOARD_MM
from plan_profiles import arc_runs
from learning import pattern, levels, valid_state, plan_event_offset

SCHEMA = 4
MIN_EXAMPLES = 3
MAX_DELTA = 36.0
KINDS = ('modules', 'trim_parts', 'panel_parts')


class RuleError(ValueError):
    pass


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def circles(outlines):
    return arc_runs(outlines)


def features(product):
    plans=[v for v in product.get('views',[]) if v['role']=='plan']
    selected=product.get('geometry_pipeline',{}).get('vertical',{}).get('view_id')
    plans=[v for v in plans if v['id']==selected] if selected else plans
    if len(plans)!=1:raise RuleError('Cần một mặt bằng được xác định rõ để rút quy tắc.')
    view=plans[0]
    outlines=[o for o in product.get('outlines',[]) if o.get('points') and all(inside([*p,*p],view['region']) for p in o['points'])]
    if not outlines:raise RuleError('Mẫu thiếu các cạnh CAD nguồn.')
    envelope=product.get('source_plan_envelope') or union([[*p,*p] for o in outlines for p in o['points']])
    base=envelope[:2]
    shifted=[dict(o,layer='2 cat nt',points=[[p[i]-base[i] for i in (0,1)] for p in o['points']]) for o in outlines]
    rects=[Rect(*[r['box'][i]-base[i%2] for i in range(4)],r.get('handle',''), '2 cat nt')
           for r in product.get('rectangles',[]) if inside(r['box'],view['region'])]
    arcs=circles(shifted)
    # Chord tessellation is display detail. Compare analytic arc endpoints instead
    # of letting intermediate chord vertices change construction topology.
    arc_edges={edge for arc in arcs for edge in arc['source_edges']}
    reduced=[]
    for o in shifted:
        for a,b in zip(o['points'],o['points'][1:]):
            edge=tuple(sorted((tuple(round(v,3) for v in a),tuple(round(v,3) for v in b))))
            if edge not in arc_edges:reduced.append(dict(o,points=[a,b]))
    reduced.extend(dict(handle='arc',layer='2 cat nt',points=[a['start'],a['end']]) for a in arcs)
    graph=pattern(dict(view,rects=rects,outlines=reduced))
    if not graph:raise RuleError('Chưa đủ cạnh/tấm để nhận cấu tạo mặt bằng.')
    stocks=[];refs=[{},{}];proof=[{},{}]
    for axis in (0,1):
        for i,value in enumerate(graph['axes'][axis]):
            key=f'edge:{i}';refs[axis][key]=value
            proof[axis][key]=sorted({o['handle'] for o in shifted if any(abs(p[axis]-value)<=TOL for p in o['points'])})
    for i,row in enumerate(graph['rows']):
        box=row['box'];width=box[2]-box[0];depth=box[3]-box[1]
        for axis,thickness in enumerate((width,depth)):
            stock=next((s for s in BOARD_MM if abs(s-thickness)<=TOL),None)
            if stock:
                stocks.append([i,axis,stock])
                key=f'centre:{i}';refs[axis][key]=(box[axis]+box[axis+2])/2;proof[axis][key]=[row['handle']]
    arc_topology=[]
    for i,arc in enumerate(arcs):
        entry=[]
        for axis in (0,1):
            key=f'arc:{i}';refs[axis][key]=arc['center'][axis];proof[axis][key]=arc['handles']
            entry.extend(min(range(len(graph['axes'][axis])),key=lambda j:abs(graph['axes'][axis][j]-arc[p][axis])) for p in ('start','end'))
        arc_topology.append([entry,round(abs(arc['sweep']),3)])
    family=digest([graph['fingerprint'],stocks,arc_topology])
    return dict(family=family,refs=refs,proof=proof,arcs=arcs,stocks=stocks,
                envelope=envelope,base=base,size=[envelope[i+2]-envelope[i] for i in (0,1)])


def canonical_profile(profile):
    segments=deepcopy(profile['segments'])
    points=[s['start'] for s in segments]
    area=sum(p[0]*q[1]-q[0]*p[1] for p,q in zip(points,points[1:]+points[:1]))
    if area<0:
        segments.reverse()
        for s in segments:
            s['start'],s['end']=s['end'],s['start']
            if s['type']=='arc':s['sweep']=-s['sweep']
    start=min(range(len(segments)),key=lambda i:tuple(round(v,3) for v in segments[i]['start']))
    return segments[start:]+segments[:start]


def example(event):
    analysis=event['analysis'];state=deepcopy(event['after']);cad=features(analysis)
    if not valid_state(state):raise RuleError('Kết quả đúng có kích thước hoặc biên dạng không hợp lệ.')
    offset=plan_event_offset(event,analysis)
    if not isinstance(offset,list) or len(offset)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>72 for v in offset):raise RuleError('Gốc mẫu chưa liên kết được với CAD nguồn.')
    if any(abs(state['bounds'][i]-cad['size'][i])>72+TOL for i in (0,1)):raise RuleError('Kích thước kết quả không khớp toàn bộ CAD nguồn.')
    parts=[];values=[[],[]]
    for kind in KINDS:
        for p in sorted(state.get(kind,[]),key=lambda p:p['origin']+p['size']):
            if abs(p['origin'][2])>.1 or p.get('panel_parts') or p.get('profile'):raise RuleError('Chỉ học khối mặt bằng đùn thẳng, chưa học chia tầng hoặc tấm lồng.')
            lo=[p['origin'][i]+offset[i] for i in (0,1)];hi=[lo[i]+p['size'][i] for i in (0,1)]
            shape=dict(kind=kind,lo=lo,hi=hi)
            shape['stock']=p.get('stock_thickness_mm')
            if p.get('plan_profile'):
                shape['profile']=canonical_profile(p['plan_profile'])
                for s in shape['profile']:
                    for field in ('start','end','center'):
                        if field in s:
                            s[field]=[s[field][i]+lo[i] for i in (0,1)]
                            for i in (0,1):values[i].append(s[field][i])
            for i in (0,1):values[i].extend([lo[i],hi[i]])
            parts.append(shape)
    planes=[levels(v) for v in values]
    def node(value,axis):return min(range(len(planes[axis])),key=lambda i:abs(planes[axis][i]-value))
    shape=[]
    for part in parts:
        p=deepcopy(part)
        p['lo']=[node(part['lo'][i],i) for i in (0,1)];p['hi']=[node(part['hi'][i],i) for i in (0,1)]
        for segment in p.get('profile',[]):
            for field in ('start','end','center'):
                if field in segment:segment[field]=[node(segment[field][i],i) for i in (0,1)]
            if segment['type']=='arc':
                segment['sweep']=round(segment['sweep'],6)
                segment.pop('radius',None)
                segment['segments']=max(12,segment['segments'])
        shape.append(p)
    # Segment count affects display only; it is not a construction rule.
    signature=deepcopy(shape)
    for p in signature:
        for s in p.get('profile',[]):s.pop('segments',None)
    return dict(id=event['id'],code=analysis.get('code',''),signature=event['signature'],cad=cad,planes=planes,shape=shape,
                shape_key=digest(signature),expected=state,offset=offset)


def fit(samples):
    shape=samples[0]['shape']
    if len({s['shape_key'] for s in samples})!=1:raise RuleError('Các mẫu cùng cấu tạo đang có cách chia/nhóm khối khác nhau.')
    bindings=[[],[]]
    for axis in (0,1):
        for index,value in enumerate(samples[0]['planes'][axis]):
            choices=[]
            for key,anchor in samples[0]['cad']['refs'][axis].items():
                deltas=[]
                for s in samples:
                    if index>=len(s['planes'][axis]) or key not in s['cad']['refs'][axis]:break
                    deltas.append(s['planes'][axis][index]-s['cad']['refs'][axis][key])
                if len(deltas)==len(samples) and max(abs(v) for v in deltas)<=MAX_DELTA+TOL and max(deltas)-min(deltas)<=.02:
                    choices.append(dict(ref=key,delta=round(sum(deltas)/len(deltas),6)))
            if not choices:raise RuleError('Có mặt chia chưa gắn được vào cạnh/tâm tấm CAD bằng một quy tắc ổn định.')
            bindings[axis].append(choices)
    return dict(shape=shape,bindings=bindings)


def infer(program,cad):
    axes=[];evidence=[]
    for axis in (0,1):
        values=[];proofs=[]
        for choices in program['bindings'][axis]:
            results=[cad['refs'][axis][c['ref']]+c['delta'] for c in choices if c['ref'] in cad['refs'][axis]]
            if len(results)!=len(choices) or max(results)-min(results)>.05:raise RuleError('Các cạnh đối chiếu cho nhiều vị trí chia khác nhau; cần xác nhận thêm mẫu.')
            values.append(sum(results)/len(results))
            proofs.append([dict(c,handles=cad['proof'][axis].get(c['ref'],[])) for c in choices])
        if any(b-a<=TOL for a,b in zip(values,values[1:])):raise RuleError('Thứ tự mặt chia đã thay đổi; không kéo giãn mẫu cũ.')
        axes.append(values);evidence.append(proofs)
    offset=[min(axes[i][p['lo'][i]] for p in program['shape']) for i in (0,1)]
    if any(abs(v)>72+TOL for v in offset):raise RuleError('Gốc suy rộng vượt phạm vi phần phụ cho phép.')
    state={k:[] for k in KINDS}
    for shape in program['shape']:
        lo=[axes[i][shape['lo'][i]] for i in (0,1)];hi=[axes[i][shape['hi'][i]] for i in (0,1)]
        kind=shape['kind'];identity=('M' if kind=='modules' else 'T' if kind=='trim_parts' else 'P')+str(len(state[kind])+1)
        p=dict(id=identity,name='Module theo quy tắc tự học' if kind=='modules' else 'Phần phụ theo quy tắc tự học',
               origin=[round(lo[i]-offset[i],4) for i in (0,1)]+[0],size=[round(hi[i]-lo[i],4) for i in (0,1)]+[1600],
               rule='learned-plan-anchors-v1',height_source='provisional_default',
               anchor_evidence={f'{"XY"[i]}{side}':evidence[i][shape[key][i]] for i in (0,1) for side,key in ((0,'lo'),(1,'hi'))})
        if kind=='trim_parts':p.update(role='manual_auxiliary',solid_proxy=True,stock_thickness_mm=shape.get('stock'),face_width_mm=p['size'][0])
        if shape.get('stock') and min(abs(p['size'][i]-shape['stock']) for i in (0,1))>TOL:raise RuleError('Độ dày phần phụ suy rộng khác ván trong mẫu.')
        if 'profile' in shape:
            segments=deepcopy(shape['profile'])
            for segment in segments:
                absolute={}
                for field in ('start','end','center'):
                    if field in segment:
                        absolute[field]=[axes[i][segment[field][i]] for i in (0,1)]
                        segment[field]=[absolute[field][i]-lo[i] for i in (0,1)]
                if segment['type']=='arc':
                    segment['radius']=math.dist(segment['start'],segment['center'])
                    if not any(math.dist(a['center'],absolute['center'])<.05 and abs(a['radius']-segment['radius'])<.05 and abs(abs(a['sweep'])-abs(segment['sweep']))<.001 for a in cad['arcs']):
                        raise RuleError('Góc bo suy rộng chưa có cung tròn CAD xác nhận tâm/bán kính.')
            p['plan_profile']=dict(schema=1,segments=segments)
        p['handles']=sorted({h for refs in p['anchor_evidence'].values() for ref in refs for h in ref['handles']})
        p['source_box']=[cad['base'][0]+lo[0],cad['base'][1]+lo[1],cad['base'][0]+hi[0],cad['base'][1]+hi[1]]
        p['plan_box']=list(p['source_box'])
        state[kind].append(p)
    parts=[p for k in KINDS for p in state[k]]
    state['bounds']=[round(max(p['origin'][i]+p['size'][i] for p in parts),4) for i in range(3)]
    if not valid_state(state) or overlapping_modules(parts):raise RuleError('Kết quả suy rộng bị chồng lấn hoặc biên cong chưa hợp lệ.')
    if any(abs(state['bounds'][i]-cad['size'][i])>72+TOL for i in (0,1)):raise RuleError('Kết quả suy rộng không khớp giới hạn CAD nguồn.')
    return state,[round(v,4) for v in offset]


def matches(state,offset,sample):
    for kind in KINDS:
        expected=sorted(sample['expected'].get(kind,[]),key=lambda p:p['origin']+p['size'])
        actual=state[kind]
        if len(actual)!=len(expected):return False
        for a,b in zip(actual,expected):
            if any(abs(a['origin'][i]+offset[i]-b['origin'][i]-sample['offset'][i])>.05 for i in (0,1)):return False
            if any(abs(a['size'][i]-b['size'][i])>.05 for i in (0,1)):return False
            if bool(a.get('plan_profile'))!=bool(b.get('plan_profile')):return False
            if a.get('plan_profile'):
                left=canonical_profile(a['plan_profile']);right=canonical_profile(b['plan_profile'])
                if len(left)!=len(right):return False
                for x,y in zip(left,right):
                    if x['type']!=y['type']:return False
                    if x['type']=='arc' and (abs(x['radius']-y['radius'])>.05 or abs(x['sweep']-y['sweep'])>.001):return False
                    for key in ('start','end','center'):
                        if key in x and math.dist(x[key],y[key])>.05:return False
    return True


class PlanRuleLibrary:
    def __init__(self,root):
        self.root=root;self.folder=root/'rules'/'plan-v1';self.catalog=None
        self._measurements={}

    def measured_features(self,product):
        # Per-worker reuse only. Hash the actual measurement inputs rather than
        # trusting a product code or an old signature after edits/translation.
        key=digest([product.get('views'),product.get('rectangles'),product.get('outlines'),
                    product.get('source_plan_envelope'),
                    product.get('geometry_pipeline',{}).get('vertical',{}).get('view_id')])
        if key not in self._measurements:
            cad=features(product)
            if len(self._measurements)>=8:self._measurements.pop(next(iter(self._measurements)))
            self._measurements[key]=cad
        return self._measurements[key]

    def refresh(self):
        files=sorted((self.root/'experiences').glob('*/*.json'))
        exclusions=sorted((self.root/'experience_exclusions').glob('*.json'))
        contents=[]
        for p in files+exclusions:
            try:contents.append((p,p.read_bytes()))
            except OSError:continue
        source_digest=digest([(str(p.relative_to(self.root)),hashlib.sha256(b).hexdigest()) for p,b in contents]+[('schema',SCHEMA),('parser_version',VERSION)])
        try:
            saved=json.loads((self.folder/'catalog.json').read_text(encoding='utf-8'))
            checksum=saved.pop('checksum')
            if saved.get('source_digest')==source_digest and digest(saved)==checksum:
                self.catalog=saved
                try:status=json.loads((self.folder/'status.json').read_text(encoding='utf8'))
                except (OSError,ValueError):status=None
                if status!=saved['summary']:atomic_json(self.folder/'status.json',saved['summary'])
                return saved['summary']
        except (OSError,ValueError,KeyError,TypeError):pass
        latest={};invalid=[]
        excluded={p.stem for p in exclusions}
        for p,raw in contents:
            if p not in files:continue
            try:
                event=json.loads(raw)
                if event.get('status')!='accepted' or event.get('signature')!=p.parent.name or event.get('id') in excluded:continue
                if event.get('analysis',{}).get('build_stages',{}).get('elevation') is not False:continue
                current=latest.get(event['signature'])
                if current is None or p.name>current[0]:latest[event['signature']]=(p.name,event)
            except (ValueError,TypeError,KeyError,AttributeError):invalid.append(dict(file=str(p.relative_to(self.root)),reason='Hồ sơ mẫu hỏng.'))
        groups=defaultdict(list)
        for _,event in latest.values():
            try:
                if event.get('parser_version')!=VERSION or not event.get('input_axes_ignored'):raise RuleError('Mẫu cũ chưa có xác nhận khối mặt bằng theo luồng hiện tại.')
                if event.get('scope',{}).get('partial_sample'):raise RuleError('Mẫu đã xác nhận còn thiếu bộ phận.')
                sample=example(event)
                groups[sample['cad']['family']].append(sample)
            except (ValueError,KeyError,TypeError,IndexError,AttributeError) as error:
                invalid.append(dict(event=event.get('id'),reason=str(error)))
        candidates=[]
        for family,samples in sorted(groups.items()):
            candidate=dict(id=family,status='waiting',examples=[s['id'] for s in samples],signatures=[s['signature'] for s in samples],
                           sources=[dict(event=s['id'],code=s['code'],size=s['cad']['size']) for s in samples],
                           tested=0,passed=0,reason=f'Cần ít nhất {MIN_EXAMPLES} hình học khác nhau cùng cấu tạo; đang có {len(samples)}.')
            try:
                if len({s['shape_key'] for s in samples})!=1:raise RuleError('Các mẫu cùng cấu tạo có cách chia/nhóm khác nhau; chưa kích hoạt.')
                if len(samples)>=MIN_EXAMPLES:
                    candidate['status']='blocked'
                    for i,held in enumerate(samples):
                        candidate['tested']+=1
                        program=fit(samples[:i]+samples[i+1:])
                        state,offset=infer(program,held['cad'])
                        if not matches(state,offset,held):raise RuleError('Quy tắc không dựng khớp mẫu được giữ riêng để kiểm thử.')
                        candidate['passed']+=1
                    candidate.update(status='active',program=fit(samples),reason='Đã vượt kiểm thử giữ riêng từng hình học; từng mặt sẽ được đo lại trên CAD mới.')
            except (ValueError,KeyError,TypeError,IndexError) as error:candidate.update(status='blocked',reason=str(error))
            candidates.append(candidate)
        summary=dict(schema=SCHEMA,updated_at=datetime.now(timezone.utc).isoformat(),examples=len(latest),
                     active=sum(c['status']=='active' for c in candidates),waiting=sum(c['status']=='waiting' for c in candidates),
                     blocked=sum(c['status']=='blocked' for c in candidates)+len(invalid),minimum_examples=MIN_EXAMPLES,
                     rules=[{k:v for k,v in c.items() if k!='program'} for c in candidates],issues=invalid)
        catalog=dict(schema=SCHEMA,source_digest=source_digest,candidates=candidates,summary=summary)
        checksum=digest(catalog);stored=dict(catalog,checksum=checksum)
        atomic_json(self.folder/'catalog.json',stored)
        revision=self.folder/'revisions'/f'{checksum}.json'
        if not revision.exists():atomic_json(revision,stored)
        atomic_json(self.folder/'status.json',summary)
        self.catalog=catalog
        return summary

    def apply(self,product):
        self.refresh()
        try:cad=self.measured_features(product)
        except (ValueError,TypeError,KeyError,IndexError):return False
        candidate=next((c for c in self.catalog['candidates'] if c['id']==cad['family']),None)
        if not candidate:return False
        if candidate['status']!='active':
            product['plan_rule_note']=candidate['reason']
            return False
        try:
            state,offset=infer(candidate['program'],cad)
        except (ValueError,TypeError,KeyError,IndexError) as error:
            product.update(status='needs_review',error=f'Quy tắc tự học cần kiểm tra: {error}',modules=[])
            product['learning']=dict(mode='review',rule=candidate['id'],message=product['error'])
            return False
        product.update(state,status='ready',height_source='provisional_default',default_height_mm=1600,
                       plan_origin_offset_mm=offset,plan_origin_basis='source_plan_envelope')
        product.pop('error',None)
        product['learning']=dict(mode='plan_rule',rule=candidate['id'],examples=candidate['examples'],
                                 tested=candidate['tested'],passed=candidate['passed'],
                                 message=f"Quy tắc tự học từ {len(candidate['examples'])} hình học đã xác nhận; cao tạm 1600 mm.")
        product.setdefault('explanation',[]).append(product['learning']['message'])
        return True
