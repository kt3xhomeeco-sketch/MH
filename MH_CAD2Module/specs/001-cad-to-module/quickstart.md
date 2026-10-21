# Validation and use
Prerequisites: SketchUp 2025, Python 3.12 with ezdxf/openpyxl; ODA File Converter for DWG.
Load MH_CAD2Module.rb or restart SketchUp. Extensions > MH CAD2Module > Quản lý: use the default app-local library (or relocate it), then choose source DWGs once. Dựng sản phẩm opens the small entry dialog. Product labels must exist uniquely in the model.
Choose a generated module and Sửa kết quả. Resize/split/merge; events save automatically. Finish mode after corrections. Vì sao dựng như vậy opens CAD evidence.

0.4.0: Settings > Giai đoạn dựng defaults to Mặt bằng only. Each plan bay becomes a 1600 mm provisional box at Z=0. Checkbox changes auto-save. Check Mặt đứng as well to restore measured-height/tier analysis; elevation requires plan. Existing product geometry is retained when settings change.
Run `python -m pytest test -q`, `ruby test/placement_test.rb`, and `rubocop --config .rubocop.yml ...` scoped to this extension. Native check must run in an aborted SketchUp operation and preserve current labels/model.

0.5.0: after a scan/build, select the product and use Quản lý > Sai. Draw each correct box as a separate root Group/Component, keeping the boxes' relative layout and actual CAD direction. Local origins/axes need no correction. As of 0.5.1, select the boxes directly in SketchUp, then click Kết quả đúng; it reads and validates the current selection at that moment. No separate box-scan button or stored selection is used. Empty selection keeps the session open. Acceptance hides only the accepted source boxes. Hủy sửa restores the old result. Plan-only samples have one base level and replay only identical geometry with provisional 1600 mm height.
