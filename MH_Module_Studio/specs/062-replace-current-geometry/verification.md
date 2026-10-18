# Verification — 2026-10-17

Initial native read of Khung/Khung noc lot.skp reproduced the reported geometry
mismatch: seven stable parts, including native side thickness 11.306 mm versus
saved 17.6 mm. An independent read-only SDK process (`outputs/source-sdk-062.json`)
read both side boards as 17.6 × 200 × 500 mm and the top as 564.8 × 174 × 17.6 mm.
Later native loads are consistent. This establishes a discrepancy in the loaded
native representation; the exact cause of that native discrepancy is not yet
proven. It does not establish disk-file corruption or blame a user Scale action.

`outputs/native-062.json` passed 15 native checks in PID 17844:

- Actual source -> LC50 replacement with a rotated, mirrored, nonuniformly scaled
  target; actual current oriented dimensions retained and source T = 17.6 mm.
- Parameter formulas remain valid; unselected shared instance retained.
- Raw Group, ordinary DC and whole managed-wrapper targets accepted without
  requiring target ATT. Native adapter picking selects an explicitly selected
  parent for replacement while preserving ordinary member cavity picking.
- Exported file strictly reread from serialized geometry.
- A controlled stale-geometry fixture is rejected by strict file verification,
  restored on its private import copy, fitted and remains parametrically valid.
- Actual source/LC50 file hashes retained; original user object transforms and
  definition GUIDs retained by fixture cleanup.

`outputs/undo-062.json` passed a separate event-loop Undo check on an already
selected component: one Undo restores geometry/name and removes imported MH
attributes. Selection is retained without redundant clear/reselect events.
An earlier unselected-fixture check detected another plugin's ProductContext
selection listener creating a separate metadata transaction after replacement.
That plugin is outside this project's scope and was not modified; native Undo
claims here cover the replacement transaction, not arbitrary later transactions
created by other plugins after a new selection.

Portable recovery tests enforce stable part keys/counts/visibility, reject
inconsistent saved formulas, retain source/current data ownership and confirm
ordinary parameter edits still reject a damaged baseline. Runtime_manifest and
the cold-load test keep the new planner in the portable calculation boundary.

Scoped gate/package completion is recorded in tasks.md.
