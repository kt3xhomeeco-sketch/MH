# Bảng ánh xạ tính năng → file — MH Module Studio

Cập nhật: **23/10/2026**.

Bảng tra nhanh theo thao tác hoặc màn hình. File đứng đầu mỗi ô là nơi nên xem trước; các file sau phụ trách phần xử lý liên quan. Đường dẫn tính từ thư mục `MH_Module_Studio/`.

| Tính năng / màn hình | File liên quan |
|---|---|
| Mở Studio / Học từ mẫu / Thử độ dày; menu và điều phối yêu cầu | [main.rb](main.rb) (`Panel#show`, `Panel#request`), [ui/index.html](ui/index.html), [ui/app.js](ui/app.js) |
| Mở màn hình Parametric | [main.rb](main.rb) (`open_parametric` → `Panel#show_parametric`), [ui/parametric.html](ui/parametric.html), [ui/parametric_window.js](ui/parametric_window.js), [ui/parametric_window.css](ui/parametric_window.css) |
| Đọc Dynamic Component và thu thập công thức ATT | [reader.rb](reader.rb), [dc_function_capture.rb](dc_function_capture.rb) |
| Phân tích và tính công thức ATT | [formulas.rb](formulas.rb), [formula_parser.rb](formula_parser.rb), [formula_math.rb](formula_math.rb) |
| Học tham số, dựng quy tắc kích thước và ràng buộc hình học | [parameters.rb](parameters.rb), [attribute_rules.rb](attribute_rules.rb), [rule_system.rb](rule_system.rb), [plane_solver.rb](plane_solver.rb) |
| Dựng dữ liệu bảng tham số và công thức có thể chỉnh sửa | [parametric.rb](parametric.rb) (`sheet`, `describe`), [parametric_sheet.rb](parametric_sheet.rb), [parametric_program.rb](parametric_program.rb) |
| Mở Thông số module / Module Options; chỉnh tham số chung khi chọn nhiều module | [module_options.rb](module_options.rb) (`show_options`, `ModuleOptions#request`: `change` / `changes`), [options_parameters.rb](options_parameters.rb), [update_work.rb](update_work.rb), [ui/module_options.html](ui/module_options.html), [ui/module_options.js](ui/module_options.js) |
| Đổi tên tham số và cập nhật các tham chiếu công thức | [parameter_rename.rb](parameter_rename.rb), [parametric.rb](parametric.rb), [parametric_model.rb](parametric_model.rb) |
| Nhận diện biến độ dày, chuẩn hóa T1/T2 | [thickness_symbols.rb](thickness_symbols.rb), [options_parameters.rb](options_parameters.rb) |
| Đọc lựa chọn LIST của DC và chuyển giá trị sang đơn vị dùng trong bảng tham số | [dc_options.rb](dc_options.rb), [parametric.rb](parametric.rb), [options_parameters.rb](options_parameters.rb) |
| Chạy Redraw từ menu hoặc phím tắt SketchUp | [main.rb](main.rb) (đăng ký lệnh) → [module_options.rb](module_options.rb) (`redraw_selected`) → [update_work.rb](update_work.rb) (`submit`) → [assembly.rb](assembly.rb) (`redraw`) |
| Chạy Redraw trong bảng Thông số module | [module_options.rb](module_options.rb) (`ModuleOptions#request`: `redraw`) → [update_work.rb](update_work.rb) (`submit`) → [assembly.rb](assembly.rb) (`redraw`) |
| Thực thi kế hoạch thay đổi hình học vào model | [runtime.rb](runtime.rb) (`apply_trial_update`, `apply_plan`), [scale_redraw.rb](scale_redraw.rb) (`apply`) |
| Tính lại hình học sau thao tác Scale | [scale_plan.rb](scale_plan.rb), [scale_redraw.rb](scale_redraw.rb), [geometry_motion.rb](geometry_motion.rb) |
| Thêm hoặc bớt chi tiết theo công thức COPY của DC | [dc_copies.rb](dc_copies.rb), [copy_runtime.rb](copy_runtime.rb) |
| Tạo liên kết thủ công, chọn mặt và chỉnh khoảng cách giữa module | [assembly_tool.rb](assembly_tool.rb), [assembly_face_picker.rb](assembly_face_picker.rb), [assembly_contacts.rb](assembly_contacts.rb), [assembly_math.rb](assembly_math.rb) |
| Tạo liên kết tự động từ các mặt bao của module được chọn | [assembly_auto_links.rb](assembly_auto_links.rb) (`selection`, `capture`, `create`), [assembly_inference.rb](assembly_inference.rb), [assembly.rb](assembly.rb) |
| Gom cụm module thành component, giữ danh tính độc lập khi sao chép | [assembly_containers.rb](assembly_containers.rb) (`group!`), [assembly.rb](assembly.rb) |
| Giữ quan hệ và kiểm tra kích thước tổng của cụm module | [assembly_envelope.rb](assembly_envelope.rb), [assembly_external.rb](assembly_external.rb), [assembly_math.rb](assembly_math.rb) |
| Hiển thị quan hệ, mặt tiếp xúc và điều khiển phiên liên kết | [assembly_hud.rb](assembly_hud.rb), [assembly_tree.rb](assembly_tree.rb), [contact_display.rb](contact_display.rb), [contact_view.rb](contact_view.rb) |
| Lưu hoặc nạp cụm module bằng SKP | [assembly_file.rb](assembly_file.rb), [assembly.rb](assembly.rb) |
| Mở thư viện, chọn thư mục và làm mới danh mục module | [library.rb](library.rb) (`Library#request`: `library_choose`, `library_refresh`), [library_catalog.rb](library_catalog.rb), [ui/library.js](ui/library.js) |
| Lưu module được chọn hoặc xuất module ra SKP | [library.rb](library.rb) (`save_selected`, `export`), [module_file.rb](module_file.rb); cụm được quản lý đi qua [assembly_file.rb](assembly_file.rb) (`save`) |
| Nạp module từ thư viện, chuẩn bị preview và phục hồi dữ liệu import hợp lệ | [library_import.rb](library_import.rb), [import_recovery.rb](import_recovery.rb) |
| Đặt module; dùng Shift để fit vào khoang hoặc khối đích | [library_hud.rb](library_hud.rb) (thao tác chuột / phím), [library.rb](library.rb) (`place`), [library_placement.rb](library_placement.rb) (`detect`, `place`, `fit_built`), [placement_math.rb](placement_math.rb) (`ray_region`), [import_links.rb](import_links.rb) (`ray_cavity`) |
| Dùng Ctrl để Replace module hoặc khối đích | [library_hud.rb](library_hud.rb), [library_placement.rb](library_placement.rb) |
| Chọn mẫu thư viện để Replace các đối tượng đang chọn | [library.rb](library.rb) (`Library#request`: `library_place`, `library_replace_selection`; có vùng chọn thì gọi `LibraryPlacement.replace_many`), [library_placement.rb](library_placement.rb) |
| Chuyển đổi hàng loạt thư viện DC sang module | [library_conversion.rb](library_conversion.rb), [dc_library_conversion.rb](dc_library_conversion.rb) |
| Tạo ảnh đại diện SKP và xử lý ảnh hiển thị trên HUD | [library_thumbnails.rb](library_thumbnails.rb), [hud_thumbnail.rb](hud_thumbnail.rb) |
| Theo dõi thay đổi danh mục thư viện | [library_monitor.rb](library_monitor.rb) (`poll`), [library.rb](library.rb) |
| Mở / thoát HUD thư viện | [main.rb](main.rb) (lệnh `Mở HUD`), [library_hud.rb](library_hud.rb) (`open_hud`), [library.rb](library.rb) (`Library#open_hud`, `library_hud_exit`) |
| Chọn bảng icon HUD, mở bảng bằng shortcut riêng | [main.rb](main.rb) (`sync_hud_board_commands`, `open_hud_board`), [library_hud.rb](library_hud.rb) (callback `select_board`), [hud_boards.rb](hud_boards.rb) (`current`) |
| Edit HUD: tạo / sửa bảng, sắp ô icon, dock, vị trí tự do và phím số | [library_hud.rb](library_hud.rb) (callback `edit`, `board`), [hud_boards.rb](hud_boards.rb) (`put`, `put_free`, `edit`), [library.rb](library.rb), [ui/hud_settings.js](ui/hud_settings.js) |
| Mở Cài đặt HUD; đổi cỡ vòng, khoảng cách, ảnh và vị trí hiển thị | [library_hud.rb](library_hud.rb) (`LibraryHUD#show_settings`, callback `settings`), [library.rb](library.rb) (`save_settings`), [ui/hud_settings.html](ui/hud_settings.html), [ui/hud_settings.js](ui/hud_settings.js), [ui/hud_settings.css](ui/hud_settings.css) |
| Import / Export config HUD | [library_hud.rb](library_hud.rb) (callback `import_config`, `export_config`) → [library.rb](library.rb) (`transfer_hud_config`, `import_hud_config`, `export_hud_config`) → [hud_config.rb](hud_config.rb) |

