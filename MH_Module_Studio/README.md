# MH Module Studio — bản kiểm chứng 0.1

Plugin độc lập đọc module tủ/kệ và tạo quy tắc riêng để đổi các tấm bên trong.
Ưu tiên đúng độ dày, kích thước ATT cố định và liên kết. Phủ bì được thay đổi ở
các trục đầu ra đã xác minh. Library/HUD riêng hoạt động trong SketchUp.

## Tra cứu và tìm lỗi

Bắt đầu ở [AGENTS.md](AGENTS.md): đọc phần liên quan trong
[FEATURE_MAP.md](FEATURE_MAP.md) → [FLOW_MAP.md](FLOW_MAP.md), rồi chỉ xem
**Ownership** trong [ARCHITECTURE.md](ARCHITECTURE.md) khi cần. Dùng
[BUG_REPORT.md](BUG_REPORT.md) để bổ sung bằng chứng còn thiếu và xác nhận bản
SketchUp đang nạp. [DEVELOPMENT.md](DEVELOPMENT.md) dành cho công việc triển khai;
[CHANGELOG.md](CHANGELOG.md) giữ lịch sử feature và không thuộc ngữ cảnh tìm lỗi mặc định.

## Nhập thông số, đổi tên và lưu cụm (047)

Bảng **Thông số module** giữ nguyên ô nhập khi nhận kết quả; có thể nhập tiếp
trong lúc dựng hình. Các thay đổi đang chờ được gộp thành một lượt. Phần tính và
dựng hình vẫn chạy trên luồng SketchUp, nên module phức tạp vẫn cần thời gian.

Đổi tên module ở đầu bảng **Parametric**, đổi tên chi tiết ngay trong cột tên.
Nhấn Enter hoặc click ra ngoài để ghi tên; có thể bấm Lưu SKP ngay khi đang sửa
tên. Đổi tên vẫn giữ bản nhập biến chưa áp dụng. Công thức ATT giữ tham chiếu
gốc; tên hiển thị mới được lưu kèm quy tắc và đối tượng. File SKP mở trực tiếp
cũng đổi tên và lưu được, không cần chọn một đối tượng đang đặt trong model.

Chọn module hoặc component cụm đã **Gộp**, mở **Thông số module → Lưu SKP**;
hoặc đọc vào Parametric rồi **Lưu SKP**. Tên file mặc định theo tên module/cụm.
Đổi tên rồi lưu tạo file tên mới, giữ file cũ; ghi đè có bản sao `.mh-backups`.
Cụm lưu các module con, giá trị hiện tại và liên kết bên trong; import lại vẫn
sửa tham số/Scale được. Cụm còn liên kết ra ngoài cần tách liên kết đó trước khi
lưu độc lập. Parametric của cụm cho đổi tên các module con; sửa công thức chi
tiết bằng cách đọc riêng module con, sửa thông số chung/riêng trong Thông số module.

Chính sách 047 thay thế yêu cầu giữ cứng phủ bì ở các mục lịch sử 041/043/046:
T và kích thước ATT cố định được ưu tiên. Nẹp Bù giữ cạnh 50 mm; T = 20 mm cho
chiều sâu 70 mm, giảm T thì chiều sâu giảm theo. App chỉ cho trục không phải
đầu vào chỉnh sửa, đã chứng minh độc lập với kích thước cha, đi theo hình học.
Mục tiêu Scale chủ động và khoảng cách liên kết vẫn phải thỏa đồng thời.

Bổ sung 048 sửa trường hợp **T vượt cạnh 50 mm** của Nẹp Bù: T = 80 mm cho
phủ bì 80 × 130 × chiều cao hiện tại, vẫn giữ hai cạnh cấu tạo 50 mm. Giảm T
thì phủ bì thu lại. Lưu/import lại hoặc Scale tiếp vẫn giữ đúng tham số; chiều
dày được ưu tiên khi vượt cạnh, không dùng phủ bì cũ để chặn thao tác đó.

Bổ sung 049 cho **cụm liên kết**: nhớ riêng mốc phủ bì, thử điều chỉnh các chiều
tự do của module con trước khi nới cụm. Với cụm khung/cánh/chân bệ đã kiểm tra,
đổi T qua 17.6 → 200 → 17.6 → 20 vẫn giữ sâu 600 mm và đủ tám liên kết. Cụm
chỉ có tấm cố định, không có chiều tự do, vẫn theo đúng T; kết quả nới tạm không
ghi đè mốc đã nhớ. Scale cụm sang 660 mm thì những lần sửa T sau dùng mốc 660.

## Ưu tiên ATT

1. Chọn group/component cha còn nguyên DC rồi **Đọc từ SketchUp** ở chế độ tự đọc.
   Có thể **Mở file SKP** qua bridge mà không chèn file vào model.
2. Bấm **Tổng hợp quy tắc module**. Với DC có công thức được hỗ trợ, một mẫu đã
   đủ. App đọc ATT ở module cha, group trung gian và từng tấm, áp dụng thuộc tính
   trên instance đè lên definition.
3. Kiểm tra nguồn **ATT** hoặc **So sánh mẫu** trên từng tham số. Danh sách công
   thức phân biệt **đã dịch** và **đọc được, chưa dịch**. Công thức còn thiếu hoặc
   chưa hỗ trợ được báo lý do; lúc đó mới dùng so sánh như phương án bổ sung.
4. Nếu cần so sánh, đọc 2–20 trạng thái cùng module: mỗi nhóm học độ dày giữ các
   đầu vào DC khác cố định. Hai trạng thái đề xuất tuyến tính; mức thứ ba và tổ
   hợp độc lập giúp kiểm tra quy tắc. Không đổi phủ bì/cấu trúc trong nhóm này.
5. **Lưu bộ quy tắc** lưu toàn bộ tham số, trạng thái và chương trình công thức
   riêng của app trong `*.mhmodule.json`. Dự án một tham số cũ vẫn mở được.

Trình dịch riêng hỗ trợ biểu thức số, `+ - * /`, so sánh, `IF`, `AND`, `OR`, `NOT`,
`MIN`, `MAX`, `ABS`, tham chiếu cùng group, `parent!…` và tên group duy nhất.
Các công thức được tính lại cho giá trị mới, kể cả nhánh điều kiện và phi tuyến
được hỗ trợ. Hệ số thăm dò chỉ dùng để nhận diện đầu vào/hiển thị hướng chuyển
động, không dùng thay công thức để chỉnh hình học. Kích thước cha lấy từ hình
học hiện tại, không ép theo cache DC có thể cũ sau stretch.

## Thử tham số

### Bổ sung ngăn kéo (036)

Đã xử lý nét viền/ray 2D có chiều bằng 0, công thức qua group có Scale,
chiều dài ray dạng danh sách số lưu trong chuỗi và chỉ số `COPY` theo từng
instance. Các nét phụ giữ hình học gốc khi di chuyển; chi tiết đặc chưa xác minh
chỉ được tịnh tiến. Kích thước mới vẫn phải qua kiểm tra phủ bì và giao tấm.

Theo báo cáo nguồn MH, thư viện `D:/Cong viec/Sketchup/DC/Modul_studio` đã
chuyển **110/227** mẫu, gồm **25 mẫu ngăn kéo** bổ sung và **3.CC Chân bệ**. Cả 25 mẫu
ngăn kéo đã được import lại và thử đổi độ
dày trong SketchUp. Trong nhóm ngăn kéo vừa thử, 4 mẫu còn bị chặn do công thức
không khớp hình gốc, công thức thiếu giá trị hoặc cấu trúc xoay chưa hỗ trợ;
xem `.conversion/report.md` trong thư viện. File nguồn DC được giữ nguyên.

Mở Library, tìm tên mẫu rồi import để dùng bản có quy tắc riêng. Component DC
gốc đang chọn không tự biến thành bản Studio. Các tham số làm đổi topology,
số lượng, góc xoay hoặc phá phủ bì không được cho phép vẫn có thể bị từ chối.

### ATT theo điều kiện và hai mẫu bổ sung (038–039)

Đầu vào nằm trong nhánh IF/MIN/ROUND được nhận diện từ cây tham chiếu ATT,
kể cả khi thay đổi nhỏ chưa làm hình học chuyển động. App tính lại công thức
gốc cho mỗi giá trị, không lấy hệ số thăm dò làm công thức thay thế. Ẩn/hiện
các chi tiết có sẵn được hỗ trợ trên chương trình đọc mới từ SketchUp; chi tiết
hiện lại được dựng đúng theo các tham số hiện tại. Tag tắt vẫn được giữ tắt.
Kích thước suy biến, giao tấm mới, thay đổi số lượng hoặc góc xoay vẫn bị chặn.
Nếu chương trình cũ thiếu dữ liệu ẩn/hiện riêng, đọc lại DC nguồn từ SketchUp.

Đã bổ sung **Hộp Treo -2 Dọc** và **Nóc 2 Thân** từ folder `DC/Dat` vào
`DC/Modul_studio`. Đây là hai nguồn bổ sung, không cộng vào mẫu số 227 của
folder MH. Hộp Treo xử lý tên tấm trùng, ATT STRING mang đơn vị chiều dài và
đáy ghép từ mặt/nhóm con. Đổi độ dày vẫn giữ phủ bì 800x450x500 của mẫu đã thử.

Nóc 2 Thân có chiều cao nguồn ở chế độ **VIEW**, phụ thuộc chính xác vào hai
lớp ván. App chỉ cho trục được chứng minh bằng công thức thay đổi theo quy tắc
này; rộng và sâu vẫn giữ 400x350. Ván 18,6 mm cho tổng cao 37,2 mm; ván 20 mm
cho tổng cao 40 mm. Không mở khóa phủ bì chung cho các module khác.

Đã thử đổi độ dày nhiều lần, Scale lặp, Undo, bản sao độc lập, lưu SKP và import
lại trong Untitled. File nguồn và hai DC gốc giữ nguyên. Mở Library, làm mới và
tìm tên hai mẫu; hoặc chọn DC nguồn rồi Đọc từ SketchUp để học bộ quy tắc mới.
HUD cũng xử lý chênh lệch tỉ lệ pixel giữa API và viewport thực tế (đã gặp 250%).

Lượt rà lại 039 chuyển thêm 14 nguồn MH (nhóm cánh kính, pano và một số mẫu
khác), từng bản đều được import lại và thử chỉnh tham số trong SketchUp.
117 nguồn MH còn lại giữ chẩn đoán trong `.conversion/report.md`; không đổi
file nguồn hoặc ghi đè những bản thư viện người dùng đã tùy biến.

