# Verification, 2026-10-15

227 source SKPs processed through native SketchUp PID26424 in model 1.skp.
Temporary definitions, root instances and selection were retained after each
aborted conversion/check transaction. All source SHA-256 hashes match.

49 files initially compiled and round-tripped as saved SKPs. Native edits revealed
a 0.1-mm envelope escape allowed by the 0.15-mm measurement tolerance; this could
make the next ATT edit fail. Separate ENVELOPE_TOLERANCE=0.001 mm now rejects such
plans before changes. Groove boundary regression added; 138 tests / 1,648
assertions and RuboCop passed. Updated RBZ packaged and Ruby reloaded in both the
test session and active project session.

Every candidate's editable inputs were tested ±0.1 mm where within range. Each
accepted change was applied to actual geometry, checked, checked for idempotence,
reversed and checked again. 37 files passed; 12 standalone panel/decorative parts
had no isolated internal change compatible with preserving their outer bounds.
Their generated SKPs were moved into .conversion/needs-review after verifying
their own export hash; originals remain in MH. Failed files were not represented
as fully converted parametric modules.

Three further Library imports (Khung Hậu Phủ, LC100, Tủ trên hồi lộ) verified
component parents/group descendants, no residual DC attributes, thumbnails,
separate definitions/IDs for two instances, real parameter edits, invariant outer
bounds and clean repeated calculation. Test geometry removed, selection restored.

Final: 37 usable SKPs; 190 unsupported (109 function-related, 7 rotation/scale,
44 structural/non-panel, 12 fixed-envelope/no internal change, 18 other formula
or geometry diagnostics). Destination report.json/report.csv/report.md and
native-verification.json contain per-file details. Library preference points to
D:/Cong viec/Sketchup/DC/Modul_studio in PID26424 and PID12360.
