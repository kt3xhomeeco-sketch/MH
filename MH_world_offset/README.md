# MH World Offset - World Resize Plugin for SketchUp

Tài liệu này ghi lại kết cấu kiến trúc, các tính năng và thuật toán xử lý chính của plugin **MH World Offset** nhằm giúp AI và các nhà phát triển hiểu nhanh dự án để nâng cấp hoặc sửa lỗi mà không làm ảnh hưởng đến các tính năng hiện có.

---

## 1. Tổng quan dự án
**MH World Offset** (còn được gọi là **MH World Resize**) là plugin hỗ trợ co giãn (resize) nhanh kích thước của Group/Component trong SketchUp theo tọa độ World (thế giới), hỗ trợ cả các đối tượng đã bị xoay xéo trong không gian 3D. Người dùng nhập thông số dịch chỉnh độc lập cho 2 hoặc 4 cạnh của mặt phẳng để thay đổi kích thước.

---

## 2. Cấu trúc thư mục

* **`MH_world_offset.rb`** (Ngoài cùng):
  - Khai báo extension `MH World Offset` với SketchUp.
  - Cấu hình thông tin cơ bản: Tác giả (`MH`), Phiên bản (`1.1.1`), mô tả và đăng ký load file `MH_world_offset/main.rb`.
* **`MH_world_offset/main.rb`** (Quan trọng nhất):
  - Chứa logic thu thập điểm hình học, tính toán hệ trục của mặt phẳng chiếu theo camera, chuyển đổi ma trận World <-> Local.
  - Chứa lớp tương tác màn hình `ObjectResizeTool` xử lý di chuột, vẽ giao diện overlay trực quan (các viền nét đứt màu sắc và mũi tên chỉ hướng) và nhận giá trị từ thanh VCB.
* **`MH_world_offset/offset.svg`**:
  - Biểu tượng nút bấm trên thanh công cụ (Toolbar).

---

## 3. Các tính năng & Cách thức sử dụng

1. **Nhập thông số qua thanh VCB**:
   - Sử dụng dấu phẩy `,` để phân tách thông số cho các phía (Đơn vị tính: mm).
   - **Định dạng 2 số (`trên,phải`)**: Co giãn đều hai bên đối diện. Ví dụ: `10,20` (Giảm trên và dưới đi 10mm, giảm trái và phải đi 20mm).
   - **Định dạng 4 số (`trên,phải,dưới,trái`)**: Dịch chỉnh độc lập từng cạnh. Ví dụ: `10,20,5,0` (Giảm trên 10mm, phải 20mm, dưới 5mm, trái giữ nguyên).
   - *Lưu ý*: Nhập số dương là giảm kích thước (thu vào), nhập số âm là tăng kích thước (phình ra).
2. **Giao diện hiển thị trực quan (Overlay)**:
   - Khi hover qua mặt phẳng đối tượng, tool tự động vẽ:
     - Đường viền nét đứt màu xanh dương, màu cam và xanh lá thể hiện khoảng thu/phình.
     - 4 mũi tên tam giác màu đỏ ở tâm mặt phẳng chỉ ra hướng các trục (trên, dưới, trái, phải) tương ứng với thứ tự nhập trên thanh VCB.
3. **Áp dụng hàng loạt (Batch Resize)**:
   - Nếu người dùng chọn trước nhiều đối tượng rồi click hoạt động tool, plugin tự động xác định mặt phẳng hướng về phía camera của từng đối tượng để áp dụng resize đồng loạt cho toàn bộ selection theo giá trị VCB.

---

## 4. Thuật toán xử lý ma trận trong `main.rb`

Thuật toán thực hiện resize đối tượng bị xoay mà không cần chỉnh sửa trực tiếp vertex bên trong định nghĩa (definition):

1. **Xác định hệ trục mặt phẳng thế giới (`face_axes_world`)**: Tìm pháp tuyến mặt phẳng `N` và hai trục song song mặt phẳng `U` (ngang), `V` (dọc).
2. **Căn chỉnh theo góc nhìn (`orient_axes_to_view`)**: Xoay hệ trục sao cho trên màn hình, trục `U` luôn hướng sang bên phải và trục `V` luôn hướng lên trên.
3. **Chuyển đổi về tọa độ Local (`local_basis_from_world_axes`)**: Áp dụng ma trận nghịch đảo của đối tượng để tìm hướng tương ứng của `U`, `V`, `N` trong không gian Local của Group/Component.
4. **Tính toán ma trận scale và tịnh tiến**:
   - Tính toán tỷ lệ co giãn `sx` (theo trục ngang U) và `sy` (theo trục dọc V).
   - Tạo ma trận scale quanh tâm hình học `scale_about_center`.
   - Tính toán vector tịnh tiến bù đắp (`translation`) để dịch chuyển đối tượng theo hướng lệch của các thông số biên nhập vào (ví dụ: nếu chỉ giảm bên phải mà giữ nguyên bên trái, đối tượng sẽ được scale và dịch chuyển tịnh tiến sang trái để mép trái giữ nguyên vị trí).
   - Áp dụng ma trận tổng hợp cuối cùng lên instance.

---

## 5. Quy tắc an toàn khi chỉnh sửa Code (Dành cho AI)

> [!IMPORTANT]
> - **Tuyệt đối không sửa trực tiếp Vertex**: Plugin thực hiện biến đổi thông qua ma trận `transformation` của instance bên ngoài. Không được chuyển sang hướng chỉnh sửa vertex bên trong definition vì sẽ làm hỏng/biến dạng các đối tượng dùng chung definition (trừ khi đối tượng đã được `make_unique`).
> - **Căn chỉnh theo Camera**: Đảm bảo thuật toán xác định hướng camera (`camera_dir_changed?`) hoạt động mượt mà để cập nhật đúng hướng các mũi tên tam giác khi người dùng xoay góc nhìn trong SketchUp.
