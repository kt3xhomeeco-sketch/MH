# Feature Specification: Position rules inside Quy tắc module

Created: 2026-10-14. User: show brace-to-side edge offsets in Quy tắc module.

## User stories and acceptance
1. P1: Selecting a part in the tree or 3D shows its face/edge relationships in Quy tắc module, including reference part/edge, measured mm, source, controlling inputs and supported symbolic expression.
2. P1: A real rear brace shows rear clearance 26 mm as Hậu dày + Hậu lùi. Changing back thickness 8→10 updates clearance to 28; it is never stored as a fixed 26 mm driving constraint.
3. P2: Existing contact/manual editing, parameter testing and project/trial persistence continue working. Older unified rules gain descriptions on load.

## Requirements
- Derive expressions from safe ATT syntax and scoped node identities, not sample regression or names.
- Exact affine expressions only; conditional/nonlinear expressions keep original ATT evidence without an invented simplified equation.
- Show current measured geometry and distinguish geometry observations from authoritative ATT.
- Own position entries are descriptive views of the existing engine; do not impose extra constraints or mutate source geometry.
- Group all relevant rules under Quy tắc module; make part selection open that palette.

## Success criteria
Portable exact-expression/current-value tests, Ruby/RuboCop gate, Electron selection/layout/injection tests and native VBO verification of rear brace clearance and preserved source/engine behaviour pass.
