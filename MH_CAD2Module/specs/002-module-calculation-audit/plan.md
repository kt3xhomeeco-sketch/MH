# Implementation Plan: Audit lõi nhận dạng module theo độ dày ván

**Branch**: `002-module-calculation-audit`  
**Date**: 2026-10-22  
**Spec**: `specs/002-module-calculation-audit/spec.md` *(chưa tạo; tài liệu này ghi lại kế hoạch audit theo yêu cầu hiện tại)*  
**Repository scope**: `MH_CAD2Module/` và chỉ khi thật cần thiết mới xét `MH_CAD2Module.rb` theo `AGENTS.md`.

> **Trạng thái tài liệu:** audit tĩnh từ code trên nhánh `main`. Chưa sửa code, chưa chạy test suite và chưa xác minh trong SketchUp ở phiên làm việc này. Các mục được gọi là *rủi ro cần tái hiện* không được coi là lỗi đã tái hiện cho đến khi fixture/test chứng minh.

## 1. Tóm tắt

Mục tiêu là rà soát và sửa có kiểm soát lõi nhận dạng tấm/module của `MH_CAD2Module`, đặc biệt các trường hợp sai do suy luận từ khoảng cách gần độ dày ván, ghép nét CAD không tương thích, loại nhầm vách hoặc chia sai ranh giới module.

Hướng xử lý là **bổ sung test tái hiện lỗi trước, sửa tối thiểu tại đúng hàm, rồi chạy hồi quy**. Không viết lại toàn bộ thuật toán, không xóa hàm/chức năng/comment hiện có nếu không có bằng chứng cần thiết, và không tự thêm tính năng ngoài phạm vi.

Các điểm trọng tâm của audit:

1. Độ dày chuẩn chỉ là bằng chứng để nhận diện tấm, không tự nó chứng minh ranh giới module.
2. Mọi kích thước đầu ra vẫn lấy từ hình học đo được; không ép số đo thực thành số chuẩn.
3. Hai tấm 18 mm có đường tiếp giáp thật có thể tạo ranh giới; một tấm 36 mm không có đường chia thật không được tự chẻ thành hai tấm 18 mm.
4. Nét tường, hatch, nét đứt, đường tâm và nét ngữ cảnh không được ghép làm bằng chứng đóng tấm chỉ vì trùng vị trí hoặc khoảng cách.
5. Module đã nhận dạng đúng ở vùng khác không được mất chỉ vì một vùng chưa đủ bằng chứng.
6. Phải giữ nguyên các ca mặt bằng chữ L, hậu giật cấp, nẹp, khoảng hở có chủ ý, cạnh CAD phân đoạn/đảo chiều và CAD gốc.

## 2. Technical Context

- **Ngôn ngữ chính**: Python cho lõi phân tích CAD; Ruby cho tích hợp SketchUp.
- **Luồng xử lý chính**: `worker/main.py::run_plan()` → `worker/plan_reader.py::analyse_plan()` → `worker/oy_sweep.py::plates()` → `worker/oy_sweep.py::bays()` → `worker/stages.py::finish_plan()`.
- **Các nguồn bằng chứng liên quan**:
  - `worker/cad_style.py`: metadata layer, linetype, màu, lineweight và nhận diện nét gián đoạn.
  - `worker/cad_datums.py`: gom nguồn theo `style_key()` khi đo panel datum.
  - `worker/plan_evidence.py` và `worker/parallel_index.py`: bằng chứng tấm song song, cạnh đóng và tấm cong.
  - `worker/plan_depth.py`: bằng chứng chiều sâu và đối chiếu kiểu nét.
  - `worker/directional_layout.py`: phục hồi bố cục khi kết quả ban đầu lỗi hoặc có dấu hiệu thiếu một phần.
  - `worker/plan_profiles.py`: biên cung tròn/hậu giật cấp và kiểm tra hình dạng.
- **Testing**: pytest cho Python; kiểm tra Ruby/RuboCop theo cấu hình repo; kiểm thử native trong SketchUp là cổng phát hành.
- **Dung sai hiện hành**: `geometry.TOL = 0.15 mm`. Danh sách độ dày chuẩn đọc từ `worker/materials.py::BOARD_MM` (hiện gồm 3, 6, 8, 9, 12, 15, 18, 25, 36 mm).
- **Giới hạn phạm vi**: không chuyển sang AI/legacy matcher để chữa kết quả của bộ quét trực tiếp; luồng plan-only hiện nêu rõ AI không được gọi.

## 3. Constitution Check

Kế hoạch phải tuân thủ `/.specify/memory/constitution.md` và `AGENTS.md`:

