# MH_Thongke - Tài liệu chức năng và Skills (Tiếng Việt)

Ngày cập nhật: 2026-05-22

Tài liệu này mô tả chi tiết:

1. Chức năng và cách hoạt động của app `MH_Thongke`.
2. Cấu trúc, mục đích và cách duy trì file skills `.md` này.
3. File plan vận hành/nâng cấp hiện tại: `MH_Thongke_Plan.md`.

---

## 1) Mục tiêu của app

`MH_Thongke` là plugin SketchUp để:

- Thống kê **phụ kiện** theo mã sản phẩm (`SPxx`, `SPxx.xx`).
- Thống kê **vật liệu** theo material trên object.
- Đối chiếu model với file Excel để ra trạng thái:
  - `Khớp`
  - `Update`
  - `No SPEC`
  - `SPEC`
- Hỗ trợ thao tác nhanh qua:
  - bảng chính `MH Thongke`
  - `Mini Import`
  - `Material HUD` (Overlay trong viewport)

---

## 2) Cách mở app

Các entry point hiện có:

- Menu: `Plugins > MH Thongke`
- Menu: `Plugins > MH Thongke - Mini Import`
- Menu: `Plugins > MH Thongke - Material HUD`
- Context menu (khi có selection): `Mini Import Phụ Kiện (Excel)`

File entry chính: `main.rb`.

---

## 3) Kiến trúc module theo file

## 3.1 Core

- `main.rb`
  - Load toàn bộ module theo đúng thứ tự phụ thuộc.
  - Đăng ký menu chính + context menu.

- `config.rb`
  - Khai báo hằng số đường dẫn (`prefs`, `snapshot`, `rules`).
  - Bộ normalize tên (`cached_norm`) và sửa lỗi mojibake (`fix_vietnamese_mojibake`).
  - HTML/JS escaping helper.

- `performance.rb`
  - Cache chữ ký mô hình và selection.
  - `process_selection_cached` để tránh quét lại khi chưa đổi dữ liệu.

- `observers.rb`
  - Gắn `SelectionObserver`, `ModelObserver`, `ViewObserver`.
  - Debounce refresh (`0.65s`) + chặn refresh thừa.
  - Tự dọn cache/entity reference khi đóng hết dialog.

- `preferences.rb`
  - Lưu/đọc `mh_thongke_prefs.json`.
  - Lưu history trong attribute model.
  - Lưu/đọc rule và xuất rule ra Excel (`match_rules_log.xlsx`).

- `snapshot_store.rb`
  - Lưu snapshot theo file SKP vào `mh_thongke_data.json`.
  - Hỗ trợ rename, delete, export snapshot.

## 3.2 Engine xử lý dữ liệu

- `data_processor.rb` (lõi thống kê)
  - Hàm chính: `process_selection`.
  - Quét model đệ quy, gom phụ kiện/vật liệu, tính số lượng/chiều dài.
  - Sinh dữ liệu auto: `Thanh nhôm LED`, `Nguồn LED`, `Bas treo suốt áo`.
  - So sánh với Excel và gán trạng thái.
  - Hỗ trợ import ngược Excel để highlight sai khác (`back_diff`, `GHOST`).

- `geometry.rb`
  - Tính bounds, kích thước, chiều dài thực theo world transform.
  - Nhận diện phần cứng đặc biệt (kính, gương, lá inox...).
  - Tạo marker phụ kiện ảo (generated PK) và gán attribute ABF/MH_Thongke.
  - Tính transform đặt marker theo mặt panel.

- `tools.rb`
  - Tool highlight/chọn object phục vụ thao tác từ dialog.

## 3.3 Giao diện chính

- `html_builder.rb`
  - Render HTML bảng thống kê chính.
  - Build status button, unit select, project total.

- `dialog.rb`
  - Tạo `UI::HtmlDialog` chính.
  - Đăng ký callback cho toàn bộ hành động:
    - refresh/filter/group/display
    - update tên/tag/đơn vị/ngày đặt/ghi chú
    - import/export Excel
    - update/keep/accept rules
    - snapshot, history, undo
    - mở Mini Import / Material HUD

## 3.4 Mini Import + HUD

- `mini_import.rb`
  - File loader cho toàn bộ module Mini Import.

- `mini_import_context.rb`
  - Quản lý mode:
    - group mode: `module` / `product`
    - source mode: `view` / `select`
  - Xác định product code đang thao tác theo camera hoặc selection.

- `excel_import.rb`
  - Module Excel dung chung cho bang chinh, Mini Import va Material HUD.
  - Doc Excel bang `win32ole`, cache theo `path + mtime`.
  - Khong dung Ruby worker thread voi Excel COM de tranh crash SketchUp.

- `mini_import_excel.rb`
  - Shim tuong thich cu, chi load `excel_import.rb` neu can.
  - Đọc Excel bằng `win32ole`, tự dò header.
  - Cache theo path + mtime để không load lặp.

