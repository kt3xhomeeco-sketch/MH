# Kế hoạch (Mức 3) — Tách hẳn THƯ VIỆN (global) vs DỮ LIỆU DỰ ÁN (project)

> Mục tiêu: chấm dứt việc "Tự sinh từ Excel" / "Lưu" làm hỏng list thư viện Superimp
> và bảng vật liệu của dự án. Tách rạch ròi 2 miền dữ liệu: **thư viện dùng chung,
> bền** và **dữ liệu theo từng dự án**.
> Trạng thái: ✅ *ĐÃ TRIỂN KHAI (audit 2026-06-13) — xem §8.* Tách kho thư viện xong,
> P1 đã sửa. `ma_vat_lieu` chốt = THƯ VIỆN CHUNG (global), chỉ dùng `ma_vat_lieu_global`.

---

## 1. Hiện trạng & gốc rễ lỗi

**3 tầng lưu của `MH::Registry`:** `global` (Config.xlsx + global JSON), `project`
(JSON theo model/SPEC). Nhưng **dialog Registry trộn tất cả vào 1 config + 1 nút "Lưu"
+ 1 nút "Tự sinh từ Excel"**.

`MH_Registry/Config.xlsx` (global) hiện chứa LẪN LỘN:

| Nhóm | Sheet | Bản chất đúng |
|---|---|---|
| **Thư viện Superimp/DC** | `superimp_import_list`, `dc_manual_materials`, `dc_thickness_options`, `dc_thickness_bindings`, `dc_type_groups`, `dc_material_profiles`, `dc_material_options`, `material_profile_choices` | Thư viện dùng chung, bền, ít đổi |
| **Quy ước Material Assign** | `ma_valid`, `ma_invalid`, `ma_column_aliases`, `ma_surface_face_rules`, `ma_finish_group` | Quy ước dùng chung (library) |
| **Bảng map mã VL** | `ma_vat_lieu` / `ma_vat_lieu_global` | THƯ VIỆN CHUNG (global) — *quyết định ở §6* |

**Hai cơ chế gây hỏng (đã xác minh trong code):**

1. **`autoGenThicknessTypes`** (nút "Tự sinh từ Excel", `registry_app.js:433`): đọc loại VL
   của **dự án hiện tại** (`dc_thickness_types` → `project_material_types` →
   `material_assign.material_names`) rồi **GHI ĐÈ** `dc_thickness_options` **và**
   `dc_manual_materials` (hàm `overwriteManualMaterialsFromTypes`) → đập nát thư viện
   Superimp bằng dữ liệu 1 dự án.

2. **Nút "Lưu" duy nhất** (`main.rb` `save_config` callback, ~dòng 439): ghi TOÀN BỘ dialog
   xuống **Config.xlsx global** (đè thư viện) **VÀ** `proj['ma_vat_lieu_rules'] = data['ma_vat_lieu']`
   xuống project. Vì `ma_vat_lieu` global dùng chung mọi dự án → mở dự án B, dialog nạp
   `ma_vat_lieu` của dự án A (đang nằm global), Lưu → đè nhầm sang dự án B.

`material_assign` đọc list VL THẬT từ **project JSON** (`material_assign.rb:148 load_data`,
`project_json_path`) — phần này vốn đã theo dự án, KHÔNG sửa.

---

## 2. Kiến trúc đích

Tách thành **2 kho riêng + 2 luồng lưu riêng + 2 khu UI riêng**:

```
A. THƯ VIỆN SUPERIMP/DC (global, bền)   ->  file riêng: MH_Registry/superimp_library.xlsx
   - superimp_import_list, dc_manual_materials, dc_thickness_options,
     dc_thickness_bindings, dc_type_groups, dc_material_profiles,
     dc_material_options, material_profile_choices
   - Quy ước Material Assign dùng chung: ma_valid, ma_invalid, ma_column_aliases,
     ma_surface_face_rules, ma_finish_group   (giữ ở Config.xlsx global - library)

B. DỮ LIỆU DỰ ÁN (project)   ->  project JSON (đã có)
   - list VL thật (đã ở project JSON qua material_assign)
   - list VL thật (đã ở project JSON qua material_assign)
```

