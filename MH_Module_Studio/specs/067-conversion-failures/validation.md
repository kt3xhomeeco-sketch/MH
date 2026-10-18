# Verified result and remaining limits

The original job recorded 131 successes / 96 failures from 227 sources. This
repair pass audited the 64 failures outside the user's curved/DADX exclusion.
Only 27 repaired files passed the final portable and native checks and were
published into `D:/Cong viec/Sketchup/DC/Modul_studio/New folder`:
8 ATT parametric modules and 19 geometry modules without geometric ATT controls.
Static geometry modules deliberately have no fabricated thickness parameter.

The cumulative conversion report is 158 successful sources / 69 failures. This
is conversion history, not a current directory count: 20 earlier successful
outputs are no longer at their old paths. Keep their records and list those
paths; do not recreate/overwrite them. The directory contained 111 SKPs before
publication and 138 afterwards. All 111 existing files retained their hashes;
all 227 source SKP hashes were checked. The report was backed up before updating.

Native validation (`outputs/conversion-067/native-check.json`, PID17900/port7891,
SketchUp 2025) loaded all 27 actual SKPs, checked parent Components, edited each
parametric module repeatedly (including T=20 and restoring the original T),
verified native mesh against the computed plan and repeated Scale twice. Every
temporary model operation was aborted and definitions/entities/selection were
checked for retention. All 27 passed. On-disk roundtrip and own payload validity
were also checked separately by the converter before publication.

Final scoped gate: 185 Ruby files, no RuboCop offenses; 343 tests, 4147 assertions,
zero failures/errors/skips. Regression fixtures include the actual failed Vách
and Cánh pano DCs. Formula units are versioned for fresh programs so existing
saved payloads retain their interpretation. No UI code changed in this pass.

Remaining 69 files are explicitly not claimed fixed:
- 32 curved/DADX sources remain outside scope per the user's earlier decision.
- The other 37 retain per-file diagnostics in the updated conversion report.
  These include non-cardinal/root-scaled frames; hidden paneled-door alternatives
  conflicting with the shared T2/output dimension; malformed IF formulas; a
  flat ABF_Offset guide requesting positive solid thickness; CHOOSE out of range;
  formulas inconsistent with captured geometry; and accessory metadata without
  a usable verified input/program. No unsupported ATT is silently discarded.
- Two initially exportable candidates were withheld by stronger checks:
  CÁNH VÁT ĐƠN cannot safely edit its non-box chamfer thickness, and 1.TA Chặn
  Cánh has a mirrored-origin X Scale issue. The final converter now rejects these
  outcomes rather than reporting a misleading successful conversion.

The optional source-DC Scale comparison for Chặn Cánh was inconclusive because
the installed DC engine raised a TypeError during redraw; no native equivalence
claim is made for that file. Its private operation was aborted.

The final RBZ was rebuilt and its archive verified. Targeted runtime reload and
Library refresh ran via VBO PID17900/port7891. All 27 published SKP hashes matched
their verified staging exports; the live catalog contained 138 entries. Reload
retained the user's model entities, definitions and selection.
