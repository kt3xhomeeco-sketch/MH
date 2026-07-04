# MATERIAL BOOTSTRAP PLAN

> Tự đổ vật liệu (prefill) lúc import DC qua MH_Superimp/VBO sao cho gần đúng nhất,
> giảm việc gõ tay khi user chạy MH_Material_Assign sau đó.

---

## 1. Mục tiêu & nguyên tắc

- **Bootstrap thông minh** ở thời điểm `after_import_dc` → ghi `DA.material` + SU material
  cho mọi `visible_group` theo Excel SPEC.
- **Không thay thế** `MH_Material_Assign` — nó vẫn là source-of-truth, user vẫn final-check.
- **Không động binding schema** (`param_panel`/`param_back`/`param_extra` giữ nguyên).
- **Bỏ heuristic `back_group?`** — thay bằng matching theo Excel per-detail.
- **Hỗ trợ multi-code** (vd `GOTN & MDFCA`) bằng cách đọc cột mô tả trong Excel row.

---

## 2. Vấn đề hiện tại

| | Hiện tại | Vấn đề |
|---|---|---|
| Material per child | `back_group?(group)` theo tên (`/hau\|hậu\|back/`) → `back_material` hoặc `panel_material` | (a) chia 2 nhóm thô, không khớp Excel per-chi-tiết. (b) khi user bind cả 2 attr là panel, tấm Hậu vẫn nhận back_material lệch mã. |
| Multi-code | `assign_multi_material_to_instance` có sẵn nhưng dùng `UI.inputbox` prompt → chỉ chạy được khi user thao tác thủ công. | Không tự dispatch lúc bulk import. |
| Detail aliases | Sheet `ma_detail_aliases` (`pattern → target`) tồn tại nhưng pipeline import có thể chưa dùng đầy đủ. | "Hông", "chân bệ" không match exact Excel. |

---

## 3. Kiến trúc mới — 4-tier resolver

Thay `back_group?` bằng `resolve_material_for_group(group, instance, profile, binding, sp_code, thickness_mm)`:

```
detail_name = nil
detail_name ||= match_key(group.name)                            # tier 1: SU name
detail_name ||= match_key(group.DA['name'])                      # tier 2: DA name
detail_name ||= match_key(formlabel_of_driving_attr(group, instance))  # tier 3: formlabel attr điều khiển thickness
detail_name ||= role_from_binding(group, binding)                # tier 4: role mặc định ('khung' / 'hậu' / param_extra raw)

excel_row = MaterialMatcher.find_matching_row(product_code: sp_code,
                                              detail_name: detail_name)
  # Matcher đã có sẵn: exact → partial substring → keyword → ma_detail_aliases

return nil if !excel_row

raw_code = excel_row['Ma_vat_lieu']
codes = split_material_codes(raw_code)   # "GOTN & MDFCA" → ["GOTN", "MDFCA"]

if codes.length == 1
  return material_name_for_multi_code(raw_code, thickness_mm)
else
  chosen_code = pick_code_for_group(group, codes, excel_row)
  return material_name_for_multi_code(chosen_code, thickness_mm)
end
```

### Tier 3: formlabel của attr điều khiển độ dày

Cho group bất kỳ trong DC, tìm key điều khiển thickness:
1. Lấy `_lenx_formula`, `_leny_formula`, `_lenz_formula` của group.
2. Trục có giá trị **nhỏ nhất** thường là thickness (heuristic). Đọc formula trục đó.
3. Tìm pattern `parent!<key>` hoặc reference `<key>` trong formula → lấy `<key>`.
4. Đọc `_<key>_formlabel` ở definition của instance.

Vd Khung Tủ Lạnh, group hậu rỗng tên:
- `_y_formula = "...-parent!ikqikbwfw7"` → key = `ikqikbwfw7`
- `_ikqikbwfw7_formlabel = "Hậu Độ Dày Tấm Back Thickness"` → contains "hậu" → match Excel `HẬU`.

### Tier 4: role từ binding

