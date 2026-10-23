"""Physical-axis stock signatures and bounded gap-indexed translation hypotheses."""
from collections import defaultdict,OrderedDict
from copy import deepcopy

from cad_datums import measure
from geometry import TOL,near
from materials import BOARD_MM

_MATCHES=OrderedDict()


def long_edges(rows,axis):
    """Merged structural strokes for a door front without visible stock pairs."""
    bins=defaultdict(list);points=[p for r in rows for p in r['points']]
    if not points:return []
    threshold=max(100,(max(p[1-axis] for p in points)-min(p[1-axis] for p in points))*.4)
    for row in rows:
        for a,b in zip(row['points'],row['points'][1:]):
            if not near(a[axis],b[axis]):continue
            pos=(a[axis]+b[axis])/2
            bins[round(pos/TOL)].append((pos,min(a[1-axis],b[1-axis]),max(a[1-axis],b[1-axis])))
    result=[]
    for values in bins.values():
        spans=sorted(values,key=lambda v:v[1]);lo=hi=None;longest=0
        for _,a,b in spans:
            if hi is None or a>hi+TOL:lo,hi=a,b
            else:hi=max(hi,b)
            longest=max(longest,hi-lo)
        if longest>=threshold:result.append([sum(v[0] for v in values)/len(values)]*2+[longest])
    return sorted(result)


def signature(rows,axis,slice_at=None):
    datum=measure(rows,[0,0])
    if not datum:return []
    bins=defaultdict(list)
    for panel in datum['panels']:
        b=panel['box_mm'];lo,hi=b[axis],b[axis+2];span=b[3-axis]-b[1-axis]
        if span<=max(40,3*(hi-lo)) or not any(near(hi-lo,s) for s in BOARD_MM):continue
        if slice_at is not None and not b[1-axis]-TOL<=slice_at<=b[3-axis]+TOL:continue
        key=round(lo/TOL)
        old=next((p for k in (key-1,key,key+1) for p in bins[k] if near(p[0],lo) and near(p[1],hi)),None)
        if old is None:bins[key].append([lo,hi,span])
        else:old[2]=max(old[2],span)
    pairs=sorted(p for ps in bins.values() for p in ps)
    # A measured18+18 seam contributes two atomic faces, not an extra36 vote.
    def compound(p):
        if not near(p[1]-p[0],36):return False
        key=round(p[0]/TOL)
        first=[q for k in (key-1,key,key+1) for q in bins[k] if near(q[0],p[0]) and near(q[1]-q[0],18)]
        key=round((p[0]+18)/TOL)
        return bool(first) and any(near(q[0],p[0]+18) and near(q[1],p[1]) for k in (key-1,key,key+1) for q in bins[k])
    return [p for p in pairs if not compound(p)]


def _tokens(pairs):
    """Index at most the next3 stations, never all possible parallel pairs."""
    for i,a in enumerate(pairs):
        for b in pairs[i+1:i+4]:
            gap=(b[0]+b[1]-a[0]-a[1])/2
            if gap>2*TOL:yield a,b,gap


