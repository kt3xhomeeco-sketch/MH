# MH Scale - Ke hoach phat trien

## Muc tieu

Tao plugin `MH_scale` la ban clone sach cua `6t2h_stretch_by_area_v1.2.3`, sau do thay doi dan co che chon vertex theo tung buoc nho, moi buoc phai duoc duyet moi lam tiep:

- Khong dung quet vung 2D tren man hinh de bat vertex.
- Dung grip, axis, side va plane de xac dinh vung vertex can di chuyen.
- Huong UI ve sau co the tham khao `smart_scale_lab`: grip box, plane cat, preview, target mode, nhap kich thuoc.
- Khong mang engine cot loi tu `smart_scale_lab` sang `MH_scale`.
- Neu can engine moi, viet rieng trong `MH_scale` theo tung ham nho, test va duyet tung buoc.

## Trang thai nguon tham chieu

### 6t2h_stretch_by_area

Nguon clone:

`C:\Users\mhngu\Downloads\6t2h_stretch_by_area_v1.2.3 - Copy`

Dac diem:

- Loader goc: `t2h_stretch_by_area.rb`
- Tool chinh: `t2h_stretch_by_area/main.rb`
- Chon vertex bang rectangle/polyline 2D tren viewport.
- Stretch bang vector tu diem 1 sang diem 2.
- Co xu ly group/component, curve, construction point/line.

Nhan xet:

- Phu hop de lam baseline clone nhanh.
- Logic cu, de bi "quet vui" vi kiem tra vertex bang `view.screen_coords`.
- Can doi namespace, loader, menu, toolbar, `file_loaded` key de khong dung plugin goc.

### smart_scale_lab

Nguon UI/engine tham chieu:

`C:\Users\mhngu\AppData\Roaming\SketchUp\SketchUp 2025\SketchUp\Plugins\smart_scale_lab`

Dac diem:

- Da co kien truc file tot: box model, plane store, hit test, overlay, stretch adapter.
- Chon grip theo bounding box, tao plane cat theo axis.
- Stretch vertex dua tren `axis`, `side`, `plane[:pos]`.
- Co preview, dimension input, target mode, Dynamic Component redraw/fix.

Nhan xet:

- Phu hop lam nguon hoc UI va engine.
- Chi dung de xem cach to chuc UI/interaction, khong lay engine stretch cot loi.
- Khong copy `vendor/stretch_core.rb`, `vendor/scale_core.rb`, `lab_stretch_adapter.rb` lam engine cho `MH_scale`.
- Khong mang logic DC redraw/fix, multi-plane phuc tap sang khi chua co lenh rieng.
- Neu tham khao mot ham UI nao, phai ghi ro ham nao, ly do, va duoc duyet truoc khi copy/chinh.

## Nguyen tac duyet tung buoc

Plugin se duoc lam theo phase. Sau moi phase:

- Dung lai.
- Bao cao file da sua, hanh vi moi, cach test.
- Cho user duyet moi lam phase tiep theo.
- Khong tu dong nhay sang phase sau du co du thoi gian.

Quy tac nay uu tien hon moi noi dung khac trong plan.

## Kien truc file du kien

```text
MH_scale.rb
MH_scale/
  main.rb
  mh_scale_plan.md
  legacy_area_tool.rb
  box_model.rb
  plane_store.rb
  hit_test.rb
  overlay.rb
  grip_plane_tool.rb
  plane_vertex_selector.rb
  stretch_operation.rb
  icons/
```

### `MH_scale.rb`

Loader SketchUp extension.

Can co:

- `require 'sketchup.rb'`
- `require 'extensions.rb'`
- Namespace `MH::Scale`
- Extension name: `MH Scale`
- Loader path: `File.join('MH_scale', 'main')`
- Version ban dau: `0.1.0`

### `main.rb`

Diem nap plugin runtime.

Can co:

- Require cac file con.
- Tao menu `Extensions > MH Scale`.
- Tao command `MH Scale`.
- Tam thoi co the mo `LegacyAreaTool` o phase 0.
- Ve sau chuyen command sang `GripPlaneTool`.

### `legacy_area_tool.rb`

Clone logic tu `6t2h` de co baseline.

Can doi:

