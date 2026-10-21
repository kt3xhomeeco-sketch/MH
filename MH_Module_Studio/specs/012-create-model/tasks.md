# Tasks

- [x] T01 Main-window button, busy/identity handling and saved-target callback.
- [x] T02 Safe snapshot-based native box generation and own rule stamping.
- [x] T03 Verify portable/native creation, isolation, read/update, rollback and UI.
- [x] T04 Document, package and reload via VBO.

RuboCop: 32 files clean; Ruby: 113 tests / 657 assertions pass. Main Electron
smoke covers adjacent button, request IDs, pending/error recovery and existing
UI behaviors. Native SketchUp PID 31852 via VBO: generator builds six real boxes
from the cached DC snapshot into an empty model, saved unticked board input20mm
and own brace formula80mm; repeated creation independent, update90mm and own
rule recapture pass. Unsupported geometry fails before creation; injected
verification failure rolls back entities and restores selection. Live rule /
template untouched; owned QA entities/definitions removed. Undo not established
through VBO. Reports: outputs/native-create-model-012.json and native-create-ui-012.json.
Main window reloaded with camera/form/tree backup; child Parametric retained.
22 runtime files packaged, excluding developer specs/tests/tools.
