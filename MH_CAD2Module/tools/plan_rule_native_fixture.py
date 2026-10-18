"""Build isolated training data and unseen targets; never write real experiences."""
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'worker'),str(ROOT/'test')]
from test_plan_rules import CASES, plan, curved_plan
from test_learning import save_example
from main import replay_experience, source_placement
from learning import ExperienceLibrary
from library import atomic_json

root=ROOT/'outputs'/'l'
products=[]
for index,factory in enumerate((plan,curved_plan)):
    for i,(widths,depth) in enumerate(CASES):
        kwargs={'radius':(100,120,90)[i]} if index else {}
        p,s=factory(widths,depth,**kwargs)
        save_example(root,p,s,eid=f'native-{index}-{i}',input_axes_ignored=True)
    kwargs={'radius':140} if index else {}
    product,_=factory((1090,470),710,**kwargs)
    product.update(code=f'NATIVE-AUTO-{index}',source_hash=str(index+1)*64,automatic_scan=True)
    assert replay_experience(product,root),product
    assert product['learning']['mode']=='plan_rule'
    product['geometry_pipeline']={'mode':'plan_only'}
    source_placement(product,{'plane':'XY','plane_offset_mm':73})
    products.append(product)
summary=ExperienceLibrary(root).refresh_plan_rules()
atomic_json(ROOT/'outputs'/'plan-rule-native-fixture.json',dict(products=products,summary=summary))
print({'active':summary['active'],'targets':len(products)})
