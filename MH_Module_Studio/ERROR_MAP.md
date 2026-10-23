# Bảng tra lỗi — MH Module Studio

Cập nhật: **23/10/2026**.

Mục đích: từ **thông báo lỗi hoặc triệu chứng** → ra **file/hàm** trong một bước, không quét dự án.

Không thay thế các tài liệu khác:

| Cần gì | Đọc file |
|---|---|
| Tính năng/màn hình → file | [FEATURE_MAP.md](FEATURE_MAP.md) |
| Luồng gọi hàm chi tiết | [FLOW_MAP.md](FLOW_MAP.md) |
| Trách nhiệm và ranh giới tầng | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Mẫu thu thập bằng chứng | [BUG_REPORT.md](BUG_REPORT.md) |
| Giới hạn đọc, quy trình điều tra | [AGENTS.md](AGENTS.md) |

## Cách dùng (3 bước)

1. Người dùng báo lỗi → tìm **nguyên văn** thông báo ở **Bảng B**. Không thấy → tìm triệu chứng ở **Bảng A**.
2. `grep` nguyên văn thông báo (hoặc một phần đặc trưng) để lấy đúng dòng hiện tại. Số dòng trong bảng có thể lệch sau khi sửa code.
3. Chỉ mở **khoảng ±30 dòng** quanh chỗ khớp. Không đọc cả file, không mở file ngoài vùng.

Không thấy ở cả hai bảng → theo [AGENTS.md](AGENTS.md): hỏi 3 câu (lỗi gì, làm gì thì lỗi, lỗi lúc nào), xin Ruby Console, rồi mới mở rộng vùng.

## Bảng A — Triệu chứng → vùng

| Triệu chứng người dùng nói | Vùng tra trước | Ghi chú |
|---|---|---|
| Bấm **Cập nhật**, hình không đổi / rất chậm | [module_options.rb](module_options.rb) (`ModuleOptions#request` change) → [update_work.rb](update_work.rb) (`submit`, `compute`) → [runtime.rb](runtime.rb) (`apply_plan`) | Chậm đã đo: xem [PERFORMANCE_DIAGNOSIS.md](PERFORMANCE_DIAGNOSIS.md) |
| Sửa **T1/T2/độ dày** nhưng không lưu | [parametric.rb](parametric.rb) (`edit_variables`, `stamp_metadata`) → [options_parameters.rb](options_parameters.rb) | Kiểm cả `module_options.rb` (`change`) |
| **Redraw** báo lỗi hoặc ra hình cũ | [module_options.rb](module_options.rb) (`redraw_selected`, request `redraw`) → [update_work.rb](update_work.rb) → [assembly.rb](assembly.rb) (`redraw`) | |
| **Scale** xong hình sai kích thước | [scale_plan.rb](scale_plan.rb) → [scale_redraw.rb](scale_redraw.rb) (`apply`) → [geometry_motion.rb](geometry_motion.rb) | |
| **Liên kết mặt** sai / không bám | [assembly_tool.rb](assembly_tool.rb) → [assembly_face_picker.rb](assembly_face_picker.rb) → [assembly_math.rb](assembly_math.rb) | |
| **HUD** không mở / không kéo được module | [library_hud.rb](library_hud.rb) → [library.rb](library.rb) (`open_hud`, `place`) → [library_placement.rb](library_placement.rb) | |
| Thư viện **không thấy file mới** | [library_monitor.rb](library_monitor.rb) (`poll`) → [library_catalog.rb](library_catalog.rb) → [library.rb](library.rb) (`library_refresh`) | |
| **Import SKP** lỗi hoặc mất dữ liệu | [library_import.rb](library_import.rb) → [import_recovery.rb](import_recovery.rb) → [reader.rb](reader.rb) | |
| **Công thức** ra sai số | [formulas.rb](formulas.rb) → [formula_parser.rb](formula_parser.rb) → [formula_math.rb](formula_math.rb) | |
| **Đổi tên biến** làm hỏng công thức | [parameter_rename.rb](parameter_rename.rb) → [parametric_model.rb](parametric_model.rb) → [parametric.rb](parametric.rb) | |
| **Panel sai độ dày** / nhận nhầm biến | [thickness_symbols.rb](thickness_symbols.rb) → [options_parameters.rb](options_parameters.rb) | |
| **Chi tiết COPY** thừa/thiếu | [dc_copies.rb](dc_copies.rb) → [copy_runtime.rb](copy_runtime.rb) | |
| **Cụm module** sai kích thước tổng | [assembly_envelope.rb](assembly_envelope.rb) → [assembly_containers.rb](assembly_containers.rb) → [assembly_math.rb](assembly_math.rb) | |

