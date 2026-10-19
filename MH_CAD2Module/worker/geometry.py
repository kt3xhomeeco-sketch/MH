"""Evidence-based orthogonal cabinet recognition. DIMENSION is never measured."""
from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
import math

TOL = 0.15  # mm


def near(a, b, tolerance=TOL):
    return abs(a - b) <= tolerance


@dataclass(frozen=True)
class Rect:
    x0: float
    y0: float
    x1: float
    y1: float
    handle: str
    layer: str = ""

    @property
    def w(self):
        return self.x1 - self.x0

    @property
    def h(self):
        return self.y1 - self.y0

    def box(self):
        return [self.x0, self.y0, self.x1, self.y1]

    def as_dict(self):
        return {"handle": self.handle, "layer": self.layer, "box": self.box()}


def rectangle(points, handle, layer=""):
    points = [(float(p[0]), float(p[1])) for p in points]
    if len(points) > 1 and near(points[0][0], points[-1][0]) and near(points[0][1], points[-1][1]):
        points.pop()
    if len(points) < 4:
        return None
    xs, ys = zip(*points)
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    if x1 - x0 <= TOL or y1 - y0 <= TOL:
        return None
    area = 0
    for a, b in zip(points, points[1:] + points[:1]):
        if not (near(a[0], b[0]) or near(a[1], b[1])):
            return None
        area += a[0] * b[1] - b[0] * a[1]
    if abs(abs(area) / 2 - (x1 - x0) * (y1 - y0)) > max(0.1, (x1 - x0) * (y1 - y0) * 1e-5):
        return None
    return Rect(x0, y0, x1, y1, str(handle), layer)


def line_rectangles(lines, min_length=100):
    """Recover thin rectangular panels from continuous, possibly segmented edges."""
    horizontal, vertical = defaultdict(list), defaultdict(list)
    xpos, ypos = {}, {}
    for a, b, handle, layer in lines:
        if near(a[1], b[1]):
            key = round(a[1], 1)
            ypos.setdefault(key, a[1])
            horizontal[key].append((min(a[0], b[0]), max(a[0], b[0]), handle, layer))
        elif near(a[0], b[0]):
            key = round(a[0], 1)
            xpos.setdefault(key, a[0])
            vertical[key].append((min(a[1], b[1]), max(a[1], b[1]), handle, layer))

    # Lists do not change below. Sort once, and reject impossible spans before
    # enumerating end-cap pairs from unrelated details elsewhere in the drawing.
    limits, runs = {}, {}
    for group in (horizontal, vertical):
        for intervals in group.values():
            intervals.sort()
            limits[id(intervals)] = (intervals[0][0], max(row[1] for row in intervals))
            joined = []
            for a, b, *_ in intervals:
                if not joined or a > joined[-1][1]+TOL:
                    joined.append([a, b])
                else:
                    joined[-1][1] = max(joined[-1][1], b)
            runs[id(intervals)] = joined

    def covered(intervals, start, finish):
        low, high = limits[id(intervals)]
        if start < low-TOL or finish > high+TOL:
            return None
        reach, used = start, []
        for a, b, identity, layer in intervals:
            if b < start - TOL or a > finish + TOL:
                continue
            if a > reach + TOL:
                return None
            reach = max(reach, b)
            used.append(identity)
            if reach >= finish - TOL:
                return used, layer
        return None

    result = {}
    # Every carcass panel has one thin direction; large empty cells aren't panels.
    for primary, secondary, primary_pos, secondary_pos, swap in (
            (vertical, horizontal, xpos, ypos, False),
            (horizontal, vertical, ypos, xpos, True)):
        axes = sorted(primary)
        for index, left in enumerate(axes):
            for right in axes[index + 1:]:
                thickness = primary_pos[right] - primary_pos[left]
                if thickness > 60 + TOL:
                    break
                if thickness < 2 - TOL:
                    continue
                cap_proofs = {key: proof for key, intervals in secondary.items()
                              if (proof := covered(intervals, primary_pos[left], primary_pos[right]))}
                # Retain the existing complexity guard before spatial pruning.
                if len(cap_proofs) > 200:
                    continue
                windows = [(max(a, c)-TOL, min(b, d)+TOL)
                           for a, b in runs[id(primary[left])] for c, d in runs[id(primary[right])]
                           if max(a, c)-TOL < min(b, d)+TOL]
                # Sweep parallel Y faces left-to-right, testing their longest
                # continuous common span first. Short details follow separately.
                for low, high in sorted(windows, key=lambda w: w[0]-w[1]):
                    caps = sorted(key for key in cap_proofs if low <= secondary_pos[key] <= high)
                    for i, bottom in enumerate(caps):
                        for top in caps[i+1:]:
                            lo, hi = secondary_pos[bottom], secondary_pos[top]
                            if hi-lo <= min_length:
                                continue
                            side_a = covered(primary[left], lo, hi)
                            if not side_a:
                                continue
                            side_b = covered(primary[right], lo, hi)
                            if not side_b:
                                continue
                            cap_a, cap_b = cap_proofs[bottom], cap_proofs[top]
                            ids = '+'.join(side_a[0]+side_b[0]+cap_a[0]+cap_b[0])
                            box = (lo, primary_pos[left], hi, primary_pos[right]) if swap else (primary_pos[left], lo, primary_pos[right], hi)
                            key = tuple(round(v, 3) for v in box)
                            result[key] = Rect(*box, ids, side_a[1])
                            if len(result) > 20000:
                                raise ValueError('Vùng LINE quá phức tạp để ghép panel; hãy quét gọn một sản phẩm.')
    return list(result.values())


