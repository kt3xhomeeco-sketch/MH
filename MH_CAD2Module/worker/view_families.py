"""Associate repeated section names with local, geometrically compatible fronts."""
from geometry import TOL
import re
from views import normalise


def widths(view):
    f=view['features']
    return [b[2]-b[0] for b in (f['box'],f['core_box'])]


def assign(views,fronts):
    from front_bands import align_fronts
    families=[]
    for front in sorted(fronts,key=lambda v:v['features']['box'][0]):
        family=next((g for g in families if any(
            abs(front['features']['height_mm']-peer['features']['height_mm'])<=72+TOL and
            any(abs(a-b)<=min(a,b)*.20+TOL for a in widths(front) for b in widths(peer)) for peer in g)),None)
        if family is None:
            candidates=[]
            for group in families:
                links=[]
                for peer in group:
                    if abs(front['features']['height_mm']-peer['features']['height_mm'])>72+TOL:continue
                    proof=align_fronts(peer['outlines'],front['outlines'],peer['features']['box'][1],front['features']['box'][1])
                    if proof['status']=='proven' and ((proof['matched_pairs']>=3 and proof['coverage']>=.8) or proof.get('height_support',0)>=2):links.append((peer,proof))
                if links:candidates.append((group,links[0]))
            if len(candidates)==1:
                family,(peer,proof)=candidates[0]
                front['family_geometry_link']=dict(front_id=peer['id'],axis='W',**proof)
        if family is None:families.append([front])
        else:family.append(front)
    ids={f['id']:g[0]['id'] for g in families for f in g}
    for view in views:
        if not fronts:continue
        box=view['features']['box'];cx=(box[0]+box[2])/2
        anchor=view if view in fronts else min(fronts,key=lambda f:(
            f.get('sheet_box')!=view.get('sheet_box'),
            abs((f['features']['box'][0]+f['features']['box'][2])/2-cx)))
        view.update(reference_front_id=anchor['id'],reference_family=ids[anchor['id']])


def link_unique_vertical(views,fronts,markers):
    """A partial open front can omit symbols present only on the complete front.

    Keep local repeated-code links first. Cross the family boundary only for a
    unique vertical marker with compatible measured height and stock geometry.
    """
    for view in views:
        f=view['features']
        if view in fronts or view['declared_role'] not in ('section','section_vertical') or f['kind']!='furniture' or f['stock_count']<2 or f['orthogonal_plan']:continue
        if f['width_mm']>1200 or f['height_mm']<f['width_mm']*1.2:continue
        numbers=set(re.findall(r'\b([A-Z0-9]+)\s*[-–]\s*\1\b',normalise(view['title'])))
        matches=[(front,m) for front in fronts for m in markers[front['id']] if numbers.intersection(m.get('numbers',[]))]
        if any(front['reference_family']==view['reference_family'] for front,_ in matches):continue
        candidates=[]
        for front,marker in matches:
            if marker['axis']!='vertical' or not marker.get('cut_line') or f['width_mm']>=max(widths(front))*.5:continue
            delta=min(abs((b[3]-b[1])-(other[3]-other[1])) for b in (f['box'],f['core_box'])
                      for other in (front['features']['box'],front['features']['core_box']))
            if delta<=72+TOL:candidates.append((front,marker))
        if len(candidates)!=1:continue
        front,_=candidates[0]
        view.update(local_reference_front_id=view.get('reference_front_id'),reference_front_id=front['id'],
                    reference_family=front['reference_family'],reference_link_basis='unique_vertical_marker_and_stock_height')
