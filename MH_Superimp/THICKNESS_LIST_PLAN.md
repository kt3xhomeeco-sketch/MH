# Kế hoạch: Danh sách độ dày cho MH_Superimp (import DC)

> Mục tiêu: thay cách "nhân bản file theo độ dày" (folder `MH` vs `18`) bằng cơ
> chế **độ dày theo loại vật liệu**, áp vào DC qua tham số, quản lý tập trung ở
> MH_Registry. Dễ dùng + khoa học + không bùng nổ số file.

## 0. Quyết định đã chốt
- DC: **mỗi file một scheme tham số riêng** → không hardcode 1 key được.
- Nơi quản lý: **MH_Registry** (tập trung), Superimp chỉ tiêu thụ qua connector.
- Chọn độ dày khi đang dùng tool: **phím Tab xoay vòng** qua các option.
- Nguồn vật liệu: **file Excel thống kê** (cột `Ma_vat_lieu`) → ra danh sách
  **loại vật liệu** thực dùng trong dự án (vd MDFCA, PLY.AC...).
- Mỗi DC: **độ dày 1 = panel**, **độ dày 2 = tấm hậu**; DC chỉ cần 1 giá trị thì
  để trống độ dày 2.
- **Mã độ dày ≠ mm thực tế** và **riêng theo từng loại vật liệu**. Ví dụ MDFCA:
  `6`→8mm, `17`→17.6mm, `9`→11mm.

## 1. Luồng dữ liệu (data flow)
```
Load material Excel → danh sách LOẠI vật liệu (= base + nhóm phủ, theo config)
        │
Import DC cho SPxx
  ├─ thongke.material_codes_for_product(SPxx)  → mã VL của SP → LOẠI (vd MDFCA)
  │
  ├─ dc_thickness_options[LOẠI]  → các OPTION = (panel_mm, back_mm) MM THỰC TẾ
  │       Tab = xoay vòng qua các option
  │
  ├─ dc_thickness_bindings[file] → param_panel / param_back / unit (file này)
  │
  ├─ apply: ghi mm thực tế vào tham số DC theo unit → redraw_with_undo
  │
  └─ gán VẬT LIỆU: giao MH_Material_Assign (material_names_for_product/code,
        nhận panel_mm/back_mm → build tên VL theo quy tắc của nó)
```

## 2.0 Tách "loại vật liệu" (key của bảng) — ĐA NHÓM TOKEN, theo config
Loại vật liệu được tách bởi **nhiều nhóm token** do user khai trong config, KHÔNG
hardcode. Có ≥2 phân loại nhóm:
- **Nhà cung cấp** (vd `AC`) — có thể ảnh hưởng độ dày → tách loại.
- **Nhóm phủ** (vd `LK`, `VER`, `MS`, `KL`) — tách loại.

### Sheet config `dc_type_groups` (MỚI) — định nghĩa token tách loại
| category | group | token_prefixes | note |
|---|---|---|---|
| supplier | AC | AC | nhà cung cấp |
| finish | LK | LK | laminate |
| finish | VER | VER,VENE | veneer |
| finish | MS | MS | sơn |

> Seed sẵn từ `ma_finish_groups`; user thêm nhóm nhà cung cấp (AC...) và sửa tùy ý.

### Quy tắc dựng key (tái dùng `material_family_parts` của Material Assign)
```
type_key(Ma_vat_lieu):
  parts  = MaterialCodeBuilder.material_family_parts(code)  # bỏ mã độ dày + đuôi .1M/.2M
  base   = parts.first                                      # vd MDFCA
  hits   = [] ; for mỗi dòng dc_type_groups: nếu parts khớp token_prefixes → hits << group
  ([base] + hits theo thứ tự category).join('.')
```
- `MDFCA.17.AC.MS.333PL` → `MDFCA.AC.MS`  (base + supplier AC + finish MS)
- `MDFCA.17.AC.LK`       → `MDFCA.AC.LK`
- `MDFCA.17`             → `MDFCA`
- Token không khai trong `dc_type_groups` (vd `333PL`) + token độ dày → bỏ khỏi key.

