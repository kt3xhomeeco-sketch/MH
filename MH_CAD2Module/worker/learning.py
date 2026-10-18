"""Transfer accepted box layouts through measured construction-edge correspondence.

This is deliberately a topology-preserving rule learner, not a shape resizer.
Every output plane must resolve to a target CAD edge or thin-panel centre.
"""
from __future__ import annotations

from copy import deepcopy
from bisect import bisect_left
from collections import Counter
import hashlib
import json
import math
import re

from geometry import TOL, Rect, inside, overlapping_modules
from library import VERSION, atomic_json
from materials import BOARD_MM
from views import normalise, recovered_rects
from plan_profiles import valid_profile

RULE_SCHEMA = 3
KINDS = ('modules', 'trim_parts', 'panel_parts')


def plan_event_offset(event,product):
    """Translate legacy small construction offsets into the full-source frame."""
    raw=event.get('plan_origin_offset_mm',[0,0])
    if not isinstance(raw,list) or len(raw)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>2*max(BOARD_MM) for v in raw):return raw
    offset=list(raw)
    analysis=event.get('analysis',{})
    if event.get('plan_origin_basis',analysis.get('plan_origin_basis'))=='source_plan_envelope':return offset
    envelope=analysis.get('envelope')
    full=analysis.get('source_plan_envelope')
    if envelope and not full:
        # Old examples lacked this field; same signature preserves relative frames.
        envelope=product.get('envelope');full=product.get('source_plan_envelope')
    if envelope and full:
        for axis in (0,1):
            shift=envelope[axis]-full[axis]
            # A partial last bay cannot define the origin of a full accepted layout.
            if abs(shift)<=2*max(BOARD_MM)+TOL:offset[axis]+=shift
    return [round(v,4) for v in offset]


class EvidenceError(ValueError):
    pass


def valid_state(state):
    if not isinstance(state, dict) or not state.get('modules'):
        return False
    bounds = state.get('bounds')
    if not isinstance(bounds, list) or len(bounds) != 3:
        return False
    if not all(type(v) in (int, float) and math.isfinite(v) and 0 < v < 100000 for v in bounds):
        return False
    parts = [p for kind in KINDS for p in state.get(kind, [])]
    ids = [p.get('id') for p in parts if isinstance(p, dict)]
    if len(ids) != len(parts) or any(not isinstance(i, str) or not i for i in ids) or len(set(ids)) != len(ids):
        return False
    nested = [p for m in state['modules'] for p in m.get('panel_parts', [])]
    for part in parts + nested:
        if not isinstance(part, dict):
            return False
        for key in ('origin', 'size'):
            row = part.get(key)
            if not isinstance(row, list) or len(row) != 3 or not all(
                    type(v) in (int, float) and math.isfinite(v) and 0 <= v < 100000 for v in row):
                return False
        if min(part['size']) <= 0:
            return False
        if 'plan_profile' in part and not valid_profile(part['plan_profile'],part['size']):
            return False
    if any(p['origin'][a] + p['size'][a] > bounds[a] + TOL for p in parts for a in range(3)):
        return False
    return not overlapping_modules(state['modules'])


def levels(values):
    groups = []
    for value in sorted(values):
        if not groups or value - groups[-1][0] > TOL:
            groups.append([value])
        else:
            groups[-1].append(value)
    return [sum(g) / len(g) for g in groups]


