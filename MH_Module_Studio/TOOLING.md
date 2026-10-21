# Công cụ phát triển MH Module Studio

Đã cấu hình ngày 14/10/2026 cho riêng MH_Module_Studio:

| Công cụ | Phiên bản | Vai trò |
| --- | --- | --- |
| Spec Kit / specify-cli | 1.2.0 | Đặc tả, kế hoạch, nhiệm vụ và đối chiếu yêu cầu |
| RuboCop | 1.92.0 | Kiểm tra Ruby về lỗi và bảo mật |
| rubocop-sketchup | 2.1.1 | Kiểm tra API, namespace và cấu trúc extension |
| Karpathy Guidelines | commit `2c606141936f` | Hướng dẫn viết, sửa và review code có phạm vi và tiêu chí kiểm chứng rõ |

Spec Kit nằm trong Python venv `.devtools/spec-kit`, tích hợp Codex tại
`.agents/skills/speckit-*`. Gems chạy bằng Ruby 3.2 bên ngoài SketchUp và được
ghim trong `Gemfile.lock`. Các công cụ này không chạy trong SketchUp và không
được đóng vào RBZ. Chúng hỗ trợ giảm lỗi, không bảo đảm plugin không có lỗi.

## Karpathy Guidelines

Đã cài skill cục bộ tại `.agents/skills/karpathy-guidelines/SKILL.md` từ
[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills/tree/2c606141936f1eeef17fa3043a72095b4765b9c2/skills/karpathy-guidelines).
Commit nguồn: `2c606141936f1eeef17fa3043a72095b4765b9c2`, cài ngày 14/10/2026.
Giữ nguyên nội dung skill; metadata nguồn khai báo giấy phép MIT.

`AGENTS.md` yêu cầu áp dụng bốn nguyên tắc khi phát triển: làm rõ giả định,
chọn giải pháp đơn giản, chỉ sửa phần cần thiết và kiểm chứng theo yêu cầu.
Spec Kit giữ đặc tả; skill hỗ trợ quyết định khi viết code; RuboCop và test
kiểm tra kết quả. Áp dụng tương xứng với công việc; yêu cầu của người dùng và
constitution của dự án được ưu tiên. Không thêm bước xin phép cho công việc
đã được cho phép hoặc viết test chỉ để lặp lại một thay đổi nhỏ.

Skill phục vụ Codex, không phải dependency của SketchUp. Không thêm các lệnh
cài plugin Claude/Cursor của repo vào app. Khi cập nhật, đọc thay đổi ở nguồn,
chọn commit cụ thể, cập nhật skill và commit ghi ở đây; không tự lấy `main`
trong lúc build. Mở MH_Module_Studio làm dự án Codex để nhận skill ở lượt tiếp
theo; các hướng dẫn trong AGENTS.md đã có thể áp dụng trong phiên hiện tại.

## Chạy kiểm tra

Mở PowerShell tại thư mục **MH_Module_Studio**, rồi chạy:

```powershell
bundle check
bundle exec ruby tools/check.rb
```

Lệnh kiểm tra chạy RuboCop trên 35 file Ruby phát hành, các test và công cụ Ruby,
sau đó chạy toàn bộ test Ruby. Để kiểm tra đúng cấu trúc RBZ, nó sao chép các
nguồn phát hành vào `outputs/lint-source`. Sửa nguồn gốc, không sửa bản sao này.
Cấu hình bật Lint, Security và toàn bộ các nhóm SketchUp; chưa áp đặt các luật
định dạng/độ phức tạp của RuboCop. Khi thêm file Ruby phát hành, cập nhật danh
sách trong `runtime_manifest.json`; kiểm tra và đóng gói dùng chung manifest.

Đóng gói bằng `python tools/package.py`: manifest tường minh 58 mục runtime,
không kèm Spec Kit, gems, dữ liệu kiểm tra hoặc script VBO. Giao diện được kiểm
tra bằng `test/ui_smoke.cjs`, `test/rules_ui_smoke.cjs`, `test/viewer_smoke.cjs`
và `test/parametric_window_smoke.cjs`, `test/module_options_smoke.cjs`, `test/library_ui_smoke.cjs`
chạy trong Electron phát triển; plugin phát hành không cần Electron.

Kiểm tra giao diện riêng: chạy `test/ui_smoke.cjs` bằng Electron. Electron
không phải dependency khi sử dụng plugin. Kiểm tra thực tế geometry, bản sao,
Undo và nạp extension vẫn cần chạy trong SketchUp 2025.

`core.rb` nạp 20 file tính toán độc lập với SketchUp. Vai trò từng file và hướng
phụ thuộc nằm trong `ARCHITECTURE.md`. Bộ kiểm tra ranh giới chạy một Ruby process
mới để bảo đảm lõi không kéo theo Reader/Runtime/giao diện hay API SketchUp,
kiểm tra việc tách lớp tính số/tọa độ/bảng và việc giữ độc lập dữ liệu giữa các
chức năng. Không sửa staging trong `outputs/lint-source`.

## Dùng Spec Kit với Codex

Mở thư mục **MH_Module_Studio** làm dự án Codex để nhận bộ skill cục bộ.
Nếu phiên đang mở chưa nhận skill mới thì mở phiên mới trong thư mục đó.
Với chức năng lớn, dùng lần lượt:

```text
$speckit-specify <mô tả chức năng và hành vi mong muốn>
$speckit-clarify
$speckit-plan
$speckit-tasks
$speckit-analyze
$speckit-implement
```

Quy tắc dự án đã điền tại `.specify/memory/constitution.md`: giữ phủ bì khi
đổi độ dày, cập nhật tấm phụ thuộc, không sửa DC gốc, lõi tính toán riêng và
không phụ thuộc MH_Superimp. Đặc tả mới sẽ nằm trong `specs/` của dự án này.
Chưa tạo đặc tả tính năng mới chỉ để hoàn thành việc cài công cụ.

Kiểm tra CLI và tích hợp:

```powershell
.\tools\specify.ps1 version
.\tools\specify.ps1 integration status --json
```

Wrapper giữ đúng thư mục dự án bằng `SPECIFY_INIT_DIR`. Spec Kit nhận `.specify`
trước Git root, nên không ghi đặc tả sang toàn bộ thư mục Plugins. Không cài
extension Git của Spec Kit, không tự tạo repository hoặc chuyển branch.

## Cài lại trên máy khác

Cần Python 3.11+ và Ruby 3.2 cùng Bundler. Từ MH_Module_Studio:

```powershell
python -m venv .devtools/spec-kit
.\.devtools\spec-kit\Scripts\python.exe -m pip install -r tools/requirements-spec-kit.txt
bundle install
```

Các template và skill đã được lưu trong dự án. Khi nâng phiên bản công cụ,
kiểm tra thay đổi, cập nhật file ghim phiên bản và chạy lại kiểm tra. Không chạy
lại `specify init --force` tùy tiện vì có thể ghi đè template đã chỉnh sửa.

Tài liệu chính thức: [Spec Kit](https://github.com/github/spec-kit),
[RuboCop SketchUp](https://github.com/SketchUp/rubocop-sketchup).
