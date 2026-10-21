# MH Material HUD

Plugin SketchUp độc lập, chỉ dùng hạ tầng `MH_shared`. Không load mã nguồn,
dialog, bộ thống kê hoặc `final_stamped_report.json` của `MH_Thongke`.

## Sử dụng

- Mở **Extensions → MH Material HUD → Material HUD — mở / kích hoạt Tab**, hoặc toolbar riêng.
- **Tab** chuyển **VIEW** (sản phẩm trong vùng nhìn) / **SELECT** (sản phẩm của đối tượng đang chọn).
- Click chọn Group/DC để làm gốc cho cả cụm; Ctrl + click chọn chi tiết sâu bên trong; Shift + click thêm/bỏ chọn. Xóa lựa chọn sẽ xóa ngữ cảnh SELECT, không giữ sản phẩm cũ.
- Esc rời công cụ, bảng vẫn hiển thị. Khi dùng công cụ khác, phím Tab thuộc công cụ đó; mở lại công cụ HUD để dùng Tab.
- Chuột phải có chọn JSON, Reload JSON, đổi chế độ và tắt HUD. Lăn chuột trên bảng để xem các dòng tiếp theo.
- Khi **MH Material Assign** đang mở và chọn một đối tượng thuộc đúng một SP, HUD
  đó hiện các nút vật liệu ở giữa phía dưới màn hình. Danh sách lấy trực tiếp từ
  JSON đang dùng tại đây: **Tab** đổi mã đang chọn, **Enter** hoặc click nút để
  gán mã đó cho object đã chọn. Excel chỉ là fallback của MH Material khi không
  có JSON runtime.

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

Danh mục nhóm gốc được lập một lần theo SP, bằng vị trí marker và bounds.
Nhóm qua ranh giới được kiểm tra thêm; với nhóm dưới mọi marker, chỉ đọc cây
tên/thuộc tính để xác định các SP có thể có. Cụm nesting không có mã SP không
bị đưa vào từng lượt đọc vật liệu. Mỗi khi đổi lựa chọn, SP đang chọn được ưu
tiên trong phần danh mục chưa đọc, giữ lại các nhóm/cache đã hoàn tất. Nhóm
khớp trực tiếp được đọc trước các nhóm qua ranh giới cần kiểm tra thêm.

Mỗi lượt kiểm tra chỉ đọc các nhóm liên quan. Nội dung face/material của một
definition được cache chung cho các instance; kết quả từng nhóm cũng được
tái sử dụng khi đổi lựa chọn/Tab. Công việc chạy qua timer với ngân sách 4 ms
mỗi lượt, nghỉ 10 ms trước khi tìm thấy vật liệu đầu tiên, sau đó nghỉ 30 ms
giữa các lượt để nhường UI. Di chuyển camera vẫn dừng quét hoàn toàn.
`OK` và `NO SPEC` hiện ngay khi vật liệu đã được đọc (JSON đã nạp đầy đủ);
chỉ `SPEC` phải chờ xác nhận vật liệu không có trong model khi
danh mục và các nhóm của SP đã đọc xong. Bước lập danh mục lần đầu vẫn chạy
nền trên toàn model, nhưng không chặn việc xác nhận các vật liệu đã tìm thấy.

Chỉ dùng bốn observer cấp collection/model, không gắn observer cho hàng nghìn
definition. MH Material và MH Ván gửi phạm vi của giao dịch gán/đổi/xóa vật
liệu qua `begin_material_change` / `finish_material_change`. Cache của SP khác
được giữ lại; definition dùng chung làm mới tất cả occurrence liên quan.
Phạm vi được chụp cả trước/sau để xử lý `make_unique`; phạm vi quá lớn hoặc
không xác định được sẽ quay về kiểm tra đầy đủ. Xác nhận phạm vi chỉ áp dụng
cho đúng revision đó, không che mất một giao dịch khác diễn ra sau nó.
Các thay đổi xác định được nguồn cập nhật SP liên quan; transaction
không theo dõi được (kể cả sửa face lồng nhau), Undo/Redo hoặc thay marker sẽ
xây lại cache để bảo đảm kết quả đúng. Callback definition chỉ ghi nhận thay
đổi, không đi ngược toàn cây instance trong lúc thao tác.
Mỗi lần cache model bị vô hiệu hóa tăng generation. Scan cũ đang chạy hoặc
đã hoàn tất không được trả lại vật liệu của generation trước; timer vật liệu
dừng ngay khi model đổi, rồi cập nhật lại sau khi giao dịch hoàn tất.
Trong khi di chuyển camera, dừng quét; chờ yên 250 ms mới cập nhật.
Khi model đổi, đọc nhóm vừa thêm/sửa và các nhóm của SP hiện tại trước khi
sắp xếp/quét phần danh mục còn lại. Chi tiết ưu tiên mã SP trong tên instance; khi tên obj/cha không có mã, phân loại theo nhãn tại vị trí đích. Metadata cũ không chọn SP. Vật liệu mới ngoài JSON
hiện `NO SPEC` ngay khi đọc được, không chờ hoàn tất toàn bộ danh mục.
Pan/zoom song song giữ cache; đổi hướng nhìn chỉ xây lại quyền sở hữu theo
marker, giữ nội dung definition và observer. Mỗi model có cache riêng;
đổi model tháo observer cũ.
Tắt HUD dừng timer. Draw chỉ vẽ dữ liệu đã chuẩn bị.

