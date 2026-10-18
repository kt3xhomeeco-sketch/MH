# Verification — 032

- Read all 69 own-library SKPs. Eight modules contained multiple thickness inputs
  in one category. User explicitly chose merging into one T1/T2 with shared value.
- Migrated **69/69 files** beneath `D:/Cong viec/Sketchup/DC/Modul_studio`, each
  with a verified backup in its folder's `.mh-backups`. No source DC file under
  `D:/Cong viec/Sketchup/DC/MH` was written. Reopened all 69 SKPs in aborted native
  transactions: canonical metadata persisted, symbols contained only T1/T2,
  stored merged values matched real geometry, and planning was idempotent.
- Cánh Viền Nẹp originally used 14 mm frame / 11 mm panel in a 24 mm envelope.
  Merged T2 uses 14 mm and a generated high-face anchor for the panel. Verified
  edits 14 → 12 → 14 mm preserve the envelope and original intersecting joint.
  The source ATT program remains evidence; the position override is an own rule.
- Updated **three live owned modules** in the current model, including rule
  symbols, exposed metadata and source signatures after library migration.
- Scoped gate: **86 Ruby files** clean; **195 tests / 2384 assertions** passed,
  no failures, errors or skips. Covers alias ownership/ranges, reference renaming,
  merged requests, stable roles, common/private rows and envelope preservation.
- **55 native checks** passed in existing SketchUp PID 19224 via VBO port 7891.
  Includes the prior assembly suite plus parent selection, mixed common values,
  T1 shared edits with fitted geometry, private member edits, copied-wrapper
  independence, single Undo, stale packets, second-member failure rollback,
  editing inside the managed wrapper and merged T2 layered-panel edits.
  Temporary QA geometry was cleaned; original entity attributes/transforms,
  definitions and selection were verified retained relative to each QA run.
- Playwright/installed Chrome: grouped compact options, mixed placeholder,
  automatic apply/queue, private edits and selection switching passed. The
  assembly inspector/Parametric smoke also passed.
- RBZ rebuilt and final runtime/dialogs refreshed via the existing session.

Reports: `outputs/thickness-032/library-audit.json`, `library-migration.json`,
`library-verification.json`, `live-migration.json`, `native.json`, `browser.json`,
`gate.log`, `reload.json`. Backup paths are recorded per file in migration report.

Limit: common automatic grouping in this dialog covers explicitly standardized
T1/T2. Other controls remain private per module. Managed assembly wrappers are
supported; arbitrary nested groups and aggregate Parametric authoring are outside
this change. No full user model was saved, closed or reopened.