def pattern(view):
    rows = []
    for r in recovered_rects(view):
        layer = normalise(r.layer)
        if layer == '0' or 'KHUAT' in layer or 'HATCH' in layer:
            continue
        if min(r.w, r.h) > 0:
            rows.append(r)
    if len(rows) < 3:
        return None
    # Retain construction profiles too: an added L-support/unclosed line must
    # not disappear merely because it did not form a rectangle.
    segments = [(a, b) for o in view['outlines']
                if not o.get('layer') or 'CAT NT' in normalise(o.get('layer', ''))
                for a, b in zip(o['points'], o['points'][1:])
                if max(abs(a[i]-b[i]) for i in (0, 1)) > TOL]
    for r in rows:
        corners = [[r.x0, r.y0], [r.x1, r.y0], [r.x1, r.y1], [r.x0, r.y1]]
        segments.extend(zip(corners, corners[1:] + corners[:1]))
    axes = [levels([r.box()[a] for r in rows for a in (axis, axis + 2)] +
                   [p[axis] for segment in segments for p in segment]) for axis in (0, 1)]
    def index(value, axis):
        return min(range(len(axes[axis])), key=lambda i: abs(axes[axis][i] - value))
    def key(r):
        return tuple(index(v, a % 2) for a, v in enumerate(r.box()))
    # Deduplicate by clustered edge incidence, never by a world-coordinate grid.
    # Raw DXF vertices and flattened polylines can differ by 0.001 mm; rounding
    # world coordinates would change the duplicate count after a translation.
    unique = {}
    for r in rows:
        unique.setdefault(key(r), r)
    rows = sorted(unique.values(), key=key)
    graph = [key(r) for r in rows]
    spans, diagonals = {}, set()
    for a, b in segments:
        p, q = tuple(index(a[i], i) for i in (0, 1)), tuple(index(b[i], i) for i in (0, 1))
        if p[0] == q[0]:
            spans.setdefault(('v', p[0]), []).append(sorted((p[1], q[1])))
        elif p[1] == q[1]:
            spans.setdefault(('h', p[1]), []).append(sorted((p[0], q[0])))
        else:
            diagonals.add(tuple(sorted((p, q))))
    profile = []
    for line, intervals in sorted(spans.items()):
        merged = []
        for a, b in sorted(intervals):
            if merged and a <= merged[-1][1]:
                merged[-1][1] = max(merged[-1][1], b)
            else:
                merged.append([a, b])
        profile.append([line, merged])
    role = view['role']
    if role == 'section_unknown':
        w, h = axes[0][-1] - axes[0][0], axes[1][-1] - axes[1][0]
        role = 'plan' if w > h * 2 and h < 1500 else 'section_vertical' if h > w * 1.5 and w < 1500 else role
    if role not in ('plan', 'front_open', 'section_vertical'):
        return None
    fingerprint = hashlib.sha256(json.dumps([role, graph, profile, sorted(diagonals)]).encode()).hexdigest()
    return {'id': view['id'], 'role': role, 'fingerprint': fingerprint, 'axes': axes,
            'rows': [{'box': r.box(), 'handle': r.handle} for r in rows]}


def product_patterns(product):
    rectangles = [Rect(*r['box'], r.get('handle', ''), r.get('layer', '')) for r in product.get('rectangles', [])]
    outlines = product.get('outlines', [])
    result = []
    for view in product.get('views', []):
        if view['role'] == 'front_check':
            continue
        region = view['region']
        v = dict(view, rects=[r for r in rectangles if inside(r.box(), region)],
                 outlines=[o for o in outlines if o['points'] and all(inside([*p, *p], region) for p in o['points'])])
        p = pattern(v)
        if p:
            result.append(p)
    return result


def anchors(view, axis):
    """References survive handle changes; coincident witnesses must stay coincident."""
    values = [(v, ['edge', i]) for i, v in enumerate(view['axes'][axis])]
    for i, row in enumerate(view['rows']):
        b = row['box']
        if b[axis + 2] - b[axis] <= 60:
            values.append(((b[axis] + b[axis + 2]) / 2, ['centre', i]))
    groups = []
    for value, ref in sorted(values):
        if not groups or value - groups[-1]['value'] > TOL:
            groups.append({'value': value, 'refs': [ref]})
        else:
            groups[-1]['refs'].append(ref)
    return groups


