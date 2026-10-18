"""Real user regressions: incomplete bays, framed doors and measured side strips."""
import json
import hashlib
from pathlib import Path

import pytest

from geometry import Rect, overlapping_modules
from views import recognise_ordered


def source_views(code):
    views=json.loads((Path(__file__).parent/f'fixtures/{code.lower()}_views.json').read_text(encoding='utf8'))
    for view in views:
        view['rects']=[Rect(*r['box'],r['handle'],r['layer']) for r in view['rects']]
    return views


@pytest.mark.parametrize('code,widths,heights,auxiliary',[
    ('SP28',[860,1422,860,1422],[2150,2150,400,400],1),
    ('SP29',[1100,1300,1134,1100,1134],[2150,700,2150,400,400],3),
    ('SP30',[1044.5]*4,[2150,2150,400,400],2),
])
def test_actual_failed_products_have_complete_measured_modules(code,widths,heights,auxiliary):
    result=recognise_ordered(source_views(code),{})
    modules=result['modules'];parts=result['trim_parts']
    assert [m['size'][0] for m in modules]==widths
    assert [m['size'][2] for m in modules]==heights
    assert all(m['size'][1]==550 and m['scope']=='carcass_and_doors' for m in modules)
    assert len(parts)==auxiliary
    assert all(p['stock_thickness_mm']==18 and p['plan_boxes'] for p in parts)
    assert modules[0]['origin'][2]==50
    assert modules[-1]['origin'][2]==2200
    assert not overlapping_modules(modules)
    assert min(p['origin'][1] for p in modules+parts)==0
    assert min(p['origin'][2] for p in modules+parts)==0
    for axis in range(3):
        assert max(p['origin'][axis]+p['size'][axis] for p in modules+parts)<=result['bounds'][axis]+.01
    assert all(m.get('joint_evidence',{}).get('section_no_cut') for m in modules if m['size'][2]==400)


def test_exterior_strip_without_its_measured_plan_footprint_still_blocks():
    views=source_views('SP30')
    for v in views:
        if v['role']=='plan':v['rects']=[r for r in v['rects'] if r.handle not in ('/F4EA','/F4EB','/F88B','/F88C')]
    with pytest.raises(ValueError,match='bề rộng'):
        recognise_ordered(views,{})


def test_repeated_bay_cannot_borrow_section_without_matching_tier_planes():
    views=source_views('SP29')
    for v in views:
        if v['role']=='section_vertical':
            v['rects']=[r for r in v['rects'] if r.handle!='/1577B']
            v['outlines']=[o for o in v['outlines'] if o['handle']!='/1577B']
    with pytest.raises(ValueError,match='mặt cắt'):
        recognise_ordered(views,{})


def test_hidden_cap_gap_cannot_be_replaced_by_a_drawer_detail():
    views=source_views('SP28')
    front=next(v for v in views if v['role']=='front_open')
    front['rects']=[r for r in front['rects'] if r.handle!='/5BB2']
    front['outlines']=[o for o in front['outlines'] if o['handle']!='/5BB2']
    with pytest.raises(ValueError,match='khoang|chồng|ghép|khép'):
        recognise_ordered(views,{})


def test_previous_recognizer_cache_does_not_preserve_the_old_failure(tmp_path,monkeypatch):
    import main
    targets=['SP30']
    target_key=hashlib.sha256(json.dumps(targets,ensure_ascii=False).encode()).hexdigest()[:12]
    old=tmp_path/f'analysis-{main.VERSION}-{target_key}.json'
    old.write_text(json.dumps({'products':[{'code':'SP30','status':'needs_review'}]}),encoding='utf8')
    monkeypatch.setattr(main,'archive_source',lambda source,root:{'folder':str(tmp_path)})
    def reparse(*args):
        raise RuntimeError('new recognizer must reparse')
    monkeypatch.setattr(main,'dxf_for_revision',reparse)
    with pytest.raises(RuntimeError,match='must reparse'):
        main.analyse_source('unchanged.dwg',tmp_path,targets=targets)
