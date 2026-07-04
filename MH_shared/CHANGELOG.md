# MH_shared CHANGELOG

## 1.1.0 - 2026-06-18

- Thêm `MH::Geo::Poly2D`:
  - tạo trục 2D từ normal;
  - chiếu point 3D lên mặt phẳng;
  - tính signed area;
  - cắt/giao convex polygon bằng Sutherland-Hodgman.
- Thêm `MH::Measure`:
  - đo longest dimension theo world bounds;
  - trả kết quả inch nội bộ hoặc mm;
  - đọc tổng `length_mm` từ row Excel/JSON.
- Đổi loader geometry trong `MH_shared.rb` sang danh sách require ưu tiên trước, rồi mới fallback load
  các file còn lại. Việc này chuẩn bị cho các module có dependency rõ như `Poly2D -> Contact/Split`.
- Bắt đầu migration qua facade:
  - `MH_PK_Addon.target_longest_dimension_mm` và `excel_row_length_mm` gọi sang `MH::Measure`;
  - primitive `cp_*` 2D trong `MH_fast_rename` gọi sang `MH::Geo::Poly2D`.
- Thêm `MH::Geo::Cluster`:
  - `UnionFind`;
  - khoảng cách AABB;
  - auto gap threshold;
  - distance clustering có/không dùng grid.
  - `MH_fast_rename` bắt đầu gọi facade cho các primitive distance/threshold.

## 1.0.0

- Loader và các module shared nền: Excel/Xlsx, Text, Bounds, TraverseModel, ModelHub, ModelReader,
  OverlayEngine, NameGrammar, ProductContext, ProjectData, Registry, Settings và `MH::Geo::*`.
