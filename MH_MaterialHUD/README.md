# MH Material HUD

Plugin SketchUp độc lập, chỉ dùng hạ tầng `MH_shared`. Không load mã nguồn,
dialog, bộ thống kê hoặc `final_stamped_report.json` của `MH_Thongke`.

## Sử dụng

- Mở **Extensions → MH Material HUD → Material HUD — mở / kích hoạt Tab**, hoặc toolbar riêng.
- **Tab** chuyển **VIEW** (sản phẩm trong vùng nhìn) / **SELECT** (sản phẩm của đối tượng đang chọn).
- Click chọn đối tượng; Shift + click thêm/bỏ chọn. Xóa lựa chọn sẽ xóa ngữ cảnh SELECT, không giữ sản phẩm cũ.
- Esc rời công cụ, bảng vẫn hiển thị. Khi dùng công cụ khác, phím Tab thuộc công cụ đó; mở lại công cụ HUD để dùng Tab.
- Chuột phải có chọn JSON, Reload JSON, đổi chế độ và tắt HUD. Lăn chuột trên bảng để xem các dòng tiếp theo.

## Nguồn dữ liệu

Dùng `MH::ProjectData`: JSON đang dùng chung trong model hoặc đường dẫn đã lưu
trong model. Có thể chọn file trực tiếp, không cần bật Registry hay Thongke.
Nếu Registry đang được nạp, HUD có thể hỏi đường dẫn JSON hiện hành khi model chưa lưu nguồn.
Nút **RELOAD JSON** của Registry truyền snapshot đã đọc sang HUD, không parse lại file.
JSON lỗi hoặc thuộc model khác sẽ xóa bảng cũ và báo lỗi, không quay về báo cáo cũ.

Bảng vật liệu gộp theo mã sản phẩm gốc, đọc `Ma_SP`, `Ma_vat_lieu` và các alias
của ProjectData; giữ `spec` và `ghi_chu` nếu JSON có. `&` tách nhiều vật liệu.
So mã bằng quy tắc `MH::MaterialCode`, bỏ độ dày và hậu tố 1M/2M khi đối chiếu.
`OK`: có trong JSON và model; `SPEC`: chỉ có trong JSON; `NO SPEC`: chỉ có trong model.
Trong lúc lập chỉ mục, hiển thị `…`, không khẳng định trạng thái khi chưa quét xong.
Bảng đối chiếu trực tiếp JSON/model. Các xác nhận VL đã lưu trong cấu hình global
của Mini Import được sao chép một lần sang `MH_MaterialHUD/data/accept_rules.json`;
sau đó đọc bản riêng, không cần thư mục/app Thongke. Không thay đổi quy tắc hay
dữ liệu phụ kiện cũ. Các session chưa lưu hoặc quy tắc riêng trong file dự án
không được tự gom vào cấu hình global.

## Hiệu năng / vòng đời

Chỉ mục model chạy từng lát khoảng 8 ms qua timer, có cache tên và mã vật liệu.
Đổi camera/lựa chọn/Tab chỉ tra chỉ mục; không import Excel hoặc quét lại model.
Model thay đổi mới lập chỉ mục lại; đổi JSON/version xóa cache dòng tương ứng.
Mỗi model có nguồn dữ liệu và chỉ mục riêng; tắt HUD dừng timer. Draw chỉ vẽ dữ liệu đã chuẩn bị.

Các nút HUD cũ của Thongke được chuyển sang bridge mở plugin mới. Observer của
Thongke không xem bảng độc lập này là một dialog cần cập nhật.
Mã HUD cũ còn trên đĩa để đối chiếu, nhưng không được loader Thongke nạp nữa.

## Kiểm thử

`ruby MH_MaterialHUD/test/standalone_test.rb`

Kiểm thử không nạp MH_Thongke/Registry, gồm reload cùng số dòng, sai model,
JSON lỗi, tách mã, so khớp độ dày/1M/2M, cache, timer, Tab và đổi chế độ không quét lại.
Kiểm thử thao tác/hiển thị thực tế cần SketchUp đang chạy và kết nối SkAgent/VBO.
