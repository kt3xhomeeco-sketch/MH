# Verification — 2026-10-15

Spec Kit prerequisites resolve this feature directory with plan/spec/tasks present.
No extension hooks/checklists requiring an extra approval are configured.

Scoped gate: 47 Ruby files clean under RuboCop; 145 tests / 1,692 assertions,
zero failures/errors/skips. Seven new portable tests cover nonuniform, uniform,
repeated Scale; saved edited inputs; own spreadsheet formulas; geometric
thickness/contact rules; unsafe shrink; missing values/topology; and retention
of the normal ATT baseline rejection outside the dedicated redraw path.

Native SketchUp 2025 PID26424/model 1.skp, through pinned VBO:
`outputs/native-scale-019.json` has ok=true and cleanup=true.
Actual component transformation changes in native transactions triggered the
installed observer/timer automatically. Verified physical envelope, saved inputs,
post-Scale ATT idempotence and further parameter edits. Tested shared-definition
copies, separate identities, multiple modules, rotated/nonuniform placement,
reflection, repeated uniform scaling, move/rotation ignored, one-step Undo/Redo,
and two Undo followed by two Redo without losing remaining history. A real
converted Library module (Khung Hậu Phủ) also passed.

Rejection checks use native geometry and Undo: too-small Scale is rolled back;
an injected verify_result error after actual geometry writes restores the
original definition, transform, shape and parameter values. Only during these
synchronous rejection tests, UI.messagebox is captured instead of displaying a
blocking dialog, and the original UI/runtime methods are restored in ensure.
Test components/new unused definitions removed; original roots/selection retained.

These native checks use the same transformation and transaction API observed
after Scale; they do not claim a physical mouse-drag session was automated.

Ruby reloaded through VBO in PID26424 (test model) and PID12360 (working project).
No geometry edited in PID12360. Explicit RBZ manifest now has 35 runtime entries
and seventeen Ruby files including the loader; developer tools/specs/tests excluded.

Boundaries remain explicit in spec/README: owned top-level box modules with
translated ATT or own geometric rules; inner-panel/nested-module Scale and
observation-only engines are not supported. Unsupported changes are rejected
with a diagnostic and whole-transaction Undo, rather than accepting partial repair.