Nút **Tạo model** nằm ngay cạnh **Lưu quy tắc** trong bảng chính. Sau khi đọc /
mở bộ quy tắc và áp dụng bảng biến, bấm nút để dựng model thật từ các tấm hộp
đã xác minh, kể cả khi model SketchUp đang trống. Nút dùng các biến đã lưu và
công thức chi tiết hiện tại; lựa chọn tick không loại bỏ giá trị nội bộ khỏi
phép tính lúc dựng. Các bản nhập chưa áp dụng trong cửa sổ Parametric chưa được
dùng để tạo model. Component cha và từng tấm được dựng mới tại tọa độ của module
đã đọc, được chọn và gắn bộ quy tắc/khóa chi tiết/giá trị tham số riêng. Có thể
dùng Move của SketchUp để đặt lại vị trí, đọc lại hoặc Cập nhật bằng quy tắc đã
lưu. Không cần chọn DC nguồn, không sửa file SKP nguồn hoặc các object có sẵn.
Chi tiết khác dạng hộp phải dùng bản nguồn để tạo bản thử, không thay bằng hộp
ước lượng. Sau khi tạo, bảng **Thông số module** mở thành cửa sổ nổi riêng trên
màn hình SketchUp, hoạt động cả khi Studio đóng. Chọn object khác để bảng theo
lựa chọn. Mở lại bằng chuột phải module → **Thông số module**, hoặc Extensions
→ **MH Module Studio · Thông số module**.

Bảng chỉ có ảnh/tên module và các dòng tham số sát nhau. Giá trị hợp lệ tự áp
dụng sau 300 ms ngừng nhập; Enter/đổi ô áp dụng ngay. Không có nút Áp dụng, phủ
bì hay thông tin phụ thường trực. Nhập sai hoặc quy tắc xung đột giữ lại nội
dung để sửa và không nhận hình học lỗi. Bảng kiểm tra root PID/model/quy tắc để
không áp một thay đổi đang chờ sang object mới. Undo/Redo đọc lại giá trị từ
object. Biến tính bằng công thức chỉ đọc; sửa các biến đầu vào của công thức.

1. Chọn module ở cấp model, thoát chế độ sửa group/component.
2. Bấm **PARAMETRIC** để mở cửa sổ riêng. Tick các tham số cần hiện trong bảng nhỏ,
   nhập giá trị/công thức rồi **Áp dụng bảng biến** và **Xem trước**.
   Chưa sửa model ở bước này.
3. **Tạo bản thử bên cạnh** tạo bản sao với các definition riêng, bỏ DC/ABF trên
   bản sao rồi áp dụng bộ quy tắc. Nguồn vẫn nguyên vẹn.
4. Chọn bản thử để **Cập nhật bản thử đang chọn**. Chương trình công thức, quy
   tắc, toàn bộ giá trị nội bộ và các tham số được tick lưu trên object cha trong
   dictionary `MH_Module_Studio`. Bản sao mới được nhận diện lại theo PID.

Cột tick không có tiêu đề, chỉ hiện/ẩn dòng trong **Thông số module**. Tham số
không tick vẫn được lưu, được sửa trong Parametric và tham gia tính toán. Các
khóa `exported` / `exposed_parameter_keys` cũ giữ để đọc dự án cũ, dùng làm cờ
hiển thị; chúng không còn cấp quyền sửa/tính hình học. Biến chưa có quy tắc
điều khiển vẫn chỉ đọc vì chưa dịch được công thức, không phụ thuộc vào tick.
Khi lưu bảng biến/lựa chọn tick, module sở hữu cùng rule ID đang chọn được cập
nhật cờ hiển thị, giữ riêng giá trị/công thức instance và hình học hiện tại.
Mỗi tấm được biến đổi một lần bằng
kế hoạch tổng hợp cuối. Kiểm tra phủ bì, kích thước và giao nhau mới; hủy thao tác
nếu hình học sau sửa không khớp. Tạo/cập nhật dùng một transaction SketchUp.

## Giới hạn hiện tại

- Đường ATT hỗ trợ các group cùng phương trục, kể cả trục lật gương. Có thể đổi kích
  thước group bao chứa tấm thường, kể cả group trùng tên nhờ ID cây riêng.
- Công thức hình học bên dưới group đang scale (trừ kích thước nominal cha đã
  xác minh và biểu thức cộng/trừ khoảng hở), xoay lệch trục, scale ở module cha,
  gốc hình học lệch trục, tham chiếu mơ hồ, hàm không hỗ trợ hoặc bị mã hóa và
  hình học không khớp công thức sẽ báo lỗi/đề nghị so sánh. Không thực thi Ruby
  từ ATT, không giải mã ABF, không gọi cơ chế redraw DC.
- Chưa cho đổi số lượng, hiện/ẩn hoặc góc xoay theo tham số. Công thức vật liệu,
  text, animation không được dùng để sửa hình học trong bản này.
- Chỉ áp dụng lên hộp đã xác minh bằng đỉnh/mặt thật: 6 mặt tứ giác, 12 cạnh,
  8 đỉnh. Tấm cong, khoét, soi rãnh hoặc shear chưa được tự biến đổi.
- Bridge trả bounds/counts: đọc được quy tắc nhưng không chứng nhận hộp từ
  bounds. Khi thử trong SketchUp, app xác minh hình học thật một lần nữa.
- So sánh vẫn giới hạn ở các độ dày khớp hình học; chưa học mọi đầu vào DC tùy ý.
- Giới hạn 600 chi tiết và 1200 group/component; đọc SKP timeout 60 giây.
- Chưa khôi phục module bị Explode; chưa khóa phím A–Z hoặc có desktop app.

## Mở và bộ đọc SKP

Mở **Extensions → MH Module Studio → Học từ mẫu / Thử độ dày** trong SketchUp 2025.
File phát hành nằm trong `outputs/MH_Module_Studio-0.1.0.rbz`.

Bridge tự tìm tại `%USERPROFILE%/Documents/MH_Apps/MH_Thongke_Desktop/bin/`
hoặc `MH_SkpBridge/bin/`, tên `MH_SkpBridge.exe`; có thể cấu hình bằng biến
`MH_MODULE_STUDIO_BRIDGE`. Giữ các DLL SDK đi kèm. Không phụ thuộc MH_Superimp.

## Kiểm tra phát triển

Dùng `bundle exec ruby tools/check.rb` cho RuboCop/SketchUp và toàn bộ test Ruby.
Chạy `test/ui_smoke.cjs` bằng Electron cho giao diện. Công cụ Spec Kit và gems
không nằm trong RBZ; xem [TOOLING.md](TOOLING.md).

Kiểm tra native ATT ngày 14/10/2026: một DC thực có 48 công thức đọc được,
29 công thức dùng trong chương trình hình học và 5 đầu vào chỉnh được. Đã xem
trước, tạo và cập nhật bản thử qua VBO; giữ phủ bì 600 × 500 × 850 mm, metadata
đúng và nguồn không đổi. Bản kiểm tra cùng các definition riêng đã được dọn.
Undo không được xác nhận qua bridge; không tính kiểm tra portable là kiểm tra
native. Báo cáo chi tiết nằm trong `outputs/att-native-*.json`.

## Parametric và quy tắc vị trí

Parametric mở trong cửa sổ riêng, giữ nguyên khung 3D ở cửa sổ chính. Bảng liền
mạch theo mockup đã duyệt: nhóm Biến module và Thông số các chi tiết ngăn bằng
dòng highlight xám, có nút thu/mở; dấu ＋ thêm biến. Ô nhập có viền khi chọn.
Nhóm biến
có tick hiện/ẩn, tên biến, ký hiệu, tính chất, giá trị, đơn vị, công thức và trạng
thái. Thêm/xóa biến riêng; biến ATT đang gắn quy tắc gốc không xóa trực tiếp.
Biến đang được tham chiếu phải sửa các công thức dùng nó trước khi xóa.
Ký hiệu mới giữ khóa ATT gốc; công thức riêng có thể dùng biến mới để điều khiển
đầu vào đã dịch, ví dụ `co_so + 0.6` cho độ dày ván. Áp dụng bảng biến lưu vào
bộ quy tắc trong app; Lưu bộ quy tắc ghi file, Tạo/Cập nhật ghi lên bản thử.

Các tính chất gồm kích thước, vị trí, góc xoay, Copies, Copy, ẩn/hiện, vật liệu,
thông tin, tương tác, số, chuỗi và đúng/sai. Đây là phân loại dữ liệu: Copy/xoay/
vật liệu/ẩn/hiện/onClick chưa được thực thi để sửa 3D; chuỗi/tương tác giữ dưới
dạng dữ liệu. Không chạy script nhập từ ATT. Công thức số dùng bộ phân tích an
toàn hiện có, phát hiện vòng lặp, tham chiếu mất và giá trị ngoài phạm vi.

Bảng dưới có mỗi tấm một dòng với Dài/LenX, Rộng/LenY, Cao/LenZ và X/Y/Z (mm)
theo trục module, cập nhật theo nguồn/kết quả xem trước. X/Y/Z là góc nhỏ nhất
của hộp tấm, không giả làm origin của group đã xoay. Ô hiện số và dấu ƒ khi có
công thức, giống ATT; double click mở ô nhập công thức ngay tại chỗ. Enter hoặc
✓ lưu và tính lại bản xem trước; Esc hoặc × hủy. Để trống khôi phục quy tắc gốc.
Công thức dùng mm, ký hiệu biến, `Module.LenX/LenY/LenZ` hoặc `Parent!giang`,
và LenX/LenY/LenZ/X/Y/Z của chính chi tiết. Ví dụ `giang + 10` cho chiều cao giằng.
Hỗ trợ IF, MIN, MAX, ABS và phép tính của bộ phân tích an toàn. Phát hiện vòng
lặp, biến mất, xung đột quy tắc, va chạm mới và đổi phủ bì trước khi nhận thay đổi.
Công thức sửa lưu trong `part_formulas` của quy tắc riêng, đi cùng bản thử và
được phục hồi khi đọc lại. Không sửa ATT/model nguồn; Tạo bản thử/Cập nhật mới
ghi hình học. Áp dụng/đọc lại bản nhập biến trước khi sửa công thức chi tiết.
Công thức rút gọn từ ATT tính cả group bao chứa và dùng ký hiệu biến đã đổi tên;
không đoán quan hệ từ các số bằng nhau. ATT gốc chưa rút gọn được giữ theo phạm
vi group trong vùng xem nguồn; editor báo rõ và cho nhập công thức thay thế
trong trục module, không thực thi nhầm biểu thức của object cha trong tấm con.
Mục ATT bổ sung giữ thuộc tính của module/group trung gian/tấm con. Các tên group
trùng như NOC1 được phân biệt bằng ID trong cây; không dùng tên để gộp công thức.
Các trường đo phủ bì giữ chỉ đọc, phù hợp với MH_stretch. Đầu vào có quy tắc
điều khiển được sửa dù tick tắt; tick chỉ quyết định hiện trong bảng nhỏ. Nút
Xem trước tính lại toàn bộ thuộc tính và 3D; Tạo
bản thử/Cập nhật dùng bản riêng. Các nhóm dùng chung thanh cuộn, không chia thành
hai khung. Các thuộc tính ATT chỉ đọc vẫn đầy đủ trong nhóm thu gọn phía dưới.

