# Verification — 2026-10-15

User clarified Ký hiệu, not the display-name column. Parametric.edit_variables
now migrates own variable and manual detail references before validation using
stable variable IDs. Generated expressions keep their existing alias mechanism.
ParametricSheet's fallback evaluator now resolves mixed-case aliases without
dropping conditional/nonlinear generated cell expressions.

New pure component parameter_rename.rb is declared in the calculation manifest.
It does not load host APIs or reopen numeric Program. Original binding keys,
source ATT text and source program data remain intact. Migration operates on
copies; invalid names/duplicates reject the edit without changing saved rules
or submitted draft data.

Spec Kit prerequisites resolved this feature's spec/plan/tasks. Scoped gate:
69 Ruby files inspected, no RuboCop offenses; 177 tests / 2,239 assertions, zero
failures/errors/skips. Seven new scenarios cover generated/manual expressions,
dependent custom variables, reordered rows, simultaneous symbol swaps, case,
scientific numbers, functions, similar prefixes, root/local scope fields,
serialization, atomic rejection, display-name independence and conditional
generated expressions. Core dependency/data-isolation tests remain green.

Actual SketchUp 2025 check used a newly started owned PID9612, VBO port55545,
outputs/rename-027/1.skp. Created an independent component from the readable
nested fixture, then saved symbol changes through Panel.request(save_variables).
Checked giang -> CaoGiang, dayvan -> VanDay, hauday -> HauDay and a custom sum
variable. Manual detail formula becomes `CaoGiang + 10 + TongDay * 0`; custom
formula becomes `VanDay + HauDay`; generated and conditional detail cells show
the new symbols. Original rule and source ATT data remain unchanged.

Three native edits after rename (giang 90 -> 80 -> 70) produced brace heights
100 -> 90 -> 80 mm, with fixed envelope, stable repeated calculation and renamed
formulas retained after decoding the rule stored on the component. Temporary
entities/definitions were removed and original selection restored. Report:
outputs/rename-027/native-check.json, ok=true, model_retained=true.

Reloaded the new helper, Parametric and ParametricSheet through VBO in the user's
existing PID21612/port7891; numeric rename check passes, model geometry,
definitions, selection and modified state unchanged. Dialog JavaScript did not
change; the existing Apply variables/revision flow is retained.

RBZ rebuilt from the explicit manifest: 50 entries including 30 Ruby files;
ZIP CRC and content-to-source checks pass. No source DC/library files converted
or overwritten. Existing module coverage/geometry limits are unchanged.
