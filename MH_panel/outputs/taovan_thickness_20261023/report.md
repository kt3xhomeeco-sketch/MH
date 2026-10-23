# MH_panel — Tạo ván copy thiếu độ dày, 2026-10-23

Đã tái hiện lỗi và sửa trong `src/tools/taovan.rb`. Nguồn có độ dày vật lý 17.6 mm nhưng definition-local chỉ 9.777778 mm do module cha scale 1.8 lần. Lệnh Tạo ván cũ lấy độ dày cục bộ rồi dùng trực tiếp để đùn tấm mới trong frame đích, tạo tấm chỉ dày 9.777778 mm.

## Bằng chứng source/runtime

- Pick giữ full transformation tại `src/tools/taovan.rb:286-301`, nhưng sampling cũ `cap_nhat_do_day` ở dòng 1002 không dùng nó.
- Sampling cũ gọi `Group.fix_scale(parent)` rồi `Board.calc_thickness(parent)`. Fix_scale chỉ bake scale của chính tấm, không bake scale của ancestor.
- `src/core/board.rb:2` delegate sang `MH_shared/geometry/board_analyzer.rb:10`, đo hai mặt lớn nhất của definition.
- Giá trị này vào `@do_day_khong_gian`; `calc_all_box_points` tạo vectors từ nó và `create_box` đùn hình thật bằng độ dài vector, dòng 733-735.
- Trước QA, hai phiên đều chưa nạp TaoVan. Theo chỉ định người dùng, coordinator nạp bản source này vào phiên Untitled PID30668, cổng VBO58922, model trống entities0/definitions0. Source_location của cap_nhat_do_day là file này dòng1002; Board.calc_thickness là src/core/board.rb dòng2. Phiên model có tên PID16708 không được dùng để thử hoặc sửa hình học.

## Bản sửa

- `src/tools/taovan.rb:1002`: lấy độ dày tự động qua helper mới; giữ nguyên độ dày nhập tay khi auto tắt.
- `auto_thickness_from_source` dòng1010: giữ policy nhận diện tấm hợp lệ cũ, lấy hai mặt chính; biến đổi vertices bằng full pick transform `@tr`; dựng hai mặt phẳng và kiểm tra song song; đo khoảng cách vuông góc bằng hai điểm thực trên mặt.
- `world_face_plane` dòng1037: helper cục bộ cho TaoVan, không thay API shared geometry.
- Không gọi fix_scale để lấy mẫu nữa; sampling không đổi geometry/transform của nguồn.
- Nếu không nhận diện được tấm hoặc transform hợp lệ thì dùng độ dày nhập tay như trước. Khi không có pick transform, fallback parent transformation.
- Không sửa Tạo cánh, quick-create, bảng cấu hình, ModuleStudio hoặc helper shared. Không đổi settings của người dùng.

## Native SketchUp trước/sau

Frame đo là world/model frame của các fixture root-level; đơn vị mm. Các trường hợp gọi real cap_nhat_do_day, calc_all_box_points và create_box (đùn hình thật), không thay thuật toán sampling hoặc extrusion. QA subclass chỉ thay một số helper preset/UI/material-code để không phụ thuộc thiết lập giao diện.

| Trường hợp | Nguồn vật lý | Trước: copied / created | Sau: copied / created | Source không đổi sau sampling |
|---|---:|---:|---:|---|
| Standalone | 17.6 | 17.6 / 17.6 | 17.6 / 17.6 | true |
| Scale của chính tấm 1.8 | 17.6 | 17.6 / 17.6 | 17.6 / 17.6 | true |
| Module cha scale 1.8 | 17.6 | 9.778 / 9.778, FAIL | 17.6 / 17.6, PASS | true |
| Cha xoay + mirror + nonuniform scale | 17.6 | 9.778 / 9.778, FAIL | 17.6 / 17.6, PASS | true |
| Auto tắt, nhập tay 9 | 17.6 | 9 / 9 | 9 / 9 | true |

