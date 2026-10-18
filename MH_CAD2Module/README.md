# MH CAD2Module 0.5.5

Bản 0.5.5 sửa SP40: ghép chuỗi khoang mặt bằng không chồng lấn, giữ đường chia hợp lệ khi có thêm đường bao ứng viên, và gộp các vòng phụ trùng nhau của cùng một nẹp. Không cần nhập tên/mã SP khi quét; mỗi lần vẫn có mã nội bộ riêng.

Trong **Settings → Giai đoạn dựng**, mặc định chỉ tích **Mặt bằng**. App đo rộng, sâu và vị trí theo mặt bằng, dựng mỗi khoang cao tạm **1600 mm**, Z=0; chưa chia tầng ngang và chưa áp mẫu chia tầng đã học. Phần phụ đo được giữ riêng, cũng cao tạm 1600 mm. Hai ô tick tự lưu theo model và dùng lại lần sau. Quét chọn một mặt bằng riêng không cần kèm mặt đứng/mặt cắt.

**Quét trực tiếp trong SketchUp:** khối dựng ngay trên mặt bằng CAD đã quét, giữ tọa độ và mặt phẳng nguồn; không cần nhãn SP để đặt vị trí. Đọc DWG bằng đường dẫn vẫn căn theo nhãn SP. Nẹp sâu 50 mm trong chế độ Mặt bằng được dựng thành khối phụ đặc có chiều sâu bằng tủ bên cạnh theo yêu cầu người dùng; dữ liệu vẫn giữ số đo nguồn 50 mm để đối chiếu. Chiều cao khối phụ tạm 1600 mm.

Từ 0.4.2, **Quét chọn không cần nhập mã SP**: thả chuột hoàn tất vùng quét sẽ bắt đầu dựng. App tự tạo định danh để nối nguồn, tác vụ và lịch sử sửa; tên hiển thị là Vùng quét CAD. Mã này không tham gia chữ ký hình học hay cách đối chiếu kinh nghiệm. Kết quả cao tạm 1600 mm vẫn không dùng làm mẫu chiều cao thực. Quét lại cùng nguồn/giai đoạn đã dựng sẽ báo chọn khối hiện có để sửa, tránh dựng chồng lên nhau.

Tích thêm **Mặt đứng** để dùng luồng đầy đủ: **mặt bằng/mặt cắt bằng → chia khoang dọc → mặt đứng bỏ cánh + mặt cắt đứng chia tầng ngang**. Bật Mặt đứng tự bật Mặt bằng; bỏ Mặt bằng cũng bỏ Mặt đứng. Mặt đứng có cánh giữ riêng bằng nút **Mặt đứng đối chiếu**. Cao 1600 mm là giá trị tạm do người dùng chọn, không phải số đo CAD. Các khối đã dựng giữ nguyên khi đổi setting; app không tự ghi đè kết quả cũ.

SP01/2.dwg đã dựng 4 khối: dưới trái 729×600×2200, dưới phải 1502×582×2150, trên trái 729×600×443, trên phải 1502×582×443 mm. Thanh nẹp mặt 24 mm dùng ván 18 được đối chiếu mặt bằng và giữ riêng dạng khung dây, không tính vào module hay thay mẫu. Cả SP tính cả nẹp được căn tâm theo nhãn. Các độ dày tham khảo do người dùng cung cấp: 6, 8, 12, 15, 18, 25, 36; 36 có thể là ghép 2×18, không tự quyết định đường chia. Số đo hình học không bị làm tròn theo vật liệu.

Khối nóc bao đủ đế hai chân theo mặt cắt. Drawing1/SP60: khối nóc 1720×582×432 mm, Z=2160 mm; thùng riêng cao 382 mm, cánh cao 407 mm. Đáy chân thấp hơn đáy cánh 25 mm; đáy cánh chỉ giúp ghép đúng mặt cắt, không phải giới hạn khối.

Đường chia chân nóc phải có mối tiếp giáp các hình chữ nhật ở mặt đứng và không xuyên qua panel đứng liền trong mặt cắt tương ứng. Nếu hai hình không khớp, app báo cần kiểm tra, không dựng khối theo cao độ đó. Nét LINE ghép kín được kiểm tra cùng quy tắc.

