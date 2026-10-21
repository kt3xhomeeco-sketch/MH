"""Regenerate QA products from archived geometry; never changes a user's model."""
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'worker'),str(ROOT/'test')]
from combined_runtime import analyse
from drawing_scope import choose_product_plan
from test_cad_views import low_product
from test_cad_levels import level_source
from test_elevation_builder import fixture
from test_view_relations import stretch_source


def write(name,product):
    (ROOT/'outputs'/f'{name}.json').write_text(json.dumps(product,ensure_ascii=False),'utf8')


def run(product,notes):
    selected=choose_product_plan(product,notes,multiple=True)
    analyse(product,selected,notes,ROOT/'outputs/registration-qa-library')
    return product


if __name__=='__main__':
    for source,target in [('named_sp24_registration','sp24-registered-product'),('named_sp25_sections','sp25-sections-product'),
                          ('named_sp27_datums','sp27-ymin-product'),('named_sp20_levels','sp20-yoz-product')]:
        d=json.loads((ROOT/f'test/fixtures/{source}.json').read_text('utf8'))
        p=run(d['product'],d['annotations']);write(target,p)
        if source=='named_sp20_levels':write('sp20-levels-product',p)
    write('cad-views-low-product',low_product(ROOT/'outputs/registration-qa-library'))
    p,n=fixture();write('single-plan-zero-product',run(p,n))
    p,n=level_source();write('cad-levels-products',run(p,n))
    p,n=stretch_source();write('stretched-chain-product',run(p,n))
    print('Regenerated8 QA products and SP20 alias; user models unchanged.')
