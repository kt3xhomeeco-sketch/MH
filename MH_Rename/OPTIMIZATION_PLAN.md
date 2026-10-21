# Kế hoạch tối ưu hóa app MH_Rename

> Mục tiêu: app **nhẹ nhàng, thống nhất, dễ bảo trì** — không đổi hành vi với người dùng.
> Phạm vi: chỉ thư mục `MH_Rename/` (không đụng `MH_fast_rename`).
> Ngày lập: 2026-06-04

---

## 0. Hiện trạng (đã kiểm chứng)

| File | Dòng | Vai trò | Ghi chú |
|------|------|---------|---------|
| `main.rb` | 2060 | Dialog UI, Quick Prefix/Rename, menu, toolbar, observer toàn cục | File chính |
| `viewport_name.rb` | 2804 | `ViewportNameTool` — tool tương tác, drill-down, geometry cache | Quá lớn |
| `viewport_overlay.rb` | 435 | `ViewportOverlay < Sketchup::Overlay` | ⚠️ **MỒ CÔI** — không file nào require/load |
| `main_backup.rb` | 2389 | Bản backup cũ | Rác |
| `main.rar`, `main1.rar` | — | Archive | Rác |
| `Config1.xlsx`, `Config.xlsx` | — | Config mẫu | Giữ |

**Tổng ~7.700 dòng Ruby, ~5.250 dòng (68%) là rác hoặc trùng lặp.**

Chuỗi nạp hiện tại:
```
main.rb
 └─ require viewport_name.rb
viewport_overlay.rb  ← KHÔNG AI NẠP (chết)
```

---

## 🔴 GIAI ĐOẠN 1 — Dọn rác (rủi ro ~0)

**Mục tiêu:** giảm ~2.840 dòng chết, console im lặng ở chế độ production.

### 1.1 Xóa file chết
- `viewport_overlay.rb` — đã grep toàn bộ Plugins: không file `.rb` nào require/load. Class kế thừa `Sketchup::Overlay` nhưng vì không được nạp nên không bao giờ đăng ký → an toàn xóa. Logic của nó (`parse_name`, `format_display_name`, layout) đã trùng với `viewport_name.rb`.
- `main_backup.rb`, `main.rar`, `main1.rar` — git đã giữ lịch sử.

### 1.2 Gom log debug
7 lệnh `puts` console thật trong `main.rb` (các dòng khác là JS trong chuỗi HTML, **giữ nguyên**):

| Dòng | Nội dung |
|------|----------|
| 73 | `Config loaded from MH_Registry` |
| 76 | `MH_Registry load failed... falling back to Excel` |
| 164 | `Config loaded from legacy Excel` |
| 166 | `Error loading Excel` |
| 527 | `SelectionObserver sync error` |
| 703 | `apply_rename: <err>` |
| 2051 | `MH::Rename reloaded` |

**Giải pháp:** thêm hằng `DEBUG = false` và hàm dùng chung:
```ruby
DEBUG = false
class << self
  def dbg(msg); puts msg if DEBUG; end
end
```
- Trong method của `class << self` (73, 76, 164, 166, 2051): gọi `dbg "..."`.
- Trong class lồng (`SelectionObserver` dòng 527, method `apply_rename` dòng 703): gọi `MH::Rename.dbg "..."`.

**Kiểm thử:** load lại plugin, mở dialog Rename, chạy rename — không còn spam console; bật `DEBUG=true` thấy log trở lại.

---

## 🟠 GIAI ĐOẠN 2 — Thống nhất logic parse tên

**Vấn đề:** logic tách tên bị viết lại **3 lần**, mỗi nơi một kiểu:

| Việc | main.rb | viewport_name.rb | viewport_overlay.rb (sẽ bị xóa GĐ1) |
|------|---------|------------------|--------------------------------------|
| Bỏ system-prefix `_123.` | `clean_name` :177 | inline :1548 | inline :127 |
| Tách prefix theo config | :1623–1642 | :1732–1752 | :129–148 |
| Parse sys/prefix/suffix | — | `parse_name` :1834–1861 | inline |
| Format tên hiển thị | inline gsub | `format_display_name` :1863–1886 | :123–170 |

**Giải pháp:** tạo file `name_parser.rb`, module `MH::Rename::NameParser`:
```ruby
module MH; module Rename; module NameParser
  SYS_PFX_RE = /^(_+\d+)\.?\s*/

  def self.strip_sys_prefix(raw)            # bỏ "_001."
  def self.extract_prefix(name, prefixes)   # tách prefix dài nhất khớp
  def self.parse_name(raw, config)          # -> {sys, prefix, core, suffix}
  def self.format_display(parsed, template) # ráp lại theo template
end; end; end
```
- `main.rb` và `viewport_name.rb` gọi module này thay vì copy-paste.
- **Cache** kết quả `parse_name` theo khóa `entityID + raw_name` (hiện overlay/tool parse lại mỗi frame).
- Sửa typo `@modul_suggestions` → giữ alias `modul_suggestions` để không vỡ config đang dùng.

