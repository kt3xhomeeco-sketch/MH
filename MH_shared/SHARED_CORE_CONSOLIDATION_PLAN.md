# Kế hoạch: Đưa "lõi xử lí" của WPS / MH_fast_rename / MH_PK_Addon về MH_shared

> Ngày: 2026-06-18 · Phạm vi khảo sát: `E:\code\Sketchup\wps`, `MH_fast_rename`, `MH_PK_Addon`
> Trạng thái: **CHỈ KHẢO SÁT + LÊN KẾ HOẠCH — chưa code**

---

## 0. Trả lời ngắn

**Có** — cả ba app đều có lõi xử lí đáng đưa về `MH_shared`, NHƯNG mức độ khác nhau:

- **WPS**: lõi geometry (Solid boolean, Face, Edge, Offset, Board) **PHẦN LỚN ĐÃ được port** vào
  `MH::Geo::*` (qua MH_panel). Việc cần làm chủ yếu là **đối chiếu parity + dedupe + bổ sung phần thiếu**
  (native offset, vài primitive), KHÔNG phải migrate lại từ đầu.
- **MH_fast_rename**: chứa 2 lõi **CHƯA có trong MH_shared** và giá trị tái dùng rất cao:
  **phát hiện mặt tiếp xúc (contact plane)** và **gom cụm không gian (spatial clustering)**.
- **MH_PK_Addon**: chứa lõi **đo kích thước**, **engine bố trí nhãn/leader (label layout)** và
  **đặt marker tránh chồng (placement)** — đều thuần, tái dùng tốt. Nhưng phần
  **product detection / chuẩn hóa text / lịch sử rename** thì **TRÙNG** với API shared đã có
  → hội tụ (converge) chứ không migrate.

Tóm lại: nên tạo thêm vài module trong `MH_shared` (Contact, Cluster, Split, Measure, LabelLayout,
Placement, Poly2D) và **gỡ trùng** các app về dùng chung.

---

## 1. Hiện trạng MH_shared (đã có)

`MH::Geo::{BoardAnalyzer, BoardBuilder, Face, Edge, Offset, Solid, Box, Util, Const}`,
`MH::{TraverseModel, ModelReader, Registry, NameGrammar, ProductContext, ModelHub,
OverlayEngine, Bounds, Text, Settings, Memo}`.

→ Đã có: boolean solid, offset (kèm tìm concave vertex), phân tích/dựng tấm ván, duyệt model,
parse tên SP (NameGrammar), so khớp product (ProductContext), chuẩn hóa tiếng Việt (Text),
HUD primitives (OverlayEngine), cache bounds (Bounds).

---

## 2. Lõi nên ĐƯA VỀ MH_shared (mới) — theo nguồn

### Từ MH_fast_rename (ưu tiên CAO — chưa có trong shared)

| Module đề xuất | Hàm nguồn (file:line) | Input→Output | Vì sao thuần/tái dùng |
|---|---|---|---|
| **MH::Geo::Contact** | `cp_faces_contact?` (main.rb:389), `cp_find_separators` (615), `cp_separator_score` (489), `cp_plane_cuts?` (440), `get_faces_world` (296) | cặp khối → mặt tiếp xúc / mặt phân tách | Chỉ phụ thuộc Geom API; 0 dính UI/naming |
| **MH::Geo::Poly2D** | `cp_poly_intersect` Sutherland–Hodgman (378), `cp_project_pts` (341) | 2 polygon 2D → giao; 3D→2D project | Primitive dùng chung cho Contact + PK overlap |
| **MH::Geo::Cluster** | `cluster_entities` grid+UnionFind (1168), `auto_gap_threshold` NN-jump (1130), `bb_distance_raw` (1122), `UnionFind` (949) | entities → các cụm gần nhau | Toán thuần, O(n log n), không dính app |
| **MH::Geo::Split** | `split_entities_into_groups` (701), `cp_split_group` (680) | entities + planes → nhóm con | Hierarchical split theo mặt phẳng |

### Từ MH_PK_Addon (ưu tiên CAO–TRUNG)

