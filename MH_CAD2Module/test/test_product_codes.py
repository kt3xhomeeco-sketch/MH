import ezdxf
import pytest

from main import product_code,run,find_products
from test_cad_views import low_source


def test_generic_codes_are_exact_tokens_and_sp_is_backward_compatible():
    assert product_code('D1')==['D1']
    assert product_code('ABC-01')==['ABC-01']
    assert product_code('SP 8')==['SP08']
    assert product_code('Tủ D1')==[]


@pytest.mark.parametrize('code',['D1','ABC-01'])
def test_generic_code_dxf_frame_is_found_and_cached_without_sp_prefix(tmp_path,code):
    lines=low_source();xs=[r[k][0] for r in lines for k in ('a','b')];ys=[r[k][1] for r in lines for k in ('a','b')]
    x0,y0=min(xs)-100,min(ys)-100;w,h=max(xs)-x0+100,max(ys)-y0+100
    doc=ezdxf.new('R2018',units=4);space=doc.modelspace();frame=doc.blocks.new('FRAME')
    frame.add_lwpolyline([(0,0),(w,0),(w,h),(0,h)],close=True);frame.add_attdef('MASP')
    space.add_blockref(frame.name,[x0,y0]).add_auto_attribs({'MASP':code})
    for row in lines:space.add_line(row['a'],row['b'])
    path=tmp_path/'generic.dxf';doc.saveas(path)
    request=dict(sources=[str(path)],targets=[code],library=str(tmp_path/'library'))
    first=run(request);second=run(request)
    assert not first['errors'] and not second['errors']
    assert [p['code'] for p in first['analyses'][0]['products']]==[code]
    assert second['analyses'][0]['products'][0]['code']==code


@pytest.mark.parametrize('attrs,expected',[
    ({'MASP':'D1','TENBV1':'SP20'},['D1']),
    ({'TENBV1':'SP20','TENBV2':'D1'},['SP20']),
])
def test_code_attributes_take_priority_over_title_shaped_like_another_code(attrs,expected):
    doc=ezdxf.new('R2018',units=4);block=doc.blocks.new('FRAME')
    block.add_lwpolyline([(0,0),(2000,0),(2000,3000),(0,3000)],close=True)
    for key in attrs:block.add_attdef(key)
    doc.modelspace().add_blockref(block.name,[0,0]).add_auto_attribs(attrs)
    products,_=find_products(doc,1)
    assert list(products)==expected
