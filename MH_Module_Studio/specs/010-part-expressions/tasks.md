# Tasks

- [x] T01 Produce scoped, exact cell expressions with aliases and fallbacks.
- [x] T02 Render expression/result pairs and remove ƒ.
- [x] T03 Verify core/UI regression, native reload and retained state.
- [x] T04 Document and package the runtime update.

Validation: RuboCop 30 files clean; 106 Ruby tests / 621 assertions pass.
Standalone Electron covers visible expressions/results, removal of ƒ, numeric
preview values and existing draft/collapse/scroll behavior. Native SketchUp
PID 31852 via VBO: `outputs/native-grid-ui-010.json` reports exact cabinet
expressions, no ƒ, retained state (dirty=false), unchanged committed rule/model
and ok=true. Native model is empty; display uses the previously read cabinet,
so this check validates HtmlDialog reload/display, not a fresh geometry trial.
RBZ includes the 22 runtime entries, excludes development tooling and specs.