Chọn một tấm trong cây hoặc 3D mở Quy tắc module, nhóm Vị trí & kích thước.
Các khoảng cách chỉ rõ mặt/mép tham chiếu, số mm hiện tại, công thức rút gọn chính
xác từ ATT và các đầu vào liên quan. Ví dụ mặt sau Giằng Sau cách mép sau hông
`Hậu dày + Hậu lùi`; 8+18=26 mm, đổi hậu 10 thành 28 mm. Bấm tham số để sửa ở
Parametric trong cửa sổ riêng và chọn đúng biến. Các dòng vị trí là
mô tả của bộ máy hiện có, không thêm ràng buộc cố định 26 mm. Biểu thức có điều
kiện/không tuyến tính giữ ATT gốc và hiển thị số đo, không đoán công thức tuyến tính.

Đã kiểm tra native module thực: 5 đầu vào, 46 thuộc tính DC bổ sung và 54 thông
số vị trí/kích thước của 6 tấm. Thử đồng thời ván 20, giằng 100, hậu 10, lùi hậu
20, rãnh 7: lùi mặt sau giằng 30 mm; cập nhật hậu 11/giằng 80 cho lùi 31 mm.
Phủ bì 600×500×850 mm, đọc lại bản thường khôi phục quy tắc/thuộc tính, nguồn giữ
nguyên. Báo cáo `outputs/native-parametric-report.json`; Undo qua VBO chưa xác nhận.

## Khung 3D và giao diện mới

Khung 3D liên tục toàn chiều rộng; cây MODULE nằm nổi bên trái trong viewport,
bảng tham số/quan hệ nổi bên phải. Các nhánh chi tiết, tham số và công thức ATT
thu/mở độc lập. Cột tick vẫn không
có tên. Hình nguồn hiện ngay sau khi đọc; chọn Module đã đọc / Kết quả xem trước
để đổi hình đang xem. Mục Trạng thái đã đọc có nút Xem 3D cho từng trạng thái.

Mặt đặc mặc định, màu đánh dấu cũng đặc; cạnh khuất được kiểm tra độ sâu.
X-ray là chế độ nhìn xuyên bật riêng. Có nút Cạnh, chọn phối cảnh/song song,
Trước/Sau/Trái/Phải/Trên/Dưới, Vừa khung và phóng lớn khung 3D; Esc thu khung lại. Kéo để xoay,
Shift hoặc kéo chuột phải để dịch, cuộn để zoom. Bản tính vẫn dùng hộp bao đã đọc;
giao diện không giả định đã nhập mesh chi tiết của tấm khoét.

Viewer chạy offline bằng WebGL; khi không có WebGL dùng bộ vẽ software có kiểm
tra độ sâu. Kiểm tra điểm ảnh nằm trong `test/viewer_smoke.cjs`, chạy bằng Electron
như `test/ui_smoke.cjs`. Không cần Electron hoặc tải thư viện mạng khi dùng plugin.

Cube góc nhìn có đủ sáu mặt, xoay theo camera; bấm mặt để nhìn vuông góc, hoặc kéo
cube để xoay model và lộ mặt khuất. Các mặt khác cũng chọn được từ menu Góc nhìn.

## Hệ quy tắc chung

Đọc một group thường tự đề xuất tham số độ dày và tiếp xúc mặt. Các mặt đối diện
cần có vùng chồng lên nhau và sai số ≤0,15 mm; cạnh/chạm góc không được coi là
tiếp xúc mặt. Tên chỉ dùng để hiển thị. Mặt được nhận dạng bằng khóa tấm, trục và
phía −/＋. Thay độ dày giữ mặt ngoài, mặt giữa hoặc mặt do người dùng chọn;
tấm liên quan bám theo, giữ phủ bì hiện tại kể cả sau MH_stretch.

Group có ATT được chuyển thành `module_rule_system` cùng giao diện với group
thường. Bộ máy công thức ATT riêng của app vẫn ưu tiên và tính lại giá trị mới.
Các quan hệ hình học nhận diện trên DC chỉ tham khảo cho tới khi bật Điều khiển.
Công thức chưa dịch hiển thị cảnh báo; app không chạy mã Ruby/ABF nhập vào.

Chọn quan hệ trong cây để sửa loại, mặt, khoảng cách, hướng chủ→theo hoặc bật/tắt.
Có thể chọn mặt trực tiếp trên 3D. Các loại hiện có: độ dày/giữ mặt, cố định mặt,
áp mặt, khoảng lệch, căn mặt, nằm giữa hai mốc và căn giữa. Công thức ATT xem trong
cây; sửa đầu vào của công thức ở Thử tham số. Giải xung đột, kích thước dương,
phủ bì và giao tấm được kiểm tra trước khi tạo/cập nhật bản thử.

Quy tắc và các ô tick được ghi vào bản thử; đọc lại bản thử khôi phục cùng hệ,
không suy đoán lại ATT đã được gỡ khỏi bản riêng. Dự án tham số cũ được mở theo
hệ mới; bộ học một biến cũ cũng được quy đổi và giữ hiệu ứng đã học. Phạm vi hiện tại là tấm hộp thẳng theo
trục module; đây chưa phải bộ giải sketch/solid/joint tổng quát của CAD.

Kiểm tra native hệ chung ngày 14/10/2026 qua VBO: DC thực 5 đầu vào/29 công thức,
group thường 5 tấm/6 quan hệ tiếp xúc. Đáy giảm từ 564 xuống 560 rồi 556 mm khi
đổi ván 18→20→22 mm, phủ bì giữ 600×500×850 mm; nguồn không đổi. Báo cáo
`outputs/native-rules-report.json`; Undo qua VBO chưa được xác nhận.


## Sửa rãnh soi và cấu trúc model (014)

Tạo model dựng component cha và các tấm group con. Tấm theo công thức ATT có
thể chạm phủ bì rồi thu lại, không tự bị khóa sau lần chạm đó. Mối ghép rãnh
đã giao nhau trong mẫu ATT có thể về độ sâu 0 rồi tăng lại; quy tắc tự sửa
không được dùng ngoại lệ này. Giá trị làm đổi phủ bì hoặc tạo giao nhau giữa
cặp tấm mới bị từ chối trước khi sửa model/lưu thông số. Mặt cố định do người
dùng đặt và quy tắc hình học vẫn giữ hiệu lực.


## Đọc hàm trong thư viện MH (016)

Đã khảo sát 227 SKP trong thư viện MH: 42 file biên dịch được quy tắc ATT,
so với 18 trước nâng cấp. Đây là số file có quy tắc, không bảo đảm mọi ATT hoặc
mọi loại hình học trong file đều sửa được. Xem báo cáo phát triển
`outputs/library-016/coverage.md` để biết từng file và giới hạn còn lại.

27 hàm tên riêng đã xác minh đọc kích thước danh nghĩa cha được dịch thành
tham chiếu trong bộ tính của app. Khi đọc trực tiếp DC đã được SketchUp nạp,
bộ đọc cũng nhận tên hàm mới nếu toàn bộ cấu trúc hàm khớp đúng mẫu đã xác minh.
Ánh xạ được lưu cùng chương trình ATT, nên quy tắc đã xuất tính độc lập với ABF.
Không thực thi hàm nhập vào và không đoán công thức từ một giá trị cache.
Hàm chưa nạp/chưa xác minh vẫn có thể chặn file đọc qua SDK.

Đã thêm SMALLEST/LARGEST, ROUND, CEILING/FLOOR, SQRT, ISEVEN, CHOOSE,
SIN/COS/TAN (góc độ), PI, TRUE/FALSE trong biểu thức số. Tấm con yêu cầu kích
thước danh nghĩa cha không bị nhân thêm scale của nhóm bao chứa lần thứ hai.
Nhánh cố định được rút gọn thành công thức trong bảng chi tiết/quy tắc module;
nhánh phụ thuộc đầu vào vẫn giữ ATT gốc. Quy tắc vị trí cũ tự nâng mô tả lên v2.

Các tấm đang ẩn giữ hình học đã đọc. Bật/tắt chúng hoặc đổi Copies/số chi tiết,
góc xoay, vật liệu chưa được điều khiển ở bản này. Tham số không tác động trong
cấu hình hiện tại giữ cố định và có lý do. Các giới hạn hộp, phủ bì, giao tấm và
không sửa nguồn vẫn áp dụng. Nên đọc DC gốc từ SketchUp để xác minh hình học;
bản model tạo bằng quy tắc cũ không tự có lại ATT nguồn đã bị loại bỏ.

## Library và HUD (017)

**Replace (062):** chọn mẫu trong Library, giữ Ctrl rồi click group/component
trong model để thay theo kích thước thực hiện tại, kể cả đã scale/xoay/lật. Đích
chỉ cung cấp phủ bì, vị trí và hướng: ATT/quy tắc hỏng, hình học hở hay dữ liệu
cụm cũ bị lỗi không chặn replace (063). Giữ T của mẫu nguồn, không đọc T của đích. Muốn
thay cả cụm đã Gộp thì chọn component cha trước rồi Ctrl+click; nếu không, click
vào module con vẫn thay riêng module đó. Liên kết nội bộ của nội dung bị thay
được bỏ cùng nội dung; cụm còn liên kết từ mặt module con ra ngoài cần thay module
con để giữ tham chiếu. Không tự xóa liên kết ngoài không thể remap.

Nếu bản hình học nạp vào bị lệch nhưng còn nguyên mã/cấu trúc chi tiết và bộ
công thức lưu nhất quán, app khôi phục bản nhập riêng trước khi fit. File nguồn
giữ nguyên. Khi Lưu SKP, file vừa ghi được mở lại kiểm tra hình học trước khi
chấp nhận ghi đè.

**Tự cập nhật folder (061):** khi Library hoặc HUD mở, file SKP thêm, đổi tên,
sửa hoặc xóa trong folder và các folder con sẽ được cập nhật sau khi thay đổi
ổn định. App kiểm tra metadata theo từng lượt nhỏ, giữ cache ảnh của file không
đổi, giữ tìm kiếm/module đang chọn nếu còn tồn tại. Đang đặt module hoặc kéo
icon thì chờ thao tác kết thúc mới cập nhật. Đóng cả Library và HUD sẽ dừng
kiểm tra; mở lại sẽ kiểm tra tiếp. Nút Làm mới vẫn dùng được.

**Góc ảnh riêng cho từng icon (051):** chọn module trong Library, chọn **Góc
ảnh** rồi bấm **Cập nhật icon**. Chỉnh trực tiếp tại Library; Setting HUD chỉ
chỉnh cỡ, vị trí, thứ tự icon và phím folder. Có ảnh gốc SKP, 3D, mặt đứng,
mặt bằng, trái, phải, sau và dưới; hướng dựa trên trục local của file SKP.
Library và HUD dùng chung ảnh. Góc đã chọn và PNG được lưu trong folder ẩn
`.mh-thumbnails` của thư viện; giữ folder này khi chuyển thư viện sang máy khác.
File SKP, công thức và hình học nguồn giữ nguyên.

Mặc định dùng **Mặt đứng** cho module chưa chọn góc riêng (056). Các góc đã
chọn vẫn giữ nguyên. HUD mới mở có thể hiện ảnh gốc tạm trong lúc tạo ảnh mặt
đứng lần đầu; ảnh hoàn tất được cache để mở lại nhanh.