def enclosures(rects):
    vertical = [r for r in rects if 3 <= r.w <= 60 and r.h > max(100, r.w * 5)]
    horizontal = [r for r in rects if 3 <= r.h <= 60 and r.w > max(100, r.h * 5)]
    result = []
    for i, left in enumerate(vertical):
        for right in vertical[i + 1:]:
            if right.x0 < left.x0:
                a, b = right, left
            else:
                a, b = left, right
            if not (near(a.y0, b.y0) and near(a.y1, b.y1) and near(a.w, b.w)):
                continue
            if b.x0 - a.x1 < 100:
                continue
            spans = [p for p in horizontal
                     if ((near(p.x0, a.x1) and near(p.x1, b.x0)) or
                         (near(p.x0, a.x0) and near(p.x1, b.x1)))
                     and (near(p.y0, a.y0) or near(p.y1, a.y0) or
                          near(p.y0, a.y1) or near(p.y1, a.y1))]
            if not spans or not any(near(p.h, a.w) for p in spans):
                continue
            # A long outer shell plus a shorter single partition stays one enclosure.
            result.append({"box": [a.x0, a.y0, b.x1, a.y1], "thickness": a.w,
                           "handles": [a.handle, b.handle] + [p.handle for p in spans],
                           "score": len(spans) + 2})
    unique = {}
    for item in result:
        key = tuple(round(v, 2) for v in item["box"])
        unique[key] = item
    return list(unique.values())


def gap_boxes(a, b):
    return max(a[0] - b[2], b[0] - a[2], 0), max(a[1] - b[3], b[1] - a[3], 0)


def assemblies(candidates):
    remaining = set(range(len(candidates)))
    groups = []
    while remaining:
        stack = [remaining.pop()]
        group = []
        while stack:
            i = stack.pop()
            group.append(candidates[i])
            for j in list(remaining):
                dx, dy = gap_boxes(candidates[i]["box"], candidates[j]["box"])
                if dx <= TOL and dy <= 120:
                    remaining.remove(j)
                    stack.append(j)
        groups.append(group)
    return sorted(groups, key=lambda g: (sum(v["score"] for v in g), max(v["box"][3] - v["box"][1] for v in g)), reverse=True)


def union(boxes):
    return [min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes)]


def inside(box, outer):
    return box[0] >= outer[0] - TOL and box[1] >= outer[1] - TOL and box[2] <= outer[2] + TOL and box[3] <= outer[3] + TOL