- `mini_import_rules.rb`
  - Rule normalize tên, equivalent/synonym.
  - Logic đặc thù Hafele và nhóm tương đương.

- `mini_import_table.rb`
  - Tạo data bảng mini từ model + excel.
  - Cache danh sách model item/excel item.

- `mini_import_entities.rb`
  - Tìm entity theo tên/id/SP.
  - Tạo phụ kiện ảo vào đúng panel mục tiêu.
  - Quy tắc chọn panel ưu tiên (`day` -> `hong trai` -> `hong phai`).

- `mini_import_accept.rb`
  - Quản lý accept rules theo session.
  - Undo/cancel/ok/apply-all có snapshot rule + xử lý entity thêm mới.

- `mini_import_dialog.rb`
  - UI mini dialog + callback thao tác:
    - `UPDATE`, `NO SPEC`, `SPEC`, `DELETE`, `RENAME`, `SET QTY`
    - `APPLY ALL`, `OK`, `CANCEL`, `UNDO`
    - `MODE`, `SOURCE`, `REFRESH`, `EXCEL`, `HUD`
    - khong tao PK moi trong MH_Thongke

- `mini_import_refresh.rb`
  - Refresh theo chữ ký trạng thái.
  - Chỉ update phần HTML/UI thực sự thay đổi.
  - Tách section `Phụ kiện` và `Vật liệu`.

- `mini_import_menu.rb`
  - Dang ky menu Mini Import/HUD.

- `material_hud.rb`
  - HUD vật liệu dạng Viewport Overlay.
  - Dùng chung logic so khớp VL với Mini Import.

---

## 4) Luồng hoạt động tổng thể

## Bước 1: Khởi tạo

1. `main.rb` load module.
2. `ensure_library_metadata`.
3. đăng ký menu + context menu.

## Bước 2: Quét model

Khi mở dialog hoặc refresh:

1. `process_selection_cached` kiểm tra chữ ký.
2. Nếu dữ liệu đã cũ -> chạy `process_selection`.
3. `process_selection` quét toàn bộ `active_entities` theo đệ quy.

## Bước 3: Phân loại object

Trong `process_selection`, mỗi Group/Component được phân loại:

- generated PK (`MH_Thongke.generated_pk == true`)
- phào chỉ
- phần cứng đặc biệt
- phụ kiện theo ABF/ZSU/ZSU_LED attrs
- vật liệu theo `entity.material` hoặc fallback `face.material`

## Bước 4: Hậu xử lý tự động

- Gộp phào chỉ về dữ liệu tổng.
- Tự tính `Thanh nhôm LED`.
- Tự tính combo `Nguồn LED` theo công suất (`led_psu_combo`).
- Tự sinh `Bas treo suốt áo` (2 cái / suốt áo).

## Bước 5: Đối chiếu Excel

Nếu đã load Excel:

- So khớp phụ kiện theo mã SP + rule normalize.
- Ưu tiên rule đã accept và rule đặc thù Hafele.
- Gán trạng thái:
  - `Khớp`: đã match hoặc được accept
  - `Update`: cần đổi tên theo Excel
  - `No SPEC`: model có nhưng Excel chưa có dòng phù hợp
  - `SPEC`: Excel có nhưng model chưa có

Vật liệu (`kind = VL`) được so khớp theo:

- tên normalize
- `material_code_norm`
- accept rule cho VL

## Bước 6: Render UI

- `html_builder.rb` build HTML cho dialog chính.
- Mini Import/HUD tự refresh theo signature riêng.

## Bước 7: Theo dõi thay đổi realtime

Observer bắt các event:

- đổi selection
- commit/undo/redo transaction
- đổi view camera

và debounce trước khi refresh để giảm lag.

---

## 5) Cách hoạt động chi tiết của Mini Import

## 5.1 Mode làm việc

- `MODUL` (`module`): thao tác theo `SPxx.xx`.
- `SẢN PHẨM` (`product`): gom theo `SPxx`.
- `SOURCE VIEW`: lấy SP từ các khối đang thấy trên màn hình.
- `SOURCE SELECT`: lấy SP từ selection hiện tại.

## 5.2 Cơ chế refresh nhanh

`import_mini_refresh_signature` kết hợp:

- danh sách SP đang hiển thị
- mode/source mode
- excel path + mtime
- hash rules/accept rules
- cache sig của process selection

Nếu signature không đổi, mini dialog không rebuild bảng.

## 5.3 Add PK

    - khong tao PK moi trong MH_Thongke

## 5.4 Session + Undo/CANCEL/OK

- Mỗi thao tác ghi snapshot rule + entity đã thêm.
- `UNDO`: hoàn tác model và khôi phục rules tương ứng.
- `CANCEL`: rollback toàn bộ session mini.
- `OK`: chốt session, giữ lại rules + dữ liệu đã sửa.