**Nguyên tắc bất biến:**
- Thao tác trên 1 dự án **không bao giờ** ghi vào kho thư viện (A).
- "Tự sinh từ Excel" chỉ tác động phía **dự án** (B) hoặc chỉ **gợi ý/merge** vào thư viện
  khi user bấm nút riêng — KHÔNG tự đè.

---

## 3. Thay đổi theo file

### 3.1 `config_manager.rb` (tách kho)
- Tách 2 nhóm sheet:
  - `superimp_library_sheets` (nhóm A) → đọc/ghi `superimp_library.xlsx`.
  - `Config.xlsx` giữ quy ước MA library (ma_valid/invalid/aliases/surface_face/finish_group).
- Thêm: `library_path` (đường dẫn superimp_library.xlsx), `load_library`/`save_library`
  (chỉ nhóm A); `load_config`/`save_config` tách phần thư viện ra khỏi phần project.
- **`ma_vat_lieu`**: giữ global trong Config.xlsx; runtime chỉ dùng nguồn global này.
- Migration: nếu `superimp_library.xlsx` chưa có → tạo từ các sheet tương ứng đang nằm
  trong Config.xlsx (copy 1 lần), rồi xoá khỏi Config.xlsx.

### 3.2 `main.rb` (tách callback lưu)
- Tách `save_config` callback thành 2 deferred:
  - `save_library` → chỉ ghi nhóm A (superimp_library.xlsx). KHÔNG đụng project.
  - `save_project_materials` → chỉ ghi `ma_vat_lieu` + suggestions vào project JSON.
- `run_mvl_pipeline`: đọc `ma_vat_lieu_global` từ Config.xlsx.
- `Connector.notify_config_changed`: tách thông báo (library-changed vs project-changed)
  để pipeline reload đúng phần.

### 3.3 `registry_app.js` + `registry.html` (tách UI + nút)
- 2 khu vực/tab rõ ràng: **"Thư viện Superimp (chung)"** vs **"Vật liệu dự án"**.
- 2 nút Lưu: **"Lưu thư viện"** (gọi `save_library`) và **"Lưu vật liệu dự án"**
  (`save_project_materials`).
- `autoGenThicknessTypes`: **bỏ `overwriteManualMaterialsFromTypes`**; với
  `dc_thickness_options` chỉ **MERGE** loại mới (giữ dòng cũ + độ dày đã nhập), không replace.
  Nếu muốn nạp loại VL dự án vào thư viện → nút riêng "Thêm loại từ dự án (merge)".
- Nút "Tự sinh từ Excel" phải là **PREVIEW/GỢI Ý**, không được tự ghi đè library đang dùng
  cho HUD. Nếu người dùng muốn đưa mã dự án vào thư viện thì bấm nút riêng và có status rõ:
  thêm bao nhiêu, bỏ qua bao nhiêu, không đụng `enabled=0`.
- `fillConfig`: nạp nhóm A từ library, `ma_vat_lieu_global` từ Config.xlsx.

### 3.4 `connectors/dc_import_pipeline.rb`
- `on_config_changed`: parse nhóm A từ library (không phụ thuộc project).
- `parse_manual_materials`/`parse_thickness_options`/`parse_bindings`/`parse_type_groups`:
  nguồn = library data.

### 3.5 `connectors/material_assign.rb`
- Giữ nguyên (đã đọc project JSON). Chỉ đảm bảo `ma_vat_lieu` lấy từ project khi cần.
- Không dùng `MaterialAssign` runtime cache làm nguồn ghi thư viện. `MH::MaterialApp.excel_data`
  là trạng thái đang chạy của Material Assign; Registry không được force reload rồi làm thay đổi
  trạng thái này chỉ để sinh list cho Superimp.

### 3.6 Nguồn Excel/cache cho "Tự sinh từ Excel" (bổ sung bắt buộc)
Vấn đề đã gặp: file Excel đã xoá mã nhưng dialog vẫn thấy mã cũ vì luồng sinh list fallback
về JSON/cache cũ (`ProjectData`, SPEC/Data JSON, `MH::MaterialApp.excel_data`).

Quy tắc mới:
- Khi user bấm **Tự sinh từ Excel**, phải đọc từ **nguồn được chỉ định rõ**:
  - hoặc file `.xlsx` đang chọn, đọc isolated/read-only;
  - hoặc project JSON hiện tại, nếu nút ghi rõ là "Tự sinh từ cache dự án".
