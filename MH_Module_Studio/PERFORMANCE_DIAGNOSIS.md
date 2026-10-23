# Chẩn đoán hiệu năng — đổi thông số Module Options (T1)

Ngày đo: 2026-10-23 · SketchUp 2025 (PID 16624) · Ruby 3.2.2 x64-mswin64_140 · MCP `127.0.0.1:7891`

Không sửa file production nào trong lúc đo. Toàn bộ số liệu lấy từ tiến trình SketchUp đang chạy,
dùng fixture QA "Khung nóc lọt" rồi dọn sạch. Bản đầy đủ kèm artifact thô nằm ở
`outputs/options_profile_20261023/` (thư mục này bị `.gitignore`, không commit).

Fixture: `Khung noc lot.skp` (80.098 B) → `rule_json` **576.538 B**, kind `module_rule_system`,
7 tấm · 43 tham số · 107 ràng buộc · 43 biến parametric · formula_engine bật.

---

## 1. Kết luận

### Nguyên nhân chính (~80–90% thời gian): vòng nhả GVL `sleep(0.001)` thực tế ngủ ~15,6 ms

`UpdateWork.compute` (update_work.rb:203–216) dùng `TracePoint` đếm call-event; cứ 64 event và ≥3 ms
thì gọi `sleep(0.001)` để nhả GVL cho UI. Trên máy/tiến trình này **mọi `sleep(n)` với n ≤ 8 ms đều
mất ~15,6 ms** (một tick đồng hồ), nên worker chỉ chạy ~18% duty cycle.

Đo trực tiếp (median, thread riêng, không tính tạo thread):

| yêu cầu | 1 ms | 2 ms | 4 ms | 8 ms | 16 ms | 20 ms | 32 ms |
|---|---|---|---|---|---|---|---|
| thực tế | **15,8** | **14,8** | **14,1** | **15,8** | 28,1 | 32,3 | 43,3 |

- `Sleep(1)` Win32 thô: **15,2 ms**; sau `timeBeginPeriod(1)`: **14,4 ms** → **không cải thiện**.
- `NtQueryTimerResolution` báo current = 4,0 ms nhưng granularity hiệu dụng vẫn ~15,6 ms.
- Power throttling: EcoQoS **tắt**, `IGNORE_TIMER_RESOLUTION` **tắt**, priority class NORMAL
  → không phải do Windows hạ ưu tiên tiến trình.

Hệ quả đo được trên đúng công việc thật (`Parametric.edit_variables`, 3 vòng, cùng một TracePoint
giống hệt production):

| chế độ nhả GVL | wall | số lần nhả | tổng thời gian nhả | so với chỉ-TracePoint |
|---|---|---|---|---|
| không TracePoint | 1.108 ms | – | – | 0,82× |
| TracePoint, không nhả | 1.357 ms | 366 | 0,5 ms | 1,00× |
| **`sleep(0.001)` (production)** | **13.836 ms** | 933 | **10.513 ms** | **10,2×** |
| `sleep(0.001)` lặp lại | 10.315 ms | 699 | 7.861 ms | 7,6× |
| `sleep(0)` | 1.180 ms | 335 | 4,9 ms | 0,87× |
| `Thread.pass` | 1.180 ms | 329 | 5,8 ms | 0,87× |

Job thật (không gắn hook đo), 2 lần:

| lần | T1 | wall | `UpdateWork` elapsed | CPU tiến trình (user+sys) | nhịp UI hụt tối đa | step main dài nhất |
|---|---|---|---|---|---|---|
| 1 | 24 mm | 12,59 s* | 12,59 s | **1,78 s** | 649 ms | 252 ms |
| 2 | 25 mm | 11,19 s | 10,95 s | **0,97 s** | 375 ms | 210 ms |

\* wall của lần 1 bị probe lấy muộn; dùng `elapsed_ms` nội bộ của UpdateWork.

→ **~10 s trong 11 s là chờ, chỉ ~1 s là CPU thật.** Hình học vẫn đúng (4 tấm chính = 25,0 mm).

Profile phiên trước khớp hoàn toàn: 738 lần sleep, yêu cầu 0,738 s nhưng thực tế **10,97 s**
(mỗi lần 14,9 ms, max 41,8 ms), `compute` 14,10 s → phần không-ngủ chỉ 3,1 s.

### Nguyên nhân thứ hai (~1 s CPU, sẽ còn lại sau khi sửa #1): validate/serialize lại toàn bộ rule

Chi phí thật từng khâu (không throttle, median 3 lần):