def geometry_signature(rects, origin_box=None, outlines=()):
    if not rects:
        return None
    origin_box = origin_box or union([r.box() for r in rects])
    data = {"version": 2, "rects": sorted([round(r.x0-origin_box[0], 2), round(r.y0-origin_box[1], 2),
                                           round(r.w, 2), round(r.h, 2)] for r in rects)}
    # Profiles can determine support boundaries even when they aren't rectangles.
    data['edges'] = sorted({tuple(sorted((tuple(round(p[i]-origin_box[i], 2) for i in range(2)),
                                         tuple(round(q[i]-origin_box[i], 2) for i in range(2)))))
                            for row in outlines for p,q in zip(row['points'], row['points'][1:])})
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def infer_depth(rects, front, modules, thickness):
    heights = [m["box"][3] - m["box"][1] for m in modules]
    evidence = []
    for wall in rects:
        if inside(wall.box(), front) or not near(wall.w, thickness):
            continue
        if not any(near(wall.h, h) for h in heights):
            continue
        panels = [p for p in rects if near(p.h, thickness) and p.w >= 150
                  and (near(p.x1, wall.x0) or near(p.x0, wall.x1))
                  and (near(p.y0, wall.y0) or near(p.y1, wall.y1))]
        for depth, count in Counter(round(p.w, 2) for p in panels).items():
            matching = [p for p in panels if near(p.w, depth)]
            if count >= 2 and any(near(p.y0, wall.y0) for p in matching) and any(near(p.y1, wall.y1) for p in matching):
                evidence.append({"depth": depth, "front_offset": wall.w,
                                 "handles": [wall.handle] + [p.handle for p in matching]})
    depths = sorted(set(e["depth"] for e in evidence))
    if not depths:
        raise ValueError("Thiếu chiều sâu: chưa ghép được mặt cắt có nóc/đáy và cánh phù hợp. Không dùng chiều sâu mặc định.")
    if len(depths) != 1:
        raise ValueError("Mâu thuẫn chiều sâu đo được: " + ", ".join(map(str, depths)) + " mm. Cần chỉ lại vùng hình chiếu.")
    return depths[0], evidence


def section_support(module, rects, outlines, depth, thickness, require_profile=True):
    """Include the full two-leg support; the door identifies the section only."""
    bottom, top = module['box'][1], module['box'][3]
    lines = [(a,b,row['handle'],row.get('layer','')) for row in outlines
             for a,b in zip(row['points'], row['points'][1:])
             if all(bottom-120-TOL <= p[1] <= bottom+TOL for p in (a,b))]
    panels = rects + line_rectangles(lines, min_length=0)
    matches = {}
    for deck in panels:
        if not (near(deck.y1, bottom) and near(deck.h, thickness) and near(deck.w+thickness, depth)):
            continue
        fronts = [r for r in panels if near(r.w, thickness) and near(r.x0, deck.x1)
                  and near(r.y1, bottom) and bottom-120 <= r.y0 < deck.y0-TOL]
        for leg in fronts:
            rears = [r for r in panels if near(r.w, thickness) and near(r.x0, deck.x0)
                     and near(r.y0, leg.y0) and near(r.y1, deck.y0)]
            if not rears:
                continue
            if not require_profile:
                matches[round(leg.y0,3)]={'bottom':leg.y0,'extension_mm':round(bottom-leg.y0,3),
                                        'section_x':[deck.x0,leg.x1],
                                        'handles':[deck.handle,leg.handle,rears[0].handle]}
            for profile in outlines:
                pts = profile['points']
                if not pts:
                    continue
                x0,y0,x1,y1 = union([[p[0],p[1],p[0],p[1]] for p in pts])
                if (near(y1, top) and leg.y0+TOL < y0 < deck.y0-TOL
                        and x0 >= leg.x1-TOL and x1 <= leg.x1+thickness+TOL):
                    matches[round(leg.y0,3)] = {'bottom': leg.y0, 'extension_mm': round(bottom-leg.y0,3),
                        'door_bottom': y0, 'below_door_mm': round(y0-leg.y0,3),
                        'section_x': [deck.x0,leg.x1],
                        'handles': [deck.handle,leg.handle,rears[0].handle,profile['handle']]}
    if len(matches)>1:
        raise ValueError('Mặt cắt có nhiều cao độ chia chân nóc; cần chỉ lại vùng tương ứng.')
    return next(iter(matches.values()), None)


