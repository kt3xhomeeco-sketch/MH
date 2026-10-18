"""Local, immutable CAD revisions. No AutoCAD integration or cloud services."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid

# Extraction/cache schema: independent of extension release and learned-rule schema.
VERSION = "0.2.3"


def library_root(value: str) -> Path:
    if not value:
        raise ValueError("Chọn thư mục thư viện trong bảng Quản lý.")
    root = Path(value).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def atomic_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def archive_source(source: str, root: Path):
    path = Path(source).resolve(strict=True)
    if path.suffix.lower() not in (".dwg", ".dxf"):
        raise ValueError("Nguồn CAD phải là DWG hoặc DXF.")
    before = path.stat()
    digest = sha256(path)
    folder = root / "sources" / digest
    folder.mkdir(parents=True, exist_ok=True)
    stored = folder / ("source" + path.suffix.lower())
    if not stored.exists():
        temporary = folder / (uuid.uuid4().hex + ".tmp")
        try:
            shutil.copyfile(path, temporary)
            after = path.stat()
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns) or sha256(temporary) != digest:
                raise ValueError("File CAD thay đổi trong lúc đọc. Lưu xong rồi thử lại.")
            os.replace(temporary, stored)
        finally:
            temporary.unlink(missing_ok=True)
    elif sha256(stored) != digest:
        raise ValueError("Bản CAD trong thư viện không khớp mã kiểm tra; cần khôi phục bản lưu.")
    manifest = folder / "source.json"
    if not manifest.exists():
        atomic_json(manifest, {"hash": digest, "original_path": str(path), "size": before.st_size,
                               "archived_at": time.time(), "stored": str(stored)})
    return {"hash": digest, "original_path": str(path), "stored": str(stored), "folder": str(folder)}


def find_converter(configured=""):
    if configured:
        path = Path(configured)
        if not path.is_file():
            raise ValueError("Không tìm thấy ODA File Converter tại đường dẫn đã chọn.")
        return path
    candidates = []
    for base in (os.environ.get("ProgramW6432"), os.environ.get("ProgramFiles"),
                 os.environ.get("ProgramFiles(x86)")):
        if base:
            candidates.extend(Path(base).glob("ODA/*/ODAFileConverter.exe"))
    if not candidates:
        raise ValueError("Cài ODA File Converter hoặc chọn ODAFileConverter.exe trong Quản lý.")
    return sorted(set(candidates), key=lambda p: p.parent.name, reverse=True)[0]


def dxf_for_revision(revision, converter="") -> Path:
    source = Path(revision["stored"])
    if source.suffix.lower() == ".dxf":
        return source
    target = source.parent / "drawing.dxf"
    if target.is_file():
        return target
    executable = find_converter(converter)
    # All temporary drawing bytes remain inside the user-selected library.
    with tempfile.TemporaryDirectory(prefix="convert-", dir=source.parent) as work:
        work = Path(work)
        input_dir, output_dir = work / "input", work / "output"
        input_dir.mkdir()
        output_dir.mkdir()
        shutil.copyfile(source, input_dir / "drawing.dwg")
        environment = {k: v for k, v in os.environ.items() if k not in
                       ("QT_PLUGIN_PATH", "QT_QPA_PLATFORM_PLUGIN_PATH", "QML2_IMPORT_PATH")}
        options = {}
        if os.name == "nt":
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 0
            options["startupinfo"] = startup
        result = subprocess.run([str(executable), str(input_dir), str(output_dir), "ACAD2018",
                                 "DXF", "0", "1", "*.dwg"], capture_output=True, timeout=150,
                                env=environment, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), **options)
        deadline = time.monotonic() + 12
        previous = None
        while time.monotonic() < deadline:
            files = list(output_dir.glob("*.dxf")) + list(output_dir.glob("*.DXF"))
            if files:
                item = files[0]
                size = item.stat().st_size
                if size > 100 and size == previous:
                    os.replace(item, target)
                    return target
                previous = size
            time.sleep(0.25)
        detail = (result.stderr or result.stdout).decode("utf-8", errors="replace")[-600:]
        raise ValueError("ODA chưa tạo được DXF hợp lệ. " + detail)


def archive_dependencies(doc, revision, root):
    dependencies = []
    base = Path(revision["original_path"]).parent
    for block in doc.blocks:
        if not (block.block.dxf.get("flags", 0) & 12):
            continue
        reference = block.block.dxf.get("xref_path", "")
        path = Path(reference)
        if not path.is_absolute():
            path = base / path
        record = {"block": block.name, "path": str(path), "resolved": path.is_file()}
        if path.is_file():
            record["revision"] = archive_source(str(path), root)
        dependencies.append(record)
    return dependencies
