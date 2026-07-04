# MH_assemble_three_test — Kế hoạch nâng cấp Dialog + Module con

> Trạng thái: **PLAN — chưa code**. Khi user gõ "code" → triển khai theo thứ tự Phase bên dưới.
> Ngày lập: 2026-06-12 · Nhánh: `mh-assemble-three-export-test`

---

## 0. Mục tiêu

1. **Dialog chính gọn, chuyên nghiệp**: chỉ còn Xuất theo Selection + mở Settings + thanh % hoàn thành.
2. **Settings dialog riêng** gom toàn bộ cấu hình: không cánh, ẩn mọi bản, không đánh số, tỉ lệ bản vẽ mặc định, và bảng **module con**.
3. **Tính năng MODULE CON**: nhóm part có tên bắt đầu bằng từ khóa (vd `Hộc`) được tách thành bản vẽ riêng "module của module", có mini-map, trong khi trang module cha gom nhóm này thành 1 bóng + 1 hàng bảng với tên hiển thị (vd `Ngăn kéo`).
4. **Không cánh 2 cấp độ** (sản phẩm / module — §3a), **selection xuất đúng subset** (§5a), **dọn hiển thị trang + bảng** (§5b), **nhập tên sản phẩm** ở dashboard, **tỉ lệ nhập tự do**.

---

## 1. Kiến trúc & nguyên tắc

- **Config dùng chung** với app gốc: mọi setting ghi vào `MH_assemble/config.json` qua `MH::Assemble.config` + `save_config` (KHÔNG tạo file config riêng). Lý do: three_test đã gọi `MH::Assemble.visible_parts / listed_parts / render_minimap_module` → sửa 1 chỗ cả 2 app cùng ăn.
- **Key mới** trong config.json:
  ```jsonc
  {
    "draw_ratio": "auto",            // tỉ lệ mặc định: "auto" | số N bất kỳ (nhập tự do, không chỉ preset)
    "draw_ratios": [5,10,15,20,25,50,100], // các nút preset tỉ lệ, sửa được trong Settings
    "sub_modules": [                 // bảng module con (2 cột)
      { "key": "Hộc",  "label": "Ngăn kéo" },
      { "key": "Khay", "label": "Khay chia" }
    ],
    "no_door_scope": {               // KHÔNG CÁNH tách 2 CẤP ĐỘ (xem §3a)
      "product": ["Cánh Trái", "..."],   // ẩn khi vẽ TRANG SẢN PHẨM (tổng quan tủ)
      "module":  ["Cánh Trái", "..."]    // ẩn khi vẽ TRANG MODULE (+ module con)
    }
  }
  ```
- **Tương thích ngược**: `profiles.no_door.hide` (cũ) GIỮ NGUYÊN cho app gốc. Lần load đầu nếu chưa có `no_door_scope` → seed cả 2 list từ `profiles.no_door.hide`. Three_test dùng helper mới `visible_parts_scoped(parts, prof, scope)` (thêm vào `MH_assemble/config.rb`, app gốc không bị ảnh hưởng).
- Three_test **không đụng** vào pipeline render PNG của app gốc — chỉ dùng scan + helpers + render_minimap_module (đã có sẵn `highlight:`/`base_parts:`/`over_tag:`/`base_tag:` từ đợt trước).

---

## 2. Dialog CHÍNH (viết lại `main.rb#dashboard`)

```
┌─ MH Assemble Three ────────────────────┐
│  Tên sản phẩm: [________________]       │  ← optional: override tên từ Excel
│  [ 🡒  XUẤT THEO SELECTION ]            │  ← nút lớn màu chủ đạo (#2577c9)
│  Profile:  (all ▾)                      │  ← dropdown nhỏ: all / full / no_door
│  [ ⚙  Cài đặt… ]                        │
│                                         │
│  ▓▓▓▓▓▓▓░░░░░  7/18 · Render trang 7   │  ← thanh % (ẩn khi rảnh, tự ẩn sau 2.5s khi xong)
└─────────────────────────────────────────┘
```

- **Bỏ** các nút: Xuất 1 module, Xuất cả tủ, Mở thư mục, ô Mã tủ/Module.
  (Xuất cả tủ vẫn dùng được qua selection: chọn cả tủ → bấm nút.)
- **Ô "Tên sản phẩm"** (mới): để trống → lấy tự động (Excel/MH_Thongke như hiện tại). Có nhập → **ưu tiên cao nhất**, dùng làm Tên sản phẩm trong khung tên mọi trang của lần xuất đó (phòng SP không có tên / muốn đổi tên Excel). Đồng thời lưu vào `config['product_names'][mã_SP]` để lần sau tự điền lại vào ô.
- Giữ nguyên cơ chế `mhThreeProgress(pct, done, total, text)` + `MH::AssembleThreeTest.panel`.
- Kích thước dialog ~320×250, STYLE_UTILITY.

