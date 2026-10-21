# Library and native placement HUD

Approved: 2026-10-15. Preserve the Studio, separate Parametric window and native
Module Options. Add a Library subtab for a folder of app-owned SKP modules.

- Recursive folder browser, search, grid/list, adjustable thumbnail size, selected
  preview, refresh, save selected owned module and begin placement.
- Save the complete rule, current inputs and visibility flags inside SKP. Import
  creates a component parent, preserves group panels and independent identities.
- Native viewport radial HUD: eight actual thumbnails/page, folder chooser,
  paging, direct selection, right-click settings with live icon sizing.
- Register an assignable SketchUp Shortcuts command. While browsing or placing,
  consume letters and number selections. Esc or Space exits to Select and removes
  pending preview; already placed modules remain. No preference rewriting/hooks.
- Keep one tool throughout browse/placement. Snap with InputPoint, click to place,
  stay in session for repeated imports. Each placement is one Undo operation.
- Scan and export never save/change the source DC or the user's model. Reject
  stale, invalid or unsupported library payloads without partially placed objects.

Acceptance: settings survive reload; nested folder/filter/size/view work; cancel
pickers releases controls; export/reload retains formulas/hidden inputs; two
imports can be edited independently; Undo/Redo works; HUD draws actual textures;
keyboard callbacks consume keys, actual native shortcuts tested separately.

User steering: coordinates in the detail table must also retain DC ATT formulas.
Accept nonzero panel-local origins by transforming actual local bounds, then
verify against captured geometry. Keep conditional expressions and formula-only
attributes in the sheet. Display a number plus ƒ, double-click edits an executable
mm expression. Never silently replace a failed ATT program with editable inferred
contacts while implying that DC dependencies were converted.
