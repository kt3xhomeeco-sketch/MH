"""Measured W/D/H links. Inspection-row offsets never enter this coordinate graph."""
from copy import deepcopy
from time import perf_counter

from geometry import TOL,near,union
from views import title_role
from view_signatures import align,long_edges,match


def edge(target,source,rows,axis='W',target_axis=0,source_axis=0,**kwargs):
    return dict(target_id=target,source_id=source,axis=axis,target_axis=target_axis,source_axis=source_axis,
                **kwargs,**align(rows[target],rows[source],target_axis,source_axis,**kwargs))


def front_link(target,source,rows,target_floor=None,source_floor=None):
    from front_bands import align_fronts
    link=dict(target_id=target,source_id=source,axis='W',target_axis=0,source_axis=0,
              **align_fronts(rows[target],rows[source],target_floor,source_floor))
    if link['status']=='insufficient':
        strokes=match(long_edges(rows[target],0),long_edges(rows[source],0))
        link=dict(target_id=target,source_id=source,axis='W',target_axis=0,source_axis=0,basis='long_edge_chain',**strokes)
    return link


def score(link):
    return link.get('changed_gap',{}).get('sequence_coverage',link.get('coverage',0))


def inverse(link):
    result=deepcopy(link)
    result['target_id'],result['source_id']=link['source_id'],link['target_id']
    result['target_axis'],result['source_axis']=link['source_axis'],link['target_axis']
    for key,other in [('target_slice','source_slice')]:
        a,b=result.pop(key,None),result.pop(other,None)
        if a is not None:result[other]=a
        if b is not None:result[key]=b
    result['offset_mm']=-link['offset_mm']
    if result.get('changed_gap'):
        g=result['changed_gap'];g['target_stations'],g['source_stations']=g['source_stations'],g['target_stations']
        for k in ('left_offset_mm','right_offset_mm','gap_difference_mm'):g[k]=-g[k]
    for c in result.get('candidates',[]):
        c['offset_mm']=-c['offset_mm']
        for m in c['matches']:m['target'],m['source']=m['source'],m['target']
    return result


def pose(root,view,path):
    result=dict(status='proven',axis='W',root_id=root,view_id=view,scale=1,
                offset_mm=round(sum(e['offset_mm'] for e in path),6),path=path,
                reason='Ghép chuỗi ván qua mặt đứng bỏ cánh.' if len(path)>1 else 'Ghép trực tiếp chuỗi ván.')
    warnings=list(dict.fromkeys(e['warning'] for e in path if e.get('warning')))
    if warnings:result['warning']=' '.join(warnings)
    return result


def cut_slice(plan,front,summaries):
    """A measured cut level transfers only between compatible front frames.

    This is a slicing constraint, not permission to infer a module height.
    """
    levels=[]
    for cut in plan.get('section_links',[]):
        linked=summaries.get(cut['front_id']);line=cut.get('cut_line')
        if cut['axis']!='horizontal' or not linked or not line:continue
        a,b=linked['box'],front['box']
        if not near(a[3]-a[1],b[3]-b[1]):continue
        if not near(line[0][1],line[1][1]) or near(line[0][0],line[1][0]):continue
        z=(line[0][1]+line[1][1])/2-a[1]
        if -TOL<=z<=b[3]-b[1]+TOL:levels.append(b[1]+z)
    if levels and all(near(x,levels[0]) for x in levels):return sum(levels)/len(levels)
    return None


