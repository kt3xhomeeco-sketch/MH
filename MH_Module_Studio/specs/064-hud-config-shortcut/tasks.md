# Tasks

- [x] Versioned config data, stable local identity and portable SKP matching.
- [x] Persist/remap layout across refresh/restart and file/folder rename.
- [x] Import/Export buttons and native dialogs with cancel/error acknowledgments.
- [x] Preferences shortcut command reuses Parametric workspace.
- [x] Ruby regression tests and Chromium HUD controls/cancel/error checks.
- [x] Native config transfer/rename/restart and model/selection preservation.
- [x] Native own-module vs source DC Scale comparison recorded: both keep
  `parent!Xuong` at 50 mm. Both allow front `parent!LenX` to scale 50 → 100 mm.
  Source ATT/geometry/selection unchanged; no dimension semantics rewritten.
- [x] Scoped gate: 171 Ruby files clean; 331 tests / 4026 assertions passed.
  Additional native CEF check helper linted separately (1 file clean).
- [x] Native CEF callback check confirms both buttons recover from cancellation
  and invalid config. Runtime reloaded through VBO PID17844/port7891. RBZ rebuilt
  and archive-verified at `outputs/MH_Module_Studio-0.1.0.rbz`.
