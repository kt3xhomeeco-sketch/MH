# Completion and evidence

- [x] Reproduced detail rename erasing the module title on the actual selected
  unowned source. Source geometry/names retained. outputs/repro-050.json.
- [x] Preserve parent title, stable snapshot ID and canonical ATT references.
- [x] Permit file-only rename/save from the original geometry with source signature
  validation, keeping the original SKP. Name editors remain available with a
  pending variable draft; Enter/blur and one-click Save order are verified.
- [x] Browser checks cover dirty symbol retention through rename, queued save once,
  cancellation, invalid-name recovery, regular assembly UI and DC input controls.
- [x] Native QA: 12 checks passed for file-only and owned cases, saved/reopened names,
  actual controller saves, source signature rejection, Library reimport and T80
  edit. Every user's object/name retained. outputs/native-050.json.
- [x] Scoped gate: 146 files lint clean; 295 tests / 3238 assertions passed.
- [x] Updated the live Parametric window through VBO. Captured drafts and uncommitted
  name text; current window had no unsaved drafts. Header and both detail editors
  are enabled, Save enabled and pending=false. outputs/reload-final-050.json.
- [x] Replaced the old reload callback relay with method-local closures in a fresh
  dialog. VBO's reused eval locals can no longer redirect this window's responses
  to a QA panel. Development instructions record this callback lifetime rule.
- [x] Final RBZ archive/manifest verification.
