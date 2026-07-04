# MH_panel — Plan sửa lỗi Tạo Cánh (chọn theo Cạnh / chọn theo Mặt)

Ngày: 2026-06-18. Phạm vi: `MH_panel/src/tools/taocanh.rb` (chính), tham chiếu `MH_panel/src/core/preset.rb`.

## 1. Hiện trạng (vì sao lỗi)

Luồng **chọn theo cạnh** (`edge_pick_mode?`) và **chọn theo mặt** (`face_pick_mode?`):
- `state 0` chọn cạnh/mặt 1 → `state 1` chọn cạnh/mặt 2 → `handle_edge_pick_click` / `handle_face_pick_click`
  build rect rồi nhảy **thẳng `@state = 3`** (bước chia).
- `draw()` (taocanh.rb:553–566): khi `edge/face_pick_mode? && @state < 2` thì **`return` sớm** ⇒
  chỉ vẽ highlight cạnh/mặt, **không vẽ preview cánh** đang hình thành.
- `update_mode_buttons` nhánh `["Cánh trong","Cánh ngoài"]` có điều kiện `!measurement_pick_mode?`
  ⇒ edge/face (và bbox) **không bao giờ hiện** nút Cánh trong/Cánh ngoài, và Tab ở state 3 chỉ đổi Tổng thể/Nội bộ.

> Bounding box đã giải quyết bằng 2 giai đoạn `@batch_stage` (`:inout` → `:divide`). Plan này **tổng quát hoá**
> cơ chế đó cho cả edge/face (cánh đơn), đồng thời thêm **live preview** lúc đang chọn.

## 2. Lỗi cần sửa
- **L1 — Thiếu live highlight:** sau khi chọn cạnh/mặt 1, di chuột tới cạnh/mặt 2 phải hiện **preview cánh** (khối ván) đang hình thành.
- **L2 — Thiếu bước Cánh trong/Cánh ngoài:** sau khi xác định cánh (2 pick), phải vào **giai đoạn chọn in/out**
  (nút + Tab) rồi Enter mới sang bước chia — giống các phương pháp khác và giống bounding box.
- **L3 —** Áp dụng y hệt cho **chọn theo mặt**.

## 3. Giải pháp

### A. Tổng quát hoá giai đoạn 2 bước cho mọi chế độ pick
Đổi/khái quát `@batch_stage` → dùng chung **`@pick_stage`** (`nil | :inout | :divide`) cho bbox + edge + face.
(Có thể giữ tên `@batch_stage` để giảm sửa, nhưng đổi cách set/đọc cho áp dụng cả edge/face.)

Set `@pick_stage = :inout`, `@state = 3` khi geometry đã xác định:
- bbox: `prepare_bounding_box_batch_preview` (đã có).
- edge: `handle_edge_pick_click` nhánh `@state == 1` sau khi `build_rect_from_edge_picks` thành công →
  thay `@state = 3` hiện tại bằng `@state = 3; @pick_stage = :inout` (chưa vào chia).
- face: `handle_face_pick_click` nhánh `@state == 1` tương tự (sau `build_rect_from_face_view_boundary`).

Sửa các điểm điều phối để áp dụng theo `@pick_stage` (không chỉ `batch_preview_active?`):
- **handle_tab** (taocanh.rb ~2373): `@state == 3 && @pick_stage == :inout` → đảo `@dao_chieu`;
  `:divide` (hoặc nil) → `toggle_noi_bo` như cũ.
- **onReturn** (taocanh.rb ~263): `@state == 3 && @pick_stage == :inout` → chuyển `:divide`
  (set `@che_do_chia=:khoang`, `update_mode_buttons/status/invalidate`); `:divide` → tạo thật
  (bbox: `create_bounding_box_batch`; edge/face: `create_rectangle` + `select_tool(nil)`).