- **Giữ CAD gốc**: chỉ phân tích bằng chứng; không di chuyển, scale, xóa hoặc sửa hình học CAD nguồn.
- **Không bịa kích thước**: đo từ LINE/POLYLINE và bằng chứng hình học. Không dùng DIM text, tên layer, màu hay AI để tạo ra kích thước.
- **Không lấy độ dày làm ranh giới tự động**: khoảng cách gần độ dày chuẩn chưa đủ để tạo module nếu không có mặt/đầu đóng và bằng chứng kết cấu phù hợp.
- **Không làm mất kết quả đúng**: chỉ cập nhật vùng bị lỗi; giữ module hợp lệ ở vùng độc lập khác, nẹp và khoảng trống có chủ ý.
- **Giữ lịch sử và cache an toàn**: không xóa mẫu được chấp nhận, correction event hay file lịch sử. Nếu thay đổi fingerprint/cache, phải tương thích lịch sử cũ và có test riêng.
- **Thay đổi tối thiểu**: không refactor lan rộng; từng dòng sửa phải truy được về yêu cầu hoặc test tái hiện.
- **Không thay đổi cách triển khai ngoài yêu cầu**: không tự commit, không đổi branch trong quá trình tạo Spec Kit; không khởi chạy AutoCAD từ runtime.
- **Release gate**: pytest, kiểm tra Ruby/RuboCop trong phạm vi plugin và kiểm chứng thực tế trong SketchUp.

## 4. Mô tả luồng hiện tại đã đọc

1. `worker/main.py::run_plan()` tạo `outlines` từ các đường được chọn và truyền `layer` cùng metadata lấy từ `cad_style.metadata(row)`.
2. `worker/plan_reader.py::analyse_plan()` gọi `plates(outlines)` để tìm ứng viên tấm, rồi gọi `bays(rects, outlines)` để ghép khoang/module.
3. Nếu không có khoang hợp lệ, hàm chuyển trạng thái sang `needs_review`; nếu lỗi hoặc kích thước kết quả có dấu hiệu thiếu, mới gọi `directional_layout.recover()`.
4. Bằng chứng bổ sung được tính qua `measure_plan(outlines)` và `plan_depth.evidence(outlines)`. Chúng có vai trò bằng chứng/phân tích, không được tự ý thay thế quy tắc tạo ranh giới module của `oy_sweep`.
5. Kết quả plan-only dùng chiều cao tạm 1600 mm theo quy ước hiện tại; không được nhầm con số này với chiều cao đo thật từ CAD.

## 5. Danh sách phát hiện và hướng xử lý

Mức độ ưu tiên:

- **P1 — ưu tiên cao**: có hệ quả logic trực tiếp từ code và có thể ảnh hưởng tới số lượng/vị trí module; cần fixture cụ thể trước khi chốt cách sửa.
- **P2 — ưu tiên vừa**: nhánh xử lý có thể bỏ sót hình học hợp lệ; cần ca hồi quy đại diện để xác nhận.
- **P3 — chẩn đoán/độ tin cậy**: không tự coi là nguyên nhân trực tiếp gây sai module; sửa sau khi các lỗi nhận dạng chính đã ổn định.

### F-01 — Bộ quét module không phân biệt họ nét khi ghép bằng chứng hình học (P1)

**Vị trí**

- `worker/main.py::run_plan()` — tạo `outlines` và truyền `layer`/metadata.
- `worker/oy_sweep.py::axes()` — xây nhóm nét song song và nhập các đoạn giao/tiếp nhau.
- `worker/oy_sweep.py::plates()` — sử dụng nhóm nét đã gộp để tạo ứng viên tấm.
- Đối chiếu với `worker/cad_style.py::style_key()`, `interrupted()` và `worker/cad_datums.py::panel_boxes()`.

**Điều thấy rõ trong code**

`run_plan()` có truyền metadata kiểu nét, nhưng `axes()` hiện chỉ giữ tọa độ, khoảng chạy và `handle`; khi nhập các đoạn, nó không xét layer, linetype, `continuous`, màu hay lineweight. Các đoạn cùng tọa độ bị gộp và hợp nhất tập `handle` kể cả khi xuất phát từ style khác nhau. Trong khi đó `cad_datums.panel_boxes()` gom hàng theo `style_key()` trước khi nhận diện panel. Hai đường phân tích vì thế có thể nhìn cùng một bộ CAD theo hai cách khác nhau.

**Rủi ro ảnh hưởng**

Một nét tường, hatch, hidden/dashed hoặc nét chú thích có thể tham gia tạo cap/biên đóng tấm trong luồng trực tiếp nếu hình học trùng đủ điều kiện. Ngược lại, không được giải quyết vấn đề bằng cách loại bỏ tất cả nét khác màu/layer: bản vẽ thực có thể dùng nhiều style cho chi tiết cùng sản phẩm, và metadata là bằng chứng hỗ trợ chứ không phải kích thước.

**Phương án xử lý**

