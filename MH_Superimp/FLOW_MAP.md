# MH Superimp — file, module and function map

Last checked: 2026-10-22.

This is the structural map of the plugin: path → Ruby module/class → key
functions and responsibility. The implementation currently lives mostly in one
large source file, `src/main.rb`.

## Load and import flow

```text
Plugins/MH_Superimp.rb
  → Plugins/MH_Superimp/src/main.rb
      → MH::Superimp list/configuration and Registry integration
      → MH::Superimp::LiveBoxPreviewTool
          → MH::Geo::Box picking/box geometry (MH_shared)
          → MH::Geo::Fit transforms (MH_shared)
          → SketchUp import/replace transaction
```

The loader registers the extension. `src/main.rb` defines the app logic and tool.
It requires `MH_shared.rb` and uses `MH::ExcelBridge`; when Registry is available,
it also reads Registry rows and calls the `dc_import_pipeline` connector.

## App files and code modules

| Path | Module/class and key functions | Responsibility |
|---|---|---|
| `../MH_Superimp.rb` | `MH::Superimp` extension registration; `LOADER_FILE` | Registers the plugin and points SketchUp to `src/main.rb` |
| `src/main.rb` — list/config | `MH::Superimp`; `registry_import_list`, `load_import_list`, `load_import_list_xlsx`, `import_list`, `reload_import_list`, `sync_registry_menu!`, `show_config_dialog` | Load and edit import catalogue; Registry is preferred, XLSX is fallback |
| `src/main.rb` — lookup/variant | `normalize_import_path`, `rebuild_import_indexes`, `item_for_path`, `swap_map`, `drawer_slide_info`, `resolve_depth_based_import` | Resolve catalogue rows, shortcut variants and drawer size from requested depth |
| `src/main.rb` — integration | `notify_imported_dc`, `watch_placed_instance`, `ensure_registry_runtime`; tool methods `registry_context`, `after_import_dc` | Notify Registry/DC import pipeline and apply product/material context |
| `src/main.rb` — `MH::Superimp::LiveBoxPreviewTool` state/input | `initialize`, `activate`, `deactivate`, `set_import_path`, `onMouseMove`, `onLButtonDown`, `onKeyDown`, `onKeyUp`, `onUserText`, `update_status` | Maintain active import, hover/pick state, typed dimensions and user interaction |
| `src/main.rb` — preview/picking/geometry | `pick_face`, `pick_edge`, `pick_object`, `compute_box_corners`, `compute_plane_corners`, `compute_final_box`, `draw` | Pick source/target geometry, calculate preview bounds and draw the live HUD/box |
| `src/main.rb` — material/swap HUD | `cycle_material_profile`, `apply_current_material_profile_to_selected_dcs`, `draw_material_profile_hud`, `draw_swap_hud`, `try_swap` | Select material profiles, update DCs and switch catalogue variants |
| `src/main.rb` — import/replace | `import_direct`, `import_to_box`, `import_with_plane`, `import_final_box`, `replace_object`, `import_or_replace` | Load SKP definitions and place/scale them in SketchUp |
| `src/import_list.xlsx` | worksheet `ImportList` | Legacy catalogue data used only when Registry has no rows; not source code |

## Shared dependencies

| Path | Module/functions | Responsibility |
|---|---|---|
| `../MH_shared/geometry/box.rb` | `MH::Geo::Box` (`pick_face`, `pick_edge`, box helpers) | Shared face/edge picking and box geometry |
| `../MH_shared/geometry/fit.rb` | `MH::Geo::Fit` (`scale_to_box`, `scale_from_min`) | Shared transforms for fitting imported geometry |
| `../MH_shared/excel_bridge.rb` and shared XLSX helpers | `MH::ExcelBridge` | Read/write the legacy import workbook |
| `../MH_Registry/` | Registry menu/catalog and `dc_import_pipeline` connector | Shared catalogue and post-import integration when installed |

`src/import_list.xlsx` is data, not code. There is no dedicated automated test
suite inside this app; native import, fit, replace and Undo flows must be checked
in SketchUp. At this check, source and installed `src/main.rb` match.
