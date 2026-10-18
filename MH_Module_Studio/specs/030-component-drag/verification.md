# Verification — 030

Verified in the user's already-running SketchUp 2025 session, PID 19224, using
guarded VBO on port 7891. No source SKP or library files were changed. The extra
QA instance launched before the user's latest instruction was closed; subsequent
checks and reload used only the existing session.

- `bundle exec ruby tools/check.rb`: 80 Ruby files, no RuboCop offenses;
  189 tests / 2320 assertions, no failures, errors or skips.
- `test/assembly_inspector_smoke.cjs`: passed in bundled Playwright with local
  Chrome. Numeric edits, opposing-face fit, repeat controls, compact layout,
  face/body instructions and Parametric read/save packets verified.
- `tools/native_component_drag_check.rb`: 26 checks passed on actual SketchUp
  entities. Includes one Undo for grouping plus solve, raw panel remapping,
  instance-local persistence, copied-wrapper independence, rotation, click-only,
  constrained body movement, face offset, Escape, actual PickHelper paths,
  mouse down/move/up, held-face draw calls without handles, assembly merge,
  owned ATT fit, thickness edits, member editing context, wrapper Scale
  reconstruction and repeat direction/count changes.
- Native fixtures were removed after each check run. Original root entities,
  transforms and attributes, definition inventory and selection were retained.
  No full model was saved, replaced or reopened.
- `python tools/package.py`: RBZ built with the updated runtime manifest.
- Final VBO reload: existing model retained, inspector active, no assembly error.
  Exactly one SketchUp process remained.

Reports: `outputs/assembly-030/native-check.json`, `gate.log`, `reload-user.json`.
Browser report remains `outputs/assembly-029/browser-check.json` (shared smoke).

Limits: full-model save/reopen and Redo were not exercised in this session.
Deferred observer timing was previously validated in 028; this pass explicitly
invoked solving after native parameter/Scale operations. Dark-overlay rendering
was exercised through native draw calls; native screenshots omit Tool overlays,
so visual appearance and physical mouse feel still benefit from user review.
Arbitrary nested groups, recovery after Explode, assembled-cabinet Library export
and an aggregate parameter sheet for the wrapper remain outside this change.