1. Viết test cho hình học giống nhau nhưng thay đổi layer/linetype/color/continuous; xác định kết quả hiện tại trước khi sửa.
2. Giữ metadata trên từng đoạn trong quá trình `axes()`; không chuyển mọi đoạn thành một tập handle không phân biệt nguồn.
3. Thiết lập chính sách tương thích style rõ ràng, dùng chung với quy tắc nhận diện panel đang có:
   - Nét được xác định rõ là interrupted/hidden/center/phantom/dot không được tự làm bằng chứng chính để đóng một tấm.
   - Không dùng tên/màu/layer để suy ra chiều dày hoặc ranh giới.
   - Hai mặt/cap không tương thích không được ghép thành tấm chỉ vì khoảng cách gần `BOARD_MM`.
   - Nếu lọc theo style làm mất bằng chứng duy nhất, không âm thầm xóa geometry; giữ nguồn, ghi rõ lý do chưa đủ bằng chứng và chuyển sang review/nhánh fallback phù hợp.
4. Chỉ chấp nhận candidate khi có đủ chứng minh hình học (hai mặt đo được và các cạnh đóng cần thiết); style dùng để phân nhóm/kiểm tra tính nhất quán, không thay thế hình học.
5. Không đổi `cad_datums` hoặc các bộ đọc khác sang một chính sách khác lần nữa; tạo test hợp đồng chứng minh các luồng trả cùng một kết luận đối với fixture tương đương.

**Test cần có**

- Một rectangle panel liên tục với style nhất quán vẫn được nhận dạng.
- Hai mặt cách nhau 18 mm nhưng style không tương thích không tự tạo một panel nếu bằng chứng đóng không độc lập xác nhận chúng.
- Nét dashed/hatch/wall bên ngoài không làm tăng chiều sâu tủ; CAD nguồn và `source_plan_envelope` vẫn được giữ.
- Nhiều màu/layer hợp lệ bên trong một cabinet vẫn được xử lý khi có bằng chứng hình học độc lập đủ mạnh.
- Quét có đường phân đoạn, đảo chiều và tọa độ dịch lớn vẫn trả cùng kết quả hình học.

### F-02 — `walls()` khử trùng ứng viên theo khoảng X, bỏ qua khoảng Y (P1)

**Vị trí**: `worker/oy_sweep.py::walls()`.

**Điều thấy rõ trong code**

Bộ `chosen` dùng khóa gồm `(box[0], box[2])`, tức chỉ hai tọa độ X của candidate. Nếu có hai vách cùng khoảng X nhưng phạm vi Y khác nhau, chúng cạnh tranh cùng một khóa; chỉ candidate được xếp hạng cao hơn theo `support` và chiều dài Y được giữ lại. Khoảng Y và danh sách handle không nằm trong khóa khử trùng.

**Rủi ro ảnh hưởng**

Một vách thuộc nhánh/tầng chiều sâu khác có thể bị rơi trước khi `bays()` ghép các vách. Hệ quả có thể là thiếu một module trong mặt bằng nhiều nhánh hoặc có các vách cùng trục X nhưng phạm vi chiều sâu khác nhau. Đây là hệ quả trực tiếp của khóa hiện tại; cần fixture để xác nhận có xảy ra trong bản vẽ thực mà dự án hỗ trợ.

**Phương án xử lý**

1. Thêm unit test gọi `walls()` với hai rectangle vách có cùng `x0/x1` nhưng khác `y0/y1`; kiểm tra xem cả hai có phải là hai bằng chứng kết cấu độc lập không.
2. Chỉ khử trùng candidate tương đương về **toàn bộ footprint** và bằng chứng nguồn; không khử theo bề rộng X đơn thuần.
3. Nếu nhiều candidate thực sự mô tả cùng một vách, xếp hạng chúng trong cùng nhóm tương đương dựa trên cap, face, seam và handle; không để candidate ở Y khác loại bỏ nhau.
4. Giữ riêng quy tắc nhận diện cặp 18+18 và vỏ 36 mm. Không thay đổi rank/merge chỉ để làm test mới qua nếu làm sai các test hiện có.
5. Kiểm tra `bays()` và `finish_plan()` để bảo đảm khôi phục thêm vách không tạo module chồng lấn hoặc ghép nhầm các vùng rời nhau.

**Test cần có**

- Hai vách cùng khoảng X nhưng khác khoảng Y đều còn trong bằng chứng nếu chúng độc lập.
- Cabinet thẳng tiêu chuẩn, cabinet có vách 18+18, vỏ 36 mm không có seam và vách trong ngắn vẫn cho kết quả đang được kỳ vọng.
- Mặt bằng chữ L vẫn nhận đủ hai nhánh và không lấp các khoảng trống có chủ ý.

### F-03 — Fingerprint/cache chưa mô tả đầy đủ metadata nếu metadata ảnh hưởng nhận dạng (P1, liên quan F-01)

**Vị trí**

