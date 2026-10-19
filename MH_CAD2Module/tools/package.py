from pathlib import Path
import zipfile

root=Path(__file__).resolve().parents[1]
target=root/"outputs"/"MH_CAD2Module-0.10.1.rbz"
target.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(target,"w",zipfile.ZIP_DEFLATED) as archive:
    archive.write(root.parent/"MH_CAD2Module.rb","MH_CAD2Module.rb")
    for path in root.glob("*.rb"):
        archive.write(path,"MH_CAD2Module/"+path.name)
    for folder in ("ui","worker"):
        for path in (root/folder).rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts:
                archive.write(path,"MH_CAD2Module/"+path.relative_to(root).as_posix())
    for name in ("README.md","requirements.txt"):
        archive.write(root/name,"MH_CAD2Module/"+name)
print(target)