Các khối ứng viên chồng nhau bị chặn ở cả bộ đọc và SketchUp trước khi dựng. Thiếu mặt bằng, mối ghép không khớp, hoặc phần nẹp không có nét đối chiếu sẽ chuyển sang Cần kiểm tra. Các bước chia dọc/ngang và ứng viên được giữ trong hồ sơ để xem nguyên nhân.

Plugin SketchUp 2025: tự đọc hình học CAD vuông góc, chia thành khối thùng và đặt theo nhãn SP. Không dùng AI, không gọi AutoCAD và không đọc số DIM làm kích thước.

## Dùng nhanh

Thanh công cụ có ba nút: **Nhập mã SP**, **Quét chọn**, **Quản lý**.

- **Nhập mã SP:** đọc các DWG/DXF đã nhớ trong Quản lý, tìm mã/tên trong khung bản vẽ rồi dựng. Có thể nhập nhiều mã, mỗi dòng một mã; Excel/CSV cũng đưa danh sách vào hộp này.
- **Quét chọn:** sau khi dán/import CAD vào SketchUp, kéo vùng bao đủ hình CAD của một SP theo giai đoạn đã chọn. App chỉ đọc cạnh trong vùng, tự lưu nguồn riêng rồi dựng ngay. Không cần nhập mã SP, DWG hoặc khung tên cho luồng này.
- **Quản lý:** nguồn đã lưu, thư viện, bản vẽ 2D phóng/thu, bằng chứng phân tích, lỗi, lịch sử và sửa kết quả.

Nhãn trong model là group có tên SP hoặc chữ Curic như SP01. Mã phải duy nhất. Tâm X của cả SP trùng tâm nhãn; mặt trước Y=0; sàn Z=0; rộng +X, sâu +Y, cao +Z. Module con giữ cao độ chân/diềm và vị trí trong sản phẩm. Nhãn không bị di chuyển. Dựng lại không tự ghi đè SP đang có.

Nếu nét đã explode mất thông tin chữ/ký hiệu, app chỉ tự phân loại khi các cụm hình học tách rời đủ rõ; không quay lại thuật toán chia mặt đứng trước khi thiếu mặt bằng. Leader mất thông tin loại đối tượng sau explode có thể không lọc được bằng ngữ nghĩa; vòng hình học vẫn phải qua kiểm tra. Khi nhập một mã SP, chỉ phân tích SP yêu cầu và dùng cache riêng để tránh xử lý các sản phẩm còn lại.

## Thư viện

Theo yêu cầu hiện tại, mặc định là `MH_CAD2Module/library` ngay cạnh code app. Nó chứa nguồn DWG/DXF hoặc nét CAD+SKP, cache, tác vụ, bản SKP trước/sau, lịch sử và kinh nghiệm. Nút **Chuyển** sao chép sang thư mục mày chọn rồi cập nhật đường dẫn; giữ bản cũ và từ chối dữ liệu đích trùng tên nhưng khác nội dung. Bản cập nhật RBZ không chứa thư viện người dùng.

Nguồn được nhận dạng bằng SHA256. Đổi tên, xóa hay sửa file gốc không xóa bản lưu. Đường dẫn nguồn được nhớ theo model/dự án; cấu hình gần nhất được dùng cho model mới. Mỗi lần dựng sẽ kiểm tra nội dung nguồn để dùng đúng phiên bản.

## Sửa và kinh nghiệm

Luồng mới trong **Quản lý → Sửa kết quả trên model**: chọn sản phẩm vừa dựng → **Sai** → vẽ các box đúng → chọn các box trong SketchUp → **Kết quả đúng**. Sai lưu kết quả cũ và tạm ẩn nó để vẽ. Mỗi box đúng là một Group hoặc Component riêng ở ngoài group sản phẩm; không cần tên, chỉnh gốc hoặc trục riêng. Không cần quét box riêng; bấm Kết quả đúng sẽ đọc các box đang chọn. Nếu chưa chọn box hợp lệ, app báo và giữ phiên sửa. App đo các đỉnh thực sau mọi phép biến đổi, chuẩn hóa cả bộ về vị trí sản phẩm, giữ vị trí tương đối. Các box cần đúng hướng hình học theo CAD; xoay trục riêng không ảnh hưởng, còn xoay thật hình hộp lệch hướng CAD sẽ được báo. Không nhận các box chồng lấn hoặc thiếu cạnh. Box mỏng có bề rộng/chiều sâu bằng độ dày ván chuẩn được giữ riêng làm phần phụ. Sau khi xác nhận, box gốc vẫn được giữ và ẩn; **Hủy sửa** hiện lại kết quả cũ.