Tab Library: Chọn folder chứa SKP, chọn nhánh trong cây folder, tìm tên, đổi
lưới/danh sách và kéo cỡ ảnh. Thumbnail lấy từ SKP; module được lưu bằng app có
camera thumbnail phối cảnh song song cố định. Chọn component đã Tạo model trong
SketchUp, bấm Lưu module để lưu SKP kèm toàn bộ công thức, giá trị hiện tại và
các lựa chọn hiện/ẩn. File này dùng độc lập với DC và MH_superimp. SKP thường
không có bộ quy tắc MH vẫn xem được thumbnail nhưng chưa đặt theo quy tắc này.

Chọn ảnh rồi Đặt vào model, hoặc Mở HUD. HUD nằm trực tiếp trong viewport
SketchUp, tối đa 8 ảnh/trang; click giữa/Tab để chọn folder, mũi tên trái/phải
chuyển trang, 1–8 chọn ảnh. Gõ chữ để tìm tên không dấu, Backspace xoá. Chuột phải
→ Cài đặt HUD để chỉnh cỡ ảnh và gán chữ A–Z chọn folder. Kích thước/lối hiển thị,
folder và chữ đã gán được lưu riêng trong preferences của extension.

Gán phím tại Preferences → Shortcuts, tìm `MH Module Studio · Mở HUD`.
Khi HUD đang nhận bàn phím, Tool tiêu thụ sự kiện nhấn/thả phím; cùng Tool tiếp
tục giữ phiên khi đặt model. Click trong SketchUp để đặt, có bắt điểm và xem
trước dạng cạnh tấm. Đặt xong thì HUD đóng; Esc khi còn cầm mẫu trở lại Library,
Esc khi đang duyệt hoặc Space sẽ thoát HUD, về Select. Các bản đã đặt được giữ lại, mỗi lần đặt/sửa
là một thao tác Undo; mỗi component có ID và definition riêng. Bảng nhỏ Thông số
module chỉnh thông số trực tiếp. Không đổi cấu hình shortcut hay cài hook toàn hệ thống.

Đã chạy VBO: lưu/import lại tham số và công thức, hai bản độc lập, sửa hình học,
Undo/Redo, thumbnail texture, xem trước cạnh và callback phím. Ở bản 017, kiểm tra
phím vật lý bị chặn khi foreground chuyển sang process khác; bản 021 đã kiểm tra
được B/R có shortcut sẵn, Esc và khôi phục B sau khi thoát. Không coi callback
giả lập là bằng chứng rằng đã thử mọi shortcut trong phiên SketchUp của người dùng.

## Công thức tọa độ trong bảng chi tiết (017)

Gốc local của tấm có thể lệch khỏi góc nhỏ nhất của hình học. Bộ tính dùng cả
biến đổi tọa độ và local bounds, rồi đối chiếu kết quả với hình đã đọc; không
loại toàn bộ ATT chỉ vì gốc lệch. Các thuộc tính chỉ có công thức nhưng không có
cache số cũng được liệt kê. X/Y/Z trong bảng là tọa độ góc nhỏ nhất theo trục
module, nên công thức từ group lồng nhau được quy đổi qua các cấp cha, về mm.

Ô hiển thị số kèm ƒ khi có công thức; double-click hiện biểu thức sửa trực tiếp.
Biểu thức tuyến tính được rút gọn, IF/hàm số được giữ dưới dạng biểu thức đã dịch
và kiểm tra giá trị. Lưu cả ATT gốc để đối chiếu. Công thức không dịch an toàn
được vẫn có chẩn đoán, không chạy Ruby nhập từ file. Model cũ đã xuất theo bộ
quy tắc hình học không tự khôi phục ATT bị bỏ; đọc lại DC gốc rồi tạo/lưu module mới.

Kiểm tra phủ bì dùng sai số riêng 0,001 mm. Sai số đo/học 0,15 mm không được dùng
để cho phép model nở ra khi sửa thông số: thay đổi rất nhỏ ở sát mép cũng phải
được từ chối trước khi sửa nếu nó làm công thức và phủ bì mất đồng bộ.

## Tự tính lại sau Scale (019)

Chọn component cha của module do Studio tạo/import ở cấp model, rồi dùng Scale
của SketchUp. Khi kết thúc thao tác, extension tự giữ phủ bì mới, khôi phục các
giá trị tham số đã lưu (độ dày, hậu lùi, rãnh...) và tính lại kích thước, X/Y/Z
theo công thức ATT cùng quy tắc riêng. Không cần mở Studio hay Thông số module.
Có thể Scale nhiều lần, riêng từng trục hoặc nhiều module cùng lúc; module đã
xoay/lật vẫn giữ nguyên phép đặt. Các bản sao dùng chung definition được tách
riêng trước khi sửa hình học.

Scale và tính lại đi cùng một Undo; Redo khôi phục kết quả đã tính mà không xoá
lịch sử Redo còn lại. Vẫn chỉnh được tham số sau đó. Nếu phủ bì quá nhỏ, quy tắc
xung đột, hoặc có lỗi khi sửa hình học, app hoàn tác thao tác Scale và báo lý do.

Áp dụng cho tấm hộp đã xác minh với công thức ATT dịch được hoặc quy tắc hình học
riêng. DC nguồn chưa chuyển đổi, Scale từng tấm bên trong, module nằm trong nhóm
khác, đổi số lượng/ẩn hiện/góc xoay và engine chỉ học từ so sánh mẫu chưa thuộc
phạm vi tự tính lại. Giữ nguyên kiểm tra ATT thông thường để không bỏ qua hình
học bị sửa ngoài quy tắc.

Sau Scale, chi tiết đang ẩn giữ nguyên hình học đã Scale thay vì trở về khung
mẫu cũ. Điều này tránh lỗi phủ bì khi thu nhỏ lần tiếp theo; khi sửa tham số,
các chi tiết ẩn tiếp tục được giữ nguyên. Không tự bật chi tiết ẩn hoặc bỏ qua
kiểm tra phủ bì và kích thước của các tấm đang hoạt động.

## HUD Library: phím, vị trí và Edit (021)

**Mở nhanh (055):** ảnh đã làm đậm/cắt khoảng trắng được giữ trong cache tạm
để mở HUD lại không xử lý pixel từ đầu. Ảnh chưa có cache hiện trước rồi cập
nhật lần lượt. Đổi góc ảnh hoặc file sẽ tạo cache mới; Esc hủy các ảnh đang chờ.

**Chọn mẫu nhanh (057):** click icon đọc khung xem trước để cầm mẫu ngay, không
chạy lại chuyển đổi công thức lúc chọn. Khi click đặt, app vẫn kiểm tra đầy đủ
file/quy tắc/hình học. Kết quả chuyển đổi hợp lệ được giữ trong bộ nhớ để các
lần đặt cùng file nhanh hơn; file thay đổi được kiểm tra lại. Lần đặt thật đầu
tiên của file cũ chưa cache vẫn có thời gian kiểm tra công thức.

**Cỡ ảnh trong vòng (052):** chuột phải HUD → Cài đặt HUD. **Cỡ vòng HUD**
đổi đường kính icon; **Ảnh trong vòng** chỉnh hình module từ 25–300%, áp dụng
ngay và nhớ sau khi mở lại. 100% hiện trọn hình vừa trong vòng; tăng quá100%
phóng to hình và cắt phần vượt vòng. App bỏ khoảng trắng thừa quanh hình trong
bộ nhớ để hình rõ hơn (054). Viền mảnh và vùng click giữ nguyên. Nét hình đậm2x khi
nạp texture HUD, không sửa file ảnh/SKP gốc (053). Góc ảnh vẫn chỉnh riêng từng
module trong Library.

Đặt/thay module (033): chọn icon rồi rê vào khoang tủ, khung xanh hiển thị vùng
lọt lòng đo từ các tấm hiện tại; click để đặt vừa vùng đó. Khoang mở được giới hạn
bởi phủ bì module, các đợt/giằng chia nhỏ vùng đặt. Ctrl + click lên module đang
có để thay bằng mẫu vừa chọn, giữ phủ bì và hướng của đối tượng cũ. Khung vàng
báo đang thay. App tính lại nội thất bằng quy tắc riêng để giữ độ dày tấm.
Liên kết cũ được chuyển theo mặt tương ứng; không xác định rõ mặt thì hoàn tác
lần thay và báo lỗi. Một lần Undo khôi phục lần đặt/thay. Phạm vi hiện tại là
khoang chữ nhật theo trục module; chi tiết cong dùng hộp bao bảo thủ.

Chuột phải trên HUD → Cài đặt HUD:
- Cỡ icon từ 24 đến 140 px, áp dụng ngay; số thứ tự thu nhỏ theo icon.
- Theo chuột: mở tại con trỏ trong vùng model, giữ vị trí đó để chọn. Nếu con trỏ
  ở ngoài vùng model thì dùng tâm viewport. Giữa màn hình: tâm vùng vẽ 3D.
  Vòng HUD được giới hạn trong viewport để icon không nằm ngoài khung.
- Edit: kéo icon trên vòng sang ô khác để đổi thứ tự. Có thể bấm Edit HUD trong
  tab Library, rồi giữ chuột kéo một card module ra thả vào ô trên vòng HUD.
  Trong lúc Edit, duyệt Library sang folder khác vẫn giữ folder đích của vòng;
  kết thúc Edit trở về folder vừa chỉnh. Thứ tự lưu theo folder trong preferences.
  Đổi folder gốc thư viện bắt đầu bố cục riêng. Không đổi thứ tự grid/list hay SKP.

Click giữa vòng để kết thúc Edit và dùng lại chức năng chọn/đặt module. Edit không
đặt model; thả ngoài vòng hoặc hủy kéo giữ nguyên bố cục. Esc/Space thoát HUD.

Chọn icon module sẽ ẩn toàn bộ vòng HUD để xem trước và đặt vào model. Click đặt
xong hoặc Ctrl + click thay module thì HUD đóng, không tự mở Thông số module.
Trong lúc đang cầm mẫu chưa đặt, Esc hủy lượt import và trở lại Library, giữ
folder/bộ lọc/trang để chọn mẫu khác. Esc khi đang duyệt Library hoặc Space ở
bất kỳ bước nào sẽ thoát HUD và khôi phục shortcut SketchUp. Trong lúc đặt, vị trí
icon cũ không chặn click và phím duyệt thư viện tạm bỏ qua.
Ảnh thumbnail phủ hình tròn, crop giữa theo đúng tỷ lệ,
chừa viền 1 px ở mọi cỡ icon.

SketchUp xử lý shortcut có sẵn trước Tool.onKeyDown. Bản Windows 64-bit dùng
native/hud_input.dll để giữ phím chỉ trên UI thread và cửa sổ model của phiên
SketchUp đang mở HUD. Các sự kiện đưa vào hàng đợi C rồi Ruby nhận qua timer;
không gọi Ruby từ callback native. Tháo bộ lọc khi đóng, đổi Tool hoặc có lỗi.
Các ô nhập ở cửa sổ Settings/Studio vẫn dùng bình thường. Không sửa Preferences
Shortcuts, cài bộ lọc toàn hệ thống hoặc chặn phím ở process khác.