- Class/namespace thanh `MH::Scale::LegacyAreaTool`.
- Message/status text sang `MH Scale`.
- Sua loi cu nhu `UI..messagebox`.
- Bo cac `p` debug khong can thiet.
- Khong dung chung `file_loaded("t2h_stretch_by_area.rb")`.

Muc tieu file nay:

- Chay duoc nhu ban goc.
- Dung de so sanh truoc/sau khi thay engine.
- Khong phat trien UI moi trong file nay.

### `box_model.rb`

Lay y tu `smart_scale_lab/lab_box_model.rb`.

Nhiem vu:

- Tinh bounding box selection.
- Lay axis min/max/length.
- Tao face handles 6 mat.
- Tao plane center/display points.
- Clamp plane vao trong bounding box.

### `plane_store.rb`

Quan ly plane cat.

Nhiem vu:

- Add/delete plane.
- Tim plane theo axis.
- Tao default plane giua bounding box.
- Re-clamp khi object thay doi kich thuoc.

### `hit_test.rb`

Nhan dien chuot dang hover/click vao dau.

Can co:

- Hit grip mat ngoai bounding box.
- Hit plane grip.
- Hit body/edge cua plane.
- Ve sau them hit stretch grip +/- cua plane.

### `overlay.rb`

Ve UI viewport.

Can co:

- Bounding box wireframe.
- Grip 6 mat.
- Plane cat.
- Preview line/ghost khi stretch.
- Mau truc X/Y/Z.

### `grip_plane_tool.rb`

Tool moi thay cho quet vung.

State du kien:

- `:idle`: chua co selection hoac dang hover object.
- `:axis_ready`: hover/click grip de chon axis/side.
- `:plane_ready`: co plane cat.
- `:dragging`: keo grip de stretch.
- `:target`: chon diem target.

Luot thao tac chinh:

1. User chon object/group/component.
2. Tool tinh bounding box.
3. User click grip ngoai: chon `axis` va `side`.
4. Tool tao default plane theo axis, ban dau o giua object.
5. User co the keo plane den vi tri cat mong muon.
6. User keo grip/nhap so/target point.
7. Engine chon vertex nam tu grip den plane va apply delta.

### `stretch_engine.rb`

Khong tao file nay trong giai doan dau de tranh cam giac mang engine lon sang.

Neu ve sau can, chi tao sau khi da duyet rieng. Ten uu tien nen ro nghia hon:

- `plane_vertex_selector.rb`: chi chon vertex theo plane.
- `stretch_operation.rb`: chi apply move/undo operation.

### `plane_vertex_selector.rb`

Module nho, viet moi trong `MH_scale`.

Input:

- `axis`
- `side`
- `plane_pos`
- `entities`
- `parent_to_world`

Nguyen tac chon vertex:

- Neu `side == :plus`: vertex move khi `axis_value(vertex_world) >= plane_pos`.
- Neu `side == :minus`: vertex move khi `axis_value(vertex_world) <= plane_pos`.
- Phase dau chi xu ly vertex/edge trong active entities hoac selection don gian.
- Group/component nested se lam sau khi user duyet.

Can than:

- `make_unique` khi definition co nhieu instance.
- Khong long `start_operation`.
- Khong apply delta hai lan.
- Curve/ArcCurve can test rieng sau.

### `stretch_operation.rb`

Module nho, viet moi trong `MH_scale`.

Nhiem vu:

- Nhan danh sach vertex da chon.
- Apply translation bang `entities.transform_entities`.
- Bọc `model.start_operation` / `commit_operation` dung mot lan.
- Khong xu ly DC, khong scale, khong multi-plane trong phase dau.

## Giai doan thuc hien

### Phase 0 - Tao clone sach

Muc tieu:

- Tao `MH_scale.rb`, `MH_scale/main.rb`, `MH_scale/legacy_area_tool.rb`.
- Doi namespace thanh `MH::Scale`.
- Menu/toolbar rieng, khong dung `t2h_stretch_by_area`.
- Chay duoc trong SketchUp nhu plugin doc lap.

Ket qua mong muon:

- `MH Scale` xuat hien trong menu.
- Chay tool clone duoc.
- Plugin goc `t2h_stretch_by_area` van hoat dong doc lap.

Cong duyet:

- Dung lai sau khi tao clone.
- User test menu/tool trong SketchUp.
- Chi khi user bao OK moi sang Phase 1.

### Phase 1 - Tach baseline va dat khung UI moi

