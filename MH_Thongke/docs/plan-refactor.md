# Kế Hoạch Refactor Kiến Trúc (Data-driven Architecture)

## 1. Tối ưu Module Nhập Dữ liệu Excel
- **Kiến trúc hiện tại:** Sử dụng `WIN32OLE` qua COM Interface để thao tác với tiến trình Excel.
  - *Hạn chế:* Hiệu năng kém (overhead lớn, độ trễ 3-5 giây), tạo process rác (`EXCEL.EXE` zombie), phụ thuộc cứng vào môi trường MS Office trên máy client.
- **Kiến trúc đề xuất:** Triển khai một Helper Executable độc lập (biên dịch bằng C# hoặc Rust) chuyên trách việc parse `.xlsx`.
  - *Giải pháp:* Helper nhận đối số dòng lệnh (CLI arguments) là đường dẫn file Excel, thực hiện parse nội dung và serialize ra định dạng `.json`. Tầng Ruby chỉ thực hiện I/O đọc file JSON.
  - *Ưu điểm:* Thời gian xử lý < 50ms, độc lập với MS Office.

---

## 2. Refactor Core Matcher & Data Pipeline
- **Kiến trúc hiện tại:** Logic Matching bị tightly-coupled (liên kết chặt chẽ) với SketchUp Ruby API. Quá trình đối chiếu dữ liệu yêu cầu phải query trực tiếp thông tin từ model. Các module hiển thị (Bảng Tổng hợp, Mini Import) tự thực hiện việc query model và áp dụng rule riêng rẽ, dẫn đến phân mảnh logic và bất đồng bộ dữ liệu.
- **Kiến trúc đề xuất:** Áp dụng mô hình Data-driven. Matcher được decouple (tách rời) hoàn toàn khỏi SketchUp API. Matcher sẽ hoạt động như một pure function: nhận đầu vào là các tập tin JSON và trả ra kết quả JSON.

### Workflow xử lý dữ liệu mới (JSON Pipeline):

1. **Data Exporters (Thu thập dữ liệu tĩnh):**
   - `model_data.json`: `ModelScanner` là module DUY NHẤT được quyền chạm vào SketchUp API. Nó có nhiệm vụ quét 3D, **tự động đo đạc diện tích ván/gỗ (Vật liệu), đếm số lượng Phụ kiện**, sau đó đóng gói TẤT CẢ thành một cục file `model_data.json`.
     *(Tuyệt đối cấm các bảng giao diện tự ý gọi API để quét model. Mọi dữ liệu Vật liệu hay Phụ kiện từ nay trở đi đều phải được đọc ra từ file JSON này).*
   - `excel_data.json`: File JSON kết xuất từ Helper `.exe`.
   - `rules_data.json`: Chứa các cấu hình và accept rules được persist từ người dùng.

2. **Core Matcher (Xử lý và Đối chiếu):**
   - Hoạt động hoàn toàn dựa trên cấu trúc dữ liệu JSON, không phụ thuộc môi trường SketchUp.
   - Đầu vào: Parse 3 tập tin `model_data.json`, `excel_data.json`, `rules_data.json`.
   - Nghiệp vụ: Thực hiện logic gom nhóm (`product_code_base`), cross-reference, và resolve status (OK, THIẾU, NO_SPEC).
   - **Phân tách luồng tính toán (Role-based Filtering):** Nếu một tập tin JSON (được tạo ra từ quá trình tính toán, đếm số lượng và diện tích trực tiếp trong Model) được gắn thẻ `Tính VL` (trong tab File), Matcher sẽ thiết lập bộ lọc chỉ lấy dữ liệu Vật Liệu (VL) để tính toán, bỏ qua hoàn toàn các cấu kiện Phụ Kiện (PK) có bên trong file đó nhằm tránh xung đột dữ liệu.
   - Đầu ra: Kết xuất ra tập tin `final_stamped_report.json` đại diện cho Single Source of Truth của toàn bộ dự án.

3. **UI Renderers (Tầng Hiển thị View & Định tuyến Dữ liệu):**
   - Xây dựng giao diện UI theo hướng Stateless. Các bảng giao diện không chứa logic tính toán nghiệp vụ.
   - Luồng hoạt động: Đọc trực tiếp file `final_stamped_report.json` và tự động định tuyến (route) dữ liệu vào đúng Table ID đích:
     - **Dữ liệu Phụ Kiện (PK):** Được định tuyến thuần túy vào Tab Phụ Kiện (Sẽ **đổi tên** `id="tab-report"` cũ thành `id="tab-acc"` cho đồng bộ ngữ nghĩa) -> Render vào bảng `<table id="table-acc">`.
     - **Dữ liệu Vật Liệu (VL):** (Đặc biệt là từ các file JSON có tag `Tính VL`) được định tuyến thuần túy vào Tab Vật Liệu (`id="tab-mat"`) -> Render vào bảng `<table id="table-mat">`.
     - **Dữ liệu Hỗn hợp (PK + VL):** Render vào Tab Tổng Hợp (`id="tab-all"`) -> Bảng `<table id="table-all">`.
     - **Bảng HUD (Floating UI):** Tước bỏ hoàn toàn logic tự tính toán, HUD sẽ chỉ làm nhiệm vụ extract dữ liệu từ `final_stamped_report.json` để hiển thị nổi trên màn hình.
   - Xử lý tương tác UI: Khi chuyển đổi Context (VD: chọn module `SP32` trong Mini Import), hệ thống thực hiện thao tác filter array trên tập dữ liệu JSON tĩnh và re-render.
   - **Tái cấu trúc thư mục UI:** Gộp và dọn dẹp triệt để thư mục `ui/mini_import` (hiện đang chứa tới 72 file nhỏ lẻ rác và phân mảnh). Xoá toàn bộ các file tự query model, chỉ giữ lại tối đa 3-4 file làm nhiệm vụ thuần UI (Dialog, Render, và Callbacks).
   - **Chuẩn hóa Giao diện (Design System):** Trích xuất toàn bộ định dạng CSS (font chữ, màu sắc, thiết kế nút bấm - buttons, bảng biểu) thành một hệ thống tiêu chuẩn chung (shared UI core/CSS). Tệp tiêu chuẩn này sẽ được nhúng (import) vào TẤT CẢ các module giao diện (Bảng Tổng, Mini Import, HUD...) nhằm đảm bảo tính đồng nhất 100% về mặt thị giác và tái sử dụng code triệt để.

### Lợi ích kỹ thuật (Technical Benefits):
- **Single Source of Truth:** Loại bỏ hoàn toàn side-effects và data inconsistency giữa các giao diện.
- **Tối ưu hóa UI Performance:** Khử bỏ hoàn toàn chi phí query API (O(N)) tại runtime. Các tác vụ điều hướng UI được giới hạn ở mức xử lý in-memory filtering.
- **Bảo trì và Testing (Testability):** Dễ dàng thiết lập Unit Testing và tái hiện (reproduce) bug thông qua việc sử dụng các JSON mock data, không yêu cầu load file `.skp` thực tế của user.

---

## 3. Cơ chế Quản lý Rules & State Mutation
- **Vấn đề:** Với mô hình UI là Stateless, khi user tương tác (ví dụ click "Accept" để map thủ công trên Bảng Mini), dữ liệu rule mới sẽ được lưu trữ và áp dụng như thế nào?
- **Giải pháp:** Sử dụng module `RulesManager` kiểm soát One-way Data Flow (Luồng dữ liệu một chiều).

### Luồng cập nhật (Update Cycle):
1. **Lưu trữ tĩnh (Persistence):** Các rules (luật map thủ công, quy tắc bỏ qua) bắt buộc phải được persist vào **Model Attribute** của SketchUp để đính kèm theo tệp `.skp`.
2. **Trigger (UI Action):** User click "Accept" (Nút tương tác này sẽ **khả dụng trên TẤT CẢ các bảng**: Bảng Tổng, Bảng Mini, HUD...). Giao diện (JS) gửi callback thông báo sự kiện thay đổi về cho hệ thống.
3. **Mutation (Cập nhật State):** `RulesManager` nhận lệnh, cập nhật Model Attribute, và ngay lập tức kết xuất (serialize) ra tập tin `rules_data.json` mới.
4. **Re-evaluate (Đối chiếu lại):** Hệ thống tự động kích hoạt **Core Matcher**. Matcher nạp 3 file JSON (`model_data.json`, `excel_data.json`, và `rules_data.json` vừa cập nhật) để chạy lại toàn bộ tiến trình đối chiếu.
5. **Re-render (Cập nhật View):** Core Matcher ghi đè kết quả ra `final_stamped_report.json`. UI tự động parse lại tập tin này và re-render trạng thái mới.

---

## 4. Ánh xạ File hệ thống (Current vs. Proposed)

Nhằm làm rõ mức độ phân mảnh của hệ thống hiện tại so với kiến trúc mới, dưới đây là bảng mapping vị trí đảm nhiệm 3 tác vụ lõi (Match, Update, Hold):

| Tác vụ Lõi | Hiện tại (Current State) | Đề xuất (Proposed State) |
|---|---|---|
| **MATCH**<br>(So khớp / Đối chiếu) | - Bảng Tổng: `engine/excel_matcher.rb`<br>- Bảng Mini: `ui/mini_import/mini_import_excel_items.rb`<br>- Bảng HUD: `ui/material_hud_data.rb` | - Gom về 1 module duy nhất là `Core Matcher`. Chỉ xử lý I/O trên tập tin JSON. |
| **UPDATE**<br>(Cập nhật Rules khi thao tác) | - Bảng Mini: `ui/mini_import/mini_import_accept_rules.rb` (Hàm `mini_accept_rule_action`) | - Chuyển sang module `RulesManager`. Nhận tín hiệu từ UI (Tương tác hợp nhất: **Hỗ trợ thao tác trên mọi bảng** thay vì chỉ Bảng Mini), ghi đĩa và kích hoạt Matcher chạy lại. |
| **HOLD / PERSIST**<br>(Lưu giữ trạng thái / Cache) | - Excel: Cache file `import_excel_cache.json` và biến RAM `@imported_excel_data`<br>- Model: Biến RAM `@data_map`<br>- Rules: Thuộc tính (Attribute) của `Sketchup.active_model` | - Loại bỏ biến RAM toàn cục. Trạng thái (State) được persist 100% ra 3 tệp JSON tĩnh: `model_data.json`, `excel_data.json`, `rules_data.json`. Tầng UI load trực tiếp từ JSON. |

---

## 5. Phân rã "God Objects" và Cơ chế hệ thống (System Mechanics)
Để kiến trúc mới hoạt động trơn tru, cần phải "phẫu thuật" triệt để các file đang bị phình to bất thường (God Objects) và chuẩn hoá lại một số cơ chế:

- **`engine/data_processor.rb` (Đang 57KB):** Chứa quá nhiều trách nhiệm. Cần chia tách các logic đang bị gom cục (logic tính khối lượng Vật liệu, đếm LED, xử lý Phụ kiện) về các module chuyên biệt tương ứng.
- **`ui/html_builder.rb` (Đang 160KB):** Chia nhỏ tệp render HTML khổng lồ này thành các UI Component nhỏ gọn (ví dụ: `TableMatRenderer`, `TableAccRenderer`, `TableAllRenderer`), đồng thời loại bỏ toàn bộ CSS rải rác chuyển vào Design System.
- **Hệ thống Snapshot (`core/snapshot_store.rb`):** Lịch sử các lần cắt (Snapshot) trước đây xử lý quá phức tạp. Sau refactor, Snapshot chỉ đơn thuần là thao tác copy tập tin `final_stamped_report.json` và lưu lại theo timestamp (Thời gian thực).
- **Cơ chế Trigger Quét ngầm (Event Hooks):** Xác định rõ khi nào `ModelScanner` được phép kích hoạt để sinh ra `model_data.json`. Đề xuất: Chỉ tự động quét lại khi có sự thay đổi lớn (Save Model, Commit Operation) hoặc khi User chủ động ấn nút làm mới, giảm thiểu việc quét vô tội vạ mỗi lần click chuột.

---

## 6. Lộ trình triển khai (Refactor Phases)
Việc đập đi xây lại toàn bộ là bất khả thi. Lộ trình cần chia thành 3 giai đoạn để đảm bảo Plugin vẫn hoạt động được trong thời gian chuyển giao:

- **Phase 1: Độc lập hóa Dữ liệu (Data Layer)**
  - Chế tạo CLI Helper (`.exe`) để parse file Excel ra JSON.
  - Xây dựng `ModelScanner` để xuất thông tin 3D ra file `model_data.json`.
- **Phase 2: Xây dựng Bộ não trung tâm (Logic Layer)**
  - Viết `RulesManager` để quản lý các quy tắc.
  - Viết `Core Matcher` (Pure Function) tiếp nhận các file JSON và sinh ra `final_stamped_report.json`.
- **Phase 3: Tái thiết Giao diện (Presentation Layer)**
  - Dọn rác 72 file trong thư mục `ui/mini_import` và cắt nhỏ `html_builder.rb`.
  - Áp dụng UI Design System chung.
  - Chuyển toàn bộ các Bảng (Tổng hợp, Mini, HUD) sang chế độ Stateless (Chỉ đọc duy nhất tệp `final_stamped_report.json`).