Library dùng pointer capture cho thao tác kéo sang viewport, tránh luồng kéo
HTML5/OLE của SketchUp tự đổi Tool. Chỉ truyền ID module qua bridge, không thả
file SKP/URL vào SketchUp. Native helper có mã nguồn trong tools/native; build
bằng tools/build_hud_input.ps1 (GCC x64, chỉ dành cho phát triển, không cần ở máy
cài extension). Chi tiết kiểm tra ở specs/021-hud-edit/verification.md.

## Đọc hàm DC và chuyển thư viện (024)

Khi ABF đang được nạp trong SketchUp, app có thể nhận nội dung hàm do bộ đọc ABF
cung cấp trước bước thực thi. Chỉ mẫu hàm đọc kích thước cha được xác minh đầy đủ
mới được dịch; không đoán ý nghĩa từ tên ngẫu nhiên hoặc số cache. Các ánh xạ lưu
trong quy tắc riêng đi cùng module, nên module đã chuyển tự tính bằng lõi của app.
Bản đọc file SKP bổ sung ánh xạ trên UI thread sau khi bridge đọc xong; thao tác
đọc definition tạm được hoàn tác, không chèn đối tượng vào model người dùng.

Đã bổ sung COPY mặc định bằng 0 ở bản gốc, giữ chỉ số riêng của từng bản sao,
ưu tiên tham chiếu tên group trong nhánh cha hiện tại và 20 hàm toán chuẩn còn
thiếu (INT/SIGN, EVEN/ODD/ISODD, DEGREES/RADIANS, EXP/LN/LOG10, lượng giác ngược,
hyperbolic và NEAREST). Các công thức số gắn nhãn STRING ở thuộc tính không phải
chiều dài vẫn được tính và kiểm tra đầu ra số. Đổi số lượng bản sao hoặc trạng
thái ẩn/hiện vẫn chịu giới hạn topology hiện tại.

Đợt 024 đạt **65/227 module đã chuyển và thử đổi hình học thật**,
tăng 28 module so với 37 bản trước. 162 file còn vướng chủ yếu xoay/lật, scale lồng,
cấu trúc không phải tấm hộp, công thức lệch hình nguồn hoặc không có thay đổi nội
bộ giữ được phủ bì. DADX trong bốn file tấm cong chưa có định nghĩa được xác minh.
Chi tiết từng file ở D:/Cong viec/Sketchup/DC/Modul_studio/.conversion/report.md.
Đọc lại DC gốc trong Studio để nhập các tham chiếu mới; bộ quy tắc đã lưu không
tự bị thay thế. Kiểm tra kỹ thuật: specs/024-dc-function-coverage/verification.md.

## Tấm lật gương và DC không cong (025)

Theo yêu cầu, dừng khảo sát DADX/tấm cong và xử lý các DC khác. Group con lật
gương hoặc xoay 180° vẫn cùng phương trục được giữ đúng dấu trục; kích thước
hiển thị dương, tọa độ lấy theo mép nhỏ nhất của hình học. Công thức trong bảng
chi tiết và dấu ƒ dùng cùng cách tính này. Biểu thức nominal cha cộng/trừ khoảng
hở không bị nhân Scale thêm lần nữa. Xoay đổi phương trục, shear hoặc thay đổi
góc xoay theo tham số vẫn chưa được hỗ trợ.

Ở phiên bản 025, thư viện có **69/227 module đã chuyển và kiểm tra đổi tham số thật**, tăng
4 bản: mặt ngăn kéo, cánh mở trên, tủ bếp trên góc trái và phải. Cả 65 bản xuất
cũ và 227 file nguồn giữ nguyên byte. Chi tiết tại
D:/Cong viec/Sketchup/DC/Modul_studio/.conversion/report.md.

Bốn bản mới đã thử đổi thông số liên tiếp rồi trả lại giá trị cũ. Mặt ngăn kéo
và cánh mở trên cũng đã thử Scale X hai lần và tính lại ổn định. Hai tủ góc còn
có chi tiết Viền không phải tấm hộp đã xác minh: chỉnh được các tham số được
kiểm tra, nhưng Scale cần tính lại Viền sẽ bị chặn và hoàn tác. Các bộ ngăn kéo
còn có helper phẳng và group Scale lồng; chưa chuyển bằng cách bỏ qua kiểm tra.
Kiểm tra kỹ thuật: specs/025-dc-mirrored-panels/verification.md. Các bổ sung
ngăn kéo 036 và Chân bệ 037 được mô tả ở đầu tài liệu.

## Tách lõi tính toán và trách nhiệm chức năng (026)

`core.rb` là đường nạp riêng cho phần tính toán, chạy được ngoài SketchUp bằng
Ruby. Phân tích công thức, phép toán, tính ATT, tọa độ ký hiệu, bảng Parametric,
giải ràng buộc và tính lại sau Scale có nơi xử lý riêng. Phần nhận diện hàm DC
đang cài nằm trong adapter; phần theo dõi Scale, Undo và ghi hình học vẫn ở
SketchUp. Giao diện gọi lõi để tính, không cài thêm phương thức vào lớp tính ATT.

Các bước học/tạo quy tắc, xem trước và xuất dữ liệu bảng dùng bản dữ liệu riêng,
tránh sửa một bản nháp làm đổi mẫu hoặc quy tắc đang dùng ở chức năng khác.
Có kiểm tra tự động hướng phụ thuộc, quyền sở hữu phương thức và dữ liệu dùng
chung. Phép toán nền vẫn được dùng chung có chủ đích; khi sửa phải chạy kiểm tra
các chức năng liên quan. Việc tách này giảm ảnh hưởng chéo, không bảo đảm mọi
thay đổi sau này đều không có lỗi.

Không đổi định dạng quy tắc/SKP đã lưu, số module đã chuyển hoặc giới hạn hình
học. Xem [ARCHITECTURE.md](ARCHITECTURE.md) để biết nơi sửa từng chức năng.

## Đổi ký hiệu biến và công thức chi tiết (027)

Đổi cột Ký hiệu trong Parametric rồi bấm Áp dụng bảng biến: công thức tự sinh,
công thức chi tiết đã sửa tay và công thức của các biến liên quan cùng cập nhật
theo ký hiệu mới. Ví dụ `giang + 10` thành `CaoGiang + 10`. Giá trị, khóa liên
kết và công thức ATT nguồn được giữ nguyên. Cột Tên biến tiếp tục là nhãn hiển thị.
Nếu ký hiệu trùng hoặc không hợp lệ thì toàn bộ lượt sửa bị từ chối, giữ bản cũ.

## Liên kết giữa các module — HUD trong model (028)

Bản 035 có cây **Cụm → Module → Tấm / Liên kết** trong viewport: bấm mũi tên mở
nhánh, click tên để chọn/highlight, cuộn để xem thêm; click liên kết để sửa.
Bảng nhỏ bên phải có mặt A/B/C, khoảng cách, Tiếp xúc / Vuông góc / Góc và Đảo phía.
Mở HUD bằng lệnh **MH Module Studio · Liên kết module HUD**.
Cây và bảng giữ nguyên khi dùng Move, Scale, Orbit hoặc Select. M/S vẫn là
shortcut SketchUp; chỉ click chọn mặt mới bật lại công cụ liên kết. Space về Select
và giữ HUD; nút × đóng cả cây/bảng mà không đổi công cụ Move/Scale đang dùng.
Hiển thị dùng Overlay chỉ đọc; input chuột giới hạn trong khung cây và xử lý ngoài
callback Overlay. Không dùng bộ giữ bàn phím của Library cho HUD liên kết.

Mở **Liên kết module** trên thanh Studio, hoặc Extensions →
**MH Module Studio · Liên kết module HUD**; có thể gán shortcut riêng.
HUD này vẽ trực tiếp trong viewport SketchUp, độc lập với HUD Library.

- **Khoảng cách:** chọn mặt A trên tấm của module tham chiếu, rồi mặt B
  trên module cần điều chỉnh. 0 mm là tiếp xúc; giá trị có dấu theo pháp tuyến
  mặt A. Hai mặt cần song song; dùng Góc để điều chỉnh hướng khi cần.
- **Căn giữa:** chọn A và C là hai mặt giới hạn song song, B thuộc module
  cần căn. Giữ kích thước và chỉ đổi vị trí theo phương của khoang.
- **Vừa khoang:** cùng các mặt đó, nhập khe mỗi bên. Cho phép đổi phủ bì B
  theo một trục; module Studio dùng bộ tính ATT/Scale hiện có để dựng lại bên
  trong và giữ độ dày. DC nguồn cần chuyển đổi trước khi dùng Vừa khoang.
- **Lấy khoảng giữa 2 mặt:** chọn R1/R2 để khoảng cách lấy từ hình học hiện tại.
  Chọn Nhập số để trở lại giá trị cố định. Khi dùng tham chiếu hoặc chia đều,
  ô khoảng cách hiện kết quả đo/tính và không ghi đè bằng nút +/-.
- **Góc:** chỉnh trực tiếp góc hai pháp tuyến, hoặc bấm Vuông góc 90°.
- **Lặp / Chia đều:** chọn B, chọn Phải/Trái/Trên/Dưới theo trục cục bộ của B.
  Số lượng tổng gồm cả B. Khoảng cách là khe giữa các biên, không phải bước tâm.
  Bật Chia đều và chọn A/C để tính khe theo khoang; tùy chọn Đều cả hai đầu.
  Bản lặp được điều khiển bởi module gốc. Đổi số lượng giảm chỉ xóa các bản
  do liên kết đó tạo; xóa liên kết giữ lại các module đã đặt.

Lưu liên kết lần đầu. Sau đó bấm +/- hoặc click ô số rồi nhập và Enter trong
Measurements để áp dụng ngay; số không có đơn vị trên HUD được hiểu là mm.
**Giữ mặt B** để kéo đổi khoảng cách theo pháp tuyến (Tiếp xúc/Vừa khoang).
**Giữ mặt khác trên thân module** để di chuyển theo các phương còn tự do:
một tiếp xúc cho trượt trên mặt, hai mặt độc lập giữ một phương, ba mặt giữ vị trí.
Mặt đang giữ được tô đậm. Không còn các tay XYZ. Khoảng cách dùng tham chiếu
hoặc chia đều cần chỉnh qua điều kiện tương ứng trong bảng.
Kéo hiện khung xem trước, thả chuột áp dụng một bước Undo; Esc hủy lượt kéo.
Space thoát HUD. Các liên kết đã lưu nằm ngay dưới HUD để chọn, sửa hoặc xóa.