- Không được gọi force reload làm thay đổi `MH::MaterialApp.excel_data` của Material Assign
  trong lúc chỉ cần sinh gợi ý cho Registry.
- Không được fallback âm thầm từ Excel sang JSON/cache cũ. Nếu Excel parse ra `0` dòng thì báo lỗi
  và **không xoá/ghi đè list hiện tại**.
- Parser Excel dùng cho Registry phải dùng cùng rule chuẩn hoá cột với Material Assign:
  `Ma_SP`, `Ten_chi_tiet`, `Ma_vat_lieu`, `Hoan_thien`. Nếu thiếu cột mã vật liệu thì báo rõ
  tên sheet/dòng header đang đọc.
- Kết quả "sinh từ Excel" phải là một danh sách preview:
  - `excel_types`: mã VL chuẩn hoá từ Excel;
  - `missing_in_library`: có trong Excel nhưng chưa có thư viện;
  - `stale_in_library`: có trong thư viện nhưng không còn trong Excel;
  - `parse_count`: số dòng Excel parse được.

### 3.7 Quy tắc HUD Superimp đọc list chuẩn
HUD Superimp chỉ đọc từ **library Superimp/DC** đã lưu và đã sync, không đọc trực tiếp Excel.

Luồng đúng:
1. Excel/project data chỉ tạo **gợi ý mã VL**.
2. User quyết định merge vào library.
3. Library lưu `dc_manual_materials` + `dc_thickness_options`.
4. Superimp HUD đọc library qua `dc_import_pipeline.on_config_changed`.

`dc_manual_materials`:
- Là bộ lọc mã vật liệu cho chế độ Manual.
- `enabled=0` nghĩa là HUD Manual không được hiển thị mã đó.
- Các thao tác sinh/merge không được tự bật lại dòng đã bị tắt.
- `label` là nhãn hiển thị, giữ nguyên khi merge.

`dc_thickness_options`:
- Là nguồn option độ dày.
- Manual lookup theo đúng `material_code_key(code)`, nếu không có mới fallback `type_key(code)`.
- Nếu mã có 4 option trong `dc_thickness_options` thì HUD phải hiện đủ 4 option, miễn là mã đó
  đang `enabled=1` trong `dc_manual_materials`.

### 3.8 Quy tắc ghi đè vs merge
Phải phân biệt rõ 3 hành động, không dùng chung 1 hàm mơ hồ:

| Hành động | Tác động | Có xoá dòng cũ? | Giữ `enabled/label`? |
|---|---|---:|---:|
| Preview từ Excel | Chỉ hiển thị gợi ý | Không | Không ghi |
| Merge vào library | Thêm mã mới, giữ thư viện | Không | Có |
| Replace theo Excel | Thay danh sách theo Excel | Có, nhưng chỉ khi user xác nhận rõ | Có với mã còn tồn tại |

Nút mặc định trong UI phải là **Preview/Merge an toàn**. Replace chỉ dùng khi user bấm nút riêng
"Ghi đè theo Excel" và dialog phải báo trước số dòng sẽ bị xoá.

---

## 4. Migration (chạy 1 lần, an toàn)
1. Backup `Config.xlsx`.
2. Tạo `superimp_library.xlsx` từ các sheet nhóm A đang có trong Config.xlsx.
3. Với mỗi project JSON đang có: xoá legacy `ma_vat_lieu_rules` / `ma_vat_lieu_project` nếu có.
4. Xoá nhóm A khỏi Config.xlsx; giữ `ma_vat_lieu` global trong Config.xlsx.
5. Log rõ đã di chuyển gì.

---

## 5. Thứ tự triển khai (mỗi bước test được)
> Trạng thái: B1 ✅, B2 ✅ (kèm tách CẢ dc_type_groups/dc_material_profiles/options/
> material_profile_choices vào library — vượt cả P3 ban đầu). B3 ❌ HỦY theo quyết định §6.
> B4 ✅ UI chỉ còn bảng `ma_vat_lieu_global`; Superimp có tab riêng. B5 ✅ bỏ mirror legacy khi lưu.