Muc tieu:

- Them `box_model.rb`, `plane_store.rb`, `hit_test.rb`, `overlay.rb`.
- Tool moi co the hien bounding box va 6 grip.
- Chua stretch that cung duoc, uu tien hit-test va ve dung.

Ket qua mong muon:

- Chon object thay box/grip.
- Hover grip dung truc X/Y/Z.
- Khong con can ve vung quet.

Gioi han:

- Chua thay engine stretch.
- Chua copy engine tu `smart_scale_lab`.
- Chi tao UI/hit-test toi thieu.

Cong duyet:

- Dung lai sau khi box/grip hien dung.
- User duyet UI/hit-test moi sang Phase 2.

### Phase 2 - Grip to plane stretch

Muc tieu:

- Them `grip_plane_tool.rb`, `plane_vertex_selector.rb`, `stretch_operation.rb`.
- Click grip chon side.
- Tao plane mac dinh.
- Keo grip de stretch vertex tu grip den plane bang engine viet moi, toi thieu.

Ket qua mong muon:

- Vertex duoc chon bang plane that, khong theo camera.
- Xoay camera khong lam doi tap vertex bi stretch.
- Phase dau co the chi ho tro geometry don gian; group/component nested de Phase sau.

Gioi han:

- Khong mang `SmartScale::StretchCore`.
- Khong mang `SmartScaleLab::StretchAdapter`.
- Khong lam range stretch, multi-cut, DC redraw/fix.

Cong duyet:

- Dung lai sau stretch plane toi thieu.
- User test cube/geometry don gian va duyet moi sang Phase 3.

### Phase 3 - Plane move va input kich thuoc

Muc tieu:

- Cho keo plane den vi tri can cat.
- Them input kich thuoc theo truc.
- Them preview amount.

Ket qua mong muon:

- Dat plane o dau thi stretch tu grip den plane o do.
- Nhap kich thuoc moi tinh ra amount dung.

Cong duyet:

- Dung lai sau plane move/input.
- User duyet moi sang Phase 4.

### Phase 4 - UI giong Smart Scale

Muc tieu:

- Them stretch grip +/- tren plane.
- Them target mode.
- Them dimension overlay.
- Them menu setting co/khong hien plane, grip, preview.

Ket qua mong muon:

- Workflow gan voi `smart_scale_lab`.
- UI gon hon va dung ten `MH Scale`.

Gioi han:

- Chi tham khao UI/interaction.
- Neu copy code UI tu `smart_scale_lab`, phai xin duyet tung file/hunk.
- Van khong copy engine stretch cot loi.

Cong duyet:

- Dung lai sau moi tinh nang UI lon: stretch grip, target mode, dimension overlay.

### Phase 5 - Test DC va nested component

Muc tieu:

- Test Dynamic Component, nested group/component.
- Quyet dinh co can mang DC redraw/fix tu `smart_scale_lab` sang khong.

Ket qua mong muon:

- Stretch khong lam geometry nhay double-delta.
- Khong bat fix/redraw neu chua can.

Gioi han:

- Chua mang DC redraw/fix tu `smart_scale_lab` neu user chua yeu cau.
- Nested component lam tung case nho, test xong moi them tiep.

## Checklist test

- Chon cube don gian, stretch X+ tu plane giua ra ngoai.
- Stretch X-, Y+, Y-, Z+, Z-.
- Xoay camera, lap lai test de dam bao khong phu thuoc viewport.
- Object co edge/face loose.
- Group don.
- Component don.
- Component co nhieu instance, kiem tra `make_unique`.
- Nested group/component cat qua plane.
- Plane gan sat min/max, khong tao kich thuoc am.
- Nhap so bang VCB/inputbox.
- Undo mot lan phai quay ve trang thai truoc stretch.

## Rung ro can tranh

- Dung lai `view.screen_coords` de quyet dinh vertex move.
- Dung chung namespace/file_loaded voi `t2h_stretch_by_area`.
- Sua truc tiep `smart_scale_lab` khi dang tao `MH_scale`.
- Mang engine cot loi tu `smart_scale_lab` sang `MH_scale`.
- Copy `vendor/stretch_core.rb`, `vendor/scale_core.rb`, `lab_stretch_adapter.rb` khi chua co duyet rieng.
- Start operation long nhau.
- Apply delta vao ca transform va vertex cung mot lan cho cung hinh hoc.
- Auto redraw/fix Dynamic Component qua som.