Khi lưu liên kết, các module liên quan được gom vào **component cha**. Quy tắc
lưu trên instance component đó bằng PID cục bộ và khóa tấm; không dùng tên để
nhận diện. Liên kết cũ ở cấp model vẫn được đọc. Sau thay đổi tham số/Move/Scale, observer cập nhật
ngoài callback giao dịch và xác minh lại kết quả. Vòng phụ thuộc hoặc các điều
kiện xung đột bị từ chối, giao dịch lỗi được hoàn tác. Các module được chọn ở
cấp model hoặc trong component liên kết do app tạo; tham chiếu mặt biên phẳng
theo trục tấm. Cụm lồng tùy ý, phục hồi sau Explode và xuất riêng cụm vào Library
chưa hỗ trợ.

## Lưu SKP và bảng liên kết mới (029)

Parametric có **Đọc SketchUp** để đọc module đang chọn, không cần quay lại Studio.
**Áp dụng bảng biến** cập nhật bản nháp quy tắc; **Lưu SKP** ghi trực tiếp ký hiệu,
nhãn, biến, công thức chi tiết và hình học vào file SKP. **Lưu bộ quy tắc** vẫn là
lưu dự án JSON. Lưu SKP nhận cả các ô biến đang nhập, không cần bấm Áp dụng trước;
hoàn tất ô công thức chi tiết bằng Enter trước khi lưu.

Mở SKP của app sẽ khôi phục payload đã lưu thay vì học lại làm mất tên ký hiệu.
Module đặt từ Library có đường dẫn nguồn; khi đọc nó trong Parametric, lần lưu
sau cập nhật file đó. Module chưa có đường dẫn sẽ hỏi nơi lưu lần đầu. Nếu đọc
module Studio đang chọn, file lưu giữ cả kích thước sau Scale và cập nhật module
đang mở; lỗi cập nhật model sau khi file đã ghi được thông báo riêng. File đã đổi
bên ngoài bị chặn để tránh ghi đè dữ liệu mới. File cũ được giữ ở `.mh-backups`.
Không thay toàn bộ SKP đang mở bằng một file component. File nguồn phải khớp
khóa chi tiết của bộ quy tắc; không ghi ép khi cấu trúc không khớp.

Bảng liên kết dùng cửa sổ utility sáng, gọn, có ô số thật, các dòng chọn mặt A/B/C
và danh sách liên kết. Chọn mặt và tay nắm vẫn ở model SketchUp; Studio web 3D chỉ
là nơi xem trước module. Bấm **Thêm mặt đối diện để vừa khoang**, rồi chọn C:
module B tự đổi kích thước theo khoang khi đủ mặt. Checkbox **Tự đổi kích thước B**
chuyển giữa Vừa khoang và Căn giữa, giữ nguyên các mặt đã chọn. Nút tạo/cập nhật
luôn nằm ở chân bảng; nội dung dài cuộn riêng. Phần mềm dùng mặt phẳng biên
của các tấm; giới hạn cấu trúc ở mục 028 vẫn áp dụng.

## Component liên kết và kéo trực tiếp (030)

Tạo liên kết tự gom các module thành một component cha, giữ nguyên từng module
và quy tắc bên trong. Thêm module vào cụm sẽ gom lại cùng một component; không
phá group tấm hoặc module. Nhân bản cụm rồi chỉnh liên kết sẽ tạo definition
riêng cho bản đang sửa. Vị trí và mặt hiển thị tính theo component cha khi xoay.
Scale cụm được chuyển xuống các module rồi tính lại nội thất bằng lõi hiện có.

Click giữ mặt B để chỉnh khoảng cách, giữ mặt khác để kéo thân bám ràng buộc;
thả chuột áp dụng, Esc hủy xem trước. Click không kéo không đổi hình học.
Muốn chỉnh thông số một module con: mở component cha rồi chọn module đó trong
bảng Thông số module. Component cha cần riêng definition trước khi sửa con.
Chưa có bảng tổng hợp các biến của toàn cụm.

Mở nhanh **Thông số module** bằng phím tự gán: vào **Window → Preferences →
Shortcuts**, tìm `MH Module Studio · Thông số module`, chọn phím và bấm `+`.
Lệnh cũng nằm ở Extensions và menu chuột phải khi chọn module Studio.

## Hai mặt tiếp xúc tự đổi kích thước (031)

Mặt A/B được tô phủ bán trong suốt: A xanh, B vàng; mặt đang giữ có màu đậm hơn.
Một liên kết tiếp xúc giữ kích thước và chỉ đổi vị trí. Khi thêm liên kết giữ mặt
còn lại trên **cùng module B**, app tự đổi kích thước theo phương cần thiết để
thỏa cả hai khoảng cách. Các liên kết tiếp tục lưu riêng và sửa được từng khoảng
cách. Có thể giữ thêm cặp mặt theo phương khác để vừa cả rộng và sâu.

Module Studio được tính lại các tấm bên trong theo bộ quy tắc, giữ độ dày đã đặt.
Mặt trong có khoảng lùi được đo theo phản ứng thực của ATT, không dùng tỉ lệ hộp
bao đơn thuần. Hai yêu cầu trái nhau trên cùng một mặt hoặc khoảng lọt lòng không
hợp lệ vẫn bị chặn và hoàn tác, kèm giải thích thay cho mã UUID của quy tắc.

## Độ dày T1/T2 và thông số cụm liên kết (032)

Tham số điều khiển độ dày tấm từ **17 đến 18,6 mm** dùng ký hiệu **T1**, dưới
17 mm dùng **T2**. Khoảng lùi, chiều sâu rãnh và các kích thước khác có cùng
giá trị được giữ nguyên. Công thức riêng của app và công thức hiển thị ở chi tiết
dùng ký hiệu mới; khóa ATT nguồn vẫn được giữ để bộ tính đọc đúng file gốc.

Nhiều đầu vào độ dày cùng nhóm được gộp thành một biến. Giá trị ván/panel chính
điều khiển các đầu vào còn lại; nếu không có thì dùng đầu vào đầu tiên. Mối nối
được lưu trong `parameter_binding_aliases`, không tạo ký hiệu T1_2/T2_2. Khi cần,
tấm phụ đã sát mặt ngoài được neo theo phủ bì để việc gộp không làm tăng kích thước
ngoài. Vai trò T1/T2 được giữ ổn định sau khi chỉnh giá trị.

Chọn **component cha đã liên kết** rồi mở **Thông số module** bằng shortcut hoặc
menu chuột phải. T1/T2 chung hiện trên cùng; các thông số riêng nằm dưới tên từng
module. Giá trị khác nhau hiện “Khác nhau”; nhập số để đặt cùng giá trị. Chỉ các
tham số được tick hiển thị trong Parametric mới xuất hiện. Sửa tham số và tính lại
liên kết thực hiện trong một lượt Undo; bản sao cụm được tách riêng trước khi sửa.

## T1 và Scale cụm liên kết (040)

T1 chung cập nhật cả module khung và module tấm cánh có độ dày được công thức DC
điều khiển. Quy tắc cũ của app tự được kiểm tra và nâng cấp khi dùng, không cần
đọc lại module. Chỉ trục đầu ra được chứng minh bằng công thức mới được phép đổi
phủ bì theo độ dày; các trục kích thước còn lại vẫn giữ đúng yêu cầu.

Scale cụm liên kết tiếp xúc giữ độ dày và khoảng cách đã đặt, đồng thời tính lại
các kích thước tự do để đạt phủ bì vừa kéo. B vẫn theo A. Yêu cầu quá nhỏ hoặc
không thể đồng thời thỏa các liên kết sẽ được hoàn tác. Bước hiệu chỉnh phủ bì mới
không áp dụng cho cụm dùng quy tắc lặp; chúng giữ cơ chế lặp hiện có.

## Giữ phủ bì cụm khi sửa thông số (041, chính sách đã đổi ở 047)

Sửa T1/T2 chung hoặc thông số riêng của module con sẽ giữ nguyên phủ bì và vị trí
của tổng cụm liên kết. App tự đổi các kích thước bên trong theo công thức và các
mặt tiếp xúc; giữ nguyên độ dày vừa nhập và khoảng cách liên kết. Scale component
cha vẫn dùng phủ bì mới do người dùng kéo. Yêu cầu không thể đồng thời thỏa hình
học và liên kết sẽ được hoàn tác; quy tắc lặp giữ cơ chế hiện có.

App giảm việc dựng thử hình học khi tính tiếp xúc, tránh tính lại Scale sau khi đã
redraw xong và gộp các lượt làm mới bảng. Nhập lại đúng giá trị hiện tại không tạo
thêm lượt redraw hoặc Undo. Không bỏ bước kiểm tra hình học cuối cùng.

## Chọn mặt trong Liên kết module (042)

- **Click:** mặt thật của tấm/group.
- **Shift + Click:** một trong sáu mặt phủ bì của module.
- **Ctrl + Click:** một trong sáu mặt phủ bì của cụm đã liên kết bằng app.

Giữ phím và rê chuột để xem mặt tô sáng trước khi click. Shift bắt được phủ bì
qua khoảng trống của module; hộp chọn đi theo trục đối tượng khi xoay/lật. Giữ
cả Ctrl và Shift sẽ chọn cấp cụm. Bảng hiển thị cấp mặt và tên mặt đang chọn.
Thao tác này chỉ có trong công cụ Liên kết module; các công cụ SketchUp và Ctrl
replace của Library giữ nguyên.

Liên kết bằng mặt cụm giữ nguyên các component cụm hiện có và liên kết bên trong;
quan hệ giữa chúng lưu ở cấp model, không phá cụm để gộp các tấm. Hỗ trợ tiếp xúc,
hai mặt đổi kích thước, căn giữa, vừa khoang và góc. Chưa lặp nguyên cả cụm và
không cho một cụm phụ thuộc ngược vào module con của chính nó. Các thao tác kéo
đổi kích thước/thêm/xóa mới trong mockup chưa được triển khai ở bước này.

## Gộp theo yêu cầu, tên module và độ dày lớn (043)

Tạo liên kết giữ các module ở vị trí hiện tại trong cây model. Khi đã tạo đủ liên
kết, chọn một liên kết rồi bấm **Gộp** trong bảng Liên kết module. Có thể liên kết
module mới với một module con trong cụm cũ rồi bấm Gộp lần nữa. Các liên kết được
chuyển vào component chung và giữ khoảng cách đã đặt. Cụm có liên kết trực tiếp
bằng mặt phủ bì toàn cụm (Ctrl) được giữ nguyên, chưa hỗ trợ phá/gộp tiếp các cụm đó.

Danh sách liên kết hiển thị cả A và B; mục **Đổi tên module** sửa tên instance A/B
ngay trên bảng. Đổi tên bản sao không sửa tên ở cụm gốc hay tên file thư viện.

Chiều dày cánh đôi theo công thức cha, kể cả khi chi tiết dùng Parent!LenY qua
nhiều nhóm lồng. Ưu tiên giữ đúng T, giữ phủ bì cụm và khoảng cách liên kết bằng
cách đổi kích thước các module bên trong. Chỉ nới trục đầu ra đã được chứng minh
khi không thể giữ phủ bì bằng các kích thước dương; không nới mục tiêu Scale.
Quy tắc công thức DC không còn trần độ dày 100 mm: chấp nhận 200 mm nếu hình học
hợp lệ, với giới hạn nhập kích thước ATT 10.000 mm. Kích thước âm, suy biến hoặc
va chạm mới không hợp lệ vẫn bị hủy; giới hạn quy tắc học từ mẫu giữ nguyên.