## 2. Cấu trúc dữ liệu (3 sheet mới trong Config.xlsx)
> `dc_type_groups` (mục 2.0) + 2 sheet dưới đây.
> (KHÔNG cần bảng code→mm: option ghi thẳng mm thực tế; mã VL do Material Assign lo.)

### 2.1 `dc_thickness_options` — danh sách option độ dày THEO LOẠI vật liệu
Lưu dạng **"rộng"**: 3 cột lớn = *mã vật liệu* + *Option 1* + *Option 2*; mỗi
option gồm **2 cột con** (độ dày 1 = panel, độ dày 2 = hậu). **Thêm option = thêm 2 cột.**

| material_type | opt1_panel | opt1_back | opt2_panel | opt2_back | … |
|---|---|---|---|---|---|
| MDFCA | 17.6 | 8 | 17.6 | 11 | … |
| MDFCA.VER | 17.6 | 8 | 18 | 11 | … |
| PLY.AC | 18 | (trống) | | | |

- Header gộp trong UI: `Mã vật liệu` | `Option 1`(2 cột) | `Option 2`(2 cột) | …
- Giá trị ô = **mm THỰC TẾ** (17.6, 8, 11…) — ghi thẳng vào tham số DC, chỉnh tay được.
- `opt*_panel` = độ dày 1 (panel), `opt*_back` = độ dày 2 (hậu); hậu trống ⇒ DC
  chỉ 1 giá trị. Cả cụm option trống ⇒ bỏ qua option đó.
- Tab xoay vòng theo thứ tự Option 1 → 2 → …
- Parser: cột 0 = loại; các cột sau đọc theo cặp (panel_mm, back_mm) tới hết.
- **Tự sinh**: load material Excel → quét `Ma_vat_lieu` → ra danh sách loại (qua
  `type_key`) → đổ sẵn các dòng (ô độ dày để trống cho user điền mm chuẩn).

### 2.2 `dc_thickness_bindings` — áp độ dày vào TỪNG FILE DC
| cột | ý nghĩa |
|---|---|
| `match` | định danh DC: đường dẫn .skp, hoặc `group:<Nhóm>`, hoặc pattern tên definition |
| `param_panel` | tên/key dynamic attribute = **độ dày 1 (panel)** |
| `param_back` | tên/key = **độ dày 2 (tấm hậu)** — ĐỂ TRỐNG nếu DC chỉ 1 giá trị |
| `unit` | `mm` (số thô) \| `length` (giá trị nội bộ SU, ghi `.mm`) \| `none` (file tĩnh, Tab bỏ qua) |
| `enabled` | 1/0 |

> Đây là lớp giải quyết "mỗi file một kiểu tham số". Thay cho key cứng
> `ba4ulq2qnw`/`ikqikbwfw7` và bảng `dc_material_options` trong pipeline hiện tại.

## 3. Thay đổi `connectors/dc_import_pipeline.rb`
- `type_key(material_code)`: tách loại theo `dc_type_groups` (mục 2.0).
- `material_types_in_project`: từ material Excel → danh sách loại VL (khử trùng qua `type_key`).
- `thickness_options(material_type)`: tra `dc_thickness_options` → list (panel_mm, back_mm).
- `thickness_options_for_context(context)`: SPxx → mã VL → loại → list option.
- `cycle_thickness_preset(context)` / `selected_thickness(context)`: thay/mở rộng
  `cycle_material_profile`; trả label HUD (vd "MDFCA · panel 17.6 / hậu 8").
- `apply_profile`: tra `dc_thickness_bindings` theo file → ghi **mm thực tế** vào
  `param_panel`/`param_back` theo `unit`, set mirror `_<key>_error`, rồi
  `redraw_with_undo` (giữ logic operation/timer cũ).
- **Gán vật liệu**: GIỮ NGUYÊN đường đi qua `material_assign` (resolve_product_materials
  → `material_names_for_product/code` với panel_mm/back_mm). Tên VL theo quy tắc Material Assign.
- Bỏ phụ thuộc key cứng `ba4ulq2qnw`/`ikqikbwfw7` và bảng `dc_material_options`.