## Quy tac lam viec

- Moi phase nen commit/test rieng.
- Phase 0 phai giu logic clone chay duoc truoc khi thay engine.
- Khi tham khao `smart_scale_lab`, uu tien doc y tuong UI, khong copy engine.
- Moi phase phai dung lai xin duyet, khong tu lam tiep.
- Ten user-facing dung `MH Scale`, khong de sot `SmartScale Lab` hay `T2H`.
- Neu co loi trong SketchUp Ruby Console, ghi lai vao plan hoac changelog truoc khi sua tiep.

## Nhat ky thuc hien

### 2026-07-04 - Chuyen huong: SmartScale UI clone vao MH_scale

Da backup:

- `MH_scale_BACKUP_20260704_100817/`
- `MH_scale_BACKUP_20260704_100817.rb`

Da thuc hien:

- Xoa noi dung runtime `MH_scale` cu.
- Copy nguyen app `smart_scale_lab` sang `MH_scale`.
- Giu lai engine tinh toan cu trong:
  - `MH_scale/mh_engine_legacy/plane_vertex_selector.rb`
  - `MH_scale/mh_engine_legacy/stretch_operation.rb`
- Doi namespace cac file runtime tu `SmartScaleLab` sang `MH::Scale`.
- Doi menu/toolbar hien thi thanh `MH Scale`.
- Sua `MH_scale.rb` de khai bao `PATH` dung toi thu muc `MH_scale`.
- Sua `MH_scale/main.rb` co `load_runtime` de reload qua VBO khong can restart app.

Da reload qua VBO SkAgent MCP:

- Reload OK vao SketchUp PID `16376`.
- Active tool: `MH::Scale::BoxTool`.
- `BoxTool`, `Overlay`, `DimensionRenderer`, `StretchAdapter` load OK.
- Thu muc `mh_engine_legacy` ton tai.

Trang thai hien tai:

- `MH_scale` dang dung UI/interaction cua SmartScale clone.
- Engine stretch hien tai van la engine SmartScale clone.
- Chua thay bang engine legacy cua `MH_scale`; can duyet rieng truoc khi lam.

### 2026-07-04 - Thay single-plane engine vao SmartScale UI

Da sua:

- `MH_scale/main.rb` load them:
  - `mh_engine_legacy/plane_vertex_selector.rb`
  - `mh_engine_legacy/stretch_operation.rb`
- `MH_scale/lab_stretch_adapter.rb`:
  - Nhanh single-plane `StretchAdapter.commit` khong goi `SmartScale::StretchCore.stretch_selection` nua.
  - Thay bang `MH::Scale::StretchOperation.commit`.
  - Vung vertex van theo engine legacy:
    - grip side den truoc plane `0.1mm`
    - origin/axis container coi nhu vertex
    - curve/arc xu ly theo tinh than `t2h`
- `MH_scale.rb` tang version len `0.4.1`.

Da reload qua VBO SkAgent MCP:

- Reload OK vao SketchUp PID `16376`.
- Active tool: `MH::Scale::BoxTool`.
- Smart UI constants OK.
- Legacy engine constants OK:
  - `PlaneVertexSelector`
  - `StretchOperation`
- Selection hien tai dang rong nen chua dry-test selector tren object dang chon.

Gioi han hien tai:

- Da thay engine cho single-plane stretch.
- Chua thay engine cho:
  - box scale
  - range stretch giua 2 plane
  - multi-cut stretch nhieu plane
- Preview hien tai van di theo preview cua SmartScale clone; commit single-plane moi dung engine legacy.

Can user test/duyet:

- Chon cube/group/DC.
- Dung UI SmartScale trong `MH Scale`.
- Test single-plane stretch truoc.
- Neu OK moi thay tiep range/multi-cut/box-scale.

### 2026-07-04 - Phase 0 clone sach

Da tao:

- `MH_scale.rb`
- `MH_scale/main.rb`
- `MH_scale/legacy_area_tool.rb`
- `MH_scale/icon_stretch_by_area_lg.png`

Da sua trong clone:

