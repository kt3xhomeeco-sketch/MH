# SmartScale Lab - Standalone Multi-Plane Stretch Plugin

Tài liệu này ghi lại toàn bộ kết cấu kiến trúc, chức năng và các quy tắc phát triển của plugin **SmartScale Lab V3**. Sử dụng tài liệu này để giúp AI và các nhà phát triển hiểu nhanh dự án mà không làm ảnh hưởng hoặc làm mất các tính năng hiện có.

---

## 1. Tổng quan dự án
**SmartScale Lab** là plugin độc lập hỗ trợ co giãn đối tượng trong SketchUp theo phương pháp đa mặt cắt (Fredo-style multi-plane stretch). Hỗ trợ snap thông minh, đồng bộ kích thước Dynamic Component (DC), tự động redraw và sửa lỗi lệch tâm tọa độ (origin offset) của các component con.

### Trạng thái hiện tại cần nhớ

* **Stretch Pro đang bị vô hiệu hóa trong code**: `BoxTool#stretch_pro_eligible?` trả về `false` ngay đầu hàm. Không bật lại khi chưa test kỹ vì nhánh này từng gây lỗi double-delta: kéo stretch 100mm nhưng face/edge bên trong bị dời thêm 100mm nữa.
* **Fix mặc định tắt**: `dc_fix_enabled` mặc định `false`. Sau thay đổi gần nhất, `schedule_dc_fix_after_stretch` chỉ chạy khi người dùng bật menu **Fix** thật sự. Không được tự chạy fix chỉ vì có `@dc_stretch_context`.
* **Redraw DC mặc định bật**: `dc_redraw_enabled` mặc định `true`, nhưng chỉ dùng cho đồng bộ/redraw DC. Redraw không được tự ý dời geometry thêm lần nữa.
* Khi sửa stretch, ưu tiên giữ luồng đơn giản: **StretchCore/StretchAdapter apply geometry một lần**, sau đó các bước DC chỉ cập nhật thuộc tính/redraw. Tránh mọi nhánh hậu xử lý tiếp tục cộng cùng delta vào face/edge/component con.

---

## 2. Cấu trúc thư mục & Nhiệm vụ của từng file

### Các file điều khiển chính (Core Controller)
* **`main.rb`**: 
  - Đăng ký menu (`Plugins -> SmartScale Lab -> SmartScale Lab Multi-Plane`) và thanh công cụ.
  - Tải tất cả các file phụ thuộc trong plugin.
* **`lab_box_tool.rb`** (Quan trọng nhất):
  - Kế thừa lớp tương tác màn hình (`Sketchup::Tool`).
  - Xử lý các sự kiện chuột (`onMouseMove`, `onLButtonDown`, `onLButtonUp`), phím tắt (`onKeyDown` - phím Tab xoay trục, Delete xóa plane, các phím mũi tên đổi hướng trục).
  - Quản lý trạng thái kéo thả (`@drag`), chế độ Target (`@target_mode`) và hộp thoại nhập kích thước chính xác (`input_dimension`).
* **`lab_state.rb`**:
  - Lưu trữ trạng thái tương tác hiện tại của người dùng: đối tượng đang hover (`hover_target`) và đối tượng đang active (`active_target`).

### Quản lý Hình học & Hiển thị (Geometry & Render)
* **`lab_box_model.rb`**:
  - Tính toán khung bao (`BoundingBox`), tọa độ các góc, các điểm neo trên mặt biên của đối tượng.
  - Xác định khoảng cách và giới hạn kẹp mặt cắt (`clamp_pos`).
* **`lab_planes.rb`**:
  - Quản lý danh sách các mặt phẳng cắt (`PlaneStore`). Phân loại thành mặt cắt mặc định (`default plane` - luôn nằm ở trung tâm trục) và mặt cắt tự tạo (`user plane` - do người dùng thêm vào).
