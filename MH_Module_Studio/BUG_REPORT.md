# Mẫu mô tả lỗi — MH Module Studio

Chỉ điền phần liên quan; bỏ qua thông tin đã có trong yêu cầu. Mẫu này là đầu vào
cho việc tìm lỗi, không yêu cầu đọc thêm lịch sử feature hoặc toàn bộ dự án.

```text
Triệu chứng / thông báo lỗi:
Tính năng, màn hình, tên lệnh hoặc phím đã dùng:
Kết quả mong muốn:
Kết quả thực tế:
Các bước tái hiện tối thiểu:
1.
2.

Môi trường: phiên bản SketchUp / hệ điều hành / phiên bản plugin nếu có:
Bản code đang chạy: đường dẫn thực tế / bằng chứng source_location:
Bản code đang kiểm tra: đường dẫn checkout:
Đã xác nhận hai bản trùng nhau chưa? Nếu chưa, ghi "chưa xác minh":

Đối tượng liên quan: ID/PID, tên, tag/layer, group/component/cụm:
Đơn vị và hệ tọa độ; transform nếu có:
Kích thước / vị trí mong muốn → thực tế:
Lỗi xảy ra khi chọn một hay nhiều đối tượng? Có đang Edit group/component không?
Stack trace hoặc ảnh đúng lúc xảy ra lỗi, nếu có:

Phạm vi được giao: chỉ tìm lỗi / sửa lỗi / kiểm chứng:
File hoặc entrypoint đã khoanh vùng theo FEATURE_MAP và FLOW_MAP:
Kiểm tra đã chạy và kết quả:
Thông tin còn thiếu:
```

Để xác nhận bản đang chạy, có thể dùng Ruby Console trong SketchUp để xem
`source_location` của đúng phương thức liên quan. Ví dụ với lệnh Parametric:

```ruby
Sketchup.version
MH::ModuleStudio.method(:open_parametric).source_location
```

Ghi lại đường dẫn trả về và đối chiếu với file đang kiểm tra. Đường dẫn tìm thấy
trên ổ đĩa hoặc đường dẫn loader dự kiến chưa chứng minh đó là bản đang chạy.
Ví dụ trên chỉ xác nhận phương thức Parametric, không xác nhận mọi file của plugin.

Với lỗi hình học, dùng bản xuất collector chỉ chứa đối tượng bị ảnh hưởng và
tham chiếu gần nó; giữ ID, đơn vị, hệ tọa độ, transform, bounds và số đo cần so sánh.
Không gửi toàn bộ SKP/DWG hoặc toàn bộ hình học cho model. Nếu chưa có bằng chứng
runtime hoặc không tái hiện được trong SketchUp, ghi rõ giới hạn đó trong báo cáo.
