import json
from pathlib import Path

from main import run


def test_real_sketchup_split_edge_fixture(tmp_path):
    lines=json.loads((Path(__file__).parent/'fixtures'/'native_panel_edges.json').read_text())
    result=run({'action':'geometry','code':'SP09','library':str(tmp_path/'lib'),'build_elevation':True,
                'geometry':{'hash':'e'*64,'lines':lines}})
    product=result['analyses'][0]['products'][0]
    assert product['status']=='ready',product.get('error')
    assert [m['size'] for m in product['modules']]==[[860,600,2110],[860,600,2110],[1720,600,432]]
    assert len(product['geometry_pipeline']['vertical']['columns'])==2
