import json
from pathlib import Path

from main import run


def test_real_sketchup_split_edge_fixture(tmp_path):
    lines=json.loads((Path(__file__).parent/'fixtures'/'native_panel_edges.json').read_text())
    result=run({'action':'geometry','code':'SP09','library':str(tmp_path/'lib'),'build_elevation':True,
                'geometry':{'hash':'e'*64,'lines':lines}})
    product=result['analyses'][0]['products'][0]
    assert product['status']=='ready',product.get('error')
    assert len(product['plan_results'])==2
    assert sorted([m['size'][0] for m in child['modules']] for child in product['plan_results'])==[[860,860],[1720]]
    for child in product['plan_results']:
        expected=2542 if child.get('height_source')=='product_elevation_bounds' else 1600
        assert all(m['size'][1:]==[600,expected] for m in child['modules'])
        assert child['elevation_pending']
    assert sorted(c['bounds'][2] for c in product['plan_results'])==[1600,2592]