## 4. Thay đổi `MH_Superimp/src/main.rb`
- Tab (`key == 9`) → `cycle_thickness_preset(registry_context)`. HUD hiện option
  độ dày hiện tại (panel/hậu).
- `import_list.xlsx`: **bỏ dòng "18" nhân bản**, còn ~18 cấu kiện logic. Cột
  `Nhóm`/`Swap Key` GIỮ cho đổi *cấu kiện* (khác đổi *độ dày*).
- Giữ `resolve_depth_based_import` (ray ngăn kéo) và file-swap — độc lập.

## 5. Helper "Học tham số" (Registry UI) — khai báo binding dễ dàng
- Chọn 1 DC trong model (hoặc load .skp) → liệt kê `dynamic_attributes`
  (tên + giá trị, lọc mirror `_`).
- Bấm dòng "độ dày 1 (panel)" / "độ dày 2 (hậu)" → tự điền `param_panel`/
  `param_back`, **tự dò `unit`** (Length ⇒ `length`; số mm thô ⇒ `mm`).
- Lưu vào `dc_thickness_bindings`.

## 6. UI Registry — đặt trong TRANG TỔNG HỢP (`data-panel="main"`)
- **Nâng card "Profile vật liệu" hiện có** (`#tbl_material_profile_choices`) thành
  bảng **`dc_thickness_options`**: dạng rộng, header gộp, mỗi option = 2 cột (panel/hậu
  mm thực tế), **nút "+ Option"** thêm 2 cột, nút **"Tải/Tự sinh từ material Excel"**
  (gom loại bằng `type_key`).
  - `material_profile_choices` (1 option) coi như bị thay thế; pipeline chưa dùng nó
    nên đổi an toàn. Giữ tương thích đọc cũ nếu cần.
- `dc_type_groups` + `dc_thickness_bindings`: đặt ở tab **Material Assign** hoặc
  **Cấu Hình** (config-level), kèm nút **"Học tham số"** cho bindings.

## 7. Tương thích ngược & di trú (không big-bang)
- File có binding ⇒ độ dày bằng tham số, xóa dần bản "18".
- File chưa khai báo binding ⇒ chạy như cũ (file-swap/swap_key).

## 8. Thứ tự triển khai
1. ✓ XONG **`dc_type_groups`** + hàm `type_key` + đọc/ghi Config.xlsx (đã test trên SU).
2. ✓ XONG (backend+UI, test trên SU) **`dc_thickness_options`** (mm thực tế, dạng rộng)
   + tự sinh loại VL từ Excel + `thickness_options_for_context` + UI card "Độ dày vật liệu (DC)".
   CÒN 2b: Tab xoay vòng trong tool Superimp + HUD panel/hậu.
2b. ✓ XONG Tab xoay vòng: pipeline `selected_profile`/`cycle_material_profile` ưu tiên
   thickness options → tool Superimp dùng nguyên Tab/HUD, KHÔNG cần sửa.
3. ✓ XONG **`dc_thickness_bindings`** + `apply_profile` ghi mm theo key/unit của binding
   (fallback key cứng cũ; gán VL vẫn qua material_assign). Test binding match OK.
4. ✓ XONG **Helper "Học tham số"** (callback `dc_dynamic_attrs`) + UI bảng
   `dc_type_groups`/`dc_thickness_bindings` trong tab Material Assign.
5. (THỦ CÔNG) Dọn `import_list.xlsx`, gỡ file "18" — để user tự làm với file thật.

## 9. Điểm cần xác nhận khi code
- ✓ Option ghi MM THỰC TẾ (17.6, 8...); gán mã VL giao Material Assign.
- ✓ Cột đầu = loại vật liệu; nguồn = Excel thống kê.
- ✓ `param_panel`=panel (độ dày 1), `param_back`=hậu (độ dày 2), trống ⇒ 1 giá trị.
- ✓ Loại = base + các nhóm token theo `dc_type_groups` (nhà cung cấp AC + phủ
  LK/VER/MS...); mỗi tổ hợp tách dòng riêng.
- ✓ Loại VL chỉ có 1 option: Tab không xoay (chỉ 1 lựa chọn) — ĐÃ CHỐT chấp nhận.