| khâu | ms | ghi chú |
|---|---|---|
| `JSON.parse` rule 576 KB | 15 | mỗi request worker đều parse lại |
| `JSON.generate` rule | 16 | `stamp_metadata` + `seed_json` |
| `Marshal` round-trip rule | 24 | `Core.copy_data` |
| `SHA256(Marshal.dump(args))` | 12 | trong `UpdateWork.calculate` |
| **`Core.rule!` = `RuleSystem.validate!`** | **100** | validate toàn bộ bundle |
| `Parametric.variables` | 15 | |
| **`Parametric.edit_variables`** | **247** | gồm 1 lần validate + validate_variables! + part_formulas + rename |
| `Parametric.targets` | 21 | |
| **`Parametric.stamp_metadata`** | **221** | gồm 1 lần validate + 2× JSON.generate 576 KB |
| **`Core.plan` (RuleSystem.plan)** | **171** | gồm 1 lần validate + plan_parameters + vòng phương trình |
| `Core.copy_data(rule)` | 15 | gọi **6.561 lần**/job (self 466 ms) |
| `Reader.live` | 3 | |

Một lần đổi T1 chạy **5 lần validate toàn rule** (~500 ms) + **3 lần parse+validate lại rule ở đầu mỗi
request worker** (~115 ms × 3) + 3 khâu nặng (`edit_variables`, `stamp_metadata`, `plan`).
TracePoint còn cộng thêm ~22% overhead (632.593 call-event cho 3 vòng đo).

### Nguyên nhân thứ ba (riêng, không do sleep): UI vẫn giật 0,2–0,65 s

`max_step_ms` của main thread 210–252 ms; nhịp `UI.start_timer(0.1)` hụt tới 375–649 ms.
Đây là các đoạn main thread chạy dài (replay `apply_changes`, `JSON.parse` 576 KB, `copy_data`,
GC) — TracePoint không chen được vào code C nên nhả GVL không cứu được. Sửa #1 **không** tự hết #3.

---

## 2. Nếu sửa (chưa áp dụng, đúng yêu cầu "không code sửa hệ thống")

Thứ tự theo mức lợi:

1. **Thay `sleep(0.001)` bằng `Thread.pass`** (hoặc `sleep(0)`), giữ nguyên nhịp 3 ms — đo được
   0,02 ms/lần nhả thay vì 15 ms → dự kiến **11–16 s xuống ~2–3 s**. `Thread.pass` vẫn nhả GVL nên
   UI vẫn chạy.
2. Nếu muốn giữ `sleep`: nâng quantum từ 3 ms lên 15–30 ms công việc mỗi lần nhả (giảm số lần nhả
   từ 764 xuống ~40–80), và **đừng** dựa vào `timeBeginPeriod` (đã đo: vô hiệu).
3. Bỏ validate lặp: validate một lần ở biên job rồi truyền `validated: true` xuyên
   `edit_variables` / `stamp_metadata` / `plan`; bỏ `Core.rule!(JSON.parse(...))` lặp ở đầu mỗi
   request worker (dùng canonical rule đã có trong `job[:canonical_rules]`).
4. `UpdateWork.calculate`: hash chuỗi canonical JSON thay vì `Marshal.dump` cả rule (12–24 ms/lần).
5. `Core.copy_data`: tránh Marshal round-trip rule lớn khi chỉ đọc; 6.561 lần/job là quá nhiều.
6. Main thread: chia replay thành nhiều step nhỏ (parse/apply/stamp riêng), để nhịp UI không hụt
   0,2–0,65 s.

---

## 3. Bằng chứng (artifacts trong `outputs/options_profile_20261023/`)

| file | nội dung |
|---|---|
| `diag_timer.txt` | sleep/Thread.pass, có/không `timeBeginPeriod` |
| `diag_timer2.txt` | main vs worker thread, priority −2, `Sleep(1)` thô, priority class |
| `diag_timer3.txt` | bảng lượng tử hoá 1→32 ms |
| `diag_throttle.txt` | A/B đúng cơ chế nhả GVL trên `edit_variables` thật |
| `diag_stages.txt`, `diag_stages2.txt` | chi phí thật từng khâu (2 lần chạy) |
| `diag_job.txt`, `diag_job2.txt` | job end-to-end: wall vs CPU vs nhịp UI |
| `diag_power.txt` | EcoQoS, timer resolution, priority class |
| `profile_light_1.json` | profile phiên trước (764 sleep / 11,2 s) |
| `DIAGNOSIS_2026-10-23.md` | bản báo cáo gốc (trùng nội dung file này) |

Script đo: `diag_stages.rb` (chứa probe timer), `diag_timer2.rb`, `diag_timer3.rb`,
`diag_throttle.rb`, `diag_job.rb`, `diag_power.rb` (đều là artifact đo, không phải code sản phẩm).

## 4. Trạng thái sau đo

- Fixture QA đã xoá; model Untitled trở lại **0 entity, 0 definition, 0 material**, không job pending.
- Không còn hook nào gắn vào code sản phẩm (đã kiểm `source_location` của `Core.rule!`,
  `UpdateWork.compute`, `Parametric.edit_variables`, `RuleSystem.validate!` → trỏ đúng file gốc).
