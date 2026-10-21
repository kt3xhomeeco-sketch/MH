Phát triển MH_pk_addon Xử dụng overlay Hud tương tác giữa nút tạo trên màn hình và obj ( tham khảo E:\Dropbox\Apps\remotely-save\LIFE\code sketchup\preset.rb)
Giữ nguyên các cách add phụ kiện theo số lượng và độ dài. không bỏ bớt att cho phụ kiện đã có.
att của phụ kiện đếm lượng
```ABF/setting-name
ABF/statistical-name
MH_Thongke/original-name
MH_Thongke/current-name
MH_Thongke/excel-match-key
MH_Thongke/excel-match-name
MH_Thongke/excel-match-spec
MH_Thongke/excel-match-kind = PK
MH_Thongke/rename-history
MH_Thongke/excel-match-history
```
và phụ kiện đo chiều dài
```ABF/setting-name
ABF/statistical-name
MH_Thongke/original-name
MH_Thongke/current-name
MH_Thongke/excel-match-key
MH_Thongke/excel-match-name
MH_Thongke/excel-match-spec
MH_Thongke/excel-match-kind = PK
MH_Thongke/rename-history
MH_Thongke/excel-match-history
MH_Thongke/measure-type = length
MH_Thongke/length-mm
MH_Thongke/length-m
MH_Thongke/length-source
```
att của pk cần có thêm các thông tin
```[
  {
    "from": "Hafele _ loại A",
    "to": "BẢN LỀ GIẢM CHẤN HAFELE 110 ĐỘ",
    "source": "mini_import",
    "action": "rename",
    "excel_key": "..."
  },
  {
    "from": "BẢN LỀ GIẢM CHẤN HAFELE 110 ĐỘ",
    "to": "BẢN LỀ GIẢM CHẤN HAFELE 350MM",
    "source": "mini_import",
    "action": "rename",
    "excel_key": "..."
  }
]
```
tác dụng để truy vết xem đã được add từ dòng excel nào
được đổi tên gì
đổi tên bao nhiêu lần
- Phía dưới bên phải để bảng danh sách phụ kiện trong excel ( có 3 cột trạng thái, cột danh sách phụ kiện, cột ghi chú ) 
- Phía dưới bên trái là danh sách thư viện 
- Các phụ kiện trong model sẽ có đường leader chỉ vào phụ kiện và tên là loại phụ kiện đó ( bao quanh tên là hình chữ nhật ) nếu có nhiều phụ kiện thì chỉ cần 1 leader 1 tên đại diện 
- Ở giữa bên dưới màn hình sẽ viết tên phụ kiện đang lựa chọn Quy trình hoạt động của app 
- bật app chọn phụ kiện hoặc chọn phụ kiện xong bật app đều được - Khi chọn 1 obj sẽ quét để lấy tên sản phẩm ( hoặc lấy tên sp đã chọn gần nhất trước đó) 
- Sau đó load và hiển thị các dòng phụ kiện ở bên trái phía dưới 
- Click vào các dòng nút phụ kiện để chọn phụ kiện sẽ add vào obj trong màn hình (khi đó ô chính giữa bên dưới sẽ hiện tên phụ kiện đang chọn ) 
- Di chuột Hover các obj trong màn hình (khi vào obj nào sẽ hightlight mặt của obj đó, ấn tab để chọn mặt đối diện của obj đó ) ( tham khảo E:\Dropbox\Apps\remotely-save\LIFE\code sketchup\view.rb)
- Click để add phụ kiện vào mặt đã được hightlight 
- Nếu phụ kiện nào được add rồi thì dòng ở cột trạng thái trong bảng phụ kiện excel sẽ hiện dấu tíck 
- Còn khi click vào các phụ kiện có dòng leader thì sẽ đổi tên sang phụ kiện mới được chỉ định 
- Đối với bảng thư viện phụ kiện cũng tương tự như thao tác với bảng danh sách phụ kiện. Khác ở chỗ không tick vào dòng phụ kiện thư viện