* **`lab_hit_test.rb`**:
  - Thực hiện dò tìm vị trí click chuột (Hit-test) của người dùng để xác định họ đang click vào: grip co giãn của plane, thân plane, hay các grip của khung bao (`BoundingBox`).
  - Thứ tự ưu tiên dò tìm: `plane_stretch > plane_move > bbox_handle > plane_body`.
* **`lab_overlay.rb`**:
  - Vẽ giao diện hiển thị trực quan (Plane, Grid lưới nét đứt, Grip hình thoi/hình hộp, đường preview co giãn) lên màn hình bằng các phương thức vẽ `draw` / `draw2d` của SketchUp View.
* **`lab_dimensions.rb`**:
  - Vẽ và hiển thị trực quan các đường kích thước hiện tại của đối tượng theo các trục X, Y, Z.

### Xử lý Co giãn & Đồng bộ Dynamic Component (Engine & Sync)
* **`lab_stretch_adapter.rb`**:
  - Bộ điều phối trung gian, tiếp nhận lệnh co giãn từ Tool và gọi các thuật toán xử lý hình học tương ứng.
* **`lab_dc_lengths.rb`** (Rất quan trọng):
  - **Đồng bộ DC**: Cập nhật thuộc tính `lenx`/`leny`/`lenz` và `_lenx_nominal`... trong attribute dictionary `dynamic_attributes` của component.
  - **Kiểm tra công thức**: Phát hiện các trục có công thức khóa (`_formula`) để giữ nguyên hình học và bỏ qua redraw (tránh lỗi công thức kéo geometry về kích thước cũ).
  - **Redraw trì hoãn**: Thực hiện gọi lệnh redraw của SketchUp (`$dc_observers.get_latest_class.redraw_with_undo`) thông qua cơ chế trì hoãn `UI.start_timer(0)` để đảm bảo quá trình co giãn trước đó đã hoàn tất và commit thành công vào Undo Stack.
  - **Sửa lỗi lệch tâm tọa độ**: Hàm `repair_roots` quét toàn bộ các component con để sửa lại tọa độ hình học (geometry origin offset) bị lệch sau khi stretch. Đây là nhánh rủi ro cao, chỉ chạy khi `Fix` được bật.
* **`lab_stretch_pro.rb`**:
  - Module hỗ trợ bổ sung cho tính năng co giãn nâng cao (Stretch Pro).
  - **Hiện không được dùng trong runtime** vì có nguy cơ apply delta lần hai sau `StretchCore`.

### Thư viện thuật toán bổ trợ (Vendor)
* **`vendor/scale_core.rb`**: Thuật toán scale cơ bản của khung bao.
* **`vendor/stretch_core.rb`**: Lõi thuật toán biến đổi vertex, di chuyển các cạnh và các component con nằm ở một phía của mặt cắt.
* **`vendor/vector_font.rb`**: Hỗ trợ vẽ font chữ dạng vector cho các nhãn kích thước.

---

## 3. Các tính năng cốt lõi của ứng dụng

1. **Co giãn đơn mặt cắt (Single-plane stretch)**: Di chuyển mặt cắt để stretch hình học về một phía.
2. **Co giãn vùng giữa 2 mặt cắt (Range stretch)**: Co giãn tỉ lệ phần hình học nằm giữa hai mặt phẳng song song cùng trục.
3. **Co giãn đa mặt cắt cùng lúc (Multi-plane stretch / BBox multi-cut)**: Kéo grip đầu trục để thực hiện stretch cắt qua nhiều plane đồng thời. Khoảng cách kéo được chia đều cho các plane.
4. **Co giãn khung bao chuẩn (Box scale)**: Co giãn thông thường không qua mặt cắt dựa trên 2 lần click chuột hoặc nhập kích thước trực tiếp.
5. **Chế độ Target (`Ctrl + Click`)**: Snap chọn điểm gốc và kéo đối tượng trùng khớp với một điểm neo mục tiêu.
6. **Tự động Redraw DC**: Redraw DC sau khi scale/stretch khi `dc_redraw_enabled` bật.
7. **Fix DC origin offset**: Có menu **Fix**, nhưng mặc định tắt. Chỉ bật để test/cứu model cụ thể, không xem là bước mặc định của stretch.

