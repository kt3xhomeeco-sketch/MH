# Acceptance and verification

- [x] Save two links among three modules without grouping/replacing instances.
- [x] Show both module names in link panel and native tree, resolve renamed names.
- [x] Rename module instance in compact link panel without rewriting source SKP.
- [x] Explicitly group three modules; link a fourth to a member; explicitly regroup.
- [x] Preserve remapped panel/module anchors and actual contact gaps after regroup.
- [x] Restore declared double-door thickness through nested Parent!LenY formulas.
- [x] Allow exact ATT 200 mm, including existing owned rules with the legacy cap.
- [x] Native repeat edits: 20 → 200 → 50 → 200 → 18.6 → 17.6 mm on both sources.
- [x] Grow linked frame on proven thickness output axis, keep selected 200 mm.
- [x] Portable regression and scoped RuboCop gate; browser controls smoke check.
- [x] Asynchronous Undo/Redo and copied component rename independence checks.
- [x] Package and reload in the existing pinned VBO session (no inspector/options
  dialog was open; updated controls will load on the next open).

Whole-assembly (Ctrl-picked) external relationships cannot currently be flattened
into another group without losing their original aggregate anchor. Keep them
intact and report the limitation on Group. Linking a new module to an individual
member of an existing group supports repeated explicit regrouping.

Validation: 262 portable tests / 2,892 assertions, no failures; 126 Ruby files
pass scoped RuboCop. Browser smoke passes both-name links, rename dispatch,
explicit Group, layout, fitting controls and existing Parametric actions.
Native `outputs/manual-043/native.json` passes repeated 200 mm edits on private
copies of both sources, actual Module Options callbacks, Scale, repeated Group,
frame expansion and exact contacts. `undo.json` passes asynchronous Undo/Redo for
Group, regroup, and independent copied-component rename. `reload.json` confirms
PID 27032, Untitled, original geometry/attributes/selection/camera retained.
RBZ rebuilt at outputs/MH_Module_Studio-0.1.0.rbz. Source SKPs were not rewritten.