**Đọc tiếp:** tra lỗi theo [ERROR_MAP.md](ERROR_MAP.md) trước khi mở bảng này khi đã có thông báo lỗi; xem luồng liên quan trong [FLOW_MAP.md](FLOW_MAP.md); chỉ mở các dòng **Ownership** cần thiết trong [ARCHITECTURE.md](ARCHITECTURE.md) khi chưa rõ trách nhiệm. Giới hạn tìm lỗi ở [AGENTS.md](AGENTS.md); mẫu thu thập bằng chứng ở [BUG_REPORT.md](BUG_REPORT.md). Hướng dẫn phát triển chi tiết ở [DEVELOPMENT.md](DEVELOPMENT.md), chỉ đọc khi được giao triển khai.

**Căn cứ đối chiếu:** dùng hai tài liệu trên để xác định trách nhiệm từng thành phần, rồi kiểm tra mã đăng ký menu, tạo dialog và điều phối callback trong `main.rb`, `library.rb`, `module_options.rb`, `library_hud.rb`; kiểm tra khai báo hàm ở các file xử lý chính và liên kết tài nguyên trong HTML. Mọi đường dẫn trong bảng đều đã kiểm tra tồn tại. Các tên hàm và callback ghi trong bảng là điểm tra cứu mã, không phải tên lệnh người dùng phải nhập.

**Giới hạn:** đây là bản tra cứu tính năng, không phải báo cáo kiểm thử hành vi. Chưa đọc mọi nhánh xử lý của từng file hoặc xác minh giao diện, hình học, Undo và thao tác phím trực tiếp trong SketchUp.

Khi thêm, đổi tên hoặc chuyển file phụ trách một tính năng, cập nhật dòng tương ứng trong bảng này.