Khi 3 tier trên đều miss:
- Key điều khiển nằm trong `param_panel`-specs → `'khung'` (hoặc `'thùng'`).
- Key điều khiển nằm trong `param_back`-specs → `'hậu'`.
- Key trong `param_extra` raw token `=panel`/`=back` → tương tự.
- Không có key → default `'khung'`.

---

## 4. Multi-code dispatch (đa số dùng 1 code, chỉ trường hợp đặc biệt mới dùng nhiều)

Khi `Ma_vat_lieu` chứa `&` (vd `GOTN & MDFCA`), Excel row CÓ thêm thông tin context để biết code nào cho phần nào. Cột thường dùng: `Ten_SP`, `GHI CHÚ`, hoặc bất kỳ trường text mô tả nào trong row.

```
def pick_code_for_group(group, codes, excel_row)
  desc = [excel_row['Ten_SP'], excel_row['Ghi_chu'], excel_row['HOÀN THIỆN']].compact.join(' ')
  desc_key = match_key(desc)
  group_key = match_key(group.name + ' ' + group.DA['name'].to_s + ' ' + formlabel_of_driving_attr(group, instance))

  # Với mỗi code, lấy keywords có thể trong description liên quan đến nó
  # Vd: "GOTN" → ["gỗ tự nhiên", "tự nhiên", "viền", "vien"]
  #     "MDFCA" → ["MDFCA", "cánh chính", "cánh"]
  # Keywords có thể build từ:
  #   (a) chính tên code (GOTN, MDFCA)
  #   (b) MH có sẵn map code → display name (kiểm tra material_assign)
  #   (c) text giữa các code trong description (parsing simple)

  best_pair = pairs.find { |code, kws| kws.any? { |kw| group_key.include?(match_key(kw)) } }
  best_pair ? best_pair.first : codes.first  # fallback code đầu + log warning
end
```

**Lưu ý**:
- Không cố định thứ tự code trong "X & Y" — phải đọc description.
- Đa số row chỉ 1 code → flow đơn giản, không phải parse description.
- Phương án parse description: bắt đầu rule-based đơn giản, refine sau khi gặp case thực tế.

---

## 5. Thay đổi cụ thể trong code

### File: `MH_Registry/connectors/dc_import_pipeline.rb`

| Vị trí | Hành động |
|---|---|
| `assign_profile_materials` | Refactor: dùng `resolve_material_for_group`, xoá `back_group?` dispatch. |
| Mới `resolve_material_for_group(group, instance, profile, binding, sp_code, thickness_mm)` | 4-tier resolver như trên. |
| Mới `resolve_thickness_for_group(group, profile, binding)` | Tìm key driver → xác định `panel_thickness_mm` hay `back_thickness_mm` (cho multi-thickness). |
| Mới `attr_driving_thickness_for_group(group)` | Trục lenx/y/z nhỏ nhất → đọc `_<axis>_formula` → extract key. |
| Mới `formlabel_for_attr(instance, key)` | `instance.definition.get_attribute('dynamic_attributes', "_#{key}_formlabel")` + clean HTML. |
| Mới `pick_code_for_group(group, codes, excel_row, instance)` | Multi-code heuristic. |
| Mới `parse_multi_code_keywords(codes, description)` | Build keyword list per code (simple, rule-based). |
| `back_group?` | Giữ lại nhưng đánh dấu deprecated, không gọi trong import flow nữa. |
| `single-thickness mode` (vừa thêm hôm trước) | Có thể xoá — logic mới đã chọn material per-child theo Excel, không còn cần. |

### File: `MH_Registry/connectors/material_assign.rb`

| Vị trí | Hành động |
|---|---|
| Verify `MaterialMatcher.find_matching_row` | Confirm có lookup `ma_detail_aliases` ở tier substring/keyword. Nếu chưa → patch. |
| Expose helper `match_key`, `material_name_for_multi_code`, `split_material_codes` | Wrap qua `MH::RegistryApp::Connector.get('material_assign')` để dùng từ pipeline. |

### File: `MH_Material_Assign/main.rb` (chỉ verify, không sửa)

