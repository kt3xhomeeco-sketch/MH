# Kế hoạch lưu lịch sử match Excel và virtual key

## Mục tiêu

- Thêm attribute mới theo kiểu cộng dồn: object cũ chưa có field lịch sử vẫn chạy bình thường, chỉ ghi thêm khi có thao tác mới.
- Không lưu tên SP/mã SP hiện tại làm nguồn quyết định chính trong attribute con; mã SP và tên SP hiện tại vẫn lấy theo group cha/context khi scan.
- Attribute chỉ lưu dấu vết: đã từng đổi tên gì, đã match với dòng Excel nào, và virtual item đang bám theo nguồn nào.
- JSON/rule chỉ là bộ quy luật hỗ trợ match, không phải nơi giữ tên thật hiện tại của model.

## Namespace attribute

Dùng dictionary `MH_Thongke` để tách khỏi các nhánh đang có như `ABF` hoặc `ZSU_LED`.

Các field chính:

- `original-name`: tên gốc lần đầu hệ thống thấy trước khi đổi.
- `current-name`: tên chuẩn mới nhất do MH_Thongke ghi nhận.
- `last-rename-from`: tên trước lượt đổi gần nhất.
- `last-rename-to`: tên sau lượt đổi gần nhất.
- `last-rename-at`: thời gian đổi gần nhất.
- `rename-history`: JSON array ngắn, giữ tối đa 10 lượt đổi.
- `excel-match-key`: key định danh dòng Excel đã match gần nhất.
- `excel-match-name`: tên Excel đã match.
- `excel-match-spec`: spec/ghi chú Excel đã match.
- `excel-match-kind`: loại dòng, ví dụ `PK`, `VL`.
- `excel-match-section`: section/nhóm nếu có.
- `excel-match-source`: nguồn thao tác, ví dụ `mini_import`.
- `excel-match-at`: thời gian match gần nhất.
- `excel-match-history`: JSON array ngắn, giữ tối đa 10 lượt match.
- `virtual-key`: key ổn định cho dòng ảo nếu object là anchor.
- `virtual-source`: nguồn tạo dòng ảo, ví dụ `LED_TOTAL`, `MODEL_LENGTH`, `EXCEL_ONLY`.
- `virtual-anchor`: id object thật mà virtual item bám vào nếu có.

## Rename history

Mỗi record trong `rename-history` gồm:

- `from`: tên cũ.
- `to`: tên mới.
- `kind`: `PK` hoặc `VL` nếu biết.
- `product`: mã SP tại thời điểm thao tác, chỉ là lịch sử, không dùng làm nguồn hiện tại.
- `section`: nhóm/section nếu có.
- `source`: nơi phát sinh thao tác.
- `action`: ví dụ `update`, `rename`, `accept`.
- `at`: thời gian ISO.
- `excel_key`: key Excel liên quan nếu có.

## Excel match key

Key dùng để biết object đã từng khớp với dòng nào của Excel, kể cả khi tên hiển thị sau này thay đổi.

Thành phần khuyến nghị:

- mã SP tại thời điểm match.
- loại dòng `PK`/`VL`.
- tên Excel đã chuẩn hóa.
- spec/ghi chú đã chuẩn hóa.
- mã vật tư nếu có.
- section/nhóm nếu có.

Ví dụ:

- `SP26|PK|BAN_LE_GIAM_CHAN_HAFELE|HAFELE_LOAI_A|PHU_KIEN`
- `SP23|VL|HDFCA_AC_LK_4574A_2M_BCT|CANH_LAMINATE_MA_4574A|VAT_LIEU`

## Virtual key

Virtual key dùng cho dòng không phải lúc nào cũng là một object thật độc lập, ví dụ nguồn LED, thanh nhôm LED, suốt treo áo, phào chỉ, tay nắm, phụ kiện Excel-only.

Format chung:

- `<SP>|PKV|<GROUP>|<SPEC>|SOURCE:<SOURCE>|ANCHOR:<ANCHOR>`

Nhóm virtual gợi ý:

- `LED_POWER`: nguồn LED/driver/adapter.
- `LED_PROFILE`: thanh nhôm LED/ray LED.
- `SUOT_AO`: suốt treo áo.
- `PHAO_CHI`: phào chỉ.
- `TAY_NAM`: tay nắm.
- `EXCEL_ONLY`: dòng chỉ có trong Excel, chưa có object thật.

Ví dụ:

- `SP26|PKV|LED_POWER|60W|SOURCE:LED_TOTAL|ANCHOR:12345`
- `SP26|PKV|LED_PROFILE|GD303_DEN|SOURCE:MODEL_LENGTH|ANCHOR:67890`
- `SP26|PKV|SUOT_AO|350MM|SOURCE:MODEL_LENGTH|ANCHOR:45678`
- `SP26|PKV|PHAO_CHI|14X20|SOURCE:EDGE|ANCHOR:23456`
- `SP26|PKV|EXCEL_ONLY|BAN_LE_GIAM_CHAN_HAFELE|SOURCE:EXCEL_ONLY`

## Quy tắc bám model

- Nếu virtual item có object thật để bám: lưu `virtual-key`, `virtual-source`, `virtual-anchor` vào object anchor.
- Nếu không có object thật: lưu vào registry cấp model/snapshot, không ép ghi vào một object không liên quan.
- Virtual key không phụ thuộc JSON; JSON chỉ hỗ trợ rule match và cache phụ.

## Các bước triển khai

1. Tạo helper đọc/ghi JSON attribute an toàn, không yêu cầu migrate object cũ.
2. Ghi `rename-history` khi đổi tên từ bảng mini/import.
3. Ghi `excel-match-*` khi object được match/accept/update theo Excel.
4. Tạo helper sinh `virtual-key` cho LED, thanh nhôm, suốt áo, phào chỉ, tay nắm và Excel-only.
5. Sau này mở rộng UI để xem lịch sử/key khi cần truy vết.
6. Sau khi ổn định mới cân nhắc cleanup/migrate dữ liệu cũ.