1. **B1 — Chặn hỏng ngay (Mức 1 lồng vào đây):** ✅ DONE
   - `autoGenThicknessTypes` không được đè `dc_manual_materials`.
   - Không force reload/ghi vào `MH::MaterialApp.excel_data` chỉ để sinh list.
   - Nếu Excel parse `0` dòng thì abort, không xoá library.
   - `enabled=0` phải được giữ, HUD không hiện mã đã tắt.
2. **B2 — Tách kho library:** thêm `superimp_library.xlsx` + load/save_library trong
   config_manager + migration. Pipeline đọc từ library. Test: sửa thư viện không đụng project.
3. **B3 — `ma_vat_lieu` project:** ❌ không làm. Chỉ dùng global.
4. **B4 — Tách UI:** tab Mã Vật Liệu chỉ có bảng global; Superimp có tab riêng.
5. **B5 — Dọn:** bỏ dual-write cũ, cập nhật notify_config_changed.

---

## 6. Quyết định ĐÃ CHỐT (2026-06-13)
- **`ma_vat_lieu` = THƯ VIỆN CHUNG (global).**
  - `ma_vat_lieu` trong Config.xlsx = mapping chung, dùng lại mọi dự án.
  - UI gọi rõ là `ma_vat_lieu_global`.
  - Không dùng `ma_vat_lieu_project`.
  - Khi lưu sẽ xoá key legacy `ma_vat_lieu_rules` / `ma_vat_lieu_project` khỏi project JSON.
- Vị trí file thư viện: `MH_Registry/superimp_library.xlsx` ✅ (đã dùng).

---

## 7. Rủi ro
- Migration đụng Config.xlsx (có cảnh báo Zip rubyzip khi đọc) → backup trước, ghi cẩn thận.
- Nhiều nơi đang đọc `data['ma_vat_lieu']` từ global → phải rà hết (run_mvl, save_config).
- Dialog đang 1 config object → tách state library/project cần kỹ để không vỡ round-trip.
- Excel parser đọc sai header có thể trả `0` dòng; tuyệt đối không dùng kết quả `0` để xoá
  thư viện nếu chưa có xác nhận.
- Cache cũ (`ProjectData`, JSON SPEC/Data, `MH::MaterialApp.excel_data`) có thể giữ mã đã xoá
  khỏi Excel. UI phải ghi rõ đang lấy từ **Excel thật** hay **cache dự án**.

---

## 8. Trạng thái triển khai — AUDIT 2026-06-12

Kiểm tra runtime qua SkAgent (load toàn bộ, 0 lỗi). Kết quả:

**✅ Đã xong:**
- **Tách kho thư viện:** `superimp_library.xlsx` chứa 8 sheet thư viện: `superimp_import_list`,
  `dc_manual_materials`, `dc_thickness_options`, `dc_thickness_bindings`, `dc_type_groups`,
  `dc_material_profiles`, `dc_material_options`, `material_profile_choices`. (Vượt cả P3 dự kiến.)
- **Config.xlsx** giờ chỉ còn: settings/prefix/suffix/modul + quy ước MA (ma_valid/invalid/
  column_aliases/surface_face_rules/finish_group/thickness/detail_aliases/tag_materials) +
  `ma_vat_lieu` (global, 19 dòng) + `dc_thickness_options_project` (lớp project của thickness).
- **Thickness 2 lớp** library + project, merge khi load (`merge_thickness_options`); autogen
  thickness chỉ ghi lớp PROJECT, SKIP mã đã có ở library.
- **P1 đã sửa:** `mergeManualMaterialsFromTypes` (thay `overwrite…`) — giữ nguyên mã thư viện,
  chỉ thêm mã mới với `enabled='0'` (không tự bật). Không xoá mã cũ.
- Pipeline đọc từ library (manual 2, thickness 18 loại, bindings 8). 4 connector OK. import 115.
- `ma_vat_lieu` global-only: UI có 1 bảng mapping global; `run_mvl` đọc global.
- Khi lưu, project JSON xoá legacy `ma_vat_lieu_rules` / `ma_vat_lieu_project`.

**⚠️ Lưu ý legacy:**
- Project cũ có `ma_vat_lieu_rules` / `ma_vat_lieu_project` sẽ bị xoá khi lưu Registry.

Liên quan: [[mh-dc-thickness-design]], [[mh-system-architecture]], [[mh-registry-config-separation]].