## Copies và danh sách lựa chọn ATT (044)

Chân bệ đọc lại công thức `Copies = số chân phụ - 1` và vị trí theo COPY. Sửa
**số chân phụ** trong Parametric, hoặc tick để hiện trong Thông số module rồi
sửa tại đó: app thêm/xóa chi tiết thật và chia lại khoảng cách theo ATT. Số chân
ở đầu vào này gồm cả chân gốc. Không cần xóa ATT hay đọc lại sau mỗi lần đổi.
Quy tắc cũ có đủ dữ liệu sẽ tự nâng cấp khi đọc, giữ ký hiệu và lựa chọn hiện/ẩn.

Danh sách DC như Kiểu khung, Kiểu chia, Có dùng/Không dùng hiện dropdown ở cột
**Giá trị** và trong bảng Thông số module. App giữ nhãn tiếng Việt riêng với giá
trị số bên dưới. Tick chỉ điều khiển hiển thị. Biến thiếu quy tắc hoặc làm đổi
góc xoay chưa hỗ trợ vẫn khóa, có lý do tại trạng thái/tooltip.

Copies hiện hỗ trợ các chi tiết cuối cây có công thức, chỉ số COPY liên tiếp và
nhận diện họ bản sao rõ ràng. Tối đa 100 bản thêm mỗi họ, tổng 600 chi tiết; kiểm
tra kích thước, va chạm và phủ bì vẫn áp dụng. Chưa nhân bản nhánh có nhóm lồng,
chưa tạo bản sao xoay, chưa tự gắn một biến Copies mới với đối tượng tùy ý.

## Chọn mặt và tự tạo liên kết (045)

Trong Liên kết module, sau khi chọn A, module A được bỏ khỏi lượt bắt mặt B:
có thể chọn mặt khung phía sau module nằm lọt. Highlight và click dùng cùng bộ
lọc. A/C vẫn có thể là hai mặt của cùng module khung khi dùng Vừa khoang hoặc
Căn giữa. Click/Shift/Ctrl và thao tác kéo module giữ cách dùng đã có.

Chọn ít nhất hai module hoặc một cụm đã Gộp, mở **Tự tạo liên kết** ngay dưới
Kiểu liên kết rồi bấm **Tự tạo liên kết từ vùng chọn**. Khoảng tìm mặt mặc định
20 mm, sửa được từ 0 đến 1000 mm; nhập 0 để chỉ dò các mặt đang sát nhau. App
đọc các mặt hộp thật đối diện có phần chồng nhau, bỏ mặt bị chắn và liên kết
trùng/vòng phụ thuộc. Liên kết giữ đúng khoảng cách hiện tại, không tự move,
scale, redraw hay gộp. Ưu tiên module lớn làm A; hướng phụ thuộc đã lưu có quyền
ưu tiên. Chọn từng dòng ở Liên kết đã lưu để sửa lại. Gộp vẫn là bước chủ động.

Tự dò hỗ trợ mặt chữ nhật kín ở biên tấm hộp; mặt cong/lỗ và khoảng trống phủ bì
không tự tạo liên kết. Chọn tối đa 40 module/2400 mặt hộp, tổng tối đa 200 liên
kết. Một Undo hủy cả lượt tạo; Redo khôi phục các liên kết.

## Giữ chiều sâu cụm khi đổi độ dày (046, đã thay thế bởi 047)

Sửa việc cánh đôi nới cụm ngay khi tăng T1 rồi giữ luôn chiều sâu bị nới khi giảm
T1. Với cụm khung/cánh/chân bệ đã kiểm tra, độ sâu 619,356 mm giữ nguyên khi đổi
T1 qua 18,6 / 40 / 80 / 200 mm. Khung và chân bệ được phép đổi chiều sâu để giữ
phủ bì; độ dày các tấm thật và tám liên kết không đổi sai giá trị đã đặt.
Áp dụng trên phủ bì hiện tại, không tự đặt lại kích thước theo một trạng thái cũ.

## Config HUD và phím Parametric (064)

Vị trí icon HUD và phím folder tự lưu, giữ lại khi đổi tên file/folder con trong
cùng thư viện. Trong **Cài đặt HUD**, dùng **Export config** để lưu JSON và
**Import config** để áp dụng lại cho Library đang chọn. Config gồm thứ tự icon,
phím folder, folder đang mở, cỡ vòng/cỡ ảnh và vị trí HUD. Khi chuyển sang thư viện
đã sao chép, app nhận diện SKP theo nội dung duy nhất nếu đường dẫn đã đổi; báo
các icon thiếu file khớp. Ảnh và góc ảnh vẫn lưu riêng trong thư viện.

Gán phím mở bảng tại **Preferences → Shortcuts → MH Module Studio · Parametric**.
Lệnh đưa bảng đang mở lên trước và giữ các công thức đang sửa.

## Custom ATT trong bảng biến (065)

Khi đọc lại DC nguồn, Parametric nhận thêm custom ATT số được công thức hình học
sử dụng, kể cả không khai báo TEXTBOX/LIST. Ví dụ `Xuong = 5` được dùng trực tiếp
trong công thức chiều dài theo cm sẽ hiện **Xuong = 50 mm**; công thức chi tiết
tham chiếu biến đó. Sửa giá trị trong bảng biến để đổi chiều xương, còn Scale giữ
nguyên giá trị đã đặt. Có thể đổi ký hiệu và tick để hiện trong Thông số module.
Các số dùng làm số lượng/tỉ lệ hoặc chưa xác định rõ đơn vị vẫn giữ dạng số.
Quy tắc đã lưu từ trước giữ nguyên cho đến khi đọc lại DC; không ghi sửa DC gốc.

## Chuyển đổi DC hàng loạt (066)

Trong **Library → Chuyển đổi DC hàng loạt**, chọn folder **DC nguồn** và **Library
đích**, rồi bấm **Bắt đầu chuyển đổi**. App đọc cả folder con, giữ tên file và đưa
custom ATT số có công thức sử dụng vào Parametric. Bấm **Dừng** để ngừng trước file
kế tiếp; các file đã chuyển vẫn được giữ. Kết quả từng file hiện ngay trong bảng;
báo cáo đầy đủ ở `.conversion/report.json`, `report.csv`, `report.md` trong đích.

Muốn nâng cấp file đã chuyển bằng bộ đọc mới, bật **Cập nhật bản đã chuyển**.
App chỉ ghi lại file còn khớp chữ ký trong báo cáo chuyển đổi, có sao lưu trong
`.conversion/backups`; file đã chỉnh tay được giữ nguyên. Mặc định bỏ qua file
đích có sẵn. Nguồn và đích phải là hai folder riêng; không sửa DC gốc. File có
công thức chưa hỗ trợ được báo lỗi riêng, không tính là đã chuyển thành công.
Bấm **Mở thư viện đích** sau khi xong để xem và import các module vừa tạo.

## Mẫu liên kết khi import (072)

Trong **Parametric → Liên kết khi import**, bật **Tự liên kết khi đặt**, chọn
các mặt và khoảng hở; **Chọn 5 mặt khoang** là cấu hình nhanh. Chọn **Module
thường** hoặc **Cánh** bằng thuộc tính, không cần đổi tên file/folder. Bấm
**Áp dụng cấu hình**, rồi **Lưu SKP** vào Library.

Khi đặt từ HUD, các mặt phù hợp trên module chủ sáng lên; dòng trạng thái báo
số mặt bắt được. Mặt trong tấm được ưu tiên; phía mở dùng mặt phủ bì module chủ
làm mốc nét đứt. Chỉ các mặt đã tick được lưu thành liên kết. Chỉ mặt thật trên
chủ được tô kín. Ctrl replace và Esc giữ cách dùng
đã có. Chủ không cần cấu hình riêng. Hiện hỗ trợ các mặt biên phẳng theo trục
module; công thức ATT hoặc chiều cố định không cho phép fit sẽ báo nguyên nhân.

Cánh **Đối mặt** chừa độ dày cánh + khe mặc định 1 mm từ khung, giữ mép phía sau.
Nhiều cánh cùng mặt chủ dùng mức chừa lớn nhất một lần. Cánh **Lọt trong** bám các
mép trong, không trừ chiều sâu khung và không ép mặt sau cánh sát hậu. Sau khi
bấm **Gộp**, độ dày có cùng ký hiệu theo module chủ; thêm module rồi Gộp tiếp vẫn
giữ chủ ban đầu. Cụm lưu SKP giữ chủ, tham số và các liên kết này.

## Redraw và cây liên kết (074–075)

**Thông số module → Redraw**, ngay cạnh **Lưu SKP**, tính lại module/cụm đang
chọn theo công thức đã lưu. Gán phím tại **Preferences → Shortcuts →
MH Module Studio · Redraw**. Lệnh giữ các liên kết, độ dày và hỗ trợ Undo.

Cây **Cụm / Module** chỉ liệt kê module tham gia liên kết còn tồn tại. Đối tượng
chưa liên kết vẫn chọn được trực tiếp trong model; chọn chúng rồi bấm
**Tự tạo liên kết từ vùng chọn** để dò liên kết mới.

Để chuẩn bị một module tự liên kết khi import: chọn module, mở Parametric,
bấm nút **Liên kết khi import** ở đầu bảng, bật **Tự liên kết khi đặt**, chọn
mặt / khoảng hở rồi **Lưu SKP** vào folder Library. Mẫu chưa được đặt không
cần xuất hiện trong cây liên kết của model. Để lưu cả cụm đã liên kết: bấm
**Gộp** trong Liên kết module, chọn cụm và **Lưu SKP**; file giữ các module
con cùng liên kết nội bộ của chúng.


## Fit và khoảng hở khi import (076)

Trong **Parametric → Liên kết khi import**, bật mặt Trước và nhập **80 mm**;
nếu cần khoảng nóc, bật mặt Trên và nhập **80 mm**. **Lưu SKP** rồi đặt lại từ
Library. Fit dùng khoảng giữa hai mặt đối diện sau các khoảng hở, giữ T và chiều khóa ATT;
không kéo module đầy khoang rồi ghi đè khoảng hở. Cánh lọt vẫn giữ chiều dày cánh.

Khoảng hở được tính bằng mm thực dù chủ đã Scale, xoay hoặc lật. Mặt phía mở
được lưu dưới dạng **Mốc phủ bì**; nhập số dương trong HUD để lùi vào trong.
Mặt chưa tick không được thêm thành liên kết. Chỉ bật một mặt trên một trục thì
giữ kích thước mẫu theo trục đó; bật hai mặt đối diện mới co giãn. Mẫu đặt bằng bản cũ từng
bỏ qua mặt trước cần được import lại để tạo liên kết mặt trước đó.

## Thao tác đặt và liên kết trực tiếp (077)

Sau khi chọn icon Library, giữ phím **khi click đặt trong model**:

