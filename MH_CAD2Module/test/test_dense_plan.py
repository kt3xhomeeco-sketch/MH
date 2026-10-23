import json
from pathlib import Path

from geometry import line_rectangles
from main import run, report_progress
from test_plan_profiles import request


def test_dense_panel_recovery_keeps_measured_rectangles_and_source_proof():
    lines=json.loads((Path(__file__).parent/'fixtures/dense_plan_edges.json').read_text())
    rows=[(l['a'],l['b'],l['handle'],l['layer']) for l in lines]
    recovered=line_rectangles(rows,min_length=0)
    assert len(recovered)==496
    assert all(r.handle and r.w>0 and r.h>0 for r in recovered)
    # A second orientation/position must not change the recovered local geometry.
    moved=[([a[1]-700,a[0]+30000],[b[1]-700,b[0]+30000],h,layer) for a,b,h,layer in rows]
    swapped=line_rectangles(moved,min_length=0)
    assert sorted(tuple(round(v,3) for v in r.box()) for r in swapped)==sorted(
        (round(r.y0-700,3),round(r.x0+30000,3),round(r.y1-700,3),round(r.x1+30000,3)) for r in recovered)


def test_worker_reports_geometry_stages_before_returning_result(tmp_path,monkeypatch):
    import main
    seen=[];original=main.report_progress
    def record(packet,root,stage,message):
        seen.append(stage);original(packet,root,stage,message)
    monkeypatch.setattr(main,'report_progress',record)
    packet=request(tmp_path);path=tmp_path/'jobs'/'progress-test'/'progress.json'
    packet['progress_file']=str(path)
    run(packet)
    assert seen==['read_edges','partition','measure_evidence','experience','prepare_result']
    assert json.loads(path.read_text())['stage']=='prepare_result'
    outside=tmp_path/'outside.json'
    report_progress(dict(progress_file=str(outside)),tmp_path,'bad','bad')
    assert not outside.exists()
