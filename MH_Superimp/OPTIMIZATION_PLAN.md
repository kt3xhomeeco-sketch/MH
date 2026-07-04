# Kế hoạch tối ưu hóa MH_Superimp

> Mục tiêu: app xử lý **nhanh hơn**, code **gọn & đúng chuẩn kiến trúc**, và hệ thống **dễ nâng cấp** về sau.
> Trạng thái: 📋 *Kế hoạch — chưa sửa code.* Hướng đã chốt: **tách file theo cấu trúc module**.

---

## 1. Hiện trạng

Toàn bộ plugin nằm trong **một file `src/main.rb` (1837 dòng)**, gộp lẫn 5 mối quan tâm:

1. Đọc/ghi Excel (`import_list.xlsx`)
2. Logic nghiệp vụ (swap map, drawer-slide ray âm/bi)
3. Tool tương tác `LiveBoxPreviewTool` (~1300 dòng, ~40 instance variable)
4. Dialog HTML quản lý danh sách
5. Đăng ký menu

Không tách module, nhiều code lặp, và **tự bật Excel qua WIN32OLE** dù hệ sinh thái `MH_*` đã có sẵn thư viện thuần Ruby (`MH::XlsxIO`, `MH::ExcelBridge`, `MH::Registry`) nạp qua `require 'MH_shared'`.

---

## 2. Các vấn đề (xếp theo mức tác động)

### 🔴 P1 — Bật Excel qua WIN32OLE (nút thắt hiệu năng lớn nhất)
- `load_import_list` (`src/main.rb:178`) và `write_import_list_xlsx` (`src/main.rb:256`) **khởi động cả tiến trình `Excel.Application`** mỗi lần đọc/ghi.
- Hệ quả: chậm hàng giây mỗi lần load list, phụ thuộc máy phải cài Excel, dễ để lại tiến trình `EXCEL.EXE` treo nếu lỗi giữa chừng.
- **Giải pháp:** dùng `MH::XlsxIO.read(path)` / `MH::XlsxIO.write(path, sheets)` (thuần Ruby, đọc trực tiếp zip/xml, vendored rubyzip). Các plugin anh em (Thongke, Registry, Rename) đều đã `require 'MH_shared'`.
  - `MH::XlsxIO.read` trả về `Hash{ sheet_name => Array<Array<String>> }`.
  - Bỏ luôn `require 'win32ole'` và phụ thuộc Excel.

### 🔴 P2 — Raytest mỗi lần di chuột (lag khi hover mặt)
- Trong mode `:hovering`, mỗi `onMouseMove` gọi `compute_box_corners` → **6 lần `model.raytest`** + dựng `BoundingBox` (`src/main.rb:937`, vòng `dirs.each` tại `src/main.rb:973`).
- `raytest` rất đắt; chạy trên từng pixel di chuột gây giật khung hình.
- **Giải pháp:**
  - Chỉ recompute khi **đổi mặt** (`@picked_face` thay đổi) hoặc con trỏ dịch quá ngưỡng (vài px).
  - Cache `axis_info` theo `face.entityID`.
  - Tách phần "raytest 6 hướng" ra khỏi vòng vẽ; dùng kết quả cache khi chỉ đổi vị trí nhỏ.

### 🟠 P3 — Code lặp 4 lần: load + scale + transform
- `replace_object` (`src/main.rb:1609`), `import_to_box` (`src/main.rb:1664`), `import_with_plane` (`src/main.rb:1715`), `import_final_box` (`src/main.rb:1767`) lặp gần như nguyên si:
  `definitions.load` → tính `dx/dy/dz` → 3 transform `t3*t2*t1` → `add_instance` → `safe_redraw_dc` → commit → select → `selectScaleTool:`.
- Bug sửa 1 chỗ phải nhớ sửa cả 4.
- **Giải pháp:** trích helper chung `place_scaled_instance(import_path, target_min, target_size, op_name)`.
- Ngoài ra mẫu gom transform `path.reverse_each { |e| t = e.transformation * t }` lặp ~5 lần (`src/main.rb:766, 947, 1068`…) → gom thành `world_transform(path)`.

### 🟠 P4 — Tra cứu tuyến tính lặp lại + tính lại `swap_map`
- `import_list.find { normalize path }` quét tuyến tính ở `item_for_path` (`src/main.rb:41`), `set_import_path` (`src/main.rb:578`), init tool (`src/main.rb:543`).
- `swap_map` (`src/main.rb:26`) duyệt lại toàn bộ list **mỗi lần gọi**.
- **Giải pháp:** dựng index `@by_path` (Hash `normalized_path => item`) và memoize `swap_map` ngay khi nạp list; xóa cache trong `reload_import_list`.

