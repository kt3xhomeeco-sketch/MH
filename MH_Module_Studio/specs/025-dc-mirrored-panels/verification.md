# Verification — 2026-10-15

User steering excludes curved DCs/DADX. No DADX implementation was added and
none of the source SKPs were changed. Scope is signed, axis-aligned child frames
and nominal-parent dimensions with additive/subtractive margins.

Spec Kit prerequisites resolved this spec/plan/tasks. Scoped RuboCop: 55 Ruby
files, no offenses. Full portable gate: 164 tests, 2,136 assertions, zero failures,
errors or skips. Four new tests cover reflected/nonzero local origins, nested
reflection, nominal offsets under resizing, positive dimension magnitudes,
ordered bounds, positive editable length cells, minimum-coordinate cells and
their formula markers, repeated edits/serialization, negative-length rejection,
shear rejection and unchanged rotation guards. Existing displaced-origin tests
also pass with parameter-dependent branches and all six editable cells.

SDK audit: 81 -> 88 compiled source files, no regressions in the prior compiled
set; all 227 current source SHA-256 values match the captures. This count is
portable compilation, not a native conversion guarantee. The audit still has
59 reader failures and 80 compiler failures. Artifacts:
outputs/dc-functions-025/coverage-after.json and summary.json.

Native SketchUp 2025 checks used VBO PID26132/port60477, an owned test model at
outputs/dc-functions-025/1.skp. Retried 24 non-curved files previously rejected
for rotation/mirroring. Four additional exports passed:

- 1.CA Mat ngan keo.skp
- 3. Cánh mở trên.skp
- Tủ bếp trên góc phải.skp
- Tủ bếp trên góc trái.skp

All 69 exported modules were rechecked against the final numeric evaluator:
real geometry edits at +/-0.1 mm where admissible, result verification,
idempotent recalculation, reverse and verification. Final authoritative report
at D:/Cong viec/Sketchup/DC/Modul_studio/.conversion/report.json has
native_verification_status=complete, native_processed=69, native_verified=69,
converted=69, failed=158, source_hashes_verified=true, user_model_retained=true.
All 65 previous exported SKPs are byte-for-byte unchanged. Finalization also
verified all 69 current export hashes and all 227 source hashes.

Each new export additionally passed three consecutive parameter edits
(+0.5 mm, +1 mm, original), with fixed envelope and idempotent calculations.
The drawer front and upward-opening door also passed two consecutive native
Scale/recalculate steps (X factors 1.05 and 0.97).

**Known native boundary:** both upper corner cabinets contain a non-box Viền
detail. After resolving nominal-offset double scaling, their Scale probe reaches
the existing verified-box safety check and is rejected there. These two files
pass parameter editing, but have NOT passed automatic Scale repair. The native
matrix report outputs/dc-functions-025/native-final.json intentionally retains
ok=false and the two explicit diagnostics. The authoritative report records
native_repeat_parameter_edits=true and native_scale_verified=false with the
corresponding reason. Do not describe all native Scale checks as passing.

Drawer source inspection also found flat annotation/helper geometry and nested
scaled containers. Those conversion barriers were retained; no arbitrary
functions executed or geometry/tolerance checks removed to increase counts.
Axis permutations, arbitrary-angle rotations, shear and changing topology remain
unsupported in this path.

Runtime formulas/position_rules/parametric were reloaded through VBO in the
user's existing SketchUp PID21612/port7891. Library refreshed; geometry,
definitions, selection and model modified state were unchanged. Existing saved
rule sets are not silently recompiled: reread source DCs to import new rules.

RBZ rebuilt at outputs/MH_Module_Studio-0.1.0.rbz. Explicit manifest remains
37 entries including 18 Ruby files and native/hud_input.dll; ZIP CRC check
passes. Developer scripts, test models, SDK captures and specs are excluded.

Documentation reference consulted:
https://help.sketchup.com/en/sketchup/constraining-attributes-dynamic-component
describes constrained child dimensions/positions during Scale. Reflection
direction is established from each actual captured transform, not guessed from
names or from that documentation.