Từ 0.5.4, **Sai** dùng đúng khối đang chọn hoặc duy nhất sản phẩm vừa dựng; không tự lấy một sản phẩm cũ bất kỳ. Thông báo sửa hiện rộng/sâu và số khoang nguồn. Trong Mặt bằng, bộ box lệch rộng/sâu quá tổng hai tấm 36 mm so với CAD sẽ bị chặn để kiểm tra gắn nhầm nguồn. Nếu các module giữ cùng bề rộng và có đối chiếu duy nhất, app giữ mặt X và mặt sau CAD khi thêm phần phụ/đổi chiều sâu; không cần căn gốc các box bằng tay. Khi chưa có mẫu khớp hình học, app nói rõ đang dùng thuật toán đo gốc.

Từ 0.5.3, app tự hỏi lại trạng thái mỗi 2 giây nếu chưa nhận được kết quả. Sau 8 giây, thông báo rõ chưa có phản hồi thay vì quay chờ mãi. App chỉ hỏi trạng thái, không tự gửi lại lệnh lưu. Nếu SketchUp xác nhận chưa nhận yêu cầu, app cho bấm gửi lại; mất kết nối hiển thị lỗi ngay. Nút **Làm mới** cũng kiểm tra yêu cầu đang chờ.

Từ 0.5.2, nút báo **Đang lưu…** ngay khi bấm và chặn bấm lặp. Khi lưu xong, nút đổi thành **Đã lưu kết quả**, kèm thông báo số module/phần phụ ngay bên dưới; không cần cuộn lên đầu cửa sổ. Lỗi chọn box hiển thị tại chỗ để chọn lại. Nút đã hoàn tất không hiện con trỏ chờ.

Trong chế độ **Mặt bằng**, các box đúng cần cùng mặt đáy, chưa chia tầng. Kinh nghiệm này chỉ dùng lại khi chữ ký hình học mặt bằng trùng khớp; lần dựng sau vẫn cao tạm 1600 mm. Nó không dùng làm mẫu chiều cao thực hoặc suy rộng sang mặt bằng khác kích thước/cấu tạo. Lịch sử lưu bản trước/sau và nguồn độc lập; chỉ bấm Kết quả đúng mới nhận mẫu.

Chọn SP/khối > **Sửa kết quả**. Bấm dòng module để chọn bên trong group. Có thể tách/gộp, đổi kích thước/vị trí, bổ sung hoặc xóa khối bằng công cụ SketchUp. Mỗi giao dịch được tự lưu; Undo/Redo cũng được ghi lại. **Kết thúc sửa** kiểm tra chồng lấn, căn tâm lại theo nhãn và nhận kết quả làm mẫu đúng. Thao tác ngoài chế độ sửa không trở thành kinh nghiệm.

Nếu chưa nhận dạng được SP, chọn SP cần kiểm tra trong bảng và Bắt đầu sửa: nhập kích thước đã xác minh để có khối đối chiếu, sau đó sửa. Vùng CAD đánh dấu bằng Shift+kéo được ghi là lỗi chưa giải quyết. Nó không tự trở thành bằng chứng đúng.

Kinh nghiệm ưu tiên mẫu có cùng chữ ký hình học. Từ bản 0.3.0, app còn rút quy tắc từ các mẫu đã chấp nhận để so khớp sản phẩm có cùng cấu tạo cạnh/tấm nhưng khác kích thước. Mỗi mặt khối phải liên kết được với cạnh hoặc tâm tấm trong CAD mới; từng khoang được đo riêng, giữ độ dày ván. Không so theo tên file/mã SP và không scale nguyên bộ khối. Mặt bằng, mặt đứng bỏ cánh và mặt cắt phải đồng thuận. Phần phụ giữ riêng và giữ liên kết với module.