### 🟡 P5 — Vi phạm chuẩn kiến trúc & khó bảo trì
- ~40 instance variable trong một class `LiveBoxPreviewTool`; state machine `@mode` rải rác qua nhiều `case`.
- Magic numbers khắp nơi: `5.mm` (offset), `100.mm` (default push), tolerance `0.5`, dải kích thước `200..700` (`src/main.rb:56`), `15px` (cạnh plane), `SWAP_TIMEOUT`.
- Màu định nghĩa nửa vời: vài hằng số ở đầu class (`src/main.rb:470`) nhưng `draw` lại hardcode `Sketchup::Color.new(...)` và `'red'/'cyan'/'black'`.
- `rescue` trống nuốt lỗi trong các hàm import (`src/main.rb:1648, 1710, 1762, 1806`) → khó debug.
- `migrate_txt_to_xlsx` (`src/main.rb:135`) là code legacy bằng Excel COM — có thể bỏ hoặc viết lại bằng XlsxIO.

---

## 3. Cấu trúc đích (đã chốt: tách file)

```
MH_Superimp/
├─ main.rb               # loader: require 'MH_shared' + require các file src/
└─ src/
   ├─ config.rb          # hằng số, màu, ngưỡng (gom hết magic numbers)
   ├─ import_list.rb     # đọc/ghi xlsx qua MH::XlsxIO + index by_path + swap_map (memoized)
   ├─ drawer_slide.rb    # logic ray âm/bi (resolve_depth_based_import, drawer_slide_info)
   ├─ registry_bridge.rb # tích hợp MH::RegistryApp::Connector (notify/watch/material profile)
   ├─ geometry.rb        # collinear edges, axis, world_transform, place_scaled_instance
   ├─ config_dialog.rb   # HtmlDialog quản lý danh sách
   ├─ tool.rb            # LiveBoxPreviewTool (mỏng hơn nhờ dùng helpers)
   └─ menu.rb            # đăng ký menu
```

Giữ `src/OLD/main.rb` làm tham chiếu trong suốt quá trình.

---

## 4. Lộ trình triển khai

Mỗi giai đoạn reload qua SkAgent và test workflow thực tế **trước khi sang bước kế**.

| GĐ | Việc | Lợi ích | Rủi ro |
|----|------|---------|--------|
| **0** | Backup `main.rb` + xác nhận `require 'MH_shared'` chạy được trong SketchUp đang mở | An toàn, đặt nền | – |
| **1** | Thay WIN32OLE → `MH::XlsxIO.read/write`; bỏ `require 'win32ole'` | **Load tức thì, bỏ phụ thuộc Excel** | Thấp |
| **2** | Trích `place_scaled_instance` + `world_transform`; 4 hàm import dùng chung | Bớt 4× lặp, sửa bug 1 chỗ | TB |
| **3** | Cache/throttle raytest hover; index `by_path`; memoize `swap_map` | **Hết giật khi rê chuột** | TB |
| **4** | Tách code ra các file `src/*.rb` theo cấu trúc mục 3 | Dễ nâng cấp/bảo trì | Thấp (chỉ di chuyển) |
| **5** | Gom hằng số vào `config.rb`; thay `rescue` trống bằng log có ý nghĩa; cân nhắc bỏ `migrate_txt_to_xlsx` | Đúng chuẩn, dễ debug | Thấp |

---

## 5. Checklist test (chạy lại sau mỗi giai đoạn)

- [ ] Load menu "MH Superimp – Multi Import" đầy đủ item từ xlsx
- [ ] Dialog "Quản lý danh sách…" mở, sửa, **Lưu** ghi đúng xlsx, "Reload xlsx" cập nhật
- [ ] Workflow 3-click: chọn cạnh → xác nhận plane → import 2D (trong plane) và 3D (ngoài plane, có depth)
- [ ] Live Box trên mặt: hover mượt, nhập số khóa kích thước, face_push 2-click
- [ ] Swap phím số 1-99 trong cùng nhóm; HUD swap hiển thị đúng
- [ ] Ctrl+Click replace giữ tool active, chạy tiếp object kế
- [ ] Tab đổi material profile (qua MH_Registry) nếu pipeline sẵn sàng
- [ ] Drawer-slide (ray âm/bi): import theo depth chọn đúng size gần nhất
- [ ] Khóa mặt ngang/dọc bằng phím mũi tên

---

## 6. Đo lường (trước/sau)

- Thời gian `load_import_list` (kỳ vọng: vài giây → < 100ms).
- Độ mượt khi rê chuột hover mặt (số raytest/giây giảm rõ).
- Số dòng `tool.rb` sau khi gỡ lặp (kỳ vọng giảm đáng kể so với 1837).

---

*Khi bắt đầu, chỉ cần yêu cầu "làm GĐ 1" (hoặc giai đoạn bất kỳ).*
