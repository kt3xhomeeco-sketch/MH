# Verification

Native SketchUp2025 PID17292, Untitled, through VBO. Only private temporary
imports/fixtures were changed; library sources and user roots/selection retained.

- `outputs/native-058.json`: three current cabinet SKPs, preview16–28ms;
  immediate first build1.06–1.12s; prepared/cached build0.21–0.29s. All actual
  builds still validate native geometry. Cached payload rejects corrupted mesh;
  source fingerprint rejects files changed after preview; definitions independent.
- `outputs/place-058.json`: complete placement including commit, after payload
  preparation:0.34s free /0.73s cavity. One native Undo removes each import,
  retaining original roots and selection. These are measured samples, not a
  guarantee for every SKP or replacement assembly.
- `outputs/hud-058.json`: native icon choice18ms, two-stage Escape retained.
  Cooperative worker allows regular native timer callbacks while preparing;
  preparing the legacy program can still take about1.5s in the background.
  Foreground placement disables that pacing; immediate first clicks still wait.
- `outputs/plan-058.json`: default legacy import and a Parametric T1=20 target
  both stamp once, save all23 upgraded input values and satisfy exact native
  formula geometry. Saved inputs cannot be mistaken for a missing default.
- `outputs/auto-058.json`:20 native checks pass, including five opposing contacts
  at exact3mm gaps, no movement/grouping, duplicate suppression, editable gaps,
  rotated/reflected geometry, obstruction and independent assembly scope.
- `outputs/ui-058.json`: real HtmlDialog shows the automatic-selection button
  at47px from the top, outside collapsed details. Normal callbacks restored;
  utility is open and native Select remains active.
- Browser assembly workflow and Library/HUD view/settings checks pass.

Portable checks cover one-worker concurrency, shared normalization with placement,
private copied strings/data, bounded eviction, uncached errors, worker failure
retry and foreground cleanup; real retained legacy Copies still expands correctly.
