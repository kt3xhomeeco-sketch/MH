"""Developer-only: package the explicit runtime manifest, excluding tooling/data."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import json

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "runtime_manifest.json").read_text(encoding="utf-8"))
runtime = manifest["calculation"] + manifest["adapters"] + manifest["assets"]
assert len(runtime) == len(set(runtime)), "Duplicate runtime entry"
assert all((root / name).resolve().is_relative_to(root) for name in runtime)
output = root / "outputs" / "MH_Module_Studio-0.1.0.rbz"
output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    archive.write(root.parent / "MH_Module_Studio.rb", "MH_Module_Studio.rb")
    for name in runtime:
        archive.write(root / name, "MH_Module_Studio/" + name)
with ZipFile(output) as archive:
    assert archive.testzip() is None
    assert archive.namelist() == ["MH_Module_Studio.rb"] + ["MH_Module_Studio/" + name for name in runtime]
print(output)
