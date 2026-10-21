# BUG: Naming DC làm sinh thêm DC "độ dày cũ" khi DC có thuộc tính `copies`

> Ngày: 2026-06-18 · Phạm vi: `MH_Registry/connectors/dc_import/*` (luồng `after_import_dc` của Superimp)
> Trạng thái: **ĐÃ SỬA & TEST OK** (hướng: bỏ hẳn ghi tên động vào DC)

## ✅ Đã triển khai (2026-06-18)

Quyết định: **bỏ hẳn việc truyền tên động vào DC**. Thêm guard
`write_dc_dynamic_names?` (= `false`) trong [naming.rb](connectors/dc_import/naming.rb):

- `cleanup_outer_instance_name` → return sớm, không ghi `entity.name` / `dynamic_attributes
  name/_name_formula/_name_error` lên instance.
- `apply_inner_group_naming` → vẫn ghi attribute `MH_Registry` (metadata sidecar, an toàn)
  nhưng **bỏ `set_entity_dynamic_name`** lên group con.
- Bật lại tên động (nếu sau này cần): đổi `write_dc_dynamic_names?` trả `true` —
  nhưng khi đó bug copies sẽ quay lại.

**Test tái hiện có kiểm soát (đã chạy live, đã dọn sạch):** import `Chân Bệ` (có `_copies`)
+ ngữ cảnh `SP01`, redraw 2 lần → vẫn **đúng 1 bộ copy** (10 con / 5 copy), không sinh bộ copy
thứ hai; `instance dynamic name = nil`, group copy-master `name = nil`; `MH_Registry dc_full_name
= "SP01"`, `dc_product_code = "SP01"` vẫn giữ. Model về đúng 60 định nghĩa, không rác.

### Đánh đổi đã chấp nhận
- BOM/Thống kê đọc tên part từ `entity.name` ([model_scanner.rb:103](../MH_Thongke/engine/model_scanner.rb:103))
  → part trong DC sẽ hiển thị tên gốc của template (không còn tiền tố `SPxx`). Dữ liệu sản
  phẩm/module vẫn nằm ở attribute `MH_Registry` nếu cần dùng lại.

### Còn lại (tuỳ chọn)
- [ ] Hàm repair dọn các DC đã bị nhiễm sẵn (`Chân Bệ#1..#5` + bộ copy kép cũ) trong model
      hiện hành: xoá group copy thừa rồi `purge_unused`. (Fix mới chỉ chặn phát sinh MỚI.)

---

## Phụ lục — chẩn đoán gốc

---

## 1. Triệu chứng (theo người dùng)

- DC được import/swap qua **MH_Superimp** dùng tính năng **copies** (att copy) thì **bị lỗi**:
  sinh ra **nhiều DC/định nghĩa con với độ dày CŨ** còn sót lại.
- **Có gán mã SP** (vd `SP01`) → **bị lỗi**.
- **Không gán mã SP** → **không lỗi**.
- Người dùng kết luận: lỗi đến từ việc **đặt tên instance + tên group** khi đưa vào.
  DC không truyền tên thì không lỗi. ✅ (Chẩn đoán xác nhận đúng.)

## 2. Bằng chứng thu được từ model live

Model hiện có 6 định nghĩa cùng gốc tên `Chân Bệ`:

```
Chân Bệ      used=0   (gốc, orphan)
Chân Bệ#1    used=1   a5dodayvan=0.7874in (20.0mm)
Chân Bệ#2    used=1   a5dodayvan=0.73228in (18.6mm)
Chân Bệ#3    used=1   18.6mm   ← KHÔNG có dc_product_code (không SP)
Chân Bệ#4    used=1   17.6mm
Chân Bệ#5    used=1   18.6mm   ← CÓ dc_product_code="SP01", tên SP01.2
```

Soi cây con của `Chân Bệ#5` (bản có mã SP):

```
child[2]  Group copies=4.0  da_name="SP01.2_chân phụ"   ruby="SP01.2_chân phụ"   ← COPY MASTER
child[6]  Group copies=4.0  da_name=...                 ruby="SP01.2_chan_doc copy 001"  ┐
child[7]  Group copies=4.0                              ruby="SP01.2_chan_doc copy 002"  │ bộ copy CŨ
child[8]  Group copies=4.0                              ruby="SP01.2_chan_doc copy 003"  │ còn sót
child[9]  Group copies=4.0                              ruby="SP01.2_chan_doc copy 004"  ┘ (độ dày cũ)
child[10] Group copies=4.0  da_name="SP01.2_chân phụ"   ruby="chan_doc copy 001"  ┐
child[11] Group copies=4.0  da_name="SP01.2_chân phụ"   ruby="chan_doc copy 002"  │ bộ copy MỚI
child[12] Group copies=4.0  da_name="SP01.2_chân phụ"   ruby="chan_doc copy 003"  │ do engine sinh
child[13] Group copies=4.0  da_name="SP01.2_chân phụ"   ruby="chan_doc copy 004"  ┘
```

→ Có **2 bộ copy cùng tồn tại** trong 1 definition. Đây chính là "nhiều DC độ dày cũ".

## 3. Nguyên nhân gốc (root cause)

DC `Chân Bệ` có group con mang `_copies=4` (vd "chân phụ"). SketchUp DC engine **tự sinh
các bản copy tạm** mỗi lần redraw, đặt tên kiểu `"<tên> copy 00N"`, và **tự quản lý/tái tạo
chúng** dựa trên tên + `_name_formula`.

Khi có **mã SP**, `after_import_dc` gọi `apply_dc_naming`:

