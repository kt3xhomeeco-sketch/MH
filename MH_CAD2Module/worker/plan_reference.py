"""Transport measured plan edges/arcs to a separate native SketchUp Group."""
from plan_profiles import arc_runs,arc_bounds
from plan_evidence import edge_key
from geometry import union


def prepare_reference(product):
    if (product.get('status')!='ready' and not product.get('envelope_preview')) or not product.get('envelope'):return
    rows=product.get('cad_reference_outlines',product.get('selected_plan_outlines',product['outlines']));base=product['envelope'][:2]
    if product.get('build_stages',{}).get('elevation') and product.get('geometry_pipeline',{}).get('mode')!='plan_and_elevation':
        horizontal=product.get('geometry_pipeline',{}).get('horizontal',{})
        first=product['modules'][0]
        if 'x_offset' not in horizontal or 'plan_box' not in first:return
        base=[product['envelope'][0]-horizontal['x_offset'],first['plan_box'][1]-first.get('carcass_origin',first['origin'])[1]]
    elif product.get('source_plan_envelope'):
        base=[product['source_plan_envelope'][i]+product.get('plan_origin_offset_mm',[0,0])[i] for i in (0,1)]
    arcs=arc_runs(rows);curved={key for arc in arcs for key in arc['source_edges']}
    segments=[];seen={};edge_rows={}
    def local(point):return [round(point[i]-base[i],6) for i in (0,1)]
    for row_id,row in enumerate(rows):
        for a,b in zip(row['points'],row['points'][1:]):
            key=edge_key(a,b);edge_rows.setdefault(key,set()).add(row_id)
            if key in curved:continue
            if key in seen:
                segments[seen[key]]['source_rows'].append(row_id);continue
            seen[key]=len(segments)
            segments.append(dict(type='line',start=local(a),end=local(b),handles=[row['handle']],source_rows=[row_id]))
    for arc in arcs:
        segments.append(dict(type='arc',start=local(arc['start']),end=local(arc['end']),center=local(arc['center']),
                             radius=arc['radius'],sweep=arc['sweep'],segments=arc['segments'],handles=arc['handles'],
                             source_rows=sorted({i for key in arc['source_edges'] for i in edge_rows.get(key,[])})))
    product['plan_reference']=dict(schema=1,source_origin_mm=base,
                                  view_id=product.get('view_analysis',{}).get('selected_view_id'),segments=segments)
    if product.get('cad_reference_level'):
        level=product['cad_reference_level']
        product['plan_reference'].update(level=level,z_mm=level.get('placement_z_mm',level.get('level_mm',0)),
            xy_offset_mm=product.get('cad_reference_offset_mm',[0,0]),shared=product.get('cad_reference_shared',False))
    if product.get('cad_reference_outlines'):
        box=union([[*p,*p] for row in rows for p in row['points']]+[arc_bounds(a) for a in arcs])
        product['plan_reference'].update(scope='all_views',bounds_mm=[round(v-base[i%2],6) for i,v in enumerate(box)],
            source_outline_count=len(rows),view_count=len(product.get('view_analysis',{}).get('candidates',[])))
        from cad_views import prepare_views
        product['plan_reference'].update(prepare_views(product,rows,base,segments))