## 3. Dialog SETTINGS (hàm mới `main.rb#settings_dialog`)

Bố cục 6 mục, mỗi mục có tiêu đề + mô tả 1 dòng; nút **Lưu** to dưới cùng; báo "✓ Đã lưu" inline (không messagebox).

| # | Mục | UI | Lưu vào |
|---|-----|----|---------|
| 1 | **KHÔNG CÁNH — cấp SẢN PHẨM** | textarea (mỗi dòng 1 tên, khớp CHÍNH XÁC) | `no_door_scope.product` |
| 2 | **KHÔNG CÁNH — cấp MODULE** | textarea | `no_door_scope.module` |
| 3 | Chi tiết **CẦN ẨN** (mọi bản) | textarea | `hide_common` |
| 4 | Chi tiết **KHÔNG ĐÁNH SỐ** | textarea | `no_number` |
| 5 | **TỈ LỆ bản vẽ** mặc định | segmented buttons `AUTO + các preset trong Settings` **+ ô nhập tự do "1: [___]"** (nhập N bất kỳ, vd 8, 35) **+ ô sửa danh sách preset** | `draw_ratio`, `draw_ratios` |
| 6 | **MODULE CON** | bảng 2 cột editable: \| Từ khóa gom \| Tên hiển thị \| + nút "+ Thêm dòng" / nút xóa từng dòng | `sub_modules` |

Callback `save`: parse JSON → gán vào `MH::Assemble.config` → `save_config` → trả script báo ✓.

### 3a. Ngữ nghĩa KHÔNG CÁNH 2 cấp độ

Trước: 1 list `profiles.no_door.hide` áp cho MỌI trang no_door. Giờ tách:

| Loại trang | Profile no_door ẩn theo list |
|---|---|
| Trang **SẢN PHẨM** (tổng quan tủ) | `no_door_scope.product` |
| Trang **MODULE** (kể cả tủ '00' và module con NK1…) | `no_door_scope.module` |

- Helper mới trong `MH_assemble/config.rb`: `visible_parts_scoped(parts, profile, scope)` (`scope = :product | :module`) — tái dùng logic exact-match + hide_common + ancestor_hidden, chỉ thay nguồn hide list khi profile = no_door.
- `module_profiles` (quyết định có ra bản no_door không) cũng nhận scope tương ứng.
- Ô nhập tỉ lệ tự do: ràng buộc N nguyên 1–1000; rỗng/0 = giữ nguyên giá trị cũ.

---

## 4. Tính năng MODULE CON (`three_export.rb`)

### 4.1 Nhận diện & gom cụm — `split_sub_modules(parts)`

```
input : mảng part (1 module sau reject flat)
output: { main: [...part không thuộc nhóm nào],
          clusters: [ { key:'Hộc', label:'Ngăn kéo', short:'NK', idx:1,
                        code:'NK1', parts:[...] }, ... ] }
```

- **Thứ tự lọc (QUAN TRỌNG)**: `visible_parts(parts, profile)` chạy TRƯỚC → rồi mới `split_sub_modules` trên phần còn hiện. (Part hộc bị ẩn theo profile thì không vào cluster.)
- **Match**: `part[:part]` bắt đầu bằng `key` (norm: bỏ dấu cách thừa, không phân biệt hoa thường; chấp nhận `Hộc - X`, `Hộc-X`, `Hộc_X`, `Hộc X`).
- **Tách instance** (2 ngăn kéo trong cùng module = 2 cluster): gom theo **container cha gần nhất** — phần tử cuối của `p[:path]` (ancestor group). Part cùng key + cùng container → cùng cluster. Part match key nhưng không có container riêng → gộp vào cluster "lẻ" cuối.
- **Đánh số ổn định**: sort cluster theo vị trí bbox (Z giảm dần → X tăng dần → Y), KHÔNG theo entityID (đổi giữa các session) → `NK1` luôn là hộc trên cùng/trái nhất, re-export không bị đảo số.
- **Mã cluster**: viết tắt từ label (lấy chữ cái đầu các từ, vd `Ngăn kéo` → `NK`) + số thứ tự: `NK1`, `NK2`. Nếu trùng viết tắt giữa các rule khác nhau → thêm phân biệt (`NK1`, `KC1`).
- Cluster CHỈ tính khi có ≥ 2 part (1 tấm lẻ trùng tên thì để lại main, tránh tách vô nghĩa).

