# MH Nep - Edge Banding Extension for ABF in SketchUp

Tài liệu này ghi lại kết cấu kiến trúc, các tính năng và cách thức tích hợp của plugin **MH Nep** nhằm giúp AI và các nhà phát triển hiểu nhanh dự án để nâng cấp hoặc sửa lỗi mà không làm ảnh hưởng đến các tính năng hiện có.

---

## 1. Tổng quan dự án
**MH Nep** là plugin mở rộng dành riêng cho SketchUp, hoạt động bổ trợ cho công cụ dán nẹp của hệ sinh thái **ABF** (plugin sản xuất đồ gỗ nội thất). Plugin cho phép dán chỉ cạnh (edge band) tự động theo hướng nhìn (hướng camera) hoặc dán thủ công trực quan qua giao diện màn hình HUD (Heads-Up Display).

---

## 2. Cấu trúc thư mục

* **`MH_nep.rb`** (Ngoài cùng):
  - Khai báo extension `MH Nep` với SketchUp.
  - Thiết lập các thông tin cơ bản: Tác giả (`MH`), Phiên bản (`1.0.0`), mô tả và đăng ký load file `MH_nep/main.rb`.
* **`MH_nep/main.rb`** (Quan trọng nhất):
  - Chứa logic quét hình học tấm ván, tính toán hướng mặt cạnh, lọc độ dày ván và lưu trữ dữ liệu nẹp theo chuẩn ABF.
  - Thực hiện Monkey Patching để tích hợp HUD vào công cụ gốc của ABF.
  - Xử lý các công cụ dán nẹp bằng tay (`ManualTool`).
* **`MH_nep/options.json`**:
  - Lưu trữ cấu hình mặc định hoặc các thiết lập người dùng lưu lại từ hộp thoại Setting (chế độ dán, hướng nhìn, mã nẹp chính/phụ, bộ lọc độ dày, danh sách bỏ qua).
* **`MH_nep/ui.html`**:
  - Giao diện HTML của hộp thoại cài đặt (`UI::HtmlDialog`) cho phép người dùng tùy chỉnh các tham số dán nẹp trực quan.

---

## 3. Các tính năng cốt lõi

1. **Tích hợp sâu với ABF (ABF Bridge)**:
   - Plugin tự động kiểm tra sự tồn tại của các class ABF (`ABF::EditEdgeBand`, `ABF::EdgeBandType`...).
   - Thực hiện hook (`install_abf_bridge!`) vào class gốc `ABF::EditEdgeBandTool` để chèn HUD tùy biến và bắt sự kiện click chuột trực tiếp trong công cụ của ABF.
2. **Dán nẹp tự động (Auto Apply)**:
   - **Chế độ hướng nhìn (`view`)**: Quét các mặt cạnh của tấm ván. Mặt cạnh nào hướng về phía chỉ định (ví dụ Trước/Sau/Trái/Phải/Trên/Dưới) sẽ được dán nẹp chính, các mặt cạnh khác dán nẹp phụ.
   - **Chế độ dán phẳng (`plain`)**: Dán tất cả 4 cạnh nhỏ của tấm ván bằng nẹp chính.
   - **Quy tắc dán Veneer**: Tự động nhận diện nếu vật liệu của tấm ván có chứa các tiền tố chỉ định (ví dụ `ver`, `VERKTSOI`...) để dán loại nẹp veneer tương ứng.
3. **Bộ lọc thông minh**:
   - Lọc theo độ dày của tấm ván (`min_thickness_mm`, `max_thickness_mm`) để tránh dán nhầm nẹp lên các tấm ván hậu hoặc ván quá dày.
   - Lọc theo độ dài tối thiểu của cạnh (`min_edge_length_mm`).
   - Bỏ qua các đối tượng nằm trong danh sách loại trừ (tên group, tên định nghĩa hoặc layer có chứa các từ khóa chỉ định).
4. **Dán tay HUD trực quan**:
   - Hiển thị thanh menu nổi trên màn hình SketchUp cho phép chọn nhanh mã nẹp, đổi nẹp bằng phím `Tab` và click chọn trực tiếp mặt cạnh để dán.
5. **Xóa nẹp hàng loạt (Clear Band)**:
   - Xóa nhanh dữ liệu nẹp của tất cả các tấm ván đang chọn hoặc trên toàn bộ model.

---

## 4. Cấu trúc dữ liệu và Tương thích ABF
Plugin lưu dữ liệu nẹp trực tiếp vào thuộc tính của Group/Component dưới dạng đối tượng `ABF::EditEdgeBand::EdgeBandData`.
* Dữ liệu lưu trữ bao gồm:
  - `types`: Danh sách các loại nẹp được sử dụng (chứa thông tin tên nẹp, độ dày, chiều rộng, màu sắc).
  - `faces`: Hash map liên kết giữa đối tượng `Sketchup::Face` và ID của loại nẹp.
  - `empty_faces`: Mảng các mặt không dán nẹp.

---

## 5. Quy tắc an toàn khi chỉnh sửa Code (Dành cho AI)

> [!IMPORTANT]
> - **Giữ nguyên giao thức ABF**: Tuyệt đối không thay đổi cấu trúc dữ liệu lưu vào thực thể (`ABF::EditEdgeBand.set_data`) vì nếu sai lệch định dạng, plugin ABF gốc sẽ không đọc được nẹp để xuất file CNC hoặc dự toán.
> - **Cẩn thận khi Monkey Patching**: Logic hook vào `ABF::EditEdgeBandTool` (`alias_method`) chỉ được cài đặt một lần duy nhất (kiểm tra `@mh_nep_bridge_installed`). Nếu định nghĩa lại hoặc chồng chéo sẽ gây lỗi lặp vô hạn (infinite loop) làm treo SketchUp.
> - **Kiểm tra sự tồn tại của ABF**: Luôn gọi `abf_ready?` trước khi thực hiện các tác vụ liên quan đến thư viện ABF để tránh lỗi crash khi người dùng chưa cài hoặc chưa bật ABF.
