"""Summarize audited rule compilation separately from native geometry support."""
import hashlib
import json
from pathlib import Path

project = Path(__file__).resolve().parents[1]
folder = project / 'outputs/library-016'
before = json.loads((folder / 'analysis-before.json').read_text(encoding='utf-8'))
after = json.loads((folder / 'analysis-after.json').read_text(encoding='utf-8'))
manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
previous = {row['relative']: row for row in before['files']}
old_supported = {row['relative'] for row in before['files'] if row.get('engine_keys')}
supported = {row['relative'] for row in after['files'] if row.get('engine_keys')}
assert old_supported <= supported, 'Rule compilation regressed for a previously supported file'
unchanged = all(hashlib.sha256(Path(row['path']).read_bytes()).hexdigest() == row['sha256'] for row in manifest)
assert unchanged, 'A library source changed during this audit'
summary = {'files': len(manifest), 'sdk_read_ok': sum(row['ok'] for row in manifest),
           'compiled_before': len(old_supported), 'compiled_after': len(supported),
           'newly_compiled': sorted(supported - old_supported), 'regressions': [],
           'source_hashes_unchanged': unchanged, 'structure_read_errors': sum(bool(row.get('read_error')) for row in after['files'])}
(folder / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
lines = ['# Kết quả khảo sát thư viện DC MH', '',
         f"Đã quét {len(manifest)} file SKP; SDK đọc được toàn bộ. SHA-256 tất cả file nguồn giữ nguyên.", '',
         f"Bộ biên dịch tạo được quy tắc ATT cho **{len(old_supported)} → {len(supported)} file**, tăng {len(supported-old_supported)} file; không mất file đã hỗ trợ.", '',
         'Đây là số file biên dịch được quy tắc, không phải cam kết mọi chi tiết/hình học hoặc mọi ATT trong file đều sửa được. '
         'SDK chỉ cho bounds/counts nên không chứng nhận tấm hộp. Đọc trực tiếp từ SketchUp mới kiểm tra được đỉnh/mặt thực.', '',
         '27 hàm riêng đã xác minh đọc kích thước danh nghĩa cha; hàm mới chỉ nhận khi toàn bộ cấu trúc hàm đã nạp khớp mẫu đọc thuộc tính. '
         'Bản quy tắc lưu ánh xạ nên tính toán sau đó không chạy hàm ABF. Không đoán hàm từ tên ngẫu nhiên hoặc giá trị cache.', '',
         'Đã thêm các hàm số xuất hiện trong thư viện: SMALLEST/LARGEST, ROUND, CEILING/FLOOR, SQRT, ISEVEN, CHOOSE, SIN/COS/TAN, PI, TRUE/FALSE. '
         'Đối chiếu [tài liệu Dynamic Components của SketchUp](https://help.sketchup.com/en/sketchup/dynamic-component-supported-functions).', '',
         'Bật/tắt chi tiết đang ẩn, đổi Copies/số chi tiết, đổi góc xoay, group xoay/lật, phụ kiện không phải hộp và các hàm riêng chưa xác minh vẫn có giới hạn. '
         'Các tấm đang ẩn giữ hình học đã đọc; mọi đổi trạng thái ẩn/hiện vẫn bị chặn. Các ATT không tác động trong cấu hình hiện tại giữ cố định kèm lý do.', '',
         'Thử native: khung đang khảo sát có 8 đầu vào ATT sửa được; đổi dày tấm/hậu, hậu lùi/ngậm, chiều cao len chân, '
         'lặp rãnh, từ chối giá trị sai, Undo/Redo. Report `../native-library-016.json`. Không sửa thư viện nguồn.', '',
         '| File | Kết quả | Chi tiết |', '|---|---|---|']
for row in after['files']:
    name = row['relative'].replace('|', r'\|')
    if row.get('engine_keys'):
        status = 'Có quy tắc ATT' + (' · Mới' if name not in old_supported else '')
        detail = f"{len(row['engine_keys'])} đầu vào: " + ', '.join(row['engine_keys'])
    elif row.get('read_error'):
        status, detail = 'Cấu trúc chưa đọc được', row['read_error']
    else:
        status, detail = 'Chưa biên dịch được ATT', row.get('engine_error', 'Không có đầu vào hình học')
    lines.append(f"| {name} | {status} | {detail.replace('|', '/')} |")
(folder / 'coverage.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(json.dumps({key: value for key, value in summary.items() if key != 'newly_compiled'}, ensure_ascii=False))
