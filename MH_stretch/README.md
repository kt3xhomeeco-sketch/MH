# MH Stretch

MH Stretch la ban clone UI tu Smart Scale Lab, dang dung engine stretch tu ban backup MH_scale cu.

Trang thai hien tai:
- Co UI grip, plane, dimension, hover, highlight vung stretch va target preview.
- Load engine stretch backup trong `mh_engine_backup`.
- Co make unique truoc stretch, chi unique definition dung chung nhieu instance.
- Co tu dong redraw Dynamic Component sau stretch qua app `MH_redraw`.
- Khong co engine scale, SmartScale core hay stretch/scale engine tu Smart Scale.

Runtime files:
- `lab_state.rb`
- `lab_box_model.rb`
- `lab_planes.rb`
- `vendor/vector_font.rb`
- `mh_engine_backup/plane_vertex_selector.rb`
- `mh_engine_backup/stretch_operation.rb`
- `lab_ui_adapter.rb`
- `lab_dimensions.rb`
- `lab_hit_test.rb`
- `lab_overlay.rb`
- `lab_box_tool.rb`

Ghi chu:
- `lab_ui_adapter.rb` chi la cau noi UI sang engine backup.
- Redraw DC chay tre sau commit stretch de tranh xung dot operation, giong `MH_scale_BACKUP_20260704_100817`.
- Khong them Smart Scale engine vao app nay neu chua duoc duyet tung buoc.