**Rủi ro:** trung bình — phải đảm bảo 3 cách parse ra cùng kết quả. Viết vài case kiểm tra tay trước/sau.

---

## 🟡 GIAI ĐOẠN 3 — Sửa rò rỉ & hiệu năng

### 3.1 Observer leak (ưu tiên cao)
`main.rb:594–599`:
```ruby
def self.attach_global_observers
  @models_observed ||= {}
  model = Sketchup.active_model
  unless @models_observed[model]
    model.selection.add_observer(MHSelectionObserver.new)  # tạo mới, không lưu ref
    @models_observed[model] = true
  end
end
```
Khi `self.reload` (`main.rb:2050`) chạy lại file → `@models_observed` reset về `{}`, nhưng observer cũ vẫn gắn trên `model.selection` → **chồng observer mỗi lần reload**.

**Giải pháp:** lưu ref observer, remove cái cũ trước khi add:
```ruby
@sel_observer ||= MHSelectionObserver.new
model.selection.remove_observer(@sel_observer) rescue nil
model.selection.add_observer(@sel_observer)
```

### 3.2 Collision detection O(n²)
`viewport_name.rb:1971–2025` — 3 layout mode (direct/scatter/leader), mỗi mode quét cặp nhãn để tránh đè → bậc 2. Với >300 nhãn (`MAX_LAYOUT_ITEMS=350`) bị giật.
**Giải pháp:** dùng lưới không gian (spatial grid) băm theo ô màn hình, chỉ so các nhãn cùng/kề ô → gần O(n).

### 3.3 Cấp phát object trong vòng vẽ
`viewport_name.rb:299–301, 372, 381, 404` — tạo `Geom::Point3d.new` mỗi item mỗi frame → áp lực GC.
**Giải pháp:** tái dùng mảng điểm/buffer; tránh `<<` append trong vòng nóng.

### 3.4 Gộp `view.invalidate`
Trong `onMouseMove`/`onLButton...` gọi `view.invalidate` ~20 lần/khung.
**Giải pháp:** đặt cờ `@needs_redraw = true`, gọi `view.invalidate` **một lần** ở cuối callback.

**Kiểm thử GĐ3:** test với model lớn (>300 đối tượng), đo độ mượt khi rê chuột; reload plugin nhiều lần kiểm tra observer không nhân đôi (selection callback chỉ chạy 1 lần).

---

## 🟢 GIAI ĐOẠN 4 — Tách file & gom UI (dài hạn)

### 4.1 Chẻ `viewport_name.rb` (2804 dòng)
| File mới | Nội dung |
|----------|----------|
| `vn_tool.rb` | lifecycle: activate/deactivate, sự kiện chuột/phím, drill-down |
| `vn_layout.rb` | 3 layout engine + collision (đã tối ưu ở 3.2) |
| `vn_geometry.rb` | translucent cache, edge collection, triangle cache |
| `vn_dialog.rb` | dialog sửa tên (thêm `set_on_closed` để khỏi leak — hiện thiếu ở :2223) |

### 4.2 Gom bảng lệnh menu/toolbar
`main.rb:1965–2015` — mỗi lệnh khai báo callback **2 lần** (1 cho submenu, 1 cho toolbar). Gom thành 1 bảng:
```ruby
COMMANDS = [
  { name: 'Rename Selected', action: -> { rename_selected } , icon: ... },
  ...
]
```
duyệt 1 lần tạo cả menu lẫn toolbar → hết trùng, dễ thêm lệnh.

---

## Thứ tự đề xuất & ước lượng

| GĐ | Nội dung | Rủi ro | Công sức | Lợi ích |
|----|----------|--------|----------|---------|
| 1 | Dọn rác + dbg | Rất thấp | ~30 phút | Nhẹ ngay, console sạch |
| 3.1 | Observer leak | Thấp | ~15 phút | Hết leak khi reload |
| 2 | NameParser dùng chung | Trung bình | ~1–2 giờ | Thống nhất, dễ sửa |
| 3.2–3.4 | Hiệu năng vẽ | Trung bình | ~2–3 giờ | Mượt với model lớn |
| 4 | Tách file + gom menu | Thấp (cơ học) | ~2 giờ | Dễ bảo trì lâu dài |

**Khuyến nghị làm theo thứ tự: GĐ1 → 3.1 → 2 → 3.2–3.4 → 4.** Sau mỗi giai đoạn load lại plugin trong SketchUp để xác nhận hoạt động.

---

## Nguyên tắc an toàn khi thực thi
- Mỗi giai đoạn = 1 commit riêng, mô tả rõ.
- Không gộp nhiều thay đổi vào 1 commit lớn.
- Sau mỗi giai đoạn: `load` lại plugin, chạy thử Rename + ViewportNameTool, báo cáo kết quả.
- Giữ `Config.xlsx`/`Config1.xlsx` nguyên vẹn.