def anchor_value(definition, view, axis):
    values, handles = [], set()
    for kind, i in definition['refs']:
        if kind == 'edge':
            v = view['axes'][axis][i]
            handles.update(r['handle'] for r in view['rows']
                           if min(abs(r['box'][axis] - v), abs(r['box'][axis + 2] - v)) <= TOL)
        else:
            row = view['rows'][i]
            v = (row['box'][axis] + row['box'][axis + 2]) / 2
            handles.add(row['handle'])
        values.append(v)
    if max(values) - min(values) > TOL:
        raise EvidenceError('Các cạnh/tâm tấm cùng mặt phẳng ở mẫu đã tách khác nhau trong CAD mới.')
    return sum(values) / len(values), sorted(handles)


def fit_axis(view, axis, planes, signs):
    points = anchors(view, axis)
    coordinates = [p['value'] for p in points]
    candidates = {}
    for sign in signs:
        offsets = {round(a['value'] - sign * p, 5) for a in points for p in planes}
        for offset in offsets:
            bindings = []
            for plane in planes:
                at = bisect_left(coordinates, offset + sign * plane)
                i = min({max(0, at-1), min(len(points)-1, at)},
                        key=lambda i: abs(points[i]['value'] - (offset + sign * plane)))
                if abs(points[i]['value'] - (offset + sign * plane)) <= TOL:
                    bindings.append([plane, points[i]])
            if len(bindings) >= 2:
                candidates[(sign, offset)] = {'sign': sign, 'bindings': bindings, 'axis': axis, 'view': view['id']}
    best = max((len(c['bindings']) for c in candidates.values()), default=0)
    result = [c for c in candidates.values() if len(c['bindings']) == best]
    if len(result) > 32:
        return []  # Repeated details do not locate the product unambiguously.
    return result


def measured_axes(prototype, pairs):
    output, evidence = [], []
    for physical in range(3):
        expected = prototype['planes'][physical]
        known, proofs = {}, {}
        pending = []
        for fit in prototype['fits'][physical]:
            for target in pairs.get(fit['view'], []):
                values = {}
                for plane, anchor in fit['bindings']:
                    value, handles = anchor_value(anchor, target, fit['axis'])
                    values[plane] = (value, {'view_id': target['id'], 'handles': handles,
                                           'construction_role': target['role'], 'anchor': anchor['refs']})
                pending.append((fit['sign'], values))
        while pending:
            remaining, changed = [], False
            for sign, values in pending:
                common = set(values).intersection(known)
                if 0 in values:
                    zero = values[0][0]
                elif len(common) >= 2:
                    zeros = [values[p][0] - sign * known[p] for p in common]
                    if max(zeros) - min(zeros) > TOL:
                        raise EvidenceError('Mặt bằng, mặt đứng và mặt cắt cho tọa độ mâu thuẫn.')
                    zero = sum(zeros) / len(zeros)
                else:
                    remaining.append((sign, values))
                    continue
                for plane, (value, proof) in values.items():
                    measured = sign * (value - zero)
                    if plane in known and abs(measured - known[plane]) > TOL:
                        raise EvidenceError('Có nhiều cách ghép cạnh cho kết quả kích thước khác nhau.')
                    if plane not in known:
                        known[plane] = measured
                        changed = True
                    proofs.setdefault(plane, []).append(dict(proof, cad_coordinate_mm=round(value, 6),
                                                            view_zero_mm=round(zero, 6), direction=sign))
            if not changed:
                break
            pending = remaining
        if any(p not in known for p in expected):
            missing = [p for p in expected if p not in known]
            raise EvidenceError(f'Trục {"XYZ"[physical]} chưa có cạnh CAD xác nhận các mặt phẳng: {missing}.')
        roles = {p['construction_role'] for rows in proofs.values() for p in rows}
        required = ({'front_open', 'plan'}, {'plan', 'section_vertical'}, {'front_open', 'section_vertical'})[physical]
        if not required.issubset(roles):
            raise EvidenceError(f'Trục {"XYZ"[physical]} thiếu đối chiếu độc lập giữa các hình chiếu.')
        if any(known[b] - known[a] <= TOL for a, b in zip(expected, expected[1:])):
            raise EvidenceError('Thứ tự các mặt phẳng đã đổi hoặc có khối bị co về không.')
        output.append(known)
        evidence.append(proofs)
    return output, evidence


