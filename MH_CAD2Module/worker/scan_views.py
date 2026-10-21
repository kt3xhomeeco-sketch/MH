"""Readable SketchUp CAD annotations and bounded, source-bound cut recognition."""
from collections import defaultdict
import math
import re
import time

from geometry import TOL,union
from views import normalise,title_role


def source_key(row):
    return '/'.join(map(str,[*row.get('path',[]),row['handle']]))


def under(path,parent):
    return bool(parent) and path[:len(parent)]==parent


def axis(a,b):
    dx,dy=[abs(b[i]-a[i]) for i in (0,1)]
    return 'vertical' if dx<=TOL and dy>TOL else 'horizontal' if dy<=TOL and dx>TOL else 'oblique'


def runs(lines,gap=100):
    """Only adjacent intervals in indexed collinear bins; never all parallel pairs."""
    bins=defaultdict(list)
    for row in lines:
        a,b=row['a'],row['b'];direction=axis(a,b)
        if direction=='oblique':continue
        dim=0 if direction=='horizontal' else 1;normal=1-dim
        bins[direction,round((a[normal]+b[normal])/2,3)].append((min(a[dim],b[dim]),max(a[dim],b[dim]),row))
    output=[]
    for (direction,offset),intervals in bins.items():
        dim=0 if direction=='horizontal' else 1
        current=None
        for low,high,row in sorted(intervals,key=lambda r:(r[0],r[1])):
            if current and low<=current['high']+gap:
                current['high']=max(current['high'],high);current['rows'].append(row)
            else:
                current=dict(low=low,high=high,rows=[row],direction=direction,offset=offset);output.append(current)
    for run in output:
        offset=run['offset'];dim=0 if run['direction']=='horizontal' else 1
        run['a']=[run['low'],offset] if dim==0 else [offset,run['low']]
        run['b']=[run['high'],offset] if dim==0 else [offset,run['high']]
    return output


def symbol_cut(symbol):
    segments=symbol.get('segments',[])
    candidates=runs(segments)
    # An oblique symbol is retained for review, never reinterpreted as vertical.
    candidates += [dict(a=r['a'],b=r['b'],direction='oblique',rows=[r]) for r in segments if axis(r['a'],r['b'])=='oblique']
    candidates.sort(key=lambda r:math.dist(r['a'],r['b']),reverse=True)
    if not candidates:return None
    if len(candidates)>1 and math.dist(candidates[0]['a'],candidates[0]['b'])-math.dist(candidates[1]['a'],candidates[1]['b'])<=TOL:
        return None
    return candidates[0]


def symbol_number(symbol,cut,texts):
    attrs=symbol.get('attributes',{})
    delta=[cut['b'][i]-cut['a'][i] for i in (0,1)]
    basis=symbol.get('basis',[[1,0],[0,1]]);u,v=basis
    determinant=u[0]*v[1]-u[1]*v[0]
    if abs(determinant)<1e-10:return []
    local=[(delta[0]*v[1]-delta[1]*v[0])/determinant,(u[0]*delta[1]-u[1]*delta[0])/determinant]
    tags=('4','5') if abs(local[0])>=abs(local[1]) else ('1','2')
    if all(k in attrs for k in tags) and normalise(attrs[tags[0]])==normalise(attrs[tags[1]]):
        number=normalise(attrs[tags[0]])
        if re.fullmatch(r'[A-Z0-9]{1,8}',number):return [number]
    if any(k in attrs for k in tags):return [] # Conflicting/partial attributes cannot be overruled by nearby labels.
    local_texts=[t for t in texts if under(t.get('path',[]),symbol.get('path',[]))]
    return endpoint_numbers(cut,local_texts)


def endpoint_numbers(cut,texts):
    radius=max(50,min(250,math.dist(cut['a'],cut['b'])*.15))
    ends=[]
    for point in (cut['a'],cut['b']):
        candidates={normalise(t['text']) for t in texts if math.dist(t['point'],point)<=radius
                    and re.fullmatch(r'[A-Z0-9]{1,8}',normalise(t['text']))}
        ends.append(candidates)
    found=ends[0]&ends[1]
    return sorted(found) if len(found)==1 else []


