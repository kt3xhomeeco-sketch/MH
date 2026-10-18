# Verification — 2026-10-16

- Scoped RuboCop: 96 Ruby files, no offenses. Portable suite: 204 tests /
  2444 assertions, no failures or errors.
- Native VBO session: existing SketchUp 2025 process 9504, port 7891.
  `native.json`: 102 checks passed including previous ATT, geometry, fit, linked
  options, component structure, replacement, Undo and rollback regression checks.
- Persistent HUD checks include real Overlay installation/drawing, expanded panel
  tree, actual instance highlight/selection, link editing, pick reactivation,
  signed-gap flip, Undo synchronization and resource cleanup.
- `motion.json`: 8 asynchronous event-loop checks passed using the actual native
  Move and Scale tools. Moving a linked component retained HUD and clearance;
  scaling 600 -> 720 mm normalized the wrapper, retained 18.6 mm board thickness,
  preserved fit and restored with one Undo. Closing HUD retained native Scale.
- `input.json`: 3 real Windows mouse click/wheel checks passed: expanded and
  scrolled the viewport tree with Move active; no module geometry changed.
  Original entities, definitions, selection/camera and global links restored.
- Browser checks passed for 286px compact controls, numeric edits, quick modes,
  flip/read-only protection, close and overflow. Previous inspector/Parametric
  smoke passed. Screenshots: `controls.png`, `native-hud.png` in the output folder.
- Mouse helper built with GCC `-Wall -Wextra -Werror`; it filters only the local
  UI thread's visible tree area and never intercepts keyboard input. Native helper
  was stopped/unloaded for recompilation without starting another SketchUp.
- Closed-window readiness/retry prevents a late HtmlDialog from appearing after
  immediate Tool changes. No orphan utility windows remain after QA.
- The final native draw checks include 1px highlight outlines and stronger filled
  faces per the user's update. No solver or ATT math was changed.
- Packaged through the explicit manifest, then hot reloaded through VBO; final HUD
  opened without adding model geometry. See `reload.json`.

Evidence: `outputs/assembly-035/{gate.log,native.json,motion.json,input.json,browser.json,reload.json}`.
The right panel is a compact native utility window; the tree/highlights are in the
viewport Overlay. Model switches close the HUD; arbitrary nested assembly editing
remains outside the existing top-level assembly contract.

API basis: [SketchUp Overlay documentation](https://ruby.sketchup.com/Sketchup/Overlay.html).
Overlay callbacks only draw; mouse commands and geometry changes run later on the
UI thread, outside those callbacks.
