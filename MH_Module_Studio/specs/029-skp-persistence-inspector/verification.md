# Verification

- 028: isolated native contact/offset, fit after 18.6→25 mm, constrained slide,
  four repeat directions, equal clear gaps, Undo/Redo, measured references,
  45° angle, normal drag/cancel and reopened SKP: outputs/assembly-028 reports.
- 029: native SKP create/rename/readback, generated detail expressions, backups,
  stale-file protection, geometry after parameter edits and model preservation:
  outputs/assembly-029/native-file-check.json, all checks true.
- Selected scaled module export, matching live symbol, source tracking and repeat
  saves: native-selected-save.json and final-native.json, all checks true.
- Opposing-face selection automatically fits the actual owned module, 550 mm:
  native-fit-check.json, ok true; utility is visible.
- Browser: inspector inputs, fit checkbox, directions, computed read-only gaps,
  layout, Parametric Read and dirty-variable Save SKP packets passed.
- Gate: 78 files RuboCop clean; 188 Ruby tests / 2313 assertions passed.
- User reload: PID 19224, root/definition/selection/transforms and modified flag
  unchanged; new utility visible. Reports are developer artifacts, not RBZ assets.
- Native gestures exercised through the real Tool callbacks. Physical mouse feel
  remains a user acceptance check; curved faces and nested assemblies are excluded.
