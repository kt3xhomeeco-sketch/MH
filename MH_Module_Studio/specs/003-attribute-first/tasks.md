# Tasks

- [x] T001 Record ATT-first precedence and bounded initial support.
- [x] T002 Retain intermediate ATT in native and bridge snapshots.
- [x] T003 Implement restricted expression interpreter and formula geometry plans.
- [x] T004 Integrate ATT-first selection, comparison fallback and provenance.
- [x] T005 Complete regression and UI checks, including one-sample operation.
- [x] T006 Reload correct VBO instance, verify native reading/preview without editing source.
- [x] T007 Update runtime package and record actual limitations.

Validation: 80 Ruby tests / 455 assertions, 21 scoped RuboCop files without
offenses, and 39 UI checks passed. A bridge fixture verifies intermediate
attributes and instance overrides. A real one-state cabinet in SketchUp PID8120
produced five ATT rules from 29 geometry expressions (48 expressions read in all).
Native preview, independent trial creation and repeated trial edit passed;
metadata matched, envelope stayed 600 x 500 x 850 mm, and the source was unchanged.
The owned test copy and private definitions were removed. Undo was not tested or
claimed. The 12-entry RBZ contains only runtime sources, UI and README.

Unsupported boundary: opaque functions, rotated/mirrored frames, non-unit root
scale, and geometry formulas below a scaled ancestor remain explicit fallback
cases. Positive scaled wrappers around ordinary leaves and duplicate group names
are supported and tested. General offset regression remains outside this change.