## Bảng B — Thông báo lỗi → vùng

Nguyên văn từ `raise` trong code. `grep` lại chuỗi này để lấy dòng hiện tại.

### Cập nhật / Redraw

| Thông báo | File | Dòng (gốc) |
|---|---|---|
| Dữ liệu dựng đã thay đổi. Đọc lại module rồi thử lại. | [update_work.rb](update_work.rb) | 68 |
| Bộ quy tắc không hỗ trợ cập nhật gộp. | [update_work.rb](update_work.rb) | 126 |
| Lượt cập nhật vượt giới hạn bộ nhớ. | [update_work.rb](update_work.rb) | 242 |
| Module đang chọn đã đổi. Nhập lại thông số trên module hiện tại. | [module_options.rb](module_options.rb) | 184 |
| Module đang chọn đã đổi. Chọn lại module để Redraw. | [module_options.rb](module_options.rb) | 199 |
| Chọn lại module cần lưu. | [module_options.rb](module_options.rb) | 193 |
| Tham số đã ẩn hoặc không được sửa trực tiếp. | [module_options.rb](module_options.rb) | 216 |
| Quy tắc hoặc thông số đã đổi. Bảng được đọc lại. | [module_options.rb](module_options.rb) | 224 |
| Yêu cầu quá lớn. | [module_options.rb](module_options.rb) | 109 |
| Đây chưa phải bản thử. Dùng Tạo bản thử để giữ nguyên module/DC nguồn. | [runtime.rb](runtime.rb) | 102, 143 |
| Module chưa có bộ quy tắc riêng. | [runtime.rb](runtime.rb) | 124 |
| Chọn đúng một group/component cha trong SketchUp. | [runtime.rb](runtime.rb) | 16 |
| Module đang bị khóa. | [runtime.rb](runtime.rb) · [scale_redraw.rb](scale_redraw.rb) | 19 · 78 |
| Cấu trúc module quá sâu. | [runtime.rb](runtime.rb) · [scale_redraw.rb](scale_redraw.rb) · [assembly.rb](assembly.rb) | 24 · 41 · 38 |
| Không tìm được group điều khiển ẩn/hiện; đọc lại module. | [runtime.rb](runtime.rb) | 251 |

### Tham số / quy tắc

| Thông báo | File | Dòng (gốc) |
|---|---|---|
| Tên cần từ 1 đến 120 ký tự, không chứa ký tự điều khiển. | [parametric.rb](parametric.rb) | 21 |
| Chi tiết đã đổi; đọc lại module. | [parametric.rb](parametric.rb) | 53 |
| Danh sách biến không hợp lệ. | [parametric.rb](parametric.rb) | 112 |
| Không thể bỏ biến ATT đang được hệ quy tắc sử dụng. | [parametric.rb](parametric.rb) | 126 |
| Tên ký hiệu hoặc ID biến bị trùng. | [parametric.rb](parametric.rb) | 131 |
| Tên, ký hiệu, loại hoặc công thức biến không hợp lệ. | [parametric.rb](parametric.rb) | 140 |
| Không phải hệ quy tắc module v1. | [rule_system.rb](rule_system.rb) | 130 |
| Cây ATT không khớp hệ quy tắc. | [rule_system.rb](rule_system.rb) | 138 |
| Tham số ATT không khớp hệ quy tắc. | [rule_system.rb](rule_system.rb) | 142 |
| Có giá trị số không hữu hạn. | [domain.rb](domain.rb) | 33 |
| Khung hình học đảo chiều. | [domain.rb](domain.rb) | 45 |
| Module không có chi tiết hoặc vượt 600 chi tiết. | [domain.rb](domain.rb) | 99 |

### Thư viện / HUD / Import

| Thông báo | File | Dòng (gốc) |
|---|---|---|
| Folder đã thay đổi. Làm mới thư viện. | [library.rb](library.rb) | 35 |
| File đã đổi hoặc bị di chuyển. Làm mới thư viện trước khi đặt. | [library.rb](library.rb) | 159 |
| Config HUD vượt 4 MB. | [library.rb](library.rb) | 88, 100 |
| Bật Edit HUD trước khi kéo module. | [library.rb](library.rb) | 273 |
| Thư viện đã đổi. Kéo lại module từ Library hiện tại. | [library_hud.rb](library_hud.rb) | 568 |
| Tạo và chọn bảng icon trong Cài đặt HUD → Edit trước. | [library_hud.rb](library_hud.rb) | 571 |
| Bảng HUD không còn tồn tại. | [library_hud.rb](library_hud.rb) | 848 |
| Bộ quy tắc thư viện không hợp lệ. | [library_import.rb](library_import.rb) | 20 |
| SKP thiếu hoặc vượt giới hạn dữ liệu module. | [library_import.rb](library_import.rb) | 142 |
| Không hỗ trợ phiên bản module thư viện này. | [library_import.rb](library_import.rb) | 146 |