- `worker/plan_evidence.py::measure_plan()` — khóa cache `_MEASURES` được tạo từ các tuple `(a, b, handle)`.
- `worker/plan_reader.py::raw_signature()` / `replay_confirmed()` — signature hiện phản ánh cạnh hình học, không phản ánh style.
- So sánh với `worker/cad_datums.py::measure()` và `worker/plan_depth.py::evidence()`; các test hiện có gồm `test_stock_cache_changes_when_style_changes`.

**Điều thấy rõ trong code**

Cache `measure_plan()` hiện không đưa layer/linetype/color/continuous/lineweight vào khóa. Signature dùng để khớp exact feedback cũng là signature cạnh hình học. Cách này chỉ an toàn cho các kết quả không phụ thuộc style; nếu F-01 khiến style trở thành một phần của bằng chứng nhận dạng, cache/fingerprint hiện tại có thể trả bằng chứng cũ khi chỉ style thay đổi.

**Phương án xử lý**

1. Trước khi sửa, xác định rõ loại dữ liệu nào là **geometry-only evidence** và loại nào **style-aware recognition evidence**. Không bắt mọi cache phải phụ thuộc metadata nếu kết quả của cache thực sự không dùng metadata.
2. Với cache có đầu ra phụ thuộc style, bổ sung các field metadata đã chuẩn hóa vào cache key và kiểm tra cả khi đổi style mà giữ nguyên tọa độ/handle.
3. Tách fingerprint hình học khỏi fingerprint phân tích có style, nếu cần. Không âm thầm đổi ý nghĩa của signature lịch sử và không xóa event được chấp nhận.
4. Trước khi replay exact feedback, kiểm tra điều kiện tương thích được định nghĩa rõ; nếu bằng chứng nhận dạng đã đổi thì không tái dùng quyết định module không còn hợp lệ. Giữ sự kiện cũ và báo trạng thái review khi cần.
5. Bổ sung kiểm thử tương thích dữ liệu lịch sử cũ và cache invalidation; không sửa trực tiếp thư viện mẫu/hồ sơ người dùng trong test.

**Test cần có**

- Geometry và handle giữ nguyên nhưng `continuous`, `linetype`, `layer` hoặc màu đổi: mọi cache/bằng chứng có phụ thuộc field đó phải được tính lại.
- Thay đổi hình học thật vẫn làm signature hình học đổi.
- Event lịch sử cũ không bị xóa hoặc ghi đè; event không đủ điều kiện không được replay yên lặng.

### F-04 — Nhận dạng hậu giật cấp chỉ chạy khi không có candidate thường (P2, cần tái hiện)

**Vị trí**: `worker/oy_sweep.py::bays()` và `worker/plan_profiles.py::stepped_bay()`.

**Điều thấy rõ trong code**

`bays()` chỉ gọi `stepped_bay(rects, outlines)` khi danh sách candidate module kiểu thường hoàn toàn rỗng. Nếu một mặt bằng vừa có ít nhất một candidate thường vừa có vùng hậu giật cấp cần nhận dạng riêng, nhánh kiểm tra profile không chạy tại điểm này.

**Chưa kết luận**

Đây là nhánh xử lý có thể bỏ sót, chưa phải lỗi đã tái hiện. `plan_reader.analyse_plan()` còn gọi `directional_layout.recover()` khi trạng thái lỗi hoặc phát hiện kết quả partial; cần kiểm tra xem nhánh đó đã khôi phục đúng trong fixture hỗn hợp chưa.

**Phương án xử lý**

1. Tạo fixture hỗn hợp: ít nhất một module chữ nhật hợp lệ cùng một biên hậu giật cấp có các cạnh nối đóng và độ sâu hai bên khác nhau.
2. Ghi nhận kết quả của `bays()` và kết quả cuối của `analyse_plan()` riêng biệt để biết nhánh nào bị mất thông tin.
3. Nếu test chứng minh lỗi, đánh giá candidate stepped **độc lập** ngay cả khi đã có candidate thường; sau đó dùng kiểm tra footprint, provenance, non-overlap và quy tắc vùng liên kết để chọn/ghép kết quả.
4. Không chỉ đổi `if not candidates` thành thêm tất cả candidate vào danh sách: điều đó có thể tạo module lớn đè lên các module con hoặc làm thay đổi footprint đo được.
5. Khi hai cách phân hoạch vẫn ngang nhau và không có bằng chứng phân định, trả trạng thái `needs_review`/provisional thay vì chọn tùy ý.

**Test cần có**

- Giữ nguyên toàn bộ test của `test_stepped_plan.py`, nhất là profile 8 đoạn, hai trim 18 mm, và ca thiếu một cạnh hậu.
- Thêm fixture hybrid; xác nhận cả vùng chữ nhật đúng và vùng giật cấp được xử lý theo quy tắc, không chồng lấn/không lấp phần lõm.