- Doi namespace tu plugin goc sang `MH::Scale`.
- Doi class tool sang `MH::Scale::LegacyAreaTool`.
- Doi menu sang `Extensions > MH Scale > Legacy Area Stretch`.
- Doi toolbar sang `MH Scale`.
- Doi `file_loaded` key sang `MH_scale/legacy_area_tool.rb` de khong dung plugin goc.
- Sua loi `UI..messagebox`.
- Bo debug `p crv`, `p vts`, `p "check_int_bounds_area"`.

Chua lam:

- Chua thay engine chon vertex.
- Chua them grip-to-plane.
- Chua copy engine tu `smart_scale_lab`.
- Chua test runtime trong SketchUp vi Ruby CLI khong co va VBO SkAgent bridge chua nhat lenh moi.

Can user duyet:

- Reload/restart SketchUp.
- Bat extension `MH Scale`.
- Test menu `Extensions > MH Scale > Legacy Area Stretch`.
- Test chay nhu baseline clone truoc khi sang Phase 1.

### 2026-07-04 - Phase 1 grip, truc grip, plane UI

Da tao:

- `MH_scale/box_model.rb`
- `MH_scale/plane_store.rb`
- `MH_scale/hit_test.rb`
- `MH_scale/overlay.rb`
- `MH_scale/grip_plane_tool.rb`

Da sua:

- `MH_scale/main.rb` load cac module UI moi.
- `MH_scale.rb` tang version len `0.2.0`.
- `MH_scale/legacy_area_tool.rb` them menu/toolbar `Grip Plane UI`.

Hanh vi moi:

- Menu `Extensions > MH Scale > Grip Plane UI`.
- Khi co selection, tool ve bounding box.
- Ve 6 grip tren cac mat X-/X+/Y-/Y+/Z-/Z+.
- Ve truc grip dang net dut noi 2 grip cung truc.
- Hover grip doi trang thai/tooltip.
- Click grip tao plane mac dinh o giua truc do.
- Plane co face mo, vien do/vang va grip o tam plane.
- Phim mui ten: chon truc X/Y/Z theo mapping hien co.
- Phim Delete: xoa plane UI.

Gioi han:

- Chua stretch geometry.
- Chua keo plane.
- Chua chon vertex theo plane.
- Chua mang engine cot loi tu `smart_scale_lab`.
- Chua copy `SmartScale::StretchCore` hay `SmartScaleLab::StretchAdapter`.

Can user duyet:

- Restart/reload SketchUp.
- Mo `Extensions > MH Scale > Grip Plane UI`.
- Chon cube/group/component va kiem tra grip/truc/plane hien dung.
- Xac nhan UI dung huong truoc khi sang buoc tiep theo.

### 2026-07-04 - Phase 2a grip-to-plane vertex move toi thieu

Da tao:

- `MH_scale/plane_vertex_selector.rb`
- `MH_scale/stretch_operation.rb`

Da sua:

- `MH_scale/main.rb` load selector/operation moi.
- `MH_scale/grip_plane_tool.rb` them drag grip va commit move.
- `MH_scale.rb`, `MH_scale/main.rb` tang version len `0.3.0`.

Hanh vi moi:

- Mouse down vao grip se tao/giu plane mac dinh theo truc do.
- Keo grip se tinh amount theo chieu truc world X/Y/Z.
- Tha chuot se move cac vertex nam trong vung tu grip side den truoc plane `0.1mm`.
- Vung chon vertex:
  - Side `:plus`: `vertex_axis_value >= plane_pos + 0.1mm`
  - Side `:minus`: `vertex_axis_value <= plane_pos - 0.1mm`
- Operation chi move vertex bang `entities.transform_entities`.
- `make_unique` component/group definition dung chung truoc khi move.

Gioi han:

- Chua co preview wireframe day du, chi co line keo grip.
- Chua keo/move plane.
- Chua co box scale/range/multi-cut.
- Chua xu ly rieng DC redraw/fix.
- Chua mang engine cot loi tu `smart_scale_lab`.

Da reload/test qua VBO SkAgent MCP:

- Reload OK, `MH::Scale::VERSION = 0.3.0`.
- Constants OK: `PlaneVertexSelector`, `StretchOperation`, `GripPlaneTool`.
- Active tool OK: `MH::Scale::GripPlaneTool`.
- Test kho selector voi selection hien tai:
  - Axis X+, plane giua selection.
  - Clearance `0.1mm`.
  - Bat duoc 20 vertex trong 4 bucket entities.

