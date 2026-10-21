# Tasks

- [x] T01 Validate, persist and safely evaluate own part-cell formulas.
- [x] T02 Integrate with geometry planning and atomic UI callbacks.
- [x] T03 Restore numeric/ƒ cells and add double-click editing.
- [x] T04 Run core/UI/native checks, document and package.

RuboCop: 31 files clean. Ruby: 112 tests / 654 assertions pass. Electron:
numeric/ƒ cells, double click, Enter, Esc, retained failed input, returned 80mm
preview, variable draft guard and table behavior pass.

Native SketchUp 25 / Ruby 3.2.2, PID 31852 through VBO:
`outputs/native-grid-ui-011.json`: retained state (dirty=false), numeric/ƒ,
double-click formula, Esc, unchanged committed rule/model, ok=true.
`outputs/native-cell-geometry-011.json`: temporary reconstruction of the captured
DC, own formulas produce 80 → 90 → restored 70mm; atomic invalid/stale edits
rejected, envelope/source preserved, sibling unchanged, formula survives own
trial capture. Owned QA geometry/definitions removed. Undo is not established
through VBO. Main user panel/rule retained; current native model remains empty.

Own cell overrides enter the existing plane solver, including contact/exterior
constraints; previous cell edits are tracked to rebuild imported ATT geometry
on repeated updates and clearing a formula. Unsupported scoped ATT evidence
remains separate from executable module-frame expressions. RBZ: 22 runtime
entries; development specs/tooling excluded and source bytes verified.