### F-05 — Chưa có hợp đồng bằng chứng chung giữa các recognizer (P2)

**Vị trí**: `worker/oy_sweep.py`, `worker/parallel_index.py`, `worker/plan_evidence.py`, `worker/plan_depth.py`, `worker/cad_datums.py`, `worker/directional_layout.py`.

**Điều thấy rõ trong kiến trúc**

Các nhánh phát hiện tấm không dùng cùng một cơ chế: `oy_sweep` tìm cặp biên theo trục X/Y và cap; `ParallelIndex` tìm mặt song song theo góc và khoảng offset; `cad_datums` tách theo style; `plan_depth` có bộ lọc bằng chứng chiều sâu; `directional_layout` thực hiện phục hồi theo hướng. Sự khác nhau có lý do, nhưng hiện có nguy cơ cùng một hình học tạo candidate/bằng chứng không đồng nhất nếu ranh giới vai trò không rõ.

**Phương án xử lý**

1. Không viết lại hoặc ép các recognizer thành một thuật toán chung.
2. Chuẩn hóa **mẫu dữ liệu bằng chứng** tối thiểu cho candidate: box đo được, measured thickness/distance, stock match (nếu có), source handles, hai mặt/đầu đóng đã xác nhận, seam nội bộ, hướng và nguồn/độ tin cậy evidence.
3. Đánh dấu rõ candidate nào chỉ là “panel evidence”, candidate nào đủ điều kiện tham gia “module boundary”, candidate nào chỉ hỗ trợ depth/datum.
4. `stock_mm` là nhãn đối chiếu; tọa độ và kích thước thực vẫn giữ nguyên số đo CAD.
5. Khi evidence mâu thuẫn, xuất cảnh báo có mã và handles liên quan; không tự ưu tiên recognizer nào nếu chưa có rule trong đặc tả.

**Test cần có**

- Cùng một fixture được chạy qua panel evidence và module scan phải giải thích được vì sao các kết quả giống/khác nhau.
- Candidate tấm chưa đủ cap không tự trở thành module.
- Candidate chiều sâu không được dùng để tạo ranh giới module chỉ vì có khoảng cách phù hợp với độ dày chuẩn.

### F-06 — Thiếu fixture cho vài tổ hợp biên; đầu ra debug chưa đủ để giải thích candidate bị loại (P3)

**Vị trí**: diagnostics trong `worker/oy_sweep.py::plates()`/`bays()` và test fixtures ở `test/`.

**Điều thấy rõ trong code**

`plates()` trả về các bộ đếm tổng hợp (`vertical_lines`, `horizontal_lines`, `stock_pairs_checked`, `front_assemblies`, `recovered_arcs`), nhưng không cung cấp đầy đủ lý do cho từng candidate bị loại hoặc vì sao một vách thắng candidate khác. Ngoài ra, `plates()` gán giá trị category cố định `'2 cat nt'` cho `Rect.layer`; giá trị này không phải layer nguồn của từng cạnh. `plan_reader.analyse_plan()` cũng khởi tạo `geometry_pipeline['order']` bằng tên các bước `parallel_stock_index`, `aligned_depth_groups`, `double_wall_seams`, trong khi luồng nhận module thực tế gọi `plates()` rồi `bays()`. Các field này có thể là thông tin phân loại/di sản, nên phải kiểm tra consumer trước khi đổi; không nên tự ý đổi nghĩa field đang có.

**Ảnh hưởng/rủi ro**

Khi kết quả sai, log hiện có thể khó trả lời đường nào đã tạo panel hoặc bước nào thật sự tạo module. Category gán cố định cũng không phản ánh style/layer gốc trong đầu ra chẩn đoán. Đây chủ yếu là vấn đề truy vết, không phải bằng chứng độc lập rằng phép tính hình học đang sai.

**Phương án xử lý**

1. Chỉ bổ sung diagnostic có giới hạn và có thể bật trong test/debug; không ghi log khổng lồ cho mọi tổ hợp cạnh.
2. Với candidate được dùng hoặc loại, có thể ghi code lý do như `thickness_not_stock`, `missing_cap`, `style_conflict`, `short_span`, `duplicate_footprint`, `unclosed_rear`, `overlap_conflict` cùng handles đo được.
3. Tách nguồn gốc cạnh (handles + style/layer nguồn) khỏi loại candidate (`panel`, `front_envelope`, `trim`, `module_candidate`) thay vì tái sử dụng `Rect.layer` cho hai nghĩa. Giữ tương thích với consumer đang dùng `front_envelope` và category hiện có.
4. Kiểm tra consumer của `geometry_pipeline['order']`; chỉ cập nhật metadata này để mô tả đúng luồng khi đã xác minh không làm hỏng giao diện hoặc dữ liệu lịch sử.
5. Giữ output runtime hiện tại tương thích; không đổi schema công khai nếu chưa có consumer/test chứng minh.
6. Thêm fixture tối thiểu cho từng lỗi được xác nhận; mỗi fixture phải giải thích bằng một assertion cụ thể thay vì chỉ assert `status == ready`.

