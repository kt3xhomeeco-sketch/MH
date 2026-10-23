"""Horizontal CAD reference heights from located cut strokes, never DIM text."""
from math import isfinite

from elevation_geometry import marker_axis
from geometry import TOL,near


def measure_levels(product,data):
    summaries={v['id']:v for v in product['view_analysis']['candidates']}
    result={}
    for view in summaries.values():
        if view['role']!='plan':continue
        links=[];issues=[]
        for cut in view['section_links']:
            if cut['axis']!='horizontal':continue
            marker=data['markers'].get(cut['marker_handle']);front=summaries.get(cut['front_id'])
            if not marker or marker_axis(marker)!='horizontal' or not front or front['role']!='elevation':
                issues.append('Dấu cắt ngang chưa có đường cắt/mặt đứng hợp lệ.');continue
            line=marker['cut_line'];box=front['box'];height=box[3]-box[1]
            level=sum(p[1] for p in line)/2-box[1]
            if not isfinite(level) or level<-TOL or level>height+TOL:
                issues.append('Dấu cắt ngang nằm ngoài chiều cao mặt đứng.');continue
            links.append(dict(marker_handle=cut['marker_handle'],front_id=front['id'],front_box=box,
                              cut_line=line,level_mm=round(level,6)))
        if links and not issues and all(near(v['level_mm'],links[0]['level_mm']) for v in links):
            result[view['id']]=dict(status='measured',view_id=view['id'],level_mm=links[0]['level_mm'],
                                    basis='horizontal_cut_geometry',links=links)
        else:
            issue='Các dấu cắt ngang cho cao độ khác nhau.' if links and not issues else '; '.join(dict.fromkeys(issues)) or 'Chưa có dấu cắt ngang liên kết để xác định cao độ.'
            result[view['id']]=dict(status='pending',view_id=view['id'],issue=issue)
    return result


def stack_offsets(children):
    """CAD stacking leaves the existing module inspection-row layout untouched."""
    first=children[0];first_base=first['plan_reference']['source_origin_mm']
    for child in children[1:]:
        view=next((v for v in first['plan_reference'].get('views',[]) if v['id']==child['plan_view_id'] and v.get('role')=='plan'),None)
        if view is None:continue
        base=child['plan_reference']['source_origin_mm']
        child['cad_reference_offset_mm']=[round(first['display_layout']['offset_mm'][i]-child['display_layout']['offset_mm'][i]+base[i]-first_base[i]+view.get('xy_offset_mm',[0,0])[i],6) for i in (0,1)]
        child['cad_reference_shared']=True


def inspection_levels(levels):
    """User-approved display spacing is never a measured cutting elevation."""
    known=[level['level_mm'] for level in levels.values() if level['status']=='measured']
    base=max(known)+1000 if known else 0
    slot=0
    for level in levels.values():
        if level['status']=='measured':continue
        level.update(status='provisional',basis='inspection_spacing',spacing_mm=1000,
                     base_mm=base,slot_index=slot,level_mm=round(base+slot*1000,6))
        slot+=1
    if len(levels)==1:
        next(iter(levels.values())).update(placement_basis='single_plan_zero',placement_z_mm=0,plan_count=1)
    return levels
