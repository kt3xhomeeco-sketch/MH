# MH Isolate

Plugin isolate/unisolate nhanh dành cho SketchUp 2025, tối ưu cho model có nhiều Group và Component lồng nhau.

## Tính năng chính

- Isolate các Group và Component đang chọn trong editing context hiện tại.
- Chỉ xử lý các object cùng cấp; mặc định không duyệt Edge/Face nằm bên trong Group hoặc Component.
- Giữ nguyên các object đã bị ẩn từ trước bằng `hidden` hoặc Tag gốc đang tắt.
- Bỏ qua object bị khóa để không tự ý thay đổi trạng thái khóa của model. Vì vậy object khóa có thể vẫn hiện trong lúc isolate.
- Mọi object đang nằm trực tiếp trên Tag `MH_DWG` được bảo vệ trong cả MH Isolate và MH Van: không chuyển sang temp Tag, không đưa vào mapping ẩn và luôn giữ nguyên Tag gốc.
- Ghi nhớ Tag gốc bằng `persistent_id` và tên Tag để trả object về đúng Tag khi restore.
- Lưu dữ liệu khôi phục trong attribute dictionary `MH_isolate` của model.
- Giữ nguyên camera khi unisolate.
- Có thể tự động zoom tới các object vừa isolate.
- Có chế độ xử lý cả loose Edge/Face khi người dùng thực sự cần.

## Cache isolate nhanh

Tùy chọn `Fast Repeated Toggle Cache` được bật mặc định.

- Lần isolate đầu tiên tạo temp Tag và lưu mapping giữa object với Tag gốc.
- Những lần isolate/unisolate tiếp theo trên cùng cache chỉ bật hoặc tắt temp Tag, không ghi lại Tag cho hàng nghìn object.
- Khi chuyển target từ object A sang object B, plugin chỉ đổi Tag cho phần selection thay đổi thay vì xử lý lại toàn bộ object cùng cấp.
- Danh sách Group/Component và reference tới object/Tag được cache trong RAM.
- Mapping bằng `persistent_id` vẫn được lưu trong model để có thể phục hồi sau khi reload plugin hoặc mở lại file.
- Cache được kiểm tra trước khi dùng. Nếu model đã thay đổi khiến cache không còn hợp lệ, plugin sẽ restore an toàn rồi dựng cache mới.

### Khi nào cache bị xóa hoặc phải dựng lại?

- Chạy lệnh `MH Unisolate` để restore Tag thật hoàn toàn.
- Chạy `Force Restore / Cleanup`.
- Tắt `Fast Repeated Toggle Cache` rồi unisolate.
- Undo về thời điểm trước khi isolate.
- Thêm/xóa object, đổi editing context hoặc thay đổi Tag làm mapping hiện tại không còn hợp lệ.
- Dùng chế độ `Include Loose Edge/Face` trong trường hợp cần restore đầy đủ loose geometry.

`MH Show All Tags` không xóa cache MH Isolate. Lệnh này chỉ chuyển cache sang trạng thái hiển thị toàn bộ để lần isolate tiếp theo vẫn nhanh.

## Show All Tags và MH Van

Lệnh `MH Show All Tags`:

- Hiển thị toàn bộ Tag và Tag Folder thông thường.
- Giữ nguyên mapping cache của MH Isolate.
- Chuyển MH Isolate sang trạng thái visual unisolate bằng cách bật temp Tag.
- Soft-show các temp Tag của `MH_Van` và giữ cache phân loại theo dòng để lần isolate tiếp theo không phải dựng lại.
- Không tự ý bật temp Tag lạ của plugin khác nếu không thể restore an toàn.

Lệnh cô lập dòng của MH Van được chuyển trực tiếp sang engine MH Isolate khi toàn bộ object của dòng nằm trong editing context hiện tại. Hai lệnh dùng chung đúng một temp Tag, một mapping vật lý và một owner `Entity#layer`. Cache temp Tag isolate kiểu cũ của MH Van sẽ được restore một lần khi migrate.

Các tính năng ẩn/hiện từng dòng độc lập của MH Van vẫn có state riêng vì chúng không có cùng ý nghĩa với isolate toàn cảnh.

Nếu muốn xóa hoàn toàn temp Tag của MH Isolate và trả object về Tag gốc ngay lập tức, dùng `MH Unisolate` hoặc `Force Restore / Cleanup`.

## Loose Edge/Face

Mặc định plugin không xử lý loose Edge/Face để tránh chậm trên model có nhiều hình học rời hoặc geometry lồng sâu.

Bật tại:

`Extensions > MH Isolate > Include Loose Edge/Face (Slower)`

Khi bật, isolate sẽ đầy đủ hơn nhưng có thể chậm đáng kể.

## Zoom khi isolate

Tùy chọn `Zoom to Isolated Objects` được bật mặc định. Có thể tắt/bật trong menu `MH Isolate`.

## Các lệnh

- `MH Toggle Isolate/Unisolate`: isolate selection hoặc chuyển nhanh giữa isolate và visual unisolate. Phù hợp để gán phím tắt.
- `MH Isolate Selected`: isolate các Group/Component đang chọn.
- `MH Unisolate`: restore thật toàn bộ object về Tag gốc và xóa cache/temp Tag.
- `MH Show All Tags`: hiện tất cả Tag nhưng giữ cache MH Isolate.
- `Force Restore / Cleanup`: cố gắng restore state còn sót và dọn temp Tag của MH Isolate.

Có thể gán phím tắt trong `Window > Preferences > Shortcuts` của SketchUp.

## Lưu ý

- Temp Tag của MH Isolate có prefix `__MH_ISOLATE_TMP__`.
- Không nên tự xóa hoặc đổi tên temp Tag khi isolate/cache đang hoạt động.
- Visual unisolate chỉ làm mọi object hiện lại; object vẫn nằm trên temp Tag để lần isolate kế tiếp diễn ra nhanh.
- Dùng `MH Unisolate` trước khi cần chỉnh sửa hệ thống Tag thủ công hoặc muốn model trở về trạng thái Tag hoàn toàn bình thường.
- Đóng bảng MH Van không xóa cache dùng chung.
- Khi thoát SketchUp, plugin tự restore object về Tag gốc và xóa temp Tag.
- Nếu file đã được save trước lúc callback thoát chạy hoặc SketchUp bị crash, chỉ cần mở lại chính file `.skp` đó. Plugin tự phát hiện state còn lưu và recover; không cần mở file recovery riêng.