def prepare(geometry):
    started=time.perf_counter();raw=geometry.get('scan_annotations',{})
    objects=raw.get('objects',[]);texts=[o for o in objects if 'text' in o]
    notes=list(geometry.get('annotations',[]));issues=list(raw.get('issues',[]));excluded=[];excluded_keys=set()
    for obj in objects:
        values=[obj['text']] if 'text' in obj else obj.get('texts',[])
        for value in dict.fromkeys(values):
            if title_role(value):notes.append(dict(kind='view_title',text=value,point=obj['point'],center_x=obj.get('center_x',obj['point'][0]),handle=obj['handle']))
        if obj.get('text_graphics'):excluded.append(obj['path'])
        if not obj.get('symbol'):continue
        excluded.append(obj['path'])
        cut=symbol_cut(obj)
        numbers=symbol_number(obj,cut,texts) if cut else []
        if not cut or not numbers or cut['direction']=='oblique':
            issues.append('Ký hiệu cắt '+obj['handle']+': chưa có đường cắt và cặp mã đọc được duy nhất theo hướng thực; giữ chiều cao tạm.')
            continue
        notes.append(dict(kind='section_marker',handle=obj['handle'],point=[sum(p[i] for p in (cut['a'],cut['b']))/2 for i in (0,1)],
                          numbers=numbers,axis=cut['direction'],cut_line=[cut['a'],cut['b']],basis='native_symbol_attributes_and_strokes'))
    source=[r for r in geometry['lines'] if not any(under(r.get('path',[]),p) for p in excluded)]
    # Exploded marks need readable repeated IDs at both endpoints. Limit probes
    # through a spatial text index and section-title IDs, not every line/text pair.
    codes={v for n in notes if n['kind']=='view_title' for v in re.findall(r'\b([A-Z0-9]+)\s*[-–]\s*\1\b',normalise(n['text']))}
    text_grid=defaultdict(list)
    for t in texts:
        if normalise(t['text']) in codes:text_grid[tuple(math.floor(v/250) for v in t['point'])].append(t)
    exploded=[]
    if text_grid:
        for run in runs(source):
            if math.dist(run['a'],run['b'])<100:continue
            nearby={}
            for point in (run['a'],run['b']):
                cell=[math.floor(v/250) for v in point]
                for x in range(cell[0]-1,cell[0]+2):
                    for y in range(cell[1]-1,cell[1]+2):
                        for t in text_grid.get((x,y),[]):nearby[t['handle']]=t
            number=endpoint_numbers(run,list(nearby.values()))
            if number:exploded.append((number[0],run))
        grouped=defaultdict(list)
        for number,run in exploded:grouped[number,run['direction']].append(run)
        for (number,direction),candidates in grouped.items():
            if len(candidates)!=1:
                issues.append(f'Dấu cắt {number}: nhiều đường cùng hướng khớp cặp chữ; không tự chọn.')
                continue
            run=candidates[0];handles=[source_key(r) for r in run['rows']];excluded_keys.update(handles)
            notes.append(dict(kind='section_marker',handle='scan-cut:'+min(handles),point=[(run['a'][i]+run['b'][i])/2 for i in (0,1)],
                              numbers=[number],axis=direction,cut_line=[run['a'],run['b']],basis='repeated_endpoint_text_and_collinear_strokes'))
    source=[r for r in source if source_key(r) not in excluded_keys]
    from cad_style import metadata
    outlines=[dict(handle=source_key(r),layer=r.get('layer',''),points=[r['a'],r['b']],**metadata(r)) for r in source]
    if not outlines:raise ValueError('Vùng quét chỉ có chữ/ký hiệu, chưa có nét hình học sản phẩm.')
    points=[p for r in outlines for p in r['points']]+[n['point'] for n in notes]
    box=union([[*p,*p] for p in points]);regions=[[box[0]-1,box[1]-1,box[2]+1,box[3]+1]]
    capture=dict(engine='native-scan-views-v1',text_objects=len(texts),view_titles=sum(n['kind']=='view_title' for n in notes),
                 section_markers=sum(n['kind']=='section_marker' for n in notes),excluded_symbol_groups=len(excluded),
                 issues=list(dict.fromkeys(issues)),seconds=round(time.perf_counter()-started,6),capture_seconds=geometry.get('capture_seconds'))
    if not capture['section_markers']:capture['issues'].append('Vùng quét chưa có dấu cắt đọc được; cần cả mã cắt và đường cắt trên mặt đứng. Chữ đã nổ thành nét không được OCR/đoán mã.')
    return outlines,notes,regions,capture