- **onCancel** (taocanh.rb ~290): `:divide` → lùi về `:inout` (xoá đường chia: `@diem_chia_*`, `@ds_o`,
  `@o_hover*`, item[:cells] nếu bbox); `:inout` → reset/huỷ preview (bbox xoá `@box_batch_preview` về state 0;
  edge/face → `reset`).
- **update_mode_buttons** (taocanh.rb ~3401): thêm nhánh `@state == 3 && @pick_stage == :inout`
  → `["Cánh trong","Cánh ngoài"]` (active theo `@dao_chieu`, on_click đảo `@dao_chieu`); `:divide` →
  `["Tổng thể","Nội bộ"]` như cũ.
- **update_status** (taocanh.rb ~655): `:inout` → "Nhấn Tab chọn Cánh trong/Cánh ngoài. Enter để chia."
- **Chặn thao tác chia khi `:inout`**: `add_division_point` (click, taocanh.rb ~233 guard đã có cho bbox →
  đổi guard sang `@pick_stage == :inout`), `handle_division_command` (`/x`), và overlay chia.

### B. Live preview khi đang chọn (L1, L3)
Trong `draw()` tại nhánh edge/face khi `@state == 1` (đã có pick1, đang hover pick2):
- Dựng **rect tạm (không mutate `@pts`)** từ `@edge_pick_first + @edge_pick_hover`
  (face: `@face_pick_first + @face_pick_hover`) và vẽ `draw_box(rect, normal, depth, view, faded: true)`
  với `depth = @dao_chieu ? @do_day : -@do_day`.
- Thêm hàm thuần tính điểm, tách từ logic hiện có:
  - `preview_rect_from_edge_picks(first, hover)` ← refactor `build_rect_from_edge_picks` để trả về 4 điểm
    (không gán `@pts`), `build_rect_*` gọi lại nó rồi gán.
  - `preview_rect_from_face_picks(first, hover, view)` ← tương tự từ `build_face_pair_info` +
    `build_rect_from_face_view_boundary`.
- Bỏ `return` sớm ở `@state < 2` **chỉ khi** dựng được rect tạm (vẫn vẽ highlight cạnh/mặt trước đó);
  nếu chưa hover hợp lệ thì giữ hành vi cũ.
- `getExtents`: thêm điểm rect tạm vào bbox để preview không bị cắt (bổ sung trong `when 0/1`).

### C. Preview ở giai đoạn `:inout`
- edge/face ở `state 3 :inout`: `draw_grid_preview` đã vẽ 1 khối cánh; `@dao_chieu` đổi → lật ngay
  (depth động). **Chặn vẽ đường chia** khi `:inout` (không set/không vẽ `@diem_chia_ht`):
  trong `pick_state3` hoặc `draw_grid_preview`/`draw_division_previews` thêm guard `return if @pick_stage == :inout`.

## 4. Điểm cần lưu ý / rủi ro
- `@pick_stage` phải `nil` ở `reset` và sau khi tạo xong (create gọi `reset`).
- Các phương pháp thường (2_diem/3_diem/tự do) **không** dùng `@pick_stage` → giữ nguyên (in/out vẫn ở state 1/2).
- `measurement_pick_mode?` vẫn dùng để phân biệt; chỉ thêm điều phối theo `@pick_stage`.
- Đảm bảo Shift (đảo mặt) vẫn đảo `@dao_chieu` ở cả 2 giai đoạn (đã có ở `onKeyUp` state>2).
- Kiểm tra `getExtents` cho rect tạm + khối preview `:inout` để không bị clip.

## 5. Test (qua VBO SkAgent, dựng obj thử rồi xoá)
1. **edge L1:** chọn cạnh 1 → di chuột tới cạnh 2 ⇒ hiện preview khối cánh (faded) theo cặp cạnh.
2. **edge L2:** click cạnh 2 ⇒ vào `:inout`, nút = Cánh trong/Cánh ngoài, Tab đảo in/out (depth lật);
   Enter ⇒ `:divide`, nút = Tổng thể/Nội bộ, chia bằng chuột/`/x`; Enter ⇒ tạo cánh thật đúng vị trí in/out.