def covers(intervals, start, finish):
    """Require continuous measured edges/panels across the requested span."""
    reach = start
    for a,b in sorted(intervals):
        if b < reach-TOL:
            continue
        if a > reach+TOL:
            return False
        reach = max(reach,b)
        if reach >= finish-TOL:
            return True
    return False


def validate_joint(module, rects, outlines, support):
    """A front contact seam must agree with an uncut section support plane."""
    boundary = support['bottom']
    sx0,sx1 = support['section_x']
    lines = [(a,b,row['handle'],row.get('layer','')) for row in outlines
             for a,b in zip(row['points'], row['points'][1:])]
    local = [(a,b,h,layer) for a,b,h,layer in lines
             if all(sx0-TOL <= p[0] <= sx1+TOL and
                    boundary-120-TOL <= p[1] <= module['box'][1]+TOL for p in (a,b))]
    panels = rects + line_rectangles(local, min_length=0)
    horizontal = [(min(a[0],b[0]),max(a[0],b[0])) for a,b,_,_ in lines
                  if near(a[1],boundary) and near(b[1],boundary)]
    crossing = [r for r in panels if sx0-TOL <= r.x0 and r.x1 <= sx1+TOL
                and 2 <= r.w <= 60 and r.h > r.w
                and r.y0+TOL < boundary < r.y1-TOL
                and not covers(horizontal,r.x0,r.x1)]
    if crossing:
        raise ValueError('Đường chia cắt xuyên panel đứng liền trong mặt cắt: ' +
                         ', '.join(sorted({r.handle for r in crossing})))
    x0,_,x1,carcass_top = module['box']
    # Use the actual front view; don't borrow rectangles from another projection.
    front = [r for r in rects if x0-TOL <= r.x0 and r.x1 <= x1+TOL]
    upper = [r for r in front if near(r.y0,boundary) and r.y1 > boundary+TOL and
             (r.y1 <= carcass_top+TOL or (r.w<=60 and r.y1<=carcass_top+120+TOL))]
    lower = [r for r in front if near(r.y1,boundary) and r.y0 < boundary-TOL]
    if not (covers([(r.x0,r.x1) for r in upper],x0,x1) and
            covers([(r.x0,r.x1) for r in lower],x0,x1)):
        raise ValueError('Cao độ chia mặt cắt không khớp đường tiếp giáp giữa các hình chữ nhật ở mặt đứng.')
    return {'front_y':boundary, 'front_handles':sorted({r.handle for r in upper+lower}),
            'section_handles':support['handles'], 'section_no_cut':True}


def overlapping_modules(modules):
    pairs = []
    for i,a in enumerate(modules):
        for b in modules[i+1:]:
            if all(min(a['origin'][axis]+a['size'][axis], b['origin'][axis]+b['size'][axis]) -
                   max(a['origin'][axis], b['origin'][axis]) > .1 for axis in range(3)):
                pairs.append(f"{a['id']}/{b['id']}")
    return pairs