## 5.5 APPLY ALL

`mini_apply_all_status` tự động:

- update tên nếu cần
- khong tao dong PK moi
- ghi accept rule cho dòng `No SPEC`

Mục tiêu là đẩy nhanh xử lý cho toàn bộ SP đang hiển thị.

---

## 6) Cách hoạt động của Material HUD

HUD chạy chủ yếu ở dạng `Sketchup::Overlay`:

- Vị trí: góc dưới bên phải viewport.
- Dữ liệu: chỉ lấy `kind = VL`.
- Trạng thái hiển thị:
  - `OK`
  - `SPEC`
  - `NO SPEC`
  - `UPDATE`

HUD dùng cùng nguồn SP của Mini Import (`view/select`) và cùng rules accept.

---

## 7) Các file dữ liệu app

- `mh_thongke_prefs.json`
  - hidden list, view mode, unit override, excel paths.

- `mh_thongke_data.json`
  - snapshot theo từng file SKP.

- `match_rules_global.json`
  - rule chung + rule riêng cho match tên.

- `match_rules_log.xlsx`
  - file log/export rule (nhiều sheet: rules, accept, đổi đơn vị, thư viện PK...).

---

## 8) Các điểm tối ưu hiệu năng hiện có

1. Cache normalize tên (`@norm_cache`).
2. Cache scan (`process_selection_cached`).
3. Cache index SP đang thấy (`visible_product_index`).
4. Cache Excel theo `path + mtime`.
5. Debounce observer để giảm refresh dồn dập.
6. Refresh Mini/HUD theo chữ ký thay vì rebuild toàn bộ.
7. Dọn reference entity khi đóng dialog để giảm RAM.

---

## 9) File Skills này là gì và hoạt động ra sao

`MH_Thongke_Skills.md` là tài liệu vận hành nội bộ cho app, không phải mã thực thi Ruby.

Mục đích:

- Ghi rõ chức năng từng module.
- Mô tả flow dữ liệu để debug nhanh.
- Là checklist cho bảo trì/nâng cấp.

Nó **không được SketchUp chạy trực tiếp**.

---

## 10) Quy tắc cập nhật file Skills (.md)

Khi code thay đổi, cần cập nhật file này theo thứ tự:

1. Cập nhật `Ngày cập nhật`.
2. Nếu thêm/xóa callback: cập nhật mục module tương ứng.
3. Nếu đổi luồng dữ liệu (`process_selection`, mini refresh, HUD): cập nhật mục flow.
4. Nếu thêm file mới: thêm vào mục kiến trúc.
5. Nếu thêm rule/business logic mới: bổ sung vào phần Mini Import hoặc so khớp Excel.

Khuyến nghị:

- Ghi ngắn, đúng hành vi runtime.
- Ưu tiên mô tả theo file + hàm chính.
- Không copy log tạm/thông tin rác vào tài liệu.

---

## 11) Quy trình sử dụng app đề xuất (thực tế)

1. Mở `Plugins > MH Thongke`.
2. Chọn hoặc import file Excel thống kê.
3. Kiểm tra trạng thái trong bảng chính.
4. Mở `Mini Import` để xử lý nhanh theo SP.
5. Dung `APPLY ALL` hoac thao tac tung dong (`UPDATE/NO SPEC/SPEC`).
6. Mở `Material HUD` để kiểm tra vật liệu theo góc nhìn hiện tại.
7. Snapshot sau mỗi lần chốt dữ liệu.

---

## 12) Checklist debug nhanh

- Không thấy dữ liệu Excel:
  - kiểm tra `import_excel_path`
  - kiểm tra file tồn tại, sheet/cột đúng header.

- Mini Import không ra SP:
  - đổi `SOURCE` giữa `VIEW` và `SELECT`
  - kiểm tra tên nhóm có mã `SPxx` hoặc `SPxx.xx`.

- HUD không hiện:
  - kiểm tra phiên bản SketchUp có hỗ trợ `Sketchup::Overlay`.
  - thử bật lại qua menu `MH Thongke - Material HUD`.

- Trạng thái không đúng kỳ vọng:
  - kiểm tra `match_rules_global.json`
  - kiểm tra `mini_accept_rules` trong model attributes
  - refresh Excel (`EXCEL`) rồi refresh model (`REFRESH`).

---

## 13) Ghi chú kỹ thuật

- App hiện dùng `win32ole` để đọc/ghi Excel trên Windows.
- Nhiều thao tác dùng attribute dictionary:
  - `ABF`
  - `MH_Thongke`
  - `ZSU_LED`
- Các object phụ kiện ảo được đánh dấu:
  - `MH_Thongke.generated_pk = true`
  - `ABF.is-statistical-object = true`