---

## 4. Luồng xử lý Stretch/Scale hiện tại

### Box Scale

* Khi `operation[:box_scale] == true`, `commit_operation` đi thẳng vào `StretchAdapter.commit_box_scale`.
* Box scale không tạo `@dc_stretch_context`, không schedule fix sau stretch và không gọi Stretch Pro.
* Đây là scale theo bounding box, khác với stretch qua plane.

### Single-plane Stretch

* `lab_box_tool.rb` tạo operation gồm `axis`, `side`, `plane_id`, `cuts`, `box_scale`.
* `StretchAdapter.commit` chuyển plane sang format engine và gọi `SmartScale::StretchCore.stretch_selection`.
* `StretchCore` là nơi chính thức được phép dời vertex/component theo delta.
* Sau khi stretch xong, `finish_model_change` có thể gọi DC redraw hoặc schedule fix tùy flag. Các bước này không được apply cùng delta thêm lần nữa.

### Multi-cut Stretch

* Khi có nhiều cut plane cùng trục, `StretchAdapter.commit_multi_cut` chia amount cho số cut.
* Component/vertex được dời theo số cut mà nó nằm qua.
* Cẩn thận không để Fix hoặc Stretch Pro chạy thêm sau multi-cut.

### Range Stretch

* Khi plane có neighbor cùng trục, app dùng range stretch giữa hai plane.
* Vertex trong vùng được dời theo tỉ lệ trong range.
* Đây là manual geometry operation, phải test riêng với nested component.

### DC Redraw / Fix / Stretch Pro

* `Redraw DC`: cập nhật thuộc tính DC và gọi redraw trì hoãn. Không được dùng để sửa hình học bằng delta.
* `Fix`: chỉ chạy khi `@dc_fix_enabled == true`.
* `Stretch Pro`: hiện disabled bằng `return false` trong `stretch_pro_eligible?`. Nếu muốn bật lại, phải sửa tận gốc cơ chế để không reorigin/apply delta trùng với `StretchCore`.

---

## 5. Các quy tắc quan trọng khi chỉnh sửa Code (Dành cho AI)

> [!IMPORTANT]
> - **Không lồng Operation**: Tuyệt đối không lồng các lệnh `model.start_operation` vào nhau vì sẽ gây crash SketchUp.
> - **Redraw DC phải chạy trì hoãn**: Lệnh `$dc_observers...redraw_with_undo` bắt buộc phải nằm trong `UI.start_timer(0)` để chạy sau khi operation stretch chính đã được commit.
> - **Giữ nguyên các hàm bổ trợ**: Khi chỉnh sửa logic co giãn, không được tự ý xóa hoặc thay đổi cấu trúc của file `lab_dc_lengths.rb` và `lab_stretch_adapter.rb` vì đây là các file cầu nối đồng bộ hệ thống.
> - **Không apply delta hai lần**: Nếu `StretchCore` đã dời vertex/component 100mm thì các bước sau như `StretchPro`, `DcLengths`, redraw, fix không được dời cùng geometry thêm 100mm nữa.
> - **Không bật Stretch Pro lại bằng preference/runtime nếu code vẫn đang disabled**: trước khi bật lại phải có test chứng minh không còn double-delta.
> - **Không tự chạy Fix khi user chưa bật Fix**: `schedule_dc_fix_after_stretch` phải respect `@dc_fix_enabled`.
> - **Khi sửa origin phải phân biệt rõ hai mục tiêu**: dời origin mà giữ geometry world-position, hoặc dời geometry thật. Không trộn hai hành vi trong cùng helper.
> - **Component/group shared definition**: trước khi sửa geometry trong definition phải cân nhắc `make_unique`, tránh làm ảnh hưởng các instance khác.

