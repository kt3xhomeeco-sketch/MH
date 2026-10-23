# Thuật toán trước bộ quét OY

Đã commit app 0.10.1 trước khi sửa tại `069ed2b62564ec8ce4657959df81175d88fa50e4`.

`MH_CAD2Module-0.10.1-069ed2b.zip` là bản nguồn đúng commit đó: loader, worker,
nhận dạng cũ, AI, học quy tắc, giao diện, test và công cụ phát triển. JSON cùng tên
ghi SHA-256/số file. ZIP này không nằm trong RBZ mới. Thư viện CAD, box đúng,
lịch sử sửa và mô hình AI riêng máy vẫn nằm nguyên chỗ cũ, không nằm trong ZIP.

Để dùng lại, giải nén vào một thư mục khác và đọc README/TOOLING của bản cũ.
Cũng có thể lấy lại nguồn từ commit trên bằng `git archive`; không cần đặt lại
toàn bộ repository hay ghi đè plugin khác.

Luồng Mặt bằng mới không gọi bộ tìm/chọn mẫu AI hoặc bộ chuyển quy tắc chia cũ.
Các hàm hình học dùng chung cho bo tròn, biên giật cấp, kiểm tra khối và luồng
Mặt đứng vẫn được giữ khi còn cần. Mẫu xác nhận cũ được giữ để đối chiếu đúng
cùng hình học và nghiên cứu sau.
