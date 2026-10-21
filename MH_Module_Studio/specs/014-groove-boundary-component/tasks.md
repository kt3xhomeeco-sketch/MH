# Tasks and verification

- [x] Reproduce accidental exterior pinning with readable_nested_dc.json.
- [x] Leave unoverridden ATT parts under formula control; retain own anchors.
- [x] Recognize original ATT overlapping pairs after groove zero without allowing
  new intersecting pairs or extending this permission to own formula overrides.
- [x] Build component parent and group children directly, with rollback.
- [x] Native VBO validation and safe repair of the reported generated module.
- [x] Scoped gate, documentation and runtime packaging.

Portable: 119 tests / 717 assertions pass, scoped RuboCop 34 files clean.
Coverage includes repeated groove cycles, subsequent edits, rejected oversized
grooves, source nonmutation, new collision rejection, manual fixed exterior
faces, own formula collision rejection and the bare ATT engine.

Native SU2025 PID31852 via VBO: outputs/native-boundary-014.json verifies component
parent/group leaves, groove 8→20→0→8→20→0 with 20mm board, other parameter edits,
oversized groove rejection followed by valid editing, shared copy independence,
injected verification failure rollback including definition count, small options
requests and cleanup without changing the user's existing object. Expected
rejection/injected errors were caught by QA, not unhandled failures.
outputs/native-undo-014.json verifies actual geometry/metadata Undo+Redo on an
isolated copy and removal of test objects/definitions, user geometry consistent.

Reported root452847 had saved sauranh0 but back-panel geometry matching sauranh20
(equal to dayvan20), with no active own overrides. Backed up its definition to
outputs/backup-reported-452847-014/module-before-repair.skp and root attributes,
transform and geometry to instance.json. One native transaction restored only
the back panel to the verified saved ATT state and converted the root to
component453534, retaining instance identity, placement, values and group leaves.
Values stay dayvan20/giang200/hauday10/luihau18/sauranh0. Further parameter preflight
passes; report outputs/repair-reported-014.json.

Runtime loaded through VBO. No UI sources changed; standalone window refreshed
for the converted selected instance. Package manifest remains 26 entries:
13 Ruby, 12 UI, README. Developer files excluded.