---

## 6. Known Issues / Vùng nguy hiểm

* **Stretch Pro double-delta**: từng gây lỗi kéo 100mm nhưng face/edge bên trong nhảy thêm 100mm. Vì vậy đang disabled.
* **Fix origin offset**: từng làm lỗi nặng hơn nếu bù geometry sai hệ tọa độ. Chỉ dùng khi bật Fix và phải test cả bên kéo lẫn bên không kéo.
* **Dynamic Component có formula**: nếu `lenx/leny/lenz` bị khóa bằng `_formula`, redraw có thể kéo geometry về kích thước cũ. `DcLengths` phải phát hiện và bỏ qua đúng các node này.
* **Nested component có origin nằm phía kéo**: đây là case dễ bị dời transform và dời geometry trùng nhau.
* **Box scale khác stretch**: không dùng logic fix/stretch context của plane cho box scale.

---

## 7. Checklist test sau mỗi lần sửa

1. Chọn một object có nested group/component, có face/edge bên trong.
2. Kéo stretch một bên đúng 100mm. Kiểm tra chi tiết bên trong chỉ dời đúng phần cần dời, không nhảy thêm 100mm.
3. Kéo bên đối diện 100mm. Kiểm tra bên không kéo không bị nhảy.
4. Test riêng phía có origin và phía không có origin.
5. Test hông trái và hông phải cùng một object.
6. Test object có default plane ở giữa: single-plane stretch.
7. Test object có 2 plane cùng trục: range stretch.
8. Test nhiều plane cùng trục: multi-cut stretch.
9. Test box scale khi không có plane/cut.
10. Test với `Redraw DC` bật và tắt.
11. Test với `Fix` tắt mặc định. Chỉ bật Fix cho test riêng.
12. Không bật `Stretch Pro` trừ khi đang sửa riêng module này.

---

## 8. Reload qua VBO SkAgent

Sau khi sửa file Ruby, có thể reload trong SketchUp qua VBO SkAgent bridge:

* Ghi Ruby command vào `vbo_sk_agent/bridge/command.rb`.
* Chờ `vbo_sk_agent/bridge/result.json` trả `status: success`.
* Sau khi reload xong, dọn `command.rb` về template:

```ruby
# VBO SkAgent - Command File
# AI agent: write Ruby code here
```

Các file thường cần reload khi sửa SmartScale:

* `smart_scale_lab/lab_box_tool.rb`
* `smart_scale_lab/lab_stretch_adapter.rb`
* `smart_scale_lab/lab_dc_lengths.rb`
* `smart_scale_lab/vendor/stretch_core.rb`

---

## 9. Chi tiết về tính năng Stretch Pro (Tính năng nâng cao đang tạm khóa)

### Khái niệm & Mục tiêu
**Stretch Pro** (được định nghĩa trong `lab_stretch_pro.rb`) là một module nâng cao được thiết kế nhằm **bảo toàn tâm tọa độ (container origins)** của các group/component con (sub-components) sau khi thực hiện co giãn đơn mặt cắt (single-cut stretch). 

Khi co giãn một Dynamic Component (DC) có chứa nhiều component con lồng nhau (nested components), việc di chuyển hình học có thể làm lệch tâm tọa độ của các component con so với phần hình học thực tế của chúng. Điều này khiến cho các thuộc tính kích thước hoặc vị trí (như `X`, `Y`, `Z`, `LenX`, `LenY`, `LenZ`) của DC bị sai lệch khi SketchUp thực hiện redraw. Stretch Pro được sinh ra để tự động tính toán lại, dịch chuyển tâm tọa độ (re-origin) và điều chỉnh lại hình học bên trong để vị trí thế giới thực của đối tượng không đổi nhưng gốc tọa độ được đưa về vị trí chính xác.