Các nút HUD cũ của Thongke được chuyển sang bridge mở plugin mới. Observer của
Thongke không xem bảng độc lập này là một dialog cần cập nhật.
Mã HUD cũ còn trên đĩa để đối chiếu, nhưng không được loader Thongke nạp nữa.

## Kiểm thử

`ruby MH_MaterialHUD/test/standalone_test.rb`

Kiểm thử không nạp MH_Thongke/Registry, gồm reload cùng số dòng, sai model,
JSON lỗi, tách mã, so khớp độ dày/1M/2M, cache, timer, Tab và đổi chế độ không quét lại.
Kiểm thử thao tác/hiển thị thực tế cần SketchUp đang chạy và kết nối SkAgent/VBO.
`test/product_store_cases.rb` kiểm tra cache definition, nhóm qua ranh giới,
metadata trong nesting, sửa/xóa/di chuyển/gán vật liệu, bảo toàn cache SP khác
và xác nhận vật liệu trước khi danh mục hoàn tất. Bao gồm giao dịch scoped,
sửa face dùng chung, đổi definition khi make_unique, cập nhật giữa lượt quét,
Undo/Redo và giao dịch không theo dõi được.

## Nhận SP theo trục X đỏ (10/10/2026)

MH_material và Desktop dùng cùng hợp đồng `name-first-world-x-v3`, không phụ thuộc camera. Ưu tiên mã SP trong tên instance obj (ví dụ `__739. SP05_Vách`); con không có mã riêng kế thừa tên cha gần nhất, con có mã riêng được ưu tiên. Không lấy tên definition dùng chung hoặc attribute Registry. Model không nhãn vẫn nhận được khối có tên SP. Sau đó mới xét nhãn theo vị trí X. Nhãn Text nằm một hàng theo X; lấy khoảng X của các chi tiết khối cấp lá sau khi áp dụng đủ transform cha. Y/Z không giới hạn. Nhãn tìm cụm khởi đầu qua mặt phẳng YZ rồi lan qua các khe X nhỏ; khe ngăn hai cụm SP quyết định ranh giới, không lấy trung điểm hai nhãn. Chi phí lan gồm cả khoảng trống từ nhãn đến chi tiết đầu tiên; nhãn ở vùng trống không khóa giữ chi tiết nằm gần cụm SP khác. Cụm tranh chấp được để chưa xác định; không dùng mã Registry thay thế khi có bố trí nhãn.

Chi tiết chứng minh SP phải có mặt và đủ ba kích thước khác 0 trong hệ trục riêng sau khi tính scale/transform. Hình phẳng dù xoay, wireframe, instance ép phẳng, nhãn Text và `_ABF_Label` không được tính. Nhãn 2D bên trong khối không thay thế khối đó làm đơn vị quét. Lookup theo đúng occurrence (entity và khoảng X), tránh nhầm hình phẳng với khối có cùng khoảng X.

Nhãn có khoảng cách giữa mép X không quá 10 mm mặc định được ghép thành cụm SP lớn chứa nhiều mã SP con. Chỉnh `MH_shared/data/product_spatial.json` → `labelGroupGapMm` để đổi ngưỡng cho cả hai app. MH_material hiển thị vật liệu của các SP con; khi gán tự động hoặc bấm SP↻, chọn SP con để tra SPEC. Lựa chọn được dùng chung trong một lượt thao tác; hủy chọn giữ nguyên vật liệu. Đọc nhận diện không tự ghi hoặc lưu SKP.

Cache nhận diện theo phiên bản model và ngưỡng nhóm nhãn, không theo camera. Di chuyển nhãn/chi tiết hoặc Undo/Redo làm tính lại. Kiểm tra số học Ruby/JS dùng chung fixture tại Desktop `test/fixtures/product_x_cases.json`; chạy `ruby MH_shared/test/product_x_cluster_check.rb <đường-dẫn-fixture>`.