Can user test/duyet:

- Keo X+ va X- tren cube/group don.
- Undo sau moi lan keo.
- Kiem tra vertex sat plane khong bi move do co khoang chua `0.1mm`.
- Neu dung huong moi sang buoc keo plane/nhap kich thuoc.

### 2026-07-04 - Phase 2b fix DC child origin offset

Van de:

- Khi stretch Dynamic Component, child object nam tron trong vung stretch bi move vertex/face ben trong definition.
- Origin/transform child van o cho cu.
- Sau khi redraw DC, geometry cua child bi lech khoi goc toa do mot doan bang delta stretch.

Da sua:

- `PlaneVertexSelector` them phan loai nested container:
  - `:moving`: child group/component nam tron trong vung grip-plane.
  - `:static`: child nam ngoai vung stretch.
  - `:crossing`: child cat qua plane.
- Child `:moving` duoc dua vao danh sach container move transform.
- Child `:moving` khong bi recurse vao vertex nua.
- Child `:crossing` moi recurse vao trong de chon vertex.
- `StretchOperation` move container bang `entity.transformation = translation(local_delta) * entity.transformation`.
- Vertex loose/geometry cat plane van move bang `entities.transform_entities`.
- Version tang len `0.3.1`.

Ket qua mong muon:

- Child object nam tron vung stretch se di chuyen ca origin/transform.
- Khong con viec face/vertex cua child bi lech khoi origin sau redraw DC.

Da reload/test qua VBO SkAgent MCP:

- Reload OK, `MH::Scale::VERSION = 0.3.1`.
- Active tool OK: `MH::Scale::GripPlaneTool`.
- Console capture khong co loi nen.
- Selection hien tai dang rong nen chua dry-test duoc tren DC dang chon.

Can user test/duyet:

- Chon DC co child object nam tron trong vung stretch.
- Keo grip stretch.
- Redraw DC.
- Kiem tra child object: face/vertex khong bi lech khoi origin.
- Test them case child cat qua plane, vi case nay van recurse vao vertex.

### 2026-07-04 - Phase 2c coi origin/axis obj nhu vertex

Yeu cau:

- Obj nao bi stretch va origin/axis nam trong khu vuc stretch thi origin/axis cung phai move nhu vertex.

Da sua:

- `PlaneVertexSelector` them `origin_containers`.
- Container crossing plane co origin nam trong moving zone se duoc ghi nhan rieng.
- `StretchOperation` them `move_origin_containers`.
- Khi move origin container crossing plane:
  - Doi `entity.transformation` de origin move theo delta.
  - Bu nguoc contents ben trong bang `-delta` local de phan static giu nguyen world position.
  - Sau do vertex nam trong moving zone van duoc move bang delta nhu cu.
- Container nam tron moving zone van move transform ca obj nhu Phase 2b.
- Version tang len `0.3.2`.

Da reload/test qua VBO SkAgent MCP:

- Reload OK, `MH::Scale::VERSION = 0.3.2`.
- `Vector3d#reverse` co san trong SketchUp Ruby.
- Console capture khong co loi nen.
- Selection hien tai dang rong nen chua test stretch tren DC dang chon.

Can user test/duyet:

- Chon lai DC co child crossing plane va origin nam trong vung stretch.
- Keo grip stretch.
- Redraw DC.
- Kiem tra origin child di theo stretch, geometry khong bi double-delta/lẹch khoi axis.

### 2026-07-04 - Phase 2d curve/circle handling theo tinh than t2h

Van de:

- Curve/circle/arc bi stretch bang vertex tho co the bi SketchUp giai lai nhu scale/bien dang.
- `t2h` goc khong bi loi nay vi gom curve rieng va ArcCurve crossing plane duoc explode/recreate truoc khi move vertex.

Da sua:

- `PlaneVertexSelector` gom `edge.curve` thanh bucket rieng, khong dua vertex curve vao vertex bucket thuong.
- Vertex nam tren curve se bi bo qua trong `collect_vertices` de tranh double move khi selection la face.
- `StretchOperation` them `move_curves`.
- Curve nam trong vung stretch duoc move qua `curve.move_vertices`.
- Curve crossing plane chi move cac vertex thuoc moving zone.
- Neu curve la `Sketchup::ArcCurve` va chi bi stretch mot phan:
  - Lay positions hien tai.
  - `explode_curve`.
  - Tao lai curve thuong bang `entities.add_curve(positions)`.
  - Move vertex tren curve moi.