Trong Quản lý, phần giải thích cho biết dùng lại hình học cũ, suy rộng từ mẫu nào, hoặc vì sao cần kiểm tra. Mẫu thiếu bộ phận (như SP27), các mẫu cho cách chia khác nhau, thay đổi cấu tạo/số tấm, thay độ dày ván hay thiếu mặt phẳng đối chiếu không được coi là kết quả tự động hoàn chỉnh. Đây là bộ quy tắc cho cấu tạo tương ứng; chưa suy ra tùy ý một hệ tủ khác số khoang hay chuyển biên dạng cong/tấm lồng.

Quy tắc dẫn xuất nằm trong `library/rules/`, tách khỏi lịch sử gốc và tự tạo lại khi cần. Mỗi lần Kết thúc sửa chấp nhận một kết quả mới, lần quét sau sẽ đọc thêm mẫu đó. Mẫu do thuật toán đề xuất chưa tự trở thành mẫu đã duyệt. App không tự sửa code; lịch sử giữ nguồn và SKP độc lập. Không bắt buộc đặt tên từng module hoặc căn khối mẫu bằng tay; các mẫu đã nhận được chuẩn hóa tọa độ và giữ cao độ từ CAD.

## Module mẫu

Trong chế độ sửa, chọn khối con > **Thay module mẫu SKP**. Mẫu SKP tĩnh phải cùng kích thước. Với mẫu parametric được chuyển bằng MH Module Studio, plugin dùng bộ dựng của Studio để đổi kích thước và kiểm tra lại, giữ độ dày ván. Mẫu có ràng buộc không đạt kích thước yêu cầu sẽ được báo và hoàn tác; không scale méo mẫu tĩnh.

## Phạm vi nhận dạng

Bản đầu nhận hệ panel/thùng nội thất vuông góc: LINE, polyline rectangle, vách đôi, nóc/đáy nối, vách đơn trong thùng trên và ghép mặt cắt để đo sâu. Không cần chữ “mặt đứng/mặt cắt”; khung mã SP cần thiết cho tìm tự động trong DWG, còn quét chọn trong SketchUp không cần khung mã.

Quét chọn hỗ trợ hình 2D trên mặt phẳng XY/XZ/YZ. Hình thiếu chiều sâu, Xref chưa bind, hình cong/chéo hoặc nhiều cấu tạo cùng bằng chứng được báo cần kiểm tra. Không có cam kết nhận mọi loại bản vẽ. Các khối là vỏ bao carcass; chân, cánh, diềm chưa được dựng thành từng tấm riêng ở giai đoạn này.

## Cài đặt và kiểm tra

Máy này đã có Python 3.12, ezdxf 1.4.3, openpyxl 3.1.5 và ODA File Converter. Trên máy khác cài `requirements.txt`, cài ODA nếu dùng DWG rồi chọn đường dẫn trong Quản lý khi tự tìm không được. Luồng quét nét không cần ODA.

Code đã nằm trong Plugins; restart SketchUp hoặc nạp loader để có menu Extensions > MH CAD2Module. Gói RBZ được tạo bởi `python tools/package.py`.

Phát triển: Spec Kit + Karpathy Guidelines + RuboCop/rubocop-sketchup. Chạy `tools/check.ps1` cho pytest/Ruby/RuboCop; `tools/ui_check.cjs` kiểm tra giao diện; công cụ native kiểm tra trong SketchUp rồi Undo để giữ model. Chi tiết trong TOOLING.md và specs/001-cad-to-module/validation.md.

0.5.6: Trong Settings → Phần phụ, ô **Tạo khối phụ (nẹp)** mặc định bật và tự nhớ lựa chọn. Bật để dựng nẹp thành box kín; tắt để bỏ qua nẹp ở lần dựng mới. Kích thước/vị trí module và vách/tấm chính vẫn giữ theo CAD. Thay đổi ô này không tự sửa các sản phẩm đã dựng hoặc tạo kinh nghiệm mới. Box do người dùng xác nhận bằng Kết quả đúng vẫn được nhận đầy đủ.

0.6.0: Dựng khối bo tròn theo mặt bằng bằng cạnh **ArcCurve**, lưu tâm/bán kính/góc quét để nhận và dựng lại kinh nghiệm đúng. Nhận cả khối bo đùn thẳng do người dùng chọn ở **Kết quả đúng**; không cần chỉnh trục/gốc riêng. CAD có cung ARC hoặc polyline bulge được đọc theo tọa độ tròn. Nguồn SP41 được đo đủ 2860×350 mm, góc R100. Giai đoạn mặt bằng vẫn cao tạm 1600 mm; hiện nhận một biên ngoài kín với cạnh thẳng theo CAD và cung tròn, chưa nhận spline, lỗ hoặc khối vát/xoắn.