### 4.2 Trang MODULE CHA (vd `SP47.06`)

- Hình: **vẫn vẽ đủ** mọi part (main + clusters) — không ẩn gì thêm; vẫn đủ 2 profile full / no_door như cũ.
- **Bóng số** — JS hiện tại là either/or (`explicitLabels` CÓ thì bỏ hết pin theo mesh) → phải nâng thành trộn:
  - mỗi mesh thêm cờ `pin` (mặc định true): part main → `pin:true` (bóng id như hiện tại); part thuộc cluster → `pin:false` (không bóng lẻ);
  - thêm trường `extra_labels: [{id:'NK1', point:[x,y,z]}]` vào page hash — mỗi cluster 1 nhãn tại tâm bbox cụm;
  - JS: addPin cho mesh có `pin!==false` + addPin cho từng `extra_labels` (object:null như overview); `relaxPinLabels` chạy chung cả 2 loại trong cùng mảng `pins` (tự né nhau, không cần code thêm).
- **Bảng**: chuyển trang cha sang cơ chế `table_rows` (đã có sẵn cho overview — `tableHtml` đang build từ `page.meshes`, không chèn hàng tùy ý được): rows = part main (`id | tên | material`) + mỗi cluster 1 hàng `NK1 | Ngăn kéo (<số part> tấm) | —`. Cột giữ nguyên `ID | Tên tấm | Material`.

### 4.3 Trang MODULE CON (xuất NGAY SAU trang cha)

- Thứ tự book: `…06 [full] → 06 [no_door] → 06·NK1 → 06·NK2 → 07 [full] → …`
- Mã bản vẽ / code: `SP47.06.NK1`; tiêu đề hiển thị: `SP47.06 · Ngăn kéo 1`.
- Nội dung: chỉ part của cluster; **id thật** từng tấm (bóng + bảng "Danh sách tấm" như trang module thường).
- Profile: qua `module_profiles(cluster_parts, profs)` — hộc thường không cánh → tự còn 1 trang full.
- **Mini-map**: `MH::Assemble.render_minimap_module(product, label, [], mods, highlight: cluster_parts, base_parts: module_solids, over_tag: "06.NK1", base_tag: "m06")`
  → nền = module cha đen-trắng, đỏ = cluster. (Tham số đã có sẵn, không cần sửa app gốc.)
- Khung tên: như trang thường (Tên công trình / Tên SP / Mã `SP47.06.NK1` / Tỉ lệ).

### 4.4 Điểm chạm code trong `three_export.rb`

| Hàm | Sửa gì |
|-----|--------|
| `product_page_builders` | sau 2 builder profile của mỗi module: chèn builders cluster (mỗi cluster × profile 1 builder). **Áp dụng CẢ nhánh tủ không module (`labels == ['00']`)** — nhánh này đang return sớm, phải chèn cluster builders trước khi return |
| `export_module` | tương tự (đường 1 module) |
| `build_page` | thêm tham số `sub_split:` — nếu có: mesh cluster gắn `pin:false`, thêm `extra_labels` + `table_rows` gộp |
| hàm mới `build_sub_module_page(product, label, cluster, prof, mini)` | dựng page con (tái dùng build_page với code/caption riêng) |
| `title_block_for` | nhận code dạng `SP47.06.NK1` (base vẫn = SP47, đã OK vì split('.')[0]) |
| JS `makePage`/`addPin` | mesh `pin:false` không tạo pin; `extra_labels` tạo pin tự do (object:null); bảng ưu tiên `table_rows` nếu có |

---

## 5. Tỉ lệ mặc định từ config (`draw_ratio`)

- `html_for`: đọc `MH::Assemble.config['draw_ratio']` → nút `data-ratio` tương ứng render sẵn `class="active"`; nếu là số ngoài preset → đánh dấu active vào ô nhập tự do của trang (panel trái mỗi viewer cũng thêm ô "1:[___]" giống Settings).
- `draw_ratios`: danh sách preset sửa được trong Settings; `AUTO` chọn tỉ lệ gần nhất từ chính danh sách này.
- `applyUiState` đọc nút active từ DOM → không cần sửa thêm.
- Settings đổi `draw_ratio` → lần xuất sau tự ăn (file HTML cũ giữ nguyên tỉ lệ lúc xuất).

---

## 5a. Xuất theo SELECTION = CHỈ chi tiết đã chọn (đổi hành vi)

Hiện tại: chọn 1 part → xuất **CẢ TỦ** chứa nó (`product_page_builders` full product). **Bỏ hành vi này.**

