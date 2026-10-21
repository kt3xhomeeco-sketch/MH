# Tasks: Unified module rules

## Foundation
- [x] T001 Amend constitution and feature pointer; prepare validated rule schema in rule_system.rb.
- [x] T002 Implement sparse plane solver in plane_solver.rb with conflict tests.
## US1 Ordinary cabinets
- [x] T003 Infer contact and thickness rules; test anchors, current envelope, noncontacts and unsafe plans.
## US2 ATT conversion
- [x] T004 Wrap existing ATT/sample engines, migrate projects and runtime dispatch; test formula priority and repeated edits.
## US3 In-view editing
- [x] T005 Implement floating expandable tree, ribbon, contextual rule editor and face picking in ui/.
- [x] T006 Add panel mutation actions and persistence; check UI interactions and cancel behaviour.
## Verification
- [x] T007 Update runtime manifests, run RuboCop/Ruby and Electron/pixel gates.
- [x] T008 Reload through VBO; validate native ordinary and ATT trials/source isolation; package and report actual limits.

## Validation evidence — 2026-10-14
- Spec-quality gate: requirements.md has 5 checked / 0 unchecked items; PASS.
- Constitution recheck: portable own schema, ATT-first provenance, current envelope and private copies preserved.
- Scoped RuboCop: 25 developer/runtime files, no offenses. Ruby: 90 runs, 503 assertions, zero failures/errors/skips.
- Electron: existing 68 UI checks; new ordinary/ATT tree/editor/direction/picking/layout/injection checks passed. WebGL + software depth checks passed across 14 camera cases, including hidden edges.
- Native VBO PID 8120: readable DC 5 inputs / 29 formulas, trial plus repeated update, source unchanged; ordinary 5-panel cabinet with 6 contacts, bottom 564→560→556 mm for thickness 18→20→22, envelope 600×500×850 mm. Reading both owned trials restores the same rules. Exact owned fixtures/copies/definitions cleaned and prior selection restored.
- Native UI: unified kind, tree inside viewport, five parameter controls, six cube faces, WebGL depth 24, GL error 0, ready.
- RBZ explicit manifest: 16 entries, archive integrity checked; no tooling/data dependencies shipped.
- Limit: native Undo behaviour is not established through VBO; no claim of a generic CAD sketch/solid/joint solver. Editable imported formula inputs remain supported; formula expressions are inspected, while face constraints are edited in the palette.
