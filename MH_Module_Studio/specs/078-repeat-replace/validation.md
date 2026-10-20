# Verification — 2026-10-20

- Scoped RuboCop: 222 Ruby files clean. Full Ruby gate: 404 tests, 4524
  assertions, zero failures/errors/skips. Native-tool-only final addition linted.
- Three Library browser suites passed, including single-click selection command,
  explicit Replace button, existing rename/delete refresh, icon settings and batch
  conversion UI. Separate portable command check verifies double-click gesture
  deduplication and no-selection ordinary placement. A HUD test verifies choosing
  a sample replaces preselection without Ctrl.
- Native SketchUp file `2`, PID 20324: 20 checks passed in native.json. Replaced
  three actual DC-like blocks at 600 × 500 × 150 mm; all acquired own rules and
  correct root identities. One Undo/Redo restores/reapplies all three. An injected
  second-target failure rolls back the first and all new definitions. Real tool
  callbacks keep Ctrl Replace active, allow the next plain-click replacement,
  then first Esc returns to Library and second exits. Receipt model_retained=true.
- Native component replacement equivalent: 12 checks passed in external.json.
  Creating an instance from an owned definition and assigning another definition
  both automatically acquire own rules. Native Scale is redrawn to the requested
  envelope. One Undo includes adoption, Redo restores properties. Changing source
  T1 to 24 replaces stale target T1=22; target edit to 26 leaves source=24. Native
  import of an old Library SKP without the new definition seed uses its payload.
  This exercises native APIs rather than physically clicking the Components tray.
  Two subsequent actual native Scale transactions still redraw successfully and
  retain exact T; the adoption observer does not consume pending Scale repair.
- Timing: initial single-target instrumented run ~0.309 s; after redundant stamp
  removal/calculation reuse a comparable single run ~0.159 s. Final three-target
  batch with metadata/observers enabled ~0.576–0.594 s total. These are fixture timings,
  not a guarantee for arbitrary complex models. Full live captures, result checks,
  ATT/T and stale-file checks remain enabled. Cheap legacy identity scans never
  run full ATT evaluation.
- QA files/receipts are under outputs/replace-078; fixture sources were read from
  outputs/direct-links-077/library. Original model geometry/definitions, selection,
  camera and saved links were restored; source SKPs and other plugins untouched.
  QA leaves development operations in Undo history. External native adoption is
  scoped to individual module definitions at model level; assembly payloads and
  unsupported nested edit contexts retain the existing app import workflow.

Final VBO reload: PID 20324, model `2`; adoption_error, scale_error and
assembly_error are null. Runtime RBZ rebuilt from the explicit manifest and
compared byte-for-byte with runtime sources; developer checks/specs are excluded.
