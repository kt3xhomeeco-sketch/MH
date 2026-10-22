# Validation — 085

- Scoped gate: 241 Ruby files clean under RuboCop/SketchUp; 436 tests and
  4717 assertions, no failures/errors/skips.
- Four portable door tests verify nominal thickness, unchanged source/target data,
  scaled/mirrored frames, reversed mounting side, explicit alternate thickness
  axes, molded source spans and unchanged ordinary/cavity/template policies.
- Isolated lifecycle test executes actual AssemblyTool.deactivate and production
  HUD draw/overlay extents: inactive/closed/other-model/Library states draw nothing;
  saved record survives deactivation and returning to linking makes it visible.
- Native PID22980 / port7891 reproduced the old locked-door rejection on a private
  18.6 mm thickness-controlled source: full box depth caused the normal envelope
  verification error. The corrected policy replaced a 600 × 500 × 800 mm box
  with a 600 × 18.6 × 800 mm door. A rotated/mirrored/nonuniformly scaled case
  produced 780 × 18.6 × 640 mm while retaining the target front datum.
- The real Library source Canh/Canh trai.skp also passed, with its physical
  17.6 mm thickness, both frames and independent replacement identities.
- Native inherited AssemblyOverlay draw/getExtents were exercised with a unique
  QA overlay: active draws real ContactView dimensions, inactive/closed emits
  no drawing and empty extents, reactivation restores dimensions. These are
  scripted lifecycle/native overlay checks, not manual mouse testing.
- All native fixtures ran in aborted operations with original geometry,
  definitions, links, selection, camera and saved Library preferences retained.
  Receipt: outputs/native-display-door085.json. Its background error entries are
  the deliberately caught negative baseline, not failures in the fixed checks.
- Rebuilt RBZ; all 109 runtime files match sources byte-for-byte.
- Reloaded into both existing SketchUp sessions (22980 and 26160); model, saved
  preferences and pending placements retained. Existing linking Tools were
  inactive and their displays were hidden after reload. No SketchUp/file was
  opened, no user SKP/config rewritten, and no commit/push performed.