3. **face L3:** lặp lại 1–2 cho chọn theo mặt.
4. **Esc:** `:divide`→`:inout`→huỷ; không sót trạng thái.
5. **Vẽ GL:** chọn tool thật, qua các bước, `get_console_output` không có lỗi mới.
6. **Hồi quy:** 2_diem/3_diem/tự do vẫn hoạt động như cũ (in/out ở state 1/2, chia ở state 3).

## 6. Ngoài phạm vi (chờ xác nhận)
- "Tấm bị lỗi material" (người dùng nhắc rồi ngắt): cần mô tả lại hiện tượng để mở plan riêng.

## 7. Ý kiến bổ sung sau khi đối chiếu code hiện tại

### 7.1. Plan đúng hướng, nhưng cần cập nhật theo thực tế code mới
Trong `MH_panel/src/tools/taocanh.rb` hiện tại đã có:
- `@batch_stage = nil` trong `reset`.
- `@batch_stage = :inout` trong `prepare_bounding_box_batch_preview`.
- Luồng `onReturn`, `onCancel`, `handle_tab`, `update_mode_buttons`, `update_status` đã bắt đầu phân biệt `:inout` / `:divide` cho Bounding Box.

Vì vậy phần plan nói “Bounding box đã giải quyết bằng 2 giai đoạn `@batch_stage`” là đúng, nhưng câu “Đổi/khái quát `@batch_stage` → dùng chung `@pick_stage`” nên cân nhắc lại.

Khuyến nghị của Codex:
- Không đổi tên biến ngay ở bước đầu, vì `@batch_stage` đã được nối vào nhiều điểm.
- Giai đoạn 1 nên giữ `@batch_stage`, nhưng đổi ý nghĩa thành **stage preview/pick chung**, không chỉ riêng batch.
- Nếu muốn tên đẹp hơn, chỉ đổi sau khi test ổn, hoặc tạo helper:
  - `inout_stage?`
  - `divide_stage?`
  - `staged_pick_mode?`

Cách này giảm rủi ro sửa lan và dễ rollback.

### 7.2. Cần tách rõ 3 nhóm mode
Hiện tool có 3 nhóm hành vi khác nhau:

| Nhóm | Mode | Luồng in/out hiện tại |
|---|---|---|
| Vẽ điểm | `2_diem`, `3_diem`, `tu_do` | In/out ở state 1/2 như cũ |
| Pick đo | `chon_theo_canh`, `chon_theo_mat` | Cần thêm `:inout` trước khi chia |
| Batch bbox | `bounding_box` nhiều khối | Đã có `:inout/:divide`, cần giữ ổn định |

Plan nên nhấn mạnh: không ép toàn bộ tool dùng stage mới. Chỉ edge/face/bbox dùng stage 2 bước sau khi đã có hình cánh hoàn chỉnh.

### 7.3. Live preview edge/face nên refactor bằng hàm thuần, tránh mutate `@pts`
Mục B đang đúng. Bổ sung thêm tiêu chí kỹ thuật:
- Hàm preview không được gán `@pts`.
- Không được thay `@source_entity`, `@source_material`, `@do_day` trong lúc hover.
- Chỉ khi click xác nhận pick thứ 2 mới ghi state thật.

Đề xuất tên helper:
```ruby
edge_preview_rect(first, hover)
face_preview_rect(first, hover, view)
apply_pick_rect!(rect, source_context)
```

Lý do: nếu hover làm mutate state, Esc/Tab/VCB rất dễ lệch, nhất là sau các lỗi Bounding Box vừa sửa.

### 7.4. `measurement_pick_mode?` là điểm rủi ro lớn
Plan có nhắc `measurement_pick_mode?`, nhưng nên thêm cảnh báo:

