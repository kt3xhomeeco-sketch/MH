# MH Module Studio — file, module and function map

Last checked: 2026-10-22.

Update note (2026-10-23): `UpdateWork.compute` no longer uses `TracePoint`, `sleep(0)`, or `Thread.pass`; workers yield naturally and cancellation is checked at phase boundaries via `UpdateWork.checkpoint` (long pure phases are not interrupted inside, but stale jobs cannot commit). Standalone RuleSystem options edits are a closed two-step combined path: `:options_update` portable work runs in a main-thread cooperative Fiber, yielding only at existing checkpoints after at least 10 ms of phase work and resuming through `UI.start_timer(0.001)`; other calculation kinds keep the background Thread worker. One worker computes edit + plan + compact stamp metadata, then `UpdateWork.prepared!` verifies the live job and flips it out of probe after the cached options result returns; native apply/stamp/verify/commit run exactly once inside the abort-on-error operation. Assembly and grouped edits keep the existing path. The worker omits the duplicated rule hash and seed JSON, and the main thread rehydrates them from `rule_json` before native work. After a successful commit only, the options window warms its member cache from the committed metadata; mismatches leave it cold so refresh reloads. Structural validation runs once per combined phase with a call-local proof; cache hits return owned copies without re-parsing.

When an error message or concrete symptom is available, map it in
[ERROR_MAP.md](ERROR_MAP.md) first (exact message → owning file). Otherwise read
the relevant behavior in [FEATURE_MAP.md](FEATURE_MAP.md), then use
this structural map: file path → Ruby module/class → role and entry functions.
Open only the relevant **Ownership** rows in [ARCHITECTURE.md](ARCHITECTURE.md)
when responsibility is unclear. Investigation limits are in [AGENTS.md](AGENTS.md);
historical feature notes are not part of this reading path.

## Load and request flow

```text
Plugins/MH_Module_Studio.rb
  → MH_Module_Studio/main.rb
      → MH::ModuleStudio::Panel#request / #show
      → MH::ModuleStudio.open / open_parametric
      → feature modules listed below
```

The loader registers the extension. `main.rb` owns the SketchUp menu, dialogs,
request dispatch, model/session observers and UI callbacks. `ui/` contains the
dialog-side HTML/CSS/JavaScript; browser tests are under `test/`.

## Runtime modules

| Path | Module/class and key functions | Responsibility |
|---|---|---|
| `core.rb`, `runtime_manifest.json` | portable Core entry; manifest lists production files | Loads host-independent calculation code without SketchUp UI/model adapters |
| `domain.rb`, `formulas.rb`, `formula_math.rb`, `formula_parser.rb`, `formula_aliases.rb` | `Core` / formula `Program`; parser/evaluator entry points | Normalize inputs, parse/evaluate approved formulas, validate and dispatch calculations |
| `parameters.rb`, `attribute_rules.rb`, `plane_solver.rb`, `position_rules.rb`, `rule_system.rb`, `studio_calculation.rb` | parameter/rule builders and solvers | Learn dimensions and constraints, build parameter plans and decide ATT-vs-geometry calculation policy |
| `symbolic_program.rb`, `parametric_program.rb`, `parametric.rb`, `parameter_rename.rb`, `thickness_symbols.rb` | `SymbolicProgram`, `ParametricProgram`, `Parametric`; rename/evaluation APIs | Keep formulas symbolic, expose editable parameters, rename variables safely and normalize thickness symbols |
| `reader.rb`, `dc_function_capture.rb`, `dc_frames.rb`, `dc_dependencies.rb`, `dc_visibility.rb`, `dc_copies.rb`, `dc_options.rb`, `dc_custom_inputs.rb`, `dc_custom_attributes.rb` | DC reader/capture and ATT policy modules | Read Dynamic Component inputs and preserve dependencies, copies, visibility, options and custom attributes |
| `frames.rb`, `construction_frame.rb`, `geometry_motion.rb`, `inactive_geometry.rb`, `static_geometry.rb`, `envelope_policy.rb`, `axis_rebase.rb` | frame/geometry policy modules | Convert coordinates and bounds; validate scale/motion and preserve inactive/static geometry rules |
| `runtime.rb`, `scale_redraw.rb`, `scale_plan.rb`, `copy_runtime.rb`, `update_work.rb` | `Runtime`; e.g. `apply_trial_update`, `apply_plan` | Apply validated parameter/scale plans inside SketchUp transactions and coordinate redraw/copy work |
| `assembly.rb`, `assembly_tool.rb`, `assembly_math.rb`, `assembly_contacts.rb`, `assembly_envelope.rb`, `assembly_inference.rb`, `assembly_external.rb`, `assembly_containers.rb`, `assembly_file.rb` | `Assembly`; e.g. `records`, `save`, `redraw` | Persist linked modules, infer/contact-fit panels, solve aggregate bounds and maintain assembly identity |
| `assembly_hud.rb`, `assembly_tree.rb`, `assembly_hud_input.rb`, `assembly_inspector.rb`, `assembly_face_picker.rb`, `assembly_presentation.rb`, `contact_display.rb`, `contact_view.rb` | HUD/tree/inspector controllers | Display assembly relationships and route picking/drag input to assembly operations |
| `library.rb`, `library_catalog.rb`, `library_import.rb`, `library_placement.rb`, `library_conversion.rb`, `library_thumbnails.rb`, `library_monitor.rb`, `module_file.rb` | `Library`; e.g. `save_selected`, `export`, `imports`, `place`, `open_hud`; `LibraryPlacement.connected_region` | Save/export/import/place module SKPs; infer a bounded envelope from directly contacting same-layer panels in exploded boxes; catalog, conversion and thumbnails |
| `module_options.rb`, `options_parameters.rb`, `parametric_sheet.rb`, `hud_*.rb`, `ui/` | dialog/HUD controllers and views | Render/edit module options, parameter sheets, assembly HUD and visual controls |

