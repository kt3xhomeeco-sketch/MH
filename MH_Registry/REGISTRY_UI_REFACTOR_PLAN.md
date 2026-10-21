# Kế hoạch sửa UI MH_Registry (chốt 2026-06-14)

> Phạm vi: `ui/registry.html`, `ui/js/registry_app.js`, `main.rb`, `config_manager.rb`.
> ⚠️ Vùng code đang bị phiên khác refactor song song (config-separation, dc_import) +
> auto-commit liên tục → làm gọn 1 lượt rồi commit ngay để giảm xung đột.

## Quyết định đã chốt với user
- Nút "Sinh từ Config": GIỮ nguồn = `superimp_library` (hiện code đã đúng). Nếu user
  thấy nó lấy file dự án → là build cũ trong SketchUp, chỉ cần reload, KHÔNG đổi code.
- Tab Superimp chỉ còn **2 nút xlsx thật**: "Sinh từ Config" + "Lưu".
- Bỏ 5 tab: Sản Phẩm, Modul, Vật Liệu, Cấu Hình, Import/Export.

## Hiện trạng (file:line tham chiếu)
- Tabs: `registry.html:23-32` (main, superimp, products, modules, materials, naming,
  ma_vat_lieu, material_assign, config, io). Tab switch: `registry_app.js:1152-1161`.
- Mark products: nút `btnMarkProducts` (`registry.html:58`) → `markProducts()`
  (`registry_app.js:1045-1059`) → callback `mark_products` (`main.rb:488-544`).
  SP lấy từ `extract_sp_codes` (`main.rb:1241-1256`, sort theo số). Đặt nhãn cứng
  `Geom::Point3d.new((1000 + 5000 * i).mm, -1000.mm, 0)` (`main.rb:531-534`).
- "Sinh từ Config": `btnReloadMaterialProfiles` (`registry.html:119`) → `autoGenThicknessTypes`
  (`registry_app.js:469-520`) → `dc_thickness_types` (`main.rb:612`) →
  `config_material_types_preview` → `material_types_from_config` (`main.rb:772-796`)
  đọc sheet `dc_manual_materials/dc_material_options/material_profile_choices/dc_thickness_options`
  (từ `superimp_library.xlsx` + `Config.xlsx`). KHÔNG đọc file dự án.
- Nút xlsx tab Superimp: `btnReloadConfigSuperimp` (Tải lại, đọc), `btnSaveSuperimpLibrary`
  (Lưu thư viện, ghi library), `btnReloadMaterialProfiles` (Sinh từ Config),
  `btnSaveMaterialProfiles` (Lưu độ dày, ghi Config+library via `merge_dc_thickness_options_to_config`).
- Save: `save_config` (`main.rb:439`) → `config_manager.save_config` (ensure_superimp_library_data!
  + save_superimp_library + ghi Config.xlsx gồm `dc_thickness_options_project`).
- Sheet phân bổ: Config.xlsx = settings/naming/ma_*/`dc_thickness_options_project`;
  superimp_library.xlsx = superimp_import_list/dc_manual_materials/dc_thickness_options/
  dc_thickness_bindings/dc_type_groups/dc_material_profiles/dc_material_options/material_profile_choices.

## A. Tab Tổng hợp — "Đánh dấu sản phẩm": thêm đầu/cuối + khoảng cách
**HTML** (card `registry.html:53-61`): thêm trước `btnMarkProducts`:
- `<select id="markStart">`, `<select id="markEnd">` (đổ từ danh sách SP).
- `<input id="markSpacing" type="number" value="5000">` (mm).

**JS** (`registry_app.js`):
- Thêm `loadSpCodes()`: gọi callback `list_sp_codes` với `mvlInputPath` → đổ option vào
  `markStart`/`markEnd` (mặc định start=đầu, end=cuối). Gọi khi chọn file (`chooseMVLInput`)
  và khi restore path lúc bootstrap.
- `markProducts()` gửi payload `{ input, start, end, spacing }` thay vì chỉ path.