Mới (giống app gốc):
- Gom part đã chọn (entityID + con cháu trong selection, qua `p[:path]`) theo `(product, module)`.
- **Chỉ render các part đã chọn** — part ngoài selection KHÔNG xuất hiện trong hình lẫn bảng, kể cả trùng tên.
- Cấu trúc book: mỗi tủ có part được chọn → (nếu chọn ≥2 module) 1 trang **tổng quan-selection** gộp part đã chọn của tủ + các trang **module-selection** (chỉ part đã chọn của module đó). Profile full/no_door theo scope tương ứng (§3a).
- **Module con vẫn áp dụng** trên subset: nếu part đã chọn chứa trọn cluster → tách trang con như thường.
- **Mini-map** trang module-selection: `base_parts:` = part đã chọn của TỦ, `highlight:` = part đã chọn của module (tái dùng tham số có sẵn, giống bản fix app gốc).
- Selection rỗng / không có part SPxx → messagebox (đã làm đợt trước, giữ nguyên).

## 5b. Chỉnh hiển thị trang (dọn thông tin thừa)

1. **BỎ** khỏi trang in:
   - thanh `.head`: `Profile: full · 18 part · 216 tam giác` → bỏ hẳn các thông tin này (giữ MÃ bản vẽ to bên trái).
   - khối `.meta`: `2026-06-12 12:27:46 · build 8ms` (+ cả warning tam giác chỉ hiện khi screen, ẩn khi in).
2. **`Số part` → `Số chi tiết`** ở mọi chỗ còn lại (header bảng overview, caption…).
3. **Tên sản phẩm bản không cánh**: khung tên ghi `<Tên sản phẩm> - Không cánh` (thay vì hiện chữ `no_door`/`no door` ở bất kỳ đâu). Áp cho cả trang sản phẩm lẫn module. (Giống `product_label` của app gốc.)
4. **Bảng "Danh sách tấm"**: cột **Tên tấm giảm 40% chiều rộng**, phần giảm dồn sang cột **Material** → `table-layout: fixed`, ID 32px giữ nguyên, Tên ≈ 36% chiều rộng bảng (từ ~60%), Material nhận phần còn lại (Material dài kiểu `HDFCA.17.AC.MS.446FR` hết bị cắt).

---

## 6. Trình tự triển khai (Phases)

- [x] **P1 — Config**: `MH_assemble/config.rb` thêm `draw_ratio` + `sub_modules` + `no_door_scope` (seed từ `profiles.no_door.hide` lần đầu) vào `load_config` + helpers `draw_ratio`, `sub_modules`, `visible_parts_scoped`, `module_profiles_scoped`. Verify roundtrip qua bridge.
- [x] **P2 — Settings dialog**: `main.rb#settings_dialog` (6 mục: không cánh SP / không cánh module / ẩn / không số / tỉ lệ preset + ô nhập tự do / bảng module con). Verify: sửa → Lưu → đọc lại config.json đúng.
- [x] **P3 — Dashboard mới**: `main.rb#dashboard` gọn (ô Tên sản phẩm + Selection + Settings + %). Verify mở panel, progress chạy, tên nhập được lưu vào `product_names`.
- [x] **P4 — Hiển thị trang (§5b)**: bỏ head-info + meta, `Số chi tiết`, hậu tố `- Không cánh`, bảng cột Tên −40% → Material. Verify HTML.
- [x] **P5 — Selection subset (§5a)**: export_selection chỉ render part đã chọn + mini-map base=selected-tủ. Verify: chọn 3 part → trang chỉ có 3 part.
- [x] **P6 — split_sub_modules**: thuần Ruby + test bridge trên SP có hộc thật (in cluster: key/label/code/số part/container).
- [x] **P7 — Trang cha**: `build_page(sub_split:)` + cờ `pin:false` + `extra_labels` + `table_rows` JS. Verify: bảng có hàng `NK1 | Ngăn kéo`, part hộc không còn bóng lẻ, pin NK1 hiện đúng tâm cụm.
- [x] **P8 — Trang con + mini-map**: builders chèn sau trang cha; mini-map nền module + đỏ cluster. Verify thứ tự trang + ảnh mini đúng.
- [x] **P9 — draw_ratio**: nút/ô active theo config (kể cả N tự do ngoài preset). Verify HTML chứa active đúng.
- [x] **P10 — Preview/Open ổn định**: sau export tự mở browser bằng native Windows path / fallback; không dùng messagebox chặn focus. Verify mở đúng file HTML mới nhất.
- [x] **P11 — Print/PDF ổn định**: trước khi in phải snapshot từng viewer 3D; `beforeprint` cũng chuẩn bị snapshot nếu user bấm Ctrl+P. Verify PDF đủ chi tiết bản vẽ.
- [x] **P12 — WebGL lifecycle**: không dựng tất cả canvas cùng lúc; lazy/recycle viewer; kéo lại trang 1-2 không mất model; sau print checkbox vẫn điều khiển viewer sống.
- [ ] **P13 — Chạy end-to-end**: chọn 1 tủ có hộc → Xuất theo Selection → review browser; kiểm Không màu, Back edge, Guide, kéo nhiều trang, In PDF; user xác nhận; commit.

