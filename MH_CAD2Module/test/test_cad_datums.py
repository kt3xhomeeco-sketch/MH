from copy import deepcopy
import math

import pytest

from cad_datums import measure,front_at
from cad_registration import register
from cad_views import project
from cad_views import depth_direction


def rect(handle,x,y,w,h,layer='wood'):
    return dict(handle=handle,layer=layer,points=[[x,y],[x+w,y],[x+w,y+h],[x,y+h],[x,y]])


@pytest.mark.parametrize('stock',[3,6,9,12,15,18,25,36])
def test_only_closed_standard_pairs_supply_registration_datums(stock):
    panels=[rect('left',0,0,stock,600),rect('right',1000-stock,0,stock,600)]
    noise=[rect(str(t),-1000-t*100,-500,t,700) for t in (20,24,30,50,100)]
    noise += [dict(handle='open18',points=[[-200,0],[-200,600],[-182,600],[-182,0]])]
    # The open stroke above has no bottom cap, so it is not a closed panel.
    datum=measure(panels+noise,[0,0])
    assert datum['box_mm']==pytest.approx([0,0,1000,600])
    assert all(set(p['handles'])<={'left','right'} for p in datum['panels'])


def test_rotated_stock_profile_and_segmented_bevel_remain_measured():
    angle=.37;c,s=math.cos(angle),math.sin(angle)
    r=rect('diagonal',100,50,18,600)
    r['points']=[[c*x-s*y,s*x+c*y] for x,y in r['points']]
    door=dict(handle='door',points=[[800,0],[818,0],[818,770],[813,770],[800,757],[800,0]])
    edges=[dict(handle=f'd{i}',points=[a,b]) for i,(a,b) in enumerate(zip(door['points'],door['points'][1:]))]
    datum=measure([r]+edges,[0,0])
    assert any(p['box_mm']==[800,0,818,770] for p in datum['panels'])
    assert any(p['handles']==['diagonal'] for p in datum['panels'])


@pytest.mark.parametrize('reverse',[False,True])
def test_walls_and_nonstock_context_cannot_push_side_back(reverse):
    plan=[rect('pl',0,0,18,600),rect('pr',982,0,18,600),rect('pf',0,0,1000,18),rect('pb',0,582,1000,18)]
    side=[rect('sl',2000,2000,18,900),rect('sr',2582,2000,18,900),rect('st',2000,2882,600,18)]
    def build(context):
        p=deepcopy(plan);s=deepcopy(side)
        if context:
            p += [rect('wall',-50,-400,1100,200,'wall'),rect('dashed',-25,900,1100,25,'ZX-NÉT ĐỨT (6)')]
            s += [rect('side-wall',1700,2000,200,950,'wall'),rect('side-dashed',1700,2900,950,25,'ZX-NÉT ĐỨT (6)')]
        def box(rows):
            ps=[p for r in rows for p in r['points']]
            return [min(p[0] for p in ps),min(p[1] for p in ps),max(p[0] for p in ps),max(p[1] for p in ps)]
        entries=[(dict(id='P',box_mm=box(p)),p),(dict(id='S',box_mm=box(s)),s)]
        product={'view_analysis':{'candidates':[dict(id='P',role='plan',reference_family='F'),dict(id='S',role='section_vertical',reference_family='F')]}}
        # Direction is tested separately from arrow parsing; inject the geometric decision.
        import cad_views
        original=cad_views.depth_direction
        try:
            cad_views.depth_direction=lambda *args:reverse
            register(entries,product,[0,0],entries[0][0])
        finally:cad_views.depth_direction=original
        v=entries[1][0];b=v['cabinet_datum']['box_mm']
        ys=[project([b[i],b[1]],v,entries[0][0]['box_mm'])[1] for i in (0,2)]
        return min(ys),max(ys),v
    plain,wall=build(False),build(True)
    assert plain[:2]==wall[:2]==(0,600)
    assert wall[2]['display_x_mm']==plain[2]['display_x_mm']==1000
    assert wall[2]['cabinet_datum']['context_rows_excluded']==2


def test_l_plan_cut_uses_local_arm_front_not_global_minimum():
    rows=[rect('a',0,0,18,600),rect('b',1982,0,18,600),rect('front',0,0,2000,18),rect('back',0,582,2000,18),
          rect('return-a',0,-1200,18,1200),rect('return-b',582,-1200,18,1200),rect('return-front',0,-1200,600,18)]
    datum=measure(rows,[0,0])
    assert datum['box_mm'][1]==-1200
    assert front_at(datum,1000)[0]==0
    assert front_at(datum,300)[0]==-1200


@pytest.mark.parametrize('reverse',[False,True])
def test_geometric_direction_is_from_standard_faces_not_context_bounds(reverse):
    plan=[rect('front',0,0,1000,18),rect('rear',0,594,1000,6)]
    side=[rect('a',2000,2000,6 if reverse else 18,900),rect('b',2582 if reverse else 2594,2000,18 if reverse else 6,900)]
    pd,sd=measure(plan,[0,0]),measure(side,[0,0])
    assert depth_direction(pd,sd) is reverse
    noisy=plan+[rect('noise',-1000,-700,900,24),rect('wall',-1000,2000,2000,200,'wall')]
    assert depth_direction(measure(noisy,[0,0]),sd) is reverse


def test_cached_datums_are_immutable_and_changed_geometry_remeasures():
    rows=[rect('a',0,0,18,600),rect('b',982,0,18,600)]
    a=measure(rows,[0,0]);a['box_mm'][1]=-900
    assert measure(rows,[100,200])['box_mm']==[-100,-200,900,400]
    rows[0]['points']=[[x,y-50] for x,y in rows[0]['points']]
    assert measure(rows,[0,0])['box_mm'][1]==-50


def test_actual_sp27_excludes_wall_depth_but_preserves_complete_source(tmp_path):
    import json
    from pathlib import Path
    from combined_runtime import analyse
    from drawing_scope import choose_product_plan
    d=json.loads((Path(__file__).parent/'fixtures/named_sp27_datums.json').read_text('utf8'))
    p=d['product'];selected=choose_product_plan(p,d['annotations'],multiple=True);analyse(p,selected,d['annotations'],tmp_path)
    ref=p['plan_reference'];side=next(v for v in ref['views'] if v.get('role')=='section_vertical')
    assert ref['plan_bounds_mm'][3]==785
    assert side['cabinet_datum']['box_mm'][2]-side['cabinet_datum']['box_mm'][0]==600
    assert side['display_y_mm']==0 and side['reversed_depth'] and side['direction_basis']=='symbol_arrows'
    assert sorted(i for v in ref['views'] for i in v['segment_indices'])==list(range(len(ref['segments'])))