**Ruby** (`main.rb`):
- Callback MỚI `list_sp_codes`: nhận input_path → `extract_sp_codes` → resolve trả `{ok, codes}`.
- `mark_products`: nhận payload hash `{input, start, end, spacing}` (giữ tương thích string cũ).
  Cắt `sp_codes` theo [index(start)..index(end)] trong list đã sort; placement đổi
  `(1000 + spacing_mm * i).mm`. Mặc định spacing 5000, start/end = toàn bộ nếu trống.

## B. Tab Superimp — chỉ còn "Sinh từ Config" + "Lưu"
**HTML** (`registry.html:93-96, 119-122`):
- Xoá nút `btnReloadConfigSuperimp` (Tải lại).
- Bỏ `btnSaveSuperimpLibrary` (Lưu thư viện) ở header; gộp vào 1 nút **"Lưu"** duy nhất
  (đặt ở header tab Superimp hoặc cạnh "Sinh từ Config").
- Đổi `btnSaveMaterialProfiles` "Lưu độ dày" → chính là nút "Lưu" gộp (hoặc bỏ, dùng 1 id chung).
- Giữ "Sinh từ Config" (`btnReloadMaterialProfiles`), và các nút sửa dòng
  (+Dòng/+Option/+Parameter/Tạo binding/Đọc tham số) — KHÔNG phải nút xlsx.

**JS**: nút "Lưu" gộp → gọi `saveConfig()` (đã ghi cả library + Config project thickness).
Bỏ handler `btnReloadConfigSuperimp`. Kiểm tra `collectConfig` gom đủ các sheet superimp
(superimp_import_list, dc_thickness_options, dc_thickness_bindings, dc_type_groups,
dc_manual_materials, material_profile_choices, dc_material_*) để "Lưu" không làm rỗng sheet.

## C. Bỏ 5 tab (Sản Phẩm, Modul, Vật Liệu, Cấu Hình, Import/Export)
- Xoá nav button (`registry.html:25,26,27,31,32`) + `<section data-panel="products|modules|materials|config|io">`.
- Xoá lệnh `renderTable('products')/('modules')/('materials')/('thickness_mappings')/('invalid_materials')`
  trong `loadData` (`registry_app.js:1143-1144`) — nếu để lại sẽ lỗi thiếu `#tbl_*`.
- Bỏ handler nút trong panel đã xoá (data-save="project|global", data-export, btnScanModel,
  btnImport, btnReload...). Rà `init()` (`registry_app.js:~1162+`) gỡ addEventListener trỏ id đã xoá.
- Dữ liệu project.json/global KHÔNG mất; chỉ ẩn trình sửa. Giữ: Tổng hợp, Superimp, Đặt Tên,
  Mã Vật Liệu, Material Assign.

## Ý kiến bổ sung / chốt kỹ thuật

### 1. Đừng để "ẩn tab" biến thành "mất dữ liệu khi lưu"
Khi xoá panel khỏi DOM, mọi `collectTable(...)` trỏ tới bảng đã xoá sẽ trả rỗng hoặc lỗi
tuỳ implementation. Vì vậy các data không còn UI chỉnh sửa phải lấy lại từ `state/configData`,
không lấy từ DOM:

- Nếu bỏ tab Cấu Hình nhưng vẫn cần lưu `ma_thickness`, `ma_detail_aliases`, `ma_valid`,
  `ma_invalid`, `ma_column_aliases`, `ma_surface_face_rules`, `ma_finish_groups` thì
  `collectConfig()` phải đổi các dòng đó sang fallback:
  `state.config.<key> || configData.<key> || []`.
- Nếu bỏ tab Sản Phẩm/Modul/Vật Liệu thì `save(project/global)` và các handler
  `data-save="project|global"` cũng phải bỏ khỏi `init()`, nhưng `state.project/state.global`
  vẫn giữ để app đọc.
- Riêng tab **Mã Vật Liệu** còn giữ, nên `ma_vat_lieu_global` vẫn collect từ DOM là đúng.

### 2. Làm B trước C sẽ ít vỡ hơn
Thứ tự hiện ghi C → B → A. Đề xuất đổi thành:
1. **B trước:** gộp nút Superimp và kiểm tra `collectConfig()` đang lưu đủ
   `superimp_import_list`, `dc_*`, `material_profile_choices`.
