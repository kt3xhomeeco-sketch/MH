# Try the feature

Read a supported module and click PARAMETRIC. Upper grid: edit values or add an
own variable; keep a valid ASCII symbol. To try a dependency, add co_so=19.4 mm
and set the board input formula to co_so+0.6. Apply the variable table, then preview.
Lower grid shows resulting panel sizes/XYZ and scoped ATT evidence. Source model
remains unchanged until an independent trial is created/updated.

Save the own project for persistence. Tick selects public variables; a computed
variable's value is read-only, while its formula can be edited in authoring.
Imported bindings cannot be removed directly. Unsupported behavior categories are
metadata and do not change copies/material/rotation/visibility.

Checks: bundle exec ruby tools/check.rb; ruby test/generate_demo.rb; run the four
test/*smoke.cjs scripts with the development Electron; python tools/package.py.
Native checks must verify the intended live SketchUp/VBO session. This feature's
UI and temporary-fixture trial checks passed on PID 31852; see tasks.md for proof.