## 6. Quy tắc thuật toán phải giữ nguyên

Những hành vi này đã được thể hiện bằng code/test hiện có và phải trở thành regression gates, không được hy sinh khi sửa các lỗi trên:

- **Đo thật, không snap số đo**: `test_all_stock_faces_are_measured_without_forcing_dimensions` gồm cả giá trị 17.94 mm; kích thước đầu ra phải dựa trên CAD.
- **Phân biệt 18+18 và 36 nguyên khối**: `test_double_18_shared_face_splits_modules_but_outer_pair_is_auxiliary`, `test_one_shared_plate_stays_inside_one_module`, `test_unseamed_36_plate_is_not_invented_as_two_18_plates`.
- **Không chia theo vách ngắn đơn lẻ**: `test_short_internal_panel_does_not_split_a_deeper_module`.
- **Không tạo module nếu không khép**: `test_different_stock_distance_and_unclosed_gaps_are_not_boards`, `test_equal_length_without_equal_y_span_does_not_form_a_module`.
- **Bảo toàn hậu giật cấp**: `test_35_edge_scan_keeps_stepped_rear_and_two_solid_trims`, `test_rectangle_cannot_replace_measured_recess_even_with_matching_size`, `test_incomplete_rear_preserves_source_and_does_not_invent_ready_module`.
- **Bảo toàn mặt bằng chữ L, dịch chuyển và xoay**: `test_actual_direct_L_scan_recovers_both_arms_and_preserves_empty_gaps` (0°, 31°, 90°, 121°).
- **Không lấp khe hở có chủ ý**: `test_shared_front_rail_cannot_close_an_empty_gap_between_cabinets`.
- **Không dùng AI/bộ chia cũ cho plan scan thường**: `test_normal_plan_cannot_call_archived_matcher_rules_or_ai`, `test_new_engine_keeps_stepped_shape_without_ai`.
- **Style/context không được suy ra chiều sâu**: các test tương ứng trong `test_plan_depth.py`, đặc biệt `test_increasing_y_uses_closed_18_and_6_not_unpaired_or_101_band`, `test_opposite_faces_of_incompatible_styles_cannot_invent_stock`, `test_stock_cache_changes_when_style_changes`.
- **Giữ CAD gốc và khoảng trống**: các fixture phải kiểm tra không chỉ số module mà cả `bounds`, `source_plan_envelope`, trim, footprint/profile, handles, trạng thái `ready`/`needs_review` và vị trí gốc khi liên quan.

## 7. Các giai đoạn thực hiện

### Phase 0 — Khóa baseline

1. Đọc diff/worktree hiện trạng trước khi sửa; không dùng thay đổi ngoài phạm vi.
2. Chạy các test liên quan hiện có và ghi lại kết quả, phiên bản Python, lệnh chạy và lỗi sẵn có.
3. Lưu snapshot JSON của kết quả cho fixtures trọng yếu: cabinet thẳng, 18+18, 36 nguyên tấm, vách ngắn, mặt bằng L, hậu giật cấp, style conflict và depth context.
4. Không dùng output hiện tại làm chuẩn tuyệt đối nếu test đang ghi một hành vi mâu thuẫn với Constitution; mở riêng một regression/test thay thế để ghi rõ lý do.

**Đạt khi:** biết test nào đang pass/fail trước chỉnh sửa; có baseline so sánh status, boxes, kích thước, trim, gaps và geometry evidence.

### Phase 1 — Tái hiện F-01 và F-02 bằng unit tests

1. Thêm test trực tiếp cho `axes()`/`plates()` khi metadata style thay đổi nhưng geometry giữ nguyên.
2. Thêm test cho `walls()` với cùng khoảng X và phạm vi Y khác nhau.
3. Thêm test đầu-cuối qua `analyse_plan()` để phát hiện khác biệt giữa candidate thô và module cuối.
4. Mỗi test cần nêu kỳ vọng đầu ra và lý do hình học; không đặt assertion theo một implementation cụ thể nếu mục tiêu là quy tắc.

**Đạt khi:** từng vấn đề có thể tái hiện độc lập; test thất bại trước sửa theo đúng lý do dự kiến, hoặc chứng minh giả thuyết không xảy ra (khi đó ghi lại và không sửa theo suy đoán).

### Phase 2 — Sửa tối thiểu logic style/provenance

