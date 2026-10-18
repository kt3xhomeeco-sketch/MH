# Full Parametric for the selected cabinet

Created: 2026-10-14. User request: convert existing DC attributes of KHUNG BẾP DƯỚI into a full Parametric table.

## User scenarios
- P1: Read the selected cabinet and edit its five DC inputs (board thickness, brace height, back thickness, back setback, groove depth) in Parametric.
- P1: Inspect converted root/intermediate/leaf attributes, actual envelope, computed panel dimensions/edge offsets and their formulas without ambiguous duplicate group names.
- P2: Preview changes, navigate a computed row to Quy tắc module, and create/re-read an independent own trial with the same rules and public input selection.

## Acceptance
Rear brace clearance 26→28 mm when back thickness 8→10; groove-derived DAYCAO and brace height/position update. Unsupported/non-geometric text formulas are retained with an explicit status, never executed as Ruby. Original geometry/attributes remain unchanged.

## Requirements and boundaries
Use the existing safe own ATT engine and complete captured dictionaries; group all scopes. Root dimensions stay measured/read-only for MH_stretch. Input export checkboxes stay untitled. No repeated geometry constraints are imposed by computed table rows. Table supports a wide expanded view while retaining the 3D workspace. Scope is this existing verified box cabinet, not arbitrary DC functions/topology.

## Success criteria
Portable conversion/current-value tests, existing/new Electron interactions, RuboCop and native VBO checks pass. Runtime-only RBZ updated.
