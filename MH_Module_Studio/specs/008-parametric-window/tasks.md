# Tasks

- [x] T01 Validate own variable definitions and safe formula dependencies.
- [x] T02 Publish variable and part grids; add synchronized native dialog adapter.
- [x] T03 Build standalone two-area editor and switch 3D Parametric entry points.
- [x] T04 Verify portable regression, Electron UI and existing checks; package.
- [x] T05 Document actual native checks or unavailable bridge limitation.

Validation: 30 Ruby files clean under RuboCop; 102 tests / 597 assertions pass.
Existing UI (68 checks), common-rules UI and viewer (14 cameras, hidden edges)
pass. Standalone window checks pass, including dependencies, read-only computed
values, stale same-template instance reset, invalid symbols, cancellation/error
recovery and injection. Runtime-only RBZ manifest has 22 entries. Offline preview
uses previously captured user module data.

New native verification ran in the current PID 31852 / port 7891: actual separate
window, main viewport without drawer, five inputs/six parts/seven part columns,
add own variable, save alias/formula, computed thickness 20, close/reopen retained
six variables and a read-only value 20. A temporary reconstructed cabinet passed
native trial 20→19 mm, envelope/source-fixture checks, custom/alias exports and
own-trial re-read. Cleanup returned the blank model to zero entities and removed
all exact owned definitions. Reports: outputs/native-window-ui-008.json and
outputs/native-window-geometry-008.json. Undo is not established through VBO.