## Main call paths

- Parameter edit: `main.rb` dialog callback → `Parametric`/`ModuleOptions` →
  `Runtime.apply_plan` → `ScaleRedraw`/geometry owners.
- Assembly link or fit: `assembly_tool.rb` / face picker → `Assembly` and
  `AssemblyMath` → contact/envelope owners → `Runtime` redraw.
- Library placement: `Library.place` → `library_hud.rb` modifier/pointer routing →
  `LibraryPlacement.detect` (open cavity first, then connected top-level cabinet
  panels for unmanaged roots, group/component bounds, or a loose face region;
  Ctrl selects Replace) → `placement_math.rb` / `ImportLinks` → native model
  transaction. `MH::Geo` is not a dependency.

Structure reviewed 2026-10-22: free-fit detection invokes
`LibraryPlacement.connected_region` → `PlacementMath.exploded_envelope` before
the individual container fallback. The helper aggregates direct face-contact
siblings only, preventing transitive collection of an entire cabinet bank.

Structure reviewed 2026-10-23: `LibraryPlacement.place` builds Fit/cavity modules
with identity; `fitted_placement` resolves native rule locks omitted from the
lightweight preview and converts physical locked lengths through the host scale.
`fit_built` derives the transform from the actual built definition. Import-template
placement uses `fit_built` too; Replace stages the replacement at identity, then
uses `fitted_placement` and `fit_built` before `resize` (reviewed 2026-10-23).

Structure reviewed 2026-10-22: `RuleSystem.plan` uses
`formula_length_growth` to release only the high envelope edge of an exterior
panel whose manual length formula grows; solver results update that edge after
pinning the low edge and other axes. File ownership and call flow are unchanged.

Structure reviewed 2026-10-22: Parametric Redraw continues through
`ModuleOptions#request` → `UpdateWork.submit` → `Assembly.redraw`. The worker
keeps successful rule JSON raw for canonical caching and wraps worker errors;
module ownership and call flow are unchanged.

Structure reviewed 2026-10-23: `ScaleModelObserver#redraw` still submits a
single `:scale` job, but a `:superseded`/`:cancelled` completion now arms one
generation-scoped `recheck_pending` timer. The recheck waits while another
job owns the `UpdateWork` slot, then recomputes `dirty_roots` from current
signatures before submitting; `reset` and any new commit invalidate it, so a
user Undo is never replayed. `ModuleOptions.redraw_selected` prints its success
status only for `:done`. Native QA entry:
`tools/native_auto_redraw_check.rb`.

Structure reviewed 2026-10-23: `AssemblyModelObserver#schedule_external_sync`
waits while either `ScaleRedraw.pending?` or `UpdateWork.pending?` owns the
model, then retries at 0.1 s under the existing generation guard. A background
external sync therefore cannot submit `:assembly` over a foreground
options/redraw job; it runs only after idle. Regression:
`test/external_sync_options_race_test.rb` uses real `UpdateWork` scheduling with
virtual 0.1 s ticks (40/80/90) to cover 4/8/9 s holds, latest-edit-wins and
stale-generation/Undo paths.

Structure reviewed 2026-10-22: import-link capture probes both sides of the picked
face, ray-tests the six local axes from the valid cavity seed, and clips open
directions to the module envelope. It falls back to the host's real panel boxes
only if a native ray cannot provide a usable cavity; the result is shared by
inset-link detection and Shift fit. Structure revised 2026-10-23: opposed doors
link module envelope planes; `module_faces` triangulates them and `highlight_faces`
selects one filled full host mounting plane, including its opening. Inset matching
keeps real panel faces; ordinary virtual boundaries remain outlined. Last-door removal restores its saved
host span directly when that host has no surviving contacts, preserving unrelated
assemblies' records. `detached_targets?` selects that path; `apply_reservations`
can restrict work to its released hosts and accepts restore targets even if the
old reservation attribute was lost. Connected hosts retain the normal solver.

Native regression entry: `tools/native_import_contact_check.rb` exercises real
Library geometry, ray cavities, deterministic inside/front picks and asynchronous
door deletion on independent copies. `run` and `start_deletion` require
`isolated: true`; their default refusal happens before observer, selection or
model mutation. Run only in an isolated idle SketchUp session, never while the
user is editing. Cleanup removes only its captured copy links and owned
definitions, preserves the prior Assembly busy value and defers while another
update or operation is active. Geometry preservation and a concurrent selection
change are reported separately; a selection change is not a QA geometry failure.
An active user update defers only QA cleanup and keeps its failure visible; the
model is left untouched until a later idle poll.
This does not establish physical mouse-hover usability or a production lag cause.

## Source versus installed copy

Before attributing a live bug to a checkout, obtain runtime evidence for the
implicated method's actual source path and version. A checkout may itself be
inside Plugins, but its location alone does not prove that SketchUp loaded it.
Use the targeted `source_location` example in [BUG_REPORT.md](BUG_REPORT.md),
adapt it to the implicated method, and compare that file with the checkout.
Record an unavailable running-copy check as unverified; do not treat an old
source/installed comparison as current evidence.

Documentation reviewed 2026-10-22: reading order and running-copy checks were
clarified; no runtime code, module ownership or call path changed in this task.