| Module đề xuất | Hàm nguồn (file:line) | Input→Output | Ghi chú |
|---|---|---|---|
| **MH::Measure** | `target_longest_dimension_mm` (length_pk.rb:10), `excel_row_length_mm` (76) | group/row → mm | Đo kích thước lớn nhất + gộp nhiều item |
| **MH::LabelLayout** | `spatial_clusters`/`name_clusters` (leaders.rb:264), `layout_labels`/`stack_column` (363), `wrap_label_lines` (429), `onscreen_markers` cull (239) | markers + viewport → vị trí nhãn không chồng | Engine 2D thuần; ghép với `OverlayEngine` |
| **MH::Geo::Placement** | `face_transform` (core.rb:336), `placement_face`/`largest_face` (324/330), `free_marker_transform` grid (413), `face_local_bounds`/`occupied_rects` (363/395) | face/entities → transform đặt vật tránh chồng | Hệ trục mặt + grid collision |
| **MH::Geo::FaceQuery** | `face_cycle` (picker.rb:73), `projected_overlap?` (121), `face_screen_rect_on_plane` (139) | face → các mặt song song/đối + test phủ | Dùng chung với Contact/Poly2D |

### Từ WPS (ưu tiên THẤP — phần lớn đã có)

| Việc | Nguồn | Ghi chú |
|---|---|---|
| Đối chiếu parity `MH::Geo::*` vs `wps utils/*` | `utils/wps_{solid,face,edge,offset,board}.rb` | Xác nhận bản port đầy đủ, gỡ bản cũ trong WPS/MH_panel |
| (Tùy chọn) Tầng tăng tốc native | `native/wps_bridge.rb` + `wps_native.dll` (`offset_polygon`, `find_concave_vertices`) | Bọc làm fast-path cho `MH::Geo::Offset`; **rủi ro**: chỉ Windows, binding Fiddle/JSON, phải bảo trì DLL |
| Primitive còn thiếu | `Method.build_arc_points` (wps_method.rb:11), `point_to_segment_distance` (29), `segments_intersect?` (41) | Bổ sung vào `MH::Geo::Util` nếu chưa có |

---

## 3. KHÔNG migrate — HỘI TỤ về API đã có (tránh đẻ trùng)

| Lõi trong app | Đã có sẵn trong shared → dùng cái này | Hành động |
|---|---|---|
| PK `detect_product_code`, `product_code_base/match?` | **MH::ProductContext** | Thay lời gọi, bỏ bản PK |
| PK `search_text` (bỏ dấu tiếng Việt) | **MH::Text.fold/slug/upper_no_accent** | Thay, bỏ bản PK |
| fast_rename `sort_and_label_zones`, `SP_REGEX`, extract label | **MH::NameGrammar** (parse SP) | Tách phần parse → NameGrammar; giữ phần "locked/renumber" ở app |
| fast_rename `content_bounds` | đã gọi **MH::Bounds.content_bounds** (tốt) | Giữ nguyên |
| PK `entity_world_transform`, `collect_markers` (tree walk) | **MH::Geo::Util** / **MH::TraverseModel** | Gộp về Util/TraverseModel |

---

## 4. App nào được hưởng lợi (beneficiary matrix)

