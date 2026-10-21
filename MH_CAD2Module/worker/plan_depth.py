"""Stock-supported Y extent; raw CAD/context is retained independently."""
from cad_datums import measure
from geometry import TOL,near
from materials import BOARD_MM


def evidence(rows):
    datum=measure(rows,[0,0])
    if not datum:return None
    # Axial pairs are the primary depth witness. A diagonal or an unpaired
    # contour cannot extend Y; real rotated plans retain the existing raw path.
    panels=[p for p in datum['panels'] if any(near(min(p['box_mm'][2]-p['box_mm'][0],p['box_mm'][3]-p['box_mm'][1]),s) for s in BOARD_MM)]
    if len(panels)<2:return None
    low=min(p['box_mm'][1] for p in panels);high=max(p['box_mm'][3] for p in panels)
    if high-low<100:return None
    return dict(basis='closed_compatible_stock_pairs',low_mm=low,high_mm=high,panels=panels,
        priority='continuous_axial_stock',context_rows_excluded=datum['context_rows_excluded'])


def preview(product,raw):
    proof=evidence(product.get('outlines',[]))
    if not proof or proof['low_mm']<raw[1]-TOL or proof['high_mm']>raw[3]+TOL:return None
    if raw[3]-raw[1]-(proof['high_mm']-proof['low_mm'])<=TOL:return None
    return proof


def corroborate(child,data):
    """Small plan drawing errors may be checked by repeated linked cuts."""
    proof=child.get('envelope_preview',{}).get('depth_evidence')
    if not proof:return
    candidate=next((v for v in child.get('view_analysis',{}).get('candidates',[]) if v['id']==child.get('plan_view_id')),None)
    if not candidate:return
    family=candidate.get('reference_family');sections=[]
    for view in data.get('views',{}).values():
        if view['role']!='section_vertical' or not family or view.get('reference_family')!=family:continue
        datum=measure(view['outlines'],[0,0])
        if not datum:continue
        box=datum['box_mm'];depth=box[2]-box[0]
        if abs(depth-(proof['high_mm']-proof['low_mm']))>1:continue
        sections.append(dict(view_id=view['id'],title=view.get('title',''),box_mm=box,depth_mm=round(depth,6),
            panels=datum['panels'],reference_family=family))
    if len(sections)<2:return
    if max(s['depth_mm'] for s in sections)-min(s['depth_mm'] for s in sections)>TOL:
        proof['section_check']=dict(status='conflict',sections=sections,issue='Các mặt cắt đứng chưa thống nhất chiều sâu; giữ số đo mặt bằng.')
        return
    chosen=sorted(s['depth_mm'] for s in sections)[len(sections)//2]
    proof['section_check']=dict(status='supported',sections=sections,chosen_depth_mm=chosen,tolerance_mm=1,
        plan_depth_mm=round(proof['high_mm']-proof['low_mm'],6),reference_family=family)
    part=child['modules'][0];part['size'][1]=chosen
    part['source_box'][3]=proof['low_mm']+chosen;part['plan_box']=list(part['source_box'])
    child['bounds'][1]=round(part['origin'][1]+chosen,6)
    names=', '.join(s['title'] or s['view_id'] for s in sections)
    child.setdefault('explanation',[]).append(f'Chiều sâu: mặt bằng đo {proof["high_mm"]-proof["low_mm"]:g} mm; {names} cùng bộ hình đo {chosen:g} mm. Dùng {chosen:g} mm, giữ nét CAD gốc và ghi sai lệch nhỏ.')