def build(summaries,rows):
    summaries={id:dict(v,box=v.get('box') or union([[*p,*p] for r in rows[id] for p in r['points']]),stock_count=v.get('stock_count',0)) for id,v in summaries.items() if id in rows}
    started=perf_counter();poses={};families=[]
    groups={}
    for v in summaries.values():
        if v['id'] not in rows or v['role'] not in ('plan','elevation'):continue
        groups.setdefault(v.get('reference_family'),[]).append(v)
    for family,views in groups.items():
        plans=sorted([v for v in views if v['role']=='plan'],key=lambda v:v['box'][0])
        if not plans:continue
        seed=plans[0];sid=seed['id'];poses[sid]=pose(sid,sid,[])
        fronts=sorted([v for v in views if v['role']=='elevation'],key=lambda v:(title_role(v.get('title',''))!='front_open',-v['stock_count'],v['box'][0]))
        links=[];anchor=None;root_link=None
        for front in fronts:
            at=cut_slice(seed,front,summaries)
            link=edge(sid,front['id'],rows,**({'source_slice':at} if at is not None else {}))
            links.append(link)
            if link['status']=='proven' and (root_link is None or score(link)>score(root_link)):
                anchor=front;root_link=link
        if anchor is None:
            for v in views:
                if v is seed:continue
                link=edge(sid,v['id'],rows);links.append(link)
                poses[v['id']]=pose(sid,v['id'],[link]) if link['status']=='proven' else dict(status=link['status'],axis='W',root_id=sid,view_id=v['id'],reason=link['reason'],candidates=link['candidates'])
        else:
            aid=anchor['id'];poses[aid]=pose(sid,aid,[root_link])
            for v in views:
                vid=v['id']
                if vid in (sid,aid):continue
                at=cut_slice(v,anchor,summaries) if v['role']=='plan' else None
                link=edge(vid,aid,rows,source_slice=at) if at is not None else (front_link(aid,vid,rows,anchor['box'][1],v['box'][1]) if v['role']=='elevation' else edge(aid,vid,rows))
                links.append(link)
                path=[root_link,inverse(link) if at is not None and link['status']=='proven' else link]
                if link['status']=='proven':
                    result=pose(sid,vid,path)
                    # A separate measured chain must agree with the preferred
                    # open-front path; a weaker repeated seam cannot override it.
                    direct=edge(sid,vid,rows);links.append(direct)
                    if direct['status']=='proven' and not near(direct['offset_mm'],result['offset_mm']):
                        strength=min(score(e) for e in path)
                        if score(direct)>strength+.000001:
                            result=pose(sid,vid,[direct]);result['warning']='Chuỗi trực tiếp có tỉ lệ khớp cao hơn; hình nguồn có thể thiếu/sai nét.'
                        elif abs(score(direct)-strength)<=.000001:
                            result=dict(status='conflict',axis='W',root_id=sid,view_id=vid,reason='Chuỗi ghép trực tiếp và qua mặt đứng cho hai vị trí khác nhau.',alternatives=[path,[direct]])
                        else:result['rejected_link']=dict(target_id=sid,source_id=vid,offset_mm=direct['offset_mm'],matched_pairs=direct['matched_pairs'],reason='Ít vị trí ván khớp hơn đường ghép qua mặt đứng bỏ cánh.')
                    poses[vid]=result
                else:
                    direct=edge(sid,vid,rows);links.append(direct)
                    poses[vid]=pose(sid,vid,[direct]) if direct['status']=='proven' else dict(status=link['status'],axis='W',root_id=sid,view_id=vid,reason=link['reason'],candidates=link['candidates'])
        families.append(dict(family=family,root_id=sid,anchor_id=anchor['id'] if anchor else None,links=links))
    return dict(schema=1,engine='stock-axis-chains-v1',poses=poses,families=families,seconds=round(perf_counter()-started,6))


def source_rows(product):
    return {v['id']:[product['outlines'][i] for i in v['source_row_indices']] if 'source_row_indices' in v else v['outlines'] for v in product.get('view_previews',[])}


def depth_link(plan_id,side_id,rows,plan_x,side_z,reverse):
    if reverse is None:return dict(status='ambiguous',reason='Chưa rõ hướng nhìn mặt cắt để kiểm tra chuỗi chiều sâu.')
    kwargs=dict(target_slice=plan_x,reverse=reverse)
    if side_z is not None:kwargs['source_slice']=side_z
    return edge(plan_id,side_id,rows,'D',1,0,**kwargs)