def recognise(rects, outlines=()):
    groups = assemblies(enclosures(rects))
    if not groups:
        raise ValueError("Chưa nhận ra hệ vách và nóc/đáy khép thùng từ hình học vuông góc.")
    modules = groups[0]
    best_height = max(m['box'][3] - m['box'][1] for m in modules)
    best_score = sum(m['score'] for m in modules)
    best_shape = sorted((round(m['box'][2]-m['box'][0], 2), round(m['box'][3]-m['box'][1], 2)) for m in modules)
    for other in groups[1:]:
        height = max(m['box'][3] - m['box'][1] for m in other)
        shape = sorted((round(m['box'][2]-m['box'][0], 2), round(m['box'][3]-m['box'][1], 2)) for m in other)
        if sum(m['score'] for m in other) == best_score and near(height, best_height) and shape != best_shape:
            raise ValueError('Có nhiều hình đứng cấu tạo cùng mức bằng chứng nhưng khác kích thước; cần quét riêng đúng sản phẩm.')
    front = union([m["box"] for m in modules])
    thickness = Counter(round(m["thickness"], 2) for m in modules).most_common(1)[0][0]
    depth, depth_evidence = infer_depth(rects, front, modules, thickness)
    for module in modules:
        # A support belongs to a stacked upper enclosure, not the floor plinth.
        if module['box'][1] <= front[1]+TOL:
            continue
        support = section_support(module, rects, outlines, depth, thickness)
        if support:
            module['joint_evidence'] = validate_joint(module, rects, outlines, support)
            module['carcass_box'] = list(module['box'])
            module['box'] = [module['box'][0], support['bottom'], *module['box'][2:]]
            module['section_support'] = support
            module['handles'] += support['handles']
    # Retain only matching full-width trims directly adjacent to the assembly.
    trims = [r for r in rects if near(r.x0, front[0]) and near(r.x1, front[2])
             and 0 < r.h <= 120 and (abs(r.y1 - front[1]) <= TOL or abs(r.y0 - front[3]) <= TOL)]
    envelope = union([front] + [r.box() for r in trims])
    back_candidates = Counter(round(min(r.w, r.h), 2) for r in rects
                              if 2 <= min(r.w, r.h) < thickness * 0.7 and max(r.w, r.h) > 200)
    back = back_candidates.most_common(1)[0][0] if back_candidates else None
    output = []
    for index, module in enumerate(sorted(modules, key=lambda m: (m["box"][1], m["box"][0]))):
        x0, y0, x1, y1 = module["box"]
        output.append({"id": f"M{index + 1:02}", "name": f"Module {index + 1:02}",
                       "origin": [round(x0 - envelope[0], 3), thickness, round(y0 - envelope[1], 3)],
                       "size": [round(x1 - x0, 3), depth, round(y1 - y0, 3)],
                       "source_box": module["box"], "handles": module["handles"],
                       "rule": "panel-enclosure-v1",
                       "explanation": f"Rộng: {thickness:g} + {x1-x0-2*thickness:g} + {thickness:g} = {x1-x0:g} mm; cao: {y1:g} − {y0:g} = {y1-y0:g} mm; sâu {depth:g} mm từ mặt cắt."})
        if 'section_support' in module:
            output[-1].update(carcass_box=module['carcass_box'], section_support=module['section_support'])
            output[-1]['joint_evidence'] = module['joint_evidence']
            output[-1]['handles'] += module['joint_evidence']['front_handles']
            output[-1]['rule'] = 'panel-enclosure-cross-view-joint-v4'
            output[-1]['explanation'] += f" Mặt cắt có đế hai chân; khối bao đủ chân cao {module['section_support']['extension_mm']:g} mm, xuống dưới đáy cánh {module['section_support']['below_door_mm']:g} mm."
            output[-1]['explanation'] += ' Đường chia trùng mối tiếp giáp hình chữ nhật ở mặt đứng và không cắt xuyên panel đứng liền ở mặt cắt.'
    # Invariant to translation, product code, entity handles and filename.
    signature = geometry_signature(rects, envelope, outlines)
    overlaps = overlapping_modules(output)
    if overlaps:
        raise ValueError('Các khối ứng viên chồng nhau (' + ', '.join(overlaps) +
                         '); có thể đang ghép chi tiết con/ngăn kéo thành module. Cần kiểm tra vùng mặt đứng và mặt cắt.')
    return {"modules": output, "bounds": [round(envelope[2]-envelope[0], 3), depth + thickness,
                                           round(envelope[3]-envelope[1], 3)],
            "panel_mm": thickness, "back_mm": back, "front_box": front, "envelope": envelope,
            "signature": signature, "depth_evidence": depth_evidence,
            "explanation": ["Kích thước đo từ LINE/POLYLINE; không sử dụng DIM.",
                            "Mỗi thùng cần hai vách cùng cao độ và panel nối nóc/đáy.",
                            "Vách ngăn đơn trong nóc chạy suốt không tạo thêm thùng.",
                            f"Chiều sâu {depth:g} mm được đối chiếu với mặt cắt; mặt cánh dày {thickness:g} mm."]}
