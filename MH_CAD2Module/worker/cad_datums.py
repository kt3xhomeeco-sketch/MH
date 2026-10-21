"""Cabinet registration datums, separate from the complete transported CAD bounds."""
import math
import re
import hashlib
import json
from collections import OrderedDict,defaultdict
from copy import deepcopy

from geometry import TOL, near, rectangle, union
from materials import BOARD_MM
from oy_sweep import plates, bays
from cad_profile_datums import closed_faces
from views import normalise
from cad_style import style_key,interrupted

_DATUMS=OrderedDict()


def context_hint(row):
    text=normalise(' '.join([row.get('layer',''),*row.get('block_names',[])]))
    return interrupted(row) or bool(re.search(r'\b(WALL|TUONG|MASONRY|CONCRETE|HIDDEN|DASH\w*|NET DUT|HATCH\w*|HACH)\b',text.replace('_',' ').replace('-',' ').replace('.',' ')))


def panel_boxes(rows):
    styles=defaultdict(list)
    for row in rows:styles[style_key(row)].append(row)
    boards=[];profiles=[]
    # Each closed witness is proved inside a compatible stroke family. Two
    # unrelated styles cannot provide opposite faces/caps of an invented board.
    for group in styles.values():
        found,_=plates(group);boards.extend(found);profiles.extend(closed_faces(group))
    # Closed source rectangles also tolerate small drawing errors that prevent
    # the strict axis sweep from joining caps (e.g. SP27's18 mm door).
    boards=[r for r in boards if r.layer!='front_envelope' and any(near(min(r.w,r.h),s) for s in BOARD_MM)]
    for row in rows:
        ps=row['points']
        if len(ps)<4 or math.dist(ps[0],ps[-1])>TOL:continue
        r=rectangle(ps,row['handle'],row.get('layer',''))
        if r and any(near(min(r.w,r.h),s) for s in BOARD_MM) and max(r.w,r.h)>2*min(r.w,r.h):boards.append(r)
    result={tuple(round(x,3) for x in r.box()):dict(box_mm=r.box(),handles=r.handle.split('+')) for r in boards}
    result.update({tuple(round(x,3) for x in r['box_mm']):r for r in profiles})
    return list(result.values()),boards


def measure(rows,base):
    key=hashlib.sha256(json.dumps([(r['handle'],context_hint(r),style_key(r),r['points']) for r in rows],separators=(',',':')).encode()).hexdigest()
    if key not in _DATUMS:
        _DATUMS[key]=measure_source(rows)
        if len(_DATUMS)>32:_DATUMS.popitem(last=False)
    _DATUMS.move_to_end(key)
    result=deepcopy(_DATUMS[key])
    if result:
        def local(b):return [round(v-base[i%2],6) for i,v in enumerate(b)]
        result['box_mm']=local(result['box_mm'])
        result['panels']=[dict(p,box_mm=local(p['box_mm'])) for p in result['panels']]
        result['bays_mm']=[local(b) for b in result['bays_mm']]
    return result


def measure_source(rows):
    clean=[r for r in rows if not context_hint(r)]
    panels,boards=panel_boxes(clean)
    # A name/linetype alone is insufficient to discard the only cabinet proof.
    excluded=len(rows)-len(clean)
    if len(panels)<2:
        panels,boards=panel_boxes(rows);clean=rows;excluded=0
    if len(panels)<2:return None
    try:cells,_=bays(boards,clean)
    except ValueError:cells=[]
    return dict(basis='closed_stock_panels',box_mm=union([p['box_mm'] for p in panels]),panels=panels,
                bays_mm=[c['box'] for c in cells],context_rows_excluded=excluded)


def front_at(datum,x):
    """Use the arm intersected by the cut, not the global minimum of an L plan."""
    cells=[b for b in datum['bays_mm'] if b[0]-TOL<=x<=b[2]+TOL]
    panels=[p['box_mm'] for p in datum['panels'] if p['box_mm'][0]-TOL<=x<=p['box_mm'][2]+TOL]
    if cells:return min(b[1] for b in cells+panels),'cut_footprint'
    # Front/back rails spanning the cut delimit even a cell with no closed bays.
    if len(panels)>=2 and max(b[3] for b in panels)-min(b[1] for b in panels)>100:
        return min(b[1] for b in panels),'cut_panel_faces'
    return datum['box_mm'][1],'cabinet_min_y'
