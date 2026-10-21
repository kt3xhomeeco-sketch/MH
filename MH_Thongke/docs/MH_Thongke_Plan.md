# MH_Thongke - File Plan App

Ngay cap nhat: 2026-05-22

File nay la plan van hanh va nang cap cho app `MH_Thongke`. File nay khong phai ma Ruby, khong duoc SketchUp chay truc tiep.

---

## 1) Muc tieu hien tai

`MH_Thongke` can on dinh 4 viec chinh:

1. Thong ke phu kien, vat lieu, phao chi, guong, kinh, la inox, LED trong model SketchUp.
2. Doi chieu model voi Excel de ra trang thai `OK`, `UPDATE`, `NO SPEC`, `SPEC`; dong Excel thieu PK trong model chi hien `THIEU`.
3. Xu ly nhanh bang `Mini Import` va `Material HUD` ma khong gay lag khi lam viec lau.
4. Luu rule/accept theo app, theo model va theo du an de khi mo file khac trong cung du an van nhan dung.

---

## 2) Trang thai module hien tai

### Core

- `main.rb`: load module, tao menu app.
- `config.rb`: path, normalize ten, fix mojibake tieng Viet, hidden PK settings.
- `performance.rb`: cache scan model, cache selection/view signature.
- `observers.rb`: observer cho selection/model/view, debounce refresh.
- `preferences.rb`: doc/ghi prefs, Excel path, hidden list, rule log.
- `snapshot_store.rb`: luu snapshot theo file SKP va tong du an.

### Thong ke du lieu

- `data_processor.rb`: engine quet model, gom PK/VL, auto sinh LED, bas suot ao, so khop Excel.
- `geometry.rb`: tinh kich thuoc, phao chi, guong/kinh/la inox, tao marker PK.
- `tools.rb`: tool highlight/chon object.

### Giao dien chinh

- `html_builder.rb`: render bang chinh, tab phu kien/vat lieu/tong hop/tong du an/nguon LED.
- `dialog.rb`: callback HtmlDialog, import/export, edit ngay dat, edit ghi chu, settings.

### Mini Import

- `mini_import.rb`: loader.
- `mini_import_context.rb`: lay SP theo `VIEW` hoac `SELECT`, che do `MODUL`/`SAN PHAM`.
- `excel_import.rb`: doc Excel dung chung cho bang chinh, Mini Import va Material HUD; cache theo path + mtime.
- `mini_import_excel.rb`: shim tuong thich cu, khong con la module chinh.
- `mini_import_rules.rb`: rule ten hang, Hafele, synonym.
- `mini_import_table.rb`: tao data bang mini tu model + Excel.
- `mini_import_entities.rb`: tim object va quan ly entity dang co trong model.
- `mini_import_accept.rb`: apply/accept/cancel/ok/undo.
- `mini_import_dialog.rb`: UI mini import va callbacks.
- `mini_import_refresh.rb`: refresh bang mini theo signature.
- `mini_import_menu.rb`: menu Mini Import/HUD.
- `mini_import_position.rb`: luu vi tri mini import va keo ve man hinh chinh neu bi lech.

### HUD

- `material_hud.rb`: overlay goc duoi ben phai viewport, hien vat lieu theo SP dang thay hoac dang select.

---

## 3) Quy tac Excel hien tai

Header quan trong:

- `Ma_SP`: ma san pham, vi du `SP01`, `SP05.8`.
- `Ten_SP`: ten san pham/hang muc.
- `Ma_vat_lieu`: ma vat lieu de so voi material model.

Quy tac ma vat lieu:

- Bo do day sau dau `.` dau tien khi so khop. Vi du `MDFCA.17` khop voi `MDFCA`.
- Neu co dang `MDFCA.17.AC.MS.403PL`, Excel co the la `MDFCA.AC.MS.403PL`.
- Neu `Ma_vat_lieu` co dau ` & `, tach thanh nhieu dong vat lieu. Vi du `PLY.CA & GOSOI` thanh `PLY.CA` va `GOSOI`.

Quy tac dong chu nho duoi ten hang:

- Mini Import va HUD can hien dong nho theo thu tu thong tin trong Excel.
- Dong nho khong chen them `Ten_SP` neu Excel da co noi dung mo ta rieng.

---

## 4) Quy tac ten hang va accept

### Hafele/ray/ban le

- `ray bi giam chan toan phan hafele` + model `ray bi 500` => update thanh `ray bi giam chan toan phan hafele 500`.
- `ray bi giam chan hafele` + model `ray bi 500` => update thanh `ray bi giam chan hafele 500`.
- `ray am giam chan hafele` + model `Ray am - 500mm` => update thanh `ray am giam chan hafele 500mm`.
- `ban le giam chan hafele` + model `ban le A` => update thanh `ban le giam chan hafele A`.
- `phu kien hafele` se suy ra theo model:
  - ray => `ray ... hafele ...`
  - ban le => `ban le ... hafele ...`
  - suot ao => `Suot ao hafele`

