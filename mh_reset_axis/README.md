# MH Reset Axis - Reset Axis Plugin for SketchUp

Tài liệu này ghi lại kết cấu kiến trúc, các tính năng và thuật toán xử lý chính của plugin **MH Reset Axis** nhằm giúp AI và các nhà phát triển hiểu nhanh dự án để nâng cấp hoặc sửa lỗi mà không làm ảnh hưởng đến các tính năng hiện có.

---

## 1. Tổng quan dự án
**MH Reset Axis** là plugin giúp thiết lập lại (reset) hệ trục tọa độ của các Group và Component Instance trong SketchUp. Plugin tự động phân tích hình học để căn chỉnh các trục X, Y, Z phù hợp và đưa điểm gốc tọa độ (Origin) về góc dưới cùng (Minimum corner) của đối tượng. Điều này rất hữu ích cho công việc sản xuất (CNC) hoặc định vị cấu kiện xây dựng.

---

## 2. Cấu trúc thư mục

* **`mh_reset_axis.rb`** (Ngoài cùng):
  - Khai báo extension `MH Reset Axis` với SketchUp.
  - Thiết lập các thông tin cơ bản: Tác giả (`MH`), Phiên bản (`1.0.9`), mô tả và đăng ký load file `mh_reset_axis/main.rb`.
* **`mh_reset_axis/main.rb`** (Quan trọng nhất):
  - Chứa toàn bộ logic thuật toán tính toán hệ trục, xử lý ma trận và biến đổi hình học trong SketchUp.
  - Tạo menu chính (`Extensions`), thanh công cụ (Toolbar) và menu chuột phải (Context Menu).
* **`mh_reset_axis/icons/`**:
  - Chứa các file biểu tượng định dạng SVG (`mode_size.svg`, `mode_vertical.svg`) cho các nút bấm trên thanh công cụ.

---

## 3. Các tính năng & Chế độ hoạt động

Plugin cung cấp 2 chế độ reset trục chính:

### A. Chế độ sắp xếp theo Kích thước (`MODE_SIZE`)
* **Khẩu hiệu**: `Dài nhất → Y, ngắn nhất → Z`
* **Cách hoạt động**:
  1. Phân tích kích thước bao của đối tượng.
  2. Định hướng lại trục sao cho chiều có kích thước dài nhất chạy dọc theo trục Y (Green Axis).
  3. Chiều có kích thước ngắn nhất chạy dọc theo trục Z (Blue Axis).

### B. Chế độ sắp xếp theo Hướng đứng (`MODE_VERTICAL`)
* **Khẩu hiệu**: `Đứng → Y, ngang → X, ngắn nhất → Z`
* **Cách hoạt động**:
  1. Định hướng lại trục sao cho phương thẳng đứng của đối tượng (song song với trục Z của thế giới) chạy dọc theo trục Y (Green Axis) của đối tượng.
  2. Phương ngang chạy dọc theo trục X (Red Axis).
  3. Chiều ngắn nhất chạy dọc theo trục Z (Blue Axis).

---

## 4. Quy trình thuật toán cốt lõi trong `main.rb`

Thuật toán của plugin thực hiện qua 5 bước chính:

1. **Thu thập dữ liệu hình học (`collect_parent_geometry`)**: Quét qua toàn bộ thực thể con trong Group/Component để lấy danh sách các điểm (vertices), hướng cạnh (edge vectors) và mặt phẳng (faces).
2. **Tìm hệ trục tối ưu**:
   - **Ưu tiên 1**: Tìm mặt phẳng có diện tích lớn nhất (`axes_from_largest_face`). Lấy pháp tuyến của mặt này làm trục Z, hướng cạnh dài nhất trên mặt làm trục Y, và trục X vuông góc với hai trục trên.
   - **Ưu tiên 2 (Fallback)**: Nếu không tìm thấy mặt phẳng hợp lệ, plugin gom nhóm các hướng cạnh song song (`direction_clusters`) và tính điểm số (`score`) dựa trên kích thước bao và hướng trục thế giới để chọn ra bộ 3 trục vuông góc tốt nhất.
3. **Tìm điểm gốc mới (`minimum_corner`)**: Tính toán điểm góc dưới cùng tối thiểu dựa trên hệ trục mới và hình học thực tế để làm điểm Origin mới.
4. **Biến đổi thực thể (`reset_definition_axes`)**:
   - Nếu định nghĩa (definition) của Component được sử dụng bởi nhiều instance khác, thực hiện `make_unique` để tránh ảnh hưởng đến các đối tượng khác trong model.
   - Dùng phép biến đổi ma trận để dịch chuyển toàn bộ thực thể bên trong định nghĩa về vị trí tương đối mới (đảm bảo hình học bên ngoài không bị dịch chuyển vị trí trong không gian thế giới).
   - Gán ma trận biến đổi mới cho Component Instance.

---

## 5. Quy tắc an toàn khi chỉnh sửa Code (Dành cho AI)

> [!IMPORTANT]
> - **Bảo toàn vị trí hình học**: Phải đảm bảo phép biến đổi ma trận ngược (`new_transformation.inverse * old_transformation`) được áp dụng chính xác cho các thực thể con. Nếu sai lệch, các đối tượng bên trong Group/Component sẽ bị nhảy vị trí trong không gian 3D.
> - **Lưu ý Operation**: Toàn bộ thao tác phải được bao bọc trong `model.start_operation` và `model.commit_operation` để có thể Ctrl+Z khôi phục nguyên trạng khi cần.