1. Sửa `oy_sweep.axes()` để giữ nguồn/style trên mỗi đoạn và ngăn ghép bằng chứng giữa các nhóm không tương thích theo chính sách đã test.
2. Tái sử dụng/đối chiếu `cad_style.style_key()` và `interrupted()` thay vì tạo một danh sách style thứ hai không thống nhất.
3. Không xóa source rows; chỉ giới hạn chúng dùng làm bằng chứng nhận dạng chính khi có lý do rõ ràng.
4. Đảm bảo mọi panel vẫn cần bằng chứng hình học đóng; không để style thay cho cap/face.
5. Cập nhật cache key trong các kết quả thực sự phụ thuộc metadata; tách geometry fingerprint và recognition fingerprint nếu cần để không phá compatibility của history.

**Đạt khi:** tests style conflict/context pass; panel thật vẫn được giữ; style-only change làm tính lại đúng các bằng chứng bị ảnh hưởng; lịch sử cũ còn nguyên.

### Phase 3 — Sửa chọn candidate vách/module

1. Trong `walls()`, đổi khử trùng sang footprint đầy đủ và provenance; chỉ so hạng các candidate tương đương.
2. Bảo đảm các vách có phạm vi Y độc lập không loại bỏ nhau chỉ vì cùng X.
3. Rà soát các bước kế tiếp trong `bays()`/`finish_plan()` sau khi thêm candidate: loại candidate trùng thật, không gộp vùng rời, không tạo overlap.
4. Giữ nguyên quy tắc seam 18+18 và phân biệt outer trim/seam nội bộ.

**Đạt khi:** fixture vách cùng X khác Y cho kết quả đúng; toàn bộ regression test tiêu chuẩn, L và trim vẫn pass.

### Phase 4 — Kiểm chứng trường hợp hậu giật cấp hỗn hợp

1. Tạo fixture vừa có candidate chữ nhật thường vừa có hậu giật cấp khép kín.
2. Chạy riêng `bays()`, `stepped_bay()` và end-to-end `analyse_plan()`/`directional_layout.recover()` để phân biệt lỗi nguồn với lỗi phục hồi.
3. Chỉ sửa điều kiện lựa chọn nếu test chứng minh vùng hợp lệ bị mất; không tự động append mọi stepped candidate.
4. Nếu hai cách chia không thể phân định từ hình học, giữ các vùng có đủ bằng chứng và đánh dấu vùng xung đột/không rõ là cần review.

**Đạt khi:** fixture hỗn hợp trả đúng footprint/profile, không lấp lõm, không làm mất module độc lập và không tạo box chồng lấn.

### Phase 5 — Chuẩn hóa evidence và diagnostics

1. Chuẩn hóa trường evidence tối thiểu chỉ khi cần cho các test trên; tránh dựng framework mới không cần thiết.
2. Phân biệt rõ panel candidate, depth witness, cabinet datum và module candidate.
3. Bổ sung reason code/handles trong debug output ở mức vừa phải để có thể giải thích vì sao một đường được dùng hoặc loại.
4. Kiểm tra schema consumers trước khi đổi tên hoặc thêm field; giữ backward compatibility.

**Đạt khi:** lỗi trong test có chẩn đoán đủ để biết face/cap/seam/layer nào là căn cứ; output hiện có không bị phá vỡ.

### Phase 6 — Regression, an toàn và kiểm chứng SketchUp

1. Chạy toàn bộ pytest của `MH_CAD2Module/test/`, không chỉ các test mới.
2. Chạy Ruby tests và RuboCop/rubocop-sketchup trong phạm vi được `AGENTS.md` yêu cầu.
3. Kiểm thử native trong SketchUp với bản sao model: quét mặt bằng thường, 18+18, 36 nguyên tấm, mặt bằng L, hậu giật cấp, style/context nhiễu và một ca không đủ bằng chứng.
4. Xác nhận lệnh Undo/redo và cách chuyển kết quả vào SketchUp không làm thay đổi/xóa CAD nguồn hoặc geometry người dùng.
5. Ghi test command, kết quả, fixtures, trạng thái SketchUp và mọi giới hạn chưa kiểm chứng.

**Đạt khi:** các gate bắt buộc đều pass; không còn regression so với baseline ngoài các thay đổi có chủ ý được ghi rõ; kết quả mơ hồ chuyển sang review thay vì tạo module chắc chắn sai.

## 8. Lệnh kiểm tra dự kiến

Chạy từ đúng môi trường đã cấu hình của repo; nếu project có script/CI chuyên biệt thì ưu tiên script đó và không tự tạo cấu hình chạy song song.

```bash
# Python regression suite (đường dẫn tương đối tính từ thư mục MH_CAD2Module)
python -m pytest test

# Có thể chạy nhóm liên quan trước vòng đầy đủ
python -m pytest test/test_oy_sweep.py \
  test/test_scanned_l_partition.py \
  test/test_stepped_plan.py \
  test/test_plan_depth.py
```

Ruby/RuboCop và kiểm thử SketchUp phải chạy theo lệnh, phiên bản và quy trình đang được repo ghi nhận; không giả định rằng pytest thay thế được các gate này. Ghi rõ nếu không có SketchUp runtime khả dụng.