def compile_sample(event):
    state = event['after']
    if event.get('scope', {}).get('partial_sample'):
        raise EvidenceError('Mẫu còn thiếu bộ phận; chỉ dùng để kiểm tra, không suy rộng tự động.')
    parts = [p for kind in KINDS for p in state.get(kind, [])]
    if any(p.get('profile') or p.get('plan_profile') or p.get('panel_parts') for p in parts):
        raise EvidenceError('Mẫu có biên dạng/tấm lồng; chưa có quy tắc chuyển từng đỉnh biên dạng.')
    if not isinstance(event.get('analysis'), dict):
        raise EvidenceError('Hồ sơ cũ chưa lưu hình học CAD để rút quy tắc.')
    try:
        views = product_patterns(event['analysis'])
    except (TypeError, KeyError, ValueError, IndexError) as error:
        raise EvidenceError('Hồ sơ mẫu chưa có hình học CAD hợp lệ để rút quy tắc.') from error
    if not {'plan', 'front_open', 'section_vertical'}.issubset({v['role'] for v in views}):
        raise EvidenceError('Mẫu chưa liên kết đủ mặt bằng, mặt đứng bỏ cánh và mặt cắt.')
    planes = [sorted({0.0, state['bounds'][a], *(round(p['origin'][a], 4) for p in parts),
                      *(round(p['origin'][a] + p['size'][a], 4) for p in parts)}) for a in range(3)]
    fits = [[], [], []]
    for v in views:
        for physical, cad_axis, signs in ((0, 0, (1,)), (1, 1, (1, -1)), (2, 1, (1,))):
            allowed = ({'front_open', 'plan'}, {'plan'}, {'front_open', 'section_vertical'})[physical]
            if v['role'] in allowed:
                fits[physical] += fit_axis(v, cad_axis, planes[physical], signs)
        if v['role'] == 'section_vertical':
            fits[1] += fit_axis(v, 0, planes[1], (1, -1))
    result = {'schema': RULE_SCHEMA, 'views': views, 'planes': planes, 'fits': fits, 'after': state}
    measured_axes(result, {v['id']: [v] for v in views})  # Require an evidenced identity round-trip.
    return result


def compatible(source, target):
    if source['fingerprint'] != target['fingerprint']:
        return False
    # This first rule family retains stock, rather than scaling thin panels.
    for a, b in zip(source['rows'], target['rows']):
        sa = min(a['box'][2] - a['box'][0], a['box'][3] - a['box'][1])
        sb = min(b['box'][2] - b['box'][0], b['box'][3] - b['box'][1])
        if any(abs(sa - stock) <= TOL for stock in BOARD_MM) and abs(sa - sb) > TOL:
            return False
    return True


def same_topology(sources, targets):
    return Counter(v['fingerprint'] for v in sources) == Counter(v['fingerprint'] for v in targets)


