"""Read-only SDK inventory of the authorized DC folder; no source files changed."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess

project = Path(__file__).resolve().parents[1]
folder = Path('D:/Cong viec/Sketchup/DC/MH')
bridges = [Path.home() / 'Documents/MH_Apps/MH_Thongke_Desktop/bin/MH_SkpBridge.exe',
           Path.home() / 'Documents/MH_Apps/MH_SkpBridge/bin/MH_SkpBridge.exe']
bridge = next(path for path in bridges if path.is_file())
output = project / 'outputs/library-016'
output.mkdir(parents=True, exist_ok=True)


def scan(path):
    token = hashlib.sha256(str(path.relative_to(folder)).encode('utf-8')).hexdigest()[:16]
    target = output / (token + '.json')
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    row = {'path': str(path), 'relative': str(path.relative_to(folder)), 'capture': str(target), 'sha256': before}
    try:
        result = subprocess.run([str(bridge), 'scan-reader-context', '--input', str(path), '--result-file', str(target)],
                                capture_output=True, timeout=60, creationflags=subprocess.CREATE_NO_WINDOW)
        capture = json.loads(target.read_text(encoding='utf-8-sig')) if target.exists() else {}
        row['ok'] = result.returncode == 0 and capture.get('ok') is True
        if not row['ok']:
            row['error'] = capture.get('error', result.stderr.decode('utf-8', errors='replace')[:300])
    except Exception as error:
        row.update(ok=False, error=str(error))
    row['source_unchanged'] = before == hashlib.sha256(path.read_bytes()).hexdigest()
    return row


paths = sorted(folder.rglob('*.skp'))
rows = []
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for row in pool.map(scan, paths):
        rows.append(row)
        if len(rows) % 25 == 0:
            print(f'Read {len(rows)}/{len(paths)} SKP files', flush=True)
(output / 'manifest.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'files': len(rows), 'read_ok': sum(row['ok'] for row in rows),
                  'sources_unchanged': all(row['source_unchanged'] for row in rows)}, ensure_ascii=False))