| Module shared (mới) | App hưởng lợi & lý do |
|---|---|
| **Geo::Contact + Split + Cluster** | **MH_assemble** (dựng cây Tủ→Module→Part chính là cluster+split), **MH_Thongke** (gom cấu kiện cho BOQ, đếm cặp tiếp xúc), **MH_fast_rename** (giữ lõi của chính nó), **MH_SelectSimilar** (gom theo cụm), **MH_panel** |
| **Measure** | **MH_Thongke** (chiều dài BOQ), **MH_assemble**/**MH Drawer** (kích thước part), **MH_PK_Addon** |
| **LabelLayout** | **MH_Name** + **MH_Rename** (nhãn viewport + leader, tránh chồng), **MH_PK_Addon**, **MH_assemble** (annotation) — hiện mỗi app tự vẽ nhãn riêng |
| **Geo::Placement + FaceQuery** | **MH_Superimp** (pick mặt, cycle mặt), **MH_PK_Addon**, **MH_fix-nesting**, tool đặt marker/nhãn lên mặt |
| **Poly2D** | nền cho Contact + FaceQuery + bất kỳ test phủ 2D |

---

## 5. Lộ trình triển khai (phân pha)

**Pha 0 — Chuẩn bị (không rủi ro)**
- Khóa API mục tiêu cho từng module mới (tên hàm, input/output, đơn vị mm vs inch).
- Viết bộ test vàng (golden) chụp output hiện tại của fast_rename (contact/cluster) và PK (measure/layout)
  trên 2–3 model thật để so sánh trước/sau khi tách.

**Pha 1 — Tách lõi THUẦN, ít rủi ro nhất (giá trị cao)**
1. `MH::Geo::Poly2D` (clipping + project) — nền cho các module sau.
2. `MH::Geo::Contact` + `MH::Geo::Cluster` + `MH::Geo::Split` (từ fast_rename), giữ const TOL ở `Geo::Const`.
3. `MH::Measure` (từ PK).
- Sau mỗi module: cho **app nguồn gọi lại module shared** (không đổi hành vi), chạy golden test.

**Pha 2 — Hội tụ phần TRÙNG**
- PK product/search/text → ProductContext/Text. fast_rename parse SP → NameGrammar.
- Gỡ code trùng trong app sau khi golden test xanh.

**Pha 3 — Module có yếu tố UI tách được**
- `MH::LabelLayout` (PK leaders) + `MH::Geo::Placement` + `Geo::FaceQuery`.
- Ghép `LabelLayout` với `OverlayEngine`; chuyển MH_Name/MH_Rename sang dùng.

**Pha 4 — WPS parity + native (tùy chọn)**
- Đối chiếu `MH::Geo::*` với `wps utils/*`, bổ sung primitive thiếu, gỡ bản cũ.
- Cân nhắc tầng native DLL cho Offset (chỉ nếu cần hiệu năng; chấp nhận rủi ro Windows-only).

---

## 6. Giữ NGUYÊN trong app (không đưa về shared)

- Toàn bộ `tool.rb` (vòng lặp tương tác chuột/phím), state `@p1/@locked/@mode/cache`.
- Render HUD cụ thể (`hud.rb`, `visibility_lab.rb`) — chỉ logic layout mới đưa ra `LabelLayout`.
- `traceability.rb` (PK) — dính chặt MH_Thongke API, đặc thù nghiệp vụ, giá trị reuse thấp.
- Zone "locked/renumber policy" (fast_rename) — chính sách nghiệp vụ, giữ ở app; chỉ tách phần parse.

## 7. Rủi ro & lưu ý

- **Đơn vị**: WPS/fast_rename/PK trộn inch (Geom) và mm. API shared phải quy ước rõ (đề xuất: nội bộ
  dùng inch như Geom, hàm `*_mm` chỉ ở biên).
- **Tolerance**: contact dùng `0.05mm`; cluster dùng gap tự suy. Đưa thành tham số có default ở `Geo::Const`,
  không hardcode rải rác.
- **Hồi quy**: contact/cluster nhạy với heuristic → bắt buộc golden test trước/sau.
- **Tránh "migrate trùng"**: kiểm tra `MH::Geo` trước khi thêm (Solid/Offset/Face đã có) để không tạo bản thứ hai.
- **Native DLL**: tăng phụ thuộc & bảo trì; chỉ làm khi đo được nút cổ chai thực sự.

---

# PHẦN B — Chiến lược: có nên đưa HOÀN TOÀN lõi WPS sang MH_shared? (bổ sung 18/06/2026)

## B.0 Trả lời ngắn

> ⚠️ NGUYÊN TẮC NỀN (đọc trước): MH_shared là **phần HỢP (superset), CỘNG THÊM (additive)** — KHÔNG
> phải thay thế. **Giữ NGUYÊN** lõi `MH::Geo` hiện có + lõi của các app MH (Contact/Cluster/Split,
> Measure/LabelLayout/Placement — xem Phần A). WPS chỉ là **một nguồn đóng góp**: ta **chỉ lấy thêm
> phần CÒN THIẾU của WPS** vào shared, tuyệt đối không chép đè / không bỏ lõi MH để "lấy nguyên WPS".

**Nên — nhưng đưa "lõi" (geometry + support layer), KHÔNG đưa "tool".** Và làm theo kiểu
**hợp nhất 1 nguồn duy nhất ngay + lấp khe theo nhu cầu (just-in-time)**, chứ không bê nguyên 16
tool sang một lần. "Hoàn toàn lõi" ở đây nghĩa là **gom đủ lớp geometry+support về 1 chỗ (gồm cả lõi
MH lẫn phần thiếu của WPS)**, KHÔNG có nghĩa thay lõi MH bằng lõi WPS.

Lý do cốt lõi: 16 tool của WPS đều đứng trên CÙNG một nền geometry (Solid/Face/Edge/Offset/Board/
Group/Material). Nếu mỗi lần clone thêm 1 tool lại mang theo bản geometry riêng (đúng như MH_panel
đang làm), bạn sẽ **port đi port lại cùng một lõi** → càng phát triển càng nhiều bản trùng. Đưa lõi
về 1 chỗ thì mỗi tool mới chỉ còn việc "viết UI + gọi MH::Geo".

## B.1 Hiện trạng: ĐANG CÓ 3 BẢN LÕI (nguy cơ phân kỳ)

1. **WPS gốc** (`E:\code\Sketchup\wps`) — đầy đủ 16 tool + lõi.
2. **MH_panel/src/core/** — bản copy gần đủ lõi: `board, group, material, abf, isolate, model, view,
   purge, preset` (+ các file `solid/edge/offset/face/offset_helpers.rb` **đã CŨ, không còn nạp**
   trong `main.rb require_core` — panel đã chuyển sang `MH::Geo` qua `geo_adapter.rb`).
3. **MH_shared/geometry/** (`MH::Geo`) — đã phủ **~82%** lõi geometry thuần (Solid 100%, Edge ~100%,
   Face ~95%, Offset ~88%, Axes 100%, Board ~62%, Util ~70%; **thiếu**: component↔group convert,
   board rebuild / get_band / tìm ván gần nhất, material/texture, một số ABF).

→ MH::Geo đã **lệch** khỏi WPS ở vài hàm (`Offset.faces` rút gọn, `Edge.weld`/`Face.unwrap` đổi sang
inject `entities` thay cho `WPS.start/commit`). Nếu để WPS và MH_shared cùng "sống" song song, hai
bên sẽ trôi xa nhau.

## B.2 Khuyến nghị (hybrid, đúng mục tiêu "sau này đủ tính năng như WPS")

**(a) Chốt MH_shared là NGUỒN DUY NHẤT (single source of truth) cho lõi.** Coi WPS là bản tham chiếu
"đóng băng", không bảo trì song song. Mọi hàm geometry sau này port từ WPS đều **đi thẳng vào
MH_shared**, không vào app.

**(b) NGAY BÂY GIỜ — gỡ trùng + lấp khe "mặt bằng chung" (rẻ, vì mới có 2 tool):**
- Xoá các file lõi cũ không dùng trong `MH_panel/src/core/` (`solid/edge/offset/face/offset_helpers.rb`)
  để tránh nhập nhằng khi `reload` nạp toàn bộ.
- Chuyển nốt `board, group, material, abf` của MH_panel **lên MH_shared** (board: thêm `rebuild`,
  `tim_van_gan_nhat`, `get_band_faces`; group: `component_to_group`, `copy_attributes/behavior`;
  material/abf: tách thành `MH::Geo::Material` / `MH::ABF` dùng chung — nhiều app MH đụng ABF).
- Để MH_panel chỉ còn `tools/` + `settings/preset/isolate/view` (phần đặc thư app).

**(c) GIỮ NGUYÊN ở app (không bao giờ shared):** toàn bộ logic tool 16 món (mộng, nối ván, bo góc,
đục khung, âm dương...) — đó là UI/interaction + heuristic riêng. Shared chỉ chứa hàm tính toán mà
tool gọi.

**(d) LẤP KHE THEO NHU CẦU:** đừng port sẵn geometry của cả 14 tool còn lại "phòng xa". Khi clone tool
nào thì port đúng các hàm lõi tool đó cần — nhưng đặt vào MH_shared. Tránh ôm code chết.

## B.3 Vì sao KHÔNG "bê hoàn toàn 16 tool" một lần
- ~10K dòng tool là UI/heuristic, reuse gần như bằng 0 → vào shared chỉ làm phình & khó bảo trì.
- Nhiều tool dùng `WPS::Material/ABF/Native` theo cách riêng → port ồ ạt kéo theo cả lớp phụ thuộc chưa
  cần. Port theo nhu cầu an toàn hơn.
- Rủi ro hồi quy: mỗi hàm lõi đưa sang phải có golden test; bê 16 tool một lần là không kiểm soát nổi.

## B.4 Kết luận cho quyết định
- MH_shared = **superset**: giữ nguyên lõi MH::Geo + lõi các app MH (Phần A) **CỘNG** phần còn thiếu
  của WPS. Không thay thế, không bỏ lõi MH.
- "Đưa hoàn toàn lõi sang shared" = **gom đủ lớp GEOMETRY + SUPPORT (board/group/material/abf) về một
  chỗ** và **xoá bản trùng ở MH_panel** → ĐÚNG và NÊN, vì đúng nghĩa "tiện nâng cấp sau". WPS chỉ đóng
  góp phần thiếu.
- "Đưa hoàn toàn TOOL sang shared" = **KHÔNG** — tool ở lại app.
- Việc cần làm sớm nhất (rẻ, lợi ngay): hợp nhất 3 bản lõi thành 1, chốt single source, đặt luật
  "mọi hàm geometry mới (dù từ WPS hay app MH) → vào MH_shared".

---

## 8. Ý kiến rà soát thêm trước khi code

### 8.1 Chốt "module boundary" theo 3 tầng, tránh shared bị phình

Kế hoạch hiện đúng hướng, nhưng nên khóa ranh giới rõ hơn trước khi tách code:

1. **Pure geometry / pure algorithm**: không sửa model, không gọi `start_operation`, càng ít phụ thuộc
   `Sketchup.active_model` càng tốt. Ví dụ: `Poly2D`, scoring plane, overlap rect, label stacking.
2. **SketchUp query**: đọc entity/bounds/face/world transform, có thể phụ thuộc `Sketchup::Face`,
   `Sketchup::Group`, `InstancePath`, nhưng không mutate model. Ví dụ: `Contact.extract_faces_world`,
   `FaceQuery`, `Measure`.
3. **SketchUp mutation**: tạo group, pushpull, convert component→group, gán material, đặt marker.
   Những hàm này nên đặt tên rõ kiểu `build_*`, `apply_*`, `create_*`, `convert_*` và ghi rõ bên gọi
   chịu trách nhiệm mở undo operation.

Điểm quan trọng: **shared mutator không nên tự `start_operation` mặc định**, vì app/tool bên ngoài
thường đã có operation tổng. Nếu cần tiện dụng, tạo wrapper riêng kiểu `with_operation: true`, mặc định
`false`, để tránh lỗi nested operation.

### 8.2 Loader của `MH_shared.rb` cần đổi trước khi thêm module phụ thuộc nhau

Hiện `MH_shared.rb` đang nạp `geometry/*.rb` bằng `Dir.glob(...).sort`. Cách này ổn khi module ít phụ
thuộc, nhưng sẽ dễ lỗi khi thêm chuỗi:

`Poly2D` → `Contact` / `FaceQuery` → `Placement` / `Split`

Khuyến nghị trước khi port:

- Chuyển sang **require tường minh theo thứ tự** trong `MH_shared.rb`, ít nhất cho nhóm geometry mới.
- Hoặc thêm `MH_shared/geometry/loader.rb` có mảng thứ tự canonical.
- Không dựa vào tên file alphabet để quyết định dependency. Nếu muốn giữ sort, đặt prefix số cũng được
  nhưng kém sạch hơn.

### 8.3 Chốt nguồn canonical cho fast_rename contact/split

`MH_fast_rename/main.rb` đang có bộ `cp_*` dùng trực tiếp cho split/cluster; đồng thời
`MH_fast_rename/contact_planes_v5.rb` có luồng contact-plane độc lập/tiền thân với tên hàm gần giống
(`faces_contact?`, `plane_cuts_obj?`, `find_all_separators`, `split_by_plane`).

Trước khi port cần làm 1 bước nhỏ:

- Xem `main.rb` là **nguồn runtime canonical** nếu tool hiện đang dùng nó.
- Dùng `contact_planes_v5.rb` làm **nguồn tham chiếu thuật toán / test case**, không copy song song.
- Ghi bảng mapping tên hàm cũ → module mới, ví dụ:
  - `cp_project_pts` / `project_pts_onto_plane` → `MH::Geo::Poly2D.project_points`
  - `cp_poly_intersect` → `MH::Geo::Poly2D.intersection`
  - `cp_faces_contact?` / `faces_contact?` → `MH::Geo::Contact.faces_contact?`
  - `cp_find_separators` → `MH::Geo::Contact.find_separators`
  - `cp_split_group` / `split_entities_into_groups` → `MH::Geo::Split.*`

Lý do: nếu copy cả hai luồng vào shared thì rất nhanh thành hai bản contact/split khác nhau ngay trong
chính `MH_shared`.

### 8.4 API cần nhận `InstancePath`/transform rõ ràng, không chỉ nhận entity trần

Các bài toán contact, measure, placement rất dễ sai khi gặp:

- component/group lồng nhiều cấp;
- instance scale/mirror;
- definition dùng chung nhiều instance;
- entity hidden/locked/tag ẩn;
- đối tượng ABF hoặc subtree muốn loại khỏi split.

Vì vậy API mới nên tránh kiểu mơ hồ `faces_for(entity)` nếu chưa biết transform. Đề xuất:

- Hàm query world-space nhận `entity` kèm `transform:` hoặc `path:`.
- Kết quả mặt nên trả về struct/hash ổn định: `{ face:, pts:, normal:, plane_d:, transform:, source: }`.
- Các hàm cluster/split nên nhận option `reject:` hoặc `include_hidden:` thay vì hardcode luật
  fast_rename.
- Các chính sách nghiệp vụ như "bỏ ABF", "modul contact keyword", "SP base only" để ở app, truyền vào
  shared qua callback/options.

### 8.5 Golden test nên là "behavior snapshot", không chỉ test hàm đơn lẻ

Mục Pha 0 đã đúng, nhưng nên cụ thể hóa bộ test tối thiểu:

- **Contact/Split**: với 2–3 model thật, snapshot số cụm, số separator, normal+d của plane, membership
  entity theo persistent_id/name. Cho phép tolerance số học, nhưng không cho phép đổi grouping âm thầm.
- **Cluster**: snapshot threshold tự suy, số cụm, kích thước từng cụm, thứ tự label nếu có.
- **Measure**: snapshot kích thước theo inch nội bộ và mm xuất ra, test cả scale/mirror.
- **LabelLayout**: snapshot rect màn hình, leader start/end, số label bị cull; thêm ảnh viewport nếu cần
  kiểm tra bằng mắt.
- **WPS parity**: test cặp input/output cho `Offset`, `BoardBuilder`, `BoardAnalyzer` trước khi xóa lõi
  cũ ở `MH_panel`.

Nên lưu output dạng JSON deterministic, có `schema_version`, để sau này đổi thuật toán còn biết đổi vì
cố ý hay do hồi quy.

### 8.6 Cần thêm tiêu chí hiệu năng, vì contact/cluster có nguy cơ O(n²)

`cp_faces_contact?`, separator scan và clustering có thể tăng rất nhanh khi model lớn. Khi port sang
shared nên đo baseline trước/sau:

- số entity / số face / số pair kiểm tra;
- thời gian extract faces, contact scan, split, cluster;
- cache hit/miss cho bounds và face world;
- ngưỡng "bật spatial index/grid" thay vì so mọi cặp.

Đề xuất: `MH::Geo::Cluster` có grid index dùng chung; `MH::Geo::Contact` cũng nên tận dụng broad-phase
bằng bounds/axis plane trước khi test polygon overlap.

### 8.7 `ABF` và `Material` là support layer, không hẳn là `Geo`

Phần B nói chuyển `material/abf` lên shared là hợp lý, nhưng namespace nên cân nhắc:

- `MH::Geo::Material` chỉ nên chứa helper hình học/vật liệu rất sát geometry, ví dụ đọc texture scale,
  sample material từ face.
- Logic ABF có vẻ là nghiệp vụ ngành mộc/phụ kiện hơn là geometry thuần, nên ưu tiên `MH::ABF` hoặc
  `MH::Cabinet::ABF`, không nhét vào `MH::Geo`.
- Nếu ABF đang dùng nhiều app, tạo facade nhỏ trước, rồi mới rút dần implementation khỏi `MH_panel`.

Nói ngắn: **shared được, nhưng đừng ép mọi thứ vào `Geo`**.

### 8.8 Migration nên có facade tương thích trong app nguồn

Khi tách lõi, không nên sửa app nguồn gọi API mới toàn bộ trong một commit lớn. Mẫu an toàn:

1. Port module mới vào `MH_shared`.
2. Trong app nguồn, giữ tên hàm cũ nhưng đổi thân hàm thành wrapper gọi shared.
3. Chạy golden test.
4. Sau khi ổn mới thay caller sang API mới và xóa wrapper.

Ví dụ `MH_fast_rename.cp_poly_intersect` có thể tạm gọi `MH::Geo::Poly2D.intersection`. Cách này làm
diff nhỏ, dễ rollback, và không ép sửa toàn bộ tool trong một lần.

### 8.9 Thêm version/changelog cho `MH_shared`

`MH::Shared::VERSION` hiện đang là `1.0.0`. Khi thêm các module lõi lớn, nên:

- bump version theo từng pha (`1.1.0` cho Poly2D/Contact/Cluster/Measure chẳng hạn);
- thêm `MH_shared/CHANGELOG.md`;
- ghi "API ổn định" và "API nội bộ/experimental";
- app phụ thuộc có thể check version tối thiểu để báo lỗi rõ ràng thay vì fail lửng.

### 8.10 Thứ tự ưu tiên đề xuất sau khi rà soát

Nếu phải chọn đường ít rủi ro nhất, tôi sẽ làm theo thứ tự:

1. **Loader + versioning + test harness** cho `MH_shared`.
2. **Poly2D** vì nhỏ, ít phụ thuộc, là nền chung.
3. **Measure** vì giá trị cao và ít mutate model.
4. **Cluster** với cache/bounds rõ ràng.
5. **Contact + Split** sau khi đã có Poly2D và test snapshot.
6. **Board/Group/Material/ABF từ MH_panel/WPS** theo nhu cầu thật của tool.
7. **LabelLayout/Placement/FaceQuery** sau cùng, vì liên quan viewport và policy tránh chồng nhiều hơn.

Lý do đổi nhẹ so với Pha 1 ban đầu: `Measure` dễ tách sạch hơn `Contact/Split`, nên làm sớm để có một
module shared thành công nhanh; `Contact/Split` để sau khi test harness đủ chặt.

---

## 9. File nguồn tham chiếu
- WPS: `E:\code\Sketchup\wps\utils\wps_{solid,face,edge,offset,board}.rb`, `wps_method.rb`, `native/wps_bridge.rb`
- fast_rename: `MH_fast_rename\main.rb` (contact ~296–700, cluster ~949–1190, label ~1382–1450), `zone.rb`, `contact_planes_v5.rb`
- PK: `MH_PK_Addon\core.rb` (~188–460, ~1078–1462), `length_pk.rb`, `leaders.rb`, `picker.rb`
- shared: `MH_shared\geometry\*.rb`, `MH_shared\{name_grammar,product_context,text,traverse_model,overlay_engine,bounds}.rb`