def changed_gap(target,source,candidates):
    """One edited gap moves a whole suffix. Compare gaps once in source order."""
    if len(target)!=len(source) or len(target)<4:return None
    if any(not near(a[1]-a[0],b[1]-b[0]) for a,b in zip(target,source)):return None
    offsets=[sum(a[i]-b[i] for i in (0,1))/2 for a,b in zip(target,source)]
    breaks=[i for i in range(len(offsets)-1) if not near(offsets[i],offsets[i+1])]
    if len(breaks)!=1:return None
    i=breaks[0]
    if i<1 or i>len(target)-3:return None # Two measured stations on either side.
    left=sum(offsets[:i+1])/(i+1);right=sum(offsets[i+1:])/(len(target)-i-1)
    side='left' if i+1>=len(target)-i-1 else 'right'
    offset=left if side=='left' else right
    chosen=next((c for c in candidates if near(c['offset_mm'],offset)),None)
    if chosen is None:return None
    indices=range(i+1) if side=='left' else range(i+1,len(target))
    matches=[dict(target=target[j][:2],source=source[j][:2],residual_mm=round(max(abs(target[j][k]-source[j][k]-offset) for k in (0,1)),6)) for j in indices]
    chosen=dict(chosen,offset_mm=round(offset,6),matches=matches,matched_pairs=len(matches),coverage=round(len(matches)/len(target),6),
                target_coverage=round(len(matches)/len(target),6),source_coverage=round(len(matches)/len(source),6))
    return dict(candidate=chosen,proof=dict(break_after=i,target_stations=[p[:2] for p in target],source_stations=[p[:2] for p in source],
        left_offset_mm=round(left,6),right_offset_mm=round(right,6),anchor_side=side,
        gap_difference_mm=round(right-left,6),sequence_coverage=1.0))


def match(target,source,reverse=False):
    """Find source -> target translation; scales and envelope tie-breaks are forbidden."""
    key=(tuple(tuple(p[:2]) for p in target),tuple(tuple(p[:2]) for p in source),reverse)
    if key in _MATCHES:
        _MATCHES.move_to_end(key);return deepcopy(_MATCHES[key])
    value=_match(target,source,reverse)
    _MATCHES[key]=deepcopy(value)
    if len(_MATCHES)>256:_MATCHES.popitem(last=False)
    return value


def _match(target,source,reverse):
    if reverse:source=sorted([[-b,-a,span] for a,b,span in source])
    if min(len(target),len(source))<2:return dict(status='insufficient',matched_pairs=0,candidates=[],reason='Cần ít nhất hai vị trí tấm độc lập theo trục đang đối chiếu.')
    index=defaultdict(list)
    for a,b,gap in _tokens(target):index[round(gap/(2*TOL))].append((a,b,gap))
    votes=defaultdict(list);overflow=False;probes=0
    for a,b,gap in _tokens(source):
        k=round(gap/(2*TOL))
        for j in (k-1,k,k+1):
            bucket=index[j]
            if len(bucket)>128:overflow=True;continue
            for x,y,g in bucket:
                probes+=1
                if abs(g-gap)>2*TOL or not near(x[1]-x[0],a[1]-a[0]) or not near(y[1]-y[0],b[1]-b[0]):continue
                dx=sum((x[i]-a[i])+(y[i]-b[i]) for i in (0,1))/4
                votes[round(dx/TOL)].append(dx)
    if len(votes)>256:overflow=True
    hypotheses=sorted(votes,key=lambda k:len(votes[k]),reverse=True)[:256]
    offsets=[]
    for k in hypotheses:
        dx=sum(votes[k])/len(votes[k])
        if not any(near(dx,x) for x in offsets):offsets.append(dx)
    bins=defaultdict(list)
    for i,p in enumerate(target):bins[round(p[0]/TOL)].append((i,p))
    candidates=[]
    for dx in offsets:
        matches=[];used=set()
        for a,b,_ in source:
            k=round((a+dx)/TOL)
            found=[(i,p) for j in (k-1,k,k+1) for i,p in bins[j] if i not in used and near(p[0],a+dx) and near(p[1],b+dx)]
            if not found:continue
            i,p=min(found,key=lambda item:abs(item[1][0]-a-dx)+abs(item[1][1]-b-dx));used.add(i)
            matches.append(dict(target=p[:2],source=[a,b],residual_mm=round(max(abs(p[0]-a-dx),abs(p[1]-b-dx)),6)))
        if len(matches)<2:continue
        coverage=len(matches)/min(len(target),len(source))
        span=max(m['target'][1] for m in matches)-min(m['target'][0] for m in matches)
        if span<=72+TOL:continue # Adjacent18+18 faces alone are one seam, not two independent stations.
        candidates.append(dict(offset_mm=round(dx,6),scale=-1 if reverse else 1,matched_pairs=len(matches),coverage=round(coverage,6),
            target_count=len(target),source_count=len(source),target_coverage=round(len(matches)/len(target),6),source_coverage=round(len(matches)/len(source),6),span_mm=round(span,6),matches=matches))
    candidates.sort(key=lambda c:(c['matched_pairs'],c['coverage'],c['span_mm']),reverse=True)
    if not candidates:return dict(status='insufficient',matched_pairs=0,candidates=[],probes=probes,reason='Không có chuỗi cặp ván cùng khoảng cách theo trục này.')
    changed=changed_gap(target,source,candidates)
    if changed and not overflow:
        best=changed['candidate']
        return dict(status='proven',**{k:v for k,v in best.items() if k!='matches'},candidates=[best],probes=probes,
            changed_gap=changed['proof'],warning='Một khoảng nối tiếp bị thay đổi; hai phía còn lại khớp theo thứ tự. Chỉ căn phía có nhiều nét khớp hơn (bằng nhau: phía trái), giữ nguyên hình và báo phần lệch.',
            reason='Nhận cùng bộ hình qua hai chuỗi hai phía của một khoảng bị stretch; không áp ngưỡng sai lệch tổng để loại.')
    best=candidates[0]
    tied=[c for c in candidates if c['matched_pairs']==best['matched_pairs'] and abs(c['coverage']-best['coverage'])<.000001]
    proven=len(tied)==1 and not overflow
    return dict(status='proven' if proven else 'ambiguous',**{k:v for k,v in best.items() if k!='matches'},
                candidates=(tied if not proven else candidates)[:8],probes=probes,
                reason='Chuỗi cặp ván có một vị trí ghép.' if proven else 'Có nhiều vị trí khớp chuỗi ván; chưa tự chọn theo mép bao.')