- Version tang len `0.3.3`.

Da reload/test qua VBO SkAgent MCP:

- Reload OK, `MH::Scale::VERSION = 0.3.3`.
- Active tool OK: `MH::Scale::GripPlaneTool`.
- Console capture khong co loi nen.
- Selection hien tai dang rong nen chua dry-test duoc truc tiep curve/circle trong model.

Can user test/duyet:

- Chon object co circle/arc/curve nam trong vung stretch.
- Keo grip stretch.
- Kiem tra circle/arc khong con bi scale/bien dang sai nhu truoc.
- Test case curve nam tron vung va case curve cat qua plane rieng.

### 2026-07-04 - Phase 2e smart-like grip/plane UI va thao tac grip

Van de:

- Grip dang la o vuong 2D, chua giong Smart Scale.
- Plane chua co grid/stretch diamond nhu Smart Scale.
- Cach keo grip dang la giu chuot-keo-tha, khong giong click grip-re chuot-click lan hai cua Smart Scale.

Da sua:

- `Overlay`:
  - Grip ngoai doi sang cube 3D-like.
  - Plane them grid net dut.
  - Plane them diamond grip `-` va `+` hai phia.
  - Active/hover plane stretch diamond co highlight.
- `HitTest`:
  - Them hit-test cho plane stretch diamond.
  - Uu tien hit `plane_stretch` truoc handle/plane body.
- `GripPlaneTool`:
  - Click grip ngoai de arm stretch.
  - Re chuot de preview amount.
  - Click lan hai de commit stretch.
  - Plane stretch diamond cung dung click-re-click.
- Version tang len `0.3.4`.

Da reload qua VBO SkAgent MCP:

- Reload OK vao SketchUp PID `16376`.
- `MH::Scale::VERSION = 0.3.4`.
- Active tool OK: `MH::Scale::GripPlaneTool`.
- Reload result xac nhan:
  - cube_grips: true
  - plane_grid: true
  - plane_stretch_diamonds: true
  - click_move_click_commit: true

Ghi chu:

- Console capture van con 1 loi `NameError` cu tu lan reload hong truoc do. Reload hien tai status OK.

Can user test/duyet:

- Hover/click grip ngoai xem cube grip co dung cam giac hon khong.
- Click grip -> re chuot -> click lan hai commit.
- Click diamond +/- tren plane -> re chuot -> click lan hai commit.
- Kiem tra plane grid/diamond co gan voi Smart Scale hon chua.

### 2026-07-04 - Phase 2f redraw, dimension UI, stretch-region highlight

Yeu cau:

- Tich hop redraw sau khi stretch, dung app co san `MH_redraw`.
- Them UI dimension giong huong Smart Scale.
- Khi keo grip can highlight phan box duoc keo ra.

Da tao:

- `MH_scale/dimension_renderer.rb`

Da sua:

- `MH_scale/main.rb` load `dimension_renderer`.
- `MH_scale/grip_plane_tool.rb`:
  - Sau stretch thanh cong se schedule redraw Dynamic Component.
  - Dung `MH::Redraw` neu load duoc.
  - Khong goi `MH::Redraw.redraw_selection` de tranh popup khi selection khong co DC.
  - Them `draw_stretch_region` highlight volume tu plane den grip side.
  - Them `DimensionRenderer` vao draw loop.
  - Dimension preview cap nhat length theo amount dang keo.
- Version tang len `0.3.5`.

Da reload qua VBO SkAgent MCP:

- Reload OK vao SketchUp PID `16376`.
- `MH::Scale::VERSION = 0.3.5`.
- `DimensionRenderer` OK.
- `MH::Redraw` available.
- Active tool OK: `MH::Scale::GripPlaneTool`.
- View refresh OK.

Ghi chu:

- Console capture van con 1 loi `NameError` cu tu lan reload hong truoc do. Khong phai loi cua ban reload hien tai.

Can user test/duyet:

- Keo grip tren DC va kiem tra DC redraw sau stretch.
- Keo grip xem highlight phan box tu plane den grip side co dung khong.
- Kiem tra dimension X/Y/Z co hien va preview kich thuoc khi keo co dung cam giac Smart Scale hon khong.
