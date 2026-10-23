"""Offline view/stock diagnostics for the archived SP35 source."""
import json,sys,html
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'worker'))
from drawing_scope import choose_product_plan,view_slots
from elevation_builder import context
from oy_sweep import plates,bays
from cad_datums import panel_boxes,context_hint

d=json.loads((ROOT/'test/fixtures/named_sp35_sections.json').read_text('utf8'));p=d['product'];notes=d['annotations']
choose_product_plan(p,notes,multiple=True);views,_=view_slots(p,notes)
data=context(p,notes)
out=['<svg xmlns="http://www.w3.org/2000/svg" width="1500" height="1800"><rect width="100%" height="100%" fill="#20282f"/>']
for i,v in enumerate(views):
    box=v['features']['box'];x,y=(i%3)*500+15,(i//3)*600+55;s=min(470/(box[2]-box[0]),510/(box[3]-box[1]))
    out.append(f'<text x="{x}" y="{y-20}" fill="white">{v["id"]} {html.escape(v["title"])} · {v["features"]["width_mm"]} × {v["features"]["height_mm"]}</text>')
    def xy(pt):return f'{x+(pt[0]-box[0])*s:.2f},{y+(box[3]-pt[1])*s:.2f}'
    for row in v['outlines']:
        color='#6ce0ef' if not context_hint(row) else '#57616a'
        out.append(f'<polyline points="{" ".join(xy(pt) for pt in row["points"])}" fill="none" stroke="{color}" stroke-width=".65"/>')
    rows=[r for r in v['outlines'] if not context_hint(r)];rects,_=plates(rows);cells,diag=bays(rects,rows)
    print(v['id'],v['title'],'box',box,'core',v['features']['core_box'],'orthogonal',v['features']['orthogonal_plan'],'bays',[(b['box'],b.get('handles')) for b in cells])
    if i==0:
        print('PLAN PLATES',[(r.box(),r.handle) for r in rects]);print('DIAG',diag)
    for j,c in enumerate(cells):
        b=c['box'];q=[(b[0],b[1]),(b[2],b[1]),(b[2],b[3]),(b[0],b[3]),(b[0],b[1])]
        out.append(f'<polyline points="{" ".join(xy(pt) for pt in q)}" fill="#ffbd0033" stroke="#ffca32" stroke-width="1"/>')
out.append('</svg>');(ROOT/'outputs/sp35-diagnostic.svg').write_text(''.join(out),'utf8')
(ROOT/'outputs/sp35-context.json').write_text(json.dumps(dict(poses=data['relations'],candidates=p['view_analysis']['candidates']),ensure_ascii=False),'utf8')
