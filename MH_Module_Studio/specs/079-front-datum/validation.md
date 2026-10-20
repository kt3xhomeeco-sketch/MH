# Verification — 2026-10-20

- Actual file `2`, PID 20324: drawer 542370 and host 534817. Saved front record
  91d861e7-e38a-4766-9113-06349ed4533a referenced Len Nóc Trước/part:0006.
  Host front Y=1124.240783938434; old datum Y=1124.8548252916567 mm. The saved
  100 mm clearance therefore physically measured 100.61404135322255 mm.
- Portable eligibility, signed-gap, scope, idempotence and new real-face tests
  pass. Full scoped gate: 224 Ruby files clean; 408 tests, 4540 assertions, no
  failures/errors/skips. Manual, outside, other-slot and measurement-bound records
  are unchanged; newly imported real front faces keep their verified references.
- Native private copies of those exact roots: 11 checks passed. Repeated actual
  clearances 80/100/200/100 mm, all panel thicknesses retained; rotated/mirrored
  nonuniformly scaled copies also measure 80 mm. Aborted QA restores original
  geometry, definitions and raw saved links (model_retained=true).
- Repaired the identified original contact in one existing Assembly transaction.
  Before: 100.61404135322255; after: 100.00000000000000 mm, displayed 100 mm.
  Host geometry unchanged. Drawer depth changed from 479.41020037804276 to
  480.02424173132914 mm to retain its rear contact; width/height unchanged.
  All saved constraints verified. No source SKP file saved or overwritten.
- User had selected an unrelated CAD group during testing. Repair used the
  captured module identities and verified their unchanged transforms/model path;
  the newer selection was left intact. Receipts: outputs/front-079/native.json,
  repair.json; original links are backed up in before-links.json.
- Runtime package rebuilt and verified against source bytes; live Ruby code was
  reloaded through VBO. This is a datum repair, not an adjustment to tolerance or
  an offset subtracted from the user's number.