## 9. Tiêu chí nghiệm thu tổng thể

- [ ] Có test tái hiện cho từng lỗi được xác nhận trước khi sửa.
- [ ] Hình học và kích thước đầu ra không bị snap về độ dày chuẩn; sai số đo thực được giữ lại.
- [ ] Không có module mới chỉ dựa vào khoảng cách bằng độ dày chuẩn mà thiếu chứng minh đóng.
- [ ] Các candidate/vách khác phạm vi Y không bị loại chỉ vì cùng khoảng X.
- [ ] Layer/linetype/color/continuous không bị bỏ qua ở nhánh cần style, đồng thời style không được dùng như kích thước.
- [ ] Cache/evidence bị ảnh hưởng được tính lại khi metadata liên quan đổi; lịch sử cũ không bị xóa.
- [ ] 18+18, 36 nguyên tấm, nẹp ngoài, vách ngắn, chữ L, hậu giật cấp và khoảng trống có chủ ý vẫn đúng.
- [ ] Mọi box/module không đủ bằng chứng được đánh dấu review/provisional, không tự được coi là kết quả chắc chắn.
- [ ] Full pytest, Ruby checks, RuboCop và xác minh SketchUp được ghi kết quả; mọi gate chưa chạy được ghi rõ.
- [ ] Chỉ thay đổi các hàm/file cần thiết; không xóa chức năng, comment hoặc refactor không liên quan.

## 10. Phạm vi file dự kiến

| File | Hướng xử lý | Phạm vi thay đổi |
|---|---|---|
| `worker/oy_sweep.py` | F-01, F-02, F-04, F-06 | Sửa cách giữ metadata/ghép interval, khử trùng vách, đánh giá stepped candidate và diagnostic có giới hạn. Đây là điểm sửa lõi ưu tiên. |
| `worker/cad_style.py` | F-01, F-03 | Ưu tiên tái sử dụng helper sẵn có; chỉ sửa nếu test chứng minh cần chuẩn hóa/compatibility rule. |
| `worker/plan_evidence.py` | F-03, F-05 | Cập nhật cache key chỉ cho evidence có phụ thuộc metadata; giữ phân biệt geometric plate evidence với module boundary. |
| `worker/plan_reader.py` | F-03, F-04, F-05 | Kiểm tra kết quả partial/recovery/fingerprint; không đổi thứ tự luồng nếu chưa có test chứng minh cần thiết. |
| `worker/parallel_index.py` | F-05 | Chỉ thay đổi nếu hợp đồng evidence cần thiết để giải thích candidate; không viết lại thuật toán offset lookup. |
| `worker/cad_datums.py` / `worker/plan_depth.py` | F-01, F-03, F-05 | Dùng làm đối chiếu hành vi hiện có và bổ sung test tương thích; tránh thay đổi nếu không cần thiết. |
| `worker/plan_profiles.py` | F-04 | Ưu tiên dùng nguyên `stepped_bay()` và các kiểm tra profile; chỉ sửa khi fixture hybrid chỉ ra lỗi tại đây. |
| `test/test_oy_sweep.py` | F-01, F-02 | Thêm unit/end-to-end regression cho style conflict và vách cùng X khác Y. |
| `test/test_plan_depth.py` | F-01, F-03 | Bảo vệ quy tắc chiều sâu, style-only cache invalidation và context/hatch. |
| `test/test_stepped_plan.py` | F-04 | Thêm ca hybrid hậu giật cấp; giữ các ca khuyết biên hiện tại. |
| `test/test_scanned_l_partition.py` | F-02, regression | Đảm bảo thay đổi vách không làm rơi nhánh chữ L hoặc lấp khe hở. |

## 11. Những việc không làm trong plan này

- Không thay toàn bộ bộ quét bằng AI hoặc matcher lịch sử.
- Không tự động chuyển mọi khoảng cách 18/36 mm thành module/seam.
- Không chỉnh sửa DIM text, source CAD, scale hoặc transform hình học nguồn.
- Không xóa fallback, hàm nhận dạng cung/hậu giật cấp, trim hoặc chức năng không liên quan.
- Không tự sửa/ghi đè file dữ liệu, cache người dùng, correction history hay các plugin khác.
- Không đánh dấu lỗi giả định là đã xác nhận khi chưa có fixture thất bại trước sửa.

## 12. Kết quả dự kiến sau khi hoàn tất

Sau audit, mỗi sai số đã xác nhận phải có đủ bốn phần: **fixture tái hiện → giải thích bằng chứng/hàm gây lỗi → patch tối thiểu → regression test**. Kết quả cuối không chỉ là “đã ready”; cần chứng minh box module, kích thước đo, depth evidence, seam/trim, khoảng trống và hình dạng hậu giật cấp đều đúng hoặc được đánh dấu cần review khi nguồn CAD chưa đủ bằng chứng.