Mỗi phase: code → reload qua bridge → verify → mới sang phase sau.

---

## 7. Quyết định đã chốt (user OK ngầm nếu không phản hồi)

1. Nhiều hộc giống nhau trong 1 module → **mỗi hộc 1 trang riêng** (không gộp SL=2 chung 1 bản vẽ) — để mini-map chỉ đúng vị trí từng hộc.
2. Cluster cần **≥ 2 part** mới tách; 1 tấm lẻ ở lại trang cha.
3. Trang cha **không ẩn** part hộc — chỉ thay numbering bằng 1 bóng cụm.
4. Mã cluster = viết tắt label + số (`NK1`); hiển thị tiêu đề `Ngăn kéo 1`.
5. Tách instance theo container cha gần nhất trong `p[:path]`.
6. Lọc profile TRƯỚC, split cluster SAU; đánh số cluster theo bbox (Z↓ → X↑), không theo entityID.
7. Tủ không module (nhánh `'00'`) cũng được tách module con.
8. `profiles.no_door.hide` cũ GIỮ cho app gốc; `no_door_scope` seed từ nó lần đầu; three_test chỉ dùng scoped.
9. Tên sản phẩm nhập ở dashboard: ưu tiên cao nhất (> Excel/MH_Thongke), lưu lại vào `product_names`.
10. Selection xuất subset: part ngoài selection không vào hình lẫn bảng; module con vẫn tách nếu cluster được chọn trọn.

## 8. Rủi ro / lưu ý

- Part hộc **rời rạc không có group container** → fallback: cả key gom thành 1 cluster duy nhất (mini-map vẫn đúng nhóm, chỉ không tách NK1/NK2).
- `extra_labels` + pins trộn: chú ý `relaxPinLabels` chạy chung cả 2 loại để không đè nhau.
- Mini-map gọi vào app gốc (render PNG qua SketchUp view) → chạy trong builder của render queue (đã async, có %).
- Settings ghi chung config.json với app gốc — **không** xóa key cũ khi save (merge, không replace).
- Browser preview: ưu tiên mở file HTML bằng đường dẫn native Windows; `UI.openURL(file://...)` có thể fail với path tiếng Việt/dấu cách.
- PDF: các control `.no-print` phải ẩn hết khi in; viewer WebGL phải được chụp thành `print-snapshot` để không bị thiếu chi tiết.
- WebGL: file 15–20 trang không được tạo toàn bộ canvas cùng lúc vì browser có giới hạn context, dễ làm trang đầu trắng/mất model.
- Guide geometry: `ConstructionLine` vẽ nét đứt đen, `depthTest:true`; phần bị part che không được nhìn xuyên. `ConstructionPoint` vẽ dấu thập nhỏ.

## 9. Test matrix bắt buộc trước khi nhập app chính

| Nhóm | Case cần kiểm |
|------|---------------|
| Selection | chọn 1 part, 1 module, cả tủ |
| Profile | `full`, `no_door`, `all` |
| Module con | có cluster, không cluster, cluster bị profile lọc còn < 2 part |
| Trang tổng | trang 1-2 có model, màu đúng, nhãn module đúng |
| Trang cha/con | cha có `NK1` và không bóng lẻ cluster; con `SPxx.yy.NK1` có id tấm thật |
| Mini-map | trang con nền module cha, đỏ đúng cluster |
| Viewer | kéo lên/xuống nhiều trang không mất model |
| Controls | Không màu, Back edge, Explode, Chân ID, view buttons |
| Guide | guide nét đứt đen, bị part che đúng depth, vào PDF |
| Print | PDF đủ chi tiết, không in toolbar/nút/slider/checkbox |

## 10. Mở rộng tương lai (ngoài scope)

- Gộp hộc giống hệt nhau thành 1 trang + SL=n.
- Module con lồng nhiều cấp (hộc trong hộc) — hiện chỉ 1 cấp.
- Tỉ lệ riêng từng trang lưu lại vào HTML khi re-export.