Sau sửa: **5/5 PASS**, QA_CLEANUP entities0 definitions0, settings_same/selection_same/camera_same/materials_same đều true. Bản sửa đã được load vào Untitled. Không để lại tấm thử.

Bằng chứng đầy đủ: `mh-panel-thickness-before.json`, `mh-panel-thickness-after.json` cùng thư mục.

## Kiểm thử portable

- `ruby -c src/tools/taovan.rb`: Syntax OK, exit0.
- `ruby -c tools/native_taovan_thickness_check.rb`: Syntax OK, exit0.
- `ruby -c tools/test_taovan_auto_thickness.rb`: Syntax OK, exit0.
- `ruby tools/test_taovan_auto_thickness.rb`: **7 runs, 8 assertions, 0 failures, 0 errors, 0 skips**, exit0.

Các test kiểm tra ancestor/own scale, xoay/mirror/nonuniform transform, bbox.center lệch khỏi mặt phẳng, auto tắt không lấy mẫu, invalid-source fallback và thiếu pick-transform fallback. Test dùng host geometry doubles và gọi helper/method thật; không thay thế kết quả native.

## Files đọc/thay đổi và giới hạn

Thay đổi mã sản phẩm: chỉ đoạn sampling và hai helper mới trong `src/tools/taovan.rb` (diff đối chiếu baseline trước sửa). Thêm `tools/test_taovan_auto_thickness.rb` và `tools/native_taovan_thickness_check.rb`; các file JSON/Markdown ở thư mục này là bằng chứng QA. Các dirty edits có sẵn được giữ nguyên; baseline liên quan được lưu trong temp `mh-panel-thickness-baseline-20261023`.

Đã đọc các đoạn liên quan trong taovan.rb, main.rb, core/board.rb, group.rb, base.rb, geo_adapter.rb; mở rộng sang MH_shared/geometry/board_analyzer.rb, face.rb, axes.rb vì là dependency trực tiếp. Worker cũng đọc settings.rb để kiểm tra giá trị đang lưu, không ghi nó. Trước khi command được xác nhận, worker đã đọc thêm các đoạn taocanh.rb; nhánh này đã được dừng khi người dùng xác nhận Tạo ván. Không dùng findings Tạo cánh để quyết định bản sửa.

Native hiện kiểm tra fixture hình tấm phẳng độc lập trong Untitled, không trực tiếp sửa module thật của người dùng. Chưa kiểm tra thao tác click chuột, các preset/material/UI hoặc mọi trường hợp đang edit sâu trong scaled context. Phép thử không chứng minh mọi hình dạng ván đều được nhận diện; source không đủ điều kiện vẫn fallback manual theo policy.

## DeepSeek / ngân sách

Model duy nhất: **opencode/deepseek-v4.1-flash-free** qua OpenCode v2.1.3. Không dùng MCP DeepSeek/Codex worker cũ, không đổi sang Pro. OpenAI quyết định kế hoạch, rà diff và tự thực thi VBO native.

OpenCode session `ses_e98258f71ffetOo6AqvqiXDXn2` ghi nhận **65 lượt phản hồi model hoàn tất**; đếm từ completed assistant messages trong sanitized session export, không khẳng định đếm được retry ẩn của provider. Xem `worker_calls.json`. Số này vượt số lượt mềm giao qua prompt ở một số giai đoạn: OpenCode CLI không cung cấp hard model-call cap trong flags đang dùng và worker không tuân thủ hoàn toàn giới hạn prompt. Các continuation được cấp theo nhu cầu cụ thể: chỉnh fixture đúng direct faces/transform/cleanup, triển khai theo kết quả native, và đổi bbox center sang điểm thực trên mặt. Đây là hạn chế thực thi ngân sách cần ghi rõ, không coi workflow này là tối thiểu token.

Không xác minh được cưỡng chế DeepSeek context <=262144 hoặc setting effort riêng bằng CLI này; không thay đổi global OpenAI context. Không có lỗi credit/quota trong lượt Free. Không có worker còn chạy hoặc công việc sửa bắt buộc chưa xử lý.