### Nguyên lý hoạt động
1. **Điều kiện kích hoạt (`BoxTool#stretch_pro_eligible?`)**:
   - Tính năng `Stretch Pro` phải được bật trong thiết lập (`@stretch_pro == true`).
   - Thao tác co giãn là co giãn đơn mặt cắt (single-cut stretch), không áp dụng cho Box Scale, Range Stretch hoặc co giãn đa mặt cắt (multi-cut stretch).
2. **Quy trình xử lý (`StretchPro.finalize`)**:
   - Quét qua toàn bộ các component con (`child`) của các component được chọn (`roots`).
   - Nếu `child` giao cắt với mặt phẳng stretch (`crossing?`) và có gốc tọa độ (origin) nằm trong vùng di chuyển (`on_moving`), nó sẽ tiến hành re-origin.
   - **`move_origin`**:
     * Gọi `make_unique` cho instance nếu dùng chung định nghĩa (definition) với instance khác.
     * Tính toán khoảng cách dịch chuyển cục bộ (`vp`).
     * Dịch chuyển toàn bộ thực thể hình học (vertices, edges, nested containers) bên trong definition của component đi một khoảng ngược lại với hướng dịch chuyển (`-vp`) bằng cách sử dụng `DcLengths.transform_definition_contents`.
     * Thay đổi transformation của instance để dịch chuyển chính instance đó đi một khoảng `vp` xuôi theo hướng dịch chuyển. Kết quả là vị trí hình học của component trên màn hình không đổi, nhưng gốc tọa độ của nó đã được dịch chuyển.
3. **Đồng bộ và Redraw**:
   - Gọi `DcLengths.sync_roots` để đồng bộ lại các thuộc tính danh định và thực hiện redraw trì hoãn để hiển thị kết quả mới.

### Lý do bị vô hiệu hóa & Lỗi Double-Delta
* **Nguyên nhân**: Trong luồng xử lý của `StretchCore` (chạy trước Stretch Pro), thuật toán đã tự động tính toán và di chuyển các đỉnh (vertices), cạnh, cũng như transformation của các nested sub-components nằm hoàn toàn hoặc một phần trong vùng di chuyển. 
* **Lỗi cộng dồn (Double-Delta)**: Khi Stretch Pro tiếp tục chạy `finalize` sau `StretchCore`, nó lại quét qua các sub-components này và tiến hành áp dụng dịch chuyển geometry lần thứ hai. Điều này dẫn đến việc hình học bên trong các component con bị dịch chuyển thêm một lượng delta bằng đúng khoảng cách stretch (ví dụ: kéo stretch thêm 100mm nhưng hình học bên trong thực tế bị dịch chuyển đi 200mm).
* **Trạng thái hiện tại**: Để đảm bảo tính ổn định và tránh lỗi double-delta, dòng đầu tiên của hàm `stretch_pro_eligible?` trong `lab_box_tool.rb` luôn trả về `false`.
* **Hướng phát triển/Mở khóa**: Nếu muốn bật lại Stretch Pro, cần phải thiết kế lại toàn bộ luồng xử lý hình học để `StretchCore` không can thiệp vào các component con mà để `StretchPro` xử lý hoàn toàn việc dịch chuyển và re-origin của chúng, hoặc ngược lại.

### Giải pháp thay thế hiện tại
Dự án sử dụng cơ chế **DC Fix** trì hoãn sau khi stretch thông qua hàm `schedule_dc_fix_after_stretch` (kêu gọi `DcLengths.repair_roots`). Cơ chế này chỉ chạy khi menu **Fix** (`@dc_fix_enabled`) được người dùng bật thủ công, giúp sửa lại lệch tâm tọa độ một cách an toàn hơn sau khi các thao tác hình học chính của `StretchCore` đã được commit hoàn toàn vào Undo Stack.