def transfer(prototype, targets):
    if not same_topology(prototype['views'], targets):
        raise EvidenceError('Số hình chiếu hoặc cấu tạo cạnh/tấm khác mẫu; không lấy thiếu một cụm để dựng.')
    pairs = {v['id']: [t for t in targets if compatible(v, t)] for v in prototype['views']}
    if any(not choices for choices in pairs.values()):
        raise EvidenceError('Cấu tạo cạnh/tấm hoặc độ dày ván không khớp mẫu.')
    axes, proofs = measured_axes(prototype, pairs)
    state = deepcopy(prototype['after'])
    for kind in KINDS:
        for part in state.get(kind, []):
            old_origin, old_size = part['origin'], part['size']
            lo = [round(v, 4) for v in old_origin]
            hi = [round(old_origin[a] + old_size[a], 4) for a in range(3)]
            part['origin'] = [round(axes[a][lo[a]], 4) for a in range(3)]
            part['size'] = [round(axes[a][hi[a]] - axes[a][lo[a]], 4) for a in range(3)]
            if 'face_width_mm' in part:
                axes_with_face = [a for a in range(3) if abs(old_size[a] - part['face_width_mm']) <= TOL]
                if len(axes_with_face) == 1:
                    part['face_width_mm'] = part['size'][axes_with_face[0]]
            part['anchor_evidence'] = {f'{"XYZ"[a]}{side}': proofs[a][p]
                                       for a in range(3) for side, p in [('0', lo[a]), ('1', hi[a])]}
            part['handles'] = sorted({h for rows in part['anchor_evidence'].values() for proof in rows for h in proof['handles']})
            for key in ('entity_id', 'source_entity_id', 'transform', 'source_box', 'carcass_box',
                        'section_support', 'joint_evidence', 'depth_evidence'):
                part.pop(key, None)
            front_planes = [[p for p in part['anchor_evidence'][key] if p['construction_role'] == 'front_open']
                            for key in ('X0', 'Z0', 'X1', 'Z1')]
            common = set.intersection(*(set(p['view_id'] for p in rows) for rows in front_planes))
            if len(common) == 1:
                front_id = common.pop()
                part['source_box'] = [next(p['cad_coordinate_mm'] for p in rows if p['view_id'] == front_id)
                                      for rows in front_planes]
            part['rule'] = 'accepted-topology-measured-anchors-v1'
            part['explanation'] = 'Giữ cách chia của mẫu đã chấp nhận; từng mặt khối được đo lại từ cạnh/tâm tấm CAD mới và đối chiếu hình chiếu.'
    state['bounds'] = [round(axes[a][prototype['planes'][a][-1]], 4) for a in range(3)]
    if not valid_state(state) or overlapping_modules([p for k in KINDS for p in state.get(k, [])]):
        raise EvidenceError('Khối sau khi ghép cạnh bị chồng lấn hoặc vượt giới hạn sản phẩm.')
    return state


def state_key(state):
    return tuple(tuple(sorted(tuple(round(v, 3) for v in p['origin'] + p['size'])
                              for p in state.get(k, []))) for k in KINDS)


