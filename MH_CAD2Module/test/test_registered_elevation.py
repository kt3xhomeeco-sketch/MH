import pytest

from main import run
from plan_reader import raw_signature
from scan_views import prepare
from library import atomic_json
from parallel_index import ParallelIndex
from test_deep_end_scan import source


def build(tmp_path,lines=None,confirm=True,top=True,box=None):
    g=dict(hash='f'*64,plane='XY',plane_offset_mm=73,lines=lines or source())
    rows,*_=prepare(g);signature=raw_signature(rows)
    if confirm:
        context=dict(source_signature=signature,module_joint_levels_mm=[692],event_id='QA',top_trim=top)
        if box is not None:context['top_trim_box_mm']=box
        if top is None:context.pop('top_trim')
        atomic_json(tmp_path/'source_context'/f'{signature}.json',context)
    return run(dict(action='geometry',library=str(tmp_path),geometry=g,build_elevation=True))['analyses'][0]['products'][0]


def test_actual_geometry_builds_four_tiers_two_ends_and_two_parallel_proven_top_parts(tmp_path):
    p=build(tmp_path)
    assert p['geometry_pipeline']['horizontal']['status']=='measured' and not p['elevation_pending']
    assert [m['size'] for m in p['modules']]==[[970,520,642],[970,520,2008],[485,520,642],[485,520,2008]]
    assert [m['origin'][2] for m in p['modules']]==[50,692,50,692]
    assert [m['size'] for m in p['trim_parts'][:2]]==[[18,600,2700],[18,600,2700]]
    assert [m['size'][1:] for m in p['trim_parts'][2:]]==[[18,30],[50,18]]
    assert [m['origin'][1:] for m in p['trim_parts'][2:]]==[[0,2700],[18,2700]]
    assert p['bounds']==[1491,600,2730] and p['placement']['plane_offset_mm']==73
    assert all(m['elevation_evidence']['parallel_proof']=='parallel_faces_and_closed_ends' for m in p['trim_parts'][2:])
    assert all(m['height_source']=='registered_view_geometry' for k in ('modules','trim_parts') for m in p[k])


def test_source_confirmations_are_required_and_do_not_supply_dimensions(tmp_path):
    p=build(tmp_path,confirm=False)
    assert p['elevation_pending'] and all(m['size'][2]==2700 for m in p['modules'])
    assert p['product_height']['module_tiers_measured'] is False
    assert any('chưa xác nhận' in issue for issue in p['geometry_pipeline']['horizontal']['issues'])


@pytest.mark.parametrize('top',[False,None])
def test_unconfirmed_or_explicitly_architectural_top_is_not_invented(tmp_path,top):
    p=build(tmp_path,top=top)
    assert len(p['modules'])==4 and len(p['trim_parts'])==2
    assert p['bounds'][2]==2700
    assert p['elevation_pending']==(top is None)


def test_confirmed_geometry_can_move_without_losing_measured_sizes(tmp_path):
    lines=source()
    for r in lines:
        for key in ('a','b'):r[key]=[r[key][0]-20000,r[key][1]+50000]
    p=build(tmp_path,lines)
    assert not p['elevation_pending'] and [m['size'][2] for m in p['modules']]==[642,2008,642,2008]


def test_missing_section_boundary_cannot_borrow_a_distant_shelf(tmp_path):
    lines=source();sx,sy=11778.880535237637,1432.415513444169
    # Remove the upper module bottom cap, not a DIM or text label.
    lines=[r for r in lines if not (all(sx+23.9<=r[k][0]<=sx+480.1 for k in ('a','b')) and
            all(abs(r[k][1]-(sy+692))<.1 or abs(r[k][1]-(sy+710))<.1 for k in ('a','b')))]
    p=build(tmp_path,lines)
    assert p['elevation_pending'] and len(p['modules'])==2


def test_changed_geometry_never_reuses_the_old_source_confirmation(tmp_path):
    p=build(tmp_path);lines=source()
    lines.append(dict(handle='new-geometry',path=[],a=[0,0],b=[0,5]))
    p=build(tmp_path,lines,confirm=False)
    assert p['elevation_pending']


def test_short_trim_stock_pair_needs_both_closing_caps_and_is_opt_in():
    lines=[([0,0],[18,0],'B'),([18,0],[18,30],'R'),([18,30],[0,30],'T'),([0,30],[0,0],'L')]
    assert ParallelIndex(lines).panels()==[]
    short=ParallelIndex(lines).panels(allow_short=True)
    assert len(short)==1 and short[0]['stock_mm']==18 and short[0]['length_mm']==30
    assert ParallelIndex(lines[:-1]).panels(allow_short=True)==[]


def test_plan_only_still_keeps_1600_even_with_source_context(tmp_path):
    build(tmp_path)
    p=run(dict(action='geometry',library=str(tmp_path),geometry=dict(hash='e'*64,lines=source())))['analyses'][0]['products'][0]
    assert p['build_stages']['elevation'] is False
    assert all(m['size'][2]==1600 for m in p['modules'])


def test_one_solid_trim_is_source_confirmed_and_keeps_both_measured_panel_proofs(tmp_path):
    p=build(tmp_path,box=[50,30])
    assert not p['elevation_pending'] and len(p['trim_parts'])==3
    trim=p['trim_parts'][-1]
    assert trim['size'][1:]==[50,30] and trim['origin'][1:]==[0,2700]
    ev=trim['elevation_evidence']
    assert ev['kind']=='top_trim_proxy' and ev['confirmed_box_mm']==[50,30]
    assert len(ev['section_parts'])==2 and ev['confirmation_event']=='QA'
    assert trim['source_box'][3]-trim['source_box'][1]==pytest.approx(50)
    assert 'stock_thickness_mm' not in trim
    # Updating context must work without changing/reloading the CAD source.
    assert len(build(tmp_path)['trim_parts'])==4


@pytest.mark.parametrize('box',[[68,30],[50,40],[-50,30],[50],['50',30]])
def test_invalid_trim_box_cannot_override_measured_section(tmp_path,box):
    p=build(tmp_path,box=box)
    assert p['elevation_pending'] and len(p['modules'])==2
    assert any('nẹp' in warning.lower() for warning in p['warnings'])