- Click thường: dùng liên kết đã lưu của mẫu. Không có mẫu liên kết hoặc không
  bắt được mặt phù hợp thì đặt nguyên kích thước.
- **Shift + Click**: Fit vừa khoang, không tạo liên kết; ngoài khoang giữ kích thước mẫu (cập nhật 080).
- **Ctrl + Click**: Replace đối tượng tại vị trí click. Ctrl ưu tiên nếu giữ cả hai phím.

Ví dụ chỉ bật Đáy, tắt Trên: module bám đáy và giữ chiều cao. Bật cả Đáy và
Trên: chiều cao chạy theo khoảng giữa hai mặt, trừ khoảng hở đã nhập.

Quét nhiều module/cụm rồi mở **Thông số module**: các ký hiệu tương thích như
**T1** được gộp lên đầu; giá trị khác nhau hiện ô trống “Khác nhau”. Sửa một
lần áp dụng cho tất cả, một Undo khôi phục cả lần sửa. Tham số riêng vẫn ở dưới
tên module. Ký hiệu tự sinh `att_1`, `att_2` không mặc nhiên coi là biến chung.

Mở **Liên kết module** để tương tác trực tiếp trong model. Tiếp xúc có khoảng
cách khác 0 hiện khối theo kích thước mặt nhỏ hơn, không gắn nhãn A/B. **Click
dim** để sửa khoảng cách; **click khối** mở cài đặt chuyên sâu. Tiếp xúc 0 vẫn
có dim để chọn. Chuột phải có **Tạo liên kết**, **Tự tạo liên kết từ vùng chọn**
và **Gộp**. Cây và bảng HUD cũ không tự mở. Move/Scale vẫn dùng bình thường;
quay lại Liên kết module để click dim/khối.

## Replace liên tục và vùng chọn (078)

- Không chọn sẵn khối: chọn mẫu trong Library/HUD, giữ **Ctrl khi click khối**
  để Replace. Sau lần đầu, tiếp tục click các khối khác bằng cùng mẫu; không
  cần mở lại HUD hoặc giữ Ctrl. **Esc lần 1** về Library, **Esc lần 2** thoát.
- Có vùng chọn: click mẫu trong Library/HUD sẽ **Replace ngay các group/component
  đang chọn**. Không cần Ctrl. Một Undo khôi phục cả lượt; một đối tượng lỗi thì
  hủy cả lượt. Tab Library cũng có nút **Replace vùng chọn**.
- Muốn đặt thêm mẫu mới thay vì Replace: bỏ vùng chọn trước khi chọn mẫu. Khi
  đặt, Shift dùng để Fit vừa khoang mà không tạo liên kết.

Mỗi khối được thay theo kích thước thực của chính nó, dùng quy tắc và T của mẫu
nguồn; không tự kích hoạt liên kết import khi Replace. Công thức khóa/độ dày vẫn
được kiểm tra, không bỏ qua điều kiện hình học để ép vừa một kích thước bất khả thi.

**Replace Component của SketchUp**: module được tạo/cập nhật bằng bản mới mang
theo bộ quy tắc trong definition. App tự nhận lại thông số, tạo nhận dạng riêng và
Redraw sau lệnh Replace. Mẫu Studio cũ nên Redraw rồi Lưu SKP một lần để cập nhật
dữ liệu mang theo. File Library có payload module cũng được nhận. Tính năng này
áp dụng cho module đơn ở cấp model; cụm SKP vẫn dùng quy trình import/Gộp của app.

Liên kết import cũ từng bám vào mặt sau giằng trước có thể hiện 100 mm nhưng đo
từ phủ bì thành 100,6 mm. Khi sửa khoảng cách hoặc Redraw, app chuyển riêng mốc
trước cũ đó về mặt trước phủ bì, giữ số đã nhập và các liên kết còn lại. Liên kết
chọn mặt thủ công không bị đổi mốc. Thao tác sửa hỗ trợ Undo.


## Fit tự do và cỡ ngăn kéo (080)

Giữ Shift khi click đặt trong một khoang để Fit vừa khung mà không tạo liên kết.
Ngoài khoang, mẫu giữ kích thước gốc. Click thường vẫn dùng bộ liên kết của mẫu;
Ctrl giữ chức năng Replace liên tục.

Các dòng ngăn kéo có file cỡ ray cùng tên dòng, cùng folder sẽ tự chọn cỡ dài nhất
còn vừa khoang: ray âm chừa 15 mm, ray bi chừa 5 mm (dung sai chọn cỡ 0,5 mm,
như MH_Superimp). Ví dụ khoang sâu 565 mm chọn ray âm 550 mm. App fit ngang/cao,
giữ chiều sâu danh nghĩa của ray; đặt tự do căn mặt trước và để phần dư ở sau.
Không kéo giãn ray 500 thành 565 mm. Khi Replace nhiều khối, mỗi khối tự chọn cỡ
riêng theo chiều sâu thực. Mẫu đang chọn không bị đổi khi rê qua các khoang.

## Bảng icon HUD tự tạo (081)

Chuột phải trên HUD → **Cài đặt HUD → Edit**. Nhập tên bảng và một phím A–Z,
bấm **Tạo bảng**. Bảng độc lập với folder Library; các ô ban đầu trống.

- Kéo từ Library vào ô nào thì icon nằm đúng ô đó; ô đang có icon được thay thế.
- Kéo icon trong HUD để đổi chỗ hai ô. Chuột phải vào icon trong Edit để xóa khỏi ô.
- **+8** thêm một trang trống. Không tự lấp đầy ô từ folder.
- Phím đã gán hoặc click giữa/Tab mở danh sách bảng. Folder Library đang xem giữ nguyên.
- Ngoài Edit, rê chuột theo hướng icon để highlight rồi click, không cần trúng vòng icon.
  Vùng giữa, nút đóng và chuyển trang vẫn có ưu tiên riêng; hướng trống không chọn gì.
- Vòng lớn chỉ có viền. Edit vẫn bắt đúng các ô tròn khi kéo thả.
- Import/Export config giữ tên bảng, phím và từng ô trống. File đổi tên được dò lại;
  file bị xóa để lại ô trống. Các thứ tự icon đã lưu trước đó được chuyển một lần,
  không tự tạo bảng từ các folder mới.


## Vòng và dải icon ở mép màn hình (082)

Trong **Cài đặt HUD → Edit**, thanh **Khoảng cách tới tâm** đưa tám icon lại gần
hoặc ra xa tâm; đường kính vòng và cỡ ảnh giữ riêng. Khoảng cách được giới hạn
để vừa viewport. Icon đang chọn có lớp màu đậm phủ lên ảnh để thấy rõ highlight.
HUD đã bỏ tiêu đề, dấu X và dòng hướng dẫn bên dưới. Esc/Space và menu chuột phải
vẫn dùng để thoát/cài đặt; chỉ hiện chuyển trang khi bảng có nhiều trang.

- Trong Edit, **click rồi thả icon** để điền một phím số **0–9**; để trống để bỏ
  phím. Phím trùng trong cùng bảng được báo và giữ dữ liệu cũ. Không tự gán số
  theo thứ tự icon; phím đã đặt dùng cả hàng số và numpad.
- **Giữ kéo icon** để đổi chỗ. Kéo ra các ô ở mép trên/dưới/trái/phải để tạo dải;
  các ô nhận thả xuất hiện trong Edit. Dải giữ theo mép viewport khi đổi kích thước.
- Có thể kéo từ Library thẳng vào dải, hoặc kéo qua lại giữa dải và vòng giữa.
  Ô trống giữ nguyên; kéo nội bộ vào ô đang có icon sẽ đổi chỗ hai icon.
- Số đã gán đi theo icon khi đổi chỗ, đổi tên file và Import/Export config, dùng
  được với icon ở dải hoặc trang khác. Các bố cục cũ không bị tự gán thêm số.


## Icon tự do và đường gióng (083)

Trong **Cài đặt HUD → Edit**, giữ kéo icon ra vị trí tùy ý trong viewport.
Khi gần thẳng hàng với icon trên vòng hoặc icon khác, đường gióng ngang/dọc
xuất hiện và bắt thẳng hàng. Căn theo vòng sẽ đi theo vị trí/tâm vòng khi mở lại.
Có thể kéo từ Library trực tiếp vào vị trí tự do, kéo trở lại vòng hoặc dải mép.
Phím số đi theo icon; vị trí được lưu trong config và giữ khi Import/Export.
Click rồi thả vẫn dùng để gán phím số.

Bảng **Thông số module** không còn dòng “Đang cập nhật… Có thể nhập tiếp”.
Bảng vẫn tự áp dụng, giữ các giá trị đang nhập và hiện lỗi khi cần.


## Bắt cạnh trước thùng khi đặt cánh (084)

Với cánh đặt ở chế độ **Tự động**, rê vào cạnh trước tấm hoặc sát cạnh đó
(trong 12 pixel màn hình) để bắt **Đối mặt**. Giữa khoang vẫn là **Lọt trong**.
Vùng bắt dựa trên mặt thật phía trước thùng, chỉ highlight các mặt của thùng;
không dùng mặt sau hoặc mặt đang ẩn. Chế độ Lọt trong được đặt riêng vẫn giữ nguyên.

Replace từng khối dùng lại kết quả tính của mẫu đã kiểm tra và giữ bản định nghĩa
nguồn riêng, tránh phải sửa lại nguồn sau khi một bản đã thay đổi T. Mỗi khối vẫn
được đọc kích thước thực, dựng riêng và kiểm tra hình học. Mẫu mới và kích thước
đích mới vẫn cần lần tính đầu tiên; tốc độ phụ thuộc độ phức tạp của bộ công thức.


## Hiện liên kết và Replace bằng cánh (085)

Dim, khối khoảng cách và highlight liên kết chỉ hiện khi đang dùng **Liên kết
module**. Chuyển sang Select/Move/Scale hoặc thoát HUD sẽ ẩn chúng; liên kết đã
lưu vẫn hoạt động. Mở lại lệnh liên kết để xem và chỉnh dim.

Replace bằng mẫu có tính chất **Cánh** sẽ lấy rộng/cao theo box đích, giữ chiều
dày thật của mẫu cánh và giữ mặt trước của box. Ví dụ box 600 × 500 × 800 mm
thay bằng cánh dày 18,6 mm sẽ thành 600 × 18,6 × 800 mm. Áp dụng cho click Replace
liên tục và Replace vùng chọn; không cần kéo dãn cánh theo chiều sâu box.


## Guide point đi theo Redraw (086)

Khi Scale hoặc đổi tham số, guide point trực tiếp trong chi tiết đi cùng phép
biến đổi của mặt/cạnh. Guide point bị bỏ sót từ bản cũ được khôi phục theo dữ
liệu khung ATT gốc khi đủ cơ sở đối chiếu; không xóa hoặc ép tất cả điểm về mép.
Redraw xử lý cả trường hợp mặt tấm đã đúng T nhưng guide còn làm khung bao phình.
Các guide đã được xử lý giữ lại chỉnh sửa vị trí thủ công ở những lần sau.