def align(target_rows,source_rows,target_axis=0,source_axis=0,target_slice=None,source_slice=None,reverse=False):
    result=match(signature(target_rows,target_axis,target_slice),signature(source_rows,source_axis,source_slice),reverse)
    if result['status']=='insufficient' or target_slice is not None or source_slice is not None:return result
    a,b=measure(target_rows,[0,0]),measure(source_rows,[0,0])
    if not a or not b:return result
    lo,hi=a['box_mm'][target_axis],a['box_mm'][target_axis+2]
    x,y=b['box_mm'][source_axis],b['box_mm'][source_axis+2]
    if reverse:x,y=-y,-x
    difference=abs((hi-lo)-(y-x))/max(hi-lo,y-x,TOL)
    result['dimension_difference_percent']=round(100*difference,3)
    if difference>TOL/max(hi-lo,y-x,TOL):result['warning']=(result.get('warning','')+' Kích thước tổng khác nhau; giữ tỉ lệ khớp cao nhất và số đo gốc, không co giãn hình.').strip()
    # Equal measured cabinet extents are a separate dimension constraint, not
    # an arbitrary nearest-raw-envelope preference among periodic candidates.
    if near(hi-lo,y-x):
        valid=[c for c in result['candidates'] if c['matched_pairs']==result['matched_pairs'] and near(x+c['offset_mm'],lo) and near(y+c['offset_mm'],hi)]
        if len(valid)==1:
            chosen=valid[0]
            result.update({k:chosen[k] for k in ('offset_mm','scale','matched_pairs','coverage','span_mm')})
            result.update(status='proven',candidates=[chosen],dimension_check=dict(basis='equal_stock_extents',target_mm=[lo,hi],source_mm=[x,y]),reason='Chuỗi ván và hai mép tủ đo được cùng xác nhận vị trí ghép.')
        elif not valid:result['warning']='Hai mép tổng chưa cùng khớp; giữ phương án có tỉ lệ nét khớp cao nhất, không co giãn hình.'
    return result