class ExperienceLibrary:
    def __init__(self, root):
        self.root = root
        self._events = None
        self.diagnostics = []
        self._plan_rules = None

    def plan_rules(self):
        if self._plan_rules is None:
            from plan_learning import PlanRuleLibrary
            self._plan_rules = PlanRuleLibrary(self.root)
        return self._plan_rules

    def refresh_plan_rules(self):
        return self.plan_rules().refresh()

    def apply_plan_rules(self, product):
        return self.plan_rules().apply(product)

    def events(self):
        if self._events is None:
            self._events = []
            active_signatures = set()
            for path in sorted((self.root / 'experiences').glob('*/*.json'), reverse=True):
                try:
                    event = json.loads(path.read_text(encoding='utf-8'))
                    if (event.get('status') == 'accepted' and event.get('parser_version') == VERSION
                            and event.get('analysis',{}).get('build_stages',{}).get('elevation') is not False
                            and event.get('signature') == path.parent.name and event.get('id')
                            and valid_state(event.get('after'))):
                        if event['signature'] in active_signatures:
                            continue
                        active_signatures.add(event['signature'])
                        self._events.append((path, event))
                except (ValueError, TypeError, KeyError, OSError):
                    self.diagnostics.append({'code': 'invalid_example', 'path': str(path),
                                             'message': 'Bỏ qua hồ sơ mẫu hỏng; lịch sử gốc được giữ nguyên.'})
        return self._events

    def compiled(self, event):
        digest = hashlib.sha256(json.dumps(event, sort_keys=True).encode()).hexdigest()
        path = self.root / 'rules' / f'v{RULE_SCHEMA}' / f'{digest}.json'
        try:
            saved = json.loads(path.read_text(encoding='utf-8'))
            if saved.get('schema') == RULE_SCHEMA and saved.get('event_hash') == digest:
                if saved.get('error'):
                    raise EvidenceError(saved['error'])
                prototype = saved.get('prototype')
                if (isinstance(prototype, dict) and saved.get('prototype_hash') ==
                        hashlib.sha256(json.dumps(prototype, sort_keys=True).encode()).hexdigest()):
                    return prototype
        except (OSError, ValueError, TypeError, AttributeError) as error:
            if isinstance(error, EvidenceError):
                raise
            pass
        try:
            prototype = compile_sample(event)
        except EvidenceError as error:
            atomic_json(path, {'schema': RULE_SCHEMA, 'event_hash': digest, 'error': str(error)})
            raise
        checksum = hashlib.sha256(json.dumps(prototype, sort_keys=True).encode()).hexdigest()
        atomic_json(path, {'schema': RULE_SCHEMA, 'event_hash': digest, 'prototype_hash': checksum, 'prototype': prototype})
        return prototype

    def apply_plan(self, product):
        """Replay explicitly accepted plan layouts at the same geometry only."""
        signature=product.get('signature')
        if not signature or not re.fullmatch(r'[0-9a-f]{64}',signature):return False
        for path in sorted((self.root/'experiences'/signature).glob('*.json'),reverse=True):
            try:
                event=json.loads(path.read_text(encoding='utf8'))
                if (self.root/'experience_exclusions'/f"{event.get('id','')}.json").is_file():continue
                if (event.get('status')!='accepted' or event.get('signature')!=signature or
                    event.get('parser_version')!=VERSION or
                    event.get('analysis',{}).get('build_stages',{}).get('elevation') is not False or
                    not event.get('input_axes_ignored') or not valid_state(event.get('after'))):continue
                state=json.loads(json.dumps(event['after']))
                offset=plan_event_offset(event,product)
                if (not isinstance(offset,list) or len(offset)!=2 or
                    any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>2*max(BOARD_MM) for v in offset)):continue
                envelope=event.get('analysis',{}).get('source_plan_envelope',event.get('analysis',{}).get('envelope'))
                if envelope and any(abs(state['bounds'][a]-(envelope[a+2]-envelope[a]))>2*max(BOARD_MM)+TOL for a in (0,1)):
                    product.update(status='needs_review',error='Mẫu box đã xác nhận không khớp kích thước CAD nguồn; cần gắn lại mẫu vào đúng sản phẩm.')
                    product['learning']={'mode':'review','event':event['id'],'issues':[{'code':'source_binding_mismatch','message':product['error']}]}
                    return False
                parts=state['modules']+state.get('trim_parts',[])+state.get('panel_parts',[])
                if any(abs(p['origin'][2])>.1 for p in parts):continue
                anchor=product.get('source_plan_envelope',product['envelope'])
                for p in parts:
                    p['size'][2]=1600;p['origin'][2]=0
                    p.pop('entity_id',None);p.pop('transform',None)
                    p['height_source']='provisional_default'
                    p['source_box']=[anchor[0]+offset[0]+p['origin'][0],anchor[1]+offset[1]+p['origin'][1],
                                     anchor[0]+offset[0]+p['origin'][0]+p['size'][0],
                                     anchor[1]+offset[1]+p['origin'][1]+p['size'][1]]
                    p['plan_box']=list(p['source_box'])
                state['bounds'][2]=1600
                product.update({k:state.get(k,[]) for k in ('modules','trim_parts','panel_parts','bounds')})
                product.update(status='ready',manual_boxes=True,height_source='provisional_default',default_height_mm=1600)
                product['plan_origin_offset_mm']=offset
                product['plan_origin_basis']='source_plan_envelope'
                product.pop('error',None)
                product['learning']={'mode':'plan_exact','event':event['id'],
                                     'message':'Bố trí mặt bằng từ box đã xác nhận cùng hình học; cao tạm 1600 mm.'}
                product['experience']={'event':event['id'],'file':str(path),'stage':'plan_only'}
                product.setdefault('explanation',[]).append(product['learning']['message'])
                return True
            except (OSError,ValueError,KeyError,TypeError):continue
        return False

    def apply(self, product):
        events = self.events()
        for path, event in events:
            if event['signature'] == product.get('signature'):
                self.install(product, event['after'], path, event, 'exact')
                if event.get('scope', {}).get('partial_sample'):
                    product.update(status='needs_review', error='Mẫu đã lưu còn thiếu bộ phận; cần bổ sung trước khi dựng hoàn chỉnh.')
                    product['learning']['mode'] = 'review'
                    product['learning']['issues'] = [{'code': 'partial_example', 'message': product['error'],
                                                       'excluded': event['scope'].get('excluded', [])}]
                return True
        targets = product_patterns(product)
        candidates, issues, matched_failures = [], [], []
        for path, event in events:
            matched = False
            try:
                prototype = self.compiled(event)
                if not same_topology(prototype['views'], targets):
                    continue
                matched = True
                candidates.append((transfer(prototype, targets), path, event))
            except EvidenceError as error:
                issue = {'code': 'unbound_example', 'event': event['id'],
                         'source_code': event.get('analysis', {}).get('code'), 'message': str(error)}
                issues.append(issue)
                if matched:
                    matched_failures.append(issue)
        if candidates:
            if len({state_key(c[0]) for c in candidates}) != 1:
                product.update(status='needs_review', error='Các mẫu tương tự đưa ra cách chia khác nhau; cần xác nhận cách chia đúng.')
                product['learning'] = {'mode': 'review', 'issues': [{'code': 'conflicting_examples', 'message': product['error'],
                                            'events': [c[2]['id'] for c in candidates]}]}
                return False
            state, path, event = candidates[0]
            self.install(product, state, path, event, 'similar')
            product['learning']['agreeing_events'] = [c[2]['id'] for c in candidates]
            return True
        if matched_failures:
            product.update(status='needs_review', error=matched_failures[0]['message'])
            product['learning'] = {'mode': 'review', 'issues': matched_failures}
            return False
        product['learning'] = {'mode': 'unmatched', 'issues': issues + self.diagnostics,
                               'message': 'Chưa có mẫu đủ bằng chứng để suy rộng; dùng kết quả đo hình học nếu hợp lệ.'}
        return False

    @staticmethod
    def install(product, state, path, event, mode):
        product['original_modules'] = product.get('modules', [])
        for key in (*KINDS, 'bounds'):
            product[key] = deepcopy(state.get(key, []))
        if mode == 'similar':
            product['geometry_pipeline'] = {'mode': 'learned_measured_anchors',
                'order': ['construction_topology', 'plan_axes', 'front_section_axes', 'measured_faces'],
                'horizontal': {'modules': product['modules']}}
        else:
            product.setdefault('geometry_pipeline', {}).setdefault('horizontal', {})['modules'] = product['modules']
        product['experience'] = {'event': event['id'], 'path': str(path), 'mode': mode}
        product['learning'] = {'schema': RULE_SCHEMA, 'mode': mode, 'event': event['id'],
                               'source_code': event.get('analysis', {}).get('code'), 'issues': []}
        caption = ('Dùng mẫu có cùng chữ ký hình học.' if mode == 'exact' else
                   'Đã áp dụng cách chia từ mẫu có cùng cấu tạo cạnh/tấm; kích thước đo lại từ CAD mới, giữ độ dày ván.')
        product.setdefault('explanation', []).append(caption)
        product.update(status='ready')
        product.pop('error', None)