- Hiện `measurement_pick_mode?` gồm edge/face/bbox.
- Nhiều nhánh cũ đang dùng điều kiện `!measurement_pick_mode?` để chặn nút `Cánh trong/Cánh ngoài` và Tab đảo mặt.
- Khi thêm `:inout`, không nên sửa `measurement_pick_mode?` quá rộng.

Khuyến nghị:
- Giữ `measurement_pick_mode?` như hiện tại.
- Thêm helper cụ thể hơn:
```ruby
def pick_inout_stage?
  @state == 3 && @batch_stage == :inout &&
    (edge_pick_mode? || face_pick_mode? || bounding_box_mode?)
end
```

Rồi dùng helper này ở `handle_tab`, `onReturn`, `update_mode_buttons`, `update_status`.

### 7.5. Enter/Esc cần có bảng trạng thái rõ hơn
Nên thêm vào plan bảng state để tránh implement nhầm:

| Tình huống | Enter | Esc |
|---|---|---|
| edge/face đang chọn pick 2 | xác nhận rect, vào `:inout` | quay lại/reset |
| `state 3 + :inout` | sang `:divide`, chưa tạo thật | huỷ preview về state 0 |
| `state 3 + :divide` | tạo cánh thật | lùi về `:inout`, xoá chia |
| bbox batch `:inout` | sang `:divide` | xoá preview batch, về chọn khối |
| bbox batch `:divide` | tạo cánh thật | lùi về `:inout`, giữ cánh ảo |

Điểm quan trọng: Enter ở `:inout` không được tạo cánh thật.

### 7.6. Chia cánh và hover highlight phải dùng cùng nguồn cells
Bài học từ Bounding Box batch: preview hiện nhưng hover highlight có thể mất nếu draw dùng một danh sách cell, còn pick hover dùng danh sách khác.

Khi thêm edge/face stage, nên đảm bảo:
- `draw_grid_preview`
- `detect_hover_cell`
- `add_division_point`
- `handle_division_command`
- `create_rectangle`

cùng đọc từ `@pts + @ds_o + @diem_chia_*`.

Không nên tạo danh sách cell riêng cho edge/face nếu không thật cần.

### 7.7. Material/source context cần được giữ tại thời điểm xác nhận pick
Edge/face pick hiện có rủi ro giống các lỗi material vừa sửa:
- Hover pick thứ 2 có thể ghi đè source/material.
- Nếu rect preview lấy source từ hover thay vì pick đầu, material có thể nhảy.

Bổ sung vào plan:
- Khi click pick 1: lưu context nguồn chính (`@source_entity`, `@source_material`, `@source_material_name`, thickness nếu cần).
- Khi hover pick 2: chỉ tính geometry preview.
- Khi click pick 2: chỉ cập nhật source nếu thật sự muốn theo pick 2; mặc định nên giữ source từ pick 1 để ổn định.

### 7.8. Test cần thêm case material và in/out
Bổ sung test:
1. Edge pick 2 cạnh thuộc 2 vật liệu khác nhau → cánh tạo ra không bị đen, dùng material kỳ vọng.
2. Face pick 2 mặt có `back_material` → cánh vẫn lấy đúng vật liệu.
3. Edge/face vào `:inout`, bấm Tab hoặc nút `Cánh trong/Cánh ngoài` → preview đảo ngay, Enter chưa tạo thật.
4. Edge/face `:divide`, chia `/2`, Enter → tạo đúng số lượng cánh.
5. Esc từ `:divide` về `:inout` vẫn giữ preview cánh, không reset toàn bộ.

### 7.9. Đề xuất thứ tự triển khai
Nên chia thành 3 commit/đợt nhỏ:

1. **Stage control:** mở rộng `@batch_stage`/helper cho edge/face, chưa live preview.
2. **Live preview:** thêm preview hover pick thứ 2 cho edge/face.
3. **Hardening:** getExtents, material/source context, VBO regression tests.

Làm theo thứ tự này dễ phát hiện lỗi hơn là sửa toàn bộ draw/state/material cùng lúc.