### Tu dong dong nghia

- `doang cua` va `gioang cua` la cung mot nhom.
- `ray bi` va `ray am` la loai ray khac nhau, khong tron neu ten loai khac.
- `300`, `400`, `500`, `550` trong ray la chieu dai, co the thay vao ten update.
- `A`, `B`, `C` trong ban le la loai ban le.
- `giam chan`, `giam chan toan phan` la tinh chat.
- `Banh xe cao 60` va `Banh xe 60` khong duoc gop nham neu business rule can tach rieng.

### Accept rule

- Bam status button hoac `APPLY ALL` phai ghi accept rule.
- Sau khi accept, dong do chuyen sang dau tick.
- Rule can dung lai duoc khi doi file Excel khac neu thong tin van khop.
- Rule can luu o:
  - model attribute,
  - file global rule,
  - file JSON du an dat canh folder Excel khi co duong dan Excel.

---

## 5) Quy tac Mini Import

### Hien thi

- Mac dinh hien thi theo `SAN PHAM`.
- Co nut chuyen `MODUL`/`SAN PHAM`.
- Co nut `VIEW`/`SELECT`:
  - `VIEW`: lay SP dang hien trong viewport, loc theo vung nhan dien trung tam.
  - `SELECT`: lay SP tu object dang select.
- Co nut refresh model va refresh Excel.
- Cot chinh: `Ten hang`, `Ghi chu`, `Trang thai`, `SL`, nut `X`.
- Ten hang co dong nho ben duoi lay tu Excel/model.
- Nhom hien thi: `Phu kien` truoc, `Vat lieu` sau.
- Phao chi nam trong nhom `Phu kien`.

### Nut trang thai

- Tat ca nut chu viet IN HOA.
- `UPDATE`, `NO SPEC`, `SPEC` la nut co the bam; `THIEU` chi la trang thai khoa.
- Bam vao nut status duoc coi la chap nhan thong tin hien tai.
- Sau khi chap nhan phai thanh dau tick.
- `APPLY ALL`: chap nhan/update cac dong dang co, khong tao PK moi.
- `OK`: giu nguyen trang thai da thao tac va dong bang.
- `CANCEL`: rollback toan bo thao tac trong lan mo mini import hien tai va dong bang.
- `Ctrl+Z`: undo lenh vua ap dung trong mini import.

### Xoa dong

- Dong `THIEU` co nut `X` de bo dong Excel khoi bang mini neu nguoi dung xac nhan khong can.
- Xoa phu kien chi xoa phu kien, khong xoa object cha.

---

## 6) Add PK

Tinh nang add PK da duoc go khoi MH_Thongke va Mini Import. App nay chi thong ke, doi chieu Excel, accept/update/rename cac entity dang ton tai trong model.

---

## 7) Quy tac vat lieu va phan cung dac biet

### Vat lieu

- Nhom ten trong UI la `Vat lieu`.
- So khop theo material code da bo do day.
- `Ma_vat_lieu` trong Excel khong cho sua trong bang chinh.
- Bang setting co hidden list PK/VL de tat hien thi nhung ten khong can thong ke.

### Phao chi

- La `Ten hang`, khong phai `Ma SP`.
- Nam trong nhom `Phu kien`.
- Don vi `md`.
- Kich thuoc lay theo bounding box: canh dai la chieu dai, hai canh con lai la mat cat.

### Guong, kinh, la inox

- Dem theo tuong/canh co ten co do day `C`.
- Kich thuoc hien thi dang `A x B`.
- `la inox`: don vi `Thanh`, nhung ten hang co the them `md` vao duoi neu rule yeu cau.

### LED

- `Den led`, `Thanh nhom LED`, `Suot ao`, `Gioang cua/Doang cua`: don vi `md` khi la hang tinh theo chieu dai.
- `Nguon LED`: don vi `Cai`.
- `Nguon LED` tinh theo tong chieu dai LED va cong suat W/m.
- Tab `NGUON LED` can hien bang thong ke LED/cam bien hien tai.
- Neu khong thay LED, can kiem tra:
  - object co `ZSU_LED.ten_hien_thi` khong,
  - object co `ABF.statistical-type = length_measuring` khong,
  - ten co chua `LED` khong,
  - hidden list co dang an ten LED khong.

---

## 8) HUD plan

HUD la overlay nhe hon HtmlDialog, dung de xem nhanh vat lieu.

Yeu cau:

- Dat sat goc duoi ben phai viewport.
- Khong co khoang trong duoi thua.
- Hien duoc nhieu SP neu nhieu SP nam trong vung nhan dien.
- Giam vung nhan dien de object chi lo mot phan nho o vien man hinh khong bi lay nham.
- Khi zoom gan, van nhan dien SP dang xem.
- Co cung source mode `VIEW`/`SELECT` voi Mini Import.
- Hien dong nho duoi ten hang giong Mini Import.
- Trang thai:
  - `OK`: nen xanh bien dam.
  - `SPEC`: nen vang.
  - `NO SPEC`/loi: nen do.

