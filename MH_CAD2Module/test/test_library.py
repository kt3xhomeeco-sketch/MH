import json
from pathlib import Path

import ezdxf
import openpyxl
import pytest

from library import archive_source, atomic_json, library_root, sha256
from main import read_product_list, replay_experience


def test_source_versions_immutable_and_deduplicated(tmp_path):
    source=tmp_path/"same-name.dxf";source.write_text("original")
    root=library_root(str(tmp_path/"library"))
    first=archive_source(str(source),root)
    assert archive_source(str(source),root)["hash"]==first["hash"]
    source.write_text("changed")
    second=archive_source(str(source),root)
    assert first["hash"]!=second["hash"]
    source.unlink()
    assert Path(first["stored"]).read_text()=="original"
    assert Path(second["stored"]).read_text()=="changed"


def test_snapshot_corruption_does_not_silently_parse(tmp_path):
    source=tmp_path/"file.dxf";source.write_text("original")
    root=library_root(str(tmp_path/"lib"));rev=archive_source(str(source),root)
    Path(rev["stored"]).write_text("damaged")
    with pytest.raises(ValueError,match="mã kiểm tra"):
        archive_source(str(source),root)


def test_excel_unique_codes_and_names(tmp_path):
    book=openpyxl.Workbook();sheet=book.active
    sheet.append(["Mã SP","Tên SP","SL"]);sheet.append(["SP1","Tủ áo",2]);sheet.append(["SP60","Tủ áo",1]);sheet.append(["SP60","",1])
    path=tmp_path/"list.xlsx";book.save(path)
    assert read_product_list(path)==["SP01","SP60"]
    sheet.delete_cols(1);book.save(path)
    assert read_product_list(path)==["Tủ áo"]


def test_unresolved_experience_never_replayed(tmp_path):
    product={"signature":"a"*64,"modules":[],"bounds":[100,100,100],"explanation":[]}
    folder=tmp_path/"experiences"/product["signature"]
    atomic_json(folder/"001.json",{"status":"unresolved","signature":product["signature"]})
    replay_experience(product,tmp_path)
    assert "experience" not in product


def test_accepted_experience_is_signature_and_version_scoped(tmp_path):
    from library import VERSION
    signature="b"*64
    module={"id":"M01","origin":[0,18,50],"size":[860,582,2110]}
    event={"id":"fixed","status":"accepted","signature":signature,"parser_version":VERSION,"after":{"modules":[module],"bounds":[860,600,2200]}}
    atomic_json(tmp_path/"experiences"/signature/"001.json",event)
    product={"signature":signature,"modules":[],"bounds":[860,600,2200],"explanation":[]}
    replay_experience(product,tmp_path)
    assert product["modules"]==[module] and product["experience"]["event"]=="fixed"
    other={"signature":"c"*64,"modules":[],"explanation":[]}
    replay_experience(other,tmp_path)
    assert "experience" not in other