- Confirm `MaterialMatcher.match_key` dùng `MH::Text.fold` (normalize lowercase + bỏ dấu).
- Confirm `material_name_for_multi_code(code, thickness)` build đúng format MH đang dùng.
- Confirm `find_matching_row` thứ tự match: exact → substring → keyword → aliases.

---

## 6. Phase rollout

### Phase 1 — Core resolver (mục tiêu chính)
- [ ] Code `resolve_material_for_group` + 4 tier
- [ ] Code `resolve_thickness_for_group` + `attr_driving_thickness_for_group`
- [ ] Refactor `assign_profile_materials`
- [ ] Test SP07 (chân bệ) — 4 detail single-code
- [ ] Test SP55 (Khung Tủ Lạnh) — empty back panel, fallback formlabel
- [ ] Verify `back_group?` không còn được gọi từ import path

### Phase 2 — Multi-code
- [ ] Code `pick_code_for_group` + `parse_multi_code_keywords`
- [ ] Test trên SP có row multi-code (cần tìm SP nào trong SPEC hiện tại có "&")
- [ ] Log warning khi heuristic không chắc

### Phase 3 — Hoàn thiện
- [ ] Bổ sung `ma_detail_aliases` mặc định trong Config cho các keyword hay gặp:
      `hông → THÙNG`, `nóc → THÙNG`, `đáy → THÙNG`, `chân bệ → THÙNG`,
      `len chân → LEN CHÂN`, `vien → VIỀN`...
- [ ] UI bảng học hiển thị preview material code per attr (để user thấy ngay lúc bind)
- [ ] Cache resolve result per (sp_code, group_signature) trong session import bulk

---

## 7. Test matrix

| Case | SP | Detail Excel | Group trong DC | Expected material |
|---|---|---|---|---|
| 1 | SP07 | HẬU | num_nhua / tấm hậu | GONHUA + thickness |
| 2 | SP07 | THÙNG, ĐỢT | chân trước/sau, hông | HDFCA.AC.VERSOI + thickness |
| 3 | SP07 | CÁNH TRÊN, CÁNH DƯỚI | cánh | HDFCA.AC + thickness |
| 4 | SP07 | TRỤ HOA VĂN | trụ | HDFCA.AC.VERSOI + thickness |
| 5 | SP55 | HẬU (qua tier 3 formlabel) | group rỗng tên `""` | GONHUA hoặc tương đương |
| 6 | SP55 | THÙNG (qua aliases "hông") | SP55_Hông Phải/Trái | HDFCA.AC.VERSOI |
| 7 | ? | Multi-code "GOTN & MDFCA" | cánh + viền cánh | viền→GOTN, cánh→MDFCA |

---

## 8. Backward compat & risk

- ✅ Không phá binding schema cũ → row binding hiện tại tiếp tục chạy.
- ✅ Profile shape giữ nguyên (`panel_thickness_mm` / `back_thickness_mm` / `panel_material` / `back_material`).
  Pipeline mới đọc từ Excel, profile chỉ giữ fallback (tier 4).
- ⚠️ Multi-code description parsing có rule-based fallback. Sẽ có case fail → log warning, để user fix qua MH_Material_Assign.
- ⚠️ Tier 3 (formlabel) phụ thuộc DC author đặt label đúng — DC không formlabel → tier này miss, rớt xuống tier 4.
- ⚠️ `ma_detail_aliases` trong Config có thể trống → cần seed defaults ở phase 3.

---

## 9. Definition of done — Phase 1

1. Import SP07 (chân bệ): viewport sau import có đúng material per child khớp Excel (4 row trên).
2. Import SP55 (Khung Tủ Lạnh): tấm hậu (group `""`) nhận GONHUA, các tấm khác nhận material theo Excel — không còn dính `back_group?`.
3. Log `[DCImportPipeline] materials ...` thay vì hiện tại chỉ panel=N back=M, thêm chi tiết per detail (tuỳ chọn).
4. Không có regression khi không có binding hoặc không có Excel data → fallback graceful về flow cũ.
