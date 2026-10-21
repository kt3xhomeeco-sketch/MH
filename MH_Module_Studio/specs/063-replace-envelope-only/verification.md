# Verification — 2026-10-17

`outputs/native-063.json` passed 22 checks in SketchUp 2025 PID 17844 through VBO.
These include the source/LC50 and recovery regressions from feature062 plus:

- Malformed own rule/value JSON and an invalid native DC formula on the target.
- A scaled managed wrapper with malformed internal link JSON and an owned child
  whose rule JSON cannot be decoded.
- A target shell with a missing face.
- Malformed global link metadata retained verbatim during detached replacement.
- A failed source fit into a 1 mm cube restores original target geometry and its
  corrupt own metadata; source validity checks are not removed.
- A broken owned target inside a scaled linked parent is replaced at its actual
  size without redrawing its discarded formula; the existing contact verifies.
- Original source SKP hashes and user object transforms/definition GUIDs retained.

The portable policy test covers referenced/unreferenced targets, scoped members
and malformed global records without requiring target ATT/native objects.

`bundle exec ruby tools/check.rb`: 167 Ruby files clean under scoped RuboCop;
326 tests / 3969 assertions, no failures/errors/skips. Existing ordinary assembly
tests run with unchanged default transaction/record/normalization policy.

Undo/package completion is recorded in tasks.md. Geometry-only target acceptance
does not disable source reconstruction or native lock/invertible-3D-frame checks.