0.6.1: Các module và phần phụ dựng mới là **Group riêng ở ngoài cùng model**, không có Group/Component bao cả sản phẩm. App nhớ các Group thuộc cùng SP để chọn, sửa và lưu kinh nghiệm. Chọn trực tiếp một Group hoặc bấm dòng module trong bảng. Gốc dựng lại từ kinh nghiệm lấy theo **toàn bộ vùng CAD import**, sửa lỗi SP42 lệch 2178 mm. Dữ liệu liên kết được lưu trong model khi mày Save SKP bình thường.

0.7.0: **App tự rút quy tắc mặt bằng**, không cần AI. Luồng vẫn là Sai → vẽ/chọn các khối đúng → Kết quả đúng. App lưu box và phản hồi trước, sau đó chạy học bằng tiến trình nền. Mục **Quy tắc tự học · Mặt bằng** cho biết số quy tắc đang dùng, chờ mẫu hoặc cần kiểm tra, kèm kích thước mẫu và lý do.

Quy tắc chỉ kích hoạt khi có ít nhất **3 hình học khác nhau cùng cấu tạo**, cùng cách chia khối và vượt kiểm thử giữ riêng từng mẫu. App học mặt chia gắn với cạnh/tâm tấm CAD, giữ độ dày và đo lại trên nguồn mới; không kéo giãn box theo tỷ lệ. Góc bo phải có cung tròn CAD xác nhận tâm/bán kính/góc quét. Nếu cách chia mâu thuẫn hoặc vị trí suy ra không thống nhất, app không dùng quy tắc đó. Mẫu đã xác nhận cùng hình học được ưu tiên trước quy tắc suy rộng.

Kinh nghiệm và các bản quy tắc nằm trong thư viện đã chọn (`rules/plan-v1/`), đi cùng khi chuyển thư viện. Mẫu đúng gốc không bị ghi đè. Học quy tắc không tự sửa khối hiện có; áp dụng khi quét/dựng lần sau. Giai đoạn này chỉ học mặt bằng, cao tạm 1600 mm; chưa suy rộng số khoang khác nhau hoặc chia tầng từ mặt đứng. Bốn mẫu mặt bằng hiện có thuộc bốn cấu tạo khác nhau, nên đang chờ thêm mẫu cùng cấu tạo để kích hoạt suy rộng; dựng lại cùng hình học vẫn dùng được mẫu đã xác nhận.


0.7.1: **Quá trình làm việc** gom các sự kiện theo từng lần quét/sản phẩm. SP quét không cần tên, hiển thị **Vừa quét SP không có mã** kèm thời gian. Bấm dòng để mở lịch sử quét, dựng, lỗi và sửa đã lưu; mở tiếp từng sự kiện để xem số module, kích thước/vị trí, nguồn, phương pháp, kinh nghiệm và bản SKP đối chiếu. Lịch sử của dòng đang mở không bị giới hạn 30 sự kiện.

Ngay dưới dòng mở có **Select → Sai → Kết quả đúng → Hủy sửa**, cùng các thao tác sửa khối. Select chọn tất cả khối đầu ra còn tồn tại của đúng SP, gồm phần phụ; không chọn CAD nguồn hoặc box gốc mày tự vẽ. Sai và thao tác sửa dùng đúng SP của dòng đó dù ngoài model đang chọn SP khác. Kết quả đúng giữ lựa chọn box bên ngoài để nhận, không tự Select lại khối cũ. Khối bị xóa hoặc dữ liệu cũ có nhiều bộ trùng nhau sẽ khóa thao tác thay vì chọn nhầm. SP chưa dựng nhưng có hình học để sửa vẫn có bước Khôi phục SP chưa dựng.

Các dòng/sự kiện cũ được đọc từ lịch sử hiện có, không viết lại. Sự kiện cũ không lưu đủ thông tin SP/phiên sửa sẽ không bị tự gán sang SP khác; không tạo lại các bước quét chưa từng được ghi. Trạng thái học và thư viện giữ nguyên.