---

## 9) Tong du an va snapshot

### File/Snapshot

- Moi file SKP thuoc mot du an.
- Tab `FILE` chi hien du an hien tai.
- Neu 5 file thuoc cung du an, mo bat ky file nao trong 5 file do deu phai thay du 5 file.
- Khong duoc tu dong tro sang Excel cua du an khac.
- Snapshot luu trong `mh_thongke_data.json`.
- Neu co Excel path, can luu them JSON du an trong folder con canh file Excel de dong bo nhieu file cung du an.

### Tong du an

Cot can co:

- `TT file CNC`
- `TT DMVT`
- `Ngay xong DMVT`

Quy tac `TT file CNC`:

- `Xong CNC`: da co entity/file `_ABF_NESTING`.
- `Dang lam CNC`: chua co `_ABF_NESTING`.
- `Vuong thong tin`: sau CNC nhung co SP chua co thong tin CNC/DMVT can thiet.

Quy tac `TT DMVT`:

- `Xong dinh muc`: tat ca PK cua SP da co `Ngay dat`, hoac SP khong co PK.
- `Dang dinh muc`: da co mot phan PK co `Ngay dat`.
- `Thieu thong tin`: ghi chu co `chua co ma` hoac `cho duyet`.

`Ngay xong DMVT`:

- Lay ngay dat cham nhat trong cac hang muc PK cua SP.
- Format ngay hien thi: `DD/MM/YYYY`.

---

## 10) Hieu nang va chong lag

Nguyen tac:

- Khong quet lai model neu signature chua doi.
- Khong rebuild HtmlDialog neu HTML/table key chua doi.
- Mini Import va HUD khong refresh khi SketchUp khong foreground, tru khi nguoi dung bam refresh.
- Excel chi load lai khi path/mtime doi hoac bam refresh Excel.
- Cache visible SP theo camera/view signature.
- Dung debounce observer, tranh refresh lien tuc khi selection/view thay doi.

Can de y:

- `APPLY ALL` va nut status can gom operation theo transaction ngan gon.
- Nhap nhieu o ngay dat/ghi chu phai batch update, tranh update_html sau tung o.
- `Ctrl+Z` phai undo dung mot lan cho ca rule va object add.

---

## 11) Cac loi da gap va diem can kiem tra khi sua

### Mini Import bat len roi tat

Kiem tra:

- `mini_import_position.rb`: toa do co nam ngoai man hinh khong.
- `refresh_import_mini_dialog`: co rescue error va hien loi trong bang khong.
- `@mini_dlg` co bi nil/hidden sau khi update table khong.

### Khong nhan Excel moi

Kiem tra:

- `@import_excel_loaded_path`
- `@import_excel_loaded_mtime`
- `import_excel_paths` theo project trong prefs.
- Co dang tro sang Excel cua du an khac khong.

### Hidden setting khong luu

Kiem tra:

- `hidden_list` trong `mh_thongke_prefs.json`.
- `normalize_hidden_names`.
- Sau khi save settings co clear cache mini/HUD khong.

### Font tieng Viet loi

Kiem tra:

- Tat ca file `.rb` va `.md` can co UTF-8.
- HtmlDialog phai co `<meta charset="UTF-8">`.
- Chu dua vao JS phai qua `js_arg`.
- Text trong HTML phai qua `html_escape`.
- Du lieu cu bi mojibake can qua `fix_vietnamese_mojibake`.

### LED mat thong ke

Kiem tra:

- `@led_per_product` co du lieu sau `process_selection`.
- `ZSU_LED.ten_hien_thi` hoac `ABF.statistical-type = length_measuring`.
- Hidden list co an `LED`, `Nguon LED`, `Thanh nhom LED` khong.
- Tab `NGUON LED` co bang thong ke hien tai.

---

## 12) Uu tien phat trien tiep

1. Lam chac co che reload/refresh VBO agent de validate nhanh sau moi lan sua.
2. Tach tiep `html_builder.rb` neu file qua lon:
   - `html_report_tab.rb`
   - `html_project_tab.rb`
   - `html_settings_tab.rb`
   - `html_led_tab.rb`
3. Giam lag khi nhap nhieu o:
   - bulk edit gom callback,
   - delay update UI den khi blur/commit.
4. Kiem tra dong bo accept rule giua 2 file cung du an.
5. Kiem tra co che project JSON canh file Excel va auto merge khi mo file khac.
6. Viet command debug rieng:
   - dump SP visible,
   - dump mini rows,
   - dump LED rows,
   - dump hidden settings,
   - dump project snapshots.