### Liên kết / công thức / bản sao

| Thông báo | File | Dòng (gốc) |
|---|---|---|
| Không tìm được duy nhất tấm đã liên kết. | [assembly.rb](assembly.rb) | 48 |
| Tấm tham chiếu đã thay đổi cấu trúc; chọn lại mặt. | [assembly.rb](assembly.rb) | 53 |
| Chọn mặt nằm trong group/component của module. | [assembly.rb](assembly.rb) | 84 |
| Mẫu chưa lưu cây ATT đầy đủ. Đọc lại module để ưu tiên công thức ATT. | [formulas.rb](formulas.rb) | 28 |
| Cây ATT không khớp các tấm trong module. | [formulas.rb](formulas.rb) | 67 |
| Copies vượt giới hạn 600 chi tiết. | [dc_copies.rb](dc_copies.rb) | 121 |
| Copies mới có góc xoay khác mẫu; chưa hỗ trợ tạo bản sao xoay. | [dc_copies.rb](dc_copies.rb) | 185 |
| Kích thước Scale nhỏ hơn độ dày / chi tiết cố định. Đã hủy thao tác. | [dc_copies.rb](dc_copies.rb) | 202 |

## Lấy bằng chứng trong 30 giây

SketchUp hiển thị lỗi ở **Window → Ruby Console**. Bắt buộc lấy:

```ruby
# 1. Phiên bản môi trường
Sketchup.version

# 2. Bản code đang chạy thật (không phải bản trên đĩa)
MH::ModuleStudio.method(:open_parametric).source_location
MH::ModuleStudio::UpdateWork.method(:compute).source_location

# 3. Lỗi vừa xảy ra
$!                     # lớp + thông báo
$!.backtrace.first(15) # 15 dòng đầu
```

Sao chép **nguyên văn** thông báo + backtrace. Ảnh chụp màn hình chỉ dùng khi không mở được console.

## Mã lỗi runtime (đã gắn ở cửa UI)

Mọi lỗi hiện lên panel đi qua `main.rb` (`add_action_callback('request')`) và được gắn tiền tố khu vực bởi `error_codes.rb`:

```text
[MH-LIB] Không đọc được thư viện.
```

Mã suy ra từ `action` của request, nên **không phải sửa từng chỗ `raise`**:

| Tiền tố | `action` chứa | Khu vực |
|---|---|---|
| `MH-UPD` | `update`, `redraw`, `options`, `import` | cập nhật / redraw / apply |
| `MH-PAR` | `parametric`, `rule` | tham số / công thức / biến |
| `MH-ASM` | `assembly` | liên kết / cụm module |
| `MH-LIB` | `library` | thư viện / HUD / import |
| `MH-SCL` | `scale` | scale |
| `MH-RUN` | còn lại | runtime / hình học |

Quy tắc:

- Mã đã có ở đầu thông báo thì không gắn lại (idempotent).
- `action` lạ hoặc không đọc được → `MH-RUN`.
- Cần mã chi tiết hơn (`MH-UPD-03`): gọi `ErrorCodes.tag('MH-UPD-03', '...')` tại chỗ `raise`, rồi thêm **một dòng** vào bảng B.
- Test: `test/error_codes_test.rb`.

Nhờ mã, ảnh chụp màn hình cũng đủ khoanh vùng.

## Giới hạn tra cứu

- Tối đa **3 lệnh grep, 2 file, 150 dòng** cho vòng đầu; sau đó chỉ mở thêm file nằm trên đường gọi trực tiếp.
- Không đọc cả file, không quét toàn dự án, không mở `CHANGELOG.md`/`README.md` khi đang chữa lỗi.
- Không kết luận khi chưa có thông báo lỗi hoặc tái hiện — theo [AGENTS.md](AGENTS.md).

## Bảo trì

Mỗi lỗi đã sửa xong → thêm **một dòng** vào bảng B (hoặc bảng A nếu là triệu chứng mới) và ghi ngày. Giữ bảng dưới ~120 dòng; quá thì gộp theo nhóm.
