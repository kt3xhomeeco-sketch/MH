import ezdxf

from main import read_geometry
from section_arrows import arrow_evidence


def test_chevrons_are_indexed_locally_and_conflicting_heads_are_not_guessed():
    cut=[[100,0],[100,1000]]
    right=[[[120,y],[100,y-20]] for y in (0,1000)]+[[[120,y],[100,y+20]] for y in (0,1000)]
    evidence=arrow_evidence(right,cut)
    assert evidence['view_direction']==[1,0] and len(evidence['arrow_heads'])==2
    left=[[[80,y],[100,y-20]] for y in (0,1000)]+[[[80,y],[100,y+20]] for y in (0,1000)]
    assert arrow_evidence(left,cut)['view_direction']==[-1,0]
    assert arrow_evidence(right+left,cut)=={}
    assert arrow_evidence([cut],cut)=={}


def test_dxf_marker_keeps_nested_visible_arrow_heads_and_ignores_hidden_parent():
    doc=ezdxf.new('R2018',units=4);head=doc.blocks.new('ARROW')
    head.add_line([20,0],[0,-20]);head.add_line([20,0],[0,20])
    block=doc.blocks.new('SECTION MARK');block.add_line([100,0],[100,1000])
    block.add_blockref('ARROW',[100,0]);block.add_blockref('ARROW',[100,1000])
    block.add_blockref('ARROW',[100,0],dxfattribs={'invisible':1,'xscale':-1})
    symbol=doc.modelspace().add_blockref(block.name,[5000,6000]);notes=[]
    read_geometry(doc,1,set(),notes)
    assert notes[0]['axis']=='vertical' and notes[0]['view_direction']==[1,0]
    assert len(notes[0]['arrow_heads'])==2
    symbol.dxf.rotation=180;notes=[];read_geometry(doc,1,set(),notes)
    assert notes[0]['view_direction']==[-1,0]