2. **C sau:** xoá tab/panel, đồng thời sửa `collectConfig()`, `loadData()`, `init()`.
3. **A cuối:** thêm UX chọn khoảng SP.

Lý do: nếu xoá tab trước khi sửa `collectConfig()`, bấm Lưu Superimp có thể ghi rỗng các
sheet ma_* hoặc dc_* không còn DOM.

### 3. "Sinh từ Config" nên là preview/merge, không ghi file
Nút này chỉ nên:
- đọc `load_config`/`config_material_types_preview`;
- tạo danh sách project thiếu so với library;
- update state/UI.

Nó không nên gọi `save_config`, không nên tự ghi `Config.xlsx`/`superimp_library.xlsx`.
Chỉ nút **Lưu** mới ghi file.

### 4. Tab Superimp chỉ 1 nút Lưu, nhưng reload vẫn nên chạy ngầm
Đúng là không cần nút "Tải lại" riêng. Nhưng nên giữ cơ chế reload ngầm:
- khi mở dialog: `loadData()` rồi `loadConfig()`;
- khi chuyển sang tab Superimp nếu cần: gọi `loadConfig()` một lần nhẹ, hoặc báo trạng thái
  đang dùng dữ liệu đã load lúc mở dialog.

Không thêm ô import thứ hai. Nguồn Superimp là `superimp_library.xlsx` + phần project
`dc_thickness_options_project` trong `Config.xlsx`.

### 5. `registry_app.js` đang có thay đổi bẩn cùng file
Hiện `registry_app.js` đã có sửa trước đó ở phần `dc_thickness_bindings` (`label`,
`data-label`, `createBinding`). Khi làm plan này cần tránh ghi đè nhầm:
- stage theo hunk;
- review `git diff --cached`;
- không format nguyên file.

### 6. Guard DOM bắt buộc sau khi xoá tab
Sau C, mọi dòng kiểu `$('id').addEventListener(...)` với id có thể bị xoá phải đổi sang helper:
```js
function on(id, event, fn) {
  var node = $(id);
  if (node) node.addEventListener(event, fn);
}
```
Rồi dùng `on('btnReloadMaterialProfiles', 'click', autoGenThicknessTypes)` cho các nút optional.
Như vậy nếu sau này bật/tắt panel bằng HTML không làm chết toàn bộ dialog.

### 7. Test bổ sung
- Bấm **Lưu** sau khi bỏ 5 tab, mở lại `Config.xlsx` và `superimp_library.xlsx` kiểm tra
  các sheet không còn UI vẫn còn dữ liệu.
- Bấm **Sinh từ Config** khi không có file dự án/SPEC nào được chọn: phải vẫn chạy.
- Mở dialog mới sau khi commit: Console không có `Cannot read property addEventListener of null`
  hoặc `Cannot set innerHTML of null`.

## Thứ tự + kiểm thử
1. B (gộp nút Superimp) — khóa lại luồng lưu đúng trước.
2. C (bỏ tab) — xoá DOM + sửa `collectConfig/loadData/init` cùng lúc.
3. A (mark products đầu/cuối/khoảng cách) — phần nhiều code nhất (callback + dropdown).
4. Reload 3 file Ruby qua bridge (MCP `execute_ruby`), mở lại dialog, test:
   - dialog load 0 lỗi JS; 5 tab còn lại hiện đúng.
   - list_sp_codes đổ dropdown; mark_products đặt nhãn theo start/end/spacing.
   - "Lưu" ghi cả 2 xlsx, "Sinh từ Config" vẫn chạy.
5. Commit ngay (tránh xung đột phiên song song).

## Rủi ro
- Phiên khác đang sửa cùng `registry.html`/`registry_app.js`/`dc_import_pipeline.rb`
  (config-separation [[mh-registry-config-separation]], dc_import refactor
  [[mh-dc-import-refactor-plan]]). Khả năng clobber — cần làm 1 lượt + commit nhanh, hoặc
  phối hợp tắt auto-commit trước.