- `apply_inner_group_naming` ([naming.rb:259](connectors/dc_import/naming.rb:259)) duyệt **TẤT CẢ**
  container con qua `visible_child_containers` → `walk_child_containers`
  ([traversal.rb:14](connectors/dc_import/traversal.rb:14), [:22](connectors/dc_import/traversal.rb:22))
  — **đệ quy vào cả cây copies**.
- Với mỗi group (kể cả **copy master** lẫn **các bản copy do engine sinh**), gọi
  `set_entity_dynamic_name` ([naming.rb:319](connectors/dc_import/naming.rb:319)) ghi đè:
  - `entity.name` (tên ruby)
  - `dynamic_attributes 'name'`
  - **`dynamic_attributes '_name_formula'`**  ← điểm chết người
  - `dynamic_attributes '_name_error'`

Hậu quả: các bản copy tạm bị **đóng băng tên + `_name_formula`** thành `"SP01.2_chân phụ"`.
Lần redraw kế tiếp, DC engine **không còn nhận ra chúng là copy tạm của master** (định danh/tên
đã đổi) → **không tái dùng/không xoá** chúng → giữ nguyên bộ cũ (kèm **độ dày cũ**) **và sinh
thêm bộ copy mới**. Mỗi lần thao tác lại → tích lũy thêm, đồng thời instance bị `make_unique`
liên tục → đẻ ra `Chân Bệ#1..#5`.

**Không gán mã SP** → `resolve_dc_naming` trả `{}` (product rỗng,
[naming.rb:18](connectors/dc_import/naming.rb:18)) → `apply_dc_naming` không chạy → copy groups
giữ tên tự nhiên `"... copy 00N"` → engine quản lý copy đúng → **không lỗi**.

### Yếu tố phụ làm nặng thêm
- Thứ tự trong `after_import_dc` ([dc_import_pipeline.rb:38-46](connectors/dc_import_pipeline.rb:38)):
  **naming chạy TRƯỚC `apply_profile` (độ dày)**, và `apply_dc_naming` tự mở/commit operation
  riêng → bộ copy bị đóng băng ở **độ dày cũ** trước khi thickness mới được ghi.

## 4. Hướng sửa

### Fix chính (bắt buộc) — KHÔNG đổi tên trong cây `copies`
Trong `apply_inner_group_naming` / `walk_child_containers`, **bỏ qua mọi entity thuộc nhánh copies**:

- Bỏ qua entity có thuộc tính `copies`/`_copies` (là copy master), **và**
- Bỏ qua mọi **con cháu** của một entity có `copies` (các bản copy sinh ra), **và**
- Bỏ qua entity có tên dạng `/ copy \d+\s*$/` (bản copy do engine tạo).

Cụ thể: thêm guard trong `walk_child_containers` để **không đệ quy** vào group có `_copies`,
và trong vòng lặp `apply_inner_group_naming` ([naming.rb:265](connectors/dc_import/naming.rb:265))
`next` nếu group nằm trong nhánh copies.

### Fix cho `set_entity_dynamic_name` (phòng thủ tầng 2)
[naming.rb:319](connectors/dc_import/naming.rb:319): **không ghi `_name_formula`** (và `_name_error`)
cho group có `_copies` hoặc là bản copy — chỉ đặt `entity.name` thuần (nếu thật sự cần), tránh
chạm `dynamic_attributes` của cây copies.

### Fix thứ tự (khuyến nghị)
Đảo `apply_profile` (độ dày) **trước** `apply_dc_naming`, hoặc gộp cả naming + thickness vào
**một operation + một lần `redraw_with_undo`** để chỉ `make_unique` đúng 1 lần với độ dày mới.

### Tiện ích dọn dẹp (tuỳ chọn)
Viết hàm repair: trong mỗi definition, **xoá các group copy thừa** (giữ lại copy master + đúng N
bản theo `_copies`), rồi `model.definitions.purge_unused` để gộp/loại bỏ `Chân Bệ#1..#5` và các
`Group#NNN` orphan (hiện có 5 orphan group + 1 orphan `Chân Bệ`).

## 5. Việc cần làm (checklist)
- [ ] Thêm helper `in_copies_subtree?(entity)` / `is_generated_copy?(entity)` trong `traversal.rb`.
- [ ] Sửa `walk_child_containers` + `apply_inner_group_naming` để bỏ qua nhánh copies.
- [ ] Thêm guard copies trong `set_entity_dynamic_name`.
- [ ] (Khuyến nghị) Gộp naming + thickness vào 1 operation/redraw, hoặc đặt thickness trước.
- [ ] Viết hàm repair + nút "Dọn copy thừa" (tuỳ chọn).
- [ ] **Test**: import DC `Chân Bệ` có mã SP → chỉ 1 definition, 1 bộ copy đúng N bản, đúng độ dày mới.
- [ ] **Test**: DC không mã SP vẫn hoạt động như cũ.
- [ ] **Test**: swap độ dày nhiều lần liên tiếp → không tích lũy copy/định nghĩa thừa.

## 6. File liên quan
- [connectors/dc_import/naming.rb](connectors/dc_import/naming.rb) — `apply_inner_group_naming`, `set_entity_dynamic_name` (thủ phạm chính)
- [connectors/dc_import/traversal.rb](connectors/dc_import/traversal.rb) — `walk_child_containers` (đệ quy vào copies)
- [connectors/dc_import_pipeline.rb](connectors/dc_import_pipeline.rb) — `after_import_dc` (thứ tự naming vs thickness)
- [connectors/dc_import/dc_attrs.rb](connectors/dc_import/dc_attrs.rb) — ghi thickness + `redraw_dc`
