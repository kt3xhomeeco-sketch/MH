# MH CAD2Module — file, module and function map

Last checked: 2026-10-22.

This is the structural map: file path → module/class → responsibility and key
entry functions. Detailed feature requirements belong in `specs/`; tests/fixtures
are in `test/`.

## Load and scan flow

```text
Plugins/MH_CAD2Module.rb
  → MH_CAD2Module/main.rb
      → MH::CAD2Module.start_scan
      → ScanTool / SelectionSource capture selected entities or a picked area
      → Main#scan / #build_request
      → jobs.rb sends bounded request to worker/main.py
      → worker returns analysis result
      → templates.rb / placement.rb / assembly.rb create or place SketchUp output
```

`main.rb` is the SketchUp coordinator and menu/toolbar entry. CAD interpretation
runs in the local Python worker; runtime code must not launch AutoCAD.

## SketchUp-side Ruby modules (`MH_CAD2Module/`)

| Path | Module/class and key functions | Responsibility |
|---|---|---|
| `main.rb` | `MH::CAD2Module`; `start_scan`, `scan`, `build_request`, `replace_template` | UI orchestration, worker request/response, result handling and output dispatch |
| `scan_tool.rb` | `ScanTool#activate` and mouse handlers | Interactive area selection and scan lifecycle in SketchUp |
| `selection_source.rb`, `scan_annotations.rb` | `SelectionSource.capture`, `build_request` | Capture selected/picked geometry and user annotations into a bounded request |
| `jobs.rb`, `activity.rb`, `partial_plan.rb` | worker/job and activity APIs | Run/cancel analysis jobs, track progress/history, retain partial results |
| `model.rb`, `storage.rb`, `ids.rb`, `settings.rb` | `Model` plus persistence helpers | Model attributes, stable IDs, settings and saved app state |
| `plan_rules.rb`, `plan_profile.rb`, `plan_reference.rb`, `plan_depth.rb`, `plan_components.rb`, `product_height.rb`, `product_labels.rb`, `product_requests.rb` | plan/product rule modules | Build and validate requested module dimensions, references, depths, components and labels |
| `templates.rb`, `assembly.rb`, `placement.rb`, `manual_boxes.rb`, `reference_build.rb`, `registered_elevation.rb`, `cad_views.rb`, `corrections.rb` | output and correction modules | Turn accepted worker results into component/group geometry, place it and apply user corrections |

## Python analysis worker (`MH_CAD2Module/worker/`)

| Path | Key functions/modules | Responsibility |
|---|---|---|
| `main.py` | `read_geometry`, `read_product_list`, `run_plan`, `run` | Parse request geometry and drive the staged analysis pipeline |
| `drawing_scope.py` | `choose_product_plan`, plan-choice helpers | Scope source drawing entities to the selected product/plan |
| `stages.py` | `requested_stages`, `infer_plan_views`, `recognise_plan`, `finish_plan` | Determine stages/views and orchestrate plan recognition |
| `geometry.py`, `views.py`, `cad_views.py`, `cad_registration.py`, `cad_datums.py`, `cad_levels.py`, `cad_profile_datums.py`, `cad_display.py`, `cad_style.py` | geometry/view/registration analyzers | Normalize CAD entities, view relations, datums, levels, display and style evidence |
| `plan_*.py`, `directional_layout.py`, `continuous_bands.py`, `front_bands.py`, `elevation_geometry.py`, `elevation_builder.py` | plan/elevation builders | Infer bays, panels, bands, sections and final module layout |
| `plan_evidence.py`, `plan_reader.py`, `plan_profiles.py`, `plan_depth.py`, `exact_feedback_index.py`, `oy_sweep.py` | evidence/profile/feedback modules | Build bounded evidence, evaluate learned profiles and reconcile feedback |

## Supporting paths

- `ui/`: dialog HTML/CSS/JavaScript for app controls and result review.
- `test/`: Python/Ruby regression tests and named CAD fixtures; choose the test
  matching the worker stage or output module above.
- `tools/`: package/check scripts and native SketchUp verification drivers; not
  runtime app modules.
- `specs/` and `.specify/`: requirements, design and task records, not runtime code.
